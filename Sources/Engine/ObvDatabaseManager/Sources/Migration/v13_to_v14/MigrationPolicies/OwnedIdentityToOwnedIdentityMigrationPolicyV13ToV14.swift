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
import ObvEncoder
import ObvCrypto
import ObvTypes

fileprivate let errorDomain = "ObvEngineMigrationV13ToV14"
fileprivate let debugPrintPrefix = "[\(errorDomain)][OwnedIdentityToOwnedIdentityMigrationPolicyV13ToV14]"


final class OwnedIdentityToOwnedIdentityMigrationPolicyV13ToV14: NSEntityMigrationPolicy {
    
    /// See `OwnedIdentityToOwnedIdentityWithValueTransformers` for more information.
    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(UIDTransformerForMigration(), forName: .uidTransformerName)
        ValueTransformer.setValueTransformer(ObvCryptoIdentityTransformerForMigration(), forName: .obvCryptoIdentityTransformerName)
        ValueTransformer.setValueTransformer(ObvOwnedCryptoIdentityTransformerForMigration(), forName: .obvOwnedCryptoIdentityTransformerName)
        ValueTransformer.setValueTransformer(EncryptedDataTransformerForMigration(), forName: .encryptedDataTransformerName)
        ValueTransformer.setValueTransformer(SeedTransformerForMigration(), forName: .seedTransformerName)
        ValueTransformer.setValueTransformer(ObvEncodedTransformerForMigration(), forName: .obvEncodedTransformerName)
    }

    /// This migration allows to store the owned identity within the keychain
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "OwnedIdentity",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)
        
        // All the properties were already mapped within `initializeDestinationInstance`. We only need to store the owned identity within the keychain.
        // First, we remove any previous entry (since it does not have the proper access group entitlement)

        guard let ownedCryptoIdentity = dInstance.value(forKey: "ownedCryptoIdentity") as? ObvOwnedCryptoIdentity else {
            let message = "Could not get owned crypto identity"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }

        try iOSSecItemDelete(cryptoIdentity: ownedCryptoIdentity.getObvCryptoIdentity())
        
        // Now we can add the owned identity within the keychain. Note that the routine called below adds the proper group access entitlements
        
        try iOSSecItemAdd(ownedCryptoIdentity: ownedCryptoIdentity)
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
        
    }
    
    
    private func iOSSecItemAdd(ownedCryptoIdentity: ObvOwnedCryptoIdentity) throws {
        let identity = ownedCryptoIdentity.getObvCryptoIdentity().getIdentity()
        let encodedOwnedCryptoIdentity = ownedCryptoIdentity.obvEncode()
        let accessGroup = Bundle.main.infoDictionary!["OBV_APP_GROUP_IDENTIFIER"]! as! String
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
                                     kSecAttrAccount as String: identity,
                                     kSecValueData as String: encodedOwnedCryptoIdentity.rawData,
                                     kSecAttrAccessGroup as String: accessGroup]
        let status = SecItemAdd(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return
        default:
            let message = "Could not store owned identity within the keychain: \(status.description)"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
    }
    
    
    private func iOSSecItemDelete(cryptoIdentity: ObvCryptoIdentity) throws {
        
        let identity = cryptoIdentity.getIdentity()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                     kSecAttrAccount as String: identity]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            let message = "Could not get owned identity within the keychain: \(status.description)"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
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
        guard let obvCryptoIdentity = value as? ObvCryptoIdentity else { assertionFailure(); return nil }
        return obvCryptoIdentity.getIdentity()
    }
    
    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { assertionFailure(); return nil }
        return ObvCryptoIdentity(from: data)
    }
}


private extension NSValueTransformerName {
    static let obvCryptoIdentityTransformerName = NSValueTransformerName(rawValue: "ObvCryptoIdentityTransformer")
}


private class ObvOwnedCryptoIdentityTransformerForMigration: ValueTransformer {

    override public class func transformedValueClass() -> AnyClass {
        return ObvOwnedCryptoIdentity.self
    }

    override public class func allowsReverseTransformation() -> Bool {
        return true
    }

    /// Transform an ObvCryptoIdentity into an instance of Data (which actually is the raw representation of an ObvEncoded object)
    override public func transformedValue(_ value: Any?) -> Any? {
        guard let obvCryptoIdentity = value as? ObvOwnedCryptoIdentity else { assertionFailure(); return nil }
        let obvEncoded = obvCryptoIdentity.obvEncode()
        return obvEncoded.rawData
    }

    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { assertionFailure(); return nil }
        guard let encodedList = ObvEncoded(withRawData: data) else { assertionFailure(); return nil }
        let returnedValue = ObvOwnedCryptoIdentity(encodedList)
        return returnedValue
    }
}


private extension NSValueTransformerName {
    static let obvOwnedCryptoIdentityTransformerName = NSValueTransformerName(rawValue: "ObvOwnedCryptoIdentityTransformer")
}


private class UIDTransformerForMigration: ValueTransformer {

    override public class func transformedValueClass() -> AnyClass {
        return UID.self
    }

    override public class func allowsReverseTransformation() -> Bool {
        return true
    }


    /// Turn an UID into a Data object. This method never fails.
    override public func transformedValue(_ value: Any?) -> Any? {
        let uid = value as! UID
        return uid.raw
    }

    /// Try to turn a Data object back into a UID. This method can return nil.
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { assertionFailure(); return nil }
        return UID(uid: data)
    }

}


private extension NSValueTransformerName {
    static let uidTransformerName = NSValueTransformerName(rawValue: "UIDTransformer")
}


private class EncryptedDataTransformerForMigration: ValueTransformer {
    
    override public class func transformedValueClass() -> AnyClass {
        return EncryptedData.self
    }
    
    override public class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    override public func transformedValue(_ value: Any?) -> Any? {
        guard let encryptedData = value as? EncryptedData else { assertionFailure(); return nil }
        return encryptedData.raw
    }
    
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { assertionFailure(); return nil }
        return EncryptedData(data: data)
    }
    
}


private extension NSValueTransformerName {
    static let encryptedDataTransformerName = NSValueTransformerName(rawValue: "EncryptedDataTransformer")
}


private class SeedTransformerForMigration: ValueTransformer {

    override public class func transformedValueClass() -> AnyClass {
        return Seed.self
    }

    override public class func allowsReverseTransformation() -> Bool {
        return true
    }


    /// Turn an Seed into a Data object. This method never fails.
    override public func transformedValue(_ value: Any?) -> Any? {
        let uid = value as! Seed
        return uid.raw
    }

    /// Try to turn a Data object back into a Seed. This method can return nil.
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { assertionFailure(); return nil }
        return Seed(with: data)
    }

}

private extension NSValueTransformerName {
    static let seedTransformerName = NSValueTransformerName(rawValue: "SeedTransformer")
}


private class ObvEncodedTransformerForMigration: ValueTransformer {

    override public class func transformedValueClass() -> AnyClass {
        return ObvEncoded.self
    }

    public override class func allowsReverseTransformation() -> Bool {
        return true
    }

    public override func transformedValue(_ value: Any?) -> Any? {
        guard let encodedData = value as? ObvEncoded else { assertionFailure(); return nil }
        return encodedData.rawData
    }

    public override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { assertionFailure(); return nil }
        return ObvEncoded(withRawData: data)
    }
}


private extension NSValueTransformerName {
    static let obvEncodedTransformerName = NSValueTransformerName(rawValue: "ObvEncodedTransformer")
}
