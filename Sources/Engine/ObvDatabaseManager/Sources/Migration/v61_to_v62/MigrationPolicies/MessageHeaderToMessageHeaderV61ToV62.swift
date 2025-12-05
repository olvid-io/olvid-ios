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

// ok
final class MessageHeaderToMessageHeaderV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "MessageHeader"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][MessageHeaderToMessageHeaderV61ToV62]"

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(UIDTransformerForMigration(), forName: .uidTransformerName)
        ValueTransformer.setValueTransformer(ObvCryptoIdentityTransformerForMigration(), forName: .obvCryptoIdentityTransformerName)
        ValueTransformer.setValueTransformer(EncryptedDataTransformerForMigration(), forName: .encryptedDataTransformerName)
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

            // deviceUid (UID) --> rawDeviceUid (Binary)

            do {
                                
                guard let deviceUid = sInstance.value(forKey: "deviceUid") as? UID else {
                    assertionFailure()
                    throw ObvError.couldNotGetDeviceUid
                }
                
                dInstance.setValue(deviceUid.raw, forKey: "rawDeviceUid")
                
            }

            // toCryptoIdentity (ObvCryptoIdentity) --> rawToCryptoIdentity (Binary)

            do {
                                
                guard let toCryptoIdentity = sInstance.value(forKey: "toCryptoIdentity") as? ObvCryptoIdentity else {
                    assertionFailure()
                    throw ObvError.couldNotGetToCryptoIdentity
                }
                
                dInstance.setValue(toCryptoIdentity.getIdentity(), forKey: "rawToCryptoIdentity")
                
            }
            
            // wrappedKey (EncryptedData) --> rawWrappedKey (Binary)
            
            do {
                                
                guard let wrappedKey = sInstance.value(forKey: "wrappedKey") as? EncryptedData else {
                    assertionFailure()
                    throw ObvError.couldNotGetWrappedKey
                }
                
                dInstance.setValue(wrappedKey.raw, forKey: "rawWrappedKey")
                
            }

            // Checks
            
            do {
                _ = try getDeviceUid(dInstance: dInstance)
                _ = try getToCryptoIdentity(dInstance: dInstance)
                _ = try getWrappedKey(dInstance: dInstance)
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetDeviceUid
        case couldNotGetToCryptoIdentity
        case couldNotGetWrappedKey
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getDeviceUid(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> UID {
        guard let rawDeviceUid = dInstance.value(forKey: "rawDeviceUid") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let deviceUid = UID(uid: rawDeviceUid) else { assertionFailure(); throw .couldNotParseValue }
        return deviceUid
    }
    
    private func getToCryptoIdentity(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> ObvCryptoIdentity {
        guard let rawToCryptoIdentity = dInstance.value(forKey: "rawToCryptoIdentity") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let toCryptoIdentity = ObvCryptoIdentity(from: rawToCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
        return toCryptoIdentity
    }

    private func getWrappedKey(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> EncryptedData {
        guard let rawWrappedKey = dInstance.value(forKey: "rawWrappedKey") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        return EncryptedData(data: rawWrappedKey)
    }
    
}


// MARK: - Private helpers

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
        guard let data = value as? Data else { return nil }
        return UID(uid: data)
    }

}


private extension NSValueTransformerName {
    static let uidTransformerName = NSValueTransformerName(rawValue: "UIDTransformer")
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


private class EncryptedDataTransformerForMigration: ValueTransformer {
    
    override public class func transformedValueClass() -> AnyClass {
        return EncryptedData.self
    }
    
    override public class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    override public func transformedValue(_ value: Any?) -> Any? {
        guard let encryptedData = value as? EncryptedData else { return nil }
        return encryptedData.raw
    }
    
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return EncryptedData(data: data)
    }
    
}


private extension NSValueTransformerName {
    static let encryptedDataTransformerName = NSValueTransformerName(rawValue: "EncryptedDataTransformer")
}
