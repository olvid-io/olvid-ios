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
import JWS



@objc(ContactGroupV2PendingMember)
final class ContactGroupV2PendingMember: NSManagedObject, ObvManagedObject, ObvErrorMaker {

    private static let entityName = "ContactGroupV2PendingMember"
    static let errorDomain = "ContactGroupV2PendingMember"

    // Attributes
 
    @NSManaged private(set) var groupInvitationNonce: Data
    @NSManaged private var rawIdentity: Data
    @NSManaged private var rawPermissions: String
    @NSManaged private var serializedIdentityCoreDetails: Data

    // Relationships
    
    @NSManaged private var rawContactGroup: ContactGroupV2? // Expected to be non-nil

    // Accessors
    
    var cryptoIdentity: ObvCryptoIdentity? {
        get {
            guard let identity = ObvCryptoIdentity(from: rawIdentity) else { assertionFailure(); return nil }
            return identity
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawIdentity = newValue.getIdentity()
        }
    }
    
    var contactGroup: ContactGroupV2? {
        get {
            assert(obvContext != nil)
            guard let rawContactGroup = self.rawContactGroup else { return nil }
            rawContactGroup.obvContext = obvContext
            return rawContactGroup
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawContactGroup = newValue
        }
    }
    
    // Other variables

    var obvContext: ObvContext?
    private var isRestoringBackup = false
    var delegateManager: ObvIdentityDelegateManager?

    var identityAndPermissionsAndDetails: GroupV2.IdentityAndPermissionsAndDetails? {
        guard let cryptoIdentity = cryptoIdentity else { assertionFailure(); return nil }
        return GroupV2.IdentityAndPermissionsAndDetails(identity: cryptoIdentity,
                                                        rawPermissions: allRawPermissions,
                                                        serializedIdentityCoreDetails: serializedIdentityCoreDetails,
                                                        groupInvitationNonce: groupInvitationNonce)
    }
    
    var identityCoreDetails: ObvIdentityCoreDetails {
        get throws {
            try ObvIdentityCoreDetails(serializedIdentityCoreDetails)
        }
    }
    
    // MARK: - Initializer
    
    private convenience init(identity: ObvCryptoIdentity, rawPermissions: Set<String>, serializedIdentityCoreDetails: Data, groupInvitationNonce: Data, contactGroup: ContactGroupV2, delegateManager: ObvIdentityDelegateManager) throws {

        guard let obvContext = contactGroup.obvContext else { assertionFailure(); throw Self.makeError(message: "Cannot find context") }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2PendingMember.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)

        self.cryptoIdentity = identity
        self.setRawPermissions(newRawPermissions: rawPermissions)
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
        self.groupInvitationNonce = groupInvitationNonce
        
        self.contactGroup = contactGroup

        self.obvContext = obvContext
        self.delegateManager = delegateManager

    }

    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: ContactGroupV2PendingMemberBackupItem, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2PendingMember.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.groupInvitationNonce = backupItem.groupInvitationNonce
        self.rawIdentity = backupItem.rawIdentity
        self.rawPermissions = backupItem.rawPermissions.joined(separator: String(Self.separatorForPermissions))
        self.serializedIdentityCoreDetails = backupItem.serializedIdentityCoreDetails
        self.isRestoringBackup = true
        self.delegateManager = nil
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(snapshotNode: ContactGroupV2PendingMemberSyncSnapshotItem, cryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2PendingMember.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        guard let groupInvitationNonce = snapshotNode.groupInvitationNonce else {
            assertionFailure()
            throw ContactGroupV2PendingMemberSyncSnapshotItem.ObvError.tryingToRestoreIncompleteNode
        }
        self.groupInvitationNonce = groupInvitationNonce
        self.rawIdentity = cryptoIdentity.getIdentity()
        self.rawPermissions = snapshotNode.rawPermissions.joined(separator: String(Self.separatorForPermissions))
        guard let serializedIdentityCoreDetails = snapshotNode.serializedIdentityCoreDetails else {
            assertionFailure()
            throw ContactGroupV2PendingMemberSyncSnapshotItem.ObvError.tryingToRestoreIncompleteNode
        }
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
        self.isRestoringBackup = true
        self.delegateManager = nil
    }

    
    static func createAllPendingMembers(from otherGroupMembers: Set<GroupV2.IdentityAndPermissionsAndDetails>, in contactGroup: ContactGroupV2, delegateManager: ObvIdentityDelegateManager) throws -> Set<ContactGroupV2PendingMember> {
        try Set(otherGroupMembers.map { member in
            try ContactGroupV2PendingMember(identity: member.identity,
                                            rawPermissions: member.rawPermissions,
                                            serializedIdentityCoreDetails: member.serializedIdentityCoreDetails,
                                            groupInvitationNonce: member.groupInvitationNonce,
                                            contactGroup: contactGroup,
                                            delegateManager: delegateManager)
        })
    }

    
    static func createPendingMember(from member: GroupV2.IdentityAndPermissionsAndDetails, in contactGroup: ContactGroupV2, delegateManager: ObvIdentityDelegateManager) throws {
        _ = try Self.init(identity: member.identity,
                          rawPermissions: member.rawPermissions,
                          serializedIdentityCoreDetails: member.serializedIdentityCoreDetails,
                          groupInvitationNonce: member.groupInvitationNonce,
                          contactGroup: contactGroup,
                          delegateManager: delegateManager)
    }
    
    
    static func createPendingMember(from member: GroupV2.KeycloakGroupMemberAndPermissions, in contactGroup: ContactGroupV2, validatingSignaturesWith jwks: ObvJWKSet, delegateManager: ObvIdentityDelegateManager) throws {

        let signedObvKeycloakUserDetails = try SignedObvKeycloakUserDetails.verifySignedUserDetails(member.signedUserDetails, with: jwks).signedUserDetails
        let obvIdentityCoreDetails = try signedObvKeycloakUserDetails.toObvIdentityCoreDetails() // These details contain the signedUserDetails
        let serializedIdentityCoreDetails = try obvIdentityCoreDetails.jsonEncode()

        _ = try Self.init(identity: member.identity,
                          rawPermissions: member.rawPermissions,
                          serializedIdentityCoreDetails: serializedIdentityCoreDetails,
                          groupInvitationNonce: member.groupInvitationNonce,
                          contactGroup: contactGroup,
                          delegateManager: delegateManager)
        
    }

    
    func delete(delegateManager: ObvIdentityDelegateManager) throws {
        guard let obvContext = obvContext else { throw Self.makeError(message: "Could not delete pending member as we cannot find ObvContext") }
        self.delegateManager = delegateManager
        obvContext.delete(self)
    }
    
    
    func updatePermissionsAndDetails(newRawPermissions: Set<String>, newSerializedIdentityCoreDetails: Data) {
        self.setRawPermissions(newRawPermissions: newRawPermissions)
        self.serializedIdentityCoreDetails = newSerializedIdentityCoreDetails
    }

    
    func updatePermissionsAndDetails(newRawPermissions: Set<String>, newsignedUserDetails: String, validatingSignaturesWith jwks: ObvJWKSet) throws {
        
        let signedObvKeycloakUserDetails = try SignedObvKeycloakUserDetails.verifySignedUserDetails(newsignedUserDetails, with: jwks).signedUserDetails
        let obvIdentityCoreDetails = try signedObvKeycloakUserDetails.toObvIdentityCoreDetails() // These details contain the signedUserDetails
        let newSerializedIdentityCoreDetails = try obvIdentityCoreDetails.jsonEncode()
        
        self.setRawPermissions(newRawPermissions: newRawPermissions)
        if self.serializedIdentityCoreDetails != newSerializedIdentityCoreDetails {
            self.serializedIdentityCoreDetails = newSerializedIdentityCoreDetails
        }
        
    }
    
    func updateGroupInvitationNonce(with newGroupInvitationNonce: Data) {
        guard groupInvitationNonce != newGroupInvitationNonce else { return }
        self.groupInvitationNonce = newGroupInvitationNonce
    }

}


// MARK: - Permissions

extension ContactGroupV2PendingMember {
    
    var allPermissions: Set<GroupV2.Permission>? {
        return Set(allRawPermissions.compactMap({ GroupV2.Permission(rawValue: $0) }))
    }
    
    var allRawPermissions: Set<String> {
        return Set(self.rawPermissions.split(separator: Self.separatorForPermissions).map({ String($0) }))
    }
    
    fileprivate static let separatorForPermissions: Character = "|"

    func setRawPermissions(newRawPermissions: Set<String>) {
        self.rawPermissions = newRawPermissions.sorted().joined(separator: String(Self.separatorForPermissions))
    }
    
}


extension ContactGroupV2PendingMember {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactGroupV2PendingMember> {
        return NSFetchRequest<ContactGroupV2PendingMember>(entityName: self.entityName)
    }

    struct Predicate {
        enum Key: String {
            case rawIdentity = "rawIdentity"
            case rawContactGroup = "rawContactGroup"
        }
        static func withIdentity(_ identity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawIdentity, EqualToData: identity.getIdentity())
        }
        private static var contactGroupIsNotNil: NSPredicate {
            return NSPredicate(withNonNilValueForKey: Key.rawContactGroup)
        }
        static func withOwnedIdentity(_ ownedIdentity: OwnedIdentity) -> NSPredicate {
            let predicateChain = [Key.rawContactGroup.rawValue,
                                  ContactGroupV2.Predicate.Key.rawOwnedIdentity.rawValue].joined(separator: ".")
            let predicateFormat = "\(predicateChain) == %@"
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                contactGroupIsNotNil,
                NSPredicate(format: predicateFormat, ownedIdentity)
            ])
        }
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            let predicateChain = [Key.rawContactGroup.rawValue,
                                  ContactGroupV2.Predicate.Key.rawOwnedIdentityIdentity.rawValue].joined(separator: ".")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                contactGroupIsNotNil,
                NSPredicate(predicateChain, EqualToData: ownedCryptoIdentity.getIdentity()),
            ])
        }
        static func inGroupWithCategory(_ category: GroupV2.Identifier.Category) -> NSPredicate {
            let predicateChain = [Key.rawContactGroup.rawValue,
                                  ContactGroupV2.Predicate.Key.rawCategory.rawValue].joined(separator: ".")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                contactGroupIsNotNil,
                NSPredicate(predicateChain, EqualToInt: category.rawValue),
            ])
        }
    }
    
    
    /// When re-sending group v2 keys after a channel creation with a contact device, we also want to look for the groups where this contact is a pending member.
    static func getPendingMemberEntriesCorrespondingToContactIdentity(_ contactIdentity: ObvCryptoIdentity, of ownedIdentity: OwnedIdentity) throws -> Set<ContactGroupV2PendingMember> {
        
        guard let obvContext = ownedIdentity.obvContext else { assertionFailure(); throw Self.makeError(message: "Could not get ObvContext from OwnedIdentity") }
        
        let request = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withIdentity(contactIdentity),
            Predicate.withOwnedIdentity(ownedIdentity),
        ])
        request.fetchBatchSize = 1_000
        
        let items = try obvContext.fetch(request)
        items.forEach({ $0.obvContext = obvContext })
        return Set(items)
        
    }
    
    
    /// Returns a set of crypto ids of users that are pending in at least one group v2 of the given category, restricting to groups of the given owned identity.
    static func getAllPendingMembersCorrespondingToOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, groupCategory: GroupV2.Identifier.Category, within context: NSManagedObjectContext) throws -> Set<ObvCryptoIdentity> {
        let request = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
            Predicate.inGroupWithCategory(groupCategory),
        ])
        request.fetchBatchSize = 1_000
        request.propertiesToFetch = [Predicate.Key.rawIdentity.rawValue]
        let items = try context.fetch(request)
        return Set(items.compactMap(\.cryptoIdentity))
    }

    
    // MARK: - Sending notifications

    override func didSave() {
        super.didSave()
        
        defer {
            isRestoringBackup = false
        }
        
        guard !isRestoringBackup else { assert(isInserted); return }

        // Send a backupableManagerDatabaseContentChanged notification
        if let delegateManager = self.delegateManager {
            if isInserted || isDeleted || isUpdated {
                guard let flowId = obvContext?.flowId else { assertionFailure(); return }
                ObvBackupNotification.backupableManagerDatabaseContentChanged(flowId: flowId)
                    .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
            }
        }

    }
}


// MARK: - For Backup purposes

extension ContactGroupV2PendingMember {
    
    var backupItem: ContactGroupV2PendingMemberBackupItem {
        return ContactGroupV2PendingMemberBackupItem(groupInvitationNonce: self.groupInvitationNonce,
                                                     rawIdentity: self.rawIdentity,
                                                     rawPermissions: self.rawPermissions,
                                                     serializedIdentityCoreDetails: self.serializedIdentityCoreDetails)
    }

}


struct ContactGroupV2PendingMemberBackupItem: Codable, Hashable, ObvErrorMaker {
    
    fileprivate let groupInvitationNonce: Data
    fileprivate let rawIdentity: Data
    fileprivate let rawPermissions: [String]
    fileprivate let serializedIdentityCoreDetails: Data

    // Allows to prevent association failures in two items have identical variables
    private let transientUuid = UUID()

    static let errorDomain = "ContactGroupV2PendingMemberBackupItem"

    fileprivate init(groupInvitationNonce: Data, rawIdentity: Data, rawPermissions: String, serializedIdentityCoreDetails: Data) {
        self.groupInvitationNonce = groupInvitationNonce
        self.rawIdentity = rawIdentity
        self.rawPermissions = rawPermissions.split(separator: ContactGroupV2PendingMember.separatorForPermissions).map({ String($0) })
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
    }

    enum CodingKeys: String, CodingKey {
        case groupInvitationNonce = "invitation_nonce"
        case rawIdentity = "contact_identity"
        case rawPermissions = "permissions"
        case serializedIdentityCoreDetails = "serialized_details"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupInvitationNonce, forKey: .groupInvitationNonce)
        try container.encode(rawIdentity, forKey: .rawIdentity)
        try container.encode(rawPermissions, forKey: .rawPermissions)
        guard let coreDetailsAsString = String(data: serializedIdentityCoreDetails, encoding: .utf8) else {
            throw Self.makeError(message: "Could not represent serializedIdentityCoreDetails as String")
        }
        try container.encode(coreDetailsAsString, forKey: .serializedIdentityCoreDetails)
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.groupInvitationNonce = try values.decode(Data.self, forKey: .groupInvitationNonce)
        self.rawIdentity = try values.decode(Data.self, forKey: .rawIdentity)
        self.rawPermissions = try values.decode([String].self, forKey: .rawPermissions)
                
        if let coreDetailsAsString = try? values.decode(String.self, forKey: .serializedIdentityCoreDetails),
                  let coreDetailsAsData = coreDetailsAsString.data(using: .utf8),
           (try? ObvIdentityCoreDetails(coreDetailsAsData)) != nil {
            self.serializedIdentityCoreDetails = coreDetailsAsData
        } else if let coreDetailsAsData = try? values.decode(Data.self, forKey: .serializedIdentityCoreDetails),
                  (try? ObvIdentityCoreDetails(coreDetailsAsData)) != nil {
            self.serializedIdentityCoreDetails = coreDetailsAsData
        } else {
            throw Self.makeError(message: "Could not decode serializedIdentityCoreDetails")
        }
        
    }
    
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupV2PendingMember = ContactGroupV2PendingMember(backupItem: self, within: obvContext)
        try associations.associate(contactGroupV2PendingMember, to: self)
    }
    
    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing to do here
    }

}


// MARK: - For Snapshot purposes

extension ContactGroupV2PendingMember {

    var snapshotItem: ContactGroupV2PendingMemberSyncSnapshotItem {
        return .init(groupInvitationNonce: self.groupInvitationNonce,
                     rawPermissions: self.rawPermissions,
                     serializedIdentityCoreDetails: self.serializedIdentityCoreDetails)
    }

}


struct ContactGroupV2PendingMemberSyncSnapshotItem: Codable, Hashable, Identifiable {
    
    fileprivate let groupInvitationNonce: Data?
    fileprivate let rawPermissions: [String]
    fileprivate let serializedIdentityCoreDetails: Data?

    let id = ObvSyncSnapshotNodeUtils.generateIdentifier()

    enum CodingKeys: String, CodingKey {
        case groupInvitationNonce = "invitation_nonce"
        case rawPermissions = "permissions"
        case serializedIdentityCoreDetails = "serialized_details"
    }

    // Allows to prevent association failures in two items have identical variables
    private let transientUuid = UUID()

    
    fileprivate init(groupInvitationNonce: Data, rawPermissions: String, serializedIdentityCoreDetails: Data) {
        self.groupInvitationNonce = groupInvitationNonce
        self.rawPermissions = rawPermissions.split(separator: ContactGroupV2PendingMember.separatorForPermissions).map({ String($0) })
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
    }

    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupInvitationNonce, forKey: .groupInvitationNonce)
        try container.encode(rawPermissions, forKey: .rawPermissions)
        if let serializedIdentityCoreDetails {
            guard let coreDetailsAsString = String(data: serializedIdentityCoreDetails, encoding: .utf8) else {
                throw ObvError.couldNotSerializeCoreDetails
            }
            try container.encode(coreDetailsAsString, forKey: .serializedIdentityCoreDetails)
        }
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.groupInvitationNonce = try values.decodeIfPresent(Data.self, forKey: .groupInvitationNonce)
        self.rawPermissions = try values.decodeIfPresent([String].self, forKey: .rawPermissions) ?? []
                
        if let coreDetailsAsString = try? values.decodeIfPresent(String.self, forKey: .serializedIdentityCoreDetails),
                  let coreDetailsAsData = coreDetailsAsString.data(using: .utf8),
           (try? ObvIdentityCoreDetails(coreDetailsAsData)) != nil {
            self.serializedIdentityCoreDetails = coreDetailsAsData
        } else if let coreDetailsAsData = try? values.decodeIfPresent(Data.self, forKey: .serializedIdentityCoreDetails),
                  (try? ObvIdentityCoreDetails(coreDetailsAsData)) != nil {
            self.serializedIdentityCoreDetails = coreDetailsAsData
        } else {
            self.serializedIdentityCoreDetails = nil
        }
        
    }
    
    
    func restoreInstance(within obvContext: ObvContext, cryptoIdentity: ObvCryptoIdentity, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        let contactGroupV2PendingMember = try ContactGroupV2PendingMember(snapshotNode: self, cryptoIdentity: cryptoIdentity, within: obvContext)
        try associations.associate(contactGroupV2PendingMember, to: self)
    }

    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing to do here
    }

    
    enum ObvError: Error {
        case couldNotSerializeCoreDetails
        case couldNotDeserializeCoreDetails
        case tryingToRestoreIncompleteNode
    }
    
}
