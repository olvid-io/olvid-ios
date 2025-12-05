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


@objc(ProtocolInstanceWaitingForContactUpgradeToOneToOne)
final class ProtocolInstanceWaitingForContactUpgradeToOneToOne: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "ProtocolInstanceWaitingForContactUpgradeToOneToOne"

    // MARK: Attributes
    
    @NSManaged private(set) var messageToSendRawId: Int
    @NSManaged private(set) var rawContactCryptoIdentity: Data? // Non-optional in the model
    @NSManaged private(set) var rawOwnedCryptoIdentity: Data? // Non-optional in the model
    
    // MARK: Relationships
    
    @NSManaged private(set) var protocolInstance: ProtocolInstance
    
    // MARK: Other variables
    
    var ownedCryptoIdentity: ObvCryptoIdentity {
        get throws(ObvError) {
            guard let rawOwnedCryptoIdentity else { assertionFailure(); throw .unexpectedNilValue }
            guard let ownedCryptoIdentity = ObvCryptoIdentity(from: rawOwnedCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
            return ownedCryptoIdentity
        }
    }
    
    var contactCryptoIdentity: ObvCryptoIdentity {
        get throws(ObvError) {
            guard let rawContactCryptoIdentity else { assertionFailure(); throw .unexpectedNilValue }
            guard let contactCryptoIdentity = ObvCryptoIdentity(from: rawContactCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
            return contactCryptoIdentity
        }
    }
    
    // MARK: - Initializer
    
    /// 2025-08-27: ok
    convenience init(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, messageToSendRawId: Int, protocolInstance: ProtocolInstance) throws {
        
        guard let context = protocolInstance.managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ProtocolInstanceWaitingForContactUpgradeToOneToOne.entityName,
                                                           in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.messageToSendRawId = messageToSendRawId
        self.rawContactCryptoIdentity = contactCryptoIdentity.getIdentity()
        self.rawOwnedCryptoIdentity = ownedCryptoIdentity.getIdentity()
        
        self.protocolInstance = protocolInstance
        
    }
    
    
    private func deleteProtocolInstanceWaitingForContactUpgradeToOneToOne() throws {
        guard let managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        managedObjectContext.delete(self)
    }
    
    
    enum ObvError: Error {
        case noContext
        case unexpectedNilValue
        case couldNotParseValue
    }

}


// MARK: - Convenience DB getters

extension ProtocolInstanceWaitingForContactUpgradeToOneToOne {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> {
        return NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne>(entityName: ProtocolInstanceWaitingForContactUpgradeToOneToOne.entityName)
    }

    private struct Predicate {
        enum Key: String {
            // Attributes
            case messageToSendRawId = "messageToSendRawId"
            case rawContactCryptoIdentity = "rawContactCryptoIdentity"
            case rawOwnedCryptoIdentity = "rawOwnedCryptoIdentity"
            // Relationships
            case protocolInstance = "protocolInstance"
            static var protocolInstanceUid: String {
                [
                    protocolInstance.rawValue,
                    ProtocolInstance.Predicate.Key.rawUID.rawValue,
                ].joined(separator: ".") }
        }
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedCryptoIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
        static func withContactCryptoIdentity(_ contactCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawContactCryptoIdentity, EqualToData: contactCryptoIdentity.getIdentity())
        }
        static func withAssociatedProtocolInstance(_ protocolInstance: ProtocolInstance) -> NSPredicate {
            NSPredicate(Key.protocolInstance, equalTo: protocolInstance)
        }
    }
    
    
    static func getAll(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> Set<ProtocolInstanceWaitingForContactUpgradeToOneToOne> {
        let request: NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> = ProtocolInstanceWaitingForContactUpgradeToOneToOne.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
            Predicate.withContactCryptoIdentity(contactCryptoIdentity),
        ])
        let items = try context.fetch(request)
        return Set(items)
    }

    
    static func getAll(within context: NSManagedObjectContext) throws -> Set<ProtocolInstanceWaitingForContactUpgradeToOneToOne> {
        let request: NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> = ProtocolInstanceWaitingForContactUpgradeToOneToOne.fetchRequest()
        let items = try context.fetch(request)
        return Set(items)
    }
    
    
    static func deleteAllRelatedToProtocolInstance(_ protocolInstance: ProtocolInstance) throws {
        guard let context = protocolInstance.managedObjectContext else {
            throw ObvError.noContext
        }
        let request: NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> = ProtocolInstanceWaitingForContactUpgradeToOneToOne.fetchRequest()
        request.predicate = Predicate.withAssociatedProtocolInstance(protocolInstance)
        request.fetchBatchSize = 1_000
        request.propertiesToFetch = []
        let items = try context.fetch(request)
        for item in items {
            try item.deleteProtocolInstanceWaitingForContactUpgradeToOneToOne()
        }
    }
    

    static func deleteRelatedToProtocolInstance(_ protocolInstance: ProtocolInstance, contactCryptoIdentity: ObvCryptoIdentity) throws {
        guard let context = protocolInstance.managedObjectContext else {
            throw ObvError.noContext
        }
        let request: NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> = ProtocolInstanceWaitingForContactUpgradeToOneToOne.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withAssociatedProtocolInstance(protocolInstance),
            Predicate.withContactCryptoIdentity(contactCryptoIdentity),
        ])
        request.fetchBatchSize = 1_000
        request.propertiesToFetch = []
        let items = try context.fetch(request)
        for item in items {
            try item.deleteProtocolInstanceWaitingForContactUpgradeToOneToOne()
        }
    }

    
    func getGenericProtocolMessageToSendWhenContactReachesTargetTrustLevel() throws -> GenericProtocolMessageToSend {
        let message = try GenericProtocolMessageToSend(channelType: .local(ownedIdentity: self.ownedCryptoIdentity),
                                                       cryptoProtocolId: self.protocolInstance.cryptoProtocolId,
                                                       protocolInstanceUid: self.protocolInstance.uid,
                                                       protocolMessageRawId: self.messageToSendRawId,
                                                       encodedInputs: [contactCryptoIdentity.obvEncode()])
        return message
    }
}
