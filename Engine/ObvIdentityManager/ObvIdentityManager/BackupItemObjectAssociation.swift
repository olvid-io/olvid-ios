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
import ObvTypes
import OlvidUtils

/// This class is used when restoring a backup
struct BackupItemObjectAssociations {

    private var association = [Int: NSManagedObjectID]()
        
    private static let errorDomain = String(describing: Self.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    mutating func associate<T: Hashable>(_ object: NSManagedObject, to hashable: T) throws {
        guard !association.keys.contains(hashable.hashValue) else {
            throw BackupItemObjectAssociations.makeError(message: "Key already exists")
        }
        association[hashable.hashValue] = object.objectID
    }

    func getObject<T: NSManagedObject, G: Hashable>(associatedTo hashable: G, within obvContext: ObvContext) throws -> T {
        guard let objectID = association[hashable.hashValue] else {
            throw BackupItemObjectAssociations.makeError(message: "Object not found")
        }
        let object = try obvContext.existingObject(with: objectID)
        guard let typedObject = object as? T else {
            throw BackupItemObjectAssociations.makeError(message: "Could not cast object")
        }
        return typedObject
    }
    
    func getObjectIfPresent<T: NSManagedObject, G: Hashable>(associatedTo hashableOrNil: G?, within obvContext: ObvContext) throws -> T? {
        guard let hashable = hashableOrNil else {
            return nil
        }
        return try getObject(associatedTo: hashable, within: obvContext)
    }
}
