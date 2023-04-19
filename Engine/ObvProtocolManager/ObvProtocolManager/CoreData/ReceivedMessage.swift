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
    
    private(set) var messageId: MessageIdentifier {
        get { return MessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }

    weak var delegateManager: ObvProtocolDelegateManager?
    var obvContext: ObvContext?

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
        self.messageId = MessageIdentifier(ownedCryptoIdentity: message.toOwnedIdentity, uid: message.receivedMessageUID ?? UID.gen(with: prng))
        self.delegateManager = delegateManager
        self.timestamp = message.timestamp
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
        static func withMessageIdentifier(_ messageId: MessageIdentifier) -> NSPredicate {
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
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ReceivedMessage> {
        return NSFetchRequest<ReceivedMessage>(entityName: ReceivedMessage.entityName)
    }
    
}


// MARK: - Convenience DB getters

extension ReceivedMessage {
    
    static func get(messageId: MessageIdentifier, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) -> ReceivedMessage? {
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
        request.fetchBatchSize = 1_000
        let items = (try? obvContext.fetch(request))
        return items?.map { $0.delegateManager = delegateManager; return $0 }
    }
    
    
    static func delete(messageId: MessageIdentifier, within obvContext: ObvContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: ReceivedMessage.entityName)
        request.predicate = Predicate.withMessageIdentifier(messageId)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        _ = try obvContext.execute(deleteRequest)
    }
    
    
    static func deleteAllAssociatedWithProtocolInstance(withUid protocolInstanceUid: UID, within obvContext: ObvContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: ReceivedMessage.entityName)
        request.predicate = Predicate.withProtocolInstanceUid(protocolInstanceUid)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        _ = try obvContext.execute(deleteRequest)
    }
    
    
    static func getAllReceivedMessageOlderThan(timestamp: Date, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> [ReceivedMessage] {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = Predicate.withTimestamp(earlierThan: timestamp)
        request.fetchBatchSize = 1_000
        let items = try obvContext.fetch(request)
        items.forEach { $0.delegateManager = delegateManager }
        return items
    }
    
    
    static func getAllMessageIds(within obvContext: ObvContext) throws -> Set<MessageIdentifier> {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.rawMessageIdUid.rawValue, Predicate.Key.rawMessageIdOwnedIdentity.rawValue]
        let items = try obvContext.fetch(request)
        return Set(items.map { $0.messageId })
    }
    
}


// MARK: Managing notifications and calls to delegates
extension ReceivedMessage {
        
    override func didSave() {
        super.didSave()

        guard let delegateManager = self.delegateManager else {
            let log = OSLog(subsystem: ObvProtocolDelegateManager.defaultLogSubsystem, category: ReceivedMessage.entityName)
            os_log("The Delegate Manager is not set", log: log, type: .error)
            return
        }

        if isInserted, let flowId = self.obvContext?.flowId {
            delegateManager.receivedMessageDelegate.processReceivedMessage(withId: messageId, flowId: flowId)
        }
    }
    
}
