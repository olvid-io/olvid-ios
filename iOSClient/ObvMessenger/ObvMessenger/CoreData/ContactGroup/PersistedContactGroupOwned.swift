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
import ObvEngine


@objc(PersistedContactGroupOwned)
final class PersistedContactGroupOwned: PersistedContactGroup {
    
    private static let entityName = "PersistedContactGroupOwned"
    private static let rawStatusKey = "rawStatus"
    private static let errorDomain = "PersistedContactGroupOwned"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: - Attributes
    
    @NSManaged private var rawStatus: Int

    // MARK: - Relationships
    
    @NSManaged var owner: PersistedObvOwnedIdentity? // If nil, this entity is eventually cascade-deleted

    // MARK: - Other variables
        
    enum Status: Int {
        case noLatestDetails = 0
        case withLatestDetails = 1
    }
    
    var status: Status {
        return Status(rawValue: self.rawStatus)!
    }
}


// MARK: - Initializer

extension PersistedContactGroupOwned {
    
    convenience init(contactGroup: ObvContactGroup, within context: NSManagedObjectContext) throws {
        
        guard contactGroup.groupType == .owned else {
            assertionFailure()
            throw Self.makeError(message: "Unexpected group type")
        }
        
        guard let owner = try PersistedObvOwnedIdentity.get(persisted: contactGroup.ownedIdentity, within: context) else {
            assertionFailure()
            throw Self.makeError(message: "Could not find owned identity")
        }
        
        try self.init(contactGroup: contactGroup,
                      groupName: contactGroup.publishedCoreDetails.name,
                      category: .owned,
                      forEntityName: PersistedContactGroupOwned.entityName,
                      within: context)
        
        self.rawStatus = Status.noLatestDetails.rawValue
        self.owner = owner

    }
    
}


// MARK: - Helper methods

extension PersistedContactGroupOwned {
    
    func setStatus(to newStatus: Status) {
        self.rawStatus = newStatus.rawValue
    }
    
}
