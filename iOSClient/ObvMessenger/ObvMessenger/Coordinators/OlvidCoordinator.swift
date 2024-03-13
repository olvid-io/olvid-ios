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
import ObvEngine
import OlvidUtils


/// This protocol is implemented by the various coordinators within the app (like the ``BootstrapCoordinator`` or the ``PersistedDiscussionsUpdatesCoordinator``). It allows to implement
/// a few methods that are useful to all coordinators.
protocol OlvidCoordinator {
    
    static var log: OSLog { get }

    var obvEngine: ObvEngine { get }
    
    var coordinatorsQueue: OperationQueue { get }
    var queueForComposedOperations: OperationQueue { get }
    var queueForSyncHintsComputationOperation: OperationQueue { get }
    
}


// MARK: - Obtaining the appropriate operations to execute in order to stay in sync with the engine

extension OlvidCoordinator {
    
    func getOperationsRequiredToSyncOwnedIdentities(isRestoringSyncSnapshotOrBackup: Bool) async -> [Operation] {
     
        var operationsToQueueOnQueueForComposedOperation = [Operation]()

        let op = ComputeHintsAboutRequiredOwnedIdentitiesSyncWithEngineOperation(obvEngine: obvEngine, contextForAppQueries: ObvStack.shared.newBackgroundContext())
        await queueForSyncHintsComputationOperation.addAndAwaitOperation(op)
        assert(op.isFinished && !op.isCancelled)
        for cryptoIdToDelete in op.cryptoIdsToDelete {
            let op1 = SyncPersistedObvOwnedIdentityWithEngineOperation(syncType: .deleteFromApp(ownedCryptoId: cryptoIdToDelete), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for cryptoIdToAdd in op.missingCryptoIds {
            let op1 = SyncPersistedObvOwnedIdentityWithEngineOperation(syncType: .addToApp(ownedCryptoId: cryptoIdToAdd, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for cryptoIdToUpdate in op.cryptoIdsToUpdate {
            let op1 = SyncPersistedObvOwnedIdentityWithEngineOperation(syncType: .syncWithEngine(ownedCryptoId: cryptoIdToUpdate), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }

        operationsToQueueOnQueueForComposedOperation.makeEachOperationDependentOnThePreceedingOne()
        return operationsToQueueOnQueueForComposedOperation
        
    }
    
    
    func getOperationsRequiredToSyncOwnedDevices(scope: ComputeHintsAboutRequiredOwnedDevicesSyncWithEngineOperation.Scope) async -> [Operation] {
        
        var operationsToQueueOnQueueForComposedOperation = [Operation]()

        let op = ComputeHintsAboutRequiredOwnedDevicesSyncWithEngineOperation(obvEngine: obvEngine, scope: scope, contextForAppQueries: ObvStack.shared.newBackgroundContext())
        await queueForSyncHintsComputationOperation.addAndAwaitOperation(op)
        assert(op.isFinished && !op.isCancelled)
        for deviceToDelete in op.devicesToDelete {
            let op1 = SyncPersistedObvOwnedDeviceWithEngineOperation(syncType: .deleteFromApp(ownedDeviceIdentifier: deviceToDelete), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for deviceToAdd in op.missingDevices {
            let op1 = SyncPersistedObvOwnedDeviceWithEngineOperation(syncType: .addToApp(ownedDeviceIdentifier: deviceToAdd), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for deviceToUpdate in op.devicesToUpdate {
            let op1 = SyncPersistedObvOwnedDeviceWithEngineOperation(syncType: .syncWithEngine(ownedDeviceIdentifier: deviceToUpdate), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }

        operationsToQueueOnQueueForComposedOperation.makeEachOperationDependentOnThePreceedingOne()
        return operationsToQueueOnQueueForComposedOperation
        
    }

    
    func getOperationsRequiredToSyncContacts(scope: ComputeHintsAboutRequiredContactIdentitiesSyncWithEngineOperation.Scope, isRestoringSyncSnapshotOrBackup: Bool) async -> [Operation] {

        var operationsToQueueOnQueueForComposedOperation = [Operation]()

        let op = ComputeHintsAboutRequiredContactIdentitiesSyncWithEngineOperation(obvEngine: obvEngine, scope: scope, contextForAppQueries: ObvStack.shared.newBackgroundContext())
        await queueForSyncHintsComputationOperation.addAndAwaitOperation(op)
        assert(op.isFinished && !op.isCancelled)
        for contactToDelete in op.contactsToDelete {
            let op1 = SyncPersistedObvContactIdentityWithEngineOperation(syncType: .deleteFromApp(contactIdentifier: contactToDelete), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for contactToAdd in op.missingContacts {
            let op1 = SyncPersistedObvContactIdentityWithEngineOperation(syncType: .addToApp(contactIdentifier: contactToAdd, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for contactToUpdate in op.contactsToUpdate {
            let op1 = SyncPersistedObvContactIdentityWithEngineOperation(syncType: .syncWithEngine(contactIdentifier: contactToUpdate, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }

        operationsToQueueOnQueueForComposedOperation.makeEachOperationDependentOnThePreceedingOne()
        return operationsToQueueOnQueueForComposedOperation
        
    }

    
    /// This method is typically used during bootstrap, for syncing contact groups between the engine and the app. The ``queueForSyncHintsComputationOperation`` is
    /// exepected to be a queue that is not synced with the queue for app databases operations, as iy may perform a heavy operation.
    func getOperationsRequiredToSyncContactDevices(scope: ComputeHintsAboutRequiredContactDevicesSyncWithEngineOperation.Scope, isRestoringSyncSnapshotOrBackup: Bool) async -> [Operation] {
        
        var operationsToQueueOnQueueForComposedOperation = [Operation]()

        let op = ComputeHintsAboutRequiredContactDevicesSyncWithEngineOperation(obvEngine: obvEngine, scope: scope, contextForAppQueries: ObvStack.shared.newBackgroundContext())
        await queueForSyncHintsComputationOperation.addAndAwaitOperation(op)
        assert(op.isFinished && !op.isCancelled)
        for deviceToDelete in op.devicesToDelete {
            let op1 = SyncPersistedObvContactDeviceWithEngineOperation(syncType: .deleteFromApp(contactDeviceIdentifier: deviceToDelete), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for deviceToAdd in op.missingDevices {
            let op1 = SyncPersistedObvContactDeviceWithEngineOperation(syncType: .addToApp(contactDeviceIdentifier: deviceToAdd, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for deviceToUpdate in op.devicesToUpdate {
            let op1 = SyncPersistedObvContactDeviceWithEngineOperation(syncType: .syncWithEngine(contactDeviceIdentifier: deviceToUpdate, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }

        operationsToQueueOnQueueForComposedOperation.makeEachOperationDependentOnThePreceedingOne()
        return operationsToQueueOnQueueForComposedOperation
        
    }

    
    /// This method is typically used during bootstrap, for syncing contact groups between the engine and the app. The ``queueForSyncHintsComputationOperation`` is
    /// exepected to be a queue that is not synced with the queue for app databases operations, as iy may perform a heavy operation.
    func getOperationsRequiredToSyncGroupsV1(isRestoringSyncSnapshotOrBackup: Bool) async -> [Operation] {
        
        var operationsToQueueOnQueueForComposedOperation = [Operation]()

        let op = ComputeHintsAboutRequiredContactGroupsSyncWithEngineOperation(obvEngine: obvEngine, scope: .allGroupsV1, contextForAppQueries: ObvStack.shared.newBackgroundContext())
        await queueForSyncHintsComputationOperation.addAndAwaitOperation(op)
        assert(op.isFinished && !op.isCancelled)
        for groupToDelete in op.contactGroupsToDelete {
            let op1 = SyncPersistedContactGroupWithEngineOperation(syncType: .deleteFromApp(groupIdentifier: groupToDelete), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for groupToAdd in op.missingContactGroups {
            let op1 = SyncPersistedContactGroupWithEngineOperation(syncType: .addToApp(groupIdentifier: groupToAdd, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for groupToUpdate in op.contactGroupsToUpdate {
            let op1 = SyncPersistedContactGroupWithEngineOperation(syncType: .syncWithEngine(groupIdentifier: groupToUpdate), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }

        operationsToQueueOnQueueForComposedOperation.makeEachOperationDependentOnThePreceedingOne()
        return operationsToQueueOnQueueForComposedOperation
        
    }

    
    func getOperationsRequiredToSyncGroupsV2(isRestoringSyncSnapshotOrBackup: Bool) async -> [Operation] {
        
        var operationsToQueueOnQueueForComposedOperation = [Operation]()

        let op = ComputeHintsAboutRequiredContactGroupsV2SyncWithEngineOperation(obvEngine: obvEngine, scope: .allGroupsV1, contextForAppQueries: ObvStack.shared.newBackgroundContext())
        await queueForSyncHintsComputationOperation.addAndAwaitOperation(op)
        assert(op.isFinished && !op.isCancelled)
        for groupToDelete in op.groupsToDelete {
            let op1 = SyncPersistedContactGroupV2WithEngineOperation(syncType: .deleteFromApp(groupIdentifier: groupToDelete), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for groupToAdd in op.missingGroups {
            let op1 = SyncPersistedContactGroupV2WithEngineOperation(syncType: .addToApp(groupIdentifier: groupToAdd, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }
        for groupToUpdate in op.groupsToUpdate {
            let op1 = SyncPersistedContactGroupV2WithEngineOperation(syncType: .syncWithEngine(groupIdentifier: groupToUpdate, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup), obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            operationsToQueueOnQueueForComposedOperation.append(composedOp)
        }

        operationsToQueueOnQueueForComposedOperation.makeEachOperationDependentOnThePreceedingOne()
        return operationsToQueueOnQueueForComposedOperation
        
    }

}


// MARK: - Creating compositions of contextual operations

extension OlvidCoordinator {
    
    func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) -> CompositionOfOneContextualOperation<T> {
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }
    
    
    func createCompositionOfTwoContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>) -> CompositionOfTwoContextualOperations<T1, T2> {
        let composedOp = CompositionOfTwoContextualOperations(op1: op1, op2: op2, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

    
    func createCompositionOfThreeContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType, T3: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, op3: ContextualOperationWithSpecificReasonForCancel<T3>) -> CompositionOfThreeContextualOperations<T1, T2, T3> {
        let composedOp = CompositionOfThreeContextualOperations(op1: op1, op2: op2, op3: op3, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

    
    func createCompositionOfFourContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType, T3: LocalizedErrorWithLogType, T4: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, op3: ContextualOperationWithSpecificReasonForCancel<T3>, op4: ContextualOperationWithSpecificReasonForCancel<T4>) -> CompositionOfFourContextualOperations<T1, T2, T3, T4> {
        let composedOp = CompositionOfFourContextualOperations(op1: op1, op2: op2, op3: op3, op4: op4, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

}


// MARK: - Queing compositions of contextual operations

extension OlvidCoordinator {
    
    func queueAndAwaitCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>) async {
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        await coordinatorsQueue.addAndAwaitOperation(composedOp)
        assert(op1.isFinished && !op1.isCancelled)
        assert(composedOp.isFinished && !composedOp.isCancelled)
    }

    
}
