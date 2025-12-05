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
import ObvTypes

// ok
final class ObvObliviousChannelToObvObliviousChannelV61ToV62: NSEntityMigrationPolicy {
    
    static let entityName: String = "ObvObliviousChannel"
    static let errorDomain: String = entityName
    static let debugPrintPrefix: String = "[\(errorDomain)][ObvObliviousChannelToObvObliviousChannelV61ToV62]"

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        ValueTransformer.setValueTransformer(UIDTransformerForMigration(), forName: .uidTransformerName)
        ValueTransformer.setValueTransformer(ObvCryptoIdentityTransformerForMigration(), forName: .obvCryptoIdentityTransformerName)
        ValueTransformer.setValueTransformer(SeedTransformerForMigration(), forName: .seedTransformerName)
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

            // currentDeviceUid (UID) --> rawCurrentDeviceUID (Binary)

            do {
                                
                guard let currentDeviceUid = sInstance.value(forKey: "currentDeviceUid") as? UID else {
                    assertionFailure()
                    throw ObvError.couldNotGetCurrentDeviceUid
                }
                
                dInstance.setValue(currentDeviceUid.raw, forKey: "rawCurrentDeviceUID")
                
            }

            // remoteCryptoIdentity (ObvCryptoIdentity) --> rawRemoteCryptoId (Binary)

            do {
                                
                guard let remoteCryptoIdentity = sInstance.value(forKey: "remoteCryptoIdentity") as? ObvCryptoIdentity else {
                    assertionFailure()
                    throw ObvError.couldNotGetRemoteCryptoIdentity
                }
                
                dInstance.setValue(remoteCryptoIdentity.getIdentity(), forKey: "rawRemoteCryptoId")
                
            }

            // remoteDeviceUid (UID) -->  rawRemoteDeviceUID (Binary)

            do {

                // The value transformer is already set
                
                guard let remoteDeviceUid = sInstance.value(forKey: "remoteDeviceUid") as? UID else {
                    assertionFailure()
                    throw ObvError.couldNotGetRemoteDeviceUid
                }
                
                dInstance.setValue(remoteDeviceUid.raw, forKey: "rawRemoteDeviceUID")
                
            }

            // seedForNextSendKey (Seed, optional) --> rawSeedForNextSendKey (Binary)
            // The seedForNextSendKey was optional in the old model, which is a mistake.
            // The rawSeedForNextSendKey is not optional in the new model
            // In practice, this should not be an issue, since the *class* was not expecting an optional
            // (which is very poor design).
            // Yet, to prevent a crash of the migration, we use a dummy byte if the seedForNextSendKey
            // happens to be nil in the source model.

            do {

                if let value = sInstance.value(forKey: "seedForNextSendKey") {
                    
                    guard let seedForNextSendKey = value as? Seed else {
                        assertionFailure()
                        throw ObvError.couldNotGetSeedForNextSendKey
                    }
                    
                    dInstance.setValue(seedForNextSendKey.raw, forKey: "rawSeedForNextSendKey")

                } else {
                    
                    assertionFailure()
                    
                    dInstance.setValue(Data(repeating: 0x55, count: 1), forKey: "rawSeedForNextSendKey")
                    
                }
                                
            }

            // Checks
            
            do {
                _ = try getCurrentDeviceUID(dInstance: dInstance)
                _ = try remoteCryptoId(dInstance: dInstance)
                _ = try getRemoteDeviceUID(dInstance: dInstance)
                _ = try getSeedForNextSendKey(dInstance: dInstance)
            }

        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetCurrentDeviceUid
        case couldNotGetRemoteCryptoIdentity
        case couldNotGetRemoteDeviceUid
        case couldNotGetSeedForNextSendKey
    }

    // For checks
    
    enum ObvErrorForChecks: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }

    private func getCurrentDeviceUID(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> UID {
        guard let rawCurrentDeviceUID = dInstance.value(forKey: "rawCurrentDeviceUID") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let uid = UID(uid: rawCurrentDeviceUID) else { assertionFailure(); throw .unexpectedNilValue }
        return uid
    }
    
    private func remoteCryptoId(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> ObvCryptoId {
        guard let rawRemoteCryptoId = dInstance.value(forKey: "rawRemoteCryptoId") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        do {
            return try ObvCryptoId(identity: rawRemoteCryptoId)
        } catch {
            assertionFailure()
            throw .couldNotParseValue
        }
    }

    private func getRemoteDeviceUID(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> UID {
        guard let rawRemoteDeviceUID = dInstance.value(forKey: "rawRemoteDeviceUID") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard let uid = UID(uid: rawRemoteDeviceUID) else { assertionFailure(); throw .unexpectedNilValue }
        return uid
    }

    private func getSeedForNextSendKey(dInstance: NSManagedObject) throws(ObvErrorForChecks) -> Seed? {
        guard let rawSeedForNextSendKey = dInstance.value(forKey: "rawSeedForNextSendKey") as? Data else { assertionFailure(); throw .unexpectedNilValue }
        guard rawSeedForNextSendKey != Data(repeating: 0x55, count: 1) else { return nil } // Special case, the prevent a failure of the whole migration process
        guard let seed = Seed(with: rawSeedForNextSendKey) else { assertionFailure(); throw .unexpectedNilValue }
        return seed
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
        guard let data = value as? Data else { return nil }
        return Seed(with: data)
    }

}

private extension NSValueTransformerName {
    static let seedTransformerName = NSValueTransformerName(rawValue: "SeedTransformer")
}
