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


@objc(ProtocolInstanceWaitingForContactUpgradeToOneToOne)
final class ProtocolInstanceWaitingForContactUpgradeToOneToOne: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "ProtocolInstanceWaitingForContactUpgradeToOneToOne"
    private static func makeError(message: String) -> Error { NSError(domain: "ProtocolInstanceWaitingForContactUpgradeToOneToOne", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: Attributes
    
    @NSManaged private(set) var contactCryptoIdentity: ObvCryptoIdentity
    @NSManaged private(set) var messageToSendRawId: Int
    @NSManaged private(set) var ownedCryptoIdentity: ObvCryptoIdentity
    
    // MARK: Relationships
    
    private(set) var protocolInstance: ProtocolInstance {
        get {
            let item = kvoSafePrimitiveValue(forKey: Predicate.Key.protocolInstance.rawValue) as! ProtocolInstance
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.protocolInstance.rawValue)
        }
    }
    
    // MARK: Other variables
    
    weak var delegateManager: ObvProtocolDelegateManager?
    var obvContext: ObvContext?
    
    // MARK: - Initializer
    
    convenience init?(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, messageToSendRawId: Int, protocolInstance: ProtocolInstance, delegateManager: ObvProtocolDelegateManager) {
        
        guard let obvContext = protocolInstance.obvContext else { return nil }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ProtocolInstanceWaitingForContactUpgradeToOneToOne.entityName,
                                                           in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        self.contactCryptoIdentity = contactCryptoIdentity
        self.messageToSendRawId = messageToSendRawId
        self.ownedCryptoIdentity = ownedCryptoIdentity
        
        self.protocolInstance = protocolInstance
        
        self.delegateManager = delegateManager
    }

}


// MARK: - Convenience DB getters

extension ProtocolInstanceWaitingForContactUpgradeToOneToOne {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> {
        return NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne>(entityName: ProtocolInstanceWaitingForContactUpgradeToOneToOne.entityName)
    }

    private struct Predicate {
        enum Key: String {
            case ownedCryptoIdentity = "ownedCryptoIdentity"
            case protocolInstance = "protocolInstance"
            case contactCryptoIdentity = "contactCryptoIdentity"
            static var protocolInstanceUid: String { [protocolInstance.rawValue, ProtocolInstance.uidKey].joined(separator: ".") }
        }
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(format: "%K == %@", Key.ownedCryptoIdentity.rawValue, ownedCryptoIdentity)
        }
        static func withContactCryptoIdentity(_ contactCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(format: "%K == %@", Key.contactCryptoIdentity.rawValue, contactCryptoIdentity)
        }
        static func withAssociatedProtocolInstance(_ protocolInstance: ProtocolInstance) -> NSPredicate {
            NSPredicate(Key.protocolInstance, equalTo: protocolInstance)
        }
    }
    
    
//    static func get(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, contactNewTrustLevel: TrustLevel, contactNewOneToOne: Bool, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> Set<ProtocolInstanceWaitingForContactUpgradeToOneToOne> {
//
//        let request: NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> = ProtocolInstanceWaitingForContactUpgradeToOneToOne.fetchRequest()
//        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
//            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
//            Predicate.withContactCryptoIdentity(contactCryptoIdentity),
//        ])
//        let items = try obvContext.fetch(request)
//        let filteredItems = items
//            .filter { $0.targetTrustLevel <= contactNewTrustLevel }
//            .filter { !$0.oneToOneRequired ||  contactNewOneToOne }
//        return Set(filteredItems.map { $0.delegateManager = delegateManager; return $0 })
//    }
    
    static func getAll(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> Set<ProtocolInstanceWaitingForContactUpgradeToOneToOne> {
        
        let request: NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> = ProtocolInstanceWaitingForContactUpgradeToOneToOne.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
            Predicate.withContactCryptoIdentity(contactCryptoIdentity),
        ])

        let items = try obvContext.fetch(request)
        return Set(items.map { $0.delegateManager = delegateManager; return $0 })

    }

    
    static func getAll(delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> Set<ProtocolInstanceWaitingForContactUpgradeToOneToOne> {
        
        let request: NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> = ProtocolInstanceWaitingForContactUpgradeToOneToOne.fetchRequest()
        let items = try obvContext.fetch(request)
        return Set(items.map { $0.delegateManager = delegateManager; return $0 })

    }
    
    static func deleteAllRelatedToProtocolInstance(_ protocolInstance: ProtocolInstance, delegateManager: ObvProtocolDelegateManager) throws {
        
        guard let obvContext = protocolInstance.obvContext else { throw NSError() }
        
        let request: NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> = ProtocolInstanceWaitingForContactUpgradeToOneToOne.fetchRequest()
        request.predicate = Predicate.withAssociatedProtocolInstance(protocolInstance)
        let items = try obvContext.fetch(request)
        for item in items {
            item.delegateManager = delegateManager
            obvContext.delete(item)
        }

    }

    static func deleteRelatedToProtocolInstance(_ protocolInstance: ProtocolInstance, contactCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager) throws {
        
        guard let obvContext = protocolInstance.obvContext else { throw NSError() }
        
        let request: NSFetchRequest<ProtocolInstanceWaitingForContactUpgradeToOneToOne> = ProtocolInstanceWaitingForContactUpgradeToOneToOne.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withAssociatedProtocolInstance(protocolInstance),
            Predicate.withContactCryptoIdentity(contactCryptoIdentity),
        ])
        let items = try obvContext.fetch(request)
        for item in items {
            item.delegateManager = delegateManager
            obvContext.delete(item)
        }
        
    }

    func getGenericProtocolMessageToSendWhenContactReachesTargetTrustLevel() -> GenericProtocolMessageToSend {
        let message = GenericProtocolMessageToSend(channelType: .Local(ownedIdentity: self.ownedCryptoIdentity),
                                                   cryptoProtocolId: self.protocolInstance.cryptoProtocolId,
                                                   protocolInstanceUid: self.protocolInstance.uid,
                                                   protocolMessageRawId: self.messageToSendRawId,
                                                   encodedInputs: [contactCryptoIdentity.obvEncode()])
        return message
    }
}
