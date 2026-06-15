/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import ObvAppCoreConstants


final class PersistedObvMessageToPersistedObvMessageV3ToV4: NSEntityMigrationPolicy {
    
    private static let errorDomain = "ObvUserNotificationsDataModelMigration"
    private static let debugPrintPrefix = "[\(errorDomain)][PersistedObvMessageToPersistedObvMessageV3ToV4]"

    let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "PersistedObvMessageToPersistedObvMessageV3ToV4")
    
    override func createDestinationInstances(forSource sInstance: NSManagedObject, in mapping: NSEntityMapping, manager: NSMigrationManager) throws {
        
        do {
            
            debugPrint("\(Self.debugPrintPrefix) createDestinationInstances starts")
            defer { debugPrint("\(Self.debugPrintPrefix) createDestinationInstances ends") }
            
            let dInstance = try initializeDestinationInstance(forEntityName: "PersistedObvMessage",
                                                              forSource: sInstance,
                                                              in: mapping,
                                                              manager: manager,
                                                              errorDomain: Self.errorDomain)

            // This migration is special in the sense that we may drop certain items.
            // We drop all `PersistedObvMessage` that have 1 or more expected attachments.
            // We must drop these, as we no longer have the required information to properly set rawAttachmentMetadatas
            // As a consequence we don't always associated dInstance to sInstance
            
            guard let expectedAttachmentsCount = sInstance.value(forKey: "expectedAttachmentsCount") as? Int else {
                assertionFailure()
                return
            }
            
            if expectedAttachmentsCount > 0 {
                // Drop the item
                return
            } else {
                dInstance.setValue(nil, forKey: "rawAttachmentMetadatas")
                manager.associate(sourceInstance: sInstance, withDestinationInstance: dInstance, for: mapping)
            }

        } catch {
            assertionFailure()
            // Don't throw, just drop the PersistedObvMessage
            //throw error
            return
        }
        
    }


}
