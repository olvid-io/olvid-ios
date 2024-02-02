/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import OlvidUtils
import ObvMetaManager


/// This database is only used within the channel creation protocol (with an owned identity) between the current device of the owned identity and one of her other device.
@objc(ChannelCreationWithOwnedDeviceProtocolInstance)
final class ChannelCreationWithOwnedDeviceProtocolInstance: NSManagedObject {
    
    private static let entityName = "ChannelCreationWithOwnedDeviceProtocolInstance"

    // MARK: Attributes

    @NSManaged private var rawOwnedIdentityIdentity: Data // Part of the primary key
    @NSManaged private var rawRemoteDeviceUid: Data // Part of the primary key

    // MARK: Relationships

    // This is necessarily a ChannelCreationWithOwnedDevice protocol instance.
    // Expected to be non-nil (optional in the model, mandatory in practice)
    @NSManaged private(set) var protocolInstance: ProtocolInstance?

    // MARK: Other variables
    
    // Expected to be non-nil.
    var ownedCryptoIdentity: ObvCryptoIdentity? {
        return ObvCryptoIdentity(from: rawOwnedIdentityIdentity)
    }
    
    // Expected to be non-nil
    var remoteDeviceUid: UID? {
        UID(uid: self.rawRemoteDeviceUid)
    }

    // MARK: - Initializer

    convenience init?(protocolInstanceUid: UID, ownedIdentity: ObvCryptoIdentity, remoteDeviceUid: UID, delegateManager: ObvProtocolDelegateManager, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        guard let protocolInstance = ProtocolInstance.get(cryptoProtocolId: CryptoProtocolId.channelCreationWithOwnedDevice,
                                                          uid: protocolInstanceUid,
                                                          ownedIdentity: ownedIdentity,
                                                          delegateManager: delegateManager,
                                                          within: obvContext) else { return nil }
        self.protocolInstance = protocolInstance
        self.rawRemoteDeviceUid = remoteDeviceUid.raw
        self.rawOwnedIdentityIdentity = protocolInstance.ownedCryptoIdentity.getIdentity()
    }
    
    
    private func deleteChannelCreationWithOwnedDeviceProtocolInstance() throws {
        guard let context = self.managedObjectContext else { throw ObvError.couldNotFindContext }
        context.delete(self)
    }
    
    
    // MARK: - Convenience DB getters

    @nonobjc class func fetchRequest() -> NSFetchRequest<ChannelCreationWithOwnedDeviceProtocolInstance> {
        return NSFetchRequest<ChannelCreationWithOwnedDeviceProtocolInstance>(entityName: self.entityName)
    }

    struct Predicate {
        enum Key: String {
            // Attributes
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
            case rawRemoteDeviceUid = "rawRemoteDeviceUid"
            // Relationships
            case protocolInstance = "protocolInstance"
        }
        static func withRemoteDeviceUid(_ remoteDeviceUid: UID) -> NSPredicate {
            NSPredicate(Key.rawRemoteDeviceUid, EqualToData: remoteDeviceUid.raw)
        }
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            return NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
    }


    /// Since we there must be at most one `ChannelCreationWithOwnedDeviceProtocolInstance` for a given owned identity and remote device, we expect the array returned by this method to contain either 0 or 1 entry.
    /// Yet, to be more resilient, we return all items found so as to let the protocol stop all protocol instances in all cases.
    static func deleteAll(ownedCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID, within obvContext: ObvContext) throws -> [UID] {
        let request: NSFetchRequest<ChannelCreationWithOwnedDeviceProtocolInstance> = ChannelCreationWithOwnedDeviceProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
            Predicate.withRemoteDeviceUid(remoteDeviceUid),
        ])
        let itemsToDelete = try obvContext.context.fetch(request)
        let protocolInstanceUids = itemsToDelete.compactMap(\.protocolInstance?.uid)
        try itemsToDelete.forEach { itemToDelete in
            try itemToDelete.deleteChannelCreationWithOwnedDeviceProtocolInstance()
        }
        return protocolInstanceUids
    }

    
    static func exists(ownedCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<ChannelCreationWithOwnedDeviceProtocolInstance> = ChannelCreationWithOwnedDeviceProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
            Predicate.withRemoteDeviceUid(remoteDeviceUid),
        ])
        let numberOfEntries = try obvContext.count(for: request)
        return numberOfEntries != 0
    }

    
    static func getAll(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifierAlt> {
        let request: NSFetchRequest<ChannelCreationWithOwnedDeviceProtocolInstance> = ChannelCreationWithOwnedDeviceProtocolInstance.fetchRequest()
        request.fetchBatchSize = 1_000
        let items = try obvContext.context.fetch(request)
        return Set(items.compactMap({
            guard let ownedCryptoIdentity = $0.ownedCryptoIdentity else { assertionFailure(); return nil }
            guard let remoteDeviceUid = $0.remoteDeviceUid else { assertionFailure(); return nil }
            return ObliviousChannelIdentifierAlt(ownedCryptoIdentity: ownedCryptoIdentity, remoteCryptoIdentity: ownedCryptoIdentity, remoteDeviceUid: remoteDeviceUid)
        }))
    }

    // MARK: - Errors
    
    enum ObvError: Error {
        case couldNotFindContext

        var localizedDescription: String {
            switch self {
            case .couldNotFindContext:
                return "Could not find context"
            }
        }
    }
    
}
