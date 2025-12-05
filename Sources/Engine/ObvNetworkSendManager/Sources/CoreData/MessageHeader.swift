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
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


@objc(MessageHeader)
final class MessageHeader: NSManagedObject {

    // MARK: Internal constants
    
    private static let entityName = "MessageHeader"
    
    // MARK: Attributes
    
    @NSManaged private var rawDeviceUid: Data? // Non-optional in the model, raw value of an UID
    @NSManaged private var rawMessageIdOwnedIdentity: Data // Required to enforce core data constraints
    @NSManaged private var rawMessageIdUid: Data // Required to enforce core data constraints
    @NSManaged private var rawToCryptoIdentity: Data? // Non-optional in the model
    @NSManaged private var rawWrappedKey: Data? // Non-optional in the model, data of an EncryptedData
    
    // MARK: Relationships
    
    // Should never be nil, it should be cascade deleted if the message is deleted.
    private var message: OutboxMessage? {
        get {
            let value = kvoSafePrimitiveValue(forKey: Predicate.Key.message.rawValue) as? OutboxMessage
            return value
        }
        set {
            guard let newValue = newValue, let messageId = newValue.messageId else {
                assertionFailure()
                return
            }
            self.messageId = messageId
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.message.rawValue)
        }
    }
    
    // MARK: Other variables
    
    var deviceUid: UID {
        get throws(ObvError) {
            guard let rawDeviceUid else { assertionFailure(); throw .unexpectedNilValue }
            guard let deviceUid = UID(uid: rawDeviceUid) else { assertionFailure(); throw .couldNotParseValue }
            return deviceUid
        }
    }
    
    var wrappedKey: EncryptedData {
        get throws(ObvError) {
            guard let rawWrappedKey else { assertionFailure(); throw .unexpectedNilValue }
            return EncryptedData(data: rawWrappedKey)
        }
    }
    
    var toCryptoIdentity: ObvCryptoIdentity {
        get throws(ObvError) {
            guard let rawToCryptoIdentity else { assertionFailure(); throw .unexpectedNilValue }
            guard let toCryptoIdentity = ObvCryptoIdentity(from: rawToCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
            return toCryptoIdentity
        }
    }
    
    private(set) var messageId: ObvMessageIdentifier {
        get { return ObvMessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }

    // MARK: - Initializer
    
    convenience init(message: OutboxMessage, toCryptoIdentity: ObvCryptoIdentity, deviceUid: UID, wrappedKey: EncryptedData) throws(ObvError) {
        
        guard let context = message.managedObjectContext else { assertionFailure(); throw .noContext }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: MessageHeader.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        guard let messageId = message.messageId else {
            assertionFailure()
            throw .noMessageId
        }
        
        self.rawToCryptoIdentity = toCryptoIdentity.getIdentity()
        self.rawDeviceUid = deviceUid.raw
        self.rawWrappedKey = wrappedKey.raw
        
        self.message = message
        self.messageId = messageId
    }

    enum ObvError: Error {
        case unexpectedNilValue
        case couldNotParseValue
        case noMessageId
        case noContext
    }
    
}


extension MessageHeader {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case rawDeviceUid = "rawDeviceUid"
            case rawMessageIdOwnedIdentity = "rawMessageIdOwnedIdentity"
            case rawMessageIdUid = "rawMessageIdUid"
            case rawToCryptoIdentity = "rawToCryptoIdentity"
            case rawWrappedKey = "rawWrappedKey"
            // Relationships
            case message = "message"
        }
        static var withoutMessage: NSPredicate {
            NSPredicate(withNilValueForKey: Key.message)
        }
    }
    
    
    static func deleteAllOrphanedHeaders(within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: MessageHeader.entityName)
        fetchRequest.predicate = Predicate.withoutMessage
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
