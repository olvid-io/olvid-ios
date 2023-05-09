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

import CoreData

public final class TypeSafeManagedObjectID<T>: Hashable {
    public let objectID: NSManagedObjectID
    public init(objectID: NSManagedObjectID) {
        self.objectID = objectID
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectID)
    }

    public static func == (lhs: TypeSafeManagedObjectID<T>, rhs: TypeSafeManagedObjectID<T>) -> Bool {
        lhs.objectID == rhs.objectID
    }

    var debugDescription: String {
        objectID.debugDescription
    }
    
    var entityName: String? {
        objectID.entity.name
    }
    
}

protocol TypeWithObjectID {
    var objectID: NSManagedObjectID { get }
}

extension TypeWithObjectID {
    var typedObjectID: TypeSafeManagedObjectID<Self> {
        TypeSafeManagedObjectID(objectID: objectID)
    }
}

extension NSManagedObject: TypeWithObjectID {}


// MARK: - ObvManagedObjectPermanentID

/// Defines a permanent identifier for `NSManagedObject` subclasses.
///
/// This type is used instead of Core Data's `NSManagedObjectID` when we need an identifier that persists between Core Data migrations.
/// This type is strongly typed (thanks to a "phantom" type) and can be represented as a String (i.e., it conforms to `CustomStringConvertible`).
///
/// When `T` conforms to `ObvIdentifiableManagedObject`, this type also conforms to `LosslessStringConvertible`.
/// We cannot explicitely indicate the `LosslessStringConvertible` conformance though, but it trivial to declare conformance for specific types as follows:
/// ```
/// extension ObvManagedObjectPermanentID<MySpecificObvIdentifiableManagedObject>: LosslessStringConvertible {}
/// ```
struct ObvManagedObjectPermanentID<T: NSManagedObject>: CustomStringConvertible, Equatable, Hashable {

    let entityName: String
    let uuid: UUID
    
    init(entityName: String, uuid: UUID) {
        self.entityName = entityName
        self.uuid = uuid
    }
    
    var description: String {
        [entityName, uuid.uuidString].joined(separator: "/")
    }
    
    init?(_ description: String, expectedEntityName: String) {
        let splits = description.split(separator: "/", maxSplits: 1)
        guard splits.count == 2 else { assertionFailure(); return nil }
        guard splits[0] == expectedEntityName else { assertionFailure(); return nil }
        guard let uuid = UUID(uuidString: String(splits[1])) else { assertionFailure(); return nil }
        self.init(entityName: expectedEntityName, uuid: uuid)
    }

}


/// Protocol allowing the `ObvManagedObjectPermanentID` type to conform to `LosslessStringConvertible`.
protocol ObvIdentifiableManagedObject: NSManagedObject {
    static var entityName: String { get }
    var objectPermanentID: ObvManagedObjectPermanentID<Self> { get }
}


extension ObvManagedObjectPermanentID: LosslessStringConvertible where T: ObvIdentifiableManagedObject {
    
    init(uuid: UUID) {
        self.entityName = T.entityName
        self.uuid = uuid
    }
    
    init?(_ description: String) {
        self.init(description, expectedEntityName: T.entityName)
    }

}
