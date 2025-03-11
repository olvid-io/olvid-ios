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
@preconcurrency import ObvEngine
import ObvCoreDataStack
import ObvCrypto
import OlvidUtils
import ObvTypes
import ObvUICoreData
import ObvSettings
import ObvLocation
import LinkPresentation
import ObvAppCoreConstants
import ObvAppTypes
import ObvUICoreDataStructs


final class PersistedDiscussionsUpdatesCoordinator: OlvidCoordinator, CoordinatorOfObvMessagesReceivedFromUserNotificationExtension, @unchecked Sendable {
    
    let obvEngine: ObvEngine
    static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: PersistedDiscussionsUpdatesCoordinator.self))
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: PersistedDiscussionsUpdatesCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    let coordinatorsQueue: OperationQueue
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue
    private let queueForOperationsMakingEngineCalls: OperationQueue
    private let queueForDispatchingOffTheMainThread = DispatchQueue(label: "PersistedDiscussionsUpdatesCoordinator internal queue for dispatching off the main thread")
    private let internalQueueForAttachmentsProgresses = OperationQueue.createSerialQueue(name: "Internal queue for progresses")
    private let queueForLongRunningConcurrentOperations: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        queue.name = "PersistedDiscussionsUpdatesCoordinator queue for long running tasks"
        return queue
    }()
    private let messagesKeptForLaterManager: MessagesKeptForLaterManager
    private let receivedReturnReceiptScheduler = ReceivedReturnReceiptScheduler()
    private let receivedContinuousLocationRateLimiter = ReceivedContinuousLocationRateLimiter()

    private var userDefaults: UserDefaults? { UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier) }
    private var screenCaptureDetector: ScreenCaptureDetector?
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?


    /// The execution of `SendUnprocessedPersistedMessageSentOperation` allows to send a message from the current device.
    /// This sent message contains a return receipt that we expect our contacts to send back to us. Since we want to treat this return receipt
    /// with higher priority than the return receipts received by this device, but sent by another owned device, we keep the locally generated
    /// return receipts' nonces in memory, so as to appropriately set the queue priorirty of the operation processing received return receipts.
    let noncesOfReturnReceiptGeneratedOnCurrentDevice = NoncesOfReturnReceiptGeneratedOnCurrentDevice()
    actor NoncesOfReturnReceiptGeneratedOnCurrentDevice {
        
        private var noncesOfReturnReceiptGeneratedOnCurrentDevice = Set<Data>()

        func insert(_ nonce: Data) {
            noncesOfReturnReceiptGeneratedOnCurrentDevice.insert(nonce)
        }
        
        func remove(_ nonce: Data) -> Bool {
            return noncesOfReturnReceiptGeneratedOnCurrentDevice.remove(nonce) != nil
        }
        
    }

    
    init(obvEngine: ObvEngine, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue, queueForOperationsMakingEngineCalls: OperationQueue, queueForSyncHintsComputationOperation: OperationQueue, messagesKeptForLaterManager: MessagesKeptForLaterManager) {
        self.obvEngine = obvEngine
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        self.queueForOperationsMakingEngineCalls = queueForOperationsMakingEngineCalls
        self.queueForSyncHintsComputationOperation = queueForSyncHintsComputationOperation
        self.messagesKeptForLaterManager = messagesKeptForLaterManager
        listenToNotifications()
        Task {
            await PersistedMessageReceived.addPersistedMessageReceivedObserver(self)
            await ReceivedFyleMessageJoinWithStatus.addReceivedFyleMessageJoinWithStatusObserver(self)
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
            await processUnprocessedRecipientInfosThatCanNowBeProcessed()
            deleteEmptyLockedDiscussion()
            trashOrphanedFilesFoundInTheFylesDirectory()
            deleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact()
            // No need to delete orphaned one to one discussions (i.e., without contact), they are cascade deleted
            // No need to delete orphaned group discussions (i.e., without contact group), they are cascade deleted
            // No need to delete orphaned PersistedMessageTimestampedMetadata, i.e., without message), they are cascade deleted
            bootstrapMessagesToBeWiped(preserveReceivedMessages: true)
            deleteOldOrOrphanedDatabaseEntries()
            cleanExpiredMuteNotificationsSetting()
            cleanOrphanedPersistedMessageTimestampedMetadata()
            synchronizeAllOneToOneDiscussionTitlesWithContactNameOperation()
            refreshNumberOfNewMessagesForAllDiscussions()
            await updateSharingLocationToFinishedState()
            Task {
                await regularlyUpdateFyleMessageJoinWithStatusProgresses()
                //fake()
            }
        }

        // The following allows to make sure that, if something was shared to Olvid from another app (e.g., the Photos app)
        // while Olvid was in the background, we will refresh the view context and insert the new objects into it. In practice,
        // this allows to make sure that messages sent by the share extension (thus stored in the database) are indeed loaded in
        // the view context (and thus, loaded by the fetch results controller of the corresponding discussion if currently on screen).
        if let userDefaults = self.userDefaults {
            userDefaults.deepRefreshObjectsModifiedByShareExtension(viewContext: ObvStack.shared.viewContext)
        }

        // The following bootstrap methods are always called, not only the first time the app appears on screen
        
        wipeReadOnceAndLimitedVisibilityMessagesThatTheShareExtensionDidNotHaveTimeToWipe()

    }
    
    
//    private final class FakeOperation: AsyncOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
//        override func main() async {
//            try! await Task.sleep(seconds: 0.03)
//            return finish()
//        }
//    }
//    
//    private func fake() {
//        Task {
//            
//            while true {
//                
//                try! await Task.sleep(seconds: 2)
//                
//                do {
//                    let ops = (0..<200).map({ _ in FakeOperation() })
//                    Task { await coordinatorsQueue.addAndAwaitOperations(ops) }
//                }
//                
//                try! await Task.sleep(seconds: 2)
//                
//                do {
//                    let ops = (0..<200).map({ _ in FakeOperation() })
//                    Task { await coordinatorsQueue.addAndAwaitOperations(ops) }
//                }
//
//                try! await Task.sleep(seconds: 2)
//                
//                do {
//                    let ops = (0..<200).map({ _ in FakeOperation() })
//                    await coordinatorsQueue.addAndAwaitOperations(ops)
//                }
//
//            }
//            
//        }
//    }
    

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

        // No need to request progresses if we are not currently displaying a discussion
        guard OlvidUserActivitySingleton.shared.currentDiscussionPermanentID != nil else { return }
        
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
            ObvMessengerCoreDataNotification.observeASecureChannelWithContactDeviceWasJustCreated { [weak self] contactDeviceObjectID in
                self?.sendAppropriateDiscussionSharedConfigurationsToContact(input: .contactDevice(contactDeviceObjectID: contactDeviceObjectID), sendSharedConfigOfOneToOneDiscussion: true)
                Task { [weak self] in await self?.processUnprocessedRecipientInfosThatCanNowBeProcessed() }
            },
            ObvMessengerCoreDataNotification.observePersistedContactGroupHasUpdatedContactIdentities() { [weak self] (persistedContactGroupObjectID, insertedContacts, removedContacts) in
                self?.processPersistedContactGroupHasUpdatedContactIdentitiesNotification(persistedContactGroupObjectID: persistedContactGroupObjectID, insertedContacts: insertedContacts, removedContacts: removedContacts)
            },
            ObvMessengerCoreDataNotification.observePersistedMessageReceivedWasDeleted() { [weak self] (_, messageIdentifierFromEngine, ownedCryptoId, _, _) in
                Task { [weak self] in await self?.processPersistedMessageReceivedWasDeletedNotification(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId) }
            },
            ObvMessengerCoreDataNotification.observeAReadOncePersistedMessageSentWasSent { [weak self] (persistedMessageSentPermanentID, persistedDiscussionPermanentID) in
                Task { [weak self] in await self?.processAReadOncePersistedMessageSentWasSentNotification(persistedMessageSentPermanentID: persistedMessageSentPermanentID, persistedDiscussionPermanentID: persistedDiscussionPermanentID) }
            },
            ObvMessengerCoreDataNotification.observePersistedContactWasDeleted { [weak self ] _, _ in
                self?.processPersistedContactWasDeletedNotification()
            },
            ObvMessengerCoreDataNotification.observePersistedObvOwnedIdentityWasDeleted { [weak self] in
                self?.processPersistedObvOwnedIdentityWasDeleted()
            },
            ObvMessengerCoreDataNotification.observeAPersistedGroupV2MemberChangedFromPendingToNonPending { [weak self] contactObjectID in
                self?.sendAppropriateDiscussionSharedConfigurationsToContact(input: .contact(contactObjectID: contactObjectID), sendSharedConfigOfOneToOneDiscussion: false)
                Task { [weak self] in await self?.processUnprocessedRecipientInfosThatCanNowBeProcessed() }
            },
            ObvMessengerCoreDataNotification.observePersistedDiscussionWasInsertedOrReactivated { [weak self] ownedCryptoId, discussionIdentifier in
                self?.processPersistedDiscussionWasInsertedOrReactivated(ownedCryptoId: ownedCryptoId, discussionIdentifier: discussionIdentifier)
            },
            ObvMessengerCoreDataNotification.observeAPersistedGroupV2WasInsertedInDatabase { [weak self] ownedCryptoId, groupIdentifier in
                Task { [weak self] in await self?.processAPersistedGroupV2WasInsertedInDatabase(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier) }
            },
            ObvMessengerCoreDataNotification.observePersistedContactWasInserted { [weak self] _, ownedCryptoId, contactCryptoId, isOneToOne in
                Task { [weak self] in await self?.processPersistedContactWasInserted(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId, isOneToOne: isOneToOne) }
            },
            ObvMessengerCoreDataNotification.observeContactOneToOneStatusChanged { [weak self] contactIdentifier, isOneToOne in
                Task { [weak self] in await self?.processContactOneToOneStatusChanged(contactIdentifier: contactIdentifier, isOneToOne: isOneToOne) }
            },
            ObvMessengerCoreDataNotification.observeOtherMembersOfGroupV2DidChange { ownedCryptoId, groupIdentifier in
                Task { [weak self] in await self?.processOtherMembersOfGroupV2DidChange(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier) }
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
            ObvMessengerInternalNotification.observeUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration { [weak self] ownedCryptoId, discussionId, expirationJSON in
                self?.processUserWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(ownedCryptoId: ownedCryptoId, discussionId: discussionId, expirationJSON: expirationJSON)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateDiscussionLocalConfiguration { [weak self] (value, localConfigurationObjectID) in
                self?.processUserWantsToUpdateDiscussionLocalConfigurationNotification(with: value, localConfigurationObjectID: localConfigurationObjectID)
            },
            ObvMessengerInternalNotification.observeUserWantsToUpdateLocalConfigurationOfDiscussion { [weak self] (value, discussionPermanentID, completionHandler) in
                Task { [weak self] in
                    await self?.processUserWantsToUpdateLocalConfigurationOfDiscussionNotification(with: value, discussionPermanentID: discussionPermanentID)
                    DispatchQueue.main.async {
                        completionHandler()
                    }
                }
            },
            ObvMessengerInternalNotification.observeUserWantsToSendEditedVersionOfSentMessage { [weak self] (ownedCryptoId, sentMessageObjectID, newTextBody) in
                Task { [weak self] in await self?.processUserWantsToSendEditedVersionOfSentMessage(ownedCryptoId: ownedCryptoId, sentMessageObjectID: sentMessageObjectID, newTextBody: newTextBody) }
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
            ObvMessengerInternalNotification.observeUserWantsToWipeFyleMessageJoinWithStatus { [weak self] (ownedCryptoId, objectIDs) in
                self?.processUserWantsToWipeFyleMessageJoinWithStatus(ownedCryptoId: ownedCryptoId, objectIDs: objectIDs)
            },
            ObvMessengerInternalNotification.observeUserWantsToForwardMessage { [weak self] messagePermanentID, discussionPermanentIDs in
                Task { [weak self] in await self?.processUserWantsToForwardMessage(messagePermanentID: messagePermanentID, discussionPermanentIDs: discussionPermanentIDs) }
            },
            ObvMessengerInternalNotification.observeUserHasOpenedAReceivedAttachment { [weak self] receivedFyleJoinID in
                self?.processUserHasOpenedAReceivedAttachment(receivedFyleJoinID: receivedFyleJoinID)
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
            ObvMessengerInternalNotification.observeNewObvEncryptedPushNotificationWasReceivedViaPushKitNotification { [weak self] encryptedPushNotification in
                Task { [weak self] in await self?.processNewObvEncryptedPushNotificationWasReceivedViaPushKitNotification(encryptedPushNotification: encryptedPushNotification) }
            },
        ])
        
        // Internal notifications

        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeNewCallLogItem() { [weak self] objectID in
                self?.processNewCallLogItemNotification(objectID: objectID)
            },
            ObvMessengerInternalNotification.observeCurrentDiscussionDidChange { [weak self] previousDiscussion, currentDiscussion in
                Task { [weak self] in
                    if let previousDiscussion {
                        await self?.userLeftDiscussion(discussionPermanentID: previousDiscussion)
                    }
                    if let currentDiscussion {
                        await self?.userEnteredDiscussion(discussionPermanentID: currentDiscussion)
                    }
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
            VoIPNotification.observeNewOwnedWebRTCMessageToSend() { [weak self] (ownedCryptoId, webrtcMessage) in
                self?.processNewOwnedWebRTCMessageToSend(ownedCryptoId: ownedCryptoId, webrtcMessage: webrtcMessage)
            },
        ])
        
        // ObvEngineNotificationNew Notifications
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeNewMessagesReceived(within: NotificationCenter.default) { [weak self] messages in
                Task { [weak self] in await self?.processNewMessagesReceivedNotification(messages: messages) }
            },
            ObvEngineNotificationNew.observeMessageWasAcknowledged(within: NotificationCenter.default) { [weak self] (ownedIdentity, messageIdentifierFromEngine, timestampFromServer, isAppMessageWithUserContent, isVoipMessage) in
                Task { [weak self] in await self?.processMessageWasAcknowledgedNotification(ownedIdentity: ownedIdentity, messageIdentifierFromEngine: messageIdentifierFromEngine, timestampFromServer: timestampFromServer, isAppMessageWithUserContent: isAppMessageWithUserContent, isVoipMessage: isVoipMessage) }
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
            ObvEngineNotificationNew.observeNewObvEncryptedReceivedReturnReceipt(within: NotificationCenter.default) { [weak self] encryptedReceivedReturnReceipt in
                Task { [weak self] in await self?.processNewObvReturnReceiptToProcessNotification(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt) }
            },
            ObvEngineNotificationNew.observeOutboxMessagesAndAllTheirAttachmentsWereAcknowledged(within: NotificationCenter.default) { [weak self] messageIdsAndTimestampsFromServer in
                Task { [weak self] in await self?.processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(messageIdsAndTimestampsFromServer: messageIdsAndTimestampsFromServer) }
            },
            ObvEngineNotificationNew.observeOutboxMessageCouldNotBeSentToServer(within: NotificationCenter.default) { [weak self] (messageIdentifierFromEngine, ownedCryptoId) in
                self?.processOutboxMessageCouldNotBeSentToServer(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId)
            },
            ObvEngineNotificationNew.observeContactWasDeleted(within: NotificationCenter.default) { [weak self] (ownedCryptoId, contactCryptoId) in
                self?.processContactWasDeletedNotification(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvEngineNotificationNew.observeMessageExtendedPayloadAvailable(within: NotificationCenter.default) { [weak self] message in
                switch message {
                case .obvMessage(let obvMessage):
                    self?.processContactMessageExtendedPayloadAvailable(obvMessage: obvMessage)
                case .obvOwnedMessage(let obvOwnedMessage):
                    self?.processOwnedMessageExtendedPayloadAvailable(obvOwnedMessage: obvOwnedMessage)
                }
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
        Task { await observeDarwinNotificationsPostedBtShareExtension() }
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
                    self?.bootstrapMessagesToBeWiped(preserveReceivedMessages: false)
                    UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
                }
            },
        ])
    }

    
    private func observeDarwinNotificationsPostedBtShareExtension() async {
        assert(self.userDefaults != nil)
        await ObvDarwinNotificationCenter.shared.addObserver(self, forDarwinNotificationName: ObvDarwinNotificationName.shareExtensionDidPostMessage)
        await ObvDarwinNotificationCenter.shared.addObserver(self, forDarwinNotificationName: ObvDarwinNotificationName.shareExtensionFailedToWipeAllEphemeralMessagesBeforeDate)
    }
        

    private func deleteOldOrOrphanedDatabaseEntries() {
        let operations = ObvUICoreDataHelper.getOperationsForDeletingOldOrOrphanedDatabaseEntries()
        for op1 in operations {
            op1.queuePriority = .low
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            self.coordinatorsQueue.addOperation(composedOp)
        }
    }


    private func wipeReadOnceAndLimitedVisibilityMessagesThatTheShareExtensionDidNotHaveTimeToWipe() {
        guard let userDefaults = userDefaults else { return }
        let op1 = WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation(userDefaults: userDefaults,
                                                                                   appType: .mainApp,
                                                                                   wipeType: .finishIfRequiredWipeStartedByAnExtension,
                                                                                   delegate: self)
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
    

    private func refreshNumberOfNewMessagesForAllDiscussions() {
        let op1 = RefreshNumberOfNewMessagesForAllDiscussionsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }
    
    
    /// Method called when starting App to update messages with a location in a SHARING state whereas it should be cancelled.
    private func updateSharingLocationToFinishedState() async {
        
        let location = ObvLocation.endSharing(type: .all)
        
        do {
            try await processObvLocationForThisPhysicalDevice(location)
        } catch {
            Self.logger.fault("Could not update location messages to finished state: \(error)")
            assertionFailure()
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


// MARK: - Implementing ObvDarwinNotificationObserver

extension PersistedDiscussionsUpdatesCoordinator: ObvDarwinNotificationObserver {
    
    func didReceiveDarwinNotification(_ darwinNotificationName: String) async {

        switch darwinNotificationName {
            
        case ObvDarwinNotificationName.shareExtensionDidPostMessage:
            
            // One or more messages with attachments were sent by the share extension. Since 2024-12-18, this notification
            // is posted when a DeletedOutboxMessage is created by the engine's send manager, i.e., when the message and all
            // its attachments are sent (i.e., stored on the server). Since the context was saved by the share extension, we were
            // not notified. We thus request a transaction history replay
            
            assert(userDefaults != nil)
            // Make sure the view context knows about the objects created by the share extension
            userDefaults?.deepRefreshObjectsModifiedByShareExtension(viewContext: ObvStack.shared.viewContext)
            // Make sure the app database knows the appropriate sent status of the created objects
            obvEngine.replayTransactionsHistory()
            
        case ObvDarwinNotificationName.shareExtensionFailedToWipeAllEphemeralMessagesBeforeDate:
            
            wipeReadOnceAndLimitedVisibilityMessagesThatTheShareExtensionDidNotHaveTimeToWipe()

        default:
            return

        }
        
    }

}



// MARK: - ReceivedFyleMessageJoinWithStatusObserver

extension PersistedDiscussionsUpdatesCoordinator: ReceivedFyleMessageJoinWithStatusObserver {
    
    func newReturnReceiptToSendForReceivedFyleMessageJoinWithStatus(returnReceiptToSend: ObvTypes.ObvReturnReceiptToSend) async {
        do {
            try await obvEngine.postReturnReceiptWithElements(returnReceiptToSend: returnReceiptToSend)
        } catch {
            assertionFailure()
        }
    }
    
}


// MARK: - PersistedMessageReceivedDelegate

extension PersistedDiscussionsUpdatesCoordinator: PersistedMessageReceivedObserver {
    
    func persistedMessageReceivedWasInserted(receivedMessage: PersistedMessageReceivedStructure) async {}
    
    func persistedMessageReceivedWasRead(ownedCryptoId: ObvCryptoId, messageIdFromServer: UID) async {}
    
    func newReturnReceiptToSendForPersistedMessageReceived(returnReceiptToSend: ObvTypes.ObvReturnReceiptToSend) async {
        do {
            try await obvEngine.postReturnReceiptWithElements(returnReceiptToSend: returnReceiptToSend)
        } catch {
            assertionFailure()
        }
    }

}


// MARK: - CoordinatorOfObvMessagesReceivedFromUserNotificationExtension

extension PersistedDiscussionsUpdatesCoordinator {
    
    /// Called when the user wants to send a message from a user notification. As for now, this is only possible from a `.missedCall` notification.
    func processUserWantsToSendMessageFromUserNotification(body: String, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        
        let op1 = CreateUnprocessedPersistedMessageSentFromBodyOperation(discussionIdentifier: discussionIdentifier, textBody: body)
        let op2 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: nil, obvEngine: obvEngine)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        composedOp.queuePriority = .veryHigh
        
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        
        assert(composedOp.isFinished && !composedOp.isCancelled)
        
        if let nonce = op2.nonceOfReturnReceiptGeneratedOnCurrentDevice {
            await self.noncesOfReturnReceiptGeneratedOnCurrentDevice.insert(nonce)
        }

    }
    

    /// Called by the `UserNotificationsCoordinator` when a received user notification contains an `ObvMessage` that should be stored in the app database.
    func persistObvMessageFromUserNotification(obvMessage: ObvMessage, queuePriority: Operation.QueuePriority) async -> PersistObvMessageFromUserNotificationResult {
        
        let result = await processReceivedObvMessage(obvMessage, source: .userNotification, queuePriority: queuePriority)
        
        switch result {
        case .done(attachmentsProcessingRequest: _):
            return .success
        case .definitiveFailure:
            return .notificationMustBeRemoved
        case .couldNotFindGroupV2InDatabase,
                .couldNotFindContactInDatabase,
                .couldNotFindOneToOneContactInDatabase,
                .contactIsNotPartOfTheGroup:
            assertionFailure()
            return .notificationMustBeRemoved
        }
        
    }
    
    
    /// Called by the user notification center delegate when the user replies to a message received from a notification right within the notification center.
    func processUserReplyFromNotificationExtension(replyBody: String, messageRepliedTo: ObvAppTypes.ObvMessageAppIdentifier) async throws {
        
        let obvEngine = self.obvEngine
        let queueForOperationsMakingEngineCalls = self.queueForOperationsMakingEngineCalls
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            
            let op1 = CreateUnprocessedReplyToPersistedMessageSentFromBodyOperation(replyBody: replyBody, messageRepliedTo: messageRepliedTo)
            let op2 = MarkReceivedMessageAsReadFromCurrentDeviceOperation(.messageAppIdentifier(messageRepliedTo))
            let op3 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: nil, obvEngine: obvEngine) {
                Task {
                    // Notify other owned devices about messages that turned not new
                    if op2.ownedIdentityHasAnotherReachableDevice {
                        let postOp = PostDiscussionReadJSONEngineOperation(op: op2, obvEngine: obvEngine)
                        await queueForOperationsMakingEngineCalls.addAndAwaitOperation(postOp)
                    }
                    
                    return continuation.resume()
                }
            }
            
            Task {
                let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
                let currentCompletion = composedOp.completionBlock
                composedOp.completionBlock = {
                    currentCompletion?()
                    if composedOp.isCancelled {
                        // One of op1, op2 or op3 cancelled. We call the completion handler
                        return continuation.resume()
                    }
                }
                composedOp.queuePriority = .veryHigh
                await coordinatorsQueue.addAndAwaitOperation(composedOp)
                
                if let nonce = op3.nonceOfReturnReceiptGeneratedOnCurrentDevice {
                    await self.noncesOfReturnReceiptGeneratedOnCurrentDevice.insert(nonce)
                }

            }

        }
        
    }
    
    
    func processUserWantsToMarkAsReadMessageShownInUserNotification(messageAppIdentifier: ObvAppTypes.ObvMessageAppIdentifier) async {
        
        let op1 = MarkReceivedMessageAsReadFromCurrentDeviceOperation(.messageAppIdentifier(messageAppIdentifier))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh
        await coordinatorsQueue.addAndAwaitOperation(composedOp)

        if op1.ownedIdentityHasAnotherReachableDevice {
            let postOp = PostDiscussionReadJSONEngineOperation(op: op1, obvEngine: obvEngine)
            await queueForOperationsMakingEngineCalls.addAndAwaitOperation(postOp)
        }
        
    }
    
    
    func processUserWantsToMuteDiscussionOfMessageShownInUserNotification(messageAppIdentifier: ObvAppTypes.ObvMessageAppIdentifier) async {

        let op1 = FetchDiscussionPermanentIDCorrespondingToMessage(messageAppIdentifier: messageAppIdentifier)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        
        guard let discussionPermanentID = op1.discussionPermanentID else { assertionFailure(); return }

        await processUserWantsToUpdateLocalConfigurationOfDiscussionNotification(
            with: .muteNotificationsEndDate(MuteDurationOption.oneHour.endDateFromNow),
            discussionPermanentID: discussionPermanentID)
        
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
        
    /// When receiving a NewPersistedObvContactDevice, we check whether there exists "related" unsent message. If this is the case, we can now post them.
    /// This method is also called during bootstrap, to make sure "unprocessed" messages are processed (i.e., sent to the engine).
    private func processUnprocessedRecipientInfosThatCanNowBeProcessed() async {
        
        let obvEngine = self.obvEngine

        let op1 = FindSentMessagesWithPersistedMessageSentRecipientInfosCanNowBeSentByEngineOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        
        guard composedOp.isFinished && !composedOp.isCancelled else {
            Self.logger.fault("Could not find sent messages with persisted message sent recipient infos can now be sent by engine")
            assertionFailure()
            return
        }
        
        let messageSentPermanentIDs = op1.messageSentPermanentIDs
        
        Self.logger.info("Found \(messageSentPermanentIDs.count) unsent messages with persisted message sent recipient infos that can now be sent by engine")
        
        for messageSentPermanentID in messageSentPermanentIDs {
            let op1 = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: messageSentPermanentID,
                                                                   alsoPostToOtherOwnedDevices: false,
                                                                   extendedPayloadProvider: nil,
                                                                   obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            if let nonce = op1.nonceOfReturnReceiptGeneratedOnCurrentDevice {
                await self.noncesOfReturnReceiptGeneratedOnCurrentDevice.insert(nonce)
            }
        }
        
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
                let objectIDOfUnprocessedMessages = sentMessages.filter({ $0.status == .unprocessed || $0.status == .processing }).compactMap({ try? $0.objectPermanentID })
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
        
        let op = SendGlobalDeleteMessagesJSONOperation(persistedMessageObjectIDs: [persistedMessageObjectID], deletionType: deletionType, obvEngine: obvEngine)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        operationsToQueue.append(.engineCall(op: op))
        
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
        
        var operationsToQueue = [OperationKind]()

        let op = SendGlobalDeleteDiscussionJSONOperation(persistedDiscussionObjectID: discussionObjectID.objectID, deletionType: deletionType, obvEngine: obvEngine)
        op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
        operationsToQueue.append(.engineCall(op: op))
        
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
    

    private func userLeftDiscussion(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
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
        await coordinatorsQueue.addAndAwaitOperations(operationsToQueue)
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
    
    
    private func processAReadOncePersistedMessageSentWasSentNotification(persistedMessageSentPermanentID: MessageSentPermanentID, persistedDiscussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
        // When a readOnce sent message status becomes "sent", we check whether the user is still within the discussion corresponding to this message.
        // If this is the case, we do nothing. Otherwise, we should delete or wipe the message as it is readOnce, has already been seen, and was properly sent.
        guard OlvidUserActivitySingleton.shared.currentDiscussionPermanentID != persistedDiscussionPermanentID else {
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
        await coordinatorsQueue.addAndAwaitOperations(operationsToQueue)
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

    
    private func processUserWantsToSendEditedVersionOfSentMessage(ownedCryptoId: ObvCryptoId, sentMessageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, newTextBody: String?) async {
        
        let op1 = EditTextBodyOfSentMessageOperation(ownedCryptoId: ownedCryptoId, persistedSentMessageObjectID: sentMessageObjectID, newTextBody: newTextBody)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            Self.logger.fault("Could not send message: \(op1.reasonForCancel)")
            return
        }

        guard let updateMessageJSONToSend = op1.updateMessageJSONToSend else {
            // Nothing to send
            return
        }
        
        let op = SendUpdateMessageJSONOperation(updateMessageJSONToSend: updateMessageJSONToSend, obvEngine: obvEngine)
        queueForOperationsMakingEngineCalls.addOperation(op)

    }
    
    
    private func processNewObvEncryptedPushNotificationWasReceivedViaPushKitNotification(encryptedPushNotification: ObvEncryptedRemoteUserNotification) async {
        do {
            let decryptedNotification = try await obvEngine.decrypt(encryptedPushNotification: encryptedPushNotification)
            switch decryptedNotification {
            case .obvMessageOrObvOwnedMessage(let obvMessageOrObvOwnedMessage):
                switch obvMessageOrObvOwnedMessage {
                case .obvMessage(let obvMessage):
                    _ = await processReceivedObvMessage(obvMessage, source: .userNotification, queuePriority: .normal)
                case .obvOwnedMessage:
                    Self.logger.fault("Unexpected decrypted notification type received from PushKitNotification (ObvOwnedMessage)")
                    assertionFailure()
                }
            case .protocolMessage:
                Self.logger.fault("Unexpected decrypted notification type received from PushKitNotification (ProtoclMessage)")
                assertionFailure()
            }
            
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
        
        if op1.ownedIdentityHasAnotherReachableDevice {
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
    
    
    private func newProgressToAddForTrackingFreeze(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, progress: Progress) {
        CompositionViewFreezeManager.shared.newProgressToAddForTrackingFreeze(draftPermanentID: draftPermanentID, progress: progress)
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

    private func processUserWantsToUpdateLocalConfigurationOfDiscussionNotification(with value: PersistedDiscussionLocalConfigurationValue, discussionPermanentID: DiscussionPermanentID) async {
        let op1 = UpdateDiscussionLocalConfigurationOperation(
            value: value,
            input: .discussionPermanentID(discussionPermanentID),
            makeSyncAtomRequest: true,
            syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
    }

}

// MARK: - Implementing ContinuousSharingLocationServiceDelegate

extension PersistedDiscussionsUpdatesCoordinator: ContinuousSharingLocationServiceDelegate {
    
    func newObvLocationToProcessForThisPhysicalDevice(_ continuousSharingLocationService: ContinuousSharingLocationService, location: ObvLocation) async throws {
        try await processObvLocationForThisPhysicalDevice(location)
    }
    
}


// MARK: - Helper methods for sending or sharing location from current physical device

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func processObvLocationForThisPhysicalDevice(_ location: ObvLocation) async throws {
        
        let op1 = ProcessObvLocationForThisPhysicalDeviceOperation(obvLocation: location)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            return
        }

        for messageSentPermanentID in op1.unprocessedMessagesToSend {
            let op1 = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: messageSentPermanentID,
                                                                   alsoPostToOtherOwnedDevices: true,
                                                                   extendedPayloadProvider: nil,
                                                                   obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            coordinatorsQueue.addOperation(composedOp) // Don't wait
        }
        
        for updateMessageJSONToSend in op1.updateMessageJSONsToSend {
            let op = SendUpdateMessageJSONOperation(updateMessageJSONToSend: updateMessageJSONToSend, obvEngine: obvEngine)
            queueForOperationsMakingEngineCalls.addOperation(op) // Don't wait
        }

    }

}



// MARK: - Processing user's calls, relayed by the RootViewController

extension PersistedDiscussionsUpdatesCoordinator {
    
    func userWantsToSendLocation(locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        let obvLocation = ObvLocation.send(locationData: locationData, discussionIdentifier: discussionIdentifier)
        try await processObvLocationForThisPhysicalDevice(obvLocation)
    }
    
    
    func processUserWantsToUpdateReaction(ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws {
        let op1 = ProcessSetOrUpdateReactionOnMessageLocalRequestOperation(ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)
        let op2 = SendReactionJSONOperation(messageObjectID: messageObjectID, obvEngine: obvEngine, emoji: newEmoji)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        composedOp.queuePriority = .veryHigh // As this was requested by the user
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "processUserWantsToUpdateReaction did cancel")
        }
    }

    
    func processMessagesAreNotNewAnymore(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async {

        let op1 = ProcessPersistedMessagesAsTheyTurnsNotNewOnCurrentDeviceOperation(
            ownedCryptoId: ownedCryptoId,
            discussionId: discussionId,
            messageIds: messageIds)
        await queueAndAwaitCompositionOfOneContextualOperation(op1: op1, queuePriority: .high) // High since this impact the user experience directly

        guard op1.isFinished && !op1.isCancelled else {
            assertionFailure()
            return
        }
        
        // Notify other owned devices about messages that turned not new
        if op1.ownedIdentityHasAnotherReachableDevice {
            let postOp = PostDiscussionReadJSONEngineOperation(op: op1, obvEngine: obvEngine)
            queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
        }

    }

    
    func processUserWantsToReadReceivedMessageThatRequiresUserActionNotification(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws {

        let op1 = AllowReadingOfMessagesReceivedThatRequireUserActionOperation(.requestedOnCurrentDevice(ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageId: messageId))
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // As this was requested by the user
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "AllowReadingOfMessagesReceivedThatRequireUserActionOperation did cancel")
        }

        let postOp = PostLimitedVisibilityMessageOpenedJSONEngineOperation(op: op1, obvEngine: obvEngine)
        queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
        
    }

    
    func processUserWantsToUpdateDraftExpiration(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws {
        let op1 = UpdateDraftConfigurationOperation(value: value, draftObjectID: draftObjectID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // As this was requested by the user
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "UpdateDraftConfigurationOperation did cancel")
        }
    }

    
    func processInsertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws {
        let op1 = InsertEndToEndEncryptedSystemMessageIfCurrentDiscussionIsEmptyOperation(discussionObjectID: discussionObjectID, markAsRead: markAsRead)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "InsertEndToEndEncryptedSystemMessageIfCurrentDiscussionIsEmptyOperation did cancel")
        }
    }

    
    func processUserWantsToRemoveReplyToMessage(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        let op1 = RemoveReplyToOnDraftOperation(draftObjectID: draftObjectID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // As this was requested by the user
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "RemoveReplyToOnDraftOperation did cancel")
        }
    }

    
    func processUserWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        let op1 = ResumeOrPauseOwnedAttachmentDownloadOperation(sentJoinObjectID: sentJoinObjectID, resumeOrPause: .resume, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // As this was requested by the user
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "ResumeOrPauseOwnedAttachmentDownloadOperation did cancel")
        }
    }
    
    
    func processUserWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        let op1 = ResumeOrPauseOwnedAttachmentDownloadOperation(sentJoinObjectID: sentJoinObjectID, resumeOrPause: .pause, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // As this was requested by the user
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "ResumeOrPauseOwnedAttachmentDownloadOperation did cancel")
        }
    }
    
    
    func processUserWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        let op1 = ResumeOrPauseAttachmentDownloadOperation(receivedJoinObjectID: receivedJoinObjectID, resumeOrPause: .pause, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // As this was requested by the user
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "ResumeOrPauseAttachmentDownloadOperation did cancel")
        }
    }

    
    func processUserWantsToDownloadReceivedFyleMessageJoinWithStatus(receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        let op1 = ResumeOrPauseAttachmentDownloadOperation(receivedJoinObjectID: receivedJoinObjectID, resumeOrPause: .resume, obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // As this was requested by the user
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "ResumeOrPauseAttachmentDownloadOperation did cancel")
        }
    }

    
    func userWantsToReplyToMessage(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        let op1 = AddReplyToOnDraftOperation(messageObjectID: messageObjectID, draftObjectID: draftObjectID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // As this was requested by the user
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "AddReplyToOnDraftOperation did cancel")
        }
    }

    
    /// Called from the `RootViewController` regularly, in order to save the latest changes made by the user to a draft.
    func processUserWantsToUpdateDraftBodyAndMentions(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftBody: String, mentions: Set<MessageJSON.UserMention>) async throws {
        let op1 = UpdateDraftBodyAndMentionsOperation(draftObjectID: draftObjectID, draftBody: draftBody, mentions: mentions)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .high // Since this impacts the user directly
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "Could not save changes made to draft")
        }
    }
    
    
    /// Called from the `RootViewController` when the user wants to add attachments to a draft
    func processUserWantsToAddAttachmentsToDraft(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, urls: [URL], completionHandler: @escaping (Bool) -> Void) {
        assert(OperationQueue.current != coordinatorsQueue)
        
        let loadItemProviderOperations = urls.map {
            LoadItemProviderOperation(itemURL: $0, progressAvailable: { [weak self] progress in
                // Called only if a progress is made available during the operation execution
                self?.newProgressToAddForTrackingFreeze(draftPermanentID: draftPermanentID, progress: progress)
            })
        }
        loadItemProviderOperations.forEach({ $0.queuePriority = .veryHigh }) // Since the user requested this

        let op1 = NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation(
            draftPermanentID: draftPermanentID,
            operationsProvidingLoadedItemProvider: loadItemProviderOperations,
            completionHandler: completionHandler,
            log: Self.log)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // Since the user requested this

        // Since we want to wait until all `LoadItemProviderOperation` are finished to execute the `NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation`, we create a dependency
        loadItemProviderOperations.forEach { loadItemProviderOperation in
            composedOp.addDependency(loadItemProviderOperation)
        }

        // Queue all the operations
        
        queueForLongRunningConcurrentOperations.addOperations(loadItemProviderOperations, waitUntilFinished: false)
        coordinatorsQueue.addOperation(composedOp)
        
    }

    
    /// Called by the `RootViewController` when the user wants to delete all the attachments of a draft.
    func userWantsToDeleteAttachmentsFromDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftTypeToDelete: DeleteAllDraftFyleJoinOfDraftOperation.DraftType) async {
        
        let op1 = DeleteAllDraftFyleJoinOfDraftOperation(draftObjectID: draftObjectID, draftTypeToDelete: draftTypeToDelete)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // As the user requested this
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            return
        }
        
        Task {
            let operations = getOperationsForDeletingOrphanedDatabaseItems()
            await coordinatorsQueue.addAndAwaitOperations(operations)
        }

    }
    

    /// Called by the `RootViewController` when the user wants to send a draft.
    func processUserWantsToSendDraft(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, textBody: String, mentions: Set<MessageJSON.UserMention>) async throws {

        let op1 = SaveBodyTextAndMentionsOfPersistedDraftOperation(draftPermanentID: draftPermanentID, bodyText: textBody, mentions: mentions)
        let op2 = CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation(draftPermanentID: draftPermanentID)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        composedOp.queuePriority = .veryHigh
        await coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            throw Self.makeError(message: "Could not process draft")
        }
        
        // If we reach this point, the sent message is created in database, in the unprocess state.
        // We can liberate the current task, whcih unfreezes the ui.
        // We still need to request the sending of the message.
        
        Task {
            
            // We don't want the computation of the extended payload to prevent the sending
            // of the message, so we execute it independently.
            
            let op3 = ComputeExtendedPayloadOperation(provider: op2)
            let composedOp2 = createCompositionOfOneContextualOperation(op1: op3)
            composedOp2.queuePriority = .veryHigh
            await coordinatorsQueue.addAndAwaitOperation(composedOp2)
            
            let extendedPayloadProvider: (any ExtendedPayloadProvider)?
            if composedOp2.isFinished && !composedOp2.isCancelled {
                extendedPayloadProvider = op3
            } else {
                assertionFailure() // In production, send the message anyway
                extendedPayloadProvider = nil
            }

            // Request the sending of the "unprocessed" messge
            
            let op4 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op2,
                                                                   alsoPostToOtherOwnedDevices: true,
                                                                   extendedPayloadProvider: extendedPayloadProvider,
                                                                   obvEngine: obvEngine)
            let composedOp3 = createCompositionOfOneContextualOperation(op1: op4)
            composedOp3.queuePriority = .veryHigh
            await coordinatorsQueue.addAndAwaitOperation(composedOp3)
            
            if let nonce = op4.nonceOfReturnReceiptGeneratedOnCurrentDevice {
                await self.noncesOfReturnReceiptGeneratedOnCurrentDevice.insert(nonce)
            }

            // Mark all messages as read
            
            let op5 = MarkAllMessagesAsNotNewWithinDiscussionOperation(input: .draftPermanentID(draftPermanentID: draftPermanentID))
            let composedOp4 = createCompositionOfOneContextualOperation(op1: op5)
            composedOp4.queuePriority = .veryHigh
            await coordinatorsQueue.addAndAwaitOperation(composedOp4)

            // Notify other owned devices about messages that turned not new

            if op5.ownedIdentityHasAnotherReachableDevice {
                let postOp = PostDiscussionReadJSONEngineOperation(op: op5, obvEngine: obvEngine)
                queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
            }

        }

    }

 
    /// Called from the `RootViewController` when the user wants to add an attachment to a draft.
    func processUserWantsToAddAttachmentsToDraft(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, itemProviders: [NSItemProvider], completionHandler: @escaping (Bool) -> Void) {
        
        let loadItemProviderOperations = itemProviders.map {
            LoadItemProviderOperation(itemProvider: $0, progressAvailable: { [weak self] progress in
                // Called only if a progress is made available during the operation execution
                self?.newProgressToAddForTrackingFreeze(draftPermanentID: draftPermanentID, progress: progress)
            })
        }
        loadItemProviderOperations.forEach({ $0.queuePriority = .veryHigh }) // Since the user requested this
        
        let op1 = NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation(
            draftPermanentID: draftPermanentID,
            operationsProvidingLoadedItemProvider: loadItemProviderOperations,
            completionHandler: completionHandler,
            log: Self.log)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // Since the user requested this
        
        // Since we want to wait until all `LoadItemProviderOperation` are finished to execute the `NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation`, we create a dependency
        loadItemProviderOperations.forEach { loadItemProviderOperation in
            composedOp.addDependency(loadItemProviderOperation)
        }

        // Queue all the operations
        
        queueForLongRunningConcurrentOperations.addOperations(loadItemProviderOperations, waitUntilFinished: false)
        coordinatorsQueue.addOperation(composedOp)
        
    }

}


// MARK: - Processing ObvEngine Notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    private func processNewMessagesReceivedNotification(messages: [ObvMessageOrObvOwnedMessage]) async {
        ObvDisplayableLogs.shared.log("[🚩] PersistedDiscussionsUpdatesCoordinator.processNewMessagesReceivedNotification(messages:) for \(messages.count) messages")
        for message in messages {
            // We dispatch the processing of this message because we don't want to block the processing of the following one.
            // Before 2024-12-27, we used not to perfom this dispatch. This was a mistake. In case the processing of first message of a batch takes a long time,
            // we might end up processing the messages of another batch before processing the second message of the first batch.
            // Although the following code is better in terms processing order, it is not perfect though, as it does not guarantee the order within a batch.
            Task {
                switch message {
                case .obvMessage(let obvMessage):
                    await processNewMessageReceivedNotification(obvMessage: obvMessage)
                case .obvOwnedMessage(let obvOwnedMessage):
                    await processNewOwnedMessageReceivedNotification(obvOwnedMessage: obvOwnedMessage)
                }
            }
        }
    }
    
    private func processNewMessageReceivedNotification(obvMessage: ObvMessage) async {
        Self.logger.debug("🧦🗺️ We received a NewMessageReceived notification with messageUploadTimestampFromServer \(obvMessage.messageUploadTimestampFromServer)")
        
        // The queuePriority is veryHigh as processing a new message is more important than processing a
        // return receipt (the priorirty of which is .high)
        let result = await processReceivedObvMessage(obvMessage, source: .engine, queuePriority: .veryHigh)
        
        let notifyEngine: EngineNotificationOnMessageProcessing

        switch result {
            
        case .definitiveFailure:
            notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)
            
        case .done(attachmentsProcessingRequest: let attachmentsProcessingRequest):
            notifyEngine = .notify(attachmentsProcessingRequest: attachmentsProcessingRequest)
            
        case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
            
            os_log("🧦 The received message belongs to a group we couldn't find in database", log: Self.log, type: .debug)
            
            if Date.now.timeIntervalSince(obvMessage.localDownloadTimestamp) < ObvMessengerConstants.maximumTimeIntervalForKeptForLaterMessages {
                
                os_log("🧦 Since the message is young enough, we keep for later, until the group is hopefully created", log: Self.log, type: .debug)
                
                await messagesKeptForLaterManager.keepForLater (
                    .obvMessageForGroupV2(
                        groupIdentifier: groupIdentifier,
                        obvMessage: obvMessage))
                notifyEngine = .doNotNotify
                
            } else {
                
                os_log("🧦 Since the message is old, we don't wait until the group is created and request its deletion to the engine", log: Self.log, type: .debug)
                
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
            
        case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
            
            if Date.now.timeIntervalSince(obvMessage.localDownloadTimestamp) < ObvMessengerConstants.maximumTimeIntervalForKeptForLaterMessages {
                
                await messagesKeptForLaterManager.keepForLater(.obvMessageExpectingOneToOneContact(
                    contactCryptoId: contactCryptoId,
                    obvMessage: obvMessage))
                notifyEngine = .doNotNotify

            } else {
                
                notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)

            }
            
        case .contactIsNotPartOfTheGroup(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            
            if Date.now.timeIntervalSince(obvMessage.localDownloadTimestamp) < ObvMessengerConstants.maximumTimeIntervalForKeptForLaterMessages {
                
                await messagesKeptForLaterManager.keepForLater(.obvMessageExpectingGroupV2Member(
                    groupIdentifier: groupIdentifier,
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
                try await obvEngine.messageWasProcessed(messageId: obvMessage.messageId, attachmentsProcessingRequest: attachmentsProcessingRequest)
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
        case .doNotNotify:
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

        case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
            
            if Date.now.timeIntervalSince(obvOwnedMessage.localDownloadTimestamp) < ObvMessengerConstants.maximumTimeIntervalForKeptForLaterMessages {
                
                await messagesKeptForLaterManager.keepForLater(.obvOwnedMessageExpectingOneToOneContact(
                    contactCryptoId: contactCryptoId,
                    obvOwnedMessage: obvOwnedMessage))
                notifyEngine = .doNotNotify

            } else {
                
                notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)

            }
            
        case .contactIsNotPartOfTheGroup(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            
            if Date.now.timeIntervalSince(obvOwnedMessage.localDownloadTimestamp) < ObvMessengerConstants.maximumTimeIntervalForKeptForLaterMessages {
                
                await messagesKeptForLaterManager.keepForLater(.obvOwnedMessageExpectingGroupV2Member(
                    groupIdentifier: groupIdentifier, 
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
                try await obvEngine.messageWasProcessed(messageId: obvOwnedMessage.messageId, attachmentsProcessingRequest: attachmentsProcessingRequest)
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
        case .doNotNotify:
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
            case .obvMessageExpectingContact,
                 .obvOwnedMessageExpectingContact,
                 .obvMessageExpectingOneToOneContact,
                 .obvOwnedMessageExpectingOneToOneContact,
                 .obvMessageExpectingGroupV2Member,
                 .obvOwnedMessageExpectingGroupV2Member:
                assertionFailure("Those messages are not expected to be part of the returned results")
            }
        }
        
        await processOtherMembersOfGroupV2DidChange(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier)
        
    }
    

    private func processPersistedContactWasInserted(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, isOneToOne: Bool) async {
        
        let messagesKeptForLater = await messagesKeptForLaterManager.getMessagesExpectingContactForOwnedCryptoId(ownedCryptoId, contactCryptoId: contactCryptoId)

        for messageKeptForLater in messagesKeptForLater {
            switch messageKeptForLater {
            case .obvMessageExpectingContact(contactCryptoId: _, obvMessage: let obvMessage):
                await processNewMessageReceivedNotification(obvMessage: obvMessage)
            case .obvOwnedMessageExpectingContact(contactCryptoId: _, obvOwnedMessage: let obvOwnedMessage):
                await processNewOwnedMessageReceivedNotification(obvOwnedMessage: obvOwnedMessage)
            case .obvMessageForGroupV2, 
                    .obvOwnedMessageForGroupV2,
                    .obvMessageExpectingOneToOneContact,
                    .obvOwnedMessageExpectingOneToOneContact,
                    .obvMessageExpectingGroupV2Member,
                    .obvOwnedMessageExpectingGroupV2Member:
                assertionFailure("Those messages are not expected to be part of the returned results")
            }
        }
        
        if isOneToOne {
            await processContactOneToOneStatusChanged(contactIdentifier: .init(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId), isOneToOne: isOneToOne)
        }
        
    }
    
    
    private func processContactOneToOneStatusChanged(contactIdentifier: ObvContactIdentifier, isOneToOne: Bool) async {
        
        guard isOneToOne else { return }
        
        let messagesKeptForLater = await messagesKeptForLaterManager.getMessagesExpectingOneToOneContactForOwnedCryptoId(contactIdentifier.ownedCryptoId, contactCryptoId: contactIdentifier.contactCryptoId)

        for messageKeptForLater in messagesKeptForLater {
            switch messageKeptForLater {
            case .obvMessageExpectingOneToOneContact(contactCryptoId: _, obvMessage: let obvMessage):
                await processNewMessageReceivedNotification(obvMessage: obvMessage)
            case .obvOwnedMessageExpectingOneToOneContact(contactCryptoId: _, obvOwnedMessage: let obvOwnedMessage):
                await processNewOwnedMessageReceivedNotification(obvOwnedMessage: obvOwnedMessage)
            case .obvMessageForGroupV2,
                    .obvMessageExpectingContact,
                    .obvOwnedMessageForGroupV2,
                    .obvOwnedMessageExpectingContact,
                    .obvMessageExpectingGroupV2Member,
                    .obvOwnedMessageExpectingGroupV2Member:
                assertionFailure("Those messages are not expected to be part of the returned results")
            }
        }
        
    }
    
    
    private func processOtherMembersOfGroupV2DidChange(ownedCryptoId: ObvCryptoId, groupIdentifier: GroupV2Identifier) async {
        
        let messagesKeptForLater = await messagesKeptForLaterManager.getMessagesExpectingGroupV2Member(ownedCryptoId, groupIdentifier: groupIdentifier)
        
        for messageKeptForLater in messagesKeptForLater {
            switch messageKeptForLater {
            case .obvMessageExpectingGroupV2Member(groupIdentifier: _, contactCryptoId: _, obvMessage: let obvMessage):
                await processNewMessageReceivedNotification(obvMessage: obvMessage)
            case .obvOwnedMessageExpectingGroupV2Member(groupIdentifier: _, contactCryptoId: _, obvOwnedMessage: let obvOwnedMessage):
                await processNewOwnedMessageReceivedNotification(obvOwnedMessage: obvOwnedMessage)
            case .obvMessageExpectingContact,
                 .obvOwnedMessageExpectingContact,
                 .obvMessageExpectingOneToOneContact,
                 .obvOwnedMessageExpectingOneToOneContact,
                 .obvMessageForGroupV2,
                 .obvOwnedMessageForGroupV2:
                assertionFailure("Those messages are not expected to be part of the returned results")
            }
        }

    }


    private func processMessageWasAcknowledgedNotification(ownedIdentity: ObvCryptoId, messageIdentifierFromEngine: Data, timestampFromServer: Date, isAppMessageWithUserContent: Bool, isVoipMessage: Bool) async {
        
        if isAppMessageWithUserContent {
            let op1 = SetTimestampMessageSentOfPersistedMessageSentRecipientInfosOperation(
                ownedCryptoId: ownedIdentity,
                messageIdentifierFromEngineAndTimestampFromServer: [(messageIdentifierFromEngine, timestampFromServer)],
                alsoMarkAttachmentsAsSent: false)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.queuePriority = .high // Since this allows the user to see a checkmark on the message
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(composedOp.isFinished && !composedOp.isCancelled)
        }

        await obvEngine.deleteHistoryConcerningTheAcknowledgementOfOutboxMessage(
            messageIdentifierFromEngine:messageIdentifierFromEngine,
            ownedIdentity:ownedIdentity)
        
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
    

    private func processNewObvReturnReceiptToProcessNotification(encryptedReceivedReturnReceipt: ObvEncryptedReceivedReturnReceipt, retryNumber: Int = 0) async {
        
        let obvEngine = self.obvEngine

        guard retryNumber < 10 else {
            assertionFailure()
            Task { await obvEngine.deleteObvReturnReceipt(encryptedReceivedReturnReceipt) }
            return
        }

        // Try to decrypt the received encrypted return receipt. For now, if this fails, we discard the receipt as it
        // probably concerns another device (i.e., the message was sent from another owned device)
        
        let decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt?
        do {
            let op = DecryptReceivedReturnReceiptOperation(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt, obvEngine: obvEngine)
            await queueForSyncHintsComputationOperation.addAndAwaitOperation(op)
            assert(op.isFinished && !op.isCancelled)
            decryptedReceivedReturnReceipt = op.decryptedReceivedReturnReceipt
        }
        
        guard let decryptedReceivedReturnReceipt else {
            Task { await obvEngine.deleteObvReturnReceipt(encryptedReceivedReturnReceipt) }
            return
        }
        
        // If we reach this point, we successfully decrypted the encrypted return receipt.
        // We will compute hints about the what we should do with it.
        
        // Note that since processing a return receipt is a two-step process (hints computing then, when appropriate, hints processing)
        // we want both steps to be atomic. This is ensured by the receivedReturnReceiptScheduler.
        
        await receivedReturnReceiptScheduler.waitForTurn()
        defer { Task { await receivedReturnReceiptScheduler.endOfTurn() } }
        
        let hintsForProcessingDecryptedReceivedReturnReceipt: HintsForProcessingDecryptedReceivedReturnReceipt
        do {
            let op = ComputeHintsForGivenDecryptedReceivedReturnReceiptOperation(decryptedReceivedReturnReceipt: decryptedReceivedReturnReceipt)
            await queueForSyncHintsComputationOperation.addAndAwaitOperation(op)
            assert(op.isFinished && !op.isCancelled)
            guard let hints = op.hintsForProcessingDecryptedReceivedReturnReceipt, hints.receivedReturnReceiptRequiresProcessing else {
                Task { await obvEngine.deleteObvReturnReceipt(encryptedReceivedReturnReceipt) }
                return
            }
            hintsForProcessingDecryptedReceivedReturnReceipt = hints
        }
        
        // If we reach this point, the return receipt must be processed
        
        do {
            let op1 = ApplyHintsForProcessingDecryptedReceivedReturnReceiptOperation(hints: hintsForProcessingDecryptedReceivedReturnReceipt)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.assertionFailureInCaseOfFault = false // This operation often fails in the simulator, when switching from the share extension back to the app. We have a retry feature just for that reason.
            // When receiving a return receipt generated locally on the current device, we set the queue priority to veryHigh, as the operation will change the checkmark on the message.
            // If the return receipt was generated on another owned device (or not in memory anymore), we keep the default priority.
            composedOp.queuePriority = await noncesOfReturnReceiptGeneratedOnCurrentDevice.remove(encryptedReceivedReturnReceipt.nonce) ? .veryHigh : .normal
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            
            if let reasonForCancel = composedOp.reasonForCancel {
                switch reasonForCancel {
                case .coreDataError(error: let error):
                    os_log("Could not process return receipt due to a Core Data error: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                case .op1Cancelled(reason: let op1ReasonForCancel):
                    switch op1ReasonForCancel {
                    case .coreDataError(error: let error):
                        os_log("Could not process return receipt: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                    }
                case .unknownReason, .op1HasUnfinishedDependency:
                    assertionFailure()
                    os_log("Could not process return receipt for an some reason", log: Self.log, type: .fault)
                }
                Task {
                    await processNewObvReturnReceiptToProcessNotification(encryptedReceivedReturnReceipt: encryptedReceivedReturnReceipt, retryNumber: retryNumber + 1)
                }
            } else {
                // If we reach this point, the receipt has been successfully processed. We can delete it from the engine.
                Task { await obvEngine.deleteObvReturnReceipt(encryptedReceivedReturnReceipt) }
            }

        }

    }

    
    /// The OutboxMessagesAndAllTheirAttachmentsWereAcknowledged notification is sent during the bootstrap of the engine, when replaying the transaction history, so as to make sure the app didn't miss any important notification.
    /// It is sent for each deleted outbox message, that exist when the message has been fully sent to the server (unless they were cancelled by the user by deleting the message).
    private func processOutboxMessagesAndAllTheirAttachmentsWereAcknowledgedNotification(messageIdsAndTimestampsFromServer: [(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, timestampFromServer: Date)]) async {
        
        // We need to deal with the case where we receive a huge list of messageIds. To do so, we proceed by batches.
        
        let allSortedIdsAndTimestamps = messageIdsAndTimestampsFromServer.sorted { $0.timestampFromServer < $1.timestampFromServer }
        let batchSize = 50
        
        for index in stride(from: 0, to: allSortedIdsAndTimestamps.count, by: batchSize) {
            
            let batch = allSortedIdsAndTimestamps[index..<min(allSortedIdsAndTimestamps.count, index+batchSize)]
            
            // Each batch is treated on a per owned identity basis
            
            let batchPerOwnedIdentity = Dictionary(grouping: batch, by: { $0.ownedCryptoId })
            
            for (ownedCryptoId, idsAndTimestamps) in batchPerOwnedIdentity {
                
                var retryIteration = 0
                var success = false
                
                while !success && retryIteration < 10 {
                    
                    retryIteration += 1
                    
                    let op1 = SetTimestampMessageSentOfPersistedMessageSentRecipientInfosOperation(
                        ownedCryptoId: ownedCryptoId,
                        messageIdentifierFromEngineAndTimestampFromServer: idsAndTimestamps.map { ($0.messageIdentifierFromEngine, $0.timestampFromServer) },
                        alsoMarkAttachmentsAsSent: true)
                    let op2 = MarkSentFyleMessageJoinWithStatusAsCompleteOperation(
                        ownedCryptoId: ownedCryptoId,
                        messageIdentifiersFromEngine: idsAndTimestamps.map({ $0.messageIdentifierFromEngine }))
                    let op3 = SetTimestampAllAttachmentsSentIfPossibleOfPersistedMessageSentRecipientInfosOperation(
                        ownedCryptoId: ownedCryptoId,
                        messageIdentifiersFromEngine: idsAndTimestamps.map({ $0.messageIdentifierFromEngine }))
                    let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
                    composedOp.assertionFailureInCaseOfFault = false // This operation often fails in the simulator, when sharing from a discussion back to the same discussion. We have a retry feature just for that reason.
                    
                    await coordinatorsQueue.addAndAwaitOperation(composedOp)
                    
                    success = composedOp.isFinished && !composedOp.isCancelled
                    
                }
                
                assert(success)
                
            }
            
            // If the batch is properly processed, we notify the engine (even if the composed operation cancelled)
            
            guard let maxTimestampFromServer = batch.last?.timestampFromServer else { assertionFailure(); return }
            Task { [weak self] in await self?.obvEngine.deleteHistoryConcerningTheAcknowledgementOfOutboxMessages(withTimestampFromServerEarlierOrEqualTo: maxTimestampFromServer) }
            
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

    
    private func processUserWantsToWipeFyleMessageJoinWithStatus(ownedCryptoId: ObvCryptoId, objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>) {
        var operationsToQueue = [Operation]()
        do {
            let op1 = WipeFyleMessageJoinsWithStatusOperation(joinObjectIDs: objectIDs, ownedCryptoId: ownedCryptoId, deletionType: .fromThisDeviceOnly)
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
    

    private func processUserWantsToForwardMessage(messagePermanentID: ObvManagedObjectPermanentID<PersistedMessage>, discussionPermanentIDs: Set<ObvManagedObjectPermanentID<PersistedDiscussion>>) async {
        for discussionPermanentID in discussionPermanentIDs {
            let op1 = CreateUnprocessedForwardPersistedMessageSentFromMessageOperation(messagePermanentID: messagePermanentID, discussionPermanentID: discussionPermanentID)
            let op2 = ComputeExtendedPayloadOperation(provider: op1)
            let op3 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: op2, obvEngine: obvEngine)
            let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            if let nonce = op3.nonceOfReturnReceiptGeneratedOnCurrentDevice {
                await self.noncesOfReturnReceiptGeneratedOnCurrentDevice.insert(nonce)
            }
        }
    }
    

    private func processUserHasOpenedAReceivedAttachment(receivedFyleJoinID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {
        let op1 = MarkAsOpenedOperation(receivedFyleMessageJoinWithStatusID: receivedFyleJoinID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

    private func processTooManyWrongPasscodeAttemptsCausedLockOut() {
        guard ObvMessengerSettings.Privacy.lockoutCleanEphemeral else { return }
        let op1 = WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperation(userDefaults: userDefaults,
                                                                                   appType: .mainApp,
                                                                                   wipeType: .startWipeFromAppOrShareExtension,
                                                                                   delegate: self)
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
//        guard let logString = (coordinatorsQueue as? AppCoordinatorsQueue)?.logOperations(ops: []) else { return }
//        ObvMessengerInternalNotification.betaUserWantsToSeeLogString(logString: logString)
//            .postOnDispatchQueue()
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


// MARK: - Implementing CallProviderDelegateSignalingDelegate

extension PersistedDiscussionsUpdatesCoordinator: CallProviderDelegateSignalingDelegate {
    
    func newWebRTCMessageToSendToAllContactDevices(webrtcMessage: ObvUICoreData.WebRTCMessageJSON, contactIdentifier: ObvTypes.ObvContactIdentifier, forStartingCall: Bool) async {
        Self.logger.info("New WebRTCMessageJSON to all contact devices")

        // When transmitting a "start call" message for the initiation of a call, we aim to ascertain whether or not the recipient does not correspond with any existing profile on this specific device.
        // If that proves true, our intent is to omit this very device from the collection of devices receiving the "start call" message.

        let deviceUIDToExclude: UID?
        
        do {
            let op1 = DetermineCurrentDeviceUIDIfIdentityIsOwnedOperation(cryptoId: contactIdentifier.contactCryptoId)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await self.coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished && !op1.isCancelled)
            deviceUIDToExclude = op1.currentDeviceUID
        }
        
        // Send the "start call" message

        let op1 = SendWebRTCMessageOperation(webrtcMessage: webrtcMessage,
                                             recipient: .allContactDevices(contactIdentifier: contactIdentifier, forStartingCall: forStartingCall, deviceUIDToExclude: deviceUIDToExclude),
                                             obvEngine: obvEngine,
                                             logger: Self.logger)
        await queueForOperationsMakingEngineCalls.addAndAwaitOperation(op1)
        assert(op1.isFinished && !op1.isCancelled)
    }
    
    
    func newWebRTCMessageToSendToSingleContactDevice(webrtcMessage: ObvUICoreData.WebRTCMessageJSON, contactDeviceIdentifier: ObvTypes.ObvContactDeviceIdentifier) async {
        Self.logger.info("New WebRTCMessageJSON to all contact devices")
        let op1 = SendWebRTCMessageOperation(webrtcMessage: webrtcMessage,
                                             recipient: .singleContactDevice(contactDeviceIdentifier: contactDeviceIdentifier),
                                             obvEngine: obvEngine,
                                             logger: Self.logger)
        await queueForOperationsMakingEngineCalls.addAndAwaitOperation(op1)
        assert(op1.isFinished && !op1.isCancelled)
    }
    
}


// MARK: - Helpers

extension PersistedDiscussionsUpdatesCoordinator {
    
    enum ProcessReceivedObvOwnedMessageResult {
        case done(attachmentsProcessingRequest: ObvAttachmentsProcessingRequest)
        case definitiveFailure
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case couldNotFindContactInDatabase(contactCryptoId: ObvCryptoId)
        case couldNotFindOneToOneContactInDatabase(contactCryptoId: ObvCryptoId)
        case contactIsNotPartOfTheGroup(groupIdentifier: GroupV2Identifier, contactCryptoId: ObvCryptoId)
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
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] webrtcMessage")
            await self.processReceivedWebRTCMessageJSON(webrtcMessage, obvOwnedMessage: obvOwnedMessage)
            return .done(attachmentsProcessingRequest: .deleteAll)
        }

        // Case #2: The ObvOwnedMessage contains a message
        
        if let messageJSON = persistedItemJSON.message {
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] messageJSON")
            os_log("The message is an ObvOwnedMessage", log: Self.log, type: .debug)
            let returnReceiptJSON = persistedItemJSON.returnReceipt
            let result = await self.createPersistedMessageSentFromReceivedObvOwnedMessage(
                obvOwnedMessage,
                messageJSON: messageJSON,
                returnReceiptJSON: returnReceiptJSON)
            switch result {
            case .sentMessageCreated(attachmentsProcessingRequest: let attachmentsProcessingRequest):
                return .done(attachmentsProcessingRequest: attachmentsProcessingRequest)
            case .remoteDeleteRequestSavedForLaterWasApplied:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
                return .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactCryptoId)
            case .couldNotFindContactInDatabase(contactCryptoId: let contactCryptoId):
                return .couldNotFindContactInDatabase(contactCryptoId: contactCryptoId)
            case .sentMessageCreationFailure:
                assertionFailure()
                return .definitiveFailure
            }
        }

        // Case #3: The ObvOwnedMessage contains a shared configuration for a discussion
        
        if let discussionSharedConfiguration = persistedItemJSON.discussionSharedConfiguration {
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] discussionSharedConfiguration")
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
            case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
                return .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactCryptoId)
            case .contactIsNotPartOfTheGroup(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfTheGroup(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
            }
        }

        // Case #4: The ObvOwnedMessage contains a JSON message indicating that some messages should be globally deleted in a discussion
        
        if let deleteMessagesJSON = persistedItemJSON.deleteMessagesJSON {
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] deleteMessagesJSON")
            os_log("The owned message is a delete message JSON", log: Self.log, type: .debug)
            let op1 = ProcessRemoteWipeMessagesRequestOperation(deleteMessagesJSON: deleteMessagesJSON,
                                                                requester: .ownedIdentity(ownedCryptoId: obvOwnedMessage.ownedCryptoId),
                                                                messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer)
            let op2 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let op3 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
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
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] deleteDiscussionJSON")
            os_log("The owned message is a delete discussion JSON", log: Self.log, type: .debug)
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
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] updateMessageJSON")
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
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] reactionJSON")
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
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] querySharedSettingsJSON")
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
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] screenCaptureDetectionJSON")
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
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] limitedVisibilityMessageOpenedJSON")
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
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] discussionRead")
            os_log("The owned message indicates that certain messages must be marked as not new within a discussion as they were read on another device", log: Self.log, type: .debug)
            let op1 = MarkAllMessagesAsNotNewWithinDiscussionOperation(input: .discussionReadJSON(ownedCryptoId: obvOwnedMessage.ownedCryptoId, discussionRead: discussionRead))
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
                return .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactCryptoId)
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
        os_log("Call to processReceivedWebRTCMessageJSON [%{public}@][%{public}@][%{public}@]", log: Self.log, type: .debug, obvMessage.messageId.debugDescription, String(webrtcMessage.callIdentifier.uuidString.prefix(8)), webrtcMessage.messageType.description)
        guard abs(obvMessage.downloadTimestampFromServer.timeIntervalSince(obvMessage.messageUploadTimestampFromServer)) < 30 else {
            // We discard old WebRTC messages
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ObvStack.shared.performBackgroundTask { (context) in
                guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(persisted: obvMessage.fromContactIdentity, whereOneToOneStatusIs: .any, within: context) else {
                    os_log("☎️ Could not find persisted contact associated with received webrtc message", log: Self.log, type: .fault)
                    return continuation.resume()
                }
                guard let contactDeviceIdentifier = obvMessage.contactDeviceIdentifier else {
                    Self.logger.fault("Cannot process received WebRTC message as the contact device is not provided")
                    assertionFailure()
                    return continuation.resume()
                }
                let contactId = OlvidUserId.known(contactObjectID: persistedContactIdentity.typedObjectID,
                                                  contactIdentifier: contactDeviceIdentifier.contactIdentifier,
                                                  contactDeviceUID: contactDeviceIdentifier.deviceUID,
                                                  displayName: persistedContactIdentity.fullDisplayName)
                ObvMessengerInternalNotification.newWebRTCMessageWasReceived(
                    webrtcMessage: webrtcMessage,
                    fromOlvidUser: contactId,
                    messageUID: obvMessage.messageUID)
                .postOnDispatchQueue()
                return continuation.resume()
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
        case couldNotFindOneToOneContactInDatabase(contactCryptoId: ObvCryptoId)
        case contactIsNotPartOfTheGroup(groupIdentifier: GroupV2Identifier, contactCryptoId: ObvCryptoId)
    }
    

    /// For now, the `queuePriority` is only relevant in the case the `ObvMessage` contains a message.
    private func processReceivedObvMessage(_ obvMessage: ObvMessage, source: ObvMessageSource, queuePriority: Operation.QueuePriority) async -> ProcessReceivedObvMessageResult {

        assert(OperationQueue.current != coordinatorsQueue)

        os_log("✉️ [%{public}@] Call to processReceivedObvMessage", log: Self.log, type: .debug, obvMessage.messageId.debugDescription)
        
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
            ObvDisplayableLogs.shared.log("[✉️][C][\(obvMessage.messageId.uid.debugDescription)] webrtcMessage")
            os_log("☎️ The message is a WebRTC signaling message", log: Self.log, type: .debug)
            await self.processReceivedWebRTCMessageJSON(webrtcMessage, obvMessage: obvMessage)
            return .done(attachmentsProcessingRequest: .deleteAll)
        }
        
        // Case #2: The ObvMessage contains a message
        
        if let messageJSON = persistedItemJSON.message {
            ObvDisplayableLogs.shared.log("[✉️][C][\(obvMessage.messageId.uid.debugDescription)] messageJSON")
            os_log("The message is an ObvMessage", log: Self.log, type: .debug)
            let returnReceiptJSON = persistedItemJSON.returnReceipt
            let result = await self.createPersistedMessageReceivedFromReceivedObvMessage(
                obvMessage,
                messageJSON: messageJSON,
                source: source,
                returnReceiptJSON: returnReceiptJSON,
                queuePriority: queuePriority)
            switch result {
            case .receivedMessageCreated(attachmentsProcessingRequest: let attachmentsProcessingRequest):
                return .done(attachmentsProcessingRequest: attachmentsProcessingRequest)
            case .couldNotFindGroupV2InDatabase(let groupIdentifier):
                return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
            case .couldNotFindContactInDatabase(contactCryptoId: let contactCryptoId):
                return .couldNotFindContactInDatabase(contactCryptoId: contactCryptoId)
            case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
                return .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactCryptoId)
            case .contactIsNotPartOfTheGroup(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfTheGroup(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
            case .receivedMessageCreationFailure:
                return .definitiveFailure
            case .messageIsPriorToLastRemoteDeletionRequest:
                return .definitiveFailure
            case .cannotCreateReceivedMessageThatAlreadyExpired:
                return .definitiveFailure
            }
        }
        
        // Case #3: The ObvMessage contains a shared configuration for a discussion
        
        if let discussionSharedConfiguration = persistedItemJSON.discussionSharedConfiguration {
            ObvDisplayableLogs.shared.log("[✉️][C][\(obvMessage.messageId.uid.debugDescription)] discussionSharedConfiguration")
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
            case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
                return .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactCryptoId)
            case .contactIsNotPartOfTheGroup(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfTheGroup(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
            }
        }

        // Case #4: The ObvMessage contains a JSON message indicating that some messages should be globally deleted in a discussion
        
        if let deleteMessagesJSON = persistedItemJSON.deleteMessagesJSON {
            ObvDisplayableLogs.shared.log("[✉️][C][\(obvMessage.messageId.uid.debugDescription)] deleteMessagesJSON")
            os_log("The message is a delete message JSON", log: Self.log, type: .debug)
            let op1 = ProcessRemoteWipeMessagesRequestOperation(deleteMessagesJSON: deleteMessagesJSON,
                                                                requester: .contact(contactIdentifier: obvMessage.fromContactIdentity),
                                                                messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
            let op2 = DeleteAllOrphanedFyleMessageJoinWithStatusOperation()
            let op3 = DeleteAllOrphanedFylesAndMoveAssociatedFilesToTrashOperation()
            let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
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
            ObvDisplayableLogs.shared.log("[✉️][C][\(obvMessage.messageId.uid.debugDescription)] deleteDiscussionJSON")
            os_log("The message is a delete discussion JSON", log: Self.log, type: .debug)
                                    
            var operationsToQueue = [Operation]()
            
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
                
                do {
                    let op1 = DetermineEngineIdentifiersOfMessagesToCancelOperation(
                        input: .remoteDiscussionDeletionRequestFromContact(deleteDiscussionJSON: deleteDiscussionJSON, obvMessage: obvMessage),
                        obvEngine: obvEngine)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    await coordinatorsQueue.addAndAwaitOperation(composedOp)
                    let op2 = CancelUploadOrDownloadOfPersistedMessagesOperation(op: op1, obvEngine: obvEngine)
                    await queueForOperationsMakingEngineCalls.addAndAwaitOperation(op2)
                }

                return .done(attachmentsProcessingRequest: .deleteAll)
                
            case nil:
                
                assertionFailure()
                return .definitiveFailure
                
            }
        }
        
        // Case #6: The ObvMessage contains a JSON message indicating that a received message has been edited by the original sender

        if let updateMessageJSON = persistedItemJSON.updateMessageJSON {
            ObvDisplayableLogs.shared.log("[✉️][C][\(obvMessage.messageId.uid.debugDescription)] updateMessageJSON")
            os_log("The message is an update message JSON", log: Self.log, type: .debug)

            // In case the update concerns a continuous location sharing, we apply rate limiter. This is useful when receiving a burst of location updates,
            // which can typically occur after a cold boot. This limiter ensures we only process the most recent location updates, and discard the obsolete ones.
            
            let action: ReceivedContinuousLocationRateLimiter.Action
            if updateMessageJSON.locationJSON?.type == .SHARING, let deviceIdentifier = obvMessage.contactDeviceIdentifier {
                // The update message concerns a continuous location sharing: we apply the rate limiter.
                action = await receivedContinuousLocationRateLimiter.limitRateOfContinuousLocationOfContactDevice(with: deviceIdentifier,
                                                                                                                  uploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                                                                                                                  downloadTimestampFromServer: obvMessage.downloadTimestampFromServer)
            } else {
                // The update message does not concer a continuous location sharing: we process the message immediately.
                action = .process
            }
            
            switch action {
            case .process: // we can update the message
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
            case .cancelled: // The message does not need to be updated.
                return .done(attachmentsProcessingRequest: .deleteAll)
            }
            
        }

        // Case #7: The ObvMessage contains a JSON message indicating that a reaction has been added by a contact

        if let reactionJSON = persistedItemJSON.reactionJSON {
            ObvDisplayableLogs.shared.log("[✉️][C][\(obvMessage.messageId.uid.debugDescription)] reactionJSON")
            let overrideExistingReaction: Bool
            switch source {
            case .userNotification:
                overrideExistingReaction = false
            case .engine:
                overrideExistingReaction = true
            }
            let op1 = ProcessSetOrUpdateReactionOnMessageOperation(
                reactionJSON: reactionJSON,
                requester: .contact(contactIdentifier: obvMessage.fromContactIdentity, overrideExistingReaction: overrideExistingReaction),
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
            ObvDisplayableLogs.shared.log("[✉️][C][\(obvMessage.messageId.uid.debugDescription)] querySharedSettingsJSON")
            let op1 = RespondToQuerySharedSettingsOperation(
                querySharedSettingsJSON: querySharedSettingsJSON,
                requester: .contact(contactIdentifier: obvMessage.fromContactIdentity))
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            return .done(attachmentsProcessingRequest: .deleteAll)
        }
        
        // Case #9: The ObvMessage contains a JSON message indicating that a contact did take a screen capture of sensitive content
        
        if let screenCaptureDetectionJSON = persistedItemJSON.screenCaptureDetectionJSON {
            ObvDisplayableLogs.shared.log("[✉️][C][\(obvMessage.messageId.uid.debugDescription)] screenCaptureDetectionJSON")
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
        case couldNotFindOneToOneContactInDatabase(contactCryptoId: ObvCryptoId)
        case contactIsNotPartOfTheGroup(groupIdentifier: GroupV2Identifier, contactCryptoId: ObvCryptoId)
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
        case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
            return .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactCryptoId)
        case .contactIsNotPartOfTheGroup(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            return .contactIsNotPartOfTheGroup(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
        case .merged:
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
        case couldNotFindOneToOneContactInDatabase(contactCryptoId: ObvCryptoId)
        case contactIsNotPartOfTheGroup(groupIdentifier: GroupV2Identifier, contactCryptoId: ObvCryptoId)
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
        case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
            return .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactCryptoId)
        case .contactIsNotPartOfTheGroup(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            return .contactIsNotPartOfTheGroup(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
        case .merged:
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

    
    enum CreatePersistedMessageReceivedFromReceivedObvMessageResult {
        case receivedMessageCreated(attachmentsProcessingRequest: ObvAttachmentsProcessingRequest)
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case couldNotFindContactInDatabase(contactCryptoId: ObvCryptoId)
        case couldNotFindOneToOneContactInDatabase(contactCryptoId: ObvCryptoId)
        case contactIsNotPartOfTheGroup(groupIdentifier: GroupV2Identifier, contactCryptoId: ObvCryptoId)
        case receivedMessageCreationFailure
        case messageIsPriorToLastRemoteDeletionRequest
        case cannotCreateReceivedMessageThatAlreadyExpired
    }

    /// This method *must* be called from `processReceivedObvMessage(...)`.
    /// This method is called when a new (received) ObvMessage is available. This message can come from one of the two followings places:
    /// - Either it was serialized within the notification extension, and deserialized here,
    /// - Either it was received by the main app.
    /// In the first case, this method is called using `overridePreviousPersistedMessage` set to `false`: we check whether the message already exists in database (using the message uid from server) and, if this is the
    /// case, we do nothing. If the message does not exist, we create it. In the second case, `overridePreviousPersistedMessage` set to `true` and we override any existing persisted message. In other words, messages
    /// comming from the engine always superseed messages comming from  the notification extension.
    ///
    /// ## About the queuePriority
    ///
    /// The `queuePriority` argument typically allows to increase the priority of operations required to create a persisted message received from a notification. This is particularly useful in scenarios where timely persistence is crucial,
    /// such as when a user taps a notification. When a user taps a notification, it's essential to ensure that the contained message is persisted before navigating to the discussion thread. In situations where the app is launched
    /// from a cold start (i.e., the tap on the notification launches the app), many operations are queued for execution during the boot process. Without elevating the priority of persisting the notification message, the user would
    /// experience delays, having to wait until all earlier queued operations complete. By setting a high queuePriority, you can ensure that the persistence operation is executed promptly, providing a seamless user experience.
    ///
    /// When no specific priority is required, we should set the value to `.normal`.
    ///
    private func createPersistedMessageReceivedFromReceivedObvMessage(_ obvMessage: ObvMessage, messageJSON: MessageJSON, source: ObvMessageSource, returnReceiptJSON: ReturnReceiptJSON?, queuePriority: Operation.QueuePriority) async -> CreatePersistedMessageReceivedFromReceivedObvMessageResult {

        os_log("Call to createPersistedMessageReceivedFromReceivedObvMessage for obvMessage %{public}@", log: Self.log, type: .debug, obvMessage.messageIdentifierFromEngine.debugDescription)

        // Create a persisted message received
        
        let op1 = CreatePersistedMessageReceivedFromReceivedObvMessageOperation(obvMessage: obvMessage,
                                                                                messageJSON: messageJSON,
                                                                                source: source,
                                                                                returnReceiptJSON: returnReceiptJSON)
        let op2 = TryToAutoReadDiscussionsReceivedMessagesThatRequireUserActionOperation(input: .operationProvidingDiscussionPermanentID(op: op1))
        let composedOp1 = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        composedOp1.queuePriority = queuePriority
        await coordinatorsQueue.addAndAwaitOperation(composedOp1)

        switch op1.result {
        case .cannotCreateReceivedMessageThatAlreadyExpired:
            return .cannotCreateReceivedMessageThatAlreadyExpired
        case .messageIsPriorToLastRemoteDeletionRequest:
            return .messageIsPriorToLastRemoteDeletionRequest
        case .couldNotFindGroupV2InDatabase(let groupIdentifier):
            return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
        case .couldNotFindContactInDatabase(contactCryptoId: let contactCryptoId):
            return .couldNotFindContactInDatabase(contactCryptoId: contactCryptoId)
        case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
            return .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactCryptoId)
        case .contactIsNotPartOfTheGroup(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            return .contactIsNotPartOfTheGroup(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
        case nil:
            return .receivedMessageCreationFailure
        case .messageCreated(discussionPermanentID: _):
            break
        }

        guard composedOp1.isFinished && !composedOp1.isCancelled else {
            assertionFailure()
            return .receivedMessageCreationFailure
        }

        // If we reach this point, the received message was properly created and some messages may have been auto-read
        // We asynchronously post this information to our other owned devices
        
        if op2.ownedIdentityHasAnotherReachableDevice {
            let postOp = PostLimitedVisibilityMessageOpenedJSONEngineOperation(op: op2, obvEngine: obvEngine)
            postOp.addDependency(op2)
            queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
        }

        assert(op1.isFinished)
        
        // Determine the attachments that should be downloaded now
        let downloadOp = DetermineAttachmentsProcessingRequestForMessageReceivedOperation(kind: .allAttachmentsOfMessage(op: op1))
        await queueAndAwaitCompositionOfOneContextualOperation(op1: downloadOp, queuePriority: queuePriority)
        
        assert(downloadOp.isFinished && !downloadOp.isCancelled)
        
        return .receivedMessageCreated(attachmentsProcessingRequest: downloadOp.attachmentsProcessingRequest ?? .doNothing)

    }

    
    enum CreatePersistedMessageSentFromReceivedObvOwnedMessageResult {
        case sentMessageCreated(attachmentsProcessingRequest: ObvAttachmentsProcessingRequest)
        case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
        case couldNotFindOneToOneContactInDatabase(contactCryptoId: ObvCryptoId)
        case couldNotFindContactInDatabase(contactCryptoId: ObvCryptoId)
        case sentMessageCreationFailure
        case remoteDeleteRequestSavedForLaterWasApplied
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
        
        let messageSentPermanentId: MessageSentPermanentID
        
        switch op1.result {
        case .couldNotFindGroupV2InDatabase(groupIdentifier: let groupIdentifier):
            return .couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
        case .couldNotFindOneToOneContactInDatabase(contactCryptoId: let contactCryptoId):
            return .couldNotFindOneToOneContactInDatabase(contactCryptoId: contactCryptoId)
        case .couldNotFindContactInDatabase(contactCryptoId: let contactCryptoId):
            return .couldNotFindContactInDatabase(contactCryptoId: contactCryptoId)
        case nil:
            assertionFailure()
            return .sentMessageCreationFailure
        case .remoteDeleteRequestSavedForLaterWasApplied:
            return .remoteDeleteRequestSavedForLaterWasApplied
        case .sentMessageCreated(messageSentPermanentId: let _messageSentPermanentId):
            messageSentPermanentId = _messageSentPermanentId
        }

        // If we reach this point, the message was properly created. We can determine the attachments to download now.

        let downloadOp = DetermineAttachmentsProcessingRequestForMessageSentOperation(kind: .allAttachmentsOfMessage(messageSentPermanentId: messageSentPermanentId))
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


// MARK: - Implementing ExpirationMessagesManagerDelegate

extension PersistedDiscussionsUpdatesCoordinator: ExpirationMessagesManagerDelegate {
    
    func wipeAllMessagesThatExpiredEarlierThanNow(launchedByBackgroundTask: Bool) async throws {
        
        let op1 = WipeExpiredMessagesOperation(launchedByBackgroundTask: launchedByBackgroundTask)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "WipeExpiredMessagesOperation did cancel")
        }

    }
    
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


// MARK: - WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperationDelegate

extension PersistedDiscussionsUpdatesCoordinator: WipeAllReadOnceAndLimitedVisibilityMessagesAfterLockOutOperationDelegate {
    
    func setExtensionFailedToWipeAllEphemeralMessagesBeforeDateOnUserDefaults(timestampOfLastMessageToWipe: Date?) {
        guard let userDefaults else { assertionFailure(); return }
        userDefaults.setExtensionFailedToWipeAllEphemeralMessagesBeforeDate(with: timestampOfLastMessageToWipe)
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


// MARK: - ScreenCaptureDetector utils

extension PersistedDiscussionsUpdatesCoordinator {
    
    func processUpdatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) async {
        await self.screenCaptureDetector?.processUpdatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(discussionPermanentID: discussionPermanentID, messagePermanentIDs: messagePermanentIDs)
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


// MARK: - UserDefault extension for refreshing objects inserted by the share extension

extension UserDefaults {
    
    func deepRefreshObjectsModifiedByShareExtension(viewContext: NSManagedObjectContext) {
        let objectsModifiedByShareExtensionURLAndEntityName = self.objectsModifiedByShareExtensionURLAndEntityName
        guard !objectsModifiedByShareExtensionURLAndEntityName.isEmpty else { return }
        self.resetObjectsModifiedByShareExtension()
        objectsModifiedByShareExtensionURLAndEntityName.forEach { (objectURI, entityName) in
            viewContext.deepRefresh(objectURI: objectURI, entityName: entityName)
        }
    }
    
}


// MARK: - ReceivedReturnReceiptScheduler

/// This scheduler guarantees atomic processing of a received return receipt.
///
/// This scheduler guarantees atomic processing of a received return receipt by ensuring two sequential steps:
/// 1. determining required tasks for complete processing and
/// 2. applying these tasks based on previously processed return receipts.
///
/// The atomic nature of this group of two operations prevents discrepancies in the process, thus maintaining data consistency.
fileprivate actor ReceivedReturnReceiptScheduler {
    
    private var continuationsOfWaitingReceipts = [CheckedContinuation<Void, Never>]()
    private var isProcessingReceipt = false
    
    func waitForTurn() async {
        
        if isProcessingReceipt {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                if isProcessingReceipt {
                    continuationsOfWaitingReceipts.insert(continuation, at: 0)
                } else {
                    isProcessingReceipt = true
                    continuation.resume()
                }
            }
        } else {
            isProcessingReceipt = true
        }
        
    }
    
    func endOfTurn() {
        if let continuation = continuationsOfWaitingReceipts.popLast() {
            continuation.resume()
        } else {
            isProcessingReceipt = false
        }
    }
    
}


// MARK: - ReceivedContinuousLocationRateLimiter


/// The RateLimiter actor functions to limit the rate at which shared continuous locations are processed when received.
///
/// This feature is especially beneficial after a long period of offline app usage, during which time contacts may have potentially sent numerous geolocations. In such situations, we aim to avoid processing multiple outdated location messages.
/// The RateLimiter fulfills this objective by temporarily pausing the handling of "older" location messages until a newer message arrives. Upon arrival of a more recent message, any older location messages are discarded.
fileprivate actor ReceivedContinuousLocationRateLimiter {
    
    enum Action {
        case process
        case cancelled
    }
    
    private static let thresholdForImmediateProcessing = TimeInterval(minutes: 1)
    
    private var mostRecentUploadTimestampForDevice = [ObvContactDeviceIdentifier: (uploadTimestampFromServer: Date, sleepTask: Task<Void, Error>)]()
    
    func limitRateOfContinuousLocationOfContactDevice(with contactDeviceIdentifier: ObvContactDeviceIdentifier, uploadTimestampFromServer: Date, downloadTimestampFromServer: Date) async -> Action {
        
        // A recent location should always be processed immediately (and cancel any earlier waiting task)
        
        if downloadTimestampFromServer.timeIntervalSince(uploadTimestampFromServer) < Self.thresholdForImmediateProcessing {
            if let (previousMostRecentUploadTimestamp, previousSleepTask) = mostRecentUploadTimestampForDevice[contactDeviceIdentifier], previousMostRecentUploadTimestamp < uploadTimestampFromServer {
                _ = mostRecentUploadTimestampForDevice.removeValue(forKey: contactDeviceIdentifier)
                previousSleepTask.cancel()
            }
            return .process
        }
        
        
        // Upon reception of an "older" location, immediate processing is withheld.
        // In cases where another location has already been placed on hold, two scenarios may unfold:
        // - The previously received position holds a more recent timestamp than the current one -> we discard the currently held message.
        // - Conversely, if the previous position's timestamp predates that of the newly arrived message -> we dismiss the older message and place the latest location on hold, waiting for any potentially fresher positions to surface.
        
        if let (previousMostRecentUploadTimestamp, previousSleepTask) = mostRecentUploadTimestampForDevice[contactDeviceIdentifier] {
            if previousMostRecentUploadTimestamp > uploadTimestampFromServer {
                return .cancelled
            } else {
                previousSleepTask.cancel()
            }
        }
        
        let sleepTask = Task { try await Task.sleep(seconds: 10) } // Note that if this task is cancelled, the sleep method immediately throws a CancellationError

        mostRecentUploadTimestampForDevice[contactDeviceIdentifier] = (uploadTimestampFromServer, sleepTask)
        
        do {
            try await sleepTask.value
        } catch {
            // This event occurs when a fresher location surfaces while another previously received position was on hold.
            // Consequently, the task associated with the aged location is cancelled, leading us to this point.
            // In such circumstances, we refrain from processing the obsolete position and return `.cancelled`.
            assert(error is CancellationError)
            return .cancelled
        }
        
        // If we reach this point, no recent location was received while we were on hold. We waited long enough: we can now process this location.
        
        return .process
        
    }
    
}
