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
import ObvEngine
import ObvTypes
import ObvUICoreData
import Combine
import ObvSettings
import OlvidUtils

final class AppCoordinatorsHolder: ObvSyncAtomRequestDelegate {
    
    private let obvEngine: ObvEngine
    private let persistedDiscussionsUpdatesCoordinator: PersistedDiscussionsUpdatesCoordinator
    private let bootstrapCoordinator: BootstrapCoordinator
    private let obvOwnedIdentityCoordinator: ObvOwnedIdentityCoordinator
    private let contactIdentityCoordinator: ContactIdentityCoordinator
    private let contactGroupCoordinator: ContactGroupCoordinator
    private let appSyncSnapshotableCoordinator: AppSyncSnapshotableCoordinator

    private var cancellables = Set<AnyCancellable>()
    
    init(obvEngine: ObvEngine) {

        ObvDisplayableLogs.shared.log("🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨 Creeating the coordonators serial queue")
        
        let queueSharedAmongCoordinators = LoggedOperationQueue.createSerialQueue(name: "Queue shared among coordinators", qualityOfService: .userInteractive)
        let queueForComposedOperations = {
            let queue = OperationQueue()
            queue.name = "Queue for composed operations"
            queue.qualityOfService = .userInteractive
            return queue
        }()
        let queueForOperationsMakingEngineCalls = {
            let queue = OperationQueue()
            queue.name = "Queue for operations making engine calls"
            queue.qualityOfService = .userInteractive
            return queue
        }()

        // Certain sync operations leverage "hints" operations that determine what should be done to ensure a proper sync between the app and the engine databases.
        // These operations do not modify the app database and thus don't need to be queued on the queue for composed operations.
        // Moreover, these hints operation might be time consuming, so we prefer not to dispatch them on the queue for composed operations.
        // Instead, we dispatch them on this queue, which doesn't have to be serial.
        let queueForSyncHintsComputationOperation = {
            let queue = OperationQueue()
            queue.name = "Queue executing hints operations"
            return queue
        }()

        self.obvEngine = obvEngine
        
        let messagesKeptForLaterManager = MessagesKeptForLaterManager()
        
        self.persistedDiscussionsUpdatesCoordinator = PersistedDiscussionsUpdatesCoordinator(
            obvEngine: obvEngine,
            coordinatorsQueue: queueSharedAmongCoordinators,
            queueForComposedOperations: queueForComposedOperations,
            queueForOperationsMakingEngineCalls: queueForOperationsMakingEngineCalls,
            queueForSyncHintsComputationOperation: queueForSyncHintsComputationOperation,
            messagesKeptForLaterManager: messagesKeptForLaterManager)
        self.bootstrapCoordinator = BootstrapCoordinator(
            obvEngine: obvEngine,
            coordinatorsQueue: queueSharedAmongCoordinators,
            queueForComposedOperations: queueForComposedOperations, 
            queueForSyncHintsComputationOperation: queueForSyncHintsComputationOperation)
        self.obvOwnedIdentityCoordinator = ObvOwnedIdentityCoordinator(
            obvEngine: obvEngine,
            coordinatorsQueue: queueSharedAmongCoordinators,
            queueForComposedOperations: queueForComposedOperations,
            queueForSyncHintsComputationOperation: queueForSyncHintsComputationOperation)
        self.contactIdentityCoordinator = ContactIdentityCoordinator(
            obvEngine: obvEngine,
            coordinatorsQueue: queueSharedAmongCoordinators,
            queueForComposedOperations: queueForComposedOperations,
            queueForSyncHintsComputationOperation: queueForSyncHintsComputationOperation)
        self.contactGroupCoordinator = ContactGroupCoordinator(
            obvEngine: obvEngine,
            coordinatorsQueue: queueSharedAmongCoordinators,
            queueForComposedOperations: queueForComposedOperations,
            queueForSyncHintsComputationOperation: queueForSyncHintsComputationOperation)
        self.appSyncSnapshotableCoordinator = AppSyncSnapshotableCoordinator(
            obvEngine: obvEngine,
            coordinatorsQueue: queueSharedAmongCoordinators,
            queueForComposedOperations: queueForComposedOperations,
            queueForSyncHintsComputationOperation: queueForSyncHintsComputationOperation)
        
        self.persistedDiscussionsUpdatesCoordinator.syncAtomRequestDelegate = self
        self.obvOwnedIdentityCoordinator.syncAtomRequestDelegate = self
        self.contactIdentityCoordinator.syncAtomRequestDelegate = self
        self.contactGroupCoordinator.syncAtomRequestDelegate = self
        self.bootstrapCoordinator.syncAtomRequestDelegate = self
        // No syncAtomRequestDelegate for the AppSyncSnapshotableCoordinator
        
    }
    
    
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }
    

    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        if forTheFirstTime {
            observeSettingsChangeToSyncThemWithOtherOwnedDevices()
        }
        await self.persistedDiscussionsUpdatesCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.bootstrapCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.obvOwnedIdentityCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.contactIdentityCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.contactGroupCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.appSyncSnapshotableCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
    }

}


// MARK: - ObvSyncAtomRequestDelegate

extension AppCoordinatorsHolder {
    
    func requestPropagationToOtherOwnedDevices(of syncAtom: ObvSyncAtom, for ownedCryptoId: ObvCryptoId) async {
        
        do {
            try await obvEngine.requestPropagationToOtherOwnedDevices(of: syncAtom, for: ownedCryptoId)
        } catch {
            assertionFailure(error.localizedDescription)
        }
        
    }
    
    
    func deleteDialog(with uuid: UUID) throws {
        try obvEngine.deleteDialog(with: uuid)
    }
    
}


// MARK: - Sync ObvMessengerSettings with other owned devices

extension AppCoordinatorsHolder {
    
    private func observeSettingsChangeToSyncThemWithOtherOwnedDevices() {
        
        ObvMessengerSettingsObservableObject.shared.$autoAcceptGroupInviteFrom
            .compactMap { (autoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice, ownedCryptoId) in
                // Filter out changes made from another device since we don't need to sync with them
                guard !changeMadeFromAnotherOwnedDevice else { return nil }
                guard let ownedCryptoId else { return nil }
                return (autoAcceptGroupInviteFrom, ownedCryptoId)
            }
            .compactMap { (autoAcceptGroupInviteFrom: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom, ownedCryptoId: ObvCryptoId) in
                // Create the ObvSyncAtom
                let category = Self.getObvSyncAtomAutoJoinGroupsCategory(from: autoAcceptGroupInviteFrom)
                let syncAtom = ObvSyncAtom.settingAutoJoinGroups(category: category)
                return (syncAtom, ownedCryptoId)
            }
            .sink { [weak self] (syncAtom: ObvSyncAtom, ownedCryptoId: ObvCryptoId) in
                // Request the sync of the ObvSyncAtom to the engine
                Task { [weak self] in
                    await self?.requestPropagationToOtherOwnedDevices(of: syncAtom, for: ownedCryptoId)
                }
            }
            .store(in: &cancellables)
        
        ObvMessengerSettingsObservableObject.shared.$doSendReadReceipt
            .compactMap { (doSendReadReceipt: Bool, changeMadeFromAnotherOwnedDevice: Bool, ownedCryptoId: ObvCryptoId?) in
                // Filter out changes made from another device since we don't need to sync with them
                guard !changeMadeFromAnotherOwnedDevice else { return nil }
                guard let ownedCryptoId else { return nil }
                return (doSendReadReceipt, ownedCryptoId)
            }
            .compactMap { (doSendReadReceipt: Bool, ownedCryptoId: ObvCryptoId) in
                // Create the ObvSyncAtom
                let syncAtom = ObvSyncAtom.settingDefaultSendReadReceipts(sendReadReceipt: doSendReadReceipt)
                return (syncAtom, ownedCryptoId)
            }
            .sink { [weak self] (syncAtom: ObvSyncAtom, ownedCryptoId: ObvCryptoId) in
                // Request the sync of the ObvSyncAtom to the engine
                Task { [weak self] in
                    await self?.requestPropagationToOtherOwnedDevices(of: syncAtom, for: ownedCryptoId)
                }
            }
            .store(in: &cancellables)

    }

    
    private static func getObvSyncAtomAutoJoinGroupsCategory(from category: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom) -> ObvSyncAtom.AutoJoinGroupsCategory {
        switch category {
        case .everyone:
            return .everyone
        case .noOne:
            return .nobody
        case .oneToOneContactsOnly:
            return .contacts
        }
    }
    
    
}


final class LoggedOperationQueue: OperationQueue {
    
    override func addOperations(_ ops: [Operation], waitUntilFinished wait: Bool) {
        ops.forEach { op in
            op.printObvDisplayableLogsWhenFinished()
        }
        _ = logOperations(ops: ops)
        super.addOperations(ops, waitUntilFinished: wait)
    }
    
    
    override func addOperation(_ op: Operation) {
        op.printObvDisplayableLogsWhenFinished()
        _ = logOperations(ops: [op])
        super.addOperation(op)
    }
    
    
    func logOperations(ops: [Operation]) -> String {
        let queuedOperations = ops.map({ $0.debugDescription })
        let currentOperations = self.operations
        if !currentOperations.isEmpty {
            let currentNotExecutingOperations = currentOperations.filter({ !$0.isExecuting })
            let currentExecutingOperations = currentOperations.filter({ $0.isExecuting })
            let currentNotExecutingOperationsAsString = currentNotExecutingOperations.map({ $0.debugDescription }).joined(separator: ", ")
            let currentExecutingOperationsAsString = currentExecutingOperations.map({ $0.debugDescription }).joined(separator: ", ")
            let stringToLog = "🍒⚠️ Queuing operation \(queuedOperations) but the queue (isSuspended=\(self.isSuspended)) is already executing the following \(currentExecutingOperations.count) operations: \(currentExecutingOperationsAsString). The following \(currentNotExecutingOperations.count) operations still need to be executed: \(currentNotExecutingOperationsAsString)"
            ObvDisplayableLogs.shared.log(stringToLog)
            return stringToLog
        } else {
            let stringToLog = "🍒✅ Queuing operation \(queuedOperations)"
            ObvDisplayableLogs.shared.log(stringToLog)
            return stringToLog
        }
    }
        
}


private extension Operation {
    
    func printObvDisplayableLogsWhenFinished() {
        if let completion = self.completionBlock {
            self.completionBlock = {
                ObvDisplayableLogs.shared.log("🐷 \(self.debugDescription) is finished")
                completion()
            }
        } else {
            self.completionBlock = {
                ObvDisplayableLogs.shared.log("🐷 \(self.debugDescription) is finished")
            }
        }
    }
    
}
