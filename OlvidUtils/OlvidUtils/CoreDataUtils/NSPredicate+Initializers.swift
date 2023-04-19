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
        self.init(key.rawValue, EqualToUuid: uuid)
    }

    convenience init(_ rawKey: String, EqualToUuid uuid: UUID) {
        self.init(format: "%K == %@", rawKey, uuid as NSUUID)
    }

    convenience init<T: RawRepresentable>(_ key: T, EqualToInt int: Int) where T.RawValue == String {
        self.init(key.rawValue, EqualToInt: int)
    }

    convenience init(_ rawKey: String, EqualToInt int: Int) {
        self.init(format: "%K == %d", rawKey, int)
    }

    convenience init<T: RawRepresentable>(_ key: T, LessThanInt int: Int) where T.RawValue == String {
        self.init(format: "%K < %d", key.rawValue, int)
    }

    convenience init<T: RawRepresentable>(_ key: T, LargerThanInt int: Int) where T.RawValue == String {
        self.init(format: "%K > %d", key.rawValue, int)
    }

    convenience init<T: RawRepresentable>(_ key: T, largerThanOrEqualToInt int: Int) where T.RawValue == String {
        self.init(format: "%K >= %d", key.rawValue, int)
    }

    convenience init<T: RawRepresentable>(_ key: T, LargerThanDouble double: Double) where T.RawValue == String {
        self.init(format: "%K > %lf", key.rawValue, double)
    }

    convenience init<T: RawRepresentable>(_ key: T, lessThanDouble double: Double) where T.RawValue == String {
        self.init(format: "%K < %lf", key.rawValue, double)
    }

    convenience init<T: RawRepresentable>(_ key: T, EqualToString string: String) where T.RawValue == String {
        self.init(format: "%K == %@", key.rawValue, string as NSString)
    }
    
    convenience init<T: RawRepresentable>(_ key: T, NotEqualToString string: String) where T.RawValue == String {
        self.init(format: "%K != %@", key.rawValue, string as NSString)
    }
    
    convenience init<T: RawRepresentable>(_ key: T, DistinctFromInt int: Int) where T.RawValue == String {
        self.init(format: "%K != %d", key.rawValue, int)
    }
    
    convenience init<T: RawRepresentable>(withNonNilValueForKey key: T) where T.RawValue == String {
        self.init(format: "%K != NIL", key.rawValue)
    }
    
    convenience init<T: RawRepresentable>(withNilValueForKey key: T) where T.RawValue == String {
        self.init(withNilValueForRawKey: key.rawValue)
    }

    convenience init(withNilValueForRawKey rawKey: String) {
        self.init(format: "%K == NIL", rawKey)
    }

    convenience init<T: RawRepresentable>(_ key: T, earlierThan date: Date) where T.RawValue == String {
        self.init(key.rawValue, earlierThan: date)
    }

    convenience init(_ rawKey: String, earlierThan date: Date) {
        self.init(format: "%K < %@", rawKey, date as NSDate)
    }

    convenience init<T: RawRepresentable>(_ key: T, laterThan date: Date) where T.RawValue == String {
        self.init(format: "%K > %@", key.rawValue, date as NSDate)
    }
    
    convenience init<T: RawRepresentable>(_ key: T, equalToDate date: Date) where T.RawValue == String {
        self.init(format: "%K == %@", key.rawValue, date as NSDate)
    }
    
    convenience init<T: RawRepresentable>(_ key: T, equalTo object: NSManagedObject) where T.RawValue == String {
        self.init(key.rawValue, equalTo: object)
    }

    convenience init(_ rawKey: String, equalTo object: NSManagedObject) {
        self.init(format: "%K == %@", rawKey, object)
    }

    convenience init<T: RawRepresentable>(_ key: T, equalToObjectWithObjectID objectID: NSManagedObjectID) where T.RawValue == String {
        self.init(format: "%K == %@", key.rawValue, objectID)
    }

    convenience init<T: RawRepresentable>(_ key: T, contains object: NSManagedObject) where T.RawValue == String {
        self.init(format: "%@ IN %K", object, key.rawValue)
    }

    convenience init<T: RawRepresentable>(_ key: T, is bool: Bool) where T.RawValue == String {
        self.init(format: bool ? "%K == YES" : "%K == NO", key.rawValue)
    }
    
    convenience init(withEntity entity: NSEntityDescription) {
        self.init(format: "entity = %@", entity)
    }
    
    convenience init(withEntityDistinctFrom entity: NSEntityDescription) {
        self.init(format: "entity != %@", entity)
    }
    
    convenience init(withObjectID objectID: NSManagedObjectID) {
        self.init(format: "SELF == %@", objectID)
    }
    
    convenience init<T: RawRepresentable>(withZeroCountForKey key: T) where T.RawValue == String {
        self.init(format: "%K.@count == 0", key.rawValue)
    }
    
    convenience init<T: RawRepresentable>(withStrictlyPositiveCountForKey key: T) where T.RawValue == String {
        self.init(format: "%K.@count > 0", key.rawValue)
    }
    
}
