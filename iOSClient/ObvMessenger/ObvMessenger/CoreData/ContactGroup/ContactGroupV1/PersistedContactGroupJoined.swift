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
import ObvTypes


@objc(PersistedContactGroupJoined)
final class PersistedContactGroupJoined: PersistedContactGroup {
    
    private static let entityName = "PersistedContactGroupJoined"
    private static let errorDomain = "PersistedContactGroupJoined"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: - Attributes

    @NSManaged private(set) var groupNameCustom: String?
    @NSManaged private(set) var customPhotoFilename: String?
    @NSManaged private var rawStatus: Int

    // MARK: - Relationships

    @NSManaged var owner: PersistedObvContactIdentity? // If nil, this entity is eventually cascade-deleted


    var status: PublishedDetailsStatusType {
        return PublishedDetailsStatusType(rawValue: self.rawStatus)!
    }

    /// Should only be called by PersistedContactGroup#displayPhotoURL
    var customPhotoURL: URL? {
        guard let customPhotoFilename = customPhotoFilename else { return nil }
        return ObvMessengerConstants.containerURL.forCustomGroupProfilePictures.appendingPathComponent(customPhotoFilename)
    }

}


// MARK: - Initializer

extension PersistedContactGroupJoined {
    
    convenience init(contactGroup: ObvContactGroup, within context: NSManagedObjectContext) throws {

        guard contactGroup.groupType == .joined else {
            assertionFailure()
            throw Self.makeError(message: "Unexpected group type")
        }
        
        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(persisted: contactGroup.ownedIdentity, within: context) else {
            assertionFailure()
            throw Self.makeError(message: "Could not find owned identity")
        }
        guard let owner = try PersistedObvContactIdentity.get(cryptoId: contactGroup.groupOwner.cryptoId, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .any) else {
            assertionFailure()
            throw Self.makeError(message: "Could not find contact identity")
        }
        
        try self.init(contactGroup: contactGroup,
                      groupName: contactGroup.trustedOrLatestCoreDetails.name,
                      category: .joined,
                      forEntityName: PersistedContactGroupJoined.entityName,
                      within: context)
        
        self.groupNameCustom = nil
        self.rawStatus = PublishedDetailsStatusType.noNewPublishedDetails.rawValue
        self.owner = owner
        self.customPhotoFilename = nil
    }
    
}


// MARK: - Convenience

extension PersistedContactGroupJoined {
    
    func setGroupNameCustom(to groupNameCustom: String) throws {
        let newGroupNameCustom = groupNameCustom.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newGroupNameCustom.isEmpty else { throw Self.makeError(message: "Cannot use an empty string as a custom group name") }
        self.groupNameCustom = newGroupNameCustom
        try resetDiscussionTitle()
    }
    
    
    func removeGroupNameCustom() throws {
        self.groupNameCustom = nil
        try resetDiscussionTitle()
    }
    
    
    func setStatus(to newStatus: PublishedDetailsStatusType) {
        self.rawStatus = newStatus.rawValue
    }

}
