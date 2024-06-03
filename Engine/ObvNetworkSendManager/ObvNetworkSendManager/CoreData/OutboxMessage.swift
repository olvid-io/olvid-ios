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
import ObvEncoder
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

@objc(OutboxMessage)
final class OutboxMessage: NSManagedObject, ObvManagedObject, ObvErrorMaker {
    
    // MARK: Internal constants
    
    private static let entityName = "OutboxMessage"
    static let errorDomain = "OutboxMessage"
    
    // MARK: Attributes
    
    @NSManaged private(set) var cancelExternallyRequested: Bool
    @NSManaged private(set) var encryptedContent: EncryptedData
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
            return Set(items.map { $0.obvContext = self.obvContext; return $0 })
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
    func deleteThisOutboxMessage(delegateManager: ObvNetworkSendDelegateManager) throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw Self.makeError(message: "Could not delete OuboxMessage as its context is nil") }
        self.messageIdWhenDeleted = self.messageId
        self.delegateManager = delegateManager
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
    
    weak var delegateManager: ObvNetworkSendDelegateManager?
    var obvContext: ObvContext?
    
    // MARK: - Initializer
    
    convenience init?(messageId: ObvMessageIdentifier, serverURL: URL, encryptedContent: EncryptedData, encryptedExtendedMessagePayload: EncryptedData?, isAppMessageWithUserContent: Bool, isVoipMessage: Bool, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) {
        
        do {
            guard try OutboxMessage.get(messageId: messageId, delegateManager: delegateManager, within: obvContext) == nil else { assertionFailure(); return nil }
        } catch {
            assertionFailure()
            return nil
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: OutboxMessage.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        self.encryptedContent = encryptedContent
        self.encryptedExtendedMessagePayload = encryptedExtendedMessagePayload
        self.messageId = messageId
        self.serverURL = serverURL
        self.isAppMessageWithUserContent = isAppMessageWithUserContent
        self.isVoipMessage = isVoipMessage
        self.creationDate = Date()
        self.delegateManager = delegateManager
        self.unsortedAttachments = Set<OutboxAttachment>()
    }

}


// MARK: - Managing proofs of work

extension OutboxMessage {
    
    // MARK: - Other stuff
    
    func cancelUpload() {
        guard !self.cancelExternallyRequested else { return }
        self.cancelExternallyRequested = true
    }
    
    func setAcknowledged(withMessageUidFromServer messageUidFromServer: UID, nonceFromServer: Data, andTimeStampFromServer timestampFromServer: Date, log: OSLog) {
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
            case encryptedContent = "encryptedContent"
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
        
    }
    
    
    

    @nonobjc class func fetchRequest() -> NSFetchRequest<OutboxMessage> {
        return NSFetchRequest<OutboxMessage>(entityName: OutboxMessage.entityName)
    }

    static func get(messageId: ObvMessageIdentifier, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> OutboxMessage? {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageId(messageId)
        request.fetchLimit = 1
        let item = (try obvContext.fetch(request)).first
        item?.delegateManager = delegateManager
        return item
    }
    
    static func getAll(delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> [OutboxMessage] {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        let items = try obvContext.fetch(request)
        return items.map { $0.delegateManager = delegateManager; return $0 }
    }
    
    static func getAllUploaded(delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> [OutboxMessage] {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        request.predicate = Predicate.uploaded(is: true)
        let items = try obvContext.fetch(request)
        return items.map { $0.delegateManager = delegateManager; return $0 }
    }
    
    static func getAllMessagesToUploadWithoutAttachments(serverURL: URL, fetchLimit: Int, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> [OutboxMessage] {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.fetchLimit = fetchLimit
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.uploaded(is: false),
            Predicate.withServerURL(serverURL: serverURL),
        ])
        let items = try obvContext.fetch(request)
            .filter({ !$0.hasAttachments }) // Only keep messages without attachments
        return items.map { $0.delegateManager = delegateManager; return $0 }
    }

    static func getAllMessagesToUploadWithAttachments(delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> [OutboxMessage] {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        request.predicate = Predicate.uploaded(is: false)
        let items = try obvContext.fetch(request)
            .filter({ $0.hasAttachments }) // Only keep messages with attachments
        return items.map { $0.delegateManager = delegateManager; return $0 }
    }

    static func delete(messageId: ObvMessageIdentifier, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageId(messageId)
        guard let item = try obvContext.fetch(request).first else { return }
        item.delegateManager = delegateManager
        try item.deleteThisOutboxMessage(delegateManager: delegateManager)
    }
    
    static func pruneOldOutboxMessages(createdEarlierThan date: Date, delegateManager: ObvNetworkSendDelegateManager, log: OSLog, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = Predicate.creationDateIsEarlierThan(date)
        request.fetchBatchSize = 500
        let items = try obvContext.fetch(request)
        for item in items {
            item.obvContext = obvContext
            item.delegateManager = delegateManager
            do {
                try item.deleteThisOutboxMessage(delegateManager: delegateManager)
            } catch {
                os_log("Could not prune an old outbox message: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // In production, continue anyway
            }
        }
    }
    
    static func deleteAllForOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity)
        request.fetchBatchSize = 500
        request.propertiesToFetch = []
        let messages = try obvContext.fetch(request)
        try messages.forEach { message in
            try message.deleteThisOutboxMessage(delegateManager: delegateManager)
        }
    }
    
    /// Returns a set of all the server URLs corresponding to at least one message still to upload.
    static func getAllServerURLsForMessagesToUpload(within obvContext: ObvContext) throws -> Set<URL> {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.fetchBatchSize = 500
        request.propertiesToFetch = [Predicate.Key.serverURL.rawValue]
        request.predicate = Predicate.uploaded(is: false)
        let messages = try obvContext.fetch(request)
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

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: OutboxMessage.entityName)
            os_log("The Outbox Message Delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        assert(delegateManager.notificationDelegate != nil, "The delegate manager is sometimes needed below")

        let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: OutboxMessage.entityName)

        guard let obvContext = self.obvContext else {
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
                _ = try DeletedOutboxMessage.getOrCreate(messageId: messageId, timestampFromServer: timestampFromServer, delegateManager: delegateManager, within: obvContext)
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
            ObvNetworkPostNotification.outboxMessageCouldNotBeSentToServer(messageId: messageId, flowId: obvContext.flowId)
                .postOnBackgroundQueue(within: notificationDelegate)
        }

    }
    
    override func didSave() {
        super.didSave()

        guard !isDeleted else { return }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: OutboxMessage.entityName)
            os_log("The Outbox Message Delegate is not set", log: log, type: .fault)
            return
        }

        if isInserted, let flowId = self.obvContext?.flowId, let messageId = self.messageId {
            let hasAttachments = self.hasAttachments
            let serverURL = self.serverURL
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
