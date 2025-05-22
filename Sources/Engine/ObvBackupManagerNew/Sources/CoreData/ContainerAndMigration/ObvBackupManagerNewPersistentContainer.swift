/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


final class ObvBackupManagerNewPersistentContainer: NSPersistentContainer, @unchecked Sendable {
    
    static var containerURL: URL?
    
    override class func defaultDirectoryURL() -> URL {
        return containerURL!
    }
    
    
    override var persistentStoreDescriptions: [NSPersistentStoreDescription] {
        get {
            let descriptions = super.persistentStoreDescriptions
            for description in descriptions {
                // Turn on remote change notifications
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                // Turn on persistent history tracking
                // description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
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
    
    
    static func excludeStoresFromBackup(description: NSPersistentStoreDescription) {
        guard let persistentStoreURL = description.url else { fatalError("No URL found within description") }
        guard FileManager.default.fileExists(atPath: persistentStoreURL.path) else { fatalError("Persistent store cannot be found at \(persistentStoreURL.path)") }
        do {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            var mutableURL = persistentStoreURL
            try mutableURL.setResourceValues(resourceValues)
        } catch let error as NSError {
            fatalError("Error excluding \(persistentStoreURL) from backup \(error.localizedDescription)")
        }
        debugPrint("The following engine persistent store was excluded from iCloud and iTunes backup: \(persistentStoreURL.path)")
    }

}
