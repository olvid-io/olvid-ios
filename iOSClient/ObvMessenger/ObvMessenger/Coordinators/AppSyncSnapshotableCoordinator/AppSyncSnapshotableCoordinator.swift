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
import os.log
import ObvTypes
import CoreData
import ObvUICoreData
import ObvCrypto
import OlvidUtils



final class AppSyncSnapshotableCoordinator: ObvAppSnapshotable {
    
    private let obvEngine: ObvEngine
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: AppSyncSnapshotableCoordinator.self))
    private let coordinatorsQueue: OperationQueue
    private let queueForComposedOperations: OperationQueue

    init(obvEngine: ObvEngine, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue) {
        self.obvEngine = obvEngine
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        do {
            try obvEngine.registerAppSnapshotableObject(self)
        } catch {
            os_log("Could not register the app within the engine for performing App data backup", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }

    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {}

    
    // MARK: - ObvSnapshotable
    
    func getSyncSnapshotNode(for ownedCryptoId: ObvCryptoId) throws -> any ObvSyncSnapshotNode {
        return try ObvStack.shared.performBackgroundTaskAndWaitOrThrow { context in
            return try AppSyncSnapshotNode(ownedCryptoId: ownedCryptoId, within: context)
        }
    }

    
    /// Called by the protocol restoring a sync snapshot during an owned identity transfer protocol
    func syncEngineDatabaseThenUpdateAppDatabase(using syncSnapshotNode: any ObvSyncSnapshotNode) async throws {
        
        // If the sync fails, the rest cannot be perfomed
        do {
            try await syncAppDatabasesWithEngine()
        } catch {
            assertionFailure()
            throw error
        }
        
        var errorToThrowInTheEnd: Error?
        
        do {
            guard let appSyncSnapshotNode = syncSnapshotNode as? AppSyncSnapshotNode else {
                assertionFailure()
                throw ObvError.unexpectedSnapshotType
            }
            try await updateAppDatabase(using: appSyncSnapshotNode)
        } catch {
            assertionFailure()
            errorToThrowInTheEnd = error
        }
        
        await ObvPushNotificationManager.shared.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()
        
        if let errorToThrowInTheEnd {
            assertionFailure()
            throw errorToThrowInTheEnd
        }
        
    }
    
    
    func requestServerToKeepDeviceActive(ownedCryptoId: ObvCryptoId, deviceUidToKeepActive: UID) async throws {
        do {
            // We first make sure the current device is known to the server
            await ObvPushNotificationManager.shared.requestRegisterToPushNotificationsForAllActiveOwnedIdentities()
            // We then make an engine request allowing to keep the device active
            try await obvEngine.requestSettingUnexpiringDevice(ownedCryptoId: ownedCryptoId, deviceIdentifier: deviceUidToKeepActive.raw)
        } catch {
            assertionFailure()
            throw error
        }
    }
    
    
    private func syncAppDatabasesWithEngine() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ObvMessengerInternalNotification.requestSyncAppDatabasesWithEngine(queuePriority: .veryHigh) { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success:
                    continuation.resume()
                }
            }.postOnDispatchQueue()
        }
    }
    
    
    private func updateAppDatabase(using appSyncSnapshotNode: AppSyncSnapshotNode) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            
            let op1 = UpdateAppDatabaseWithAppSyncSnapshotNodeOperation(appSyncSnapshotNode: appSyncSnapshotNode)
            let composedOp = createCompositionOfOneContextualOperation(op1: op1)
            composedOp.queuePriority = .high
            
            composedOp.appendCompletionBlock {
                guard !op1.isCancelled else {
                    if let reasonForCancel = op1.reasonForCancel {
                        continuation.resume(throwing: reasonForCancel)
                        return
                    } else {
                        let error = ObvError.updateAppDatabaseFailedWithoutSpecifyingError
                        continuation.resume(throwing: error)
                        return
                    }
                }
                continuation.resume()
            }
            
            coordinatorsQueue.addOperation(composedOp)
        }
    }

    
    func serializeObvSyncSnapshotNode(_ syncSnapshotNode: any ObvSyncSnapshotNode) throws -> Data {
        guard let node = syncSnapshotNode as? AppSyncSnapshotNode else {
            assertionFailure()
            throw ObvError.unexpectedSnapshotType
        }
        let jsonEncoder = JSONEncoder()
        return try jsonEncoder.encode(node)
    }
    
    
    func deserializeObvSyncSnapshotNode(_ serializedSyncSnapshotNode: Data) throws -> any ObvSyncSnapshotNode {
        let jsonDecoder = JSONDecoder()
        return try jsonDecoder.decode(AppSyncSnapshotNode.self, from: serializedSyncSnapshotNode)
    }

    
    enum ObvError: Error {
        case unexpectedSnapshotType
        case updateAppDatabaseFailedWithoutSpecifyingError
    }
        
}


// MARK: - Helpers

extension AppSyncSnapshotableCoordinator {

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
