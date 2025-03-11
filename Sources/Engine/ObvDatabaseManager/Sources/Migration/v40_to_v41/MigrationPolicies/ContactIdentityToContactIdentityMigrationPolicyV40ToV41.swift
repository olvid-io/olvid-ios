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
import ObvTypes
import ObvEncoder
import ObvCrypto
import ObvMetaManager
import OlvidUtils


final class ContactIdentityToContactIdentityMigrationPolicyV40ToV41: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "ObvEngineMigrationV40ToV41"
    static let debugPrintPrefix = "[\(errorDomain)][ContactIdentityToContactIdentityMigrationPolicyV40ToV41]"

    // Tested
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "ContactIdentity",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: Self.errorDomain)
        defer {
            manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
        }

        // We need to set a value for the new mandatory 'ownedIdentityIdentity' attribute.
        // We read its value from the `ownedIdentity` relationship of the source instance
        
        guard let ownedIdentityObject = sInstance.value(forKey: "ownedIdentity") as? NSManagedObject else {
            assertionFailure()
            throw Self.makeError(message: "Could not read the value of the owned identity")
        }
                
        let transformer = ObvCryptoIdentityTransformer()
        guard let value = ownedIdentityObject.value(forKey: "cryptoIdentity"),
                let ownedIdentityIdentity = transformer.transformedValue(value) as? Data,
        let ownedCryptoIdentity = ObvCryptoIdentity(from: ownedIdentityIdentity)  else {
            assertionFailure()
            throw Self.makeError(message: "Could not read the value of the owned identity's identity as Data")
        }
        
        dInstance.setValue(ownedCryptoIdentity.getIdentity(), forKey: "ownedIdentityIdentity")
        
    }
    
}
