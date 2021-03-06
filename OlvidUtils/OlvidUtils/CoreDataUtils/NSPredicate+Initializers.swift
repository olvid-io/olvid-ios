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


/// See https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Predicates/Articles/pCreating.html
public extension NSPredicate {
    
    convenience init<T: RawRepresentable>(_ key: T, EqualToUrl url: URL) where T.RawValue == String {
        self.init(format: "%K == %@", key.rawValue, url as NSURL)
    }
    
    convenience init<T: RawRepresentable>(_ key: T, EqualToData data: Data) where T.RawValue == String {
        self.init(key.rawValue, EqualToData: data)
    }

    convenience init(_ key: String, EqualToData data: Data) {
        self.init(format: "%K == %@", key, data as NSData)
    }

    convenience init<T: RawRepresentable>(_ key: T, EqualToUuid uuid: UUID) where T.RawValue == String {
        self.init(format: "%K == %@", key.rawValue, uuid as NSUUID)
    }

    convenience init<T: RawRepresentable>(_ key: T, EqualToInt int: Int) where T.RawValue == String {
        self.init(format: "%K == %d", key.rawValue, int)
    }

    convenience init<T: RawRepresentable>(_ key: T, EqualToString string: String) where T.RawValue == String {
        self.init(format: "%K == %@", key.rawValue, string as NSString)
    }

    convenience init<T: RawRepresentable>(_ key: T, DistinctFromInt int: Int) where T.RawValue == String {
        self.init(format: "%K != %d", key.rawValue, int)
    }

    convenience init<T: RawRepresentable>(withNonNilValueForKey key: T) where T.RawValue == String {
        self.init(format: "%K != NIL", key.rawValue)
    }

    convenience init<T: RawRepresentable>(withNilValueForKey key: T) where T.RawValue == String {
        self.init(format: "%K == NIL", key.rawValue)
    }
    
    convenience init<T: RawRepresentable>(_ key: T, earlierThan date: Date) where T.RawValue == String {
        self.init(format: "%K < %@", key.rawValue, date as NSDate)
    }

    convenience init<T: RawRepresentable>(_ key: T, equalToDate date: Date) where T.RawValue == String {
        self.init(format: "%K == %@", key.rawValue, date as NSDate)
    }

    convenience init<T: RawRepresentable>(_ key: T, equalTo object: NSManagedObject) where T.RawValue == String {
        self.init(format: "%K == %@", key.rawValue, object)
    }

    convenience init<T: RawRepresentable>(_ key: T, is bool: Bool) where T.RawValue == String {
        self.init(format: bool ? "%K == YES" : "%K == NO", key.rawValue)
    }

    convenience init(withEntity entity: NSEntityDescription) {
        self.init(format: "entity = %@", entity)
    }
}
