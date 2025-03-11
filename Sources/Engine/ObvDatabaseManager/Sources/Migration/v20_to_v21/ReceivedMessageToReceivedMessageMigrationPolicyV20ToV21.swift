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
import ObvCrypto

fileprivate let errorDomain = "ObvEngineMigrationV20ToV21"
fileprivate let debugPrintPrefix = "[\(errorDomain)][ReceivedMessageToReceivedMessageMigrationPolicyV20ToV21]"

final class ReceivedMessageToReceivedMessageMigrationPolicyV20ToV21: NSEntityMigrationPolicy {
    
    private func makeError(message: String) -> Error {
        let message = [debugPrintPrefix, message].joined(separator: " ")
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    override func begin(_ mapping: NSEntityMapping, with manager: NSMigrationManager) throws {
        try UtilsForMigrationV20ToV21.shared.enforceV21ConstraintsOnV20(manager: manager)
    }

    // Tested
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "ReceivedMessage",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)

        // Get the messageId (raw UID) from the source instance and use it to set the rawMessageIdUid (Data) of the destination instance

        guard let messageUid = sInstance.value(forKey: "messageId") as? UID else {
            throw makeError(message: "Could not get the messageId value")
        }

        let rawMessageIdUid = messageUid.raw

        dInstance.setValue(rawMessageIdUid, forKey: "rawMessageIdUid")

        // Get the unique owned identity raw identity and set the rawMessageIdOwnedIdentity of the destination instance

        let ownedIdentityIdentity = try UtilsForMigrationV20ToV21.shared.findOwnedIdentityRawIdentityInSourceContext(manager: manager)
        dInstance.setValue(ownedIdentityIdentity, forKey: "rawMessageIdOwnedIdentity")

        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)

    }
    
}
