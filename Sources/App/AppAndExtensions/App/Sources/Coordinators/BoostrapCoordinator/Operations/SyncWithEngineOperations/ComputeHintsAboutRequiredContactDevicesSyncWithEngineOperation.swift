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
import OlvidUtils
import ObvEngine
import os.log
import CoreData
import ObvTypes
import ObvUICoreData


/// This operation computes the required sync tasks to be performed at the app level, given the data available at the engine level. It  does so for contact devices.
/// This operation does *not* update the app database, it only evaluates what should be done to be in sync.
///
/// This operation is expected to be executed on a queue that is *not* synchronized with app database updates. We do so for efficiency reasons.
/// The actual work of updating the app database is done, in practice, by executing the ``SyncPersistedObvContactDeviceWithEngineOperation`` on the appropriate queue.
///
/// This operation also takes a ``scope`` as an input. During bootstrap, it is set to ``.allContactDevices``. On certain occasions, when we only need to sync the devices of a specific contact, we can specify ``.contactDevicesOfContact``.
final class ComputeHintsAboutRequiredContactDevicesSyncWithEngineOperation: AsyncOperationWithSpecificReasonForCancel<ComputeHintsAboutRequiredOwnedDevicesSyncWithEngineOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let obvEngine: ObvEngine
    private let scope: Scope
    private let contextForAppQueries: NSManagedObjectContext

    enum Scope {
        case allContactDevices
        case restrictToOwnedCryptoId(ownedCryptoId: ObvCryptoId)
        case contactDevicesOfContact(contactIdentifier: ObvContactIdentifier)
    }

    init(obvEngine: ObvEngine, scope: Scope, contextForAppQueries: NSManagedObjectContext) {
        self.obvEngine = obvEngine
        self.scope = scope
        self.contextForAppQueries = contextForAppQueries
        super.init()
    }
        
    private(set) var missingDevices = Set<ObvContactDeviceIdentifier>()
    private(set) var devicesToDelete = Set<ObvContactDeviceIdentifier>()
    private(set) var devicesToUpdate = Set<ObvContactDeviceIdentifier>()
        
    override func main() async {
        
        do {
            
            let ownedCryptoIds: Set<ObvCryptoId>
            switch scope {
            case .allContactDevices:
                ownedCryptoIds = try await getAllOwnedCryptoIdWithinApp()
            case .restrictToOwnedCryptoId(ownedCryptoId: let ownedCryptoId):
                ownedCryptoIds = Set([ownedCryptoId])
            case .contactDevicesOfContact(contactIdentifier: let contactIdentifier):
                ownedCryptoIds = Set([contactIdentifier.ownedCryptoId])
            }

            for ownedCryptoId in ownedCryptoIds {
                
                // Get all contact devices within the engine (or only those of the contact, depending on the scope)
                
                let obvContactDevicesWithinEngine: Set<ObvContactDevice>
                switch scope {
                case .allContactDevices, .restrictToOwnedCryptoId:
                    obvContactDevicesWithinEngine = try await obvEngine.getAllObvContactDevicesOfContactsOfOwnedIdentity(ownedCryptoId)
                case .contactDevicesOfContact(contactIdentifier: let contactIdentifier):
                    obvContactDevicesWithinEngine = try obvEngine.getAllObvContactDevicesOfContact(with: contactIdentifier)
                }
                let contactDeviceIdentifiersWithinEngine = Set(obvContactDevicesWithinEngine.map(\.deviceIdentifier))
                
                // Get the contact device identifiers within the app

                let contactDeviceIdentifiersWithinApp: Set<ObvContactDeviceIdentifier>
                switch scope {
                case .allContactDevices, .restrictToOwnedCryptoId:
                    contactDeviceIdentifiersWithinApp = try await getAllContactDeviceIdentifiersWithinApp(ownedCryptoId: ownedCryptoId)
                case .contactDevicesOfContact(contactIdentifier: let contactIdentifier):
                    contactDeviceIdentifiersWithinApp = try await getAllContactDeviceIdentifiersWithinApp(contactIdentifier: contactIdentifier)
                }

                // Determine the owned devices to create, delete, or that might need to be updated
                
                let missingDevices = contactDeviceIdentifiersWithinEngine.subtracting(contactDeviceIdentifiersWithinApp)
                let devicesToDelete = contactDeviceIdentifiersWithinApp.subtracting(contactDeviceIdentifiersWithinEngine)
                let devicesThatMightNeedToBeUpdated = contactDeviceIdentifiersWithinApp.subtracting(devicesToDelete)

                // Among the devices that might need to be updated, determine the ones that indeed need to be updated by simulating the update

                for device in devicesThatMightNeedToBeUpdated {
                    
                    guard let contactDeviceWithinEngine = obvContactDevicesWithinEngine.filter({ $0.deviceIdentifier == device }).first else {
                        assertionFailure()
                        continue
                    }

                    if try await contactDeviceWithinAppWouldBeUpdated(with: contactDeviceWithinEngine) {
                        self.devicesToUpdate.insert(device)
                    }

                }
                
                self.missingDevices.formUnion(missingDevices)
                self.devicesToDelete.formUnion(devicesToDelete)
                
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

    
    private func getAllContactDeviceIdentifiersWithinApp(ownedCryptoId: ObvCryptoId) async throws -> Set<ObvContactDeviceIdentifier> {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvContactDeviceIdentifier>, Error>) in
            context.perform {
                do {
                    let ownedDevicesWithinApp = try PersistedObvContactDevice.getAllContactDeviceIdentifiersOfContactsOfOwnedIdentity(ownedCryptoId: ownedCryptoId, within: context)
                    return continuation.resume(returning: ownedDevicesWithinApp)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

    
    private func getAllContactDeviceIdentifiersWithinApp(contactIdentifier: ObvContactIdentifier) async throws -> Set<ObvContactDeviceIdentifier> {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvContactDeviceIdentifier>, Error>) in
            context.perform {
                do {
                    let ownedDevicesWithinApp = try PersistedObvContactDevice.getAllContactDeviceIdentifiersOfContact(contactIdentifier: contactIdentifier, within: context)
                    return continuation.resume(returning: ownedDevicesWithinApp)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }


    private func contactDeviceWithinAppWouldBeUpdated(with contactDeviceWithinEngine: ObvContactDevice) async throws -> Bool {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            context.perform {
                do {
                    guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: contactDeviceWithinEngine.deviceIdentifier.ownedCryptoId, within: context) else {
                        assertionFailure()
                        return continuation.resume(returning: false)
                    }
                    let contactDeviceHadToBeUpdated = try persistedOwnedIdentity.updateContactDevice(with: contactDeviceWithinEngine, isRestoringSyncSnapshotOrBackup: false)
                    return continuation.resume(returning: contactDeviceHadToBeUpdated)
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
