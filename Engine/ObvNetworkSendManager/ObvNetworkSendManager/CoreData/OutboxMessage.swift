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
import ObvEncoder
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

@objc(OutboxMessage)
final class OutboxMessage: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "OutboxMessage"
    private static let cancelExternallyRequestedKey = "cancelExternallyRequested"
    private static let rawMessageIdOwnedIdentityKey = "rawMessageIdOwnedIdentity"
    static let rawMessageIdUidKey = "rawMessageIdUid"
    static let timestampFromServerKey = "timestampFromServer"
    private static let ownedIdentityKey = "ownedIdentity"
    private static let rawMessageUidFromServerKey = "rawMessageUidFromServer"
    static let uploadedKey = "uploaded"
    private static let unsortedAttachmentsKey = "unsortedAttachments"
    
    private static let errorDomain = "OutboxMessage"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Attributes
    
    @NSManaged private(set) var cancelExternallyRequested: Bool
    @NSManaged private(set) var encryptedContent: EncryptedData
    @NSManaged private var rawEncryptedExtendedMessagePayload: Data?
    @NSManaged private(set) var isAppMessageWithUserContent: Bool
    @NSManaged private(set) var isVoipMessage: Bool
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
            let items = kvoSafePrimitiveValue(forKey: OutboxMessage.unsortedAttachmentsKey) as! Set<OutboxAttachment>
            return Set(items.map { $0.obvContext = self.obvContext; return $0 })
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OutboxMessage.unsortedAttachmentsKey)
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

    // MARK: Other variables
    
    private(set) var messageId: MessageIdentifier {
        get { return MessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }
    
    private(set) var messageUidFromServer: UID? {
        get { guard let uid = self.rawMessageUidFromServer else { return nil };  return UID(uid: uid) }
        set { self.rawMessageUidFromServer = newValue?.raw }
    }
    
    var canBeDeleted: Bool {
        let allAttachmentsCanBeDeleted = attachments.allSatisfy({ $0.canBeDeleted })
        return allAttachmentsCanBeDeleted && (uploaded || cancelExternallyRequested)
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
    
    convenience init?(messageId: MessageIdentifier, serverURL: URL, encryptedContent: EncryptedData, encryptedExtendedMessagePayload: EncryptedData?, isAppMessageWithUserContent: Bool, isVoipMessage: Bool, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) {
        
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
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<OutboxMessage> {
        return NSFetchRequest<OutboxMessage>(entityName: OutboxMessage.entityName)
    }

    static func get(messageId: MessageIdentifier, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> OutboxMessage? {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        OutboxMessage.rawMessageIdOwnedIdentityKey, messageId.ownedCryptoIdentity.getIdentity() as NSData,
                                        OutboxMessage.rawMessageIdUidKey, messageId.uid.raw as NSData)
        let item = (try obvContext.fetch(request)).first
        item?.delegateManager = delegateManager
        return item
    }
    
    class func getAll(delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> [OutboxMessage] {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        let items = try obvContext.fetch(request)
        return items.map { $0.delegateManager = delegateManager; return $0 }
    }
    
    class func getAllNotUploaded(delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) -> [OutboxMessage]? {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == false", uploadedKey)
        let items = try? obvContext.fetch(request)
        return items?.map { $0.delegateManager = delegateManager; return $0 }
    }

    class func getAllUploaded(delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> [OutboxMessage] {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == true", uploadedKey)
        let items = try obvContext.fetch(request)
        return items.map { $0.delegateManager = delegateManager; return $0 }
    }

    class func delete(messageId: MessageIdentifier, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<OutboxMessage> = OutboxMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        OutboxMessage.rawMessageIdOwnedIdentityKey, messageId.ownedCryptoIdentity.getIdentity() as NSData,
                                        OutboxMessage.rawMessageIdUidKey, messageId.uid.raw as NSData)
        guard let item = (try? obvContext.fetch(request))?.first else { throw NSError() }
        item.delegateManager = delegateManager
        obvContext.delete(item)
    }
}


// MARK: - Managing Change Events

extension OutboxMessage {
    
    override func prepareForDeletion() {
        super.prepareForDeletion()
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: OutboxMessage.entityName)
            os_log("The Outbox Message Delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        

        let log = OSLog(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: OutboxMessage.entityName)

        guard let obvContext = self.obvContext else {
            os_log("The obvContext is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notificationDelegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        if let timestampFromServer = self.timestampFromServer {
            _ = DeletedOutboxMessage(messageId: self.messageId, timestampFromServer: timestampFromServer, delegateManager: delegateManager, within: obvContext)
            
        }
        
        let messageId = self.messageId
        let flowId = obvContext.flowId
        if let timestampFromServer = self.timestampFromServer {
            try? obvContext.addContextDidSaveCompletionHandler { (error) in
                guard error == nil else { return }
                ObvNetworkPostNotification.outboxMessagesAndAllTheirAttachmentsWereAcknowledged(messageIdsAndTimestampsFromServer: [(messageId, timestampFromServer)], flowId: flowId)
                    .postOnBackgroundQueue(within: notificationDelegate)
            }
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

        if isInserted, let flowId = self.obvContext?.flowId {
            let messageId = self.messageId
            DispatchQueue(label: "Queue for calling newOutboxMessage").async {
                delegateManager.networkSendFlowDelegate.newOutboxMessage(messageId: messageId, flowId: flowId)
            }
        }
        
    }
    
}
