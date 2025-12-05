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
final class OwnedIdentityToOwnedIdentityV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "OwnedIdentity"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][OwnedIdentityToOwnedIdentityV61ToV62]"

    /// Since we `OwnedIdentity` entity is mapped first in the xcmappingmodel, we immediately register all value transformers.
    /// See `OwnedIdentityToOwnedIdentityWithValueTransformers` for more information.
    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(ObvCryptoIdentityTransformerForMigration(), forName: .obvCryptoIdentityTransformerName)
        ValueTransformer.setValueTransformer(ObvOwnedCryptoIdentityTransformerForMigration(), forName: .obvOwnedCryptoIdentityTransformerName)
        ValueTransformer.setValueTransformer(UIDTransformerForMigration(), forName: .uidTransformerName)
        ValueTransformer.setValueTransformer(EncryptedDataTransformerForMigration(), forName: .encryptedDataTransformerName)
        ValueTransformer.setValueTransformer(SeedTransformerForMigration(), forName: .seedTransformerName)
        ValueTransformer.setValueTransformer(ObvEncodedTransformerForMigration(), forName: .obvEncodedTransformerName)
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

            // cryptoIdentity (ObvCryptoIdentity) --> rawCryptoIdentity (Binary)

            do {
                                
                guard let cryptoIdentity = sInstance.value(forKey: "cryptoIdentity") as? ObvCryptoIdentity else {
                    assertionFailure()
                    throw ObvError.couldNotGetCryptoIdentity
                }
                
                dInstance.setValue(cryptoIdentity.getIdentity(), forKey: "rawCryptoIdentity")
                
            }

            // ownedCryptoIdentity (ObvOwnedCryptoIdentity) --> rawOwnedCryptoIdentity (Binary)

            do {
                                
                guard let ownedCryptoIdentity = sInstance.value(forKey: "ownedCryptoIdentity") as? ObvOwnedCryptoIdentity else {
                    assertionFailure()
                    throw ObvError.couldNotGetOwnedCryptoIdentity
                }
                
                dInstance.setValue(ownedCryptoIdentity.obvEncode().rawData, forKey: "rawOwnedCryptoIdentity")
                
            }

            // Checks
            
            do {
                _ = try getCryptoIdentity(dInstance: dInstance)
                _ = try getOwnedCryptoIdentity(dInstance: dInstance)
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetCryptoIdentity
        case couldNotGetOwnedCryptoIdentity
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getCryptoIdentity(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> ObvCryptoIdentity {
        guard let rawCryptoIdentity = dInstance.value(forKey: "rawCryptoIdentity") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let cryptoIdentity = ObvCryptoIdentity(from: rawCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
        return cryptoIdentity
    }

    private func getOwnedCryptoIdentity(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> ObvOwnedCryptoIdentity {
        guard let rawOwnedCryptoIdentity = dInstance.value(forKey: "rawOwnedCryptoIdentity") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let encodedList = ObvEncoded(withRawData: rawOwnedCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
        guard let ownedCryptoIdentity = ObvOwnedCryptoIdentity(encodedList) else { assertionFailure(); throw .couldNotParseValue }
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


private class ObvOwnedCryptoIdentityTransformerForMigration: ValueTransformer {

    override public class func transformedValueClass() -> AnyClass {
        return ObvOwnedCryptoIdentity.self
    }

    override public class func allowsReverseTransformation() -> Bool {
        return true
    }

    /// Transform an ObvCryptoIdentity into an instance of Data (which actually is the raw representation of an ObvEncoded object)
    override public func transformedValue(_ value: Any?) -> Any? {
        guard let obvCryptoIdentity = value as? ObvOwnedCryptoIdentity else { return nil }
        let obvEncoded = obvCryptoIdentity.obvEncode()
        return obvEncoded.rawData
    }

    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        guard let encodedList = ObvEncoded(withRawData: data) else { return nil }
        return ObvOwnedCryptoIdentity(encodedList)
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
