/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


final class BootstrapCoordinator: ObvErrorMaker {
    
    private let obvEngine: ObvEngine
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BootstrapCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    private let coordinatorsQueue: OperationQueue
    private let queueForComposedOperations: OperationQueue
    weak var syncAtomRequestDelegate: ObvSyncAtomRequestDelegate?

    static let errorDomain = "BootstrapCoordinator"

    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)

    init(obvEngine: ObvEngine, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue) {
        self.obvEngine = obvEngine
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
        removeOldCachedURLMetadata()
        resyncPersistedInvitationsWithEngine()
        sendUnsentDrafts()
        if ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled {
            ObvMessengerInternalNotification.userWantsToStartIncrementalCleanBackup(cleanAllDevices: false).postOnDispatchQueue()
        }
        deleteOldPendingRepliedTo()
        resetOwnObvCapabilities()
        autoAcceptPendingGroupInvitesIfPossible()
        if forTheFirstTime {
            processRequestSyncAppDatabasesWithEngine(queuePriority: .veryLow, completion: { _ in })
            deleteOrphanedPersistedAttachmentSentRecipientInfosOperation()
        }
    }

    
    private func listenToNotifications() {
        
        // Internal Notifications

        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observePersistedContactWasInserted { [weak self] contactPermanentID, _, _ in
                self?.processPersistedContactWasInsertedNotification(contactPermanentID: contactPermanentID)
            },
            ObvMessengerInternalNotification.observeRequestSyncAppDatabasesWithEngine { [weak self] (queuePriority, completion) in
                self?.processRequestSyncAppDatabasesWithEngine(queuePriority: queuePriority, completion: completion)
            },
        ])
        
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

    
    private func removeOldCachedURLMetadata() {
        let dateLimit = Date().addingTimeInterval(TimeInterval(integerLiteral: -ObvMessengerConstants.TTL.cachedURLMetadata))
        LPMetadataProvider.removeCachedURLMetadata(olderThan: dateLimit)
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

    
    private func sendUnsentDrafts() {
        let op1 = SendUnsentDraftsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryLow
        coordinatorsQueue.addOperation(composedOp)
    }


    private func processRequestSyncAppDatabasesWithEngine(queuePriority: Operation.QueuePriority, completion: @escaping (Result<Void,Error>) -> Void) {
        assert(!Thread.isMainThread)

        var operationsToQueue = [Operation]()
        
        do {
            let op1 = SyncPersistedObvOwnedIdentitiesWithEngineOperation(obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.queuePriority = queuePriority
            composedOp.logExecutionDuration(log: Self.log)
            operationsToQueue.append(composedOp)
        }
        
        do {
            let op1 = SyncPersistedObvOwnedDevicesWithEngineOperation(obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.queuePriority = queuePriority
            composedOp.logExecutionDuration(log: Self.log)
            operationsToQueue.append(composedOp)
        }
        
        do {
            let op1 = SyncPersistedObvContactIdentitiesWithEngineOperation(obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.queuePriority = queuePriority
            composedOp.logExecutionDuration(log: Self.log)
            operationsToQueue.append(composedOp)
        }

        do {
            let op1 = SyncPersistedObvContactDevicesWithEngineOperation(obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.queuePriority = queuePriority
            composedOp.logExecutionDuration(log: Self.log)
            operationsToQueue.append(composedOp)
        }
        
        do {
            let op1 = SyncPersistedContactGroupsWithEngineOperation(obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.queuePriority = queuePriority
            composedOp.logExecutionDuration(log: Self.log)
            operationsToQueue.append(composedOp)
        }

        do {
            let op1 = SyncPersistedContactGroupsV2WithEngineOperation(obvEngine: obvEngine)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.queuePriority = queuePriority
            composedOp.logExecutionDuration(log: Self.log)
            operationsToQueue.append(composedOp)
        }
        
        let blockOp = BlockOperation()
        blockOp.completionBlock = {
            guard operationsToQueue.allSatisfy({ $0.isFinished && !$0.isCancelled }) else {
                let reasonForCancel = Self.makeError(message: "One of the sync methods failed")
                assertionFailure()
                completion(.failure(reasonForCancel))
                return
            }
            completion(.success(()))
        }
        operationsToQueue.append(blockOp)
        
        operationsToQueue.makeEachOperationDependentOnThePreceedingOne()
        
        coordinatorsQueue.addOperations(operationsToQueue, waitUntilFinished: false)

    }

    
    private func processPersistedContactWasInsertedNotification(contactPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>) {
        /* When receiving a PersistedContactWasInsertedNotification, we re-sync the groups from the engine. This is required when the following situation occurs :
         * Bob creates a group with Alice and Charlie, who do not know each other. Alice receives a new list of group members including Charlie *before* she includes
         * Charlie in her contacts. In that case, Charlie stays in the list of pending members. Here, we re-sync the groups members, making sure Charlie appears in
         * the list of group members.
         */
        let op1 = SyncPersistedContactGroupsWithEngineOperation(obvEngine: obvEngine)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1)
        composedOp.queuePriority = .veryLow
        coordinatorsQueue.addOperation(composedOp)
    }
    
    
    private func resetOwnObvCapabilities() {
        do {
            try obvEngine.setCapabilitiesOfCurrentDeviceForAllOwnedIdentities(ObvMessengerConstants.supportedObvCapabilities)
        } catch {
            assertionFailure("Could not set capabilities")
        }
    }

}


// MARK: - Helpers

extension BootstrapCoordinator {

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

    
    private func createCompositionOfFourContextualOperation<T1: LocalizedErrorWithLogType, T2: LocalizedErrorWithLogType, T3: LocalizedErrorWithLogType, T4: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T1>, op2: ContextualOperationWithSpecificReasonForCancel<T2>, op3: ContextualOperationWithSpecificReasonForCancel<T3>, op4: ContextualOperationWithSpecificReasonForCancel<T4>) -> CompositionOfFourContextualOperations<T1, T2, T3, T4> {
        let composedOp = CompositionOfFourContextualOperations(op1: op1, op2: op2, op3: op3, op4: op4, contextCreator: ObvStack.shared, queueForComposedOperations: queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: Self.log)
        }
        return composedOp
    }

}
