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
import ObvEngine
import OlvidUtils


@objc(PersistedObvContactDevice)
final class PersistedObvContactDevice: NSManagedObject, Identifiable, ObvErrorMaker {
    
    // MARK: - Internal constants
    
    private static let entityName = "PersistedObvContactDevice"
    static let errorDomain = "PersistedObvContactDevice"
    
    // MARK: Properties
    
    @NSManaged private(set) var identifier: Data
    @NSManaged private var rawIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var rawOwnedIdentityIdentity: Data // Required for core data constraints
    
    // MARK: Relationships
    
    // If nil, the following entity is eventually cascade-deleted
    @NSManaged private var rawIdentity: PersistedObvContactIdentity? // *Never* accessed directly

    // MARK: Other variables
    
    private(set) var identity: PersistedObvContactIdentity? {
        get {
            return self.rawIdentity
        }
        set {
            assert(newValue != nil)
            if let value = newValue {
                self.rawIdentityIdentity = value.cryptoId.getIdentity()
            }
            self.rawIdentity = newValue
        }
    }

    
    // MARK: - Initializer
    
    /// Shall **only** be called from the ``func insert(_ device: ObvContactDevice) throws`` method of a `PersistedObvContactIdentity`.
    convenience init(obvContactDevice device: ObvContactDevice, within context: NSManagedObjectContext) throws {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedObvContactDevice.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        let persistedContact: PersistedObvContactIdentity
        if let _identity = try PersistedObvContactIdentity.get(persisted: device.contactIdentity, whereOneToOneStatusIs: .any, within: context) {
            persistedContact = _identity
        } else {
            let _identity = try PersistedObvContactIdentity(contactIdentity: device.contactIdentity, within: context)
            persistedContact = _identity
        }
        
        self.identifier = device.identifier
        self.rawIdentityIdentity = device.contactIdentity.cryptoId.getIdentity()
        self.rawOwnedIdentityIdentity = device.contactIdentity.ownedIdentity.cryptoId.getIdentity()
        self.identity = persistedContact
        
    }

    // MARK: - For deletion
    
    private var contactIdentityCryptoIdForDeletion: ObvCryptoId?
    
}


// MARK: - Convenience DB getters

extension PersistedObvContactDevice {
    
    struct Predicate {
        enum Key: String {
            // Properties
            case identifier = "identifier"
            case rawIdentityIdentity = "rawIdentityIdentity"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
            // Relationships
            case rawIdentity = "rawIdentity"
        }
        static func withContactDeviceIdentifier(_ contactDeviceIdentifier: Data) -> NSPredicate {
            NSPredicate(Key.identifier, EqualToData: contactDeviceIdentifier)
        }
        static func withContactCryptoId(_ contactCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawIdentityIdentity, EqualToData: contactCryptoId.getIdentity())
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
    }
    

    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedObvContactDevice> {
        return NSFetchRequest<PersistedObvContactDevice>(entityName: self.entityName)
    }

    
    static func delete(contactDeviceIdentifier: Data, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {

        let request: NSFetchRequest<PersistedObvContactDevice> = self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withContactDeviceIdentifier(contactDeviceIdentifier),
            Predicate.withContactCryptoId(contactCryptoId),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        request.fetchLimit = 1
        guard let object = try context.fetch(request).first else { return }
        assert(object.identity != nil)
        object.contactIdentityCryptoIdForDeletion = object.identity?.cryptoId
        context.delete(object)
    }

    
    static func get(contactDeviceObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedObvContactDevice? {
        return try context.existingObject(with: contactDeviceObjectID) as? PersistedObvContactDevice
    }
    
}


// MARK: - Sending notifications on change

extension PersistedObvContactDevice {
    
    override func didSave() {
        super.didSave()

        if isInserted, let contactCryptoId = self.identity?.cryptoId {
            
            ObvMessengerCoreDataNotification.newPersistedObvContactDevice(contactDeviceObjectID: self.objectID, contactCryptoId: contactCryptoId)
                .postOnDispatchQueue()
            
        } else if isDeleted, let contactCryptoId = self.contactIdentityCryptoIdForDeletion {
            
            ObvMessengerCoreDataNotification.deletedPersistedObvContactDevice(contactCryptoId: contactCryptoId)
                .postOnDispatchQueue()
            
        }
    }
    
}
