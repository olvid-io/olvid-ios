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


final class OwnedIdentityToOwnedIdentityV59ToV60: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "OwnedIdentity"
    static let debugPrintPrefix = "[\(errorDomain)][OwnedIdentityToOwnedIdentityV59ToV60]"
    
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
            }
            
            let dInstance = try initializeDestinationInstance(forEntityName: "OwnedIdentity",
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)
            defer {
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }
            
            // The new version of the model adds an "rawBackupSeed" attribute that we set to a deterministic value, that depends on the MAC key
            
            ValueTransformer.setValueTransformer(ObvOwnedCryptoIdentityTransformerForMigration(), forName: .obvOwnedCryptoIdentityTransformerName)

            guard let ownedCryptoIdentity = sInstance.value(forKey: "ownedCryptoIdentity") as? ObvOwnedCryptoIdentity else {
                assertionFailure()
                throw ObvError.couldNotGetOwnedCryptoIdentity
            }

            let secretMACKey = ownedCryptoIdentity.secretMACKey
            
            let backupSeed: BackupSeed
            do {
                backupSeed = try Self.getDeterministicBackupSeedForLegacyIdentity(secretMACKey: secretMACKey)
            } catch {
                assertionFailure()
                throw ObvError.failedToGenerateDeterministicBackupSeed(error: error)
            }
            
            dInstance.setValue(backupSeed.raw, forKey: "rawBackupSeed")
            
        } catch {
            assertionFailure()
            throw error
        }
        
    }
    
    enum ObvError: Error {
        case couldNotGetOwnedCryptoIdentity
        case failedToTurnRandomIntoSeed
        case failedToGenerateDeterministicBackupSeed(error: Error)
    }

    
    private static func getDeterministicBackupSeedForLegacyIdentity(secretMACKey: any MACKey) throws -> BackupSeed {
        let data = BackupSeedForLegacyIdentityForMigration.hashPadding
        let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
        let fixedByte = Data([BackupSeedForLegacyIdentityForMigration.macPayload])
        var hashInput = try MAC.compute(forData: fixedByte, withKey: secretMACKey)
        hashInput.append(data)
        let r = sha256.hash(hashInput)
        guard let backupSeed = BackupSeed(with: r.prefix(BackupSeed.byteLength)) else {
            throw ObvError.failedToTurnRandomIntoSeed
        }
        return backupSeed
    }

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


private struct BackupSeedForLegacyIdentityForMigration {
    public static let macPayload: UInt8 = 0xcc
    public static let hashPadding = "backupKey".data(using: .utf8)!
}
