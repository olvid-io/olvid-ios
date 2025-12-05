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
final class ReceivedMessageToReceivedMessageV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "ReceivedMessage"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][ReceivedMessageToReceivedMessageV61ToV62]"

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(ObvEncodedTransformerForMigration(), forName: .obvEncodedTransformerName)
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

            // encodedEncodedInputs (ObvEncoded) --> rawEncodedEncodedInputs (Binary)

            do {
                                
                guard let encodedEncodedInputs = sInstance.value(forKey: "encodedEncodedInputs") as? ObvEncoded else {
                    assertionFailure()
                    throw ObvError.couldNotGetEncodedEncodedInputs
                }
                
                dInstance.setValue(encodedEncodedInputs.rawData, forKey: "rawEncodedEncodedInputs")

            }

            // encodedUserDialogResponse (ObvEncoded, optional) --> rawEncodedUserDialogResponse (Binary, optional)

            do {
                
                // The value transformer is already set
                
                if let value = sInstance.value(forKey: "encodedUserDialogResponse") {
                    
                    guard let encodedUserDialogResponse = value as? ObvEncoded else {
                        assertionFailure()
                        throw ObvError.couldNotGetEncodedUserDialogResponse
                    }
                    
                    dInstance.setValue(encodedUserDialogResponse.rawData, forKey: "rawEncodedUserDialogResponse")
                    
                    // check
                    
                    _ = try getEncodedUserDialogResponse(dInstance: dInstance)
                    
                }
                
            }

            // protocolInstanceUid (UID) --> rawProtocolInstanceUid (Binary)

            do {
                                
                guard let protocolInstanceUid = sInstance.value(forKey: "protocolInstanceUid") as? UID else {
                    assertionFailure()
                    throw ObvError.couldNotGetProtocolInstanceUid
                }
                
                dInstance.setValue(protocolInstanceUid.raw, forKey: "rawProtocolInstanceUid")

            }

            // Checks
            
            do {
                _ = try getEncodedInputs(dInstance: dInstance)
                // We don't test rawEncodedUserDialogResponse here
                _ = try getProtocolInstanceUid(dInstance: dInstance)
                
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetEncodedEncodedInputs
        case couldNotGetEncodedUserDialogResponse
        case couldNotGetProtocolInstanceUid
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getEncodedInputs(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> [ObvEncoded] {
        guard let rawEncodedEncodedInputs = dInstance.value(forKey: "rawEncodedEncodedInputs") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let encoded = ObvEncoded(withRawData: rawEncodedEncodedInputs) else { assertionFailure(); throw .couldNotParseValue }
        guard let encodedInputs = [ObvEncoded](encoded) else { assertionFailure(); throw .couldNotParseValue }
        return encodedInputs
    }

    private func getProtocolInstanceUid(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> UID {
        guard let rawProtocolInstanceUid = dInstance.value(forKey: "rawProtocolInstanceUid") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let protocolInstanceUid = UID(uid: rawProtocolInstanceUid) else { assertionFailure(); throw .couldNotParseValue }
        return protocolInstanceUid
    }

    /// Since `rawEncodedUserDialogResponse` may be nil, this method should only be called when we know the destination has a non-nil value
    private func getEncodedUserDialogResponse(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> ObvEncoded {
        guard let rawEncodedUserDialogResponse = dInstance.value(forKey: "rawEncodedUserDialogResponse") as? Data else { assertionFailure(); throw .couldNotParseValue }
        guard let obvEncoded = ObvEncoded(withRawData: rawEncodedUserDialogResponse) else { assertionFailure(); throw .couldNotParseValue }
        return obvEncoded
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
