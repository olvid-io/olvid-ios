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
final class ReceivedMessage: NSManagedObject, ObvManagedObject {

    // MARK: Internal constants
    
    private static let entityName = "ReceivedMessage"
    private static let receptionChannelInfoKey = "receptionChannelInfo"
    private static let protocolInstanceUidKey = "protocolInstanceUid"
    private static let protocolRawIdKey = "protocolRawId"
    private static let encodedEncodedInputsKey = "encodedEncodedInputs"
    private static let rawMessageIdOwnedIdentityKey = "rawMessageIdOwnedIdentity"
    private static let rawMessageIdUidKey = "rawMessageIdUid"
    
    // MARK: Attributes
    
    private(set) var encodedInputs: [ObvEncoded] {
        get {
            let rawValue = kvoSafePrimitiveValue(forKey: ReceivedMessage.encodedEncodedInputsKey) as! ObvEncoded
            return [ObvEncoded](rawValue)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.obvEncode(), forKey: ReceivedMessage.encodedEncodedInputsKey)
        }
    }
    
    @NSManaged private(set) var encodedUserDialogResponse: ObvEncoded? // Non-nil only if the received message is a user response to a UI dialog
    @NSManaged private(set) var userDialogUuid: UUID? // Non-nil only if the received message is a user response to a UI dialog
    @NSManaged private(set) var protocolInstanceUid: UID
    @NSManaged private(set) var protocolMessageRawId: Int
    
    private(set) var cryptoProtocolId: CryptoProtocolId {
        get {
            let rawValue = kvoSafePrimitiveValue(forKey: ReceivedMessage.protocolRawIdKey) as! Int
            return CryptoProtocolId(rawValue: rawValue)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.rawValue, forKey: ReceivedMessage.protocolRawIdKey)
        }
    }
    
    @NSManaged private var rawMessageIdOwnedIdentity: Data
    @NSManaged private var rawMessageIdUid: Data

    private(set) var receptionChannelInfo: ObvProtocolReceptionChannelInfo {
        get {
            let raw = kvoSafePrimitiveValue(forKey: ReceivedMessage.receptionChannelInfoKey) as! Data
            let encoded = ObvEncoded(withRawData: raw)!
            return ObvProtocolReceptionChannelInfo(encoded)!
        }
        set {
            kvoSafeSetPrimitiveValue(newValue.obvEncode().rawData, forKey: ReceivedMessage.receptionChannelInfoKey)
        }
    }
    
    @NSManaged private(set) var timestamp: Date
    
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
        self.messageId = MessageIdentifier(ownedCryptoIdentity: message.toOwnedIdentity, uid: UID.gen(with: prng))
        self.delegateManager = delegateManager
        self.timestamp = message.timestamp
    }

}


// MARK: - Fetch request

extension ReceivedMessage {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ReceivedMessage> {
        return NSFetchRequest<ReceivedMessage>(entityName: ReceivedMessage.entityName)
    }
}


// MARK: - Convenience DB getters

extension ReceivedMessage {
    
    static func get(messageId: MessageIdentifier, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) -> ReceivedMessage? {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        rawMessageIdOwnedIdentityKey, messageId.ownedCryptoIdentity.getIdentity() as NSData,
                                        rawMessageIdUidKey, messageId.uid.raw as NSData)
        let item = (try? obvContext.fetch(request))?.first
        item?.delegateManager = delegateManager
        return item
    }
    
    static func getAll(protocolInstanceUid: UID, ownedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) -> [ReceivedMessage]? {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        protocolInstanceUidKey, protocolInstanceUid,
                                        rawMessageIdOwnedIdentityKey, ownedCryptoIdentity.getIdentity() as NSData)
        let items = (try? obvContext.fetch(request))
        return items?.map { $0.delegateManager = delegateManager; return $0 }
    }
    
    static func delete(messageId: MessageIdentifier, within obvContext: ObvContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: ReceivedMessage.entityName)
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        rawMessageIdOwnedIdentityKey, messageId.ownedCryptoIdentity.getIdentity() as NSData,
                                        rawMessageIdUidKey, messageId.uid.raw as NSData)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        _ = try obvContext.execute(deleteRequest)
    }
    
    static func deleteAllAssociatedWithProtocolInstance(withUid protocolInstanceUid: UID, within obvContext: ObvContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: ReceivedMessage.entityName)
        request.predicate = NSPredicate(format: "%K == %@", ReceivedMessage.protocolInstanceUidKey, protocolInstanceUid)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        _ = try obvContext.execute(deleteRequest)
    }
    
    static func getAll(delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> [ReceivedMessage] {
        let request: NSFetchRequest<ReceivedMessage> = ReceivedMessage.fetchRequest()
        let items = try obvContext.fetch(request)
        return items.map { $0.delegateManager = delegateManager; return $0 }
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
