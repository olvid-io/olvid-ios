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
import ObvUICoreData
import ObvSettings


final class ObvMessengerPersistentContainer: NSPersistentContainer {
    
    override class func defaultDirectoryURL() -> URL {
        let url = ObvUICoreDataConstants.ContainerURL.forDatabase.url
        if !FileManager.default.fileExists(atPath: url.absoluteString) {
            try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    override var persistentStoreDescriptions: [NSPersistentStoreDescription] {
        get {
            let descriptions = super.persistentStoreDescriptions
            for description in descriptions {
                // Turn on remote change notifications
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                // Turn on persistent history tracking
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
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
