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


/// This operation computes the required sync tasks to be performed at the app level, given the data available at the engine level. It  does so for owned identities.
/// This operation does *not* update the app database, it only evaluates what should be done to be in sync.
///
/// This operation is expected to be executed on a queue that is *not* synchronized with app database updates. We do so for efficiency reasons.
/// The actual work of updating the app database is done, in practice, by executing the ``SyncPersistedObvOwnedIdentitiesWithEngineOperation`` on the appropriate queue.
final class ComputeHintsAboutRequiredOwnedIdentitiesSyncWithEngineOperation: AsyncOperationWithSpecificReasonForCancel<ComputeHintsAboutRequiredOwnedIdentitiesSyncWithEngineOperation.ReasonForCancel> {
    
    private let obvEngine: ObvEngine
    private let contextForAppQueries: NSManagedObjectContext

    init(obvEngine: ObvEngine, contextForAppQueries: NSManagedObjectContext) {
        self.obvEngine = obvEngine
        self.contextForAppQueries = contextForAppQueries
        super.init()
    }
    
    private(set) var missingCryptoIds = Set<ObvCryptoId>()
    private(set) var cryptoIdsToDelete = Set<ObvCryptoId>()
    private(set) var cryptoIdsToUpdate = Set<ObvCryptoId>()
        
    override func main() async {
        
        do {
            
            // Get all owned identities within the engine
            
            let obvOwnedIdentitiesWithinEngine = try obvEngine.getOwnedIdentities()
            let cryptoIdsWithinEngine = Set(obvOwnedIdentitiesWithinEngine.map { $0.cryptoId })
            
            // Get the owned identities within the app
            
            let cryptoIdsWithinApp = try await getAllOwnedCryptoIdWithinApp()
            
            // Determine the owned identities to create, delete, or that might need to be updated
            
            self.missingCryptoIds = cryptoIdsWithinEngine.subtracting(cryptoIdsWithinApp)
            self.cryptoIdsToDelete = cryptoIdsWithinApp.subtracting(cryptoIdsWithinEngine)
            let cryptoIdsThatMightNeedToBeUpdated = cryptoIdsWithinApp.subtracting(cryptoIdsToDelete)
            
            // Among the owned identities that might need to be updated, determine the ones that indeed need to be updated by simulating the update
            
            for ownedCryptoId in cryptoIdsThatMightNeedToBeUpdated {
                
                guard let ownedIdentityWithinEngine = obvOwnedIdentitiesWithinEngine.filter({ $0.cryptoId == ownedCryptoId }).first else {
                    assertionFailure()
                    continue
                }
                
                guard let ownedCapabilitiesWithinEngine = try obvEngine.getCapabilitiesOfOwnedIdentity(ownedCryptoId) else {
                    assertionFailure()
                    continue
                }
                
                if try await ownedIdentityWithinAppWouldBeUpdated(with: ownedIdentityWithinEngine, orWith: ownedCapabilitiesWithinEngine) {
                    self.cryptoIdsToUpdate.insert(ownedCryptoId)
                }
                                
            }
            
            return finish()
            
        } catch {
            assertionFailure()
            return cancel(withReason: .error(error: error))
        }
        
    }
    

    private func ownedIdentityWithinAppWouldBeUpdated(with ownedIdentityWithinEngine: ObvOwnedIdentity, orWith capabilitiesWithinEngine: Set<ObvCapability>) async throws -> Bool {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            context.perform {
                do {
                    guard let ownedIdentityWithinApp = try PersistedObvOwnedIdentity.get(persisted: ownedIdentityWithinEngine, within: context) else {
                        assertionFailure()
                        return continuation.resume(returning: false)
                    }
                    try ownedIdentityWithinApp.update(with: ownedIdentityWithinEngine)
                    ownedIdentityWithinApp.setOwnedCapabilities(to: capabilitiesWithinEngine)
                    let returnedValue = !ownedIdentityWithinApp.changedValues().isEmpty
                    return continuation.resume(returning: returnedValue)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
    private func getAllOwnedCryptoIdWithinApp() async throws -> Set<ObvCryptoId> {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvCryptoId>, Error>) in
            context.perform {
                do {
                    let ownedCryptoIdsWithinApp = try PersistedObvOwnedIdentity.getAll(within: context)
                        .map(\.cryptoId)
                    return continuation.resume(returning: Set(ownedCryptoIdsWithinApp))
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
