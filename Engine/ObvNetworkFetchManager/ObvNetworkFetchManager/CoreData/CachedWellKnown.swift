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

import Foundation
import CoreData
import ObvTypes
import ObvMetaManager
import OlvidUtils

@objc(CachedWellKnown)
final class CachedWellKnown: NSManagedObject, ObvManagedObject {

    // MARK: Internal constants

    private static let entityName = "CachedWellKnown"
    static let serverKey = "serverURL"

    // MARK: Attributes

    @NSManaged private(set) var serverURL: URL
    @NSManaged private(set) var wellKnownData: Data /// bytes sent by the server
    @NSManaged private(set) var downloadTimestamp: Date

    var wellKnownJSON: WellKnownJSON? {
        return try? WellKnownJSON.decode(wellKnownData)
    }
    
    var obvContext: ObvContext?

    // MARK: - Initializer

    convenience init?(serverURL: URL, wellKnownData: Data, downloadTimestamp: Date, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: CachedWellKnown.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.serverURL = serverURL
        self.wellKnownData = wellKnownData
        self.downloadTimestamp = downloadTimestamp
        guard self.wellKnownJSON != nil else { return nil }
    }

    func update(with wellKnownData: Data) {
        self.downloadTimestamp = Date()
        self.wellKnownData = wellKnownData
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<CachedWellKnown> {
        return NSFetchRequest<CachedWellKnown>(entityName: CachedWellKnown.entityName)
    }


    static func getAllCachedWellKnown(within context: ObvContext) throws -> [CachedWellKnown] {
        let request: NSFetchRequest<CachedWellKnown> = CachedWellKnown.fetchRequest()
        return try context.fetch(request)
    }

    private struct Predicate {
        static func withURL(_ serverURL: URL) -> NSPredicate {
            NSPredicate(format: "%K == %@", CachedWellKnown.serverKey, serverURL as CVarArg)
        }
    }

    static func getCachedWellKnown(for server: URL, within context: ObvContext) throws -> CachedWellKnown? {
        let request: NSFetchRequest<CachedWellKnown> = CachedWellKnown.fetchRequest()
        request.predicate = Predicate.withURL(server)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}
