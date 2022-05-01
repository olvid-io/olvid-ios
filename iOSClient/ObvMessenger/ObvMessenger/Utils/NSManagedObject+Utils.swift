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

extension NSManagedObject {

    /// This method allows to force the persistent store backing the shared ObvStack to refresh a specific persisted object.
    /// In prtactice, this is used when the share extension modifies the database while the main app is in the background. In that case,
    /// we want to make the app persistent store aware of these new objects. This methods allows to do just that, by forcing a "deep" refresh
    /// of the object into the view context.
    static func refreshObjectInPersistentStore(for objectID: NSManagedObjectID, with entityName: String) throws {
        let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: entityName)
        request.predicate = NSPredicate(format: "self == %@", objectID)
        request.fetchLimit = 1
        request.returnsObjectsAsFaults = false

        if #available(iOS 15.0, *) {
            try ObvStack.shared.viewContext.performAndWait {
                guard let object = try ObvStack.shared.viewContext.fetch(request).first else { return }
                ObvStack.shared.viewContext.refresh(object, mergeChanges: true)
            }

        } else {
            ObvStack.shared.viewContext.performAndWait {
                guard let object = try? ObvStack.shared.viewContext.fetch(request).first else { return }
                ObvStack.shared.viewContext.refresh(object, mergeChanges: true)
            }
        }
    }


}
