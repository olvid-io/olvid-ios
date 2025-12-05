/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvMetaManager

@objc(CachedWellKnown)
final class CachedWellKnown: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "CachedWellKnown"
    
    // MARK: Attributes
    
    @NSManaged private(set) var serverURL: URL // Primary key
    @NSManaged private(set) var wellKnownData: Data // bytes sent by the server
    @NSManaged private(set) var downloadTimestamp: Date
    
    var wellKnownJSON: WellKnownJSON? {
        return try? WellKnownJSON.decode(wellKnownData)
    }
    
    // MARK: - Initializer
    
    private convenience init?(serverURL: URL, wellKnownData: Data, downloadTimestamp: Date, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: CachedWellKnown.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.serverURL = serverURL
        self.wellKnownData = wellKnownData
        self.downloadTimestamp = downloadTimestamp
        guard self.wellKnownJSON != nil else { return nil }
    }
    
    
    static func createCachedWellKnown(serverURL: URL, wellKnownData: Data, downloadTimestamp: Date, within context: NSManagedObjectContext) -> Self? {
        let newCachedWellKnown = Self.init(serverURL: serverURL, wellKnownData: wellKnownData, downloadTimestamp: downloadTimestamp, within: context)
        return newCachedWellKnown
    }
    
    
    func deleteCachedWellKnown() throws {
        guard let managedObjectContext else {
            throw ObvError.contextIsNil
        }
        managedObjectContext.delete(self)
    }
    
    func update(with wellKnownData: Data) {
        self.downloadTimestamp = Date.now
        self.wellKnownData = wellKnownData
    }
    
}
    
// MARK: - Queries

extension CachedWellKnown {
    
    private struct Predicate {
        
        enum Key: String {
            // Attributes
            case serverURL = "serverURL"
            case wellKnownData = "wellKnownData"
            case downloadTimestamp = "downloadTimestamp"
        }
        
        static func withServerURL(_ serverURL: URL) -> NSPredicate {
            NSPredicate(Key.serverURL, EqualToUrl: serverURL)
        }
        
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<CachedWellKnown> {
        return NSFetchRequest<CachedWellKnown>(entityName: CachedWellKnown.entityName)
    }


    static func getAllCachedWellKnown(within context: NSManagedObjectContext) throws -> [CachedWellKnown] {
        let request: NSFetchRequest<CachedWellKnown> = CachedWellKnown.fetchRequest()
        request.fetchBatchSize = 10
        return try context.fetch(request)
    }


    static func getCachedWellKnown(for server: URL, within context: NSManagedObjectContext) throws -> CachedWellKnown? {
        let request: NSFetchRequest<CachedWellKnown> = CachedWellKnown.fetchRequest()
        request.predicate = Predicate.withServerURL(server)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
}


// MARK: - Errors

extension CachedWellKnown {
    
    enum ObvError: Error {
        case contextIsNil
    }
    
}
