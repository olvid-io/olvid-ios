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
import ObvEngine
import ObvCrypto
import os.log
import ObvTypes
import OlvidUtils
import ObvSettings


@objc(PersistedMessageSentRecipientInfos)
public final class PersistedMessageSentRecipientInfos: NSManagedObject {
    
    private static let entityName = "PersistedMessageSentRecipientInfos"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedMessageSentRecipientInfos")
    
    // MARK: Attributes

    @NSManaged public private(set) var couldNotBeSentToServer: Bool // Set to true if the engine could not send message during 30 days
    @NSManaged public private(set) var messageIdentifierFromEngine: Data?
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
            throw ObvUICoreDataError.discussionIsNil
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
        self.messageIdentifierFromEngine = nil
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
    

    public func messageWasSentNoLaterThan(_ timestamp: Date, alsoMarkAttachmentsAsSent: Bool) {
        
        if let currentTimeStamp = self.timestampMessageSent, currentTimeStamp != min(timestamp, currentTimeStamp) {
            self.timestampMessageSent = min(timestamp, currentTimeStamp)
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

        if let currentTimeStamp = self.timestampDelivered, currentTimeStamp != min(timestamp, currentTimeStamp) {
            self.timestampDelivered = min(timestamp, currentTimeStamp)
        } else {
            self.timestampDelivered = timestamp
        }
        
        if andRead {
            if let currentTimeStamp = self.timestampRead, currentTimeStamp != min(timestamp, currentTimeStamp) {
                self.timestampRead = min(timestamp, currentTimeStamp)
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
    
    
    /// Exclusively called by the `ComputeHintsForGivenDecryptedReceivedReturnReceiptOperation`.
    public static func computeHintsForProcessingDecryptedReceivedReturnReceipt(decryptedReceivedReturnReceipt: ObvDecryptedReceivedReturnReceipt, within context: NSManagedObjectContext) throws -> HintsForProcessingDecryptedReceivedReturnReceipt {

        let messageInfosToMarkAsDelivered: (TypeSafeManagedObjectID<PersistedMessageSentRecipientInfos>, andRead: Bool)?
        let attachmentInfosToMarkAsDelivered: (TypeSafeManagedObjectID<PersistedAttachmentSentRecipientInfos>, andRead: Bool)?
        var messageInfosToMarkAsSent = Set<TypeSafeManagedObjectID<PersistedMessageSentRecipientInfos>>()
        let messageToRefresh: (messageSent: TypeSafeManagedObjectID<PersistedMessageSent>, newStatus: PersistedMessageSent.MessageStatus)?
        let sentFyleMessageJoinWithStatusToRefresh: (sentFyleMessageJoinWithStatus: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, newReceptionStatus: SentFyleMessageJoinWithStatus.FyleReceptionStatus)?
        var markAsCompleteAllSentFyleMessageJoinWithStatusOfRefreshedMessage = false
        
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
            
            messageInfosToMarkAsDelivered = infos.hasChanges ? (infos.typedObjectID, andRead) : nil
            
            if messageSentToRefresh == nil && infos.hasChanges {
                messageSentToRefresh = infos.messageSent
            }
            
            // If a message was delivered to a recipient, we know we should mark all the attachments as "sent" (i.e., complete)

            if let messageSentToRefresh {
                let joins = messageSentToRefresh.markAllFyleMessageJoinWithStatusesAsComplete()
                markAsCompleteAllSentFyleMessageJoinWithStatusOfRefreshedMessage = !joins.filter({ $0.hasChanges }).isEmpty
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
                    if otherInfo.hasChanges {
                        messageInfosToMarkAsSent.insert(otherInfo.typedObjectID)
                    }
                    if messageSentToRefresh == nil && otherInfo.hasChanges {
                        messageSentToRefresh = otherInfo.messageSent
                    }
                }
            }

        } else {
            messageInfosToMarkAsDelivered = nil
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
                
                attachmentInfosToMarkAsDelivered = attachmentInfos.hasChanges ? (attachmentInfos.typedObjectID, andRead) : nil
                
                // If the infos were changed for the recipient, we might have to update the global status for this attachment.
                
                if attachmentInfosToMarkAsDelivered != nil {
                    
                    if let refreshedJoin: SentFyleMessageJoinWithStatus = messageInfos.messageSent.refreshStatusOfSentFyleMessageJoinWithStatus(atIndex: attachmentNumber) {
                        sentFyleMessageJoinWithStatusToRefresh = refreshedJoin.hasChanges ? (refreshedJoin.typedObjectID, refreshedJoin.receptionStatus) : nil
                    } else {
                        sentFyleMessageJoinWithStatusToRefresh = nil
                    }
                                            
                } else {
                    
                    sentFyleMessageJoinWithStatusToRefresh = nil
                    
                }
                
            } else {
                
                attachmentInfosToMarkAsDelivered = nil
                sentFyleMessageJoinWithStatusToRefresh = nil
                
            }
            
        } else {
            
            // The receipt does not concern an attachment
            
            attachmentInfosToMarkAsDelivered = nil
            sentFyleMessageJoinWithStatusToRefresh = nil

        }
                
        // If we reach this point, we might need to refresh the sent message status
        
        if let messageSentToRefresh {
            messageSentToRefresh.refreshStatus()
            messageToRefresh = messageSentToRefresh.hasChanges ? (messageSentToRefresh.typedObjectID, messageSentToRefresh.status) : nil
        } else {
            messageToRefresh = nil
        }
        
        // Return the hints
        
        let hints = HintsForProcessingDecryptedReceivedReturnReceipt(
            serverTimestamp: decryptedReceivedReturnReceipt.timestamp,
            messageInfosToMarkAsDelivered: messageInfosToMarkAsDelivered,
            messageInfosToMarkAsSent: messageInfosToMarkAsSent,
            attachmentInfosToMarkAsDelivered: attachmentInfosToMarkAsDelivered,
            messageToRefresh: messageToRefresh,
            sentFyleMessageJoinWithStatusToRefresh: sentFyleMessageJoinWithStatusToRefresh,
            markAsCompleteAllSentFyleMessageJoinWithStatusOfRefreshedMessage: markAsCompleteAllSentFyleMessageJoinWithStatusOfRefreshedMessage)
        
        return hints

    }
    
    
    private static func getPersistedMessageSentRecipientInfos(objectID: TypeSafeManagedObjectID<PersistedMessageSentRecipientInfos>, within context: NSManagedObjectContext) throws -> PersistedMessageSentRecipientInfos? {
        let request: NSFetchRequest<PersistedMessageSentRecipientInfos> = PersistedMessageSentRecipientInfos.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    /// Exclusively called from `ApplyHintsForProcessingDecryptedReceivedReturnReceiptOperation`.
    public static func applyHintsForProcessingDecryptedReceivedReturnReceipt(hints: HintsForProcessingDecryptedReceivedReturnReceipt, within context: NSManagedObjectContext) throws {
        
        if let (messageInfosToMarkAsDelivered, andRead) = hints.messageInfosToMarkAsDelivered {
            let infos = try Self.getPersistedMessageSentRecipientInfos(objectID: messageInfosToMarkAsDelivered, within: context)
            infos?.messageWasDeliveredNoLaterThan(hints.serverTimestamp, andRead: andRead)
        }
        
        for messageInfosToMarkAsSent in hints.messageInfosToMarkAsSent {
            let otherInfo = try Self.getPersistedMessageSentRecipientInfos(objectID: messageInfosToMarkAsSent, within: context)
            otherInfo?.messageWasSentNoLaterThan(hints.serverTimestamp, alsoMarkAttachmentsAsSent: true)
        }
        
        if let (attachmentInfosToMarkAsDelivered, andRead) = hints.attachmentInfosToMarkAsDelivered {
            let attachmentInfos = try PersistedAttachmentSentRecipientInfos.getPersistedMessageSentRecipientInfos(objectID: attachmentInfosToMarkAsDelivered, within: context)
            attachmentInfos?.attachmentWasDelivered(andRead: andRead)
        }
        
        if let (sentFyleMessageJoinWithStatus, newReceptionStatus) = hints.sentFyleMessageJoinWithStatusToRefresh {
            let sentFyleMessageJoinWithStatusToRefresh = try SentFyleMessageJoinWithStatus.getSentFyleMessageJoinWithStatus(objectID: sentFyleMessageJoinWithStatus, within: context)
            sentFyleMessageJoinWithStatusToRefresh?.tryToSetReceptionStatusTo(newReceptionStatus)
        }
        
        if let (messageSent, newStatus) = hints.messageToRefresh {
            let messageSentToRefresh = try PersistedMessageSent.getPersistedMessageSent(objectID: messageSent, within: context)
            messageSentToRefresh?.setStatusOnApplyingHintOnPersistedMessageSentRecipientInfos(newStatus: newStatus)
            if hints.markAsCompleteAllSentFyleMessageJoinWithStatusOfRefreshedMessage {
                _ = messageSentToRefresh?.markAllFyleMessageJoinWithStatusesAsComplete()
            }
        }
        
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


// MARK: - HintsForProcessingDecryptedReceivedReturnReceipt

public struct HintsForProcessingDecryptedReceivedReturnReceipt {

    let serverTimestamp: Date
    
    /// There is one `PersistedMessageSentRecipientInfos` per recipient (contact) of a sent message. When receiving a return receipt, it comes from one of those
    /// recipients (from one of their device, but we do not distinguish between devices). It can either be a "read" receipt (in which case `andRead` is `true`), or a reception receipt.
    let messageInfosToMarkAsDelivered: (TypeSafeManagedObjectID<PersistedMessageSentRecipientInfos>, andRead: Bool)?
    
    /// If a recipient (contact) sends us back a return receipt, we know the message was received by the server of this recipient and thus, "sent" to all recipients sharing the same server.
    /// This set stores all the `PersistedMessageSentRecipientInfos` corresponding to the recipients for which we can mark the message as "sent" (i.e., received by the server).
    let messageInfosToMarkAsSent: Set<TypeSafeManagedObjectID<PersistedMessageSentRecipientInfos>>
    
    /// There is one `PersistedMessageSentRecipientInfos` per recipient (contact) of a sent message. For each of these message infos, there is one `PersistedAttachmentSentRecipientInfos`
    /// per attachment. When receiving a return receipt for a specific attachment from on of those recipients, we mark the attachment as delivered to this recipient (and "read", if the receipt is a "read" receipt).
    let attachmentInfosToMarkAsDelivered: (TypeSafeManagedObjectID<PersistedAttachmentSentRecipientInfos>, andRead: Bool)?
    
    
    /// The change of a `PersistedMessageSentRecipientInfos` can have an impact on the whole status of the corresponding sent message. If this is the case, `messageToRefresh`
    /// is non-nil.
    let messageToRefresh: (messageSent: TypeSafeManagedObjectID<PersistedMessageSent>, newStatus: PersistedMessageSent.MessageStatus)?
    
    
    /// The change of a `PersistedAttachmentSentRecipientInfos` can have an impact on the whole status of the corresponding attachment of the sent message. In this case, `sentFyleMessageJoinWithStatusToRefresh`
    /// is non-nil.
    let sentFyleMessageJoinWithStatusToRefresh: (sentFyleMessageJoinWithStatus: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, newReceptionStatus: SentFyleMessageJoinWithStatus.FyleReceptionStatus)?
    
    
    /// Since recipients are notified that a message is available only after all attachments have been sent to the server, we know we can mark all attachments as "sent" (i.e., complete) when receiving a return receipt.
    /// Note that this is an imprecise reasoning, in particular when considering contacts on distinct server. Here, we  consider that attachments should be shown as "sent" if there were successfully sent to at least one server.
    /// This constant can only be true if `messageToRefresh` is non-nil.
    let markAsCompleteAllSentFyleMessageJoinWithStatusOfRefreshedMessage: Bool

    public var receivedReturnReceiptRequiresProcessing: Bool {
        messageInfosToMarkAsDelivered != nil || attachmentInfosToMarkAsDelivered != nil || !messageInfosToMarkAsSent.isEmpty || messageToRefresh != nil || sentFyleMessageJoinWithStatusToRefresh != nil
    }
    
}
