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
import ObvEngine
import OlvidUtils
import ObvCrypto
import ObvTypes
import ObvSettings
import ObvAppTypes



@objc(PersistedOneToOneDiscussion)
public final class PersistedOneToOneDiscussion: PersistedDiscussion, ObvIdentifiableManagedObject {
    
    public static let entityName = "PersistedOneToOneDiscussion"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedOneToOneDiscussion")

    // Attributes
    
    @NSManaged private var rawContactIdentityIdentity: Data? // Keeps track of the bytes of the contact, making it possible to unlock a discussion

    // Relationships

    @NSManaged private var rawContactIdentity: PersistedObvContactIdentity? // If nil, this entity is eventually cascade-deleted
    
    // Accessors
    
    public private(set) var contactIdentity: PersistedObvContactIdentity? {
        get {
            return rawContactIdentity
        }
        set {
            if let newValue = newValue {
                assert(self.rawContactIdentityIdentity == nil || self.rawContactIdentityIdentity == newValue.identity)
                self.rawContactIdentityIdentity = newValue.identity
            }
            self.rawContactIdentity = newValue
        }
    }
    

    /// Expected to be non-nil
    var contactCryptoId: ObvCryptoId? {
        guard let rawContactIdentityIdentity else { assertionFailure(); return nil }
        return try? ObvCryptoId(identity: rawContactIdentityIdentity)
    }
    
    
    /// Expected to be non-nil
    public var contactIdentifier: ObvContactIdentifier? {
        guard let contactCryptoId, let ownedCryptoId = ownedIdentity?.cryptoId else { assertionFailure(); return nil }
        return .init(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
    }
    
    
    /// Expected to be non-nil, unless this `NSManagedObject` is deleted.
    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedOneToOneDiscussion> {
        get throws {
            guard self.managedObjectContext != nil else { assertionFailure(); throw ObvUICoreDataError.noContext }
            return ObvManagedObjectPermanentID<PersistedOneToOneDiscussion>(uuid: self.permanentUUID)
        }
    }

    public var oneToOneIdentifier: OneToOneIdentifierJSON {
        get throws {
            guard let ownedCryptoId = ownedIdentity?.cryptoId else {
                throw ObvUICoreDataError.ownedIdentityIsNil
            }
            if let contactCryptoId = contactIdentity?.cryptoId {
                return OneToOneIdentifierJSON(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            } else if let contactIdentityIdentity = self.rawContactIdentityIdentity, let contactCryptoId = try? ObvCryptoId(identity: contactIdentityIdentity) {
                return OneToOneIdentifierJSON(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            } else {
                assertionFailure()
                throw ObvUICoreDataError.contactIdentityIsNil
            }
        }
    }

    // MARK: - Initializer
    
    private convenience init(contactIdentity: PersistedObvContactIdentity, status: Status, isRestoringSyncSnapshotOrBackup: Bool) throws {
        guard let ownedIdentity = contactIdentity.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it was just deleted.", log: PersistedOneToOneDiscussion.log, type: .error)
            throw ObvUICoreDataError.ownedIdentityIsNil
        }
        try self.init(title: contactIdentity.nameForSettingOneToOneDiscussionTitle,
                      ownedIdentity: ownedIdentity,
                      forEntityName: PersistedOneToOneDiscussion.entityName,
                      status: status,
                      shouldApplySharedConfigurationFromGlobalSettings: true,
                      isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)

        self.contactIdentity = contactIdentity

        try? insertSystemMessagesIfDiscussionIsEmpty(markAsRead: false, messageTimestamp: Date())

    }
    
    
    static func createPersistedOneToOneDiscussion(for contactIdentity: PersistedObvContactIdentity, status: Status, isRestoringSyncSnapshotOrBackup: Bool) throws -> PersistedOneToOneDiscussion  {
        let oneToOneDiscussion = try self.init(contactIdentity: contactIdentity, status: status, isRestoringSyncSnapshotOrBackup: isRestoringSyncSnapshotOrBackup)
        return oneToOneDiscussion
    }
    
    
    // MARK: - Status management
    
    override func setStatus(to newStatus: PersistedDiscussion.Status) throws {
        guard self.status != newStatus else { return }
        // Insert the appropriate system message in the group discussion
        switch (self.status, newStatus) {
        case (.locked, .active):
            try PersistedMessageSystem.insertContactIsOneToOneAgainSystemMessage(within: self)
        default:
            break
        }
        try super.setStatus(to: newStatus)
        if newStatus == .locked {
            _ = try PersistedMessageSystem(.contactWasDeleted,
                                           optionalContactIdentity: nil,
                                           optionalOwnedCryptoId: nil,
                                           optionalCallLogItem: nil,
                                           discussion: self,
                                           timestamp: Date())
        }
    }


    /// Exclusively called from `PersistedObvContactIdentity`, when the contact is updated.
    func resetDiscussionTitleWithContactIfAppropriate() {
        guard self.managedObjectContext != nil else { assertionFailure(); return }
        guard let contactIdentity else { assertionFailure(); return }
        do {
            try self.resetTitle(to: contactIdentity.nameForSettingOneToOneDiscussionTitle)
        } catch {
            os_log("one2one discussion title could not be reset: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
        
    
    // MARK: - Receiving discussion shared configurations
    
    /// Called when receiving a shared configuration from a contact. Returns `true` iff the shared configuration had to be updated.
    ///
    /// Since a contact of a OneToOne discussion is always allowed to change the shared configuration, no particular check is made here, and we can call the super implementation.
    func mergeDiscussionSharedConfiguration(discussionSharedConfiguration: SharedConfiguration, receivedFrom contact: PersistedObvContactIdentity) throws -> (sharedSettingHadToBeUpdated: Bool, weShouldSendBackOurSharedSettings: Bool) {
        
        guard self.contactIdentity == contact else {
            throw ObvUICoreDataError.unexpectedContact
        }
        
        let (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettingsIfAllowedTo) = try super.mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration)
        
        // We are always allowed to change the settings of a oneToOne discussion
        let weShouldSendBackOurSharedSettings = weShouldSendBackOurSharedSettingsIfAllowedTo
        
        return (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettings)
        
    }
    
    
    /// Called when receiving a ``DiscussionSharedConfigurationJSON`` from an owned identity. Returns `true` iff the shared configuration had to be updated.
    ///
    /// Since an owned identiy of a OneToOne discussion is always allowed to change the shared configuration, no particular check is made here, and we can call the super implementation.
    func mergeDiscussionSharedConfiguration(discussionSharedConfiguration: SharedConfiguration, receivedFrom ownedIdentity: PersistedObvOwnedIdentity) throws -> (sharedSettingHadToBeUpdated: Bool, weShouldSendBackOurSharedSettings: Bool) {
    
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        let (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettingsIfAllowedTo) = try super.mergeReceivedDiscussionSharedConfiguration(discussionSharedConfiguration)

        // We are always allowed to change the settings of a oneToOne discussion
        let weShouldSendBackOurSharedSettings = weShouldSendBackOurSharedSettingsIfAllowedTo

        return (sharedSettingHadToBeUpdated, weShouldSendBackOurSharedSettings)
        
    }
    
    
    /// Called when an owned identity decided to change this discussion's shared configuration from the current device.
    func replaceDiscussionSharedConfiguration(with expiration: ExpirationJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity) throws -> Bool {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        let sharedSettingHadToBeUpdated = try super.replaceReceivedDiscussionSharedConfiguration(with: expiration)
        
        return sharedSettingHadToBeUpdated

    }
    
    
    // MARK: - Processing wipe requests

    func processWipeMessageRequest(of messagesToDelete: [MessageReferenceJSON], receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        guard self.contactIdentity == contact else {
            throw ObvUICoreDataError.unexpectedContact
        }
        
        let infos = try super.processWipeMessageRequest(of: messagesToDelete, from: contact.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return infos

    }
    
    
    func processWipeMessageRequest(of messagesToDelete: [MessageReferenceJSON], receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> [InfoAboutWipedOrDeletedPersistedMessage] {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        let infos = try super.processWipeMessageRequest(of: messagesToDelete, from: ownedIdentity.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)

        return infos
                            
    }
    
    
    // MARK: - Processing discussion (all messages) wipe requests for other owned devices (contact are not allowed to delete all messages from a one2one discussion)

    
    override func processRemoteRequestToWipeAllMessagesWithinThisDiscussion(from ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        try super.processRemoteRequestToWipeAllMessagesWithinThisDiscussion(from: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }

    
    // MARK: - Processing delete requests from the owned identity

    override func processMessageDeletionRequestRequestedFromCurrentDevice(of ownedIdentity: PersistedObvOwnedIdentity, messageToDelete: PersistedMessage, deletionType: DeletionType) throws -> InfoAboutWipedOrDeletedPersistedMessage {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        switch deletionType {
        case .fromThisDeviceOnly:
            break
        case .fromAllOwnedDevices:
            guard ownedIdentity.hasAnotherDeviceWhichIsReachable else {
                throw ObvUICoreDataError.cannotDeleteMessageFromAllOwnedDevicesAsOwnedIdentityHasNoOtherReachableDevice
            }
        case .fromAllOwnedDevicesAndAllContactDevices:
            guard messageToDelete is PersistedMessageSent else {
                throw ObvUICoreDataError.onlySentMessagesCanBeDeletedFromContactDevicesWhenInOneToOneDiscussion
            }
        }
        
        let info = try super.processMessageDeletionRequestRequestedFromCurrentDevice(of: ownedIdentity, messageToDelete: messageToDelete, deletionType: deletionType)
        
        return info
        
    }

    
    override func processDiscussionDeletionRequestFromCurrentDevice(of ownedIdentity: PersistedObvOwnedIdentity, deletionType: DeletionType) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        switch deletionType {
        case .fromThisDeviceOnly:
            break
        case .fromAllOwnedDevices:
            guard ownedIdentity.hasAnotherDeviceWhichIsReachable else {
                throw ObvUICoreDataError.cannotDeleteDiscussionFromAllOwnedDevicesAsOwnedIdentityHasNoOtherReachableDevice
            }
        case .fromAllOwnedDevicesAndAllContactDevices:
            throw ObvUICoreDataError.cannotDeleteOneToOneDiscussionFromContactDevices
        }

        try super.processDiscussionDeletionRequestFromCurrentDevice(of: ownedIdentity, deletionType: deletionType)
        
    }

    
    // MARK: - Receiving messages and attachments from a contact or another owned device

    override func createOrOverridePersistedMessageReceived(from contact: PersistedObvContactIdentity, obvMessage: ObvMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, source: ObvMessageSource, receivedLocation: ReceivedLocation?) throws -> (discussionPermanentID: DiscussionPermanentID, messagePermanentId: MessageReceivedPermanentID?) {
        
        guard self.contactIdentity == contact else {
            throw ObvUICoreDataError.unexpectedContact
        }
        
        return try super.createOrOverridePersistedMessageReceived(
            from: contact,
            obvMessage: obvMessage,
            messageJSON: messageJSON,
            returnReceiptJSON: returnReceiptJSON,
            source: source,
            receivedLocation: receivedLocation)
        
    }
    
    
    override func createPersistedMessageSentFromOtherOwnedDevice(from ownedIdentity: PersistedObvOwnedIdentity, obvOwnedMessage: ObvOwnedMessage, messageJSON: MessageJSON, returnReceiptJSON: ReturnReceiptJSON?, sentLocation: SentLocation?) throws -> MessageSentPermanentID? {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedContact
        }

        return try super.createPersistedMessageSentFromOtherOwnedDevice(
            from: ownedIdentity,
            obvOwnedMessage: obvOwnedMessage,
            messageJSON: messageJSON,
            returnReceiptJSON: returnReceiptJSON,
            sentLocation: sentLocation)
    }
    
    
    // MARK: - Processing edit requests

    func processUpdateMessageRequest(_ updateMessageJSON: UpdateMessageJSON, receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        guard self.contactIdentity == contact else {
            throw ObvUICoreDataError.unexpectedContact
        }

        let updatedMessage = try super.processUpdateMessageRequest(updateMessageJSON, receivedFromContactCryptoId: contact.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return updatedMessage
        
    }

    
    func processUpdateMessageRequest(_ updateMessageJSON: UpdateMessageJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        let updatedMessage = try super.processUpdateMessageRequest(updateMessageJSON, receivedFromOwnedCryptoId: ownedIdentity.cryptoId, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return updatedMessage
        
    }
    
    
    override func processLocalUpdateMessageRequest(from ownedIdentity: PersistedObvOwnedIdentity, for messageSent: PersistedMessageSent, newTextBody: String?) throws {

        try super.processLocalUpdateMessageRequest(from: ownedIdentity, for: messageSent, newTextBody: newTextBody)
        
    }

    // MARK: - Process reaction requests

    override func processSetOrUpdateReactionOnMessageLocalRequest(from ownedIdentity: PersistedObvOwnedIdentity, for message: PersistedMessage, newEmoji: String?) throws {
        
        try super.processSetOrUpdateReactionOnMessageLocalRequest(from: ownedIdentity, for: message, newEmoji: newEmoji)

    }

    
    override func processSetOrUpdateReactionOnMessageRequest(_ reactionJSON: ReactionJSON, receivedFrom contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date, overrideExistingReaction: Bool) throws -> PersistedMessage? {
        
        guard self.contactIdentity == contact else {
            throw ObvUICoreDataError.unexpectedContact
        }

        let updatedMessage = try super.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer, overrideExistingReaction: overrideExistingReaction)
        
        return updatedMessage
        
    }
    
    
    override func processSetOrUpdateReactionOnMessageRequest(_ reactionJSON: ReactionJSON, receivedFrom ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws -> PersistedMessage? {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        let updatedMessage = try super.processSetOrUpdateReactionOnMessageRequest(reactionJSON, receivedFrom: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
        return updatedMessage
        
    }

    
    // MARK: - Process screen capture detections

    override func processDetectionThatSensitiveMessagesWereCaptured(_ screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, from contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.contactIdentity == contact else {
            throw ObvUICoreDataError.unexpectedContact
        }

        try super.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: contact, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }

    
    override func processDetectionThatSensitiveMessagesWereCaptured(_ screenCaptureDetectionJSON: ScreenCaptureDetectionJSON, from ownedIdentity: PersistedObvOwnedIdentity, messageUploadTimestampFromServer: Date) throws {
        
        guard self.ownedIdentity == ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }

        try super.processDetectionThatSensitiveMessagesWereCaptured(screenCaptureDetectionJSON, from: ownedIdentity, messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        
    }

    
    override func processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by ownedIdentity: PersistedObvOwnedIdentity) throws {
        
        try super.processLocalDetectionThatSensitiveMessagesWereCapturedInThisDiscussion(by: ownedIdentity)
        
    }
 
    
    // MARK: - Inserting system messages within discussions

    func oneToOneContactWasIntroducedTo(otherContact: PersistedObvContactIdentity) throws {
        
        guard otherContact.ownedIdentity == self.ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        
        try PersistedMessageSystem.insertContactWasIntroducedToAnotherContact(within: self, otherContact: otherContact)
        
    }

}


// MARK: - NSFetchRequest

extension PersistedOneToOneDiscussion {
    
    struct Predicate {
        enum Key: String {
            case rawContactIdentityIdentity = "rawContactIdentityIdentity"
            case rawContactIdentity = "rawContactIdentity"
            static let ownedIdentityIdentity = [PersistedDiscussion.Predicate.Key.ownedIdentity.rawValue, PersistedObvOwnedIdentity.Predicate.Key.identity.rawValue].joined(separator: ".")
        }
        static func withContactCryptoId(_ cryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawContactIdentityIdentity, EqualToData: cryptoId.getIdentity())
        }
        static func withContactIdentity(_ contact: PersistedObvContactIdentity) -> NSPredicate {
            NSPredicate(Key.rawContactIdentity, equalTo: contact)
        }
        static func withOwnedCryptoId(_ ownCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownCryptoId.getIdentity())
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<PersistedOneToOneDiscussion>) -> NSPredicate {
            PersistedDiscussion.Predicate.withPermanentID(permanentID.downcast)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            PersistedDiscussion.Predicate.persistedDiscussion(withObjectID: objectID)
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedOneToOneDiscussion> {
        return NSFetchRequest<PersistedOneToOneDiscussion>(entityName: PersistedOneToOneDiscussion.entityName)
    }
    
    
    /// Fetches the `PersistedOneToOneDiscussion` on the basis of the `oneToOneIdentifier` of the discussion (which, for now, corresponds to the identity of the contact).
    public static func fetchPersistedOneToOneDiscussion(oneToOneIdentifier: OneToOneIdentifierJSON, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedOneToOneDiscussion? {
        guard let contactCryptoId = oneToOneIdentifier.getContactIdentity(ownedIdentity: ownedCryptoId) else {
            throw ObvUICoreDataError.inconsistentOneToOneIdentifier
        }
        let request: NSFetchRequest<PersistedOneToOneDiscussion> = PersistedOneToOneDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withContactCryptoId(contactCryptoId),
        ])
        request.fetchLimit = 1
        return (try context.fetch(request)).first
    }

    
    /// Returns a `NSFetchRequest` for all the one-tone discussions of the owned identity, sorted by the discussion title.
    public static func getFetchRequestForAllActiveOneToOneDiscussionsSortedByTitleForOwnedIdentity(with ownedCryptoId: ObvCryptoId) -> FetchRequestControllerModel<PersistedDiscussion> {
        let request: NSFetchRequest<PersistedDiscussion> = NSFetchRequest<PersistedDiscussion>(entityName: PersistedOneToOneDiscussion.entityName)
        request.sortDescriptors = [NSSortDescriptor(key: PersistedDiscussion.Predicate.Key.title.rawValue, ascending: true)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            PersistedDiscussion.Predicate.withStatus(.active),
        ])
        request.relationshipKeyPathsForPrefetching = [
            PersistedDiscussion.Predicate.Key.illustrativeMessage.rawValue,
            PersistedDiscussion.Predicate.Key.localConfiguration.rawValue,
        ]
        return FetchRequestControllerModel(fetchRequest: request, sectionNameKeyPath: nil)
    }


    /// This method returns a `PersistedOneToOneDiscussion` if one can be found and `nil` otherwise.
    /// If `status` is non-nil, the returned discussion will have this specific status.
    public static func get(with contact: PersistedObvContactIdentity, status: Status?) throws -> PersistedOneToOneDiscussion? {
        guard let context = contact.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedOneToOneDiscussion> = PersistedOneToOneDiscussion.fetchRequest()
        var predicates = [Predicate.withContactIdentity(contact)]
        if let status = status {
            predicates.append(PersistedDiscussion.Predicate.withStatus(status))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.fetchLimit = 1
        return (try context.fetch(request)).first
    }
    
    
    /// This method returns a `PersistedOneToOneDiscussion` if one can be found and `nil` otherwise.
    static func getWithContactCryptoId(_ contact: ObvCryptoId, ofOwnedCryptoId ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedOneToOneDiscussion? {
        let request: NSFetchRequest<PersistedOneToOneDiscussion> = PersistedOneToOneDiscussion.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactCryptoId(contact),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        request.fetchLimit = 1
        return (try context.fetch(request)).first
    }

    
    static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<PersistedOneToOneDiscussion>, within context: NSManagedObjectContext) throws -> PersistedOneToOneDiscussion? {
        let request: NSFetchRequest<PersistedOneToOneDiscussion> = PersistedOneToOneDiscussion.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func getPersistedOneToOneDiscussion(ownedIdentity: PersistedObvOwnedIdentity, oneToOneDiscussionId: OneToOneDiscussionIdentifier) throws -> PersistedOneToOneDiscussion? {
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedOneToOneDiscussion> = PersistedOneToOneDiscussion.fetchRequest()
        switch oneToOneDiscussionId {
        case .objectID(let objectID):
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withObjectID(objectID),
                Predicate.withOwnedCryptoId(ownedIdentity.cryptoId),
            ])
        case .contactCryptoId(let contactCryptoId):
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withOwnedCryptoId(ownedIdentity.cryptoId),
                Predicate.withContactCryptoId(contactCryptoId),
            ])
        }
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}


public extension TypeSafeManagedObjectID where T == PersistedOneToOneDiscussion {
    var downcast: TypeSafeManagedObjectID<PersistedDiscussion> {
        TypeSafeManagedObjectID<PersistedDiscussion>(objectID: objectID)
    }
}
