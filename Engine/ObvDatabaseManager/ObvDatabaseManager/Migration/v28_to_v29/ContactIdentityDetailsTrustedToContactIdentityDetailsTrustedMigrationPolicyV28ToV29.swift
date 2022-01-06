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

fileprivate let errorDomain = "ObvEngineMigrationV28ToV29"
fileprivate let debugPrintPrefix = "[\(errorDomain)][ContactIdentityDetailsTrustedToContactIdentityDetailsTrustedMigrationPolicyV28ToV29]"

final class ContactIdentityDetailsTrustedToContactIdentityDetailsTrustedMigrationPolicyV28ToV29: NSEntityMigrationPolicy {
    
    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "ContactIdentityDetailsTrusted",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)
        
        // Get the contact associated with the source instance, then find the published details in the source contact, if they exist.
        // In that case, we look for existing server key and label and set them on the destination instance.
        if let sContactIdentity = sInstance.value(forKey: "contactIdentity") as? NSManagedObject,
           let sPublishedIdentityDetails = sContactIdentity.value(forKey: "publishedIdentityDetails") as? NSManagedObject,
           let sPhotoServerLabel = sPublishedIdentityDetails.value(forKey: "photoServerLabel") as? String,
           let sPhotoServerKeyEncoded = sPublishedIdentityDetails.value(forKey: "photoServerKeyEncoded") as? Data {
            
            dInstance.setValue(sPhotoServerLabel, forKey: "photoServerLabel")
            dInstance.setValue(sPhotoServerKeyEncoded, forKey: "photoServerKeyEncoded")

        }
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.

        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
        
}
