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
import CoreData
import os.log
import OlvidUtils
import ObvEngine
import ObvTypes
import ObvUICoreData


/// This operation computes the required sync tasks to be performed at the app level, given the data available at the engine level. It  does so for groups v2.
/// This operation does *not* update the app database, it only evaluates what should be done to be in sync.
///
/// This operation is expected to be executed on a queue that is *not* synchronized with app database updates. We do so for efficiency reasons.
/// The actual work of updating the app database is done, in practice, by executing the ``SyncPersistedContactGroupV2WithEngineOperation`` on the appropriate queue.
final class ComputeHintsAboutRequiredContactGroupsV2SyncWithEngineOperation: AsyncOperationWithSpecificReasonForCancel<ComputeHintsAboutRequiredOwnedDevicesSyncWithEngineOperation.ReasonForCancel> {
    
    private let obvEngine: ObvEngine
    private let scope: Scope
    private let contextForAppQueries: NSManagedObjectContext

    enum Scope {
        case allGroupsV1
        case restrictToOwnedCryptoId(ownedCryptoId: ObvCryptoId)
    }

    init(obvEngine: ObvEngine, scope: Scope, contextForAppQueries: NSManagedObjectContext) {
        self.obvEngine = obvEngine
        self.scope = scope
        self.contextForAppQueries = contextForAppQueries
        super.init()
    }
    
    private(set) var missingGroups = Set<ObvGroupV2Identifier>()
    private(set) var groupsToDelete = Set<ObvGroupV2Identifier>()
    private(set) var groupsToUpdate = Set<ObvGroupV2Identifier>()
        
    override func main() async {
        
        do {
            
            let ownedCryptoIds: Set<ObvCryptoId>
            switch scope {
            case .allGroupsV1:
                ownedCryptoIds = try await getAllOwnedCryptoIdWithinApp()
            case .restrictToOwnedCryptoId(ownedCryptoId: let ownedCryptoId):
                ownedCryptoIds = Set([ownedCryptoId])
            }

            for ownedCryptoId in ownedCryptoIds {
                
                // Get all contact groups within the engine
                
                let obvContactGroupsV2WithinEngine = try obvEngine.getAllObvGroupV2OfOwnedIdentity(with: ownedCryptoId)
                let contactGroupV2IdentifiersWithinEngine = Set(obvContactGroupsV2WithinEngine.map(\.obvGroupIdentifier))
                
                // Get the contact group identifiers within the app
                
                let contactGroupV2IdentifiersWithinApp = try await getAllContactGroupV2IdentifiersWithinApp(ownedCryptoId: ownedCryptoId)
                
                // Determine the owned devices to create, delete, or that might need to be updated
                
                let missingContactGroups = contactGroupV2IdentifiersWithinEngine.subtracting(contactGroupV2IdentifiersWithinApp)
                let contactGroupsToDelete = contactGroupV2IdentifiersWithinApp.subtracting(contactGroupV2IdentifiersWithinEngine)
                let groupsThatMightNeedToBeUpdated = contactGroupV2IdentifiersWithinApp.subtracting(contactGroupsToDelete)

                // Among the devices that might need to be updated, determine the ones that indeed need to be updated by simulating the update

                for group in groupsThatMightNeedToBeUpdated {
                    
                    guard let groupWithinEngine = obvContactGroupsV2WithinEngine.filter({ $0.obvGroupIdentifier == group }).first else {
                        assertionFailure()
                        continue
                    }

                    if try await contactGroupWithinAppWouldBeUpdated(with: groupWithinEngine) {
                        self.groupsToUpdate.insert(group)
                    }

                }
                
                self.missingGroups.formUnion(missingContactGroups)
                self.groupsToDelete.formUnion(contactGroupsToDelete)
                
            }
            
            return finish()
            
        } catch {
            assertionFailure()
            return cancel(withReason: .error(error: error))
        }
        
    }
    
    
    private func getAllOwnedCryptoIdWithinApp() async throws -> Set<ObvCryptoId> {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvCryptoId>, Error>) in
            context.perform {
                do {
                    let ownedCryptoIds = try PersistedObvOwnedIdentity.getAll(within: context)
                        .map(\.cryptoId)
                    return continuation.resume(returning: Set(ownedCryptoIds))
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

    
    private func getAllContactGroupV2IdentifiersWithinApp(ownedCryptoId: ObvCryptoId) async throws -> Set<ObvGroupV2Identifier> {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvGroupV2Identifier>, Error>) in
            context.perform {
                do {
                    let groupsWithinApp = try PersistedGroupV2.getAllGroupV2Identifiers(ownedCryptoId: ownedCryptoId, within: context)
                    return continuation.resume(returning: Set(groupsWithinApp))
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }


    private func contactGroupWithinAppWouldBeUpdated(with groupWithinEngine: ObvGroupV2) async throws -> Bool {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            context.perform {
                do {
                    guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: groupWithinEngine.ownIdentity, within: context) else {
                        assertionFailure()
                        return continuation.resume(returning: false)
                    }
                    _ = try persistedOwnedIdentity.createOrUpdateGroupV2(obvGroupV2: groupWithinEngine, createdByMe: false, isRestoringSyncSnapshotOrBackup: false)
                    return continuation.resume(returning: context.hasChanges)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    public enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case error(error: Error)

        public var logType: OSLogType {
            switch self {
            case .error:
                return .fault
            }
        }

        public var errorDescription: String? {
            switch self {
            case .error(error: let error):
                return "error: \(error.localizedDescription)"
            }
        }

    }

}
