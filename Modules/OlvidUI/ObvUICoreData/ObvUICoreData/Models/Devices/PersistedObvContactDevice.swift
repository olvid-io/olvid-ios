/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import os.log
import CoreData
import ObvTypes
import ObvEngine
import OlvidUtils
import ObvCrypto
import ObvSettings


@objc(PersistedObvContactDevice)
public final class PersistedObvContactDevice: NSManagedObject, Identifiable, ObvErrorMaker {
    
    // MARK: - Internal constants
    
    private static let entityName = "PersistedObvContactDevice"
    public static let errorDomain = "PersistedObvContactDevice"
    
    // MARK: Properties
    
    @NSManaged public private(set) var identifier: Data
    @NSManaged private var rawIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var rawOwnedIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var rawPreKeyAvailable: Bool
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
            assert(rawOwnedIdentityIdentity != rawIdentityIdentity)
            let ownedCryptoId = try ObvCryptoId(identity: rawOwnedIdentityIdentity)
            let contactCryptoId = try ObvCryptoId(identity: rawIdentityIdentity)
            return ObvContactIdentifier(
                contactCryptoId: contactCryptoId,
                ownedCryptoId: ownedCryptoId)
        }
    }

    
    public var contactDeviceIdentifier: ObvContactDeviceIdentifier {
        get throws {
            let contactIdentifier = try self.contactIdentifier
            guard let deviceUID = UID(uid: self.identifier) else {
                assertionFailure()
                throw ObvError.couldNotComputeDeviceUID
            }
            return .init(contactIdentifier: contactIdentifier, deviceUID: deviceUID)
        }
    }
    
    private enum SecureChannelStatusRaw: Int {
        case creationInProgress = 0
        case created = 1
    }
    
    public enum SecureChannelStatus: Equatable {
        
        case creationInProgress(preKeyAvailable: Bool)
        case created(preKeyAvailable: Bool)
        
        fileprivate var rawValue: Int {
            switch self {
            case .creationInProgress:
                return SecureChannelStatusRaw.creationInProgress.rawValue
            case .created:
                return SecureChannelStatusRaw.created.rawValue
            }
        }
        
        public var isPreKeyAvailable: Bool {
            switch self {
            case .creationInProgress(preKeyAvailable: let preKeyAvailable),
                    .created(preKeyAvailable: let preKeyAvailable):
                return preKeyAvailable
            }
        }
        
        public var isReachable: Bool {
            switch self {
            case .creationInProgress(preKeyAvailable: let preKeyAvailable):
                return preKeyAvailable
            case .created:
                return true
            }
        }
        
        init(_ status: ObvContactDevice.SecureChannelStatus) {
            switch status {
            case .creationInProgress(preKeyAvailable: let preKeyAvailable):
                self = .creationInProgress(preKeyAvailable: preKeyAvailable)
            case .created(preKeyAvailable: let preKeyAvailable):
                self = .created(preKeyAvailable: preKeyAvailable)
            }
        }
    }

    
    // Expected to be non-nil
    public private(set) var secureChannelStatus: SecureChannelStatus? {
        get {
            guard let secureChannelStatusRaw = SecureChannelStatusRaw(rawValue: rawSecureChannelStatus) else { assertionFailure(); return nil }
            let preKeyAvailable = self.rawPreKeyAvailable
            switch secureChannelStatusRaw {
            case .creationInProgress:
                return .creationInProgress(preKeyAvailable: preKeyAvailable)
            case .created:
                return .created(preKeyAvailable: preKeyAvailable)
            }
        }
        set {
            guard let newValue else { assertionFailure(); return }
            if self.rawSecureChannelStatus != newValue.rawValue {
                self.rawSecureChannelStatus = newValue.rawValue
            }
            if self.rawPreKeyAvailable != newValue.isPreKeyAvailable {
                self.rawPreKeyAvailable = newValue.isPreKeyAvailable
            }
        }
    }


    /// Used when restoring a sync snapshot or when restoring a backup to prevent any notification on insertion
    private var isInsertedWhileRestoringSyncSnapshot = false

    
    // MARK: - Initializer
    
    /// Shall **only** be called from the ``func insert(_ device: ObvContactDevice) throws`` method of a `PersistedObvContactIdentity`.
    convenience init(obvContactDevice device: ObvContactDevice, persistedContact: PersistedObvContactIdentity, isRestoringSyncSnapshotOrBackup: Bool) throws {
        
        guard let context = persistedContact.managedObjectContext else {
            throw ObvError.couldNotFindContext
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedObvContactDevice.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.isInsertedWhileRestoringSyncSnapshot = isRestoringSyncSnapshotOrBackup

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
        static func withContactIdentifier(_ contactIdentifier: ObvContactIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withOwnedCryptoId(contactIdentifier.ownedCryptoId),
                withContactCryptoId(contactIdentifier.contactCryptoId),
            ])
        }
    }
    

    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedObvContactDevice> {
        return NSFetchRequest<PersistedObvContactDevice>(entityName: self.entityName)
    }


    public static func get(contactDeviceObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedObvContactDevice? {
        return try context.existingObject(with: contactDeviceObjectID) as? PersistedObvContactDevice
    }
    
    public static func getAllContactDeviceIdentifiersOfContactsOfOwnedIdentity(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Set<ObvContactDeviceIdentifier> {
        
        let request: NSFetchRequest<PersistedObvContactDevice> = self.fetchRequest()
        request.fetchBatchSize = 1_000
        request.propertiesToFetch = [
            Predicate.Key.identifier.rawValue,
            Predicate.Key.rawOwnedIdentityIdentity.rawValue,
            Predicate.Key.rawIdentityIdentity.rawValue
        ]
        request.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        let results = try context.fetch(request)
        return try Set(results.compactMap { device in
            return try device.contactDeviceIdentifier
        })
        
    }

    
    public static func getAllContactDeviceIdentifiersOfContact(contactIdentifier: ObvContactIdentifier, within context: NSManagedObjectContext) throws -> Set<ObvContactDeviceIdentifier> {
        
        let request: NSFetchRequest<PersistedObvContactDevice> = self.fetchRequest()
        request.fetchBatchSize = 50
        request.propertiesToFetch = [
            Predicate.Key.identifier.rawValue,
            Predicate.Key.rawOwnedIdentityIdentity.rawValue,
            Predicate.Key.rawIdentityIdentity.rawValue
        ]
        request.predicate = Predicate.withContactIdentifier(contactIdentifier)
        let results = try context.fetch(request)
        return try Set(results.compactMap { device in
            return try device.contactDeviceIdentifier
        })
        
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
            isInsertedWhileRestoringSyncSnapshot = false
        }
        
        guard !isInsertedWhileRestoringSyncSnapshot else {
            assert(isInserted)
            let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: Self.self))
            os_log("Insertion of a PersistedObvContactDevice during a snapshot restore --> we don't send any notification", log: log, type: .info)
            return
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
        case couldNotComputeDeviceUID
        
        var localizedDescription: String {
            switch self {
            case .couldNotFindContext:
                return "Could not find context"
            case .couldNotComputeDeviceUID:
                return "Could not compute device UID"
            }
        }
    }
    
}
