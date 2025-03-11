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


/// This operation computes the required sync tasks to be performed at the app level, given the data available at the engine level. It  does so for owned devices.
/// This operation does *not* update the app database, it only evaluates what should be done to be in sync.
///
/// This operation is expected to be executed on a queue that is *not* synchronized with app database updates. We do so for efficiency reasons.
/// The actual work of updating the app database is done, in practice, by executing the ``SyncPersistedObvOwnedDevicesWithEngineOperation`` on the appropriate queue.
final class ComputeHintsAboutRequiredOwnedDevicesSyncWithEngineOperation: AsyncOperationWithSpecificReasonForCancel<ComputeHintsAboutRequiredOwnedDevicesSyncWithEngineOperation.ReasonForCancel>, @unchecked Sendable {
    
    private let obvEngine: ObvEngine
    private let scope: Scope
    private let contextForAppQueries: NSManagedObjectContext

    enum Scope {
        case allOwnedDevices
        case ownedDevicesOfOwnedIdentity(ownedCryptoId: ObvCryptoId)
    }

    init(obvEngine: ObvEngine, scope: Scope, contextForAppQueries: NSManagedObjectContext) {
        self.obvEngine = obvEngine
        self.scope = scope
        self.contextForAppQueries = contextForAppQueries
        super.init()
    }
    
    private(set) var missingDevices = Set<ObvOwnedDeviceIdentifier>()
    private(set) var devicesToDelete = Set<ObvOwnedDeviceIdentifier>()
    private(set) var devicesToUpdate = Set<ObvOwnedDeviceIdentifier>()
        
    override func main() async {
        
        do {
            
            // Get all owned devices within the engine
            
            let obvOwnedDevicesWithinEngine: Set<ObvOwnedDevice>
            switch scope {
            case .allOwnedDevices:
                obvOwnedDevicesWithinEngine = try await obvEngine.getAllOwnedDevices(restrictToActiveOwnedIdentities: true)
            case .ownedDevicesOfOwnedIdentity(ownedCryptoId: let ownedCryptoId):
                obvOwnedDevicesWithinEngine = try obvEngine.getAllOwnedDevicesOfOwnedIdentity(ownedCryptoId)
            }
            let ownedDeviceIdentifiersWithinEngine = Set(obvOwnedDevicesWithinEngine.compactMap(\.ownedDeviceIdentifier))
            
            // Get the owned devices within the app

            let ownedDeviceIdentifiersWithinApp: Set<ObvOwnedDeviceIdentifier>
            switch scope {
            case .allOwnedDevices:
                ownedDeviceIdentifiersWithinApp = try await getAllOwnedDeviceIdentifiersWithinApp()
            case .ownedDevicesOfOwnedIdentity(ownedCryptoId: let ownedCryptoId):
                ownedDeviceIdentifiersWithinApp = try await getAllOwnedDeviceIdentifiersWithinAppForOwnedCryptoId(ownedCryptoId)
            }

            // Determine the owned devices to create, delete, or that might need to be updated
            
            self.missingDevices = ownedDeviceIdentifiersWithinEngine.subtracting(ownedDeviceIdentifiersWithinApp)
            self.devicesToDelete = ownedDeviceIdentifiersWithinApp.subtracting(ownedDeviceIdentifiersWithinEngine)
            let devicesThatMightNeedToBeUpdated = ownedDeviceIdentifiersWithinApp.subtracting(devicesToDelete)

            // Among the devices that might need to be updated, determine the ones that indeed need to be updated by simulating the update

            for device in devicesThatMightNeedToBeUpdated {
                
                guard let ownedDeviceWithinEngine = obvOwnedDevicesWithinEngine.filter({ $0.ownedDeviceIdentifier == device }).first else {
                    assertionFailure()
                    continue
                }

                if try await ownedDeviceWithinAppWouldBeUpdated(with: ownedDeviceWithinEngine) {
                    self.devicesToUpdate.insert(device)
                }

            }
            
            return finish()
            
        } catch {
            assertionFailure()
            return cancel(withReason: .error(error: error))
        }
        
    }
    
    
    private func getAllOwnedDeviceIdentifiersWithinApp() async throws -> Set<ObvOwnedDeviceIdentifier> {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvOwnedDeviceIdentifier>, Error>) in
            context.perform {
                do {
                    let ownedDevicesWithinApp = try PersistedObvOwnedDevice.getAllOwnedDeviceIdentifiers(within: context)
                    return continuation.resume(returning: ownedDevicesWithinApp)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

    
    private func getAllOwnedDeviceIdentifiersWithinAppForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) async throws -> Set<ObvOwnedDeviceIdentifier> {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvOwnedDeviceIdentifier>, Error>) in
            context.perform {
                do {
                    let ownedDevicesWithinApp = try PersistedObvOwnedDevice.getAllOwnedDeviceIdentifiersOfOwnedCryptoId(ownedCryptoId, within: context)
                    return continuation.resume(returning: ownedDevicesWithinApp)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
    }


    private func ownedDeviceWithinAppWouldBeUpdated(with ownedDeviceWithinEngine: ObvOwnedDevice) async throws -> Bool {
        let context = self.contextForAppQueries
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            context.perform {
                do {
                    guard let ownedDeviceIdentifier = ownedDeviceWithinEngine.ownedDeviceIdentifier else {
                        assertionFailure()
                        return continuation.resume(returning: false)
                    }
                    guard let ownedDeviceWithinApp = try PersistedObvOwnedDevice.getPersistedObvOwnedDevice(with: ownedDeviceIdentifier, within: context) else {
                        assertionFailure()
                        return continuation.resume(returning: false)
                    }
                    try ownedDeviceWithinApp.updatePersistedObvOwnedDevice(with: ownedDeviceWithinEngine)
                    let returnedValue = !ownedDeviceWithinApp.changedValues().isEmpty
                    return continuation.resume(returning: returnedValue)
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
