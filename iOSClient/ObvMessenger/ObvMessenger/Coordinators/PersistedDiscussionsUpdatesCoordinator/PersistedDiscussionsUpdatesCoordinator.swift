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
import os.log
import CoreData
import ObvEngine
import CoreDataStack
import ObvCrypto
import OlvidUtils
import ObvTypes
import ObvUICoreData
import ObvSettings
import LinkPresentation


final class PersistedDiscussionsUpdatesCoordinator: OlvidCoordinator {
    
    let obvEngine: ObvEngine
    static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: PersistedDiscussionsUpdatesCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    private var kvoTokens = [NSKeyValueObservation]()
    let coordinatorsQueue: OperationQueue
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue
    private let queueForOperationsMakingEngineCalls: OperationQueue
    private let queueForDispatchingOffTheMainThread = DispatchQueue(label: "PersistedDiscussionsUpdatesCoordinator internal queue for dispatching off the main thread")
    private let internalQueueForAttachmentsProgresses = OperationQueue.createSerialQueue(name: "Internal queue for progresses", qualityOfService: .default)
    private let queueForLongRunningConcurrentOperations: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.name = "PersistedDiscussionsUpdatesCoordinator queue for long running tasks"
        return queue
    }()
    private let messagesKeptForLaterManager: MessagesKeptForLaterManager

    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)
    private var screenCaptureDetector: ScreenCaptureDetector?
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    init(obvEngine: ObvEngine, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue, queueForOperationsMakingEngineCalls: OperationQueue, queueForSyncHintsComputationOperation: OperationQueue, messagesKeptForLaterManager: MessagesKeptForLaterManager) {
        self.obvEngine = obvEngine
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        self.queueForOperationsMakingEngineCalls = queueForOperationsMakingEngineCalls
        self.queueForSyncHintsComputationOperation = queueForSyncHintsComputationOperation
        self.messagesKeptForLaterManager = messagesKeptForLaterManager
        listenToNotifications()
        Task {
            screenCaptureDetector = await ScreenCaptureDetector()
            await screenCaptureDetector?.setDelegate(to: self)
            await screenCaptureDetector?.startDetecting()
        }
    }
    
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {

        if forTheFirstTime {
            periodicallyRefreshReceivedAttachmentProgress()
            processUnprocessedRecipientInfosThatCanNowBeProcessed()
            deleteEmptyLockedDiscussion()
            trashOrphanedFilesFoundInTheFylesDirectory()
            deleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact()
            // No need to delete orphaned one to one discussions (i.e., without contact), they are cascade deleted
            // No need to delete orphaned group discussions (i.e., without contact group), they are cascade deleted
            // No need to delete orphaned PersistedMessageTimestampedMetadata, i.e., without message), they are cascade deleted
            bootstrapMessagesToBeWiped(preserveReceivedMessages: true)
            bootstrapWipeAllMessagesThatExpiredEarlierThanNow()
            deleteOldOrOrphanedDatabaseEntries()
            cleanExpiredMuteNotificationsSetting()
            cleanOrphanedPersistedMessageTimestampedMetadata()
            synchronizeAllOneToOneDiscussionTitlesWithContactNameOperation()
            synchronizeDiscussionsIllustrativeMessageAndRefreshNumberOfNewMessages()
            Task {
                await regularlyUpdateFyleMessageJoinWithStatusProgresses()
            }
        }

        // The following bootstrap methods are always called, not only the first time the app appears on screen
        
        await bootstrapMessagesDecryptedWithinNotificationExtension()
        wipeReadOnceAndLimitedVisibilityMessagesThatTheShareExtensionDidNotHaveTimeToWipe()

    }
    

    private static let errorDomain = "PersistedDiscussionsUpdatesCoordinator"
    private static func makeError(message: String) -> Error { NSError(domain: PersistedDiscussionsUpdatesCoordinator.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { PersistedDiscussionsUpdatesCoordinator.makeError(message: message) }
        
    // Variables used to refresh the attachment downloads progresses
    private var timerForRefreshingAttachmentDownloadProgresses: Timer?
    private static let timeIntervalForRefreshingAttachmentDownloadProgresses: TimeInterval = 0.3
    private var dateOfLastReceivedAttachmentProgressRefreshQuery = Date.distantPast
    
    private func periodicallyRefreshReceivedAttachmentProgress() {
        DispatchQueue.main.async { [weak self] in
            guard let _self = self else { return }
            _self.timerForRefreshingAttachmentDownloadProgresses = Timer.scheduledTimer(
                timeInterval: PersistedDiscussionsUpdatesCoordinator.timeIntervalForRefreshingAttachmentDownloadProgresses,
                target: _self,
                selector: #selector(_self.requestAttachmentDownloadProgressesIfAppropriate),
                userInfo: nil,
                repeats: true)
        }
    }
    
    // This timer is used to periodically refresh the attachment download/upload progresses, which is particularly useful when they are stalled.
    // Indeed, in that case, the engine will stop returning progress updates (as we only request for progresses that were updated since our previous request).
    // In that case we want to update the throughput and remaining time of the progresses. We do it in this timer block.
    private var timerForRefreshingFyleMessageJoinWithStatusProgresses: Timer?
    
    @MainActor
    private func regularlyUpdateFyleMessageJoinWithStatusProgresses() {
        assert(Thread.isMainThread)
        guard self.timerForRefreshingFyleMessageJoinWithStatusProgresses == nil else { return }
        self.timerForRefreshingFyleMessageJoinWithStatusProgresses = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { timer in
            guard timer.isValid else { return }
            assert(Thread.isMainThread)
            Task {
                await FyleMessageJoinWithStatus.refreshAllProgresses()
            }
        })
    }

    /// This method is periodically called. It asks the engine to send fresh progresses for downloading attachments, when appropriate.
    @objc private func requestAttachmentDownloadProgressesIfAppropriate() {
        guard ObvUserActivitySingleton.shared.currentUserActivity.isContinueDiscussion else { return }
        
        let date = dateOfLastReceivedAttachmentProgressRefreshQuery
        dateOfLastReceivedAttachmentProgressRefreshQuery = Date()
        
        // Progresses for downloaded attachments
        Task {
            do {
                let progresses = try await obvEngine.requestDownloadAttachmentProgressesUpdatedSince(date: date)
                guard !progresses.isEmpty else { return }
                let op = ProcessNewReceivedJoinProgressesReceivedFromEngineOperation(progresses: progresses)
                internalQueueForAttachmentsProgresses.addOperation(op)
            } catch {
                os_log("Could not obtain download progresses from engine: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            }
        }
        
        // Progresses for uploaded attachments
        Task {
            do {
                let progresses = try await obvEngine.requestUploadAttachmentProgressesUpdatedSince(date: date)
                guard !progresses.isEmpty else { return }
                let op = ProcessNewSentJoinProgressesReceivedFromEngineOperation(progresses: progresses)
                internalQueueForAttachmentsProgresses.addOperation(op)
            } catch {
                os_log("Could not obtain download progresses from engine: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            }

        }
        
    }
    

    private func listenToNotifications() {
        
        defer {
            os_log("☎️ PersistedDiscussionsUpdatesCoordinator is listening to notifications", log: Self.log, type: .info)
        }
        
        // ObvMessengerCoreDataNotification
        
        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observeNewDraftToSend() { [weak self] draftPermanentID in
                Task { [weak self] in await self?.processNewDraftToSendNotification(draftPermanentID: draftPermanentID) }
            },
            ObvMessengerCoreDataNotification.observeASecureChannelWithContactDeviceWasJustCreated { [weak self] contactDeviceObjectID in
                self?.sendAppropriateDiscussionSharedConfigurationsToContact(input: .contactDevice(contactDeviceObjectID: contactDeviceObjectID), sendSharedConfigOfOneToOneDiscussion: true)
                self?.processUnprocessedRecipientInfosThatCanNowBeProcessed()
            },
            ObvMessengerCoreDataNotification.observePersistedContactGroupHasUpdatedContactIdentities() { [weak self] (persistedContactGroupObjectID, insertedContacts, removedContacts) in
                self?.processPersistedContactGroupHasUpdatedContactIdentitiesNotification(persistedContactGroupObjectID: persistedContactGroupObjectID, insertedContacts: insertedContacts, removedContacts: removedContacts)
            },
            ObvMessengerCoreDataNotification.observePersistedMessageReceivedWasDeleted() { [weak self] (_, messageIdentifierFromEngine, ownedCryptoId, _, _) in
                Task { [weak self] in await self?.processPersistedMessageReceivedWasDeletedNotification(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId) }
            },
            ObvMessengerCoreDataNotification.observePersistedMessageReceivedWasRead { (persistedMessageReceivedObjectID) in
                Task { [weak self] in await self?.processPersistedMessageReceivedWasReadNotification(persistedMessageReceivedObjectID: persistedMessageReceivedObjectID) }
            },
            ObvMessengerCoreDataNotification.observeReceivedFyleJoinHasBeenMarkAsOpened { (receivedFyleJoinID) in
                Task { [weak self] in await self?.processReceivedFyleJoinHasBeenMarkAsOpenedNotification(receivedFyleJoinID: receivedFyleJoinID) }
            },
            ObvMessengerCoreDataNotification.observeAReadOncePersistedMessageSentWasSent { [weak self] (persistedMessageSentPermanentID, persistedDiscussionPermanentID) in
                self?.processAReadOncePersistedMessageSentWasSentNotification(persistedMessageSentPermanentID: persistedMessageSentPermanentID, persistedDiscussionPermanentID: persistedDiscussionPermanentID)
            },
            ObvMessengerCoreDataNotification.observePersistedContactWasDeleted { [weak self ] _, _ in
                self?.processPersistedContactWasDeletedNotification()
            },
            ObvMessengerCoreDataNotification.observeADeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus { [weak self] (returnReceipt, contactCryptoId, ownedCryptoId, messageIdentifierFromEngine, attachmentNumber) in
                self?.processADeliveredReturnReceiptShouldBeSent(returnReceipt: returnReceipt, contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
            },
            ObvMessengerCoreDataNotification.observeADeliveredReturnReceiptShouldBeSentForPersistedMessageReceived { [weak self] returnReceipt, contactCryptoId, ownedCryptoId, messageIdentifierFromEngine in
                self?.processADeliveredReturnReceiptShouldBeSent(returnReceipt: returnReceipt, contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: nil)
            },
            ObvMessengerCoreDataNotification.observePersistedObvOwnedIdentityWasDeleted { [weak self] in
                self?.processPersistedObvOwnedIdentityWasDeleted()
            },
            ObvMessengerCoreDataNotification.observeAPersistedGroupV2MemberChangedFromPendingToNonPending { [weak self] contactObjectID in
                self?.sendAppropriateDiscussionSharedConfigurationsToContact(input: .contact(contactObjectID: contactObjectID), sendSharedConfigOfOneToOneDiscussion: false)
                self?.processUnprocessedRecipientInfosThatCanNowBeProcessed()
            },
            ObvMessengerCoreDataNotification.observePersistedDiscussionWasInsertedOrReactivated { [weak self] ownedCryptoId, discussionIdentifier in
                self?.processPersistedDiscussionWasInsertedOrReactivated(ownedCryptoId: ownedCryptoId, discussionIdentifier: discussionIdentifier)
            },
            ObvMessengerCoreDataNotification.observeAPersistedGroupV2WasInsertedInDatabase { [weak self] ownedCryptoId, groupIdentifier in
                Task { [weak self] in await self?.processAPersistedGroupV2WasInsertedInDatabase(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier) }
            },
            ObvMessengerCoreDataNotification.observePersistedContactWasInserted { [weak self] _, ownedCryptoId, contactCryptoId in
                Task { [weak self] in await self?.processPersistedContactWasInserted(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId) }
            },
        ])
        
        // Internal notifications (User requests)
        
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserRequestedDeletionOfPersistedMessage() { [weak self] (ownedCryptoId, persistedMessageObjectID, deletionType) in
                Task { [weak self] in await self?.processUserRequestedDeletionOfPersistedMessageNotification(ownedCryptoId: ownedCryptoId, persistedMessageObjectID: persistedMessageObjectID, deletionType: deletionType) }
            },
            ObvMessengerInternalNotification.observeUserRequestedDeletionOfPersistedDiscussion() { [weak self] (ownedCryptoId, discussionObjectID, deletionType, completionHandler) in
                self?.processUserRequestedDeletionOfPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionObjectID: discussionObjectID, deletionType: deletionType, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToReadReceivedMessageThatRequiresUserAction { [weak self] (ownedCryptoId, discussionId, messageId) in
                Task { [weak self] in await self?.processUserWantsToReadReceivedMessageThatRequiresUserActionNotification(ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageId: messageId) }
            },
            ObvMessengerInternalNotification.observeUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration { [weak self] ownedCryptoId, discussionId, expirationJSON in
                self?.processUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(ownedCryptoId: ownedCryptoId, discussionId: discussionId, expirationJSON: expirationJSON)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateDiscussionLocalConfiguration { [weak self] (value, localConfigurationObjectID) in
                self?.processUserWantsToUpdateDiscussionLocalConfigurationNotification(with: value, localConfigurationObjectID: localConfigurationObjectID)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateLocalConfigurationOfDiscussion { [weak self] (value, discussionPermanentID, completionHandler) in
                self?.processUserWantsToUpdateLocalConfigurationOfDiscussionNotification(with: value, discussionPermanentID: discussionPermanentID, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToSendEditedVersionOfSentMessage { [weak self] (ownedCryptoId, sentMessageObjectID, newTextBody) in
                self?.processUserWantsToSendEditedVersionOfSentMessage(ownedCryptoId: ownedCryptoId, sentMessageObjectID: sentMessageObjectID, newTextBody: newTextBody)
            },
            ObvMessengerInternalNotification.observeUserWantsToMarkAllMessagesAsNotNewWithinDiscussion { [weak self] (persistedDiscussionObjectID, completionHandler) in
                Task { [weak self] in
                    guard let self else { completionHandler(false); return }
                    do {
                        try await processUserWantsToMarkAllMessagesAsNotNewWithinDiscussionNotification(persistedDiscussionObjectID: persistedDiscussionObjectID)
                        DispatchQueue.main.async { completionHandler(true) }
                    } catch {
                        DispatchQueue.main.async { completionHandler(false) }
                    }
                }
            },
            ObvMessengerInternalNotification.observeUserWantsToRemoveDraftFyleJoin { [weak self] (draftFyleJoinObjectID) in
                self?.processUserWantsToRemoveDraftFyleJoinNotification(draftFyleJoinObjectID: draftFyleJoinObjectID)
            },
            ObvMessengerInternalNotification.observeUserRepliedToReceivedMessageWithinTheNotificationExtension { [weak self] contactPermanentID, messageIdentifierFromEngine, textBody, completionHandler in
                Task { [weak self] in await self?.processUserRepliedToReceivedMessageWithinTheNotificationExtensionNotification(contactPermanentID: contactPermanentID, messageIdentifierFromEngine: messageIdentifierFromEngine, textBody: textBody, completionHandler: completionHandler) }
            },
            ObvMessengerInternalNotification.observeUserRepliedToMissedCallWithinTheNotificationExtension { [weak self] discussionPermanentID, textBody, completionHandler in
                self?.processUserRepliedToMissedCallWithinTheNotificationExtensionNotification(discussionPermanentID: discussionPermanentID, textBody: textBody, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToMarkAsReadMessageWithinTheNotificationExtension { contactPermanentID, messageIdentifierFromEngine, completionHandler in
                Task { [weak self] in await self?.processUserWantsToMarkAsReadMessageWithinTheNotificationExtensionNotification(contactPermanentID: contactPermanentID, messageIdentifierFromEngine: messageIdentifierFromEngine, completionHandler: completionHandler) }
            },
            ObvMessengerInternalNotification.observeUserWantsToWipeFyleMessageJoinWithStatus { [weak self] (ownedCryptoId, objectIDs) in
                self?.processUserWantsToWipeFyleMessageJoinWithStatus(ownedCryptoId: ownedCryptoId, objectIDs: objectIDs)
            },
            ObvMessengerInternalNotification.observeUserWantsToForwardMessage { [weak self] messagePermanentID, discussionPermanentIDs in
                self?.processUserWantsToForwardMessage(messagePermanentID: messagePermanentID, discussionPermanentIDs: discussionPermanentIDs)
            },
            ObvMessengerInternalNotification.observeUserHasOpenedAReceivedAttachment { [weak self] receivedFyleJoinID in
                self?.processUserHasOpenedAReceivedAttachment(receivedFyleJoinID: receivedFyleJoinID)
            },
            NewSingleDiscussionNotification.observeUserWantsToDownloadReceivedFyleMessageJoinWithStatus { [weak self] joinObjectID in
                self?.processUserWantsToDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: joinObjectID)
            },
            NewSingleDiscussionNotification.observeUserWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice { [weak self] sentJoinObjectID in
                self?.processUserWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(sentJoinObjectID: sentJoinObjectID)
            },
            NewSingleDiscussionNotification.observeUserWantsToPauseDownloadReceivedFyleMessageJoinWithStatus { [weak self] joinObjectID in
                self?.processUserWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: joinObjectID)
            },
            NewSingleDiscussionNotification.observeUserWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice { [weak self] sentJoinObjectID in
                self?.processUserWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(sentJoinObjectID: sentJoinObjectID)
            },
            ObvMessengerInternalNotification.observeUserWantsToReorderDiscussions { [weak self] (discussionObjectIds, ownedIdentity, completionHandler) in
                self?.processUserWantsToReorderDiscussions(discussionObjectIds: discussionObjectIds, ownedIdentity: ownedIdentity, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeBetaUserWantsToDebugCoordinatorsQueue { [weak self] in
                self?.processBetaUserWantsToDebugCoordinatorsQueue()
            },
            ObvMessengerInternalNotification.observeUserWantsToArchiveDiscussion { [weak self] discussionPermanentID, completionHandler in
                self?.processUserWantsToArchiveDiscussion(discussionPermanentID: discussionPermanentID, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToUnarchiveDiscussion { [weak self] discussionPermanentID, updateTimestampOfLastMessage, completionHandler in
                self?.processUserWantsToUnarchiveDiscussion(discussionPermanentID: discussionPermanentID, updateTimestampOfLastMessage: updateTimestampOfLastMessage, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateReaction { [weak self] ownedCryptoId, messageObjectID, newEmoji in
                self?.processUserWantsToUpdateReaction(ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)
            },
            ObvMessengerInternalNotification.observeNewObvEncryptedPushNotificationWasReceivedViaPushKitNotification { [weak self] encryptedPushNotification in
                Task { [weak self] in await self?.processNewObvEncryptedPushNotificationWasReceivedViaPushKitNotification(encryptedPushNotification: encryptedPushNotification) }
            },
        ])
        
        // Internal notifications

        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeMessagesAreNotNewAnymore() { [weak self] (ownedCryptoId, discussionId, messageIds) in
                Task { [weak self] in await self?.processMessagesAreNotNewAnymore(ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageIds: messageIds) }
            },
            ObvMessengerInternalNotification.observeNewCallLogItem() { [weak self] objectID in
                self?.processNewCallLogItemNotification(objectID: objectID)
            },
            ObvMessengerInternalNotification.observeWipeAllMessagesThatExpiredEarlierThanNow { [weak self] (launchedByBackgroundTask, completionHandler) in
                self?.processWipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: launchedByBackgroundTask, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeCurrentUserActivityDidChange() { [weak self] (previousUserActivity, currentUserActivity) in
                if let previousDiscussionPermanentID = previousUserActivity.discussionPermanentID, previousDiscussionPermanentID != currentUserActivity.discussionPermanentID {
                    self?.userLeftDiscussion(discussionPermanentID: previousDiscussionPermanentID)
                }
                if let currentDiscussionPermanentID = currentUserActivity.discussionPermanentID, currentDiscussionPermanentID != previousUserActivity.discussionPermanentID {
                    Task { [weak self] in await self?.userEnteredDiscussion(discussionPermanentID: currentDiscussionPermanentID) }
                }
            },
            ObvMessengerInternalNotification.observeADiscussionSharedConfigurationIsNeededByContact { [weak self] contactIdentifier, discussionId in
                self?.processADiscussionSharedConfigurationIsNeededByContact(contactIdentifier: contactIdentifier, discussionId: discussionId)
            },
            ObvMessengerInternalNotification.observeADiscussionSharedConfigurationIsNeededByAnotherOwnedDevice { [weak self] ownedCryptoId, discussionId in
                self?.processADiscussionSharedConfigurationIsNeededByAnotherOwnedDevice(ownedCryptoId: ownedCryptoId, discussionId: discussionId)
            },
            ObvMessengerInternalNotification.observeApplyAllRetentionPoliciesNow { [weak self] (launchedByBackgroundTask, completionHandler) in
                self?.processApplyAllRetentionPoliciesNowNotification(launchedByBackgroundTask: launchedByBackgroundTask, completionHandler: completionHandler)
            },
            NewSingleDiscussionNotification.observeInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty { [weak self] (discussionObjectID, markAsRead) in
                self?.processInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: discussionObjectID, markAsRead: markAsRead)
            },
            ObvMessengerInternalNotification.observeInsertDebugMessagesInAllExistingDiscussions { [weak self] in
                self?.processInsertDebugMessagesInAllExistingDiscussions()
            },
            ObvMessengerInternalNotification.observeCleanExpiredMuteNotficationsThatExpiredEarlierThanNow { [weak self] in
                self?.cleanExpiredMuteNotificationsSetting()
            },
            ObvMessengerInternalNotification.observeTooManyWrongPasscodeAttemptsCausedLockOut { [weak self] in
                self?.processTooManyWrongPasscodeAttemptsCausedLockOut()
            },
            ObvMessengerInternalNotification.observeUpdateNormalizedSearchKeyOnPersistedDiscussions { [weak self] ownedIdentity, completionHandler in
                self?.processUpdateNormalizedSearchKeyOnPersistedDiscussions(ownedIdentity: ownedIdentity, completionHandler: completionHandler)
            },
        ])
        
        // Internal VoIP notifications
        
        observationTokens.append(contentsOf: [
            VoIPNotification.observeReportCallEvent { [weak self] (callUUID, callReport, groupIdentifier, ownedCryptoId) in
                self?.processReportCallEvent(callUUID: callUUID, callReport: callReport, groupIdentifier: groupIdentifier, ownedCryptoId: ownedCryptoId)
            },
            VoIPNotification.observeCallWasEnded { [weak self] uuidForCallKit in
                self?.processCallWasEnded(uuidForCallKit: uuidForCallKit)
            },
            VoIPNotification.observeNewWebRTCMessageToSend() { [weak self] (webrtcMessage, contactID, forStartingCall) in
                self?.processNewWebRTCMessageToSendNotification(webrtcMessage: webrtcMessage, contactID: contactID, forStartingCall: forStartingCall)
            },
            VoIPNotification.observeNewOwnedWebRTCMessageToSend() { [weak self] (ownedCryptoId, webrtcMessage) in
                self?.processNewOwnedWebRTCMessageToSend(ownedCryptoId: ownedCryptoId, webrtcMessage: webrtcMessage)
            },
        ])
        
        // Draft specific notifications
        
        observationTokens.append(contentsOf: [
            NewSingleDiscussionNotification.observeUserWantsToReplyToMessage { [weak self] messageObjectID, draftObjectID in
                self?.processUserWantsToReplyToMessage(messageObjectID: messageObjectID, draftObjectID: draftObjectID)
            },
            NewSingleDiscussionNotification.observeUserWantsToRemoveReplyToMessage { [weak self] draftObjectID in
                self?.processUserWantsToRemoveReplyToMessage(draftObjectID: draftObjectID)
            },
            NewSingleDiscussionNotification.observeUserWantsToAddAttachmentsToDraft { [weak self] draftPermanentID, itemProviders, completionHandler in
                self?.processUserWantsToAddAttachmentsToDraft(draftPermanentID: draftPermanentID, itemProviders: itemProviders, completionHandler: completionHandler)
            },
            NewSingleDiscussionNotification.observeUserWantsToAddAttachmentsToDraftFromURLs { [weak self] draftPermanentID, urls, completionHandler in
                self?.processUserWantsToAddAttachmentsToDraft(draftPermanentID: draftPermanentID, urls: urls, completionHandler: completionHandler)
            },
            NewSingleDiscussionNotification.observeUserWantsToDeleteAllAttachmentsToDraft { [weak self] draftObjectID in
                self?.processUserWantsToDeleteAllAttachmentsToDraft(draftObjectID: draftObjectID)
            },
            NewSingleDiscussionNotification.observeUserWantsToDeletePreviewAttachmentsToDraft { [weak self] draftObjectID in
                self?.processUserWantsToDeleteAllAttachmentsToDraft(draftObjectID: draftObjectID, draftTypeToDelete: .preview)
            },
            NewSingleDiscussionNotification.observeUserWantsToDeleteNotPreviewAttachmentsToDraft { [weak self] draftObjectID in
                self?.processUserWantsToDeleteAllAttachmentsToDraft(draftObjectID: draftObjectID, draftTypeToDelete: .notPreview)
            },
            NewSingleDiscussionNotification.observeUserWantsToSendDraft { [weak self] draftPermanentID, textBody, mentions in
                self?.processUserWantsToSendDraft(draftPermanentID: draftPermanentID, textBody: textBody, mentions: mentions)
            },
            NewSingleDiscussionNotification.observeUserWantsToSendDraftWithOneAttachment { [weak self] draftPermanentID, attachmentURL in
                self?.processUserWantsToSendDraftWithAttachments(draftPermanentID: draftPermanentID, attachmentsURL: [attachmentURL])
            },
            NewSingleDiscussionNotification.observeUserWantsToUpdateDraftExpiration { [weak self] draftObjectID, value in
                self?.processUserWantsToUpdateDraftExpiration(draftObjectID: draftObjectID, value: value)
            },
            NewSingleDiscussionNotification.observeUserWantsToUpdateDraftBodyAndMentions { [weak self] draftObjectID, draftBody, mentions in
                self?.processUserWantsToUpdateDraftBodyAndMentions(draftObjectID: draftObjectID, draftBody: draftBody, mentions: mentions)
            },
        ])
        
        // ObvEngineNotificationNew Notifications
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeNewMessageReceived(within: NotificationCenter.default) { [weak self] obvMessage in
                Task { [weak self] in await self?.processNewMessageReceivedNotification(obvMessage: obvMessage) }
            },
            ObvEngineNotificationNew.observeNewOwnedMessageReceived(within: NotificationCenter.default) { [weak self] obvOwnedMessage in
                Task { [weak self] in await self?.processNewOwnedMessageReceivedNotification(obvOwnedMessage: obvOwnedMessage) }
            },
            ObvEngineNotificationNew.observeMessageWasAcknowledged(within: NotificationCenter.default) { [weak self] (ownedIdentity, messageIdentifierFromEngine, timestampFromServer, isAppMessageWithUserContent, isVoipMessage) in
                self?.processMessageWasAcknowledgedNotification(ownedIdentity: ownedIdentity, messageIdentifierFromEngine: messageIdentifierFromEngine, timestampFromServer: timestampFromServer, isAppMessageWithUserContent: isAppMessageWithUserContent, isVoipMessage: isVoipMessage)
            },
            ObvEngineNotificationNew.observeAttachmentWasAcknowledgedByServer(within: NotificationCenter.default) { [weak self] (ownedCryptoId, messageIdentifierFromEngine, attachmentNumber) in
                self?.processAttachmentWasAcknowledgedByServerNotification(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
            },
            ObvEngineNotificationNew.observeAttachmentDownloadCancelledByServer(within: NotificationCenter.default) { [weak self] (obvAttachment) in
                Task { [weak self] in await self?.processAttachmentDownloadCancelledByServerNotification(obvAttachment: obvAttachment) }
            },
            ObvEngineNotificationNew.observeOwnedAttachmentDownloadCancelledByServer(within: NotificationCenter.default) { [weak self] obvOwnedAttachment in
                Task { [weak self] in await self?.processOwnedAttachmentDownloadCancelledByServerNotification(obvOwnedAttachment: obvOwnedAttachment) }
            },
            ObvEngineNotificationNew.observeCannotReturnAnyProgressForMessageAttachments(within: NotificationCenter.default) { [weak self] ownedCryptoId, messageIdentifierFromEngine in
                self?.processCannotReturnAnyProgressForMessageAttachmentsNotification(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine)
            },
            ObvEngineNotificationNew.observeAttachmentDownloaded(within: NotificationCenter.default) { [weak self] (obvAttachment) in
                Task { [weak self] in await self?.processAttachmentDownloadedNotification(obvAttachment: obvAttachment) }
                
            },
            ObvEngineNotificationNew.observeOwnedAttachmentDownloaded(within: NotificationCenter.default) { [weak self] (obvOwnedAttachment) in
                Task { [weak self] in await self?.processOwnedAttachmentDownloadedNotification(obvOwnedAttachment: obvOwnedAttachment) }
            },
            ObvEngineNotificationNew.observeAttachmentDownloadWasResumed(within: NotificationCenter.default) { [weak self] ownCryptoId, messageIdentifierFromEngine, attachmentNumber in
                self?.processAttachmentDownloadWasResumed(ownedCryptoId: ownCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
            },
            ObvEngineNotificationNew.observeOwnedAttachmentDownloadWasResumed(within: NotificationCenter.default) { [weak self] ownCryptoId, messageIdentifierFromEngine, attachmentNumber in
                self?.processOwnedAttachmentDownloadWasResumed(ownedCryptoId: ownCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
            },
            ObvEngineNotificationNew.observeAttachmentDownloadWasPaused(within: NotificationCenter.default) { [weak self] ownCryptoId, messageIdentifierFromEngine, attachmentNumber in
                self?.processAttachmentDownloadWasPaused(ownedCryptoId: ownCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
            },
            ObvEngineNotificationNew.observeOwnedAttachmentDownloadWasPaused(within: NotificationCenter.default) { [weak self] ownCryptoId, messageIdentifierFromEngine, attachmentNumber in
                self?.processOwnedAttachmentDownloadWasPaused(ownedCryptoId: ownCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
            },
            ObvEngineNotificationNew.observeNewObvReturnReceiptToProcess(within: NotificationCenter.default) { [weak self] (obvReturnReceipt) in
                self?.processNewObvReturnReceiptToProcessNotification(obvReturnReceipt: obvReturnReceipt)
            },
            ObvEngineNotificationNew.observeOutboxMessagesAndAllTheirAttachmentsWereAcknowledged(within: NotificationCenter.default) { [weak self] messageIdsAndTimestampsFromServer in
                self?.processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(messageIdsAndTimestampsFromServer: messageIdsAndTimestampsFromServer)
            },
            ObvEngineNotificationNew.observeOutboxMessageCouldNotBeSentToServer(within: NotificationCenter.default) { [weak self] (messageIdentifierFromEngine, ownedCryptoId) in
                self?.processOutboxMessageCouldNotBeSentToServer(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId)
            },
            ObvEngineNotificationNew.observeContactWasDeleted(within: NotificationCenter.default) { [weak self] (ownedCryptoId, contactCryptoId) in
                self?.processContactWasDeletedNotification(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvEngineNotificationNew.observeContactMessageExtendedPayloadAvailable(within: NotificationCenter.default) { [weak self] obvMessage in
                self?.processContactMessageExtendedPayloadAvailable(obvMessage: obvMessage)
            },
            ObvEngineNotificationNew.observeOwnedMessageExtendedPayloadAvailable(within: NotificationCenter.default) { [weak self] obvOwnedMessage in
                self?.processOwnedMessageExtendedPayloadAvailable(obvOwnedMessage: obvOwnedMessage)
            },
            ObvEngineNotificationNew.observeContactWasRevokedAsCompromisedWithinEngine(within: NotificationCenter.default) { [weak self] obvContactIdentifier in
                self?.processContactWasRevokedAsCompromisedWithinEngine(obvContactIdentifier: obvContactIdentifier)
            },
            ObvEngineNotificationNew.observeNewUserDialogToPresent(within: NotificationCenter.default) { [weak self] obvDialog in
                self?.processNewUserDialogToPresent(obvDialog: obvDialog)
            },
            ObvEngineNotificationNew.observeAPersistedDialogWasDeleted(within: NotificationCenter.default) { [weak self] ownedCryptoId, uuid in
                self?.processAPersistedDialogWasDeleted(uuid: uuid, ownedCryptoId: ownedCryptoId)
            },
            ObvEngineNotificationNew.observeContactIntroductionInvitationSent(within: NotificationCenter.default) { [weak self] ownedIdentity, contactIdentityA, contactIdentityB in
                self?.processContactIntroductionInvitationSent(ownedIdentity: ownedIdentity, contactIdentityA: contactIdentityA, contactIdentityB: contactIdentityB)
            },
        ])

        // Bootstrapping
        
        observeAppStateChangedNotifications()

        // Share extension
        observeNewSentMessagesAddedByExtension()
        observeExtensionFailedToWipeAllEphemeralMessagesBeforeDate()
    }
 
}


// MARK: - Bootstrapping

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func observeAppStateChangedNotifications() {
        observationTokens.append(contentsOf: [
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
                // We do not specify a queue for the observer as this would run the code synchronously on the given queue, blocking the main thread.
                // Instead, we "manually" dispatch work asynchronously.
                self?.queueForDispatchingOffTheMainThread.async {
                    assert(!Thread.isMainThread)
                    let backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "PersistedDiscussionsUpdatesCoordinator background task")
                    self?.cleanJsonMessagesSavedByNotificationExtension()
                    self?.bootstrapMessagesToBeWiped(preserveReceivedMessages: false)
                    UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
                }
            },
        ])
    }

    
    private func observeNewSentMessagesAddedByExtension() {
        guard let userDefaults = self.userDefaults else {
            os_log("The user defaults database is not set", log: Self.log, type: .fault)
            return
        }
        kvoTokens.append(userDefaults.observe(\.objectsModifiedByShareExtension) { [weak self] (userDefaults, _) in
            self?.queueForDispatchingOffTheMainThread.async {
                let objectsModifiedByShareExtensionURLAndEntityName = userDefaults.objectsModifiedByShareExtensionURLAndEntityName
                guard !objectsModifiedByShareExtensionURLAndEntityName.isEmpty else { return }
                userDefaults.resetObjectsModifiedByShareExtension()
                objectsModifiedByShareExtensionURLAndEntityName.forEach { (objectURI, entityName) in
                    ObvStack.shared.viewContext.deepRefresh(objectURI: objectURI, entityName: entityName)
                }
            }
        })
    }
    
    
    private func observeExtensionFailedToWipeAllEphemeralMessagesBeforeDate() {
        guard let userDefaults = self.userDefaults else {
            os_log("The user defaults database is not set", log: Self.log, type: .fault)
            return
        }
        let token = userDefaults.observe(\.extensionFailedToWipeAllEphemeralMessagesBeforeDate) { [weak self] (userDefaults, change) in
            self?.wipeReadOnceAndLimitedVisibilityMessagesThatTheShareExtensionDidNotHaveTimeToWipe()
        }
        kvoTokens.append(token)
    }
    
    
    private func deleteOldOrOrphanedDatabaseEntries() {
        let operations = ObvUICoreDataHelper.getOperationsForDeletingOldOrOrphanedDatabaseEntries()
        for op1 in operations {
            op1.queuePriority = .low
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            self.coordinatorsQueue.addOperation(composedOp)
        }
    }


    private func cleanJsonMessagesSavedByNotificationExtension() {
        assert(!Thread.isMainThread)
        let op = DeleteAllJsonMessagesSavedByNotificationExtension()
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        coordinatorsQueue.addOperation(op)
    }
    
    
    /// When the notification extension successfully decrypts a notification, it recovers an ObvMessage. This message is
    /// then serialized as a json and saved in an appropriate directory before showing the actual user notifications.
    /// Within this method, we loop through all these json files in order to immediately populate the local database of messages.
    /// Once we are done, we delete all the json files that we have processed.
    /// Note that if a message with the same uid from server already exists, we do *not* modify it using the content of the json.
    private func bootstrapMessagesDecryptedWithinNotificationExtension() async {
        
        assert(OperationQueue.current != coordinatorsQueue)
        
        guard let urls = try? FileManager.default.contentsOfDirectory(at: ObvUICoreDataConstants.ContainerURL.forMessagesDecryptedWithinNotificationExtension.url, includingPropertiesForKeys: nil) else {
            os_log("📮 We could not list the serialized json files saved by the notification extension", log: Self.log, type: .error)
            return
        }

        os_log("📮 Find %{public}@ message%{public}@ saved by the notification extension.", log: Self.log, type: .info, String(urls.count), urls.count == 1 ? "" : "s")

        let obvMessages: [ObvMessage] = urls.compactMap { url in
            guard let serializedObvMessage = try? Data(contentsOf: url) else {
                os_log("📮 Could not read the content of %{public}@. This file will be deleted.", log: Self.log, type: .error)
                return nil
            }
            guard let obvMessage = try? ObvMessage.decodeFromJson(data: serializedObvMessage) else {
                os_log("📮 Could not decode the content of %{public}@. This file will be deleted.", log: Self.log, type: .error)
                return nil
            }
            return obvMessage
        }
        
        for url in urls {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                os_log("📮 Failed to delete a notification content: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }

        for obvMessage in obvMessages {
            _ = await processReceivedObvMessage(obvMessage, overridePreviousPersistedMessage: false)
        }
        
    }


    private func wipeReadOnceAndLimitedVisibilityMessagesThatTheShareExtensionDidNotHaveTimeToWipe() {
        guard let userDefaults = userDefaults else { return }
        let op1 = WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation(userDefaults: userDefaults,
                                                                                   appType: .mainApp,
                                                                                   wipeType: .finishIfRequiredWipeStartedByAnExtension)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    

    private func bootstrapMessagesToBeWiped(preserveReceivedMessages: Bool) {
        do {
            let op1 = WipeOrDeleteReadOnceMessagesOperation(preserveReceivedMessages: preserveReceivedMessages, restrictToDiscussionWithPermanentID: nil)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            self.coordinatorsQueue.addOperation(composedOp)
        }
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            self.coordinatorsQueue.addOperation(composedOp)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            self.coordinatorsQueue.addOperation(composedOp)
        }
        self.coordinatorsQueue.addOperation {
            ObvMessengerInternalNotification.trashShouldBeEmptied
                .postOnDispatchQueue()
        }
    }

    
    private func bootstrapWipeAllMessagesThatExpiredEarlierThanNow() {
        let op1 = WipeExpiredMessagesOperation(launchedByBackgroundTask: false)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func cleanExpiredMuteNotificationsSetting() {
        let op1 = CleanExpiredMuteNotficationEndDatesOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

        
    private func cleanOrphanedPersistedMessageTimestampedMetadata() {
        let op1 = CleanOrphanedPersistedMessageTimestampedMetadataOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func synchronizeAllOneToOneDiscussionTitlesWithContactNameOperation() {
        let op1 = SynchronizeOneToOneDiscussionTitlesWithContactNameOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    

    private func synchronizeDiscussionsIllustrativeMessageAndRefreshNumberOfNewMessages() {
        do {
            let op1 = SynchronizeDiscussionsIllustrativeMessageOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            self.coordinatorsQueue.addOperation(composedOp)
        }
        do {
            let op1 = RefreshNumberOfNewMessagesForAllDiscussionsOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            self.coordinatorsQueue.addOperation(composedOp)
        }
    }
    
    
    private func deleteEmptyLockedDiscussion() {
        assert(OperationQueue.current != coordinatorsQueue)
        let op1 = DeleteAllEmptyLockedDiscussionsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    /// This method aynchronously lists all the files of the Fyles directory and compare this list to the list of entries of the `Fyles` database.
    /// Each file that cannot be found is a candidate for being trashed. We do not trash the file right away though, since we are doing this work
    /// asynchronously : some other operation may have created a `Fyle` while we were doing the comparison. Instead, we pass
    /// the list of candidates to an appropriate operations that will perform checks and trash the files if appropriate, in a synchronous way.
    private func trashOrphanedFilesFoundInTheFylesDirectory() {

        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            
            let namesOfFilesOnDisk: Set<String>
            do {
                let allFilesInFyle = try Set(FileManager.default.contentsOfDirectory(at: ObvUICoreDataConstants.ContainerURL.forFyles.url, includingPropertiesForKeys: nil))
                namesOfFilesOnDisk = Set(allFilesInFyle.map({ $0.lastPathComponent }))
            } catch {
                os_log("Could not list the files of the Fyles directory: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
                                    
            let namesOfFilesToKeep: Set<String>
            do {
                namesOfFilesToKeep = Set(try Fyle.getAllFilenames(within: context))
            } catch {
                os_log("Could not get all Fyle's filenames: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }

            let namesOfFilesCandidatesForTrash = namesOfFilesOnDisk.subtracting(namesOfFilesToKeep)
            let urlsOfFilesCandidatesForTrash = Set(namesOfFilesCandidatesForTrash.map({ Fyle.getFileURL(lastPathComponent: $0) }))
            
            guard !urlsOfFilesCandidatesForTrash.isEmpty else {
                return
            }

            let op = TrashFilesThatHaveNoAssociatedFyleOperation(urlsCandidatesForTrash: urlsOfFilesCandidatesForTrash)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            self?.coordinatorsQueue.addOperation(op)
            self?.coordinatorsQueue.addOperation({
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            })

        }
        
    }

}
        
        
        
// MARK: - Observing Internal notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func deleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact() {
        let op = DeletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToDeletedContactIdentityOperation()
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        self.coordinatorsQueue.addOperation(op)
    }
}


// MARK: - Processing Internal notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    /// When receiving a `NewDraftToSend` notification, we turn the draft into a `PersistedMessageSent`, reset the draft, and save the context.
    /// If this succeeds, we send the new (unprocessed)  `PersistedMessageSent`.
    private func processNewDraftToSendNotification(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>) async {
        assert(OperationQueue.current != coordinatorsQueue)
        assert(!Thread.isMainThread)
        let op1 = CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation(draftPermanentID: draftPermanentID)
        let op2 = ComputeExtendedPayloadOperation(provider: op1)
        let op3 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1,
                                                               alsoPostToOtherOwnedDevices: true,
                                                               extendedPayloadProvider: op2,
                                                               obvEngine: obvEngine)
        let op4 = MarkAllMessagesAsNotNewWithinDiscussionOperation(input: .draftPermanentID(draftPermanentID: draftPermanentID))
        let composedOp1 = createCompositionOfFourContextualOperation(op1: op1, op2: op2, op3: op3, op4: op4)
        await coordinatorsQueue.addAndAwaitOperation(composedOp1)
        
        guard composedOp1.isFinished && !composedOp1.isCancelled else {
            assertionFailure()
            NewSingleDiscussionNotification.draftCouldNotBeSent(draftPermanentID: draftPermanentID)
                .postOnDispatchQueue()
            return
        }
        
        // Notify other owned devices about messages that turned not new

        if op4.ownedIdentityHasAnotherDeviceWithChannel {
            let postOp = PostDiscussionReadJSONEngineOperation(op: op4, obvEngine: obvEngine)
            postOp.addDependency(composedOp1)
            queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
        }
        
    }
    
    
    private func processInsertDebugMessagesInAllExistingDiscussions() {
#if DEBUG
//        assert(OperationQueue.current != coordinatorsQueue)
//        var objectIDs = [(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>)]()
//        ObvStack.shared.performBackgroundTask { [weak self] context in
//            guard let _self = self else { return }
//            guard let discussions = try? PersistedDiscussion.getAllSortedByTimestampOfLastMessageForAllOwnedIdentities(within: context) else { assertionFailure(); return }
//            objectIDs = discussions.map({ ($0.typedObjectID, $0.draft.objectPermanentID) })
//            let numberOfMessagesToInsert = 100
//            for objectID in objectIDs {
//                for messageNumber in 0..<numberOfMessagesToInsert {
//                    debugPrint("Message \(messageNumber) out of \(numberOfMessagesToInsert)")
//                    if Bool.random() {
//                        let op1 = CreateRandomDraftDebugOperation(discussionObjectID: objectID.discussionObjectID)
//                        let op2 = CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation(draftPermanentID: objectID.draftPermanentID)
//                        let op3 = MarkSentMessageAsDeliveredDebugOperation()
//                        op3.addDependency(op2)
//                        let composedOp = _self.createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
//                        self?.coordinatorsQueue.addOperation(composedOp)
//                        self?.coordinatorsQueue.addOperation({ guard !composedOp.isCancelled else { assertionFailure(); return } })
//                    } else {
//                        let op1 = CreateRandomMessageReceivedDebugOperation(discussionObjectID: objectID.discussionObjectID)
//                        let composedOp = _self.createCompositionOfOneContextualOperation(op1: op1)
//                        self?.coordinatorsQueue.addOperation(composedOp)
//                        self?.coordinatorsQueue.addOperation({ guard !composedOp.isCancelled else { assertionFailure(); return } })
//                    }
//                }
//            }
//        }
#endif
    }
    
    /// When receiving a NewPersistedObvContactDevice, we check whether there exists "related" unsent message. If this is the case, we can now post them.
    private func processUnprocessedRecipientInfosThatCanNowBeProcessed() {
        let obvEngine = self.obvEngine
        let op1 = FindSentMessagesWithPersistedMessageSentRecipientInfosCanNowBeSentByEngineOperation()
        let op2 = BlockOperation()
        op2.completionBlock = { [weak self] in
            guard let _self = self else { return }
            guard !op1.isCancelled else {
                assertionFailure()
                return
            }
            assert(op1.isFinished)
            for messageSentPermanentID in op1.messageSentPermanentIDs {
                let op1 = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: messageSentPermanentID,
                                                                       alsoPostToOtherOwnedDevices: false,
                                                                       extendedPayloadProvider: nil,
                                                                       obvEngine: obvEngine)
                let composedOp = _self.createCompositionOfOneContextualOperation(op1: op1)
                composedOp.queuePriority = .low
                self?.coordinatorsQueue.addOperation(composedOp)
            }
        }
        op2.addDependency(op1)
        op1.queuePriority = .low
        op2.queuePriority = .low
        coordinatorsQueue.addOperation(op1)
        coordinatorsQueue.addOperation(op2)
    }
    

    /// When a new discussion is inserted in databse (or when a locked/pre discussion becomes active again), we send our shared configuration (that was applied using the default settings for new discussions) to all contacts and owned devices.
    private func processPersistedDiscussionWasInsertedOrReactivated(ownedCryptoId: ObvCryptoId, discussionIdentifier: DiscussionIdentifier) {
        let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(ownedCryptoId: ownedCryptoId, discussionId: discussionIdentifier, sendTo: .allContactsAndOtherOwnedDevices, obvEngine: obvEngine)
        op.queuePriority = .low
        op.completionBlock = { if op.isCancelled { assertionFailure() } }
        coordinatorsQueue.addOperation(op)
    }

    
    /// When receiving a NewPersistedObvContactDevice notification of a contact, we look for all group v2 discussions where this contact is a member and that we administrate.
    /// For each discussion found, we send the shared configuration.
    /// We also send the shared configuration of the one-to-one discussion we have with this contact.
    /// This method is also used when a contact that was a pending group v2 member accepts the invitation.
    private func sendAppropriateDiscussionSharedConfigurationsToContact(input: FindAdministratedGroupV2DiscussionsAndOneToOneDiscussionWithContactOperation.Input, sendSharedConfigOfOneToOneDiscussion: Bool) {
        let obvEngine = self.obvEngine
        let op1 = FindAdministratedGroupV2DiscussionsAndOneToOneDiscussionWithContactOperation(input: input, includeOneToOneDiscussionInResult: sendSharedConfigOfOneToOneDiscussion)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        let op2 = BlockOperation()
        op2.completionBlock = { [weak self] in
            guard !composedOp.isCancelled else {
                assertionFailure()
                return
            }
            assert(op1.isFinished)
            if !op1.isCancelled {
                guard let ownedCryptoId = op1.ownedCryptoId,
                      let contactCryptoId = op1.contactCryptoId else { assertionFailure(); return }
                for discussionId in op1.persistedDiscussionIdentifiers {
                    let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(ownedCryptoId: ownedCryptoId, discussionId: discussionId, sendTo: .specificContact(contactCryptoId: contactCryptoId), obvEngine: obvEngine)
                    op.queuePriority = .low
                    op.completionBlock = { if op.isCancelled { assertionFailure() } }
                    self?.coordinatorsQueue.addOperation(op)
                }
            }
        }
        op2.addDependency(composedOp)
        composedOp.queuePriority = .low
        op2.queuePriority = .low
        coordinatorsQueue.addOperation(composedOp)
        coordinatorsQueue.addOperation(op2)
    }
    
    
    /// When receiving a `PersistedContactGroupHasUpdatedContactIdentities` notification from the App, we check whether there exists unprocessed (unsent) messages within the corresponding group discussion.
    /// If this is the case, we can now post them.
    /// We also insert the the system messages of category `.contactJoinedGroup` and `.contactLeftGroup` as appropriate.
    private func processPersistedContactGroupHasUpdatedContactIdentitiesNotification(persistedContactGroupObjectID: NSManagedObjectID, insertedContacts: Set<PersistedObvContactIdentity>, removedContacts: Set<PersistedObvContactIdentity>) {
                
        let obvEngine = self.obvEngine
        
        ObvStack.shared.performBackgroundTask { [weak self] context in
        
            guard let _self = self else { return }
            
            // Task 1: Recover the persistedDiscussionObjectID and send unprocessed messages within this group

            guard let contactGroup = try? context.existingObject(with: persistedContactGroupObjectID) as? PersistedContactGroup else { return }
            guard let ownedCryptoId = contactGroup.ownedIdentity?.cryptoId else { assertionFailure(); return }
            let contactGroupIsOwned = contactGroup.category == .owned
            let groupDiscussion = contactGroup.discussion
            guard let discussionId = try? groupDiscussion.identifier else { assertionFailure(); return }
            let discussionObjectID = groupDiscussion.objectID
            let contactGroupHasAtLeastOneRemoteContactDevice = contactGroup.hasAtLeastOneRemoteContactDevice()

            var operationsToQueue = [Operation]()
            
            if contactGroupHasAtLeastOneRemoteContactDevice {
                let sentMessages = groupDiscussion.messages.compactMap { $0 as? PersistedMessageSent }
                let objectIDOfUnprocessedMessages = sentMessages.filter({ $0.status == .unprocessed || $0.status == .processing }).map({ $0.objectPermanentID })
                let ops: [(ComputeExtendedPayloadOperation, SendUnprocessedPersistedMessageSentOperation)] = objectIDOfUnprocessedMessages.map({
                    let op1 = ComputeExtendedPayloadOperation(messageSentPermanentID: $0)
                    let op2 = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: $0, alsoPostToOtherOwnedDevices: false, extendedPayloadProvider: op1, obvEngine: obvEngine)
                        return (op1, op2)
                    })
                let composedOps = ops.map { _self.createCompositionOfTwoContextualOperation(op1: $0.0, op2: $0.1) }
                operationsToQueue.append(contentsOf: composedOps)
            }
            
            // Task 2: Insert a system message of category "contactJoinedGroup"
            
            do {
                let ops: [CompositionOfOneContextualOperation] = insertedContacts.map {
                    let op1 = InsertPersistedMessageSystemIntoDiscussionOperation(
                        persistedMessageSystemCategory: .contactJoinedGroup,
                        persistedDiscussionObjectID: discussionObjectID,
                        optionalContactIdentityObjectID: $0.objectID,
                        optionalCallLogItemObjectID: nil)
                    let composedOp = _self.createCompositionOfOneContextualOperation(op1: op1)
                    return composedOp
                }
                operationsToQueue.append(contentsOf: ops)
            }

            // Task 3: Insert a system message of category "contactLeftGroup"
            
            do {
                let ops: [CompositionOfOneContextualOperation] = removedContacts.map {
                    let op1 = InsertPersistedMessageSystemIntoDiscussionOperation(
                        persistedMessageSystemCategory: .contactLeftGroup,
                        persistedDiscussionObjectID: discussionObjectID,
                        optionalContactIdentityObjectID: $0.objectID,
                        optionalCallLogItemObjectID: nil)
                    let composedOp = _self.createCompositionOfOneContextualOperation(op1: op1)
                    return composedOp
                }
                operationsToQueue.append(contentsOf: ops)
            }

            // Task 4: In case the group is owned, send the shared configuration of the group discussion to all group members
            
            if contactGroupIsOwned && contactGroupHasAtLeastOneRemoteContactDevice {
                let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(ownedCryptoId: ownedCryptoId, discussionId: discussionId, sendTo: .allContactsAndOtherOwnedDevices, obvEngine: obvEngine)
                op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
                operationsToQueue.append(op)
            }

            // Actually queue the operations
            
            guard !operationsToQueue.isEmpty else { return }
            operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
            self?.coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
            
        }
        
    }
    
    
    /// When notified that a `PersistedMessageReceived` has been deleted, we cancel any potential download within the engine
    private func processPersistedMessageReceivedWasDeletedNotification(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId) async {
        do {
            try await obvEngine.cancelDownloadOfMessage(ownedCryptoId: ownedCryptoId, messageIdentifier: messageIdentifierFromEngine)
        } catch {
            os_log("Could not cancel the download of a message that we just deleted from the app", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
    }
    

    /// Called when the user requests the local or global deletion of a message.
    private func processUserRequestedDeletionOfPersistedMessageNotification(ownedCryptoId: ObvCryptoId, persistedMessageObjectID: NSManagedObjectID, deletionType: DeletionType) async {
        
        var operationsToQueue = [OperationKind]()
        
        switch deletionType {
        case .local:
            break // We will do the work below
        case .global:
            let op = SendGlobalDeleteMessagesJSONOperation(persistedMessageObjectIDs: [persistedMessageObjectID], obvEngine: obvEngine)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(.engineCall(op: op))
        }
        
        do {
            let op1 = DetermineEngineIdentifiersOfMessagesToCancelOperation(input: .messages(persistedMessageObjectIDs: [persistedMessageObjectID]), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(.contextual(op: composedOp))
            let op2 = CancelUploadOrDownloadOfPersistedMessagesOperation(op: op1, obvEngine: obvEngine)
            operationsToQueue.append(.engineCall(op: op2))
        }
        
        do {
            let op1 = DeletePersistedMessagesOperation(persistedMessageObjectIDs: Set([persistedMessageObjectID]), ownedCryptoId: ownedCryptoId, deletionType: deletionType)
            let op2 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let op3 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
            operationsToQueue.append(.contextual(op: composedOp))
        }
        
        do {
            let op = BlockOperation()
            op.completionBlock = {
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            }
            operationsToQueue.append(.engineCall(op: op))
        }

        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        
        for op in operationsToQueue {
            switch op {
            case .contextual(let op):
                coordinatorsQueue.addOperation(op)
            case .engineCall(let op):
                queueForOperationsMakingEngineCalls.addOperation(op)
            }
        }
        
    }
    
    
    private func processUserRequestedDeletionOfPersistedDiscussion(ownedCryptoId: ObvCryptoId, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, deletionType: DeletionType, completionHandler: @escaping (Bool) -> Void) {
        cleanJsonMessagesSavedByNotificationExtension()
        
        var operationsToQueue = [OperationKind]()
        
        switch deletionType {
        case .local:
            break
        case .global:
            let op = SendGlobalDeleteDiscussionJSONOperation(persistedDiscussionObjectID: discussionObjectID.objectID, obvEngine: obvEngine)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(.engineCall(op: op))
        }
        
        do {
            let op1 = DetermineEngineIdentifiersOfMessagesToCancelOperation(
                input: .discussion(persistedDiscussionObjectID: discussionObjectID.objectID),
                obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(.contextual(op: composedOp))
            let op2 = CancelUploadOrDownloadOfPersistedMessagesOperation(op: op1, obvEngine: obvEngine)
            operationsToQueue.append(.engineCall(op: op2))
        }

        do {
            let op1 = DeletePersistedDiscussionOperation(
                ownedCryptoId: ownedCryptoId,
                discussionObjectID: discussionObjectID,
                deletionType: deletionType)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(.contextual(op: composedOp))
        }
        
        do {
            let operations = getOperationsForDeletingOrphanedDatabaseItems { success in
                DispatchQueue.main.async {
                    completionHandler(success)
                }
            }
            operationsToQueue.append(contentsOf: operations.map({ .contextual(op: $0) }) )
        }
                
        guard !operationsToQueue.isEmpty else { return }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        for op in operationsToQueue {
            switch op {
            case .contextual(let op):
                coordinatorsQueue.addOperation(op)
            case .engineCall(let op):
                queueForOperationsMakingEngineCalls.addOperation(op)
            }
        }

//        ObvStack.shared.performBackgroundTask { [weak self] context in
//            guard let discussion = try? PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: context) else {
//                return
//            }
//            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId else { return }
//            self?.deletePersistedDiscussion(
//                withObjectID: persistedDiscussionObjectID,
//                requester: .ownedIdentity(ownedCryptoId: ownedCryptoId, deletionType: deletionType),
//                completionHandler: completionHandler)
//        }
        
    }
    
    
    private func getOperationsForDeletingOrphanedDatabaseItems(completionHandler: ((Bool) -> Void)? = nil) -> [Operation] {
        
        var operationsToReturn = [Operation]()

        do {
            let op1 = DeleteAllOrphanedPersistedMessagesOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToReturn.append(composedOp)
        }
        
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToReturn.append(composedOp)
        }
        
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToReturn.append(composedOp)
        }
        
        do {
            let op = BlockOperation()
            op.completionBlock = {
                let oneOperationCancelled = operationsToReturn.reduce(false) { $0 || $1.isCancelled }
                let success = !oneOperationCancelled
                completionHandler?(success)
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            }
            operationsToReturn.append(op)
        }

        operationsToReturn.makeEachOperationDependentOnThePreceedingOne()
        
        return operationsToReturn

    }
    

    private func processMessagesAreNotNewAnymore(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async {
        assert(OperationQueue.current != coordinatorsQueue)

        let op1 = ProcessPersistedMessagesAsTheyTurnsNotNewOperation(
            ownedCryptoId: ownedCryptoId,
            discussionId: discussionId,
            messageIds: messageIds)
        await queueAndAwaitCompositionOfOneContextualOperation(op1: op1)

        guard op1.isFinished && !op1.isCancelled else {
            assertionFailure()
            return
        }
        
        // Notify other owned devices about messages that turned not new
        if op1.ownedIdentityHasAnotherDeviceWithChannel {
            let postOp = PostDiscussionReadJSONEngineOperation(op: op1, obvEngine: obvEngine)
            queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
        }

    }
    

    private func processNewWebRTCMessageToSendNotification(webrtcMessage: WebRTCMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, forStartingCall: Bool) {
        os_log("☎️ We received an observeNewWebRTCMessageToSend notification", log: Self.log, type: .info)
        let op1 = SendWebRTCMessageOperation(webrtcMessage: webrtcMessage, contactID: contactID, forStartingCall: forStartingCall, obvEngine: obvEngine, log: Self.log)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processNewOwnedWebRTCMessageToSend(ownedCryptoId: ObvCryptoId, webrtcMessage: WebRTCMessageJSON) {
        let op1 = SendOwnedWebRTCMessageOperation(webrtcMessage: webrtcMessage, ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }


    private func processNewCallLogItemNotification(objectID: TypeSafeManagedObjectID<PersistedCallLogItem>) {
        os_log("☎️ We received an NewReportCallItem notification", log: Self.log, type: .info)
        do {
            let op1 = DetermineDiscussionForReportingCallOperation(persistedCallLogItemObjectID: objectID)
            let op2 = InsertPersistedMessageSystemIntoDiscussionOperation(
                persistedMessageSystemCategory: .callLogItem,
                operationProvidingPersistedDiscussion: op1,
                optionalContactIdentityObjectID: nil,
                optionalCallLogItemObjectID: objectID)
            let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
            coordinatorsQueue.addOperations([composedOp], waitUntilFinished: false)
        }
    }
    
    
    private func processPersistedContactWasDeletedNotification() {
        os_log("☎️ We received an PersistedContactWasDeleted notification", log: Self.log, type: .info)
        let op = CleanCallLogContactsOperation()
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        coordinatorsQueue.addOperation(op)
    }
    
    
    private func processWipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: Bool, completionHandler: @escaping (Bool) -> Void) {
        let op1 = WipeExpiredMessagesOperation(launchedByBackgroundTask: launchedByBackgroundTask)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        let currentCompletion = composedOp.completionBlock
        composedOp.completionBlock = {
            currentCompletion?()
            composedOp.logReasonIfCancelled(log: Self.log)
            let success = !composedOp.isCancelled
            completionHandler(success)
        }
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func userLeftDiscussion(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) {
        var operationsToQueue = [Operation]()
        do {
            let op1 = WipeOrDeleteReadOnceMessagesOperation(preserveReceivedMessages: false, restrictToDiscussionWithPermanentID: discussionPermanentID)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = DeleteMessagesWithExpiredTimeBasedRetentionOperation(restrictToDiscussionWithPermanentID: discussionPermanentID)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(op)
        }
        do {
            let op = DeleteMessagesWithExpiredCountBasedRetentionOperation(restrictToDiscussionWithPermanentID: discussionPermanentID)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(op)
        }
        do {
            let operations = getOperationsForDeletingOrphanedDatabaseItems()
            operationsToQueue.append(contentsOf: operations)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    
    
    private func userEnteredDiscussion(discussionPermanentID: DiscussionPermanentID) async {
        let op1 = TryToAutoReadDiscussionsReceivedMessagesThatRequireUserActionOperation(input: .discussionPermanentID(discussionPermanentID: discussionPermanentID))
        await queueAndAwaitCompositionOfOneContextualOperation(op1: op1)
        guard op1.isFinished && !op1.isCancelled else {
            assertionFailure()
            return
        }
        let postOp = PostLimitedVisibilityMessageOpenedJSONEngineOperation(op: op1, obvEngine: obvEngine)
        postOp.addDependency(op1)
        queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
    }
    
    
    private func processUserWantsToReadReceivedMessageThatRequiresUserActionNotification(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async {
        let op1 = AllowReadingOfMessagesReceivedThatRequireUserActionOperation(.requestedOnCurrentDevice(ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageId: messageId))
        await queueAndAwaitCompositionOfOneContextualOperation(op1: op1)
        guard op1.isFinished && !op1.isCancelled else {
            assertionFailure()
            return
        }
        let postOp = PostLimitedVisibilityMessageOpenedJSONEngineOperation(op: op1, obvEngine: obvEngine)
        postOp.addDependency(op1)
        queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
    }
    
    
    private func processPersistedMessageReceivedWasReadNotification(persistedMessageReceivedObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>) async {
        // We do not need to sync the sending of a read receipt on the operation queue
        do {
            try await postMessageReadReceiptIfRequired(persistedMessageReceivedObjectID: persistedMessageReceivedObjectID)
        } catch {
            os_log("The Return Receipt could not be posted", log: Self.log, type: .fault)
            assertionFailure()
        }
    }
    
    private func processReceivedFyleJoinHasBeenMarkAsOpenedNotification(receivedFyleJoinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async {
        // We do not need to sync the sending of a read receipt on the operation queue
        do {
            try await postAttachementReadReceiptIfRequired(receivedFyleJoinID: receivedFyleJoinID)
        } catch {
            os_log("The Return Receipt could not be posted", log: Self.log, type: .fault)
            assertionFailure()
        }
    }
    
    
    private func processAReadOncePersistedMessageSentWasSentNotification(persistedMessageSentPermanentID: MessageSentPermanentID, persistedDiscussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) {
        // When a readOnce sent message status becomes "sent", we check whether the user is still within the discussion corresponding to this message.
        // If this is the case, we do nothing. Otherwise, we should delete or wipe the message as it is readOnce, has already been seen, and was properly sent.
        guard ObvUserActivitySingleton.shared.currentDiscussionPermanentID != persistedDiscussionPermanentID else {
            os_log("A readOnce outbound message was sent but the user is still within the discussion, so we do *not* delete the message immediately", log: Self.log, type: .info)
            return
        }
        os_log("A readOnce outbound message was sent after the user left the discussion. We delete/wipe the message now", log: Self.log, type: .info)
        var operationsToQueue = [Operation]()
        do {
            let op1 = WipeOrDeleteReadOnceMessagesOperation(preserveReceivedMessages: false, restrictToDiscussionWithPermanentID: persistedDiscussionPermanentID)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let operations = getOperationsForDeletingOrphanedDatabaseItems()
            operationsToQueue.append(contentsOf: operations)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    
    
    private func processUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, expirationJSON: ExpirationJSON) {
        var operationsToQueue = [Operation]()
        do {
            let op1 = ReplaceDiscussionSharedExpirationConfigurationOperation(ownedCryptoIdAsInitiator: ownedCryptoId, discussionId: discussionId, expirationJSON: expirationJSON)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(ownedCryptoId: ownedCryptoId, discussionId: discussionId, sendTo: .allContactsAndOtherOwnedDevices, obvEngine: obvEngine)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(op)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    

    private func processApplyAllRetentionPoliciesNowNotification(launchedByBackgroundTask: Bool, completionHandler: @escaping (Bool) -> Void) {
        var operationsToQueue = [Operation]()
        do {
            let op = DeleteMessagesWithExpiredTimeBasedRetentionOperation(restrictToDiscussionWithPermanentID: nil)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(op)
            if launchedByBackgroundTask {
                let logOp = BlockOperation()
                operationsToQueue.append(logOp)
            }
        }
        do {
            let op = DeleteMessagesWithExpiredCountBasedRetentionOperation(restrictToDiscussionWithPermanentID: nil)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(op)
        }
        do {
            let operations = getOperationsForDeletingOrphanedDatabaseItems(completionHandler: completionHandler)
            operationsToQueue.append(contentsOf: operations)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    
    
    private func processADiscussionSharedConfigurationIsNeededByContact(contactIdentifier: ObvContactIdentifier, discussionId: DiscussionIdentifier) {
        let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(
            ownedCryptoId: contactIdentifier.ownedCryptoId,
            discussionId: discussionId,
            sendTo: .specificContact(contactCryptoId: contactIdentifier.contactCryptoId),
            obvEngine: obvEngine)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        coordinatorsQueue.addOperation(op)
    }

    
    private func processADiscussionSharedConfigurationIsNeededByAnotherOwnedDevice(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier) {
        let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(ownedCryptoId: ownedCryptoId, discussionId: discussionId, sendTo: .otherOwnedDevices, obvEngine: obvEngine)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        coordinatorsQueue.addOperation(op)
    }

    
    private func processUserWantsToSendEditedVersionOfSentMessage(ownedCryptoId: ObvCryptoId, sentMessageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, newTextBody: String?) {
        let op1 = EditTextBodyOfSentMessageOperation(ownedCryptoId: ownedCryptoId, persistedSentMessageObjectID: sentMessageObjectID, newTextBody: newTextBody)
        let op2 = SendUpdateMessageJSONOperation(sentMessageObjectID: sentMessageObjectID, obvEngine: obvEngine)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processUserWantsToUpdateReaction(ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) {
        let op1 = ProcessSetOrUpdateReactionOnMessageLocalRequestOperation(ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)
        let op2 = SendReactionJSONOperation(messageObjectID: messageObjectID, obvEngine: obvEngine, emoji: newEmoji)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processNewObvEncryptedPushNotificationWasReceivedViaPushKitNotification(encryptedPushNotification: ObvEncryptedPushNotification) async {
        do {
            let obvMessage = try await obvEngine.decrypt(encryptedPushNotification: encryptedPushNotification)
            _ = await processReceivedObvMessage(obvMessage, overridePreviousPersistedMessage: false)
        } catch {
            os_log("☎️ Could not decrypt encrypted push notification received via PushKit. The start call may have been received via WebScoket", log: Self.log, type: .info)
        }
    }
    
    
    private func processUserWantsToMarkAllMessagesAsNotNewWithinDiscussionNotification(persistedDiscussionObjectID: NSManagedObjectID) async throws {
        os_log("Call to processUserWantsToMarkAllMessagesAsNotNewWithinDiscussionNotification for discussion %{public}@", log: Self.log, type: .debug, persistedDiscussionObjectID.debugDescription)
        
        let localIdentifier = String(UUID().debugDescription.prefix(4))
        
        os_log("[%{public}@] Executing a MarkAllMessagesAsNotNewWithinDiscussionOperation for discussion %{public}@", log: Self.log, type: .debug, localIdentifier, persistedDiscussionObjectID.debugDescription)
        let op1 = MarkAllMessagesAsNotNewWithinDiscussionOperation(input: .persistedDiscussionObjectID(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>(objectID: persistedDiscussionObjectID)))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh
        composedOp.qualityOfService = .userInitiated
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        os_log("[%{public}@] Did execute MarkAllMessagesAsNotNewWithinDiscussionOperation for discussion %{public}@", log: Self.log, type: .debug, localIdentifier, persistedDiscussionObjectID.debugDescription)
        
        guard op1.isFinished && !op1.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "MarkAllMessagesAsNotNewWithinDiscussionOperation cancelled")
        }
        
        // Notify other owned devices about messages that turned not new
        
        if op1.ownedIdentityHasAnotherDeviceWithChannel {
            let postOp = PostDiscussionReadJSONEngineOperation(op: op1, obvEngine: obvEngine)
            queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
        }

    }
    
    
    private func processUserWantsToRemoveDraftFyleJoinNotification(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) {
        var operationsToQueue = [Operation]()
        do {
            let op = DeleteDraftFyleJoinOperation(draftFyleJoinObjectID: draftFyleJoinObjectID)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(op)
        }
        do {
            let operations = getOperationsForDeletingOrphanedDatabaseItems()
            operationsToQueue.append(contentsOf: operations)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    
    
}


// MARK: - Draft specific notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func processUserWantsToReplyToMessage(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        let op1 = AddReplyToOnDraftOperation(messageObjectID: messageObjectID, draftObjectID: draftObjectID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUserWantsToRemoveReplyToMessage(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        let op1 = RemoveReplyToOnDraftOperation(draftObjectID: draftObjectID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    

    private func processUserWantsToAddAttachmentsToDraft(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, itemProviders: [NSItemProvider], completionHandler: @escaping (Bool) -> Void) {
        assert(OperationQueue.current != coordinatorsQueue)
                
        let loadItemProviderOperations = itemProviders.map {
            LoadItemProviderOperation(itemProvider: $0, progressAvailable: { [weak self] progress in
                // Called only if a progress is made available during the operation execution
                self?.newProgressToAddForTrackingFreeze(draftPermanentID: draftPermanentID, progress: progress)
            })
        }
        
        let op1 = NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation(
            draftPermanentID: draftPermanentID,
            operationsProvidingLoadedItemProvider: loadItemProviderOperations,
            completionHandler: completionHandler,
            log: Self.log)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        
        // Since we want to wait until all `LoadItemProviderOperation` are finished to execute the `NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation`, we create a dependency
        loadItemProviderOperations.forEach { loadItemProviderOperation in
            composedOp.addDependency(loadItemProviderOperation)
        }

        // Queue all the operations
        
        queueForLongRunningConcurrentOperations.addOperations(loadItemProviderOperations, waitUntilFinished: false)
        coordinatorsQueue.addOperation(composedOp)
    }
    
    private func newProgressToAddForTrackingFreeze(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, progress: Progress) {
        CompositionViewFreezeManager.shared.newProgressToAddForTrackingFreeze(draftPermanentID: draftPermanentID, progress: progress)
    }
    

    private func processUserWantsToAddAttachmentsToDraft(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, urls: [URL], completionHandler: @escaping (Bool) -> Void) {
        assert(OperationQueue.current != coordinatorsQueue)
        
        let loadItemProviderOperations = urls.map {
            LoadItemProviderOperation(itemURL: $0, progressAvailable: { [weak self] progress in
                // Called only if a progress is made available during the operation execution
                self?.newProgressToAddForTrackingFreeze(draftPermanentID: draftPermanentID, progress: progress)
            })
        }

        let op1 = NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation(
            draftPermanentID: draftPermanentID,
            operationsProvidingLoadedItemProvider: loadItemProviderOperations,
            completionHandler: completionHandler,
            log: Self.log)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        
        // Since we want to wait until all `LoadItemProviderOperation` are finished to execute the `NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation`, we create a dependency
        loadItemProviderOperations.forEach { loadItemProviderOperation in
            composedOp.addDependency(loadItemProviderOperation)
        }

        // Queue all the operations
        
        queueForLongRunningConcurrentOperations.addOperations(loadItemProviderOperations, waitUntilFinished: false)
        coordinatorsQueue.addOperation(composedOp)
        
    }

    private func processUserWantsToDeleteAllAttachmentsToDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftTypeToDelete: DeleteAllDraftFyleJoinOfDraftOperation.DraftType = .all) {
        
        var operationsToQueue = [Operation]()

        do {
            let op1 = DeleteAllDraftFyleJoinOfDraftOperation(draftObjectID: draftObjectID, draftTypeToDelete: draftTypeToDelete)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }

        do {
            let operations = getOperationsForDeletingOrphanedDatabaseItems()
            operationsToQueue.append(contentsOf: operations)
        }

        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)

    }
    
    
    private func processUserWantsToSendDraft(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) {
        var operationsToQueue = [Operation]()
        let composedOp: CompositionOfTwoContextualOperations<SaveBodyTextOfPersistedDraftOperationReasonForCancel, RequestedSendingOfDraftOperationReasonForCancel>
        do {
            let op1 = SaveBodyTextAndMentionsOfPersistedDraftOperation(draftPermanentID: draftPermanentID, bodyText: textBody, mentions: mentions)
            let op2 = RequestedSendingOfDraftOperation(draftPermanentID: draftPermanentID)
            composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = BlockOperation()
            op.completionBlock = {
                assert(composedOp.isFinished)
                if composedOp.isCancelled {
                    NewSingleDiscussionNotification.draftCouldNotBeSent(draftPermanentID: draftPermanentID)
                        .postOnDispatchQueue()
                }
            }
            operationsToQueue.append(op)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    

    private func processUserWantsToSendDraftWithAttachments(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, attachmentsURL: [URL]) {
        
        let loadItemProviderOperations = attachmentsURL.map {
            LoadItemProviderOperation(itemURL: $0, progressAvailable: { [weak self] progress in
                // Called only if a progress is made available during the operation execution
                self?.newProgressToAddForTrackingFreeze(draftPermanentID: draftPermanentID, progress: progress)
            })
        }

        let op1 = NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation(
            draftPermanentID: draftPermanentID,
            operationsProvidingLoadedItemProvider: loadItemProviderOperations,
            completionHandler: nil,
            log: Self.log)
        let op2 = RequestedSendingOfDraftOperation(draftPermanentID: draftPermanentID)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        
        let op = BlockOperation()
        op.completionBlock = {
            if composedOp.isCancelled {
                NewSingleDiscussionNotification.draftCouldNotBeSent(draftPermanentID: draftPermanentID)
                    .postOnDispatchQueue()
            }
        }
        
        // Since we want to wait until all `LoadItemProviderOperation` are finished to execute the `NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation`, we create a dependency
        loadItemProviderOperations.forEach { loadItemProviderOperation in
            composedOp.addDependency(loadItemProviderOperation)
        }
        op.addDependency(composedOp)

        // Queue all the operations
        
        queueForLongRunningConcurrentOperations.addOperations(loadItemProviderOperations + [op], waitUntilFinished: false)
        coordinatorsQueue.addOperation(composedOp)

    }

    private func processUserWantsToUpdateDraftExpiration(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) {
        let op1 = UpdateDraftConfigurationOperation(value: value, draftObjectID: draftObjectID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUserWantsToUpdateDraftBodyAndMentions(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftBody: String, mentions: Set<MessageJSON.UserMention>) {
        let op1 = UpdateDraftBodyAndMentionsOperation(draftObjectID: draftObjectID, draftBody: draftBody, mentions: mentions)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUserWantsToUpdateDiscussionLocalConfigurationNotification(with value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) {
        let op1 = UpdateDiscussionLocalConfigurationOperation(
            value: value,
            input: .configurationObjectID(localConfigurationObjectID),
            makeSyncAtomRequest: true,
            syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUserWantsToUpdateLocalConfigurationOfDiscussionNotification(with value: PersistedDiscussionLocalConfigurationValue, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, completionHandler: @escaping () -> Void) {
        let op1 = UpdateDiscussionLocalConfigurationOperation(
            value: value,
            input: .discussionPermanentID(discussionPermanentID),
            makeSyncAtomRequest: true,
            syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        op1.completionBlock = {
            DispatchQueue.main.async {
                completionHandler()
            }
        }
        coordinatorsQueue.addOperation(composedOp)
    }

}


// MARK: - Processing ObvEngine Notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func processNewMessageReceivedNotification(obvMessage: ObvMessage) async {
        os_log("🧦 We received a NewMessageReceived notification", log: Self.log, type: .debug)
        
        ObvDisplayableLogs.shared.log("[🧦][\(obvMessage.messageUID.debugDescription)] Call to processNewMessageReceivedNotification")

        let result = await processReceivedObvMessage(obvMessage, overridePreviousPersistedMessage: true)
        
        let notifyEngine: EngineNotificationOnMessageProcessing

        switch result {
            
        case .definitiveFailure:
            notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)
            
        case .done(attachmentsProcessingRequest: let attachmentsProcessingRequest):
            notifyEngine = .notify(attachmentsProcessingRequest: attachmentsProcessingRequest)
            
        case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
            
            if Date.now.timeIntervalSince(obvMessage.localDownloadTimestamp) < ObvMessengerConstants.maximumTimeIntervalForKeptForLaterMessages {
                
                await messagesKeptForLaterManager.keepForLater(
                    .obvMessageForGroupV2(
                        groupIdentifier: groupIdentifier,
                        obvMessage: obvMessage))
                notifyEngine = .doNotNotify

            } else {
                
                notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)

            }

        case .couldNotFindContactInDatabase(contactCryptoId: let contactCryptoId):
            
            if Date.now.timeIntervalSince(obvMessage.localDownloadTimestamp) < ObvMessengerConstants.maximumTimeIntervalForKeptForLaterMessages {
                
                await messagesKeptForLaterManager.keepForLater(.obvMessageExpectingContact(
                    contactCryptoId: contactCryptoId,
                    obvMessage: obvMessage))
                notifyEngine = .doNotNotify

            } else {
                
                notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)

            }

        }
        
        // If notifyEngine == true, the received message was processed at the app level.
        // We can inform the engine so that it will mark the message (but not the attachments) for deletion.
        
        switch notifyEngine {
        case .notify(let attachmentsProcessingRequest):
            do {
                ObvDisplayableLogs.shared.log("[🧦][\(obvMessage.messageUID.debugDescription)] Calling engine as ObvMessage was processed")
                try await obvEngine.messageWasProcessed(messageId: obvMessage.messageId, attachmentsProcessingRequest: attachmentsProcessingRequest)
                ObvDisplayableLogs.shared.log("[🧦][\(obvMessage.messageUID.debugDescription)] Did call engine as ObvMessage was processed")
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
        case .doNotNotify:
            ObvDisplayableLogs.shared.log("[🧦][\(obvMessage.messageUID.debugDescription)] Not calling engine for ObvMessage")
            return
        }

    }
    
    
    /// Enum of actions to take after processing a message received from the engine.
    ///
    /// After an engine message is received and processed by this coordinator, we must either
    /// - notify the engine that we processed the message (so that is can mark the message for deletion) and indicate what should be done with the attachments,
    /// - or wait until it is appropriate to notify the engine (e.g., when receiving a message for a group that does not yet exist because we did not receive the group creation message yet).
    private enum EngineNotificationOnMessageProcessing {
        case notify(attachmentsProcessingRequest: ObvAttachmentsProcessingRequest)
        case doNotNotify
    }
    
    
    private func processNewOwnedMessageReceivedNotification(obvOwnedMessage: ObvOwnedMessage) async {
        os_log("🧦 We received a NewOwnedMessageReceived notification", log: Self.log, type: .debug)

        ObvDisplayableLogs.shared.log("[🧦][\(obvOwnedMessage.messageUID.debugDescription)] Call to processNewOwnedMessageReceivedNotification")

        let result = await processReceivedObvOwnedMessage(obvOwnedMessage)
        
        let notifyEngine: EngineNotificationOnMessageProcessing

        switch result {
            
        case .definitiveFailure:
            notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)

        case .done(attachmentsProcessingRequest: let attachmentsProcessingRequest):
            notifyEngine = .notify(attachmentsProcessingRequest: attachmentsProcessingRequest)

        case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
            
            if Date.now.timeIntervalSince(obvOwnedMessage.localDownloadTimestamp) < ObvMessengerConstants.maximumTimeIntervalForKeptForLaterMessages {
                
                await messagesKeptForLaterManager.keepForLater(.obvOwnedMessageForGroupV2(
                    groupIdentifier: groupIdentifier,
                    obvOwnedMessage: obvOwnedMessage))
                notifyEngine = .doNotNotify

            } else {
                
                notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)

            }
            
        case .couldNotFindContactInDatabase(contactCryptoId: let contactCryptoId):
            
            if Date.now.timeIntervalSince(obvOwnedMessage.localDownloadTimestamp) < ObvMessengerConstants.maximumTimeIntervalForKeptForLaterMessages {
                
                await messagesKeptForLaterManager.keepForLater(.obvOwnedMessageExpectingContact(
                    contactCryptoId: contactCryptoId,
                    obvOwnedMessage: obvOwnedMessage))
                notifyEngine = .doNotNotify

            } else {
                
                notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)

            }

        }

        // If notifyEngine == true, the received message was processed at the app level.
        // We can inform the engine that will mark the message (not the attachments) for deletion.
        
        switch notifyEngine {
        case .notify(let attachmentsProcessingRequest):
            do {
                ObvDisplayableLogs.shared.log("[🧦][\(obvOwnedMessage.messageUID.debugDescription)] Calling engine as ObvOwnedMessage was processed")
                try await obvEngine.messageWasProcessed(messageId: obvOwnedMessage.messageId, attachmentsProcessingRequest: attachmentsProcessingRequest)
                ObvDisplayableLogs.shared.log("[🧦][\(obvOwnedMessage.messageUID.debugDescription)] Did call engine as ObvOwnedMessage was processed")
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
        case .doNotNotify:
            ObvDisplayableLogs.shared.log("[🧦][\(obvOwnedMessage.messageUID.debugDescription)] Do not call engine for ObvOwnedMessage")
            return
        }
        

    }


    private func processAPersistedGroupV2WasInsertedInDatabase(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV2Identifier) async {

        let messagesKeptForLater = await messagesKeptForLaterManager.getGroupV2MessagesKeptForLaterForOwnedCryptoId(ownedCryptoId, groupIdentifier: groupIdentifier)
        
        for messageKeptForLater in messagesKeptForLater {
            switch messageKeptForLater {
            case .obvMessageForGroupV2(_, let obvMessage):
                await processNewMessageReceivedNotification(obvMessage: obvMessage)
            case .obvOwnedMessageForGroupV2(_, let obvOwnedMessage):
                await processNewOwnedMessageReceivedNotification(obvOwnedMessage: obvOwnedMessage)
            case .obvMessageExpectingContact, .obvOwnedMessageExpectingContact:
                assertionFailure("Those messages are not expected to be part of the returned results")
            }
        }
        
    }
    
    
    private func processPersistedContactWasInserted(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async {
        
        let messagesKeptForLater = await messagesKeptForLaterManager.getMessagesExpectingContactForOwnedCryptoId(ownedCryptoId, contactCryptoId: contactCryptoId)

        for messageKeptForLater in messagesKeptForLater {
            switch messageKeptForLater {
            case .obvMessageExpectingContact(contactCryptoId: _, obvMessage: let obvMessage):
                await processNewMessageReceivedNotification(obvMessage: obvMessage)
            case .obvOwnedMessageExpectingContact(contactCryptoId: _, obvOwnedMessage: let obvOwnedMessage):
                await processNewOwnedMessageReceivedNotification(obvOwnedMessage: obvOwnedMessage)
            case .obvMessageForGroupV2, .obvOwnedMessageForGroupV2:
                assertionFailure("Those messages are not expected to be part of the returned results")
            }
        }
        
    }


    private func processMessageWasAcknowledgedNotification(ownedIdentity: ObvCryptoId, messageIdentifierFromEngine: Data, timestampFromServer: Date, isAppMessageWithUserContent: Bool, isVoipMessage: Bool) {
        
        var operationsToQueue = [Operation]()

        if isAppMessageWithUserContent {
            let op1 = SetTimestampMessageSentOfPersistedMessageSentRecipientInfosOperation(
                ownedCryptoId: ownedIdentity,
                messageIdentifierFromEngineAndTimestampFromServer: [(messageIdentifierFromEngine, timestampFromServer)])
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        
        do {
            let op = BlockOperation()
            op.completionBlock = {
                Task { [weak self] in
                    await self?.obvEngine.deleteHistoryConcerningTheAcknowledgementOfOutboxMessage(
                        messageIdentifierFromEngine:messageIdentifierFromEngine,
                        ownedIdentity:ownedIdentity)
                }
            }
            operationsToQueue.append(op)
        }
        
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)        
    }

    
    private func processAttachmentWasAcknowledgedByServerNotification(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int) {
        let op1 = MarkSentFyleMessageJoinWithStatusAsCompleteOperation(
            ownedCryptoId: ownedCryptoId,
            messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo: [(messageIdentifierFromEngine, restrictToAttachmentNumbers: [attachmentNumber])])
        let op2 = SetTimestampAllAttachmentsSentIfPossibleOfPersistedMessageSentRecipientInfosOperation(
            ownedCryptoId: ownedCryptoId,
            messageIdentifiersFromEngine: [messageIdentifierFromEngine])
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processAttachmentDownloadCancelledByServerNotification(obvAttachment: ObvAttachment) async {
        os_log("We received an AttachmentDownloadCancelledByServer notification", log: Self.log, type: .debug)
        let obvEngine = self.obvEngine
        var operationsToQueue = [Operation]()
        let composedOp: CompositionOfOneContextualOperation<UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation.ReasonForCancel>
        do {
            let op1 = UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation(obvAttachment: obvAttachment, obvEngine: obvEngine)
            composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        let downloadOp = DetermineAttachmentsProcessingRequestForMessageReceivedOperation(kind: .specificAttachment(attachmentId: obvAttachment.attachmentId))
        do {
            let composedOpForDownload = createCompositionOfOneContextualOperation(op1: downloadOp)
            operationsToQueue.append(composedOpForDownload)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        await coordinatorsQueue.addAndAwaitOperations(operationsToQueue)
        if let attachmentsProcessingRequest = downloadOp.attachmentsProcessingRequest {
            do {
                try await obvEngine.messageWasProcessed(messageId: obvAttachment.attachmentId.messageId, attachmentsProcessingRequest: attachmentsProcessingRequest)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    /// This notification is typically sent when we request progress for attachments that cannot be found anymore within the engine's inbox.
    /// Typical if the message/attachments were deleted by the sender before they were completely sent.
    private func processCannotReturnAnyProgressForMessageAttachmentsNotification(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data) {
        let op1 = MarkAllIncompleteReceivedFyleMessageJoinWithStatusAsCancelledByServer(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    

    private func processOwnedAttachmentDownloadCancelledByServerNotification(obvOwnedAttachment: ObvOwnedAttachment) async {
        os_log("We received an OwnedAttachmentDownloadCancelledByServer notification", log: Self.log, type: .debug)
        let obvEngine = self.obvEngine
        var operationsToQueue = [Operation]()
        let composedOp: CompositionOfOneContextualOperation<UpdatePersistedMessageSentFromReceivedObvOwnedAttachmentOperation.ReasonForCancel>
        do {
            let op1 = UpdatePersistedMessageSentFromReceivedObvOwnedAttachmentOperation(obvOwnedAttachment: obvOwnedAttachment, obvEngine: obvEngine)
            composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        let downloadOp = DetermineAttachmentsProcessingRequestForMessageSentOperation(kind: .specificAttachment(attachmentId: obvOwnedAttachment.attachmentId))
        do {
            let composedOpForDownload = createCompositionOfOneContextualOperation(op1: downloadOp)
            operationsToQueue.append(composedOpForDownload)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        await coordinatorsQueue.addAndAwaitOperations(operationsToQueue)
        if let attachmentsProcessingRequest = downloadOp.attachmentsProcessingRequest {
            do {
                try await obvEngine.messageWasProcessed(messageId: obvOwnedAttachment.attachmentId.messageId, attachmentsProcessingRequest: attachmentsProcessingRequest)
            } catch {
                assertionFailure()
            }
        }
    }

    
    private func processAttachmentDownloadedNotification(obvAttachment: ObvAttachment) async {
        let obvEngine = self.obvEngine
        var operationsToQueue = [Operation]()
        let composedOp: CompositionOfOneContextualOperation<UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation.ReasonForCancel>
        do {
            let op1 = UpdatePersistedMessageReceivedFromReceivedObvAttachmentOperation(obvAttachment: obvAttachment, obvEngine: obvEngine)
            composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        let downloadOp = DetermineAttachmentsProcessingRequestForMessageReceivedOperation(kind: .specificAttachment(attachmentId: obvAttachment.attachmentId))
        do {
            let composedOpForDownload = createCompositionOfOneContextualOperation(op1: downloadOp)
            operationsToQueue.append(composedOpForDownload)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        await coordinatorsQueue.addAndAwaitOperations(operationsToQueue)
        if let attachmentsProcessingRequest = downloadOp.attachmentsProcessingRequest {
            do {
                try await obvEngine.messageWasProcessed(messageId: obvAttachment.attachmentId.messageId, attachmentsProcessingRequest: attachmentsProcessingRequest)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    private func processOwnedAttachmentDownloadedNotification(obvOwnedAttachment: ObvOwnedAttachment) async {
        let obvEngine = self.obvEngine
        var operationsToQueue = [Operation]()
        do {
            let op1 = UpdatePersistedMessageSentFromReceivedObvOwnedAttachmentOperation(obvOwnedAttachment: obvOwnedAttachment, obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        let op1 = DetermineAttachmentsProcessingRequestForMessageSentOperation(kind: .specificAttachment(attachmentId: obvOwnedAttachment.attachmentId))
        do {
            let composedOpForDownload = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOpForDownload)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        await coordinatorsQueue.addAndAwaitOperations(operationsToQueue)
        if let attachmentsProcessingRequest = op1.attachmentsProcessingRequest {
            do {
                try await obvEngine.messageWasProcessed(messageId: obvOwnedAttachment.attachmentId.messageId, attachmentsProcessingRequest: attachmentsProcessingRequest)
            } catch {
                assertionFailure()
            }
        }
    }

    
    private func processAttachmentDownloadWasResumed(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int) {
        let op1 = MarkReceivedJoinAsResumedOrPausedOperation(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber, resumeOrPause: .resume)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processAttachmentDownloadWasPaused(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int) {
        let op1 = MarkReceivedJoinAsResumedOrPausedOperation(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber, resumeOrPause: .pause)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processOwnedAttachmentDownloadWasResumed(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int) {
        let op1 = MarkReceivedSentJoinAsResumedOrPausedOperation(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber, resumeOrPause: .resume)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processOwnedAttachmentDownloadWasPaused(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int) {
        let op1 = MarkReceivedSentJoinAsResumedOrPausedOperation(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber, resumeOrPause: .pause)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    

    private func processNewObvReturnReceiptToProcessNotification(obvReturnReceipt: ObvReturnReceipt, retryNumber: Int = 0) {
        
        let obvEngine = self.obvEngine

        guard retryNumber < 10 else {
            assertionFailure()
            Task { await obvEngine.deleteObvReturnReceipt(obvReturnReceipt) }
            return
        }
                
        var operationsToQueue = [Operation]()
        
        let op1 = ProcessObvReturnReceiptOperation(obvReturnReceipt: obvReturnReceipt, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.assertionFailureInCaseOfFault = false // This operation often fails in the simulator, when switching from the share extension back to the app. We have a retry feature just for that reason.
        operationsToQueue.append(composedOp)
        
        let op = BlockOperation()
        op.completionBlock = { [weak self] in
            assert(op1.isFinished)
            assert(composedOp.isFinished)
            if let reasonForCancel = composedOp.reasonForCancel {
                switch reasonForCancel {
                case .coreDataError(error: let error):
                    os_log("Could not process return receipt due to a Core Data error: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                case .op1Cancelled(reason: let op1ReasonForCancel):
                    switch op1ReasonForCancel {
                    case .contextIsNil:
                        os_log("Could not process return receipt: %{public}@", log: Self.log, type: .fault, reasonForCancel.localizedDescription)
                    case .coreDataError(error: let error):
                        os_log("Could not process return receipt: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                    case .couldNotFindAnyPersistedMessageSentRecipientInfosInDatabase:
                        os_log("Could not find message corresponding to the return receipt. We delete the receipt.", log: Self.log, type: .error)
                        Task { await obvEngine.deleteObvReturnReceipt(obvReturnReceipt) }
                        return
                    }
                case .unknownReason, .op1HasUnfinishedDependency:
                    assertionFailure()
                    os_log("Could not process return receipt for an unknwoen reason", log: Self.log, type: .fault)
                }
                self?.processNewObvReturnReceiptToProcessNotification(obvReturnReceipt: obvReturnReceipt, retryNumber: retryNumber + 1)
            } else {
                // If we reach this point, the receipt has been successfully processed. We can delete it from the engine.
                Task { await obvEngine.deleteObvReturnReceipt(obvReturnReceipt) }
            }
        }
        operationsToQueue.append(op)

        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)

    }

    
    /// The OutboxMessagesAndAllTheirAttachmentsWereAcknowledged notification is sent during the bootstrap of the engine, when replaying the transaction history, so as to make sure the app didn't miss any important notification.
    /// It is sent for each deleted outbox message, that exist when the message has been fully sent to the server (unless they were cancelled by the user by deleting the message).
    private func processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(messageIdsAndTimestampsFromServer: [(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)]) {

        // We need to deal with the case where we receive a huge list of messageIds. To do so, we proceed by batches.

        let allSortedIdsAndTimestamps = messageIdsAndTimestampsFromServer.sorted { $0.timestampFromServer < $1.timestampFromServer }
        let batchSize = 50
        
        for index in stride(from: 0, to: allSortedIdsAndTimestamps.count, by: batchSize) {

            let batch = allSortedIdsAndTimestamps[index..<min(allSortedIdsAndTimestamps.count, index+batchSize)]

            var operationsToQueue = [Operation]()
            
            // Each batch is treated on a per owned identity basis
            
            let batchPerOwnedIdentity = Dictionary(grouping: batch, by: { $0.ownedCryptoId })

            for (ownedCryptoId, idsAndTimestamps) in batchPerOwnedIdentity {
                
                let op1 = SetTimestampMessageSentOfPersistedMessageSentRecipientInfosOperation(
                    ownedCryptoId: ownedCryptoId,
                    messageIdentifierFromEngineAndTimestampFromServer: idsAndTimestamps.map { ($0.messageIdentifierFromEngine, $0.timestampFromServer) })
                let op2 = MarkSentFyleMessageJoinWithStatusAsCompleteOperation(
                    ownedCryptoId: ownedCryptoId,
                    messageIdentifiersFromEngine: idsAndTimestamps.map({ $0.messageIdentifierFromEngine }))
                let op3 = SetTimestampAllAttachmentsSentIfPossibleOfPersistedMessageSentRecipientInfosOperation(
                    ownedCryptoId: ownedCryptoId,
                    messageIdentifiersFromEngine: idsAndTimestamps.map({ $0.messageIdentifierFromEngine }))
                let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
                
                operationsToQueue.append(composedOp)
                
            }

            // If the batch is properly processed, we notify the engine (even if the composed operation cancelled)
            
            do {
                let op = BlockOperation()
                op.completionBlock = {
                    guard let maxTimestampFromServer = batch.last?.timestampFromServer else { assertionFailure(); return }
                    Task { [weak self] in await self?.obvEngine.deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(withTimestampFromServerEarlierOrEqualTo: maxTimestampFromServer) }
                }
                operationsToQueue.append(op)
            }

            // Queue the operations for this batch
            
            operationsToQueue.forEach { $0.queuePriority = .low }
            operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
            coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)

        }
        
    }

    
    /// If the network manager fails to send a message during 30 days, it deletes the outbos message and sends a notification that we catch here.
    private func processOutboxMessageCouldNotBeSentToServer(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId) {
        let op1 = MarkSentMessageAsCouldNotBeSentToServerOperation(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .low
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    /// When a contact is deleted, we look for all associated `PersistedMessageSentRecipientInfos` instance with no message identifier from engine and delete these instances.
    /// For each of these instances, we also recompute the status of the associated `PersistedMessageSent` (since the absence of a particular `PersistedMessageSentRecipientInfos`
    /// may have an influence on the result of the computation).
    ///
    /// Those `PersistedMessageSentRecipientInfos` instances are created when sending a message to this contact. In the case we have no channel
    /// with this contact at that point in time, the message won't be accepted by the engine
    /// and will prevent the message to be marked as sent. In practice, the user sees a "rabbit" that cannot go away. Deleting these instances and recomputing the `PersistedMessageSent`
    /// statues allow to prevent this bad user experience. Moreover, the message would never be sent anyway.
    private func processContactWasDeletedNotification(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        let op = DeletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToContactIdentityOperation(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        coordinatorsQueue.addOperation(op)
    }

    
    /// Called when the engine received successfully downloaded and decrypted an extended payload for an application message sent by a contact.
    private func processContactMessageExtendedPayloadAvailable(obvMessage: ObvMessage) {
        let op1 = ExtractReceivedExtendedPayloadOperation(input: .messageSentByContact(obvMessage: obvMessage))
        let op2 = SaveReceivedExtendedPayloadOperation(extractReceivedExtendedPayloadOp: op1)
        let composedOp = createCompositionOfOneContextualOperation(op1: op2)
        composedOp.addDependency(op1)
        self.coordinatorsQueue.addOperations([op1, composedOp], waitUntilFinished: false)
    }

    
    /// Called when the engine received successfully downloaded and decrypted an extended payload for an application message sent from another device of an owned identity.
    private func processOwnedMessageExtendedPayloadAvailable(obvOwnedMessage: ObvOwnedMessage) {
        let op1 = ExtractReceivedExtendedPayloadOperation(input: .messageSentByOtherDeviceOfOwnedIdentity(obvOwnedMessage: obvOwnedMessage))
        let op2 = SaveReceivedExtendedPayloadOperation(extractReceivedExtendedPayloadOp: op1)
        let composedOp = createCompositionOfOneContextualOperation(op1: op2)
        composedOp.addDependency(op1)
        self.coordinatorsQueue.addOperations([op1, composedOp], waitUntilFinished: false)
    }

    
    private func processContactWasRevokedAsCompromisedWithinEngine(obvContactIdentifier: ObvContactIdentifier) {
        // When the engine informs us that a contact has been revoked as compromised, we insert the appropriate system message within the discussion
        ObvStack.shared.performBackgroundTask { [weak self] context in
            guard let _self = self else { return }
            let contact: PersistedObvContactIdentity
            do {
                guard let _contact = try PersistedObvContactIdentity.get(persisted: obvContactIdentifier, whereOneToOneStatusIs: .any, within: context) else { assertionFailure(); return }
                contact = _contact
            } catch {
                os_log("Could not get contact: %{public}", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            if let oneToOneDiscussionObjectID = contact.oneToOneDiscussion?.objectID {
                let op1 = InsertPersistedMessageSystemIntoDiscussionOperation(
                    persistedMessageSystemCategory: .contactRevokedByIdentityProvider,
                    persistedDiscussionObjectID: oneToOneDiscussionObjectID,
                    optionalContactIdentityObjectID: contact.objectID,
                    optionalCallLogItemObjectID: nil,
                    messageUploadTimestampFromServer: nil)
                let composedOp = _self.createCompositionOfOneContextualOperation(op1: op1)
                self?.coordinatorsQueue.addOperations([composedOp], waitUntilFinished: false)
            }
        }
    }

    
    private func processNewUserDialogToPresent(obvDialog: ObvDialog) {
        assert(OperationQueue.current != coordinatorsQueue)
        guard let syncAtomRequestDelegate else { assertionFailure(); return }
        let op1 = ProcessObvDialogOperation(obvDialog: obvDialog, obvEngine: obvEngine, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processAPersistedDialogWasDeleted(uuid: UUID, ownedCryptoId: ObvCryptoId) {
        assert(OperationQueue.current != coordinatorsQueue)
        coordinatorsQueue.addOperation {
            ObvStack.shared.performBackgroundTaskAndWait { (context) in
                do {
                    guard let persistedInvitation = try PersistedInvitation.getPersistedInvitation(uuid: uuid, ownedCryptoId: ownedCryptoId, within: context) else { return }
                    try persistedInvitation.delete()
                    try context.save(logOnFailure: Self.log)
                } catch let error {
                    os_log("Could not delete PersistedInvitation: %@", log: Self.log, type: .error, error.localizedDescription)
                    assertionFailure()
                }
            }
        }
    }
    
    
    private func processContactIntroductionInvitationSent(ownedIdentity: ObvCryptoId, contactIdentityA: ObvCryptoId, contactIdentityB: ObvCryptoId) {
        let op1 = ProcessContactIntroductionInvitationSentOperation(ownedCryptoId: ownedIdentity, contactCryptoIdA: contactIdentityA, contactCryptoIdB: contactIdentityB)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processUserRepliedToReceivedMessageWithinTheNotificationExtensionNotification(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>, messageIdentifierFromEngine: Data, textBody: String, completionHandler: @escaping () -> Void) async {
        // This call will add the received message decrypted by the notification extension into the database to be sure that we will be able to reply to this message.
        await bootstrapMessagesDecryptedWithinNotificationExtension()

        let op1 = CreateUnprocessedReplyToPersistedMessageSentFromBodyOperation(contactPermanentID: contactPermanentID, messageIdentifierFromEngine: messageIdentifierFromEngine, textBody: textBody)
        let op2 = MarkAsReadReceivedMessageOperation(contactPermanentID: contactPermanentID, messageIdentifierFromEngine: messageIdentifierFromEngine)
        let op3 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: nil, obvEngine: obvEngine) {
            DispatchQueue.main.async { completionHandler() }
        }
        let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
        let currentCompletion = composedOp.completionBlock
        composedOp.completionBlock = {
            currentCompletion?()
            if composedOp.isCancelled {
                // One of op1, op2 or op3 cancelled. We call the completion handler
                DispatchQueue.main.async { completionHandler() }
            }
        }
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        
        // Notify other owned devices about messages that turned not new
        if op2.ownedIdentityHasAnotherDeviceWithChannel {
            let postOp = PostDiscussionReadJSONEngineOperation(op: op2, obvEngine: obvEngine)
            queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
        }

    }


    private func processUserRepliedToMissedCallWithinTheNotificationExtensionNotification(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, textBody: String, completionHandler: @escaping () -> Void) {

        let op1 = CreateUnprocessedPersistedMessageSentFromBodyOperation(discussionPermanentID: discussionPermanentID, textBody: textBody)
        let op2 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: nil, obvEngine: obvEngine) {
            DispatchQueue.main.async {
                completionHandler()
            }
        }
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        let currentCompletion = composedOp.completionBlock
        composedOp.completionBlock = {
            currentCompletion?()
            if composedOp.isCancelled {
                DispatchQueue.main.async {
                    completionHandler()
                }
            }
        }
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processUserWantsToMarkAsReadMessageWithinTheNotificationExtensionNotification(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>, messageIdentifierFromEngine: Data, completionHandler: @escaping () -> Void) async {
        
        // The following method call adds the received message decrypted by the notification extension into the database.
        // This allows to be sure that we will be able to mark it as read.
        await bootstrapMessagesDecryptedWithinNotificationExtension()

        let op1 = MarkAsReadReceivedMessageOperation(contactPermanentID: contactPermanentID, messageIdentifierFromEngine: messageIdentifierFromEngine)
        let composedOp1 = createCompositionOfOneContextualOperation(op1: op1)
        let currentCompletion = composedOp1.completionBlock
        
        composedOp1.completionBlock = {
            
            currentCompletion?()
            
            Task { [weak self] in
                
                guard !op1.isCancelled else {
                    DispatchQueue.main.async {
                        completionHandler()
                    }
                    return
                }
                
                // Post a read receipt if required. Normally, this is triggered by a change in the database that eventually calls this coordinator back.
                // Here, we cannot wait until this happens (because we have a completion handler to call), so we post a read receipt immediately.
                // Yes, we might be sending two read receipts...
                
                if let persistedMessageReceivedObjectID = op1.persistedMessageReceivedObjectID {
                    do {
                        try await self?.postMessageReadReceiptIfRequired(persistedMessageReceivedObjectID: persistedMessageReceivedObjectID)
                    } catch {
                        os_log("Could not post read receipt", log: Self.log, type: .fault)
                        assertionFailure()
                        // Continue anyway
                    }
                }
                
            }
        }
        
        coordinatorsQueue.addOperation(composedOp1)
        
        // Notify other owned devices about messages that turned not new
        if op1.ownedIdentityHasAnotherDeviceWithChannel {
            let postOp = PostDiscussionReadJSONEngineOperation(op: op1, obvEngine: obvEngine)
            postOp.addDependency(composedOp1)
            queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
        }

    }
    
    
    private func processUserWantsToWipeFyleMessageJoinWithStatus(ownedCryptoId: ObvCryptoId, objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>) {
        var operationsToQueue = [Operation]()
        do {
            let op1 = WipeFyleMessageJoinsWithStatusOperation(joinObjectIDs: objectIDs, ownedCryptoId: ownedCryptoId, deletionType: .local)
            let op2 = DeletePersistedMessagesOperation(operationProvidingPersistedMessageObjectIDsToDelete: op1)
            let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
            operationsToQueue.append(composedOp)
        }
        do {
            let operations = getOperationsForDeletingOrphanedDatabaseItems()
            operationsToQueue.append(contentsOf: operations)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    

    private func processUserWantsToForwardMessage(messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, discussionPermanentIDs: Set<ObvManagedObjectPermanentID<PersistedDiscussion>>) {
        for discussionPermanentID in discussionPermanentIDs {
            let op1 = CreateUnprocessedForwardPersistedMessageSentFromMessageOperation(messagePermanentID: messagePermanentID, discussionPermanentID: discussionPermanentID)
            let op2 = ComputeExtendedPayloadOperation(provider: op1)
            let op3 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: op2, obvEngine: obvEngine)
            let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
            coordinatorsQueue.addOperation(composedOp)
        }
    }

    private func processUserHasOpenedAReceivedAttachment(receivedFyleJoinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {
        let op1 = MarkAsOpenedOperation(receivedFyleMessageJoinWithStatusID: receivedFyleJoinID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUserWantsToDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {
        let op1 = ResumeOrPauseAttachmentDownloadOperation(receivedJoinObjectID: receivedJoinObjectID, resumeOrPause: .resume, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUserWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) {
        let op1 = ResumeOrPauseOwnedAttachmentDownloadOperation(sentJoinObjectID: sentJoinObjectID, resumeOrPause: .resume, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    private func processUserWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {
        let op1 = ResumeOrPauseAttachmentDownloadOperation(receivedJoinObjectID: receivedJoinObjectID, resumeOrPause: .pause, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUserWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) {
        let op1 = ResumeOrPauseOwnedAttachmentDownloadOperation(sentJoinObjectID: sentJoinObjectID, resumeOrPause: .pause, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    /// Call when a return receipt shall be sent. When `attachmentNumber` is nil, the return receipt concerns a `PersistedMessageReceived`, otherwise, it concerns a `ReceivedFyleMessageJoinWithStatus`.
    private func processADeliveredReturnReceiptShouldBeSent(returnReceipt: ReturnReceiptJSON, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, attachmentNumber: Int?) {
        
        do {
            try obvEngine.postReturnReceiptWithElements(returnReceipt.elements,
                                                        andStatus: ReturnReceiptJSON.Status.delivered.rawValue,
                                                        forContactCryptoId: contactCryptoId,
                                                        ofOwnedIdentityCryptoId: ownedCryptoId,
                                                        messageIdentifierFromEngine: messageIdentifierFromEngine,
                                                        attachmentNumber: attachmentNumber)
        } catch {
            os_log("🧾 Failed to post return receipt", log: Self.log, type: .fault)
        }
        
    }

    
    private func processTooManyWrongPasscodeAttemptsCausedLockOut() {
        guard ObvMessengerSettings.Privacy.lockoutCleanEphemeral else { return }
        let op1 = WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation(userDefaults: userDefaults,
                                                                                   appType: .mainApp,
                                                                                   wipeType: .startWipeFromAppOrShareExtension)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processPersistedObvOwnedIdentityWasDeleted() {
        let operationsToQueue = getOperationsForDeletingOrphanedDatabaseItems { [weak self] _ in
            self?.trashOrphanedFilesFoundInTheFylesDirectory()
            self?.deleteOldOrOrphanedDatabaseEntries()
            self?.cleanExpiredMuteNotificationsSetting()
            self?.cleanOrphanedPersistedMessageTimestampedMetadata()
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    
    
    private func processBetaUserWantsToDebugCoordinatorsQueue() {
        guard let logString = (coordinatorsQueue as? LoggedOperationQueue)?.logOperations(ops: []) else { return }
        ObvMessengerInternalNotification.betaUserWantsToSeeLogString(logString: logString)
            .postOnDispatchQueue()
    }
    
    private func processUserWantsToArchiveDiscussion(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, completionHandler: ((Bool) -> Void)?) {
        let op1 = ArchiveDiscussionOperation(discussionPermanentID: discussionPermanentID, action: .archive)
        op1.completionBlock = {
            completionHandler?(!op1.isCancelled)
        }
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUserWantsToUnarchiveDiscussion(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, updateTimestampOfLastMessage: Bool, completionHandler: ((Bool) -> Void)?) {
        let op1 = ArchiveDiscussionOperation(discussionPermanentID: discussionPermanentID, action: .unarchive(updateTimestampOfLastMessage: updateTimestampOfLastMessage))
        op1.completionBlock = {
            completionHandler?(!op1.isCancelled)
        }
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUpdateNormalizedSearchKeyOnPersistedDiscussions(ownedIdentity: ObvCryptoId, completionHandler: (() -> Void)?) {
        let op1 = UpdateNormalizedSearchKeyOnPersistedDiscussionsOperation(ownedIdentity: ownedIdentity)
        op1.completionBlock = {
            completionHandler?()
        }
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUserWantsToReorderDiscussions(discussionObjectIds: [NSManagedObjectID], ownedIdentity: ObvCryptoId, completionHandler: ((Bool) -> Void)?) {
        let op1 = ReorderDiscussionsOperation(input: .discussionObjectIDs(discussionObjectIDs: discussionObjectIds), ownedIdentity: ownedIdentity, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        op1.completionBlock = {
            completionHandler?(!op1.isCancelled)
        }
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
}


// MARK: - Helpers

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func postMessageReadReceiptIfRequired(persistedMessageReceivedObjectID: TypeSafeManagedObjectID<PersistedMessageReceived>) async throws {
        // We do not need to sync the sending of a read receipt on the operation queue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ObvStack.shared.performBackgroundTask { [weak self] (context) in
                do {
                    guard let messageReceived = try PersistedMessageReceived.get(with: persistedMessageReceivedObjectID, within: context) else {
                        continuation.resume()
                        return
                    }
                    try self?.postMessageReadReceiptIfRequired(messageReceived: messageReceived)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func postMessageReadReceiptIfRequired(messageReceived: PersistedMessageReceived) throws {
        guard messageReceived.discussion?.localConfiguration.doSendReadReceipt ?? ObvMessengerSettings.Discussions.doSendReadReceipt else { return }
        guard let returnReceiptJSON = messageReceived.returnReceipt else { return }
        guard let contactCryptoId = messageReceived.contactIdentity?.cryptoId else { return }
        guard let ownedCryptoId = messageReceived.contactIdentity?.ownedIdentity?.cryptoId else { return }
        let messageIdentifierFromEngine = messageReceived.messageIdentifierFromEngine
        try obvEngine.postReturnReceiptWithElements(returnReceiptJSON.elements,
                                                    andStatus: ReturnReceiptJSON.Status.read.rawValue,
                                                    forContactCryptoId: contactCryptoId,
                                                    ofOwnedIdentityCryptoId: ownedCryptoId,
                                                    messageIdentifierFromEngine: messageIdentifierFromEngine,
                                                    attachmentNumber: nil)
    }

    private func postAttachementReadReceiptIfRequired(receivedFyleJoinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        // We do not need to sync the sending of a read receipt on the operation queue
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ObvStack.shared.performBackgroundTask { [weak self] (context) in
                do {
                    guard let receivedFyleJoin = try ReceivedFyleMessageJoinWithStatus.get(objectID: receivedFyleJoinID, within: context) else {
                        continuation.resume()
                        return
                    }
                    try self?.postAttachementReadReceiptIfRequired(receivedFyleJoin: receivedFyleJoin)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func postAttachementReadReceiptIfRequired(receivedFyleJoin: ReceivedFyleMessageJoinWithStatus) throws {
        let messageReceived = receivedFyleJoin.receivedMessage
        guard messageReceived.discussion?.localConfiguration.doSendReadReceipt ?? ObvMessengerSettings.Discussions.doSendReadReceipt else { return }
        guard let returnReceiptJSON = messageReceived.returnReceipt else { return }
        guard let contactCryptoId = messageReceived.contactIdentity?.cryptoId else { return }
        guard let ownedCryptoId = messageReceived.contactIdentity?.ownedIdentity?.cryptoId else { return }
        os_log("🧾 Calling postReturnReceiptWithElements with nonce %{public}@ and attachmentNumber: %{public}@ from postAttachementReadReceiptIfRequired", log: Self.log, type: .info, returnReceiptJSON.elements.nonce.hexString(), String(describing: receivedFyleJoin.index))
        try obvEngine.postReturnReceiptWithElements(returnReceiptJSON.elements,
                                                    andStatus: ReturnReceiptJSON.Status.read.rawValue,
                                                    forContactCryptoId: contactCryptoId,
                                                    ofOwnedIdentityCryptoId: ownedCryptoId,
                                                    messageIdentifierFromEngine: receivedFyleJoin.receivedMessage.messageIdentifierFromEngine,
                                                    attachmentNumber: receivedFyleJoin.index)
    }

    
    
    enum ProcessReceivedObvOwnedMessageResult {
        case done(attachmentsProcessingRequest: ObvAttachmentsProcessingRequest)
        case definitiveFailure
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case couldNotFindContactInDatabase(contactCryptoId: ObvCryptoId)
    }
    
    /// Returns `true` if the message can be marked for deletion in the engine, and `false` otherwise.
    private func processReceivedObvOwnedMessage(_ obvOwnedMessage: ObvOwnedMessage) async -> ProcessReceivedObvOwnedMessageResult {
        
        assert(OperationQueue.current != coordinatorsQueue)

        os_log("Call to processReceivedObvOwnedMessage", log: Self.log, type: .debug)
        
        let persistedItemJSON: PersistedItemJSON
        do {
            persistedItemJSON = try PersistedItemJSON.jsonDecode(obvOwnedMessage.messagePayload)
        } catch {
            os_log("Could not decode the message payload", log: Self.log, type: .error)
            assertionFailure()
            return .definitiveFailure
        }

        // Case #1: The ObvOwnedMessage contains a WebRTC signaling message
        
        if let webrtcMessage = persistedItemJSON.webrtcMessage {
            os_log("☎️ The owned message is a WebRTC signaling message", log: Self.log, type: .debug)
            await self.processReceivedWebRTCMessageJSON(webrtcMessage, obvOwnedMessage: obvOwnedMessage)
            return .done(attachmentsProcessingRequest: .deleteAll)
        }

        // Case #2: The ObvOwnedMessage contains a message
        
        if let messageJSON = persistedItemJSON.message {
            os_log("The message is an ObvOwnedMessage", log: Self.log, type: .debug)
            let returnReceiptJSON = persistedItemJSON.returnReceipt
            let result = await self.createPersistedMessageSentFromReceivedObvOwnedMessage(
                obvOwnedMessage,
                messageJSON: messageJSON,
                returnReceiptJSON: returnReceiptJSON)
            switch result {
            case .sentMessageCreated(attachmentsProcessingRequest: let attachmentsProcessingRequest):
                return .done(attachmentsProcessingRequest: attachmentsProcessingRequest)
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .sentMessageCreationFailure:
                assertionFailure()
                return .definitiveFailure
            }
        }

        // Case #3: The ObvOwnedMessage contains a shared configuration for a discussion
        
        if let discussionSharedConfiguration = persistedItemJSON.discussionSharedConfiguration {
            os_log("The message is shared discussion configuration", log: Self.log, type: .debug)
            let result = await updateSharedConfigurationOfPersistedDiscussion(
                using: discussionSharedConfiguration,
                fromOtherDeviceOfOwnedId: obvOwnedMessage.ownedCryptoId,
                messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer,
                messageLocalDownloadTimestamp: obvOwnedMessage.localDownloadTimestamp)
            switch result {
            case .done:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .failed:
                return .definitiveFailure
            case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .couldNotFindContactInDatabase(contactCryptoId: let contactCryptoId):
                return .couldNotFindContactInDatabase(contactCryptoId: contactCryptoId)
            }
        }

        // Case #4: The ObvOwnedMessage contains a JSON message indicating that some messages should be globally deleted in a discussion
        
        if let deleteMessagesJSON = persistedItemJSON.deleteMessagesJSON {
            os_log("The owned message is a delete message JSON", log: Self.log, type: .debug)
            let op1 = ProcessRemoteWipeMessagesRequestOperation(deleteMessagesJSON: deleteMessagesJSON,
                                                                requester: .ownedIdentity(ownedCryptoId: obvOwnedMessage.ownedCryptoId),
                                                                messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }

        // Case #5: The ObvOwnedMessage contains a JSON message indicating that a discussion should be globally deleted

        if let deleteDiscussionJSON = persistedItemJSON.deleteDiscussionJSON {
            os_log("The owned message is a delete discussion JSON", log: Self.log, type: .debug)
            cleanJsonMessagesSavedByNotificationExtension()
            var operationsToQueue = [Operation]()
            do {
                let op1 = DetermineEngineIdentifiersOfMessagesToCancelOperation(
                    input: .remoteDiscussionDeletionRequestFromOtherOwnedDevice(deleteDiscussionJSON: deleteDiscussionJSON, obvOwnedMessage: obvOwnedMessage),
                    obvEngine: obvEngine)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                await coordinatorsQueue.addAndAwaitOperation(composedOp)
                let op2 = CancelUploadOrDownloadOfPersistedMessagesOperation(op: op1, obvEngine: obvEngine)
                await queueForOperationsMakingEngineCalls.addAndAwaitOperation(op2)
            }
            let op1: ProcessRemoteWipeDiscussionRequestOperation
            do {
                op1 = ProcessRemoteWipeDiscussionRequestOperation(
                    deleteDiscussionJSON: deleteDiscussionJSON,
                    requester: .ownedIdentity(ownedCryptoId: obvOwnedMessage.ownedCryptoId),
                    messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                let currentCompletion = composedOp.completionBlock
                composedOp.completionBlock = {
                    currentCompletion?()
                    composedOp.logReasonIfCancelled(log: Self.log)
                }
                operationsToQueue.append(composedOp)
            }
            do {
                let operations = getOperationsForDeletingOrphanedDatabaseItems()
                operationsToQueue.append(contentsOf: operations)
            }
            guard !operationsToQueue.isEmpty else { assertionFailure(); return .definitiveFailure }
            operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
            await coordinatorsQueue.addAndAwaitOperations(operationsToQueue)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }

        // Case #6: The ObvOwnedMessage contains a JSON message indicating that a received message has been edited by the original sender

        if let updateMessageJSON = persistedItemJSON.updateMessageJSON {
            os_log("The owned message is an update message JSON", log: Self.log, type: .debug)
            let op1 = EditTextBodyOfReceivedMessageOperation(
                updateMessageJSON: updateMessageJSON,
                requester: .ownedIdentity(ownedCryptoId: obvOwnedMessage.ownedCryptoId),
                messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }

        // Case #7: The ObvOwnedMessage contains a JSON message indicating that a reaction has been from another owned device

        if let reactionJSON = persistedItemJSON.reactionJSON {
            os_log("The owned message is a reaction", log: Self.log, type: .debug)
            let op1 = ProcessSetOrUpdateReactionOnMessageOperation(
                reactionJSON: reactionJSON,
                requester: .ownedIdentity(ownedCryptoId: obvOwnedMessage.ownedCryptoId),
                messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Case #8: The ObvOwnedMessage contains a JSON message containing a request for a group v2 discussion shared settings
        
        if let querySharedSettingsJSON = persistedItemJSON.querySharedSettingsJSON {
            os_log("The owned message contains a request for a group v2 discussion share settings", log: Self.log, type: .debug)
            let op1 = RespondToQuerySharedSettingsOperation(
                querySharedSettingsJSON: querySharedSettingsJSON,
                requester: .ownedIdentity(ownedCryptoId: obvOwnedMessage.ownedCryptoId))
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            return .done(attachmentsProcessingRequest: .deleteAll)
        }
        
        // Case #9: The ObvOwnedMessage contains a JSON message indicating that a contact did take a screen capture of sensitive content
        
        if let screenCaptureDetectionJSON = persistedItemJSON.screenCaptureDetectionJSON {
            os_log("The owned message indicates that a contact or a owned identity did take a screen capture of sensitive content", log: Self.log, type: .debug)
            let op1 = ProcessDetectionThatSensitiveMessagesWereCapturedOperation(
                screenCaptureDetectionJSON: screenCaptureDetectionJSON,
                requester: .ownedIdentity(ownedCryptoId: obvOwnedMessage.ownedCryptoId),
                messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Case #10: The ObvOwnedMessage contains a JSON message indicating that a received message with limited visibility was read on another owned device
        
        if let limitedVisibilityMessageOpenedJSON = persistedItemJSON.limitedVisibilityMessageOpenedJSON {
            os_log("The owned message indicates that a received message with limited visibility was read on another owned device", log: Self.log, type: .debug)
            guard let discussionId = try? limitedVisibilityMessageOpenedJSON.getDiscussionId(ownedCryptoId: obvOwnedMessage.ownedCryptoId) else {
                assertionFailure()
                return .done(attachmentsProcessingRequest: .deleteAll)
            }
            guard let messageId = try? limitedVisibilityMessageOpenedJSON.getMessageId(ownedCryptoId: obvOwnedMessage.ownedCryptoId) else {
                assertionFailure()
                return .done(attachmentsProcessingRequest: .deleteAll)
            }
            let op1 = AllowReadingOfMessagesReceivedThatRequireUserActionOperation(
                .requestedOnAnotherOwnedDevice(
                    ownedCryptoId: obvOwnedMessage.ownedCryptoId,
                    discussionId: discussionId,
                    messageId: messageId,
                    messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer))
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Case #11: The ObvOwnedMessage contains a JSON message indicating that certain messages must be marked as "not new" within a discussion as they were read on another device
        
        if let discussionRead = persistedItemJSON.discussionRead {
            os_log("The owned message indicates that certain messages must be marked as not new within a discussion as they were read on another device", log: Self.log, type: .debug)
            let op1 = MarkAllMessagesAsNotNewWithinDiscussionOperation(input: .discussionReadJSON(ownedCryptoId: obvOwnedMessage.ownedCryptoId, discussionRead: discussionRead))
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Unknow case, we mark the message for deletion
        
        assertionFailure()
        return .definitiveFailure

    }
    
    
    private func processReceivedWebRTCMessageJSON(_ webrtcMessage: WebRTCMessageJSON, obvMessage: ObvMessage) async {
        guard abs(obvMessage.downloadTimestampFromServer.timeIntervalSince(obvMessage.messageUploadTimestampFromServer)) < 30 else {
            // We discard old WebRTC messages
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ObvStack.shared.performBackgroundTask { (context) in
                guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: context) else {
                    os_log("☎️ Could not find persisted contact associated with received webrtc message", log: Self.log, type: .fault)
                    continuation.resume()
                    return
                }
                let contactId = OlvidUserId.known(
                    contactObjectID: persistedContactIdentity.typedObjectID,
                    ownCryptoId: obvMessage.fromContactIdentity.ownedCryptoId,
                    remoteCryptoId: obvMessage.fromContactIdentity.contactCryptoId,
                    displayName: persistedContactIdentity.fullDisplayName)
                ObvMessengerInternalNotification.newWebRTCMessageWasReceived(
                    webrtcMessage: webrtcMessage,
                    fromOlvidUser: contactId,
                    messageUID: obvMessage.messageUID)
                .postOnDispatchQueue()
                continuation.resume()
            }
        }
    }

    
    private func processReceivedWebRTCMessageJSON(_ webrtcMessage: WebRTCMessageJSON, obvOwnedMessage: ObvOwnedMessage) async {
        guard abs(obvOwnedMessage.downloadTimestampFromServer.timeIntervalSince(obvOwnedMessage.messageUploadTimestampFromServer)) < 30 else {
            // We discard old WebRTC messages
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ObvStack.shared.performBackgroundTask { (context) in
                let ownedUser = OlvidUserId.ownedIdentity(ownedCryptoId: obvOwnedMessage.ownedCryptoId)
                ObvMessengerInternalNotification.newWebRTCMessageWasReceived(
                    webrtcMessage: webrtcMessage,
                    fromOlvidUser: ownedUser,
                    messageUID: obvOwnedMessage.messageUID)
                .postOnDispatchQueue()
                continuation.resume()
            }
        }
    }

    
    enum ProcessReceivedObvMessageResult {
        case done(attachmentsProcessingRequest: ObvAttachmentsProcessingRequest)
        case definitiveFailure
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case couldNotFindContactInDatabase(contactCryptoId: ObvCryptoId)
    }
    
    
    private func processReceivedObvMessage(_ obvMessage: ObvMessage, overridePreviousPersistedMessage: Bool) async -> ProcessReceivedObvMessageResult {

        assert(OperationQueue.current != coordinatorsQueue)

        os_log("Call to processReceivedObvMessage", log: Self.log, type: .debug)
        
        let persistedItemJSON: PersistedItemJSON
        do {
            persistedItemJSON = try PersistedItemJSON.jsonDecode(obvMessage.messagePayload)
        } catch {
            os_log("Could not decode the message payload", log: Self.log, type: .error)
            assertionFailure()
            return .definitiveFailure
        }
        
        // Case #1: The ObvMessage contains a WebRTC signaling message
        
        if let webrtcMessage = persistedItemJSON.webrtcMessage {
            os_log("☎️ The message is a WebRTC signaling message", log: Self.log, type: .debug)
            await self.processReceivedWebRTCMessageJSON(webrtcMessage, obvMessage: obvMessage)
            return .done(attachmentsProcessingRequest: .deleteAll)
        }
        
        // Case #2: The ObvMessage contains a message
        
        if let messageJSON = persistedItemJSON.message {
            os_log("The message is an ObvMessage", log: Self.log, type: .debug)
            let returnReceiptJSON = persistedItemJSON.returnReceipt
            let result = await self.createPersistedMessageReceivedFromReceivedObvMessage(
                obvMessage,
                messageJSON: messageJSON,
                overridePreviousPersistedMessage: overridePreviousPersistedMessage,
                returnReceiptJSON: returnReceiptJSON)
            switch result {
            case .receivedMessageCreated(attachmentsProcessingRequest: let attachmentsProcessingRequest):
                return .done(attachmentsProcessingRequest: attachmentsProcessingRequest)
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .receivedMessageCreationFailure:
                return .definitiveFailure
            }
        }
        
        // Case #3: The ObvMessage contains a shared configuration for a discussion
        
        if let discussionSharedConfiguration = persistedItemJSON.discussionSharedConfiguration {
            os_log("The message is shared discussion configuration", log: Self.log, type: .debug)
            let result = await updateSharedConfigurationOfPersistedDiscussion(
                using: discussionSharedConfiguration,
                fromContact: obvMessage.fromContactIdentity,
                messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                messageLocalDownloadTimestamp: obvMessage.localDownloadTimestamp)
            switch result {
            case .done:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .failed:
                return .definitiveFailure
            case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .couldNotFindContactInDatabase(contactCryptoId: let contactCryptoId):
                return .couldNotFindContactInDatabase(contactCryptoId: contactCryptoId)
            }
        }

        // Case #4: The ObvMessage contains a JSON message indicating that some messages should be globally deleted in a discussion
        
        if let deleteMessagesJSON = persistedItemJSON.deleteMessagesJSON {
            os_log("The message is a delete message JSON", log: Self.log, type: .debug)
            let op1 = ProcessRemoteWipeMessagesRequestOperation(deleteMessagesJSON: deleteMessagesJSON,
                                                                requester: .contact(contactIdentifier: obvMessage.fromContactIdentity),
                                                                messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Case #5: The ObvMessage contains a JSON message indicating that a discussion should be globally deleted

        if let deleteDiscussionJSON = persistedItemJSON.deleteDiscussionJSON {
            os_log("The message is a delete discussion JSON", log: Self.log, type: .debug)
            cleanJsonMessagesSavedByNotificationExtension()
            var operationsToQueue = [Operation]()
            do {
                let op1 = DetermineEngineIdentifiersOfMessagesToCancelOperation(
                    input: .remoteDiscussionDeletionRequestFromContact(deleteDiscussionJSON: deleteDiscussionJSON, obvMessage: obvMessage),
                    obvEngine: obvEngine)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                await coordinatorsQueue.addAndAwaitOperation(composedOp)
                let op2 = CancelUploadOrDownloadOfPersistedMessagesOperation(op: op1, obvEngine: obvEngine)
                await queueForOperationsMakingEngineCalls.addAndAwaitOperation(op2)
            }
            let op1: ProcessRemoteWipeDiscussionRequestOperation
            do {
                op1 = ProcessRemoteWipeDiscussionRequestOperation(
                    deleteDiscussionJSON: deleteDiscussionJSON,
                    requester: .contact(contactIdentifier: obvMessage.fromContactIdentity),
                    messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                let currentCompletion = composedOp.completionBlock
                composedOp.completionBlock = {
                    currentCompletion?()
                    composedOp.logReasonIfCancelled(log: Self.log)
                }
                operationsToQueue.append(composedOp)
            }
            do {
                let operations = getOperationsForDeletingOrphanedDatabaseItems()
                operationsToQueue.append(contentsOf: operations)
            }
            guard !operationsToQueue.isEmpty else { assertionFailure(); return .definitiveFailure }
            operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
            await coordinatorsQueue.addAndAwaitOperations(operationsToQueue)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Case #6: The ObvMessage contains a JSON message indicating that a received message has been edited by the original sender

        if let updateMessageJSON = persistedItemJSON.updateMessageJSON {
            os_log("The message is an update message JSON", log: Self.log, type: .debug)
            let op1 = EditTextBodyOfReceivedMessageOperation(
                updateMessageJSON: updateMessageJSON,
                requester: .contact(contactIdentifier: obvMessage.fromContactIdentity),
                messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }

        // Case #7: The ObvMessage contains a JSON message indicating that a reaction has been added by a contact

        if let reactionJSON = persistedItemJSON.reactionJSON {
            let op1 = ProcessSetOrUpdateReactionOnMessageOperation(
                reactionJSON: reactionJSON,
                requester: .contact(contactIdentifier: obvMessage.fromContactIdentity),
                messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Case #8: The ObvMessage contains a JSON message containing a request for a group v2 discussion shared settings
        
        if let querySharedSettingsJSON = persistedItemJSON.querySharedSettingsJSON {
            let op1 = RespondToQuerySharedSettingsOperation(
                querySharedSettingsJSON: querySharedSettingsJSON,
                requester: .contact(contactIdentifier: obvMessage.fromContactIdentity))
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            return .done(attachmentsProcessingRequest: .deleteAll)
        }
        
        // Case #9: The ObvMessage contains a JSON message indicating that a contact did take a screen capture of sensitive content
        
        if let screenCaptureDetectionJSON = persistedItemJSON.screenCaptureDetectionJSON {
            let op1 = ProcessDetectionThatSensitiveMessagesWereCapturedOperation(
                screenCaptureDetectionJSON: screenCaptureDetectionJSON,
                requester: .contact(contactIdentifier: obvMessage.fromContactIdentity),
                messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Unknow case, we decide to mark the message for deletion
        
        assertionFailure()
        return .definitiveFailure

    }
    
    enum UpdateSharedConfigurationOfPersistedDiscussionReceivedFromContactResult {
        case done
        case failed
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case couldNotFindContactInDatabase(contactCryptoId: ObvCryptoId)
    }
    
    /// This method is called when receiving a message from the engine that contains a shared configuration for a persisted discussion (typically, either one2one, or a group discussion owned by the sender of this message).
    /// We use this new configuration to update ours.
    private func updateSharedConfigurationOfPersistedDiscussion(using discussionSharedConfiguration: DiscussionSharedConfigurationJSON, fromContact: ObvContactIdentifier, messageUploadTimestampFromServer: Date, messageLocalDownloadTimestamp: Date) async -> UpdateSharedConfigurationOfPersistedDiscussionReceivedFromContactResult {
        
        let op1 = MergeDiscussionSharedExpirationConfigurationOperation(
            discussionSharedConfiguration: discussionSharedConfiguration,
            origin: .fromContact(contactIdentifier: fromContact),
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            messageLocalDownloadTimestamp: messageLocalDownloadTimestamp)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        assert(op1.isFinished)
        
        switch op1.result {
        case .couldNotFindGroupV2InDatabase(let groupIdentifier):
            return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
        case .couldNotFindContactInDatabase(contactCryptoId: let contactCryptoId):
            return .couldNotFindContactInDatabase(contactCryptoId: contactCryptoId)
        case .merged, .contactIsNotOneToOne:
            return .done
        case nil:
            assertionFailure()
            return .failed
        }
        
    }

    
    enum UpdateSharedConfigurationOfPersistedDiscussionReceivedFromOtherOwnedDevice {
        case done
        case failed
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case couldNotFindContactInDatabase(contactCryptoId: ObvCryptoId)
    }

    
    /// This method is called when receiving a message from the engine that contains a shared configuration for a persisted discussion (typically, either one2one, or a group discussion owned by the sender of this message).
    /// We use this new configuration to update ours.
    private func updateSharedConfigurationOfPersistedDiscussion(using discussionSharedConfiguration: DiscussionSharedConfigurationJSON, fromOtherDeviceOfOwnedId ownedCryptoId: ObvCryptoId, messageUploadTimestampFromServer: Date, messageLocalDownloadTimestamp: Date) async -> UpdateSharedConfigurationOfPersistedDiscussionReceivedFromOtherOwnedDevice {
        
        let op1 = MergeDiscussionSharedExpirationConfigurationOperation(
            discussionSharedConfiguration: discussionSharedConfiguration,
            origin: .fromOtherDeviceOfOwnedIdentity(ownedCryptoId: ownedCryptoId),
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            messageLocalDownloadTimestamp: messageLocalDownloadTimestamp)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        assert(op1.isFinished)
        
        switch op1.result {
        case .couldNotFindGroupV2InDatabase(let groupIdentifier):
            return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
        case .couldNotFindContactInDatabase(contactCryptoId: let contactCryptoId):
            return .couldNotFindContactInDatabase(contactCryptoId: contactCryptoId)
        case .merged, .contactIsNotOneToOne:
            return .done
        case nil:
            assertionFailure()
            return .failed
        }

    }

    
    private func processReportCallEvent(callUUID: UUID, callReport: CallReport, groupIdentifier: GroupIdentifier?, ownedCryptoId: ObvCryptoId) {
        let op = ReportCallEventOperation(callUUID: callUUID,
                                          callReport: callReport,
                                          groupIdentifier: groupIdentifier,
                                          ownedCryptoId: ownedCryptoId)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        self.coordinatorsQueue.addOperation(op)
    }

    
    private func processCallWasEnded(uuidForCallKit: UUID) {
        let op = ReportEndCallOperation(callUUID: uuidForCallKit)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        self.coordinatorsQueue.addOperation(op)
    }
    
    
    private func processInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) {
        let op1 = InsertEndToEndEncryptedSystemMessageIfCurrentDiscussionIsEmptyOperation(discussionObjectID: discussionObjectID, markAsRead: markAsRead)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }


    enum CreatePersistedMessageReceivedFromReceivedObvMessageResult {
        case receivedMessageCreated(attachmentsProcessingRequest: ObvAttachmentsProcessingRequest)
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case receivedMessageCreationFailure
    }

    /// This method *must* be called from `processReceivedObvMessage(...)`.
    /// This method is called when a new (received) ObvMessage is available. This message can come from one of the two followings places:
    /// - Either it was serialized within the notification extension, and deserialized here,
    /// - Either it was received by the main app.
    /// In the first case, this method is called using `overridePreviousPersistedMessage` set to `false`: we check whether the message already exists in database (using the message uid from server) and, if this is the
    /// case, we do nothing. If the message does not exist, we create it. In the second case, `overridePreviousPersistedMessage` set to `true` and we override any existing persisted message. In other words, messages
    /// comming from the engine always superseed messages comming from  the notification extension.
    private func createPersistedMessageReceivedFromReceivedObvMessage(_ obvMessage: ObvMessage, messageJSON: MessageJSON, overridePreviousPersistedMessage: Bool, returnReceiptJSON: ReturnReceiptJSON?) async -> CreatePersistedMessageReceivedFromReceivedObvMessageResult {

        os_log("Call to createPersistedMessageReceivedFromReceivedObvMessage for obvMessage %{public}@", log: Self.log, type: .debug, obvMessage.messageIdentifierFromEngine.debugDescription)

        // Create a persisted message received
        
        let op1 = CreatePersistedMessageReceivedFromReceivedObvMessageOperation(obvMessage: obvMessage,
                                                                                messageJSON: messageJSON,
                                                                                overridePreviousPersistedMessage: overridePreviousPersistedMessage,
                                                                                returnReceiptJSON: returnReceiptJSON)
        let op2 = TryToAutoReadDiscussionsReceivedMessagesThatRequireUserActionOperation(input: .operationProvidingDiscussionPermanentID(op: op1))
        let composedOp1 = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        await coordinatorsQueue.addAndAwaitOperation(composedOp1)

        switch op1.result {
        case .couldNotFindGroupV2InDatabase(let groupIdentifier):
            return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
        case nil:
            return .receivedMessageCreationFailure
        case .messageCreated:
            break
        }

        guard composedOp1.isFinished && !composedOp1.isCancelled else {
            assertionFailure()
            return .receivedMessageCreationFailure
        }

        // If we reach this point, the received message was properly created and some messages may have been auto-read
        // We asynchronously post this information to our other owned devices
        
        if op2.ownedIdentityHasAnotherDeviceWithChannel {
            let postOp = PostLimitedVisibilityMessageOpenedJSONEngineOperation(op: op2, obvEngine: obvEngine)
            postOp.addDependency(op2)
            queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
        }

        // Determine the attachments that should be downloaded now
        
        assert(op1.isFinished)
        let downloadOp = DetermineAttachmentsProcessingRequestForMessageReceivedOperation(kind: .allAttachmentsOfMessage(op: op1))
        await queueAndAwaitCompositionOfOneContextualOperation(op1: downloadOp)
        
        assert(downloadOp.isFinished && !downloadOp.isCancelled)
        
        return .receivedMessageCreated(attachmentsProcessingRequest: downloadOp.attachmentsProcessingRequest ?? .doNothing)

    }

    
    enum CreatePersistedMessageSentFromReceivedObvOwnedMessageResult {
        case sentMessageCreated(attachmentsProcessingRequest: ObvAttachmentsProcessingRequest)
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case sentMessageCreationFailure
    }

    /// This method *must* be called from ``PersistedDiscussionsUpdatesCoordinator.processReceivedObvOwnedMessage(_:completionHandler:)``.
    /// This method is called when a new (received) ObvOwnedMessage is available. This message can come from one of the two followings places:
    /// - Either it was serialized within the notification extension, and deserialized here,
    /// - Either it was received by the main app.
    /// In the first case, this method is called using `overridePreviousPersistedMessage` set to `false`: we check whether the message already exists in database (using the message uid from server) and, if this is the
    /// case, we do nothing. If the message does not exist, we create it. In the second case, `overridePreviousPersistedMessage` set to `true` and we override any existing persisted message. In other words, messages
    /// comming from the engine always superseed messages comming from  the notification extension.
    private func createPersistedMessageSentFromReceivedObvOwnedMessage(_ obvOwnedMessage: ObvOwnedMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?) async -> CreatePersistedMessageSentFromReceivedObvOwnedMessageResult {

        os_log("Call to createPersistedMessageSentFromReceivedObvOwnedMessage for obvOwnedMessage %{public}@", log: Self.log, type: .debug, obvOwnedMessage.messageIdentifierFromEngine.debugDescription)

        // Create a persisted message sent
        
        let op1 = CreatePersistedMessageSentFromReceivedObvOwnedMessageOperation(obvOwnedMessage: obvOwnedMessage,
                                                                                 messageJSON: messageJSON,
                                                                                 returnReceiptJSON: returnReceiptJSON)
        await queueAndAwaitCompositionOfOneContextualOperation(op1: op1)
        
        guard op1.isFinished && !op1.isCancelled else {
            assertionFailure()
            return .sentMessageCreationFailure
        }
        
        switch op1.result {
        case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
            return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
        case nil:
            assertionFailure()
            return .sentMessageCreationFailure
        case .sentMessageCreated:
            break
        }

        // If we reach this point, the message was properly created. We can determine the attachments to download now.

        let downloadOp = DetermineAttachmentsProcessingRequestForMessageSentOperation(kind: .allAttachmentsOfMessage(op: op1))
        await queueAndAwaitCompositionOfOneContextualOperation(op1: downloadOp)

        assert(downloadOp.isFinished && !downloadOp.isCancelled)

        return .sentMessageCreated(attachmentsProcessingRequest: downloadOp.attachmentsProcessingRequest ?? .doNothing)

    }

    
    private func logReasonOfCancelledOperations(_ operations: [OperationThatCanLogReasonForCancel]) {
        let cancelledOps = operations.filter({ $0.isCancelled })
        for op in cancelledOps {
            op.logReasonIfCancelled(log: Self.log)
        }
    }

}


fileprivate struct MessageIdentifierFromEngineAndOwnedCryptoId: Hashable {
    
    let messageIdentifierFromEngine: Data
    let ownedCryptoId: ObvCryptoId
    
}

// MARK: - ScreenCaptureDetectorDelegate

extension PersistedDiscussionsUpdatesCoordinator: ScreenCaptureDetectorDelegate {
    
    
    func screenCaptureOfSensitiveMessagesWasDetected(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
        processDectection(discussionPermanentID: discussionPermanentID)
    }
    
    func screenshotOfSensitiveMessagesWasDetected(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
        processDectection(discussionPermanentID: discussionPermanentID)
    }
    
    
    private func processDectection(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) {
        let op1 = ProcessDetectionThatSensitiveMessagesWereCapturedByOwnedIdentityOperation(discussionPermanentID: discussionPermanentID,
                                                                                            obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }
    
}



// MARK: - Internal utils

enum OperationKind {
    case contextual(op: Operation)
    case engineCall(op: Operation)
    var operation: Operation {
        switch self {
        case .contextual(let op):
            return op
        case .engineCall(let op):
            return op
        }
    }
}


extension [OperationKind] {
    
    /// Calls `self[n+1].addDependency(self[n])` for all operations in `self`. The first operation is not made dependent of any operation.
    func makeEachOperationDependentOnThePreceedingOne() {
        let operations = self.map { $0.operation }
        operations.makeEachOperationDependentOnThePreceedingOne()
    }

}


extension [Operation] {
    
    /// Calls `self[n+1].addDependency(self[n])` for all operations in `self`. The first operation is not made dependent of any operation.
    func makeEachOperationDependentOnThePreceedingOne() {
        guard self.count > 1 else { return } // Only one operation, no need to create a dependency
        for opIndex in 0..<self.count-1 {
            self[opIndex+1].addDependency(self[opIndex])
        }
    }
    
}


// MARK: - Helpers

//extension PersistedDiscussionsUpdatesCoordinator {
//    
//    private func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) -> CompositionOfOneContextualOperation<T> {
//        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
//        composedOp.completionBlock = { [weak composedOp] in
//            assert(composedOp != nil)
//            composedOp?.logReasonIfCancelled(log: Self.log)
//        }
//        return composedOp
//    }
//    
//    private func createCompositionOfTwoContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>) -> CompositionOfTwoContextualOperations<T1, T2> {
//        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
//        composedOp.completionBlock = { [weak composedOp] in
//            assert(composedOp != nil)
//            composedOp?.logReasonIfCancelled(log: Self.log)
//        }
//        return composedOp
//    }
//
//    private func createCompositionOfThreeContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType, T3: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, op3: ContextualOperationWithSpecificReasonForCancel<T3>) -> CompositionOfThreeContextualOperations<T1, T2, T3> {
//        let composedOp = CompositionOfThreeContextualOperations(op1: op1, op2: op2, op3: op3, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
//        composedOp.completionBlock = { [weak composedOp] in
//            assert(composedOp != nil)
//            composedOp?.logReasonIfCancelled(log: Self.log)
//        }
//        return composedOp
//    }
//
//    private func createCompositionOfFourContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType, T3: LocalizedErrorWithLogType, T4: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, op3: ContextualOperationWithSpecificReasonForCancel<T3>, op4: ContextualOperationWithSpecificReasonForCancel<T4>) -> CompositionOfFourContextualOperations<T1, T2, T3, T4> {
//        let composedOp = CompositionOfFourContextualOperations(op1: op1, op2: op2, op3: op3, op4: op4, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
//        composedOp.completionBlock = { [weak composedOp] in
//            assert(composedOp != nil)
//            composedOp?.logReasonIfCancelled(log: Self.log)
//        }
//        return composedOp
//    }
//
//}


// MARK: - NSManagedObjectContext utils

fileprivate extension NSManagedObjectContext {
    
    
    func deepRefresh(objectURI: URL, entityName: String) {
        guard let objectID = ObvStack.shared.managedObjectID(forURIRepresentation: objectURI) else { return }
        deepRefresh(objectID: objectID, entityName: entityName)
    }
    
    
    func deepRefresh(objectID: NSManagedObjectID, entityName: String) {
        assert(self.concurrencyType == .mainQueueConcurrencyType, "This method was implemented to refresh the view context")
        self.perform {
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: entityName)
            request.predicate = NSPredicate(withObjectID: objectID)
            request.fetchLimit = 1
            request.returnsObjectsAsFaults = false
            if let object = try? self.fetch(request).first {
                ObvStack.shared.viewContext.refresh(object, mergeChanges: true)
            }
        }
    }
    
}
