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

import Foundation
import Combine
import OSLog
import ObvEngine
import ObvAppCoreConstants
import ObvTypes
import ObvAppTypes
import ObvUserNotificationsCreator
import ObvUserNotificationsDatabase
import ObvUserNotificationsTypes
import OlvidUtils
import ObvUICoreData
import ObvUICoreDataStructs
import ObvCrypto
import ObvCommunicationInteractor


/// This coordinator schedules local user notifications, and remove both local and remote user notifications from the notification center as needed.
/// Additionally, it acts as a ``UNUserNotificationCenterDelegate``, making it responsible for handling user interactions with user notifications and
/// determining whether to display specific notifications when the app is running in the foreground.
final class UserNotificationsCoordinator: NSObject {

    static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: UserNotificationsCoordinator.self))
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: UserNotificationsCoordinator.self))

    private let notificationsCoordinatorQueue = OperationQueue.createSerialQueue(name: "UserNotificationsCoordinator queue", qualityOfService: .userInteractive)
    private let queueForComposedOperations = {
        let queue = OperationQueue()
        queue.name = "UserNotificationsCoordinator queue for composed operations"
        queue.qualityOfService = .userInteractive
        return queue
    }()

    private var observationTokens = [NSObjectProtocol]()
    private var cancellables = Set<AnyCancellable>()

    private var obvEngine: ObvEngine?
    
    var coordinator: CoordinatorOfObvMessagesReceivedFromUserNotificationExtension?
    
    override init() {
        super.init()
        registerAsUNUserNotificationCenterDelegate()
        listenToNotifications()
        continuouslyRemoveUserNotificationsOfReactionOnEnteringDiscussion()
        Task {
            await PersistedMessageReceived.addPersistedMessageReceivedObserver(self)
            await PersistedMessage.addObserver(self)
            await PersistedInvitation.addPersistedInvitationObserver(self)
            await PersistedDiscussion.addObserver(self)
            await PersistedObvOwnedIdentity.addObserver(self)
            await PersistedCallLogItem.addObserver(self)
        }
    }
    
    
    func setObvEngine(to obvEngine: ObvEngine) {
        assert(self.obvEngine == nil)
        self.obvEngine = obvEngine
    }
    
    
    /// Register as the UNUserNotificationCenter's delegate
    /// This must be set before the app finished launching.
    /// See https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate
    private func registerAsUNUserNotificationCenterDelegate() {

        let notificationCenter = UNUserNotificationCenter.current()
        notificationCenter.delegate = self
        
        // Register the custom actions/categories

        ObvUserNotificationCategoryIdentifier.setAllNotificationCategories(on: notificationCenter)

    }
    
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        if forTheFirstTime {
            await deleteOrphanedPersistedObvMessage()
            await persistExistingObvMessagesWithUserNotifications()
            removeStaticNotifications()
            await removeOldNotificationsThatAreNoLongerShown()
        }
    }
    
    private struct StaticRequestIdentifier {
        static let postUserNotificationAsAnotherCallParticipantStartedCamera = "StaticRequestIdentifier.postUserNotificationAsAnotherCallParticipantStartedCamera"
        static var all: [String] {
            [
                Self.postUserNotificationAsAnotherCallParticipantStartedCamera,
            ]
        }
    }
    
    
    private func removeStaticNotifications() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: StaticRequestIdentifier.all)
    }
    
}


// MARK: - Bootstrap

extension UserNotificationsCoordinator {
    
    /// During bootstrap, we remove old `PersistedUserNotification` if they are no longer shown in the notification center.
    private func removeOldNotificationsThatAreNoLongerShown() async {
        
        let requestIdentifiersOfDeliveredNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
            .map({ $0.request.identifier })
        
        let op1 = DeleteOldPersistedUserNotificationThatAreNoLongerShownOperation(requestIdentifiersOfDeliveredNotifications: Set(requestIdentifiersOfDeliveredNotifications))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp)
        assert(composedOp.isFinished && !composedOp.isCancelled)

    }
    
    private func deleteOrphanedPersistedObvMessage() async {
        let op1 = DeleteOrphanedPersistedObvMessageOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp)
        assert(composedOp.isFinished && !composedOp.isCancelled)
    }
    
    
    private func persistExistingObvMessagesWithUserNotifications() async {
        
        guard let coordinator else {
            Self.logger.fault("Could not persist ObvMessages stored in user notifications as the coordinator is nil")
            assertionFailure()
            return
        }
        
        let op1 = GetAllObvMessagesFromPersistedUserNotificationsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            return
        }
        
        let requestIdentifiersAndObvMessages = op1.requestIdentifiersAndObvMessages
        
        for (requestIdentifier, obvMessage, obvMessageUpdate) in requestIdentifiersAndObvMessages {
            
            let result = await coordinator.persistObvMessageFromUserNotification(obvMessage: obvMessage, queuePriority: .normal)
            
            switch result {

            case .success:
                
                // If we reaceived an update on the ObvMessage we just persisted, e.g., because the sender of the message updated the body of the message,
                // we also persist the update
                
                if let obvMessageUpdate {
                    _ = await coordinator.persistObvMessageFromUserNotification(obvMessage: obvMessageUpdate, queuePriority: .normal)
                }

                // We don't want to persist the ObvMessage twice, so we mark it as persisted
                
                do {
                    let op1 = MarkPersistedObvMessageAsPersistedInAppOperation(requestIdentifier: requestIdentifier)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    Task { await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp) }
                }

            case .notificationMustBeRemoved:

                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
                
                let op2 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
                let composedOp2 = createCompositionOfOneContextualOperation(op1: op2)
                await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp2)
                
            }
                        
        }
        
    }
    
}


// MARK: - Listening to the engine's notification on new ObvMessage received

extension UserNotificationsCoordinator {
    
    private func listenToNotifications() {
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeNewMessagesReceived(within: NotificationCenter.default) { [weak self] messages in
                Task { [weak self] in
                    for message in messages {
                        switch message {
                        case .obvMessage(let obvMessage):
                            await self?.processNewMessageReceivedNotification(obvMessage: obvMessage)
                        case .obvOwnedMessage:
                            return
                        }
                    }
                }
            },
            ObvMessengerInternalNotification.observePostUserNotificationAsAnotherCallParticipantStartedCamera { otherParticipantNames in
                Task { [weak self] in await self?.processPostUserNotificationAsAnotherCallParticipantStartedCamera(otherParticipantNames: otherParticipantNames) }
            },
        ])
        
    }

}


// MARK: - Removing reaction notifications on entering discussion

extension UserNotificationsCoordinator {
    
    /// We observe the current discussion shown on screen. When it changes, we remove all notifications concerning reactions for messages within this discussion.
    private func continuouslyRemoveUserNotificationsOfReactionOnEnteringDiscussion() {
        OlvidUserActivitySingleton.shared.$currentUserActivity
            .compactMap(\.?.currentDiscussion)
            .sink { [weak self] currentDiscussionIdentifier in
                Task { [weak self] in
                    await self?.removeAllReactionNotificationsForDiscussion(discussionIdentifier: currentDiscussionIdentifier)
                }
            }
            .store(in: &cancellables)
    }

    
    private func removeAllReactionNotificationsForDiscussion(discussionIdentifier: ObvDiscussionIdentifier) async {
        
        let op1 = GetRequestIdentifiersForShownReactionsOnSentMessagesOperation(discussionIdentifier: discussionIdentifier)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp)
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: op1.requestIdentifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: op1.requestIdentifiers)

        for requestIdentifier in op1.requestIdentifiers {
            let op2 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
            let composedOp2 = createCompositionOfOneContextualOperation(op1: op2)
            await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp2)
        }
        
    }
    
}


// MARK: - Implementing PersistedCallLogItemDelegate

extension UserNotificationsCoordinator: PersistedCallLogItemObserver {
    
    func aPersistedCallLogItemCallReportKindHasChanged(callLog: PersistedCallLogItemStructure) async {
        
        // The intent manager also listens to this notification.
        // Make sure **we** are in charge
        
        switch callLog.notificationKind {
        case .none:
            return
        case .startCallItentOnly:
            // The intent manager is in charge of suggesting an intent
            return
        case .userNotificationAndStartCallIntent:
            // We are in charge of scheduling a local user notification and of suggesting the intent
            break
        }

        do {
            let requestIdentifier = UUID().uuidString
            let content = try await ObvUserNotificationContentCreator.createNotificationContentForCallLog(callLog: callLog)
            let notification = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: nil)
            try await UNUserNotificationCenter.current().add(notification)
        } catch {
            Self.logger.fault("Could not schedule a local user notification for the call log: \(error.localizedDescription)")
            assertionFailure()
        }

    }
    
}


// MARK: - Implementing PersistedObvOwnedIdentityDelegate

extension UserNotificationsCoordinator: PersistedObvOwnedIdentityObserver {
    
    /// When a profile (owned identity) is hidden, we remove all notifications concerning this profile.
    func aPersistedObvOwnedIdentityIsHiddenChanged(ownedCryptoId: ObvCryptoId, isHidden: Bool) async {
        
        guard isHidden else { return }
        
        let op1 = GetRequestIdentifiersOfShownUserNotificationsOperation(.ownedCryptoId(ownedCryptoId: ownedCryptoId))
        let composedOp1 = createCompositionOfOneContextualOperation(op1: op1)
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp1)

        let requestIdentifiers = op1.requestIdentifiers
        guard !requestIdentifiers.isEmpty else { return }
        
        // If we reach this line, there is user notification to delete
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
        
        for requestIdentifier in requestIdentifiers {
            let op2 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
            let composedOp2 = createCompositionOfOneContextualOperation(op1: op2)
            await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp2)
        }
        
    }
    
}


// MARK: - Implementing PersistedDiscussionDelegate

extension UserNotificationsCoordinator: PersistedDiscussionObserver {
    
    func aPersistedDiscussionStatusChanged(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, status: ObvUICoreData.PersistedDiscussion.Status) async {

        guard status == .locked else { return }
        
        await self.removeAllUserNotificationsForDiscussion(discussionIdentifier: discussionIdentifier)
        
    }
    
    /// When a discussion is archived, all the messages are deleted (but this does not trigger a deletion notification for each message). So we use this method to remove all the user notifications concerning this discussion.
    func aPersistedDiscussionIsArchivedChanged(discussionIdentifier: ObvDiscussionIdentifier, isArchived: Bool) async {

        guard isArchived else { return }
        
        await self.removeAllUserNotificationsForDiscussion(discussionIdentifier: discussionIdentifier)
        
    }
    
    /// When a discussion is deleted, we removes all the user notifications relating to that discussion
    func aPersistedDiscussionWasDeleted(discussionIdentifier: ObvDiscussionIdentifier) async {
        await self.removeAllUserNotificationsForDiscussion(discussionIdentifier: discussionIdentifier)
    }
    
    
    /// When a discussion is read (either locally or from another owned device), we remove all **reaction** user notifications for that discussion.
    ///
    /// We restrict to reactions, since the "received message" user notification are already dealt with.
    func aPersistedDiscussionWasRead(discussionIdentifier: ObvDiscussionIdentifier, localDateWhenDiscussionRead: Date) async {
        
        let op1 = GetRequestIdentifiersOfShownUserNotificationsOperation(.restrictToReactionNotifications(discussionIdentifier: discussionIdentifier))
        let composedOp1 = createCompositionOfOneContextualOperation(op1: op1)
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp1)

        let requestIdentifiers = op1.requestIdentifiers
        
        // If we reach this line, there is user notification to delete
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
        
        for requestIdentifier in requestIdentifiers {
            let op2 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
            let composedOp2 = createCompositionOfOneContextualOperation(op1: op2)
            await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp2)
        }
        
        // Remove any other notification that has the discussionIdentifier set. This happens, e.g., for missed call notifications,
        // that are not stored in the User notification database as they are scheduled by the app.
        
        do {
            let requestIdentifiers = await UNUserNotificationCenter.current().deliveredNotifications()
                .filter({ $0.request.content.discussionIdentifier == discussionIdentifier })
                .map({ $0.request.identifier })
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
        }

    }
        
}


// MARK: - Implementing PersistedMessageReceivedDelegate

extension UserNotificationsCoordinator: PersistedMessageReceivedObserver {
    
    func persistedMessageReceivedWasInserted(receivedMessage: ObvUICoreDataStructs.PersistedMessageReceivedStructure) async {
        // We don't do anything when a PersistedMessageReceived is inserted: we already scheduled a notification for that message when receiving the corresponding ObvMessage from the engine.
    }
    
    
    func newReturnReceiptToSendForPersistedMessageReceived(returnReceiptToSend: ObvTypes.ObvReturnReceiptToSend) async {
        // Nothing to do in this coordinator, the return receipts are sent by the PersistedDiscussionsUpdatesCoordinator
    }
    
    
    /// Called when a `PersistedMessageReceived` is read. In that case, we want to remove any corresponding user notification.
    func persistedMessageReceivedWasRead(ownedCryptoId: ObvCryptoId, messageIdFromServer: UID) async {
        
        let op1 = GetRequestIdentifierOfShownUserNotificationForReceivedMessageOperation(ownedCryptoId: ownedCryptoId, messageIdFromServer: messageIdFromServer)
        let composedOp1 = createCompositionOfOneContextualOperation(op1: op1)
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp1)
        
        guard let requestIdentifier = op1.requestIdentifier else { return }
        
        // If we reach this line, there is user notification to delete
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
        
        let op2 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
        let composedOp2 = createCompositionOfOneContextualOperation(op1: op2)
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp2)

    }

}


// MARK: - Implementing PersistedMessageDelegate

extension UserNotificationsCoordinator: PersistedMessageObserver {
    
    /// Called when a sent or received message was wiped or deleted. When the identified message is a received message, we want to remove the corresponding user notifications if it exists.
    func aPersistedMessageWasWipedOrDeleted(messageIdentifier: ObvAppTypes.ObvMessageAppIdentifier) async {
        
        guard messageIdentifier.isReceived else { return }

        let op1 = GetRequestIdentifiersOfShownUserNotificationsOperation(.messageIdentifiers(messageAppIdentifiers: [messageIdentifier]))
        let composedOp1 = createCompositionOfOneContextualOperation(op1: op1)
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp1)

        let requestIdentifiers = op1.requestIdentifiers
        guard !requestIdentifiers.isEmpty else { return }
        
        // If we reach this line, there is user notification to delete
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
        
        for requestIdentifier in requestIdentifiers {
            let op2 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
            let composedOp2 = createCompositionOfOneContextualOperation(op1: op2)
            await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp2)
        }
        
    }
    
}


// MARK: - Implementing PersistedInvitationDelegate

extension UserNotificationsCoordinator: PersistedInvitationObserver {
    
    /// Called when an invitation is deleted. We delete the corresponding user notification.
    func aPersistedInvitationWasDeleted(ownedCryptoId: ObvCryptoId, invitationUUID: UUID) async {
        
        let requestIdentifier = invitationUUID.uuidString
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
        
    }
    
    
    /// Called when an invitation is created or updated. We will use the `PersistedInvitationStructure` to schedule a local user notification
    func aPersistedInvitationWasInsertedOrUpdated(invitation: PersistedInvitationStructure) async {
        
        let requestIdentifier = invitation.obvDialog.uuid.uuidString

        // Start by removing any pre-existing user notification for an invitation with the same UUID
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
        
        // Determine the new user notification to show for this invitation

        let notificationToShow = await ObvUserNotificationContentCreator.determineNotificationToShow(invitation: invitation)
        
        switch notificationToShow {
            
        case .silent:
            
            return
            
        case .full(content: let content):
            
            // There might be a notification to remove: one that would have been posted by the notification extension when receiving
            // the protocol message
            
            if let toRemove = content.toRemove {
                await removeAllUserNotificationsAboutObvProtocolMessage(obvProtocolMessage: toRemove)
            }

            // We create and add the user notification based on the content
            
            let notification = UNNotificationRequest(identifier: requestIdentifier, content: content.content, trigger: nil)
        
            do {
                // Note that if the user disallowed notifications (e.g., from the Settings app), the following method call does nothing.
                try await UNUserNotificationCenter.current().add(notification)
            } catch {
                Self.logger.fault("Failed to add a local user notification for an invitation: \(error.localizedDescription)")
            }

        }
        
    }
    
    
    /// Removes all existing user notifications related to the provided `ObvProtocolMessage`.
    ///
    /// This method is called when the app publishes a new notification for an inserted `PersistedInvitation`, allowing it to override any previous notifications that may have been published by the notification extension.
    ///
    /// The reason for removing these older notifications is that they lack associated actions (e.g., accept/reject), which are available in notifications published directly by the app.
    private func removeAllUserNotificationsAboutObvProtocolMessage(obvProtocolMessage: ObvProtocolMessage) async {

        let identifiersOfNotificationsToRemove = await UNUserNotificationCenter.current().deliveredNotifications()
            .filter({ $0.request.content.obvCategoryIdentifier == .protocolMessage && $0.request.content.obvProtocolMessage?.obvEqual(to: obvProtocolMessage) == true })
            .map({ $0.request.identifier })

        guard !identifiersOfNotificationsToRemove.isEmpty else { return }
        
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiersOfNotificationsToRemove)
        
    }
    
}


// MARK: - Processing notifications

extension UserNotificationsCoordinator {
    
    /// When a user starts her camera during a video call, we notify, then remove the notification after a few seconds.
    private func processPostUserNotificationAsAnotherCallParticipantStartedCamera(otherParticipantNames: [String]) async {
        let requestIdentifier = StaticRequestIdentifier.postUserNotificationAsAnotherCallParticipantStartedCamera
        let content: UNNotificationContent
        do {
            content = try ObvUserNotificationContentCreator.createNotificationContentWhenAnotherCallParticipantStartedCamera()
        } catch {
            Self.logger.fault("Could not create notification content: \(error.localizedDescription)")
            return
        }
        let notification = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: nil)
        do {
            // Note that if the user disallowed notifications (e.g., from the Settings app), the following method call does nothing.
            try await UNUserNotificationCenter.current().add(notification)
        } catch {
            Self.logger.fault("Failed to add a local user notification for a received message: \(error.localizedDescription)")
            return
        }
        // Remove the notification after a few seconds
        try? await Task.sleep(seconds: 5)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
        
    }
    
    
    private func processNewMessageReceivedNotification(obvMessage: ObvMessage) async {
        
        // Don't publish a user notification of "old" messages
        
        guard obvMessage.downloadTimestampFromServer.timeIntervalSince(obvMessage.messageUploadTimestampFromServer) < .init(minutes: 5) else {
            return
        }
                
        do {
            
            let requestIdentifier = UUID().uuidString

            let content: UNNotificationContent

            do {
                
                // Determine the kind of notification to show
                
                let notificationToShow = try await ObvUserNotificationContentCreator.determineNotificationToShow(obvMessage: obvMessage, obvStackShared: ObvStack.shared)
                
                // Construct the actual notification depending on the kind of notification to show
                
                switch notificationToShow {
                    
                case .silent:
                    
                    return
                    
                case .minimal(content: let _content), .silentWithUpdatedBadgeCount(content: let _content):
                    
                    content = _content
                    
                case .addReceivedMessage(content: let _content, messageAppIdentifier: let messageAppIdentifier, userNotificationCategory: let userNotificationCategory, contactDeviceUIDs: _):
                    
                    // Make sure we are in charge of posting the notification by trying to create a PersistedUserNotification
                    
                    let op1 = CreatePersistedUserNotificationForReceivedMessageOperation(
                        requestIdentifier: requestIdentifier,
                        obvMessage: obvMessage,
                        receivedMessageAppIdentifier: messageAppIdentifier,
                        userNotificationCategory: userNotificationCategory,
                        creator: .mainApp)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp)
                    
                    guard let result = op1.result else {
                        Self.logger.error("Could not create the PersistedUserNotification. We don't schedule any user notification.")
                        return
                    }
                    
                    switch result {
                    case .existed:
                        Self.logger.info("We don't schedule any user notification as one already exists for this ObvMessage")
                        return
                    case .created:
                        Self.logger.info("We just persisted the ObvMessage in the user notification DB, we will schedule a local user notification.")
                    }
                    
                    content = _content
                    
                case .addReactionOnSentMessage(content: let _content, sentMessageReactedTo: let sentMessageReactedTo, reactor: let reactor, userNotificationCategory: let userNotificationCategory):
                    
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
                        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp)
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
                        return
                    }
                    
                    // Then we add a notification for the new reaction

                    let op1 = CreatePersistedUserNotificationForReceivedReactionOperation(
                        requestIdentifier: requestIdentifier,
                        obvMessage: obvMessage,
                        sentMessageReactedTo: sentMessageReactedTo,
                        reactor: reactor,
                        userNotificationCategory: userNotificationCategory,
                        creator: .mainApp)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp)
                    
                    guard let result = op1.result else {
                        Self.logger.error("Could not create the PersistedUserNotification. We don't schedule any user notification.")
                        return
                    }
                    
                    switch result {
                    case .existed:
                        Self.logger.info("We don't schedule any user notification as one already exists for this ObvMessage")
                        return
                    case .created:
                        Self.logger.info("We just persisted the ObvMessage in the user notification DB, we will schedule a local user notification.")
                    }
                    
                    content = _content
                    
                case .removeReceivedMessages(content: _, messageAppIdentifiers: _),
                        .removePreviousNotificationsBasedOnObvDiscussionIdentifier(content: _, obvDiscussionIdentifier: _):
                    
                    // These "notificationToShow" are only used to remove notifications concerning received messages from the notification extension
                    
                    return
                    
                case .updateReceivedMessage(content: let _content, messageAppIdentifier: let messageAppIdentifier):

                    let op1 = MarkReceivedMessageNotificationAsUpdatedOperation(
                        messageAppIdentifier: messageAppIdentifier,
                        dateOfUpdate: obvMessage.messageUploadTimestampFromServer,
                        newRequestIdentifier: requestIdentifier,
                        obvMessageUpdate: obvMessage)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp)
                    
                    guard let previousRequestIdentifier = op1.previousRequestIdentifier, composedOp.isFinished, !composedOp.isCancelled else {
                        Self.logger.info("We don't update the user notification for the received message that was edited")
                        return
                    }
                    
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [previousRequestIdentifier])
                    
                    content = _content
                                        
                case .removeReactionOnSentMessage(content: let _content, sentMessageReactedTo: let sentMessageReactedTo, reactor: let reactor):
                    
                    let existingNotifications = await UNUserNotificationCenter.current().deliveredNotifications()
                        .filter({ $0.request.content.reactor == reactor })
                        .filter({ $0.request.content.sentMessageReactedTo == sentMessageReactedTo })
                    
                    // We remove any earlier reaction notification on the same message from the same creator
                    
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
                        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp)
                    }
                    
                    content = _content

                }
                
            }

            // If we reach this point, we are in charge of posting the notification

            let notification = UNNotificationRequest(identifier: requestIdentifier, content: content, trigger: nil)

            do {
                // Note that if the user disallowed notifications (e.g., from the Settings app), the following method call does nothing.
                try await UNUserNotificationCenter.current().add(notification)
            } catch {
                Self.logger.fault("Failed to add a local user notification for a received message: \(error.localizedDescription)")
            }

        } catch {
            
            Self.logger.fault("Could not schedule local user notification: \(error.localizedDescription)")
            assertionFailure()
            
        }
        
    }
    
}


// MARK: - Implementing UNUserNotificationCenterDelegate

extension UserNotificationsCoordinator: UNUserNotificationCenterDelegate {
    
    /// Asks the delegate how to handle a notification that arrived while the app was running in the foreground.
    ///
    /// All remote user notifications are processed through the notification extension, even when the app is in the foreground. However, if the notification extension successfully decrypts and publishes
    /// a user notification while the app is active, this method is triggered, providing an opportunity to customize the presentation options.
    ///
    /// It's worth noting that, in general, the notification extension fails to post a user notification when the app is in the foreground, as the app typically receives and decrypts messages more quickly due to the
    /// WebSocket connection. As a result, the notification extension fails to decrypt and returns a 'silent' notification. In such cases, since no user notification is presented to the user,
    /// this method is not triggered because of a remote user notification posted by the notification extension, but by a local user notification posted by the app. Indeed, note that this method is also called when
    /// scheduling a local user notification (i.e., when scheduling a user notification from the app). So this is a good place to centralize the code allowing to test whether
    /// showing the notification is appropriate (e.g., we might decide not to show the notification for a given received message if the user is currently within the corresponding discussion).
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {

        // We expect all notification to have an ObvUserNotificationCategoryIdentifier
        
        guard let obvCategoryIdentifier = notification.request.content.obvCategoryIdentifier else {
            Self.logger.fault("Could not determine the ObvUserNotificationCategoryIdentifier of the notification to present. Not showing the notification.")
            assertionFailure()
            return []
        }
        
        // Make sure the user accepted to display notifications
        
        let authorizationStatus = await center.notificationSettings().authorizationStatus
        switch authorizationStatus {
        case .denied:
            return []
        case .authorized, .notDetermined, .provisional, .ephemeral:
            break
        @unknown default:
            break
        }

        // Wait until the app is initialized

        _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
        
        
        // If we reach this point, we know we are initialized and active. We decide what to show depending on the notification category and the  current activity of the user.

        switch obvCategoryIdentifier {
            
        case .minimal:
            
            // Don't show a minimal notification while the app is in the foreground
            return []
            
        case .acceptInvite, .invitationWithNoAction, .protocolMessage:
            
            // If the user is in the invitation tab, don't show the notification. Otherwise, show it
            
            if OlvidUserActivitySingleton.shared.currentUserActivity?.selectedTab == .invitations {
                return []
            } else {
                return [.badge, .banner, .sound, .list]
            }
            
        case .newMessage, .newMessageWithLimitedVisibility, .newMessageWithHiddenContent:
            
            // Under macOS, always show the new message notification if the current user interface active appearance is `inactive`
            // (which is the case, e.g., when the app is minimized or not the main active window)
            
            if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst{
                if OlvidUserActivitySingleton.shared.traitCollectionActiveAppearance != .active {
                    return [.badge, .banner, .sound, .list]
                }
            }
            
            // If the user is in the discussions tab (but not in a specific discussion), don't show the notification
            // This does not apply to macOS
            
            if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst{
                // This creteria does not apply on macOS
            } else {
                if OlvidUserActivitySingleton.shared.currentUserActivity?.selectedTab == .latestDiscussions &&
                    OlvidUserActivitySingleton.shared.currentUserActivity?.currentDiscussion == nil {
                    return []
                }
            }
            
            // If the user is currently displaying the discussion corresponding to the new message, don't show the notification
            
            guard let discussionIdentifier = notification.request.content.discussionIdentifier else {
                assertionFailure()
                return []
            }
            
            if OlvidUserActivitySingleton.shared.currentUserActivity?.currentDiscussion == discussionIdentifier {
                return []
            }
            
            // In all other cases, show the notification
            
            return [.badge, .banner, .sound, .list]
            
        case .newReaction:
            
            guard let discussionIdentifier = notification.request.content.discussionIdentifier else {
                assertionFailure()
                return []
            }

            // Under macOS, always show the new reaction notification if the current user interface active appearance is `inactive`
            // (which is the case, e.g., when the app is minimized or not the main active window)
            
            if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst{
                if OlvidUserActivitySingleton.shared.traitCollectionActiveAppearance != .active {
                    return [.badge, .banner, .sound, .list]
                }
            }

            // If the user is currently displaying the discussion corresponding to the new message on which we received a reaction,
            // show a discrete notification. Otherwise, show a notification.

            if OlvidUserActivitySingleton.shared.currentUserActivity?.currentDiscussion == discussionIdentifier {
                return [.banner]
            } else {
                return [.badge, .banner, .sound, .list]
            }

        case .missedCall, .postUserNotificationAsAnotherCallParticipantStartedCamera, .rejectedIncomingCallBecauseOfDeniedRecordPermission:
            
            return [.badge, .banner, .sound, .list]
            
        }

    }
    

    /// `UNUserNotificationCenterDelegate` method called when the user performs an action on a user notification.
    ///
    /// Note that simply tapping or dismissing a notification is an action, as well as all the custom actions defined in `ObvUserNotificationAction`.
    /// We process all these actions here.
    @MainActor
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        
        do {
            
            Self.logger.info("🥏 Call to userNotificationCenter didReceive withCompletionHandler")
            
            _ = await NewAppStateManager.shared.waitUntilAppIsInitialized()
            
            // Process the response depending on the notification category
            
            let categoryIdentifier = response.notification.request.content.categoryIdentifier
            guard let userNotificationCategory = ObvUserNotificationCategoryIdentifier(rawValue: categoryIdentifier) else {
                Self.logger.fault("Could not determine user notification category: \(categoryIdentifier)")
                assertionFailure()
                return
            }
            
            switch userNotificationCategory {
                
            case .minimal:
                
                return
                
            case .newMessage,
                    .newMessageWithLimitedVisibility,
                    .newMessageWithHiddenContent,
                    .newReaction:
                
                try await processUNNotificationResponseForNewMessageUserNotificationCategory(response: response)
                
            case .invitationWithNoAction:
                
                try await processUNNotificationResponseForInvitationWithNoActionUserNotificationCategory(response: response)
                                
            case .acceptInvite:

                try await processUNNotificationResponseForInvitationWithAcceptInviteUserNotificationCategory(response: response)
                
            case .missedCall:
                
                try await processUNNotificationResponseForMissedCallUserNotificationCategory(response: response)

            case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
                
                let deepLink = ObvDeepLink.requestRecordPermission
                _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
                ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                    .postOnDispatchQueue()
                
            case .postUserNotificationAsAnotherCallParticipantStartedCamera:
                
                let deepLink = ObvDeepLink.olvidCallView
                _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
                ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                    .postOnDispatchQueue()
                
            case .protocolMessage:
                
                guard let obvContactIdentifier = response.notification.request.content.contactIdentifier else {
                    assertionFailure()
                    return
                }
                let deepLink = ObvDeepLink.invitations(ownedCryptoId: obvContactIdentifier.ownedCryptoId)
                _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
                ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                    .postOnDispatchQueue()

            }
            
        } catch {
            Self.logger.fault("Failed to process the user action performed on the notification: \(error.localizedDescription)")
            assertionFailure()
        }

    }

    
}


// MARK: - Private helpers

extension UserNotificationsCoordinator {
    
    private func removeAllUserNotificationsForDiscussion(discussionIdentifier: ObvDiscussionIdentifier) async {
        
        let op1 = GetRequestIdentifiersOfShownUserNotificationsOperation(.discussionAndLastReadMessageServerTimestamp(discussionIdentifier: discussionIdentifier, lastReadMessageServerTimestamp: nil))
        let composedOp1 = createCompositionOfOneContextualOperation(op1: op1)
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp1)

        let requestIdentifiers = op1.requestIdentifiers
        guard !requestIdentifiers.isEmpty else { return }
        
        // If we reach this line, there is user notification to delete
        
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
        
        for requestIdentifier in requestIdentifiers {
            let op2 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
            let composedOp2 = createCompositionOfOneContextualOperation(op1: op2)
            await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp2)
        }

    }
    
    
    private func persistObvMessageContainedOrLogError(in response: UNNotificationResponse) async throws {
        do {
            return try await persistObvMessageContained(in: response)
        } catch {
            switch error {
            case .coordinatorIsNil:
                Self.logger.fault("Cannot process the user action performed on the notification as the coordinator is nil. It should have been set during bootstrap.")
            case .failedToPersistObvMessageFromUserNotification:
                Self.logger.error("Could not process the ObvMessage extracted from the actioned notification. Cannot navigate to the message.")
            case .failedToGetPersistedMessagePermanentID:
                Self.logger.error("Could not obtain identifier of the persisted message corresponding to the user notification. Cannot navigate to the message.")
            }
            assertionFailure()
            throw error
        }
    }
    
    
    /// If the user interacts with a local or remote user notification (e.g. tap the notification, perform a custom action, etc.), this method always gets called (by the ``userNotificationCenter(_:didReceive:)`` delegate method).
    ///
    /// Independently on the exact creator of the user notification (notification extention or main app), we always extract the `ObvMessage` from the notification, and communicate it to the discussion coordinator to make sure it is persisted.
    /// This coordinator sends us back a message identifier that will allow us to post a deeplink to that message.
    ///
    /// Note that this method is also called when the user dismisses the notification (since it is called for all user actions). This will allow to make sure a temporary received message
    /// is indeed persisted in the received messages database at the app level.
    private func persistObvMessageContained(in response: UNNotificationResponse) async throws(ObvProcessUNNotificationResponseError) {
        
        guard let coordinator else {
            Self.logger.fault("Cannot process the user action performed on the notification as the coordinator is nil. It should have been set during bootstrap.")
            assertionFailure()
            throw .coordinatorIsNil
        }
        
        let requestIdentifier = response.notification.request.identifier
        
        let op1 = GetObvMessageFromPersistedUserNotificationOperation(requestIdentifier: requestIdentifier)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh
        composedOp.qualityOfService = .userInitiated
        await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp)
        
        guard op1.isFinished && !op1.isCancelled else {
            assertionFailure()
            return
        }
        
        guard let obvMessage = op1.obvMessage else {
            // There is nothing to persist. This happens, e.g., if the notification is created by the app.
            return
        }

        let result = await coordinator.persistObvMessageFromUserNotification(obvMessage: obvMessage, queuePriority: .veryHigh)
        
        switch result {

        case .success:

            // If we reaceived an update on the ObvMessage we just persisted, e.g., because the sender of the message updated the body of the message,
            // we also persist the update
            
            if let obvMessageUpdate = op1.obvMessageUpdate {
                _ = await coordinator.persistObvMessageFromUserNotification(obvMessage: obvMessageUpdate, queuePriority: .veryHigh)
            }

        case .notificationMustBeRemoved:

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [requestIdentifier])
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [requestIdentifier])
            
            let op2 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
            let composedOp2 = createCompositionOfOneContextualOperation(op1: op2)
            composedOp2.queuePriority = .veryHigh
            composedOp2.qualityOfService = .userInitiated
            await notificationsCoordinatorQueue.addAndAwaitOperation(composedOp2)

        }
                
    }

}


// MARK: - Creating compositions of contextual operations

extension UserNotificationsCoordinator {
    
    func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) -> CompositionOfOneContextualOperation<T> {
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvUserNotificationsStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

}


// MARK: - Errors

extension UserNotificationsCoordinator {
    
    enum ObvProcessUNNotificationResponseError: Error {
        case coordinatorIsNil
        case failedToPersistObvMessageFromUserNotification
        case failedToGetPersistedMessagePermanentID
    }
    
    enum ObvError: Error {
        case unexpectedAction
        case coordinatorIsNil
        case obvDialogIsNil
        case couldNotExtractInvitationUUID
        case couldNotGetObvDialogOfInvitation
        case obvEngineIsNil
        case messageAppIdentifierIsNil
    }
    
}


// MARK: - Protocol definition: CoordinatorOfObvMessagesReceivedFromUserNotificationExtension

enum PersistObvMessageFromUserNotificationResult {
    case success
    case notificationMustBeRemoved
}

/// Expected to be implemented by the `PersistedDiscussionsUpdatesCoordinator` and set during initialization
protocol CoordinatorOfObvMessagesReceivedFromUserNotificationExtension: AnyObject {
    func persistObvMessageFromUserNotification(obvMessage: ObvMessage, queuePriority: Operation.QueuePriority) async -> PersistObvMessageFromUserNotificationResult
    func processUserReplyFromNotificationExtension(replyBody: String, messageRepliedTo: ObvMessageAppIdentifier) async throws
    func processUserWantsToMarkAsReadMessageShownInUserNotification(messageAppIdentifier: ObvMessageAppIdentifier) async throws
    func processUserWantsToMuteDiscussionOfMessageShownInUserNotification(messageAppIdentifier: ObvMessageAppIdentifier) async throws
    func processUserWantsToSendMessageFromUserNotification(body: String, discussionIdentifier: ObvDiscussionIdentifier) async throws
}



// MARK: - Processing UNNotificationResponse depending on the content's category

extension UserNotificationsCoordinator {
    
    private func processUNNotificationResponseForMissedCallUserNotificationCategory(response: UNNotificationResponse) async throws {

        // As we are considering a `missedCall` category, we expect the ObvUserNotificationContentCreator to have set the contact (i.e., the caller)
        // and the appropriate as parameters of the notification's content
        
        guard let callerIdentifier = response.notification.request.content.contactIdentifier else {
            Self.logger.fault("Could not process missedCall notification response as the caller identifier is nost set")
            assertionFailure()
            return
        }
        
        guard let discussionIdentifier = response.notification.request.content.discussionIdentifier else {
            Self.logger.fault("Could not process missedCall notification response as the discussion identifier is nost set")
            assertionFailure()
            return
        }
        
        switch response.actionIdentifier {
            
        case UNNotificationDismissActionIdentifier:
            // Do nothing
            return
            
        case UNNotificationDefaultActionIdentifier:
            
            // Navigate to the discussion
            guard let discussionPermanentID = await getPersistedDiscussionObjectPermanentID(discussionId: discussionIdentifier) else {
                Self.logger.fault("Could not determine the one2one discussion we have with the caller")
                assertionFailure()
                return
            }
            
            let deepLink = ObvDeepLink.singleDiscussion(ownedCryptoId: callerIdentifier.ownedCryptoId, objectPermanentID: discussionPermanentID)
            
            _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()

            return
            
        default:

            guard let obvUserNotificationAction = ObvUserNotificationAction(rawValue: response.actionIdentifier) else {
                Self.logger.fault("Unrecognized user notification action. The received identifier is \(response.actionIdentifier).")
                assertionFailure()
                return
            }
            
            switch obvUserNotificationAction {
                
            case .accept, .decline, .mute, .replyTo, .markAsRead:
                assertionFailure("Unexpected action for a missedCall category")
                return

            case .sendMessage:
                
                guard let textResponse = response as? UNTextInputNotificationResponse, !textResponse.userText.isEmpty else {
                    assertionFailure()
                    return
                }
                
                // We want the text response to go into the discussion we have with the caller, which is not necessarilly the one in the notification (which
                // might be a group discussion)
                
                guard let discussionIdentifier = await getOneToOneDiscussionIdentifier(contactIdentifier: callerIdentifier) else {
                    assertionFailure()
                    return
                }
                
                do {
                    try await coordinator?.processUserWantsToSendMessageFromUserNotification(body: textResponse.userText, discussionIdentifier: discussionIdentifier)
                } catch {
                    Self.logger.fault("Failed to process the user request to reply to a message from a user notification: \(error.localizedDescription)")
                    return
                }

            case .callBack:
                
                let ownedCryptoId = discussionIdentifier.ownedCryptoId
                let contactCryptoId = callerIdentifier.contactCryptoId
                let groupId: GroupIdentifier?
                switch discussionIdentifier {
                case .oneToOne:
                    groupId = nil
                case .groupV1(let id):
                    groupId = .groupV1(groupV1Identifier: id.groupV1Identifier)
                case .groupV2(let id):
                    groupId = .groupV2(groupV2Identifier: id.identifier.appGroupIdentifier)
                }

                ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set([contactCryptoId]), groupId: groupId, startCallIntent: nil)
                    .postOnDispatchQueue()

                return
            }

        }
        
    }
    

    /// Helper method called by the  `UNUserNotificationCenterDelegate` delegate method called when the user interacts with
    /// a user notification of category `.acceptInvite`.
    private func processUNNotificationResponseForInvitationWithAcceptInviteUserNotificationCategory(response: UNNotificationResponse) async throws {
        
        guard let obvEngine else {
            assertionFailure()
            throw ObvError.obvEngineIsNil
        }
        
        guard var obvDialog = response.notification.request.content.obvDialog else {
            assertionFailure()
            throw ObvError.obvDialogIsNil
        }

        switch response.actionIdentifier {
            
        case UNNotificationDefaultActionIdentifier,
                UNNotificationDismissActionIdentifier:

            // The behaviour shall be the same than for invitation with no actions
            try await processUNNotificationResponseForInvitationWithNoActionUserNotificationCategory(response: response)
            return
            
        default:

            guard let obvUserNotificationAction = ObvUserNotificationAction(rawValue: response.actionIdentifier) else {
                Self.logger.fault("Unrecognized user notification action. The received identifier is \(response.actionIdentifier).")
                assertionFailure()
                return
            }
            
            switch obvUserNotificationAction {
                
            case .mute, .callBack, .replyTo, .sendMessage, .markAsRead:

                throw ObvError.unexpectedAction
                
            case .accept:

                try obvDialog.setResponseToAcceptInviteGeneric(acceptInvite: true)
                
            case .decline:
                
                try obvDialog.setResponseToAcceptInviteGeneric(acceptInvite: false)

            }

            try await obvEngine.respondTo(obvDialog)
            
        }
        
    }
    

    /// Helper method called by the  `UNUserNotificationCenterDelegate` delegate method called when the user interacts with
    /// a user notification of category `.invitationWithNoAction`.
    private func processUNNotificationResponseForInvitationWithNoActionUserNotificationCategory(response: UNNotificationResponse) async throws {
        
        guard let ownedCryptoId = response.notification.request.content.obvDialog?.ownedCryptoId else {
            assertionFailure()
            throw ObvError.obvDialogIsNil
        }

        switch response.actionIdentifier {
            
        case UNNotificationDefaultActionIdentifier:

            // If the user tapped the notification, it means she wishes to open Olvid and navigate to invitations tab
            
            let deepLink = ObvDeepLink.invitations(ownedCryptoId: ownedCryptoId)
            
            _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()

            return
            
        case UNNotificationDismissActionIdentifier:
            
            // Nothing to do in particular
            return
            
        default:

            // Nothing to do in particular
            assertionFailure("We do not expect a specific action, this should be investigated.")
            return

        }
        
    }

    /// Helper method called by the  `UNUserNotificationCenterDelegate` delegate method called when the user interacts with
    /// a user notification of category `.newMessage`, `.newMessageWithLimitedVisibility`, or `.newReaction`.
    private func processUNNotificationResponseForNewMessageUserNotificationCategory(response: UNNotificationResponse) async throws {
        
        let requestIdentifier = response.notification.request.identifier

        guard let coordinator else {
            Self.logger.fault("Cannot process the user action performed on the notification as the coordinator is nil. It should have been set during bootstrap.")
            assertionFailure()
            throw ObvError.coordinatorIsNil
        }

        try await persistObvMessageContainedOrLogError(in: response)

        guard let messageAppIdentifier = response.notification.request.content.messageAppIdentifier ?? response.notification.request.content.sentMessageReactedTo else {
            throw ObvError.messageAppIdentifierIsNil
        }

        switch response.actionIdentifier {
            
        case UNNotificationDefaultActionIdentifier:
            
            // If the user tapped the notification, it means she wishes to open Olvid and navigate to the discussion.
            
            // Navigate to the message
            
            let deepLink = ObvDeepLink.message(messageAppIdentifier)
            
            _ = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
            
            // Since the user notification was tapped, it won't appear in the device's notification center anymore.
            // We update its entry in the user notification store
            
            let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            notificationsCoordinatorQueue.addOperation(composedOp)
            
            return
            
        case UNNotificationDismissActionIdentifier:
            
            // Since the user notification was dismissed, it won't appear in the device's notification center anymore.
            // We update its entry in the user notification store
            
            let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            notificationsCoordinatorQueue.addOperation(composedOp)
            
            return
            
        default:
            
            guard let obvUserNotificationAction = ObvUserNotificationAction(rawValue: response.actionIdentifier) else {
                Self.logger.fault("Unrecognized user notification action. The received identifier is \(response.actionIdentifier).")
                assertionFailure()
                return
            }
            
            switch obvUserNotificationAction {
                
            case .accept, .decline, .callBack, .sendMessage:
                throw ObvError.unexpectedAction
                
            case .mute:
                
                // This action concerns user notification with the `.newMessage`, `.newMessageWithLimitedVisibility`, or `.newReaction` category. See `static ObvUserNotificationCategory.setAllNotificationCategories(on:)`.
                
                do {
                    try await coordinator.processUserWantsToMuteDiscussionOfMessageShownInUserNotification(messageAppIdentifier: messageAppIdentifier)
                } catch {
                    Self.logger.fault("Failed to process the user request to mute the discussion of a message from a user notification: \(error.localizedDescription)")
                    return
                }
                
                return
                
            case .replyTo:
                
                // This action only concerns user notification with the `.newMessage` category. See `static ObvUserNotificationCategory.setAllNotificationCategories(on:)`.
                
                guard let replyBody = (response as? UNTextInputNotificationResponse)?.userText, !replyBody.isEmpty else {
                    assertionFailure()
                    return
                }
                
                do {
                    try await coordinator.processUserReplyFromNotificationExtension(replyBody: replyBody, messageRepliedTo: messageAppIdentifier)
                } catch {
                    Self.logger.fault("Failed to process the user request to reply to a message from a user notification: \(error.localizedDescription)")
                    return
                }
                
                let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                notificationsCoordinatorQueue.addOperation(composedOp)
                
                return
                
            case .markAsRead:
                
                // This action only concerns user notification with the `.newMessage` category. See `static ObvUserNotificationCategory.setAllNotificationCategories(on:)`.
                
                do {
                    try await coordinator.processUserWantsToMarkAsReadMessageShownInUserNotification(messageAppIdentifier: messageAppIdentifier)
                } catch {
                    Self.logger.error("Failed to process the user request to mark a message from a user notification: \(error.localizedDescription)")
                    return
                }
                
                let op1 = UpdateStatusOfPersistedUserNotificationOperation(requestIdentifier: requestIdentifier, newStatus: .removed)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                notificationsCoordinatorQueue.addOperation(composedOp)
                
                return
                
            }
            
        }

    }
    
}


// MARK: - Private helpers

extension UserNotificationsCoordinator {
    
    @MainActor
    private func getOneToOneDiscussionIdentifier(contactIdentifier: ObvContactIdentifier) async -> ObvDiscussionIdentifier? {
        guard let persistedContact = try? PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return nil
        }
        guard let discussionIdentifier = persistedContact.oneToOneDiscussion?.discussionIdentifier else {
            assertionFailure()
            return nil
        }
        return discussionIdentifier
    }
    
    
    /// Given a discussion identifier, this helper methods returns the permanent identifier of the corresponding discussion. Helps creating a deep link to the discussion.
    @MainActor
    private func getPersistedDiscussionObjectPermanentID(discussionId: ObvDiscussionIdentifier) async -> ObvManagedObjectPermanentID<PersistedDiscussion>? {
        guard let discussion = try? PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: discussionId.ownedCryptoId, discussionId: discussionId.toDiscussionIdentifier(), within: ObvStack.shared.viewContext) else {
            assertionFailure()
            return nil
        }
        return discussion.discussionPermanentID
    }
    
}
