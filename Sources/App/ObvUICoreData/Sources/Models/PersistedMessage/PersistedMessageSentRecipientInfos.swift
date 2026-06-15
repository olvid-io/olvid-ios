/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvCrypto
import OSLog
import ObvTypes
import ObvAppTypes
import OlvidUtils
import ObvSettings


@objc(PersistedMessageSentRecipientInfos)
public final class PersistedMessageSentRecipientInfos: NSManagedObject {
    
    private static let entityName = "PersistedMessageSentRecipientInfos"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedMessageSentRecipientInfos")
    private static let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedMessageSentRecipientInfos")
    
    // MARK: Attributes

    @NSManaged public private(set) var couldNotBeSentToServer: Bool // Set to true if the engine could not send message during 30 days
    @NSManaged public private(set) var messageIdentifierFromEngine: Data? // Set to 0x55 when the associated message was sent from another owned device
    @NSManaged private var recipientIdentity: Data
    @NSManaged private(set) var returnReceiptKey: Data?
    @NSManaged private var returnReceiptNonce: Data?
    /// Set when the all the attachments have been sent. If the message has no attachment, this is set at the same time `timestampMessageSent` is set.
    @NSManaged private(set) var timestampAllAttachmentsSent: Date?
    @NSManaged public private(set) var timestampDelivered: Date?
    @NSManaged public private(set) var timestampRead: Date?
    /// Set when the server receives the message (but not the attachments). This timestamp is returned by the server.
    @NSManaged public private(set) var timestampMessageSent: Date?

    // MARK: Relationships
    
    @NSManaged public private(set) var messageSent: PersistedMessageSent
    @NSManaged public private(set) var attachmentInfos: Set<PersistedAttachmentSentRecipientInfos>

    // MARK: Computed variables
    
    public var recipientCryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: recipientIdentity)
    }
    
    public func getRecipient() throws -> PersistedObvContactIdentity? {
        guard let discussion = messageSent.discussion else {
            throw ObvUICoreDataError.couldNotFindDiscussion
        }
        guard let ownedIdentity = discussion.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it has just been deleted.", log: Self.log, type: .error)
            return nil
        }
        return try PersistedObvContactIdentity.get(cryptoId: recipientCryptoId, ownedIdentity: ownedIdentity, whereOneToOneStatusIs: .any)
    }
        
    public var recipientName: String {
        if let recipient = try? getRecipient() {
            return recipient.customDisplayName ?? recipient.fullDisplayName
        } else {
            // This happens when the message is sent in a group v2, with a pending member (who did not accept the group invitation yet),
            // and who is not part of our contacts yet.
            if let recipient = (messageSent.discussion as? PersistedGroupV2Discussion)?.group?.otherMembers.first(where: { $0.identity == recipientIdentity }) {
                return recipient.displayedCustomDisplayNameOrFirstNameOrLastName ?? "-"
            } else {
                return "-"
            }
        }
    }
    
    public var returnReceiptElements: (nonce: Data, key: Data)? {
        return (self.returnReceiptNonce, self.returnReceiptKey) as? (Data, Data) ?? nil
    }
    
    
    public var elements: ObvReturnReceiptElements? {
        guard let returnReceiptNonce, let returnReceiptKey else { return nil }
        return .init(nonce: returnReceiptNonce, key: returnReceiptKey)
    }
    

    /// We consider that a message and its attachments are sent when the message is received by the server (i.e., `timestampMessageSent` is not `nil`)
    /// and the attachments have been fully received by the server (i.e., `timestampAllAttachmentsSent` is not `nil`).
    /// For a message without attachment, the `timestampMessageSent` is sufficient.
    var messageAndAttachmentsAreSent: Bool {
        timestampMessageSent != nil && timestampAllAttachmentsSent != nil
    }


    // MARK: - Initializer
    
    /// Shall *only* be called from within the intialiazer of `PersistedMessageSent`.
    convenience init(recipientIdentity: Data, messageSent: PersistedMessageSent) throws {
     
        guard let context = messageSent.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedMessageSentRecipientInfos.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        _ = try ObvCryptoId(identity: recipientIdentity)
        
        self.couldNotBeSentToServer = false
        self.messageIdentifierFromEngine = nil // Note that in case of a message sent from another owned device, we will soon call `func setValuesReceivedFromAnotherOwnedDevice(...)`
        self.recipientIdentity = recipientIdentity
        self.returnReceiptKey = nil
        self.returnReceiptNonce = nil
        self.timestampDelivered = nil
        self.timestampRead = nil
        self.timestampMessageSent = nil
        self.timestampAllAttachmentsSent = nil
        
        self.messageSent = messageSent
        self.attachmentInfos = Set(messageSent.fyleMessageJoinWithStatuses.compactMap({ try? PersistedAttachmentSentRecipientInfos(index: $0.index, info: self) }))

    }
    
    
    public func delete() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        context.delete(self)
        messageSent.refreshStatus()
    }


    // MARK: - Other methods
    
    public func setMessageIdentifierFromEngine(to messageIdentifierFromEngine: Data, andReturnReceiptElementsTo elements: ObvReturnReceiptElements) {
        assert(elements.nonce.count == 16)
        self.messageIdentifierFromEngine = messageIdentifierFromEngine
        self.returnReceiptNonce = elements.nonce
        self.returnReceiptKey = elements.key
        self.messageSent.refreshStatus()
    }
    
    
    func setValuesReceivedFromAnotherOwnedDevice(returnReceiptJSON: ReturnReceiptJSON, messageUploadTimestampFromServer: Date) {
        // 2025-09-01: Fixed a bug in macOS 13 where setting an empty `Data()` object was incorrectly treated as `NULL`.
        // This caused messages sent from other owned devices to be mistakenly identified as originating from the current device,
        // resulting in the message being resent and received twice by the recipient.
        self.messageIdentifierFromEngine = Data(repeating: 0x55, count: 1)
        self.returnReceiptNonce = returnReceiptJSON.elements.nonce
        self.returnReceiptKey = returnReceiptJSON.elements.key
        // The following method call sets `timestampMessageSent` and `timestampAllAttachmentsSent`.
        self.messageWasSentNoLaterThan(messageUploadTimestampFromServer, alsoMarkAttachmentsAsSent: true)
        self.messageSent.refreshStatus()
    }
    

    public func messageWasSentNoLaterThan(_ timestamp: Date, alsoMarkAttachmentsAsSent: Bool) {
        
        if let currentTimeStamp = self.timestampMessageSent {
            if currentTimeStamp > timestamp {
                self.timestampMessageSent = timestamp
            }
        } else {
            self.timestampMessageSent = timestamp
        }
        
        // If the message has no attachment, we also set timestampAllAttachmentsSent
        if messageSent.fyleMessageJoinWithStatuses.isEmpty || alsoMarkAttachmentsAsSent {
            if self.timestampAllAttachmentsSent != timestamp {
                self.timestampAllAttachmentsSent = timestamp
            }
        }
        
        self.setAsCouldBeSentToServer()
        
        self.messageSent.refreshStatus()

    }


    public func setTimestampAllAttachmentsSentIfPossible() {
        guard self.timestampAllAttachmentsSent == nil else { return }
        let allAttachmentsAreComplete = messageSent.fyleMessageJoinWithStatuses.allSatisfy { $0.status == .complete }
        guard allAttachmentsAreComplete else { return }
        self.timestampAllAttachmentsSent = Date()
        self.setAsCouldBeSentToServer()
        self.messageSent.refreshStatus()
    }

    
    public func setAsCouldNotBeSentToServer() {
        guard timestampMessageSent == nil && timestampRead == nil && timestampDelivered == nil && timestampAllAttachmentsSent == nil else {
            assertionFailure()
            return
        }
        self.couldNotBeSentToServer = true
        self.messageSent.refreshStatus()
    }
    
    
    private func setAsCouldBeSentToServer() {
        if self.couldNotBeSentToServer {
            self.couldNotBeSentToServer = false
        }
    }

    
    private func messageWasDeliveredNoLaterThan(_ timestamp: Date, andRead: Bool) {

        messageWasSentNoLaterThan(timestamp, alsoMarkAttachmentsAsSent: true)

        if let currentTimeStamp = self.timestampDelivered {
            if currentTimeStamp > timestamp {
                self.timestampDelivered = timestamp
            }
        } else {
            self.timestampDelivered = timestamp
        }
        
        if andRead {
            if let currentTimeStamp = self.timestampRead {
                if currentTimeStamp > timestamp {
                    self.timestampRead = timestamp
                }
            } else {
                self.timestampRead = timestamp
            }
        }
     
        attachmentInfos.forEach { $0.attachmentWasUploaded() }
        
    }

    
    // MARK: - Convenience DB getters
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case couldNotBeSentToServer = "couldNotBeSentToServer"
            case messageIdentifierFromEngine = "messageIdentifierFromEngine"
            case recipientIdentity = "recipientIdentity"
            case returnReceiptKey = "returnReceiptKey"
            case returnReceiptNonce = "returnReceiptNonce"
            case timestampAllAttachmentsSent = "timestampAllAttachmentsSent"
            case timestampDelivered = "timestampDelivered"
            case timestampRead = "timestampRead"
            case timestampMessageSent = "timestampMessageSent"
            // Relationships
            case messageSent = "messageSent"
            // Others
            static let ownedIdentityIdentity = [
                messageSent.rawValue,
                PersistedMessage.Predicate.Key.discussion.rawValue,
                PersistedDiscussion.Predicate.Key.ownedIdentity.rawValue,
                PersistedObvOwnedIdentity.Predicate.Key.identity.rawValue,
            ].joined(separator: ".")
            static let discussion = [
                messageSent.rawValue,
                PersistedMessage.Predicate.Key.discussion.rawValue,
            ].joined(separator: ".")
        }
        static func withMessageSent(equalTo messageSent: PersistedMessageSent) -> NSPredicate {
            NSPredicate(Key.messageSent, equalTo: messageSent)
        }
        static func withMessageIdentifierFromEngine(equalTo messageIdentifierFromEngine: Data) -> NSPredicate {
            NSPredicate(Key.messageIdentifierFromEngine, EqualToData: messageIdentifierFromEngine)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func withRecipientIdentity(_ recipientIdentity: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.recipientIdentity, EqualToData: recipientIdentity.getIdentity())
        }
        static func withReturnReceiptNonce(_ returnReceiptNonce: Data) -> NSPredicate {
            NSPredicate(Key.returnReceiptNonce, EqualToData: returnReceiptNonce)
        }
        static var withNoMessageIdentifierFromEngine: NSPredicate {
            NSPredicate(withNilValueForKey: Key.messageIdentifierFromEngine)
        }
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            NSPredicate(Key.discussion, equalTo: discussion)
        }
        static var withoutTimestampDelivered: NSPredicate {
            NSPredicate(withNilValueForKey: Key.timestampDelivered)
        }
        static var withTimestampDelivered: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.timestampDelivered)
        }
        static func withTimestampDelivered(laterThan date: Date) -> NSPredicate {
            NSPredicate(Key.timestampDelivered, laterThan: date)
        }
        static var withoutTimestampMessageSent: NSPredicate {
            NSPredicate(withNilValueForKey: Key.timestampMessageSent)
        }
        static func withTimestampMessageSent(laterThan date: Date) -> NSPredicate {
            NSPredicate(Key.timestampMessageSent, laterThan: date)
        }
        static var withoutTimestampRead: NSPredicate {
            NSPredicate(withNilValueForKey: Key.timestampRead)
        }
        static var withTimestampRead: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.timestampRead)
        }
        static func withTimestampRead(laterThan date: Date) -> NSPredicate {
            NSPredicate(Key.timestampRead, laterThan: date)
        }
        static var withoutTimestampAllAttachmentsSent: NSPredicate {
            NSPredicate(withNilValueForKey: Key.timestampAllAttachmentsSent)
        }
        static var withTimestampAllAttachmentsSent: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.timestampAllAttachmentsSent)
        }
        static func withRecipientIdentifier(_ recipientIdentifier: ObvContactIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.withOwnedCryptoId(recipientIdentifier.ownedCryptoId),
                Self.withRecipientIdentity(recipientIdentifier.contactCryptoId),
            ])
        }
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<PersistedMessageSentRecipientInfos>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageSentRecipientInfos> {
        return NSFetchRequest<PersistedMessageSentRecipientInfos>(entityName: PersistedMessageSentRecipientInfos.entityName)
    }


    public static func getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withMessageIdentifierFromEngine(equalTo: messageIdentifierFromEngine),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        return try context.fetch(request)
    }


    public static func getAllPersistedMessageSentRecipientInfosWithoutTimestampMessageSentAndMatching(messageIdentifierFromEngine: Data, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withoutTimestampMessageSent,
            Predicate.withMessageIdentifierFromEngine(equalTo: messageIdentifierFromEngine),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        return try context.fetch(request)
    }

    /// Returns all the `PersistedMessageSentRecipientInfos` that are still unprocessed, i.e., that have no message identifier from the engine.
    public static func getAllUnprocessed(within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = Predicate.withNoMessageIdentifierFromEngine
        return try context.fetch(request)
    }

    
    public static func getAllUnprocessedForSpecificContact(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [PersistedMessageSentRecipientInfos] {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withNoMessageIdentifierFromEngine,
            Predicate.withRecipientIdentity(contactCryptoId),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        return try context.fetch(request)
    }

    
    static func getAllUnprocessedForContact(contactCryptoId: ObvCryptoId, forMessagesWithinDiscussion discussion: PersistedDiscussion) throws -> [PersistedMessageSentRecipientInfos] {
        guard let context = discussion.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withNoMessageIdentifierFromEngine,
            Predicate.withRecipientIdentity(contactCryptoId),
            Predicate.withinDiscussion(discussion),
        ])
        return try context.fetch(request)
    }

    
    /// When receiving an encrypted ObvReturnReceipt, the first thing we do is to try to decrypt it. This is performed by an operation that is *not* exectued on the coordinators queue. This operation calls
    /// this method to obtain a set of decryption key candidates.
    public static func getDecryptionKeyCandidatesForReceivedReturnReceipt(nonce: Data, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Set<Data> {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [Predicate.Key.returnReceiptKey.rawValue]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withReturnReceiptNonce(nonce),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        guard let results = try context.fetch(request) as? [[String: Data]] else { assertionFailure(); throw ObvUICoreDataError.couldNotCastFetchedResult }
        let keys = try results.map { dict in
            guard let key = dict[Predicate.Key.returnReceiptKey.rawValue] else { assertionFailure(); throw ObvUICoreDataError.couldNotCastFetchedResult }
            return key
        }
        return Set(keys)
    }
    
    
    public static func markSentMessageAsCouldNotBeSentToServer(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngine: Data, within context: NSManagedObjectContext) throws {
        
        let infos = try PersistedMessageSentRecipientInfos.getAllPersistedMessageSentRecipientInfos(
            messageIdentifierFromEngine: messageIdentifierFromEngine,
            ownedCryptoId: ownedCryptoId,
            within: context)
        
        guard !infos.isEmpty else {
            // No info found, so there is nothing to do
            return
        }
        
        for info in infos {
            info.setAsCouldNotBeSentToServer()
        }

    }
    
    
    public static func setTimestampAllAttachmentsSentIfPossibleOfPersistedMessageSentRecipientInfos(ownedCryptoId: ObvCryptoId, messageIdentifiersFromEngine: [Data], within context: NSManagedObjectContext) throws {

        for messageIdentifierFromEngine in messageIdentifiersFromEngine {
            
            let infos = try PersistedMessageSentRecipientInfos.getAllPersistedMessageSentRecipientInfos(messageIdentifierFromEngine: messageIdentifierFromEngine, ownedCryptoId: ownedCryptoId, within: context)
            guard !infos.isEmpty else {
                continue
            }
            
            for info in infos {
                info.setTimestampAllAttachmentsSentIfPossible()
            }
            
        }

    }
    
    
    /// This method not only marks the appropriate `SentFyleMessageJoinWithStatus` as complete, it also marks all the appropriate `PersistedAttachmentSentRecipientInfos` as complete too.
    /// It shall only be called when the associated sent message was sent from the **current** device.
    ///
    /// - Parameters:
    ///   - messageIdentifierFromEngine: The message identifier from the engine. If this identifier corresponds to more than one `PersistedMessageSent`, the result of this operation is not properly defined. But this case is very unlikely.
    ///   - restrictToAttachmentNumbers: If `nil`, all attachments are considered. Otherwise, only the specified attachments are considered.
    public static func markSentFyleMessageJoinWithStatusAsFullyUploadedByCurrentDevice(
        ownedCryptoId: ObvCryptoId,
        messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo: [(messageIdentifierFromEngine: Data, restrictToAttachmentNumbers: [Int]?)],
        within context: NSManagedObjectContext) throws {
        
        for (messageIdentifierFromEngine, restrictToAttachmentNumbers) in messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo {
            
            let infos = try PersistedMessageSentRecipientInfos.getAllPersistedMessageSentRecipientInfos(
                messageIdentifierFromEngine: messageIdentifierFromEngine,
                ownedCryptoId: ownedCryptoId,
                within: context)
            guard !infos.isEmpty, let persistedMessageSent = infos.first?.messageSent else {
                continue
            }
            
            guard persistedMessageSent.isSentFromCurrentDevice else {
                Self.logger.fault("This method shall only be called from messages sent from the current device, but it is called on a message sent from another owned device.")
                assertionFailure()
                throw ObvUICoreDataError.shouldNotBeCalledOnMessageSentFromAnotherOwnedDevice
            }
            
            let attachmentNumbers: [Int]
            if let restrictToAttachmentNumbers {
                attachmentNumbers = restrictToAttachmentNumbers
            } else {
                attachmentNumbers = Array(0..<persistedMessageSent.fyleMessageJoinWithStatuses.count)
            }
            
            for attachmentNumber in attachmentNumbers {
                // Mark all the approprate `PersistedAttachmentSentRecipientInfos` as complete
                infos.forEach { info in
                    info.attachmentInfos.first(where: { $0.index == attachmentNumber })?.attachmentWasUploaded()
                }
                
                guard attachmentNumber < persistedMessageSent.fyleMessageJoinWithStatuses.count else {
                    assertionFailure()
                    continue
                }
                
                // Mark the appropriate `SentFyleMessageJoinWithStatus` as complete
                let fyleMessageJoinWithStatus = persistedMessageSent.fyleMessageJoinWithStatuses[attachmentNumber]
                fyleMessageJoinWithStatus.markAsFullyUploadedByCurrentDevice()
            }
            
        } // End of for (messageIdentifierFromEngine, restrictToAttachmentNumbers) in messageIdentifierFromEngineAndAttachmentNumbersToRestrictTo

    }
    
    
    public static func markMessageWasSentNoLaterThan(ownedCryptoId: ObvCryptoId, messageIdentifierFromEngineAndTimestampFromServer: [(messageIdentifierFromEngine: Data, timestampFromServer: Date)], alsoMarkAttachmentsAsSent: Bool, within context: NSManagedObjectContext) throws {
        
        for (messageIdentifierFromEngine, timestampFromServer) in messageIdentifierFromEngineAndTimestampFromServer {
            
            let infos = try PersistedMessageSentRecipientInfos.getAllPersistedMessageSentRecipientInfosWithoutTimestampMessageSentAndMatching(
                messageIdentifierFromEngine: messageIdentifierFromEngine,
                ownedCryptoId: ownedCryptoId,
                within: context)
            
            // Note that the infos list may be empty for that messageIdentifierFromEngine and owned identity.
            // Since we now (2022-02-24) also filter out infos that already have a timestampMessageSent, this is not an issue.
            
            infos.forEach {
                $0.messageWasSentNoLaterThan(timestampFromServer, alsoMarkAttachmentsAsSent: alsoMarkAttachmentsAsSent)
            }
            
        }
        
    }
    
    
    public static func deleteRecipientInfosThatHaveNoMsgIdentifierFromEngineAndAssociatedToDeletedContact(within context: NSManagedObjectContext) throws {
        
        let infos: [PersistedMessageSentRecipientInfos] = try PersistedMessageSentRecipientInfos.getAllUnprocessed(within: context)

        var infosWithDeletedContact = [PersistedMessageSentRecipientInfos]()
        for info in infos {
            do {
                let recipient = try info.getRecipient()
                if recipient == nil {
                    infosWithDeletedContact.append(info)
                }
            } catch {
                os_log("Could not get contact: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // We continue anyway
            }
        }
        
        guard !infosWithDeletedContact.isEmpty else { return }
        
        let associatedSentMessages = infosWithDeletedContact.map({ $0.messageSent })
        
        for info in infosWithDeletedContact {
            context.delete(info)
        }
        
        for message in associatedSentMessages {
            message.refreshStatus()
        }
                
    }
    
    
    /// This method deletes all `PersistedMessageSentRecipientInfos` instances associated to the contact identity the that have no `messageIdentifierFromEngine`. It appropriately recompute the status of the associated messages.
    ///
    /// This operation is called when a contact is deleted. Yet, we do not test whether the contact is indeed deleted since, when receiving the information from the engine, the `PersistedObvContactIdentity` might not have been deleted already.
    public static func deletePersistedMessageSentRecipientInfosWithoutMessageIdentifierFromEngineAndAssociatedToContactIdentity(contactIdentifier: ObvContactIdentifier, within context: NSManagedObjectContext) throws {
        
        let infos: [PersistedMessageSentRecipientInfos] = try PersistedMessageSentRecipientInfos.getAllUnprocessedForSpecificContact(contactCryptoId: contactIdentifier.contactCryptoId, ownedCryptoId: contactIdentifier.ownedCryptoId, within: context)
        
        guard !infos.isEmpty else { return }
        
        let associatedSentMessages = infos.map({ $0.messageSent })
        
        for info in infos {
            context.delete(info)
        }
        
        for message in associatedSentMessages {
            message.refreshStatus()
        }
        
    }
    
    
    /// Processes an `ObvDecryptedReceivedReturnReceipt` and updates the relevant objects.
    ///
    /// The updated objects are expected instances of one of the following `NSManagedObject` subclasses:
    /// - `PersistedMessageSentRecipientInfos`
    /// - `PersistedAttachmentSentRecipientInfos`
    /// - `PersistedMessageSent`
    /// - `SentFyleMessageJoinWithStatus`
    ///
    /// **In practice**
    /// - The caller typically provides a temporary "read-only" background context, which is **not saved**.
    /// - Required changes (updates or deletes) are collected and stored for later replay.
    /// - These changes are applied asynchronously on the appropriate queues for efficiency and thread safety.
    public static func processDecryptedReceivedReturnReceipt(decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt, within context: NSManagedObjectContext) throws {

        var messageSentToRefresh: PersistedMessageSent?
        
        // The return receipt might concern an attachment, but we consider it concerns a message
        
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        
        var andPredicates: [NSPredicate] = [
            Predicate.withRecipientIdentifier(decryptedReceivedReturnReceipt.contactIdentifier),
            Predicate.withReturnReceiptNonce(decryptedReceivedReturnReceipt.nonce),
        ]
        switch decryptedReceivedReturnReceipt.status {
        case .delivered:
            let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.withoutTimestampDelivered,
                Predicate.withTimestampDelivered(laterThan: decryptedReceivedReturnReceipt.timestamp),
            ])
            andPredicates.append(predicate)
        case .read:
            let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                Predicate.withoutTimestampRead,
                Predicate.withTimestampRead(laterThan: decryptedReceivedReturnReceipt.timestamp),
            ])
            andPredicates.append(predicate)
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
        
        request.fetchLimit = 1
        
        if let infos = try context.fetch(request).first {
            
            let andRead: Bool
            switch decryptedReceivedReturnReceipt.status {
            case .delivered:
                andRead = false
            case .read:
                andRead = true
            }
            
            infos.messageWasDeliveredNoLaterThan(decryptedReceivedReturnReceipt.timestamp, andRead: andRead)
            
            //messageInfosToMarkAsDelivered = infos.hasChanges ? (infos.typedObjectID, andRead) : nil
            
            if messageSentToRefresh == nil && infos.hasChanges {
                messageSentToRefresh = infos.messageSent
            }
            
            // If a message was delivered to a recipient, and if the message is sent from the current device, we know we should mark all the attachments as "sent" (i.e., complete)
            if let messageSentToRefresh, messageSentToRefresh.isSentFromCurrentDevice {
                _ = messageSentToRefresh.markAllFyleMessageJoinWithStatusesAsFullyUploadedByCurrentDevice()
            }
                        
            // If a message was delivered to a recipient, we know it was at least stored on the server for all other infos with the same message identifier
            // from server. So we set the sent timestamp for those recipients.

            if let messageIdentifierFromEngine = infos.messageIdentifierFromEngine {
                let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
                request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                    Predicate.withMessageSent(equalTo: infos.messageSent),
                    Predicate.withMessageIdentifierFromEngine(equalTo: messageIdentifierFromEngine),
                    NSCompoundPredicate(orPredicateWithSubpredicates: [
                        Predicate.withoutTimestampMessageSent,
                        Predicate.withTimestampMessageSent(laterThan: decryptedReceivedReturnReceipt.timestamp),
                    ]),
                ])
                request.fetchBatchSize = 100
                let otherInfos = try context.fetch(request)
                for otherInfo in otherInfos {
                    otherInfo.messageWasSentNoLaterThan(decryptedReceivedReturnReceipt.timestamp, alsoMarkAttachmentsAsSent: true)
                    if messageSentToRefresh == nil && otherInfo.hasChanges {
                        messageSentToRefresh = otherInfo.messageSent
                    }
                }
            }

        }

        // If the return receipts concerns an attachment, we also want to update the appropriate PersistedAttachmentSentRecipientInfos
        
        if let attachmentNumber = decryptedReceivedReturnReceipt.attachmentNumber {
            
            // The receipt concerns an attachment

            let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withRecipientIdentifier(decryptedReceivedReturnReceipt.contactIdentifier),
                Predicate.withReturnReceiptNonce(decryptedReceivedReturnReceipt.nonce),
            ])
            request.fetchLimit = 1
            
            if let messageInfos: PersistedMessageSentRecipientInfos = try context.fetch(request).first,
                let attachmentInfos: PersistedAttachmentSentRecipientInfos = messageInfos.attachmentInfos.first(where: { $0.index == attachmentNumber }) {
                
                let andRead: Bool
                switch decryptedReceivedReturnReceipt.status {
                case .delivered:
                    andRead = false
                case .read:
                    andRead = true
                }
                
                attachmentInfos.attachmentWasDelivered(andRead: andRead)
                
                let attachmentInfosToMarkAsDelivered = attachmentInfos.hasChanges ? (attachmentInfos.typedObjectID, andRead) : nil
                
                // If the infos were changed for the recipient, we might have to update the global status for this attachment.
                
                if attachmentInfosToMarkAsDelivered != nil {
                    
                    _ = messageInfos.messageSent.refreshStatusOfSentFyleMessageJoinWithStatus(atIndex: attachmentNumber)
                                            
                }
                
            }
            
        }
                
        // If we reach this point, we might need to refresh the sent message status
        
        if let messageSentToRefresh {
            messageSentToRefresh.refreshStatus()
        }
        
    }
    
    
    public static func getPersistedMessageSentRecipientInfos(objectID: TypeSafeManagedObjectID<PersistedMessageSentRecipientInfos>, within context: NSManagedObjectContext) throws -> PersistedMessageSentRecipientInfos? {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    

    /// Before version 3.1, we could end up in a situation where a sent message was considered as delivered for a recipient (i.e., `timestampDelivered != nil`) but not sent (i.e., `timestampMessageSent != nil`),
    /// which makes no sense. This method, exclusively called from ``ConsolidateLegacyTimestampsOfPersistedMessageSentRecipientInfosOperation``, consolidates all the timestamps.
    public static func consolidateLegacyTimestamps(within context: NSManagedObjectContext, maxNumberOfChanges: Int) throws {
        
        var numberOfChanges = 0
        
        do {
            let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withoutTimestampDelivered,
                Predicate.withTimestampRead,
            ])
            request.includesPendingChanges = true
            request.fetchLimit = maxNumberOfChanges
            let infos = try context.fetch(request)
            for info in infos {
                guard info.timestampDelivered == nil && info.timestampRead != nil else { assertionFailure(); continue }
                info.timestampDelivered = info.timestampRead
                numberOfChanges += 1
                guard numberOfChanges < maxNumberOfChanges else {
                    return
                }
            }
        }

        do {
            let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    Predicate.withoutTimestampMessageSent,
                    Predicate.withoutTimestampAllAttachmentsSent,
                ]),
                Predicate.withTimestampDelivered,
            ])
            request.includesPendingChanges = true
            request.fetchLimit = max(0, maxNumberOfChanges-numberOfChanges)
            let infos = try context.fetch(request)
            for info in infos {
                guard info.timestampDelivered != nil else { assertionFailure(); continue }
                var changeMade = false
                if info.timestampMessageSent == nil {
                    info.timestampMessageSent = info.timestampDelivered
                    changeMade = true
                }
                if info.timestampAllAttachmentsSent == nil {
                    info.timestampAllAttachmentsSent = info.timestampDelivered
                    changeMade = true
                }
                assert(info.messageAndAttachmentsAreSent)
                if changeMade {
                    numberOfChanges += 1
                    guard numberOfChanges < maxNumberOfChanges else {
                        return
                    }
                }
            }
        }

    }

}
