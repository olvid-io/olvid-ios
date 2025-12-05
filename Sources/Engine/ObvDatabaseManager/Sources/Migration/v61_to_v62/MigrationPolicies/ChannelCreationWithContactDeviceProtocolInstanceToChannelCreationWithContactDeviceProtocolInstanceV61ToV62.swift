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
final class ChannelCreationWithContactDeviceProtocolInstanceToChannelCreationWithContactDeviceProtocolInstanceV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "ChannelCreationWithContactDeviceProtocolInstance"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][ChannelCreationWithContactDeviceProtocolInstanceToChannelCreationWithContactDeviceProtocolInstanceV61ToV62]"
    
    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(UIDTransformerForMigration(), forName: .uidTransformerName)
        ValueTransformer.setValueTransformer(ObvCryptoIdentityTransformerForMigration(), forName: .obvCryptoIdentityTransformerName)
    }

    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
            }
            
            let dInstance = try initializeDestinationInstance(forEntityName: "ChannelCreationWithContactDeviceProtocolInstance",
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }
            
            // contactDeviceUid (UID) --> rawContactDeviceUid (Binary)
            
            do {
                                
                guard let contactDeviceUid = sInstance.value(forKey: "contactDeviceUid") as? UID else {
                    assertionFailure()
                    throw ObvError.couldNotGetSourceContactDeviceUid
                }
                
                dInstance.setValue(contactDeviceUid.raw, forKey: "rawContactDeviceUid")
                
            }

            // contactIdentity (ObvCryptoIdentity) --> rawContactIdentity (Binary)
            
            do {
                                
                guard let contactIdentity = sInstance.value(forKey: "contactIdentity") as? ObvCryptoIdentity else {
                    assertionFailure()
                    throw ObvError.couldNotGetObvCryptoIdentity
                }
                
                dInstance.setValue(contactIdentity.getIdentity(), forKey: "rawContactIdentity")
                
            }
            
            // Checks
            
            do {
                _ = try getContactDeviceUid(dInstance: dInstance)
                _ = try getContactIdentity(dInstance: dInstance)
            }
            
        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetSourceContactDeviceUid
        case couldNotGetObvCryptoIdentity
    }
    
    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }
    
    private func getContactDeviceUid(dInstance: NSManagedObject) throws -> UID {
        guard let rawContactDeviceUid = dInstance.value(forKey: "rawContactDeviceUid") as? Data else { assertionFailure(); throw ObvErrorForChecks.unexpectedNilValue }
        guard let contactDeviceUid = UID(uid: rawContactDeviceUid) else { assertionFailure(); throw ObvErrorForChecks.couldNotParseValue }
        return contactDeviceUid
    }
    
    private func getContactIdentity(dInstance: NSManagedObject) throws -> ObvCryptoIdentity {
        guard let rawContactIdentity = dInstance.value(forKey: "rawContactIdentity") as? Data else { assertionFailure(); throw ObvErrorForChecks.unexpectedNilValue }
        guard let contactIdentity = ObvCryptoIdentity(from: rawContactIdentity) else { assertionFailure(); throw ObvErrorForChecks.couldNotParseValue }
        return contactIdentity
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
