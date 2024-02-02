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
import ObvEngine
import ObvTypes
import OlvidUtils
import ObvSettings


@objc(PersistedContactGroupJoined)
public final class PersistedContactGroupJoined: PersistedContactGroup, ObvErrorMaker {
    
    private static let entityName = "PersistedContactGroupJoined"
    public static let errorDomain = "PersistedContactGroupJoined"
    
    // MARK: Attributes

    @NSManaged private(set) var customPhotoFilename: String?
    @NSManaged private(set) var groupNameCustom: String?
    @NSManaged private var rawStatus: Int

    // MARK: Relationships

    @NSManaged public var owner: PersistedObvContactIdentity? // If nil, this entity is eventually cascade-deleted

    // MARK: Other variables

    public var status: PublishedDetailsStatusType {
        return PublishedDetailsStatusType(rawValue: self.rawStatus)!
    }
    
    /// Should only be called by PersistedContactGroup#displayPhotoURL
    var customPhotoURL: URL? {
        guard let customPhotoFilename = customPhotoFilename else { return nil }
        return ObvUICoreDataConstants.ContainerURL.forCustomGroupProfilePictures.appendingPathComponent(customPhotoFilename)
    }


    // MARK: - Initializer

    public convenience init(contactGroup: ObvContactGroup, within context: NSManagedObjectContext) throws {

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


    // MARK: - Receiving discussion shared configurations

    
    /// Called when receiving a ``DiscussionSharedConfigurationJSON`` from a contact or an owned identity indicating this particular group as the target. This method makes sure the contact  or the owned identity is allowed to change the configuration, i.e., that she is the group owner.
    override func mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration: PersistedDiscussion.SharedConfiguration, receivedFrom cryptoId: ObvCryptoId) throws -> (sharedSettingHadToBeUpdated: Bool, weShouldSendBackOurSharedSettings: Bool) {
        
        let (sharedSettingHadToBeUpdated, _) = try super.mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration: discussionSharedConfiguration, receivedFrom: cryptoId)
        
        // Since we joined this group, we are not allowed to change its shared settings, so we never send ours back

        let weShouldSendBackOurSharedSettings = false

        return (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettings)
        
    }
    
}


// MARK: - Other methods

extension PersistedContactGroupJoined {
    
    func setGroupNameCustom(to groupNameCustom: String?) throws -> Bool {
        let groupNameCustomHadToBeUpdated: Bool
        let newGroupNameCustom = groupNameCustom?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let newGroupNameCustom, !newGroupNameCustom.isEmpty {
            if self.groupNameCustom != newGroupNameCustom {
                self.groupNameCustom = newGroupNameCustom
                groupNameCustomHadToBeUpdated = true
            } else {
                groupNameCustomHadToBeUpdated = false
            }
        } else {
            if self.groupNameCustom != nil {
                self.groupNameCustom = nil
                groupNameCustomHadToBeUpdated = true
            } else {
                groupNameCustomHadToBeUpdated = false
            }
        }
        if groupNameCustomHadToBeUpdated {
            try discussion.resetTitle(to: self.displayName)
        }
        return groupNameCustomHadToBeUpdated
    }
    
    
    public func setStatus(to newStatus: PublishedDetailsStatusType) {
        guard self.rawStatus != newStatus.rawValue else { return }
        self.rawStatus = newStatus.rawValue
        try? createOrUpdateTheAssociatedDisplayedContactGroup()
    }

}
