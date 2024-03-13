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


/// This operation computes the required sync tasks to be performed at the app level, given the data available at the engine level. It  does so for contact groups (i.e., groups v1).
/// This operation does *not* update the app database, it only evaluates what should be done to be in sync.
///
/// This operation is expected to be executed on a queue that is *not* synchronized with app database updates. We do so for efficiency reasons.
/// The actual work of updating the app database is done, in practice, by executing the ``SyncPersistedContactGroupWithEngineOperation`` on the appropriate queue.
final class ComputeHintsAboutRequiredContactGroupsSyncWithEngineOperation: AsyncOperationWithSpecificReasonForCancel<ComputeHintsAboutRequiredOwnedDevicesSyncWithEngineOperation.ReasonForCancel> {
    
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
    
    private(set) var missingContactGroups = Set<ObvGroupV1Identifier>()
    private(set) var contactGroupsToDelete = Set<ObvGroupV1Identifier>()
    private(set) var contactGroupsToUpdate = Set<ObvGroupV1Identifier>()
        
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
                
                let obvContactGroupsWithinEngine = try obvEngine.getAllContactGroupsForOwnedIdentity(with: ownedCryptoId)
                let contactGroupIdentifiersWithinEngine = Set(obvContactGroupsWithinEngine.map(\.obvGroupIdentifier))
                
                // Get the contact group identifiers within the app
                
                let contactGroupIdentifiersWithinApp = try await getAllContactGroupIdentifiersWithinApp(ownedCryptoId: ownedCryptoId)
                
                // Determine the owned devices to create, delete, or that might need to be updated
                
                let missingContactGroups = contactGroupIdentifiersWithinEngine.subtracting(contactGroupIdentifiersWithinApp)
                let contactGroupsToDelete = contactGroupIdentifiersWithinApp.subtracting(contactGroupIdentifiersWithinEngine)
                let groupsThatMightNeedToBeUpdated = contactGroupIdentifiersWithinApp.subtracting(contactGroupsToDelete)

                // Among the devices that might need to be updated, determine the ones that indeed need to be updated by simulating the update

                for group in groupsThatMightNeedToBeUpdated {
                    
                    guard let groupWithinEngine = obvContactGroupsWithinEngine.filter({ $0.obvGroupIdentifier == group }).first else {
                        assertionFailure()
                        continue
                    }

                    if try await contactGroupWithinAppWouldBeUpdated(with: groupWithinEngine) {
                        self.contactGroupsToUpdate.insert(group)
                    }

                }
                
                self.missingContactGroups.formUnion(missingContactGroups)
                self.contactGroupsToDelete.formUnion(contactGroupsToDelete)
                
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

    
    private func getAllContactGroupIdentifiersWithinApp(ownedCryptoId: ObvCryptoId) async throws -> Set<ObvGroupV1Identifier> {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvGroupV1Identifier>, Error>) in
            context.perform {
                do {
                    let groupsWithinApp = try PersistedContactGroup.getAllContactGroupIdentifiers(ownedCryptoId: ownedCryptoId, within: context)
                        .map({ ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: $0) })
                    return continuation.resume(returning: Set(groupsWithinApp))
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }


    private func contactGroupWithinAppWouldBeUpdated(with contactGroupWithinEngine: ObvContactGroup) async throws -> Bool {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            context.perform {
                do {
                    guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: contactGroupWithinEngine.ownedIdentity.cryptoId, within: context) else {
                        assertionFailure()
                        return continuation.resume(returning: false)
                    }
                    let groupHasUpdates = try persistedOwnedIdentity.updateContactGroup(with: contactGroupWithinEngine)
                    return continuation.resume(returning: groupHasUpdates)
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
