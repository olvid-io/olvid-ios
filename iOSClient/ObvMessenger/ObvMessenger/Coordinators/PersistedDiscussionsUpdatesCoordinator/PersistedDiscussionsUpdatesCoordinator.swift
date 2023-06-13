/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


final class PersistedDiscussionsUpdatesCoordinator {
    
    private let obvEngine: ObvEngine
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: PersistedDiscussionsUpdatesCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    private var kvoTokens = [NSKeyValueObservation]()
    private let coordinatorsQueue: OperationQueue
    private let queueForComposedOperations: OperationQueue
    private let queueForDispatchingOffTheMainThread = DispatchQueue(label: "PersistedDiscussionsUpdatesCoordinator internal queue for dispatching off the main thread")
    private let internalQueueForAttachmentsProgresses = OperationQueue.createSerialQueue(name: "Internal queue for progresses", qualityOfService: .default)
    private let queueForLongRunningConcurrentOperations: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.name = "PersistedDiscussionsUpdatesCoordinator queue for long running tasks"
        return queue
    }()

    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)
    private var screenCaptureDetector: ScreenCaptureDetector?

    init(obvEngine: ObvEngine, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue) {
        self.obvEngine = obvEngine
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
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
            deleteOrphanedExpirations()
            deleteOldOrOrphanedRemoteDeleteAndEditRequests()
            deleteOldOrOrphanedPendingReactions()
            cleanExpiredMuteNotificationsSetting()
            cleanOrphanedPersistedMessageTimestampedMetadata()
            synchronizeAllOneToOneDiscussionTitlesWithContactNameOperation()
            synchronizeDiscussionsIllustrativeMessageAndRefreshNumberOfNewMessages()
            Task {
                await regularlyUpdateFyleMessageJoinWithStatusProgresses()
            }
        }

        // The following bootstrap methods are always called, not only the first time the app appears on screen
        
        bootstrapMessagesDecryptedWithinNotificationExtension()
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
        
        // Internal notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observeNewDraftToSend() { [weak self] draftPermanentID in
                self?.processNewDraftToSendNotification(draftPermanentID: draftPermanentID)
            },
            ObvMessengerCoreDataNotification.observeNewPersistedObvContactDevice() { [weak self] (contactDeviceObjectID, _) in
                self?.sendAppropriateDiscussionSharedConfigurationsToContact(input: .contactDevice(contactDeviceObjectID: contactDeviceObjectID), sendSharedConfigOfOneToOneDiscussion: true)
                self?.processUnprocessedRecipientInfosThatCanNowBeProcessed()
            },
            ObvMessengerCoreDataNotification.observePersistedContactGroupHasUpdatedContactIdentities() { [weak self] (persistedContactGroupObjectID, insertedContacts, removedContacts) in
                self?.processPersistedContactGroupHasUpdatedContactIdentitiesNotification(persistedContactGroupObjectID: persistedContactGroupObjectID, insertedContacts: insertedContacts, removedContacts: removedContacts)
            },
            ObvMessengerCoreDataNotification.observePersistedMessageReceivedWasDeleted() { [weak self] (_, messageIdentifierFromEngine, ownedCryptoId, _, _) in
                self?.processPersistedMessageReceivedWasDeletedNotification(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserRequestedDeletionOfPersistedMessage() { [weak self] (ownedCryptoId, persistedMessageObjectID, deletionType) in
                self?.processUserRequestedDeletionOfPersistedMessageNotification(ownedCryptoId: ownedCryptoId, persistedMessageObjectID: persistedMessageObjectID, deletionType: deletionType)
            },
            ObvMessengerInternalNotification.observeUserRequestedDeletionOfPersistedDiscussion() { [weak self] (persistedDiscussionObjectID, deletionType, completionHandler) in
                self?.processUserRequestedDeletionOfPersistedDiscussion(persistedDiscussionObjectID: persistedDiscussionObjectID, deletionType: deletionType, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeMessagesAreNotNewAnymore() { [weak self] persistedMessageObjectIDs in
                self?.processMessagesAreNotNewAnymore(persistedMessageObjectIDs: persistedMessageObjectIDs)
            },
            ObvMessengerInternalNotification.observeNewObvMessageWasReceivedViaPushKitNotification { [weak self] (obvMessage) in
                self?.processNewObvMessageWasReceivedViaPushKitNotification(obvMessage: obvMessage)
            },
            ObvMessengerInternalNotification.observeNewWebRTCMessageToSend() { [weak self] (webrtcMessage, contactID, forStartingCall) in
                self?.processNewWebRTCMessageToSendNotification(webrtcMessage: webrtcMessage, contactID: contactID, forStartingCall: forStartingCall)
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
                    self?.userEnteredDiscussion(discussionPermanentID: currentDiscussionPermanentID)
                }
            },
            ObvMessengerInternalNotification.observeUserWantsToReadReceivedMessagesThatRequiresUserAction { [weak self] (persistedMessageObjectIDs) in
                self?.processUserWantsToReadReceivedMessagesThatRequiresUserActionNotification(persistedMessageObjectIDs: persistedMessageObjectIDs)
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
            ObvMessengerInternalNotification.observeUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration { [weak self] (persistedDiscussionObjectID, expirationJSON, ownedCryptoId) in
                self?.processUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(persistedDiscussionObjectID: persistedDiscussionObjectID, expirationJSON: expirationJSON, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerCoreDataNotification.observeAnOldDiscussionSharedConfigurationWasReceived { [weak self] (persistedDiscussionObjectID) in
                self?.processAnOldDiscussionSharedConfigurationWasReceivedNotification(persistedDiscussionObjectID: persistedDiscussionObjectID)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateDiscussionLocalConfiguration { [weak self] (value, localConfigurationObjectID) in
                self?.processUserWantsToUpdateDiscussionLocalConfigurationNotification(with: value, localConfigurationObjectID: localConfigurationObjectID)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateLocalConfigurationOfDiscussion { [weak self] (value, discussionPermanentID, completionHandler) in
                self?.processUserWantsToUpdateLocalConfigurationOfDiscussionNotification(with: value, discussionPermanentID: discussionPermanentID, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeApplyAllRetentionPoliciesNow { [weak self] (launchedByBackgroundTask, completionHandler) in
                self?.processApplyAllRetentionPoliciesNowNotification(launchedByBackgroundTask: launchedByBackgroundTask, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToSendEditedVersionOfSentMessage { [weak self] (sentMessageObjectID, newTextBody) in
                self?.processUserWantsToSendEditedVersionOfSentMessage(sentMessageObjectID: sentMessageObjectID, newTextBody: newTextBody)
            },
            ObvMessengerInternalNotification.observeUserWantsToMarkAllMessagesAsNotNewWithinDiscussion { [weak self] (persistedDiscussionObjectID, completionHandler) in
                self?.processUserWantsToMarkAllMessagesAsNotNewWithinDiscussionNotification(persistedDiscussionObjectID: persistedDiscussionObjectID, completionHandler: completionHandler)
            },
            ObvMessengerInternalNotification.observeUserWantsToRemoveDraftFyleJoin { [weak self] (draftFyleJoinObjectID) in
                self?.processUserWantsToRemoveDraftFyleJoinNotification(draftFyleJoinObjectID: draftFyleJoinObjectID)
            },
            ObvMessengerCoreDataNotification.observePersistedContactWasDeleted { [weak self ] _, _ in
                self?.processPersistedContactWasDeletedNotification()
            },
            NewSingleDiscussionNotification.observeInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty { [weak self] (discussionObjectID, markAsRead) in
                self?.processInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: discussionObjectID, markAsRead: markAsRead)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateReaction { [weak self] messageObjectID, emoji in
                self?.processUserWantsToUpdateReaction(messageObjectID: messageObjectID, emoji: emoji)
            },
            ObvMessengerInternalNotification.observeInsertDebugMessagesInAllExistingDiscussions { [weak self] in
                self?.processInsertDebugMessagesInAllExistingDiscussions()
            },
            ObvMessengerInternalNotification.observeCleanExpiredMuteNotficationsThatExpiredEarlierThanNow { [weak self] in
                self?.cleanExpiredMuteNotificationsSetting()
            },
            ObvMessengerInternalNotification.observeUserRepliedToReceivedMessageWithinTheNotificationExtension { [weak self] contactPermanentID, messageIdentifierFromEngine, textBody, completionHandler in
                self?.processUserRepliedToReceivedMessageWithinTheNotificationExtensionNotification(contactPermanentID: contactPermanentID, messageIdentifierFromEngine: messageIdentifierFromEngine, textBody: textBody, completionHandler: completionHandler)
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
            NewSingleDiscussionNotification.observeUserWantsToPauseDownloadReceivedFyleMessageJoinWithStatus { [weak self] joinObjectID in
                self?.processUserWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: joinObjectID)
            },
            ObvMessengerCoreDataNotification.observeADeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus { [weak self] (returnReceipt, contactCryptoId, ownedCryptoId, messageIdentifierFromEngine, attachmentNumber) in
                self?.processADeliveredReturnReceiptShouldBeSent(returnReceipt: returnReceipt, contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
            },
            ObvMessengerCoreDataNotification.observeADeliveredReturnReceiptShouldBeSentForPersistedMessageReceived { [weak self] returnReceipt, contactCryptoId, ownedCryptoId, messageIdentifierFromEngine in
                self?.processADeliveredReturnReceiptShouldBeSent(returnReceipt: returnReceipt, contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: nil)
            },
            ObvMessengerInternalNotification.observeTooManyWrongPasscodeAttemptsCausedLockOut { [weak self] in
                self?.processTooManyWrongPasscodeAttemptsCausedLockOut()
            },
            ObvMessengerCoreDataNotification.observePersistedObvOwnedIdentityWasDeleted { [weak self] in
                self?.processPersistedObvOwnedIdentityWasDeleted()
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
            ObvMessengerInternalNotification.observeUpdateNormalizedSearchKeyOnPersistedDiscussions { [weak self] ownedIdentity, completionHandler in
                self?.processUpdateNormalizedSearchKeyOnPersistedDiscussions(ownedIdentity: ownedIdentity, completionHandler: completionHandler)
            },
        ])
        
        // Internal VoIP notifications
        
        observationTokens.append(contentsOf: [
            VoIPNotification.observeReportCallEvent { [weak self] (callUUID, callReport, groupIdentifier, ownedCryptoId) in
                self?.processReportCallEvent(callUUID: callUUID, callReport: callReport, groupIdentifier: groupIdentifier, ownedCryptoId: ownedCryptoId)
            },
            VoIPNotification.observeCallHasBeenUpdated { [weak self] callUUID, updateKind in
                self?.processCallHasBeenUpdated(callUUID: callUUID, updateKind: updateKind)
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
        
        // ObvEngine Notifications
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeNewMessageReceived(within: NotificationCenter.default) { [weak self] (obvMessage, completionHandler) in
                self?.processNewMessageReceivedNotification(obvMessage: obvMessage, completionHandler: completionHandler)
            },
            ObvEngineNotificationNew.observeMessageWasAcknowledged(within: NotificationCenter.default) { [weak self] (ownedIdentity, messageIdentifierFromEngine, timestampFromServer, isAppMessageWithUserContent, isVoipMessage) in
                self?.processMessageWasAcknowledgedNotification(ownedIdentity: ownedIdentity, messageIdentifierFromEngine: messageIdentifierFromEngine, timestampFromServer: timestampFromServer, isAppMessageWithUserContent: isAppMessageWithUserContent, isVoipMessage: isVoipMessage)
            },
            ObvEngineNotificationNew.observeAttachmentWasAcknowledgedByServer(within: NotificationCenter.default) { [weak self] (ownedCryptoId, messageIdentifierFromEngine, attachmentNumber) in
                self?.processAttachmentWasAcknowledgedByServerNotification(ownedCryptoId: ownedCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
            },
            ObvEngineNotificationNew.observeAttachmentDownloadCancelledByServer(within: NotificationCenter.default) { [weak self] (obvAttachment) in
                self?.processAttachmentDownloadCancelledByServerNotification(obvAttachment: obvAttachment)
            },
            ObvEngineNotificationNew.observeCannotReturnAnyProgressForMessageAttachments(within: NotificationCenter.default) { [weak self] (messageIdentifierFromEngine) in
                self?.processCannotReturnAnyProgressForMessageAttachmentsNotification(messageIdentifierFromEngine: messageIdentifierFromEngine)
            },
            ObvEngineNotificationNew.observeAttachmentDownloaded(within: NotificationCenter.default) { [weak self] (obvAttachment) in
                self?.processAttachmentDownloadedNotification(obvAttachment: obvAttachment)
            },
            ObvEngineNotificationNew.observeAttachmentDownloadWasResumed(within: NotificationCenter.default) { [weak self] ownCryptoId, messageIdentifierFromEngine, attachmentNumber in
                self?.processAttachmentDownloadWasResumed(ownedCryptoId: ownCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
            },
            ObvEngineNotificationNew.observeAttachmentDownloadWasPaused(within: NotificationCenter.default) { [weak self] ownCryptoId, messageIdentifierFromEngine, attachmentNumber in
                self?.processAttachmentDownloadWasPaused(ownedCryptoId: ownCryptoId, messageIdentifierFromEngine: messageIdentifierFromEngine, attachmentNumber: attachmentNumber)
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
            ObvEngineNotificationNew.observeMessageExtendedPayloadAvailable(within: NotificationCenter.default) { [weak self] (obvMessage) in
                self?.processMessageExtendedPayloadAvailable(obvMessage: obvMessage)
            },
            ObvEngineNotificationNew.observeContactWasRevokedAsCompromisedWithinEngine(within: NotificationCenter.default) { [weak self] obvContactIdentity in
                self?.processContactWasRevokedAsCompromisedWithinEngine(obvContactIdentity: obvContactIdentity)
            },
            ObvEngineNotificationNew.observeNewUserDialogToPresent(within: NotificationCenter.default) { [weak self] obvDialog in
                self?.processNewUserDialogToPresent(obvDialog: obvDialog)
            },
            ObvEngineNotificationNew.observeAPersistedDialogWasDeleted(within: NotificationCenter.default) { [weak self] ownedCryptoId, uuid in
                self?.processAPersistedDialogWasDeleted(uuid: uuid, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerCoreDataNotification.observeAPersistedGroupV2MemberChangedFromPendingToNonPending { [weak self] contactObjectID in
                self?.sendAppropriateDiscussionSharedConfigurationsToContact(input: .contact(contactObjectID: contactObjectID), sendSharedConfigOfOneToOneDiscussion: false)
                self?.processUnprocessedRecipientInfosThatCanNowBeProcessed()
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
    
    
    private func deleteOldOrOrphanedRemoteDeleteAndEditRequests() {
        let op1 = DeleteOldOrOrphanedRemoteDeleteAndEditRequestsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }


    private func deleteOldOrOrphanedPendingReactions() {
        let op1 = DeleteOldOrOrphanedPendingReactionsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        coordinatorsQueue.addOperation(composedOp)
    }


    private func deleteOrphanedExpirations() {
        let op = DeleteOrphanedExpirationsOperation()
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        coordinatorsQueue.addOperation(op)
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
    private func bootstrapMessagesDecryptedWithinNotificationExtension() {
        
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
            processReceivedObvMessage(obvMessage, overridePreviousPersistedMessage: false, completionHandler: nil)
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
        let op1 = SynchronizeDiscussionsIllustrativeMessageOperation()
        let op2 = RefreshNumberOfNewMessagesForAllDiscussionsOperation()
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        self.coordinatorsQueue.addOperation(composedOp)
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
    private func processNewDraftToSendNotification(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>) {
        assert(OperationQueue.current != coordinatorsQueue)
        assert(!Thread.isMainThread)
        let op1 = CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation(draftPermanentID: draftPermanentID)
        let op2 = ComputeExtendedPayloadOperation(provider: op1)
        let op3 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, extendedPayloadProvider: op2, obvEngine: obvEngine)
        let op4 = MarkAllMessagesAsNotNewWithinDiscussionOperation(draftPermanentID: draftPermanentID)
        let composedOp = createCompositionOfFourContextualOperation(op1: op1, op2: op2, op3: op3, op4: op4)
        coordinatorsQueue.addOperation(composedOp)
        coordinatorsQueue.addOperation {
            guard !composedOp.isCancelled else {
                NewSingleDiscussionNotification.draftCouldNotBeSent(draftPermanentID: draftPermanentID)
                    .postOnDispatchQueue()
                assertionFailure()
                return
            }
        }
    }
    
    
    private func processInsertDebugMessagesInAllExistingDiscussions() {
#if DEBUG
        assert(OperationQueue.current != coordinatorsQueue)
        var objectIDs = [(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>)]()
        ObvStack.shared.performBackgroundTask { [weak self] context in
            guard let _self = self else { return }
            guard let discussions = try? PersistedDiscussion.getAllSortedByTimestampOfLastMessageForAllOwnedIdentities(within: context) else { assertionFailure(); return }
            objectIDs = discussions.map({ ($0.typedObjectID, $0.draft.objectPermanentID) })
            let numberOfMessagesToInsert = 100
            for objectID in objectIDs {
                for messageNumber in 0..<numberOfMessagesToInsert {
                    debugPrint("Message \(messageNumber) out of \(numberOfMessagesToInsert)")
                    if Bool.random() {
                        let op1 = CreateRandomDraftDebugOperation(discussionObjectID: objectID.discussionObjectID)
                        let op2 = CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation(draftPermanentID: objectID.draftPermanentID)
                        let op3 = MarkSentMessageAsDeliveredDebugOperation()
                        op3.addDependency(op2)
                        let composedOp = _self.createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
                        self?.coordinatorsQueue.addOperation(composedOp)
                        self?.coordinatorsQueue.addOperation({ guard !composedOp.isCancelled else { assertionFailure(); return } })
                    } else {
                        let op1 = CreateRandomMessageReceivedDebugOperation(discussionObjectID: objectID.discussionObjectID)
                        let composedOp = _self.createCompositionOfOneContextualOperation(op1: op1)
                        self?.coordinatorsQueue.addOperation(composedOp)
                        self?.coordinatorsQueue.addOperation({ guard !composedOp.isCancelled else { assertionFailure(); return } })
                    }
                }
            }
        }
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
                let op1 = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: messageSentPermanentID, extendedPayloadProvider: nil, obvEngine: obvEngine)
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
            for persistedDiscussionObjectID in op1.persistedDiscussionObjectIDs {
                let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(persistedDiscussionObjectID: persistedDiscussionObjectID.objectID, obvEngine: obvEngine)
                op.queuePriority = .low
                op.completionBlock = { if op.isCancelled { assertionFailure() } }
                self?.coordinatorsQueue.addOperation(op)
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
            let contactGroupIsOwned = contactGroup.category == .owned
            let groupDiscussion = contactGroup.discussion
            let discussionObjectID = groupDiscussion.objectID
            let contactGroupHasAtLeastOneRemoteContactDevice = contactGroup.hasAtLeastOneRemoteContactDevice()

            var operationsToQueue = [Operation]()
            
            if contactGroupHasAtLeastOneRemoteContactDevice {
                let sentMessages = groupDiscussion.messages.compactMap { $0 as? PersistedMessageSent }
                let objectIDOfUnprocessedMessages = sentMessages.filter({ $0.status == .unprocessed || $0.status == .processing }).map({ $0.objectPermanentID })
                let ops: [(ComputeExtendedPayloadOperation, SendUnprocessedPersistedMessageSentOperation)] = objectIDOfUnprocessedMessages.map({
                    let op1 = ComputeExtendedPayloadOperation(messageSentPermanentID: $0)
                    let op2 = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: $0, extendedPayloadProvider: op1, obvEngine: obvEngine)
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
                let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(persistedDiscussionObjectID: discussionObjectID, obvEngine: obvEngine)
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
    private func processPersistedMessageReceivedWasDeletedNotification(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId) {
        do {
            try obvEngine.cancelDownloadOfMessage(withIdentifier: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId)
        } catch {
            os_log("Could not cancel the download of a message that we just deleted from the app", log: Self.log, type: .fault)
            assertionFailure()
            return
        }
    }
    

    private func processUserRequestedDeletionOfPersistedMessageNotification(ownedCryptoId: ObvCryptoId, persistedMessageObjectID: NSManagedObjectID, deletionType: DeletionType) {
        
        var operationsToQueue = [Operation]()
        
        switch deletionType {
        case .local:
            break // We will do the work below
        case .global:
            let op = SendGlobalDeleteMessagesJSONOperation(persistedMessageObjectIDs: [persistedMessageObjectID], obvEngine: obvEngine)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(op)
        }
        
        do {
            let op1 = CancelUploadOrDownloadOfPersistedMessagesOperation(persistedMessageObjectIDs: [persistedMessageObjectID], obvEngine: obvEngine)
            let requester = RequesterOfMessageDeletion.ownedIdentity(ownedCryptoId: ownedCryptoId, deletionType: .local)
            let op2 = DeletePersistedMessagesOperation(persistedMessageObjectIDs: Set([persistedMessageObjectID]), requester: requester)
            let op3 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let op4 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfFourContextualOperation(op1: op1, op2: op2, op3: op3, op4: op4)
            operationsToQueue.append(composedOp)
        }
        
        do {
            let op = BlockOperation()
            op.completionBlock = {
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            }
            operationsToQueue.append(op)
        }

        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
        
    }
    
    
    private func processUserRequestedDeletionOfPersistedDiscussion(persistedDiscussionObjectID: NSManagedObjectID, deletionType: DeletionType, completionHandler: @escaping (Bool) -> Void) {
        
        ObvStack.shared.performBackgroundTask { [weak self] context in
            guard let discussion = try? PersistedDiscussion.get(objectID: persistedDiscussionObjectID, within: context) else {
                return
            }
            guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId else { return }
            self?.deletePersistedDiscussion(
                withObjectID: persistedDiscussionObjectID,
                requester: .ownedIdentity(ownedCryptoId: ownedCryptoId, deletionType: deletionType),
                completionHandler: completionHandler)
        }
        
    }
    
    
    /// This methods properly deletes a discussion. It is typically called when the user requests the deletion of all messages within a discussion. But it is also called when a contact performs a global delete of a discussion, in which case `requestedBy` is non `nil`.
    private func deletePersistedDiscussion(withObjectID persistedDiscussionObjectID: NSManagedObjectID, requester: RequesterOfMessageDeletion, completionHandler: @escaping (Bool) -> Void) {
        
        assert(OperationQueue.current != coordinatorsQueue)
        
        /*
         * If Alice sends us a message, then deletes the discussion, the following occurs:
         * 1. A user notification is received (and displayed), and a serialized version is saved, ready to be processed next time Olvid is launched
         * 2. We receive the delete request in the background and we arrive here.
         * 3. If we do not delete the serialized notifications, all the discussions messages included in these serialized notifications would appear.
         * So we need to delete these serialized notifications when a discussion is globally deleted. We actually do it even if the deletion is only local,
         * since there is no reason to have a serialized notification present after the app is launched.
         */
        cleanJsonMessagesSavedByNotificationExtension()
        
        var operationsToQueue = [Operation]()
        
        switch requester {
        case .contact:
            // We are performing a local deletion, request by a contact. We will do the work below
            break
        case .ownedIdentity(_, let deletionType):
            switch deletionType {
            case .local:
                break // We will do the work below
            case .global:
                let op = SendGlobalDeleteDiscussionJSONOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, obvEngine: obvEngine)
                op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
                operationsToQueue.append(op)
            }
        }
        
        do {
            let op1 = CancelUploadOrDownloadOfPersistedMessagesOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        
        let deleteAllPersistedMessagesWithinDiscussionOperation: DeleteAllPersistedMessagesWithinDiscussionOperation
        do {
            deleteAllPersistedMessagesWithinDiscussionOperation = DeleteAllPersistedMessagesWithinDiscussionOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, requester: requester)
            let composedOp = createCompositionOfOneContextualOperation(op1: deleteAllPersistedMessagesWithinDiscussionOperation)
            let currentCompletion = composedOp.completionBlock
            composedOp.completionBlock = {
                currentCompletion?()
                composedOp.logReasonIfCancelled(log: Self.log)
                DispatchQueue.main.async {
                    completionHandler(!composedOp.isCancelled)
                }
            }
            operationsToQueue.append(composedOp)
        }
        
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        
        do {
            let op = BlockOperation()
            op.completionBlock = {
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            }
            operationsToQueue.append(op)
        }
        
        // If the requester is a contact (meaning she requested to globally delete the discussion), we insert a discussionWasRemotelyWiped system message in the new discussion, but only if at least one message was deleted.

        switch requester {
        case .ownedIdentity:
            break
        case .contact(_, _, let messageUploadTimestampFromServer):
            let op = BlockOperation()
            op.completionBlock = { [weak self] in
                guard let _self = self else { return }
                assert(deleteAllPersistedMessagesWithinDiscussionOperation.isFinished)
                guard !deleteAllPersistedMessagesWithinDiscussionOperation.isCancelled else { return }
                let newDiscussionObjectID = deleteAllPersistedMessagesWithinDiscussionOperation.newDiscussionObjectID
                let atLeastOneIllustrativeMessageWasDeleted = deleteAllPersistedMessagesWithinDiscussionOperation.atLeastOneIllustrativeMessageWasDeleted
                let contactIdentityObjectID = deleteAllPersistedMessagesWithinDiscussionOperation.contactRequesterIdentityObjectID
                assert(newDiscussionObjectID != nil)
                assert(contactIdentityObjectID != nil)
                if let newDiscussionObjectID, let contactIdentityObjectID, atLeastOneIllustrativeMessageWasDeleted {
                    let op1 = InsertPersistedMessageSystemIntoDiscussionOperation(
                        persistedMessageSystemCategory: .discussionWasRemotelyWiped,
                        persistedDiscussionObjectID: newDiscussionObjectID,
                        optionalContactIdentityObjectID: contactIdentityObjectID, optionalCallLogItemObjectID: nil,
                        messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                    let composedOp = _self.createCompositionOfOneContextualOperation(op1: op1)
                    self?.coordinatorsQueue.addOperation(composedOp)
                }
            }
            operationsToQueue.append(op)
        }

        // We can now queue all operations
            
        guard !operationsToQueue.isEmpty else { return }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)

    }
    
    
    private func processMessagesAreNotNewAnymore(persistedMessageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessage>>) {
        assert(OperationQueue.current != coordinatorsQueue)
        let op1 = ProcessPersistedMessagesAsTheyTurnsNotNewOperation(persistedMessageObjectIDs: persistedMessageObjectIDs)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processNewObvMessageWasReceivedViaPushKitNotification(obvMessage: ObvMessage) {
        processReceivedObvMessage(obvMessage, overridePreviousPersistedMessage: false, completionHandler: nil)
    }
    
    
    private func processNewWebRTCMessageToSendNotification(webrtcMessage: WebRTCMessageJSON, contactID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, forStartingCall: Bool) {
        os_log("☎️ We received an observeNewWebRTCMessageToSend notification", log: Self.log, type: .info)
        let op1 = SendWebRTCMessageOperation(webrtcMessage: webrtcMessage, contactID: contactID, forStartingCall: forStartingCall, obvEngine: obvEngine, log: Self.log)
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
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = BlockOperation()
            op.completionBlock = {
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            }
            operationsToQueue.append(op)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    
    
    private func userEnteredDiscussion(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) {
        let op = AllowReadingOfAllMessagesReceivedThatRequireUserActionOperation(discussionPermanentID: discussionPermanentID)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        coordinatorsQueue.addOperation(op)
    }
    
    
    private func processUserWantsToReadReceivedMessagesThatRequiresUserActionNotification(persistedMessageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessageReceived>>) {
        let op = AllowReadingOfMessagesReceivedThatRequireUserActionOperation(persistedMessageReceivedObjectIDs: persistedMessageObjectIDs)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        coordinatorsQueue.addOperation(op)
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
    
    
    private func processAReadOncePersistedMessageSentWasSentNotification(persistedMessageSentPermanentID: ObvManagedObjectPermanentID<PersistedMessageSent>, persistedDiscussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) {
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
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = BlockOperation()
            op.completionBlock = {
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            }
            operationsToQueue.append(op)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    
    
    private func processUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(persistedDiscussionObjectID: NSManagedObjectID, expirationJSON: ExpirationJSON, ownedCryptoId: ObvCryptoId) {
        var operationsToQueue = [Operation]()
        do {
            let op = ReplaceDiscussionSharedExpirationConfigurationOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, expirationJSON: expirationJSON, ownedCryptoIdAsInitiator: ownedCryptoId)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(op)
        }
        do {
            let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, obvEngine: obvEngine)
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
                op.completionBlock = {
                    ObvDisplayableLogs.shared.log("DeleteMessagesWithExpiredTimeBasedRetentionOperation deleted \(op.numberOfDeletedMessages) messages")
                }
                operationsToQueue.append(logOp)
            }
        }
        do {
            let op = DeleteMessagesWithExpiredCountBasedRetentionOperation(restrictToDiscussionWithPermanentID: nil)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(op)
        }
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = BlockOperation()
            op.completionBlock = {
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
                let oneOperationCancelled = operationsToQueue.reduce(false) { $0 || $1.isCancelled }
                let success = !oneOperationCancelled
                completionHandler(success)
            }
            operationsToQueue.append(op)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    
    
    private func processAnOldDiscussionSharedConfigurationWasReceivedNotification(persistedDiscussionObjectID: NSManagedObjectID) {
        let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(persistedDiscussionObjectID: persistedDiscussionObjectID, obvEngine: obvEngine)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        coordinatorsQueue.addOperation(op)
    }
    
    
    private func processUserWantsToSendEditedVersionOfSentMessage(sentMessageObjectID: NSManagedObjectID, newTextBody: String) {
        let op1 = EditTextBodyOfSentMessageOperation(persistedSentMessageObjectID: sentMessageObjectID, newTextBody: newTextBody)
        let op2 = SendUpdateMessageJSONOperation(persistedSentMessageObjectID: sentMessageObjectID, obvEngine: obvEngine)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processUserWantsToUpdateReaction(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, emoji: String?) {
        let op1 = UpdateReactionsOfMessageOperation(emoji: emoji, messageObjectID: messageObjectID)
        let op2 = SendReactionJSONOperation(messageObjectID: messageObjectID, obvEngine: obvEngine, emoji: emoji)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processUserWantsToMarkAllMessagesAsNotNewWithinDiscussionNotification(persistedDiscussionObjectID: NSManagedObjectID, completionHandler: @escaping (Bool) -> Void) {
        os_log("Call to processUserWantsToMarkAllMessagesAsNotNewWithinDiscussionNotification for discussion %{public}@", log: Self.log, type: .debug, persistedDiscussionObjectID.debugDescription)
        var operationsToQueue = [Operation]()
        do {
            os_log("Creating a MarkAllMessagesAsNotNewWithinDiscussionOperation for discussion %{public}@", log: Self.log, type: .debug, persistedDiscussionObjectID.debugDescription)
            let op1 = MarkAllMessagesAsNotNewWithinDiscussionOperation(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>(objectID: persistedDiscussionObjectID) )
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = BlockOperation()
            op.completionBlock = {
                DispatchQueue.main.async { completionHandler(true) }
            }
            operationsToQueue.append(op)
        }
        // Since the operation were user initiated, we increase their priority and quality of service
        operationsToQueue.forEach { $0.queuePriority = .veryHigh }
        operationsToQueue.forEach { $0.qualityOfService = .userInteractive }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    
    
    private func processUserWantsToRemoveDraftFyleJoinNotification(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) {
        var operationsToQueue = [Operation]()
        do {
            let op = DeleteDraftFyleJoinOperation(draftFyleJoinObjectID: draftFyleJoinObjectID)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(op)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = BlockOperation()
            op.completionBlock = {
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            }
            operationsToQueue.append(op)
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
        if #available(iOS 15, *) {
            CompositionViewFreezeManager.shared.newProgressToAddForTrackingFreeze(draftPermanentID: draftPermanentID, progress: progress)
        }
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

    private func processUserWantsToDeleteAllAttachmentsToDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        
        var operationsToQueue = [Operation]()
        do {
            let op1 = DeleteAllDraftFyleJoinOfDraftOperation(draftObjectID: draftObjectID)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        
        do {
            let op = BlockOperation()
            op.completionBlock = {
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            }
            operationsToQueue.append(op)
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
        let op1 = UpdateDiscussionLocalConfigurationOperation(value: value, localConfigurationObjectID: localConfigurationObjectID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processUserWantsToUpdateLocalConfigurationOfDiscussionNotification(with value: PersistedDiscussionLocalConfigurationValue, discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, completionHandler: @escaping () -> Void) {
        let op1 = UpdateDiscussionLocalConfigurationOperation(value: value, discussionPermanentID: discussionPermanentID)
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
    
    private func processNewMessageReceivedNotification(obvMessage: ObvMessage, completionHandler: @escaping (Set<ObvAttachment>) -> Void) {
        os_log("🧦 We received a NewMessageReceived notification", log: Self.log, type: .debug)

        let attachmentsToDownloadAsap = Set(obvMessage.attachments.filter {
            // A negative maxAttachmentSizeForAutomaticDownload means "unlimited"
            ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload < 0 || $0.totalUnitCount < ObvMessengerSettings.Downloads.maxAttachmentSizeForAutomaticDownload
        })
        let localCompletionHandler = {
            completionHandler(attachmentsToDownloadAsap)
        }

        processReceivedObvMessage(obvMessage, overridePreviousPersistedMessage: true, completionHandler: localCompletionHandler)
        
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

    
    private func processAttachmentDownloadCancelledByServerNotification(obvAttachment: ObvAttachment) {
        os_log("We received an AttachmentDownloadCancelledByServer notification", log: Self.log, type: .debug)
        let obvEngine = self.obvEngine
        var operationsToQueue = [Operation]()
        let composedOp: CompositionOfOneContextualOperation<ProcessFyleWithinDownloadingAttachmentOperationReasonForCancel>
        do {
            let op1 = ProcessFyleWithinDownloadingAttachmentOperation(obvAttachment: obvAttachment, newProgress: nil, obvEngine: obvEngine)
            composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = BlockOperation()
            op.completionBlock = {
                assert(composedOp.isFinished)
                guard !composedOp.isCancelled else { return }
                // If we reach this point, we have successfully processed the fyle within the attachment. We can ask the engine to delete the attachment
                do {
                    try obvEngine.deleteObvAttachment(attachmentNumber: obvAttachment.number,
                                                      ofMessageWithIdentifier: obvAttachment.messageIdentifier,
                                                      ownedCryptoId: obvAttachment.ownedCryptoId)
                } catch {
                    os_log("The engine failed to delete the attachment", log: Self.log, type: .fault)
                }
            }
            operationsToQueue.append(op)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }

    
    /// This notification is typically sent when we request progress for attachments that cannot be found anymore within the engine's inbox.
    /// Typical if the message/attachments were deleted by the sender before they were completely sent.
    private func processCannotReturnAnyProgressForMessageAttachmentsNotification(messageIdentifierFromEngine: Data) {
        let op = MarkAllIncompleteReceivedFyleMessageJoinWithStatusAsCancelledByServer(messageIdentifierFromEngine: messageIdentifierFromEngine)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        coordinatorsQueue.addOperation(op)
    }

    
    private func processAttachmentDownloadedNotification(obvAttachment: ObvAttachment) {
        let obvEngine = self.obvEngine
        var operationsToQueue = [Operation]()
        let composedOp: CompositionOfOneContextualOperation<ProcessFyleWithinDownloadingAttachmentOperationReasonForCancel>
        do {
            let op1 = ProcessFyleWithinDownloadingAttachmentOperation(obvAttachment: obvAttachment, newProgress: nil, obvEngine: obvEngine)
            composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = BlockOperation()
            op.completionBlock = {
                assert(composedOp.isFinished)
                guard !composedOp.isCancelled else { return }
                // If we reach this point, we have successfully processed the fyle within the attachment. We can ask the engine to delete the attachment
                do {
                    try obvEngine.deleteObvAttachment(attachmentNumber: obvAttachment.number,
                                                      ofMessageWithIdentifier: obvAttachment.messageIdentifier,
                                                      ownedCryptoId: obvAttachment.ownedCryptoId)
                } catch {
                    os_log("The engine failed to delete the attachment we just persisted", log: Self.log, type: .fault)
                    assertionFailure()
                }
            }
            operationsToQueue.append(op)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
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

    
    private func processNewObvReturnReceiptToProcessNotification(obvReturnReceipt: ObvReturnReceipt, retryNumber: Int = 0) {
        
        guard retryNumber < 10 else {
            assertionFailure()
            return
        }
        
        let obvEngine = self.obvEngine
        
        var operationsToQueue = [Operation]()
        
        let op1 = ProcessObvReturnReceiptOperation(obvReturnReceipt: obvReturnReceipt, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.assertionFailureInCaseOfFault = false // This operation often fails in the simulator, when switch from the share extension back to the app. We have a retry feature just for that reason.
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
                case .unknownReason:
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

    
    /// Called when the engine received successfully downloaded and decrypted an extended payload for an application message.
    private func processMessageExtendedPayloadAvailable(obvMessage: ObvMessage) {
        let op1 = ExtractReceivedExtendedPayloadOperation(obvMessage: obvMessage)
        let op2 = SaveReceivedExtendedPayloadOperation(extractReceivedExtendedPayloadOp: op1)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func processContactWasRevokedAsCompromisedWithinEngine(obvContactIdentity: ObvContactIdentity) {
        // When the engine informs us that a contact has been revoked as compromised, we insert the appropriate system message within the discussion
        ObvStack.shared.performBackgroundTask { [weak self] context in
            guard let _self = self else { return }
            let contact: PersistedObvContactIdentity
            do {
                guard let _contact = try PersistedObvContactIdentity.get(persisted: obvContactIdentity, whereOneToOneStatusIs: .any, within: context) else { assertionFailure(); return }
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
        let op1 = ProcessObvDialogOperation(obvDialog: obvDialog, obvEngine: obvEngine)
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

    
    private func processUserRepliedToReceivedMessageWithinTheNotificationExtensionNotification(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>, messageIdentifierFromEngine: Data, textBody: String, completionHandler: @escaping () -> Void) {
        // This call will add the received message decrypted by the notification extension into the database to be sure that we will be able to reply to this message.
        bootstrapMessagesDecryptedWithinNotificationExtension()

        let op1 = CreateUnprocessedReplyToPersistedMessageSentFromBodyOperation(contactPermanentID: contactPermanentID, messageIdentifierFromEngine: messageIdentifierFromEngine, textBody: textBody)
        let op2 = MarkAsReadReceivedMessageOperation(contactPermanentID: contactPermanentID, messageIdentifierFromEngine: messageIdentifierFromEngine)
        let op3 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, extendedPayloadProvider: nil, obvEngine: obvEngine) {
            DispatchQueue.main.async {
                completionHandler()
            }
        }
        let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
        let currentCompletion = composedOp.completionBlock
        composedOp.completionBlock = {
            currentCompletion?()
            if composedOp.isCancelled {
                // One of op1, op2 or op3 cancelled. We call the completion handler
                DispatchQueue.main.async {
                    completionHandler()
                }
            }
        }
        coordinatorsQueue.addOperation(composedOp)
    }


    private func processUserRepliedToMissedCallWithinTheNotificationExtensionNotification(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, textBody: String, completionHandler: @escaping () -> Void) {

        let op1 = CreateUnprocessedPersistedMessageSentFromBodyOperation(discussionPermanentID: discussionPermanentID, textBody: textBody)
        let op2 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, extendedPayloadProvider: nil, obvEngine: obvEngine) {
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
        bootstrapMessagesDecryptedWithinNotificationExtension()

        let op1 = MarkAsReadReceivedMessageOperation(contactPermanentID: contactPermanentID, messageIdentifierFromEngine: messageIdentifierFromEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        let currentCompletion = composedOp.completionBlock
        
        composedOp.completionBlock = {
            
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
                
                // Recompute all badges
                
                ObvMessengerInternalNotification.needToRecomputeAllBadges { _ in
                    DispatchQueue.main.async {
                        completionHandler()
                    }
                }.postOnDispatchQueue()
                
            }
        }
        
        coordinatorsQueue.addOperation(composedOp)
        
    }
    
    
    private func processUserWantsToWipeFyleMessageJoinWithStatus(ownedCryptoId: ObvCryptoId, objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>) {
        var operationsToQueue = [Operation]()
        do {
            let requester = RequesterOfMessageDeletion.ownedIdentity(ownedCryptoId: ownedCryptoId, deletionType: .local)
            let op1 = WipeFyleMessageJoinsWithStatusOperation(joinObjectIDs: objectIDs, requester: requester)
            let op2 = DeletePersistedMessagesOperation(operationProvidingPersistedMessageObjectIDsToDelete: op1)
            let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
            operationsToQueue.append(composedOp)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = BlockOperation()
            op.completionBlock = {
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            }
            operationsToQueue.append(op)
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
    }
    

    private func processUserWantsToForwardMessage(messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, discussionPermanentIDs: Set<ObvManagedObjectPermanentID<PersistedDiscussion>>) {
        for discussionPermanentID in discussionPermanentIDs {
            let op1 = CreateUnprocessedForwardPersistedMessageSentFromMessageOperation(messagePermanentID: messagePermanentID, discussionPermanentID: discussionPermanentID)
            let op2 = ComputeExtendedPayloadOperation(provider: op1)
            let op3 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, extendedPayloadProvider: op2, obvEngine: obvEngine)
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

    
    private func processUserWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {
        let op1 = ResumeOrPauseAttachmentDownloadOperation(receivedJoinObjectID: receivedJoinObjectID, resumeOrPause: .pause, obvEngine: obvEngine)
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
        var operationsToQueue = [Operation]()
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op1 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op1 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueue.append(composedOp)
        }
        do {
            let op = BlockOperation()
            op.completionBlock = { [weak self] in
                self?.trashOrphanedFilesFoundInTheFylesDirectory()
                self?.deleteOrphanedExpirations()
                self?.deleteOldOrOrphanedRemoteDeleteAndEditRequests()
                self?.deleteOldOrOrphanedPendingReactions()
                self?.cleanExpiredMuteNotificationsSetting()
                self?.cleanOrphanedPersistedMessageTimestampedMetadata()
                ObvMessengerInternalNotification.trashShouldBeEmptied
                    .postOnDispatchQueue()
            }
            operationsToQueue.append(op)
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
        let op1 = ReorderDiscussionsOperation(discussionObjectIDs: discussionObjectIds, ownedIdentity: ownedIdentity)
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
        guard messageReceived.discussion.localConfiguration.doSendReadReceipt ?? ObvMessengerSettings.Discussions.doSendReadReceipt else { return }
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
        guard messageReceived.discussion.localConfiguration.doSendReadReceipt ?? ObvMessengerSettings.Discussions.doSendReadReceipt else { return }
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

    
    private func processReceivedObvMessage(_ obvMessage: ObvMessage, overridePreviousPersistedMessage: Bool, completionHandler: (() -> Void)?) {

        assert(OperationQueue.current != coordinatorsQueue)

        os_log("Call to processReceivedObvMessage", log: Self.log, type: .debug)
        
        let persistedItemJSON: PersistedItemJSON
        do {
            persistedItemJSON = try PersistedItemJSON.jsonDecode(obvMessage.messagePayload)
        } catch {
            os_log("Could not decode the message payload", log: Self.log, type: .error)
            completionHandler?()
            assertionFailure()
            return
        }
        
        let completionHandlerManager = ManagerOfCompletionHandlerFromEngineOnMessageReception(completionHandler: completionHandler)

        // Case #1: The ObvMessage contains a WebRTC signaling message
        
        if let webrtcMessage = persistedItemJSON.webrtcMessage {
            
            os_log("☎️ The message is a WebRTC signaling message", log: Self.log, type: .debug)
            
            completionHandlerManager.addExpectation(.webRTCSignalingMessage)
            
            ObvStack.shared.performBackgroundTask { (context) in
                guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: context) else {
                    os_log("☎️ Could not find persisted contact associated with received webrtc message", log: Self.log, type: .fault)
                    completionHandlerManager.removeExpectation(.webRTCSignalingMessage, processingWasASuccess: false)
                    return
                }
                let contactId = OlvidUserId.known(contactObjectID: persistedContactIdentity.typedObjectID,
                                                  ownCryptoId: obvMessage.fromContactIdentity.ownedIdentity.cryptoId,
                                                  remoteCryptoId: obvMessage.fromContactIdentity.cryptoId,
                                                  displayName: persistedContactIdentity.fullDisplayName)
                ObvMessengerInternalNotification.newWebRTCMessageWasReceived(webrtcMessage: webrtcMessage,
                                                                             contactId: contactId,
                                                                             messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                                                             messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine)
                    .postOnDispatchQueue()
                completionHandlerManager.removeExpectation(.webRTCSignalingMessage, processingWasASuccess: true)
            }
        }
        
        // Case #2: The ObvMessage contains a message
        
        if let messageJSON = persistedItemJSON.message {
            
            os_log("The message is an ObvMessage", log: Self.log, type: .debug)

            completionHandlerManager.addExpectation(.standardMessage)

            let returnReceiptJSON = persistedItemJSON.returnReceipt

            createPersistedMessageReceivedFromReceivedObvMessage(
                obvMessage,
                messageJSON: messageJSON,
                overridePreviousPersistedMessage: overridePreviousPersistedMessage,
                returnReceiptJSON: returnReceiptJSON,
                completionHandlerManager: completionHandlerManager)
            
        }
        
        // Case #3: The ObvMessage contains a shared configuration for a discussion
        
        if let discussionSharedConfiguration = persistedItemJSON.discussionSharedConfiguration {
            
            os_log("The message is shared discussion configuration", log: Self.log, type: .debug)

            completionHandlerManager.addExpectation(.sharedConfigurationForDiscussion)

            updateSharedConfigurationOfPersistedDiscussion(
                using: discussionSharedConfiguration,
                fromContactIdentity: obvMessage.fromContactIdentity,
                messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                completionHandlerManager: completionHandlerManager)
            
        }

        // Case #4: The ObvMessage contains a JSON message indicating that some messages should be globally deleted in a discussion
        
        if let deleteMessagesJSON = persistedItemJSON.deleteMessagesJSON {
            os_log("The message is a delete message JSON", log: Self.log, type: .debug)
            completionHandlerManager.addExpectation(.globalMessageDeletion)
            let op1 = WipeMessagesOperation(messagesToDelete: deleteMessagesJSON.messagesToDelete,
                                            groupIdentifier: deleteMessagesJSON.groupIdentifier,
                                            requester: obvMessage.fromContactIdentity,
                                            messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                            saveRequestIfMessageCannotBeFound: true)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            let currentCompletion = composedOp.completionBlock
            composedOp.completionBlock = {
                currentCompletion?()
                completionHandlerManager.removeExpectation(.globalMessageDeletion, processingWasASuccess: !composedOp.isCancelled)
            }
            coordinatorsQueue.addOperation(composedOp)
        }
        
        // Case #5: The ObvMessage contains a JSON message indicating that a discussion should be globally deleted

        if let deleteDiscussionJSON = persistedItemJSON.deleteDiscussionJSON {
            os_log("The message is a delete discussion JSON", log: Self.log, type: .debug)
            completionHandlerManager.addExpectation(.globalDiscussionDeletion)
            let op1 = GetAppropriateActiveDiscussionOperation(contact: obvMessage.fromContactIdentity, groupIdentifier: deleteDiscussionJSON.groupIdentifier)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            let currentCompletion = composedOp.completionBlock
            composedOp.completionBlock = { [weak self] in
                currentCompletion?()
                assert(op1.isFinished)
                assert(op1.persistedDiscussionObjectID != nil || op1.isCancelled)
                guard let persistedDiscussionObjectID = op1.persistedDiscussionObjectID else { return }
                // An appropriate discussion to delete was found, we can delete it
                let requester = RequesterOfMessageDeletion.contact(ownedCryptoId: obvMessage.fromContactIdentity.ownedIdentity.cryptoId,
                                                                   contactCryptoId: obvMessage.fromContactIdentity.cryptoId,
                                                                   messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
                self?.deletePersistedDiscussion(withObjectID: persistedDiscussionObjectID.objectID,
                                                requester: requester,
                                                completionHandler: { success in
                    completionHandlerManager.removeExpectation(.globalDiscussionDeletion, processingWasASuccess: success)
                })
            }
            coordinatorsQueue.addOperation(composedOp)
        }
        
        // Case #6: The ObvMessage contains a JSON message indicating that a received message has been edited by the original sender

        if let updateMessageJSON = persistedItemJSON.updateMessageJSON {
            os_log("The message is an update message JSON", log: Self.log, type: .debug)
            completionHandlerManager.addExpectation(.messageEdition)
            let op1 = EditTextBodyOfReceivedMessageOperation(newTextBody: updateMessageJSON.newTextBody,
                                                             requester: obvMessage.fromContactIdentity,
                                                             groupIdentifier: updateMessageJSON.groupIdentifier,
                                                             receivedMessageToEdit: updateMessageJSON.messageToEdit,
                                                             messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                                             saveRequestIfMessageCannotBeFound: true,
                                                             newMentions: updateMessageJSON.userMentions)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            let currentCompletion = composedOp.completionBlock
            composedOp.completionBlock = {
                currentCompletion?()
                completionHandlerManager.removeExpectation(.messageEdition, processingWasASuccess: !composedOp.isCancelled)
            }
            coordinatorsQueue.addOperation(composedOp)
        }

        // Case #7: The ObvMessage contains a JSON message indicating that a reaction has been add by a contact

        if let reactionJSON = persistedItemJSON.reactionJSON {
            completionHandlerManager.addExpectation(.newReaction)
            let op1 = UpdateReactionsOfMessageOperation(contactIdentity: obvMessage.fromContactIdentity,
                                                        reactionJSON: reactionJSON,
                                                        reactionTimestamp: obvMessage.messageUploadTimestampFromServer,
                                                        addPendingReactionIfMessageCannotBeFound: true)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            let currentCompletion = composedOp.completionBlock
            composedOp.completionBlock = {
                currentCompletion?()
                completionHandlerManager.removeExpectation(.newReaction, processingWasASuccess: !composedOp.isCancelled)
            }
            coordinatorsQueue.addOperation(composedOp)
        }
        
        // Case #8: The ObvMessage contains a JSON message containing a request for a group v2 discussion shared settings
        
        if let querySharedSettingsJSON = persistedItemJSON.querySharedSettingsJSON {
            completionHandlerManager.addExpectation(.groupv2DiscussionSharedSettings)
            let op1 = RespondToQuerySharedSettingsOperation(fromContactIdentity: obvMessage.fromContactIdentity,
                                                            querySharedSettingsJSON: querySharedSettingsJSON)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            let currentCompletion = composedOp.completionBlock
            composedOp.completionBlock = {
                currentCompletion?()
                completionHandlerManager.removeExpectation(.groupv2DiscussionSharedSettings, processingWasASuccess: !composedOp.isCancelled)
            }
            coordinatorsQueue.addOperation(composedOp)
        }
        
        // Case #9: The ObvMessage contains a JSON message indicating that a contact did take a screen capture of sensitive content
        
        if let screenCaptureDetectionJSON = persistedItemJSON.screenCaptureDetectionJSON {
            completionHandlerManager.addExpectation(.screenCapture)
            let op1 = ProcessDetectionThatSensitiveMessagesWereCapturedByContactOperation(contactIdentity: obvMessage.fromContactIdentity,
                                                                                          screenCaptureDetectionJSON: screenCaptureDetectionJSON)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            let currentCompletion = composedOp.completionBlock
            composedOp.completionBlock = {
                currentCompletion?()
                completionHandlerManager.removeExpectation(.screenCapture, processingWasASuccess: !composedOp.isCancelled)
            }
            coordinatorsQueue.addOperation(composedOp)
        }
        
        // The inbox message has been processed, we can call the completion handler.
        // This completion handler is typically used to mark the message from deletion within the FetchManager in the engine.
        
        completionHandlerManager.callCompletionHandlerAsap()
        
    }
    
    
    /// This method is called when receiving a message from the engine that contains a shared configuration for a persisted discussion (typically, either one2one, or a group discussion owned by the sender of this message).
    /// We use this new configuration to update ours.
    private func updateSharedConfigurationOfPersistedDiscussion(using discussionSharedConfiguration: DiscussionSharedConfigurationJSON, fromContactIdentity: ObvContactIdentity, messageUploadTimestampFromServer: Date, completionHandlerManager: ManagerOfCompletionHandlerFromEngineOnMessageReception) {
        let op1 = MergeDiscussionSharedExpirationConfigurationOperation(
            discussionSharedConfiguration: discussionSharedConfiguration,
            fromContactIdentity: fromContactIdentity,
            messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        let currentCompletion = composedOp.completionBlock
        composedOp.completionBlock = {
            currentCompletion?()
            completionHandlerManager.removeExpectation(.sharedConfigurationForDiscussion, processingWasASuccess: !composedOp.isCancelled )
        }
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func processReportCallEvent(callUUID: UUID, callReport: CallReport, groupIdentifier: GroupIdentifierBasedOnObjectID?, ownedCryptoId: ObvCryptoId) {
        let op = ReportCallEventOperation(callUUID: callUUID,
                                          callReport: callReport,
                                          groupIdentifier: groupIdentifier,
                                          ownedCryptoId: ownedCryptoId)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        self.coordinatorsQueue.addOperation(op)
    }

    
    private func processCallHasBeenUpdated(callUUID: UUID, updateKind: CallUpdateKind) {
        guard case .state(let newState) = updateKind else { return }
        guard newState.isFinalState else { return }
        let op = ReportEndCallOperation(callUUID: callUUID)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        self.coordinatorsQueue.addOperation(op)
    }
    
    
    private func processInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) {
        assert(OperationQueue.current != coordinatorsQueue)
        let op1 = InsertEndToEndEncryptedSystemMessageIfCurrentDiscussionIsEmptyOperation(discussionObjectID: discussionObjectID, markAsRead: markAsRead)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    
    /// This method *must* be called from `processReceivedObvMessage(...)`.
    /// This method is called when a new (received) ObvMessage is available. This message can come from one of the two followings places:
    /// - Either it was serialized within the notification extension, and deserialized here,
    /// - Either it was received by the main app.
    /// In the first case, this method is called using `overridePreviousPersistedMessage` set to `false`: we check whether the message already exists in database (using the message uid from server) and, if this is the
    /// case, we do nothing. If the message does not exist, we create it. In the second case, `overridePreviousPersistedMessage` set to `true` and we override any existing persisted message. In other words, messages
    /// comming from the engine always superseed messages comming from  the notification extension.
    private func createPersistedMessageReceivedFromReceivedObvMessage(_ obvMessage: ObvMessage, messageJSON: MessageJSON, overridePreviousPersistedMessage: Bool, returnReceiptJSON: ReturnReceiptJSON?, completionHandlerManager: ManagerOfCompletionHandlerFromEngineOnMessageReception) {

        ObvDisplayableLogs.shared.log("🍤 Starting createPersistedMessageReceivedFromReceivedObvMessage")
        defer { ObvDisplayableLogs.shared.log("🍤 Ending createPersistedMessageReceivedFromReceivedObvMessage") }

        assert(OperationQueue.current != coordinatorsQueue)

        os_log("Call to createPersistedMessageReceivedFromReceivedObvMessage for obvMessage %{public}@", log: Self.log, type: .debug, obvMessage.messageIdentifierFromEngine.debugDescription)

        // Create a persisted message received
        let op1 = CreatePersistedMessageReceivedFromReceivedObvMessageOperation(obvMessage: obvMessage,
                                                                                messageJSON: messageJSON,
                                                                                overridePreviousPersistedMessage: overridePreviousPersistedMessage,
                                                                                returnReceiptJSON: returnReceiptJSON,
                                                                                obvEngine: obvEngine)
        // Check for a previously received delete or edit request and apply it
        let op2 = ApplyExistingRemoteDeleteAndEditRequestOperation(obvMessage: obvMessage, messageJSON: messageJSON)
        // Look for a previously received reaction for that message. If found, apply it.
        let op3 = ApplyPendingReactionsOperation(obvMessage: obvMessage, messageJSON: messageJSON)

        let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
        let currentCompletion = composedOp.completionBlock

        composedOp.completionBlock = {
            currentCompletion?()
            completionHandlerManager.removeExpectation(.standardMessage, processingWasASuccess: !composedOp.isCancelled )
        }
        self.coordinatorsQueue.addOperation(composedOp)

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

extension [Operation] {
    
    /// Calls `self[n+1].addDependency(self[n])` for all operations in `self`. The first operation is not made dependent of any operation.
    func makeEachOperationDependentOnThePreceedingOne() {
        guard self.count > 0 else { assertionFailure(); return }
        guard self.count > 1 else { return } // Only one operation, no need to create a dependency
        for opIndex in 0..<self.count-1 {
            self[opIndex+1].addDependency(self[opIndex])
        }
    }
    
}



// MARK: - ManagerOfCompletionHandlerFromEngineOnMessageReception

/// This actor allows to manage completion handlers received from the engine when receiving a message.
/// It makes it possible to call the completion handler only when all operations processing the message are finished.
///
/// Each expectation corresponds to a kind of internal JSON we can find in a received `ObvMessage`.
private final class ManagerOfCompletionHandlerFromEngineOnMessageReception {
    
    enum Expectation {
        case webRTCSignalingMessage
        case standardMessage
        case sharedConfigurationForDiscussion
        case globalMessageDeletion
        case globalDiscussionDeletion
        case messageEdition
        case newReaction
        case groupv2DiscussionSharedSettings
        case screenCapture
    }
    
    // Queue shared among `ManagerOfCompletionHandlerFromEngineOnMessageReception` instances
    private static let internalQueue = OperationQueue.createSerialQueue(name: "ManagerOfCompletionHandlerFromEngineOnMessageReception internal queue", qualityOfService: .default)
    
    private let completionHandler: (() -> Void)?
    private var expectations = Set<Expectation>()
    private var callCompletionHandlerIfExpectationsIsEmpty = false
    
    init(completionHandler: (() -> Void)?) {
        self.completionHandler = completionHandler
    }
    
    deinit {
        debugPrint("ManagerOfCompletionHandlerFromEngineOnMessageReception deinit")
    }
        
    func addExpectation(_ expectation: Expectation) {
        Self.internalQueue.addOperation { [weak self] in
            self?.expectations.insert(expectation)
        }
    }
    
    func removeExpectation(_ expectation: Expectation, processingWasASuccess: Bool) {
        // We keep a local strong reference to self
        // This allows to make sure self is not deallocated during the execution of the operation
        let _self = self
        Self.internalQueue.addOperation {
            assert(processingWasASuccess == true)
            _self.expectations.remove(expectation)
            if _self.callCompletionHandlerIfExpectationsIsEmpty == true && _self.expectations.isEmpty == true, let completionHandler = _self.completionHandler {
                Task { completionHandler() }
            }
        }
    }
    
    func callCompletionHandlerAsap() {
        let _self = self
        // We keep a local strong reference to self
        // This allows to make sure self is not deallocated during the execution of the operation
        Self.internalQueue.addOperation {
            assert(_self.callCompletionHandlerIfExpectationsIsEmpty == false)
            _self.callCompletionHandlerIfExpectationsIsEmpty = true
            if _self.expectations.isEmpty == true, let completionHandler = _self.completionHandler {
                Task { completionHandler() }
            }
        }
    }
    
}


// MARK: - Helpers

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) -> CompositionOfOneContextualOperation<T> {
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }
    
    private func createCompositionOfTwoContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>) -> CompositionOfTwoContextualOperations<T1, T2> {
        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

    private func createCompositionOfThreeContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType, T3: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, op3: ContextualOperationWithSpecificReasonForCancel<T3>) -> CompositionOfThreeContextualOperations<T1, T2, T3> {
        let composedOp = CompositionOfThreeContextualOperations(op1: op1, op2: op2, op3: op3, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

    private func createCompositionOfFourContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType, T3: LocalizedErrorWithLogType, T4: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, op3: ContextualOperationWithSpecificReasonForCancel<T3>, op4: ContextualOperationWithSpecificReasonForCancel<T4>) -> CompositionOfFourContextualOperations<T1, T2, T3, T4> {
        let composedOp = CompositionOfFourContextualOperations(op1: op1, op2: op2, op3: op3, op4: op4, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

}


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
