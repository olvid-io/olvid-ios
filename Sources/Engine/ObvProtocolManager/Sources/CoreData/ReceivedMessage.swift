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


@objc(ReceivedMessage)
final class ReceivedMessage: NSManagedObject {

    private static let entityName = "ReceivedMessage"
    static weak var delegateManager: ObvProtocolDelegateManager?
    
    // MARK: Attributes
    
    @NSManaged private(set) var protocolMessageRawId: Int
    @NSManaged private var protocolRawId: Int
    @NSManaged private var rawEncodedEncodedInputs: Data? // Non-optional in the model
    @NSManaged private var rawEncodedUserDialogResponse: Data? // Non-nil only if the received message is a user response to a UI dialog
    @NSManaged private var rawMessageIdOwnedIdentity: Data? // Non-optional in the model
    @NSManaged private var rawMessageIdUid: Data? // Non-optional in the model
    @NSManaged private var rawProtocolInstanceUid: Data? // Non-optional in the model
    @NSManaged private var rawReceptionChannelInfo: Data? // Non-optional in the model
    @NSManaged private(set) var timestamp: Date
    @NSManaged private(set) var userDialogUuid: UUID? // Non-nil only if the received message is a user response to a UI dialog

    // MARK: Other variables
    
    var encodedInputs: [ObvEncoded] {
        get throws(ObvError) {
            guard let rawEncodedEncodedInputs else { assertionFailure(); throw .unexpectedNilValue }
            guard let encoded = ObvEncoded(withRawData: rawEncodedEncodedInputs) else { assertionFailure(); throw .couldNotParseValue }
            guard let encodedInputs = [ObvEncoded](encoded) else { assertionFailure(); throw .couldNotParseValue }
            return encodedInputs
        }
    }
    
    /// Non-nil only if the received message is a user response to a UI dialog
    var encodedUserDialogResponse: ObvEncoded? {
        guard let rawEncodedUserDialogResponse else { return nil }
        return ObvEncoded(withRawData: rawEncodedUserDialogResponse)
    }

    
    var protocolInstanceUid: UID {
        get throws(ObvError) {
            guard let rawProtocolInstanceUid else { assertionFailure(); throw .unexpectedNilValue }
            guard let protocolInstanceUid = UID(uid: rawProtocolInstanceUid) else { assertionFailure(); throw .couldNotParseValue }
            return protocolInstanceUid
        }
    }

    
    var cryptoProtocolId: CryptoProtocolId {
        get throws {
            guard let cryptoProtocolId = CryptoProtocolId(rawValue: protocolRawId) else {
                assertionFailure()
                throw ObvError.couldNotParseValue
            }
            return cryptoProtocolId
        }
    }

    
    var messageId: ObvMessageIdentifier {
        get throws {
            guard let rawMessageIdOwnedIdentity else {
                assertionFailure()
                throw ObvError.unexpectedNilValue
            }
            guard let rawMessageIdUid else {
                assertionFailure()
                throw ObvError.unexpectedNilValue
            }
            guard let messageId = ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid) else {
                assertionFailure()
                throw ObvError.couldNotParseValue
            }
            return messageId
        }
    }
    
    
    var receptionChannelInfo: ObvProtocolReceptionChannelInfo {
        get throws {
            guard let rawReceptionChannelInfo else {
                assertionFailure()
                throw ObvError.unexpectedNilValue
            }
            guard let encoded = ObvEncoded(withRawData: rawReceptionChannelInfo) else {
                assertionFailure()
                throw ObvError.couldNotParseValue
            }
            guard let receptionChannelInfo = ObvProtocolReceptionChannelInfo(encoded) else {
                assertionFailure()
                throw ObvError.couldNotParseValue
            }
            return receptionChannelInfo
        }
    }


    private var messageIdOnDeletion: ObvMessageIdentifier?

    // MARK: - Initializer
    
    /// 2025-08-27: ok
    private convenience init(with message: GenericReceivedProtocolMessage, using prng: PRNGService, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ReceivedMessage.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.rawEncodedEncodedInputs = message.encodedInputs.obvEncode().rawData
        self.rawEncodedUserDialogResponse = message.encodedUserDialogResponse?.rawData
        self.userDialogUuid = message.userDialogUuid
        self.rawProtocolInstanceUid = message.protocolInstanceUid.raw
        self.protocolMessageRawId = message.protocolMessageRawId
        self.protocolRawId = message.cryptoProtocolId.rawValue
        self.rawReceptionChannelInfo = message.receptionChannelInfo.obvEncode().rawData
        self.rawMessageIdOwnedIdentity = message.toOwnedIdentity.getIdentity()
        self.rawMessageIdUid = message.receivedMessageUID?.raw ?? UID.gen(with: prng).raw
        self.timestamp = message.timestamp
        
    }

    
    static func createReceivedMessage(with message: GenericReceivedProtocolMessage, using prng: PRNGService, within context: NSManagedObjectContext) -> ReceivedMessage {
        return self.init(with: message, using: prng, within: context)
    }
    
    
    func deleteReceivedMessage() throws {
        guard let managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        managedObjectContext.delete(self)
    }
    
    
    // MARK: - Observers
    
    private static var observersHolder = ReceivedMessageObserversHolder()
    
    public static func addObvObserver(_ newObserver: ReceivedMessageObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}


// MARK: - Errors

extension ReceivedMessage {
    
    enum ObvError: Error {
        case noContext
        case unexpectedNilValue
        case couldNotParseValue
    }
    
}


// MARK: - Predicates and Fetch request

extension ReceivedMessage {
    
    struct Predicate {
        enum Key: String {
            case protocolMessageRawId = "protocolMessageRawId"
            case protocolRawId = "protocolRawId"
            case rawEncodedEncodedInputs = "rawEncodedEncodedInputs"
            case rawEncodedUserDialogResponse = "rawEncodedUserDialogResponse"
            case rawMessageIdOwnedIdentity = "rawMessageIdOwnedIdentity"
            case rawMessageIdUid = "rawMessageIdUid"
            case rawProtocolInstanceUid = "rawProtocolInstanceUid"
            case rawReceptionChannelInfo = "rawReceptionChannelInfo"
            case timestamp = "timestamp"
            case userDialogUuid = "userDialogUuid"
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
            NSPredicate(Key.rawProtocolInstanceUid, EqualToData: protocolInstanceUid.raw)
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
    
    static func get(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws -> ReceivedMessage? {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = Predicate.withMessageIdentifier(messageId)
        request.fetchLimit = 1
        let item = (try context.fetch(request)).first
        return item
    }
    
    
    static func getAll(protocolInstanceUid: UID, ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> [ReceivedMessage]? {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withProtocolInstanceUid(protocolInstanceUid),
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.timestamp.rawValue, ascending: true)]
        request.fetchBatchSize = 1_000
        let items = try context.fetch(request)
        return items
    }
    
    
    static func deleteReceivedMessage(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: ReceivedMessage.entityName)
        request.predicate = Predicate.withMessageIdentifier(messageId)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
    
    static func deleteAllAssociatedWithProtocolInstance(withUid protocolInstanceUid: UID, ownedIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: ReceivedMessage.entityName)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withProtocolInstanceUid(protocolInstanceUid),
            Predicate.withOwnedCryptoIdentity(ownedIdentity),
        ])
        
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
    
    static func getAllReceivedMessageOlderThan(timestamp: Date, within context: NSManagedObjectContext) throws -> [ReceivedMessage] {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = Predicate.withTimestamp(earlierThan: timestamp)
        request.fetchBatchSize = 1_000
        let items = try context.fetch(request)
        return items
    }
    
    
    static func getAllMessageIds(within context: NSManagedObjectContext) throws -> [ObvMessageIdentifier] {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.rawMessageIdUid.rawValue, Predicate.Key.rawMessageIdOwnedIdentity.rawValue]
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.timestamp.rawValue, ascending: true)]
        let items = try context.fetch(request)
        return items.compactMap { try? $0.messageId }
    }
    
    
    static func batchDeleteAllReceivedMessagesForOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: ReceivedMessage.entityName)
        fetchRequest.predicate = Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
    
    static func deleteReceivedMessagesConcerningAnOwnedIdentityTransferProtocol(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = Predicate.withCryptoProtocolId(.ownedIdentityTransfer)
        request.propertiesToFetch = []
        let items = try context.fetch(request)
        try items.forEach { try $0.deleteReceivedMessage() }
    }
    
}


// MARK: Managing notifications and calls to delegates
extension ReceivedMessage {
        
    override func willSave() {
        super.willSave()
        
        if isDeleted {
            do {
                messageIdOnDeletion = try self.messageId
            } catch {
                assertionFailure()
            }
        }
        
    }
    
    override func didSave() {
        super.didSave()

        if isDeleted {
            assert(messageIdOnDeletion != nil)
            if let messageIdOnDeletion {
                Task { await Self.observersHolder.aReceivedMessageWasDeleted(messageId: messageIdOnDeletion) }
            }
        }
        
    }
    
}


// MARK: - ReceivedMessage observers

protocol ReceivedMessageObserver: AnyObject {
    func aReceivedMessageWasDeleted(messageId: ObvMessageIdentifier) async
}


private actor ReceivedMessageObserversHolder: ReceivedMessageObserver {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: ReceivedMessageObserver?
        init(value: ReceivedMessageObserver?) {
            self.value = value
        }
    }

    func addObserver(_ newObserver: ReceivedMessageObserver) {
        self.observers.append(.init(value: newObserver))
    }
    
    // Implementing PersistedMessageObserver
    
    func aReceivedMessageWasDeleted(messageId: ObvMessageIdentifier) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.aReceivedMessageWasDeleted(messageId: messageId) }
            }
        }
    }
    
}
