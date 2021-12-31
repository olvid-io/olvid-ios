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

import CoreData

final class TypeSafeManagedObjectID<T>: Hashable {
    let objectID: NSManagedObjectID
    init(objectID: NSManagedObjectID) {
        self.objectID = objectID
    }
    
    func uriRepresentation() -> TypeSafeURL<T> {
        return TypeSafeURL(url: objectID.uriRepresentation())
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(objectID)
    }

    static func == (lhs: TypeSafeManagedObjectID<T>, rhs: TypeSafeManagedObjectID<T>) -> Bool {
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

struct TypeSafeURL<T>: Hashable {
    let url: URL

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }

    var path: String {
        url.path
    }

    var absoluteString: String {
        url.absoluteString
    }
}
