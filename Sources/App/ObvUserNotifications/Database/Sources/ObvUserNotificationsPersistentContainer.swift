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
                // This store lives in the App Group and is opened by THREE separate processes — the
                // Notification Service Extension (writes pending rows), the main app (drains/deletes
                // them), and the Intents extension (reads them). Each process has its own coordinator
                // and row cache; the in-process `NSManagedObjectContextDidSave` merging that
                // CoreDataStack relies on never crosses process boundaries. Persistent history
                // tracking + remote-change notifications are the only supported way for one process
                // to learn about another's committed writes and refresh its stale row cache —
                // otherwise a long-lived reader (the Intents extension) keeps re-surfacing pending
                // messages the app has already drained.
                //
                // Safe to enable on the existing production store: it adds Core Data's history tables
                // lazily on the next write (no model migration, no data loss), and every process
                // opens this store through this single container class, so the options are always
                // consistent. Two requirements come with it:
                //   1. Once shipped enabled, KEEP it enabled — disabling history tracking on a store
                //      that had it is the unsupported direction.
                //   2. History must be pruned or it grows unbounded — see the launch-time prune in
                //      AppMainManager (ObvPersistentHistoryMerger.pruneHistory).
                description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
                description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
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
