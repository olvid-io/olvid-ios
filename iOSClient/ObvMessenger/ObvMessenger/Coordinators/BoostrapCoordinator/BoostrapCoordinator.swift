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


final class BootstrapCoordinator: OlvidCoordinator, ObvErrorMaker {
    
    let obvEngine: ObvEngine
    static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BootstrapCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    let coordinatorsQueue: OperationQueue
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?
    
    static let errorDomain = "BootstrapCoordinator"
    
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)
    
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
        if let userDefaults = self.userDefaults {
            userDefaults.resetObjectsModifiedByShareExtension()
        }
        pruneObsoletePersistedInvitations()
        removeOldCachedPreviewFetched()
        resyncPersistedInvitationsWithEngine()
        sendUnsentDrafts()
        downloadPreviewsNotDownloadedYet()
        if ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled {
            ObvMessengerInternalNotification.userWantsToStartIncrementalCleanBackup(cleanAllDevices: false).postOnDispatchQueue()
        }
        deleteOldPendingRepliedTo()
        resetOwnObvCapabilities()
        autoAcceptPendingGroupInvitesIfPossible()
        if forTheFirstTime {
            await processRequestSyncAppDatabasesWithEngine(queuePriority: .normal, isRestoringSyncSnapshotOrBackup: false)
            await refreshInvitationsBadgeCountsForAllOwnedIdentities()
            deleteOrphanedPersistedAttachmentSentRecipientInfosOperation()
            await migrateUtiOfFyleMessageJoinWithStatusForLinkPreviews()
        }
    }
    
    
    private func listenToNotifications() {
        
        // Internal Notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeRequestSyncAppDatabasesWithEngine { [weak self] (queuePriority, isRestoringSyncSnapshotOrBackup, completion) in
                Task { [weak self] in
                    guard let self else { assertionFailure(); completion(.failure(ObvError.selfIsNil)); return }
                    await processRequestSyncAppDatabasesWithEngine(queuePriority: queuePriority, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
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
        let dateLimit = Date().addingTimeInterval(TimeInterval(integerLiteral: -ObvMessengerConstants.TTL.cachedURLMetadata))
        MissingReceivedLinkPreviewFetcher.removeCachedPreviewFilesGenerated(olderThan: dateLimit)
    }

    private func resyncPersistedInvitationsWithEngine() {
        Task(priority: .utility) {
            do {
                guard let syncAtomRequestDelegate else { assertionFailure(); return }
                let obvDialogsFromEngine = try await obvEngine.getAllDialogsWithinEngine()
                let op1 = SyncPersistedInvitationsWithEngineOperation(obvDialogsFromEngine: obvDialogsFromEngine, obvEngine: obvEngine, syncAtomRequestDelegate: syncAtomRequestDelegate)
                let composedOp = createCompositionOfOneContextualOperation(op1: op1)
                composedOp.queuePriority = .veryLow
                coordinatorsQueue.addOperation(composedOp)
            } catch {
                os_log("Could not get all the dialog from engine: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            }
        }
    }

    
    private func refreshInvitationsBadgeCountsForAllOwnedIdentities() async {
        let op1 = RefreshInvitationsBadgeCountsForAllOwnedIdentitiesOperation()
        await queueAndAwaitCompositionOfOneContextualOperation(op1: op1)
    }

    
    private func sendUnsentDrafts() {
        let op1 = SendUnsentDraftsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryLow
        coordinatorsQueue.addOperation(composedOp)
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

    
    private func processRequestSyncAppDatabasesWithEngine(queuePriority: Operation.QueuePriority, isRestoringSyncSnapshotOrBackup: Bool) async {
        
        let syncUUID = UUID()
        
        os_log("↻ %{public}@ Starting a sync with priority %{public}@", log: Self.log, type: .debug, syncUUID.debugDescription, queuePriority.debugDescription)
        
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
            let ops = await getOperationsRequiredToSyncOwnedIdentities(isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.ownedIdentities)
            }
            os_log("↻ %{public}@ Did sync owned identities", log: Self.log, type: .debug, syncUUID.debugDescription)
        }
        
        // Sync owned devices
        
        do {
            os_log("↻ %{public}@ Will sync owned devices", log: Self.log, type: .debug, syncUUID.debugDescription)
            let ops = await getOperationsRequiredToSyncOwnedDevices(scope: .allOwnedDevices)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.ownedDevices)
            }
            os_log("↻ %{public}@ Did sync owned devices", log: Self.log, type: .debug, syncUUID.debugDescription)
        }
        
        // Sync contact identities
        
        do {
            os_log("↻ %{public}@ Will sync contacts", log: Self.log, type: .debug, syncUUID.debugDescription)
            let ops = await getOperationsRequiredToSyncContacts(scope: .allContacts, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.contacts)
            }
            os_log("↻ %{public}@ Did sync contacts", log: Self.log, type: .debug, syncUUID.debugDescription)
        }
        
        // Sync contact devices
        
        do {
            os_log("↻ %{public}@ Will sync contact devices", log: Self.log, type: .debug, syncUUID.debugDescription)
            let ops = await getOperationsRequiredToSyncContactDevices(scope: .allContactDevices, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.contactDevices)
            }
            os_log("↻ %{public}@ Did sync contact devices", log: Self.log, type: .debug, syncUUID.debugDescription)
        }
        
        // Sync group v1
        
        do {
            os_log("↻ %{public}@ Will sync groups V1", log: Self.log, type: .debug, syncUUID.debugDescription)
            let ops = await getOperationsRequiredToSyncGroupsV1(isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.groupsV1)
            }
            os_log("↻ %{public}@ Did sync groups V1", log: Self.log, type: .debug, syncUUID.debugDescription)
        }
        
        // Sync group v2
        
        do {
            os_log("↻ %{public}@ Will sync groups V2", log: Self.log, type: .debug, syncUUID.debugDescription)
            let ops = await getOperationsRequiredToSyncGroupsV2(isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
            if !ops.isEmpty {
                ops.forEach { $0.queuePriority = queuePriority }
                await coordinatorsQueue.addAndAwaitOperations(ops)
                ops.forEach { assert($0.isFinished && !$0.isCancelled) }
                syncPerformed.insert(.groupsV2)
            }
            os_log("↻ %{public}@ Did sync groups V2", log: Self.log, type: .debug, syncUUID.debugDescription)
        }
        
        // Break out if possible
        
        os_log("↻ %{public}@ Sync performed: %{public}@", log: Self.log, type: .debug, syncUUID.debugDescription, syncPerformed.isEmpty ? "None" : syncPerformed.map({ $0.debugDescription }).joined(separator: ","))
                
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
