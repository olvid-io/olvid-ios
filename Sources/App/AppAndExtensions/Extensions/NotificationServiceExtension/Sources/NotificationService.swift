/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

@preconcurrency import UserNotifications
import OSLog
import CoreData
@preconcurrency import ObvEngine
import ObvTypes
import ObvAppTypes
import ObvCrypto
import ObvUICoreData
import ObvSettings
import OlvidUtils
import ObvAppCoreConstants
import ObvUserNotificationsDatabase
import ObvUserNotificationsCreator



final class NotificationService: UNNotificationServiceExtension {
    

    private var contentHandler: ((UNNotificationContent) -> Void)?

    private static let coordinatorsQueue = OperationQueue.createSerialQueue(name: "UserNotificationsCoordinator queue", qualityOfService: .userInteractive)
    private static let queueForComposedOperations = {
        let queue = OperationQueue()
        queue.name = "UserNotificationsCoordinator queue for composed operations"
        queue.qualityOfService = .userInteractive
        return queue
    }()

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NotificationService.self))
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NotificationService.self))
    private static let runningLog = RunningLogError()

    
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // For now, we simply discard the received encrypted payload and publish a minimal user notification.
        ObvDisplayableLogs.shared.log("[NotificationService] serviceExtensionTimeWillExpire")
        Self.logger.fault("The notification service serviceExtensionTimeWillExpire method was called: we discard the remote user notification.")
        contentHandler?(ObvUserNotificationContentCreator.createMinimalNotificationContent(badge: .unchanged).content)
    }

    
    /// The task started here must not use `self`: the system may hand this process several notifications at once, and their tasks run
    /// concurrently. What a request needs of its own is created inside its task, and what the process shares is started by ``TheEngineAndTheStacksOfThisProcess``.
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping @Sendable (UNNotificationContent) -> Void) {

        ObvDisplayableLogs.shared.setContainerURLForDisplayableLogs(to: ObvUICoreDataConstants.ContainerURL.forDisplayableLogs.url)
        ObvDisplayableLogs.shared.doEnableRunningLogs(ObvMessengerSettings.Advanced.enableRunningLogs)
        ObvDisplayableLogs.shared.log("[NotificationService] didReceive request")

        self.contentHandler = contentHandler

        Task {

            // Start the engine, unless another notification already did

            let engine: ObvEngine
            do {
                engine = try await TheEngineAndTheStacksOfThisProcess.shared.engine()
            } catch {
                Self.logger.fault("Could not initialize the engine, so the remote user notification cannot be processed. The content handler is not called, exactly as it was not before.")
                return
            }

            let notificationContent = NotificationContent()

            do {
                try await Self.didReceive(request, engine: engine, notificationContent: notificationContent)
            } catch {
                if let obvError = error as? ObvError {
                    switch obvError {
                    case .couldNotDecrypt:
                        Self.logger.error("Could not decrypt the remote user notification. This happens if the app was faster to download and decrypt the message, in which case the decryption key was deleted. The app should soon post a user notification.")
                    default:
                        Self.logger.fault("Could not fully process the remote user notification: \(error.localizedDescription)")
                        assertionFailure()
                    }
                } else {
                    Self.logger.fault("Could not fully process the remote user notification: \(error.localizedDescription)")
                    assertionFailure()
                }
            }
            
            contentHandler(ObvUserNotificationContentCreator.ensuringPrivacy(of: notificationContent.bestAttemptContent))

            Self.runningLog.removeAllEvents()

        }

    }
    
    
    private static func didReceive(_ request: UNNotificationRequest, engine: ObvEngine, notificationContent: NotificationContent) async throws {

        // Initialize the Core Data stacks of the App database and of the ObvUserNotificationsDataModel database, unless another notification already did

        try await TheEngineAndTheStacksOfThisProcess.shared.initializeTheStacks()

        // Parse the information of the received notification
        
        guard let encryptedRemoteUserNotification = ObvEncryptedRemoteUserNotification(content: request.content) else {
            throw ObvError.couldNotParseEncryptedPushNotification
        }

        // Decrypt the remote user notification payload.
        // This can fail, e.g., if the associated message was already received and decrypted by the app as, in that case, the decryption key was deleted from database.
        
        let decryptedNotification: ObvDecryptedNotification
        do {
            decryptedNotification = try await engine.decrypt(encryptedPushNotification: encryptedRemoteUserNotification)
        } catch {
            Self.logger.error("Failed to decrypt encrypted remote user notification: \(error.localizedDescription).")
            notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
            throw ObvError.couldNotDecrypt
        }

        switch decryptedNotification {
        case .obvMessageOrObvOwnedMessage(let obvMessageOrObvOwnedMessage):
            try await didReceive(obvMessageOrObvOwnedMessage, requestIdentifier: request.identifier, engine: engine, notificationContent: notificationContent)
        case .protocolMessage(let obvProtocolMessage):
            try await didReceive(obvProtocolMessage, requestIdentifier: request.identifier, notificationContent: notificationContent)
        }
        
        
        
    }
    
    
    private static func didReceive(_ obvProtocolMessage: ObvProtocolMessage, requestIdentifier: String, notificationContent: NotificationContent) async throws {

        // Determine the kind of notification to show

        var notificationToShow = try await ObvUserNotificationContentCreator.determineNotificationToShow(obvProtocolMessage: obvProtocolMessage, obvStackShared: ObvStack.shared)
        
        let newBadgeValue = await Self.currentNumberOfPendingAndDeliveredUserNotifications() + 1
        notificationToShow = notificationToShow.withUpdatedBadgeCount(newBadgeValue)

        // Construct the actual notification depending on the kind of notification to show

        notificationContent.setBestAttemptContentFromObvProtocolMessage(to: notificationToShow)

    }
    
    
    private static func didReceive(_ obvMessageOrObvOwnedMessage: ObvMessageOrObvOwnedMessage, requestIdentifier: String, engine: ObvEngine, notificationContent: NotificationContent) async throws {
        
        switch obvMessageOrObvOwnedMessage {
            
        case .obvMessage(let obvMessage):
            
            // Determine the kind of notification to show

            var notificationToShow = try await ObvUserNotificationContentCreator.determineNotificationToShow(obvMessage: obvMessage, receivedMessageSave: .notYetSaved, obvStackShared: ObvStack.shared)

            // Construct the actual notification depending on the kind of notification to show
            
            switch notificationToShow {

            case .silent, .minimal, .silentWithUpdatedBadgeCount:

                break

            case .addReceivedMessage(content: _, messageAppIdentifier: let messageAppIdentifier, userNotificationCategory: let userNotificationCategory):

                // Make sure we are in charge of posting the notification by trying to create a PersistedUserNotification
                
                let op1 = CreatePersistedUserNotificationForReceivedMessageOperation(
                    requestIdentifier: requestIdentifier,
                    obvMessage: obvMessage,
                    receivedMessageAppIdentifier: messageAppIdentifier,
                    userNotificationCategory: userNotificationCategory,
                    creator: .notificationExtension)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                
                guard let result = op1.result else {
                    Self.logger.error("Could not create PersistedUserNotification. We don't schedule any user notification.")
                    notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
                    return
                }
                
                switch result {
                case .existed:
                    Self.logger.info("We don't schedule any user notification as one already exists for this ObvMessage")
                    notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
                    return
                case .created:
                    Self.logger.info("We just persisted the ObvMessage in the user notification DB, we will schedule a local user notification.")
                }

                // Since we persisted the decrypted notification content, we can send a return receipt if there is one to send (for now, only for messages, not for reactions)
                
                do {
                    if let returnReceipt = try PersistedItemJSON.jsonDecode(obvMessage.messagePayload).returnReceipt {
                        let returnReceiptToSend = ObvReturnReceiptToSend(elements: returnReceipt.elements,
                                                                         status: .delivered,
                                                                         contactIdentifier: obvMessage.fromContactIdentity,
                                                                         attachmentNumber: nil)
                        // Waited for: this extension is about to finish and only the app sweeps that store, so
                        // otherwise the receipt would sit there until the next foreground and the sender would stop
                        // seeing a prompt delivery tick for exactly the messages that arrive by push. If this
                        // extension is killed while waiting, the row is already there and the app's next sweep sends it.
                        await engine.postReturnReceiptsWithElements(returnReceiptsToSend: [returnReceiptToSend], waitUntilSent: true)
                    }
                } catch {
                    Self.logger.fault("The payload of a message could not be decoded, so it has no return receipt to post")
                    // Continue anyway
                }
                
                // The current badge value of the notification to show is probably incorrect as it was computed on the basis of the messages currently persisted
                // in the app database. This database might not be aware of the latest messages we received: it only knows about the messages received during
                // the last time time it was up and running. For this reason, we update the badge value on the basis of the current shown user notifications,
                // including the notification that we are about to schedule.

                let newBadgeValue = await Self.currentNumberOfPendingAndDeliveredUserNotifications() + 1

                notificationToShow = notificationToShow.withUpdatedBadgeCount(newBadgeValue)
                
            case .addReactionOnSentMessage(content: _, sentMessageReactedTo: let sentMessageReactedTo, reactor: let reactor, userNotificationCategory: let userNotificationCategory):
                
                let existingNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
                    .filter({ $0.request.content.reactor == reactor })
                    .filter({ $0.request.content.sentMessageReactedTo == sentMessageReactedTo })
                
                // We first remove any earlier reaction notification on the same message from the same creator
                
                let identifiersOfRequestsToRemove = existingNotifications
                    .filter({
                        guard let previousTimestamp = $0.request.content.uploadTimestampFromServer else { assertionFailure(); return false }
                        return previousTimestamp < obvMessage.messageUploadTimestampFromServer
                    })
                    .map({ $0.request.identifier })
                
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersOfRequestsToRemove)
                
                for identifier in identifiersOfRequestsToRemove {
                    let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: identifier, newStatus: .removed)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                }
                
                // We make sure there isn't a shown notification that is more recent than the one we received.
                // If it's the case, we don't go any further
                
                let noRecentExists = existingNotifications
                    .filter({
                        guard let previousTimestamp = $0.request.content.uploadTimestampFromServer else { assertionFailure(); return false }
                        return previousTimestamp >= obvMessage.messageUploadTimestampFromServer
                    })
                    .isEmpty

                guard noRecentExists else {
                    notificationToShow = .silent
                    return
                }

                // Make sure we are in charge of posting the notification by trying to create a PersistedUserNotification
                
                let op1 = CreatePersistedUserNotificationForReceivedReactionOperation(
                    requestIdentifier: requestIdentifier,
                    obvMessage: obvMessage,
                    sentMessageReactedTo: sentMessageReactedTo,
                    reactor: reactor,
                    userNotificationCategory: userNotificationCategory,
                    creator: .notificationExtension)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                
                guard let result = op1.result else {
                    Self.logger.error("Could not create PersistedUserNotification. We don't schedule any user notification.")
                    notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
                    return
                }
                
                switch result {
                case .existed:
                    Self.logger.info("We don't schedule any user notification as one already exists for this ObvMessage")
                    notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
                    return
                case .created:
                    Self.logger.info("We just persisted the ObvMessage in the user notification DB, we will schedule a local user notification.")
                }
                
            case .addPollVoteOnSentMessage(content: _, sentMessageVotedTo: let sentMessageVotedTo, reactor: let reactor, userNotificationCategory: let userNotificationCategory):
                
                let existingNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
                    .filter({ $0.request.content.reactor == reactor })
                    .filter({ $0.request.content.sentMessageReactedTo == sentMessageVotedTo })
                
                // We first remove any earlier reaction notification on the same message from the same creator
                
                let identifiersOfRequestsToRemove = existingNotifications
                    .filter({
                        guard let previousTimestamp = $0.request.content.uploadTimestampFromServer else { assertionFailure(); return false }
                        return previousTimestamp < obvMessage.messageUploadTimestampFromServer
                    })
                    .map({ $0.request.identifier })
                
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersOfRequestsToRemove)
                
                for identifier in identifiersOfRequestsToRemove {
                    let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: identifier, newStatus: .removed)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                }
                
                // We make sure there isn't a shown notification that is more recent than the one we received.
                // If it's the case, we don't go any further
                
                let noRecentExists = existingNotifications
                    .filter({
                        guard let previousTimestamp = $0.request.content.uploadTimestampFromServer else { assertionFailure(); return false }
                        return previousTimestamp >= obvMessage.messageUploadTimestampFromServer
                    })
                    .isEmpty

                guard noRecentExists else {
                    notificationToShow = .silent
                    return
                }

                // Make sure we are in charge of posting the notification by trying to create a PersistedUserNotification
                
                let op1 = CreatePersistedUserNotificationForReceivedPollVoteOperation(
                    requestIdentifier: requestIdentifier,
                    obvMessage: obvMessage,
                    sentMessageVotedTo: sentMessageVotedTo,
                    reactor: reactor,
                    userNotificationCategory: userNotificationCategory,
                    creator: .notificationExtension)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                
                guard let result = op1.result else {
                    Self.logger.error("Could not create PersistedUserNotification. We don't schedule any user notification.")
                    notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
                    return
                }
                
                switch result {
                case .existed:
                    Self.logger.info("We don't schedule any user notification as one already exists for this ObvMessage")
                    notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
                    return
                case .created:
                    Self.logger.info("We just persisted the ObvMessage in the user notification DB, we will schedule a local user notification.")
                }
                
            case .removeReceivedMessages(content: _, messageAppIdentifiers: let messageAppIdentifiers):
                
                let requestIdentifiers = try await getRequestIdentifiersOfShownUserNotifications(messageAppIdentifiers: messageAppIdentifiers)
                
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
                
                let newBadgeValue = await Self.currentNumberOfPendingAndDeliveredUserNotifications()
                                
                notificationToShow = notificationToShow.withUpdatedBadgeCount(newBadgeValue)
                
                notificationContent.setBestAttemptContentFromObvMessage(to: notificationToShow)

                for requestIdentifier in requestIdentifiers {
                    let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                }
                
            case .removePreviousNotificationsBasedOnObvDiscussionIdentifier(content: _, obvDiscussionIdentifier: let discussionIdentifier):
                
                let requestIdentifiers = try await getRequestIdentifiersOfShownUserNotifications(
                    discussionIdentifier: discussionIdentifier,
                    lastReadMessageServerTimestamp: nil)
                
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
                
                let newBadgeValue = await Self.currentNumberOfPendingAndDeliveredUserNotifications()
                                
                notificationToShow = notificationToShow.withUpdatedBadgeCount(newBadgeValue)
                
                notificationContent.setBestAttemptContentFromObvMessage(to: notificationToShow)

                for requestIdentifier in requestIdentifiers {
                    let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                }
                
            case .updateReceivedMessage(content: _, messageAppIdentifier: let messageAppIdentifier):
                
                let op1 = MarkReceivedMessageNotificationAsUpdatedOperation(
                    messageAppIdentifier: messageAppIdentifier,
                    dateOfUpdate: obvMessage.messageUploadTimestampFromServer,
                    newRequestIdentifier: requestIdentifier,
                    obvMessageUpdate: obvMessage)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                
                guard let previousRequestIdentifier = op1.previousRequestIdentifier, composedOp.isFinished, !composedOp.isCancelled else {
                    Self.logger.info("We don't update the user notification for the received message that was edited")
                    return
                }
                
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [previousRequestIdentifier])
                
            case .removeReactionOnSentMessage(content: _, sentMessageReactedTo: let sentMessageReactedTo, reactor: let reactor):
                
                let existingNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
                    .filter({ $0.request.content.reactor == reactor })
                    .filter({ $0.request.content.sentMessageReactedTo == sentMessageReactedTo })
                
                // We first remove any earlier reaction notification on the same message from the same creator
                
                let identifiersOfRequestsToRemove = existingNotifications
                    .filter({
                        guard let previousTimestamp = $0.request.content.uploadTimestampFromServer else { assertionFailure(); return false }
                        return previousTimestamp < obvMessage.messageUploadTimestampFromServer
                    })
                    .map({ $0.request.identifier })
                
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersOfRequestsToRemove)
                
                for identifier in identifiersOfRequestsToRemove {
                    let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: identifier, newStatus: .removed)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                }
                
            case .removePollVoteOnSentMessage(content: _, sentMessageVotedTo: let sentMessageVotedTo, reactor: let reactor):
                
                let existingNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
                    .filter({ $0.request.content.reactor == reactor })
                    .filter({ $0.request.content.sentMessageReactedTo == sentMessageVotedTo })
                
                // We first remove any earlier reaction notification on the same message from the same creator
                
                let identifiersOfRequestsToRemove = existingNotifications
                    .filter({
                        guard let previousTimestamp = $0.request.content.uploadTimestampFromServer else { assertionFailure(); return false }
                        return previousTimestamp < obvMessage.messageUploadTimestampFromServer
                    })
                    .map({ $0.request.identifier })
                
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersOfRequestsToRemove)
                
                for identifier in identifiersOfRequestsToRemove {
                    let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: identifier, newStatus: .removed)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                }
                
            }
            
            // If we reach this point, we can use the notificationToShow to update the best attempt

            notificationContent.setBestAttemptContentFromObvMessage(to: notificationToShow)

        case .obvOwnedMessage(let obvOwnedMessage):
            
            // By default, we consider that an ObvOwnedMessage should never show any user notification
            
            notificationContent.setBestAttemptContentFromObvOwnedMessage(to: .silent)
            
            // Determine the kind of notification to show

            var notificationToShow = try await ObvUserNotificationContentCreator.determineNotificationToShow(obvOwnedMessage: obvOwnedMessage, obvStackShared: ObvStack.shared)

            // Construct the actual notification depending on the kind of notification to show
            
            switch notificationToShow {
                
            case .silent, .silentWithUpdatedBadgeCount:
                
                notificationContent.setBestAttemptContentFromObvOwnedMessage(to: notificationToShow)

            case .removePreviousNotificationsBasedOnObvDiscussionIdentifier(content: _, obvDiscussionIdentifier: let discussionIdentifier, lastReadMessageServerTimestamp: let lastReadMessageServerTimestamp):
                
                let requestIdentifiers = try await getRequestIdentifiersOfShownUserNotifications(
                    discussionIdentifier: discussionIdentifier,
                    lastReadMessageServerTimestamp: lastReadMessageServerTimestamp)
                
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
                
                let newBadgeValue = await Self.currentNumberOfPendingAndDeliveredUserNotifications()
                                
                notificationToShow = notificationToShow.withUpdatedBadgeCount(newBadgeValue)
                
                notificationContent.setBestAttemptContentFromObvOwnedMessage(to: notificationToShow)

                for requestIdentifier in requestIdentifiers {
                    let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                }
                
            case .removePreviousNotificationsBasedOnObvMessageAppIdentifiers(content: _, messageAppIdentifiers: let messageAppIdentifiers):
                
                let requestIdentifiers = try await getRequestIdentifiersOfShownUserNotifications(messageAppIdentifiers: messageAppIdentifiers)
                
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
                
                let newBadgeValue = await Self.currentNumberOfPendingAndDeliveredUserNotifications()
                                
                notificationToShow = notificationToShow.withUpdatedBadgeCount(newBadgeValue)
                
                notificationContent.setBestAttemptContentFromObvOwnedMessage(to: notificationToShow)

                for requestIdentifier in requestIdentifiers {
                    let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                }
                
            case .historyTransferRequestFromAnotherOwnedDevice(content: _):
                
                let newBadgeValue = await Self.currentNumberOfPendingAndDeliveredUserNotifications()
                                
                notificationToShow = notificationToShow.withUpdatedBadgeCount(newBadgeValue+1)

                notificationContent.setBestAttemptContentFromObvOwnedMessage(to: notificationToShow)

            }
            
        }
        
        
    }
    
    
    // MARK: - Errors
    
    enum ObvError: Error {
        case couldNotParseEncryptedPushNotification
        case couldNotFindContact
        case unexpectedItemType
        case couldNotFindOwnedIdentity
        case couldNotFindGroupV2Discussion
        case couldNotDecrypt
    }
    
    
    // MARK: - Helper methods
    
    
    private static func currentNumberOfPendingAndDeliveredUserNotifications() async -> Int {
        Self.logger.info("☝️ Will compute current number of pending and delivered user notifications")
        let countDelivered = await UNUserNotificationCenter.current().deliveredNotifications()
            .filter { $0.request.content.messageAppIdentifier != nil || $0.request.content.obvProtocolMessage != nil } // Restrict to notifications about received messages
            .count
        Self.logger.info("☝️ Count delivered is \(countDelivered)")
        let countPending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.content.messageAppIdentifier != nil || $0.content.obvProtocolMessage != nil } // Restrict to notifications about received messages
            .count
        Self.logger.info("☝️ Count delivered is \(countPending)")
        Self.logger.info("☝️ Did compute current number of pending and delivered user notifications: \(countPending + countDelivered)")
        return countPending + countDelivered
    }
    
    
    /// When receiving an `ObvOwnedMessage` with a "discussion read" payload, we want to remove all notifications for messages within that discussion, with a server timestamp earlier or equal to the date until when the messages
    /// were read on another owned device. This method allows to fetch the request identifiers of the user notifications to remove.
    private static func getRequestIdentifiersOfShownUserNotifications(discussionIdentifier: ObvDiscussionIdentifier, lastReadMessageServerTimestamp: Date?) async throws -> [String] {

        let op1 = GetRequestIdentifiersOfShownUserNotificationsOperation(.discussionAndLastReadMessageServerTimestamp(
            discussionIdentifier: discussionIdentifier,
            lastReadMessageServerTimestamp: lastReadMessageServerTimestamp))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
        
        if let reasonForCancel = op1.reasonForCancel {
            switch reasonForCancel {
            case .coreDataError(error: let error):
                throw error
            }
        } else {
            return op1.requestIdentifiers
        }
        
    }
    
    
    /// When receiving an `ObvOwnedMessage` with a "delete message" or discussion payload, we want to remove all notifications for deleted messages within that discussion. This method allows to fetch the request identifiers of the user notifications to remove.
    private static func getRequestIdentifiersOfShownUserNotifications(messageAppIdentifiers: [ObvMessageAppIdentifier]) async throws -> [String] {
        
        let op1 = GetRequestIdentifiersOfShownUserNotificationsOperation(.messageIdentifiers(messageAppIdentifiers: messageAppIdentifiers))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
        
        if let reasonForCancel = op1.reasonForCancel {
            switch reasonForCancel {
            case .coreDataError(error: let error):
                throw error
            }
        } else {
            return op1.requestIdentifiers
        }

    }

}


// MARK: - The engine and the Core Data stacks of this process

extension NotificationService {

    /// Starts the engine, and initializes the Core Data stacks, once for the whole process however many notifications ask at the same time.
    ///
    /// Neither may run twice at once: starting the engine writes statics of the engine, and each stack checks for an existing instance
    /// before making one. A start that fails is forgotten, so that the next notification tries again.
    fileprivate actor TheEngineAndTheStacksOfThisProcess {

        static let shared = TheEngineAndTheStacksOfThisProcess()

        private var startOfTheEngine: Task<ObvEngine, Error>?

        func engine() async throws -> ObvEngine {
            if let startOfTheEngine {
                return try await startOfTheEngine.value
            } else {
                let startOfTheEngine = Task {
                    try await ObvEngine.startLimitedToDecrypting(
                        sharedContainerIdentifier: ObvAppCoreConstants.appGroupIdentifier,
                        mainContainerURL: ObvUICoreDataConstants.ContainerURL.mainEngineContainer.url,
                        logPrefix: "DecryptingLimitedEngine",
                        remoteNotificationByteIdentifierForServer: ObvAppCoreConstants.remoteNotificationByteIdentifierForServer,
                        appType: .notificationExtension,
                        runningLog: NotificationService.runningLog)
                }
                self.startOfTheEngine = startOfTheEngine
                do {
                    return try await startOfTheEngine.value
                } catch {
                    self.startOfTheEngine = nil
                    throw error
                }
            }
        }

        func initializeTheStacks() throws {
            try ObvStack.initSharedInstance(
                transactionAuthor: ObvUICoreDataConstants.AppCategory.notificationExtension.transactionAuthor,
                runningLog: NotificationService.runningLog,
                enableMigrations: false
            )
            try ObvUserNotificationsStack.initSharedInstance(
                transactionAuthor: ObvUICoreDataConstants.AppCategory.notificationExtension.transactionAuthor,
                runningLog: NotificationService.runningLog,
                enableMigrations: false,
                deleteStoreOnFailure: true
            )
        }

    }

}


// MARK: - NotificationContent

/// Owned by the task of a single request, which is why it needs no isolation of its own.
fileprivate final class NotificationContent {
    private(set) var bestAttemptContent: UNNotificationContent = ObvUserNotificationContentCreator.createMinimalNotificationContent(badge: .unchanged).content
    func setBestAttemptContentFromObvMessage(to newContent: ObvUserNotificationContentTypeForObvMessage) {
        self.bestAttemptContent = newContent.content
    }
    func setBestAttemptContentFromObvOwnedMessage(to newContent: ObvUserNotificationContentTypeForObvOwnedMessage) {
        self.bestAttemptContent = newContent.content
    }
    func setBestAttemptContentFromObvProtocolMessage(to newContent: ObvUserNotificationContentTypeForObvProtocolMessage) {
        self.bestAttemptContent = newContent.content
    }
}


// MARK: - ObvEncryptedRemoteUserNotification extension


fileprivate extension ObvEncryptedRemoteUserNotification {
    
    init?(content: UNNotificationContent) {
        
        let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "ObvEncryptedPushNotification")

        let wrappedKeyString = content.userInfo["encryptedHeader"] as? String ?? content.title
        let encryptedContentString = content.userInfo["encryptedMessage"] as? String ?? content.body
        
        guard let wrappedKey = Data(base64Encoded: wrappedKeyString) else {
            os_log("Could not decode de base64encoded wrapped key string found in the encrypted header of the user info", log: log, type: .error)
            return nil
        }
        
        guard let encryptedContent = Data(base64Encoded: encryptedContentString) else {
            os_log("Could not decode de base64encoded encrypted content found in the encrypted message field of the user info", log: log, type: .error)
            return nil
        }
        
        guard let maskingUID = content.userInfo["maskinguid"] as? String else {
            os_log("Could not find the masking uid (as a String) in the user info dictionary", log: log, type: .error)
            return nil
        }
        
        guard let messageUploadTimestampFromServerAsDouble = content.userInfo["timestamp"] as? Double else {
            os_log("Could not find the message upload timestamp from server (as a Double) in the user info dictionary", log: log, type: .error)
            return nil
        }

        guard let messageIdFromServer = content.userInfo["messageuid"] as? String else {
            os_log("Could not find the messageId from server (as a String) in the user info dictionary", log: log, type: .error)
            return nil
        }

        var encryptedExtendedContent: Data?
        if let encryptedExtendedContentString = content.userInfo["extendedContent"] as? String {
            encryptedExtendedContent = Data(base64Encoded: encryptedExtendedContentString)
        }

        let messageUploadTimestampFromServer = Date(timeIntervalSince1970: messageUploadTimestampFromServerAsDouble / 1000.0)

        self.init(messageIdFromServer: messageIdFromServer,
                  wrappedKey: wrappedKey,
                  encryptedContent: encryptedContent,
                  encryptedExtendedContent: encryptedExtendedContent,
                  maskingUID: maskingUID,
                  messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                  localDownloadTimestamp: Date())
        
    }
    
}


// MARK: - Creating compositions of contextual operations

extension NotificationService {
    
    static func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) -> CompositionOfOneContextualOperation<T> {
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvUserNotificationsStack.shared, queueForComposedOperations: Self.queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

}
