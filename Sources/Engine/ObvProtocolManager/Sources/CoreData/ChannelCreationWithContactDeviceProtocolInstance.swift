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
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


/// This database is only used within the channel creation protocol (with a contact identity) between the current device of the owned identity and the contact device
@objc(ChannelCreationWithContactDeviceProtocolInstance)
final class ChannelCreationWithContactDeviceProtocolInstance: NSManagedObject {

    // MARK: Internal constants
    
    private static let entityName = "ChannelCreationWithContactDeviceProtocolInstance"
    private static let logger = Logger(subsystem: ObvProtocolDelegateManager.defaultLogSubsystem, category: ChannelCreationWithContactDeviceProtocolInstance.entityName)
    
    // MARK: Attributes
    
    @NSManaged private var rawContactDeviceUid: Data? // Non-optional in the model
    @NSManaged private var rawContactIdentity: Data? // Non-optional in the model
    
    // MARK: Relationships
    
    // Primary key (enforced by a one-to-one relationship). This is necessarily a ChannelCreationWithContactDevice protocol instance.
    @NSManaged private(set) var protocolInstance: ProtocolInstance

    // MARK: Other variables
    
    var ownedCryptoIdentity: ObvCryptoIdentity {
        get throws {
            return try protocolInstance.ownedCryptoIdentity
        }
    }
    
    var contactIdentity: ObvCryptoIdentity {
        get throws {
            guard let rawContactIdentity else { assertionFailure(); throw ObvError.unexpectedNilValue }
            guard let contactIdentity = ObvCryptoIdentity(from: rawContactIdentity) else { assertionFailure(); throw ObvError.couldNotParseValue }
            return contactIdentity
        }
    }
    
    var contactDeviceUid: UID {
        get throws {
            guard let rawContactDeviceUid else { assertionFailure(); throw ObvError.unexpectedNilValue }
            guard let contactDeviceUid = UID(uid: rawContactDeviceUid) else { assertionFailure(); throw ObvError.couldNotParseValue }
            return contactDeviceUid
        }
    }
    
    // MARK: - Initializer
    
    /// 2025-08-27: ok
    convenience init?(protocolInstanceUid: UID, ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ChannelCreationWithContactDeviceProtocolInstance.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        guard let protocolInstance = try? ProtocolInstance.get(
            cryptoProtocolId: CryptoProtocolId.channelCreationWithContactDevice,
            uid: protocolInstanceUid,
            ownedIdentity: ownedIdentity,
            within: context) else { return nil }
        self.protocolInstance = protocolInstance
        self.rawContactIdentity = contactIdentity.getIdentity()
        self.rawContactDeviceUid = contactDeviceUid.raw
    }

    
    private func deleteChannelCreationWithContactDeviceProtocolInstance() throws {
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
extension ChannelCreationWithContactDeviceProtocolInstance {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case rawContactDeviceUid = "rawContactDeviceUid"
            case rawContactIdentity = "rawContactIdentity"
            // Relationships
            case protocolInstance = "protocolInstance"
        }
        static func withContactIdentity(_ contactIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawContactIdentity, EqualToData: contactIdentity.getIdentity())
        }
        static func withContactDeviceUid(_ contactDeviceUid: UID) -> NSPredicate {
            NSPredicate(Key.rawContactDeviceUid, EqualToData: contactDeviceUid.raw)
        }
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            let rawKey: String = [
                Key.protocolInstance.rawValue,
                ProtocolInstance.Predicate.Key.rawOwnedCryptoIdentity.rawValue,
            ].joined(separator: ".")
            return NSPredicate(rawKey, EqualToData: ownedCryptoIdentity.getIdentity())
        }
    }

    @nonobjc class func fetchRequest() -> NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance> {
        return NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance>(entityName: ChannelCreationWithContactDeviceProtocolInstance.entityName)
    }
    
    
    static func delete(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, andOwnedIdentity ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> UID? {
        let request: NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance> = ChannelCreationWithContactDeviceProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactIdentity(contactIdentity),
            Predicate.withContactDeviceUid(contactDeviceUid),
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
        ])
        guard let item = try context.fetch(request).first else {
            logger.error("Did not find a ChannelCreationProtocolInstanceInWaitingState to delete")
            return nil
        }
        let protocolInstanceUid = try item.protocolInstance.uid
        try item.deleteChannelCreationWithContactDeviceProtocolInstance()
        return protocolInstanceUid
    }
    
    
    static func exists(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, andOwnedIdentity ownedCryptoIdentity: ObvCryptoIdentity, within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance> = ChannelCreationWithContactDeviceProtocolInstance.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactIdentity(contactIdentity),
            Predicate.withContactDeviceUid(contactDeviceUid),
            Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity),
        ])
        request.fetchLimit = 1
        request.propertiesToFetch = []
        let item = try context.fetch(request).first
        return item != nil
    }
    
    
    static func getAll(within context: NSManagedObjectContext) throws -> Set<ObliviousChannelIdentifierAlt> {
        let request: NSFetchRequest<ChannelCreationWithContactDeviceProtocolInstance> = ChannelCreationWithContactDeviceProtocolInstance.fetchRequest()
        request.fetchBatchSize = 1_000
        let items = try context.fetch(request)
        let identifiers = items.compactMap {
            do {
                return try ObliviousChannelIdentifierAlt(
                    ownedCryptoIdentity: $0.ownedCryptoIdentity,
                    remoteCryptoIdentity: try $0.contactIdentity,
                    remoteDeviceUid: try $0.contactDeviceUid)
            } catch {
                logger.fault("Parsing failed: \(error, privacy: .public)")
                assertionFailure()
                return nil
            }
        }
        return Set(identifiers)
    }
    
}
