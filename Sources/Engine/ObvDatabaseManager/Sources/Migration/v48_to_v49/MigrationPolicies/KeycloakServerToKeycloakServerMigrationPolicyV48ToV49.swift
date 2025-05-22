/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

/// This policy allows to migrate the API keys found in each ``OwnedIdentity`` entity to its (optional) associated `KeycloakServer` entity.
/// ``OwnedIdentity`` without keycloak server will "lose" their API key, as they are not needed anymore.
final class KeycloakServerToKeycloakServerMigrationPolicyV48ToV49: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "KeycloakServer"
    static let debugPrintPrefix = "[\(errorDomain)][KeycloakServerToKeycloakServerMigrationPolicyV48ToV49]"

    private static let apiKeyForOwnedIdentityKey = "KeycloakServerToKeycloakServerMigrationPolicyV48ToV49.apiKeyForOwnedIdentityKey"
    
    // Tested
    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {

        do {
            
            // This method is called once for this entity, before all relationships of all entities have been re-created.
            
            // We look for all owned identities to get their (optional) `apiKey` value (UUID). Since we want to store these values in the KeycloakServer corresponding to this owned identity, we store the value in the manager's userInfo dictionary.
            
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "OwnedIdentity")
            let ownedIdentityObjects = try manager.sourceContext.fetch(fetchRequest)
            
            var apiKeyForOwnedIdentity = [Data: UUID]()
            
            for ownedIdentityObject in ownedIdentityObjects {
                guard let ownedIdentity = ownedIdentityObject.value(forKey: "cryptoIdentity") as? ObvCryptoIdentity else {
                    throw ObvError.couldNotGetCryptoIdentity
                }
                if let apiKey = ownedIdentityObject.value(forKey: "apiKey") as? UUID {
                    apiKeyForOwnedIdentity[ownedIdentity.getIdentity()] = apiKey
                }
            }
            
            var userInfo = manager.userInfo ?? [AnyHashable: Any]()
            userInfo[Self.apiKeyForOwnedIdentityKey] = apiKeyForOwnedIdentity
            manager.userInfo = userInfo
            
        } catch {
            assertionFailure()
            throw error
        }

    }
    
    
    // Tested
    override func end(_ mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            // This method is called once for this entity, after all relationships of all entities have been re-created.
            
            debugPrint("\(Self.debugPrintPrefix) end(_ mapping: NSEntityMapping, manager: NSMigrationManager) starts")
            defer {
                debugPrint("\(Self.debugPrintPrefix) end(_ mapping: NSEntityMapping, manager: NSMigrationManager) ends")
            }
            
            guard let apiKeyForOwnedIdentity = manager.userInfo?[Self.apiKeyForOwnedIdentityKey] as? [Data: UUID] else {
                throw ObvError.couldNotRecoverApiKeyForOwnedIdentityDictFromManagersUserInfo
            }
            
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "KeycloakServer")
            let keycloakServerObjects = try manager.destinationContext.fetch(fetchRequest)
            
            for keycloakServerObject in keycloakServerObjects {
                guard let rawOwnedIdentity = keycloakServerObject.value(forKey: "rawOwnedIdentity") as? Data else {
                    throw ObvError.couldNotGetCryptoIdentity
                }
                if let apiKey = apiKeyForOwnedIdentity[rawOwnedIdentity] {
                    keycloakServerObject.setValue(apiKey, forKey: "ownAPIKey")
                } else {
                    assertionFailure("We expect a keycloak managed owned identity to have an API key")
                }
            }
            
        } catch {
            assertionFailure()
            throw error
        }
        
    }
 
    
    enum ObvError: Error {
        case couldNotGetCryptoIdentity
        case couldNotRecoverApiKeyForOwnedIdentityDictFromManagersUserInfo
    }

}


private final class ObvCryptoIdentityTransformerForMigration: ValueTransformer {
    
    override public class func transformedValueClass() -> AnyClass {
        return ObvCryptoIdentity.self
    }
    
    override public class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    /// Transform an ObvIdentity into an instance of Data
    override public func transformedValue(_ value: Any?) -> Any? {
        guard let obvCryptoIdentity = value as? ObvCryptoIdentity else { return nil }
        return obvCryptoIdentity.getIdentity()
    }
    
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return ObvCryptoIdentity(from: data)
    }
}

private extension NSValueTransformerName {
    static let obvCryptoIdentityTransformerName = NSValueTransformerName(rawValue: "ObvCryptoIdentityTransformer")
}
