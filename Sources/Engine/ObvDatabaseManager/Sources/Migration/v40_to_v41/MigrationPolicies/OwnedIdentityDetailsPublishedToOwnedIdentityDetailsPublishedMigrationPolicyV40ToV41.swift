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
import ObvCrypto
import ObvEncoder
import OlvidUtils


final class OwnedIdentityDetailsPublishedToOwnedIdentityDetailsPublishedMigrationPolicyV40ToV41: NSEntityMigrationPolicy, ObvErrorMaker {
    
    static let errorDomain = "ObvEngineMigrationV40ToV41"
    static let debugPrintPrefix = "[\(errorDomain)][OwnedIdentityDetailsPublishedToOwnedIdentityDetailsPublishedMigrationPolicyV40ToV41]"

    // Tested
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "OwnedIdentityDetailsPublished",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: Self.errorDomain)
        defer {
            manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
        }

        // The 'photoServerLabel' String attribute is replaced by the 'rawPhotoServerLabel' attribute of type Binary.

        guard let optionalLabelAsString = sInstance.value(forKey: "photoServerLabel") as? String? else {
            throw Self.makeError(message: "Could not read the label attribute of a OwnedIdentityDetailsPublished entity")
        }
        
        if let label = optionalLabelAsString {
            if let uid = UID(hexString: label) {
                dInstance.setValue(uid.raw, forKey: "rawPhotoServerLabel")
            } else if let labelAsData = Data(base64Encoded: label), let uid = UID(uid: labelAsData) {
                dInstance.setValue(uid.raw, forKey: "rawPhotoServerLabel")
            } else {
                throw Self.makeError(message: "Could not turn the label attribute of a OwnedIdentityDetailsPublished entity into an UID")
            }
        }

    }
    
}
