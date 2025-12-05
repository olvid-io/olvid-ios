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
import CoreData
import OlvidUtils
import ObvCrypto
import ObvEncoder

// ok
final class PersistedTrustOriginToPersistedTrustOriginV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "PersistedTrustOrigin"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][PersistedTrustOriginToPersistedTrustOriginV61ToV62]"

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(ObvCryptoIdentityTransformerForMigration(), forName: .obvCryptoIdentityTransformerName)
    }

    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
            }
            
            let dInstance = try initializeDestinationInstance(forEntityName: Self.entityName,
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }

            // mediatorOrGroupOwnerCryptoIdentity (ObvCryptoIdentity, optional) --> rawMediatorOrGroupOwnerCryptoIdentity (Binary, optional)

            do {
                                
                // The `mediatorOrGroupOwnerCryptoIdentity` is optional
                if let value = sInstance.value(forKey: "mediatorOrGroupOwnerCryptoIdentity") {
                    
                    guard let mediatorOrGroupOwnerCryptoIdentity = value as? ObvCryptoIdentity else {
                        assertionFailure()
                        throw ObvError.couldNotGetMediatorOrGroupOwnerCryptoIdentity
                    }
                    
                    dInstance.setValue(mediatorOrGroupOwnerCryptoIdentity.getIdentity(), forKey: "rawMediatorOrGroupOwnerCryptoIdentity")
                    
                }
                
            }

            // Checks
            
            do {
                _ = try getMediatorOrGroupOwnerCryptoIdentity(dInstance: dInstance)
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetMediatorOrGroupOwnerCryptoIdentity
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getMediatorOrGroupOwnerCryptoIdentity(dInstance: NSManagedObject) throws -> ObvCryptoIdentity? {
        guard let value = dInstance.value(forKey: "rawMediatorOrGroupOwnerCryptoIdentity") else { return nil }
        guard let rawMediatorOrGroupOwnerCryptoIdentity = value as? Data else { assertionFailure(); return nil }
        guard let cryptoIdentity = ObvCryptoIdentity(from: rawMediatorOrGroupOwnerCryptoIdentity) else { assertionFailure(); return nil }
        return cryptoIdentity
    }

}


// MARK: - Private helpers

private final class ObvCryptoIdentityTransformerForMigration: ValueTransformer {
    
    override class func transformedValueClass() -> AnyClass {
        return ObvCryptoIdentity.self
    }
    
    override class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    /// Transform an ObvIdentity into an instance of Data
    override func transformedValue(_ value: Any?) -> Any? {
        guard let obvCryptoIdentity = value as? ObvCryptoIdentity else { return nil }
        return obvCryptoIdentity.getIdentity()
    }
    
    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return ObvCryptoIdentity(from: data)
    }
}


private extension NSValueTransformerName {
    static let obvCryptoIdentityTransformerName = NSValueTransformerName(rawValue: "ObvCryptoIdentityTransformer")
}
