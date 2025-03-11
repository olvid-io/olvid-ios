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
import OSLog
import ObvEngine
import ObvTypes
import ObvUICoreData
import Combine
import ObvSettings
import OlvidUtils
import ObvAppCoreConstants

final class AppCoordinatorsHolder: ObvSyncAtomRequestDelegate {
    
    private let obvEngine: ObvEngine
    let persistedDiscussionsUpdatesCoordinator: PersistedDiscussionsUpdatesCoordinator
    let bootstrapCoordinator: BootstrapCoordinator
    private let obvOwnedIdentityCoordinator: ObvOwnedIdentityCoordinator
    private let contactIdentityCoordinator: ContactIdentityCoordinator
    private let contactGroupCoordinator: ContactGroupCoordinator
    private let appSyncSnapshotableCoordinator: AppSyncSnapshotableCoordinator
    let userNotificationsCoordinator: UserNotificationsCoordinator

    private var cancellables = Set<AnyCancellable>()
    
    init(obvEngine: ObvEngine, userNotificationsCoordinator: UserNotificationsCoordinator) {

        ObvDisplayableLogs.shared.log("INIT")
        
        let queueSharedAmongCoordinators = AppCoordinatorsQueue.shared
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
        self.userNotificationsCoordinator = userNotificationsCoordinator
        self.userNotificationsCoordinator.setObvEngine(to: obvEngine)
        
        self.persistedDiscussionsUpdatesCoordinator.syncAtomRequestDelegate = self
        self.obvOwnedIdentityCoordinator.syncAtomRequestDelegate = self
        self.contactIdentityCoordinator.syncAtomRequestDelegate = self
        self.contactGroupCoordinator.syncAtomRequestDelegate = self
        self.bootstrapCoordinator.syncAtomRequestDelegate = self
        // No syncAtomRequestDelegate for the AppSyncSnapshotableCoordinator
        // No syncAtomRequestDelegate for the UserNotificationsCoordinator
        
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
        await self.userNotificationsCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
    }

}


// MARK: - ObvSyncAtomRequestDelegate

extension AppCoordinatorsHolder {
    
    /// Used to propagate an ``ObvSyncAtom`` when it concerns a specific owned identity (e.g., like the order of pinned discussions).
    func requestPropagationToOtherOwnedDevices(of syncAtom: ObvSyncAtom, for ownedCryptoId: ObvCryptoId) async {
        do {
            try await obvEngine.requestPropagationToOtherOwnedDevices(of: syncAtom, for: ownedCryptoId)
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    
    /// Used to propagate an ``ObvSyncAtom`` when it concerns a **global** setting (e.g., like the global setting allowing to send read receipts).
    private func requestPropagationToOtherOwnedDevicesOfAllOwnedIdentities(of syncAtom: ObvSyncAtom) async {
        do {
            try await obvEngine.requestPropagationToOtherOwnedDevicesOfAllOwnedIdentities(of: syncAtom)
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
            .dropFirst() // Don't consider the initial value set on autoAcceptGroupInviteFrom
            .compactMap { (autoAcceptGroupInviteFrom, changeMadeFromAnotherOwnedDevice) in
                // Filter out changes made from another device since we don't need to sync with them
                guard !changeMadeFromAnotherOwnedDevice else { return nil }
                return autoAcceptGroupInviteFrom
            }
            .compactMap { (autoAcceptGroupInviteFrom: ObvMessengerSettings.ContactsAndGroups.AutoAcceptGroupInviteFrom) in
                // Create the ObvSyncAtom
                let category = Self.getObvSyncAtomAutoJoinGroupsCategory(from: autoAcceptGroupInviteFrom)
                let syncAtom = ObvSyncAtom.settingAutoJoinGroups(category: category)
                return syncAtom
            }
            .sink { [weak self] (syncAtom: ObvSyncAtom) in
                // Request the sync of the ObvSyncAtom to the engine
                Task { [weak self] in
                    await self?.requestPropagationToOtherOwnedDevicesOfAllOwnedIdentities(of: syncAtom)
                }
            }
            .store(in: &cancellables)
        
        ObvMessengerSettingsObservableObject.shared.$doSendReadReceipt
            .dropFirst() // Don't consider the initial value set on doSendReadReceipt
            .compactMap { (doSendReadReceipt: Bool, changeMadeFromAnotherOwnedDevice: Bool) in
                // Filter out changes made from another device since we don't need to sync with them
                guard !changeMadeFromAnotherOwnedDevice else { return nil }
                return doSendReadReceipt
            }
            .compactMap { (doSendReadReceipt: Bool) in
                // Create the ObvSyncAtom
                let syncAtom = ObvSyncAtom.settingDefaultSendReadReceipts(sendReadReceipt: doSendReadReceipt)
                return syncAtom
            }
            .sink { [weak self] (syncAtom: ObvSyncAtom) in
                // Request the sync of the ObvSyncAtom to the engine
                Task { [weak self] in
                    await self?.requestPropagationToOtherOwnedDevicesOfAllOwnedIdentities(of: syncAtom)
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


// MARK: - AppCoordinatorsQueue

final class AppCoordinatorsQueue: OperationQueue, @unchecked Sendable {
    
    fileprivate static let shared = AppCoordinatorsQueue()
    
    private override init() {
        super.init()
        self.maxConcurrentOperationCount = 1
        self.qualityOfService = .userInteractive
        self.name = "AppCoordinatorsQueue"
    }

    override func addOperation(_ op: Operation) {
        //op.printObvDisplayableLogsWhenFinished()
        //_ = logOperations(ops: [op])
        decrementNumberOfOperationsToExecuteWhenFinished(op: op)
        AppCoordinatorsQueueMonitor.shared.incrementOperationCount()
        super.addOperation(op)
    }

    
    override func addOperations(_ ops: [Operation], waitUntilFinished wait: Bool) {
//        ops.forEach { op in
//            op.printObvDisplayableLogsWhenFinished()
//        }
        //_ = logOperations(ops: ops)
        for op in ops {
            decrementNumberOfOperationsToExecuteWhenFinished(op: op)
        }
        AppCoordinatorsQueueMonitor.shared.incrementOperationCount(increment: ops.count)
        super.addOperations(ops, waitUntilFinished: wait)
    }
    
    
    private func decrementNumberOfOperationsToExecuteWhenFinished(op: Operation) {
        let completionBlock = op.completionBlock
        op.completionBlock = {
            completionBlock?()
            AppCoordinatorsQueueMonitor.shared.decrementOperationCount()
        }
    }
    
    
//    func logOperations(ops: [Operation]) -> String {
//        let queuedOperations = ops.map({ $0.debugDescription })
//        let currentOperations = self.operations
//        if !currentOperations.isEmpty {
//            let currentNotExecutingOperations = currentOperations.filter({ !$0.isExecuting })
//            let currentExecutingOperations = currentOperations.filter({ $0.isExecuting })
//            let currentNotExecutingOperationsAsString = currentNotExecutingOperations.map({ $0.debugDescription }).joined(separator: ", ")
//            let currentExecutingOperationsAsString = currentExecutingOperations.map({ $0.debugDescription }).joined(separator: ", ")
//            let stringToLog = "🍒⚠️ Queuing operation \(queuedOperations) but the queue (isSuspended=\(self.isSuspended)) is already executing the following \(currentExecutingOperations.count) operations: \(currentExecutingOperationsAsString). The following \(currentNotExecutingOperations.count) operations still need to be executed: \(currentNotExecutingOperationsAsString)"
//            ObvDisplayableLogs.shared.log(stringToLog)
//            return stringToLog
//        } else {
//            let stringToLog = "🍒✅ Queuing operation \(queuedOperations)"
//            ObvDisplayableLogs.shared.log(stringToLog)
//            return stringToLog
//        }
//    }
        
}


private extension Operation {
    
//    func printObvDisplayableLogsWhenFinished() {
//        if let completion = self.completionBlock {
//            self.completionBlock = {
//                ObvDisplayableLogs.shared.log("🐷 \(self.debugDescription) is finished")
//                completion()
//            }
//        } else {
//            self.completionBlock = {
//                ObvDisplayableLogs.shared.log("🐷 \(self.debugDescription) is finished")
//            }
//        }
//    }
    
}


// MARK: - Monitoring App's coordinators queue

/// This singleton provides a centralized way to monitor the load of the operation queue shared across all coordinators.
///
/// This class implements a single writer / multiple readers synchronization technique to monitor the coordinator's queue.
///
/// Each time an operation is added or removed from the coordinator's queue, the `operationCount` property of this monitor is updated. When the count reaches a predefined threshold, indicating a heavy load on the coordinator's queue, the monitor publishes a `progress`.
///
/// Once a `progress` is published, it is continuously refreshed until all the operations are finished. Upon completion, the `progress` is reset to nil.
///
/// In practice, the ``NewDiscussionsViewController`` observes this monitor to receive updates on the coordinator's queue load.
final class AppCoordinatorsQueueMonitor {
    
    static let shared = AppCoordinatorsQueueMonitor()
    private let queue = DispatchQueue(label: "AppCoordinatorsQueueMonitor.queue", attributes: .concurrent)
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "AppCoordinatorsQueueMonitor")

    private init() {}
    
    private var operationCount: Int = 0
    private var unitCountForProgress: (total: Int, completed: Int)?
    private static let operationCountThresholdForProgress: Int = 100
    private static let preventProgressFromGoingBackwards = false
    
    @Published var coordinatorsOperationsProgress: CoordinatorsOperationsProgress?
    private var lastProgressUpdate = Date.distantPast
    private static let timeIntervalThresholdForProgressFractionCompletedUpdate: TimeInterval = 0.3

    fileprivate func incrementOperationCount(increment: Int = 1) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            operationCount += increment
            updateUnitCountForProgress(operationCount: operationCount)
        }
    }

    fileprivate func decrementOperationCount(decrement: Int = 1) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            operationCount = max(0, operationCount - decrement)
            updateUnitCountForProgress(operationCount: operationCount)
        }
    }

    private func updateUnitCountForProgress(operationCount: Int) {
        queue.async { [weak self] in
            guard let self else { return }
                        
            guard unitCountForProgress != nil || operationCount > Self.operationCountThresholdForProgress else { return }

            let increment: Int
            if let unitCountForProgress {
                increment = operationCount - unitCountForProgress.total + unitCountForProgress.completed
            } else {
                increment = operationCount
            }

            if let unitCountForProgress {
                
                // We are monitoring a progress

                let newTotalUnitCount: Int
                let newCompletedUnitCount: Int

                if Self.preventProgressFromGoingBackwards {
                    
                    if increment < 0 {
                        // Some queued operations have finished
                        newTotalUnitCount = unitCountForProgress.total
                        newCompletedUnitCount = min(newTotalUnitCount, max(unitCountForProgress.completed, unitCountForProgress.total - operationCount))
                    } else if increment > 0 {
                        // Some new operations have been queued
                        guard unitCountForProgress.total > 0 else { assertionFailure(); return }
                        let fractionCompleted = Double(unitCountForProgress.completed) / Double(unitCountForProgress.total)
                        newCompletedUnitCount = min(operationCount, Int(ceil(fractionCompleted * Double(operationCount))))
                        newTotalUnitCount = operationCount
                    } else {
                        newTotalUnitCount = unitCountForProgress.total
                        newCompletedUnitCount = unitCountForProgress.completed
                    }

                } else {
                    
                    if increment < 0 {
                        // Some queued operations have finished
                        newTotalUnitCount = unitCountForProgress.total
                        newCompletedUnitCount = unitCountForProgress.completed + abs(increment)
                    } else if increment > 0 {
                        // Some new operations have been queued
                        newTotalUnitCount = unitCountForProgress.total + abs(increment)
                        newCompletedUnitCount = unitCountForProgress.completed
                    } else {
                        newTotalUnitCount = unitCountForProgress.total
                        newCompletedUnitCount = unitCountForProgress.completed
                    }
                                                            
                }
                                
                queue.async(flags: .barrier) { [weak self] in
                    guard let self else { return }
                    self.unitCountForProgress = (newTotalUnitCount, newCompletedUnitCount)
                    updateProgress(unitCountForProgress: (newTotalUnitCount, newCompletedUnitCount))
                }

                if newCompletedUnitCount >= newTotalUnitCount || operationCount == 0 {
                    queue.async(flags: .barrier) { [weak self] in
                        self?.unitCountForProgress = nil
                    }
                }

            } else {
                
                // We are not yet monitoring a progress
                
                if operationCount > 0 {
                    
                    queue.async(flags: .barrier) { [weak self] in
                        guard let self else { return }
                        self.unitCountForProgress = (operationCount, 0)
                        updateProgress(unitCountForProgress: (operationCount, 0))
                    }
                    
                }
                
            }

        }
    }
    
    
    private func updateProgress(unitCountForProgress: (total: Int, completed: Int)?) {
        
        // Update the published fraction completed if appropriate
        
        if let unitCountForProgress, unitCountForProgress.total > 0 {
            
            if unitCountForProgress.completed >= unitCountForProgress.total {
                
                self.lastProgressUpdate = Date.now
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    coordinatorsOperationsProgress?.setFractionCompleted(to: 1.0)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard coordinatorsOperationsProgress != nil else { return }
                    coordinatorsOperationsProgress = nil
                }
                
            } else {
                
                guard Date.now.timeIntervalSince(lastProgressUpdate) > Self.timeIntervalThresholdForProgressFractionCompletedUpdate else { return }
                let newFractionCompleted = Double(unitCountForProgress.completed) / Double(unitCountForProgress.total)
                self.lastProgressUpdate = Date.now
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if coordinatorsOperationsProgress == nil {
                        coordinatorsOperationsProgress = CoordinatorsOperationsProgress()
                    }
                    coordinatorsOperationsProgress?.setFractionCompleted(to: newFractionCompleted)
                }
                
            }
            
        } else {
            
            self.lastProgressUpdate = Date.now
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard coordinatorsOperationsProgress != nil else { return }
                coordinatorsOperationsProgress = nil
            }
            
        }

    }
    
    
    @MainActor
    final class CoordinatorsOperationsProgress: ObservableObject, Equatable, Hashable {
        
        private let uuid = UUID()
        
        @Published fileprivate(set) var fractionCompleted: Double = 0
        
        fileprivate func setFractionCompleted(to newFractionCompleted: Double) {
            guard self.fractionCompleted != newFractionCompleted else { return }
            self.fractionCompleted = newFractionCompleted
        }
        
        // Equatable and Hashable
        
        nonisolated static func == (lhs: CoordinatorsOperationsProgress, rhs: CoordinatorsOperationsProgress) -> Bool {
            lhs.uuid == rhs.uuid
        }
        
        nonisolated func hash(into hasher: inout Hasher) {
            hasher.combine(uuid)
        }
        
    }
    
}
