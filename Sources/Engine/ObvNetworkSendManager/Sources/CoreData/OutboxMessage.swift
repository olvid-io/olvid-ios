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
import OSLog
import ObvEncoder
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

@objc(OutboxMessage)
final class OutboxMessage: NSManagedObject, ObvErrorMaker {
    
    // MARK: Internal constants
    
    private static let entityName = "OutboxMessage"
    static let errorDomain = "OutboxMessage"
    static weak var delegateManager: ObvNetworkSendDelegateManager?

    // MARK: Attributes
    
    @NSManaged private(set) var cancelExternallyRequested: Bool
    @NSManaged private var rawEncryptedContent: Data? // Non-optional in the model
    @NSManaged private var rawEncryptedExtendedMessagePayload: Data?
    @NSManaged private(set) var isAppMessageWithUserContent: Bool
    @NSManaged private(set) var isVoipMessage: Bool
    @NSManaged private(set) var creationDate: Date // Local item creation timestamp
    @NSManaged private(set) var nonceFromServer: Data?
    @NSManaged private var rawMessageIdOwnedIdentity: Data
    @NSManaged private var rawMessageIdUid: Data
    @NSManaged private var rawMessageUidFromServer: Data?
    @NSManaged private(set) var serverURL: URL
    @NSManaged private(set) var timestampFromServer: Date?
    @NSManaged private(set) var uploaded: Bool
        
    // MARK: Relationships
    
    @NSManaged var headers: Set<MessageHeader>
    
    private var unsortedAttachments: Set<OutboxAttachment> {
        get {
            let items = kvoSafePrimitiveValue(forKey: Predicate.Key.unsortedAttachments.rawValue) as! Set<OutboxAttachment>
            return Set(items)
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.unsortedAttachments.rawValue)
        }
    }

    var attachments: [OutboxAttachment] {
        switch unsortedAttachments.count {
        case 0:
            return []
        case 1:
            return [unsortedAttachments.first!]
        default:
            return unsortedAttachments.sorted(by: { $0.attachmentNumber < $1.attachmentNumber })
        }
    }
    
    var hasAttachments: Bool {
        !unsortedAttachments.isEmpty
    }

    // MARK: Other variables
    
    var encryptedContent: EncryptedData {
        get throws(ObvError) {
            guard let rawEncryptedContent else { assertionFailure(); throw .unexpectedNilValue }
            return EncryptedData(data: rawEncryptedContent)
        }
    }
    
    /// Expected to be non-nil. We never allow setting this identifier to `nil`.
    private(set) var messageId: ObvMessageIdentifier? {
        get {
            guard !isDeleted else { return nil }
            return ObvMessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw
        }
    }
    
    /// Always `nil`, unless this outbox message get deleted
    private var messageIdWhenDeleted: ObvMessageIdentifier?
    
    private(set) var messageUidFromServer: UID? {
        get { guard let uid = self.rawMessageUidFromServer else { return nil };  return UID(uid: uid) }
        set { self.rawMessageUidFromServer = newValue?.raw }
    }
    
    var canBeDeleted: Bool {
        let allAttachmentsCanBeDeleted = attachments.allSatisfy({ $0.canBeDeleted })
        return allAttachmentsCanBeDeleted && (uploaded || cancelExternallyRequested)
    }
    
    /// This method deletes `self`.
    func deleteThisOutboxMessage() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not delete OuboxMessage as its context is nil") }
        self.messageIdWhenDeleted = self.messageId
        context.delete(self)
    }
    
    private(set) var encryptedExtendedMessagePayload: EncryptedData? {
        get {
            guard let data = rawEncryptedExtendedMessagePayload else { return nil }
            return EncryptedData(data: data)
        }
        set {
            self.rawEncryptedExtendedMessagePayload = newValue?.raw
        }
    }
    
    // MARK: - Initializer
    
    convenience init?(messageId: ObvMessageIdentifier, serverURL: URL, encryptedContent: EncryptedData, encryptedExtendedMessagePayload: EncryptedData?, isAppMessageWithUserContent: Bool, isVoipMessage: Bool, within context: NSManagedObjectContext) {
        
        do {
            guard try OutboxMessage.get(messageId: messageId, within: context) == nil else { assertionFailure(); return nil }
        } catch {
            assertionFailure()
            return nil
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: OutboxMessage.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.rawEncryptedContent = encryptedContent.raw
        self.encryptedExtendedMessagePayload = encryptedExtendedMessagePayload
        self.messageId = messageId
        self.serverURL = serverURL
        self.isAppMessageWithUserContent = isAppMessageWithUserContent
        self.isVoipMessage = isVoipMessage
        self.creationDate = Date()
        self.unsortedAttachments = Set<OutboxAttachment>()
    }
    
    enum ObvError: Error {
        case unexpectedNilValue
    }

}


// MARK: - Managing proofs of work

extension OutboxMessage {
    
    // MARK: - Other stuff
    
    func cancelUpload() {
        guard !self.cancelExternallyRequested else { return }
        self.cancelExternallyRequested = true
    }
    
    func setAcknowledged(withMessageUidFromServer messageUidFromServer: UID, nonceFromServer: Data, andTimeStampFromServer timestampFromServer: Date) {
        uploaded = true
        self.messageUidFromServer = messageUidFromServer
        self.nonceFromServer = nonceFromServer
        self.timestampFromServer = timestampFromServer
    }
    
    func resetForResend() throws {
        messageUidFromServer = nil
        nonceFromServer = nil
        uploaded = false
        for attachment in attachments {
            try attachment.resetForResend()
        }
    }
    
    // MARK: - Setting signed URLs
    
    /// We expect one array of URLs per attachment
    func setAttachmentUploadPrivateUrls(_ urls: [[URL]]) throws {
        assert(urls.count == attachments.count)
        guard urls.count == attachments.count else { throw OutboxMessage.makeError(message: "Unexpected private urls count") }
        for (attachment, signedURLs) in zip(self.attachments, urls) {
            try attachment.setChunkUploadSignedUrls(signedURLs)
        }
    }

}


// MARK: - Convenience DB getters

extension OutboxMessage {
    
    struct Predicate {
        
        enum Key: String {
            case cancelExternallyRequested = "cancelExternallyRequested"
            case rawEncryptedContent = "rawEncryptedContent"
            case rawEncryptedExtendedMessagePayload = "rawEncryptedExtendedMessagePayload"
            case isAppMessageWithUserContent = "isAppMessageWithUserContent"
            case isVoipMessage = "isVoipMessage"
            case creationDate = "creationDate"
            case nonceFromServer = "nonceFromServer"
            case rawMessageIdOwnedIdentity = "rawMessageIdOwnedIdentity"
            case rawMessageIdUid = "rawMessageIdUid"
            case rawMessageUidFromServer = "rawMessageUidFromServer"
            case serverURL = "serverURL"
            case timestampFromServer = "timestampFromServer"
            case uploaded = "uploaded"
            case unsortedAttachments = "unsortedAttachments"
        }
        
        static func withMessageId(_ messageId: ObvMessageIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawMessageIdOwnedIdentity, EqualToData: messageId.ownedCryptoIdentity.getIdentity()),
                NSPredicate(Key.rawMessageIdUid, EqualToData: messageId.uid.raw),
            ])
        }
        
        static func uploaded(is uploaded: Bool) -> NSPredicate {
            NSPredicate(Key.uploaded, is: uploaded)
        }
        
        static func creationDateIsEarlierThan(_ date: Date) -> NSPredicate {
            NSPredicate(Key.creationDate, earlierThan: date)
        }
        
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawMessageIdOwnedIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
        
        static func withServerURL(serverURL url: URL) -> NSPredicate {
            NSPredicate(Key.serverURL, EqualToUrl: url)
        }
        
        static var withNoAttachments: NSPredicate {
            NSPredicate(withCount: 0, forKey: Predicate.Key.unsortedAttachments)
        }
        
    }
    
    
    

    @nonobjc class func fetchRequest() -> NSFetchRequest<OutboxMessage> {
        return NSFetchRequest<OutboxMessage>(entityName: OutboxMessage.entityName)
    }

    static func get(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws -> OutboxMessage? {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageId(messageId)
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item
    }
    
    static func getAll(within context: NSManagedObjectContext) throws -> [OutboxMessage] {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        let items = try context.fetch(request)
        return items
    }
    
    static func getAllUploaded(within context: NSManagedObjectContext) throws -> [OutboxMessage] {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        request.predicate = Predicate.uploaded(is: true)
        let items = try context.fetch(request)
        return items
    }
    
    static func getAllMessagesToUploadWithoutAttachments(serverURL: URL, fetchLimit: Int, maxNumberOfHeaders: Int, within context: NSManagedObjectContext) throws -> [OutboxMessage] {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.fetchLimit = fetchLimit
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.uploaded(is: false),
            Predicate.withServerURL(serverURL: serverURL),
            Predicate.withNoAttachments,
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.creationDate.rawValue, ascending: true)]
        let items = try context.fetch(request)
        guard !items.isEmpty else { return [] }
        for item in items {
            assert(!item.hasAttachments)
        }
        // If have at most `fetchLimit` items. We also want to limit the total number headers they represent.
        var itemsToReturn: [OutboxMessage] = []
        var currentNumberOfHeaders: Int = 0
        for item in items {
            guard currentNumberOfHeaders < max(1, maxNumberOfHeaders) else {
                return itemsToReturn
            }
            itemsToReturn += [item]
            currentNumberOfHeaders += item.headers.count
        }
        debugPrint("currentNumberOfHeaders: \(currentNumberOfHeaders)")
        debugPrint("itemsToReturn.count: \(itemsToReturn.count)")
        return itemsToReturn
    }
    

    static func getAllMessagesToUploadWithAttachments(within context: NSManagedObjectContext) throws -> [OutboxMessage] {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        request.predicate = Predicate.uploaded(is: false)
        let items = try context.fetch(request)
            .filter({ $0.hasAttachments }) // Only keep messages with attachments
        return items
    }

    static func delete(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageId(messageId)
        guard let item = try context.fetch(request).first else { return }
        try item.deleteThisOutboxMessage()
    }
    
    static func pruneOldOutboxMessages(createdEarlierThan date: Date, log: OSLog, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = Predicate.creationDateIsEarlierThan(date)
        request.fetchBatchSize = 500
        let items = try context.fetch(request)
        for item in items {
            do {
                try item.deleteThisOutboxMessage()
            } catch {
                os_log("Could not prune an old outbox message: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // In production, continue anyway
            }
        }
    }
    
    static func deleteAllForOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity)
        request.fetchBatchSize = 500
        request.propertiesToFetch = []
        let messages = try context.fetch(request)
        try messages.forEach { message in
            try message.deleteThisOutboxMessage()
        }
    }
    
    /// Returns a set of all the server URLs corresponding to at least one message still to upload.
    static func getAllServerURLsForMessagesToUpload(within context: NSManagedObjectContext) throws -> Set<URL> {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        request.propertiesToFetch = [Predicate.Key.serverURL.rawValue]
        request.predicate = Predicate.uploaded(is: false)
        let messages = try context.fetch(request)
        let serverURLs = Set(messages.map(\.serverURL))
        return serverURLs
    }
}


// MARK: - Managing Change Events

extension OutboxMessage {
    
    override func prepareForDeletion() {
        super.prepareForDeletion()
        
        guard let managedObjectContext else { assertionFailure(); return }
        guard managedObjectContext.concurrencyType != .mainQueueConcurrencyType else { return }

        guard let delegateManager = Self.delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: OutboxMessage.entityName)
            os_log("The Outbox Message Delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        assert(delegateManager.notificationDelegate != nil, "The delegate manager is sometimes needed below")

        let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: OutboxMessage.entityName)

        guard let context = self.managedObjectContext else {
            os_log("The obvContext is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        guard let messageId = self.messageIdWhenDeleted else {
            os_log("Could not recover messageId of deleted OutboxMessage", log: log, type: .fault)
            assertionFailure()
            return
        }

        if let timestampFromServer = self.timestampFromServer {
            do {
                _ = try DeletedOutboxMessage.getOrCreate(messageId: messageId, timestampFromServer: timestampFromServer, within: context)
            } catch {
                os_log("Could not get or create a DeletedOutboxMessage: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // In production, continue anyway
            }
        } else {
            guard let notificationDelegate = delegateManager.notificationDelegate else {
                os_log("The notificationDelegate is not set", log: log, type: .fault)
                assertionFailure()
                return
            }
            ObvNetworkPostNotification.outboxMessageCouldNotBeSentToServer(messageId: messageId, flowId: FlowIdentifier())
                .postOnBackgroundQueue(within: notificationDelegate)
        }

    }
    
    override func didSave() {
        super.didSave()

        guard !isDeleted else { return }
        
        guard let delegateManager = Self.delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: OutboxMessage.entityName)
            os_log("The Outbox Message Delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        if isInserted, let messageId = self.messageId {
            let hasAttachments = self.hasAttachments
            let serverURL = self.serverURL
            let flowId = FlowIdentifier()
            if hasAttachments {
                DispatchQueue(label: "Queue for calling newOutboxMessage").async {
                    delegateManager.networkSendFlowDelegate.newOutboxMessageWithAttachments(messageId: messageId, flowId: flowId)
                }
            } else {
                Task { try? await delegateManager.networkSendFlowDelegate.requestBatchUploadMessagesWithoutAttachment(serverURL: serverURL, flowId: flowId) }
            }
            
        }
        
    }
    
}
