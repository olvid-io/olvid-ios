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

fileprivate let errorDomain = "ObvEngineMigrationV17ToV18"
fileprivate let debugPrintPrefix = "[\(errorDomain)][InboxAttachmentToInboxAttachmentMigrationPolicyV17ToV18]"


final class InboxAttachmentToInboxAttachmentMigrationPolicyV17ToV18: NSEntityMigrationPolicy {
    
    
    /// This migration allows to store the owned identity within the keychain
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        debugPrint("\(debugPrintPrefix) createDestinationInstances starts")
        defer {
            debugPrint("\(debugPrintPrefix) createDestinationInstances ends")
        }
        
        let dInstance = try initializeDestinationInstance(forEntityName: "InboxAttachment",
                                                          forSource: sInstance,
                                                          in: mapping,
                                                          manager: manager,
                                                          errorDomain: errorDomain)
        
        /* The objective is to map the Boolean values `downloadPaused`, `isDownloaded`, `markedForDeletion` onto the new `rawStatus` attribute.
         * This attribute is an Integer that can take the following values (in v18) :
         * paused = 0
         * resumed = 1
         * downloaded = 2
         * cancelledByServer = 3
         * markedForDeletion = 4
         * We assume that the mapped instances are not cancelled by the server.
         */

        // Step 1: Find the current values of the Booleans
        
        guard let downloadPaused = sInstance.value(forKey: "downloadPaused") as? Bool else {
            let message = "Could not get the downloadPaused value"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }

        guard let isDownloaded = sInstance.value(forKey: "isDownloaded") as? Bool else {
            let message = "Could not get the isDownloaded value"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }

        guard let markedForDeletion = sInstance.value(forKey: "markedForDeletion") as? Bool else {
            let message = "Could not get the markedForDeletion value"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: errorDomain, code: 0, userInfo: userInfo)
        }

        // Step 2: Map the Boolean values onto the appropriate status
        
        let rawStatus: Int
        if markedForDeletion {
            rawStatus = Status.markedForDeletion.rawValue
        } else if isDownloaded {
            rawStatus = Status.downloaded.rawValue
        } else if downloadPaused {
            rawStatus = Status.paused.rawValue
        } else {
            rawStatus = Status.resumed.rawValue
        }
        
        // Step 3: Set the rawStatus on the destination instance
        
        dInstance.setValue(rawStatus, forKey: "rawStatus")
        
        // The migration manager needs to know the connection between the source object, the newly created destination object, and the mapping.
        
        manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
        
    }
    
    enum Status: Int {
        case paused = 0
        case resumed = 1
        case downloaded = 2
        case cancelledByServer = 3
        case markedForDeletion = 4
    }
}
