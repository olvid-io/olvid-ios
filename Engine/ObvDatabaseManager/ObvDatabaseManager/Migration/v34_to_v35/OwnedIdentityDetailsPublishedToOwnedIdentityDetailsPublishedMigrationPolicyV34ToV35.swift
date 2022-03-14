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

fileprivate let errorDomain = "ObvEngineMigrationV34ToV35"
fileprivate let debugPrintPrefix = "[\(errorDomain)][OwnedIdentityDetailsPublishedToOwnedIdentityDetailsPublishedMigrationPolicyV34ToV35]"

final class OwnedIdentityDetailsPublishedToOwnedIdentityDetailsPublishedMigrationPolicyV34ToV35: NSEntityMigrationPolicy {
    
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
        
        let dInstance = try initializeDestinationInstance(forEntityName: "OwnedIdentityDetailsPublished",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)
        defer {
            manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
        }
        
        // Get the current photoURL, and only keep the filename
        if let photoURL = sInstance.value(forKey: "photoURL") as? URL {
            let photoFilename = photoURL.lastPathComponent
            dInstance.setValue(photoFilename, forKey: "photoFilename")
        }
        
    }
        
}
