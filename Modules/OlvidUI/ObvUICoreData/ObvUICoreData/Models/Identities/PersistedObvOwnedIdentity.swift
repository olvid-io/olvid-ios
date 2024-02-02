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
import ObvTypes
import ObvEngine
import os.log
import OlvidUtils
import ObvCrypto
import UI_ObvCircledInitials
import ObvSettings
import ObvEncoder
import Contacts


@objc(PersistedObvOwnedIdentity)
public final class PersistedObvOwnedIdentity: NSManagedObject, Identifiable, ObvErrorMaker, ObvIdentifiableManagedObject {
    
    public static let entityName = "PersistedObvOwnedIdentity"
    public static let errorDomain = "PersistedObvOwnedIdentity"
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedObvOwnedIdentity")

    // MARK: Properties

    @NSManaged public private(set) var apiKeyExpirationDate: Date?
    @NSManaged public private(set) var badgeCountForDiscussionsTab: Int // Does not take into account new messages from muted discussions (was numberOfNewMessages)
    @NSManaged public private(set) var badgeCountForInvitationsTab: Int
    @NSManaged private var capabilityGroupsV2: Bool
    @NSManaged private var capabilityOneToOneContacts: Bool
    @NSManaged private var capabilityWebrtcContinuousICE: Bool
    @NSManaged public private(set) var customDisplayName: String?
    @NSManaged public var fullDisplayName: String
    @NSManaged private(set) var identity: Data
    @NSManaged public private(set) var isActive: Bool
    @NSManaged public private(set) var isKeycloakManaged: Bool
    @NSManaged private var permanentUUID: UUID
    @NSManaged public private(set) var photoURL: URL?
    @NSManaged private var rawAPIKeyStatus: Int
    @NSManaged private var rawAPIPermissions: Int
    @NSManaged private var serializedIdentityCoreDetails: Data
    @NSManaged private var hiddenProfileHash: Data?
    @NSManaged private var hiddenProfileSalt: Data?
    
    // MARK: Relationships

    @NSManaged private(set) var contactGroups: Set<PersistedContactGroup>
    @NSManaged private(set) var contactGroupsV2: Set<PersistedGroupV2>
    @NSManaged public private(set) var contacts: Set<PersistedObvContactIdentity>
    @NSManaged public private(set) var invitations: Set<PersistedInvitation>
    @NSManaged public private(set) var devices: Set<PersistedObvOwnedDevice>

    // MARK: Variables
    
    public var sortedDevices: [PersistedObvOwnedDevice] {
        devices.sorted { device1, device2 in
            return device1.objectInsertionDate < device2.objectInsertionDate
        }
    }
    
    public var hasAnotherDeviceWithChannel: Bool {
        return devices.first(where: { $0.secureChannelStatus == .created }) != nil
    }

    public var isHidden: Bool {
        hiddenProfileHash != nil && hiddenProfileSalt != nil
    }
    
    public var identityCoreDetails: ObvIdentityCoreDetails {
        return try! ObvIdentityCoreDetails(serializedIdentityCoreDetails)
    }

    public var cryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: identity)
    }

    var customOrFullDisplayName: String {
        customDisplayName ?? fullDisplayName
    }

    private var changedKeys = Set<String>()

    public private(set) var apiKeyStatus: APIKeyStatus {
        get {
            let localStatus = APIKeyStatus(rawValue: rawAPIKeyStatus) ?? .free
            switch localStatus {
            case .valid, .freeTrial, .anotherOwnedIdentityHasValidAPIKey:
                return localStatus
            case .unknown, .licensesExhausted, .expired, .free, .awaitingPaymentGracePeriod, .awaitingPaymentOnHold, .freeTrialExpired:
                if let context = managedObjectContext, (localStatus == .free || localStatus == .unknown) {
                    let anotherProfileHasValiAPIKey = (try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: context).first(where: { $0.rawAPIKeyStatus == APIKeyStatus.valid.rawValue })) != nil
                    if anotherProfileHasValiAPIKey {
                        return .anotherOwnedIdentityHasValidAPIKey
                    }
                }
                return localStatus
            }
        }
        set {
            rawAPIKeyStatus = newValue.rawValue
        }
    }
    
    private var apiPermissions: APIPermissions {
        get {
            return APIPermissions(rawValue: rawAPIPermissions)
        }
        set {
            rawAPIPermissions = newValue.rawValue
        }
    }
    
    
    /// If this owned identity has the canCall permission, this method returns her crypto Id. Otherwise, it looks for another owned identity allowed to emit a call. If one is found, this methods returns her owned identity.
    /// If no owned identity has the canCall permission, this method returns `nil`.
    public var ownedCryptoIdAllowedToEmitSecureCall: ObvCryptoId? {
        if apiPermissions.contains(.canCall) {
            return self.cryptoId
        } else {
            // This owned identity hasn't the canCall permission. But if any other active non-hidden owned identity has the permission, we know this one will be allowed to make calls too.
            if let context = managedObjectContext {
                let anotherProfileThatHasCanCallPermission = try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: context)
                    .filter({ $0.cryptoId != self.cryptoId })
                    .first(where: {
                        // We do not directly access the apiPermissions var to prevent an infinite loop
                        let otherAPIPermissions = APIPermissions(rawValue: $0.rawAPIPermissions)
                        return otherAPIPermissions.contains(.canCall)
                    
                })
                return anotherProfileThatHasCanCallPermission?.cryptoId
            } else {
                return nil
            }
        }
    }

    
    /// The api permissions of this owned identity, taking into account the permissions of other owned identities that may "augment" the permissions.
    /// This variable is typically used when displaying the permissions to the user.
    public var effectiveAPIPermissions: APIPermissions {
        var effectiveAPIPermissions = self.apiPermissions
        if ownedCryptoIdAllowedToEmitSecureCall != nil {
            effectiveAPIPermissions.insert(.canCall)
        }
        return effectiveAPIPermissions
    }
    
        
    
    public var apiKeyElements: APIKeyElements {
        return APIKeyElements(
            status: apiKeyStatus,
            permissions: apiPermissions,
            expirationDate: apiKeyExpirationDate)
    }
    
    
    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity> {
        ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>(uuid: self.permanentUUID)
    }
    
    
    public var circledInitialsConfiguration: CircledInitialsConfiguration {
        .contact(initial: customDisplayName ?? fullDisplayName,
                 photo: .url(url: photoURL),
                 showGreenShield: isKeycloakManaged,
                 showRedShield: false,
                 cryptoId: cryptoId,
                 tintAdjustementMode: .normal)
    }

    public var totalBadgeCount: Int {
        return badgeCountForDiscussionsTab + badgeCountForInvitationsTab
    }
    
    
    public var asCNContact: CNContact {
        let contact = CNMutableContact()
        if let firstName = identityCoreDetails.firstName {
            contact.givenName = firstName
        }
        if let lastName = identityCoreDetails.lastName {
            contact.familyName = lastName
        }
        if let company = identityCoreDetails.company {
            contact.organizationName = company
        }
        if let position = identityCoreDetails.position {
            contact.jobTitle = position
        }
        if let customDisplayName {
            contact.nickname = customDisplayName
        }
        contact.contactType = .person
        return contact
    }
    
    
    // MARK: - Initializer
    
    public convenience init?(ownedIdentity: ObvOwnedIdentity, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedObvOwnedIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        do { self.serializedIdentityCoreDetails = try ownedIdentity.currentIdentityDetails.coreDetails.jsonEncode() } catch { return nil }
        self.fullDisplayName = ownedIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
        self.identity = ownedIdentity.cryptoId.getIdentity()
        self.isActive = true
        self.capabilityWebrtcContinuousICE = false
        self.isKeycloakManaged = ownedIdentity.isKeycloakManaged
        self.customDisplayName = nil
        self.badgeCountForDiscussionsTab = 0
        self.badgeCountForInvitationsTab = 0
        self.permanentUUID = UUID()
        self.apiKeyExpirationDate = nil
        self.apiKeyStatus = APIKeyStatus.free
        self.apiPermissions = APIPermissions()
        self.contacts = Set<PersistedObvContactIdentity>()
        self.invitations = Set<PersistedInvitation>()
        self.photoURL = ownedIdentity.currentIdentityDetails.photoURL
        self.hiddenProfileHash = nil
        self.hiddenProfileSalt = nil
    }

    
    public func update(with ownedIdentity: ObvOwnedIdentity) throws {
        guard self.identity == ownedIdentity.cryptoId.getIdentity() else {
            throw Self.makeError(message: "Trying to update an owned identity with the data of another owned identity")
        }
        self.serializedIdentityCoreDetails = try ownedIdentity.currentIdentityDetails.coreDetails.jsonEncode()
        self.fullDisplayName = ownedIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
        self.isActive = ownedIdentity.isActive
        self.isKeycloakManaged = ownedIdentity.isKeycloakManaged
        self.photoURL = ownedIdentity.currentIdentityDetails.photoURL
    }

    
    public func updatePhotoURL(with url: URL?) {
        self.photoURL = url
    }

    public func deactivate() {
        if self.isActive {
            self.isActive = false
        }
    }
    
    public func activate() {
        if !self.isActive {
            self.isActive = true
        }
    }
    
    public func delete() throws {
        guard let context = managedObjectContext else {
            throw ObvUICoreDataError.noContext
        }
        context.delete(self)
    }
    
    
    /// Returns `true` iff the custom name had to be changed in database
    public func setOwnedCustomDisplayName(to newCustomDisplayName: String?) -> Bool {
        let trimmed = newCustomDisplayName?.trimmingWhitespacesAndNewlinesAndMapToNilIfZeroLength()
        guard self.customDisplayName != trimmed else { return false }
        self.customDisplayName = trimmed
        return true
    }
    
    
    // MARK: - Helpers for backups

    var hiddenProfileHashAndSaltForBackup: (hash: Data, salt: Data)? {
        guard let hiddenProfileHash, let hiddenProfileSalt else { return nil }
        return (hiddenProfileHash, hiddenProfileSalt)
    }
     
    func setHiddenProfileHashAndSaltDuringBackupRestore(hash: Data, salt: Data) {
        self.hiddenProfileHash = hash
        self.hiddenProfileSalt = salt
    }

    
    var isBeingRestoredFromBackup = false
    
}


// MARK: - Contact Capabilities

extension PersistedObvOwnedIdentity {

    public func setContactCapabilities(to newCapabilities: Set<ObvCapability>) {
        for capability in ObvCapability.allCases {
            switch capability {
            case .webrtcContinuousICE:
                self.capabilityWebrtcContinuousICE = newCapabilities.contains(capability)
            case .oneToOneContacts:
                self.capabilityOneToOneContacts = newCapabilities.contains(capability)
            case .groupsV2:
                self.capabilityGroupsV2 = newCapabilities.contains(capability)
            }
        }
    }
    
    
    var allCapabilitites: Set<ObvCapability> {
        var capabilitites = Set<ObvCapability>()
        for capability in ObvCapability.allCases {
            switch capability {
            case .webrtcContinuousICE:
                if self.capabilityWebrtcContinuousICE {
                    capabilitites.insert(capability)
                }
            case .oneToOneContacts:
                if self.capabilityOneToOneContacts {
                    capabilitites.insert(capability)
                }
            case .groupsV2:
                if self.capabilityGroupsV2 {
                    capabilitites.insert(capability)
                }
            }
        }
        return capabilitites
    }
    
    
    public func supportsCapability(_ capability: ObvCapability) -> Bool {
        allCapabilitites.contains(capability)
    }

}


// MARK: - Owned devices

extension PersistedObvOwnedIdentity {
    
    public func syncWith(ownedDevicesWithinEngine: Set<ObvOwnedDevice>) throws {

        guard ownedDevicesWithinEngine.allSatisfy({
            $0.ownedCryptoId == self.cryptoId
        }) else {
            throw ObvUICoreDataError.unexpectedOwnedCryptoId
        }
        
        let deviceIdentifiersWithinApp = Set(devices.map(\.identifier))
        let deviceIdentifiersWithinEngine = Set(ownedDevicesWithinEngine.map(\.identifier))
        
        // Determine the devices to add/remove/update
        
        let deviceIdentifiersToRemove = deviceIdentifiersWithinApp.subtracting(deviceIdentifiersWithinEngine)
        let deviceIdentifiersToAdd = deviceIdentifiersWithinEngine.subtracting(deviceIdentifiersWithinApp)
        let deviceIdentifiersToUpdate = deviceIdentifiersWithinApp.intersection(deviceIdentifiersWithinEngine)

        // Remove devices
        
        let devicesToRemove = devices.filter({ deviceIdentifiersToRemove.contains($0.identifier) })
        for deviceToRemove in devicesToRemove {
            try deviceToRemove.deletePersistedObvOwnedDevice()
        }
        
        // Insert devices
        
        let devicesToAdd = ownedDevicesWithinEngine.filter({ deviceIdentifiersToAdd.contains($0.identifier) })
        for deviceToAdd in devicesToAdd {
            try PersistedObvOwnedDevice.createIfRequired(obvOwnedDevice: deviceToAdd, ownedIdentity: self)
        }

        // Update devices
        
        let devicesToUpdate = ownedDevicesWithinEngine.filter({ deviceIdentifiersToUpdate.contains($0.identifier) })
        for obvOwned in devicesToUpdate {
            try self.devices
                .first(where: { $0.identifier == obvOwned.identifier })?
                .updatePersistedObvOwnedDevice(with: obvOwned)
        }

    }
    
}


// MARK: - Hide/Unhide profile

extension PersistedObvOwnedIdentity {
    
    public func hideProfileWithPassword(_ password: String) throws {
        guard password.count >= ObvUICoreDataConstants.minimumLengthOfPasswordForHiddenProfiles else {
            throw Self.makeError(message: "Password is too short to hide profile")
        }
        guard try !anotherPasswordIfAPrefixOfThisPassword(password: password) else {
            throw Self.makeError(message: "Another password is the prefix of this password")
        }
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        let newHiddenProfileSalt = prng.genBytes(count: ObvUICoreDataConstants.seedLengthForHiddenProfiles)
        let newHiddenProfileHash = try Self.computehiddenProfileHash(password, salt: newHiddenProfileSalt)
        self.hiddenProfileSalt = newHiddenProfileSalt
        self.hiddenProfileHash = newHiddenProfileHash
    }
    
    
    public func unhideProfile() {
        if self.hiddenProfileHash != nil {
            self.hiddenProfileHash = nil
        }
        if self.hiddenProfileSalt != nil {
            self.hiddenProfileSalt = nil
        }
    }
    
    
    private func anotherPasswordIfAPrefixOfThisPassword(password: String) throws -> Bool {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let allHiddenOwnedIdentities = try Self.getAllHiddenOwnedIdentities(within: context)
        for hiddenOwnedIdentity in allHiddenOwnedIdentities {
            guard let hiddenProfileSalt = hiddenOwnedIdentity.hiddenProfileSalt, let hiddenProfileHash = hiddenOwnedIdentity.hiddenProfileHash else { assertionFailure(); continue }
            for length in ObvUICoreDataConstants.minimumLengthOfPasswordForHiddenProfiles...password.count {
                let prefix = String(password.prefix(length))
                let hashObtained = try Self.computehiddenProfileHash(prefix, salt: hiddenProfileSalt)
                if hashObtained == hiddenProfileHash {
                    return true
                }
            }
        }
        return false
    }
    
    
    private static func computehiddenProfileHash(_ password: String, salt: Data) throws -> Data {
        return try PBKDF.pbkdf2sha1(password: password, salt: salt, rounds: 1000, derivedKeyLength: 20)
    }
    
    
    private func isUnlockedUsingPassword(_ password: String) throws -> Bool {
        guard let hiddenProfileHash, let hiddenProfileSalt else { return false }
        let computedHash = try Self.computehiddenProfileHash(password, salt: hiddenProfileSalt)
        return hiddenProfileHash == computedHash
    }
    
    
    public static func passwordCanUnlockSomeHiddenOwnedIdentity(password: String, within context: NSManagedObjectContext) throws -> Bool {
        guard password.count >= ObvUICoreDataConstants.minimumLengthOfPasswordForHiddenProfiles else { return false }
        let hiddenOwnedIdentities = try Self.getAllHiddenOwnedIdentities(within: context)
        for hiddenOwnedIdentity in hiddenOwnedIdentities {
            if try hiddenOwnedIdentity.isUnlockedUsingPassword(password) {
                return true
            }
        }
        return false
    }
    
    
    public var isLastUnhiddenOwnedIdentity: Bool {
        get throws {
            guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find owned identity") }
            if isHidden { return false }
            let unhiddenOwnedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: context)
            assert(unhiddenOwnedIdentities.contains(self))
            return unhiddenOwnedIdentities.count <= 1
        }
    }

}

// MARK: - Receiving messages and attachments sent from a contact

extension PersistedObvOwnedIdentity {
    

    /// When  receiving an `ObvMessage` from a contact, we fetch the persisted contact indicated in the message and then call this method to create the `PersistedMessageReceived`.
    /// Returns all the `ObvAttachment` that are fully received, i.e., such that the `ReceivedFyleMessageJoinWithStatus` status is `.complete` and if the `Fyle` has a full file on disk.
    public func createOrOverridePersistedMessageReceived(obvMessage: ObvMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, overridePreviousPersistedMessage: Bool) throws -> (discussionPermanentID: DiscussionPermanentID, attachmentFullyReceivedOrCancelledByServer: [ObvAttachment]) {
        
        guard obvMessage.fromContactIdentity.ownedCryptoId == self.cryptoId else {
            assertionFailure()
            throw ObvUICoreDataError.unexpectedOwnedCryptoId
        }
        
        guard let contact = try PersistedObvContactIdentity.get(cryptoId: obvMessage.fromContactIdentity.contactCryptoId, ownedIdentity: self, whereOneToOneStatusIs: .any) else {
            throw ObvUICoreDataError.couldNotFindContact
        }
        
        let values = try contact.createOrOverridePersistedMessageReceived(
            obvMessage: obvMessage,
            messageJSON: messageJSON,
            returnReceiptJSON: returnReceiptJSON,
            overridePreviousPersistedMessage: overridePreviousPersistedMessage)
        
        return values
        
    }
    
}


// MARK: - Receiving messages and attachments sent from another owned device

extension PersistedObvOwnedIdentity {
    
    /// When  receiving an `ObvOwnedMessage` from another owned device, we fetch the persisted owned identity indicated in the message and then call this method to create the `PersistedMessageSent`.
    /// Returns all the `ObvOwnedAttachment` that are fully received, i.e., such that the `SentFyleMessageJoinWithStatus` status is `.complete` and if the `Fyle` has a full file on disk.
    public func createPersistedMessageSentFromOtherOwnedDevice(obvOwnedMessage: ObvOwnedMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?) throws -> [ObvOwnedAttachment] {

        guard obvOwnedMessage.ownedCryptoId == self.cryptoId else {
            throw ObvUICoreDataError.unexpectedOwnedCryptoId
        }
        
        // Determine the discussion or the group where the new PersistedMessageReceived should be inserted
        
        let attachmentFullyReceivedOrCancelledByServer: [ObvOwnedAttachment]
        
        if let oneToOneIdentifier = messageJSON.oneToOneIdentifier {
            
            let oneToneDiscussion = try fetchOneToOneDiscussion(with: oneToOneIdentifier)
            attachmentFullyReceivedOrCancelledByServer = try oneToneDiscussion.createPersistedMessageSentFromOtherOwnedDevice(
                from: self,
                obvOwnedMessage: obvOwnedMessage,
                messageJSON: messageJSON,
                returnReceiptJSON: returnReceiptJSON)
            
        } else if let groupIdentifier = messageJSON.groupIdentifier {
            
            let group = try fetchGroup(with: groupIdentifier)
            
            switch group {

            case .v1(group: let group):

                attachmentFullyReceivedOrCancelledByServer = try group.createPersistedMessageSentFromOtherOwnedDevice(
                    from: self,
                    obvOwnedMessage: obvOwnedMessage,
                    messageJSON: messageJSON,
                    returnReceiptJSON: returnReceiptJSON)
                
            case .v2(group: let group):

                attachmentFullyReceivedOrCancelledByServer = try group.createPersistedMessageSentFromOtherOwnedDevice(
                    from: self,
                    obvOwnedMessage: obvOwnedMessage,
                    messageJSON: messageJSON,
                    returnReceiptJSON: returnReceiptJSON)

            }

        } else {
            
            throw ObvUICoreDataError.couldNotDetermineTheOneToOneDiscussion
            
        }
        
        return attachmentFullyReceivedOrCancelledByServer
        
    }
    
    
    /// Returns `true` iff the attachment is cancelled or fully received (i.e., if the `SentFyleMessageJoinWithStatus` status is `.complete` and if the `Fyle` has a full file on disk).
    public func processObvOwnedAttachmentFromOtherOwnedDevice(obvOwnedAttachment: ObvOwnedAttachment) throws -> Bool {

        guard obvOwnedAttachment.ownedCryptoId == self.cryptoId else {
            throw ObvUICoreDataError.unexpectedOwnedCryptoId
        }
        
        guard let sentMessage = try PersistedMessageSent.getPersistedMessageSentFromOtherOwnedDevice(messageIdentifierFromEngine: obvOwnedAttachment.messageIdentifier, from: self) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageSent
        }
        
        let attachmentFullyReceivedOrCancelledByServer = try sentMessage.processObvOwnedAttachmentFromOtherOwnedDevice(obvOwnedAttachment)

        return attachmentFullyReceivedOrCancelledByServer
        
    }

    
    public func markAttachmentFromOwnedDeviceAsResumed(messageIdentifierFromEngine: Data, attachmentNumber: Int) throws {
        
        guard let sentMessage = try PersistedMessageSent.getPersistedMessageSentFromOtherOwnedDevice(messageIdentifierFromEngine: messageIdentifierFromEngine, from: self) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageSent
        }
        
        try sentMessage.markAttachmentFromOwnedDeviceAsResumed(attachmentNumber: attachmentNumber)

    }

    
    public func markAttachmentFromOwnedDeviceAsPaused(messageIdentifierFromEngine: Data, attachmentNumber: Int) throws {

        guard let sentMessage = try PersistedMessageSent.getPersistedMessageSentFromOtherOwnedDevice(messageIdentifierFromEngine: messageIdentifierFromEngine, from: self) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageSent
        }

        try sentMessage.markAttachmentFromOwnedDeviceAsPaused(attachmentNumber: attachmentNumber)

    }

    
    /// Returns the OneToOne discussion corresponding to the identifier. This method makes sure the discussion is one of this owned identity.
    private func fetchOneToOneDiscussion(with oneToOneIdentifier: OneToOneIdentifierJSON) throws -> PersistedOneToOneDiscussion {

        guard let contactCryptoId = oneToOneIdentifier.getContactIdentity(ownedIdentity: self.cryptoId) else {
            assertionFailure("This is really unexpected. This method should not have been called in the first place.")
            throw ObvUICoreDataError.couldNotDetermineContactCryptoId
        }
        
        guard let contact = try PersistedObvContactIdentity.get(cryptoId: contactCryptoId, ownedIdentity: self, whereOneToOneStatusIs: .any) else {
            throw ObvUICoreDataError.couldNotFindContactWithId(contactIdentifier: .init(contactCryptoId: contactCryptoId, ownedCryptoId: self.cryptoId))
        }

        guard let oneToOneDiscussion = contact.oneToOneDiscussion else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        return oneToOneDiscussion
        
    }
    
    
    private enum Group {
        case v1(group: PersistedContactGroup)
        case v2(group: PersistedGroupV2)
    }

    
    /// Helper method that fetches the group correspongin the ``GroupIdentifier``and that makes sure this contact is part of the group.
    private func fetchGroup(with groupIdentifier: GroupIdentifier) throws -> Group {
        
        switch groupIdentifier {
            
        case .groupV1(groupV1Identifier: let groupV1Identifier):
            
            guard let contactGroup = try PersistedContactGroup.getContactGroup(groupIdentifier: groupV1Identifier, ownedIdentity: self) else {
                throw ObvUICoreDataError.couldNotFindGroupV1InDatabase(groupIdentifier: groupV1Identifier)
            }
            
            return .v1(group: contactGroup)
            
        case .groupV2(groupV2Identifier: let groupV2Identifier):
            
            guard let group = try PersistedGroupV2.get(ownIdentity: self, appGroupIdentifier: groupV2Identifier) else {
                throw ObvUICoreDataError.couldNotFindGroupV2InDatabase(groupIdentifier: groupV2Identifier)
            }
                        
            return .v2(group: group)
            
        }

    }
    
    
    /// Helper method that fetches the group discussion correspongin the ``GroupIdentifier``and that makes sure this contact is part of the group.
    private func fetchGroupDiscussion(with groupIdentifier: GroupIdentifier) throws -> PersistedDiscussion {
        
        let group = try fetchGroup(with: groupIdentifier)
        
        switch group {
        case .v1(group: let group):
            
            return group.discussion
            
        case .v2(group: let group):
            
            guard let discussion = group.discussion else {
                throw ObvUICoreDataError.couldNotFindDiscussion
            }
            
            return discussion
            
        }
        
    }

    
    /// Called when an extended payload is received for a message sent from another device of the owned identity. If at least one extended payload was saved for one of the attachments, this method returns the objectID of the message. Otherwise, it returns `nil`.
    public func saveExtendedPayload(foundIn attachementImages: [NotificationAttachmentImage], for obvOwnedMessage: ObvOwnedMessage) throws -> TypeSafeManagedObjectID<PersistedMessageSent>? {
        
        guard obvOwnedMessage.ownedCryptoId == self.cryptoId else {
            throw ObvUICoreDataError.unexpectedOwnedCryptoId
        }
        
        guard let sentMessage = try PersistedMessageSent.getPersistedMessageSentFromOtherOwnedDevice(messageIdentifierFromEngine: obvOwnedMessage.messageIdentifierFromEngine, from: self) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageSent
        }

        let atLeastOneExtendedPayloadCouldBeSaved = try sentMessage.saveExtendedPayload(foundIn: attachementImages)
        
        return atLeastOneExtendedPayloadCouldBeSaved ? sentMessage.typedObjectID : nil
        
    }

    
}


// MARK: - Receiving discussion shared configurations

extension PersistedObvOwnedIdentity {
    
    /// Called when receiving a ``DiscussionSharedConfigurationJSON`` from a contact
    public func mergeReceivedDiscussionSharedConfigurationSentByContact(discussionSharedConfiguration: DiscussionSharedConfigurationJSON, messageUploadTimestampFromServer: Date, messageLocalDownloadTimestamp: Date, contactCryptoId: ObvCryptoId) throws -> (discussionId: DiscussionIdentifier, weShouldSendBackOurSharedSettings: Bool) {
        
        guard let persistedContact = try PersistedObvContactIdentity.get(cryptoId: contactCryptoId, ownedIdentity: self, whereOneToOneStatusIs: .any) else {
            throw ObvUICoreDataError.couldNotFindContact
        }

        let values = try persistedContact.mergeReceivedDiscussionSharedConfigurationSentByThisContact(
            discussionSharedConfiguration: discussionSharedConfiguration, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return values

    }
    
    
    /// Called when receiving a ``DiscussionSharedConfigurationJSON`` from another owned device of this ``PersistedObvOwnedIdentity``.
    public func mergeReceivedDiscussionSharedConfigurationSentByThisOwnedIdentity(discussionSharedConfiguration: DiscussionSharedConfigurationJSON, messageUploadTimestampFromServer: Date) throws -> (discussionId: DiscussionIdentifier, weShouldSendBackOurSharedSettings: Bool) {
                
        let returnedValues: (discussion: PersistedDiscussion, weShouldSendBackOurSharedSettings: Bool)
        let sharedSettingHadToBeUpdated: Bool
        
        if let oneToOneIdentifier = discussionSharedConfiguration.oneToOneIdentifier {
            
            let oneToneDiscussion = try fetchOneToOneDiscussion(with: oneToOneIdentifier)
            
            let (_sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettings) = try oneToneDiscussion.mergeDiscussionSharedConfiguration(
                discussionSharedConfiguration: discussionSharedConfiguration.sharedConfig,
                receivedFrom: self)
            
            sharedSettingHadToBeUpdated = _sharedSettingHadToBeUpdated
            returnedValues = (oneToneDiscussion, weShouldSendBackOurSharedSettings)
            
        } else if let groupIdentifier = discussionSharedConfiguration.groupIdentifier {
            
            let group = try fetchGroup(with: groupIdentifier)

            switch group {

            case .v1(group: let group):
                
                let (_sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettings) = try group.mergeReceivedDiscussionSharedConfiguration(
                    discussionSharedConfiguration: discussionSharedConfiguration.sharedConfig,
                    receivedFrom: self.cryptoId)
                
                sharedSettingHadToBeUpdated = _sharedSettingHadToBeUpdated
                returnedValues = (group.discussion, weShouldSendBackOurSharedSettings)
                
            case .v2(group: let group):

                guard let groupDiscussion = group.discussion else {
                    throw ObvUICoreDataError.couldNotFindDiscussion
                }

                let (_sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettings) = try group.mergeReceivedDiscussionSharedConfiguration(
                    discussionSharedConfiguration: discussionSharedConfiguration.sharedConfig,
                    receivedFrom: self)
                
                sharedSettingHadToBeUpdated = _sharedSettingHadToBeUpdated
                returnedValues = (groupDiscussion, weShouldSendBackOurSharedSettings)
                
            }

        } else {

            throw ObvUICoreDataError.couldNotFindDiscussion

        }

        // In all cases, if the shared settings had to be updated, we insert an appropriate message in the discussion
        
        if sharedSettingHadToBeUpdated {
            try returnedValues.discussion.insertSystemMessageIndicatingThatDiscussionSharedConfigurationWasUpdatedByOwnedIdentity(messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        }

        return try (returnedValues.discussion.identifier, returnedValues.weShouldSendBackOurSharedSettings)
        
    }
    
    
    /// Called when the owned identity decided to change the shared configuration of a discussion on the current device.
    public func replaceDiscussionSharedConfigurationSentByThisOwnedIdentity(with expiration: ExpirationJSON, inDiscussionWithId discussionId: DiscussionIdentifier) throws {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        guard discussion.ownedIdentity == self else {
            throw ObvUICoreDataError.unexpectedOwnedCryptoId
        }
        
        let sharedSettingHadToBeUpdated: Bool
        
        switch try discussion.kind {
            
        case .oneToOne:
            
            guard let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotFindDiscussion
            }
            
            sharedSettingHadToBeUpdated = try oneToOneDiscussion.replaceDiscussionSharedConfiguration(with: expiration, receivedFrom: self)
                        
        case .groupV1(withContactGroup: let group):
            
            guard let group else {
                throw ObvUICoreDataError.couldNotDetemineGroupV1
            }
            
            sharedSettingHadToBeUpdated = try group.replaceReceivedDiscussionSharedConfiguration(with: expiration, receivedFrom: self)

        case .groupV2(withGroup: let group):
            
            guard let group else {
                throw ObvUICoreDataError.couldNotDetemineGroupV2
            }
            
            sharedSettingHadToBeUpdated = try group.replaceReceivedDiscussionSharedConfiguration(with: expiration, receivedFrom: self)

        }
        
        if sharedSettingHadToBeUpdated {
            try? discussion.insertSystemMessageIndicatingThatDiscussionSharedConfigurationWasUpdatedByOwnedIdentity(
                messageUploadTimestampFromServer: nil)
        }
        
    }
    
}


// MARK: - Processing delete requests from the owned identity

extension PersistedObvOwnedIdentity {

    public func processWipeMessageRequestFromOtherOwnedDevice(deleteMessagesJSON: DeleteMessagesJSON, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        let messagesToDelete = deleteMessagesJSON.messagesToDelete

        let infos: [InfoAboutWipedOrDeletedPersistedMessage]
        
        if let oneToOneIdentifier = deleteMessagesJSON.oneToOneIdentifier {
            
            let oneToneDiscussion = try fetchOneToOneDiscussion(with: oneToOneIdentifier)
            infos = try oneToneDiscussion.processWipeMessageRequest(of: messagesToDelete, from: self.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

        } else if let groupIdentifier = deleteMessagesJSON.groupIdentifier {
            
            let group = try fetchGroup(with: groupIdentifier)
            
            switch group {
                
            case .v1(group: let group):
                
                infos = try group.processWipeMessageRequest(of: messagesToDelete, receivedFrom: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .v2(group: let group):
                
                infos = try group.processWipeMessageRequest(of: messagesToDelete, receivedFrom: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            }

        } else {

            throw ObvUICoreDataError.couldNotFindDiscussion

        }
        
        return infos

        
    }
    
    
    public func processMessageDeletionRequestRequestedFromCurrentDeviceOfThisOwnedIdentity(persistedMessageObjectIDs: Set<NSManagedObjectID>, deletionType: DeletionType) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        let infos = try persistedMessageObjectIDs.compactMap {
            try processMessageDeletionRequestRequestedFromCurrentDeviceOfThisOwnedIdentity(persistedMessageObjectID: $0, deletionType: deletionType)
        }
        
        return infos
        
    }
    
    
    func processMessageDeletionRequestRequestedFromCurrentDeviceOfThisOwnedIdentity(persistedMessageObjectID: NSManagedObjectID, deletionType: DeletionType) throws -> InfoAboutWipedOrDeletedPersistedMessage? {

        guard let context = self.managedObjectContext else {
            throw ObvUICoreDataError.noContext
        }
        
        guard let messageToDelete = try PersistedMessage.get(with: persistedMessageObjectID, within: context) else { return nil }
        
        let info: InfoAboutWipedOrDeletedPersistedMessage
        
        if let oneToOneDiscussion = messageToDelete.discussion as? PersistedOneToOneDiscussion {
            
            info = try oneToOneDiscussion.processMessageDeletionRequestRequestedFromCurrentDevice(
                of: self,
                messageToDelete: messageToDelete,
                deletionType: deletionType)
            
        } else if let groupDiscussion = (messageToDelete.discussion as? PersistedGroupDiscussion) {
            
            if let group = groupDiscussion.contactGroup {
                info = try group.processMessageDeletionRequestRequestedFromCurrentDevice(
                    of: self,
                    messageToDelete: messageToDelete,
                    deletionType: deletionType)
            } else {
                // Happens for disbanded groups
                info = try groupDiscussion.processMessageDeletionRequestRequestedFromCurrentDevice(
                    of: self,
                    messageToDelete: messageToDelete,
                    deletionType: deletionType)
            }
            
        } else if let groupDiscussion = messageToDelete.discussion as? PersistedGroupV2Discussion {
            
            if let group = groupDiscussion.group {
                info = try group.processMessageDeletionRequestRequestedFromCurrentDevice(
                    of: self,
                    messageToDelete: messageToDelete,
                    deletionType: deletionType)
            } else {
                // Happens for disbanded groups
                info = try groupDiscussion.processMessageDeletionRequestRequestedFromCurrentDevice(
                    of: self,
                    messageToDelete: messageToDelete,
                    deletionType: deletionType)
            }

        } else {
            
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindDiscussion
            
        }

        return info
        
    }
    
    
    public func processDiscussionDeletionRequestFromCurrentDeviceOfThisOwnedIdentity(discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, deletionType: DeletionType) throws {

        guard let context = self.managedObjectContext else {
            throw ObvUICoreDataError.noContext
        }
        
        guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID.objectID, within: context) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        switch try discussion.kind {
            
        case .oneToOne:
            
            guard let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotFindDiscussion
            }

            try oneToOneDiscussion.processDiscussionDeletionRequestFromCurrentDevice(of: self, deletionType: deletionType)
            if oneToOneDiscussion.status == .locked {
                incrementBadgeCountForDiscussionsTab(by: -discussion.numberOfNewMessages)
            }
                        
        case .groupV1(withContactGroup: let group):
            
            if let group {
                try group.processDiscussionDeletionRequestFromCurrentDevice(of: self, deletionType: deletionType)
            } else {
                // This happens when the group has been disbanded
                incrementBadgeCountForDiscussionsTab(by: -discussion.numberOfNewMessages)
                try discussion.processDiscussionDeletionRequestFromCurrentDevice(of: self, deletionType: deletionType)
            }

        case .groupV2(withGroup: let group):
            
            if let group {
                try group.processDiscussionDeletionRequestFromCurrentDevice(of: self, deletionType: deletionType)
            } else {
                // This happens when the group has been disbanded
                incrementBadgeCountForDiscussionsTab(by: -discussion.numberOfNewMessages)
                try discussion.processDiscussionDeletionRequestFromCurrentDevice(of: self, deletionType: deletionType)
            }
                
        }
        
    }
    
}


// MARK: - Processing discussion (all messages) remote wipe requests

extension PersistedObvOwnedIdentity {
    
    /// Called when receiving a request to wipe a discussion from another owned device.
    public func processThisOwnedIdentityRemoteRequestToWipeAllMessagesWithinDiscussion(deleteDiscussionJSON: DeleteDiscussionJSON, messageUploadTimestampFromServer: Date) throws {
        
        if let oneToOneIdentifier = deleteDiscussionJSON.oneToOneIdentifier {
            
            let oneToneDiscussion = try fetchOneToOneDiscussion(with: oneToOneIdentifier)
            try oneToneDiscussion.processRemoteRequestToWipeAllMessagesWithinThisDiscussion(from: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

        } else if let groupIdentifier = deleteDiscussionJSON.groupIdentifier {
            
            let group = try fetchGroup(with: groupIdentifier)
            
            switch group {
                
            case .v1(group: let group):
                
                try group.processRemoteRequestToWipeAllMessagesWithinThisGroupDiscussion(from: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            case .v2(group: let group):
                
                try group.processRemoteRequestToWipeAllMessagesWithinThisGroupDiscussion(from: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

            }

        } else {

            throw ObvUICoreDataError.couldNotFindDiscussion

        }
        
    }
    
    
    /// When receiving a `DeleteDiscussionJSON` request, we need to request the engine to cancel any processing sent message. This method allows to determine which sent messages are still processing.
    public func getObjectIDsOfPersistedMessageSentStillProcessing(deleteDiscussionJSON: DeleteDiscussionJSON) throws -> [TypeSafeManagedObjectID<PersistedMessageSent>] {
        
        guard let context = self.managedObjectContext else {
            throw ObvUICoreDataError.noContext
        }
        
        let persistedDiscussionObjectID: NSManagedObjectID
        
        if let oneToOneIdentifier = deleteDiscussionJSON.oneToOneIdentifier {
            
            let oneToneDiscussion = try fetchOneToOneDiscussion(with: oneToOneIdentifier)
            persistedDiscussionObjectID = oneToneDiscussion.objectID
            
        } else if let groupIdentifier = deleteDiscussionJSON.groupIdentifier {
            
            let groupDiscussion = try fetchGroupDiscussion(with: groupIdentifier)
            persistedDiscussionObjectID = groupDiscussion.objectID

        } else {
            
            throw ObvUICoreDataError.couldNotFindDiscussion
            
        }
        
        let allProcessingMessageSent = try PersistedMessageSent.getAllProcessingWithinDiscussion(persistedDiscussionObjectID: persistedDiscussionObjectID, within: context)
        return allProcessingMessageSent.map { $0.typedObjectID }

    }

}



// MARK: - Processing edit requests

extension PersistedObvOwnedIdentity {

    public func processUpdateMessageRequestFromThisOwnedIdentity(updateMessageJSON: UpdateMessageJSON, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {

        if let oneToOneIdentifier = updateMessageJSON.oneToOneIdentifier {
            
            let oneToneDiscussion = try fetchOneToOneDiscussion(with: oneToOneIdentifier)
            let updatedMessage = try oneToneDiscussion.processUpdateMessageRequest(updateMessageJSON, receivedFrom: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            return updatedMessage
            
        } else if let groupIdentifier = updateMessageJSON.groupIdentifier {
            
            let group = try fetchGroup(with: groupIdentifier)
            
            switch group {
                
            case .v1(group: let group):
                
                let updatedMessage = try group.processUpdateMessageRequest(updateMessageJSON, receivedFrom: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                return updatedMessage

            case .v2(group: let group):
                
                let updatedMessage = try group.processUpdateMessageRequest(updateMessageJSON, receivedFrom: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                return updatedMessage

            }
            
        } else {
            
            throw ObvUICoreDataError.couldNotFindDiscussion

        }
        
    }

    
    public func processLocalUpdateMessageRequestFromThisOwnedIdentity(persistedSentMessageObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, newTextBody: String?) throws -> PersistedMessage? {
        
        guard let context = self.managedObjectContext else {
            throw ObvUICoreDataError.noContext
        }
        
        guard let messageSent = try PersistedMessageSent.getPersistedMessageSent(objectID: persistedSentMessageObjectID, within: context) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageSent
        }
        
        guard let discussion = messageSent.discussion else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        switch try discussion.kind {
            
        case .oneToOne:
            
            guard let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotFindDiscussion
            }

            try oneToOneDiscussion.processLocalUpdateMessageRequest(from: self, for: messageSent, newTextBody: newTextBody)
                        
        case .groupV1(withContactGroup: let group):
            
            guard let group else {
                throw ObvUICoreDataError.couldNotDetemineGroupV1
            }

            try group.processLocalUpdateMessageRequest(from: self, for: messageSent, newTextBody: newTextBody)

        case .groupV2(withGroup: let group):
            
            guard let group else {
                throw ObvUICoreDataError.couldNotDetemineGroupV2
            }
            
            try group.processLocalUpdateMessageRequest(from: self, for: messageSent, newTextBody: newTextBody)

        }

        return messageSent
        
    }

    
    // MARK: - Process reaction requests
    
    /// Called when the owned identity requested to set (or update) a reaction on a message from the current device.
    public func processSetOrUpdateReactionOnMessageLocalRequestFromThisOwnedIdentity(messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) throws -> PersistedMessage? {
        
        guard let context = self.managedObjectContext else {
            throw ObvUICoreDataError.noContext
        }
        
        guard let message = try PersistedMessage.get(with: messageObjectID, within: context) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessage
        }
        
        guard let discussion = message.discussion else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        switch try discussion.kind {
            
        case .oneToOne:
            
            guard let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotFindDiscussion
            }

            try oneToOneDiscussion.processSetOrUpdateReactionOnMessageLocalRequest(from: self, for: message, newEmoji: newEmoji)
                        
        case .groupV1(withContactGroup: let group):
            
            guard let group else {
                throw ObvUICoreDataError.couldNotDetemineGroupV1
            }

            try group.processSetOrUpdateReactionOnMessageLocalRequest(from: self, for: message, newEmoji: newEmoji)

        case .groupV2(withGroup: let group):
            
            guard let group else {
                throw ObvUICoreDataError.couldNotDetemineGroupV2
            }
            
            try group.processSetOrUpdateReactionOnMessageLocalRequest(from: self, for: message, newEmoji: newEmoji)

        }

        return message

        
    }

    
    public func processSetOrUpdateReactionOnMessageRequestFromThisOwnedIdentity(reactionJSON: ReactionJSON, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        if let oneToOneIdentifier = reactionJSON.oneToOneIdentifier {
            
            let oneToneDiscussion = try fetchOneToOneDiscussion(with: oneToOneIdentifier)
            let updatedMessage = try oneToneDiscussion.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            return updatedMessage
            
        } else if let groupIdentifier = reactionJSON.groupIdentifier {
            
            let group = try fetchGroup(with: groupIdentifier)
            
            switch group {
                
            case .v1(group: let group):
                
                let updatedMessage = try group.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                return updatedMessage

            case .v2(group: let group):
                
                let updatedMessage = try group.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                return updatedMessage

            }
            
        } else {
            
            throw ObvUICoreDataError.couldNotFindDiscussion

        }

    }
    
    
    // MARK: - Process screen capture detections

    public func processLocalDetectionThatSensitiveMessagesWereCapturedByThisOwnedIdentity(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) throws -> (screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, recipients: Set<ObvCryptoId>) {
    
        guard let context = self.managedObjectContext else {
            throw ObvUICoreDataError.noContext
        }
        
        guard let discussion = try PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: context) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        let screenCaptureDetectionJSON: ScreenCaptureDetectionJSON
        let recipients: Set<ObvCryptoId>
        
        switch try discussion.kind {
            
        case .oneToOne:
            
            guard let oneToOneDiscussion = discussion as? PersistedOneToOneDiscussion else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotFindDiscussion
            }

            try oneToOneDiscussion.processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by: self)
            
            screenCaptureDetectionJSON = ScreenCaptureDetectionJSON(oneToOneIdentifier: try oneToOneDiscussion.oneToOneIdentifier)
            recipients = Set([oneToOneDiscussion.contactIdentity?.cryptoId].compactMap({$0}))
                                    
        case .groupV1(withContactGroup: let group):
            
            guard let group else {
                throw ObvUICoreDataError.couldNotDetemineGroupV1
            }

            try group.processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by: self)

            screenCaptureDetectionJSON = ScreenCaptureDetectionJSON(groupV1Identifier: try group.getGroupId())
            recipients = Set(group.contactIdentities.compactMap({ $0.cryptoId }))

        case .groupV2(withGroup: let group):
            
            guard let group else {
                throw ObvUICoreDataError.couldNotDetemineGroupV2
            }

            try group.processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by: self)

            screenCaptureDetectionJSON = ScreenCaptureDetectionJSON(groupV2Identifier: group.groupIdentifier)
            recipients = Set(group.contactsAmongOtherPendingAndNonPendingMembers.map({ $0.cryptoId }))

        }

        return (screenCaptureDetectionJSON, recipients)

    }
    
        
    public func processDetectionThatSensitiveMessagesWereCapturedByThisOwnedIdentity(screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, messageUploadTimestampFromServer: Date) throws {
        
        if let oneToOneIdentifier = screenCaptureDetectionJSON.oneToOneIdentifier {
            
            let oneToneDiscussion = try fetchOneToOneDiscussion(with: oneToOneIdentifier)
            try oneToneDiscussion.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            
        } else if let groupIdentifier = screenCaptureDetectionJSON.groupIdentifier {
            
            let group = try fetchGroup(with: groupIdentifier)
            
            switch group {
                
            case .v1(group: let group):
                
                try group.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
            case .v2(group: let group):
                
                try group.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: self, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
            }
            
        } else {
            
            throw ObvUICoreDataError.couldNotFindDiscussion

        }
        
    }
    
    
    // MARK: - Process requests for group v2 shared settings

    /// Returns our groupV2 discussion's shared settings in case we detect that it is pertinent to send them back to this contact
    public func processQuerySharedSettingsRequestFromThisOwnedIdentity(querySharedSettingsJSON: QuerySharedSettingsJSON) throws -> (weShouldSendBackOurSharedSettings: Bool, discussionId: DiscussionIdentifier) {
        
        if let oneToOneIdentifier = querySharedSettingsJSON.oneToOneIdentifier {
            
            let oneToneDiscussion = try fetchOneToOneDiscussion(with: oneToOneIdentifier)
            let discussionId = try oneToneDiscussion.identifier

            let weShouldSendBackOurSharedSettings = try oneToneDiscussion.processQuerySharedSettingsRequest(querySharedSettingsJSON: querySharedSettingsJSON)
            
            return (weShouldSendBackOurSharedSettings, discussionId)

        } else if let groupIdentifier = querySharedSettingsJSON.groupIdentifier {
            
            let group = try fetchGroup(with: groupIdentifier)
            
            switch group {
                
            case .v1(group: let group):
                
                let (weShouldSendBackOurSharedSettings, discussionId) = try group.processQuerySharedSettingsRequest(from: self, querySharedSettingsJSON: querySharedSettingsJSON)
                
                return (weShouldSendBackOurSharedSettings, discussionId)

            case .v2(group: let group):
                
                let (weShouldSendBackOurSharedSettings, discussionId) = try group.processQuerySharedSettingsRequest(from: self, querySharedSettingsJSON: querySharedSettingsJSON)
                
                return (weShouldSendBackOurSharedSettings, discussionId)
            }
            
        } else {
            
            throw ObvUICoreDataError.couldNotFindDiscussion

        }

    }

    
    // MARK: - Inserting system messages within discussions
    
    public func processContactIntroductionInvitationSentByThisOwnedIdentity(contactCryptoIdA: ObvCryptoId, contactCryptoIdB: ObvCryptoId) throws {
                
        try processIntroductionOfContact(contactCryptoIdA, to: contactCryptoIdB)
        try processIntroductionOfContact(contactCryptoIdB, to: contactCryptoIdA)

    }
    
    
    private func processIntroductionOfContact(_ contactCryptoIdA: ObvCryptoId, to contactCryptoIdB: ObvCryptoId) throws {
        
        guard let contactA = try PersistedObvContactIdentity.get(cryptoId: contactCryptoIdA, ownedIdentity: self, whereOneToOneStatusIs: .oneToOne) else {
            throw ObvUICoreDataError.couldNotFindOneToOneContact
        }

        guard let contactB = try PersistedObvContactIdentity.get(cryptoId: contactCryptoIdB, ownedIdentity: self, whereOneToOneStatusIs: .any) else {
            throw ObvUICoreDataError.couldNotFindOneToOneContact
        }

        guard let oneToOneDiscussion = contactA.oneToOneDiscussion else {
            throw ObvUICoreDataError.couldNotDetermineTheOneToOneDiscussion
        }
        
        try oneToOneDiscussion.oneToOneContactWasIntroducedTo(otherContact: contactB)
        
    }

}

// MARK: - Group v1

extension PersistedObvOwnedIdentity {
    
    /// Returns `true` iff the custom display name of the joined group had to be updated in database
    public func setCustomNameOfJoinedGroupV1(groupIdentifier: GroupV1Identifier, to newGroupNameCustom: String?) throws -> Bool {
        
        guard let group = try PersistedContactGroupJoined.getContactGroup(groupIdentifier: groupIdentifier, ownedIdentity: self) as? PersistedContactGroupJoined else {
            throw ObvUICoreDataError.couldNotFindGroupV1InDatabase(groupIdentifier: groupIdentifier)
        }

        let groupNameCustomHadToBeUpdated = try group.setGroupNameCustom(to: newGroupNameCustom)
        
        return groupNameCustomHadToBeUpdated
        
    }
    
    
    /// Returns `true` iff the personal note had to be updated in database
    public func setPersonalNoteOnGroupV1(groupIdentifier: GroupV1Identifier, newText: String?) throws -> Bool {
        
        guard let group = try PersistedContactGroup.getContactGroup(groupIdentifier: groupIdentifier, ownedIdentity: self) else {
            throw ObvUICoreDataError.couldNotFindGroupV1InDatabase(groupIdentifier: groupIdentifier)
        }

        let noteHadToBeUpdatedInDatabase = group.setNote(to: newText)
        
        return noteHadToBeUpdatedInDatabase
        
    }

}


// MARK: - Group v2

extension PersistedObvOwnedIdentity {
    
    public func createOrUpdateGroupV2(obvGroupV2: ObvGroupV2, createdByMe: Bool) throws -> PersistedGroupV2 {
        
        guard obvGroupV2.ownIdentity == self.cryptoId else {
            assertionFailure()
            throw ObvUICoreDataError.unexpectedOwnedCryptoId
        }
        
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        
        let group = try PersistedGroupV2.createOrUpdate(obvGroupV2: obvGroupV2, createdByMe: createdByMe, within: context)
        
        return group

    }
    
    
    /// Returns `true` iff the custom display name of the joined group had to be updated in database
    public func setCustomNameOfGroupV2(groupIdentifier: Data, to newGroupNameCustom: String?) throws -> Bool {
        
        guard let group = try PersistedGroupV2.get(ownIdentity: self, appGroupIdentifier: groupIdentifier) else {
            throw ObvUICoreDataError.couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
        }
        
        let groupNameCustomHadToBeUpdated = try group.updateCustomNameWith(with: newGroupNameCustom)
        
        return groupNameCustomHadToBeUpdated
        
    }

    
    public func updateCustomPhotoOfGroupV2(withGroupIdentifier groupIdentifier: Data, withPhoto newPhoto: UIImage?, within obvContext: ObvContext) throws {
        
        guard obvContext.context == self.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.inappropriateContext
        }
        
        guard let group = try PersistedGroupV2.get(ownIdentity: self, appGroupIdentifier: groupIdentifier) else {
            throw ObvUICoreDataError.couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
        }

        try group.updateCustomPhotoWithPhoto(newPhoto, within: obvContext)
        
    }
    
    
    /// Returns `true` iff the personal note had to be updated in database
    public func setPersonalNoteOnGroupV2(groupIdentifier: Data, newText: String?) throws -> Bool {
        
        guard let group = try PersistedGroupV2.get(ownIdentity: self, appGroupIdentifier: groupIdentifier) else {
            throw ObvUICoreDataError.couldNotFindGroupV2InDatabase(groupIdentifier: groupIdentifier)
        }

        let noteHadToBeUpdatedInDatabase = group.setNote(to: newText)
        
        return noteHadToBeUpdatedInDatabase
        
    }

}


// MARK: - Other methods for contacts

extension PersistedObvOwnedIdentity {
    
    /// Returns `true` iff the personal note had to be updated in database
    public func setPersonalNoteOnContact(contactCryptoId: ObvCryptoId, newText: String?) throws -> Bool {
        
        guard let contact = try PersistedObvContactIdentity.get(cryptoId: contactCryptoId, ownedIdentity: self, whereOneToOneStatusIs: .any) else {
            throw ObvUICoreDataError.couldNotFindContact
        }
        
        let noteHadToBeUpdatedInDatabase = contact.setNote(to: newText)
        
        return noteHadToBeUpdatedInDatabase
        
    }
    
}


// MARK: - Utils

extension PersistedObvOwnedIdentity {
    
    public func set(apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?) {
        if self.apiKeyStatus != apiKeyStatus {
            self.apiKeyStatus = apiKeyStatus
        }
        if self.apiPermissions != apiPermissions {
            self.apiPermissions = apiPermissions
        }
        if self.apiKeyExpirationDate != apiKeyExpirationDate {
            self.apiKeyExpirationDate = apiKeyExpirationDate
        }
    }
        
    
    public func getPersistedMessageReceivedCorrespondingTo(limitedVisibilityMessageOpenedJSON: LimitedVisibilityMessageOpenedJSON) throws -> PersistedMessageReceived? {
        
        if let oneToOneIdentifier = limitedVisibilityMessageOpenedJSON.oneToOneIdentifier {
            
            let oneToneDiscussion = try fetchOneToOneDiscussion(with: oneToOneIdentifier)
            return try oneToneDiscussion.getPersistedMessageReceivedCorrespondingTo(messageReference: limitedVisibilityMessageOpenedJSON.messageReference)
            
        } else if let groupIdentifier = limitedVisibilityMessageOpenedJSON.groupIdentifier {
            
            let group = try fetchGroup(with: groupIdentifier)
            
            switch group {

            case .v1(group: let group):

                return try group.discussion.getPersistedMessageReceivedCorrespondingTo(messageReference: limitedVisibilityMessageOpenedJSON.messageReference)
                
            case .v2(group: let group):

                guard let discussion = group.discussion else{
                    throw ObvUICoreDataError.couldNotFindDiscussion
                }
                
                return try discussion.getPersistedMessageReceivedCorrespondingTo(messageReference: limitedVisibilityMessageOpenedJSON.messageReference)

            }

        } else {
            
            throw ObvUICoreDataError.couldNotDetermineTheOneToOneDiscussion
            
        }

    }
    
    
    public func isDiscussionActive(discussionId: DiscussionIdentifier) throws -> Bool {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        return discussion.status == .active
        
    }
    
}


// MARK: - Handling badge counts for tabs

extension PersistedObvOwnedIdentity {
    
    /// Refreshes the badge count for the discussions tab. Called during bootstrap.
    /// Note that this **cannot** be called in a context including pending changes since those will **not** be taken into account (this is a limitation of Core Data, see https://developer.apple.com/documentation/coredata/nsfetchrequest/1506724-includespendingchanges).
    public func refreshBadgeCountForDiscussionsTab() throws {
        guard self.managedObjectContext != nil else { assertionFailure(); throw Self.makeError(message: "Cannot find context") }
        let newNumberOfNewMessages = try PersistedDiscussion.countSumOfNewMessagesWithinUnmutedDiscussionsForOwnedIdentity(self)
        let numberOfMutedDiscussionsMentioningOwnedIdentity = try PersistedDiscussion.countNumberOfMutedDiscussionsWithNewMessageMentioningOwnedIdentity(self)
        let newBadgeCountForDiscussionsTab = newNumberOfNewMessages + numberOfMutedDiscussionsMentioningOwnedIdentity
        if self.badgeCountForDiscussionsTab != newBadgeCountForDiscussionsTab {
            self.badgeCountForDiscussionsTab = newBadgeCountForDiscussionsTab
        }
    }
    
    
    /// Refreshes the badge count for the discussions tab. Called during bootstrap and each time a significant change occurs at the ``PersistedInvitation`` level.
    /// To the contrary of ``PersistedObvOwnedIdentity.refreshBadgeCountForDiscussionsTab()``, this method can be called within the context that updated a ``PersistedInvitation`` since the count method we used does take pending changes into account.
    public func refreshBadgeCountForInvitationsTab() throws {
        guard self.managedObjectContext != nil else { assertionFailure(); throw Self.makeError(message: "Cannot find context") }
        let newBadgeCountForInvitationsTab = try PersistedInvitation.computeBadgeCountForInvitationsTab(of: self)
        if self.badgeCountForInvitationsTab != newBadgeCountForInvitationsTab {
            self.badgeCountForInvitationsTab = newBadgeCountForInvitationsTab
        }
    }
    

    /// Called exclusively by a persisted discussion of this owned identity, when it updates its own number of new messages, or when it updates the Boolean indicating that a new message mentions an this owned identity.
    /// This method is required as ``PersistedObvOwnedIdentity.refreshBadgeCountForDiscussionsTab()`` cannot be called atomically with changes made at the ``PersistedDiscussion`` level.
    func incrementBadgeCountForDiscussionsTab(by value: Int) {
        guard value != 0 else { return }
        self.badgeCountForDiscussionsTab = max(0, self.badgeCountForDiscussionsTab + value)
    }
    
}


// MARK: - Allow reading messages with limited visibility

extension PersistedObvOwnedIdentity {
    
    public func userWantsToReadReceivedMessageWithLimitedVisibility(discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier, dateWhenMessageWasRead: Date, requestedOnAnotherOwnedDevice: Bool) throws -> InfoAboutWipedOrDeletedPersistedMessage? {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussionWithId(discussionId: discussionId)
        }
        
        return try discussion.userWantsToReadReceivedMessageWithLimitedVisibility(messageId: messageId, dateWhenMessageWasRead: dateWhenMessageWasRead, requestedOnAnotherOwnedDevice: requestedOnAnotherOwnedDevice)
        
    }
    
    
    /// Returns an array of the received message identifiers that were read.
    public func userWantsToAllowReadingAllReceivedMessagesReceivedThatRequireUserAction(discussionId: DiscussionIdentifier, dateWhenMessageWasRead: Date) throws -> ([InfoAboutWipedOrDeletedPersistedMessage], [ReceivedMessageIdentifier]) {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }

        return try discussion.userWantsToAllowReadingAllReceivedMessagesReceivedThatRequireUserAction(dateWhenMessageWasRead: dateWhenMessageWasRead)
        
    }

    
    
    public func getLimitedVisibilityMessageOpenedJSON(discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) throws -> LimitedVisibilityMessageOpenedJSON {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }

        return try discussion.getLimitedVisibilityMessageOpenedJSON(messageId: messageId)
    }
    
}


// MARK: - Marking received messages as not new

extension PersistedObvOwnedIdentity {
    
    public func markReceivedMessageAsNotNew(discussionId: DiscussionIdentifier, receivedMessageId: ReceivedMessageIdentifier, dateWhenMessageTurnedNotNew: Date) throws -> Date? {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }

        let lastReadMessageServerTimestamp = try discussion.markReceivedMessageAsNotNew(receivedMessageId: receivedMessageId, dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)
        
        return lastReadMessageServerTimestamp
        
    }

    
    public func markAllMessagesAsNotNew(discussionId: DiscussionIdentifier, untilDate: Date?, dateWhenMessageTurnedNotNew: Date) throws -> Date? {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussionWithId(discussionId: discussionId)
        }

        let lastReadMessageServerTimestamp = try discussion.markAllMessagesAsNotNew(untilDate: untilDate, dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)
        
        return lastReadMessageServerTimestamp

    }

    
    public func markAllMessagesAsNotNew(discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier], dateWhenMessageTurnedNotNew: Date) throws -> Date? {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussionWithId(discussionId: discussionId)
        }

        let lastReadMessageServerTimestamp = try discussion.markAllMessagesAsNotNew(messageIds: messageIds, dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)
        
        return lastReadMessageServerTimestamp
        
    }
    
    
    public func getDiscussionReadJSON(discussionId: DiscussionIdentifier, lastReadMessageServerTimestamp: Date) throws -> DiscussionReadJSON {

        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussionWithId(discussionId: discussionId)
        }

        switch try discussion.kind {
        case .oneToOne(withContactIdentity: let contact):
            guard let contactCryptoId = contact?.cryptoId else {
                throw ObvUICoreDataError.couldNotFindContact
            }
            return DiscussionReadJSON(
                lastReadMessageServerTimestamp: lastReadMessageServerTimestamp,
                oneToOneIdentifier: .init(ownedCryptoId: self.cryptoId, contactCryptoId: contactCryptoId))
        case .groupV1(withContactGroup: let group):
            guard let groupV1Identifier = try group?.getGroupId() else {
                throw ObvUICoreDataError.couldNotDetemineGroupV1
            }
            return DiscussionReadJSON(
                lastReadMessageServerTimestamp: lastReadMessageServerTimestamp,
                groupV1Identifier: groupV1Identifier)
        case .groupV2(withGroup: let group):
            guard let groupV2Identifier = group?.groupIdentifier else {
                throw ObvUICoreDataError.couldNotDetemineGroupV2
            }
            return DiscussionReadJSON(
                lastReadMessageServerTimestamp: lastReadMessageServerTimestamp,
                groupV2Identifier: groupV2Identifier)
        }

    }
    
}


// MARK: - Getting discussions

extension PersistedObvOwnedIdentity {
    
    public func getPersistedDiscussion(withDiscussionId discussionId: DiscussionIdentifier) throws -> PersistedDiscussion {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }

        return discussion
        
    }
    
}


// MARK: - Getting messages objectIDs for refreshing them in the view context and other

extension PersistedObvOwnedIdentity {
    
    public func getObjectIDOfReceivedMessage(discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) throws -> NSManagedObjectID {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        return try discussion.getObjectIDOfReceivedMessage(messageId: messageId)
        
    }
    
    
    public func getReceivedMessageTypedObjectID(discussionId: DiscussionIdentifier, receivedMessageId: ReceivedMessageIdentifier) throws -> TypeSafeManagedObjectID<PersistedMessageReceived> {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        return try discussion.getReceivedMessageTypedObjectID(receivedMessageId: receivedMessageId)
        
    }
    
    
    public static func getDiscussionIdentifiers(from persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> (ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier) {
        
        guard let discussion = try PersistedDiscussion.get(objectID: persistedDiscussionObjectID.objectID, within: context) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }

        guard let ownedIdentity = discussion.ownedIdentity else {
            throw ObvUICoreDataError.couldNotFindOwnedIdentity
        }
        
        return (ownedIdentity.cryptoId, try discussion.identifier)
        
    }
    
    
    public static func getDiscussionIdentifiers(from draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, within context: NSManagedObjectContext) throws -> (ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier) {
        
        guard let draft = try PersistedDraft.getManagedObject(withPermanentID: draftPermanentID, within: context) else {
            throw ObvUICoreDataError.couldNotFindDraft
        }
        
        let discussion = draft.discussion
        
        guard let ownedIdentity = discussion.ownedIdentity else {
            throw ObvUICoreDataError.couldNotFindOwnedIdentity
        }

        return (ownedIdentity.cryptoId, try discussion.identifier)

    }
    
    
    public func getDiscussionObjectID(discussionId: DiscussionIdentifier) throws -> NSManagedObjectID {
        
        guard let discussion = try PersistedDiscussion.getPersistedDiscussion(ownedIdentity: self, discussionId: discussionId) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }

        return discussion.objectID
        
    }
    
}


// MARK: - Convenience DB getters

extension PersistedObvOwnedIdentity {
    
    struct Predicate {
        enum Key: String {
            // Properties
            case apiKeyExpirationDate = "apiKeyExpirationDate"
            case badgeCountForDiscussionsTab = "badgeCountForDiscussionsTab"
            case badgeCountForInvitationsTab = "badgeCountForInvitationsTab"
            case capabilityGroupsV2 = "capabilityGroupsV2"
            case capabilityOneToOneContacts = "capabilityOneToOneContacts"
            case capabilityWebrtcContinuousICE = "capabilityWebrtcContinuousICE"
            case customDisplayName = "customDisplayName"
            case fullDisplayName = "fullDisplayName"
            case identity = "identity"
            case isActive = "isActive"
            case isKeycloakManaged = "isKeycloakManaged"
            case permanentUUID = "permanentUUID"
            case photoURL = "photoURL"
            case rawAPIKeyStatus = "rawAPIKeyStatus"
            case rawAPIPermissions = "rawAPIPermissions"
            case serializedIdentityCoreDetails = "serializedIdentityCoreDetails"
            case hiddenProfileHash = "hiddenProfileHash"
            case hiddenProfileSalt = "hiddenProfileSalt"
            // Relationships
            case contactGroups = "contactGroups"
            case contactGroupsV2 = "contactGroupsV2"
            case contacts = "contacts"
            case invitations = "invitations"
        }
        static func persistedObvOwnedIdentity(withObjectID typedObjectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>) -> NSPredicate {
            NSPredicate(withObjectID: typedObjectID.objectID)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.identity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func excludingOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSCompoundPredicate(notPredicateWithSubpredicate: NSPredicate(Key.identity, EqualToData: ownedCryptoId.getIdentity()))
        }
        static func withOwnedIdentityIdentity(_ ownedIdentityIdentity: Data) -> NSPredicate {
            NSPredicate(Key.identity, EqualToData: ownedIdentityIdentity)
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>) -> NSPredicate {
            NSPredicate(Key.permanentUUID, EqualToUuid: permanentID.uuid)
        }
        static func isHidden(_ value: Bool) -> NSPredicate {
            let isHiddenPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.hiddenProfileHash),
                NSPredicate(withNonNilValueForKey: Key.hiddenProfileSalt),
            ])
            return value ? isHiddenPredicate : NSCompoundPredicate(notPredicateWithSubpredicate: isHiddenPredicate)
        }
        static func whereIsActiveIs(_ isActive: Bool) -> NSPredicate {
            NSPredicate(Key.isActive, is: isActive)
        }
        static func isKeycloakManaged(is value: Bool) -> NSPredicate {
            NSPredicate(Key.isKeycloakManaged, is: value)
        }
    }

    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedObvOwnedIdentity> {
        return NSFetchRequest<PersistedObvOwnedIdentity>(entityName: self.entityName)
    }

    
    public static func deleteOwnedIdentity(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        guard let ownedIdentity = try get(cryptoId: ownedCryptoId, within: context) else { return }
        try ownedIdentity.delete()
    }
    
    
    static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(cryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(cryptoId)
        return try context.fetch(request).first
    }

    
    public static func getHiddenOwnedIdentity(password: String, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let allHiddenOwnedIdentities = try Self.getAllHiddenOwnedIdentities(within: context)
        return try allHiddenOwnedIdentities.first(where: { try $0.isUnlockedUsingPassword(password) })
    }
    
    static func get(identity: Data, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withOwnedIdentityIdentity(identity)
        return try context.fetch(request).first
    }

    
    public static func get(persisted obvOwnedIdentity: ObvOwnedIdentity, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(obvOwnedIdentity.cryptoId)
        return try context.fetch(request).first
    }

    
    public static func getAll(within context: NSManagedObjectContext) throws -> [PersistedObvOwnedIdentity] {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        return try context.fetch(request)
    }
    
    
    public static func getCryptoIdsOfAllActiveOwnedIdentities(within context: NSManagedObjectContext) throws -> Set<ObvCryptoId> {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.whereIsActiveIs(true)
        request.propertiesToFetch = [Predicate.Key.identity.rawValue]
        let ownedIdentities = try context.fetch(request)
        return Set(ownedIdentities.map({ $0.cryptoId }))
    }
    
    
    public static func countCryptoIdsOfAllActiveNonHiddenNonKeycloakOwnedIdentities(within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.whereIsActiveIs(true),
            Predicate.isHidden(false),
            Predicate.isKeycloakManaged(is: false),
        ])
        return try context.count(for: request)
    }
    
    
    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        return try context.existingObject(with: objectID) as? PersistedObvOwnedIdentity
    }

    
    public static func get(objectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.persistedObvOwnedIdentity(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    public static func getAllNonHiddenOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedObvOwnedIdentity] {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.isHidden(false)
        request.sortDescriptors = [
            NSSortDescriptor(key: Predicate.Key.customDisplayName.rawValue, ascending: true),
            NSSortDescriptor(key: Predicate.Key.fullDisplayName.rawValue, ascending: true),
        ]
        return try context.fetch(request)
    }

    
    public static func getAllHiddenOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedObvOwnedIdentity] {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.isHidden(true)
        return try context.fetch(request)
    }


    /// Internal type used in ``static PersistedObvOwnedIdentity.countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId:badgesToSum:within:)``.
    private enum BadgeTypeForSum {
        case discussions
        case invitations
    }
    
    /// This method uses aggregate functions to return the sum of the number of new messages or new invitations for owned identities but the one excluded.
    ///
    /// This is used when computing the app badge (in which case, `excludedOwnedCryptoId` is nil) and when evaluating if a red dot should be shown in the top left owned profile picture view (in which case, we want to exclude that owned identity).
    private static func countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId: ObvCryptoId?, badgesToSum: BadgeTypeForSum, within context: NSManagedObjectContext) throws -> Int {
        
        // Create an expression description that will allow to aggregate the values of the numberOfNewMessages column
        let expressionDescription = NSExpressionDescription()
        expressionDescription.name = "sumOfBadgeCounts"
        
        switch badgesToSum {
        case .discussions:
            expressionDescription.expression = NSExpression(format: "@sum.\(Predicate.Key.badgeCountForDiscussionsTab.rawValue)")
        case .invitations:
            expressionDescription.expression = NSExpression(format: "@sum.\(Predicate.Key.badgeCountForInvitationsTab.rawValue)")
        }
        
        expressionDescription.expressionResultType = .integer64AttributeType
        
        // Create a predicate that will restrict to the discussions of the owned identity
        let excludingOwnedCryptoIdPredicate: NSPredicate
        if let excludedOwnedCryptoId {
            excludingOwnedCryptoIdPredicate = Predicate.excludingOwnedCryptoId(excludedOwnedCryptoId)
        } else {
            excludingOwnedCryptoIdPredicate = NSPredicate(value: true)
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            excludingOwnedCryptoIdPredicate,
            Predicate.isHidden(false),
        ])
        
        // Create the fetch request
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.predicate = predicate
        request.propertiesToFetch = [expressionDescription]
        request.includesPendingChanges = true
        guard let results = try context.fetch(request).first as? [String: Int] else { throw makeError(message: "Could cast fetched result") }
        guard let sumOfNumberOfNewMessages = results["sumOfBadgeCounts"] else { throw makeError(message: "Could not get sumOfBadgeCounts") }
        return sumOfNumberOfNewMessages
    }
    
    
    public static func computeAppBadgeValue(within context: NSManagedObjectContext) throws -> Int {
        let sumOfBadgeCountsOfDiscussionsTabs = try countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId: nil, badgesToSum: .discussions, within: context)
        let sumOfBadgeCountsOfInvitationsTabs = try countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId: nil, badgesToSum: .invitations, within: context)
        return sumOfBadgeCountsOfDiscussionsTabs + sumOfBadgeCountsOfInvitationsTabs
    }
    
    
    public static func shouldShowRedDotOnTheProfilePictureView(of ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Bool {
        let sumOfBadgeCountsOfDiscussionsTabs = try countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId: ownedCryptoId, badgesToSum: .discussions, within: context)
        let sumOfBadgeCountsOfInvitationsTabs = try countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId: ownedCryptoId, badgesToSum: .invitations, within: context)
        let sum = sumOfBadgeCountsOfDiscussionsTabs + sumOfBadgeCountsOfInvitationsTabs
        return sum > 0
    }
}


// MARK: - Sending notifications on change

extension PersistedObvOwnedIdentity {
    
    public override func willSave() {
        super.willSave()
        if !isInserted && isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }

    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
        }

        if isInserted {
            let notification = ObvMessengerCoreDataNotification.newPersistedObvOwnedIdentity(ownedCryptoId: self.cryptoId, isActive: self.isActive)
            notification.postOnDispatchQueue()
        }
        
        if !isDeleted {
            
            if changedKeys.contains(Predicate.Key.isActive.rawValue) {
                if self.isActive {
                    let notification = ObvMessengerCoreDataNotification.ownedIdentityWasReactivated(ownedIdentityObjectID: self.objectID)
                    notification.postOnDispatchQueue()
                } else {
                    let notification = ObvMessengerCoreDataNotification.ownedIdentityWasDeactivated(ownedIdentityObjectID: self.objectID)
                    notification.postOnDispatchQueue()
                }
            }
            
            if changedKeys.contains(Predicate.Key.fullDisplayName.rawValue) ||
                changedKeys.contains(Predicate.Key.photoURL.rawValue) ||
                changedKeys.contains(Predicate.Key.customDisplayName.rawValue) ||
                changedKeys.contains(Predicate.Key.isKeycloakManaged.rawValue) {
                ObvMessengerCoreDataNotification.ownedCircledInitialsConfigurationDidChange(
                    ownedIdentityPermanentID: objectPermanentID,
                    ownedCryptoId: cryptoId,
                    newOwnedCircledInitialsConfiguration: circledInitialsConfiguration)
                .postOnDispatchQueue()
            }
            
            if !isBeingRestoredFromBackup && (changedKeys.contains(Predicate.Key.hiddenProfileSalt.rawValue) || changedKeys.contains(Predicate.Key.hiddenProfileHash.rawValue)) {
                ObvMessengerCoreDataNotification.ownedIdentityHiddenStatusChanged(ownedCryptoId: cryptoId, isHidden: isHidden)
                    .postOnDispatchQueue()
            }
            
            if changedKeys.contains(Predicate.Key.badgeCountForDiscussionsTab.rawValue) || changedKeys.contains(Predicate.Key.badgeCountForInvitationsTab.rawValue) {
                ObvMessengerCoreDataNotification.badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity(ownedCryptoId: cryptoId)
                    .postOnDispatchQueue()
            }
            
        } else {
            
            ObvMessengerCoreDataNotification.persistedObvOwnedIdentityWasDeleted
                .postOnDispatchQueue()
            
        }

    }
    
}


// MARK: - OwnedIdentityPermanentID

typealias OwnedIdentityPermanentID = ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>

// MARK: - MentionableIdentity

/// Allows a `PersistedObvOwnedIdentity` to be displayed in the views showing mentions.
extension PersistedObvOwnedIdentity: MentionableIdentity {
    
    public var mentionnedCryptoId: ObvCryptoId? {
        return self.cryptoId
    }
    
    public var mentionSearchMatcher: String {
        return mentionPersistedName
    }

    public var mentionPickerTitle: String {
        return mentionPersistedName
    }

    public var mentionPickerSubtitle: String? {
        return nil
    }

    public var mentionPersistedName: String {
        return PersonNameComponentsFormatter.localizedString(from: identityCoreDetails.personNameComponents,
                                                             style: .default)
    }

    public var innerIdentity: MentionableIdentityTypes.InnerIdentity {
        return .owned(typedObjectID)
    }
}


// MARK: - For snapshot purposes

extension PersistedObvOwnedIdentity {
    
    var syncSnapshotNode: PersistedObvOwnedIdentitySyncSnapshotNode {
        get throws {
            guard let managedObjectContext else { throw ObvUICoreDataError.noContext }
            return try .init(ownedCryptoId: cryptoId,
                         customDisplayName: customDisplayName,
                         contacts: contacts,
                         contactGroups: contactGroups,
                         contactGroupsV2: contactGroupsV2,
                         within: managedObjectContext)
        }
    }
    
}


struct PersistedObvOwnedIdentitySyncSnapshotNode: ObvSyncSnapshotNode {
    
    private let domain: Set<CodingKeys>
    private let customDisplayName: String?
    private let contacts: [ObvCryptoId: PersistedObvContactIdentitySyncSnapshotNode]
    private let groupsV1: [GroupV1Identifier: PersistedContactGroupSyncSnapshotNode]
    private let groupsV2: [GroupV2Identifier: PersistedGroupV2SyncSnapshotNode]
    private let pinnedDiscussions: [ObvSyncAtom.DiscussionIdentifier] // Part of the pinned domain
    private let hasPinnedDiscussions: Bool? // Part of the pinned domain
    private let orderedPinnedDiscussions: Bool // Always true under iOS
    
    let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case customDisplayName = "custom_name"
        case contacts = "contacts"
        case groupsV1 = "groups"
        case groupsV2 = "groups2"
        case pinnedDiscussions = "pinned_discussions" // not used as a domain
        case pinned = "pinned"
        case domain = "domain"
        case orderedPinnedDiscussions = "pinned_sorted"
    }

    private static let defaultDomain: Set<CodingKeys> = Set(CodingKeys.allCases.filter({ $0 != .domain && $0 != .pinnedDiscussions }))

    
    init(ownedCryptoId: ObvCryptoId, customDisplayName: String?, contacts: Set<PersistedObvContactIdentity>, contactGroups: Set<PersistedContactGroup>, contactGroupsV2: Set<PersistedGroupV2>, within context: NSManagedObjectContext) throws {
        
        self.domain = Self.defaultDomain
        
        self.customDisplayName = customDisplayName
        // contacts
        do {
            let keysAndValues: [(ObvCryptoId, PersistedObvContactIdentitySyncSnapshotNode)] = contacts.compactMap { ($0.cryptoId, $0.syncSnapshotNode) }
            self.contacts = Dictionary(keysAndValues, uniquingKeysWith: { (first, _) in assertionFailure(); return first })
        }
        // groupsV1
        do {
            let keysAndValues: [(GroupV1Identifier, PersistedContactGroupSyncSnapshotNode)] = contactGroups.compactMap {
                guard let groupV1Identifier = try? $0.getGroupV1Identifier() else { return nil }
                return (groupV1Identifier, $0.syncSnapshotNode) }
            self.groupsV1 = Dictionary(keysAndValues, uniquingKeysWith: { (first, _) in assertionFailure(); return first })
        }
        // groupsV2
        do {
            let keysAndValues: [(GroupV2Identifier, PersistedGroupV2SyncSnapshotNode)] = contactGroupsV2.compactMap { ($0.groupIdentifier, $0.syncSnapshotNode) }
            self.groupsV2 = Dictionary(keysAndValues, uniquingKeysWith: { (first, _) in assertionFailure(); return first })
        }
        // hasPinnedDiscussions and pinnedDiscussions
        do {
            let pinnedDiscussions = try PersistedDiscussion.getAllPinnedDiscussions(ownedCryptoId: ownedCryptoId, with: context)
            self.hasPinnedDiscussions = !pinnedDiscussions.isEmpty
            self.pinnedDiscussions = pinnedDiscussions.compactMap({ Self.getObvSyncAtomDiscussionIdentifierFrom(persistedDiscussion: $0) })
        }
     
        self.orderedPinnedDiscussions = true
        
    }
    
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(customDisplayName, forKey: .customDisplayName)
        // contacts
        do {
            let dict: [String: PersistedObvContactIdentitySyncSnapshotNode] = .init(contacts, keyMapping: { $0.getIdentity().base64EncodedString() }, valueMapping: { $0 })
            try container.encode(dict, forKey: .contacts)
        }
        // groupsV1
        do {
            let dict: [String: PersistedContactGroupSyncSnapshotNode] = .init(groupsV1, keyMapping: { $0.description }, valueMapping: { $0 })
            try container.encode(dict, forKey: .groupsV1)
        }
        // groupsV2
        do {
            let dict: [String: PersistedGroupV2SyncSnapshotNode] = .init(groupsV2, keyMapping: { $0.base64EncodedString() }, valueMapping: { $0 })
            try container.encode(dict, forKey: .groupsV2)
        }
        // pinned
        try container.encode(hasPinnedDiscussions, forKey: .pinned)
        try container.encode(pinnedDiscussions.map({ $0.obvEncode().rawData }), forKey: .pinnedDiscussions)
        try container.encode(orderedPinnedDiscussions, forKey: .orderedPinnedDiscussions)
        // domain
        try container.encode(domain, forKey: .domain)
    }
    
    
    init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
            self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
            self.customDisplayName = try values.decodeIfPresent(String.self, forKey: .customDisplayName)
            // Decode contacts (the keys are the contact identities)
            do {
                let dict = try values.decodeIfPresent([String: PersistedObvContactIdentitySyncSnapshotNode].self, forKey: .contacts) ?? [:]
                self.contacts = Dictionary(dict, keyMapping: { $0.base64EncodedToData?.identityToObvCryptoId }, valueMapping: { $0 })
            }
            // Decode groupsV1 (the keys are GroupV1Identifier)
            do {
                let dict = try values.decodeIfPresent([String: PersistedContactGroupSyncSnapshotNode].self, forKey: .groupsV1) ?? [:]
                self.groupsV1 = Dictionary(dict, keyMapping: { GroupV1Identifier($0) }, valueMapping: { $0 })
            }
            // Decode groupsV2 (the keys are GroupV2.Identifier)
            do {
                let dict = try values.decodeIfPresent([String: PersistedGroupV2SyncSnapshotNode].self, forKey: .groupsV2) ?? [:]
                self.groupsV2 = Dictionary(dict, keyMapping: { GroupV2Identifier(base64Encoded: $0) }, valueMapping: { $0 })
            }
            // hasPinnedDiscussions and pinnedDiscussions
            do {
                self.hasPinnedDiscussions = try values.decodeIfPresent(Bool.self, forKey: .pinned)
                self.orderedPinnedDiscussions = try values.decodeIfPresent(Bool.self, forKey: .orderedPinnedDiscussions) ?? false
                let rawPinned = try values.decodeIfPresent([Data].self, forKey: .pinnedDiscussions) ?? []
                self.pinnedDiscussions = rawPinned
                    .compactMap({ ObvEncoded(withRawData: $0) })
                    .compactMap({ ObvSyncAtom.DiscussionIdentifier($0) })
            }
        } catch {
            assertionFailure()
            throw error
        }
    }

    
    /// User the values of this node to udate the `PersistedObvOwnedIdentity`
    /// - Parameter ownedIdentity: The `PersistedObvOwnedIdentity` instance to update
    func useToUpdate(_ ownedIdentity: PersistedObvOwnedIdentity) {
        
        if domain.contains(.customDisplayName) {
            _ = ownedIdentity.setOwnedCustomDisplayName(to: self.customDisplayName)
        }
        
        if domain.contains(.contacts) {
            contacts.forEach { (contactCryptoId, contactNode) in
                guard let contact = try? PersistedObvContactIdentity.get(cryptoId: contactCryptoId, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .any) else {
                    assertionFailure()
                    return
                }
                contactNode.useToUpdate(contact)
            }
        }
        
        if domain.contains(.groupsV1) {
            groupsV1.forEach { (groupId, groupNode) in
                guard let group = try? PersistedContactGroup.getContactGroup(groupIdentifier: groupId, ownedIdentity: ownedIdentity) else {
                    assertionFailure()
                    return
                }
                groupNode.useToUpdate(group)
            }
        }
        
        if domain.contains(.groupsV2) {
            groupsV2.forEach { (groupId, groupNode) in
                guard let group = try? PersistedGroupV2.get(ownIdentity: ownedIdentity, appGroupIdentifier: groupId) else {
                    assertionFailure()
                    return
                }
                groupNode.useToUpdate(group)
            }
        }

        if domain.contains(.pinned) {
            let discussionObjectIDs: [NSManagedObjectID] = pinnedDiscussions.compactMap { discussionIdentifier in
                switch discussionIdentifier {
                case .oneToOne(let contactCryptoId):
                    return try? PersistedOneToOneDiscussion.getPersistedOneToOneDiscussion(ownedIdentity: ownedIdentity, oneToOneDiscussionId: .contactCryptoId(contactCryptoId: contactCryptoId))?.objectID
                case .groupV1(groupIdentifier: let groupIdentifier):
                    return try? PersistedGroupDiscussion.getPersistedGroupDiscussion(ownedIdentity: ownedIdentity, groupV1DiscussionId: .groupV1Identifier(groupV1Identifier: groupIdentifier))?.objectID
                case .groupV2(let groupIdentifier):
                    return try? PersistedGroupV2Discussion.getPersistedGroupV2Discussion(ownedIdentity: ownedIdentity, groupV2DiscussionId: .groupV2Identifier(groupV2Identifier: groupIdentifier))?.objectID
                }
            }
            assert(ownedIdentity.managedObjectContext != nil)
            if let context = ownedIdentity.managedObjectContext {
                _ = try? PersistedDiscussion.setPinnedDiscussions(
                    persistedDiscussionObjectIDs: discussionObjectIDs,
                    ordered: orderedPinnedDiscussions,
                    ownedCryptoId: ownedIdentity.cryptoId,
                    within: context)
            }
        }
        
    }
    
    
    enum ObvError: Error {
        case ownedIdentityDoesNotExist
        case contextIsNil
    }
    
    // Helpers
    
    private static func getObvSyncAtomDiscussionIdentifierFrom(persistedDiscussion: PersistedDiscussion) -> ObvSyncAtom.DiscussionIdentifier? {
        guard let discussionKind = try? persistedDiscussion.kind else { assertionFailure(); return nil }
        switch discussionKind {
        case .oneToOne(withContactIdentity: let persistedContact):
            guard let persistedContact else { assertionFailure(); return nil }
            return .oneToOne(contactCryptoId: persistedContact.cryptoId)
        case .groupV1(withContactGroup: let groupV1):
            guard let groupV1 else { assertionFailure(); return nil }
            guard let groupId = try? groupV1.getGroupId() else { assertionFailure(); return nil }
            return .groupV1(groupIdentifier: groupId)
        case .groupV2(withGroup: let groupV2):
            guard let groupV2 else { assertionFailure(); return nil }
            return .groupV2(groupIdentifier: groupV2.groupIdentifier)
        }

    }

}


// MARK: - Private Helpers

private extension String {
    
    var base64EncodedToData: Data? {
        guard let data = Data(base64Encoded: self) else { assertionFailure(); return nil }
        return data
    }
    
}


private extension Data {
    
    var identityToObvCryptoId: ObvCryptoId? {
        guard let cryptoId = try? ObvCryptoId(identity: self) else { assertionFailure(); return nil }
        return cryptoId
    }
    
}
