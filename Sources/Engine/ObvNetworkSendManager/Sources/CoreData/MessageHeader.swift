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
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

@objc(MessageHeader)
final class MessageHeader: NSManagedObject, ObvManagedObject {

    // MARK: Internal constants
    
    private static let entityName = "MessageHeader"
    static private let messageKey = "message"
    static let toCryptoIdentityKey = "toCryptoIdentity"
    
    // MARK: Attributes
    
    @NSManaged private(set) var deviceUid: UID
    @NSManaged private var rawMessageIdOwnedIdentity: Data // Required to enforce core data constraints
    @NSManaged private var rawMessageIdUid: Data // Required to enforce core data constraints
    @NSManaged private(set) var toCryptoIdentity: ObvCryptoIdentity
    @NSManaged private(set) var wrappedKey: EncryptedData
    
    // MARK: Relationships
    
    // Should never be nil, it should be cascade deleted if the message is deleted.
    private var message: OutboxMessage? {
        get {
            let value = kvoSafePrimitiveValue(forKey: MessageHeader.messageKey) as? OutboxMessage
            value?.delegateManager = delegateManager
            value?.obvContext = self.obvContext
            return value
        }
        set {
            guard let newValue = newValue, let messageId = newValue.messageId else {
                assertionFailure()
                return
            }
            if delegateManager == nil {
                delegateManager = newValue.delegateManager
            }
            self.messageId = messageId
            kvoSafeSetPrimitiveValue(newValue, forKey: MessageHeader.messageKey)
        }
    }
    
    // MARK: Other variables
    
    private(set) var messageId: ObvMessageIdentifier {
        get { return ObvMessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }

    weak var delegateManager: ObvNetworkSendDelegateManager?
    weak var obvContext: ObvContext?
    
    // MARK: - Initializer
    
    convenience init?(message: OutboxMessage, toCryptoIdentity: ObvCryptoIdentity, deviceUid: UID, wrappedKey: EncryptedData) {
        
        guard let obvContext = message.obvContext else { return nil }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: MessageHeader.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)

        guard let messageId = message.messageId else {
            assertionFailure()
            return nil
        }
        
        self.toCryptoIdentity = toCryptoIdentity
        self.deviceUid = deviceUid
        self.wrappedKey = wrappedKey
        
        self.message = message
        self.messageId = messageId
    }

}


extension MessageHeader {
    
    static func deleteAllOrphanedHeaders(within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: MessageHeader.entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == NIL", messageKey)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        request.resultType = .resultTypeObjectIDs
        let result = try obvContext.execute(request) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [obvContext.context])
        } else {
            assertionFailure()
        }
    }

    
}
