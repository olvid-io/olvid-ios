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

import Foundation
import OSLog
import CoreData
@preconcurrency import ObvEngine
import ObvCoreDataStack
import ObvCrypto
import OlvidUtils
import ObvTypes
import ObvUICoreData
import ObvSettings
import ObvLocation
import ObvAppCoreConstants
import ObvAppTypes
import ObvUICoreDataStructs
import ObvAppInboxService
import ObvAppInboxTypes
import LinkPresentation
import UniformTypeIdentifiers
import ObvHistoryTransfer


protocol PersistedDiscussionsUpdatesCoordinatorDelegate: AnyObject {
    
    func decryptAndProcessReceiptsStoredForLater(_ coordinator: PersistedDiscussionsUpdatesCoordinator, ownedCryptoId: ObvCryptoId, elements: ObvReturnReceiptElements) async
    
    func newReceivedWebrtcHistoryTransferMessageJSON(_ coordinator: PersistedDiscussionsUpdatesCoordinator, webrtcHistoryTransferMessageJSON: WebRTCHistoryTransferMessageJSON, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier) async throws
    func newWebrtcHistoryTransferInterruptionRequest(_ coordinator: PersistedDiscussionsUpdatesCoordinator, transferId: String) async throws
    
}


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
    private let receivedContinuousLocationRateLimiter = ReceivedContinuousLocationRateLimiter()
    private let loadItemProviderHelper = LoadItemProviderHelper()
    private let linkPreviewFetcherForDraft = LinkPreviewFetcherForDraft()

    private var userDefaults: UserDefaults? { UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier) }
    private var screenCaptureDetector: ScreenCaptureDetector?
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?
    
    private var currentlyProcessingObsoleteMessageIdentifiersForLater = false
    
    private var taskForDiscardingExpiredPersistedLocationContinuousReceived: Task<Void, Never>? = nil

    private let currentDeviceLiveLocationSharingHelper = CurrentDeviceLiveLocationSharingHelper()
    
    private let historyTransferConfirmationRequestHelper = HistoryTransferConfirmationRequestHelper()
    
    /// Allows to keep receipts for later, when they are received before the concerned message (which happens when the message is sent from another owned device).
    /// Also allows to keep ObvMessage and ObvOwnedMessage for later, marking them as onHold at the engine level.
    private let appInboxService: ObvAppInboxService
    
    weak var delegate: PersistedDiscussionsUpdatesCoordinatorDelegate? // In practice, it's the AppCoordinatorsHolder
    
    init(obvEngine: ObvEngine,
         appInboxService: ObvAppInboxService,
         coordinatorsQueue: OperationQueue,
         queueForComposedOperations: OperationQueue,
         queueForOperationsMakingEngineCalls: OperationQueue,
         queueForSyncHintsComputationOperation: OperationQueue) {
        self.obvEngine = obvEngine
        self.appInboxService = appInboxService
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        self.queueForOperationsMakingEngineCalls = queueForOperationsMakingEngineCalls
        self.queueForSyncHintsComputationOperation = queueForSyncHintsComputationOperation
        listenToNotifications()
        Task {
            await PersistedMessageReceived.addObvObserver(self)
            await ReceivedFyleMessageJoinWithStatus.addObvObserver(self)
            await PersistedDiscussion.addObvObserver(self)
            await PersistedObvOwnedIdentity.addObvObserver(self)
            await PersistedGroupV2Member.addObvObserver(self)
            await PersistedMessage.addObserver(self)
            await PersistedObvContactIdentity.addObvObserver(self)
            await PersistedLocationContinuousReceived.addPersistedLocationContinuousReceivedObserver(self)
            await PersistedLocationContinuousSent.addPersistedLocationContinuousSentObserver(self)
            screenCaptureDetector = await ScreenCaptureDetector()
            await screenCaptureDetector?.setDelegate(to: self)
            await screenCaptureDetector?.startDetecting()
            discardExpiredPersistedLocationContinuousReceived()
        }
    }
    
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {

        if forTheFirstTime {
            LoadItemProviderHelper.requestDeletionOfObsoleteDirectoriesForLoadedNSItemProviders()
            migrateReadMetadataOfPersistedMessageReceived()
            periodicallyRefreshReceivedAttachmentProgress()
            await processUnprocessedRecipientInfosThatCanNowBeProcessed()
            deleteEmptyLockedDiscussion()
            trashOrphanedFilesFoundInTheFylesDirectory()
            // No need to delete orphaned one to one discussions (i.e., without contact), they are cascade deleted
            // No need to delete orphaned group discussions (i.e., without contact group), they are cascade deleted
            // No need to delete orphaned PersistedMessageTimestampedMetadata, i.e., without message), they are cascade deleted
            bootstrapMessagesToBeWiped(preserveReceivedMessages: true)
            deleteOldOrOrphanedDatabaseEntries()
            cleanExpiredMuteNotificationsSetting()
            cleanOrphanedPersistedMessageTimestampedMetadata()
            synchronizeAllOneToOneDiscussionTitlesWithContactNameOperation()
            refreshNumberOfNewMessagesForAllDiscussions()
            await fixSortDateOfDiscussionWithMessagesButWithNoSortDate()
            await replayGroupPastEvents(.forAllGroupMembersThatNeedReplayOfPastEvents)
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
        guard OlvidUserActivitySingleton.shared.currentDiscussionID != nil else { return }
        
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
                Task { [weak self] in
                    await self?.sendAppropriateDiscussionSharedConfigurationsToContact(
                        input: .contactDevice(contactDeviceObjectID: contactDeviceObjectID))
                    await self?.processUnprocessedRecipientInfosThatCanNowBeProcessed()
                }
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
                Task { try await self?.processUserWantsToUpdateDiscussionLocalConfiguration(with: value, localConfigurationObjectID: localConfigurationObjectID) }
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
            ObvMessengerInternalNotification.observeUserHasOpenedAReceivedAttachment { [weak self] receivedFyleJoinID in
                self?.processUserHasOpenedAReceivedAttachment(receivedFyleJoinID: receivedFyleJoinID)
            },
            ObvMessengerInternalNotification.observeUserWantsToReorderDiscussions { [weak self] (discussionObjectIds, ownedIdentity, completionHandler) in
                Task { [weak self] in
                    guard let self else { completionHandler?(false); return }
                    do {
                        try await processUserWantsToReorderDiscussions(discussionObjectIds: discussionObjectIds, ownedIdentity: ownedIdentity)
                        completionHandler?(true)
                    } catch {
                        completionHandler?(false)
                    }
                }
            },
            ObvMessengerInternalNotification.observeBetaUserWantsToDebugCoordinatorsQueue { [weak self] in
                self?.processBetaUserWantsToDebugCoordinatorsQueue()
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
            ObvEngineNotificationNew.observeServerAndInboxContainNoMoreUnprocessedMessages(within: NotificationCenter.default) { [weak self] ownedCryptoId, downloadTimestampFromServer in
                Task { [weak self] in await self?.processServerAndInboxContainNoMoreUnprocessedMessages(ownedCryptoId: ownedCryptoId, downloadTimestampFromServer: downloadTimestampFromServer) }
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
    
    
    /// This bootstrap method identifies and fixes discussions affected by a rare bug in early versions of v3.10.
    /// In these versions, some `PersistedDiscussion` instances incorrectly have a `nil` `sortDate`
    /// despite containing a non-empty array of `messages`.
    private func fixSortDateOfDiscussionWithMessagesButWithNoSortDate() async {
        do {
            let discussionObjectIDs = try await self.getIdsOfDiscussionsWithMessagesButWithNoSortDate()
            for discussionObjectID in discussionObjectIDs {
                let op1 = ResetSortDateToMostRecentMessageTimestampIfRequiredOperation(discussionObjectID: discussionObjectID)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                await self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                guard composedOp.isFinished && !composedOp.isCancelled else {
                    Self.logger.fault("Failed to fix sort date of discussion")
                    assertionFailure()
                    continue
                }
            }
        } catch {
            Self.logger.fault("Could not fix sort date of discussions: \(error)")
        }
    }
    
    
    private func getIdsOfDiscussionsWithMessagesButWithNoSortDate() async throws -> [TypeSafeManagedObjectID<PersistedDiscussion>] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[TypeSafeManagedObjectID<PersistedDiscussion>], any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let discussionIds = try PersistedDiscussion.getIdsOfDiscussionsWithMessagesButWithNoSortDate(within: context)
                    return continuation.resume(returning: discussionIds)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }

    }
    
    
    /// Previously, we stored the timestamp when a received message was read as metadata associated with the message.
    /// However, this approach impeded the implementation of batch updates to mark all new messages as 'not new'.
    /// To resolve this issue, we migrated to storing the "read" timestamp directly in the `PersistedMessageReceived` table.
    /// This method lazily handles migration from the legacy "read" metadata storage format.
    private func migrateReadMetadataOfPersistedMessageReceived() {
        Task {
            
            guard let userDefaults else { assertionFailure(); return }
            let userDefaultsKey = "PersistedDiscussionsUpdatesCoordinator.migrateReadMetadataOfPersistedMessageReceived.wasFullyPerformed"
            guard userDefaults.value(forKey: userDefaultsKey) == nil else { return }
            
            var migrationIsFinished = false
            
            while(!migrationIsFinished) {
                
                let op1 = MigrateReadMetadataOfPersistedMessageReceivedOperation()
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                composedOp.queuePriority = .low
                await self.coordinatorsQueue.addAndAwaitOperation(composedOp)
                
                guard composedOp.isFinished && !composedOp.isCancelled else {
                    Self.logger.fault("Failed to migrate read metadatas of received messsages. Will retry in a few seconds.")
                    assertionFailure()
                    try? await Task.sleep(seconds: Double.random(in: 1.0..<10.0))
                    continue
                }
                
                migrationIsFinished = op1.migrationIsFinished
                
                Self.logger.info("Is read metadata about received messages finished: \(migrationIsFinished)")
                
                if migrationIsFinished {
                    userDefaults.setValue(true, forKey: userDefaultsKey)
                    return
                } else {
                    try? await Task.sleep(seconds: Double.random(in: 1.0..<2.0))
                }
                
            }
            
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


// MARK: - Implementing PersistedLocationContinuousReceivedObserver

extension PersistedDiscussionsUpdatesCoordinator: PersistedLocationContinuousReceivedObserver {
    
    func aPersistedLocationContinuousReceivedWasInserted() async {
        discardExpiredPersistedLocationContinuousReceived()
    }
    
}


// MARK: - Implementing PersistedLocationContinuousSentObserver

extension PersistedDiscussionsUpdatesCoordinator: PersistedLocationContinuousSentObserver {
    
    func aPersistedLocationContinuousSentWasInserted() async {
        discardExpiredPersistedLocationContinuousReceived() // Also used for location sent from other owned devices
    }
    
}


// MARK: - Discarding obsolete PersistedLocationContinuousReceived

extension PersistedDiscussionsUpdatesCoordinator {
    
    /// Discards expired `PersistedLocationContinuousReceived` entries and schedules future cleanup.
    ///
    /// This method performs two main tasks:
    /// 1. **Expiration Check**: Iterates through all `PersistedLocationContinuousReceived` entries and removes those that have expired.
    /// 2. **Rescheduling**: After cleanup, it identifies the earliest expiration date among the remaining entries and schedules a recursive call to itself for that time.
    ///
    /// This method is automatically invoked during app bootstrap and whenever a new `PersistedLocationContinuousReceived` or `PersistedLocationContinuousSent` is created.
    /// It ensures that only valid, non-expired location data is retained.
    private func discardExpiredPersistedLocationContinuousReceived() {
        taskForDiscardingExpiredPersistedLocationContinuousReceived?.cancel()
        taskForDiscardingExpiredPersistedLocationContinuousReceived = Task {

            let op1 = DiscardExpiredPersistedLocationContinuousReceivedOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await self.coordinatorsQueue.addAndAwaitOperation(composedOp)
            guard composedOp.isFinished && !composedOp.isCancelled else {
                Self.logger.fault("Failed to discard expired location continuous received")
                assertionFailure()
                return
            }
            
            do {
                guard let nextExpirationDate = try await Self.getEarliestExpirationDateOfPersistedLocationContinuousReceived() else { return }
                let timeToWait = nextExpirationDate.timeIntervalSinceNow
                guard timeToWait > 0 else { return }
                try await Task.sleep(seconds: timeToWait)
                Task.detached { [weak self] in // Detached so that the child task is not cancelled by cancelling this task
                    guard let self else { return }
                    discardExpiredPersistedLocationContinuousReceived()
                }
            } catch {
                if error is CancellationError { return }
                Self.logger.fault("Failure while getting the earliest expiration date: \(error)")
                assertionFailure()
                return
            }
            
        }
    }
    
    
    /// Returns the earliest expiration date among all continuous location received and locations sent from other owned devices.
    private static func getEarliestExpirationDateOfPersistedLocationContinuousReceived() async throws -> Date? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Date?, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let dateForReceived = try PersistedLocationContinuousReceived.getEarliestExpirationDateAfterNow(within: context)
                    let dateForSentFromOtherOwnedDevice = try PersistedLocationContinuousSent.getEarliestExpirationDateFromOtherOwnedDevicesAfterNow(within: context)
                    if dateForReceived == nil && dateForSentFromOtherOwnedDevice == nil {
                        return continuation.resume(returning: nil)
                    } else {
                        let date = min(dateForReceived ?? .distantFuture, dateForSentFromOtherOwnedDevice ?? .distantFuture)
                        return continuation.resume(returning: date)
                    }
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
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

// MARK: - Implementing PersistedObvOwnedIdentityObserver

extension PersistedDiscussionsUpdatesCoordinator: PersistedObvOwnedIdentityObserver {
    
    func aPersistedObvOwnedIdentityWasDeleted(ownedCryptoId: ObvCryptoId) async {
        let operationsToQueue = getOperationsForDeletingOrphanedDatabaseItems { [weak self] _ in
            self?.trashOrphanedFilesFoundInTheFylesDirectory()
            self?.deleteOldOrOrphanedDatabaseEntries()
            self?.cleanExpiredMuteNotificationsSetting()
            self?.cleanOrphanedPersistedMessageTimestampedMetadata()
        }
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        await coordinatorsQueue.addAndAwaitOperations(operationsToQueue)
        await appInboxService.deleteMessageIdentifiersForLater(ownedCryptoId: ownedCryptoId)
    }

}


// MARK: - Implementing PersistedDiscussionObserver

extension PersistedDiscussionsUpdatesCoordinator: PersistedDiscussionObserver {

    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedDiscussionChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        // This coordinator does nothing in this case
    }
        
    func aPersistedDiscussionStatusChanged(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, status: ObvUICoreData.PersistedDiscussion.Status) async {
        // This coordinator does nothing in this case
    }
    
    func aPersistedDiscussionIsArchivedChanged(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, isArchived: Bool) async {
        // This coordinator does nothing in this case
    }
    
    func aPersistedDiscussionWasDeleted(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async {
        // This coordinator does nothing in this case
    }
    
    func aPersistedDiscussionWasRead(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier, localDateWhenDiscussionRead: Date) async {
        // This coordinator does nothing in this case
    }
    
    
    /// When a discussion is inserted or reactivated, we query the `ObvAppInboxService` for all message identifiers that were saved for this discussion.
    /// For each identifier, we request the corresponding `ObvMessage` or `ObvOwnedMessage` from the engine and attempt to reprocess the message.
    /// Typically, this reprocessing is successful, allowing us to request the deletion of the identifier from the `ObvAppInboxService`.
    func aPersistedDiscussionWasInsertedOrReactivated(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier) async {
        
        sendPersistedDiscussionSharedConfigurationIfAllowedTo(ownedCryptoId: discussionIdentifier.ownedCryptoId, discussionIdentifier: discussionIdentifier.toDiscussionIdentifier())
        
        let messageIdentifiersForLater = await appInboxService.fetchMessageIdentifiersForLater(identifierOfExpectedDiscussion: discussionIdentifier)

        await self.reprocessEngineMessagesForLater(messageIdentifiersForLater: messageIdentifiersForLater)

    }
    
    
    /// When a new discussion is inserted in database (or when a locked/pre discussion becomes active again), we send our shared configuration (that was applied using the default settings for new discussions) to all contacts and owned devices.
    private func sendPersistedDiscussionSharedConfigurationIfAllowedTo(ownedCryptoId: ObvCryptoId, discussionIdentifier: DiscussionIdentifier) {
        let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(ownedCryptoId: ownedCryptoId, discussionId: discussionIdentifier, sendTo: .allContactsAndOtherOwnedDevices, obvEngine: obvEngine)
        op.queuePriority = .low
        op.completionBlock = { if op.isCancelled { assertionFailure() } }
        coordinatorsQueue.addOperation(op)
    }

}


// MARK: - Implementing PersistedMessageObserver

extension PersistedDiscussionsUpdatesCoordinator: PersistedMessageObserver {
    
    /// When a message is inserted, we query the `ObvAppInboxService` for all message identifiers that were saved for this message. These
    /// engine messages typically are reactions, poll votes, or request to open a sensitive message).
    /// For each identifier, we request the corresponding `ObvMessage` or `ObvOwnedMessage` from the engine and attempt to reprocess the message.
    /// Typically, this reprocessing is successful, allowing us to request the deletion of the identifier from the `ObvAppInboxService`.
    func aPersistedSentOrReceivedMessageWasInserted(messageIdentifier: ObvMessageAppIdentifier) async {
        let messageIdentifiersForLater = await appInboxService.fetchMessageIdentifiersForLater(identifierOfExpectedMessage: messageIdentifier)
        debugPrint(messageIdentifiersForLater.count)
        await self.reprocessEngineMessagesForLater(messageIdentifiersForLater: messageIdentifiersForLater)
    }
    
}


// MARK: - Reprocessing messages kept for later

extension PersistedDiscussionsUpdatesCoordinator {

    /// Upon certain app database changes (e.g., discussion insertion, discussion activation, new group member added, etc.), this coordinator gets
    /// notified and queries the `ObvAppInboxService` for (engine) message identifiers related to these events.
    /// This method processes a list of these identifiers to reprocess the corresponding engine messages.
    func reprocessEngineMessagesForLater(messageIdentifiersForLater: [ObvMessageIdentifier]) async {
        
        for messageIdentifierForLater in messageIdentifiersForLater {
            
            let obvMessageOrObvOwnedMessage: ObvMessageOrObvOwnedMessage
            do {
                guard let _obvMessageOrObvOwnedMessage = try await obvEngine.fetchOnHoldMessage(messageId: messageIdentifierForLater) else {
                    await appInboxService.deleteMessageIdentifiersForLater(messageId: messageIdentifierForLater)
                    continue
                }
                obvMessageOrObvOwnedMessage = _obvMessageOrObvOwnedMessage
            } catch {
                assertionFailure()
                Self.logger.fault("Could not feth on hold message from engine: \(error.localizedDescription)")
                continue
            }
            
            switch obvMessageOrObvOwnedMessage {
                
            case .obvMessage(let obvMessage):
                let result = await processReceivedObvMessage(obvMessage, source: .engine, queuePriority: .veryHigh)
                switch result {
                    
                case .done(let attachmentsProcessingRequest):
                    try? await obvEngine.messageWasProcessed(messageId: obvMessage.messageId, attachmentsProcessingRequest: attachmentsProcessingRequest)
                    await appInboxService.deleteMessageIdentifiersForLater(messageId: messageIdentifierForLater)
                    
                case .definitiveFailure:
                    try? await obvEngine.messageWasProcessed(messageId: obvMessage.messageId, attachmentsProcessingRequest: .deleteAll)
                    await appInboxService.deleteMessageIdentifiersForLater(messageId: messageIdentifierForLater)
                    
                case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                    do {
                        try await appInboxService.storeOrReplaceMessageIdentifierForLater(
                            messageUIDFromEngine: obvMessage.messageUID,
                            messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                            identifierOfExpectedDiscussion: discussionIdentifier)
                    } catch {
                        Self.logger.fault("Could not store or replace message identifier stored for later: \(error.localizedDescription, privacy: .public)")
                    }

                case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                    do {
                        try await appInboxService.storeOrReplaceMessageIdentifierForLater(
                            messageUIDFromEngine: obvMessage.messageUID,
                            messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                            identifierOfExpectedGroup: groupIdentifier,
                            cryptoIdOfExpectedContact: contactCryptoId)
                    } catch {
                        Self.logger.fault("Could not store or replace message identifier stored for later: \(error.localizedDescription, privacy: .public)")
                    }
                    
                case .couldNotFindMessageInDatabase(messageIdentifier: let messageIdentifier):
                    do {
                        try await appInboxService.storeOrReplaceMessageIdentifierForLater(
                            messageUIDFromEngine: obvMessage.messageUID,
                            messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                            identifierOfExpectedMessage: messageIdentifier)
                    } catch {
                        Self.logger.fault("Could not store or replace message identifier stored for later: \(error.localizedDescription, privacy: .public)")
                    }
                    
                case .obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived:
                    assertionFailure("This result is unexpected in this context")
                    continue
                    
                }
                
            case .obvOwnedMessage(let obvOwnedMessage):
                let result = await processReceivedObvOwnedMessage(obvOwnedMessage)
                switch result {
                    
                case .done(attachmentsProcessingRequest: let attachmentsProcessingRequest):
                    try? await obvEngine.messageWasProcessed(messageId: obvOwnedMessage.messageId, attachmentsProcessingRequest: attachmentsProcessingRequest)
                    await appInboxService.deleteMessageIdentifiersForLater(messageId: messageIdentifierForLater)
                    
                case .definitiveFailure:
                    try? await obvEngine.messageWasProcessed(messageId: obvOwnedMessage.messageId, attachmentsProcessingRequest: .deleteAll)
                    await appInboxService.deleteMessageIdentifiersForLater(messageId: messageIdentifierForLater)
                    
                case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                    do {
                        try await appInboxService.storeOrReplaceMessageIdentifierForLater(
                            messageUIDFromEngine: obvOwnedMessage.messageUID,
                            messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer,
                            identifierOfExpectedDiscussion: discussionIdentifier)
                    } catch {
                        Self.logger.fault("Could not store or replace message identifier stored for later: \(error.localizedDescription, privacy: .public)")
                    }

                case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                    do {
                        try await appInboxService.storeOrReplaceMessageIdentifierForLater(
                            messageUIDFromEngine: obvOwnedMessage.messageUID,
                            messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer,
                            identifierOfExpectedGroup: groupIdentifier,
                            cryptoIdOfExpectedContact: contactCryptoId)
                    } catch {
                        Self.logger.fault("Could not store or replace message identifier stored for later: \(error.localizedDescription, privacy: .public)")
                    }

                case .couldNotFindMessageInDatabase(messageIdentifier: let messageIdentifier):
                    do {
                        try await appInboxService.storeOrReplaceMessageIdentifierForLater(
                            messageUIDFromEngine: obvOwnedMessage.messageUID,
                            messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer,
                            identifierOfExpectedMessage: messageIdentifier)
                    } catch {
                        Self.logger.fault("Could not store or replace message identifier stored for later: \(error.localizedDescription, privacy: .public)")
                    }

                }
            }
            
        }
        
    }
    
}

// MARK: - ReceivedFyleMessageJoinWithStatusObserver

extension PersistedDiscussionsUpdatesCoordinator: ReceivedFyleMessageJoinWithStatusObserver {
    
    func newReturnReceiptToSendForReceivedFyleMessageJoinWithStatus(returnReceiptToSend: ObvTypes.ObvReturnReceiptToSend) async {
        do {
            try await obvEngine.postReturnReceiptsWithElements(returnReceiptsToSend: [returnReceiptToSend])
        } catch {
            assertionFailure()
        }
    }
    
}


// MARK: - PersistedMessageReceivedDelegate

extension PersistedDiscussionsUpdatesCoordinator: PersistedMessageReceivedObserver {
    
    func persistedMessageReceivedWasInserted(receivedMessage: PersistedMessageReceivedStructure) async {}
    
    func persistedMessageReceivedWasRead(ownedCryptoId: ObvCryptoId, messageIdFromServer: UID) async {}
    
    func newReturnReceiptsToSendForPersistedMessageReceived(returnReceiptsToSend: [ObvReturnReceiptToSend]) async {
        do {
            try await obvEngine.postReturnReceiptsWithElements(returnReceiptsToSend: returnReceiptsToSend)
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
        
    }
    

    /// Called by the `UserNotificationsCoordinator` when a received user notification contains an `ObvMessage` that should be stored in the app database.
    func persistObvMessageFromUserNotification(obvMessage: ObvMessage, queuePriority: Operation.QueuePriority) async -> PersistObvMessageFromUserNotificationResult {
        
        let result = await processReceivedObvMessage(obvMessage, source: .userNotification, queuePriority: queuePriority)
        
        switch result {
        case .done(attachmentsProcessingRequest: _):
            return .success
        case .definitiveFailure:
            return .notificationMustBeRemoved
        case .obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived:
            // This happens when we are notified of a new message without body but with an attachment. In that case, the content of the ObvMessage
            // from the notification center is insufficient to create a proper PersistedMessageReceived in database.
            return .notificationMustBeRemoved
        case .couldNotFindActiveDiscussionInDatabase:
            return .notificationMustBeRemoved
        case .contactIsNotPartOfGroupOrRequiresPermissions:
            return .notificationMustBeRemoved
        case .couldNotFindMessageInDatabase:
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
            with: .muteNotificationsEndDate(ObvMuteDurationOption.oneHour.endDateFromNow),
            discussionPermanentID: discussionPermanentID)
        
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
        }
        
    }
    
    
    
    private enum SendAppropriateDiscussionSharedConfigurationsToContactKind {
        case contactDevice(contactDeviceObjectID: TypeSafeManagedObjectID<PersistedObvContactDevice>)
        case groupMember(groupIdentifier: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId)
    }
    
    /// When receiving a NewPersistedObvContactDevice notification of a contact, we look for all group v2 discussions where this contact is a member and that we administrate.
    /// For each discussion found, we send the shared configuration.
    /// We also send the shared configuration of the one-to-one discussion we have with this contact.
    /// This method is also used when a contact that was a pending group v2 member accepts the invitation.
    private func sendAppropriateDiscussionSharedConfigurationsToContact(input: SendAppropriateDiscussionSharedConfigurationsToContactKind) async {
        
        switch input {
            
        case .contactDevice(contactDeviceObjectID: let contactDeviceObjectID):
            do {
                let (contactIdentifier, persistedDiscussionIdentifiers) = try await findAdministratedGroupV2DiscussionsAndOneToOneDiscussionWithContactOperation(contactDeviceObjectID: contactDeviceObjectID)
                for discussionId in persistedDiscussionIdentifiers {
                    let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(
                        ownedCryptoId: contactIdentifier.ownedCryptoId,
                        discussionId: discussionId,
                        sendTo: .specificContact(contactCryptoId: contactIdentifier.contactCryptoId),
                        obvEngine: obvEngine)
                    await queueForOperationsMakingEngineCalls.addAndAwaitOperation(op)
                    assert(op.isFinished && !op.isCancelled)
                }
            } catch {
                assertionFailure()
            }
            
        case .groupMember(groupIdentifier: let groupIdentifier, memberCryptoId: let memberCryptoId):
            let ownedCryptoId: ObvCryptoId = groupIdentifier.ownedCryptoId
            let discussionId: DiscussionIdentifier = .groupV2(id: .groupV2Identifier(groupV2Identifier: groupIdentifier.identifier.appGroupIdentifier))
            let op = SendPersistedDiscussionSharedConfigurationIfAllowedToOperation(ownedCryptoId: ownedCryptoId, discussionId: discussionId, sendTo: .specificContact(contactCryptoId: memberCryptoId), obvEngine: obvEngine)
            await queueForOperationsMakingEngineCalls.addAndAwaitOperation(op)
            assert(op.isFinished && !op.isCancelled)
            
        }
        
    }
    
    
    /// Helper methods for `sendAppropriateDiscussionSharedConfigurationsToContact(...)`
    private func findAdministratedGroupV2DiscussionsAndOneToOneDiscussionWithContactOperation(contactDeviceObjectID: TypeSafeManagedObjectID<PersistedObvContactDevice>) async throws -> (contactIdentifier: ObvContactIdentifier, discussionIdentifiers: [DiscussionIdentifier]) {
        
        let (contactIdentifier, persistedDiscussionIdentifiers) = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(ObvContactIdentifier, [DiscussionIdentifier]), any Error>) in
            
            ObvStack.shared.performBackgroundTask { context in
                
                do {
                    // Find the contact device and corresponding contact
                    
                    let device = try PersistedObvContactDevice.get(contactDeviceObjectID: contactDeviceObjectID.objectID, within: context)
                    
                    guard let device else {
                        throw Self.makeError(message: "Could not find contact device")
                    }
                    
                    guard let contact = device.identity else {
                        throw Self.makeError(message: "Could not find contact")
                    }
                    
                    let contactIdentifier = try contact.obvContactIdentifier
                    
                    // Find all group v2 that include this contact and keep those that we administrate
                    
                    let administratedGroups = try PersistedGroupV2.getAllPersistedGroupV2(whereContactIdentitiesInclude: contact)
                        .filter({ $0.ownedIdentityIsAllowedToChangeSettings })

                    // Save the identifiers of the corresponding discussions
                    
                    var persistedDiscussionIdentifiers = administratedGroups.compactMap({ try? $0.discussion?.identifier })

                    if let oneToOneDiscussionIdentifier = try? contact.oneToOneDiscussion?.identifier {
                        persistedDiscussionIdentifiers.append(oneToOneDiscussionIdentifier)
                    }
                    
                    return continuation.resume(returning: (contactIdentifier, persistedDiscussionIdentifiers))
                    
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
                
            }
        }
        return (contactIdentifier, persistedDiscussionIdentifiers)
    }
    
    
    /// When receiving a `PersistedContactGroupHasUpdatedContactIdentities` notification from the App, we check whether there exists unprocessed (unsent) messages within the corresponding group discussion.
    /// If this is the case, we can now post them.
    /// We also insert the the system messages of category `.contactJoinedGroup` and `.contactLeftGroup` as appropriate.
    /// We also reprocess any received message kept for later (which is relevant for a joined group for which we received a message before knowing a bout the group member).
    private func processPersistedContactGroupHasUpdatedContactIdentitiesNotification(persistedContactGroupObjectID: NSManagedObjectID, insertedContacts: Set<PersistedObvContactIdentity>, removedContacts: Set<PersistedObvContactIdentity>) {
                
        let obvEngine = self.obvEngine
        
        ObvStack.shared.performBackgroundTask { [weak self] context in
        
            guard let self else { return }
            
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
                let composedOps = ops.map { self.createCompositionOfTwoContextualOperation(op1: $0.0, op2: $0.1) }
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
                    let composedOp = self.createCompositionOfOneContextualOperation(op1: op1)
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
                    let composedOp = self.createCompositionOfOneContextualOperation(op1: op1)
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
            self.coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)
            
            // Task 5: Replay any existing received message kept for later

            if let obvGroupIdentifier = try? contactGroup.obvGroupIdentifier {
                
                Task { [weak self] in
                    
                    guard let self else { return }
                    
                    let messageIdentifiersForLater = await appInboxService.fetchMessageIdentifiersForLater(
                        identifierOfExpectedGroup: .groupV1(obvGroupIdentifier),
                        cryptoIdOfExpectedContact: nil)
                    
                    await reprocessEngineMessagesForLater(messageIdentifiersForLater: messageIdentifiersForLater)
                    
                }
                
            }
            
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

        do {
            let op = SendGlobalDeleteDiscussionJSONOperation(persistedDiscussionObjectID: discussionObjectID.objectID, deletionType: deletionType, obvEngine: obvEngine)
            op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
            operationsToQueue.append(.engineCall(op: op))
        }
        
        do {
            let op = SendEndSharingLocationJSONWhenDeletingDiscussionOperation(discussionIdentifier: .objectID(discussionObjectID.objectID), obvEngine: obvEngine)
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
        guard OlvidUserActivitySingleton.shared.currentDiscussionID?.permanentID != persistedDiscussionPermanentID else {
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

    
    private func processUserWantsToSendEditedVersionOfSentMessage(ownedCryptoId: ObvCryptoId, sentMessageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, newTextBody: AttributedString?) async {
        
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
        
        // Send read receipts.
        // Note that the check about whether we should send read receipts has been made already: if
        // the array of sent messages for read receipt is non-empty, it means we must send these
        // receipts.
        
        if let result = op1.result {
            switch result {
            case .processed(let receivedMessagesForReadReceipts):
                sendReadReceipts(receivedMessagesForReadReceipts: receivedMessagesForReadReceipts)
            case .couldNotFindActiveDiscussionInDatabase:
                return
            }
        }

    }
    
    
    /// This method is typically called after (locally) marking a complete discussion as read or when sending a draft (which also mark the discussion as read).
    /// In that case, we might have to send one read receipt per read messages (if
    /// appropriate given the current discussion or global configuration). If we receive a non-empty list here, it means that we *must* send these read receipts.
    /// Note that this method returns immediately.
    private func sendReadReceipts(receivedMessagesForReadReceipts: [TypeSafeManagedObjectID<PersistedMessageReceived>]) {
        ObvStack.shared.performBackgroundTask { context in
            PersistedMessageReceived.sendObvReturnReceiptForMessageReceived(objectIDs: receivedMessagesForReadReceipts, within: context)
            // We do **not** save the context. It is only used to fetch data, which is also the reason why the method is not
            // performed on any particular queue.
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

// MARK: - Implementing PersistedObvContactIdentityObserver

extension PersistedDiscussionsUpdatesCoordinator: PersistedObvContactIdentityObserver {
    
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedObvContactIdentityChanged(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        // We do nothing
    }
    
    /// When a user becomes "reachable" (either because a secure channel was created with one of their device, or thanks to a device's prekey), we are notified here.
    /// We then consider all the groups where this contact is
    /// - a non-pending member
    /// - such that the `NeedsReplayOfPastEvents` is `true`.
    /// For all these groups, we replay past events (i.e., we re-send own reactions and own poll votes) associated to messages sent/received during the period of time
    /// when this user was pending.
    func contactChangedAsAtLeastOneDeviceAllowsThemToReceiveMessages(contactIdentifier: ObvTypes.ObvContactIdentifier) async {
        await replayGroupPastEvents(.forSpecificContact(contactIdentifier: contactIdentifier))
    }
    
}


// MARK: - Replaying own reactions and poll votes for group members switching to non-pending state

extension PersistedDiscussionsUpdatesCoordinator {
    
    private enum GroupPastEventsToReplay {
        case forSpecificGroupMember(groupIdentifier: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId)
        case forSpecificContact(contactIdentifier: ObvTypes.ObvContactIdentifier)
        case forAllGroupMembersThatNeedReplayOfPastEvents
    }
    

    /// Sends pending group interactions to a member after their status changes from pending to non-pending.
    ///
    /// When a group v2 member transitions from the pending to the non-pending state,
    /// this method ensures they receive all relevant interactions that occurred while they were pending.
    /// Specifically, it sends:
    ///   - The current user's reactions on messages sent or received in the group during the member's pending period.
    ///   - The current user's poll votes on polls sent or received in the group during the member's pending period.
    ///
    /// If the group member happens to have no device allowing them to receive our messages, we do nothing. For this reason, when a user becomes
    /// "reachable", this method is also called (with the `.forSpecificContact` kind). In that case, we consider all the groups v2 where this contact is
    /// - a non-pending member
    /// - such that the `NeedsReplayOfPastEvents` is `true`.
    /// For all these groups, we replay past events by call this same method again (but with the `.forSpecificGroupMember` input kind).
    private func replayGroupPastEvents(_ kind: GroupPastEventsToReplay) async {
        switch kind {
            
        case .forSpecificGroupMember(groupIdentifier: let groupIdentifier, memberCryptoId: let memberCryptoId):
            
            do {
                // Make sure we have a way to reach the member
                let contactIdentifier = ObvContactIdentifier(contactCryptoId: memberCryptoId, ownedCryptoId: groupIdentifier.ownedCryptoId)
                guard try await self.atLeastOneDeviceAllowsContactToReceiveMessages(contactIdentifier: contactIdentifier) else {
                    // Since we have no way to send messages to the contact, we do nothing. Note that, as soon as the contact becomes reachable,
                    // this method is called with the `.forSpecificContact` input kind.
                    return
                }
                // Requests the date interval for replaying events (note that this returns `.noNeedToReplayPastEvents` if the member's NeedsReplayOfPastEvents flag is false).
                let datesIntervalToReplayPastEvents = try await getDatesIntervalToReplayPastEvents(groupId: groupIdentifier, memberCryptoId: memberCryptoId)
                switch datesIntervalToReplayPastEvents {
                case .replayOfPastEventsBetween(dateInterval: let dateInterval):
                    try await replaySentReactions(groupIdentifier: groupIdentifier, memberCryptoId: memberCryptoId, dateInterval: dateInterval)
                    try await replaySentPollVotes(groupIdentifier: groupIdentifier, memberCryptoId: memberCryptoId, dateInterval: dateInterval)
                case .noNeedToReplayPastEvents:
                    break
                }
                // The replay process is done, we update the group member `NeedsReplayOfPastEvents` flag
                let op = ResetNeedsReplayOfPastEventsForGroupMemberOperation(groupIdentifier: groupIdentifier, memberCryptoId: memberCryptoId)
                let composedOp = createCompositionOfOneContextualOperation(op1: op)
                await coordinatorsQueue.addAndAwaitOperation(composedOp)
                assert(composedOp.isFinished && !composedOp.isCancelled)
            } catch {
                assertionFailure()
            }
            
        case .forSpecificContact(contactIdentifier: let contactIdentifier):
            
            do {
                let groupsWhereContactExpectsReplays: [ObvGroupV2Identifier] = try await getGroupsWhereMembersNeedsReplayOfPastEvents(contactIdentifier: contactIdentifier)
                let memberCryptoId: ObvCryptoId = contactIdentifier.contactCryptoId
                for groupIdentifier in groupsWhereContactExpectsReplays {
                    do {
                        try await replayGroupPastEvents(.forSpecificGroupMember(groupIdentifier: groupIdentifier, memberCryptoId: memberCryptoId))
                    } catch {
                        assertionFailure() // In production, continue with the next group
                    }
                }
            } catch {
                assertionFailure()
            }
            
        case .forAllGroupMembersThatNeedReplayOfPastEvents:
            
            do {
                let membersThatNeedReplayOfPastEvents: [(groupIdentifier: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId)] = try await getGroupMembersThatNeedReplayOfPastEvents()
                for groupMember in membersThatNeedReplayOfPastEvents {
                    do {
                        try await replayGroupPastEvents(.forSpecificGroupMember(groupIdentifier: groupMember.groupIdentifier, memberCryptoId: groupMember.memberCryptoId))
                    } catch {
                        assertionFailure() // In production, continue with the next group member
                    }
                }
            } catch {
                assertionFailure()
            }
            
        }
    }
    
    
    /// Helper method for `replayGroupPastEvents(_:)`
    private func getGroupMembersThatNeedReplayOfPastEvents() async throws -> [(groupIdentifier: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId)] {
        let groupMembers: [(groupIdentifier: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId)] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[(groupIdentifier: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId)], any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let groupMembers: [(groupIdentifier: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId)] = try PersistedGroupV2Member.getGroupMembersThatNeedReplayOfPastEvents(within: context)
                    return continuation.resume(returning: groupMembers)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
        return groupMembers
    }
    
    
    /// Helper method for `replayGroupPastEvents(_:)`
    private func getGroupsWhereMembersNeedsReplayOfPastEvents(contactIdentifier: ObvContactIdentifier) async throws -> [ObvGroupV2Identifier] {
        let groupsWhereContactExpectsReplays: [ObvGroupV2Identifier] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[ObvGroupV2Identifier], any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let groupsWhereContactExpectsReplays: [ObvGroupV2Identifier] = try PersistedGroupV2Member.getGroupsWhereMembersNeedsReplayOfPastEvents(contactIdentifier: contactIdentifier, within: context)
                    return continuation.resume(returning: groupsWhereContactExpectsReplays)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
        return groupsWhereContactExpectsReplays
    }
    
    
    /// Helper method for `replayGroupPastEvents(_:)`
    private func replaySentReactions(groupIdentifier: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId, dateInterval: PersistedGroupV2Member.DateInterval) async throws {
        
        let sentReactionsToReplay: [(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, emoji: String, originalServerTimestamp: Date)] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[(TypeSafeManagedObjectID<PersistedMessage>, String, originalServerTimestamp: Date)], any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let sentReactionsToReplay = try PersistedMessageReactionSent.getReactionsSentOnGroupMessages(groupIdentifier: groupIdentifier, dateInterval: dateInterval, within: context)
                    return continuation.resume(returning: sentReactionsToReplay)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
        
        for sentReactionToReplay in sentReactionsToReplay {
            let op = SendReactionJSONOperation(messageObjectID: sentReactionToReplay.messageObjectID,
                                               obvEngine: obvEngine,
                                               emoji: sentReactionToReplay.emoji,
                                               originalServerTimestamp: sentReactionToReplay.originalServerTimestamp)
            let composedOp = createCompositionOfOneContextualOperation(op1: op)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(composedOp.isFinished && !composedOp.isCancelled)
        }
        
    }
    
    
    /// Helper method for `replayGroupPastEvents(_:)`
    private func replaySentPollVotes(groupIdentifier: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId, dateInterval: PersistedGroupV2Member.DateInterval) async throws {
        
        let sentVotesToReplay: [(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, version: Int, originalServerTimestamp: Date)] = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, version: Int, originalServerTimestamp: Date)], any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let sentVotesToReplay = try PersistedPollVoteSent.getPollVoteSentOnGroupMessages(groupIdentifier: groupIdentifier, dateInterval: dateInterval, within: context)
                    return continuation.resume(returning: sentVotesToReplay)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
        
        for sentVoteToReplay in sentVotesToReplay {
            let op = SendPollVoteJSONOperation(messageObjectID: sentVoteToReplay.messageObjectID,
                                               obvEngine: obvEngine,
                                               pollVoteCandidateUuid: sentVoteToReplay.pollVoteCandidateUuid,
                                               voted: true, // The votes returned restrict to those where 'voted' is true.
                                               version: sentVoteToReplay.version,
                                               originalServerTimestamp: sentVoteToReplay.originalServerTimestamp)
            let composedOp = createCompositionOfOneContextualOperation(op1: op)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(composedOp.isFinished && !composedOp.isCancelled)
        }
        
    }
    
    
    /// Helper method for `replayGroupPastEvents(_:)`
    private func atLeastOneDeviceAllowsContactToReceiveMessages(contactIdentifier: ObvContactIdentifier) async throws -> Bool {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let contact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: context) else {
                        return continuation.resume(returning: false)
                    }
                    return continuation.resume(returning: contact.atLeastOneDeviceAllowsThisContactToReceiveMessages)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    /// Helper method for `replayGroupPastEvents(_:)`
    private func getDatesIntervalToReplayPastEvents(groupId: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId) async throws -> PersistedGroupV2Member.DatesIntervalToReplayPastEvents {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PersistedGroupV2Member.DatesIntervalToReplayPastEvents, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let datesIntervalToReplayPastEvents = try PersistedGroupV2Member.getDatesIntervalToReplayPastEvents(groupId: groupId, memberCryptoId: memberCryptoId, within: context)
                    return continuation.resume(returning: datesIntervalToReplayPastEvents)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
}


// MARK: - Draft specific notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    /// Called both from the notification observer and from the RootViewController.
    func processUserWantsToUpdateDiscussionLocalConfiguration(
        with value: PersistedDiscussionLocalConfigurationValue,
        localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) async throws {
            let op1 = UpdateDiscussionLocalConfigurationOperation(
                value: value,
                input: .configurationObjectID(localConfigurationObjectID),
                makeSyncAtomRequest: true,
                syncAtomRequestDelegate: syncAtomRequestDelegate)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await self.coordinatorsQueue.addAndAwaitOperation(composedOp)
            guard composedOp.isFinished && !composedOp.isCancelled else {
                assertionFailure()
                throw Self.makeError(message: "UpdateDiscussionLocalConfigurationOperation did cancel")
            }
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


// MARK: - History transfer methods

extension PersistedDiscussionsUpdatesCoordinator {
    
    /// Called on the source device, just before starting a history transfer.
    ///
    /// The source device sends a confirmation request (in a `WebRTCHistoryTransferControlJSON`) to the destination. This allows to ensure the destination is up and running. The user will confirm the transfer on the destination.
    /// Following the user confirmation on the destination device, it sends back a confirmation message that this method will return.
    func historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(transferId: String, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws -> ObvHistoryTransfer.DestinationOwnedDeviceDecision {
        let request = WebRTCHistoryTransferControlJSON(transferId: transferId, kind: .requestTransfer)
        let itemJSON = PersistedItemJSON(webRTCHistoryTransferControlJSON: request)
        let payload = try itemJSON.jsonEncode()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvHistoryTransfer.DestinationOwnedDeviceDecision, any Error>) in
            Task {
                await self.historyTransferConfirmationRequestHelper.store(continuation, transferId: transferId)
                do {
                    _ = try await obvEngine.post(messagePayload: payload, toOtherOwnedDevice: otherOwnedDeviceIdentifier, withUserContent: true)
                } catch {
                    
                }
            }
        }
    }
    
    
    /// Called on the destination device, at the beginning of a history transfer, if the user accepts the transfer.
    func userWantsToAcceptHistoryTransfer(sourceDeviceIdentifier: ObvOwnedDeviceIdentifier, requestIdFromSource: String) async throws {
        _ = await self.historyTransferConfirmationRequestHelper.resumeContinuation(transferId: requestIdFromSource, decisionReceivedFromDestinationOwnedDevice: .startTransfer)
    }
    
    
    /// Called on the destination device, at the beginning of a history transfer, if the user does not accept the transfer.
    func userWantsToCancelHistoryTransfer(sourceDeviceIdentifier: ObvOwnedDeviceIdentifier, requestIdFromSource: String) async throws {
        _ = await self.historyTransferConfirmationRequestHelper.resumeContinuation(transferId: requestIdFromSource, decisionReceivedFromDestinationOwnedDevice: .cancelTransfer)
    }
    
}

// MARK: - Implementing ContinuousSharingLocationManagerDelegate

extension PersistedDiscussionsUpdatesCoordinator: ContinuousSharingLocationManagerDelegate {
    
    /// This method is called each time we have a new location generated by CoreLocation, for the current physical device.
    /// Note that the `ContinuousSharingLocationManager` filters out certain location, to limit the number of updates we send to our contacts.
    /// So we can immediatly process the new location.
    func newObvLocationToProcessForThisPhysicalDevice(_ continuousSharingLocationManager: ContinuousSharingLocationManager, location: ObvLocation) async {
        do {
            try await processObvLocationForThisPhysicalDevice(location)
        } catch {
            Self.logger.fault("Failed to process ObvLocation for this physical device: \(error.localizedDescription)")
            assertionFailure()
        }
    }
    
    
    /// Determines the discussions eligible to receive high-frequency ("live") location updates from the current device.
    ///
    /// Each time `ContinuousSharingLocationManager` receives a new location for the current device, this method is called to:
    /// - Decide whether the location should be discarded (e.g., if a location was recently shared).
    /// - Identify the discussions where the user has requested live location updates from this device.
    ///
    /// - Returns: A set of discussion identifiers that should receive the new location update.
    func requestUpdatedSetOfDiscussionsRequiringHighAccuracyLocationUpdates(_ continuousSharingLocationManager: ContinuousSharingLocationManager) async -> Set<ObvAppTypes.ObvDiscussionIdentifier> {
        return await self.currentDeviceLiveLocationSharingHelper.discussionIdentifiers
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


// MARK: - Erros
extension PersistedDiscussionsUpdatesCoordinator {
    
    enum ObvError: Error {
        case deleteAllDraftFyleJoinOfDraftOperationCancelled
        case couldNotForwardMessage
        case delegateIsNil
    }
    
}


// MARK: - Processing user's calls, relayed by the RootViewController

extension PersistedDiscussionsUpdatesCoordinator {
        
    func userWantsToDeleteDiscussionsAndHasConfirmed(discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>], deletionType: DeletionType) async throws {
        
        // Make sure all the discussion's concern the same owned identity
        
        let ownedCryptoIds = try await getOwnedCryptoIdsAssociatedWith(discussionObjectIDs: discussionObjectIDs)
        guard ownedCryptoIds.count == 1, let ownedCryptoId = ownedCryptoIds.first else {
            assertionFailure()
            throw Self.makeError(message: "Unexpected number of owned identities")
        }
        
        // Delete the discussions
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for discussionObjectID in discussionObjectIDs {
                group.addTask {
                    try await self.processUserRequestedDeletionOfPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionObjectID: discussionObjectID, deletionType: deletionType)
                }
                try await group.next() // If one of the tasks throws, we throw
            }
        }
    }
    
    
    /// Helper method for `userWantsToDeleteDiscussionsAndHasConfirmed()`
    private func processUserRequestedDeletionOfPersistedDiscussion(ownedCryptoId: ObvCryptoId, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, deletionType: DeletionType) async throws {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            self.processUserRequestedDeletionOfPersistedDiscussion(ownedCryptoId: ownedCryptoId, discussionObjectID: discussionObjectID, deletionType: deletionType) { success in
                success ? continuation.resume() : continuation.resume(throwing: Self.makeError(message: "Deletion request failed"))
            }
        }
    }
    
    /// Helper method for `userWantsToDeleteDiscussionsAndHasConfirmed()`
    private func getOwnedCryptoIdsAssociatedWith(discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws -> Set<ObvCryptoId> {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvCryptoId>, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    var ownedCryptoIds: Set<ObvCryptoId> = []
                    for discussionObjectID in discussionObjectIDs {
                        let discussion = try PersistedDiscussion.get(objectID: discussionObjectID.objectID, within: context)
                        guard let ownedCryptoId = discussion?.ownedIdentity?.cryptoId else { continue }
                        ownedCryptoIds.insert(ownedCryptoId)
                    }
                    return continuation.resume(returning: ownedCryptoIds)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    func userWantsToArchiveDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) async throws {
        let op1 = ArchiveDiscussionOperation(input: .discussionObjectID(discussionObjectID), action: .archive, makeSyncAtomRequest: true, syncAtomRequestDelegate: self.syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "ArchiveDiscussionOperation did cancel")
        }
    }
    

    func userWantsToUnarchiveDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) async throws {
        let op1 = ArchiveDiscussionOperation(input: .discussionObjectID(discussionObjectID), action: .unarchive, makeSyncAtomRequest: true, syncAtomRequestDelegate: self.syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "(Un)ArchiveDiscussionOperation did cancel")
        }
    }
    

    func userWantsToReorderPinnedDiscussions(ownedCryptoId: ObvCryptoId, objectIDOfPinnedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        try await self.processUserWantsToReorderDiscussions(discussionObjectIds: objectIDOfPinnedDiscussions.map(\.objectID), ownedIdentity: ownedCryptoId)
    }
    
    func userWantsToMarkAllMessagesAsReadInDiscussion(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) async throws {
        try await self.processUserWantsToMarkAllMessagesAsNotNewWithinDiscussionNotification(persistedDiscussionObjectID: discussionObjectID.objectID)
    }
    
    
    func userWantsToStopSharingLocationInDiscussion(discussionIdentifier: ObvDiscussionIdentifier) async throws {
        let obvLocation = ObvLocation.endSharing(type: .discussion(discussionIdentifier: discussionIdentifier))
        try await processObvLocationForThisPhysicalDevice(obvLocation)
        await self.currentDeviceLiveLocationSharingHelper.stopLiveLocationSharing(for: discussionIdentifier)
    }

    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice() async throws {
        let obvLocation = ObvLocation.endSharing(type: .all)
        try await processObvLocationForThisPhysicalDevice(obvLocation)
        await self.currentDeviceLiveLocationSharingHelper.stopAllLiveLocationSharing()
    }
    
    
    func userWantsToSendLocation(locationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        let obvLocation = ObvLocation.send(locationData: locationData, discussionIdentifier: discussionIdentifier)
        try await processObvLocationForThisPhysicalDevice(obvLocation)
    }
    
    
    func userWantsToShareLocationContinuously(initialLocationData: ObvLocationData, discussionIdentifier: ObvDiscussionIdentifier, expirationMode: SharingLocationExpirationMode) async throws {
        
        let obvLocation = ObvLocation.startSharing(locationData: initialLocationData, discussionIdentifier: discussionIdentifier, expirationDate: expirationMode.expirationDate)
        try await processObvLocationForThisPhysicalDevice(obvLocation)
        
        // If the user requested "live" sharing (i.e., high accuracy/frequency), inform the ContinuousSharingLocationManager
        
        if expirationMode.isLiveSharing {
            switch expirationMode.expirationDate {
            case .never:
                assertionFailure("We should not be live sharing without an expiration date")
            case .after(date: let date):
                await self.currentDeviceLiveLocationSharingHelper.newDiscussionWhereCurrentDeviceIsPerformingLiveLocationSharing(
                    discussionIdentifier: discussionIdentifier,
                    expirationDate: date)
            }
        }
        
    }
    
    
    func userWantsToCreatePoll(for discussionIdentifier: ObvDiscussionIdentifier, poll: ObvPoll) async throws {

        let op1 = CreateUnprocessedPersistedMessageForPollOperation(discussionIdentifier: discussionIdentifier, poll: poll)
        
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            return
        }

        guard let messageSentPermanentID = op1.unprocessedMessageToSend else {
            assertionFailure()
            return
        }
        
        let op2 = SendUnprocessedPersistedMessageSentOperation(messageSentPermanentID: messageSentPermanentID,
                                                               alsoPostToOtherOwnedDevices: true,
                                                               extendedPayloadProvider: nil,
                                                               obvEngine: obvEngine)
        
        let composedOp2 = createCompositionOfOneContextualOperation(op1: op2)
        coordinatorsQueue.addOperation(composedOp2) // Don't wait
        
    }
    
    
    func processUserWantsToUpdateReaction(ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws {
        let op1 = ProcessSetOrUpdateReactionOnMessageLocalRequestOperation(ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)
        let op2 = SendReactionJSONOperation(messageObjectID: messageObjectID, obvEngine: obvEngine, emoji: newEmoji, originalServerTimestamp: nil)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        composedOp.queuePriority = .veryHigh // As this was requested by the user
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "processUserWantsToUpdateReaction did cancel")
        }
    }
    
    
    func processUserWantsToUpdatePollVote(ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, voted: Bool, version: Int) async throws {
        
        let op1 = ProcessSetOrUpdatePollVoteOnMessageLocalRequestOperation(ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, pollVoteCandidateUuid: pollVoteCandidateUuid, voted: voted, version: version)
        let op2 = SendPollVoteJSONOperation(messageObjectID: messageObjectID, obvEngine: obvEngine, pollVoteCandidateUuid: pollVoteCandidateUuid, voted: voted, version: version, originalServerTimestamp: nil)
        
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
    func processUserWantsToUpdateDraftBodyAndMentions(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, draftBody: AttributedString) async throws {
        let op1 = UpdateDraftBodyAndMentionsOperation(draftObjectID: draftObjectID, draftBody: draftBody)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .high // Since this impacts the user directly
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard composedOp.isFinished && !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "Could not save changes made to draft")
        }
        
        // The draft was saved. If it contains an https URL, and no preview exists for this URL, fetch a preview
        // for it, and attach it to the draft

        if ObvMessengerSettings.Discussions.attachLinkPreviewToMessageSent {
            do {
                let result = try await linkPreviewFetcherForDraft.fetchLinkPreviewForDraft(draftObjectID)
                switch result {
                case .obsoleteRequest:
                   break
                case .shouldDeletePreviousLinkMetadata:
                    do {
                        try await userWantsToDeleteLinkPreviewFromDraft(draftObjectID: draftObjectID)
                    } catch {
                        assertionFailure()
                    }
                case .shouldSaveLinkMetadata(let linkMetadata):
                    do {
                        try await userWantsToDeleteLinkPreviewFromDraft(draftObjectID: draftObjectID)
                        _ = try await processUserWantsToAddAttachmentsToDraft(draftObjectID: draftObjectID, itemProviders: [NSItemProvider(item: linkMetadata, typeIdentifier: UTType.olvidLinkPreview.identifier)], source: .none)
                    } catch {
                        assertionFailure()
                    }
                case .nothingToDo:
                    break
                }
            } catch {
                assertionFailure()
            }
        }
        
    }
    
    
    private func userWantsToDeleteLinkPreviewFromDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        
        let op1 = DeleteAllDraftFyleJoinOfDraftOperation(draftObjectID: draftObjectID, draftTypeToDelete: .preview)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // As the user requested this
        await coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            throw ObvError.deleteAllDraftFyleJoinOfDraftOperationCancelled
        }

        Task {
            let operations = getOperationsForDeletingOrphanedDatabaseItems()
            await coordinatorsQueue.addAndAwaitOperations(operations)
        }

    }
    
    
    private func userWantsToSaveLinkPreviewForDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        
    }
    
    
    
    /// Called by the `RootViewController` when the user wants to delete only one attachment of a draft.
    func userWantsToDeleteDraftAttachment(draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) async {
        
        let op1 = DeleteDraftFyleJoinOfDraftOperation(draftFyleJoinObjectID: draftFyleJoinObjectID)
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
    func processUserWantsToSendDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: AttributedString) async throws {

        let op1 = SaveBodyTextAndMentionsOfPersistedDraftOperation(draftObjectID: draftObjectID, bodyText: textBody)
        let op2 = CreateUnprocessedPersistedMessageSentFromPersistedDraftOperation(draftObjectID: draftObjectID)
        let composedOp = createCompositionOfTwoContextualOperation(op1: op1, op2: op2)
        composedOp.queuePriority = .veryHigh
        await coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            throw Self.makeError(message: "Could not process draft")
        }
        
        // If we reach this point, the sent message is created in database, in the unprocess state.
        // We free the current task we want to unfreeze the UI.
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
            
            // Mark all messages as read
            
            let op5 = MarkAllMessagesAsNotNewWithinDiscussionOperation(input: .draftObjectID(draftObjectID))
            let composedOp4 = createCompositionOfOneContextualOperation(op1: op5)
            composedOp4.queuePriority = .veryHigh
            await coordinatorsQueue.addAndAwaitOperation(composedOp4)

            // Notify other owned devices about messages that turned not new

            if op5.ownedIdentityHasAnotherReachableDevice {
                let postOp = PostDiscussionReadJSONEngineOperation(op: op5, obvEngine: obvEngine)
                queueForOperationsMakingEngineCalls.addOperation(postOp) // No need to await the end
            }

            // Send read receipts.
            // Note that the check about whether we should send read receipts has been made already: if
            // the array of sent messages for read receipt is non-empty, it means we must send these
            // receipts.
            
            if let result = op5.result {
                switch result {
                case .couldNotFindActiveDiscussionInDatabase:
                    break
                case .processed(let receivedMessagesForReadReceipts):
                    sendReadReceipts(receivedMessagesForReadReceipts: receivedMessagesForReadReceipts)
                }
            }

        }

    }

    
    /// Called from the `RootViewController` when the user wants to add attachments to a draft.
    func processUserWantsToAddAttachmentsToDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL]) async throws {
        
        // Load all the item providers
        
        let loadedItemProvidersToAttach = await self.loadItemProviderHelper.load(urls)

        // Update the draft we the loaded item providers
        
        try await updateDraft(draftObjectID: draftObjectID, loadedItemProvidersToAttach: loadedItemProvidersToAttach)

    }

    
    /// Called from the `RootViewController` when the user wants to add attachments to a draft.
    func processUserWantsToAddAttachmentsToDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], source: LoadItemProviderHelper.ItemProviderProviderSource) async throws -> [LoadedItemProviderToPaste] {
        
        // Load all the item providers
        
        let loadedItemProviders = try await self.loadItemProviderHelper.load(itemProviders, source: source, progressProvider: nil)
        
        // Update the draft with the loaded item providers to attach
        
        try await updateDraft(draftObjectID: draftObjectID, loadedItemProvidersToAttach: loadedItemProviders.toAttach)
        
        // Return the item providers to paste
        
        return loadedItemProviders.toPaste
        
    }
    
    
    private func updateDraft(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, loadedItemProvidersToAttach: [LoadedItemProviderToAttach]) async throws {
        
        let op1 = NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation(
            draftObjectID: draftObjectID,
            loadedItemProvidersToAttach: loadedItemProvidersToAttach,
            completionHandler: nil,
            log: Self.log)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryHigh // Since the user requested this
        await coordinatorsQueue.addAndAwaitOperation(composedOp)

        guard !composedOp.isCancelled else {
            assertionFailure()
            throw Self.makeError(message: "NewCreateDraftFyleJoinsFromLoadedFileRepresentationsOperation operation cancelled: \(String(describing: op1.reasonForCancel))")
        }

    }
 
}


extension PersistedDiscussionsUpdatesCoordinator: PersistedGroupV2MemberObserver {
    
    func aPersistedGroupV2MemberWasInsertedOrChanged(groupIdentifier: ObvTypes.ObvGroupV2Identifier, memberIdentifier: ObvTypes.ObvCryptoId) async {
        let messageIdentifiersForLater = await appInboxService.fetchMessageIdentifiersForLater(identifierOfExpectedGroup: .groupV2(groupIdentifier), cryptoIdOfExpectedContact: memberIdentifier)
        await self.reprocessEngineMessagesForLater(messageIdentifiersForLater: messageIdentifiersForLater)
    }
    
    func aPersistedGroupV2MemberChangedFromPendingToNonPending(groupIdentifier: ObvGroupV2Identifier, memberCryptoId: ObvCryptoId) async {
        
        await sendAppropriateDiscussionSharedConfigurationsToContact(input: .groupMember(groupIdentifier: groupIdentifier, memberCryptoId: memberCryptoId))
        await processUnprocessedRecipientInfosThatCanNowBeProcessed()
        await replayGroupPastEvents(.forSpecificGroupMember(groupIdentifier: groupIdentifier, memberCryptoId: memberCryptoId))
        
    }
    
}


// MARK: - Processing ObvEngine Notifications

extension PersistedDiscussionsUpdatesCoordinator {
    
    func processNewMessagesReceivedNotification(messages: [ObvMessageOrObvOwnedMessage]) async {
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
            
        case .done(attachmentsProcessingRequest: let attachmentsProcessingRequest):
            notifyEngine = .notify(attachmentsProcessingRequest: attachmentsProcessingRequest)

        case .definitiveFailure:
            notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)
                        
        case .obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived:
            assertionFailure("This is unexpected as the message was not received from the notification extension but from the engine. This should be investigated.")
            notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)
                        
        case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
            do {
                try await self.appInboxService.storeOrReplaceMessageIdentifierForLater(
                    messageUIDFromEngine: obvMessage.messageUID,
                    messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                    identifierOfExpectedDiscussion: discussionIdentifier)
                notifyEngine = .putOnHold
            } catch {
                assertionFailure(error.localizedDescription)
                notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)
            }
            
        case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            do {
                try await self.appInboxService.storeOrReplaceMessageIdentifierForLater(
                    messageUIDFromEngine: obvMessage.messageUID,
                    messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                    identifierOfExpectedGroup: groupIdentifier,
                    cryptoIdOfExpectedContact: contactCryptoId)
                notifyEngine = .putOnHold
            } catch {
                assertionFailure(error.localizedDescription)
                notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)
            }

        case .couldNotFindMessageInDatabase(messageIdentifier: let messageIdentifier):
            do {
                try await self.appInboxService.storeOrReplaceMessageIdentifierForLater(
                    messageUIDFromEngine: obvMessage.messageUID,
                    messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer,
                    identifierOfExpectedMessage: messageIdentifier)
                notifyEngine = .putOnHold
            } catch {
                assertionFailure(error.localizedDescription)
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
        case .putOnHold:
            do {
                try await obvEngine.putMessageOnHold(messageId: obvMessage.messageId)
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
        case putOnHold
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

        case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
            do {
                try await self.appInboxService.storeOrReplaceMessageIdentifierForLater(
                    messageUIDFromEngine: obvOwnedMessage.messageUID,
                    messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer,
                    identifierOfExpectedDiscussion: discussionIdentifier)
                notifyEngine = .putOnHold
            } catch {
                assertionFailure(error.localizedDescription)
                notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)
            }

        case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            do {
                try await self.appInboxService.storeOrReplaceMessageIdentifierForLater(
                    messageUIDFromEngine: obvOwnedMessage.messageUID,
                    messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer,
                    identifierOfExpectedGroup: groupIdentifier,
                    cryptoIdOfExpectedContact: contactCryptoId)
                notifyEngine = .putOnHold
            } catch {
                assertionFailure(error.localizedDescription)
                notifyEngine = .notify(attachmentsProcessingRequest: .deleteAll)
            }
            
        case .couldNotFindMessageInDatabase(messageIdentifier: let messageIdentifier):
            do {
                try await self.appInboxService.storeOrReplaceMessageIdentifierForLater(
                    messageUIDFromEngine: obvOwnedMessage.messageUID,
                    messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer,
                    identifierOfExpectedMessage: messageIdentifier)
                notifyEngine = .putOnHold
            } catch {
                assertionFailure(error.localizedDescription)
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
        case .putOnHold:
            do {
                try await obvEngine.putMessageOnHold(messageId: obvOwnedMessage.messageId)
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
        case .doNotNotify:
            return
        }
        
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
    
    
    /// When we are notified that the fetch manager did a non-truncated listing, we query the `AppInboxService` to set the timestamp of first non truncated listing
    /// after insertion. When then delete old entries.
    private func processServerAndInboxContainNoMoreUnprocessedMessages(ownedCryptoId: ObvCryptoId, downloadTimestampFromServer: Date) async {
        // Set timestamp of first truncated listing
        await self.appInboxService.setTimestampOfFirstNonTruncatedListingAfterInsertion(ownedCryptoId: ownedCryptoId)
        // Delete obsolete entries
        guard !currentlyProcessingObsoleteMessageIdentifiersForLater else { return }
        currentlyProcessingObsoleteMessageIdentifiersForLater = true
        defer { currentlyProcessingObsoleteMessageIdentifiersForLater = false }
        let obsoleteMessageIdentifiers = await self.appInboxService.fetchObsoleteMessageIdentifiersForLater(ownedCryptoId: ownedCryptoId)
        for messageId in obsoleteMessageIdentifiers {
            try? await obvEngine.messageWasProcessed(messageId: messageId, attachmentsProcessingRequest: .deleteAll)
            await appInboxService.deleteMessageIdentifiersForLater(messageId: messageId)
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
    

    /// Called by the `RootViewController` when the user requests a message forward to one or more discussions
    func processUserWantsToForwardMessage(identifierOfMessageToForwad: ObvMessageAppIdentifier, identifiersOfDiscussionsWhereMessageShouldBeForwarded: Set<ObvDiscussionIdentifier>) async throws {
        for discussionIdentifier in identifiersOfDiscussionsWhereMessageShouldBeForwarded {
            let op1 = CreateUnprocessedForwardPersistedMessageSentFromMessageOperation(identifierOfMessageToForwad: identifierOfMessageToForwad, identifiersOfDiscussionWhereMessageShouldBeForwarded: discussionIdentifier)
            let op2 = ComputeExtendedPayloadOperation(provider: op1)
            let op3 = SendUnprocessedPersistedMessageSentOperation(unprocessedPersistedMessageSentProvider: op1, alsoPostToOtherOwnedDevices: true, extendedPayloadProvider: op2, obvEngine: obvEngine)
            let composedOp = createCompositionOfThreeContextualOperation(op1: op1, op2: op2, op3: op3)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            guard composedOp.isFinished && !composedOp.isCancelled else {
                assertionFailure()
                throw ObvError.couldNotForwardMessage
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
    
    
    private func processBetaUserWantsToDebugCoordinatorsQueue() {
//        guard let logString = (coordinatorsQueue as? AppCoordinatorsQueue)?.logOperations(ops: []) else { return }
//        ObvMessengerInternalNotification.betaUserWantsToSeeLogString(logString: logString)
//            .postOnDispatchQueue()
    }
    
//    private func processUserWantsToArchiveDiscussion(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, completionHandler: ((Bool) -> Void)?) {
//        let op1 = ArchiveDiscussionOperation(input: .discussionPermanentID(discussionPermanentID: discussionPermanentID), action: .archive, makeSyncAtomRequest: true, syncAtomRequestDelegate: self.syncAtomRequestDelegate)
//        op1.completionBlock = {
//            completionHandler?(!op1.isCancelled)
//        }
//        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
//        self.coordinatorsQueue.addOperation(composedOp)
//    }

//    private func processUserWantsToUnarchiveDiscussion(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, completionHandler: ((Bool) -> Void)?) {
//        let op1 = ArchiveDiscussionOperation(input: .discussionPermanentID(discussionPermanentID: discussionPermanentID), action: .unarchive, makeSyncAtomRequest: true, syncAtomRequestDelegate: self.syncAtomRequestDelegate)
//        op1.completionBlock = {
//            completionHandler?(!op1.isCancelled)
//        }
//        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
//        self.coordinatorsQueue.addOperation(composedOp)
//    }

    private func processUpdateNormalizedSearchKeyOnPersistedDiscussions(ownedIdentity: ObvCryptoId, completionHandler: (() -> Void)?) {
        let op1 = UpdateNormalizedSearchKeyOnPersistedDiscussionsOperation(ownedIdentity: ownedIdentity)
        op1.completionBlock = {
            completionHandler?()
        }
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        self.coordinatorsQueue.addOperation(composedOp)
    }

//    private func processUserWantsToReorderDiscussions(discussionObjectIds: [NSManagedObjectID], ownedIdentity: ObvCryptoId, completionHandler: ((Bool) -> Void)?) {
//        let op1 = ReorderDiscussionsOperation(input: .discussionObjectIDs(discussionObjectIDs: discussionObjectIds), ownedIdentity: ownedIdentity, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
//        op1.completionBlock = {
//            completionHandler?(!op1.isCancelled)
//        }
//        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
//        self.coordinatorsQueue.addOperation(composedOp)
//    }
    
    private func processUserWantsToReorderDiscussions(discussionObjectIds: [NSManagedObjectID], ownedIdentity: ObvCryptoId) async throws {
        let op1 = ReorderDiscussionsOperation(input: .discussionObjectIDs(discussionObjectIDs: discussionObjectIds), ownedIdentity: ownedIdentity, makeSyncAtomRequest: true, syncAtomRequestDelegate: syncAtomRequestDelegate)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await self.coordinatorsQueue.addAndAwaitOperation(composedOp)
        if composedOp.isCancelled {
            throw Self.makeError(message: "ReorderDiscussionsOperation operation cancelled: \(String(describing: op1.reasonForCancel))")
        }
    }
    
}


// MARK: - Implementing CallProviderDelegateSignalingDelegate

extension PersistedDiscussionsUpdatesCoordinator: CallProviderDelegateSignalingDelegate {
    
    func newWebRTCMessageToSendToAllContactDevices(webrtcMessage: ObvAppTypes.WebRTCMessageJSON, contactIdentifier: ObvTypes.ObvContactIdentifier, forStartingCall: Bool) async {
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
    
    
    func newWebRTCMessageToSendToSingleContactDevice(webrtcMessage: ObvAppTypes.WebRTCMessageJSON, contactDeviceIdentifier: ObvTypes.ObvContactDeviceIdentifier) async {
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
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier)
        case couldNotFindMessageInDatabase(messageIdentifier: ObvMessageAppIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
        case definitiveFailure

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
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
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
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
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
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }

        // Case #5: The ObvOwnedMessage contains a JSON message indicating that a discussion should be globally deleted

        if let deleteDiscussionJSON = persistedItemJSON.deleteDiscussionJSON {
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] deleteDiscussionJSON")
            os_log("The owned message is a delete discussion JSON", log: Self.log, type: .debug)
            
            var operationsToQueue = [OperationKind]()

            // Assuming that we are sharing the current physical device location in the discussion we are about to delete, we want to send END_SHARING location
            // messages before deleting the discussion, since we are about to end sharing (as soon as the sent messages containing the location are deleted).
            if let discussionIdentifier = try? deleteDiscussionJSON.getObvDiscussionId(ownedCryptoId: obvOwnedMessage.ownedCryptoId) {
                let op = SendEndSharingLocationJSONWhenDeletingDiscussionOperation(discussionIdentifier: .obvDiscussionIdentifier(discussionIdentifier), obvEngine: obvEngine)
                op.completionBlock = { op.logReasonIfCancelled(log: Self.log) }
                operationsToQueue.append(.engineCall(op: op))
            }

            
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
                operationsToQueue.append(.contextual(op: composedOp))
            }
            do {
                let operations = getOperationsForDeletingOrphanedDatabaseItems()
                operationsToQueue.append(contentsOf: operations.map({ .contextual(op: $0) }))
            }
            guard !operationsToQueue.isEmpty else { assertionFailure(); return .definitiveFailure }
            operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
            
            for op in operationsToQueue {
                switch op {
                case .contextual(let op):
                    await coordinatorsQueue.addAndAwaitOperation(op)
                case .engineCall(let op):
                    queueForOperationsMakingEngineCalls.addOperation(op)
                }
            }
            
            assert(op1.isFinished)

            switch op1.result {
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions:
                assertionFailure("This result is unexpected when receiving an ObvOwned message from another owned device")
                return .definitiveFailure
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
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
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
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .couldNotFindMessageInDatabase(messageIdentifier: let messageIdentifier):
                return .couldNotFindMessageInDatabase(messageIdentifier: messageIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
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
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Case #10: The ObvOwnedMessage contains a JSON message indicating that a received message with limited visibility was read on another owned device
        
        if let limitedVisibilityMessageOpenedJSON = persistedItemJSON.limitedVisibilityMessageOpenedJSON {
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] limitedVisibilityMessageOpenedJSON")
            os_log("The owned message indicates that a received message with limited visibility was read on another owned device", log: Self.log, type: .debug)
            guard let discussionId = try? limitedVisibilityMessageOpenedJSON.getObvDiscussionId(ownedCryptoId: obvOwnedMessage.ownedCryptoId) else {
                assertionFailure()
                return .done(attachmentsProcessingRequest: .deleteAll)
            }
            guard let messageId = try? limitedVisibilityMessageOpenedJSON.getMessageId(ownedCryptoId: obvOwnedMessage.ownedCryptoId) else {
                assertionFailure()
                return .done(attachmentsProcessingRequest: .deleteAll)
            }
            
            guard let obvDiscussionIdentifier = try? limitedVisibilityMessageOpenedJSON.getObvDiscussionId(ownedCryptoId: obvOwnedMessage.ownedCryptoId) else {
                assertionFailure()
                return .done(attachmentsProcessingRequest: .deleteAll)
            }
            
            let op1 = AllowReadingOfMessagesReceivedThatRequireUserActionOperation(
                .requestedOnAnotherOwnedDevice(
                    ownedCryptoId: obvOwnedMessage.ownedCryptoId,
                    discussionId: discussionId.toDiscussionIdentifier(),
                    messageId: messageId,
                    messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer,
                    obvDiscussionIdentifier: obvDiscussionIdentifier))
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .couldNotFindMessageInDatabase(messageIdentifier: let messageIdentifier):
                return .couldNotFindMessageInDatabase(messageIdentifier: messageIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
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
            case .processed(receivedMessagesForReadReceipts: let receivedMessagesForReadReceipts):
                assert(receivedMessagesForReadReceipts.isEmpty, "The operation is expected to return an empty array here, since we do not send read receipts when the messages are read from another owned device")
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Case #12: The ObvOwnedMessage contains a JSON message indicating that a poll vote has been sent from another owned device

        if let pollVoteJSON = persistedItemJSON.pollVoteJSON {
            ObvDisplayableLogs.shared.log("[✉️][O][\(obvOwnedMessage.messageId.uid.debugDescription)] pollVoteJSON")
            Self.logger.debug("The owned message is a poll vote")
            let op1 = ProcessSetOrUpdatePollVoteOnMessageOperation(
                pollVoteJSON: pollVoteJSON,
                requester: .ownedIdentity(ownedCryptoId: obvOwnedMessage.ownedCryptoId),
                messageUploadTimestampFromServer: obvOwnedMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .couldNotFindMessageInDatabase(messageIdentifier: let messageIdentifier):
                return .couldNotFindMessageInDatabase(messageIdentifier: messageIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Case #13: The ObvOwnedMessage contains a JSON message relating to a message history transfer between this device and another owned device
        
        if let webrtcHistoryTransferMessageJSON = persistedItemJSON.webrtcHistoryTransferMessageJSON {
            
            do {
                guard let delegate else {
                    assertionFailure()
                    return .definitiveFailure
                }
                guard let otherOwnedDeviceIdentifier = obvOwnedMessage.ownedDeviceIdentifier else {
                    assertionFailure()
                    return .definitiveFailure
                }
                try await delegate.newReceivedWebrtcHistoryTransferMessageJSON(self, webrtcHistoryTransferMessageJSON: webrtcHistoryTransferMessageJSON, otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier)
                return .done(attachmentsProcessingRequest: .deleteAll)
            } catch {
                //assertionFailure()
                return .definitiveFailure
            }
            
        }
        
        // Case #14: The ObvOwnedMessage contains a JSON message part of a history transfer control
        
        if let webRTCHistoryTransferControlJSON = persistedItemJSON.webRTCHistoryTransferControlJSON {
            
            let transferId = webRTCHistoryTransferControlJSON.transferId
            
            switch webRTCHistoryTransferControlJSON.kind {
                
            case .requestTransfer:
                // This is a request, sent by the source to this destination device
                do {
                    if obvOwnedMessage.localDownloadTimestamp.timeIntervalSinceNow < 30 {
                        guard let otherOwnedDeviceIdentifier = obvOwnedMessage.ownedDeviceIdentifier else {
                            assertionFailure()
                            return .definitiveFailure
                        }
                        try processReceivedWebRTCHistoryTransferConfirmationRequest(transferId: transferId, otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier)
                    }
                    return .done(attachmentsProcessingRequest: .deleteAll)
                } catch {
                    return .definitiveFailure
                }

                
            case .acceptTransfer:
                // This is sent by the destination to this source device to accept the transfer request
                Task {
                    await self.historyTransferConfirmationRequestHelper.resumeContinuation(transferId: transferId, decisionReceivedFromDestinationOwnedDevice: .startTransfer)
                }
                return .done(attachmentsProcessingRequest: .deleteAll)


            case .rejectOrAbortTransfer:
                // This is sent by the destination to this source device to reject the transfer request.
                // It can also be sent by the source or the destination, during a transfer, to interrupt the transfer
                // If we are in the first case, the historyTransferConfirmationRequestHelper can handle the request. If it can't, we consider
                // it is an interruption.
                let messageConcernsASentRequest = await self.historyTransferConfirmationRequestHelper.resumeContinuation(transferId: transferId, decisionReceivedFromDestinationOwnedDevice: .cancelTransfer)
                if !messageConcernsASentRequest {
                    // The user decided to interrupt an ongoing transfer, from the other device
                    Task {
                        do {
                            guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
                            try await delegate.newWebrtcHistoryTransferInterruptionRequest(self, transferId: transferId)
                        } catch {
                            Self.logger.fault("Could not process the history transfer interruption request sent by the other device: \(error.localizedDescription, privacy: .public)")
                            assertionFailure()
                        }
                    }
                }
                return .done(attachmentsProcessingRequest: .deleteAll)

            }
            
        }
        
        // Unknow case, we mark the message for deletion
        
        assertionFailure()
        return .definitiveFailure

    }
    
    
    /// Called just before a history transfer, when this destination device receives a confirmation request (in a `WebRTCHistoryTransferControlJSON` message) from the source device.
    private func processReceivedWebRTCHistoryTransferConfirmationRequest(transferId: String, otherOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier) throws {
        Task {
            do {
                let decision = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvHistoryTransfer.DestinationOwnedDeviceDecision, any Error>) in
                    Task {
                        await self.historyTransferConfirmationRequestHelper.store(continuation, transferId: transferId)
                        let deepLink = ObvDeepLink.webRTCHistoryTransferConfirmation(sourceDeviceIdentifier: otherOwnedDeviceIdentifier, transferId: transferId)
                        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                            .postOnDispatchQueue()
                    }
                }
                let confirmation: WebRTCHistoryTransferControlJSON
                switch decision {
                case .startTransfer:
                    confirmation = WebRTCHistoryTransferControlJSON(transferId: transferId, kind: .acceptTransfer)
                case .cancelTransfer:
                    confirmation = WebRTCHistoryTransferControlJSON(transferId: transferId, kind: .rejectOrAbortTransfer)
                }
                let itemJSON = PersistedItemJSON(webRTCHistoryTransferControlJSON: confirmation)
                let payload = try itemJSON.jsonEncode()
                _ = try await obvEngine.post(messagePayload: payload, toOtherOwnedDevice: otherOwnedDeviceIdentifier)
            } catch {
                assertionFailure()
            }
        }
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
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier)
        case couldNotFindMessageInDatabase(messageIdentifier: ObvMessageAppIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
        case obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived
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
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
            case .obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived:
                return .obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived
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
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .failed:
                return .definitiveFailure
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
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
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
                
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):

                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
                
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)

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
                action = await receivedContinuousLocationRateLimiter.limitRateOfContinuousLocationOfContactDevice(
                    with: deviceIdentifier,
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
                case .processed:
                    return .done(attachmentsProcessingRequest: .deleteAll)
                case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                    return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
                case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                    return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
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
            case .historyTransfer:
                assertionFailure("Unexpected source")
                return .definitiveFailure
            }
            let op1 = ProcessSetOrUpdateReactionOnMessageOperation(
                reactionJSON: reactionJSON,
                requester: .contact(contactIdentifier: obvMessage.fromContactIdentity, overrideExistingReaction: overrideExistingReaction),
                messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .couldNotFindMessageInDatabase(messageIdentifier: let messageIdentifier):
                return .couldNotFindMessageInDatabase(messageIdentifier: messageIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
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
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
            case nil:
                assertionFailure()
                return .definitiveFailure
            }
        }
        
        // Case #10: The ObvMessage contains a JSON message indicating that a poll Vote has been sent by a contact

        if let pollVoteJSON = persistedItemJSON.pollVoteJSON {
            ObvDisplayableLogs.shared.log("[✉️][C][\(obvMessage.messageId.uid.debugDescription)] pollVoteJSON")
            let op1 = ProcessSetOrUpdatePollVoteOnMessageOperation(pollVoteJSON: pollVoteJSON, requester: .contact(contactIdentifier: obvMessage.fromContactIdentity), messageUploadTimestampFromServer: obvMessage.messageUploadTimestampFromServer)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            assert(op1.isFinished)

            switch op1.result {
            case .processed:
                return .done(attachmentsProcessingRequest: .deleteAll)
            case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
                return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
            case .couldNotFindMessageInDatabase(messageIdentifier: let messageIdentifier):
                return .couldNotFindMessageInDatabase(messageIdentifier: messageIdentifier)
            case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
                return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
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
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
    }
    
    /// This method is called when receiving a message from the engine that contains a shared configuration for a persisted discussion (typically, either one2one, or a group discussion owned by the sender of this message).
    /// We use this new configuration to update ours.
    private func updateSharedConfigurationOfPersistedDiscussion(using discussionSharedConfiguration: DiscussionSharedConfigurationJSON, fromContact: ObvContactIdentifier, messageUploadTimestampFromServer: Date, messageLocalDownloadTimestamp: Date) async -> UpdateSharedConfigurationOfPersistedDiscussionReceivedFromContactResult {
        
        // Before actually executing/saving the MergeDiscussionSharedExpirationConfigurationOperation, we make sure it is required.
        guard await isMergeDiscussionSharedExpirationConfigurationOperationRequired(using: discussionSharedConfiguration, fromContact: fromContact, messageUploadTimestampFromServer: messageUploadTimestampFromServer, messageLocalDownloadTimestamp: messageLocalDownloadTimestamp) else {
            return .done
        }
        
        let op1 = MergeDiscussionSharedExpirationConfigurationOperation(
            discussionSharedConfiguration: discussionSharedConfiguration,
            origin: .fromContact(contactIdentifier: fromContact),
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            messageLocalDownloadTimestamp: messageLocalDownloadTimestamp)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        assert(op1.isFinished)
        
        switch op1.result {
        case .merged:
            return .done
        case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
            return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
        case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
        case nil:
            assert(op1.isCancelled)
            assertionFailure()
            return .failed
        }
        
    }
    
    
    /// Helper method for `updateSharedConfigurationOfPersistedDiscussion(using:fromContact:messageUploadTimestampFromServer:messageLocalDownloadTimestamp:)`
    private func isMergeDiscussionSharedExpirationConfigurationOperationRequired(using discussionSharedConfiguration: DiscussionSharedConfigurationJSON, fromContact: ObvContactIdentifier, messageUploadTimestampFromServer: Date, messageLocalDownloadTimestamp: Date) async -> Bool {
        do {
            return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<Bool, any Error>, context: NSManagedObjectContext) in
                let op1 = MergeDiscussionSharedExpirationConfigurationOperation(
                    discussionSharedConfiguration: discussionSharedConfiguration,
                    origin: .fromContact(contactIdentifier: fromContact),
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                    messageLocalDownloadTimestamp: messageLocalDownloadTimestamp)
                let obvContext = ObvContext(context: context, flowId: FlowIdentifier(), file: #fileID, line: #line, function: #function)
                let viewContext = ObvStack.shared.viewContext
                op1.main(obvContext: obvContext, viewContext: viewContext)
                switch op1.result {
                case .merged:
                    return continuation.resume(returning: context.hasChanges)
                default:
                    return continuation.resume(returning: true)
                }
            }
        } catch {
            assertionFailure()
            return true
        }
        
    }
    

    enum UpdateSharedConfigurationOfPersistedDiscussionReceivedFromOtherOwnedDevice {
        case done
        case failed
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
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
        case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
            return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
        case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
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
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvAppTypes.ObvDiscussionIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
        case obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived
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
        case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
            return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
        case .cannotCreateReceivedMessageThatAlreadyExpired:
            return .cannotCreateReceivedMessageThatAlreadyExpired
        case .messageIsPriorToLastRemoteDeletionRequest:
            return .messageIsPriorToLastRemoteDeletionRequest
        case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
        case .obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived:
            return .obvMessageReceivedFromUserNotificationIsInsufficientToCreateMessageReceived
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
        case couldNotFindActiveDiscussionInDatabase(discussionIdentifier: ObvDiscussionIdentifier)
        case contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: ObvGroupIdentifier, contactCryptoId: ObvCryptoId)
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
        case .sentMessageCreated(messageSentPermanentId: let _messageSentPermanentId):
            messageSentPermanentId = _messageSentPermanentId
        case .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: let discussionIdentifier):
            return .couldNotFindActiveDiscussionInDatabase(discussionIdentifier: discussionIdentifier)
        case .remoteDeleteRequestSavedForLaterWasApplied:
            return .remoteDeleteRequestSavedForLaterWasApplied
        case .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: let groupIdentifier, contactCryptoId: let contactCryptoId):
            return .contactIsNotPartOfGroupOrRequiresPermissions(groupIdentifier: groupIdentifier, contactCryptoId: contactCryptoId)
        case nil:
            assertionFailure()
            return .sentMessageCreationFailure
        }

        // If we reach this point, the message was properly created. We can determine the attachments to download now.

        let downloadOp = DetermineAttachmentsProcessingRequestForMessageSentOperation(kind: .allAttachmentsOfMessage(messageSentPermanentId: messageSentPermanentId))
        await queueAndAwaitCompositionOfOneContextualOperation(op1: downloadOp)

        assert(downloadOp.isFinished && !downloadOp.isCancelled)
        
        // We stored a 'sent' message, we now check for any receipts from contacts that were received before this message
        // and stored temporarily in the AppInbox. These receipts can now be decrypted using the decryption key from ReturnReceiptJSON.

        Task {
            if let elements = returnReceiptJSON?.elements {
                assert(delegate != nil)
                await delegate?.decryptAndProcessReceiptsStoredForLater(self, ownedCryptoId: obvOwnedMessage.ownedCryptoId, elements: elements)
            }
        }

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


// MARK: - Private helper: LinkPreviewFetcherForDraft

/// A `LinkPreviewFetcherForDraft` functions to fetch a preview of the first `https` URL found in a draft.
///
/// Each time a draft is saved, the singleton instance of this `LinkPreviewFetcherForDraft` is used to fetch a link metadata of the first `https` URL found in a draft.
/// It will be up to the caller to save the returned `LPLinkMetadata` as an attachement of the draft
fileprivate actor LinkPreviewFetcherForDraft {
    
    private var currentURLForDraft = [TypeSafeManagedObjectID<PersistedDraft> :  URL]()
    private var taskFetchingLinkMetadaForURL = [URL : Task<ObvLinkMetadata, Error>]()
    private var cache = NSCache<NSURL, ObvLinkMetadata>()
    private var latestRequestDateForDraft = [TypeSafeManagedObjectID<PersistedDraft> : Date]()
    
    enum Result {
        case obsoleteRequest
        case shouldDeletePreviousLinkMetadata
        case shouldSaveLinkMetadata(ObvLinkMetadata)
        case nothingToDo
        
    }
    
    func fetchLinkPreviewForDraft(_ draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws -> Result {
        
        let currentRequestDate = Date.now
        
        latestRequestDateForDraft[draftObjectID] = max(currentRequestDate, latestRequestDateForDraft[draftObjectID, default: currentRequestDate])
        
        guard currentRequestDate >= latestRequestDateForDraft[draftObjectID, default: currentRequestDate] else { return .obsoleteRequest }

        let (extractedURLs, urlOfExistingLinkMetadata) = try await extractHttpsURLsAndHttpsURLOfExistingLinkMetadataFromDraft(draftObjectID)

        guard currentRequestDate >= latestRequestDateForDraft[draftObjectID, default: currentRequestDate] else { return .obsoleteRequest }
        
        if extractedURLs.isEmpty {
            return urlOfExistingLinkMetadata == nil ? .nothingToDo : .shouldDeletePreviousLinkMetadata
        } else {
            if let urlOfExistingLinkMetadata {
                if extractedURLs.contains(where: { urlOfExistingLinkMetadata == $0 }) {
                    return .nothingToDo
                }
            } else {
                // We will try to fetch the metadata of one of the extracted URLs
            }
        }
        
        // If we reach this point, we need to fetch metada for one of the URLs extracted from the draft body
        
        for url in extractedURLs {
            if let cachedLinkMetadata = cache.object(forKey: url as NSURL) {
                return .shouldSaveLinkMetadata(cachedLinkMetadata)
            } else {
                let linkMetadata: ObvLinkMetadata
                do {
                    linkMetadata = try await Self.fetchLinkMetadata(for: url)
                    cache.setObject(linkMetadata, forKey: url as NSURL)
                    guard currentRequestDate >= latestRequestDateForDraft[draftObjectID, default: currentRequestDate] else { return .obsoleteRequest }
                    return .shouldSaveLinkMetadata(linkMetadata)
                } catch {
                    guard currentRequestDate >= latestRequestDateForDraft[draftObjectID, default: currentRequestDate] else { return .obsoleteRequest }
                    // Continue with the next extracted URL
                }
            }
        }
        
        // If we reach this point, we could not fetch metada for any of the URLs extracted from the draft body.
        
        return urlOfExistingLinkMetadata == nil ? .nothingToDo : .shouldDeletePreviousLinkMetadata

    }
    
    
    private static func fetchLinkMetadata(for url: URL) async throws -> ObvLinkMetadata {
        let previewMetadataProvider = LPMetadataProvider() // Note that LPMetadataProvider is a one-shot object
        let lpLinkMetadata = try await previewMetadataProvider.startFetchingMetadata(for: url)
        let obvLinkMetadata = await ObvLinkMetadata.from(linkMetadata: lpLinkMetadata)
        return obvLinkMetadata
    }
    
    
    private func extractHttpsURLsAndHttpsURLOfExistingLinkMetadataFromDraft(_ draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws -> (extractedURLs: [URL], urlOfExistingLinkMetadata: URL?)  {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(extractedURLs: [URL], urlOfExistingLinkMetadata: URL?), any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let body = try PersistedDraft.getBodyOfPersistedDraft(objectID: draftObjectID, within: context)
                    let urls = body?.extractURLs().filter { $0.scheme?.lowercased() == "https" && $0.host() != nil } ?? []
                    let linkMetadata = try PersistedDraftFyleJoin.getLinkMetadaAsObvLinkMetadata(draftObjectID: draftObjectID, within: context)
                    return continuation.resume(returning: (urls, linkMetadata?.url))
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
}


// MARK: - Private helper: CurrentDeviceLiveLocationSharingHelper, for storing discussion identifiers where the current device performs live location sharing

/// Manages the identifiers of discussions where the user has requested live location updates for the current device.
///
/// This helper is used to:
/// - Store the identifier of a discussion when the user enables live location sharing for the current device.
/// - Remove the identifier when live sharing is stopped.
///
/// The `discussionIdentifiers` set is updated whenever the user enables or disables live location sharing for a discussion.
/// It is regularly queried by `ContinuousSharingLocationManager` to determine which discussions should receive new location updates.
private actor CurrentDeviceLiveLocationSharingHelper {
    
    private(set) var discussionIdentifiers = Set<ObvDiscussionIdentifier>()
    private var cancelTaskForDiscussion = [ObvDiscussionIdentifier : Task<Void, Error>]()
    
    func newDiscussionWhereCurrentDeviceIsPerformingLiveLocationSharing(discussionIdentifier: ObvDiscussionIdentifier, expirationDate: Date) {
        if let previousTask = cancelTaskForDiscussion[discussionIdentifier] {
            previousTask.cancel()
        }
        self.discussionIdentifiers.insert(discussionIdentifier)
        cancelTaskForDiscussion[discussionIdentifier] = Task {
            let timeToWait = max(0, expirationDate.timeIntervalSinceNow)
            try await Task.sleep(seconds: timeToWait) // If the task is cancelled, no further code is executed
            self.discussionIdentifiers.remove(discussionIdentifier)
        }
    }
    
    func stopAllLiveLocationSharing() {
        discussionIdentifiers.removeAll()
        while let (_ , task) = cancelTaskForDiscussion.popFirst() {
            task.cancel()
        }
    }
    
    func stopLiveLocationSharing(for discussionIdentifier: ObvDiscussionIdentifier) {
        discussionIdentifiers.remove(discussionIdentifier)
        let task = cancelTaskForDiscussion.removeValue(forKey: discussionIdentifier)
        task?.cancel()
    }
    
}



// - MARK: Helper when sending (resp. receiving) history transfer confirmation request to destination (resp. from source) device

private actor HistoryTransferConfirmationRequestHelper {
        
    private var destinationOwnedDeviceDecisionContinuationForTransferId = [String : CheckedContinuation<ObvHistoryTransfer.DestinationOwnedDeviceDecision, any Error>]()

    func store(_ continuation: CheckedContinuation<ObvHistoryTransfer.DestinationOwnedDeviceDecision, any Error>, transferId: String) {
        if let previousContinuation = self.destinationOwnedDeviceDecisionContinuationForTransferId.removeValue(forKey: transferId) {
            previousContinuation.resume(throwing: ObvError.cancelled)
        }
        self.destinationOwnedDeviceDecisionContinuationForTransferId[transferId] = continuation
    }
    
    
    /// Returns `true` if a continuation was resumed, `false` otherwise.
    func resumeContinuation(transferId: String, decisionReceivedFromDestinationOwnedDevice: ObvHistoryTransfer.DestinationOwnedDeviceDecision) -> Bool {
        guard let continuation = self.destinationOwnedDeviceDecisionContinuationForTransferId.removeValue(forKey: transferId) else { return false }
        continuation.resume(returning: decisionReceivedFromDestinationOwnedDevice)
        return true
    }
    
    enum ObvError: Error {
        case cancelled
    }
    
}
