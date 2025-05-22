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
import ObvTypes
import LinkPresentation
import OlvidUtils
import ObvEngine
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants
import ObvLocation


final class BootstrapCoordinator: OlvidCoordinator, ObvErrorMaker {
    
    let obvEngine: ObvEngine
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: BootstrapCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    let coordinatorsQueue: OperationQueue
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?
    
    static let errorDomain = "BootstrapCoordinator"
    
    private let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)
    
    init(obvEngine: ObvEngine, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue, queueForSyncHintsComputationOperation: OperationQueue) {
        self.obvEngine = obvEngine
        self.queueForSyncHintsComputationOperation = queueForSyncHintsComputationOperation
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        listenToNotifications()
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        await updateLegacyStatusesOfSentMessagesIfRequired()
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
        
        if forTheFirstTime {
            await syncAppDatabasesWithEngineIfRequired(queuePriority: .normal, syncRequestType: .foreground)
            await refreshInvitationsBadgeCountsForAllOwnedIdentities()
            deleteOrphanedPersistedAttachmentSentRecipientInfosOperation()
            await migrateUtiOfFyleMessageJoinWithStatusForLinkPreviews()
            await resetInconsistentDiscussionExistenceAndVisibilityDurations()
        }
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
            ObvMessengerInternalNotification.observeResyncContactIdentityDevicesWithEngine { [weak self] obvContactIdentifier in
                Task { [weak self] in await self?.processResyncContactIdentityDevicesWithEngineNotification(obvContactIdentifier: obvContactIdentifier) }
            },
        ])
        
    }
    
    
    enum ObvError: Error {
        case selfIsNil
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
    

    /// Update the legacy sent message statutes of previously sent messages to update them if required. This method also consolidates the timestamps in sent message infos as, before v3.1,
    /// we could end up in a situation where a sent info could have a non-nil delivered timestamp, with a nil sent timestamp (which makes no sense).
    private func updateLegacyStatusesOfSentMessagesIfRequired() async {

        guard let userDefaults else { assertionFailure(); return }

        // We only allow the commit of 50 changes at once per operation. This is to make sure that saving the Core Data context doesn't take too long.
        let maxNumberOfChanges = 50
                
        do {
            
            let userDefaultsKey = "BootstrapCoordinator.ConsolidateLegacyTimestampsOfPersistedMessageSentRecipientInfosOperation.wasFullyPerformed"
            defer {
                userDefaults.setValue(true, forKey: userDefaultsKey)
            }

            if userDefaults.value(forKey: userDefaultsKey) == nil {
                
                var operationDidSaveSomeChanges = true

                while operationDidSaveSomeChanges {
                    
                    let op1 = ConsolidateLegacyTimestampsOfPersistedMessageSentRecipientInfosOperation(maxNumberOfChanges: maxNumberOfChanges)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    composedOp.queuePriority = .veryHigh
                    await coordinatorsQueue.addAndAwaitOperation(composedOp)
                    
                    guard op1.isFinished && !op1.isCancelled else {
                        assertionFailure()
                        return
                    }
                    
                    operationDidSaveSomeChanges = op1.didSaveSomeChanges
                    
                }
                
                userDefaults.setValue(true, forKey: userDefaultsKey)
                                
            }
            
        }
        
        do {
            
            let userDefaultsKey = "BootstrapCoordinator.UpdateLegacyStatusesOfSentMessagesOperation.wasFullyPerformed"
            defer {
                userDefaults.setValue(true, forKey: userDefaultsKey)
            }

            if userDefaults.value(forKey: userDefaultsKey) == nil {
                
                var operationDidSaveSomeChanges = true

                while operationDidSaveSomeChanges {
                    
                    let op1 = UpdateLegacyStatusesOfSentMessagesOperation(maxNumberOfChanges: maxNumberOfChanges)
                    let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                    composedOp.queuePriority = .veryHigh
                    await coordinatorsQueue.addAndAwaitOperation(composedOp)
                    
                    guard op1.isFinished && !op1.isCancelled else {
                        assertionFailure()
                        return
                    }
                    
                    operationDidSaveSomeChanges = op1.didSaveSomeChanges
                    
                }
                
                userDefaults.setValue(true, forKey: userDefaultsKey)
                
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


    private func processResyncContactIdentityDevicesWithEngineNotification(obvContactIdentifier: ObvContactIdentifier) async {
        let operationsToQueueOnQueueForComposedOperation = await getOperationsRequiredToSyncContactDevices(scope: .contactDevicesOfContact(contactIdentifier: obvContactIdentifier), isRestoringSyncSnapshotOrBackup: false)
        operationsToQueueOnQueueForComposedOperation.makeEachOperationDependentOnThePreceedingOne()
        await coordinatorsQueue.addAndAwaitOperations(operationsToQueueOnQueueForComposedOperation)
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
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
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
    
    func userRequestedAppDatabaseSyncWithEngine(rootViewController: RootViewController) async throws {
        await syncAppDatabasesWithEngineIfRequired(queuePriority: .veryHigh, syncRequestType: .userRequested)
    }
    
}



// MARK: - Private helpers

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
