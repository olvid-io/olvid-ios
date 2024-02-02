/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

/// This type is used when restoring a snapshot
struct SnapshotNodeManagedObjectAssociations {

    private var association = [String: NSManagedObjectID]()
        
    mutating func associate<T: Identifiable<String>>(_ object: NSManagedObject, to hashable: T) throws {
        guard !association.keys.contains(hashable.id) else {
            throw ObvError.theKeyAlreadyExists
        }
        association[hashable.id] = object.objectID
    }


    func getObject<T: NSManagedObject, G: Identifiable<String>>(associatedTo hashable: G, within obvContext: ObvContext) throws -> T {
        return try getObject(associatedTo: hashable, within: obvContext.context)
    }
    
    
    func getObject<T: NSManagedObject, G: Identifiable<String>>(associatedTo hashable: G, within context: NSManagedObjectContext) throws -> T {
        guard let objectID = association[hashable.id] else {
            throw ObvError.objectNotFound
        }
        let object = try context.existingObject(with: objectID)
        guard let typedObject = object as? T else {
            throw ObvError.couldNotCastObject
        }
        return typedObject
    }


    func getObjectIfPresent<T: NSManagedObject, G: Identifiable<String>>(associatedTo hashableOrNil: G?, within obvContext: ObvContext) throws -> T? {
        return try getObjectIfPresent(associatedTo: hashableOrNil, within: obvContext.context)
    }

    
    func getObjectIfPresent<T: NSManagedObject, G: Identifiable<String>>(associatedTo hashableOrNil: G?, within context: NSManagedObjectContext) throws -> T? {
        guard let hashable = hashableOrNil else {
            return nil
        }
        return try getObject(associatedTo: hashable, within: context)
    }


    enum ObvError: Error {
        case theKeyAlreadyExists
        case objectNotFound
        case couldNotCastObject
        case contextNotFound
    }
    
}
