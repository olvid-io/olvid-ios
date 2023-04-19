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
import OlvidUtils


@objc(PersistedMessageExpiration)
class PersistedMessageExpiration: NSManagedObject, ObvErrorMaker {
    
    private static let entityName = "PersistedMessageExpiration"
    static let errorDomain = "PersistedMessageExpiration"
    
    // MARK: Attributes
    
    @NSManaged private(set) var expirationDate: Date
    @NSManaged private(set) var creationTimestamp: Date
    
    // MARK: - Initializer
    
    convenience init?(duration: TimeInterval, relativeTo now: Date, entityName: String, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.expirationDate = Date(timeInterval: duration, since: now)
        self.creationTimestamp = now
    }
    
}


extension PersistedMessageExpiration {
    
    struct Predicate {
        enum Key: String {
            case expirationDate = "expirationDate"
            case creationTimestamp = "creationTimestamp"
        }
        static func withExpirationDateLaterThan(_ date: Date) -> NSPredicate {
            NSPredicate(Key.expirationDate, laterThan: date)
        }
    }

    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageExpiration> {
        return NSFetchRequest<PersistedMessageExpiration>(entityName: PersistedMessageExpiration.entityName)
    }

    
    static func get(with: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedMessageExpiration {
        guard let object = try context.existingObject(with: with) as? PersistedMessageExpiration else {
            throw Self.makeError(message: "Could not find object")
        }
        return object
    }

    
    static func getEarliestExpiration(laterThan date: Date, within context: NSManagedObjectContext) throws -> PersistedMessageExpiration? {
        let request: NSFetchRequest<PersistedMessageExpiration> = PersistedMessageExpiration.fetchRequest()
        request.predicate = Predicate.withExpirationDateLaterThan(date)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.expirationDate.rawValue, ascending: true)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    var initialExpirationDuration: TimeInterval {
        expirationDate.timeIntervalSince(creationTimestamp)
    }
    
    
    override func didSave() {
        super.didSave()
        if self.isInserted {
            ObvMessengerCoreDataNotification.newMessageExpiration(expirationDate: expirationDate)
                .postOnDispatchQueue()
        }
    }

}
