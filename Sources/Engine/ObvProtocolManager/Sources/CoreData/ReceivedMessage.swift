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
import os.log
import ObvEncoder
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


@objc(ReceivedMessage)
final class ReceivedMessage: NSManagedObject, ObvManagedObject, ObvErrorMaker {

    private static let entityName = "ReceivedMessage"
    static let errorDomain = "ReceivedMessage"

    
    // MARK: Attributes
    
    private(set) var encodedInputs: [ObvEncoded] {
        get {
            let rawValue = kvoSafePrimitiveValue(forKey: Predicate.Key.encodedEncodedInputs.rawValue) as! ObvEncoded
            return [ObvEncoded](rawValue)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.obvEncode(), forKey: Predicate.Key.encodedEncodedInputs.rawValue)
        }
    }
    
    @NSManaged private(set) var encodedUserDialogResponse: ObvEncoded? // Non-nil only if the received message is a user response to a UI dialog
    @NSManaged private(set) var protocolInstanceUid: UID
    @NSManaged private(set) var protocolMessageRawId: Int
    
    private(set) var cryptoProtocolId: CryptoProtocolId {
        get {
            let rawValue = kvoSafePrimitiveValue(forKey: Predicate.Key.protocolRawId.rawValue) as! Int
            return CryptoProtocolId(rawValue: rawValue)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.rawValue, forKey: Predicate.Key.protocolRawId.rawValue)
        }
    }
    
    @NSManaged private var rawMessageIdOwnedIdentity: Data
    @NSManaged private var rawMessageIdUid: Data

    private(set) var receptionChannelInfo: ObvProtocolReceptionChannelInfo {
        get {
            let raw = kvoSafePrimitiveValue(forKey: Predicate.Key.receptionChannelInfo.rawValue) as! Data
            let encoded = ObvEncoded(withRawData: raw)!
            return ObvProtocolReceptionChannelInfo(encoded)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.obvEncode().rawData, forKey: Predicate.Key.receptionChannelInfo.rawValue)
        }
    }
    
    @NSManaged private(set) var timestamp: Date
    @NSManaged private(set) var userDialogUuid: UUID? // Non-nil only if the received message is a user response to a UI dialog

    
    // MARK: Other variables
    
    private(set) var messageId: ObvMessageIdentifier {
        get { return ObvMessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }

    weak var delegateManager: ObvProtocolDelegateManager?
    weak var obvContext: ObvContext?
    private var messageIdOnDeletion: ObvMessageIdentifier?

    // MARK: - Initializer
    
    convenience init(with message: GenericReceivedProtocolMessage, using prng: PRNGService, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ReceivedMessage.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.encodedInputs = message.encodedInputs
        self.encodedUserDialogResponse = message.encodedUserDialogResponse
        self.userDialogUuid = message.userDialogUuid
        self.protocolInstanceUid = message.protocolInstanceUid
        self.protocolMessageRawId = message.protocolMessageRawId
        self.cryptoProtocolId = message.cryptoProtocolId
        self.receptionChannelInfo = message.receptionChannelInfo
        self.messageId = ObvMessageIdentifier(ownedCryptoIdentity: message.toOwnedIdentity, uid: message.receivedMessageUID ?? UID.gen(with: prng))
        self.delegateManager = delegateManager
        self.timestamp = message.timestamp
        
        // Instead of using the didSave method to call the delegate method, we add a "didSave" completion to the obvContext.
        // This allows to make sure the completions are executed in the right order (first in, first out).
        // Since the ReceivedMessage received from the network are processed according to their timestamp, this allows to preserver that order.
        
        do {
            let flowId = obvContext.flowId
            let messageId = self.messageId
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                delegateManager.receivedMessageDelegate.processReceivedMessage(withId: messageId, flowId: flowId)
            }
        } catch {
            assertionFailure(error.localizedDescription)
            // Continue anyway
        }
    }

    
    func deleteReceivedMessage() throws {
        guard let managedObjectContext else { throw Self.makeError(message: "Cannot delete message as it has no context") }
        managedObjectContext.delete(self)
    }
    
}


// MARK: - Predicates and Fetch request

extension ReceivedMessage {
    
    struct Predicate {
        enum Key: String {
            case encodedEncodedInputs = "encodedEncodedInputs"
            case protocolInstanceUid = "protocolInstanceUid"
            case protocolRawId = "protocolRawId"
            case rawMessageIdOwnedIdentity = "rawMessageIdOwnedIdentity"
            case rawMessageIdUid = "rawMessageIdUid"
            case receptionChannelInfo = "receptionChannelInfo"
            case timestamp = "timestamp"
        }
        static func withMessageIdentifier(_ messageId: ObvMessageIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withOwnedCryptoIdentity(messageId.ownedCryptoIdentity),
                NSPredicate(Key.rawMessageIdUid, EqualToData: messageId.uid.raw),
            ])
        }
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawMessageIdOwnedIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
        static func withProtocolInstanceUid(_ protocolInstanceUid: UID) -> NSPredicate {
            NSPredicate(format: "%K == %@", Key.protocolInstanceUid.rawValue, protocolInstanceUid)
        }
        static func withTimestamp(earlierThan timestamp: Date) -> NSPredicate {
            NSPredicate(Key.timestamp, earlierThan: timestamp)
        }
        static func withCryptoProtocolId(_ cryptoProtocolId: CryptoProtocolId) -> NSPredicate {
            NSPredicate(Key.protocolRawId, EqualToInt: cryptoProtocolId.rawValue)
        }
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ReceivedMessage> {
        return NSFetchRequest<ReceivedMessage>(entityName: ReceivedMessage.entityName)
    }
    
}


// MARK: - Convenience DB getters

extension ReceivedMessage {
    
    static func get(messageId: ObvMessageIdentifier, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) -> ReceivedMessage? {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        let item = (try? obvContext.fetch(request))?.first
        item?.delegateManager = delegateManager
        return item
    }
    
    
    static func getAll(protocolInstanceUid: UID, ownedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) -> [ReceivedMessage]? {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withProtocolInstanceUid(protocolInstanceUid),
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.timestamp.rawValue, ascending: true)]
        request.fetchBatchSize = 1_000
        let items = (try? obvContext.fetch(request))
        return items?.map { $0.delegateManager = delegateManager; return $0 }
    }
    
    
    static func delete(messageId: ObvMessageIdentifier, within obvContext: ObvContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: ReceivedMessage.entityName)
        request.predicate = Predicate.withMessageIdentifier(messageId)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try obvContext.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [obvContext.context])
        } else {
            assertionFailure()
        }
    }
    
    
    static func deleteAllAssociatedWithProtocolInstance(withUid protocolInstanceUid: UID, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: ReceivedMessage.entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withProtocolInstanceUid(protocolInstanceUid),
            Predicate.withOwnedCryptoIdentity(ownedIdentity),
        ])
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try obvContext.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [obvContext.context])
        } else {
            assertionFailure()
        }
    }
    
    
    static func getAllReceivedMessageOlderThan(timestamp: Date, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> [ReceivedMessage] {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = Predicate.withTimestamp(earlierThan: timestamp)
        request.fetchBatchSize = 1_000
        let items = try obvContext.fetch(request)
        items.forEach { $0.delegateManager = delegateManager }
        return items
    }
    
    
    static func getAllMessageIds(within obvContext: ObvContext) throws -> [ObvMessageIdentifier] {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.rawMessageIdUid.rawValue, Predicate.Key.rawMessageIdOwnedIdentity.rawValue]
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.timestamp.rawValue, ascending: true)]
        let items = try obvContext.fetch(request)
        return items.map { $0.messageId }
    }
    
    
    static func batchDeleteAllReceivedMessagesForOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: ReceivedMessage.entityName)
        fetchRequest.predicate = Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try obvContext.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [obvContext.context])
        } else {
            assertionFailure()
        }
    }
    
    
    static func deleteReceivedMessagesConcerningAnOwnedIdentityTransferProtocol(within obvContext: ObvContext) throws {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = Predicate.withCryptoProtocolId(.ownedIdentityTransfer)
        request.propertiesToFetch = []
        let items = try obvContext.fetch(request)
        try items.forEach { try $0.deleteReceivedMessage() }
    }
    
}


// MARK: Managing notifications and calls to delegates
extension ReceivedMessage {
        
    override func willSave() {
        super.willSave()
        
        if isDeleted {
            messageIdOnDeletion = self.messageId
        }
        
    }
    
    override func didSave() {
        super.didSave()

        guard let delegateManager = self.delegateManager else {
            let log = OSLog(subsystem: ObvProtocolDelegateManager.defaultLogSubsystem, category: ReceivedMessage.entityName)
            os_log("The Delegate Manager is not set", log: log, type: .error)
            return
        }

        if isDeleted {
            assert(messageIdOnDeletion != nil)
            assert(delegateManager.notificationDelegate != nil)
            if let messageIdOnDeletion, let notificationDelegate = delegateManager.notificationDelegate {
                ObvProtocolNotification.protocolReceivedMessageWasDeleted(protocolMessageId: messageIdOnDeletion)
                    .postOnBackgroundQueue(within: notificationDelegate)
            }
        }
        
    }
    
}
