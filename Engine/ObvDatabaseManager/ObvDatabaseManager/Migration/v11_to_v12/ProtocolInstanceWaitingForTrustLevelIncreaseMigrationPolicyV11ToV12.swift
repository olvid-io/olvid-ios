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

fileprivate let errorDomain = "ObvEngineMigrationV11ToV12"
fileprivate let debugPrintPrefix = "[\(errorDomain)][ProtocolInstanceWaitingForTrustLevelIncreaseMigrationPolicyV11ToV12]"


final class ProtocolInstanceWaitingForTrustLevelIncreaseMigrationPolicyV11ToV12: NSEntityMigrationPolicy {
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        // We do migrate instances that have a relationship with a protocol instance of the GroupCreation protocol which is deprecated
        
        guard let protocolInstance = sInstance.value(forKey: "protocolInstance") as? NSObject else {
            let message = "Could not get associated protocol instance"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }

        guard let cryptoProtocolRawId = protocolInstance.value(forKey: "cryptoProtocolRawId") as? Int else {
            let message = "Could not get protocol raw id"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }
        
        guard cryptoProtocolRawId != 5 else {
            return
        }

        let dInstance = try initializeDestinationInstance(forEntityName: "ProtocolInstanceWaitingForTrustLevelIncrease",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
        
    }
}
