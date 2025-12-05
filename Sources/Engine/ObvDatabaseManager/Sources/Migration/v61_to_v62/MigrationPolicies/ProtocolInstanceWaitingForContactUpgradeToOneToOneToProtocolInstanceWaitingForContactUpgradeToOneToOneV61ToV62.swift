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
final class ProtocolInstanceWaitingForContactUpgradeToOneToOneToProtocolInstanceWaitingForContactUpgradeToOneToOneV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "ProtocolInstanceWaitingForContactUpgradeToOneToOne"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][ProtocolInstanceWaitingForContactUpgradeToOneToOneToProtocolInstanceWaitingForContactUpgradeToOneToOneV61ToV62]"

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

            // contactCryptoIdentity (ObvCryptoIdentity) --> rawContactCryptoIdentity (Binary)

            do {
                                
                guard let contactCryptoIdentity = sInstance.value(forKey: "contactCryptoIdentity") as? ObvCryptoIdentity else {
                    assertionFailure()
                    throw ObvError.couldNotGetContactCryptoIdentity
                }
                
                dInstance.setValue(contactCryptoIdentity.getIdentity(), forKey: "rawContactCryptoIdentity")

            }

            // ownedCryptoIdentity (ObvCryptoIdentity) --> rawOwnedCryptoIdentity (Binary)

            do {

                // The value transformer is already set
                
                guard let ownedCryptoIdentity = sInstance.value(forKey: "ownedCryptoIdentity") as? ObvCryptoIdentity else {
                    assertionFailure()
                    throw ObvError.couldNotGetOwnedCryptoIdentity
                }
                
                dInstance.setValue(ownedCryptoIdentity.getIdentity(), forKey: "rawOwnedCryptoIdentity")

            }

            // Checks
            
            do {
                _ = try getContactCryptoIdentity(dInstance: dInstance)
                _ = try getOwnedCryptoIdentity(dInstance: dInstance)
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetContactCryptoIdentity
        case couldNotGetOwnedCryptoIdentity
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getContactCryptoIdentity(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> ObvCryptoIdentity {
        guard let rawContactCryptoIdentity = dInstance.value(forKey: "rawContactCryptoIdentity") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let contactCryptoIdentity = ObvCryptoIdentity(from: rawContactCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
        return contactCryptoIdentity
    }

    private func getOwnedCryptoIdentity(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> ObvCryptoIdentity {
        guard let rawOwnedCryptoIdentity = dInstance.value(forKey: "rawOwnedCryptoIdentity") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let ownedCryptoIdentity = ObvCryptoIdentity(from: rawOwnedCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
        return ownedCryptoIdentity
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
