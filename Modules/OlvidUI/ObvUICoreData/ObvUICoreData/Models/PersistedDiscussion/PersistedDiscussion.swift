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
import os.log
import ObvTypes
import UI_CircledInitialsView_CircledInitialsConfiguration

@objc(PersistedDiscussion)
public class PersistedDiscussion: NSManagedObject {

    fileprivate static let entityName = "PersistedDiscussion"
    private static let errorDomain = "PersistedDiscussion"
    
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: PersistedDiscussion.self))
    
    public static func makeError(message: String, code: Int = 0) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: Self.errorDomain, code: code, userInfo: userInfo)
    }

    public enum PinnedSectionKeyPathValue: String {
        case pinned = "1"
        case unpinned = "0"
    }
    
    // Attributes
    
    @NSManaged public private(set) var aNewReceivedMessageDoesMentionOwnedIdentity: Bool // True iff a new received message has doesMentionOwnedIdentity set to True
    @NSManaged public private(set) var isArchived: Bool
    @NSManaged var lastOutboundMessageSequenceNumber: Int
    @NSManaged var lastSystemMessageSequenceNumber: Int
    @NSManaged private var normalizedSearchKey: String?
    @NSManaged public private(set) var numberOfNewMessages: Int // Set to 0 when this discussion is muted (not to be used when displaying the number of new messages when entering the discussion)
    @NSManaged private var onChangeFlag: Int // Only used internally to trigger UI updates, transient
    @NSManaged public private(set) var permanentUUID: UUID
    @NSManaged private var rawPinnedIndex: NSNumber?
    @NSManaged private(set) var pinnedSectionKeyPath: String // Shall only be modified in the setter of pinnedIndex
    @NSManaged private var rawStatus: Int
    @NSManaged private(set) var senderThreadIdentifier: UUID
    @NSManaged public private(set) var timestampOfLastMessage: Date
    @NSManaged public private(set) var title: String
    

    // Relationships

    @NSManaged public private(set) var draft: PersistedDraft
    @NSManaged public private(set) var illustrativeMessage: PersistedMessage?
    @NSManaged public private(set) var localConfiguration: PersistedDiscussionLocalConfiguration
    @NSManaged public private(set) var messages: Set<PersistedMessage>
    @NSManaged public private(set) var ownedIdentity: PersistedObvOwnedIdentity? // If nil, this entity is eventually cascade-deleted
    @NSManaged private(set) var remoteDeleteAndEditRequests: Set<RemoteDeleteAndEditRequest>
    @NSManaged public private(set) var sharedConfiguration: PersistedDiscussionSharedConfiguration
    
    // Other variables
    
    private var changedKeys = Set<String>()

    public private(set) var status: Status {
        get {
            guard let status = Status(rawValue: rawStatus) else { assertionFailure(); return .active }
            return status
        }
        set {
            self.rawStatus = newValue.rawValue
        }
    }

    public private(set) var pinnedIndex: Int? {
        get {
            return rawPinnedIndex?.intValue
        }
        set {
            guard self.rawPinnedIndex?.intValue != newValue else { return }
            if let newValue {
                self.rawPinnedIndex = newValue as NSNumber
                pinnedSectionKeyPath = PinnedSectionKeyPathValue.pinned.rawValue
            } else {
                self.rawPinnedIndex = nil
                pinnedSectionKeyPath = PinnedSectionKeyPathValue.unpinned.rawValue
            }
        }
    }
    
    public enum Status: Int {
        case preDiscussion = 0
        case active = 1
        case locked = 2
    }
    
    
    public enum Kind {
        case oneToOne(withContactIdentity: PersistedObvContactIdentity?)
        case groupV1(withContactGroup: PersistedContactGroup?)
        case groupV2(withGroup: PersistedGroupV2?)
    }
    
    
    public var kind: Kind {
        get throws {
            if let discussionOneToOne = self as? PersistedOneToOneDiscussion {
                return .oneToOne(withContactIdentity: discussionOneToOne.contactIdentity)
            } else if let discussionGroupV1 = self as? PersistedGroupDiscussion {
                return .groupV1(withContactGroup: discussionGroupV1.contactGroup)
            } else if let discussionGroupV2 = self as? PersistedGroupV2Discussion {
                return .groupV2(withGroup: discussionGroupV2.group)
            } else {
                assertionFailure()
                throw Self.makeError(message: "Unknown discussion type")
            }
        }
    }
    
    public var discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion> {
        ObvManagedObjectPermanentID(entityName: PersistedDiscussion.entityName, uuid: self.permanentUUID)
    }
    
    private var discussionPermanentIDOnDeletion: ObvManagedObjectPermanentID<PersistedDiscussion>?

    public var displayPhotoURL: URL? {
        get throws {
            switch try kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                return contactIdentity?.customPhotoURL ?? contactIdentity?.photoURL
            case .groupV1(withContactGroup: let contactGroup):
                return contactGroup?.displayPhotoURL
            case .groupV2(withGroup: let group):
                return group?.displayPhotoURL
            }
        }
    }
    
    public var showGreenShield: Bool {
        get throws {
            switch try kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                return contactIdentity?.isCertifiedByOwnKeycloak ?? false
            case .groupV1:
                return false
            case .groupV2:
                return false
            }
        }
    }
     
    
    public var showRedShield: Bool {
        get throws {
            switch try kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                guard let contactIdentity = contactIdentity else { return false }
                return !contactIdentity.isActive
            case .groupV1:
                return false
            case .groupV2:
                return false
            }
        }
    }
    
    
    public var circledInitialsConfiguration: CircledInitialsConfiguration? {
        switch status {
        case .locked:
            return .icon(.lockFill)
        case .preDiscussion, .active:
            switch try? kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                return contactIdentity?.circledInitialsConfiguration
            case .groupV1(withContactGroup: let contactGroup):
                return contactGroup?.circledInitialsConfiguration
            case .groupV2(withGroup: let group):
                return group?.circledInitialsConfiguration
            case .none:
                assertionFailure()
                return .icon(.lockFill)
            }
        }
    }

    
    // MARK: - Initializer

    convenience init(title: String, ownedIdentity: PersistedObvOwnedIdentity, forEntityName entityName: String, status: Status, shouldApplySharedConfigurationFromGlobalSettings: Bool, sharedConfigurationToKeep: PersistedDiscussionSharedConfiguration? = nil, localConfigurationToKeep: PersistedDiscussionLocalConfiguration? = nil, permanentUUIDToKeep: UUID?, draftToKeep: PersistedDraft?, pinnedIndexToKeep: Int?, timestampOfLastMessageToKeep: Date?) throws {
        
        guard let context = ownedIdentity.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.isArchived = false
        self.lastOutboundMessageSequenceNumber = 0
        self.lastSystemMessageSequenceNumber = 0
        self.normalizedSearchKey = nil
        self.numberOfNewMessages = 0
        self.permanentUUID = permanentUUIDToKeep ?? UUID()
        self.rawPinnedIndex = pinnedIndexToKeep as? NSNumber
        self.pinnedSectionKeyPath = (pinnedIndexToKeep == nil) ? PinnedSectionKeyPathValue.unpinned.rawValue : PinnedSectionKeyPathValue.pinned.rawValue
        self.onChangeFlag = 0
        self.senderThreadIdentifier = UUID()
        self.timestampOfLastMessage = timestampOfLastMessageToKeep ?? Date()
        self.title = title
        self.status = status
        self.aNewReceivedMessageDoesMentionOwnedIdentity = false
        
        if sharedConfigurationToKeep != nil {
            self.sharedConfiguration = sharedConfigurationToKeep!
        } else {
            let sharedConfiguration = try PersistedDiscussionSharedConfiguration(discussion: self)
            if shouldApplySharedConfigurationFromGlobalSettings {
                sharedConfiguration.setValuesUsingSettings()
            }
            self.sharedConfiguration = sharedConfiguration
        }
        
        let localConfiguration = try (localConfigurationToKeep ?? PersistedDiscussionLocalConfiguration(discussion: self))
        self.localConfiguration = localConfiguration
        self.sharedConfiguration = sharedConfiguration
        self.draft = try draftToKeep ?? PersistedDraft(within: self)
        self.messages = Set<PersistedMessage>()
        self.ownedIdentity = ownedIdentity
        self.remoteDeleteAndEditRequests = Set<RemoteDeleteAndEditRequest>()
          
    }
    
    
    func setHasUpdates() {
        self.onChangeFlag += 1
    }

    
    func resetNewReceivedMessageDoesMentionOwnedIdentityValue() {
        let count: Int
        do {
            count = try PersistedMessageReceived.countNewAndMentionningOwnedIdentity(within: self)
        } catch {
            assertionFailure("Could not count the number of received messages that are new and which mentions owned identity: \(error.localizedDescription)")
            count = 0
        }
        let newNewMessageDoesMentionOwnedIdentityValue = (count > 0)
        if self.aNewReceivedMessageDoesMentionOwnedIdentity != newNewMessageDoesMentionOwnedIdentityValue {
            self.aNewReceivedMessageDoesMentionOwnedIdentity = newNewMessageDoesMentionOwnedIdentityValue
            if self.hasNotificationsMuted {
                let incrementForOwnedIdentity = self.aNewReceivedMessageDoesMentionOwnedIdentity ? 1 : -1
                ownedIdentity?.incrementBadgeCountForDiscussionsTab(by: incrementForOwnedIdentity)
            }
        }
    }
    
    
    func resetTimestampOfLastMessageIfCurrentValueIsEarlierThan(_ date: Date) {
        if self.timestampOfLastMessage < date {
            self.timestampOfLastMessage = date
        }
    }
    
    // MARK: Performing deletions
        
    /// Deletes this discussion after making sure the `requester` is allowed to do so. If the `requester` is `nil`, this discussion is deleted without any check. This makes it possible to easily perform cleaning.
    public func deleteDiscussion(requester: RequesterOfMessageDeletion?) throws {
        
        // Make sure the deletion is allowed
        
        if let requester = requester {
            try throwIfRequesterIsNotAllowedToDeleteDiscussion(requester: requester)
        }
                
        // The deletion is allowed, we can perform it now
        
        guard let context = self.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        context.delete(self)
        
    }

    
    /// This methods throws an error if the requester of the discussion deletion is not allowed to perform such a deletion.
    ///
    /// The `deletionType` parameter only makes sense when the requester is an owned identity, and the discussion is a group v2 discussion:
    /// - for a `.local` deletion, deletion is always allowed
    /// - for a `.global` deletion, we make sure the owned identity is allowed to perform a global deletion in the corresponding group
    func throwIfRequesterIsNotAllowedToDeleteDiscussion(requester: RequesterOfMessageDeletion) throws {
        
        // Locked and preDiscussion can only be locally deleted by an owned identity
        
        switch status {
        case .locked, .preDiscussion:
            switch requester {
            case .contact:
                throw Self.makeError(message: "A contact cannot delete a locked or preDiscussion")
            case .ownedIdentity(let ownedCryptoId, let deletionType):
                guard let discussionOwnedCryptoId = ownedIdentity?.cryptoId else {
                    return // Rare case, we allow deletion
                }
                guard (discussionOwnedCryptoId == ownedCryptoId) else {
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected owned identity for deleting this discussion")
                }
                switch deletionType {
                case .local:
                    return // Allow deletion
                case .global:
                    throw Self.makeError(message: "We cannot globally delete a locked or preDiscussion")
                }
            }
        case .active:
            break // We need to consider the discussion kind to decide whether we should throw or not
        }
        
        // If we reach this point, we are considering an active discussion

        switch try kind {
            
        case .oneToOne, .groupV1:
            
            // It is always ok to delete a oneToOne or a groupV1 discussion
            return
            
        case .groupV2(withGroup: let group):
                        
            guard let group = group else {
                
                // If the group cannot be found (which is unexpected), we allow the deletion of the discussion only if the request comes from an owned identity.

                switch requester {
                case .ownedIdentity(ownedCryptoId: _, deletionType: let deletionType):
                    switch deletionType {
                    case .local:
                        return // Allow deletion
                    case .global:
                        throw Self.makeError(message: "Since we cannot find the group, we disallow global deletion by owned identity")
                    }
                case .contact:
                    assertionFailure()
                    throw Self.makeError(message: "Since we cannot find the group, we disallow deletion by a contact")
                }

            }
            
            // For a group v2 discussion, we make sure the requester is either the owned identity or a member with the appropriate rights.

            switch requester {
                
            case .ownedIdentity(ownedCryptoId: let ownedCryptoId, deletionType: let deletionType):
                
                guard (try group.ownCryptoId == ownedCryptoId) else {
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected owned identity for deleting this discussion")
                }
                switch deletionType {
                case .local:
                    return // Allow deletion
                case .global:
                    guard group.ownedIdentityIsAllowedToRemoteDeleteAnything else {
                        throw Self.makeError(message: "Owned identity is not allowed to perform a global (remote) delete")
                    }
                    return // Allow deletion
                }
                
            case .contact(let ownedCryptoId, let contactCryptoId, _):
                
                guard (try group.ownCryptoId == ownedCryptoId) else {
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected owned identity associated to contact for deleting this discussion")
                }
                guard let member = group.otherMembers.first(where: { $0.identity == contactCryptoId.getIdentity() }) else {
                    throw Self.makeError(message: "The deletion requester is not part of the group")
                }
                guard member.isAllowedToRemoteDeleteAnything else {
                    assertionFailure()
                    throw Self.makeError(message: "The member is not allowed to delete this discussion")
                }
                return // Allow deletion
            }

        }
        
    }
    
    
    func requesterIsAllowedToDeleteDiscussion(requester: RequesterOfMessageDeletion) -> Bool {
        do {
            try throwIfRequesterIsNotAllowedToDeleteDiscussion(requester: requester)
        } catch {
            return false
        }
        return true
    }
    
    
    public var globalDeleteActionCanBeMadeAvailable: Bool {
        guard let ownedCryptoId = ownedIdentity?.cryptoId else { return false }
        let requester = RequesterOfMessageDeletion.ownedIdentity(ownedCryptoId: ownedCryptoId, deletionType: .global)
        return requesterIsAllowedToDeleteDiscussion(requester: requester)
    }
    
    
    // MARK: - Status management

    func setStatus(to newStatus: Status) throws {
        self.status = newStatus
    }

}


// MARK: - Utility methods for PersistedSystemMessage showing the number of new messages

extension PersistedDiscussion {

    var appropriateSortIndexAndNumberOfNewMessagesForNewMessagesSystemMessage: (sortIndex: Double, numberOfNewMessages: Int)? {

        assert(Thread.isMainThread)

        guard let context = self.managedObjectContext else {
            assertionFailure()
            return nil
        }

        guard context.concurrencyType == NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType else {
            assertionFailure()
            return nil
        }

        let firstNewMessage: PersistedMessage
        do {
            let firstNewReceivedMessage: PersistedMessageReceived?
            do {
                firstNewReceivedMessage = try PersistedMessageReceived.getFirstNew(in: self)
            } catch {
                assertionFailure()
                return nil
            }

            let firstNewRelevantSystemMessage: PersistedMessageSystem?
            do {
                firstNewRelevantSystemMessage = try PersistedMessageSystem.getFirstNewRelevantSystemMessage(in: self)
            } catch {
                assertionFailure()
                return nil
            }

            switch (firstNewReceivedMessage, firstNewRelevantSystemMessage) {
            case (.none, .none):
                return nil
            case (.some(let msg), .none):
                firstNewMessage = msg
            case (.none, .some(let msg)):
                firstNewMessage = msg
            case (.some(let msg1), .some(let msg2)):
                firstNewMessage = msg1.sortIndex < msg2.sortIndex ? msg1 : msg2
            }
        }

        let numberOfNewMessages: Int
        do {
            let numberOfNewReceivedMessages = try PersistedMessageReceived.countNew(within: self)
            let numberOfNewRelevantSystemMessages = try PersistedMessageSystem.countNewRelevantSystemMessages(in: self)
            numberOfNewMessages = numberOfNewReceivedMessages + numberOfNewRelevantSystemMessages
        } catch {
            assertionFailure()
            return nil
        }

        guard numberOfNewMessages > 0 else {
            return nil
        }

        let sortIndexForFirstNewMessageLimit: Double

        if let messageAboveFirstUnNewReceivedMessage = try? PersistedMessage.getMessage(beforeSortIndex: firstNewMessage.sortIndex, in: self) {
            if (messageAboveFirstUnNewReceivedMessage as? PersistedMessageSystem)?.category == .numberOfNewMessages {
                // The message just above the first new message is a PersistedMessageSystem showing the number of new messages
                // We can simply use its sortIndex
                sortIndexForFirstNewMessageLimit = messageAboveFirstUnNewReceivedMessage.sortIndex
            } else {
                // The message just above the first new message is *not* a PersistedMessageSystem showing the number of new messages
                // We compute the mean of the sort indexes of the two messages to get a sortIndex appropriate to "insert" a new message between the two
                let preceedingSortIndex = messageAboveFirstUnNewReceivedMessage.sortIndex
                sortIndexForFirstNewMessageLimit = (firstNewMessage.sortIndex + preceedingSortIndex) / 2.0
            }
        } else {
            // There is no message above, we simply take a smaller sort index
            let preceedingSortIndex = firstNewMessage.sortIndex - 1
            sortIndexForFirstNewMessageLimit = (firstNewMessage.sortIndex + preceedingSortIndex) / 2.0
        }

        return (sortIndexForFirstNewMessageLimit, numberOfNewMessages)

    }

}


// MARK: - Illustrative message

extension PersistedDiscussion {
    
    /// Used during bootstrap, this method resets the illustrative message to the most appropriate value.
    public func resetIllustrativeMessage() throws {
        guard self.managedObjectContext != nil else { assertionFailure(); throw Self.makeError(message: "Cannot find context") }
        let appropriateIllustrativeMessage = try PersistedMessage.getAppropriateIllustrativeMessage(in: self)
        if self.illustrativeMessage != appropriateIllustrativeMessage {
            self.illustrativeMessage = appropriateIllustrativeMessage
        }
    }

    
    /// Exclusively called from `PersistedMessage`, when a new message is inserted or updated.
    ///
    /// If the criteria for being an illustrative message changes here, we should also update the `getAppropriateIllustrativeMessage` method of `PersistedMessage`.
    func resetIllustrativeMessageWithMessageIfAppropriate(newMessage: PersistedMessage) {
        
        guard self.managedObjectContext != nil else { assertionFailure(); return }

        // Make sure the new message concerns this discussion
        guard newMessage.discussion == self else { assertionFailure(); return }
        
        // Check if the message can be an illustrative message
        guard newMessage is PersistedMessageSent || newMessage is PersistedMessageReceived || (newMessage as? PersistedMessageSystem)?.category.isRelevantForIllustrativeMessage == true else {
            return
        }
        
        if let currentIllustrativeMessage = self.illustrativeMessage, currentIllustrativeMessage.sortIndex < newMessage.sortIndex {
            // The current illustrative message has a smaller sort index than the new message -> we use the new message a the illustrative message
            self.illustrativeMessage = newMessage
        } else if self.illustrativeMessage == nil {
            // There was no illustrative message, we can now use the new message
            self.illustrativeMessage = newMessage
        }

    }
    
}


// MARK: - Refreshing the counter of new messages

extension PersistedDiscussion {

    /// Refreshes the counter of new messages within this discussion.
    ///
    /// This method is called during bootstrap, each time a message is inserted, each time a message's status changes, or when the discussion mute setting changes.
    public func refreshNumberOfNewMessages() throws {
        guard self.managedObjectContext != nil else { assertionFailure(); throw Self.makeError(message: "Cannot find context") }
        let newNumberOfNewMessages: Int
        if isDeleted || localConfiguration.hasValidMuteNotificationsEndDate {
            newNumberOfNewMessages = 0
        } else {
            let numberOfNewMessagesReceived = try PersistedMessageReceived.countNew(within: self)
            let numberOfNewMessagesSystem = try PersistedMessageSystem.countNew(within: self)
            newNumberOfNewMessages = numberOfNewMessagesReceived + numberOfNewMessagesSystem
        }
        var incrementForOwnedIdentity = 0
        if self.numberOfNewMessages != newNumberOfNewMessages {
            incrementForOwnedIdentity = newNumberOfNewMessages - self.numberOfNewMessages
            self.numberOfNewMessages = newNumberOfNewMessages
        }
        ownedIdentity?.incrementBadgeCountForDiscussionsTab(by: incrementForOwnedIdentity)
    }
}


// MARK: - Manage pinned discussions

extension PersistedDiscussion {
    
    public var isPinned: Bool {
        pinnedIndex != nil
    }
    
    
    public static func setPinnedDiscussions(persistedDiscussionObjectIDs: [NSManagedObjectID], ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        
        try removePinnedFromPinnedDiscussionsForOwnedIdentity(ownedCryptoId, within: context)
        
        let retrievedDiscussions = try persistedDiscussionObjectIDs
            .compactMap({ try PersistedDiscussion.get(objectID: $0, within: context) })
            .filter({ $0.ownedIdentity?.cryptoId == ownedCryptoId })
        
        assert(retrievedDiscussions.count == persistedDiscussionObjectIDs.count)
        
        for (index, discussion) in retrievedDiscussions.enumerated() {
            discussion.pinnedIndex = index
        }

    }
    
}


// MARK: - Other methods

extension PersistedDiscussion {

    func resetTitle(to newTitle: String) throws {
        guard !newTitle.isEmpty else { throw Self.makeError(message: "The new title is empty") }
        if self.title != newTitle {
            self.title = newTitle
        }
    }

    public func insertSystemMessagesIfDiscussionIsEmpty(markAsRead: Bool, messageTimestamp: Date) throws {
        guard self.messages.isEmpty else { return }
        let systemMessage = try PersistedMessageSystem(.discussionIsEndToEndEncrypted, optionalContactIdentity: nil, optionalCallLogItem: nil, discussion: self, timestamp: messageTimestamp)
        if markAsRead {
            systemMessage.status = .read
        }
        insertUpdatedDiscussionSharedSettingsSystemMessageIfRequired(markAsRead: markAsRead)
    }

    /// If the discussion has some ephemeral setting set (read once, limited visibility or limited existence), the method inserts a system message allowing the user to see what kind of ephemerality is set.
    public func insertUpdatedDiscussionSharedSettingsSystemMessageIfRequired(markAsRead: Bool) {
        guard self.sharedConfiguration.isEphemeral else { return }
        let expirationJSON = self.sharedConfiguration.toExpirationJSON()
        try? PersistedMessageSystem.insertUpdatedDiscussionSharedSettingsSystemMessage(within: self, optionalContactIdentity: nil, expirationJSON: expirationJSON,  messageUploadTimestampFromServer: nil, markAsRead: markAsRead)
    }

    
    public static func insertSystemMessagesIfDiscussionIsEmpty(discussionObjectID: NSManagedObjectID, markAsRead: Bool, within context: NSManagedObjectContext) throws {
        guard context.concurrencyType != .mainQueueConcurrencyType else { throw Self.makeError(message: "insertSystemMessagesIfDiscussionIsEmpty expects to be on background context") }
        guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: context) else { throw Self.makeError(message: "Could not find discussion") }
        try discussion.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: markAsRead, messageTimestamp: Date())
    }
    
    
    public func getAllActiveParticipants() throws -> (ownCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>) {

        let contactCryptoIds: Set<ObvCryptoId>
        let ownCryptoId: ObvCryptoId

        switch try kind {

        case .oneToOne(withContactIdentity: let contactIdentity):
            
            guard let contactIdentity = contactIdentity else {
                throw Self.makeError(message: "Could not find contact identity")
            }
            guard let oneToOneDiscussion = self as? PersistedOneToOneDiscussion else {
                assertionFailure()
                throw Self.makeError(message: "Unexpected discussion kind")
            }
            contactCryptoIds = contactIdentity.isActive ? Set([contactIdentity.cryptoId]) : Set([])
            guard let _ownCryptoId = oneToOneDiscussion.ownedIdentity?.cryptoId else {
                throw Self.makeError(message: "Could not determine owned cryptoId (1)")
            }
            ownCryptoId = _ownCryptoId
            
        case .groupV1(withContactGroup: let group):
            
            guard let contactGroup = group else {
                throw Self.makeError(message: "Could not find contact group")
            }
            guard let _ownCryptoId = ownedIdentity?.cryptoId else {
                throw Self.makeError(message: "Could not determine owned cryptoId (2)")
            }
            ownCryptoId = _ownCryptoId
            switch contactGroup.category {
            case .owned:
                contactCryptoIds = Set(contactGroup.contactIdentities.filter({ $0.isActive }).map({ $0.cryptoId }))
            case .joined:
                guard let groupOwner = try? ObvCryptoId(identity: contactGroup.ownerIdentity) else {
                    throw Self.makeError(message: "Could not determine group owner")
                }
                assert(groupOwner != ownCryptoId)
                var cryptoIds = Set(contactGroup.contactIdentities.filter({ $0.isActive }).compactMap({ $0.cryptoId == ownCryptoId ? nil : $0.cryptoId }))
                assert((contactGroup as? PersistedContactGroupJoined)?.owner != nil)
                if (contactGroup as? PersistedContactGroupJoined)?.owner?.isActive == true {
                    cryptoIds.insert(groupOwner)
                }
                contactCryptoIds = cryptoIds
            }
            
        case .groupV2(withGroup: let group):
            
            guard let group = group else {
                throw Self.makeError(message: "Could not find group v2")
            }
            
            ownCryptoId = try group.ownCryptoId
            contactCryptoIds = Set(group.contactsAmongNonPendingOtherMembers.filter({ $0.isActive }).map({ $0.cryptoId }))

        }
        
        return (ownCryptoId, contactCryptoIds)
        
    }
    

    public var isCallAvailable: Bool {
        switch self.status {
        case .preDiscussion, .locked:
            return false
        case .active:
            switch try? self.kind {
            case .oneToOne:
                return true
            case .groupV1(withContactGroup: let contactGroup):
                if let contactGroup = contactGroup {
                    return !contactGroup.contactIdentities.isEmpty
                } else {
                    return false
                }
            case .groupV2(withGroup: let group):
                if let group = group {
                    return !group.otherMembers.isEmpty
                } else {
                    return false
                }
            case .none:
                assertionFailure()
                return false
            }
        }
    }
    
    public var subtitle: String {
        if let oneToOne = self as? PersistedOneToOneDiscussion {
            return oneToOne.contactIdentity?.identityCoreDetails?.positionAtCompany() ?? ""
        } else if let groupDiscussion = self as? PersistedGroupDiscussion {
            return groupDiscussion.contactGroup?.sortedContactIdentities.map({ $0.customOrFullDisplayName }).joined(separator: ", ") ?? ""
        } else if let groupDiscussion = self as? PersistedGroupV2Discussion {
            return groupDiscussion.group?.otherMembersSorted.compactMap({ $0.displayedCustomDisplayNameOrFirstNameOrLastName }).joined(separator: ", ") ?? ""
        } else {
            assertionFailure()
            return ""
        }
    }
    
    
    /// This variable is `true` iff the owned identity is allowed to send messages within this discussion.
    /// In oneToOne and group V1 discussions, the owned identity is always allowed to send messages.
    /// For group V2 discussions, it depends from the rights of the owned identity.
    var ownedIdentityIsAllowedToSendMessagesInThisDiscussion: Bool {
        get throws {
            switch try self.kind {
            case .oneToOne, .groupV1:
                return true // We are always allowed to send messages in oneToOne and groupV1 discussions
            case .groupV2(withGroup: let group):
                guard let group = group else { return false }
                return group.ownedIdentityIsAllowedToSendMessage
            }
        }
    }

    
    /// Updates the updateNormalizedSearchKey attribute of this entity
    func updateNormalizedSearchKey() throws {
        let newNormalizedSearchKey: String?
        switch try kind {
        case .groupV1(let group):
            if let group {
                newNormalizedSearchKey = DisplayedContactGroup.normalizedSearchKeyFromGroupV1(group)
            } else {
                newNormalizedSearchKey = title
            }
        case .groupV2(let group):
            if let group {
                newNormalizedSearchKey = DisplayedContactGroup.normalizedSearchKeyFromGroupV2(group)
            } else {
                newNormalizedSearchKey = title
            }
        case .oneToOne(let identity):
            if let identity {
                newNormalizedSearchKey = identity.sortDisplayName
            } else {
                newNormalizedSearchKey = title
            }
        }
        guard self.normalizedSearchKey != newNormalizedSearchKey else { return }
        self.normalizedSearchKey = newNormalizedSearchKey
    }
}

// MARK: - Retention related methods

extension PersistedDiscussion {

    public func sendNotificationIndicatingThatAnOldDiscussionSharedConfigurationWasReceived() {
        ObvMessengerCoreDataNotification.anOldDiscussionSharedConfigurationWasReceived(persistedDiscussionObjectID: self.objectID)
            .postOnDispatchQueue()
    }
    
    
    /// If `nil`, no message should be deleted because of time retention. Otherwise, the return
    /// date is the limit date for retention.
    ///
    /// If the non `nil`:
    /// - Outbound messages that were sent before this date should be deleted
    /// - Non-new inbound messages that were received before this date should be deleted
    public var effectiveTimeBasedRetentionDate: Date? {
        guard let timeInterval = self.effectiveTimeIntervalRetention else { return nil }
        return Date(timeIntervalSinceNow: -timeInterval)
    }
    
    public var effectiveTimeIntervalRetention: TimeInterval? {
        switch localConfiguration.timeBasedRetention {
        case .useAppDefault:
            guard let timeInterval = ObvMessengerSettings.Discussions.timeBasedRetentionPolicy.timeInterval else { return nil }
            return timeInterval
        default:
            return localConfiguration.timeBasedRetention.timeInterval
        }
    }
    
    public var effectiveCountBasedRetention: Int? {
        switch localConfiguration.countBasedRetentionIsActive {
        case .none:
            // Use the app default configuration to know whether we should return a value
            guard ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive else { return nil }
            // If we reach this point, there is a count-based retention policy that applies.
            // If it exists, the local count based superseeds the app default count based retention.
            return localConfiguration.countBasedRetention ?? ObvMessengerSettings.Discussions.countBasedRetentionPolicy
        case .some(true):
            return localConfiguration.countBasedRetention ?? ObvMessengerSettings.Discussions.countBasedRetentionPolicy
        case .some(false):
            return nil
        }
    }
    
}

// MARK: - Configuration related methods

public extension PersistedDiscussion {

    var autoRead: Bool {
        localConfiguration.autoRead ?? ObvMessengerSettings.Discussions.autoRead
    }

    var retainWipedOutboundMessages: Bool {
        localConfiguration.retainWipedOutboundMessages ?? ObvMessengerSettings.Discussions.retainWipedOutboundMessages
    }

    /// Helper attribute, this is solely to be used for UI-related purposes. Like showing the moon icon on the discussions list to indicate that this discussion is muted
    var hasNotificationsMuted: Bool {
        return localConfiguration.hasNotificationsMuted
    }

}


// MARK: - Managing the isArchived Boolean

extension PersistedDiscussion {
    
    public func unarchive() {
        guard isArchived else { return }
        isArchived = false
        // Since we unarchive the discussion, it will be shown in the list of recent discussions.
        // We want to make sure is contains the end-to-end encryption system message, as well as other informative messages.
        try? insertSystemMessagesIfDiscussionIsEmpty(markAsRead: true, messageTimestamp: Date())
    }
    
    public func unarchiveAndUpdateTimestampOfLastMessage() {
        unarchive()
        timestampOfLastMessage = Date()
    }
    
    public func archive() throws {

        guard !isArchived else { return }
        isArchived = true

        try PersistedMessageReceived.markAllAsNotNew(within: self)
        try PersistedMessageSystem.markAllAsNotNew(within: self)
        
        self.pinnedIndex = nil

    }
    
}

// MARK: - Convenience DB getters

extension PersistedDiscussion {

    struct Predicate {
        enum Key: String {
            // Attributes
            case aNewReceivedMessageDoesMentionOwnedIdentity = "aNewReceivedMessageDoesMentionOwnedIdentity"
            case isArchived = "isArchived"
            case lastOutboundMessageSequenceNumber = "lastOutboundMessageSequenceNumber"
            case lastSystemMessageSequenceNumber = "lastSystemMessageSequenceNumber"
            case normalizedSearchKey = "normalizedSearchKey"
            case numberOfNewMessages = "numberOfNewMessages"
            case permanentUUID = "permanentUUID"
            case rawPinnedIndex = "rawPinnedIndex"
            case pinnedSectionKeyPath = "pinnedSectionKeyPath"
            case rawStatus = "rawStatus"
            case senderThreadIdentifier = "senderThreadIdentifier"
            case timestampOfLastMessage = "timestampOfLastMessage"
            case title = "title"
            // Relationships
            case draft = "draft"
            case illustrativeMessage = "illustrativeMessage"
            case localConfiguration = "localConfiguration"
            case messages = "messages"
            case ownedIdentity = "ownedIdentity"
            case remoteDeleteAndEditRequests = "remoteDeleteAndEditRequests"
            case sharedConfiguration = "sharedConfiguration"
            static let ownedIdentityIdentity = [Key.ownedIdentity.rawValue, PersistedObvOwnedIdentity.Predicate.Key.identity.rawValue].joined(separator: ".")
            static let muteNotificationsEndDate = [Predicate.Key.localConfiguration.rawValue, PersistedDiscussionLocalConfiguration.Predicate.Key.muteNotificationsEndDate.rawValue].joined(separator: ".")
        }
        static func whereIsPinnedIs(_ isPinned: Bool) -> NSPredicate {
            if isPinned {
                return NSPredicate(withNonNilValueForKey: Key.rawPinnedIndex)
            } else {
                return NSPredicate(withNilValueForKey: Key.rawPinnedIndex)
            }
        }
        static func withOwnCryptoId(_ ownCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownCryptoId.getIdentity())
        }
        static func persistedDiscussion(withObjectID objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
        static func withStatus(_ status: Status) -> NSPredicate {
            NSPredicate(Key.rawStatus, EqualToInt: status.rawValue)
        }
        static var withNoMessage: NSPredicate {
            NSPredicate(withZeroCountForKey: PersistedDiscussion.Predicate.Key.messages)
        }
        static var withMessages: NSPredicate {
            NSPredicate(withStrictlyPositiveCountForKey: Predicate.Key.messages)
        }
        static func withNormalizedSearchKey(contains text: String) -> NSPredicate {
            NSPredicate(containsText: text, forKey: Predicate.Key.normalizedSearchKey)
        }
        static fileprivate var isPersistedGroupDiscussion: NSPredicate {
            NSPredicate(withEntity: PersistedGroupDiscussion.entity())
        }
        static fileprivate var isPersistedGroupV2Discussion: NSPredicate {
            NSPredicate(withEntity: PersistedGroupV2Discussion.entity())
        }
        static fileprivate var isGroupDiscussion: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                isPersistedGroupDiscussion,
                isPersistedGroupV2Discussion,
            ])
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) -> NSPredicate {
            NSPredicate(Key.permanentUUID, EqualToUuid: permanentID.uuid)
        }
        static func isArchived(is bool: Bool) -> NSPredicate {
            NSPredicate(Key.isArchived, is: bool)
        }
        static var isUnmuted: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(withNilValueForRawKey: Key.muteNotificationsEndDate),
                NSPredicate(Key.muteNotificationsEndDate, earlierThan: Date()),
            ])
        }
        static func whereANewReceivedMessageDoesMentionOwnedIdentity(is bool: Bool) -> NSPredicate {
            NSPredicate(Key.aNewReceivedMessageDoesMentionOwnedIdentity, is: bool)
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedDiscussion> {
        return NSFetchRequest<PersistedDiscussion>(entityName: PersistedDiscussion.entityName)
    }
    
    
    public static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedDiscussion? {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = Predicate.persistedDiscussion(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    public static func get(objectID: TypeSafeManagedObjectID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> PersistedDiscussion? {
        return try get(objectID: objectID.objectID, within: context)
    }

    
    public static func getAllSortedByTimestampOfLastMessageForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedDiscussion] {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.timestampOfLastMessage.rawValue, ascending: false)]
        return try context.fetch(request)
    }
    
    
    public static func getAllActiveDiscussionsForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedDiscussion] {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = Predicate.withStatus(.active)
        request.fetchBatchSize = 500
        return try context.fetch(request)
    }

    
    public static func getAllDiscussionsForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedDiscussion] {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.fetchBatchSize = 500
        return try context.fetch(request)
    }

    
    /// Deletes all the locked discussions that have no message, for all owned identities.
    public static func deleteAllLockedDiscussionsWithNoMessage(within context: NSManagedObjectContext, log: OSLog) throws {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withStatus(.locked),
            Predicate.withNoMessage,
        ])
        let emptyLockedDiscussions = try context.fetch(request)
        for discussion in emptyLockedDiscussions {
            do {
                try discussion.deleteDiscussion(requester: nil)
            } catch {
                os_log("One of the empty locked discussion could not be deleted", log: log, type: .fault)
                assertionFailure()
                // Continue anyway
            }
        }
    }


    public static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, within context: NSManagedObjectContext) throws -> PersistedDiscussion? {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    /// This method uses aggregate functions to return the sum of the number of new messages for all discussions corresponding to a specific owned identity.
    /// This is used when computing the new value of the badge for the discussions tab.
    /// See also ``static PersistedDiscussion.countNumberOfMutedDiscussionsWithNewMessageMentioningOwnedIdentity(_:)``.
    static func countSumOfNewMessagesWithinUnmutedDiscussionsForOwnedIdentity(_ persistedOwnedIdentity: PersistedObvOwnedIdentity) throws -> Int {
        guard let context = persistedOwnedIdentity.managedObjectContext else { throw Self.makeError(message: "Context is not set") }
        // Create an expression description that will allow to aggregate the values of the numberOfNewMessages column
        let expressionDescription = NSExpressionDescription()
        expressionDescription.name = "sumOfNumberOfNewMessages"
        expressionDescription.expression = NSExpression(format: "@sum.\(Predicate.Key.numberOfNewMessages.rawValue)")
        expressionDescription.expressionResultType = .integer64AttributeType
        // Create a predicate that will restrict to the discussions of the owned identity, and that restrict to unmuted discussions
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(persistedOwnedIdentity.cryptoId),
            Predicate.isUnmuted,
        ])
        // Create the fetch request
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.predicate = predicate
        request.propertiesToFetch = [expressionDescription]
        request.includesPendingChanges = true
        guard let results = try context.fetch(request).first as? [String: Int] else { throw makeError(message: "Could cast fetched result") }
        guard let sumOfNumberOfNewMessages = results["sumOfNumberOfNewMessages"] else { throw makeError(message: "Could not get uploadedByteCount") }
        return sumOfNumberOfNewMessages
    }
    
    
    /// This method returns the number of muted discussions that contain at least one new message that mentions the owned identity.
    /// This is used when computing the new value of the badge for the discussions tab.
    /// See also ``static PersistedDiscussion.countSumOfNewMessagesWithinUnmutedDiscussionsForOwnedIdentity(_:)``.
    static func countNumberOfMutedDiscussionsWithNewMessageMentioningOwnedIdentity(_ persistedOwnedIdentity: PersistedObvOwnedIdentity) throws -> Int {
        guard let context = persistedOwnedIdentity.managedObjectContext else { throw Self.makeError(message: "Context is not set") }
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(persistedOwnedIdentity.cryptoId),
            NSCompoundPredicate(notPredicateWithSubpredicate: Predicate.isUnmuted),
            Predicate.whereANewReceivedMessageDoesMentionOwnedIdentity(is: true),
        ])
        request.includesPendingChanges = true
        return try context.count(for: request)
    }
    
    
    private static func removePinnedFromPinnedDiscussionsForOwnedIdentity(_ ownedIdentity: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(ownedIdentity),
            Predicate.whereIsPinnedIs(true),
        ])
        request.fetchBatchSize = 100
        request.propertiesToFetch = []
        
        let results = try context.fetch(request)
        results.forEach({ $0.pinnedIndex = nil })
    }
    
    
    /// Updates the normalizedSearchKeys of all discussions for the given owenedIdentity
    /// - Parameters:
    ///   - ownedIdentity: The ownedIdentity whose discussions we want to update
    ///   - context: The context in which those updates should occur
    public static func updateNormalizedSearchKeysForOwnedIdentity(_ ownedIdentity: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(ownedIdentity)
        ])
        request.fetchBatchSize = 100
        request.propertiesToFetch = []
        
        let results = try context.fetch(request)
        for discussion in results {
            do {
                try discussion.updateNormalizedSearchKey()
            } catch {
                os_log("Failed to update normalized search key %@", log: log, type: .fault, error.localizedDescription)
                continue
            }
        }
    }
    
    public static func countUnarchivedDiscussionsOfOwnedIdentity(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(ownedCryptoId),
            Predicate.isArchived(is: false),
        ])
        return try context.count(for: request)
    }
    
}


// MARK: - NSFetchRequest creators

extension PersistedDiscussion {

    /// Returns the `objectID`s of all the discussions of the given owned identity. This is typically used to perform a deletion of all the discussions when the owned identity gets deleted.
    static func getObjectIDsOfAllDiscussionsOfOwnedIdentity(persistedOwnedIdentity: PersistedObvOwnedIdentity) throws -> [NSManagedObjectID] {
        guard let context = persistedOwnedIdentity.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let request = NSFetchRequest<NSManagedObjectID>(entityName: Self.entityName)
        request.resultType = .managedObjectIDResultType
        request.predicate = Predicate.withOwnCryptoId(persistedOwnedIdentity.cryptoId)
        let objectIDs = try context.fetch(request)
        return objectIDs
    }
    
    
    /// Returns a `NSFetchRequest` for all the group discussions (both V1 and V2) of the owned identity, sorted by the discussion title.
    public static func getFetchRequestForAllGroupDiscussionsSortedByTitleForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> FetchRequestControllerModel<PersistedDiscussion> {
        let fetchRequest: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.title.rawValue, ascending: true)]
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(ownedCryptoId),
            Predicate.isGroupDiscussion,
        ])
        fetchRequest.relationshipKeyPathsForPrefetching = [
            Predicate.Key.illustrativeMessage.rawValue,
            Predicate.Key.localConfiguration.rawValue,
        ]
        return FetchRequestControllerModel(fetchRequest: fetchRequest, sectionNameKeyPath: nil)
    }

    
    /// Returns a `NSFetchRequest` for the non-archived discussions of the owned identity, sorted by the timestamp of the last message of each discussion.
    public static func getFetchRequestForNonArchivedRecentDiscussionsForOwnedIdentity(with ownedCryptoId: ObvCryptoId, splitPinnedDiscussionsIntoSections: Bool) -> FetchRequestControllerModel<PersistedDiscussion> {
        let fetchRequest: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(ownedCryptoId),
            Predicate.isArchived(is: false),
        ])
        
        let sectionNameKeyPath: String?
        if splitPinnedDiscussionsIntoSections {
            fetchRequest.sortDescriptors = [
                NSSortDescriptor(key: Predicate.Key.pinnedSectionKeyPath.rawValue, ascending: false),
                NSSortDescriptor(key: Predicate.Key.rawPinnedIndex.rawValue, ascending: true),
                NSSortDescriptor(key: Predicate.Key.timestampOfLastMessage.rawValue, ascending: false)
            ]
            sectionNameKeyPath = Predicate.Key.pinnedSectionKeyPath.rawValue
        } else {
            fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.timestampOfLastMessage.rawValue, ascending: false)]
            sectionNameKeyPath = nil
        }
        
        fetchRequest.relationshipKeyPathsForPrefetching = [
            Predicate.Key.illustrativeMessage.rawValue,
            Predicate.Key.localConfiguration.rawValue,
        ]
        return FetchRequestControllerModel(fetchRequest: fetchRequest, sectionNameKeyPath: sectionNameKeyPath)
    }


    /// Returns a `NSFetchRequest` for the non-empty and active discussions of the owned identity, sorted by the timestamp of the last message of each discussion.
    public static func getFetchRequestForAllActiveRecentDiscussionsForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> FetchRequestControllerModel<PersistedDiscussion> {

        let fetchRequest: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()

        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(ownedCryptoId),
            Predicate.withStatus(.active)
        ])

        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.timestampOfLastMessage.rawValue, ascending: false)]

        return FetchRequestControllerModel(fetchRequest: fetchRequest, sectionNameKeyPath: nil)
    }
    
    /// Returns a `NSFetchRequest` for the non-empty discussions of the owned identity, sorted by the timestamp of the last message of each discussion.
    public static func getFetchRequestForSearchTermForDiscussionsForOwnedIdentity(with ownedCryptoId: ObvCryptoId, searchTerm: String?) -> FetchRequestControllerModel<PersistedDiscussion> {
        let fetchRequest: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        
        var subPredicates = [Predicate.withOwnCryptoId(ownedCryptoId)]
        
        if let searchTerm {
            let searchTerms = searchTerm.trimmingWhitespacesAndNewlines().split(separator: " ").map({ String($0) })
            let searchTermsPredicates = searchTerms.map({ Predicate.withNormalizedSearchKey(contains: $0) })
            let searchTermsPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: searchTermsPredicates)
            subPredicates.append(searchTermsPredicate)
        }
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
        
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: Predicate.Key.pinnedSectionKeyPath.rawValue, ascending: false),
            NSSortDescriptor(key: Predicate.Key.rawPinnedIndex.rawValue, ascending: true),
            NSSortDescriptor(key: Predicate.Key.timestampOfLastMessage.rawValue, ascending: false)
        ]
        let sectionNameKeyPath = Predicate.Key.pinnedSectionKeyPath.rawValue
        
        fetchRequest.relationshipKeyPathsForPrefetching = [
            Predicate.Key.illustrativeMessage.rawValue,
            Predicate.Key.localConfiguration.rawValue,
        ]
        return FetchRequestControllerModel(fetchRequest: fetchRequest, sectionNameKeyPath: sectionNameKeyPath)
    }
    
    public static func getFetchedResultsController(model: FetchRequestControllerModel<PersistedDiscussion>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDiscussion> {
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: model.fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: model.sectionNameKeyPath,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
        
    
    static func getAllLockedWithNoMessage(within context: NSManagedObjectContext) throws -> [PersistedDiscussion] {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withStatus(.locked),
            Predicate.withNoMessage,
        ])
        return try context.fetch(request)
    }


}


// MARK: - Sending notifications on changes

extension PersistedDiscussion {
    
    public override func willSave() {
        super.willSave()
        if isInserted {
            do {
                try self.updateNormalizedSearchKey()
            } catch {
                assertionFailure("Could not update normalised search key when creating the discussion: \(error.localizedDescription)")
            }
        }
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
        if isDeleted {
            assert(self.managedObjectContext?.concurrencyType != .mainQueueConcurrencyType)
            self.discussionPermanentIDOnDeletion = self.discussionPermanentID
        }
    }

    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
            discussionPermanentIDOnDeletion = nil
        }
        
        if changedKeys.contains(Predicate.Key.title.rawValue) {
            ObvMessengerCoreDataNotification.persistedDiscussionHasNewTitle(objectID: typedObjectID, title: title)
                .postOnDispatchQueue()
        }
        
        if changedKeys.contains(Predicate.Key.rawStatus.rawValue), !isDeleted {
            ObvMessengerCoreDataNotification.persistedDiscussionStatusChanged(discussionPermanentID: self.discussionPermanentID, newStatus: status)
                .postOnDispatchQueue()
        }
        
        if changedKeys.contains(Predicate.Key.isArchived.rawValue), !isDeleted, self.isArchived {
            ObvMessengerCoreDataNotification.persistedDiscussionWasArchived(discussionPermanentID: self.discussionPermanentID)
                .postOnDispatchQueue()
        }

        if let discussionPermanentIDOnDeletion, isDeleted {
            ObvMessengerCoreDataNotification.persistedDiscussionWasDeleted(discussionPermanentID: discussionPermanentIDOnDeletion, objectIDOfDeletedDiscussion: self.typedObjectID)
                .postOnDispatchQueue()
        }
        
        if isInserted {
            ObvMessengerCoreDataNotification.persistedDiscussionWasInserted(discussionPermanentID: discussionPermanentID, objectID: typedObjectID)
                .postOnDispatchQueue()
        }
        
    }
    
}

// MARK: - Downcasting ObvManagedObjectPermanentID of subclasses of PersistedDiscussion

extension ObvManagedObjectPermanentID where T: PersistedDiscussion {

    var downcast: ObvManagedObjectPermanentID<PersistedDiscussion> {
        ObvManagedObjectPermanentID<PersistedDiscussion>(entityName: PersistedDiscussion.entityName, uuid: self.uuid)
    }
     
    public init?(_ description: String) {
        self.init(description, expectedEntityName: PersistedDiscussion.entityName)
    }

}


// MARK: - DiscussionPermanentID

public typealias DiscussionPermanentID = ObvManagedObjectPermanentID<PersistedDiscussion>
