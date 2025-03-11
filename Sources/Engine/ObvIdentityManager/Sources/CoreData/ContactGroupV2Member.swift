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
import OlvidUtils
import ObvTypes
import ObvMetaManager
import ObvCrypto



@objc(ContactGroupV2Member)
final class ContactGroupV2Member: NSManagedObject, ObvManagedObject, ObvErrorMaker {

    private static let entityName = "ContactGroupV2Member"
    static let errorDomain = "ContactGroupV2Member"

    // Attributes
 
    @NSManaged private var rawPermissions: String
    @NSManaged private(set) var groupInvitationNonce: Data

    // Relationships
    
    @NSManaged private var rawContactGroup: ContactGroupV2? // Expected to be non-nil
    @NSManaged private var rawContactIdentity: ContactIdentity? // Expected to be non-nil

    // Accessors
    
    private(set) var contactGroup: ContactGroupV2? {
        get {
            let value = self.rawContactGroup
            value?.obvContext = obvContext
            return value
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawContactGroup = newValue
        }
    }
    
    fileprivate var contactIdentity: ContactIdentity? {
        get {
            let value = self.rawContactIdentity
            value?.obvContext = obvContext
            return value
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawContactIdentity = newValue
        }
    }
    
    var cryptoIdentity: ObvCryptoIdentity? {
        contactIdentity?.cryptoIdentity
    }

    // Other variables

    weak var obvContext: ObvContext?

    var identityAndPermissionsAndDetails: GroupV2.IdentityAndPermissionsAndDetails? {
        guard let contactIdentity = contactIdentity else { assertionFailure(); return nil }
        let coreDetails = contactIdentity.publishedIdentityDetails?.serializedIdentityCoreDetails ?? contactIdentity.trustedIdentityDetails.serializedIdentityCoreDetails
        guard let contactCryptoId = contactIdentity.cryptoIdentity else { assertionFailure(); return nil }
        return GroupV2.IdentityAndPermissionsAndDetails(identity: contactCryptoId,
                                                        rawPermissions: allRawPermissions,
                                                        serializedIdentityCoreDetails: coreDetails,
                                                        groupInvitationNonce: groupInvitationNonce)
    }

    // MARK: - Initializer
    
    private convenience init(rawPermissions: Set<String>, groupInvitationNonce: Data, rawContactGroup: ContactGroupV2, rawContactIdentity: ContactIdentity, within obvContext: ObvContext) {

        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2Member.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)

        self.setRawPermissions(newRawPermissions: rawPermissions)
        self.groupInvitationNonce = groupInvitationNonce

        self.rawContactGroup = rawContactGroup
        self.rawContactIdentity = rawContactIdentity
        
        self.obvContext = obvContext
        
    }
    
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: ContactGroupV2MemberBackupItem, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2Member.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.groupInvitationNonce = backupItem.groupInvitationNonce
        self.rawPermissions = backupItem.rawPermissions.joined(separator: String(Self.separatorForPermissions))
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(snapshotItem: ContactGroupV2MemberSyncSnapshotItem, within obvContext: ObvContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2Member.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        guard let groupInvitationNonce = snapshotItem.groupInvitationNonce else {
            assertionFailure()
            throw ContactGroupV2MemberSyncSnapshotItem.ObvError.tryingToRestoreIncompleteNode
        }
        self.groupInvitationNonce = groupInvitationNonce
        self.rawPermissions = snapshotItem.rawPermissions.joined(separator: String(Self.separatorForPermissions))
    }

    
    /// Shall only be called from a ContactGroupV2 instance (that must check that this member does not exist yet)
    static func createMember(from contact: ContactIdentity, inContactGroup group: ContactGroupV2, rawPermissions: Set<String>, groupInvitationNonce: Data) throws {
        guard contact.obvContext == group.obvContext else { throw Self.makeError(message: "Cannot insert member as the contexts do not match") }
        guard let obvContext = group.obvContext else { throw Self.makeError(message: "Cannot insert member as the group has no ObvContext") }
        _ = self.init(rawPermissions: rawPermissions, groupInvitationNonce: groupInvitationNonce, rawContactGroup: group, rawContactIdentity: contact, within: obvContext)
    }
     
    
    func delete() throws {
        guard let obvContext = obvContext else { throw Self.makeError(message: "Could not delete member as we cannot find ObvContext") }
        obvContext.delete(self)
    }
    
    
    func updateGroupInvitationNonce(with newGroupInvitationNonce: Data) {
        guard groupInvitationNonce != newGroupInvitationNonce else { return }
        self.groupInvitationNonce = newGroupInvitationNonce
    }
    
}


// MARK: - Permissions

extension ContactGroupV2Member {
    
    var allPermissions: Set<GroupV2.Permission>? {
        return Set(allRawPermissions.compactMap({ GroupV2.Permission(rawValue: $0) }))
    }
    
    fileprivate static let separatorForPermissions: Character = "|"
    
    private var allRawPermissions: Set<String> {
        return Set(self.rawPermissions.split(separator: Self.separatorForPermissions).map({ String($0) }))
    }

    func setRawPermissions(newRawPermissions: Set<String>) {
        self.rawPermissions = newRawPermissions.sorted().joined(separator: String(Self.separatorForPermissions))
    }
    
}


// MARK: - Convenience DB getters

extension ContactGroupV2Member {
    
    struct Predicate {
        enum Key: String {
            case rawContactIdentity = "rawContactIdentity"
        }
    }
    
}


// MARK: - For Backup purposes

extension ContactGroupV2Member {
    
    var backupItem: ContactGroupV2MemberBackupItem? {
        guard let contactIdentity = self.rawContactIdentity else { assertionFailure(); return nil }
        return ContactGroupV2MemberBackupItem(rawPermissions: self.rawPermissions,
                                              groupInvitationNonce: self.groupInvitationNonce,
                                              contactIdentity: contactIdentity)
    }

}


struct ContactGroupV2MemberBackupItem: Codable, Hashable, ObvErrorMaker {
    
    fileprivate let rawPermissions: [String]
    fileprivate let groupInvitationNonce: Data
    fileprivate let contactIdentity: Data // Used to restore the rawContactIdentity relationship

    // Allows to prevent association failures in two items have identical variables
    private let transientUuid = UUID()

    static let errorDomain = "ContactGroupV2MemberBackupItem"

    fileprivate init(rawPermissions: String, groupInvitationNonce: Data, contactIdentity: ContactIdentity) {
        self.groupInvitationNonce = groupInvitationNonce
        self.rawPermissions = rawPermissions.split(separator: ContactGroupV2Member.separatorForPermissions).map({ String($0) })
        self.contactIdentity = contactIdentity.identity
    }

    enum CodingKeys: String, CodingKey {
        case groupInvitationNonce = "invitation_nonce"
        case rawPermissions = "permissions"
        case contactIdentity = "contact_identity"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupInvitationNonce, forKey: .groupInvitationNonce)
        try container.encode(rawPermissions, forKey: .rawPermissions)
        try container.encode(contactIdentity, forKey: .contactIdentity)
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.groupInvitationNonce = try values.decode(Data.self, forKey: .groupInvitationNonce)
        self.rawPermissions = try values.decode([String].self, forKey: .rawPermissions)
        self.contactIdentity = try values.decode(Data.self, forKey: .contactIdentity)
    }
    
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupV2Member = ContactGroupV2Member(backupItem: self, within: obvContext)
        try associations.associate(contactGroupV2Member, to: self)
    }
    
    func restoreRelationships(associations: BackupItemObjectAssociations, ownedIdentity: Data, within obvContext: ObvContext) throws {

        let contactGroupV2Member: ContactGroupV2Member = try associations.getObject(associatedTo: self, within: obvContext)

        // Restore the rawContactIdentity relationship by searching the context for the first registered ContactIdentity that has has the appropriate primary key (owned identity and contact identity).
        
        let allcontactIdentities = Set(obvContext.registeredObjects.compactMap({ $0 as? ContactIdentity }))
        let appropriateContact = allcontactIdentities.first(where: {
            $0.ownedIdentityIdentity == ownedIdentity && $0.identity == self.contactIdentity
        })
        guard let appropriateContact = appropriateContact else {
            throw Self.makeError(message: "Could not find contact associated to group v2 member")
        }
        
        contactGroupV2Member.contactIdentity = appropriateContact
        
    }

}



// MARK: - For Snapshot purposes

extension ContactGroupV2Member {
    
    var snapshotItem: ContactGroupV2MemberSyncSnapshotItem {
        .init(rawPermissions: self.rawPermissions,
              groupInvitationNonce: self.groupInvitationNonce)
    }

}


struct ContactGroupV2MemberSyncSnapshotItem: Codable, Hashable, Identifiable {
    
    fileprivate let rawPermissions: [String]
    fileprivate let groupInvitationNonce: Data?

    let id = ObvSyncSnapshotNodeUtils.generateIdentifier()

    enum CodingKeys: String, CodingKey {
        case groupInvitationNonce = "invitation_nonce"
        case rawPermissions = "permissions"
    }

    
    fileprivate init(rawPermissions: String, groupInvitationNonce: Data) {
        self.groupInvitationNonce = groupInvitationNonce
        self.rawPermissions = rawPermissions.split(separator: ContactGroupV2Member.separatorForPermissions).map({ String($0) })
    }

    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(groupInvitationNonce, forKey: .groupInvitationNonce)
        try container.encode(rawPermissions, forKey: .rawPermissions)
    }

    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.groupInvitationNonce = try values.decodeIfPresent(Data.self, forKey: .groupInvitationNonce)
        self.rawPermissions = try values.decodeIfPresent([String].self, forKey: .rawPermissions) ?? []
    }
    
    
    func restoreInstance(within obvContext: ObvContext, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        let contactGroupV2Member = try ContactGroupV2Member(snapshotItem: self, within: obvContext)
        try associations.associate(contactGroupV2Member, to: self)
    }
    
    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, ownedIdentity: Data, cryptoIdentity: ObvCryptoIdentity, contactIdentities: [ObvCryptoIdentity: ContactIdentity], within obvContext: ObvContext) throws {

        let contactGroupV2Member: ContactGroupV2Member = try associations.getObject(associatedTo: self, within: obvContext)

        guard let contactIdentity = contactIdentities[cryptoIdentity] else {
            throw ObvError.couldNotFindContactAssociatedToGroupV2Member
        }
        
        contactGroupV2Member.contactIdentity = contactIdentity
        
    }

    
    enum ObvError: Error {
        case couldNotFindContactAssociatedToGroupV2Member
        case tryingToRestoreIncompleteNode
    }
    
}
