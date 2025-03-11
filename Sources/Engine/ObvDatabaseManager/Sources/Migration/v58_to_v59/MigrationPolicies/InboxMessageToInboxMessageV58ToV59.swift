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
import ObvCrypto


final class InboxMessageToInboxMessageV58ToV59: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "InboxMessage"
    static let debugPrintPrefix = "[\(errorDomain)][InboxMessageToInboxMessageV58ToV59]"
    
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
            }
            
            let dInstance = try initializeDestinationInstance(forEntityName: "InboxMessage",
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }
            
            // Move the old `encryptedContent` to the new `rawEncryptedContent` attribute.
            // Doing this allows to remove the usage of the EncryptedData (ValueTransformer).
            
            ValueTransformer.setValueTransformer(EncryptedDataTransformerForMigration(), forName: .encryptedDataTransformerName)

            guard let encryptedContent = sInstance.value(forKey: "encryptedContent") as? EncryptedData else {
                assertionFailure()
                throw ObvError.couldNotGetEncryptedContent
            }

            dInstance.setValue(encryptedContent.raw, forKey: "rawEncryptedContent")
            
            // Move the old `fromCryptoIdentity` to the new `rawFromIdentity` attribute.
            // Doing this allows to remove the usage of the ObvCryptoIdentity (ValueTransformer).
            // Note that the `fromCryptoIdentity` of an InboxMessage can be nil (when the message has yet to be decrypted).

            ValueTransformer.setValueTransformer(ObvCryptoIdentityTransformerForMigration(), forName: .obvCryptoIdentityTransformerName)

            if let fromCryptoIdentity = sInstance.value(forKey: "fromCryptoIdentity") {
                
                guard let fromCryptoIdentity = fromCryptoIdentity as? ObvCryptoIdentity else {
                    assertionFailure()
                    throw ObvError.couldNotGetFromCryptoIdentity
                }

                dInstance.setValue(fromCryptoIdentity.getIdentity(), forKey: "rawFromIdentity")

            }
            
            // Move the old `wrappedKey` to the new `rawWrappedKey` attribute.
            // Doing this allows to remove the usage of the EncryptedData (ValueTransformer).

            guard let wrappedKey = sInstance.value(forKey: "wrappedKey") as? EncryptedData else {
                assertionFailure()
                throw ObvError.couldNotGetWrappedKey
            }

            dInstance.setValue(wrappedKey.raw, forKey: "rawWrappedKey")

            
        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetEncryptedContent
        case couldNotGetFromCryptoIdentity
        case couldNotGetWrappedKey
    }

}


// MARK: - Private helpers

private final class EncryptedDataTransformerForMigration: ValueTransformer {
    
    override class func transformedValueClass() -> AnyClass {
        return EncryptedData.self
    }
    
    override class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    override func transformedValue(_ value: Any?) -> Any? {
        guard let encryptedData = value as? EncryptedData else { return nil }
        return encryptedData.raw
    }
    
    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return EncryptedData(data: data)
    }
    
}


private extension NSValueTransformerName {
    static let encryptedDataTransformerName = NSValueTransformerName(rawValue: "EncryptedDataTransformer")
}


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
