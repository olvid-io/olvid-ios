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
import ObvCrypto
import ObvTypes
import OlvidUtils


@objc(ChannelCreationPingSignatureReceived)
final class ChannelCreationPingSignatureReceived: NSManagedObject, ObvManagedObject {
        
    // MARK: Internal constants

    private static let entityName = "ChannelCreationPingSignatureReceived"
    private static let rawContactDeviceUidKey = "rawContactDeviceUid"
    private static let rawContactIdentityKey = "rawContactIdentity"
    private static let rawOwnedIdentityKey = "rawOwnedIdentity"
    private static let signatureKey = "signature"

    // MARK: Attributes

    @NSManaged private var rawContactDeviceUid: Data
    @NSManaged private var rawContactIdentity: Data
    @NSManaged private var rawOwnedIdentity: Data
    @NSManaged private var signature: Data

    // MARK: Variables
    
    private var contactDeviceUid: UID {
        get { UID(uid: rawContactDeviceUid)! }
        set { rawContactDeviceUid = newValue.raw }
    }
    
    private var contactIdentity: ObvCryptoIdentity {
        get { ObvCryptoIdentity(from: rawContactIdentity)! }
        set { rawContactIdentity = newValue.getIdentity() }
    }
    
    private var ownedIdentity: ObvCryptoIdentity {
        get { ObvCryptoIdentity(from: rawOwnedIdentity)! }
        set { rawOwnedIdentity = newValue.getIdentity() }
    }
    
    var obvContext: ObvContext?

    // MARK: - Initializer

    convenience init?(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, contactDeviceUID: UID, signature: Data, within obvContext: ObvContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ChannelCreationPingSignatureReceived.entityName,
                                                           in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)

        self.contactDeviceUid = contactDeviceUID
        self.contactIdentity = contactCryptoIdentity
        self.ownedIdentity = ownedCryptoIdentity
        self.signature = signature
        
    }
    
}


// MARK: - Convenience DB getters

extension ChannelCreationPingSignatureReceived {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ChannelCreationPingSignatureReceived> {
        return NSFetchRequest<ChannelCreationPingSignatureReceived>(entityName: ChannelCreationPingSignatureReceived.entityName)
    }

    private struct Predicate {
        static func withContactDeviceUid(_ contactDeviceUid: UID) -> NSPredicate {
            NSPredicate(format: "%K == %@",
                        ChannelCreationPingSignatureReceived.rawContactDeviceUidKey,
                        contactDeviceUid.raw as NSData)
        }
        static func withContactIdentityKey(_ contactIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(format: "%K == %@",
                        ChannelCreationPingSignatureReceived.rawContactIdentityKey,
                        contactIdentity.getIdentity() as NSData)
        }
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(format: "%K == %@",
                        ChannelCreationPingSignatureReceived.rawOwnedIdentityKey,
                        ownedCryptoIdentity.getIdentity() as NSData)
        }
        static func withSignature(_ signature: Data) -> NSPredicate {
            NSPredicate(format: "%K == %@",
                        ChannelCreationPingSignatureReceived.signatureKey,
                        signature as NSData)
        }
    }
    
    static func exists(ownedCryptoIdentity: ObvCryptoIdentity, contactCryptoIdentity: ObvCryptoIdentity, contactDeviceUID: UID, signature: Data, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<ChannelCreationPingSignatureReceived> = ChannelCreationPingSignatureReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactDeviceUid(contactDeviceUID),
            Predicate.withContactIdentityKey(contactCryptoIdentity),
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
            Predicate.withSignature(signature),
        ])
        let count = try obvContext.count(for: request)
        return count > 0
    }
    
    static func deleteAllAssociatedWithOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<ChannelCreationPingSignatureReceived> = ChannelCreationPingSignatureReceived.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity)
        request.fetchBatchSize = 100
        request.includesPropertyValues = false
        let items = try obvContext.fetch(request)
        for item in items {
            obvContext.delete(item)
        }
    }
    
    static func deleteAllAssociatedWithContactIdentity(_ contactCryptoIdentity: ObvCryptoIdentity, ownedIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<ChannelCreationPingSignatureReceived> = ChannelCreationPingSignatureReceived.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactIdentityKey(contactCryptoIdentity),
            Predicate.withOwnedCryptoIdentity(ownedIdentity),
        ])
        request.fetchBatchSize = 100
        request.includesPropertyValues = false
        let items = try obvContext.fetch(request)
        for item in items {
            obvContext.delete(item)
        }
    }

}
