/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvAppCoreConstants


public final class ObvUserNotificationsPersistentContainer: NSPersistentContainer, @unchecked Sendable {
    
    public override class func defaultDirectoryURL() -> URL {
        let url = ObvAppCoreConstants.securityApplicationGroupURL
            .appendingPathComponent("ObvUserNotifications", isDirectory: true)
            .appendingPathComponent("Database", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.absoluteString) {
            try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    public override var persistentStoreDescriptions: [NSPersistentStoreDescription] {
        get {
            let descriptions = super.persistentStoreDescriptions
            for description in descriptions {
                // Prevent automatic migrations
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
