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

@objc(DeletedOutboxMessage)
final class DeletedOutboxMessage: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "DeletedOutboxMessage"
    
    private static let errorDomain = "DeletedOutboxMessage"

    // MARK: Attributes

    @NSManaged private var rawMessageIdOwnedIdentity: Data
    @NSManaged private var rawMessageIdUid: Data
    @NSManaged private(set) var timestampFromServer: Date

    // MARK: Other variables

    private(set) var messageId: MessageIdentifier {
        get { return MessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }

    weak var delegateManager: ObvNetworkSendDelegateManager?
    var obvContext: ObvContext?

    private convenience init(messageId: MessageIdentifier, timestampFromServer: Date, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: DeletedOutboxMessage.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.messageId = messageId
        self.timestampFromServer = timestampFromServer
        self.delegateManager = delegateManager
    }
    
    static func getOrCreate(messageId: MessageIdentifier, timestampFromServer: Date, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> DeletedOutboxMessage {
        if let existingDeletedOutboxMessage = try DeletedOutboxMessage.getDeletedOutboxMessage(messageId: messageId, delegateManager: delegateManager, within: obvContext) {
            assertionFailure("In practice, this should never occur")
            return existingDeletedOutboxMessage
        }
        return DeletedOutboxMessage(messageId: messageId, timestampFromServer: timestampFromServer, delegateManager: delegateManager, within: obvContext)
    }
        
}


// MARK: - Convenience DB getters

extension DeletedOutboxMessage {
    
    struct Predicate {
        
        enum Key: String {
            case rawMessageIdOwnedIdentity = "rawMessageIdOwnedIdentity"
            case rawMessageIdUid = "rawMessageIdUid"
            case timestampFromServer = "timestampFromServer"
        }
        
        static func withMessageId(_ messageId: MessageIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawMessageIdOwnedIdentity, EqualToData: messageId.ownedCryptoIdentity.getIdentity()),
                NSPredicate(Key.rawMessageIdUid, EqualToData: messageId.uid.raw),
            ])
        }

    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<DeletedOutboxMessage> {
        return NSFetchRequest<DeletedOutboxMessage>(entityName: DeletedOutboxMessage.entityName)
    }

    static func getAll(delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> [DeletedOutboxMessage] {
        let request: NSFetchRequest<DeletedOutboxMessage> = DeletedOutboxMessage.fetchRequest()
        let items = try obvContext.fetch(request)
        return items.map { $0.delegateManager = delegateManager; return $0 }
    }
    
    private static func getDeletedOutboxMessage(messageId: MessageIdentifier, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> DeletedOutboxMessage? {
        let request: NSFetchRequest<DeletedOutboxMessage> = DeletedOutboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageId(messageId)
        request.fetchLimit = 1
        let item = try obvContext.fetch(request).first
        item?.delegateManager = delegateManager
        item?.obvContext = obvContext
        return item
    }
    
    static func batchDelete(messageIds: [MessageIdentifier], within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: DeletedOutboxMessage.entityName)
        var predicates = [NSPredicate]()
        for ownedIdentity in Set(messageIds.map({$0.ownedCryptoIdentity})) {
            let messageIdsOfOwnedIdentity = Set(messageIds.filter({ $0.ownedCryptoIdentity == ownedIdentity }).map({ $0.uid.raw as NSData }))
            let predicate = NSPredicate(format: "%K IN %@ AND %K == %@",
                                        Predicate.Key.rawMessageIdUid.rawValue, messageIdsOfOwnedIdentity as NSSet,
                                        Predicate.Key.rawMessageIdOwnedIdentity.rawValue, ownedIdentity.getIdentity() as NSData)
            predicates.append(predicate)
        }
        fetchRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        _ = try obvContext.execute(request)
    }
    
    
    static func batchDelete(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: DeletedOutboxMessage.entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", Predicate.Key.rawMessageIdOwnedIdentity.rawValue, ownedCryptoIdentity.getIdentity() as NSData)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        _ = try obvContext.execute(request)
    }
    
}
