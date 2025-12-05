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

@objc(DeletedOutboxMessage)
final class DeletedOutboxMessage: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "DeletedOutboxMessage"
    private static let errorDomain = "DeletedOutboxMessage"
    static weak var delegateManager: ObvNetworkSendDelegateManager?

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

    private convenience init(messageId: ObvMessageIdentifier, timestampFromServer: Date, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: DeletedOutboxMessage.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.messageId = messageId
        self.timestampFromServer = timestampFromServer
        self.insertionDate = Date()
    }
    
    static func getOrCreate(messageId: ObvMessageIdentifier, timestampFromServer: Date, within context: NSManagedObjectContext) throws -> DeletedOutboxMessage {
        if let existingDeletedOutboxMessage = try DeletedOutboxMessage.getDeletedOutboxMessage(messageId: messageId, within: context) {
            assertionFailure("In practice, this should never occur")
            return existingDeletedOutboxMessage
        }
        return DeletedOutboxMessage(messageId: messageId, timestampFromServer: timestampFromServer, within: context)
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
        
        static func withOwnedCryptoId(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawMessageIdOwnedIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
        
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<DeletedOutboxMessage> {
        return NSFetchRequest<DeletedOutboxMessage>(entityName: DeletedOutboxMessage.entityName)
    }

    static func getAll(within context: NSManagedObjectContext) throws -> [DeletedOutboxMessage] {
        let request: NSFetchRequest<DeletedOutboxMessage> = DeletedOutboxMessage.fetchRequest()
        request.propertiesToFetch = [
            Predicate.Key.rawMessageIdOwnedIdentity.rawValue,
            Predicate.Key.rawMessageIdUid.rawValue,
            Predicate.Key.timestampFromServer.rawValue,
        ]
        let items = try context.fetch(request)
        return items
    }
    
    private static func getDeletedOutboxMessage(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws -> DeletedOutboxMessage? {
        let request: NSFetchRequest<DeletedOutboxMessage> = DeletedOutboxMessage.fetchRequest()
        request.predicate = Predicate.withMessageId(messageId)
        request.fetchLimit = 1
        let item = try context.fetch(request).first
        return item
    }
    
    static func batchDelete(messageId: ObvMessageIdentifier, within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: DeletedOutboxMessage.entityName)
        fetchRequest.predicate = Predicate.withMessageId(messageId)
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

    
    static func batchDelete(withTimestampFromServerEarlierOrEqualTo date: Date, within context: NSManagedObjectContext) throws {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: DeletedOutboxMessage.entityName)
        request.predicate = Predicate.withTimestampFromServer(earlierOrEqualTo: date)
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

    
    static func batchDelete(ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: DeletedOutboxMessage.entityName)
        fetchRequest.predicate = Predicate.withOwnedCryptoId(ownedCryptoIdentity)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        request.resultType = .resultTypeObjectIDs
        let result = try context.execute(request) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
}


// MARK: Did save

extension DeletedOutboxMessage {
    
    override func didSave() {
        
        guard !isDeleted else { return }

        let logger = Logger(subsystem: ObvNetworkSendDelegateManager.defaultLogSubsystem, category: DeletedOutboxMessage.entityName)

        guard let delegateManager = Self.delegateManager else {
            logger.fault("The Outbox Message Delegate is not set")
            assertionFailure()
            return
        }
        
        if isInserted {
            
            // The following notification is particularly useful when sending a message/attachments using the share extension. In that case,
            // the share extension is the one that creates this DeletedOutboxMessage. It does not dismiss until the flow is ended,
            // i.e., until this DeletedOutboxMessage is created. This flow ends thanks to the ObvNetworkPostNotification.deletedOutboxMessageWasCreated
            // sent below by the networkSendFlowDelegate.
            
            let messageId = self.messageId
            Task {
                await delegateManager.networkSendFlowDelegate.deletedOutboxMessageWasCreated(messageId: messageId, flowId: FlowIdentifier())
            }
            
        }
        
    }
    
}
