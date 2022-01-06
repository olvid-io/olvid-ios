/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
        let encodedOwnedCryptoIdentity = ownedCryptoIdentity.encode()
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
