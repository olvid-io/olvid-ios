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

    @NSManaged private(set) var insertionDate: Date? // Local date when this DeletedOutboxMessage was inserted in database, expected to be non nil
    @NSManaged private var rawMessageIdOwnedIdentity: Data
    @NSManaged private var rawMessageIdUid: Data
    @NSManaged private(set) var timestampFromServer: Date

    // MARK: Other variables

    private(set) var messageId: ObvMessageIdentifier {
        get { return ObvMessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }

    weak var delegateManager: ObvNetworkSendDelegateManager?
    weak var obvContext: ObvContext?

    private convenience init(messageId: ObvMessageIdentifier, timestampFromServer: Date, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: DeletedOutboxMessage.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.messageId = messageId
        self.timestampFromServer = timestampFromServer
        self.delegateManager = delegateManager
        self.insertionDate = Date()
    }
    
    static func getOrCreate(messageId: ObvMessageIdentifier, timestampFromServer: Date, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> DeletedOutboxMessage {
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
            case insertionDate = "insertionDate"
            case rawMessageIdOwnedIdentity = "rawMessageIdOwnedIdentity"
            case rawMessageIdUid = "rawMessageIdUid"
            case timestampFromServer = "timestampFromServer"
        }
        
        static func withMessageId(_ messageId: ObvMessageIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.rawMessageIdOwnedIdentity, EqualToData: messageId.ownedCryptoIdentity.getIdentity()),
                NSPredicate(Key.rawMessageIdUid, EqualToData: messageId.uid.raw),
            ])
        }
        
        static func withTimestampFromServer(earlierOrEqualTo date: Date) -> NSPredicate {
            NSPredicate(Key.timestampFromServer, earlierOrEqualTo: date)
        }
        
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<DeletedOutboxMessage> {
        return NSFetchRequest<DeletedOutboxMessage>(entityName: DeletedOutboxMessage.entityName)
    }

    static func getAll(delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> [DeletedOutboxMessage] {
        let request: NSFetchRequest<DeletedOutboxMessage> = DeletedOutboxMessage.fetchRequest()
        request.propertiesToFetch = [
            Predicate.Key.rawMessageIdOwnedIdentity.rawValue,
            Predicate.Key.rawMessageIdUid.rawValue,
            Predicate.Key.timestampFromServer.rawValue,
        ]
        let items = try obvContext.fetch(request)
        return items.map { $0.delegateManager = delegateManager; return $0 }
    }
    
    private static func getDeletedOutboxMessage(messageId: ObvMessageIdentifier, delegateManager: ObvNetworkSendDelegateManager, within obvContext: ObvContext) throws -> DeletedOutboxMessage? {
        let request: NSFetchRequest<DeletedOutboxMessage> = DeletedOutboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageId(messageId)
        request.fetchLimit = 1
        let item = try obvContext.fetch(request).first
        item?.delegateManager = delegateManager
        item?.obvContext = obvContext
        return item
    }
    
    static func batchDelete(messageId: ObvMessageIdentifier, within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: DeletedOutboxMessage.entityName)
        fetchRequest.predicate = Predicate.withMessageId(messageId)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        _ = try obvContext.execute(deleteRequest)
    }

    
    static func batchDelete(withTimestampFromServerEarlierOrEqualTo date: Date, within obvContext: ObvContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: DeletedOutboxMessage.entityName)
        request.predicate = Predicate.withTimestampFromServer(earlierOrEqualTo: date)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        _ = try obvContext.execute(deleteRequest)
    }

    
    static func batchDelete(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: DeletedOutboxMessage.entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", Predicate.Key.rawMessageIdOwnedIdentity.rawValue, ownedCryptoIdentity.getIdentity() as NSData)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        _ = try obvContext.execute(request)
    }
    
}


// MARK: Did save

extension DeletedOutboxMessage {
    
    override func didSave() {
        
        guard !isDeleted else { return }

        let logger = Logger(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: DeletedOutboxMessage.entityName)

        guard let delegateManager = delegateManager else {
            logger.fault("The Outbox Message Delegate is not set")
            assertionFailure()
            return
        }
        
        if isInserted, let flowId = self.obvContext?.flowId {
            
            // The following notification is particularly useful when sending a message/attachments using the share extension. In that case,
            // the share extension is the one that creates this DeletedOutboxMessage. It does not dismiss until the flow is ended,
            // i.e., until this DeletedOutboxMessage is created. This flow ends thanks to the ObvNetworkPostNotification.deletedOutboxMessageWasCreated
            // sent below by the networkSendFlowDelegate.
            
            let messageId = self.messageId
            Task {
                await delegateManager.networkSendFlowDelegate.deletedOutboxMessageWasCreated(messageId: messageId, flowId: flowId)
            }
            
        }
        
    }
    
}
