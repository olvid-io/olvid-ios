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
import OlvidUtils

@objc(LinkBetweenProtocolInstances)
class LinkBetweenProtocolInstances: NSManagedObject, ObvManagedObject {

    // MARK: Internal constants
    
    private static let entityName = "LinkBetweenProtocolInstances"
    static let childProtocolInstanceUidKey = "childProtocolInstanceUid"
    private static let expectedChildStateRawIdKey = "expectedChildStateRawId"
    private static let parentProtocolInstanceKey = "parentProtocolInstance"
    private static let parentProtocolInstanceOwnedCryptoIdentityKey = [parentProtocolInstanceKey, ProtocolInstance.ownedCryptoIdentityKey].joined(separator: ".")
    private static let childProtocolInstanceOwnedCryptoIdentityKey = parentProtocolInstanceOwnedCryptoIdentityKey
    private static let parentProtocolInstanceUidKey = [parentProtocolInstanceKey, ProtocolInstance.uidKey].joined(separator: ".")
    
    // MARK: Attributes
    
    // Both the child and parent protocol instances share the same owned identity
    
    @NSManaged private(set) var childProtocolInstanceUid: UID
    @NSManaged private(set) var expectedChildStateRawId: Int
    @NSManaged private(set) var messageToSendRawId: Int // When the child reaches the expected state, a message with this raw id will be sent to the parent protocol
    
    // MARK: Relationships
    
    private(set) var parentProtocolInstance: ProtocolInstance {
        get {
            let item = kvoSafePrimitiveValue(forKey: LinkBetweenProtocolInstances.parentProtocolInstanceKey) as! ProtocolInstance
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: LinkBetweenProtocolInstances.parentProtocolInstanceKey)
        }
    }
    
    // MARK: Other variables
    
    var obvContext: ObvContext?

    var protocolInstancesOwnedIdentity: ObvCryptoIdentity {
        return parentProtocolInstance.ownedCryptoIdentity
    }
    
    var delegateManager: ObvProtocolDelegateManager? {
        return parentProtocolInstance.delegateManager
    }
    
    // MARK: - Initializer
    
    convenience init?(parentProtocolInstance: ProtocolInstance, childProtocolInstanceUid: UID, expectedChildStateRawId: Int, messageToSendRawId: Int) {
        guard let obvContext = parentProtocolInstance.obvContext else { return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: LinkBetweenProtocolInstances.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.childProtocolInstanceUid = childProtocolInstanceUid
        self.expectedChildStateRawId = expectedChildStateRawId
        self.messageToSendRawId = messageToSendRawId
        self.parentProtocolInstance = parentProtocolInstance
    }

}


// MARK: - Convenience DB getters
extension LinkBetweenProtocolInstances {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<LinkBetweenProtocolInstances> {
        return NSFetchRequest<LinkBetweenProtocolInstances>(entityName: LinkBetweenProtocolInstances.entityName)
    }
    
    class func getGenericProtocolMessageToSendWhenChildProtocolInstance(withUid childUid: UID, andOwnedIdentity childOwnedCryptoIdentity: ObvCryptoIdentity, reachesState childState: ConcreteProtocolState, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> [GenericProtocolMessageToSend] {
        let request: NSFetchRequest<LinkBetweenProtocolInstances> = LinkBetweenProtocolInstances.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %d",
                                        childProtocolInstanceUidKey, childUid,
                                        childProtocolInstanceOwnedCryptoIdentityKey, childOwnedCryptoIdentity,
                                        expectedChildStateRawIdKey, childState.rawId)
        guard let links = try? obvContext.fetch(request) else { return [GenericProtocolMessageToSend]() }
        let encodedInputs = try ChildToParentProtocolMessageInputs(childProtocolInstanceUid: childUid,
                                                                   childProtocolInstanceReachedState: childState).toListOfEncoded()
        let messages: [GenericProtocolMessageToSend] = links.map { link in
            return GenericProtocolMessageToSend(channelType: .Local(ownedIdentity: link.parentProtocolInstance.ownedCryptoIdentity),
                                                cryptoProtocolId: link.parentProtocolInstance.cryptoProtocolId,
                                                protocolInstanceUid: link.parentProtocolInstance.uid,
                                                protocolMessageRawId: link.messageToSendRawId,
                                                encodedInputs: encodedInputs)
        }
        return messages
    }
    
    // Normaly, there should be only one parent protocol of a given protocol. But there might be multiple links, since the parent might require to be notified at various states of the child protocol.
    static func getAllLinksForWhichTheChildProtocolHasUid(_ childUid: UID, andOwnedIdentity childOwnedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> [LinkBetweenProtocolInstances] {
        let request: NSFetchRequest<LinkBetweenProtocolInstances> = LinkBetweenProtocolInstances.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        childProtocolInstanceUidKey, childUid,
                                        childProtocolInstanceOwnedCryptoIdentityKey, childOwnedCryptoIdentity)
        let links = try obvContext.fetch(request)
        return links.map { $0.parentProtocolInstance.delegateManager = delegateManager; return $0 }
    }
    
    static func getAllLinksForWhichTheParentProtocolHasUid(_ parentUid: UID, andOwnedIdentity childOwnedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) throws -> [LinkBetweenProtocolInstances] {
        let request: NSFetchRequest<LinkBetweenProtocolInstances> = LinkBetweenProtocolInstances.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        parentProtocolInstanceUidKey, parentUid,
                                        parentProtocolInstanceOwnedCryptoIdentityKey, childOwnedCryptoIdentity)
        let links = try obvContext.fetch(request)
        return links.map { $0.parentProtocolInstance.delegateManager = delegateManager; return $0 }
    }
}
