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
import ObvEngine
import ObvTypes
import os.log
import ObvCrypto
import OlvidUtils
import ObvUIObvCircledInitials
import ObvSettings
import ObvAppTypes


@objc(PersistedContactGroup)
public class PersistedContactGroup: NSManagedObject {
    
    private static let entityName = "PersistedContactGroup"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedContactGroup")

    // MARK: - Attributes
    
    @NSManaged public private(set) var groupName: String
    @NSManaged private var groupUidRaw: Data
    @NSManaged public private(set) var note: String?
    @NSManaged public private(set) var ownerIdentity: Data // MUST be kept in sync with the owner relationship of subclasses
    @NSManaged private var photoURL: URL? // Reset with the engine photo URL when it changes and during bootstrap
    @NSManaged private var rawCategory: Int
    @NSManaged private(set) var rawOwnedIdentityIdentity: Data // Required for core data constraints

    // MARK: - Relationships
    
    @NSManaged public private(set) var contactIdentities: Set<PersistedObvContactIdentity>
    @NSManaged public private(set) var discussion: PersistedGroupDiscussion
    @NSManaged public private(set) var displayedContactGroup: DisplayedContactGroup? // Expected to be non nil
    @NSManaged public private(set) var pendingMembers: Set<PersistedPendingGroupMember>
    // If nil, the following relationship will eventually be cascade-deleted
    @NSManaged private var rawOwnedIdentity: PersistedObvOwnedIdentity? // *Never* accessed directly

    // MARK: - Other variables
    
    private var changedKeys = Set<String>()
    private var insertedContacts = Set<PersistedObvContactIdentity>()
    private var removedContacts = Set<PersistedObvContactIdentity>()
    private var insertedPendingMembers = Set<PersistedPendingGroupMember>()
    
    public private(set) var ownedIdentity: PersistedObvOwnedIdentity? {
        get {
            return self.rawOwnedIdentity
        }
        set {
            assert(newValue != nil)
            if let value = newValue {
                self.rawOwnedIdentityIdentity = value.cryptoId.getIdentity()
            }
            self.rawOwnedIdentity = newValue
        }
    }
        
    public var category: Category {
        return Category(rawValue: rawCategory)!
    }
    
    public enum Category: Int {
        case owned = 0
        case joined = 1
    }
    
    public var groupUid: UID {
        return UID(uid: groupUidRaw)!
    }
    
    public var displayName: String {
        if let groupJoined = self as? PersistedContactGroupJoined {
            return groupJoined.groupNameCustom ?? self.groupName
        } else {
            return self.groupName
        }
    }

    public var displayPhotoURL: URL? {
        if let groupJoined = self as? PersistedContactGroupJoined {
            return groupJoined.customPhotoURL ?? self.photoURL
        } else {
            return self.photoURL
        }
    }


    public var sortedContactIdentities: [PersistedObvContactIdentity] {
        contactIdentities.sorted(by: { $0.sortDisplayName < $1.sortDisplayName })
    }
    
    
    public func hasAtLeastOneRemoteContactDevice() -> Bool {
        for contact in self.contactIdentities {
            if !contact.devices.isEmpty {
                return true
            }
        }
        return false
    }


    public var circledInitialsConfiguration: CircledInitialsConfiguration {
        .group(photo: .url(url: displayPhotoURL), groupUid: groupUid)
    }
    
    
    /// Returns `true` iff the personal note had to be updated in database
    func setNote(to newNote: String?) -> Bool {
        if self.note != newNote {
            self.note = newNote
            return true
        } else {
            return false
        }
    }


    public func getGroupId() throws -> GroupV1Identifier {
        let groupOwner = try ObvCryptoId(identity: self.ownerIdentity)
        return GroupV1Identifier(groupUid: self.groupUid, groupOwner: groupOwner)
    }

    
    public func getGroupV1Identifier() throws -> GroupV1Identifier {
        return try self.getGroupId()
    }
    
    
    public var obvGroupIdentifier: ObvGroupV1Identifier {
        get throws {
            let groupV1Identifier = try self.getGroupId()
            guard let ownedCryptoId = ownedIdentity?.cryptoId else {
                assertionFailure()
                throw ObvUICoreDataError.unexpectedOwnedIdentity
            }
            return .init(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
        }
    }

    
    // MARK: - Updating a group from an ObvContactGroup from engine
    
    /// Returns `true` iff the group has updates
    func updateContactGroup(with obvContactGroupFromEngine: ObvContactGroup) throws -> Bool {
        
        guard self.rawOwnedIdentityIdentity == obvContactGroupFromEngine.ownedIdentity.cryptoId.getIdentity() else {
            assertionFailure()
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        guard self.groupUidRaw == obvContactGroupFromEngine.groupUid.raw else {
            assertionFailure()
            throw ObvUICoreDataError.unexpectedGroupUID
        }
        
        guard self.ownerIdentity == obvContactGroupFromEngine.groupOwner.cryptoId.getIdentity() else {
            assertionFailure()
            throw ObvUICoreDataError.unexpectedGroupOwner
        }
        
        try setContactIdentities(to: obvContactGroupFromEngine.groupMembers)
        try setPendingMembers(to: obvContactGroupFromEngine.pendingGroupMembers)
        updatePhoto(with: obvContactGroupFromEngine.trustedOrLatestPhotoURL)
        
        if let groupJoined = self as? PersistedContactGroupJoined {
            
            try groupJoined.resetGroupName(to: obvContactGroupFromEngine.trustedOrLatestCoreDetails.name)
            if obvContactGroupFromEngine.publishedDetailsAndTrustedOrLatestDetailsAreEquivalentForTheUser() {
                groupJoined.setStatus(to: .noNewPublishedDetails)
            } else {
                switch groupJoined.status {
                case .noNewPublishedDetails:
                    groupJoined.setStatus(to: .unseenPublishedDetails)
                case .unseenPublishedDetails, .seenPublishedDetails:
                    break // Don't change the status
                }
            }
            
        } else if let groupOwned = self as? PersistedContactGroupOwned {
            
            try groupOwned.resetGroupName(to: obvContactGroupFromEngine.publishedCoreDetails.name)
            
            let declinedMemberIdentites = Set(obvContactGroupFromEngine.declinedPendingGroupMembers
                .map { $0.cryptoId }
            )
            for pendingMember in groupOwned.pendingMembers {
                let newDeclined = declinedMemberIdentites.contains(pendingMember.cryptoId)
                pendingMember.setDeclined(to: newDeclined)
            }

        }
        
        let groupHasUpdates = !self.changedValues().isEmpty
        
        if groupHasUpdates {
            try createOrUpdateTheAssociatedDisplayedContactGroup()
        }
        
        return groupHasUpdates

    }
    
    
    // MARK: - Receiving discussion shared configurations

    /// Called when receiving a ``DiscussionSharedConfigurationJSON`` from a contact or an owned identity indicating this particular group as the target. This method makes sure the contact  or the owned identity is allowed to change the configuration, i.e., that she is the group owner.
    ///
    /// Note that ``PersistedContactGroupJoined`` subclass overrides this method to check the permissions.
    ///
    func mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration: PersistedDiscussion.SharedConfiguration, receivedFrom cryptoId: ObvCryptoId) throws -> (sharedSettingHadToBeUpdated: Bool, weShouldSendBackOurSharedSettings: Bool) {
        
        guard self.ownerIdentity == cryptoId.getIdentity() else {
            throw ObvUICoreDataError.initiatorOfTheChangeIsNotTheGroupOwner
        }
        
        let (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettingsIfAllowedTo) = try discussion.mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration)
        
        return (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettingsIfAllowedTo)
        
    }

    
    func replaceReceivedDiscussionSharedConfiguration(with expiration: ExpirationJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity) throws -> Bool {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        guard self.ownerIdentity == ownedIdentity.identity else {
            throw ObvUICoreDataError.initiatorOfTheChangeIsNotTheGroupOwner
        }

        let sharedSettingHadToBeUpdated = try discussion.replaceReceivedDiscussionSharedConfiguration(with: expiration)
        
        return sharedSettingHadToBeUpdated

    }

    
    // MARK: - Processing wipe requests

    func processWipeMessageRequest(of messagesToDelete: [MessageReferenceJSON], receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        guard self.contactIdentities.contains(contact) || self.ownerIdentity == contact.cryptoId.getIdentity() else {
            throw ObvUICoreDataError.unexpectedContact
        }
        
        let infos = try discussion.processWipeMessageRequest(of: messagesToDelete, from: contact.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return infos
        
    }

    
    func processWipeMessageRequest(of messagesToDelete: [MessageReferenceJSON], receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        let infos = try discussion.processWipeMessageRequest(of: messagesToDelete, from: ownedIdentity.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return infos
        
    }

    
    // MARK: - Processing discussion (all messages) wipe requests from another owned device (contacts cannot delete all messages of a group v1 discussion)
    
    /// Returns the number of new messages that were deleted
    func processRemoteRequestToWipeAllMessagesWithinThisGroupDiscussion(from ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> Int {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        try discussion.processRemoteRequestToWipeAllMessagesWithinThisDiscussion(from: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return discussion.numberOfNewMessages
        
    }

    
    // MARK: - Processing delete requests from the owned identity

    func processMessageDeletionRequestRequestedFromCurrentDevice(of ownedIdentity: PersistedObvOwnedIdentity, messageToDelete: PersistedMessage, deletionType: DeletionType) throws -> InfoAboutWipedOrDeletedPersistedMessage {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        let info = try self.discussion.processMessageDeletionRequestRequestedFromCurrentDevice(of: ownedIdentity, messageToDelete: messageToDelete, deletionType: deletionType)
        
        return info
        
    }

    
    func processDiscussionDeletionRequestFromCurrentDevice(of ownedIdentity: PersistedObvOwnedIdentity, deletionType: DeletionType) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        try self.discussion.processDiscussionDeletionRequestFromCurrentDevice(of: ownedIdentity, deletionType: deletionType)
        
    }
    
    
    // MARK: - Receiving messages and attachments from a contact or another owned device

    func createOrOverridePersistedMessageReceived(from contact: PersistedObvContactIdentity, obvMessage: ObvMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, source: ObvMessageSource, receivedLocation: ReceivedLocation?) throws -> (discussionPermanentID: DiscussionPermanentID, messagePermanentId: MessageReceivedPermanentID?) {
        
        guard self.contactIdentities.contains(contact) else {
            throw ObvUICoreDataError.unexpectedContact
        }

        return try discussion.createOrOverridePersistedMessageReceived(
            from: contact,
            obvMessage: obvMessage,
            messageJSON: messageJSON,
            returnReceiptJSON: returnReceiptJSON,
            source: source,
            receivedLocation: receivedLocation)
        
    }
    
    
    func createPersistedMessageSentFromOtherOwnedDevice(from ownedIdentity: PersistedObvOwnedIdentity, obvOwnedMessage: ObvOwnedMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, sentLocation: SentLocation?) throws -> MessageSentPermanentID? {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        return try discussion.createPersistedMessageSentFromOtherOwnedDevice(
            from: ownedIdentity,
            obvOwnedMessage: obvOwnedMessage,
            messageJSON: messageJSON,
            returnReceiptJSON: returnReceiptJSON,
            sentLocation: sentLocation)
    }
    
    
    // MARK: - Processing edit requests

    func processUpdateMessageRequest(_ updateMessageJSON: UpdateMessageJSON, receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {

        guard self.contactIdentities.contains(contact) else {
            throw ObvUICoreDataError.unexpectedContact
        }

        let updatedMessage = try discussion.processUpdateMessageRequest(updateMessageJSON, receivedFromContactCryptoId: contact.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        return updatedMessage
        
    }

    
    func processUpdateMessageRequest(_ updateMessageJSON: UpdateMessageJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedContact
        }

        let updatedMessage = try discussion.processUpdateMessageRequest(updateMessageJSON, receivedFromOwnedCryptoId: ownedIdentity.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return updatedMessage
        
    }

    
    func processLocalUpdateMessageRequest(from ownedIdentity: PersistedObvOwnedIdentity, for messageSent: PersistedMessageSent, newTextBody: String?) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedContact
        }

        try discussion.processLocalUpdateMessageRequest(from: ownedIdentity, for: messageSent, newTextBody: newTextBody)
        
    }
    
//    func processLocalUpdateMessageRequest(from ownedIdentity: PersistedObvOwnedIdentity, for messageSent: PersistedMessageSent, newLocation: ObvLocation?) throws {
//        
//        guard self.ownedIdentity == ownedIdentity else {
//            throw ObvUICoreDataError.unexpectedContact
//        }
//
//        try discussion.processLocalUpdateMessageRequest(from: ownedIdentity, for: messageSent, newLocation: newLocation)
//        
//    }
    
    
    // MARK: - Process reaction requests

    func processSetOrUpdateReactionOnMessageLocalRequest(from ownedIdentity: PersistedObvOwnedIdentity, for message: PersistedMessage, newEmoji: String?) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedContact
        }

        try discussion.processSetOrUpdateReactionOnMessageLocalRequest(from: ownedIdentity, for: message, newEmoji: newEmoji)
        
    }

    
    func processSetOrUpdateReactionOnMessageRequest(_ reactionJSON: ReactionJSON, receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date, overrideExistingReaction: Bool) throws -> PersistedMessage? {
        
        guard self.contactIdentities.contains(contact) else {
            throw ObvUICoreDataError.unexpectedContact
        }

        let updatedMessage = try discussion.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer, overrideExistingReaction: overrideExistingReaction)
        return updatedMessage

    }
    
    
    func processSetOrUpdateReactionOnMessageRequest(_ reactionJSON: ReactionJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        let updatedMessage = try discussion.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return updatedMessage

    }

    
    // MARK: - Process screen capture detections

    func processDetectionThatSensitiveMessagesWereCaptured(_ screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, from contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.contactIdentities.contains(contact) else {
            throw ObvUICoreDataError.unexpectedContact
        }

        try discussion.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }

    
    func processDetectionThatSensitiveMessagesWereCaptured(_ screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, from ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        try discussion.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

    }

    
    func processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by ownedIdentity: PersistedObvOwnedIdentity) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        try discussion.processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by: ownedIdentity)
        
    }
    
    
    // MARK: - Process requests for group v1 shared settings

    func processQuerySharedSettingsRequest(from contact: PersistedObvContactIdentity, querySharedSettingsJSON: QuerySharedSettingsJSON) throws -> (weShouldSendBackOurSharedSettings: Bool, discussionId: DiscussionIdentifier) {
        
        guard self.ownedIdentity == contact.ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        let discussionId = try discussion.identifier
        let weShouldSendBackOurSharedSettings = try discussion.processQuerySharedSettingsRequest(querySharedSettingsJSON: querySharedSettingsJSON)
        
        return (weShouldSendBackOurSharedSettings, discussionId)
        
    }
    
    
    func processQuerySharedSettingsRequest(from ownedIdentity: PersistedObvOwnedIdentity, querySharedSettingsJSON: QuerySharedSettingsJSON) throws -> (weShouldSendBackOurSharedSettings: Bool, discussionId: DiscussionIdentifier) {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        let discussionId = try discussion.identifier
        let weShouldSendBackOurSharedSettings = try discussion.processQuerySharedSettingsRequest(querySharedSettingsJSON: querySharedSettingsJSON)
        
        return (weShouldSendBackOurSharedSettings, discussionId)
        
    }


    /// Used when restoring a sync snapshot or when restoring a backup to prevent any notification on insertion
    private(set) var isInsertedWhileRestoringSyncSnapshot = false

    
    // MARK: - Observers
    
    private static var observersHolder = ObserversHolder()
    
    public static func addObvObserver(_ newObserver: PersistedContactGroupObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}


// MARK: - Initializer

extension PersistedContactGroup {
    
    convenience init(contactGroup: ObvContactGroup, groupName: String, category: Category, isRestoringSyncSnapshotOrBackup: Bool, forEntityName entityName: String, within context: NSManagedObjectContext) throws {

        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(persisted: contactGroup.ownedIdentity, within: context) else {
            throw ObvUICoreDataError.couldNotFindOwnedIdentity
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.isInsertedWhileRestoringSyncSnapshot = isRestoringSyncSnapshotOrBackup

        self.rawCategory = category.rawValue
        self.groupName = groupName
        self.groupUidRaw = contactGroup.groupUid.raw
        self.ownerIdentity = contactGroup.groupOwner.cryptoId.getIdentity()
        self.photoURL = contactGroup.trustedOrLatestPhotoURL

        let _contactIdentities = try contactGroup.groupMembers.compactMap { try PersistedObvContactIdentity.get(persisted: $0.contactIdentifier, whereOneToOneStatusIs: .any, within: context) }
        self.contactIdentities = Set(_contactIdentities)
        
        if let discussion = try PersistedGroupDiscussion.getWithGroupUID(contactGroup.groupUid,
                                                                         groupOwnerCryptoId: contactGroup.groupOwner.cryptoId,
                                                                         ownedCryptoId: ownedIdentity.cryptoId,
                                                                         within: context) {
            try discussion.setStatus(to: .active)
            self.discussion = discussion
        } else {
            self.discussion = try PersistedGroupDiscussion(contactGroup: self,
                                                           groupName: groupName,
                                                           ownedIdentity: ownedIdentity,
                                                           status: .active,
                                                           isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
        }
        self.rawOwnedIdentityIdentity = ownedIdentity.cryptoId.getIdentity()
        self.ownedIdentity = ownedIdentity
        let _pendingMembers = try contactGroup.pendingGroupMembers.compactMap { try PersistedPendingGroupMember(genericIdentity: $0, contactGroup: self) }
        self.pendingMembers = Set(_pendingMembers)
        
        // Create or update the DisplayedContactGroup
        
        try createOrUpdateTheAssociatedDisplayedContactGroup()

    }
    
    
    func createOrUpdateTheAssociatedDisplayedContactGroup() throws {
        if let displayedContactGroup {
            displayedContactGroup.updateUsingUnderlyingGroup()
        } else {
            self.displayedContactGroup = try DisplayedContactGroup(groupV1: self)
        }
    }
    
    
    func delete() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        try discussion.setStatus(to: .locked)
        context.delete(self)
    }
    
    
    func resetDiscussionTitle() throws {
        try self.discussion.resetTitle(to: displayName)
    }
    

    private func resetGroupName(to groupName: String) throws {
        let newGroupName = groupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newGroupName.isEmpty else { assertionFailure(); throw ObvUICoreDataError.tryingToResetGroupNameWithEmptyString }
        if self.groupName != groupName {
            self.groupName = groupName
        }
        try resetDiscussionTitle()
    }


    private func updatePhoto(with photo: URL?) {
        if self.photoURL != photo {
            self.photoURL = photo
            self.discussion.setHasUpdates()
        }
    }
}


// MARK: - Managing contact identities

extension PersistedContactGroup {
    
    
    private func insert(_ contactIdentity: PersistedObvContactIdentity) {
        if !self.contactIdentities.contains(contactIdentity) {
            self.contactIdentities.insert(contactIdentity)
            self.insertedContacts.insert(contactIdentity)
        }
    }
    
    
    private func remove(_ contactIdentity: PersistedObvContactIdentity) {
        if self.contactIdentities.contains(contactIdentity) {
            self.contactIdentities.remove(contactIdentity)
            self.removedContacts.insert(contactIdentity)
        }
    }
    
    
    private func set(_ contactIdentities: Set<PersistedObvContactIdentity>) {
        let contactsToAdd = contactIdentities.subtracting(self.contactIdentities)
        let contactsToRemove = self.contactIdentities.subtracting(contactIdentities)
        for contact in contactsToAdd {
            self.insert(contact)
        }
        for contact in contactsToRemove {
            self.remove(contact)
        }
    }
    

    private func setContactIdentities(to contactIdentities: Set<ObvContactIdentity>) throws {
        guard let context = managedObjectContext else { return }
        guard !contactIdentities.isEmpty else {
            set(Set())
            return
        }
        // We make sure all contact identities concern the same owned identity
        let ownedIdentities = Set(contactIdentities.map { $0.ownedIdentity })
        guard ownedIdentities.count == 1 else {
            throw ObvUICoreDataError.unexpecterCountOfOwnedIdentities
        }
        let ownedIdentity = ownedIdentities.first!.cryptoId
        // Get the persisted contacts corresponding to the contact identities
        let cryptoIds = Set(contactIdentities.map { $0.cryptoId })
        let persistedContact = try PersistedObvContactIdentity.getAllContactsWithCryptoId(in: cryptoIds, ofOwnedIdentity: ownedIdentity, whereOneToOneStatusIs: .any, within: context)
        self.set(persistedContact)
    }

}


// MARK: - Managing PersistedPendingGroupMember

extension PersistedContactGroup {
    
    private func setPendingMembers(to pendingIdentities: Set<ObvGenericIdentity>) throws {
        guard let context = managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        let pendingMembers: Set<PersistedPendingGroupMember> = try Set(pendingIdentities.map { (obvGenericIdentity) in
            if let pendingMember = (self.pendingMembers.filter { $0.cryptoId == obvGenericIdentity.cryptoId }).first {
                return pendingMember
            } else {
                let newPendingMember = try PersistedPendingGroupMember(genericIdentity: obvGenericIdentity, contactGroup: self)
                self.insertedPendingMembers.insert(newPendingMember)
                return newPendingMember
            }
        })
        let pendingMembersToRemove = self.pendingMembers.subtracting(pendingMembers)
        for pendingMember in pendingMembersToRemove {
            context.delete(pendingMember)
        }
    }

}


// MARK: - Convenience DB getters

extension PersistedContactGroup {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case groupName = "groupName"
            case groupUidRaw = "groupUidRaw"
            case note = "note"
            case ownerIdentity = "ownerIdentity"
            case photoURL = "photoURL"
            case rawCategory = "rawCategory"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
            // Relationships
            case contactIdentities = "contactIdentities"
            case discussion = "discussion"
            case displayedContactGroup = "displayedContactGroup"
            case pendingMembers = "pendingMembers"
            case rawOwnedIdentity = "rawOwnedIdentity"
        }
        static func withOwnCryptoId(_ ownedIdentity: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownedIdentity.getIdentity())
        }
        static func withPersistedObvOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, equalTo: ownedIdentity)
        }
        static func withContactIdentity(_ contactIdentity: PersistedObvContactIdentity) -> NSPredicate {
            NSPredicate(Key.contactIdentities, contains: contactIdentity)
        }
        static func withGroupIdentifier(_ groupId: GroupV1Identifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.groupUidRaw, EqualToData: groupId.groupUid.raw),
                NSPredicate(Key.ownerIdentity, EqualToData: groupId.groupOwner.getIdentity()),
            ])
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedContactGroup> {
        return NSFetchRequest<PersistedContactGroup>(entityName: PersistedContactGroup.entityName)
    }


    public static func getContactGroup(groupIdentifier: GroupV1Identifier, ownedIdentity: PersistedObvOwnedIdentity) throws -> PersistedContactGroup? {
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withGroupIdentifier(groupIdentifier),
            Predicate.withPersistedObvOwnedIdentity(ownedIdentity),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func getContactGroup(groupIdentifier: GroupV1Identifier, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedContactGroup? {
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withGroupIdentifier(groupIdentifier),
            Predicate.withOwnCryptoId(ownedCryptoId),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    public static func getAllContactGroupIdentifiers(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Set<GroupV1Identifier> {
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        request.predicate = Predicate.withOwnCryptoId(ownedCryptoId)
        request.fetchBatchSize = 1_000
        request.propertiesToFetch = [
            Predicate.Key.groupUidRaw.rawValue,
            Predicate.Key.ownerIdentity.rawValue,
        ]
        let groups = try context.fetch(request)
        let groupIdentifiers: [GroupV1Identifier] = groups.compactMap { group in
            guard let groupOwner = try? ObvCryptoId(identity: group.ownerIdentity) else { assertionFailure(); return nil }
            return GroupV1Identifier(groupUid: group.groupUid, groupOwner: groupOwner)
        }
        return Set(groupIdentifiers)
    }
    
    
    public static func getAllContactGroups(wherePendingMembersInclude contactIdentity: PersistedObvContactIdentity, within context: NSManagedObjectContext) throws -> Set<PersistedContactGroup> {
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        guard let ownedIdentity = contactIdentity.ownedIdentity else { throw ObvUICoreDataError.ownedIdentityIsNil }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPersistedObvOwnedIdentity(ownedIdentity),
            NSPredicate(withStrictlyPositiveCountForKey: Predicate.Key.pendingMembers),
        ])
        let groups = Set(try context.fetch(request))
        return groups.filter { $0.pendingMembers.map({ $0.cryptoId }).contains(contactIdentity.cryptoId) }
    }
    
    
    public static func getAllContactGroups(whereContactIdentitiesInclude contactIdentity: PersistedObvContactIdentity, within context: NSManagedObjectContext) throws -> Set<PersistedContactGroup> {
        let request: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        guard let ownedIdentity = contactIdentity.ownedIdentity else { throw ObvUICoreDataError.ownedIdentityIsNil }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPersistedObvOwnedIdentity(ownedIdentity),
            Predicate.withContactIdentity(contactIdentity),
        ])
        return Set(try context.fetch(request))
    }

    
    public static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedContactGroup? {
        return try context.existingObject(with: objectID) as? PersistedContactGroup
    }
    
}


// MARK: - Convenience NSFetchedResultsController creators

extension PersistedContactGroup {
    
    static func getFetchedResultsControllerForAllContactGroups(for contactIdentity: PersistedObvContactIdentity, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedContactGroup> {
        let fetchRequest: NSFetchRequest<PersistedContactGroup> = PersistedContactGroup.fetchRequest()
        fetchRequest.predicate = Predicate.withContactIdentity(contactIdentity)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.groupName.rawValue, ascending: true)]
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
    
}


// MARK: - Sending notifications on change

extension PersistedContactGroup {
    
    public override func willSave() {
        super.willSave()
        changedKeys = Set<String>(self.changedValues().keys)
    }
    
    
    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
            insertedContacts.removeAll()
            removedContacts.removeAll()
            insertedPendingMembers.removeAll()
            isInsertedWhileRestoringSyncSnapshot = false
        }
        
        guard !isInsertedWhileRestoringSyncSnapshot else {
            assert(isInserted)
            let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: Self.self))
            os_log("Insertion of a PersistedContactGroup during a snapshot restore --> we don't send any notification", log: log, type: .info)
            return
        }

        if changedKeys.contains(Predicate.Key.contactIdentities.rawValue) {
            ObvMessengerCoreDataNotification.persistedContactGroupHasUpdatedContactIdentities(
                persistedContactGroupObjectID: objectID,
                insertedContacts: insertedContacts,
                removedContacts: removedContacts)
            .postOnDispatchQueue()
        }
        
        // Potentially notify that the previous backed up profile snapshot is obsolete.
        // We only notify in case of a change. Insertion/Deletion are notified by
        // the engine.
        // See `PersistedObvOwnedIdentity` for a list of entities that might post a similar notification.
        
        if !isDeleted && !isInserted && !changedKeys.isEmpty {
            if changedKeys.contains("groupNameCustom") ||
                changedKeys.contains(Predicate.Key.note.rawValue) ||
                changedKeys.contains(Predicate.Key.discussion.rawValue) {
                let ownedIdentity = self.rawOwnedIdentityIdentity
                if let ownedCryptoId = try? ObvCryptoId(identity: ownedIdentity) {
                    Task {
                        await Self.observersHolder.previousBackedUpProfileSnapShotIsObsoleteAsPersistedContactGroupChanged(ownedCryptoId: ownedCryptoId)
                    }
                } else {
                    assertionFailure()
                }
            }
        }
        
    }
    
}


// MARK: - For snapshot purposes

extension PersistedContactGroup {
    
    var syncSnapshotNode: PersistedContactGroupSyncSnapshotNode {
        .init(groupNameCustom: (self as? PersistedContactGroupJoined)?.groupNameCustom,
              note: note,
              discussion: discussion)
    }
    
}


struct PersistedContactGroupSyncSnapshotNode: ObvSyncSnapshotNode {
    
    private let domain: Set<CodingKeys>
    private let groupNameCustom: String? // Only for joined group under iOS
    private let note: String?
    private let discussionConfiguration: PersistedDiscussionConfigurationSyncSnapshotNode?

    let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case groupNameCustom = "custom_name"
        case note = "personal_note"
        case discussionConfiguration = "discussion_customization"
        case domain = "domain"
    }

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    
    init(groupNameCustom: String?, note: String?, discussion: PersistedGroupDiscussion?) {
        self.groupNameCustom = groupNameCustom
        self.note = note
        self.discussionConfiguration = discussion?.syncSnapshotNode
        self.domain = Self.defaultDomain
    }
    
    
    // Synthesized implementation of encode(to encoder: Encoder)


    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
        self.groupNameCustom = try values.decodeIfPresent(String.self, forKey: .groupNameCustom)
        self.note = try values.decodeIfPresent(String.self, forKey: .note)
        self.discussionConfiguration = try values.decodeIfPresent(PersistedDiscussionConfigurationSyncSnapshotNode.self, forKey: .discussionConfiguration)
    }

    
    func useToUpdate(_ contactGroup: PersistedContactGroup) {
        
        if domain.contains(.groupNameCustom) {
            if let contactGroupJoined = contactGroup as? PersistedContactGroupJoined {
                _ = try? contactGroupJoined.setGroupNameCustom(to: groupNameCustom)
            }
        }
        
        if domain.contains(.note) {
            _ = contactGroup.setNote(to: note)
        }
        
        if domain.contains(.discussionConfiguration) {
            discussionConfiguration?.useToUpdate(contactGroup.discussion)
        }
        
    }
    
}


// MARK: - PersistedContactGroup observers

public protocol PersistedContactGroupObserver: AnyObject {
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedContactGroupChanged(ownedCryptoId: ObvCryptoId) async
}


private actor ObserversHolder: PersistedContactGroupObserver {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: PersistedContactGroupObserver?
        init(value: PersistedContactGroupObserver?) {
            self.value = value
        }
    }

    func addObserver(_ newObserver: PersistedContactGroupObserver) {
        self.observers.append(.init(value: newObserver))
    }
    
    // Implementing PersistedObvOwnedIdentityObserver
    
    func previousBackedUpProfileSnapShotIsObsoleteAsPersistedContactGroupChanged(ownedCryptoId: ObvCryptoId) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.previousBackedUpProfileSnapShotIsObsoleteAsPersistedContactGroupChanged(ownedCryptoId: ownedCryptoId) }
            }
        }
    }

}
