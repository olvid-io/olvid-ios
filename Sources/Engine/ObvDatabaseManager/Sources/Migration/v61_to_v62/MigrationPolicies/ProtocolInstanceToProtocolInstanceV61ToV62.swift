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
final class ProtocolInstanceToProtocolInstanceV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "ProtocolInstance"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][ProtocolInstanceToProtocolInstanceV61ToV62]"

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(ObvEncodedTransformerForMigration(), forName: .obvEncodedTransformerName)
        ValueTransformer.setValueTransformer(ObvCryptoIdentityTransformerForMigration(), forName: .obvCryptoIdentityTransformerName)
        ValueTransformer.setValueTransformer(UIDTransformerForMigration(), forName: .uidTransformerName)
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

            // encodedCurrentState (ObvEncoded) --> rawEncodedCurrentState (Binary)

            do {
                                
                guard let encodedCurrentState = sInstance.value(forKey: "encodedCurrentState") as? ObvEncoded else {
                    assertionFailure()
                    throw ObvError.couldNotGetEncodedCurrentState
                }
                
                dInstance.setValue(encodedCurrentState.rawData, forKey: "rawEncodedCurrentState")

            }

            // ownedCryptoIdentity (ObvCryptoIdentity) --> rawOwnedCryptoIdentity (Binary)

            do {
                                
                guard let ownedCryptoIdentity = sInstance.value(forKey: "ownedCryptoIdentity") as? ObvCryptoIdentity else {
                    assertionFailure()
                    throw ObvError.couldNotGetOwnedCryptoIdentity
                }
                
                dInstance.setValue(ownedCryptoIdentity.getIdentity(), forKey: "rawOwnedCryptoIdentity")

            }

            // uid (UID) --> rawUID (Binary)

            do {
                                
                guard let uid = sInstance.value(forKey: "uid") as? UID else {
                    assertionFailure()
                    throw ObvError.couldNotGetUID
                }
                
                dInstance.setValue(uid.raw, forKey: "rawUID")

            }

            // Checks
            
            do {
                _ = try getEncodedCurrentState(dInstance: dInstance)
                _ = try getOwnedCryptoIdentity(dInstance: dInstance)
                _ = try getUid(dInstance: dInstance)
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetEncodedCurrentState
        case couldNotGetOwnedCryptoIdentity
        case couldNotGetUID
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getEncodedCurrentState(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> ObvEncoded {
        guard let rawEncodedCurrentState = dInstance.value(forKey: "rawEncodedCurrentState") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let encoded = ObvEncoded(withRawData: rawEncodedCurrentState) else { assertionFailure(); throw .couldNotParseValue }
        return encoded
    }

    private func getOwnedCryptoIdentity(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> ObvCryptoIdentity {
        guard let rawOwnedCryptoIdentity = dInstance.value(forKey: "rawOwnedCryptoIdentity") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let ownedCryptoIdentity = ObvCryptoIdentity(from: rawOwnedCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
        return ownedCryptoIdentity
    }

    private func getUid(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> UID {
        guard let rawUID = dInstance.value(forKey: "rawUID") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let uid = UID(uid: rawUID) else { assertionFailure(); throw .couldNotParseValue }
        return uid
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


private class ObvEncodedTransformerForMigration: ValueTransformer {

    override public class func transformedValueClass() -> AnyClass {
        return ObvEncoded.self
    }

    public override class func allowsReverseTransformation() -> Bool {
        return true
    }

    public override func transformedValue(_ value: Any?) -> Any? {
        guard let encodedData = value as? ObvEncoded else { return nil }
        return encodedData.rawData
    }

    public override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return ObvEncoded(withRawData: data)
    }
}


private extension NSValueTransformerName {
    static let obvEncodedTransformerName = NSValueTransformerName(rawValue: "ObvEncodedTransformer")
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
        guard let data = value as? Data else { return nil }
        return UID(uid: data)
    }

}


private extension NSValueTransformerName {
    static let uidTransformerName = NSValueTransformerName(rawValue: "UIDTransformer")
}
