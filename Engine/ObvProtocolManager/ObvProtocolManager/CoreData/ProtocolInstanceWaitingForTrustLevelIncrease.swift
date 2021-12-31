/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


@objc(ProtocolInstanceWaitingForTrustLevelIncrease)
final class ProtocolInstanceWaitingForTrustLevelIncrease: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "ProtocolInstanceWaitingForTrustLevelIncrease"
    private static let protocolInstanceKey = "protocolInstance"
    private static let protocolInstanceUidKey = [protocolInstanceKey, ProtocolInstance.uidKey].joined(separator: ".")
    private static let contactCryptoIdentityKey = "contactCryptoIdentity"
    private static let ownedCryptoIdentityKey = "ownedCryptoIdentity"
    
    // MARK: Attributes
    
    @NSManaged private(set) var contactCryptoIdentity: ObvCryptoIdentity
    @NSManaged private(set) var messageToSendRawId: Int
    @NSManaged private(set) var ownedCryptoIdentity: ObvCryptoIdentity
    @NSManaged private var targetTrustLevelRaw: String
    
    // MARK: Relationships
    
    private(set) var protocolInstance: ProtocolInstance {
        get {
            let item = kvoSafePrimitiveValue(forKey: ProtocolInstanceWaitingForTrustLevelIncrease.protocolInstanceKey) as! ProtocolInstance
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ProtocolInstanceWaitingForTrustLevelIncrease.protocolInstanceKey)
        }
    }
    
    // MARK: Other variables
    
    weak var delegateManager: ObvProtocolDelegateManager?
    var obvContext: ObvContext?
    private(set) var targetTrustLevel: TrustLevel {
        get { return TrustLevel(rawValue: self.targetTrustLevelRaw)! }
        set { self.targetTrustLevelRaw = newValue.rawValue }
    }
    
    // MARK: - Initializer
    
    convenience init?(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, targetTrustLevel: TrustLevel, messageToSendRawId: Int, protocolInstance: ProtocolInstance, delegateManager: ObvProtocolDelegateManager) {
        
        guard let obvContext = protocolInstance.obvContext else { return nil }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ProtocolInstanceWaitingForTrustLevelIncrease.entityName,
                                                           in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        self.contactCryptoIdentity = contactCryptoIdentity
        self.messageToSendRawId = messageToSendRawId
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.targetTrustLevel = targetTrustLevel
        
        self.protocolInstance = protocolInstance
        
        self.delegateManager = delegateManager
    }

}


// MARK: - Convenience DB getters

extension ProtocolInstanceWaitingForTrustLevelIncrease {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<ProtocolInstanceWaitingForTrustLevelIncrease> {
        return NSFetchRequest<ProtocolInstanceWaitingForTrustLevelIncrease>(entityName: ProtocolInstanceWaitingForTrustLevelIncrease.entityName)
    }

    static func get(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, maxTrustLevel: TrustLevel, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> Set<ProtocolInstanceWaitingForTrustLevelIncrease> {
        
        let request: NSFetchRequest<ProtocolInstanceWaitingForTrustLevelIncrease> = ProtocolInstanceWaitingForTrustLevelIncrease.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        ownedCryptoIdentityKey, ownedCryptoIdentity,
                                        contactCryptoIdentityKey, contactCryptoIdentity)
        let items = try obvContext.fetch(request)
        let filteredItems = items.filter { $0.targetTrustLevel < maxTrustLevel }
        return Set(filteredItems.map { $0.delegateManager = delegateManager; return $0 })
    }
    
    
    static func getAll(delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> Set<ProtocolInstanceWaitingForTrustLevelIncrease> {
        
        let request: NSFetchRequest<ProtocolInstanceWaitingForTrustLevelIncrease> = ProtocolInstanceWaitingForTrustLevelIncrease.fetchRequest()
        let items = try obvContext.fetch(request)
        return Set(items.map { $0.delegateManager = delegateManager; return $0 })

    }
    
    static func deleteAllRelatedToProtocolInstance(_ protocolInstance: ProtocolInstance, delegateManager: ObvProtocolDelegateManager) throws {
        
        guard let obvContext = protocolInstance.obvContext else { throw NSError() }
        
        let request: NSFetchRequest<ProtocolInstanceWaitingForTrustLevelIncrease> = ProtocolInstanceWaitingForTrustLevelIncrease.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", protocolInstanceKey, protocolInstance)
        let items = try obvContext.fetch(request)
        for item in items {
            item.delegateManager = delegateManager
            obvContext.delete(item)
        }

    }

    static func deleteRelatedToProtocolInstance(_ protocolInstance: ProtocolInstance, contactCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager) throws {
        
        guard let obvContext = protocolInstance.obvContext else { throw NSError() }
        
        let request: NSFetchRequest<ProtocolInstanceWaitingForTrustLevelIncrease> = ProtocolInstanceWaitingForTrustLevelIncrease.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        protocolInstanceKey, protocolInstance,
                                        contactCryptoIdentityKey, contactCryptoIdentity)
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
                                                   encodedInputs: [contactCryptoIdentity.encode()])
        return message
    }
}
