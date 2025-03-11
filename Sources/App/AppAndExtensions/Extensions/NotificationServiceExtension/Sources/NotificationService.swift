/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

import UserNotifications
import OSLog
import CoreData
import ObvEngine
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
    private var notificationContent = NotificationContent()

    private static let coordinatorsQueue = OperationQueue.createSerialQueue(name: "UserNotificationsCoordinator queue", qualityOfService: .userInteractive)
    private static let queueForComposedOperations = {
        let queue = OperationQueue()
        queue.name = "UserNotificationsCoordinator queue for composed operations"
        queue.qualityOfService = .userInteractive
        return queue
    }()

    private var obvEngine: ObvEngine?
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NotificationService.self))
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: NotificationService.self))
    private static let runningLog = RunningLogError()
    private static let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)

    
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // For now, we simply discard the received encrypted payload and publish a minimal user notification.
        Self.logger.fault("The notification service serviceExtensionTimeWillExpire method was called: we discard the remote user notification.")
        contentHandler?(ObvUserNotificationContentCreator.createMinimalNotificationContent(badge: .unchanged).content)
    }

    
    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {

        self.contentHandler = contentHandler
        self.notificationContent = NotificationContent()
        
        Task {

            // Initialize the engine if required
            
            let engine = try self.obvEngine ?? initializeObvEngine()

            do {
                try await didReceive(request, engine: engine)
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
            
            let bestAttemptContent = await self.notificationContent.bestAttemptContent
            contentHandler(bestAttemptContent)
            
            self.obvEngine = nil
            Self.runningLog.removeAllEvents()

        }

    }
    
    
    private func didReceive(_ request: UNNotificationRequest, engine: ObvEngine) async throws {
                        
        // Initialize the CoreData Stack allowing to access the App database
        
        try ObvStack.initSharedInstance(transactionAuthor: ObvUICoreDataConstants.AppCategory.notificationExtension.transactionAuthor, runningLog: Self.runningLog, enableMigrations: false)
        
        // Initialize the CoreData Stack allowing to access the ObvUserNotificationsDataModel database
        
        try ObvUserNotificationsStack.initSharedInstance(transactionAuthor: ObvUICoreDataConstants.AppCategory.notificationExtension.transactionAuthor,
                                                         runningLog: Self.runningLog,
                                                         enableMigrations: false,
                                                         deleteStoreOnFailure: true)
        
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
            await self.notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
            throw ObvError.couldNotDecrypt
        }

        switch decryptedNotification {
        case .obvMessageOrObvOwnedMessage(let obvMessageOrObvOwnedMessage):
            try await didReceive(obvMessageOrObvOwnedMessage, requestIdentifier: request.identifier, engine: engine)
        case .protocolMessage(let obvProtocolMessage):
            try await didReceive(obvProtocolMessage, requestIdentifier: request.identifier)
        }
        
        
        
    }
    
    
    private func didReceive(_ obvProtocolMessage: ObvProtocolMessage, requestIdentifier: String) async throws {

        // Determine the kind of notification to show

        var notificationToShow = try await ObvUserNotificationContentCreator.determineNotificationToShow(obvProtocolMessage: obvProtocolMessage, obvStackShared: ObvStack.shared)
        
        let newBadgeValue = await Self.currentNumberOfPendingAndDeliveredUserNotifications() + 1
        notificationToShow = notificationToShow.withUpdatedBadgeCount(newBadgeValue)

        // Construct the actual notification depending on the kind of notification to show

        await self.notificationContent.setBestAttemptContentFromObvProtocolMessage(to: notificationToShow)

    }
    
    
    private func didReceive(_ obvMessageOrObvOwnedMessage: ObvMessageOrObvOwnedMessage, requestIdentifier: String, engine: ObvEngine) async throws {
        
        switch obvMessageOrObvOwnedMessage {
            
        case .obvMessage(let obvMessage):
            
            // Determine the kind of notification to show

            var notificationToShow = try await ObvUserNotificationContentCreator.determineNotificationToShow(obvMessage: obvMessage, obvStackShared: ObvStack.shared)

            // Construct the actual notification depending on the kind of notification to show
            
            switch notificationToShow {

            case .silent, .minimal, .silentWithUpdatedBadgeCount:

                break

            case .addReceivedMessage(content: _, messageAppIdentifier: let messageAppIdentifier, userNotificationCategory: let userNotificationCategory, contactDeviceUIDs: let contactDeviceUIDs):

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
                    await self.notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
                    return
                }
                
                switch result {
                case .existed:
                    Self.logger.info("We don't schedule any user notification as one already exists for this ObvMessage")
                    await self.notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
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
                                                                         contactDeviceUIDs: contactDeviceUIDs,
                                                                         attachmentNumber: nil)
                        try await engine.postReturnReceiptWithElements(returnReceiptToSend: returnReceiptToSend)
                    }
                } catch {
                    Self.logger.fault("The Return Receipt could not be posted")
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
                    await self.notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
                    return
                }
                
                switch result {
                case .existed:
                    Self.logger.info("We don't schedule any user notification as one already exists for this ObvMessage")
                    await self.notificationContent.setBestAttemptContentFromObvMessage(to: .silent)
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
                
                await self.notificationContent.setBestAttemptContentFromObvMessage(to: notificationToShow)

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
                
                await self.notificationContent.setBestAttemptContentFromObvMessage(to: notificationToShow)

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
                
            }
            
            // If we reach this point, we can use the notificationToShow to update the best attempt

            await self.notificationContent.setBestAttemptContentFromObvMessage(to: notificationToShow)

        case .obvOwnedMessage(let obvOwnedMessage):
            
            // By default, we consider that an ObvOwnedMessage should never show any user notification
            
            await self.notificationContent.setBestAttemptContentFromObvOwnedMessage(to: .silent)
            
            // Determine the kind of notification to show

            var notificationToShow = try await ObvUserNotificationContentCreator.determineNotificationToShow(obvOwnedMessage: obvOwnedMessage, obvStackShared: ObvStack.shared)

            // Construct the actual notification depending on the kind of notification to show
            
            switch notificationToShow {
                
            case .silent, .silentWithUpdatedBadgeCount:
                
                await self.notificationContent.setBestAttemptContentFromObvOwnedMessage(to: notificationToShow)

            case .removePreviousNotificationsBasedOnObvDiscussionIdentifier(content: _, obvDiscussionIdentifier: let discussionIdentifier, lastReadMessageServerTimestamp: let lastReadMessageServerTimestamp):
                
                let requestIdentifiers = try await getRequestIdentifiersOfShownUserNotifications(
                    discussionIdentifier: discussionIdentifier,
                    lastReadMessageServerTimestamp: lastReadMessageServerTimestamp)
                
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
                
                let newBadgeValue = await Self.currentNumberOfPendingAndDeliveredUserNotifications()
                                
                notificationToShow = notificationToShow.withUpdatedBadgeCount(newBadgeValue)
                
                await self.notificationContent.setBestAttemptContentFromObvOwnedMessage(to: notificationToShow)

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
                
                await self.notificationContent.setBestAttemptContentFromObvOwnedMessage(to: notificationToShow)

                for requestIdentifier in requestIdentifiers {
                    let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await Self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                }

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
    
    
    private func initializeObvEngine() throws -> ObvEngine {
        let mainEngineContainer = ObvUICoreDataConstants.ContainerURL.mainEngineContainer.url
        ObvEngine.mainContainerURL = mainEngineContainer
        let obvEngine = try ObvEngine.startLimitedToDecrypting(
            sharedContainerIdentifier: ObvAppCoreConstants.appGroupIdentifier,
            logPrefix: "DecryptingLimitedEngine",
            remoteNotificationByteIdentifierForServer: ObvAppCoreConstants.remoteNotificationByteIdentifierForServer,
            appType: .notificationExtension,
            runningLog: Self.runningLog)
        return obvEngine
    }
    
    
    /// When receiving an `ObvOwnedMessage` with a "discussion read" payload, we want to remove all notifications for messages within that discussion, with a server timestamp earlier or equal to the date until when the messages
    /// were read on another owned device. This method allows to fetch the request identifiers of the user notifications to remove.
    private func getRequestIdentifiersOfShownUserNotifications(discussionIdentifier: ObvDiscussionIdentifier, lastReadMessageServerTimestamp: Date?) async throws -> [String] {

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
    private func getRequestIdentifiersOfShownUserNotifications(messageAppIdentifiers: [ObvMessageAppIdentifier]) async throws -> [String] {
        
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


// MARK: - NotificationContent

fileprivate actor NotificationContent {
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
    
    func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) -> CompositionOfOneContextualOperation<T> {
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvUserNotificationsStack.shared, queueForComposedOperations: Self.queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

}
