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


/// This operation computes the required sync tasks to be performed at the app level, given the data available at the engine level. It  does so for contact identities.
/// This operation does *not* update the app database, it only evaluates what should be done to be in sync.
///
/// This operation is expected to be executed on a queue that is *not* synchronized with app database updates. We do so for efficiency reasons.
/// The actual work of updating the app database is done, in practice, by executing the ``SyncPersistedObvContactIdentityWithEngineOperation`` on the appropriate queue.
final class ComputeHintsAboutRequiredContactIdentitiesSyncWithEngineOperation: AsyncOperationWithSpecificReasonForCancel<ComputeHintsAboutRequiredContactIdentitiesSyncWithEngineOperation.ReasonForCancel> {
    
    private let obvEngine: ObvEngine
    private let scope: Scope
    private let contextForAppQueries: NSManagedObjectContext

    enum Scope {
        case allContacts
        case restrictToOwnedCryptoId(ownedCryptoId: ObvCryptoId)
        case specificContact(contactIdentifier: ObvContactIdentifier)
    }

    init(obvEngine: ObvEngine, scope: Scope, contextForAppQueries: NSManagedObjectContext) {
        self.obvEngine = obvEngine
        self.scope = scope
        self.contextForAppQueries = contextForAppQueries
        super.init()
    }
    
    private(set) var missingContacts = Set<ObvContactIdentifier>()
    private(set) var contactsToDelete = Set<ObvContactIdentifier>()
    private(set) var contactsToUpdate = Set<ObvContactIdentifier>()
        
    override func main() async {
        
        do {
            
            let ownedCryptoIds: Set<ObvCryptoId>
            switch scope {
            case .allContacts:
                ownedCryptoIds = try await getAllOwnedCryptoIdWithinApp()
            case .restrictToOwnedCryptoId(ownedCryptoId: let ownedCryptoId):
                ownedCryptoIds = Set([ownedCryptoId])
            case .specificContact(contactIdentifier: let contactIdentifier):
                ownedCryptoIds = Set([contactIdentifier.ownedCryptoId])
            }
            
            
            for ownedCryptoId in ownedCryptoIds {
                
                // Get all contacts within the engine as well as their capabilities (or restrict to the specified contact, depending on the scope)
                
                let obvContactIdentitiesWithinEngine: Set<ObvContactIdentity>
                switch scope {
                case .allContacts, .restrictToOwnedCryptoId:
                    obvContactIdentitiesWithinEngine = try obvEngine.getContactsOfOwnedIdentity(with: ownedCryptoId)
                case .specificContact(contactIdentifier: let contactIdentifier):
                    guard let obvContactIdentity = try obvEngine.getContactIdentity(with: contactIdentifier.contactCryptoId, ofOwnedIdentityWith: contactIdentifier.ownedCryptoId) else {
                        // If the contact cannot be found we consider it must be deleted from the app
                        self.contactsToDelete.insert(contactIdentifier)
                        return finish()
                    }
                    obvContactIdentitiesWithinEngine = Set([obvContactIdentity])
                }
                let contactIdentifiersWithinEngine = Set(obvContactIdentitiesWithinEngine.map(\.contactIdentifier))
                let allCapabilitiesWithinEngine = try obvEngine.getCapabilitiesOfAllContactsOfOwnedIdentity(ownedCryptoId)

                // Get the contact identifiers within the app

                let contactIdentifiersWithinApp: Set<ObvContactIdentifier>
                switch scope {
                case .allContacts, .restrictToOwnedCryptoId:
                    contactIdentifiersWithinApp = try await getAllContactIdentifiersWithinApp(ownedCryptoId: ownedCryptoId)
                case .specificContact(let contactIdentifier):
                    contactIdentifiersWithinApp = try await getAllContactIdentifiersWithinApp(ownedCryptoId: ownedCryptoId)
                        .filter({ $0 == contactIdentifier })
                }

                // Determine the owned devices to create, delete, or that might need to be updated
                
                let missingContacts = contactIdentifiersWithinEngine.subtracting(contactIdentifiersWithinApp)
                let contactsToDelete = contactIdentifiersWithinApp.subtracting(contactIdentifiersWithinEngine)
                let contactsThatMightNeedToBeUpdated = contactIdentifiersWithinApp.subtracting(contactsToDelete)

                // Among the contacts that might need to be updated, determine the ones that indeed need to be updated by simulating the update

                for contact in contactsThatMightNeedToBeUpdated {
                    
                    guard let obvContactIdentityWithinEngine = obvContactIdentitiesWithinEngine.filter({ $0.contactIdentifier == contact }).first else {
                        assertionFailure()
                        continue
                    }
                    
                    guard let capabilitiesWithinEngine = allCapabilitiesWithinEngine[contact.contactCryptoId] else {
                        // Capabilities might not be available yet for that contact (e.g., after a transfer)
                        continue
                    }

                    if try await contactWithinAppWouldBeUpdated(with: obvContactIdentityWithinEngine, orWith: capabilitiesWithinEngine) {
                        self.contactsToUpdate.insert(contact)
                    }

                }
                
                self.missingContacts.formUnion(missingContacts)
                self.contactsToDelete.formUnion(contactsToDelete)
                                
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
    
    
    
    private func getAllContactIdentifiersWithinApp(ownedCryptoId: ObvCryptoId) async throws -> Set<ObvContactIdentifier> {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvContactIdentifier>, Error>) in
            context.perform {
                do {
                    let contactIdentifiers = try PersistedObvContactIdentity.getAllContactIdentifiersOfContactsOfOwnedIdentity(with: ownedCryptoId, within: context)
                    return continuation.resume(returning: contactIdentifiers)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }


    private func contactWithinAppWouldBeUpdated(with obvContactIdentityWithinEngine: ObvContactIdentity, orWith capabilitiesWithinEngine: Set<ObvCapability>) async throws -> Bool {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            context.perform {
                do {
                    guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: obvContactIdentityWithinEngine.ownedIdentity.cryptoId, within: context) else {
                        assertionFailure()
                        return continuation.resume(returning: false)
                    }
                    let contactIsUpdated = try persistedOwnedIdentity.updateContact(with: obvContactIdentityWithinEngine, isRestoringSyncSnapshotOrBackup: false)
                    let capabilitiesWereUpdated = try persistedOwnedIdentity.setContactCapabilities(contactCryptoId: obvContactIdentityWithinEngine.cryptoId, newCapabilities: capabilitiesWithinEngine)
                    return continuation.resume(returning: contactIsUpdated || capabilitiesWereUpdated)
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
