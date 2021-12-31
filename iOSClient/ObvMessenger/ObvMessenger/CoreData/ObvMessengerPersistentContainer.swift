/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

final class ObvMessengerPersistentContainer: NSPersistentContainer {
    
    override class func defaultDirectoryURL() -> URL {
        if !FileManager.default.fileExists(atPath: ObvMessengerConstants.containerURL.forDatabase.absoluteString) {
            try! FileManager.default.createDirectory(at: ObvMessengerConstants.containerURL.forDatabase, withIntermediateDirectories: true)
        }
        return ObvMessengerConstants.containerURL.forDatabase
    }
    
    override var persistentStoreDescriptions: [NSPersistentStoreDescription] {
        get {
            let descriptions = super.persistentStoreDescriptions
            for description in descriptions {
                // Turn on persistent history tracking
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
                // Turn on remote change notifications
                description.setOption(true as NSNumber, forKey: "NSPersistentStoreRemoteChangeNotificationOptionKey")
                // Prevent lightweight migration
                description.shouldMigrateStoreAutomatically = false
                description.shouldInferMappingModelAutomatically = false
                // Secure Delete
                description.setValue("TRUE" as NSObject, forPragmaNamed: "secure_delete")
            }
            return descriptions
        }
        set {
            super.persistentStoreDescriptions = newValue
        }
    }
    
}
