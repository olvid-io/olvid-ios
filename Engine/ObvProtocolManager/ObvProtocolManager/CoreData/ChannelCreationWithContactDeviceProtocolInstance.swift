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
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


/// This database is only used within the channel creation protocol (with a contact identity) between the current device of the owned identity and the contact device
@objc(ChannelCreationWithContactDeviceProtocolInstance)
final class ChannelCreationWithContactDeviceProtocolInstance: NSManagedObject, ObvManagedObject {

    // MARK: Internal constants
    
    private static let entityName = "ChannelCreationWithContactDeviceProtocolInstance"
    private static let contactIdentityKey = "contactIdentity"
    private static let contactDeviceUidKey = "contactDeviceUid"
    private static let protocolInstanceKey = "protocolInstance"
    private static let protocolInstanceOwnedCryptoIdentityKey = [protocolInstanceKey, ProtocolInstance.Predicate.Key.ownedCryptoIdentity.rawValue].joined(separator: ".")
    private static let protocolInstanceUidKey = [protocolInstanceKey, ProtocolInstance.Predicate.Key.uid.rawValue].joined(separator: ".")
    
    // MARK: Attributes
    
    @NSManaged private(set) var contactIdentity: ObvCryptoIdentity
    @NSManaged private(set) var contactDeviceUid: UID
    
    // MARK: Relationships
    
    // Primary key (enforced by a one-to-one relationship). This is necessarily a ChannelCreationWithContactDevice protocol instance.
    private(set) var protocolInstance: ProtocolInstance {
        get {
            let item = kvoSafePrimitiveValue(forKey: ChannelCreationWithContactDeviceProtocolInstance.protocolInstanceKey) as! ProtocolInstance
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ChannelCreationWithContactDeviceProtocolInstance.protocolInstanceKey)
        }
    }

    // MARK: Other variables
    
    var ownedCryptoIdentity: ObvCryptoIdentity {
        return protocolInstance.ownedCryptoIdentity
    }
    
    var obvContext: ObvContext?
    
    // MARK: - Initializer
    
    convenience init?(protocolInstanceUid: UID, ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ChannelCreationWithContactDeviceProtocolInstance.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        guard let protocolInstance = ProtocolInstance.get(cryptoProtocolId: CryptoProtocolId.ChannelCreationWithContactDevice,
                                                          uid: protocolInstanceUid,
                                                          ownedIdentity: ownedIdentity,
                                                          delegateManager: delegateManager,
                                                          within: obvContext) else { return nil }
        self.protocolInstance = protocolInstance
        self.contactIdentity = contactIdentity
        self.contactDeviceUid = contactDeviceUid
    }

}


// MARK: - Convenience DB getters
extension ChannelCreationWithContactDeviceProtocolInstance {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance> {
        return NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance>(entityName: ChannelCreationWithContactDeviceProtocolInstance.entityName)
    }
    
    static func getUidofChannelCreationProtocolInstanceBetween(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, andOwnedIdentity ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) -> UID? {
        let request: NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance> = ChannelCreationWithContactDeviceProtocolInstance.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                                        contactIdentityKey, contactIdentity,
                                        contactDeviceUidKey, contactDeviceUid,
                                        protocolInstanceOwnedCryptoIdentityKey, ownedCryptoIdentity)
        let item = (try? obvContext.fetch(request))?.first
        return item?.protocolInstance.uid
    }
    
    static func delete(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, andOwnedIdentity ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> UID? {
        let request: NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance> = ChannelCreationWithContactDeviceProtocolInstance.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                                        contactIdentityKey, contactIdentity,
                                        contactDeviceUidKey, contactDeviceUid,
                                        protocolInstanceOwnedCryptoIdentityKey, ownedCryptoIdentity)
        guard let item = (try obvContext.fetch(request)).first else {
            let log = OSLog(subsystem: ObvProtocolDelegateManager.defaultLogSubsystem, category: ChannelCreationWithContactDeviceProtocolInstance.entityName)
            os_log("Did not find a ChannelCreationProtocolInstanceInWaitingState to delete", log: log, type: .error)
            return nil
        }
        let protocolInstanceUid = item.protocolInstance.uid
        obvContext.delete(item)
        return protocolInstanceUid
    }
    
    static func exists(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, andOwnedIdentity ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance> = ChannelCreationWithContactDeviceProtocolInstance.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                                        contactDeviceUidKey, contactDeviceUid,
                                        contactIdentityKey, contactIdentity,
                                        protocolInstanceOwnedCryptoIdentityKey, ownedCryptoIdentity)
        return try obvContext.count(for: request) != 0
    }
    
    static func getAll(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifierAlt> {
        let request: NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance> = ChannelCreationWithContactDeviceProtocolInstance.fetchRequest()
        request.fetchBatchSize = 1_000
        let items = try obvContext.fetch(request)
        return Set(items.map({ ObliviousChannelIdentifierAlt(ownedCryptoIdentity: $0.ownedCryptoIdentity, remoteCryptoIdentity: $0.contactIdentity, remoteDeviceUid: $0.contactDeviceUid) }))
    }
}
