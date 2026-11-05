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
import os
import CoreData
import ObvTypes
import OlvidUtils
@preconcurrency import ObvEngine
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants
import ObvLocation
import ObvAppInboxService
import ObvAppTypes


protocol BootstrapCoordinatorDelegate: AnyObject {
    func reprocessEngineMessagesForLater(_ bootstrapCoordinator: BootstrapCoordinator, messageIdentifiersForLater: [ObvMessageIdentifier]) async
}


/// **`@unchecked Sendable`, and the promise covers one property only.**
///
/// The conformance is required by ``PersistedObvOwnedIdentityObserver``, which this registers itself with — so this object really is reached from more than
/// one place, and the requirement is not a formality. What is left mutable after the re-entrancy guard moved under its own lock is ``observationTokens``, and
/// that one is safe by its lifetime rather than by exclusion: it is written by `listenToNotifications()`, which `init` calls before this object is handed to
/// anybody, and read again only in `deinit`, when nobody holds it. Nothing writes it in between.
///
/// **It is not a blanket.** Any stored property added here that is written while the app runs needs its own answer, as the sync guard did — the compiler will
/// no longer ask.
final class BootstrapCoordinator: OlvidCoordinator, ObvErrorMaker, @unchecked Sendable {
    
    let obvEngine: ObvEngine
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: BootstrapCoordinator.self))
    static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: BootstrapCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    let coordinatorsQueue: OperationQueue
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?
    weak var delegate: BootstrapCoordinatorDelegate?
    
    /// Not private: the stale-settings pass of the engine-inbox drain lives in an extension of its own, in another file, and walks this service's rows.
    let appInboxService: ObvAppInboxService
    /// Whether a sync of the message identifiers kept for later is already running, so a second one stands aside.
    ///
    /// **Under a lock because the three callers can genuinely overlap**, and a plain `Bool` cannot express *test it and claim it* as one act. This screen's
    /// coordinator is reached from the app appearing, from a background task and from the reader asking, each on whatever executor called it — so two of them
    /// reading `false` before either writes `true` is a thing that can happen, and the guard would then let both through, which is the one outcome it exists to
    /// prevent. `PersistedDiscussionsUpdatesCoordinator` holds *have I already done this* the same way.
    private let isSyncMessageIdsKeptForLaterIfRequiredInProgress = OSAllocatedUnfairLock<Bool>(initialState: false)
    /// Whether a drain of the engine's inbox is already running, so a second one stands aside. Two callers rather than the three above — a background
    /// processing task and the reader asking in the settings — and the same reason: they can overlap, and on whatever executor called them.
    let isDrainingTheEngineInboxInProgress = OSAllocatedUnfairLock<Bool>(initialState: false)
    private let siriVocabularyManager = SiriVocabularyManager()

    static let errorDomain = "BootstrapCoordinator"

    /// Not private: the drain of the engine's inbox writes its report here, from an extension in its own file.
    let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)
    
    init(obvEngine: ObvEngine, appInboxService: ObvAppInboxService, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue, queueForSyncHintsComputationOperation: OperationQueue) {
        self.obvEngine = obvEngine
        self.appInboxService = appInboxService
        self.queueForSyncHintsComputationOperation = queueForSyncHintsComputationOperation
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        listenToNotifications()
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        
        if forTheFirstTime {

            await setDateOfCreationOfFirstProfileIfRequired(withDate: nil)
            pruneObsoletePersistedInvitations()
            removeOldCachedPreviewFetched()
            await resyncPersistedInvitationsWithEngine()
            downloadPreviewsNotDownloadedYet()
            if ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled {
                ObvMessengerInternalNotification.userWantsToStartIncrementalCleanBackup(cleanAllDevices: false).postOnDispatchQueue()
            }
            deleteOldPendingRepliedTo()
            resetOwnObvCapabilities()
            autoAcceptPendingGroupInvitesIfPossible()
            
            if #available(iOS 17.0, *) {
                await removeDirectoryForLegacyMapSnapshots()
            }

            await syncAppDatabasesWithEngineIfRequired(queuePriority: .normal, syncRequestType: .foreground)
            await refreshInvitationsBadgeCountsForAllOwnedIdentities()
            deleteOrphanedPersistedAttachmentSentRecipientInfosOperation()
            await migrateUtiOfFyleMessageJoinWithStatusForLinkPreviews()
            await resetInconsistentDiscussionExistenceAndVisibilityDurations()
            do {
                try await syncMessageIdsKeptForLaterIfRequired(syncRequestType: .foreground)
            } catch {
                Self.logger.fault("Could not sync message IDs kept for later: \(error)")
            }
            await updateContactsAndDiscussionsVocabularies()
        }
        
    }
    
    private func updateContactsAndDiscussionsVocabularies() async {
        await siriVocabularyManager.performPostInitialization()
        await siriVocabularyManager.updateContactsVocabularies()
    }
    
    private func listenToNotifications() {
        
        // Internal Notifications
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeRequestSyncAppDatabasesWithEngine { [weak self] (queuePriority, isRestoringSyncSnapshotOrBackup, completion) in
                Task { [weak self] in
                    guard let self else { assertionFailure(); completion(.failure(ObvError.selfIsNil)); return }
                    let syncRequestType: DatabaseSyncRequestType = isRestoringSyncSnapshotOrBackup ? .restoringSyncSnapshotOrBackup : .foreground
                    await syncAppDatabasesWithEngineIfRequired(queuePriority: queuePriority, syncRequestType: syncRequestType)
                    completion(.success((coordinatorsQueue, queueForComposedOperations)))
                }
            },
        ])
        
        Task {
            await PersistedObvOwnedIdentity.addObvObserver(self)
        }

    }
    
    
    enum ObvError: Error {
        case selfIsNil
    }
    
}

// MARK: - Implementing PersistedObvOwnedIdentityObserver

extension BootstrapCoordinator: PersistedObvOwnedIdentityObserver {
    
    func newPersistedObvOwnedIdentity(ownedCryptoId: ObvCryptoId, isActive: Bool) async {
        await setDateOfCreationOfFirstProfileIfRequired(withDate: Date.now)
    }

}


// MARK: - Implementing BackgroundTasksManagerDelegate

extension BootstrapCoordinator: BackgroundTasksManagerDelegate {
    
    func newBackupsAreConfiguredAndCanBePerformed() async throws -> Bool {
        let deviceBackupSeed = try await obvEngine.getDeviceActiveBackupSeed()
        return deviceBackupSeed != nil
    }
    
    
    func createAndUploadDeviceAndProfilesBackupDuringBackgroundProcessing() async throws {
        try await obvEngine.createAndUploadDeviceAndProfilesBackupDuringBackgroundProcessing()
    }
    
    
    func syncAppDatabasesWithEngine(backgroundTasksManager: BackgroundTasksManager) async throws {
        await syncAppDatabasesWithEngineIfRequired(queuePriority: .veryHigh, syncRequestType: .processingBackgroundTask)
    }
 
    
    func syncMessageIdsKeptForLater(_ backgroundTasksManager: BackgroundTasksManager) async throws {
        try await syncMessageIdsKeptForLaterIfRequired(syncRequestType: .processingBackgroundTask)
    }


    func drainEngineInbox(_ backgroundTasksManager: BackgroundTasksManager, deadline: Date, run: ObvInboxDrainInProgress) async -> ObvInboxDrainReport {
        await drainEngineInbox(deadline: deadline, run: run, trigger: .backgroundProcessingTask)
    }

}



extension BootstrapCoordinator {
    
    private func deleteOrphanedPersistedAttachmentSentRecipientInfosOperation() {
        assert(!Thread.isMainThread)
        let op1 = DeleteOrphanedPersistedAttachmentSentRecipientInfosOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryLow
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func pruneObsoletePersistedInvitations() {
        assert(!Thread.isMainThread)
        let op1 = DeletePersistedInvitationTheCannotBeParsedAnymoreOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryLow
        coordinatorsQueue.addOperation(composedOp)
    }
    

    private func setDateOfCreationOfFirstProfileIfRequired(withDate date: Date?) async {
        do {
            guard let userDefaults else { assertionFailure(); return }
            
            guard userDefaults.dateOrNil(for: ObvMessengerConstants.UserDefaultsKeys.dateOfCreationOfFirstProfile) == nil else {
                // The date of creation of the first profile is already set, there is nothing left to do.
                return
            }
            
            if let date {
                
                userDefaults.setDate(date, for: ObvMessengerConstants.UserDefaultsKeys.dateOfCreationOfFirstProfile)
                
            } else {
                
                let numberOfProfiles = try await countProfiles()
                guard numberOfProfiles > 0 else {
                    // No profile exists yet. The `dateOfCreationOfFirstProfile` will be set when a profile will be created.
                    return
                }
                guard let guessedDate = try await obvEngine.guessDateOfCreationOfFirstProfile() else {
                    // We could not guess the date of creation of the first profile, which can happen if the profile has no contacts
                    return
                }
                
                userDefaults.setDate(guessedDate, for: ObvMessengerConstants.UserDefaultsKeys.dateOfCreationOfFirstProfile)
                
            }
        } catch {
            Self.logger.fault("Could not set the date of creation of the first profile: \(error)")
            assertionFailure()
        }
    }
    
    
    private func countProfiles() async throws -> Int {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let count = try PersistedObvOwnedIdentity.countAll(within: context)
                    return continuation.resume(returning: count)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    /// If there exist some group invitations that are pending, but that should be automatically accepted based on the current app settings, we accept them during bootstraping.
    private func autoAcceptPendingGroupInvitesIfPossible() {
        assert(!Thread.isMainThread)
        let op1 = AutoAcceptPendingGroupInvitesIfPossibleOperation(obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryLow
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func deleteOldPendingRepliedTo() {
        assert(!Thread.isMainThread)
        let op1 = DeleteOldPendingRepliedToOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryLow
        coordinatorsQueue.addOperation(composedOp)
    }

    
    private func removeOldCachedPreviewFetched() {
        let dateLimit = Date.now.addingTimeInterval(-ObvMessengerConstants.TTL.cachedURLMetadata)
        MissingReceivedLinkPreviewFetcher.removeCachedPreviewFilesGenerated(olderThan: dateLimit)
    }
    
    @available(iOS 17.0, *)
    @MainActor
    private func removeDirectoryForLegacyMapSnapshots() {
        let snapshotDir = ObvUICoreDataConstants.ContainerURL.forMapSnapshots.url
        guard FileManager.default.fileExists(atPath: snapshotDir.path) else { return }
        do {
            try FileManager.default.removeItem(at: snapshotDir)
        } catch {
            assertionFailure()
        }
    }

    private func resyncPersistedInvitationsWithEngine() async {
        do {
            guard let syncAtomRequestDelegate else { assertionFailure(); return }
            let obvDialogsFromEngine = try await obvEngine.getAllDialogsWithinEngine()
            let op1 = SyncPersistedInvitationsWithEngineOperation(obvDialogsFromEngine: obvDialogsFromEngine, obvEngine: obvEngine, syncAtomRequestDelegate: syncAtomRequestDelegate)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            coordinatorsQueue.addOperation(composedOp)
        } catch {
            os_log("Could not get all the dialog from engine: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
    }

    
    private func refreshInvitationsBadgeCountsForAllOwnedIdentities() async {
        let op1 = RefreshInvitationsBadgeCountsForAllOwnedIdentitiesOperation()
        await queueAndAwaitCompositionOfOneContextualOperation(op1: op1)
    }

    
    private func downloadPreviewsNotDownloadedYet() {
        let operation = DownloadPreviewsNotDownloadedYetOperation(obvEngine: obvEngine)
        let composedOperation = createCompositionOfOneContextualOperation(op1: operation)
        composedOperation.queuePriority = .veryLow
        coordinatorsQueue.addOperation(composedOperation)
    }


    enum DatabaseSyncRequestType {
        case userRequested
        case foreground
        case processingBackgroundTask
        case restoringSyncSnapshotOrBackup
        var isRestoringSyncSnapshotOrBackup: Bool {
            switch self {
            case .restoringSyncSnapshotOrBackup:
                return true
            default:
                return false
            }
        }

    }

    
    private enum MessageIdsKeptForLaterSyncRequestType {
        case processingBackgroundTask
        case foreground
        case userRequested
    }
    
    
    private func syncMessageIdsKeptForLaterIfRequired(syncRequestType: MessageIdsKeptForLaterSyncRequestType) async throws {
        
        // Taken and claimed as one act — see ``isSyncMessageIdsKeptForLaterIfRequiredInProgress``. Whoever finds it free owns the sync until the `defer`.
        let thisSyncIsOurs = isSyncMessageIdsKeptForLaterIfRequiredInProgress.withLock { isInProgress in
            guard !isInProgress else { return false }
            isInProgress = true
            return true
        }
        guard thisSyncIsOurs else { return }
        defer { isSyncMessageIdsKeptForLaterIfRequiredInProgress.withLock { $0 = false } }
        
        guard let delegate else {
            assertionFailure()
            Self.logger.fault("Could not sync messageIdsKeptForLater as the delegate is nil")
            return
        }
        
        let syncUUID = UUID()

        // If we are processing a foreground request, we don't perform the sync if one was performed recently
        
        switch syncRequestType {
        case .foreground:
            assert(userDefaults != nil)
            let dateOfLastAppInboxSyncMessageIdsKeptForLater = userDefaults?.dateOrNil(forKey: ObvMessengerConstants.UserDefaultsKeys.dateOfLastAppInboxSyncMessageIdsKeptForLater.rawValue) ?? .distantPast
            guard Date.now.timeIntervalSince(dateOfLastAppInboxSyncMessageIdsKeptForLater) > TimeInterval(days: 2) else {
                Self.logger.debug("↻ \(syncUUID, privacy: .public) Not performing an app database sync in foreground as one was performed on \(dateOfLastAppInboxSyncMessageIdsKeptForLater, privacy: .public)")
                return
            }
            Self.logger.debug("↻ \(syncUUID, privacy: .public) Performing an app database sync in foreground as none has been performed recently (last one: \(dateOfLastAppInboxSyncMessageIdsKeptForLater, privacy: .public))")
        case .processingBackgroundTask, .userRequested:
            break
        }
        
        defer {
            userDefaults?.set(Date.now, forKey: ObvMessengerConstants.UserDefaultsKeys.dateOfLastAppInboxSyncMessageIdsKeptForLater.rawValue)
        }

        // Replay messages from engine kept for later that expect a discussion that now exist
        
        do {
            let allExpectedDiscussionIdentifiers = try await self.appInboxService.getAllExpectedDiscussionIdentifiers()
            for discussionIdentifier in allExpectedDiscussionIdentifiers {
                do {
                    if try await isDiscussionExisting(discussionIdentifier: discussionIdentifier) {
                        let messageIdentifiersForLater = await self.appInboxService.fetchMessageIdentifiersForLater(identifierOfExpectedDiscussion: discussionIdentifier)
                        await delegate.reprocessEngineMessagesForLater(self, messageIdentifiersForLater: messageIdentifiersForLater)
                    }
                } catch {
                    Self.logger.fault("Could not check if discussion \(discussionIdentifier) exists: \(error, privacy: .public)")
                }
            }
        } catch {
            Self.logger.fault("Could not get all expected discussion identifiers: \(error, privacy: .public)")
        }
                
        // Replay messages from engine kept for later that expect a group member that now exist

        do {
            let allExpectedGroupMemberIdentifiers = try await self.appInboxService.getAllExpectedGroupMembersIdentifiers()
            for memberId in allExpectedGroupMemberIdentifiers {
                do {
                    if try await isGroupMemberExisting(memberId: memberId) {
                        let messageIdentifiersForLater = await self.appInboxService.fetchMessageIdentifiersForLater(identifierOfExpectedGroup: memberId.groupId, cryptoIdOfExpectedContact: memberId.memberCryptoId)
                        await delegate.reprocessEngineMessagesForLater(self, messageIdentifiersForLater: messageIdentifiersForLater)
                    }
                } catch {
                    Self.logger.fault("Could not check if group member exists: \(error, privacy: .public)")
                }
            }
        } catch {
            Self.logger.fault("Could not get all expected group members identifiers: \(error, privacy: .public)")
        }

        // Replay messages from engine kept for later that expect a message that now exist
        
        do {
            let allExpectedMessageIdentifiers = try await self.appInboxService.getAllExpectedMessageIdentifiers()
            for messageId in allExpectedMessageIdentifiers {
                do {
                    if try await isMessageExisting(messageId: messageId) {
                        let messageIdentifiersForLater = await self.appInboxService.fetchMessageIdentifiersForLater(identifierOfExpectedMessage: messageId)
                        await delegate.reprocessEngineMessagesForLater(self, messageIdentifiersForLater: messageIdentifiersForLater)
                    }
                } catch {
                    Self.logger.fault("Could not check if message exists: \(error, privacy: .public)")
                }
            }
        } catch {
            Self.logger.fault("Could not get all expected message identifiers: \(error, privacy: .public)")
        }

    }
    
    
    private func syncAppDatabasesWithEngineIfRequired(queuePriority: Operation.QueuePriority, syncRequestType: DatabaseSyncRequestType) async {
        
        let syncUUID = UUID()
        
        let writeToDisplayableLogs: Bool
        switch syncRequestType {
        case .foreground, .userRequested, .restoringSyncSnapshotOrBackup:
            writeToDisplayableLogs = false
        case .processingBackgroundTask:
            writeToDisplayableLogs = true
        }
        
        // If we are processing a foreground request, we don't perform the sync if one was performed recently
        
        switch syncRequestType {
        case .foreground:
            assert(userDefaults != nil)
            let dateOfLastAppDatabaseSync = userDefaults?.dateOrNil(forKey: ObvMessengerConstants.UserDefaultsKeys.dateOfLastDatabaseSync.rawValue) ?? .distantPast
            guard Date.now.timeIntervalSince(dateOfLastAppDatabaseSync) > TimeInterval(days: 2) else {
                os_log("↻ %{public}@ Not performing an app database sync in foreground as one was performed on %{public}@", log: Self.log, type: .debug, syncUUID.debugDescription, dateOfLastAppDatabaseSync.description)
                return
            }
            os_log("↻ %{public}@ Performing an app database sync in foreground as none has been performed recently (last one: %{public}@)", log: Self.log, type: .debug, syncUUID.debugDescription, dateOfLastAppDatabaseSync.description)
        case .processingBackgroundTask, .userRequested, .restoringSyncSnapshotOrBackup:
            break
        }
        
        defer {
            userDefaults?.set(Date.now, forKey: ObvMessengerConstants.UserDefaultsKeys.dateOfLastDatabaseSync.rawValue)
        }
        
        // Perform the sync
        
        os_log("↻ %{public}@ Starting a sync with priority %{public}@", log: Self.log, type: .debug, syncUUID.debugDescription, queuePriority.debugDescription)
        if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Starting a sync with priority \(queuePriority.debugDescription)") }
        
        enum SyncPerformed: Hashable, CustomDebugStringConvertible {
            case ownedIdentities
            case ownedDevices
            case contacts
            case contactDevices
            case groupsV1
            case groupsV2
            var debugDescription: String {
                switch self {
                case .ownedIdentities: return "ownedIdentities"
                case .ownedDevices: return "ownedDevices"
                case .contacts: return "contacts"
                case .contactDevices: return "contactDevices"
                case .groupsV1: return "groupsV1"
                case .groupsV2: return "groupsV2"
                }
            }
        }
        
        var syncPerformed = Set<SyncPerformed>()
        
        // Sync owned identities
        
        do {
            os_log("↻ %{public}@ Will sync owned identities", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Will sync owned identities") }
            let ops = await getOperationsRequiredToSyncOwnedIdentities(isRestoringSyncSnapshotOrBackup: syncRequestType.isRestoringSyncSnapshotOrBackup)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.ownedIdentities)
            }
            os_log("↻ %{public}@ Did sync owned identities", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Did sync owned identities") }
        }
        
        // Sync owned devices
        
        do {
            os_log("↻ %{public}@ Will sync owned devices", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Will sync owned devices") }
            let ops = await getOperationsRequiredToSyncOwnedDevices(scope: .allOwnedDevices)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.ownedDevices)
            }
            os_log("↻ %{public}@ Did sync owned devices", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Did sync owned devices") }
        }
        
        // Sync contact identities
        
        do {
            os_log("↻ %{public}@ Will sync contacts", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Will sync contacts") }
            let ops = await getOperationsRequiredToSyncContacts(scope: .allContacts, isRestoringSyncSnapshotOrBackup: syncRequestType.isRestoringSyncSnapshotOrBackup)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.contacts)
            }
            os_log("↻ %{public}@ Did sync contacts", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Did sync contacts") }
        }
        
        // Sync contact devices
        
        do {
            os_log("↻ %{public}@ Will sync contact devices", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Will sync contact devices") }
            let ops = await getOperationsRequiredToSyncContactDevices(scope: .allContactDevices, isRestoringSyncSnapshotOrBackup: syncRequestType.isRestoringSyncSnapshotOrBackup)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.contactDevices)
            }
            os_log("↻ %{public}@ Did sync contact devices", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Did sync contact devices") }
        }
        
        // Sync group v1
        
        do {
            os_log("↻ %{public}@ Will sync groups V1", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Will sync groups V1") }
            let ops = await getOperationsRequiredToSyncGroupsV1(isRestoringSyncSnapshotOrBackup: syncRequestType.isRestoringSyncSnapshotOrBackup)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { op in
                    debugPrint(op)
                    assert(op.isFinished && !op.isCancelled)
                }
                syncPerformed.insert(.groupsV1)
            }
            os_log("↻ %{public}@ Did sync groups V1", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Did sync groups V1") }
        }
        
        // Sync group v2
        
        do {
            os_log("↻ %{public}@ Will sync groups V2", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Will sync groups V2") }
            let ops = await getOperationsRequiredToSyncGroupsV2(isRestoringSyncSnapshotOrBackup: syncRequestType.isRestoringSyncSnapshotOrBackup)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.groupsV2)
            }
            os_log("↻ %{public}@ Did sync groups V2", log: Self.log, type: .debug, syncUUID.debugDescription)
            if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Did sync groups V2") }
        }
        
        // Break out if possible
        
        os_log("↻ %{public}@ Sync performed: %{public}@", log: Self.log, type: .debug, syncUUID.debugDescription, syncPerformed.isEmpty ? "None" : syncPerformed.map({ $0.debugDescription }).joined(separator: ","))
        if writeToDisplayableLogs { ObvDisplayableLogs.shared.log("🤿 \(syncUUID.debugDescription) Sync performed: \(syncPerformed.isEmpty ? "None" : syncPerformed.map({ $0.debugDescription }).joined(separator: ","))") }

    }
    
    
    private func resetOwnObvCapabilities() {
        do {
            try obvEngine.setCapabilitiesOfCurrentDeviceForAllOwnedIdentities(ObvMessengerConstants.supportedObvCapabilities)
        } catch {
            assertionFailure("Could not set capabilities")
        }
    }
    
    
    /// 2023-01 : This method migrates previously received "link preview" attachments and updates their UTI.
    ///
    /// This is required in two cases:
    /// - before updating to v1.4, we received link preview from an Android device
    /// - before updating to v1.4, an owned device was an Android device and sent link previews
    private func migrateUtiOfFyleMessageJoinWithStatusForLinkPreviews() async {
        
        guard let userDefaults else { assertionFailure(); return }
        let userDefaultsKey = "BootstrapCoordinator.migrateUtiOfFyleMessageJoinWithStatusForLinkPreviews.wasCalled"
        guard userDefaults.value(forKey: userDefaultsKey) == nil else {
            // This method was called in the past, we don't run it twice.
            return
        }
        
        // Determine the objectIDs of FyleMessageJoinWithStatus that have an UTI that starts with the string "dyn."
        
        let objectIDsOfJoinsWithDynamicUTI: [TypeSafeManagedObjectID<FyleMessageJoinWithStatus>]
        do {
            let op1 = GetIdsOfFyleMessageJoinWithStatusWithDynamicUTIOperation()
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.queuePriority = .veryLow
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
            guard op1.isFinished && !op1.isCancelled else { assertionFailure(); return }
            guard let _joins = op1.idsOfJoinsWithDynamicUTI else { assertionFailure(); return }
            objectIDsOfJoinsWithDynamicUTI = _joins
        }
        
        for joinObjectID in objectIDsOfJoinsWithDynamicUTI {
            let op1 = MigrateUtiOfFyleMessageJoinWithStatusForLinkPreviewIfAppropriateOperation(objectID: joinObjectID)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.queuePriority = .veryLow
            await coordinatorsQueue.addAndAwaitOperation(composedOp)
        }

        userDefaults.setValue(true, forKey: userDefaultsKey)
                
    }
    
    
    private func resetInconsistentDiscussionExistenceAndVisibilityDurations() async {
        
        let op1 = ResetInconsistentDiscussionExistenceAndVisibilityDurationsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        guard op1.isFinished && !op1.isCancelled else { assertionFailure(); return }
        
    }

}


// MARK: - Called from the RootViewController

extension BootstrapCoordinator {
    
    /// Runs, on demand, the drain that a background processing task performs at night.
    ///
    /// The only way to exercise the drain on a simulator, where `scheduleBackgroundTasks()` submits nothing and there is no window to be launched into — and
    /// the only place a backlog can be forged to drain. The deadline is the reader's patience rather than a system window.
    /// - Parameter run: **the caller's** run, not one of our own. It is how the screen that asked for this stops it when the reader leaves, so creating
    /// another here — which an earlier version did, shadowing this parameter and compiling perfectly — leaves them holding an object nothing reads.
    ///
    /// **No deadline, deliberately.** Every other way this run can end says something about the work or about the reader's intent: there is nothing left to
    /// do, nothing is moving any more, the memory is running out, they left the screen, they backgrounded the app. A clock says neither, and it stops a run
    /// that is succeeding: a reader holding half a million messages needs the better part of an hour at the rate this clears them, and a five-minute cap
    /// turned that into ten taps each cut off mid-stride.
    ///
    /// What bounds it instead is the screen. The run holds the device awake only while that screen is up, and it is stopped by the screen going away or by
    /// the app being backgrounded — so a run nobody is watching does not exist. That is the whole of the guarantee, since the drain no longer takes a
    /// continued processing task and the endings that used to mention one are gone with it.
    func userRequestedDrainOfTheEngineInbox(rootViewController: RootViewController, run: ObvInboxDrainInProgress) async -> ObvInboxDrainReport {
        let report = await drainEngineInbox(deadline: .distantFuture, run: run, trigger: .userRequestedItInTheSettings)
        report.store(in: userDefaults)
        return report
    }


    func userRequestedAppDatabaseSyncWithEngine(rootViewController: RootViewController) async throws {
        await syncAppDatabasesWithEngineIfRequired(queuePriority: .veryHigh, syncRequestType: .userRequested)
        do {
            try await syncMessageIdsKeptForLaterIfRequired(syncRequestType: .userRequested)
        } catch {
            Self.logger.fault("Could not sync message identifiers kept for later: \(error)")
        }
    }
    
}



// MARK: - Private helpers when syncing engine message identifiers saved for later (during bootstrap)

extension BootstrapCoordinator {
    
    private func isDiscussionExisting(discussionIdentifier: ObvDiscussionIdentifier) async throws -> Bool {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let isExisting = try PersistedDiscussion.isPersistedDiscussionExisting(discussionIdentifier: discussionIdentifier, within: context)
                    return continuation.resume(returning: isExisting)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func isGroupMemberExisting(memberId: ObvGroupMemberIdentifier) async throws -> Bool {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let isExisting: Bool
                    switch memberId.groupId {
                    case .groupV1(let groupId):
                        isExisting = try PersistedContactGroup.isGroupMemberExisting(
                            groupId: groupId,
                            memberCryptoId: memberId.memberCryptoId,
                            within: context)
                    case .groupV2(let groupId):
                        isExisting = try PersistedGroupV2Member.isNonPendingGroupMemberWithAssociatedPersistedContactExisting(
                            groupId: groupId,
                            memberCryptoId: memberId.memberCryptoId,
                            within: context)
                    }
                    return continuation.resume(returning: isExisting)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func isMessageExisting(messageId: ObvMessageAppIdentifier) async throws -> Bool {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let isExisting = try PersistedMessage.isMessageExisting(messageId: messageId, within: context)
                    return continuation.resume(returning: isExisting)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
}

private extension Operation.QueuePriority {
    
    var debugDescription: String {
        switch self {
        case .veryLow: return "veryLow"
        case .low: return "low"
        case .normal: return "normal"
        case .high: return "high"
        case .veryHigh: return "veryHigh"
        @unknown default:
            assertionFailure()
            return "unknown"
        }
    }
    
}
