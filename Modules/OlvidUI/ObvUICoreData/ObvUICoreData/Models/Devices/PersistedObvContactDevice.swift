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
import ObvTypes
import ObvEngine
import OlvidUtils


@objc(PersistedObvContactDevice)
public final class PersistedObvContactDevice: NSManagedObject, Identifiable, ObvErrorMaker {
    
    // MARK: - Internal constants
    
    private static let entityName = "PersistedObvContactDevice"
    public static let errorDomain = "PersistedObvContactDevice"
    
    // MARK: Properties
    
    @NSManaged public private(set) var identifier: Data
    @NSManaged private var rawIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var rawOwnedIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var rawSecureChannelStatus: Int

    // MARK: Relationships
    
    // If nil, the following entity is eventually cascade-deleted
    @NSManaged private var rawIdentity: PersistedObvContactIdentity? // *Never* accessed directly

    // MARK: Other variables
    
    private var changedKeys = Set<String>()

    public private(set) var identity: PersistedObvContactIdentity? {
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

    
    public var contactIdentifier: ObvContactIdentifier {
        get throws {
            let ownedCryptoId = try ObvCryptoId(identity: rawOwnedIdentityIdentity)
            let contactCryptoId = try ObvCryptoId(identity: rawIdentityIdentity)
            return ObvContactIdentifier(
                contactCryptoId: contactCryptoId,
                ownedCryptoId: ownedCryptoId)
        }
    }

    
    public enum SecureChannelStatus: Int {
        case creationInProgress = 0
        case created = 1
        
        init(_ status: ObvContactDevice.SecureChannelStatus) {
            switch status {
            case .creationInProgress:
                self = .creationInProgress
            case .created:
                self = .created
            }
        }
    }

    
    // Expected to be non-nil
    public private(set) var secureChannelStatus: SecureChannelStatus? {
        get {
            return SecureChannelStatus(rawValue: rawSecureChannelStatus)
        }
        set {
            guard let newValue else { assertionFailure(); return }
            self.rawSecureChannelStatus = newValue.rawValue
        }
    }

    
    // MARK: - Initializer
    
    /// Shall **only** be called from the ``func insert(_ device: ObvContactDevice) throws`` method of a `PersistedObvContactIdentity`.
    convenience init(obvContactDevice device: ObvContactDevice, persistedContact: PersistedObvContactIdentity) throws {
        
        guard let context = persistedContact.managedObjectContext else {
            throw ObvError.couldNotFindContext
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedObvContactDevice.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.identifier = device.identifier
        self.rawIdentityIdentity = device.contactIdentifier.contactCryptoId.getIdentity()
        self.rawOwnedIdentityIdentity = device.contactIdentifier.ownedCryptoId.getIdentity()
        self.identity = persistedContact
        self.secureChannelStatus = SecureChannelStatus(device.secureChannelStatus)
        
    }
    
    
    func updateWith(obvContactDevice device: ObvContactDevice) throws {
        guard try self.identity?.obvContactIdentifier == device.contactIdentifier, self.identifier == device.identifier else {
            assertionFailure()
            throw Self.makeError(message: "Unexpected device identifier")
        }
        if self.secureChannelStatus != SecureChannelStatus(device.secureChannelStatus) {
            self.secureChannelStatus = SecureChannelStatus(device.secureChannelStatus)
        }
    }

    // MARK: - For deletion
    
    private var contactIdentityCryptoIdForDeletion: ObvCryptoId?
    
    func deleteThisDevice() throws {
        guard let context = managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        context.delete(self)
    }
    
}


// MARK: - Convenience DB getters

extension PersistedObvContactDevice {
    
    struct Predicate {
        enum Key: String {
            // Properties
            case identifier = "identifier"
            case rawIdentityIdentity = "rawIdentityIdentity"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
            case rawSecureChannelStatus = "rawSecureChannelStatus"
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


    public static func get(contactDeviceObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedObvContactDevice? {
        return try context.existingObject(with: contactDeviceObjectID) as? PersistedObvContactDevice
    }
    
}


// MARK: - Sending notifications on change

extension PersistedObvContactDevice {
    
    public override func prepareForDeletion() {
        super.prepareForDeletion()
        guard managedObjectContext?.concurrencyType != .mainQueueConcurrencyType else { return }
        self.contactIdentityCryptoIdForDeletion = rawIdentity?.cryptoId
    }
    
    
    public override func willSave() {
        super.willSave()
        changedKeys = Set<String>(self.changedValues().keys)
    }

    
    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
        }
        
        if isInserted, let contactCryptoId = self.identity?.cryptoId {
            
            ObvMessengerCoreDataNotification.newPersistedObvContactDevice(contactDeviceObjectID: self.objectID, contactCryptoId: contactCryptoId)
                .postOnDispatchQueue()
            
        } else if isDeleted, let contactCryptoId = self.contactIdentityCryptoIdForDeletion {
            
            ObvMessengerCoreDataNotification.deletedPersistedObvContactDevice(contactCryptoId: contactCryptoId)
                .postOnDispatchQueue()
            
        }
        
        if !isDeleted && changedKeys.contains(Predicate.Key.rawSecureChannelStatus.rawValue), let secureChannelStatus {
            switch secureChannelStatus {
            case .creationInProgress:
                break
            case .created:
                ObvMessengerCoreDataNotification.aSecureChannelWithContactDeviceWasJustCreated(contactDeviceObjectID: self.typedObjectID)
                    .postOnDispatchQueue()
            }
        }
    }
    
}


// MARK: - Errors

extension PersistedObvContactDevice {
    
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
