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
import ObvEncoder
import ObvCrypto
import os.log


@objc(ContactGroupV2)
final class ContactGroupV2: NSManagedObject, ObvManagedObject, ObvErrorMaker {

    private static let entityName = "ContactGroupV2"
    static let errorDomain = "ContactGroupV2"

    // Attributes
    
    @NSManaged private var frozen: Bool // True when restoring a backup, set back to false when we know we are in sync with the server
    @NSManaged private(set) var groupVersion: Int
    @NSManaged private(set) var ownGroupInvitationNonce: Data
    @NSManaged private var rawBlobMainSeed: Data
    @NSManaged private var rawBlobVersionSeed: Data
    @NSManaged private var rawCategory: Int  // Part of GroupV2.Identifier, part of primary key
    @NSManaged private var rawGroupUID: Data  // Part of GroupV2.Identifier, part of primary key
    @NSManaged fileprivate var rawOwnedIdentityIdentity: Data // Part of primary key
    @NSManaged private var rawOwnPermissions: String // Permission strings joined with a "|"
    @NSManaged private var rawServerURL: URL // Part of GroupV2.Identifier, part of primary key
    @NSManaged private var rawGroupAdminServerAuthenticationPrivateKey: Data? // Non-nil for group admins, required to update the blob on the server
    @NSManaged private var rawVerifiedAdministratorsChain: Data

    // Relationships
    
    @NSManaged private var rawOtherMembers: Set<ContactGroupV2Member>
    @NSManaged private var rawOwnedIdentity: OwnedIdentity? // Expected to be non-nil
    @NSManaged private var rawPendingMembers: Set<ContactGroupV2PendingMember>
    @NSManaged private var rawPublishedDetails: ContactGroupV2Details? // Nil if we decided to trust the latest published details
    @NSManaged private var rawTrustedDetails: ContactGroupV2Details? // Expected to be non-nil

    // Accessors
    
    var groupIdentifier: GroupV2.Identifier? {
        get {
            guard let category = GroupV2.Identifier.Category(rawValue: rawCategory),
                  let groupUID = UID(uid: rawGroupUID)  else { assertionFailure(); return nil }
            return GroupV2.Identifier(groupUID: groupUID, serverURL: rawServerURL, category: category)
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawGroupUID = newValue.groupUID.raw
            self.rawServerURL = newValue.serverURL
            self.rawCategory = newValue.category.rawValue
        }
    }
        
    private(set) var blobMainSeed: Seed? {
        get {
            guard let seed = Seed(with: rawBlobMainSeed) else { assertionFailure(); return nil }
            return seed
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawBlobMainSeed = newValue.raw
        }
    }

    private(set) var blobVersionSeed: Seed? {
        get {
            guard let seed = Seed(with: rawBlobVersionSeed) else { assertionFailure(); return nil }
            return seed
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawBlobVersionSeed = newValue.raw
        }
    }

    private(set) var ownedIdentity: OwnedIdentity? {
        get {
            guard let rawOwnedIdentity = rawOwnedIdentity else { assertionFailure(); return nil }
            rawOwnedIdentity.obvContext = self.obvContext
            return rawOwnedIdentity
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawOwnedIdentity = newValue
        }
    }

    fileprivate(set) var trustedDetails: ContactGroupV2Details? {
        get {
            guard let rawTrustedDetails = rawTrustedDetails else { assertionFailure(); return nil }
            rawTrustedDetails.obvContext = self.obvContext
            if let delegateManager = self.delegateManager {
                rawTrustedDetails.delegateManager = delegateManager
            }
            return rawTrustedDetails
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawTrustedDetails = newValue
        }
    }

    fileprivate(set) var publishedDetails: ContactGroupV2Details? {
        get {
            guard let rawPublishedDetails = rawPublishedDetails else { return nil }
            rawPublishedDetails.obvContext = self.obvContext
            if let delegateManager = self.delegateManager {
                rawPublishedDetails.delegateManager = delegateManager
            }
            return rawPublishedDetails
        }
        set {
            self.rawPublishedDetails = newValue
        }
    }
    
    private var groupAdminServerAuthenticationPrivateKey: PrivateKeyForAuthentication? {
        get {
            guard let rawPrivateKey = rawGroupAdminServerAuthenticationPrivateKey else { return nil }
            guard let encodedPrivateKey = ObvEncoded(withRawData: rawPrivateKey),
                  let privateKey = PrivateKeyForAuthenticationDecoder.obvDecode(encodedPrivateKey) else { assertionFailure(); return nil }
            return privateKey
        }
        set {
            self.rawGroupAdminServerAuthenticationPrivateKey = newValue?.obvEncode().rawData
        }
    }
    
    private var verifiedAdministratorsChain: GroupV2.AdministratorsChain? {
        get {
            guard let encodedChain = ObvEncoded(withRawData: rawVerifiedAdministratorsChain),
                  let chain = GroupV2.AdministratorsChain(encodedChain) else { assertionFailure(); return nil }
            return chain
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawVerifiedAdministratorsChain = newValue.obvEncode().rawData
        }
    }
    
    fileprivate var otherMembers: Set<ContactGroupV2Member> {
        get {
            assert(obvContext != nil)
            rawOtherMembers.forEach { $0.obvContext = obvContext }
            return rawOtherMembers
        }
        set {
            rawOtherMembers = newValue
        }
    }

    fileprivate var pendingMembers: Set<ContactGroupV2PendingMember> {
        get {
            assert(obvContext != nil)
            rawPendingMembers.forEach { $0.obvContext = obvContext }
            return rawPendingMembers
        }
        set {
            rawPendingMembers = newValue
        }
    }

    // Other variables

    var obvContext: ObvContext?
    var delegateManager: ObvIdentityDelegateManager?
    private var changedKeys = Set<String>()
    private var valuesOnDeletion: (ownedIdentity: ObvCryptoIdentity, appGroupIdentifier: Data)?
    private var creationOrUpdateInitiator = ObvGroupV2.CreationOrUpdateInitiator.createdOrUpdatedBySomeoneElse // Kept in memory, reset to an appropriate value if required
    

    /// Expected to be non-nil
    var identifierVersionAndKeys: GroupV2.IdentifierVersionAndKeys? {
        guard let blobKeys = self.blobKeys else { assertionFailure(); return nil }
        guard let groupIdentifier = self.groupIdentifier else { assertionFailure(); return nil }
        return GroupV2.IdentifierVersionAndKeys(groupIdentifier: groupIdentifier, groupVersion: groupVersion, blobKeys: blobKeys)
    }

    
    func getTrustedPhotoURL(delegateManager: ObvIdentityDelegateManager) -> URL? {
        trustedDetails?.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
    }
    
    func unfreeze() {
        self.frozen = false
    }

    func freeze() {
        self.frozen = true
    }

    /// Expected to be non-nil
    var blobKeys: GroupV2.BlobKeys? {
        guard let blobVersionSeed = self.blobVersionSeed else { assertionFailure(); return nil }
        return GroupV2.BlobKeys(blobMainSeed: blobMainSeed, blobVersionSeed: blobVersionSeed, groupAdminServerAuthenticationPrivateKey: groupAdminServerAuthenticationPrivateKey)
    }
    
    func getPendingMembersAndPermissions() throws -> Set<GroupV2.IdentityAndPermissions> {
        Set(try pendingMembers.map { pendingMember in
            guard let cryptoIdentity = pendingMember.cryptoIdentity else { throw Self.makeError(message: "Could not obtain crypto identity") }
            return GroupV2.IdentityAndPermissions(identity: cryptoIdentity, rawPermissions: pendingMember.allRawPermissions)
        })
    }
    
    // MARK: - Initializer
    
    private convenience init(frozen: Bool, groupIdentifier: GroupV2.Identifier, rawOwnPermissions: Set<String>, verifiedAdministratorsChain: GroupV2.AdministratorsChain, groupVersion: Int, blobMainSeed: Seed, blobVersionSeed: Seed, ownGroupInvitationNonce: Data, ownedIdentity: OwnedIdentity, trustedDetails: ContactGroupV2Details, otherGroupMembers: Set<GroupV2.IdentityAndPermissionsAndDetails>, groupAdminServerAuthenticationPrivateKey: PrivateKeyForAuthentication?, delegateManager: ObvIdentityDelegateManager) throws {
        
        guard let obvContext = ownedIdentity.obvContext else { assertionFailure(); throw Self.makeError(message: "No obvContext in owned identity") }
        
        // Check that the group does not already exists for this group identifier and identity
        
        guard try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) == nil else {
            throw Self.makeError(message: "The group already exists")
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)

        self.obvContext = obvContext
        self.delegateManager = delegateManager
        
        self.frozen = frozen
        self.groupIdentifier = groupIdentifier
        self.rawOwnedIdentityIdentity = ownedIdentity.cryptoIdentity.getIdentity()
        self.setRawPermissions(newRawOwnPermissions: rawOwnPermissions)
        self.verifiedAdministratorsChain = verifiedAdministratorsChain
        self.groupVersion = groupVersion
        self.blobMainSeed = blobMainSeed
        self.blobVersionSeed = blobVersionSeed
        self.ownGroupInvitationNonce = ownGroupInvitationNonce
        self.groupAdminServerAuthenticationPrivateKey = groupAdminServerAuthenticationPrivateKey

        self.ownedIdentity = ownedIdentity
        self.trustedDetails = trustedDetails
        self.publishedDetails = nil
        self.pendingMembers = try ContactGroupV2PendingMember.createAllPendingMembers(from: otherGroupMembers,
                                                                                      in: self,
                                                                                      delegateManager: delegateManager)
        self.otherMembers = Set<ContactGroupV2Member>()
        
    }
    
    private var isRestoringBackup = false
    
    /// Used *exclusively* during a backup restore for creating an instance, relationships are recreater in a second step
    fileprivate convenience init(backupItem: ContactGroupV2BackupItem, ownedIdentity: Data, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.frozen = true // True when restoring a backup
        self.groupVersion = backupItem.groupVersion
        self.ownGroupInvitationNonce = backupItem.ownGroupInvitationNonce
        self.rawBlobMainSeed = backupItem.rawBlobMainSeed
        self.rawBlobVersionSeed = backupItem.rawBlobVersionSeed
        self.rawCategory = backupItem.rawCategory
        self.rawGroupUID = backupItem.rawGroupUID
        self.rawOwnedIdentityIdentity = ownedIdentity
        self.rawOwnPermissions = backupItem.rawOwnPermissions.joined(separator: String(Self.separatorForPermissions))
        self.rawServerURL = backupItem.rawServerURL
        self.rawGroupAdminServerAuthenticationPrivateKey = backupItem.rawGroupAdminServerAuthenticationPrivateKey
        self.rawVerifiedAdministratorsChain = backupItem.rawVerifiedAdministratorsChain
        isRestoringBackup = true
    }

    
    /// Called when creating a new group for which we are an administrator. This method is *not* the one to call when restoring a backup.
    static func createContactGroupV2AdministratedByOwnedIdentity(_ ownedIdentity: OwnedIdentity, serializedGroupCoreDetails: Data, photoURL: URL?, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, using prng: PRNGService, solveChallengeDelegate: ObvSolveChallengeDelegate, delegateManager: ObvIdentityDelegateManager) throws -> (contactGroup: ContactGroupV2, groupAdminServerAuthenticationPublicKey: PublicKeyForAuthentication) {
        
        guard let obvContext = ownedIdentity.obvContext else { assertionFailure(); throw Self.makeError(message: "Cannot find ObvContext in OwnedIdentity") }
        
        // Augment the other members with their details (each member is expected to be a contact of the owned identity)
        
        let otherGroupMembers: Set<GroupV2.IdentityAndPermissionsAndDetails> = Set(try otherGroupMembers.map { member in
            guard let contact = try ContactIdentity.get(contactIdentity: member.identity, ownedIdentity: ownedIdentity.cryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
                assertionFailure()
                throw Self.makeError(message: "One of the group member is not a contact of the owned identity")
            }
            guard contact.allCapabilities?.contains(.groupsV2) == true else {
                assertionFailure()
                throw Self.makeError(message: "One of the contacts does not have the GroupV2 capability")
            }
            let serializedIdentityCoreDetails = contact.publishedIdentityDetails?.serializedIdentityCoreDetails ?? contact.trustedIdentityDetails.serializedIdentityCoreDetails
            let groupInvitationNonce = prng.genBytes(count: ObvConstants.groupInvitationNonceLength)
            return GroupV2.IdentityAndPermissionsAndDetails(identity: member.identity,
                                                            rawPermissions: member.rawPermissions,
                                                            serializedIdentityCoreDetails: serializedIdentityCoreDetails,
                                                            groupInvitationNonce: groupInvitationNonce)
        })
        
        // We we create an "owned" group, we have all permissions (including, of course, the groupAdmin permission)
        
        let ownPermissions = ownRawPermissions.union(Set([GroupV2.Permission.groupAdmin.rawValue]))
        
        // Bootstrap the administrators chain
        
        let otherAdministrators = otherGroupMembers.filter({ $0.hasGroupAdminPermission }).map({ $0.identity })
        let verifiedAdministratorsChain = try GroupV2.AdministratorsChain.startNewChain(ownedIdentity: ownedIdentity.cryptoIdentity,
                                                                                        otherAdministrators: otherAdministrators,
                                                                                        using: prng,
                                                                                        solveChallengeDelegate: solveChallengeDelegate,
                                                                                        within: obvContext)
        
        // Compute the group UID
        
        let groupUID = verifiedAdministratorsChain.groupUID
        let groupIdentifier = GroupV2.Identifier(groupUID: groupUID,
                                                 serverURL: ownedIdentity.cryptoIdentity.serverURL,
                                                 category: .server)

        // Generate the seeds allowing to derive the blob encryption key
        
        let blobMainSeed = prng.genSeed()
        let blobVersionSeed = prng.genSeed()
        
        // Generate the nonce used when leaving the group
        
        let ownGroupInvitationNonce = prng.genBytes(count: ObvConstants.groupInvitationNonceLength)
        
        // If the photoURL is non-nil, create new ServerPhotoInfo for it
        
        let serverPhotoInfo: GroupV2.ServerPhotoInfo?
        if photoURL == nil {
            serverPhotoInfo = nil
        } else {
            serverPhotoInfo = GroupV2.ServerPhotoInfo.generate(for: ownedIdentity.cryptoIdentity, with: prng)
        }
        
        // Create the trusted details
        
        let trustedDetails = ContactGroupV2Details(serverPhotoInfo: serverPhotoInfo,
                                                   serializedCoreDetails: serializedGroupCoreDetails,
                                                   photoURL: photoURL,
                                                   delegateManager: delegateManager,
                                                   within: obvContext)
        
        // Create the signature key allowing to update the blob on server
        
        let (publicKey, privateKey) = ObvCryptoSuite.sharedInstance.authentication().generateKeyPair(with: prng)
                        
        let group = try self.init(frozen: true,
                                  groupIdentifier: groupIdentifier,
                                  rawOwnPermissions: ownPermissions,
                                  verifiedAdministratorsChain: verifiedAdministratorsChain,
                                  groupVersion: 0,
                                  blobMainSeed: blobMainSeed,
                                  blobVersionSeed: blobVersionSeed,
                                  ownGroupInvitationNonce: ownGroupInvitationNonce,
                                  ownedIdentity: ownedIdentity,
                                  trustedDetails: trustedDetails,
                                  otherGroupMembers: otherGroupMembers,
                                  groupAdminServerAuthenticationPrivateKey: privateKey,
                                  delegateManager: delegateManager)
        
        // Set an appropriate value for the initiator
        
        group.creationOrUpdateInitiator = .createdByMe

        return (group, publicKey)
        
    }

    
    /// Called when joigning a new group (we may be an administrator or not but if we are, we certainly did not create the group). This method is *not* the one to call when restoring a backup.
    static func createContactGroupV2JoinedByOwnedIdentity(_ ownedIdentity: OwnedIdentity, groupIdentifier: GroupV2.Identifier, serverBlob: GroupV2.ServerBlob, blobKeys: GroupV2.BlobKeys, delegateManager: ObvIdentityDelegateManager) throws {
        
        guard let obvContext = ownedIdentity.obvContext else { assertionFailure(); throw Self.makeError(message: "Cannot find ObvContext in OwnedIdentity") }
        
        // If the group already exists, do nothing
        
        guard try ContactGroupV2.getContactGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, delegateManager: delegateManager) == nil else {
            return
        }

        guard serverBlob.administratorsChain.integrityChecked else {
            assertionFailure()
            throw Self.makeError(message: "We expect the integrity of the blob's administrator chain to be checked at this point")
        }
        
        guard let ownMember = serverBlob.groupMembers.first(where: { $0.identity == ownedIdentity.cryptoIdentity }) else {
            assertionFailure()
            throw Self.makeError(message: "We are not part of the group")
        }
        let otherGroupMembers = serverBlob.groupMembers.filter({ $0.identity != ownedIdentity.cryptoIdentity })
        
        guard let blobMainSeed = blobKeys.blobMainSeed else {
            assertionFailure()
            throw Self.makeError(message: "Cannot create group without the main seed")
        }
        
        // Create the trusted details
        
        let trustedDetails = ContactGroupV2Details(serverPhotoInfo: serverBlob.serverPhotoInfo,
                                                   serializedCoreDetails: serverBlob.serializedGroupCoreDetails,
                                                   photoURL: nil,
                                                   delegateManager: delegateManager,
                                                   within: obvContext)

        // We start by creating a group where all the members are pending members. They will evenutally send us "Pings" within the GroupV2 protocol to indicate that they accepted the group invitation.
        
        let group = try self.init(frozen: false,
                                  groupIdentifier: groupIdentifier,
                                  rawOwnPermissions: ownMember.rawPermissions,
                                  verifiedAdministratorsChain: serverBlob.administratorsChain,
                                  groupVersion: serverBlob.groupVersion,
                                  blobMainSeed: blobMainSeed,
                                  blobVersionSeed: blobKeys.blobVersionSeed,
                                  ownGroupInvitationNonce: ownMember.groupInvitationNonce,
                                  ownedIdentity: ownedIdentity,
                                  trustedDetails: trustedDetails,
                                  otherGroupMembers: otherGroupMembers,
                                  groupAdminServerAuthenticationPrivateKey: blobKeys.groupAdminServerAuthenticationPrivateKey,
                                  delegateManager: delegateManager)
        
        // Set an appropriate value for the initiator
        
        group.creationOrUpdateInitiator = .createdOrUpdatedBySomeoneElse
                
    }

    
    func delete() throws {
        guard let obvContext = obvContext else { assertionFailure(); throw Self.makeError(message: "Could not delete ContactGroupV2 as the ObvContext is not available") }
        guard let delegateManager = self.delegateManager else { assertionFailure(); return }
        guard let ownedIdentity = ownedIdentity?.cryptoIdentity else { assertionFailure(); return }
        guard let obvGroupV2 = getObvGroupV2(delegateManager: delegateManager) else { assertionFailure(); return }
        valuesOnDeletion = (ownedIdentity, obvGroupV2.appGroupIdentifier)
        obvContext.delete(self)
    }
    
}


// MARK: - Permissions

extension ContactGroupV2 {
    
    var allOwnPermissions: Set<ObvGroupV2.Permission> {
        Set(allRawOwnPermissions.compactMap({ ObvGroupV2.Permission(rawValue: String($0)) }))
    }
    
    fileprivate static let separatorForPermissions: Character = "|"
    
    var allRawOwnPermissions: Set<String> {
        let split = self.rawOwnPermissions.split(separator: Self.separatorForPermissions)
        return Set(split.map({ String($0) }))
    }

    /// Shall *only* be used when creating an administrated group
    private func setRawPermissions(newRawOwnPermissions: Set<String>) {
        self.rawOwnPermissions = newRawOwnPermissions.sorted().joined(separator: String(Self.separatorForPermissions))
    }
    
}


// MARK: - Blob management

extension ContactGroupV2 {
    
    func getServerBlob() throws -> GroupV2.ServerBlob {
        
        guard let verifiedAdministratorsChain = self.verifiedAdministratorsChain else { assertionFailure(); throw Self.makeError(message: "Could not get verified administrator chains") }
        
        let groupMembers: Set<GroupV2.IdentityAndPermissionsAndDetails>
        do {
            
            // Pending members
            let pendingMembers = self.pendingMembers.compactMap({ $0.identityAndPermissionsAndDetails })
            guard pendingMembers.count == self.pendingMembers.count else { throw Self.makeError(message: "Could not extract identity, permissions and details of a pending group member") }
            
            // Other members
            let otherMembers = self.otherMembers.compactMap({ $0.identityAndPermissionsAndDetails })
            guard otherMembers.count == self.otherMembers.count else { throw Self.makeError(message: "Could not extract identity, permissions and details of a group member") }
            
            // Owned identity as a member
            guard let ownedIdentity = self.ownedIdentity else { throw Self.makeError(message: "Could not get owned identity") }
            let ownAsMember = GroupV2.IdentityAndPermissionsAndDetails(identity: ownedIdentity.cryptoIdentity,
                                                                       rawPermissions: allRawOwnPermissions,
                                                                       serializedIdentityCoreDetails: ownedIdentity.publishedIdentityDetails.serializedIdentityCoreDetails,
                                                                       groupInvitationNonce: ownGroupInvitationNonce)
            
            groupMembers = Set(pendingMembers + otherMembers + [ownAsMember])
        }
        
        guard let serializedGroupCoreDetails = publishedDetails?.serializedCoreDetails ?? trustedDetails?.serializedCoreDetails else {
            throw Self.makeError(message: "Could not extract group core details")
        }
        
        let serverPhotoInfo = publishedDetails?.serverPhotoInfo ?? trustedDetails?.serverPhotoInfo
                
        return GroupV2.ServerBlob(administratorsChain: verifiedAdministratorsChain,
                                  groupMembers: groupMembers,
                                  groupVersion: groupVersion,
                                  serializedGroupCoreDetails: serializedGroupCoreDetails,
                                  serverPhotoInfo: serverPhotoInfo)
        
    }
    
    
    /// Compute the encoded, signed, padded, and encrypted blob from the ServerBlob we have
    func getEncryptedServerBlob(solveChallengeDelegate: ObvSolveChallengeDelegate, using prng: PRNGService, within obvContext: ObvContext) throws -> EncryptedData {
        
        let blob = try getServerBlob()
        
        guard let ownedIdentity = self.ownedIdentity else { assertionFailure(); throw Self.makeError(message: "Could not find associated owned identity") }

        guard let blobMainSeed = self.blobMainSeed, let blobVersionSeed = self.blobVersionSeed else { throw Self.makeError(message: "Could not determine the blob seeds") }

        let encryptedBlob = try blob.signThenEncrypt(ownedIdentity: ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity(),
                                                     blobMainSeed: blobMainSeed,
                                                     blobVersionSeed: blobVersionSeed,
                                                     solveChallengeDelegate: solveChallengeDelegate,
                                                     with: prng,
                                                     within: obvContext)
        
        return encryptedBlob

    }
    
}


// MARK: - Members and pending members management

extension ContactGroupV2 {

    /// This method removes an identity from the other pending members and from the other members of the group.
    /// If the owned identity is part of the identities to removed, this method throws.
    func removeOtherMembersOrPendingMembers(_ identitiesToRemove: Set<ObvCryptoIdentity>) throws {
        
        guard let ownedIdentity = self.ownedIdentity else { throw Self.makeError(message: "Could not find owned identity") }
        
        guard !identitiesToRemove.contains(ownedIdentity.cryptoIdentity) else {
            assertionFailure()
            throw Self.makeError(message: "Cannot remove owned identity from the set of other pending members or other members")
        }
        
        self.otherMembers = otherMembers.filter { member in
            guard let memberCryptoIdentity = member.cryptoIdentity else { return false }
            return !identitiesToRemove.contains(memberCryptoIdentity)
        }
        
        self.pendingMembers = pendingMembers.filter { pendingMember in
            guard let pendingMemberCryptoIdentity = pendingMember.cryptoIdentity else { return false }
            return !identitiesToRemove.contains(pendingMemberCryptoIdentity)
        }
        
    }
    
    
    func getAllOtherMembersOrPendingMembersIdentifiedByNonce(_ nonce: Data) throws -> Set<GroupV2.IdentityAndPermissionsAndDetails> {
        let members: Set<GroupV2.IdentityAndPermissionsAndDetails> = try Set(self.otherMembers.filter({ $0.groupInvitationNonce == nonce }).map { member in
            guard let identityAndPermissionsAndDetails = member.identityAndPermissionsAndDetails else { throw Self.makeError(message: "Could not get member's identityAndPermissionsAndDetails") }
            return identityAndPermissionsAndDetails
        })
        let pendingMembers: Set<GroupV2.IdentityAndPermissionsAndDetails> = try Set(self.pendingMembers.filter({ $0.groupInvitationNonce == nonce }).map { pendingMember in
            guard let identityAndPermissionsAndDetails = pendingMember.identityAndPermissionsAndDetails else { throw Self.makeError(message: "Could not get pending member's identityAndPermissionsAndDetails") }
            return identityAndPermissionsAndDetails
        })
        return members.union(pendingMembers)
    }
    
    
    func getAllOtherMembersOrPendingMembers() throws -> Set<GroupV2.IdentityAndPermissionsAndDetails> {
        let members: Set<GroupV2.IdentityAndPermissionsAndDetails> = try Set(self.otherMembers.map { member in
            guard let identityAndPermissionsAndDetails = member.identityAndPermissionsAndDetails else { throw Self.makeError(message: "Could not get member's identityAndPermissionsAndDetails") }
            return identityAndPermissionsAndDetails
        })
        let pendingMembers: Set<GroupV2.IdentityAndPermissionsAndDetails> = try Set(self.pendingMembers.map { pendingMember in
            guard let identityAndPermissionsAndDetails = pendingMember.identityAndPermissionsAndDetails else { throw Self.makeError(message: "Could not get pending member's identityAndPermissionsAndDetails") }
            return identityAndPermissionsAndDetails
        })
        return members.union(pendingMembers)
    }
    
    
    func getAllNonPendingAdministratorsIdentitites() throws  -> Set<ObvCryptoIdentity> {
        var admins: Set<ObvCryptoIdentity> = Set(self.otherMembers.compactMap { member in
            guard let allMembersPermission = member.allPermissions else { assertionFailure(); return nil }
            guard allMembersPermission.contains(.groupAdmin) else { return nil }
            return member.cryptoIdentity
            
        })
        guard let ownedIdentity = ownedIdentity?.cryptoIdentity else {
            throw Self.makeError(message: "Cannot determine owned identity")
        }
        if allOwnPermissions.contains(.groupAdmin) {
            admins.insert(ownedIdentity)
        }
        return admins
    }


    /// This method moves a pending member to the members of the group. If this pending member is not a contact of the owned identity yet, it creates the contact.
    func movePendingMemberToOtherMembers(pendingMemberCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvIdentityDelegateManager) throws {

        guard let ownedIdentity = ownedIdentity else { throw Self.makeError(message: "Could not find owned identity") }
       
        // Moving a pending member to other members can only be done for server groups
        
        guard let groupIdentifier = self.groupIdentifier else {
            assertionFailure()
            throw Self.makeError(message: "Could not determine the group identifier")
        }
        
        guard groupIdentifier.category == .server else {
            assertionFailure()
            throw Self.makeError(message: "Keycloak groups never have pending members, only Server groups have")
        }
        
        // If the pending member is actually already a member, we just make sure the identity does not appear in the pending members anymore and return

        guard otherMembers.first(where: { $0.cryptoIdentity == pendingMemberCryptoIdentity }) == nil else {
            // The pending member is already a member. We just make sure the identity does not appear in the pending members anymore and return
            if let pendingMember = pendingMembers.first(where: { $0.cryptoIdentity == pendingMemberCryptoIdentity }) {
                try pendingMember.delete(delegateManager: delegateManager)
            }
            return
        }
        
        // At this point we known the `pendingMemberCryptoIdentity` is not a proper member yet.
        // We look for this identity in the pending members.
        
        guard let pendingMember = pendingMembers.first(where: { $0.cryptoIdentity == pendingMemberCryptoIdentity }) else {
            throw Self.makeError(message: "Could not find pending member")
        }
         
        // Before moving the pending member to the members we make sure she is a contact. In case she already is, we only add a trust origin.
        
        let identityCoreDetails = try pendingMember.identityCoreDetails
        let obvGroupV2Identifier = groupIdentifier.toObvGroupV2Identifier
        let contact = try ownedIdentity.addContactOrTrustOrigin(cryptoIdentity: pendingMemberCryptoIdentity,
                                                                identityCoreDetails: identityCoreDetails,
                                                                trustOrigin: .serverGroupV2(timestamp: Date(), groupIdentifier: obvGroupV2Identifier),
                                                                isOneToOne: false,
                                                                delegateManager: delegateManager)
        
        // Now that we know for sure that the pending member is a contact, we can move it from the pending members to the members

        try ContactGroupV2Member.createMember(from: contact, inContactGroup: self, rawPermissions: pendingMember.allRawPermissions, groupInvitationNonce: pendingMember.groupInvitationNonce)
        try pendingMember.delete(delegateManager: delegateManager)
        
    }
    
}


// MARK: - Updating a group

extension ContactGroupV2 {
    
    /// Given a new version of the server blob and of the blob keys, this method updates the group (members, own informations, details of the group, etc.).
    ///
    /// The server blob received is expected to be a consolidated server blob, i.e., the server blob as it exists on server, consolidated with the log entries of the members who declined the invitation or who left the group.
    /// This means that, although this server blob may have the same version number as the one we have in database, it might be different.
    /// For this reason, we accept that the version number is superior *or equal* to the version we know about.
    /// Note that, if these versions are equal, we do *not* accept any member or pending member insertion, nor any member or pending member update. We only allow member or pending member deletions.
    ///
    /// This method returns a set of the identities of the members that have been inserted or that have a new nonce. Eventually, this set is sent back to the group V2 management protocol so as to ping all these members.
    func updateGroupV2(newBlobKeys: GroupV2.BlobKeys, consolidatedServerBlob: GroupV2.ServerBlob, groupUpdatedByOwnedIdentity: Bool, delegateManager: ObvIdentityDelegateManager) throws -> Set<ObvCryptoIdentity> {
        
        guard let obvContext = self.obvContext else { throw Self.makeError(message: "Cannot update group as it has no context") }

        assert(self.frozen, "Since we are updating the group, we expect it to be frozen at this point")
        
        guard consolidatedServerBlob.groupVersion >= groupVersion else { assertionFailure(); throw Self.makeError(message: "Cannot upgrade group with information of an earlier version") }
        self.groupVersion = consolidatedServerBlob.groupVersion
        
        self.blobMainSeed = newBlobKeys.blobMainSeed
        self.blobVersionSeed = newBlobKeys.blobVersionSeed
        self.groupAdminServerAuthenticationPrivateKey = newBlobKeys.groupAdminServerAuthenticationPrivateKey
        
        guard consolidatedServerBlob.administratorsChain.integrityChecked else { throw Self.makeError(message: "Cannot update group if the administrators chain is not checked") }
        guard let knownVerifiedAdministratorsChain = self.verifiedAdministratorsChain else {
            assertionFailure()
            throw Self.makeError(message: "We do not have a known administrator chain to check")
        }
        guard knownVerifiedAdministratorsChain.isPrefixOfOtherAdministratorsChain(consolidatedServerBlob.administratorsChain) else {
            throw Self.makeError(message: "The known administrator chain is not a prefix of the new one. We cannot accept the new one.")
        }
        self.verifiedAdministratorsChain = consolidatedServerBlob.administratorsChain
        
        guard let ownedIdentity = self.ownedIdentity else { throw Self.makeError(message: "Cannot find owned identity") }
        
        guard let ownMember = consolidatedServerBlob.groupMembers.first(where: { $0.identity == ownedIdentity.cryptoIdentity }) else {
            throw Self.makeError(message: "We are not indicated as part of the group")
        }
        
        if ownMember.hasGroupAdminPermission {
            guard self.groupAdminServerAuthenticationPrivateKey != nil else {
                throw Self.makeError(message: "Although we are indicated as an admin of the group, we do not have the authentication private key")
            }
        }
        
        self.setRawPermissions(newRawOwnPermissions: ownMember.rawPermissions)
        self.ownGroupInvitationNonce = ownMember.groupInvitationNonce
                
        // Update the details of the group (it is up to the app to determine whether these details should be auto trusted)
        
        do {
            if let trustedDetails = self.trustedDetails {
                if trustedDetails.serverPhotoInfo != consolidatedServerBlob.serverPhotoInfo ||
                    trustedDetails.serializedCoreDetails != consolidatedServerBlob.serializedGroupCoreDetails {
                    // Keep the previous photo iff the server photo infos did not change
                    let newPhotoURL: URL?
                    if trustedDetails.serverPhotoInfo != consolidatedServerBlob.serverPhotoInfo {
                        newPhotoURL = nil
                    } else {
                        newPhotoURL = trustedDetails.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
                    }
                    let newDetails = ContactGroupV2Details(serverPhotoInfo: consolidatedServerBlob.serverPhotoInfo,
                                                           serializedCoreDetails: consolidatedServerBlob.serializedGroupCoreDetails,
                                                           photoURL: newPhotoURL,
                                                           delegateManager: delegateManager,
                                                           within: obvContext)
                    try self.publishedDetails?.delete(delegateManager: delegateManager)
                    if groupUpdatedByOwnedIdentity {
                        try self.trustedDetails?.delete(delegateManager: delegateManager)
                        self.trustedDetails = newDetails
                    } else {
                        self.publishedDetails = newDetails
                    }
                } else {
                    try self.publishedDetails?.delete(delegateManager: delegateManager)
                }
            } else {
                assertionFailure()
                self.trustedDetails = ContactGroupV2Details(serverPhotoInfo: consolidatedServerBlob.serverPhotoInfo,
                                                            serializedCoreDetails: consolidatedServerBlob.serializedGroupCoreDetails,
                                                            photoURL: nil,
                                                            delegateManager: delegateManager,
                                                            within: obvContext)
                try self.publishedDetails?.delete(delegateManager: delegateManager)
            }
        }

        // Delete members and pending members
        
        let identitiesToKeep = Set(consolidatedServerBlob.groupMembers.map({ $0.identity })) // Always contains the owned identity
        do {
            let membersToDelete = self.otherMembers.filter {
                guard let cryptoIdentity = $0.cryptoIdentity else { return true }
                return !identitiesToKeep.contains(cryptoIdentity)
            }
            try membersToDelete.forEach {
                self.otherMembers.remove($0)
                try $0.delete()
            }
            let pendingMembersToDelete = self.pendingMembers.filter {
                guard let cryptoIdentity = $0.cryptoIdentity else { return true }
                return !identitiesToKeep.contains(cryptoIdentity)
            }
            try pendingMembersToDelete.forEach {
                self.pendingMembers.remove($0)
                try $0.delete(delegateManager: delegateManager)
            }
        }

        // Insert new members and pending members
        
        let knownIdentities = Set(self.otherMembers.compactMap({ $0.cryptoIdentity }) + self.pendingMembers.compactMap({ $0.cryptoIdentity }) + [ownMember.identity])
        let identitiesToInsert = identitiesToKeep.subtracting(knownIdentities)
        
        for identityToInsert in identitiesToInsert {
            guard let groupMember = consolidatedServerBlob.groupMembers.first(where: { $0.identity == identityToInsert }) else { assertionFailure(); continue }
            try ContactGroupV2PendingMember.createPendingMember(from: groupMember, in: self, delegateManager: delegateManager)
        }
        
        // Update existing members that have a new nonce. Also update the permissions and details when appropriate.
        
        var updatedIdentities = Set<ObvCryptoIdentity>()
        
        for member in self.otherMembers {
            guard let cryptoIdentity = member.cryptoIdentity else { assertionFailure(); continue }
            guard let blobMember = consolidatedServerBlob.groupMembers.first(where: { $0.identity == cryptoIdentity }) else { assertionFailure(); continue }
            if member.groupInvitationNonce != blobMember.groupInvitationNonce {
                member.updateGroupInvitationNonce(with: blobMember.groupInvitationNonce)
                updatedIdentities.insert(cryptoIdentity)
            }
            // We also the permissions (without inserting the identity in the set of updated identites, since this should not triger a ping at the protocol level)
            member.setRawPermissions(newRawPermissions: blobMember.rawPermissions)
        }
        
        for pendingMember in self.pendingMembers {
            guard let cryptoIdentity = pendingMember.cryptoIdentity else { assertionFailure(); continue }
            guard let blobMember = consolidatedServerBlob.groupMembers.first(where: { $0.identity == cryptoIdentity }) else { assertionFailure(); continue }
            if pendingMember.groupInvitationNonce != blobMember.groupInvitationNonce {
                pendingMember.updateGroupInvitationNonce(with: blobMember.groupInvitationNonce)
                updatedIdentities.insert(cryptoIdentity)
            }
            // We also update the details and permissions (without inserting the identity in the set of updated identites, since this should not triger a ping at the protocol level)
            pendingMember.updatePermissionsAndDetails(newRawPermissions: blobMember.rawPermissions, newSerializedIdentityCoreDetails: blobMember.serializedIdentityCoreDetails)
        }
        
        // Deal with a case that should never happen: when an identity appears both in the other members and in the pending members, remove it from the pending members
        
        do {
            let cryptoIdentitiesOfOtherMembers = Set(self.otherMembers.compactMap({ $0.cryptoIdentity }))
            let cryptoIdentitiesOfPendingMembers = Set(self.pendingMembers.compactMap({ $0.cryptoIdentity }))
            let identitiesToRemoveFromPendingMembers = cryptoIdentitiesOfOtherMembers.intersection(cryptoIdentitiesOfPendingMembers)
            assert(identitiesToRemoveFromPendingMembers.isEmpty)
            self.pendingMembers = self.pendingMembers.filter({
                guard let cryptoIdentity = $0.cryptoIdentity else { assertionFailure(); return true }
                return !identitiesToRemoveFromPendingMembers.contains(cryptoIdentity)
            })
        }
        
        // Set an appropriate value for the initiator
        
        if groupUpdatedByOwnedIdentity {
            self.creationOrUpdateInitiator = .updatedByMe
        } else {
            self.creationOrUpdateInitiator = .createdOrUpdatedBySomeoneElse
        }
        
        // Create a list of the inserted and updated identities.
        // This will be returned to allow the protocol to "ping" these identities
        
        let insertedOrUpdatedIdentities = identitiesToInsert.union(updatedIdentities)

        return insertedOrUpdatedIdentities
        
    }
    
    
    /// When the user accepts new published details (or when the app does so automatically), this method is called.
    /// Note that the `delete` method also deletes the photo if the context saves succesfully.
    func replaceTrustedDetailsByPublishedDetails(identityPhotosDirectory: URL, delegateManager: ObvIdentityDelegateManager) throws {
        guard let publishedDetails = self.publishedDetails else { return }
        try trustedDetails?.delete(delegateManager: delegateManager)
        self.trustedDetails = publishedDetails
        self.publishedDetails = nil
    }
    
}


// MARK: - Updating the photo

extension ContactGroupV2 {
    
    func photoNeedsToBeDownloaded(serverPhotoInfo: GroupV2.ServerPhotoInfo, delegateManager: ObvIdentityDelegateManager) -> Bool {
        let photoIsAvailable = trustedDetails?.hasPhotoForServerPhotoInfo(serverPhotoInfo, delegateManager: delegateManager) == true ||
        publishedDetails?.hasPhotoForServerPhotoInfo(serverPhotoInfo, delegateManager: delegateManager) == true
        return !photoIsAvailable
    }
    
    
    func updatePhoto(withData photoData: Data, serverPhotoInfo: GroupV2.ServerPhotoInfo, delegateManager: ObvIdentityDelegateManager) throws {
        if self.publishedDetails?.serverPhotoInfo == serverPhotoInfo {
            try self.publishedDetails?.setGroupPhoto(data: photoData, delegateManager: delegateManager)
        }
        if self.trustedDetails?.serverPhotoInfo == serverPhotoInfo {
            try self.trustedDetails?.setGroupPhoto(data: photoData, delegateManager: delegateManager)
        }
        // At this point, if the only difference between the published and the trusted details are the photos infos (the actual bytes of the photo being identical) we can replace the trusted details by the published details.
        if let publishedDetails = self.publishedDetails, let trustedDetails = self.trustedDetails {
            if trustedDetails.trustedDetailsAreIdenticalToOtherDetailsExceptForTheServerPhotoInfo(publishedDetails: publishedDetails, delegateManager: delegateManager) {
                try? replaceTrustedDetailsByPublishedDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory, delegateManager: delegateManager)
            }
        }
        let creationOrUpdateInitiator = self.creationOrUpdateInitiator
        assert(obvContext != nil)
        try? obvContext?.addContextDidSaveCompletionHandler { [weak self] error in
            guard error == nil else { return }
            guard let obvGroupV2 = self?.getObvGroupV2(delegateManager: delegateManager) else { assertionFailure(); return }
            ObvIdentityNotificationNew.groupV2WasUpdated(obvGroupV2: obvGroupV2, initiator: creationOrUpdateInitiator)
                .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
        }
    }
    
}



// MARK: - Convenience DB getters

extension ContactGroupV2 {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactGroupV2> {
        return NSFetchRequest<ContactGroupV2>(entityName: self.entityName)
    }

    
    struct Predicate {
        enum Key: String {
            case rawCategory = "rawCategory"
            case rawGroupUID = "rawGroupUID"
            case rawServerURL = "rawServerURL"
            case rawOwnedIdentity = "rawOwnedIdentity"
            case rawOtherMembers = "rawOtherMembers"
            case rawPendingMembers = "rawPendingMembers"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
        }
        static func forOwnedIdentity(ownedIdentity: OwnedIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, equalTo: ownedIdentity)
        }
        static func forOwnedCryptoId(_ ownedCryptoId: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withGroupIdentifier(_ groupIdentifier: GroupV2.Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawCategory, EqualToInt: groupIdentifier.category.rawValue),
                NSPredicate(Key.rawGroupUID, EqualToData: groupIdentifier.groupUID.raw),
                NSPredicate(Key.rawServerURL, EqualToUrl: groupIdentifier.serverURL),
            ])
        }
        static func withContactIdentityAmongMembersOrPendingMembers(_ contactIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                withContactIdentityAmongOtherMembers(contactIdentity),
                withContactIdentityAmongPendingMembers(contactIdentity),
            ])
        }
        private static func withContactIdentityAmongOtherMembers(_ contactIdentity: ObvCryptoIdentity) -> NSPredicate {
            let predicateChain = [Key.rawOtherMembers.rawValue,
                                  ContactGroupV2Member.Predicate.Key.rawContactIdentity.rawValue,
                                  ContactIdentity.Predicate.Key.cryptoIdentity.rawValue].joined(separator: ".")
            let predicateFormat = "ANY \(predicateChain) == %@"
            return NSPredicate(format: predicateFormat, contactIdentity)
        }
        private static func withContactIdentityAmongPendingMembers(_ contactIdentity: ObvCryptoIdentity) -> NSPredicate {
            let predicateChain = [Key.rawPendingMembers.rawValue,
                                  ContactGroupV2PendingMember.Predicate.Key.rawIdentity.rawValue].joined(separator: ".")
            let predicateFormat = "ANY \(predicateChain) == %@"
            
            return NSPredicate(format: predicateFormat, contactIdentity.getIdentity() as NSData)
        }
    }
    
    
    static func countAllContactGroupV2WithContact(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws -> Int {
        let request = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forOwnedCryptoId(ownedIdentity),
            Predicate.withContactIdentityAmongMembersOrPendingMembers(contactIdentity),
        ])
        request.fetchBatchSize = 1_000
        return try obvContext.count(for: request)
    }
    
    
    static func getContactGroupV2(withGroupIdentifier groupIdentifier: GroupV2.Identifier, of ownedIdentity: OwnedIdentity, delegateManager: ObvIdentityDelegateManager) throws -> ContactGroupV2? {
        
        guard let obvContext = ownedIdentity.obvContext else { assertionFailure(); throw Self.makeError(message: "Could not get ObvContext from OwnedIdentity") }
        
        let request = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forOwnedIdentity(ownedIdentity: ownedIdentity),
            Predicate.withGroupIdentifier(groupIdentifier),
        ])
        request.fetchLimit = 1
        
        let item = try obvContext.fetch(request).first
        item?.obvContext = obvContext
        item?.delegateManager = delegateManager
        return item
        
    }
    
    
    static func getAllObvGroupV2(of ownedIdentity: OwnedIdentity, delegateManager: ObvIdentityDelegateManager) throws -> Set<ObvGroupV2> {
        guard let obvContext = ownedIdentity.obvContext else { assertionFailure(); throw Self.makeError(message: "Could not get ObvContext from OwnedIdentity") }
        
        let request = Self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forOwnedIdentity(ownedIdentity: ownedIdentity),
        ])
        request.fetchBatchSize = 1_000
        
        let items = try obvContext.fetch(request)
        items.forEach { item in
            item.delegateManager = delegateManager
        }
        return Set(items.compactMap({ $0.getObvGroupV2(delegateManager: delegateManager) }))

    }
    
}


// MARK: - Other methods

extension ContactGroupV2 {
    
    private func getObvGroupV2(delegateManager: ObvIdentityDelegateManager) -> ObvGroupV2? {
        guard let ownedIdentity = self.ownedIdentity else { assertionFailure(); return nil }
        guard let groupIdentifier = self.groupIdentifier?.toObvGroupV2Identifier else { assertionFailure(); return nil }
        let otherMembers = Set(self.otherMembers.compactMap({ $0.identityAndPermissionsAndDetails?.toObvGroupV2IdentityAndPermissionsAndDetails(isPending: false) }))
        assert(otherMembers.count == self.otherMembers.count)
        let pendingMembers = Set(self.pendingMembers.compactMap({ $0.identityAndPermissionsAndDetails?.toObvGroupV2IdentityAndPermissionsAndDetails(isPending: true) }))
        assert(pendingMembers.count == self.pendingMembers.count)

        // Trusted details and photo

        let trustedDetailsAndPhoto: ObvGroupV2.DetailsAndPhoto
        do {
            guard let serializedGroupTrustedCoreDetails = self.trustedDetails?.serializedCoreDetails else { assertionFailure(); return nil }
            let url = self.trustedDetails?.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
            let trustedPhotoURLFromEngine: ObvGroupV2.DetailsAndPhoto.PhotoURLFromEngineType
            if let url = url {
                trustedPhotoURLFromEngine = .downloaded(url: url)
            } else if self.trustedDetails?.serverPhotoInfo == nil {
                trustedPhotoURLFromEngine = .none
            } else {
                trustedPhotoURLFromEngine = .downloading
            }
            trustedDetailsAndPhoto = ObvGroupV2.DetailsAndPhoto(serializedGroupCoreDetails: serializedGroupTrustedCoreDetails,
                                                                photoURLFromEngine: trustedPhotoURLFromEngine)
        }

        // Published details and photo

        let publishedDetailsAndPhoto: ObvGroupV2.DetailsAndPhoto?
        if let serializedGroupPublishedCoreDetails = self.publishedDetails?.serializedCoreDetails {
            let url = self.publishedDetails?.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
            let publishedPhotoURLFromEngine: ObvGroupV2.DetailsAndPhoto.PhotoURLFromEngineType
            if let url = url {
                publishedPhotoURLFromEngine = .downloaded(url: url)
            } else if self.publishedDetails?.serverPhotoInfo == nil {
                publishedPhotoURLFromEngine = .none
            } else {
                publishedPhotoURLFromEngine = .downloading
            }
            publishedDetailsAndPhoto = ObvGroupV2.DetailsAndPhoto(serializedGroupCoreDetails: serializedGroupPublishedCoreDetails,
                                                                  photoURLFromEngine: publishedPhotoURLFromEngine)
        } else {
            publishedDetailsAndPhoto = nil
        }

        // Construct and return an ObvGroupV2
        
        let obvGroupV2 = ObvGroupV2(groupIdentifier: groupIdentifier,
                                    ownIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity.cryptoIdentity),
                                    ownPermissions: allOwnPermissions,
                                    otherMembers: otherMembers.union(pendingMembers),
                                    trustedDetailsAndPhoto: trustedDetailsAndPhoto,
                                    publishedDetailsAndPhoto: publishedDetailsAndPhoto,
                                    updateInProgress: self.frozen)
        return obvGroupV2
    }
    
}



// MARK: - Sending notifications

extension ContactGroupV2 {

    override func willSave() {
        super.willSave()
        
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        } else if isDeleted {
            assert(valuesOnDeletion != nil)
        }
        
    }
    
    override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
            valuesOnDeletion = nil
            isRestoringBackup = false
            creationOrUpdateInitiator = .createdOrUpdatedBySomeoneElse
        }
        
        // We do not send any notification after inserting an object during a backup restore.
        guard !isRestoringBackup else { assert(isInserted); return }
        guard let delegateManager = self.delegateManager else { assertionFailure(); return }
        guard let notificationDelegate = delegateManager.notificationDelegate else { assertionFailure(); return }
        
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactGroupV2.entityName)

        if !isDeleted {
            
            guard let obvGroupV2 = getObvGroupV2(delegateManager: delegateManager) else { assertionFailure(); return }
            let creationOrUpdateInitiator = self.creationOrUpdateInitiator
            if isInserted {
                ObvIdentityNotificationNew.groupV2WasCreated(obvGroupV2: obvGroupV2, initiator: creationOrUpdateInitiator)
                    .postOnBackgroundQueue(within: notificationDelegate)
            } else if !changedKeys.isEmpty {
                ObvIdentityNotificationNew.groupV2WasUpdated(obvGroupV2: obvGroupV2, initiator: creationOrUpdateInitiator)
                    .postOnBackgroundQueue(within: notificationDelegate)
            }
            
        } else {
            guard let valuesOnDeletion = valuesOnDeletion else { assertionFailure(); return }
            ObvIdentityNotificationNew.groupV2WasDeleted(ownedIdentity: valuesOnDeletion.ownedIdentity, appGroupIdentifier: valuesOnDeletion.appGroupIdentifier)
                .postOnBackgroundQueue(within: notificationDelegate)
        }
        
        // Send a backupableManagerDatabaseContentChanged notification
        if isInserted || isDeleted || isUpdated || !changedKeys.isEmpty {
            guard let flowId = obvContext?.flowId else {
                os_log("Could not notify that this backupable manager database content changed", log: log, type: .fault)
                assertionFailure()
                return
            }
            ObvBackupNotification.backupableManagerDatabaseContentChanged(flowId: flowId)
                .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
        }

    }

}


// MARK: - For Backup purposes

extension ContactGroupV2 {
    
    var backupItem: ContactGroupV2BackupItem? {
        guard let rawTrustedDetails = self.rawTrustedDetails else { assertionFailure(); return nil }
        return ContactGroupV2BackupItem(groupVersion: self.groupVersion,
                                        ownGroupInvitationNonce: self.ownGroupInvitationNonce,
                                        rawBlobMainSeed: self.rawBlobMainSeed,
                                        rawBlobVersionSeed: self.rawBlobVersionSeed,
                                        rawCategory: self.rawCategory,
                                        rawGroupUID: self.rawGroupUID,
                                        rawOwnPermissions: self.rawOwnPermissions,
                                        rawServerURL: self.rawServerURL,
                                        rawGroupAdminServerAuthenticationPrivateKey: self.rawGroupAdminServerAuthenticationPrivateKey,
                                        rawVerifiedAdministratorsChain: self.rawVerifiedAdministratorsChain,
                                        rawOtherMembers: self.rawOtherMembers,
                                        rawPendingMembers: self.rawPendingMembers,
                                        rawPublishedDetails: self.rawPublishedDetails,
                                        rawTrustedDetails: rawTrustedDetails)
    }

}


struct ContactGroupV2BackupItem: Codable, Hashable, ObvErrorMaker {
    
    fileprivate let groupVersion: Int
    fileprivate let ownGroupInvitationNonce: Data
    fileprivate let rawBlobMainSeed: Data
    fileprivate let rawBlobVersionSeed: Data
    fileprivate let rawCategory: Int
    fileprivate let rawGroupUID: Data
    fileprivate let rawOwnPermissions: [String]
    fileprivate let rawServerURL: URL
    fileprivate let rawGroupAdminServerAuthenticationPrivateKey: Data?
    fileprivate let rawVerifiedAdministratorsChain: Data
    fileprivate let rawOtherMembers: Set<ContactGroupV2MemberBackupItem>
    fileprivate let rawPendingMembers: Set<ContactGroupV2PendingMemberBackupItem>
    fileprivate let rawPublishedDetails: ContactGroupV2DetailsBackupItem?
    fileprivate let rawTrustedDetails: ContactGroupV2DetailsBackupItem

    
    // Allows to prevent association failures in two items have identical variables
    private let transientUuid = UUID()

    static let errorDomain = "ContactGroupV2BackupItem"

    fileprivate init(groupVersion: Int, ownGroupInvitationNonce: Data, rawBlobMainSeed: Data, rawBlobVersionSeed: Data, rawCategory: Int, rawGroupUID: Data, rawOwnPermissions: String, rawServerURL: URL, rawGroupAdminServerAuthenticationPrivateKey: Data?, rawVerifiedAdministratorsChain: Data, rawOtherMembers: Set<ContactGroupV2Member>, rawPendingMembers: Set<ContactGroupV2PendingMember>, rawPublishedDetails: ContactGroupV2Details?, rawTrustedDetails: ContactGroupV2Details) {
        self.groupVersion = groupVersion
        self.ownGroupInvitationNonce = ownGroupInvitationNonce
        self.rawBlobMainSeed = rawBlobMainSeed
        self.rawBlobVersionSeed = rawBlobVersionSeed
        self.rawCategory = rawCategory
        self.rawGroupUID = rawGroupUID
        self.rawOwnPermissions = rawOwnPermissions.split(separator: ContactGroupV2.separatorForPermissions).map({ String($0) })
        self.rawServerURL = rawServerURL
        self.rawGroupAdminServerAuthenticationPrivateKey = rawGroupAdminServerAuthenticationPrivateKey
        self.rawVerifiedAdministratorsChain = rawVerifiedAdministratorsChain
        self.rawOtherMembers = Set(rawOtherMembers.compactMap({ $0.backupItem }))
        self.rawPendingMembers = Set(rawPendingMembers.map({ $0.backupItem }))
        self.rawPublishedDetails = rawPublishedDetails?.backupItem
        self.rawTrustedDetails = rawTrustedDetails.backupItem
    }


    enum CodingKeys: String, CodingKey {
        case groupVersion = "version"
        case ownGroupInvitationNonce = "invitation_nonce"
        case rawBlobMainSeed = "main_seed"
        case rawBlobVersionSeed = "version_seed"
        case rawCategory = "category"
        case rawGroupUID = "group_uid"
        case rawOwnPermissions = "permissions"
        case rawServerURL = "server_url"
        case rawGroupAdminServerAuthenticationPrivateKey = "encoded_admin_key"
        case rawVerifiedAdministratorsChain = "verified_admin_chain"
        case rawOtherMembers = "members"
        case rawPendingMembers = "pending_members"
        case details = "details" // Cannot be nil
        case trustedDetailsIfThereArePublishedDetails = "trusted_details" // Can be nil
    }
    
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(groupVersion, forKey: .groupVersion)
        try container.encode(ownGroupInvitationNonce, forKey: .ownGroupInvitationNonce)
        try container.encode(rawBlobMainSeed, forKey: .rawBlobMainSeed)
        try container.encode(rawBlobVersionSeed, forKey: .rawBlobVersionSeed)
        try container.encode(rawCategory, forKey: .rawCategory)
        try container.encode(rawGroupUID, forKey: .rawGroupUID)
        try container.encode(rawOwnPermissions, forKey: .rawOwnPermissions)
        try container.encode(rawServerURL, forKey: .rawServerURL)
        try container.encodeIfPresent(rawGroupAdminServerAuthenticationPrivateKey, forKey: .rawGroupAdminServerAuthenticationPrivateKey)
        try container.encode(rawVerifiedAdministratorsChain, forKey: .rawVerifiedAdministratorsChain)
        try container.encode(rawOtherMembers, forKey: .rawOtherMembers)
        try container.encodeIfNotEmpty(rawPendingMembers, forKey: .rawPendingMembers)
        // Special rules for backuping the details in a way that also works for the Android version of Olvid
        if let rawPublishedDetails = rawPublishedDetails {
            try container.encode(rawPublishedDetails, forKey: .details)
            try container.encode(rawTrustedDetails, forKey: .trustedDetailsIfThereArePublishedDetails)
        } else {
            try container.encode(rawTrustedDetails, forKey: .details)
            // Nothing to do for the .trustedDetailsIfThereArePublishedDetails key
        }
    }

    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.groupVersion = try values.decode(Int.self, forKey: .groupVersion)
        self.ownGroupInvitationNonce = try values.decode(Data.self, forKey: .ownGroupInvitationNonce)
        self.rawBlobMainSeed = try values.decode(Data.self, forKey: .rawBlobMainSeed)
        self.rawBlobVersionSeed = try values.decode(Data.self, forKey: .rawBlobVersionSeed)
        self.rawCategory = try values.decode(Int.self, forKey: .rawCategory)
        self.rawGroupUID = try values.decode(Data.self, forKey: .rawGroupUID)
        self.rawOwnPermissions = try values.decode([String].self, forKey: .rawOwnPermissions)
        self.rawServerURL = try values.decode(URL.self, forKey: .rawServerURL)
        self.rawGroupAdminServerAuthenticationPrivateKey = try values.decodeIfPresent(Data.self, forKey: .rawGroupAdminServerAuthenticationPrivateKey)
        self.rawVerifiedAdministratorsChain = try values.decode(Data.self, forKey: .rawVerifiedAdministratorsChain)
        self.rawOtherMembers = try values.decode(Set<ContactGroupV2MemberBackupItem>.self, forKey: .rawOtherMembers)
        self.rawPendingMembers = try values.decodeIfPresent(Set<ContactGroupV2PendingMemberBackupItem>.self, forKey: .rawPendingMembers) ?? Set<ContactGroupV2PendingMemberBackupItem>()
        if values.allKeys.contains(.trustedDetailsIfThereArePublishedDetails) {
            self.rawPublishedDetails = try values.decodeIfPresent(ContactGroupV2DetailsBackupItem.self, forKey: .details)
            self.rawTrustedDetails = try values.decode(ContactGroupV2DetailsBackupItem.self, forKey: .trustedDetailsIfThereArePublishedDetails)
        } else {
            self.rawTrustedDetails = try values.decode(ContactGroupV2DetailsBackupItem.self, forKey: .details)
            self.rawPublishedDetails = nil
        }
    }
    
    
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations, ownedIdentity: Data) throws {
        
        // Restore instance associated with this backup item
        
        let contactGroupV2 = ContactGroupV2(backupItem: self, ownedIdentity: ownedIdentity, within: obvContext)
        try associations.associate(contactGroupV2, to: self)
        
        // Restores the instances associated with the backup items depending on this backup item
        
        try rawOtherMembers.forEach { try $0.restoreInstance(within: obvContext, associations: &associations) }
        try rawPendingMembers.forEach { try $0.restoreInstance(within: obvContext, associations: &associations) }
        try rawPublishedDetails?.restoreInstance(within: obvContext, associations: &associations)
        try rawTrustedDetails.restoreInstance(within: obvContext, associations: &associations)
        
    }

    
    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        
        let contactGroupV2: ContactGroupV2 = try associations.getObject(associatedTo: self, within: obvContext)

        // Restore the relationships of this instance

        contactGroupV2.otherMembers = Set(try self.rawOtherMembers.map({ try associations.getObject(associatedTo: $0, within: obvContext) }))
        contactGroupV2.pendingMembers = Set(try self.rawPendingMembers.map({ try associations.getObject(associatedTo: $0, within: obvContext) }))
        // The rawOwnedIdentity relationship is set when restoring the relationships of the OwnedIdentity
        contactGroupV2.publishedDetails = try associations.getObjectIfPresent(associatedTo: self.rawPublishedDetails, within: obvContext)
        contactGroupV2.trustedDetails = try associations.getObject(associatedTo: self.rawTrustedDetails, within: obvContext)
        
        // Restore the relationships of this instance relationships

        try self.rawOtherMembers.forEach({ try $0.restoreRelationships(associations: associations, ownedIdentity: contactGroupV2.rawOwnedIdentityIdentity, within: obvContext) })
        try self.rawPendingMembers.forEach({ try $0.restoreRelationships(associations: associations, within: obvContext) })
        try self.rawPublishedDetails?.restoreRelationships(associations: associations, within: obvContext)
        try self.rawTrustedDetails.restoreRelationships(associations: associations, within: obvContext)

    }
    
}