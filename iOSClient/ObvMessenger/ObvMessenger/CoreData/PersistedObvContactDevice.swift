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

import ObvEngine

@objc(PersistedObvContactDevice)
final class PersistedObvContactDevice: NSManagedObject, Identifiable {
    
    // MARK: - Internal constants
    
    private static let entityName = "PersistedObvContactDevice"
    static let identifierKey = "identifier"
    static let rawIdentityKey = "rawIdentity"
    static let identityIdentityKey = [PersistedObvContactDevice.rawIdentityKey, PersistedObvContactIdentity.identityKey].joined(separator: ".")
    static let identityOwnedIdentityIdentityKey = [PersistedObvContactDevice.rawIdentityKey, PersistedObvContactIdentity.ownedIdentityIdentityKey].joined(separator: ".")

    private static let errorDomain = "PersistedObvContactDevice"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: - Properties
    
    @NSManaged private(set) var identifier: Data
    @NSManaged private var rawIdentityIdentity: Data // Required for core data constraints
    
    
    // MARK: - Relationships
    
    // If nil, the following entity is eventually cascade-deleted
    @NSManaged private var rawIdentity: PersistedObvContactIdentity? // *Never* accessed directly

    // MARK: - Other variables
    
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
    
    convenience init?(obvContactDevice device: ObvContactDevice, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedObvContactDevice.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        let identity: PersistedObvContactIdentity
        if let _identity = try? PersistedObvContactIdentity.get(persisted: device.contactIdentity, within: context) {
            identity = _identity
        } else {
            guard let _identity = PersistedObvContactIdentity(contactIdentity: device.contactIdentity, within: context) else { return nil }
            identity = _identity
        }
        
        self.identifier = device.identifier
        self.rawIdentityIdentity = identity.cryptoId.getIdentity()
        self.identity = identity
        
    }

    // MARK: - For deletion
    
    private var contactIdentityCryptoIdForDeletion: ObvCryptoId?
    
}


// MARK: - Convenience DB getters

extension PersistedObvContactDevice {

    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedObvContactDevice> {
        return NSFetchRequest<PersistedObvContactDevice>(entityName: self.entityName)
    }

    static func delete(contactDeviceIdentifier: Data, contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {

        let request: NSFetchRequest<PersistedObvContactDevice> = self.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                                        identifierKey, contactDeviceIdentifier as NSData,
                                        identityIdentityKey, contactCryptoId.getIdentity() as NSData,
                                        identityOwnedIdentityIdentityKey, ownedCryptoId.getIdentity() as NSData)
        request.fetchLimit = 1
        guard let object = try context.fetch(request).first else { return }
        assert(object.identity != nil)
        object.contactIdentityCryptoIdForDeletion = object.identity?.cryptoId
        context.delete(object)

    }
    
}


// MARK: - Sending notifications on change

extension PersistedObvContactDevice {
    
    override func didSave() {
        super.didSave()

        if isInserted, let contactCryptoId = self.identity?.cryptoId {
            
            ObvMessengerInternalNotification.newPersistedObvContactDevice(contactDeviceObjectID: self.objectID, contactCryptoId: contactCryptoId)
                .postOnDispatchQueue()
            
        } else if isDeleted, let contactCryptoId = self.contactIdentityCryptoIdForDeletion {
            
            ObvMessengerInternalNotification.deletedPersistedObvContactDevice(contactCryptoId: contactCryptoId)
                .postOnDispatchQueue()
            
        }
    }
    
}
