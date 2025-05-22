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
import OSLog
import OlvidUtils
import ObvCoreDataStack
import ObvCrypto
import ObvTypes


final class BackupManagerDatabaseCoordinator {
    
    private static let logger = Logger(subsystem: "io.olvid.BackupManagerCoordinator", category: "BackupManagerCoordinator")
    private static let log = OSLog(subsystem: "io.olvid.BackupManagerCoordinator", category: "BackupManagerCoordinator")

    /// This is set in the `finalizeInitialization(flowId:runningLog:)` method
    private var coreDataStack: CoreDataStack<ObvBackupManagerNewPersistentContainer>
    
    private static let qualityOfService: QualityOfService = .default
    private let queueForPerformingComposedOperations = OperationQueue.createSerialQueue(name: "Queue contextual operations of ObvBackupManagerNew", qualityOfService: qualityOfService)
    private let queueWithinComposedOperations = {
        let queue = OperationQueue()
        queue.name = "ObvBackupManagerNew Queue within composed operations"
        queue.qualityOfService = qualityOfService
        return queue
    }()
    
    private let physicalDeviceName: String
    private let prng: PRNGService

    init(physicalDeviceName: String, prng: PRNGService, transactionAuthor: String, enableMigrations: Bool, runningLog: RunningLogError) throws {

        self.physicalDeviceName = physicalDeviceName
        self.prng = prng

        let manager = DataMigrationManagerForObvBackupManagerNew(modelName: "ObvBackupManagerModel",
                                                                 storeName: "ObvBackupManagerModel",
                                                                 transactionAuthor: transactionAuthor,
                                                                 enableMigrations: enableMigrations,
                                                                 migrationRunningLog: runningLog)
        try manager.initializeCoreDataStack()
        let newCoreDataStack = manager.coreDataStack
        self.coreDataStack = newCoreDataStack

    }
    
}


// MARK: - Database methods

extension BackupManagerDatabaseCoordinator {
    
    func createDeviceBackupSeed(serverURLForStoringDeviceBackup: URL, flowId: FlowIdentifier) async throws(ObvBackupManagerError.CreateDeviceBackupSeed) -> PersistedDeviceBackupSeedStruct {
        
        let op1 = CreateNewPersistedDeviceBackupSeedOperation(serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup, physicalDeviceName: self.physicalDeviceName, prng: prng)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)
        
        guard composedOp.isFinished && !composedOp.isCancelled, let createdBackupSeed = op1.createdBackupSeed else {
            Self.logger.fault("CreateNewPersistedDeviceBackupSeedOperation failed \(op1.reasonForCancel)")
            guard let reasonForCancel = composedOp.reasonForCancel else {
                assertionFailure()
                throw .unknownError
            }
            switch reasonForCancel {
            case .unknownReason:
                assertionFailure()
                throw .unknownError
            case .coreDataError(error: let error):
                throw .coreDataError(error: error)
            case .op1Cancelled(reason: let reason):
                switch reason {
                case .coreDataError(error: let error):
                    if let obvError = error as? PersistedDeviceBackupSeed.ObvError {
                        switch obvError {
                        case .anActivePersistedDeviceBackupSeedAlreadyExists:
                            throw .anActivePersistedDeviceBackupSeedAlreadyExists
                        case .coreDataError(let error):
                            throw .coreDataError(error: error)
                        case .couldNotParseBackupSeed:
                            throw .coreDataError(error: obvError)
                        case .contextIsNil:
                            throw .coreDataError(error: obvError)
                        case .noActiveDeviceBackupSeed:
                            throw .coreDataError(error: obvError)
                        case .couldNotParseSecAttrAccount:
                            throw .coreDataError(error: obvError)
                        case .couldNotParseServerURL:
                            throw .coreDataError(error: obvError)
                        }
                    } else {
                        assertionFailure()
                        throw .otherError(error: error)
                    }
                }
            case .op1HasUnfinishedDependency:
                assertionFailure()
                throw .unknownError
            }
        }

        return createdBackupSeed
        
    }
    
    
    func deletePersistedDeviceBackupSeed(backupSeed: BackupSeed, flowId: FlowIdentifier) async throws(ObvBackupManagerError.DeletePersistedDeviceBackupSeed) {
        
        let op1 = DeletePersistedDeviceBackupSeedOperation(backupSeed: backupSeed)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)
        
        guard composedOp.isFinished && !composedOp.isCancelled && !op1.isCancelled else {
            Self.logger.fault("CreateNewPersistedDeviceBackupSeedOperation failed \(op1.reasonForCancel)")
            guard let reasonForCancel = composedOp.reasonForCancel else {
                assertionFailure()
                throw .unknownError
            }
            switch reasonForCancel {
            case .unknownReason:
                assertionFailure()
                throw .unknownError
            case .coreDataError(error: let error):
                throw .coreDataError(error: error)
            case .op1Cancelled(reason: let reason):
                switch reason {
                case .coreDataError(error: let error):
                    throw .coreDataError(error: error)
                }
            case .op1HasUnfinishedDependency(op1: _):
                assertionFailure()
                throw .unknownError
            }
        }
        
    }
    
    
    /// Returns the physical device backup seed and serverURL corresponding to the given `BackupSeed`. It does not matter whether the seed is active or not.
    func getDeviceBackupSeedAndServerURL(backupSeed: BackupSeed, flowId: FlowIdentifier) async throws -> ObvBackupSeedAndStorageServerURL? {
        
        let op1 = GetDeviceBackupSeedAndServerOperation(backupSeed: backupSeed)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }
        
        return op1.deviceBackupSeedAndServer
        
    }
    
    
    /// Returns the current (active) physical device backup seed, if there is one
    func getActiveDeviceBackupSeedStruct(flowId: FlowIdentifier) async throws(ObvBackupManagerError.GetDeviceActiveBackupSeedAndServerURL) -> PersistedDeviceBackupSeedStruct? {
        
        let op1 = GetActiveDeviceBackupSeedStructOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)
        
        guard composedOp.isFinished && !composedOp.isCancelled && !op1.isCancelled else {
            guard let reasonForCancel = composedOp.reasonForCancel else {
                assertionFailure()
                throw .unknownError
            }
            switch reasonForCancel {
            case .unknownReason:
                assertionFailure()
                throw .unknownError
            case .coreDataError(error: let error):
                throw .coreDataError(error: error)
            case .op1Cancelled(reason: let reason):
                switch reason {
                case .coreDataError(error: let error):
                    if let obvError = error as? PersistedDeviceBackupSeed.GetError {
                        switch obvError {
                        case .couldNotParseBackupSeed:
                            throw .couldNotParseBackupSeed
                        case .couldNotParseServerURL:
                            throw .couldNotParseServerURL
                        case .coreDataError(let error):
                            throw .coreDataError(error: error)
                        case .couldNotParseSecAttrAccount:
                            throw .coreDataError(error: error)
                        }
                    } else {
                        assertionFailure()
                        throw .otherError(error: error)
                    }
                }
            case .op1HasUnfinishedDependency(op1: _):
                assertionFailure()
                throw .unknownError
            }
        }
        
        return op1.activeDeviceBackupSeedStruct
        
    }
    
    
//    func getOrCreateKeychainSecAttrAccountForThisPhysicalDevice(flowId: FlowIdentifier) async throws(ObvBackupManagerError.GetKeychainSecAttrAccount) -> String {
//        
//        let op1 = GetOrCreateKeychainSecAttrAccountForThisPhysicalDeviceOperation(physicalDeviceName: physicalDeviceName)
//        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
//        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)
//
//        guard composedOp.isFinished && !composedOp.isCancelled && !op1.isCancelled, let secAttrAccount = op1.secAttrAccount else {
//            guard let reasonForCancel = composedOp.reasonForCancel else {
//                assertionFailure()
//                throw .unknownError
//            }
//            switch reasonForCancel {
//            case .unknownReason:
//                assertionFailure()
//                throw .unknownError
//            case .coreDataError(error: let error):
//                throw .coreDataError(error: error)
//            case .op1Cancelled(reason: let reason):
//                switch reason {
//                case .coreDataError(error: let error):
//                    throw .coreDataError(error: error)
//                }
//            case .op1HasUnfinishedDependency(op1: _):
//                assertionFailure()
//                throw .unknownError
//            }
//        }
//
//        return secAttrAccount
//        
//    }
    
    
    func deactivateAllPersistedDeviceBackupSeeds(flowId: FlowIdentifier) async throws(ObvBackupManagerError.DeactivateAllPersistedDeviceBackupSeeds) {
        
        let op1 = DeactivateAllPersistedDeviceBackupSeedsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)
        
        guard composedOp.isFinished && !composedOp.isCancelled && !op1.isCancelled else {
            guard let reasonForCancel = composedOp.reasonForCancel else {
                assertionFailure()
                throw .unknownError
            }
            switch reasonForCancel {
            case .unknownReason:
                assertionFailure()
                throw .unknownError
            case .coreDataError(error: let error):
                throw .coreDataError(error: error)
            case .op1Cancelled(reason: let reason):
                switch reason {
                case .coreDataError(error: let error):
                    throw .coreDataError(error: error)
                }
            case .op1HasUnfinishedDependency(op1: _):
                assertionFailure()
                throw .unknownError
            }
        }

    }
    
    
    func getOrCreateProfileBackupThreadUIDForOwnedCryptoId(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws(ObvBackupManagerError.GetOrCreateProfileBackupThreadUIDForOwnedCryptoId) -> UID {

        let op1 = GetOrCreateProfileBackupThreadUIDForOwnedCryptoIdOperation(ownedCryptoId: ownedCryptoId, prng: prng)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)
        
        guard composedOp.isFinished && !composedOp.isCancelled && !op1.isCancelled else {
            assertionFailure()
            guard let reasonForCancel = composedOp.reasonForCancel else {
                assertionFailure()
                throw .unknownError
            }
            switch reasonForCancel {
            case .coreDataError(error: let error):
                assertionFailure()
                throw .coreDataError(error: error)
            case .unknownReason:
                assertionFailure()
                throw .unknownError
            case .op1Cancelled(reason: let reason):
                switch reason {
                case .coreDataError(error: let error):
                    throw .coreDataError(error: error)
                }
            case .op1HasUnfinishedDependency:
                assertionFailure()
                throw .unknownError
            }
        }
        
        guard let profileBackupThreadUID = op1.profileBackupThreadUID else {
            assertionFailure()
            throw .unknownError
        }
        
        return profileBackupThreadUID
        
    }

    
    func getAllProfileBackupThreadIds(flowId: FlowIdentifier) async throws -> [(ownedCryptoId: ObvCryptoId, profileBackupThreadUID: UID)] {
        
        let op1 = GetAllProfileBackupThreadIdOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }
        
        return op1.allProfileBackupThreadIds
        
    }
    
    
    func getAllInactiveDeviceBackupSeeds(flowId: FlowIdentifier) async throws -> [PersistedDeviceBackupSeedStruct] {
        
        let op1 = GetAllInactiveDeviceBackupSeedsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }
        
        return op1.allInactiveDeviceBackupSeeds

    }
    
    
    func deletePersistedProfileBackupThreadId(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws {
        
        let op1 = DeletePersistedProfileBackupThreadIdOperation(ownedCryptoId: ownedCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }
        
    }
    
    
    func deleteAllInactiveDeviceBackupSeeds(flowId: FlowIdentifier) async throws {
        
        let op1 = DeleteAllInactiveDeviceBackupSeedsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }

    }
    
    
    func determineIfFetchedBackupWasMadeByThisDevice(ownedCryptoId: ObvCryptoId, threadUID: UID, flowId: FlowIdentifier) async throws -> Bool {
        
        let op1 = DetermineIfFetchedBackupWasMadeByThisDeviceOperation(ownedCryptoId: ownedCryptoId, threadUID: threadUID)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }

        return op1.backupMadeByThisDevice
        
    }
    
    
    // MARK: For scheduling device backups
    
    func setNextDeviceBackupUUID(flowId: FlowIdentifier) async throws {

        let op1 = SetNextDeviceBackupUUIDOperation(uuid: flowId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }
        
    }
    
    
    func getNextDeviceBackupUUID(flowId: FlowIdentifier) async throws -> UUID? {
        
        let op1 = GetNextDeviceBackupUUIDOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }

        return op1.uuid
        
    }
    
    
    func removeNextDeviceBackupUUID(flowIdToRemove: FlowIdentifier) async throws {
        
        let op1 = RemoveNextDeviceBackupUUIDOperation(uuidToRemove: flowIdToRemove)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowIdToRemove)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }

    }

    
    // MARK: For scheduling profile backups
    
    func setNextProfileBackupUUID(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws {

        let op1 = SetNextProfileBackupUUIDOperation(uuid: flowId, ownedCryptoId: ownedCryptoId, prng: prng)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }
        
    }
    
    
    func getNextProfileBackupUUIDs(flowId: FlowIdentifier) async throws -> [ObvCryptoId: UUID] {
        
        let op1 = GetNextProfileBackupUUIDsOperation()
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }

        return op1.uuidForOwnedCryptoId
        
    }
    
    
    func removeNextProfileBackupUUID(ownedCryptoId: ObvCryptoId, flowIdToRemove: FlowIdentifier) async throws {
        
        let op1 = RemoveNextProfileBackupUUIDOperation(uuidToRemove: flowIdToRemove, ownedCryptoId: ownedCryptoId)
        let composedOp = createCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowIdToRemove)
        await queueForPerformingComposedOperations.addAndAwaitOperation(composedOp)

        guard composedOp.isFinished && !composedOp.isCancelled else {
            if let reasonForCancel = op1.reasonForCancel {
                throw reasonForCancel
            } else if let reasonForCancel = composedOp.reasonForCancel {
                throw reasonForCancel
            } else {
                throw ObvError.unknownError
            }
        }

    }
    
}


// MARK: - Errors

// MARK: - Helpers for contextual operations

extension BackupManagerDatabaseCoordinator {
    
    func createCompositionOfOneContextualOperation<T: LocalizedErrorWithLogType>(op1: ContextualOperationWithSpecificReasonForCancel<T>, log: OSLog, flowId: FlowIdentifier) -> CompositionOfOneContextualOperation<T> {
        
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: coreDataStack, queueForComposedOperations: queueWithinComposedOperations, log: log, flowId: flowId)
        
        composedOp.completionBlock = { [weak composedOp] in
            assert(composedOp != nil)
            composedOp?.logReasonIfCancelled(log: log)
        }
        return composedOp
        
    }
    
}
