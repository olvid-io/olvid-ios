/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvAppCoreConstants



final class AppSyncSnapshotableCoordinator: OlvidCoordinator, ObvAppSnapshotable {
    
    let obvEngine: ObvEngine
    static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: AppSyncSnapshotableCoordinator.self))
    let coordinatorsQueue: OperationQueue
    let queueForComposedOperations: OperationQueue
    let queueForSyncHintsComputationOperation: OperationQueue

    init(obvEngine: ObvEngine, coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue, queueForSyncHintsComputationOperation: OperationQueue) {
        self.obvEngine = obvEngine
        self.coordinatorsQueue = coordinatorsQueue
        self.queueForComposedOperations = queueForComposedOperations
        self.queueForSyncHintsComputationOperation = queueForSyncHintsComputationOperation
        do {
            try obvEngine.registerAppSnapshotableObject(self)
        } catch {
            os_log("Could not register the app within the engine for performing App data backup", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }

    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {}

    
    // MARK: - ObvAppSnapshotable
    
    @MainActor
    func getAdditionalInfosFromAppForProfileBackup(ownedCryptoId: ObvCryptoId) async throws -> AdditionalInfosFromAppForProfileBackup {
        
        let platform: OlvidPlatform
        
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            platform = .iPhone
        case .pad:
            platform = .iPad
        case .mac:
            platform = .mac
        default:
            assertionFailure()
            platform = .iPhone
        }
        
        return .init(platform: platform)
        
    }
    

    func getSyncSnapshotNode(for context: ObvSyncSnapshot.Context) throws -> any ObvSyncSnapshotNode {
        switch context {
        case .transfer(let ownedCryptoId):
            // We return the exact same snapshot node than in the "backupProfile" case
            return try ObvStack.shared.performBackgroundTaskAndWaitOrThrow { context in
                return try AppSyncSnapshotNode(ownedCryptoId: ownedCryptoId, within: context)
            }
        case .backupDevice:
            return try ObvStack.shared.performBackgroundTaskAndWaitOrThrow { context in
                return try AppDeviceSnapshotNode(within: context)
            }
        case .backupProfile(let ownedCryptoId):
            // We return the exact same snapshot node than in the "transfer" case
            return try ObvStack.shared.performBackgroundTaskAndWaitOrThrow { context in
                return try AppSyncSnapshotNode(ownedCryptoId: ownedCryptoId, within: context)
            }
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
            ObvMessengerInternalNotification.requestSyncAppDatabasesWithEngine(queuePriority: .veryHigh, isRestoringSyncSnapshotOrBackup: true) { result in
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
        let jsonEncoder = JSONEncoder()
        switch syncSnapshotNode {
        case is AppSyncSnapshotNode:
            return try jsonEncoder.encode(syncSnapshotNode)
        case is AppDeviceSnapshotNode:
            return try jsonEncoder.encode(syncSnapshotNode)
        default:
            assertionFailure()
            throw ObvError.unexpectedSnapshotType
        }
    }
    
    
    func deserializeObvSyncSnapshotNode(_ serializedSyncSnapshotNode: Data, context: ObvSyncSnapshot.Context) throws -> any ObvSyncSnapshotNode {
        let jsonDecoder = JSONDecoder()
        switch context {
        case .transfer, .backupProfile:
            return try jsonDecoder.decode(AppSyncSnapshotNode.self, from: serializedSyncSnapshotNode)
        case .backupDevice:
            return try jsonDecoder.decode(AppDeviceSnapshotNode.self, from: serializedSyncSnapshotNode)
        }
    }

    
    enum ObvError: Error {
        case unexpectedSnapshotType
        case updateAppDatabaseFailedWithoutSpecifyingError
    }
        
}
