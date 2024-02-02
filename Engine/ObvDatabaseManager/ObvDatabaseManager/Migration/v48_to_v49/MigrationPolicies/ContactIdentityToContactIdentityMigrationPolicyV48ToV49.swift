/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


final class ContactIdentityToContactIdentityMigrationPolicyV48ToV49: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "ContactIdentity"
    static let debugPrintPrefix = "[\(errorDomain)][ContactIdentityToContactIdentityMigrationPolicyV48ToV49]"

    // Tested
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
            }
            
            let dInstance = try initializeDestinationInstance(forEntityName: "ContactIdentity",
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }
            
            // Move the old `cryptoIdentity` to the new `rawIdentity` attribute.
            // Doing this allows to remove the usage of the ObvCryptoIdentityTransformer (ValueTransformer).
            
            ValueTransformer.setValueTransformer(ObvCryptoIdentityTransformerForMigration(), forName: .obvCryptoIdentityTransformerName)

            guard let cryptoIdentity = sInstance.value(forKey: "cryptoIdentity") as? ObvCryptoIdentity else {
                throw ObvError.couldNotGetCryptoIdentity
            }
            
            dInstance.setValue(cryptoIdentity.getIdentity(), forKey: "rawIdentity")
            
        } catch {
            assertionFailure()
            throw error
        }
                
    }
    
    enum ObvError: Error {
        case couldNotGetCryptoIdentity
    }
    
}


private final class ObvCryptoIdentityTransformerForMigration: ValueTransformer {
    
    override public class func transformedValueClass() -> AnyClass {
        return ObvCryptoIdentity.self
    }
    
    override public class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    /// Transform an ObvIdentity into an instance of Data
    override public func transformedValue(_ value: Any?) -> Any? {
        guard let obvCryptoIdentity = value as? ObvCryptoIdentity else { return nil }
        return obvCryptoIdentity.getIdentity()
    }
    
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return ObvCryptoIdentity(from: data)
    }
}

private extension NSValueTransformerName {
    static let obvCryptoIdentityTransformerName = NSValueTransformerName(rawValue: "ObvCryptoIdentityTransformer")
}
