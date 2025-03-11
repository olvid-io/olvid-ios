/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvUIObvCircledInitials
import ObvEngine
import ObvSettings
import ObvAppTypes


@objc(PersistedDiscussion)
public class PersistedDiscussion: NSManagedObject {

    fileprivate static let entityName = "PersistedDiscussion"
    
    private static let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: PersistedDiscussion.self))
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: PersistedDiscussion.self))
    
    public enum PinnedSectionKeyPathValue: String {
        case pinned = "1"
        case unpinned = "0"
    }
    
    // Attributes
    
    @NSManaged public private(set) var aNewReceivedMessageDoesMentionOwnedIdentity: Bool // True iff a new received message has doesMentionOwnedIdentity set to True
    @NSManaged public private(set) var isArchived: Bool
    @NSManaged private var lastOutboundMessageSequenceNumber: Int
    @NSManaged private var lastSystemMessageSequenceNumber: Int
    @NSManaged private var normalizedSearchKey: String?
    @NSManaged public private(set) var numberOfNewMessages: Int // Set to 0 when this discussion is muted (not to be used when displaying the number of new messages when entering the discussion)
    @NSManaged private var onChangeFlag: Int // Only used internally to trigger UI updates, transient
    @NSManaged public private(set) var permanentUUID: UUID
    @NSManaged private var rawLocalDateWhenDiscussionRead: Date?
    @NSManaged private var rawPinnedIndex: NSNumber?
    @NSManaged private(set) var pinnedSectionKeyPath: String // Shall only be modified in the setter of pinnedIndex
    @NSManaged private var rawServerTimestampWhenDiscussionReadOnAnotherOwnedDevice: Date?
    @NSManaged private var rawStatus: Int
    @NSManaged private(set) var senderThreadIdentifier: UUID // Of the owned identity, on this device (it is different for the same owned identity on her other owned devices)
    @NSManaged private var serverTimestampOfLastRemoteDeletion: Date? // When a remote discussion delete request comes from a remote (owned or contact) device, we keep the request's server timestamp
    @NSManaged public private(set) var timestampOfLastMessage: Date
    @NSManaged public private(set) var title: String
    

    // Relationships

    @NSManaged public private(set) var draft: PersistedDraft
    @NSManaged public private(set) var illustrativeMessage: PersistedMessage?
    @NSManaged public private(set) var localConfiguration: PersistedDiscussionLocalConfiguration
    @NSManaged public private(set) var messages: Set<PersistedMessage>
    @NSManaged public private(set) var ownedIdentity: PersistedObvOwnedIdentity? // If nil, this entity is eventually cascade-deleted
    @NSManaged public private(set) var sharedConfiguration: PersistedDiscussionSharedConfiguration
    
    // Other variables
    
    /// 2023-07-17: This is the most appropriate identifier to use in, e.g., notifications
    public var identifier: DiscussionIdentifier {
        get throws {
            switch try self.kind {
            case .oneToOne:
                return .oneToOne(id: .objectID(objectID: self.objectID))
            case .groupV1:
                return .groupV1(id: .objectID(objectID: self.objectID))
            case .groupV2:
                return .groupV2(id: .objectID(objectID: self.objectID))
            }
        }
    }
    
    private var changedKeys = Set<String>()

    public private(set) var status: Status {
        get {
            guard let status = Status(rawValue: rawStatus) else { assertionFailure(); return .active }
            return status
        }
        set {
            if self.rawStatus != newValue.rawValue {
                self.rawStatus = newValue.rawValue
            }
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
                throw ObvUICoreDataError.unknownDiscussionType
            }
        }
    }
    
    
    public func getLimitedVisibilityMessageOpenedJSON(for message: PersistedMessage) throws -> LimitedVisibilityMessageOpenedJSON {
        guard self == message.discussion else {
            throw ObvUICoreDataError.unexpectedDiscussionForMessage
        }
        guard let messageReference = message.toMessageReferenceJSON() else {
            throw ObvUICoreDataError.couldNotConstructMessageReferenceJSON
        }
        switch try self.kind {
        case .oneToOne:
            guard let oneToOneIdentifier = try (self as? PersistedOneToOneDiscussion)?.oneToOneIdentifier else {
                throw ObvUICoreDataError.couldNotDetermineDiscussionIdentifier
            }
            return LimitedVisibilityMessageOpenedJSON(messageReference: messageReference, oneToOneIdentifier: oneToOneIdentifier)
        case .groupV1(withContactGroup: let contactGroup):
            guard let groupId = try contactGroup?.getGroupId() else {
                throw ObvUICoreDataError.couldNotDetermineDiscussionIdentifier
            }
            return LimitedVisibilityMessageOpenedJSON(messageReference: messageReference, groupV1Identifier: groupId)
        case .groupV2(withGroup: let group):
            guard let groupIdentifier = group?.groupIdentifier else {
                throw ObvUICoreDataError.couldNotDetermineDiscussionIdentifier
            }
            return LimitedVisibilityMessageOpenedJSON(messageReference: messageReference, groupV2Identifier: groupIdentifier)
        }
    }

    
    public var discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion> {
        ObvManagedObjectPermanentID(entityName: PersistedDiscussion.entityName, uuid: self.permanentUUID)
    }
    
    public var discussionIdentifier: ObvDiscussionIdentifier {
        get throws {
            switch try self.kind {
            case .oneToOne:
                guard let discussion = self as? PersistedOneToOneDiscussion else {
                    assertionFailure()
                    throw ObvUICoreDataError.inconsistentDiscussion
                }
                guard let id = discussion.contactIdentifier else {
                    assertionFailure()
                    throw ObvUICoreDataError.unexpectedContactIdentifier
                }
                return .oneToOne(id: id)
            case .groupV1:
                guard let discussion = self as? PersistedGroupDiscussion else {
                    assertionFailure()
                    throw ObvUICoreDataError.inconsistentDiscussion
                }
                guard let id = discussion.groupIdentifier else {
                    assertionFailure()
                    throw ObvUICoreDataError.couldNotParseGroupIdentifier
                }
                return .groupV1(id: id)
            case .groupV2:
                guard let discussion = self as? PersistedGroupV2Discussion else {
                    assertionFailure()
                    throw ObvUICoreDataError.inconsistentDiscussion
                }
                guard let id = discussion.obvGroupIdentifier else {
                    throw ObvUICoreDataError.groupV2IsNil
                }
                return .groupV2(id: id)
            }
        }
    }
    
    private var discussionIdentifierOnDeletion: ObvDiscussionIdentifier?
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
    
    
    var serverTimestampWhenDiscussionReadOnAnotherOwnedDevice: Date {
        get {
            rawServerTimestampWhenDiscussionReadOnAnotherOwnedDevice ?? .distantPast
        }
        set {
            if let rawServerTimestampWhenDiscussionReadOnAnotherOwnedDevice {
                guard newValue > rawServerTimestampWhenDiscussionReadOnAnotherOwnedDevice else { return }
                self.rawServerTimestampWhenDiscussionReadOnAnotherOwnedDevice = newValue
            } else {
                self.rawServerTimestampWhenDiscussionReadOnAnotherOwnedDevice = newValue
            }
        }
    }

    
    var localDateWhenDiscussionRead: Date {
        get {
            rawLocalDateWhenDiscussionRead ?? .distantPast
        }
        set {
            if let rawLocalDateWhenDiscussionRead {
                guard newValue > rawLocalDateWhenDiscussionRead else { return }
                self.rawLocalDateWhenDiscussionRead = newValue
            } else {
                self.rawLocalDateWhenDiscussionRead = newValue
            }
        }
    }

    
    /// Handles deletion requests for discussions
    ///
    /// This method is triggered when:
    /// - The user initiates a local deletion request from this device or a remote deletion request from another owned device.
    /// - A group member with moderation rights requests deletion in a Group v2 discussion.
    ///
    /// Note: For remote deletion requests (from another device or a group moderator), we store the server timestamp to ensure that any messages sent before the deletion request but received later are not displayed in the discussion.
    /// If the request is local, `messageUploadTimestampFromServer` will be `nil`.
    func removeAllMessages(messageUploadTimestampFromServer: Date?) {
        
        if let messageUploadTimestampFromServer {
            if let serverTimestampOfLastRemoteDeletion {
                if serverTimestampOfLastRemoteDeletion < messageUploadTimestampFromServer {
                    self.serverTimestampOfLastRemoteDeletion = messageUploadTimestampFromServer
                }
            } else {
                self.serverTimestampOfLastRemoteDeletion = messageUploadTimestampFromServer
            }
        }
        
        self.messages.removeAll()
    }

    
    // MARK: - Initializer

    convenience init(title: String, ownedIdentity: PersistedObvOwnedIdentity, forEntityName entityName: String, status: Status, shouldApplySharedConfigurationFromGlobalSettings: Bool, isRestoringSyncSnapshotOrBackup: Bool) throws {
        
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.isInsertedWhileRestoringSyncSnapshot = isRestoringSyncSnapshotOrBackup
        
        self.isArchived = false
        self.lastOutboundMessageSequenceNumber = 0
        self.lastSystemMessageSequenceNumber = 0
        self.normalizedSearchKey = nil
        self.numberOfNewMessages = 0
        self.permanentUUID = UUID()
        self.rawPinnedIndex = nil
        self.pinnedSectionKeyPath = PinnedSectionKeyPathValue.unpinned.rawValue
        self.onChangeFlag = 0
        self.senderThreadIdentifier = UUID()
        self.timestampOfLastMessage = Date()
        self.title = title
        self.status = status
        self.aNewReceivedMessageDoesMentionOwnedIdentity = false
        self.rawLocalDateWhenDiscussionRead = nil
        self.serverTimestampOfLastRemoteDeletion = nil
        
        let sharedConfiguration = try PersistedDiscussionSharedConfiguration(discussion: self)
        if shouldApplySharedConfigurationFromGlobalSettings {
            sharedConfiguration.setValuesUsingSettings()
        }
        self.sharedConfiguration = sharedConfiguration
        
        let localConfiguration = try PersistedDiscussionLocalConfiguration(discussion: self, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
        self.localConfiguration = localConfiguration
        self.sharedConfiguration = sharedConfiguration
        self.draft = try PersistedDraft(within: self)
        self.messages = Set<PersistedMessage>()
        self.ownedIdentity = ownedIdentity
          
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
        
    func deletePersistedDiscussion() throws {
        guard let context = managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        self.discussionIdentifierOnDeletion = try self.discussionIdentifier
        context.delete(self)
    }
    
    
    /// This is expected to be called from the UI in order to determine which deletion types can be shown.
    ///
    /// This is implemented by creating a child context in which we simulate the deletion of the discussion.
    /// Of course, the child context is not saved to prevent any side-effect (view contexts are never saved anyway).
    public var deletionTypesThatCanBeMadeAvailableForThisDiscussion: Set<DeletionType> {
        
        guard let context = self.managedObjectContext else {
            assertionFailure()
            return Set()
        }
        
        guard context.concurrencyType == .mainQueueConcurrencyType else {
            assertionFailure()
            return Set()
        }
        
        var acceptableDeletionTypes = Set<DeletionType>()
        
        for deletionType in DeletionType.allCases {
            
            let childViewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
            childViewContext.parent = context
            guard let discussionInChildViewContext = try? PersistedDiscussion.get(objectID: self.objectID, within: childViewContext) else {
                assertionFailure()
                return Set()
            }
            guard let ownedIdentityInChildViewContext = discussionInChildViewContext.ownedIdentity else {
                assertionFailure()
                return Set()
            }
            do {
                _ = try ownedIdentityInChildViewContext.processDiscussionDeletionRequestFromCurrentDeviceOfThisOwnedIdentity(discussionObjectID: discussionInChildViewContext.typedObjectID, deletionType: deletionType)
                acceptableDeletionTypes.insert(deletionType)
            } catch {
                continue
            }
            
        }
        
        return acceptableDeletionTypes

    }
    

    private func setLastOutboundMessageSequenceNumber(to newLastOutboundMessageSequenceNumber: Int) {
        if self.lastOutboundMessageSequenceNumber != newLastOutboundMessageSequenceNumber {
            self.lastOutboundMessageSequenceNumber = newLastOutboundMessageSequenceNumber
        }
    }
    
    
    func incrementLastOutboundMessageSequenceNumber() -> Int {
        setLastOutboundMessageSequenceNumber(to: lastOutboundMessageSequenceNumber + 1)
        return lastOutboundMessageSequenceNumber
    }
    
    
    private func setLastSystemMessageSequenceNumber(to newLastSystemMessageSequenceNumber: Int) {
        if self.lastSystemMessageSequenceNumber != newLastSystemMessageSequenceNumber {
            self.lastSystemMessageSequenceNumber = newLastSystemMessageSequenceNumber
        }
    }

    
    func incrementLastSystemMessageSequenceNumber() -> Int {
        self.setLastSystemMessageSequenceNumber(to: lastSystemMessageSequenceNumber + 1)
        return lastSystemMessageSequenceNumber
    }
    
    
    /// Used when restoring a sync snapshot or when restoring a backup to prevent any notification on insertion
    private var isInsertedWhileRestoringSyncSnapshot = false

    
    // MARK: - Observers
    
    private static var observersHolder = PersistedDiscussionObserversHolder()
    
    public static func addObserver(_ newObserver: PersistedDiscussionObserver) async {
        await observersHolder.addObserver(newObserver)
    }
    
    
    // MARK: - Status management

    func setStatus(to newStatus: Status) throws {
        self.status = newStatus
    }

    
    // MARK: - Receiving discussion shared configurations

    /// We mark this method as `final` just because, at the time of writing, we don't need to override it in subclasses.
    final func mergeReceivedDiscussionSharedConfiguration(_ remoteSharedConfiguration: SharedConfiguration) throws -> (sharedSettingHadToBeUpdated: Bool, weShouldSendBackOurSharedSettings: Bool) {
        
        switch self.status {
            
        case .locked:
            
            throw ObvUICoreDataError.cannotChangeShareConfigurationOfLockedDiscussion
            
        case .preDiscussion:
            
            throw ObvUICoreDataError.cannotChangeShareConfigurationOfPreDiscussion
            
        case .active:
            
            let (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettingsIfAllowedTo) = try self.sharedConfiguration.mergePersistedDiscussionSharedConfiguration(with: remoteSharedConfiguration)
            return (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettingsIfAllowedTo)
            
        }
        
    }

    
    func replaceReceivedDiscussionSharedConfiguration(with expiration: ExpirationJSON) throws -> Bool {
        
        switch self.status {
            
        case .locked:
            throw ObvUICoreDataError.cannotChangeShareConfigurationOfLockedDiscussion
            
        case .preDiscussion:
            throw ObvUICoreDataError.cannotChangeShareConfigurationOfPreDiscussion
            
        case .active:
            let sharedSettingHadToBeUpdated = try self.sharedConfiguration.replacePersistedDiscussionSharedConfiguration(with: expiration)
            return sharedSettingHadToBeUpdated
            
        }

    }

    
    func insertSystemMessageIndicatingThatDiscussionSharedConfigurationWasUpdatedByOwnedIdentity(messageUploadTimestampFromServer: Date?) throws {
        
        try PersistedMessageSystem.insertUpdatedDiscussionSharedSettingsSystemMessage(
            within: self,
            optionalContactIdentity: nil,
            expirationJSON: self.sharedConfiguration.toExpirationJSON(),
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            markAsRead: true)

    }

    
    func insertSystemMessageIndicatingThatDiscussionSharedConfigurationWasUpdatedByContact(persistedContact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date?) throws {
        
        try PersistedMessageSystem.insertUpdatedDiscussionSharedSettingsSystemMessage(
            within: self,
            optionalContactIdentity: persistedContact,
            expirationJSON: self.sharedConfiguration.toExpirationJSON(),
            messageUploadTimestampFromServer: messageUploadTimestampFromServer,
            markAsRead: false)

    }

    
    struct SharedConfiguration {
        let version: Int
        let expiration: ExpirationJSON
    }

    
    // MARK: - Processing wipe requests

    /// Called when receiving a wipe message request from a contact or from another owned device
    func processWipeMessageRequest(of messagesToDelete: [MessageReferenceJSON], from requester: ObvCryptoId, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        switch self.status {
            
        case .locked:
                
            throw ObvUICoreDataError.aContactCannotWipeMessageFromLockedDiscussion

        case .preDiscussion:
            
            throw ObvUICoreDataError.aContactCannotWipeMessageFromPrediscussion

        case .active:
            
            let infosForSent = try self.processWipeMessageRequestForPersistedMessageSent(
                among: messagesToDelete,
                from: requester,
                messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            let infosForReceived = try self.processWipeMessageRequestForPersistedMessageReceived(
                among: messagesToDelete,
                from: requester,
                messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            
            let infos = infosForSent + infosForReceived
            
            return infos

        }

    }
    
    
    private func processWipeMessageRequestForPersistedMessageSent(among messagesToDelete: [MessageReferenceJSON], from requesterCryptoId: ObvCryptoId, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        guard let ownedIdentity else { throw ObvUICoreDataError.ownedIdentityIsNil }
        
        // Don't accept a wipe request from a contact for a sent message, unless the discussion is a group discussion with the appropriate permissions
        
        if requesterCryptoId != ownedIdentity.cryptoId {
            switch try self.kind {
            case .oneToOne, .groupV1:
                return []
            case .groupV2(withGroup: let group):
                guard let group, let requester = group.otherMembers.first(where: { $0.identity == requesterCryptoId.getIdentity() }) else {
                    assertionFailure()
                    return []
                }
                guard requester.isAllowedToRemoteDeleteAnything else {
                    return []
                }
                // If we reach this point, the contact is allowed to wipe a sent message in this discussion
            }
        }
        
        // Get the sent messages to wipe
        
        var sentMessagesToWipe = [PersistedMessageSent]()
        do {
            let sentMessages = messagesToDelete
                .filter({ $0.senderIdentifier == ownedIdentity.cryptoId.getIdentity() }) // Restrict to sent messages
            for sentMessage in sentMessages {
                if let persistedMessageSent = try PersistedMessageSent.get(senderSequenceNumber: sentMessage.senderSequenceNumber,
                                                                           senderThreadIdentifier: sentMessage.senderThreadIdentifier,
                                                                           ownedIdentity: sentMessage.senderIdentifier,
                                                                           discussion: self),
                   !persistedMessageSent.isWiped {
                    sentMessagesToWipe.append(persistedMessageSent)
                } else {
                    _ = try RemoteRequestSavedForLater.createWipeOrDeleteRequest(
                        requesterCryptoId: requesterCryptoId,
                        messageReference: sentMessage,
                        serverTimestamp: messageUploadTimestampFromServer,
                        discussion: self)
                }
            }
        }

        // Wipe each message and notify on context change

        var infos = [InfoAboutWipedOrDeletedPersistedMessage]()

        for message in sentMessagesToWipe {
            
            let info: InfoAboutWipedOrDeletedPersistedMessage
            
            do {
                info = try message.wipeThisMessage(requesterCryptoId: requesterCryptoId)
            } catch {
                assertionFailure(error.localizedDescription) // In production, continue with next message
                continue
            }

            infos.append(info)

        }

        return infos
        
    }
    
    
    private func processWipeMessageRequestForPersistedMessageReceived(among messagesToDelete: [MessageReferenceJSON], from requesterCryptoId: ObvCryptoId, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        guard let ownedIdentity else {
            throw ObvUICoreDataError.ownedIdentityIsNil
        }
        
        // Don't accept a wipe request of a received message unless the requester is the sender of the message or the owned identity. Only exception: group v2 discussions where the requested has the appropriate permission.
        
        let requesterIsAllowedToRemoteDeleteAnythingOnThisDevice: Bool
        if requesterCryptoId == ownedIdentity.cryptoId {
            requesterIsAllowedToRemoteDeleteAnythingOnThisDevice = true
        } else {
            switch try self.kind {
            case .oneToOne, .groupV1:
                requesterIsAllowedToRemoteDeleteAnythingOnThisDevice = false
            case .groupV2(withGroup: let group):
                guard let group, let requester = group.otherMembers.first(where: { $0.identity == requesterCryptoId.getIdentity() }) else {
                    assertionFailure()
                    return []
                }
                requesterIsAllowedToRemoteDeleteAnythingOnThisDevice = requester.isAllowedToRemoteDeleteAnything
            }
        }
        
        // Get received messages to wipe. If a message cannot be found, save the request for later if `saveRequestIfMessageCannotBeFound` is true

        var receivedMessagesToWipe = [PersistedMessageReceived]()
        do {
            let receivedMessages = messagesToDelete
                .filter({ $0.senderIdentifier != ownedIdentity.cryptoId.getIdentity() }) // Restrict to received messages
                .filter({ $0.senderIdentifier == requesterCryptoId.getIdentity() || requesterIsAllowedToRemoteDeleteAnythingOnThisDevice }) // Requester is allowed to delete her messages. She may be allowed to delete anything.
            for receivedMessage in receivedMessages {
                if let persistedMessageReceived = try PersistedMessageReceived.get(senderSequenceNumber: receivedMessage.senderSequenceNumber,
                                                                                   senderThreadIdentifier: receivedMessage.senderThreadIdentifier,
                                                                                   contactIdentity: receivedMessage.senderIdentifier,
                                                                                   discussion: self),
                   !persistedMessageReceived.isWiped {
                    receivedMessagesToWipe.append(persistedMessageReceived)
                } else {
                    _ = try RemoteRequestSavedForLater.createWipeOrDeleteRequest(
                        requesterCryptoId: requesterCryptoId,
                        messageReference: receivedMessage,
                        serverTimestamp: messageUploadTimestampFromServer,
                        discussion: self)
                }
            }
        }

        var infos = [InfoAboutWipedOrDeletedPersistedMessage]()

        for message in receivedMessagesToWipe {
            
            let info: InfoAboutWipedOrDeletedPersistedMessage
            
            do {
                info = try message.wipeThisMessage(requesterCryptoId: requesterCryptoId)
            } catch {
                assertionFailure(error.localizedDescription) // In production, continue with next message
                continue
            }
            
            infos.append(info)

        }

        return infos
        
    }
    
    
    // MARK: - Processing discussion (all messages) remote delete requests from other owned devices (contacts are only allowed to delete group V2 discussions, in certain cases)

    /// Called when receiving a wipe discussion request from another owned device.
    func processRemoteRequestToWipeAllMessagesWithinThisDiscussion(from ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws {
        
        // The owned identity can only globally delete a discussion when it is active.
        switch status {
            
        case .preDiscussion:
            
            throw ObvUICoreDataError.ownedIdentityCannotGloballyDeletePrediscussion
            
        case .active:
            
            self.removeAllMessages(messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            try self.archive()
            
        case .locked:
            
            self.removeAllMessages(messageUploadTimestampFromServer: messageUploadTimestampFromServer)
            try self.deletePersistedDiscussion()

        }
        
    }

    
    // MARK: - Processing delete requests from the owned identity

    func processMessageDeletionRequestRequestedFromCurrentDevice(of ownedIdentity: PersistedObvOwnedIdentity, messageToDelete: PersistedMessage, deletionType: DeletionType) throws -> InfoAboutWipedOrDeletedPersistedMessage {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        guard messageToDelete.discussion == self else {
            throw ObvUICoreDataError.unexpectedDiscussionForMessage
        }

        switch deletionType {
        case .fromThisDeviceOnly:
            // Always allow a message deletion on this device when the request was made on this device
            break
        case .fromAllOwnedDevices:
            // Throw if we have no other owned devices. This is handy when using the method to determine if the option
            // to delete from all other owned devices is pertinent
            guard ownedIdentity.hasAnotherDeviceWhichIsReachable else {
                throw ObvUICoreDataError.ownedIdentityDoesNotHaveAnotherReachableDevice
            }
        case .fromAllOwnedDevicesAndAllContactDevices:
            switch self.status {
            case .locked, .preDiscussion:
                throw ObvUICoreDataError.cannotGloballyDeleteMessageFromLockedOrPrediscussion
            case .active:
                break
            }
        }
        
        let info = try messageToDelete.processMessageDeletionRequestRequestedFromCurrentDevice(deletionType: deletionType)
        
        return info
        
    }
    
    
    func processDiscussionDeletionRequestFromCurrentDevice(of ownedIdentity: PersistedObvOwnedIdentity, deletionType: DeletionType) throws {
                
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        // We can only globally delete a discussion from an active discussion

        switch deletionType {
        case .fromThisDeviceOnly:
            break
        case .fromAllOwnedDevices:
            break
        case .fromAllOwnedDevicesAndAllContactDevices:
            switch self.status {
            case .locked, .preDiscussion:
                throw ObvUICoreDataError.cannotGloballyDeleteLockedOrPrediscussion
            case .active:
                break
            }
        }

        self.removeAllMessages(messageUploadTimestampFromServer: nil)

        do {
            try self.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: true, messageTimestamp: Date())
        } catch {
            assertionFailure(error.localizedDescription)
        }

        switch self.status {
        case .active, .preDiscussion:
            try self.archive()
        case .locked:
            try self.deletePersistedDiscussion()
        }
        
    }

    
    // MARK: - Receiving messages and attachments from a contact or another owned device

    func createOrOverridePersistedMessageReceived(from contact: PersistedObvContactIdentity, obvMessage: ObvMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, source: ObvMessageSource, receivedLocation: ReceivedLocation?) throws -> (discussionPermanentID: DiscussionPermanentID, messagePermanentId: MessageReceivedPermanentID?) {
        
        // If the message has a limited existence, make sure it is not already obsolete
        
        if let existenceDuration = messageJSON.expiration?.existenceDuration {
            switch source {
            case .engine:
                guard obvMessage.downloadTimestampFromServer.timeIntervalSince(obvMessage.messageUploadTimestampFromServer) < existenceDuration else {
                    throw ObvUICoreDataError.cannotCreateReceivedMessageThatAlreadyExpired
                }
            case .userNotification:
                guard Date.now.timeIntervalSince(obvMessage.messageUploadTimestampFromServer) < existenceDuration else {
                    throw ObvUICoreDataError.cannotCreateReceivedMessageThatAlreadyExpired
                }
            }
        }

        // We ensures that the received message is posterior to the last remote deletion request
        
        if let serverTimestampOfLastRemoteDeletion {
            guard obvMessage.messageUploadTimestampFromServer > serverTimestampOfLastRemoteDeletion else {
                Self.logger.error("We just a received message that is prior to the last remote deletion request. Discarding the message.")
                throw ObvUICoreDataError.messageIsPriorToLastRemoteDeletionRequest
            }
        }

        // Try to insert a EndToEndEncryptedSystemMessage if the discussion is empty.

        try? self.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: true, messageTimestamp: Date())

        // If overridePreviousPersistedMessage is true, we update any previously stored message from DB. If no such message exists, we create it.
        // If overridePreviousPersistedMessage is false, we make sure that no existing PersistedMessageReceived exists in DB. If this is the case, we create the message.
        // Note that processing attachments requires overridePreviousPersistedMessage to be true

        let createdOrUpdatedMessage: PersistedMessageReceived
        
        switch source {
            
        case .engine:
            
            Self.logger.debug("Creating or updating a persisted message (source: \(source.debugDescription))")

            createdOrUpdatedMessage = try PersistedMessageReceived.createOrUpdatePersistedMessageReceived(
                obvMessage: obvMessage,
                messageJSON: messageJSON,
                source: source,
                returnReceiptJSON: returnReceiptJSON,
                receivedLocation: receivedLocation,
                from: contact,
                in: self)

        case .userNotification:
            
            // Make sure the message does not already exists in DB. If it does, we simply return it.
            // If a location was passed and has no associated message, delete it

            if let messageReceived = try PersistedMessageReceived.get(messageIdentifierFromEngine: obvMessage.messageIdentifierFromEngine, from: contact) {
                
                if let receivedLocation {
                    switch receivedLocation {
                    case .oneShot(let location):
                        try location.deleteIfAssociatedReceivedMessageIsNil()
                    case .continuous(let location, _):
                        try location.deleteIfReceivedMessagesIsEmpty()
                    }
                }
                
                return (self.discussionPermanentID, try? messageReceived.objectPermanentID)
            }
            
            // We make sure that message has a body (for now, this message comes from the notification extension, and there is no point in creating a `PersistedMessageReceived` if there is no body.

            guard messageJSON.body?.isEmpty == false else {
                throw ObvUICoreDataError.messageHasNoBody
            }

            // Create the PersistedMessageReceived

            Self.logger.debug("Creating or updating a persisted message (source: \(source.debugDescription))")

            createdOrUpdatedMessage = try PersistedMessageReceived.createPersistedMessageReceived(
                obvMessage: obvMessage,
                messageJSON: messageJSON,
                source: source,
                returnReceiptJSON: returnReceiptJSON,
                receivedLocation: receivedLocation,
                from: contact,
                in: self)

        }

        do {
            try RemoteRequestSavedForLater.applyRemoteRequestsSavedForLater(for: createdOrUpdatedMessage)
        } catch {
            assertionFailure(error.localizedDescription) // Continue anyway
        }
        
        // If the server timestamp of the message is less than the discussion's serverTimestampWhenDiscussionReadOnAnotherOwnedDevice, immediately mark
        // this message as read.
        // This situation happens because we might receive a message from another owned device indicating that all this discussion messages have been read until a certain date
        // **before** receiving the messages themselves.
        
        if obvMessage.messageUploadTimestampFromServer <= self.serverTimestampWhenDiscussionReadOnAnotherOwnedDevice {
            do {
                _ = try createdOrUpdatedMessage.markAsNotNew(dateWhenMessageTurnedNotNew: self.serverTimestampWhenDiscussionReadOnAnotherOwnedDevice, requestedOnAnotherOwnedDevice: true)
            } catch {
                assertionFailure(error.localizedDescription) // In production, continue anyway
            }
        }

        let messageReceivedPermanentId = try? createdOrUpdatedMessage.objectPermanentID // Can be nil if the message was deleted, e.g., because of a remote delete request saved for later
        
        return (self.discussionPermanentID, messageReceivedPermanentId)

    }
    
    
    func createPersistedMessageSentFromOtherOwnedDevice(from ownedIdentity: PersistedObvOwnedIdentity, obvOwnedMessage: ObvOwnedMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, sentLocation: SentLocation?) throws -> MessageSentPermanentID? {
        
        // Make sure the received message is not a read once message. If this is the case, we don't want to show the message on this (other) owned device
        
        if let expiration = messageJSON.expiration {
            guard !expiration.readOnce else {
                return nil
            }
        }

        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        
        // Try to insert a EndToEndEncryptedSystemMessage if the discussion is empty
        
        try? PersistedDiscussion.insertSystemMessagesIfDiscussionIsEmpty(discussionObjectID: self.objectID, markAsRead: true, within: context)

        // Make sure the message does not already exists in DB
        
        if let messageSent = try PersistedMessageSent.getPersistedMessageSentFromOtherOwnedDevice(messageIdentifierFromEngine: obvOwnedMessage.messageIdentifierFromEngine, in: self) {
            messageSent.processObvOwnedAttachmentsFromOtherOwnedDevice(of: obvOwnedMessage)
            return try messageSent.objectPermanentID
        }
        
        // Create the PersistedMessageSent

        let createdMessage = try PersistedMessageSent.createPersistedMessageSentFromOtherOwnedDevice(
            obvOwnedMessage: obvOwnedMessage,
            messageJSON: messageJSON,
            returnReceiptJSON: returnReceiptJSON,
            sentLocation: sentLocation,
            in: self)

        do {
            try RemoteRequestSavedForLater.applyRemoteRequestsSavedForLater(for: createdMessage)
        } catch {
            assertionFailure(error.localizedDescription) // Continue anyway
        }

        let messageSentPermanentId = try? createdMessage.objectPermanentID // nil if the created message was just deleted by applying a saved delete request
        
        return messageSentPermanentId

    }
    
    
    // MARK: - Processing edit requests

    func processUpdateMessageRequest(_ updateMessageJSON: UpdateMessageJSON, receivedFromContactCryptoId contactCryptoId: ObvCryptoId, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        switch self.status {
            
        case .locked:
                
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInLockedDiscussion

        case .preDiscussion:
            
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInPrediscussion

        case .active:

            // Since the request comes from a contact, we restrict the message search to received messages.
            // If the message cannot be found, save the request for later.

            let messageToEdit = updateMessageJSON.messageToEdit
            
            if let message = try PersistedMessageReceived.get(senderSequenceNumber: messageToEdit.senderSequenceNumber,
                                                              senderThreadIdentifier: messageToEdit.senderThreadIdentifier,
                                                              contactIdentity: messageToEdit.senderIdentifier,
                                                              discussion: self) {
                
                guard message.contactIdentity?.cryptoId == contactCryptoId else {
                    throw ObvUICoreDataError.aContactRequestedUpdateOnMessageFromSomeoneElse
                }
                
                try message.processUpdateReceivedMessageRequest(
                    newTextBody: updateMessageJSON.newTextBody,
                    newUserMentions: updateMessageJSON.userMentions,
                    newLocation: updateMessageJSON.locationJSON,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                    requester: contactCryptoId)
                
                return message
                
            } else {
                
                _ = try RemoteRequestSavedForLater.createEditRequest(
                    requesterCryptoId: contactCryptoId,
                    updateMessageJSON: updateMessageJSON,
                    serverTimestamp: messageUploadTimestampFromServer,
                    discussion: self)
                
                return nil
                
            }
            
        }

    }

    
    func processUpdateMessageRequest(_ updateMessageJSON: UpdateMessageJSON, receivedFromOwnedCryptoId ownedCryptoId: ObvCryptoId, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        guard self.ownedIdentity?.cryptoId == ownedCryptoId else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        switch self.status {
            
        case .locked:
                
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInLockedDiscussion

        case .preDiscussion:
            
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInPrediscussion

        case .active:

            // Since the request comes from an owned identity, we restrict the message search to sent messages.
            // If the message cannot be found, save the request for later.

            let messageToEdit = updateMessageJSON.messageToEdit
            
            if let message = try PersistedMessageSent.get(senderSequenceNumber: messageToEdit.senderSequenceNumber,
                                                          senderThreadIdentifier: messageToEdit.senderThreadIdentifier,
                                                          ownedIdentity: messageToEdit.senderIdentifier,
                                                          discussion: self) {
                
                guard message.discussion?.ownedIdentity?.cryptoId == ownedCryptoId else {
                    throw ObvUICoreDataError.unexpectedOwnedIdentity
                }
                
                try message.processUpdateSentMessageRequest(
                    newTextBody: updateMessageJSON.newTextBody,
                    newUserMentions: updateMessageJSON.userMentions,
                    newLocation: updateMessageJSON.locationJSON,
                    messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                    requester: ownedCryptoId)
                
                return message

            } else {
                
                _ = try RemoteRequestSavedForLater.createEditRequest(
                    requesterCryptoId: ownedCryptoId,
                    updateMessageJSON: updateMessageJSON,
                    serverTimestamp: messageUploadTimestampFromServer,
                    discussion: self)
                
                return nil
                
            }
            
        }

    }
    
    func processLocalUpdateMessageRequest(from ownedIdentity: PersistedObvOwnedIdentity, for messageSent: PersistedMessageSent, newTextBody: String?) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        guard messageSent.discussion == self else {
            throw ObvUICoreDataError.unexpectedDiscussionForMessage
        }
        
        switch self.status {
            
        case .locked:
                
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInLockedDiscussion

        case .preDiscussion:
            
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInPrediscussion

        case .active:

            try messageSent.replaceContentWith(newBody: newTextBody, newMentions: Set<MessageJSON.UserMention>())

        }

    }
    
    
    // MARK: - Process reaction requests

    func processSetOrUpdateReactionOnMessageLocalRequest(from ownedIdentity: PersistedObvOwnedIdentity, for message: PersistedMessage, newEmoji: String?) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        guard message.discussion == self else {
            throw ObvUICoreDataError.unexpectedDiscussionForMessage
        }

        switch self.status {
            
        case .locked:
                
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInLockedDiscussion

        case .preDiscussion:
            
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInPrediscussion

        case .active:

            try message.setReactionFromOwnedIdentity(withEmoji: newEmoji, messageUploadTimestampFromServer: nil)

        }

    }

    
    func processSetOrUpdateReactionOnMessageRequest(_ reactionJSON: ReactionJSON, receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date, overrideExistingReaction: Bool) throws -> PersistedMessage? {
        
        switch self.status {
            
        case .locked:
                
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInLockedDiscussion

        case .preDiscussion:
            
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInPrediscussion

        case .active:

            let messageToEdit = reactionJSON.messageReference

            if let message = try PersistedMessageReceived.get(senderSequenceNumber: messageToEdit.senderSequenceNumber,
                                                              senderThreadIdentifier: messageToEdit.senderThreadIdentifier,
                                                              contactIdentity: messageToEdit.senderIdentifier,
                                                              discussion: self) {
                
                try message.setReactionFromContact(contact, withEmoji: reactionJSON.emoji, reactionTimestamp: messageUploadTimestampFromServer, overrideExistingReaction: overrideExistingReaction)
                
                return message
                
            } else if let message = try PersistedMessageSent.get(senderSequenceNumber: messageToEdit.senderSequenceNumber,
                                                                 senderThreadIdentifier: messageToEdit.senderThreadIdentifier,
                                                                 ownedIdentity: messageToEdit.senderIdentifier,
                                                                 discussion: self) {
                
                try message.setReactionFromContact(contact, withEmoji: reactionJSON.emoji, reactionTimestamp: messageUploadTimestampFromServer, overrideExistingReaction: overrideExistingReaction)
                
                return message

            } else {
                
                _ = try RemoteRequestSavedForLater.createSetOrUpdateReactionRequest(
                    requesterCryptoId: contact.cryptoId,
                    reactionJSON: reactionJSON,
                    serverTimestamp: messageUploadTimestampFromServer,
                    discussion: self)
                
                return nil
                
            }
                        
        }

    }
    
    
    func processSetOrUpdateReactionOnMessageRequest(_ reactionJSON: ReactionJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        switch self.status {
            
        case .locked:
                
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInLockedDiscussion

        case .preDiscussion:
            
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInPrediscussion

        case .active:

            let messageToEdit = reactionJSON.messageReference

            if let message = try PersistedMessageReceived.get(senderSequenceNumber: messageToEdit.senderSequenceNumber,
                                                              senderThreadIdentifier: messageToEdit.senderThreadIdentifier,
                                                              contactIdentity: messageToEdit.senderIdentifier,
                                                              discussion: self) {
                
                try message.setReactionFromOwnedIdentity(withEmoji: reactionJSON.emoji, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
                
                return message
                
            } else if let message = try PersistedMessageSent.get(senderSequenceNumber: messageToEdit.senderSequenceNumber,
                                                                 senderThreadIdentifier: messageToEdit.senderThreadIdentifier,
                                                                 ownedIdentity: messageToEdit.senderIdentifier,
                                                                 discussion: self) {
                
                try message.setReactionFromOwnedIdentity(withEmoji: reactionJSON.emoji, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

                return message

            } else {
                
                _ = try RemoteRequestSavedForLater.createSetOrUpdateReactionRequest(
                    requesterCryptoId: ownedIdentity.cryptoId,
                    reactionJSON: reactionJSON,
                    serverTimestamp: messageUploadTimestampFromServer,
                    discussion: self)
                
                return nil
                
            }
                        
        }

    }
    
    
    // MARK: - Process screen capture detections

    func processDetectionThatSensitiveMessagesWereCaptured(_ screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, from contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws {

        switch self.status {
            
        case .locked:
                
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInLockedDiscussion

        case .preDiscussion:
            
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInPrediscussion

        case .active:

            _ = try PersistedMessageSystem.insertContactIdentityDidCaptureSensitiveMessages(within: self, contact: contact, timestamp: messageUploadTimestampFromServer)

        }

    }
    
    
    func processDetectionThatSensitiveMessagesWereCaptured(_ screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, from ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws {
        
        switch self.status {
            
        case .locked:
                
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInLockedDiscussion

        case .preDiscussion:
            
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInPrediscussion

        case .active:

            _ = try PersistedMessageSystem.insertOwnedIdentityDidCaptureSensitiveMessages(within: self, ownedCryptoId: ownedIdentity.cryptoId, timestamp: messageUploadTimestampFromServer)

        }

    }
    
    func processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by ownedIdentity: PersistedObvOwnedIdentity) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        switch self.status {
            
        case .locked:
                
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInLockedDiscussion

        case .preDiscussion:
            
            throw ObvUICoreDataError.aMessageCannotBeUpdatedInPrediscussion

        case .active:

            _ = try PersistedMessageSystem.insertOwnedIdentityDidCaptureSensitiveMessages(within: self)

        }

    }
    
}


// MARK: - Process requests for this discussion shared settings

extension PersistedDiscussion {
    
    func processQuerySharedSettingsRequest(querySharedSettingsJSON: QuerySharedSettingsJSON) throws -> Bool {
        
        let sharedSettingsVersionKnownByContact = querySharedSettingsJSON.knownSharedSettingsVersion ?? Int.min
        let sharedExpirationKnownByContact = querySharedSettingsJSON.knownSharedExpiration

        // Get the values known locally
        
        let sharedSettingsVersionKnownLocally = sharedConfiguration.version
        let sharedExpirationKnownLocally: ExpirationJSON?
        if sharedSettingsVersionKnownLocally >= 0 {
            sharedExpirationKnownLocally = sharedConfiguration.toExpirationJSON()
        } else {
            sharedExpirationKnownLocally = nil
        }

        // If the locally known values are identical to the values known to the contact, we are done, we do not need to answer the query
        
        guard sharedSettingsVersionKnownByContact <= sharedSettingsVersionKnownLocally || sharedExpirationKnownByContact != sharedExpirationKnownLocally else {
            return false
        }

        // If we reach this point, something differed between the shared settings of our contact and ours

        var weShouldSentBackTheSharedSettings = false
        if sharedSettingsVersionKnownLocally > sharedSettingsVersionKnownByContact {
            weShouldSentBackTheSharedSettings = true
        } else if sharedSettingsVersionKnownLocally == sharedSettingsVersionKnownByContact && sharedExpirationKnownByContact != sharedExpirationKnownLocally {
            weShouldSentBackTheSharedSettings = true
        }

        return weShouldSentBackTheSharedSettings
        
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
    
    /// When deleting an illustrative message, we need to find another appropriate illustrative message.
    func resetIllustrativeMessage() throws {
        guard self.managedObjectContext != nil else { assertionFailure(); throw ObvUICoreDataError.noContext }
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
    /// This method is called each time a message is inserted, each time a message's status changes, or when the discussion mute setting changes.
    /// It is **not** called during bootstrap for efficiency reasons, see ``static PersistedDiscussion.refreshNumberOfNewMessagesOfAllDiscussions(ownedIdentity:)``.
    public func refreshNumberOfNewMessages() throws {
        guard self.managedObjectContext != nil else { assertionFailure(); throw ObvUICoreDataError.noContext }
        
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

        setNumberOfNewMessages(to: newNumberOfNewMessages)
        
        ownedIdentity?.incrementBadgeCountForDiscussionsTab(by: incrementForOwnedIdentity)
    }
    
    
    private func setNumberOfNewMessages(to newValue: Int) {
        guard newValue >= 0 else { assertionFailure(); return }
        if self.numberOfNewMessages != newValue {
            self.numberOfNewMessages = newValue
        }
    }
    
    
    /// Refreshes the counter of new messages within all discussions of the given owned identity.
    ///
    /// Called during bootstrap.
    public static func refreshNumberOfNewMessagesOfAllDiscussions(ownedIdentity: PersistedObvOwnedIdentity) throws {
        
        let allDiscussions = try Self.getAllDiscussionsOfOwnedIdentity(ownedIdentity)

        let objectIDsOfDiscussionsWithValidMuteNotificationsEndDate = try getObjectIDsOfDiscussionsWithValidMuteNotificationsEndDate(ownedIdentity: ownedIdentity)

        let numberOfNewReceivedMessagesForDiscussionWithObjectID = try PersistedMessageReceived.getAllDiscussionsWithNewPersistedMessageReceived(ownedIdentity: ownedIdentity)
        let numberOfNewSystemMessagesForDiscussionWithObjectID = try PersistedMessageSystem.getAllDiscussionsWithNewAndRelevantPersistedMessageSystem(ownedIdentity: ownedIdentity)

        var newBadgeCountForDiscussionTabOfOwnedIdentity = 0
        
        for discussion in allDiscussions {
            
            if objectIDsOfDiscussionsWithValidMuteNotificationsEndDate.contains(discussion.typedObjectID) {

                // The discussion is muted, the number of new messages to show in the list of recent discussions is 0
                discussion.setNumberOfNewMessages(to: 0)

            } else {

                let numberOfNewReceivedMessages = numberOfNewReceivedMessagesForDiscussionWithObjectID[discussion.typedObjectID] ?? 0
                let numberOfNewSystemMessages = numberOfNewSystemMessagesForDiscussionWithObjectID[discussion.typedObjectID] ?? 0
                let newNumberOfNewMessages = numberOfNewReceivedMessages + numberOfNewSystemMessages
                
                if newNumberOfNewMessages > 0 {
                    discussion.setNumberOfNewMessages(to: newNumberOfNewMessages)
                    newBadgeCountForDiscussionTabOfOwnedIdentity += newNumberOfNewMessages
                } else {
                    discussion.setNumberOfNewMessages(to: 0)
                }

            }
                        
        }
        
        ownedIdentity.setBadgeCountForDiscussionsTab(to: newBadgeCountForDiscussionTabOfOwnedIdentity)
        
    }
    
    
    private static func getObjectIDsOfDiscussionsWithValidMuteNotificationsEndDate(ownedIdentity: PersistedObvOwnedIdentity) throws -> Set<TypeSafeManagedObjectID<PersistedDiscussion>> {
        
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Self.entityName)
        request.resultType = .managedObjectIDResultType
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedIdentity(ownedIdentity),
            Predicate.withValidMuteNotificationsEndDate,
        ])
        let result = try context.fetch(request) as? [NSManagedObjectID] ?? []
        return Set(result.map { TypeSafeManagedObjectID<PersistedDiscussion>(objectID: $0) })

    }
        
}


// MARK: - Manage pinned discussions

extension PersistedDiscussion {
    
    public var isPinned: Bool {
        pinnedIndex != nil
    }
    
    
    /// Returns `true` iff at least one discussion's pinnedIndex was updated in database
    public static func setPinnedDiscussions(persistedDiscussionObjectIDs: [NSManagedObjectID], ordered: Bool, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Bool {

        let pinnedDiscussionBeforeUpdate = try PersistedDiscussion.getAllPinnedDiscussions(ownedCryptoId: ownedCryptoId, with: context).map({ $0.objectID })
        
        let orderedObjectIDsOfPinnedDiscussions: [NSManagedObjectID]

        if ordered {
            
            orderedObjectIDsOfPinnedDiscussions = persistedDiscussionObjectIDs
            
        } else {
            
            // This happens when receiving a list of pinned discussions from an Android device, where the pinned discussion behaviour is different (they are not sorted)
            
            let objectIDsOfCurrentlyPinnedDiscussions = try Self.getObjectIDsOfAllPinnedDiscussions(ownedCryptoId: ownedCryptoId, with: context)
            let setOfReceivedPinnedDiscussions = Set(persistedDiscussionObjectIDs)
            let objectIDsToKeepPinned = objectIDsOfCurrentlyPinnedDiscussions.filter({ setOfReceivedPinnedDiscussions.contains($0) })
            let setOfObjectIDsToKeepPinned = Set(objectIDsToKeepPinned)
            let objectIDsToAdd = persistedDiscussionObjectIDs.filter({ !setOfObjectIDsToKeepPinned.contains($0) })
            orderedObjectIDsOfPinnedDiscussions = objectIDsToKeepPinned + objectIDsToAdd

        }
        
        try removePinnedFromPinnedDiscussionsForOwnedIdentity(ownedCryptoId, within: context)
        
        let retrievedDiscussions = try orderedObjectIDsOfPinnedDiscussions
            .compactMap({ try PersistedDiscussion.get(objectID: $0, within: context) })
            .filter({ $0.ownedIdentity?.cryptoId == ownedCryptoId })
        
        assert(retrievedDiscussions.count == orderedObjectIDsOfPinnedDiscussions.count)
        
        for (index, discussion) in retrievedDiscussions.enumerated() {
            if discussion.pinnedIndex != index {
                discussion.pinnedIndex = index
            }
        }

        let pinnedDiscussionAfterUpdate = try PersistedDiscussion.getAllPinnedDiscussions(ownedCryptoId: ownedCryptoId, with: context).map({ $0.objectID })

        let atLeastOnePinnedIndexWasChanged = pinnedDiscussionBeforeUpdate != pinnedDiscussionAfterUpdate
        
        return atLeastOnePinnedIndexWasChanged
        
    }
    
}


// MARK: - Other methods

extension PersistedDiscussion {

    func resetTitle(to newTitle: String) throws {
        guard !newTitle.isEmpty else { throw ObvUICoreDataError.newTitleIsEmpty }
        if self.title != newTitle {
            self.title = newTitle
        }
    }

    public func insertSystemMessagesIfDiscussionIsEmpty(markAsRead: Bool, messageTimestamp: Date) throws {
        guard self.messages.isEmpty else { return }
        let systemMessage = try PersistedMessageSystem(.discussionIsEndToEndEncrypted, optionalContactIdentity: nil, optionalOwnedCryptoId: nil, optionalCallLogItem: nil, discussion: self, timestamp: messageTimestamp)
        if markAsRead {
            systemMessage.markAsRead()
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
        guard context.concurrencyType != .mainQueueConcurrencyType else { assertionFailure(); throw ObvUICoreDataError.inappropriateContext }
        guard let discussion = try PersistedDiscussion.get(objectID: discussionObjectID, within: context) else { throw ObvUICoreDataError.couldNotFindDiscussion }
        try discussion.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: markAsRead, messageTimestamp: Date())
    }
    
    
    public func getAllActiveParticipants() throws -> (ownCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>) {

        let contactCryptoIds: Set<ObvCryptoId>
        let ownCryptoId: ObvCryptoId

        switch try kind {

        case .oneToOne(withContactIdentity: let contactIdentity):
            
            guard let contactIdentity else {
                throw ObvUICoreDataError.contactIdentityIsNil
            }
            guard let oneToOneDiscussion = self as? PersistedOneToOneDiscussion else {
                assertionFailure()
                throw ObvUICoreDataError.unexpectedDiscussionKind
            }
            contactCryptoIds = contactIdentity.isActive ? Set([contactIdentity.cryptoId]) : Set([])
            guard let _ownCryptoId = oneToOneDiscussion.ownedIdentity?.cryptoId else {
                throw ObvUICoreDataError.ownedIdentityIsNil
            }
            ownCryptoId = _ownCryptoId
            
        case .groupV1(withContactGroup: let group):
            
            guard let contactGroup = group else {
                throw ObvUICoreDataError.groupV1IsNil
            }
            guard let _ownCryptoId = ownedIdentity?.cryptoId else {
                throw ObvUICoreDataError.ownedIdentityIsNil
            }
            ownCryptoId = _ownCryptoId
            switch contactGroup.category {
            case .owned:
                contactCryptoIds = Set(contactGroup.contactIdentities.filter({ $0.isActive }).map({ $0.cryptoId }))
            case .joined:
                guard let groupOwner = try? ObvCryptoId(identity: contactGroup.ownerIdentity) else {
                    throw ObvUICoreDataError.couldNotDetermineGroupOwner
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
            
            guard let group else {
                throw ObvUICoreDataError.groupV2IsNil
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
    
    
    func getPersistedMessageReceivedCorrespondingTo(messageReference: MessageReferenceJSON) throws -> PersistedMessageReceived? {
        return try PersistedMessageReceived.get(
            senderSequenceNumber: messageReference.senderSequenceNumber,
            senderThreadIdentifier: messageReference.senderThreadIdentifier,
            contactIdentity: messageReference.senderIdentifier,
            discussion: self)
    }
    
    
    public static func getIdentifiers(for discussionPermanentID: DiscussionPermanentID, within context: NSManagedObjectContext) throws -> (ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier) {

        guard let discussion = try PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: context) else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        
        guard let ownedCryptoId = discussion.ownedIdentity?.cryptoId else {
            throw ObvUICoreDataError.ownedIdentityIsNil
        }
        
        let discussionId = try discussion.identifier
        
        return (ownedCryptoId, discussionId)
        
    }

}


// MARK: - Retention related methods

extension PersistedDiscussion {

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
        resetTimestampOfLastMessageIfCurrentValueIsEarlierThan(Date())
    }
    
    public func archive() throws {

        guard !isArchived else { return }
        isArchived = true

        _ = try markAllMessagesAsNotNew(serverTimestampWhenDiscussionReadOnAnotherOwnedDevice: nil, dateWhenMessageTurnedNotNew: .now)
        
        self.pinnedIndex = nil

    }
    
}


// MARK: - Allow reading messages with limited visibility

extension PersistedDiscussion {
    
    func userWantsToReadReceivedMessageWithLimitedVisibility(messageId: ReceivedMessageIdentifier, dateWhenMessageWasRead: Date, requestedOnAnotherOwnedDevice: Bool) throws -> InfoAboutWipedOrDeletedPersistedMessage? {
        
        guard let receivedMessage = try PersistedMessageReceived.getPersistedMessageReceived(discussion: self, messageId: messageId) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageReceived
        }
        
        let infos = try receivedMessage.userWantsToReadThisReceivedMessageWithLimitedVisibility(dateWhenMessageWasRead: dateWhenMessageWasRead, requestedOnAnotherOwnedDevice: requestedOnAnotherOwnedDevice)
        
        return infos
        
    }
    
    
    /// Returns an array of the received message identifiers that were read
    func userWantsToAllowReadingAllReceivedMessagesReceivedThatRequireUserAction(dateWhenMessageWasRead: Date) throws -> ([InfoAboutWipedOrDeletedPersistedMessage], [ReceivedMessageIdentifier]) {
        
        // Since this method is expected to be called for implementing the discussion auto-read feature, we check whether autoRead is `true`
        
        guard self.autoRead else { return ([], []) }
        
        let receivedMessagesThatRequireUserActionForReading = try PersistedMessageReceived.getAllReceivedMessagesThatRequireUserActionForReading(discussion: self)

        var identifiersOfReadReceivedMessages = [ReceivedMessageIdentifier]()
        var allInfos = [InfoAboutWipedOrDeletedPersistedMessage]()
        
        for receivedMessage in receivedMessagesThatRequireUserActionForReading {
            
            // Check that the message ephemerality is at least that of the discussion, otherwise, do not auto read
            
            guard receivedMessage.ephemeralityIsAtLeastAsPermissiveThanDiscussionSharedConfiguration else {
                continue
            }

            let infos = try receivedMessage.userWantsToReadThisReceivedMessageWithLimitedVisibility(dateWhenMessageWasRead: dateWhenMessageWasRead, requestedOnAnotherOwnedDevice: false)
            
            if let infos {
                allInfos.append(infos)
            }
            identifiersOfReadReceivedMessages.append(receivedMessage.receivedMessageIdentifier)
            
        }

        return (allInfos, identifiersOfReadReceivedMessages)
        
    }

    
    
    func getLimitedVisibilityMessageOpenedJSON(messageId: ReceivedMessageIdentifier) throws -> LimitedVisibilityMessageOpenedJSON {
        
        guard let receivedMessage = try PersistedMessageReceived.getPersistedMessageReceived(discussion: self, messageId: messageId) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageReceived
        }
        
        guard let ownedCryptoId = ownedIdentity?.cryptoId else {
            throw ObvUICoreDataError.ownedIdentityIsNil
        }

        let messageReference = receivedMessage.toReceivedMessageReferenceJSON()
        
        switch try kind {
        case .oneToOne(withContactIdentity: let contactIdentity):
            guard let contactCryptoId = contactIdentity?.cryptoId else {
                throw ObvUICoreDataError.contactIdentityIsNil
            }
            return .init(messageReference: messageReference,
                         oneToOneIdentifier: .init(
                            ownedCryptoId: ownedCryptoId,
                            contactCryptoId: contactCryptoId))
        case .groupV1(withContactGroup: let group):
            guard let group else {
                throw ObvUICoreDataError.groupV1IsNil
            }
            return .init(messageReference: messageReference,
                         groupV1Identifier: try group.getGroupId())
        case .groupV2(withGroup: let group):
            guard let group else {
                throw ObvUICoreDataError.groupV2IsNil
            }
            return .init(messageReference: messageReference,
                         groupV2Identifier: group.groupIdentifier)
        }

    }

}


// MARK: - Marking received messages as not new

extension PersistedDiscussion {
    
    func markReceivedMessageAsNotNew(receivedMessageId: ReceivedMessageIdentifier, dateWhenMessageTurnedNotNew: Date, requestedOnAnotherOwnedDevice: Bool) throws -> Date? {

        guard let receivedMessage = try PersistedMessageReceived.getPersistedMessageReceived(discussion: self, messageId: receivedMessageId) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageReceived
        }

        let lastReadMessageServerTimestamp = try receivedMessage.markAsNotNew(dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew, requestedOnAnotherOwnedDevice: requestedOnAnotherOwnedDevice)
        
        return lastReadMessageServerTimestamp
        
    }

    
    func markAllMessagesAsNotNew(serverTimestampWhenDiscussionReadOnAnotherOwnedDevice: Date?, dateWhenMessageTurnedNotNew: Date) throws -> Date? {
        
        let lastReadReceivedMessageServerTimestamp: Date?
        if let serverTimestampWhenDiscussionReadOnAnotherOwnedDevice {
            self.serverTimestampWhenDiscussionReadOnAnotherOwnedDevice = serverTimestampWhenDiscussionReadOnAnotherOwnedDevice
            lastReadReceivedMessageServerTimestamp = try PersistedMessageReceived.markAllAsNotNew(within: self,
                                                                                                  serverTimestampWhenDiscussionReadOnAnotherOwnedDevice: serverTimestampWhenDiscussionReadOnAnotherOwnedDevice,
                                                                                                  dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)
        } else {
            lastReadReceivedMessageServerTimestamp = try PersistedMessageReceived.markAllAsNotNew(within: self,
                                                                                                  dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew,
                                                                                                  requestedOnAnotherOwnedDevice: false)
        }
        let lastReadSystemMessageServerTimestamp = try PersistedMessageSystem.markAllAsNotNew(within: self, dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew)

        self.localDateWhenDiscussionRead = dateWhenMessageTurnedNotNew

        // Before returning the result, we add a notification on the context save, allowing to remove all user notifications concerning

        switch (lastReadReceivedMessageServerTimestamp, lastReadSystemMessageServerTimestamp) {
        case (.some(let date1), .some(let date2)):
            return max(date1, date2)
        case (.some(let date), .none):
            return date
        case (.none, .some(let date)):
            return date
        case (.none, .none):
            return nil
        }
        
    }
    
    
    func markAllMessagesAsNotNew(messageIds: [MessageIdentifier], dateWhenMessageTurnedNotNew: Date, requestedOnAnotherOwnedDevice: Bool) throws -> Date? {
        
        guard !messageIds.isEmpty else { return nil }
        
        var lastReadMessageServerTimestamp = Date.distantPast
        
        for messageId in messageIds {
            guard let message = try PersistedMessage.getPersistedMessage(discussion: self, messageId: messageId) else {
                // This can happen when dealing with ephemeral messages
                continue
            }
            switch message.kind {
            case .received:
                assert(message is PersistedMessageReceived)
                _ = try (message as? PersistedMessageReceived)?.markAsNotNew(dateWhenMessageTurnedNotNew: dateWhenMessageTurnedNotNew, requestedOnAnotherOwnedDevice: requestedOnAnotherOwnedDevice)
                lastReadMessageServerTimestamp = max(lastReadMessageServerTimestamp, message.timestamp)
            case .system:
                (message as? PersistedMessageSystem)?.markAsRead()
                lastReadMessageServerTimestamp = max(lastReadMessageServerTimestamp, message.timestamp)
            default:
                assertionFailure()
                throw ObvUICoreDataError.unexpectedMessageKind
            }
        }
        
        return lastReadMessageServerTimestamp
        
    }


}


// MARK: - Getting messages objectIDS for refreshing them in the view context

extension PersistedDiscussion {
    
    func getObjectIDOfReceivedMessage(messageId: ReceivedMessageIdentifier) throws -> NSManagedObjectID {
        
        guard let receivedMessage = try PersistedMessageReceived.getPersistedMessageReceived(discussion: self, messageId: messageId) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageReceived
        }

        return receivedMessage.objectID
        
    }
    
    func getReceivedMessageTypedObjectID(receivedMessageId: ReceivedMessageIdentifier) throws -> TypeSafeManagedObjectID<PersistedMessageReceived> {
        
        guard let receivedMessage = try PersistedMessageReceived.getPersistedMessageReceived(discussion: self, messageId: receivedMessageId) else {
            throw ObvUICoreDataError.couldNotFindPersistedMessageReceived
        }

        return receivedMessage.typedObjectID

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
            case rawLocalDateWhenDiscussionRead = "rawLocalDateWhenDiscussionRead"
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
        static func withOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            withOwnCryptoId(ownedIdentity.cryptoId)
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
        static var withValidMuteNotificationsEndDate: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForRawKey: Key.muteNotificationsEndDate),
                NSPredicate(Key.muteNotificationsEndDate, laterThan: Date()),
            ])
        }
        static func whereANewReceivedMessageDoesMentionOwnedIdentity(is bool: Bool) -> NSPredicate {
            NSPredicate(Key.aNewReceivedMessageDoesMentionOwnedIdentity, is: bool)
        }
        static var withNonNilLocalConfiguration: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.localConfiguration)
        }
        static var withDefaultPerformInteractionDonation: NSPredicate {
            let rawKey = [Key.localConfiguration.rawValue, PersistedDiscussionLocalConfiguration.Predicate.Key.rawPerformInteractionDonation.rawValue].joined(separator: ".")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.withNonNilLocalConfiguration,
                .init(withNilValueForRawKey: rawKey),
            ])
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

    
    private static func getAllDiscussionsOfOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) throws -> [PersistedDiscussion] {
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.fetchBatchSize = 1_000
        request.predicate = Predicate.withOwnedIdentity(ownedIdentity)
        request.propertiesToFetch = [Predicate.Key.numberOfNewMessages.rawValue]
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
                try discussion.deletePersistedDiscussion()
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
    
    
    static func getPersistedDiscussion(ownedIdentity: PersistedObvOwnedIdentity, discussionId: DiscussionIdentifier) throws -> PersistedDiscussion? {
        switch discussionId {
        case .oneToOne(let id):
            return try PersistedOneToOneDiscussion.getPersistedOneToOneDiscussion(ownedIdentity: ownedIdentity, oneToOneDiscussionId: id)
        case .groupV1(let id):
            return try PersistedGroupDiscussion.getPersistedGroupDiscussion(ownedIdentity: ownedIdentity, groupV1DiscussionId: id)
        case .groupV2(let id):
            return try PersistedGroupV2Discussion.getPersistedGroupV2Discussion(ownedIdentity: ownedIdentity, groupV2DiscussionId: id)
        }
    }
    
    
    public static func getPersistedDiscussion(ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, within context: NSManagedObjectContext) throws -> PersistedDiscussion? {
        guard let persistedOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else { return nil }
        return try Self.getPersistedDiscussion(ownedIdentity: persistedOwnedIdentity, discussionId: discussionId)
    }
    
    
    public static func getPersistedDiscussion(discussionIdentifier: ObvDiscussionIdentifier, within context: NSManagedObjectContext) throws -> PersistedDiscussion? {
        return try getPersistedDiscussion(ownedCryptoId: discussionIdentifier.ownedCryptoId,
                                          discussionId: discussionIdentifier.toDiscussionIdentifier(),
                                          within: context)
    }

    
    public static func getIdentifiersOfActiveDiscussionsWithDefaultPerformInteractionDonation(within context: NSManagedObjectContext) throws -> [ObvDiscussionIdentifier] {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withStatus(.active),
            Predicate.withDefaultPerformInteractionDonation,
        ])
        request.fetchBatchSize = 100
        let items = try context.fetch(request)
        let discussionIdentifiers = items.compactMap({ try? $0.discussionIdentifier})
        assert(items.count == discussionIdentifiers.count)
        return discussionIdentifiers
    }
        
}


// MARK: - NSFetchRequest creators

extension PersistedDiscussion {

    /// Returns the `objectID`s of all the discussions of the given owned identity. This is typically used to perform a deletion of all the discussions when the owned identity gets deleted.
    static func getObjectIDsOfAllDiscussionsOfOwnedIdentity(persistedOwnedIdentity: PersistedObvOwnedIdentity) throws -> [NSManagedObjectID] {
        guard let context = persistedOwnedIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request = NSFetchRequest<NSManagedObjectID>(entityName: Self.entityName)
        request.resultType = .managedObjectIDResultType
        request.predicate = Predicate.withOwnCryptoId(persistedOwnedIdentity.cryptoId)
        let objectIDs = try context.fetch(request)
        return objectIDs
    }
    
    
    /// When changing the pinned index of a discussion, we must propagate the change to our other owned devices. This requires a list of discussion identifiers. We use this method to make it possible to build this list.
    public static func getAllPinnedDiscussions(ownedCryptoId: ObvCryptoId, with context: NSManagedObjectContext) throws -> [PersistedDiscussion] {
        let request: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(ownedCryptoId),
            Predicate.whereIsPinnedIs(true),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.rawPinnedIndex.rawValue, ascending: true)]
        request.fetchBatchSize = 100
        return try context.fetch(request)
    }
    
    
    static func getObjectIDsOfAllPinnedDiscussions(ownedCryptoId: ObvCryptoId, with context: NSManagedObjectContext) throws -> [NSManagedObjectID] {
        let request = NSFetchRequest<NSManagedObjectID>(entityName: PersistedDiscussion.entityName)
        request.resultType = .managedObjectIDResultType
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnCryptoId(ownedCryptoId),
            Predicate.whereIsPinnedIs(true),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.rawPinnedIndex.rawValue, ascending: true)]
        request.fetchBatchSize = 100
        return try context.fetch(request)

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
    public static func getFetchRequestForSearchTermForDiscussionsForOwnedIdentity(with ownedCryptoId: ObvCryptoId, restrictToActiveDiscussions: Bool, searchTerm: String?) -> FetchRequestControllerModel<PersistedDiscussion> {
        let fetchRequest: NSFetchRequest<PersistedDiscussion> = PersistedDiscussion.fetchRequest()
        
        var subPredicates = [Predicate.withOwnCryptoId(ownedCryptoId)]
        
        if restrictToActiveDiscussions {
            subPredicates.append(Predicate.withStatus(.active))
        }
        
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
        } else {
            // If the illustrative message is not part of the messages anymore (which happens when we wipe all messages of a discussion), we remove it.
            // Note that setting the illustrativeMessage to nil ensures we don't enter an infinite loop as the test won't trigger twice.
            if let illustrativeMessage, illustrativeMessage.discussion == nil {
                self.illustrativeMessage = nil
            }
        }
    }

    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
            discussionPermanentIDOnDeletion = nil
            isInsertedWhileRestoringSyncSnapshot = false
        }
        
        guard !isInsertedWhileRestoringSyncSnapshot else {
            assert(isInserted)
            let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: Self.self))
            os_log("Insertion of a PersistedDiscussion during a snapshot restore --> we don't send any notification", log: log, type: .info)
            return
        }

        if changedKeys.contains(Predicate.Key.title.rawValue) {
            ObvMessengerCoreDataNotification.persistedDiscussionHasNewTitle(objectID: typedObjectID, title: title)
                .postOnDispatchQueue()
        }
        
        if changedKeys.contains(Predicate.Key.rawStatus.rawValue), !isDeleted {
            ObvMessengerCoreDataNotification.persistedDiscussionStatusChanged(discussionPermanentID: self.discussionPermanentID, newStatus: status)
                .postOnDispatchQueue()
            do {
                let discussionIdentifier = try self.discussionIdentifier
                let status = self.status
                Task { await Self.observersHolder.aPersistedDiscussionStatusChanged(discussionIdentifier: discussionIdentifier, status: status) }
            } catch {
                Self.logger.error("Could not compute discussion identifier: \(error)")
                assertionFailure()
            }
        }
        
        if changedKeys.contains(Predicate.Key.isArchived.rawValue), !isDeleted, self.isArchived {
            ObvMessengerCoreDataNotification.persistedDiscussionWasArchived(discussionPermanentID: self.discussionPermanentID)
                .postOnDispatchQueue()
            do {
                let discussionIdentifier = try self.discussionIdentifier
                let isArchived = self.isArchived
                Task { await Self.observersHolder.aPersistedDiscussionIsArchivedChanged(discussionIdentifier: discussionIdentifier, isArchived: isArchived) }
            } catch {
                Self.logger.error("Could not compute discussion identifier: \(error)")
                assertionFailure()
            }
        }

        if let discussionPermanentIDOnDeletion, isDeleted {
            ObvMessengerCoreDataNotification.persistedDiscussionWasDeleted(discussionPermanentID: discussionPermanentIDOnDeletion, objectIDOfDeletedDiscussion: self.typedObjectID)
                .postOnDispatchQueue()
        }
        
        if isDeleted {
            if let discussionIdentifier = self.discussionIdentifierOnDeletion {
                Task { await Self.observersHolder.aPersistedDiscussionWasDeleted(discussionIdentifier: discussionIdentifier) }
            } else {
                assertionFailure() // In production, continue
            }
        }
        
        if isInserted || (changedKeys.contains(Predicate.Key.rawStatus.rawValue) && self.status == .active) {
            guard let ownedCryptoId = ownedIdentity?.cryptoId,
                  let discussionIdentifier = try? self.identifier else { assertionFailure(); return }
            ObvMessengerCoreDataNotification.persistedDiscussionWasInsertedOrReactivated(ownedCryptoId: ownedCryptoId, discussionIdentifier: discussionIdentifier)
                .postOnDispatchQueue()
        }
        
        if !isDeleted && changedKeys.contains(Predicate.Key.rawLocalDateWhenDiscussionRead.rawValue) {
            do {
                let discussionIdentifier = try self.discussionIdentifier
                let localDateWhenDiscussionRead = self.localDateWhenDiscussionRead
                Task { await Self.observersHolder.aPersistedDiscussionWasRead(discussionIdentifier: discussionIdentifier, localDateWhenDiscussionRead: localDateWhenDiscussionRead) }
            } catch {
                Self.logger.error("Could not compute discussion identifier: \(error)")
                assertionFailure()
            }
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


extension DiscussionSharedConfigurationJSON {
    
    var sharedConfig: PersistedDiscussion.SharedConfiguration {
        .init(version: self.version,
              expiration: self.expiration)
    }
    
}



// MARK: - For snapshot purposes

extension PersistedDiscussion {
    
    var syncSnapshotNode: PersistedDiscussionConfigurationSyncSnapshotNode {
        .init(localConfiguration: localConfiguration,
              sharedConfiguration: sharedConfiguration)
    }
    
}


struct PersistedDiscussionConfigurationSyncSnapshotNode: ObvSyncSnapshotNode {

    private let domain: Set<CodingKeys>
    private let localConfiguration: PersistedDiscussionLocalConfigurationSyncSnapshotItem?
    private let sharedConfiguration: PersistedDiscussionSharedConfigurationSyncSnapshotItem?
    
    let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case localConfiguration = "local_settings"
        case sharedConfiguration = "shared_settings"
        case domain = "domain"
    }

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    init(localConfiguration: PersistedDiscussionLocalConfiguration, sharedConfiguration: PersistedDiscussionSharedConfiguration) {
        self.domain = Self.defaultDomain
        self.localConfiguration = localConfiguration.syncSnapshotNode
        self.sharedConfiguration = sharedConfiguration.syncSnapshotNode
    }
    
    
    // Synthesized implementation of encode(to encoder: Encoder)

    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKeys = try container.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
        self.localConfiguration = try container.decodeIfPresent(PersistedDiscussionLocalConfigurationSyncSnapshotItem.self, forKey: .localConfiguration)
        self.sharedConfiguration = try container.decodeIfPresent(PersistedDiscussionSharedConfigurationSyncSnapshotItem.self, forKey: .sharedConfiguration)
    }
    

    func useToUpdate(_ discussion: PersistedDiscussion) {
        
        if domain.contains(.localConfiguration) {
            localConfiguration?.useToUpdate(discussion.localConfiguration)
        }
        
        if domain.contains(.sharedConfiguration) {
            sharedConfiguration?.useToUpdate(discussion.sharedConfiguration)
        }
        
    }

}


// MARK: - PersistedDiscussion observers

public protocol PersistedDiscussionObserver {
    func aPersistedDiscussionStatusChanged(discussionIdentifier: ObvDiscussionIdentifier, status: PersistedDiscussion.Status) async
    func aPersistedDiscussionIsArchivedChanged(discussionIdentifier: ObvDiscussionIdentifier, isArchived: Bool) async
    func aPersistedDiscussionWasDeleted(discussionIdentifier: ObvDiscussionIdentifier) async
    func aPersistedDiscussionWasRead(discussionIdentifier: ObvDiscussionIdentifier, localDateWhenDiscussionRead: Date) async
}


private actor PersistedDiscussionObserversHolder: PersistedDiscussionObserver {
    
    private var observers = [PersistedDiscussionObserver]()
    
    func addObserver(_ newObserver: PersistedDiscussionObserver) {
        self.observers.append(newObserver)
    }
    
    // Implementing PersistedDiscussionObserver
    
    func aPersistedDiscussionStatusChanged(discussionIdentifier: ObvDiscussionIdentifier, status: PersistedDiscussion.Status) async {
        for observer in observers {
            await observer.aPersistedDiscussionStatusChanged(discussionIdentifier: discussionIdentifier, status: status)
        }
    }
    
    func aPersistedDiscussionIsArchivedChanged(discussionIdentifier: ObvDiscussionIdentifier, isArchived: Bool) async {
        for observer in observers {
            await observer.aPersistedDiscussionIsArchivedChanged(discussionIdentifier: discussionIdentifier, isArchived: isArchived)
        }
    }
    
    func aPersistedDiscussionWasDeleted(discussionIdentifier: ObvDiscussionIdentifier) async {
        for observer in observers {
            await observer.aPersistedDiscussionWasDeleted(discussionIdentifier: discussionIdentifier)
        }
    }

    func aPersistedDiscussionWasRead(discussionIdentifier: ObvDiscussionIdentifier, localDateWhenDiscussionRead: Date) async {
        for observer in observers {
            await observer.aPersistedDiscussionWasRead(discussionIdentifier: discussionIdentifier, localDateWhenDiscussionRead: localDateWhenDiscussionRead)
        }
    }

}


// MARK: - NSFetchedResultsController safeObject

public extension NSFetchedResultsController<PersistedDiscussion> {
    
    /// Provides a safe way to access a `PersistedMessage` at an `indexPath`.
    func safeObject(at indexPath: IndexPath) -> PersistedDiscussion? {
        guard let selfSections = self.sections, indexPath.section < selfSections.count else { return nil }
        let sectionInfos = selfSections[indexPath.section]
        guard indexPath.item < sectionInfos.numberOfObjects else { return nil }
        return self.object(at: indexPath)
    }
    
}
