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


@objc(PersistedObvOwnedDevice)
public final class PersistedObvOwnedDevice: NSManagedObject, Identifiable {
    
    // MARK: - Internal constants
    
    private static let entityName = "PersistedObvOwnedDevice"
    
    // MARK: Properties
    
    @NSManaged public private(set) var expirationDate: Date?
    @NSManaged public private(set) var identifier: Data // Required for core data constraints
    @NSManaged public private(set) var latestRegistrationDate: Date?
    @NSManaged private(set) var objectInsertionDate: Date
    @NSManaged private(set) var rawOwnedIdentityIdentity: Data // Required for core data constraints
    @NSManaged private(set) var rawSecureChannelStatus: Int
    @NSManaged private var specifiedName: String?

    // MARK: Relationships

    // If nil, the following entity is eventually cascade-deleted
    @NSManaged private var rawOwnedIdentity: PersistedObvOwnedIdentity? // *Never* accessed directly, except from ``PersistedObvOwnedDevice.getter:ownedIdentity``

    // MARK: Other variables
    
    public var name: String {
        specifiedName ?? String(identifier.hexString().prefix(4))
    }
    
    public var ownedCryptoId: ObvCryptoId {
        get throws {
            try ObvCryptoId(identity: rawOwnedIdentityIdentity)
        }
    }
    
    public private(set) var ownedIdentity: PersistedObvOwnedIdentity? {
        get {
            return self.rawOwnedIdentity
        }
        set {
            assert(newValue != nil)
            guard let newValue else { assertionFailure(); return }
            self.rawOwnedIdentityIdentity = newValue.cryptoId.getIdentity()
            self.rawOwnedIdentity = newValue
        }
    }

    public enum SecureChannelStatus: Int {
        case currentDevice = 0
        case creationInProgress = 1
        case created = 2
        
        init(_ status: ObvOwnedDevice.SecureChannelStatus) {
            switch status {
            case .currentDevice:
                self = .currentDevice
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
    
    private convenience init(identifier: Data, secureChannelStatus: SecureChannelStatus, name: String?, expirationDate: Date?, latestRegistrationDate: Date?, ownedIdentity: PersistedObvOwnedIdentity) throws {
        
        guard let context = ownedIdentity.managedObjectContext else {
            assertionFailure()
            throw ObvError.noContextProvided
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedObvOwnedDevice.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.identifier = identifier
        self.ownedIdentity = ownedIdentity
        self.secureChannelStatus = secureChannelStatus
        self.objectInsertionDate = Date()
        self.specifiedName = name
        self.expirationDate = expirationDate
        self.latestRegistrationDate = latestRegistrationDate
        
    }
    
    
    /// Shall **only** be called from ``PersistedObvOwnedIdentity.updateOrCreateOwnedDevice(identifier:secureChannelStatus:)``
    static func createIfRequired(obvOwnedDevice: ObvOwnedDevice, ownedIdentity: PersistedObvOwnedIdentity) throws {
        
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvError.noContextProvided }
        guard obvOwnedDevice.ownedCryptoId == ownedIdentity.cryptoId else { assertionFailure(); throw ObvError.unexpectedOwnedCryptoId }
        
        guard try Self.fetchPersistedObvOwnedDevice(obvOwnedDevice: obvOwnedDevice, within: context) == nil else { return }
        
        _ = try self.init(
            identifier: obvOwnedDevice.identifier,
            secureChannelStatus: SecureChannelStatus(obvOwnedDevice.secureChannelStatus),
            name: obvOwnedDevice.name,
            expirationDate: obvOwnedDevice.expirationDate,
            latestRegistrationDate: obvOwnedDevice.latestRegistrationDate,
            ownedIdentity: ownedIdentity)
    }

    
    func updatePersistedObvOwnedDevice(with obvOwnedDevice: ObvOwnedDevice) throws {
        
        guard let ownedIdentity else { assertionFailure(); throw ObvError.ownedIdentityIsNil }
        guard obvOwnedDevice.ownedCryptoId == ownedIdentity.cryptoId else { assertionFailure(); throw ObvError.unexpectedOwnedCryptoId }
        guard obvOwnedDevice.identifier == identifier else { assertionFailure(); throw ObvError.unexpectedIdentifier }
        
        if self.secureChannelStatus != SecureChannelStatus(obvOwnedDevice.secureChannelStatus) {
            self.secureChannelStatus = SecureChannelStatus(obvOwnedDevice.secureChannelStatus)
        }
        
        if self.specifiedName != obvOwnedDevice.name {
            self.specifiedName = obvOwnedDevice.name
        }
        
        if self.expirationDate != obvOwnedDevice.expirationDate {
            self.expirationDate = obvOwnedDevice.expirationDate
        }
        
        if self.latestRegistrationDate != obvOwnedDevice.latestRegistrationDate {
            self.latestRegistrationDate = obvOwnedDevice.latestRegistrationDate
        }
        
    }
    
    
    private static func secureChannelStatus(from secureChannelStatus: ObvOwnedDevice.SecureChannelStatus) -> SecureChannelStatus {
        switch secureChannelStatus {
        case .currentDevice:
            return .currentDevice
        case .creationInProgress:
            return .creationInProgress
        case .created:
            return .created
        }
    }
    
    
    func deletePersistedObvOwnedDevice() throws {
        guard let context = self.managedObjectContext else {
            throw ObvError.noContextProvided
        }
        context.delete(self)
    }
    
}


// MARK: - Convenience DB getters

extension PersistedObvOwnedDevice {
    
    struct Predicate {
        enum Key: String {
            // Properties
            case identifier = "identifier"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
            case specifiedName = "specifiedName"
            case rawSecureChannelStatus = "rawSecureChannelStatus"
            // Relationships
            case rawOwnedIdentity = "rawOwnedIdentity"
        }
        static func withIdentifier(_ identifier: Data) -> NSPredicate {
            NSPredicate(Key.identifier, EqualToData: identifier)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentityIdentity, EqualToData: ownedCryptoId.getIdentity())
        }
        static var withoutSpecifiedName: NSPredicate {
            NSPredicate(withNilValueForKey: Key.specifiedName)
        }
        static func withSecureChannelStatus(_ secureChannelStatus: SecureChannelStatus) -> NSPredicate {
            NSPredicate(Key.rawSecureChannelStatus, EqualToInt: secureChannelStatus.rawValue)
        }
    }
    

    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedObvOwnedDevice> {
        return NSFetchRequest<PersistedObvOwnedDevice>(entityName: self.entityName)
    }

    
    public static func delete(identifier: Data, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        guard let ownedDevice = try Self.fetchPersistedObvOwnedDevice(identifier: identifier, ownedCryptoId: ownedCryptoId, within: context) else { return }
        try ownedDevice.deletePersistedObvOwnedDevice()
    }

    
    public static func fetchPersistedObvOwnedDevice(identifier: Data, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedObvOwnedDevice? {
        let request: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withIdentifier(identifier),
            Predicate.withOwnedCryptoId(ownedCryptoId),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func fetchPersistedObvOwnedDevice(obvOwnedDevice: ObvOwnedDevice, within context: NSManagedObjectContext) throws -> PersistedObvOwnedDevice? {
        let request: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withIdentifier(obvOwnedDevice.identifier),
            Predicate.withOwnedCryptoId(obvOwnedDevice.ownedCryptoId),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func fetchCurrentPersistedObvOwnedDeviceWithNoSpecifiedName(within context: NSManagedObjectContext) throws -> [PersistedObvOwnedDevice] {
        let request: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withoutSpecifiedName,
            Predicate.withSecureChannelStatus(.currentDevice),
        ])
        request.fetchBatchSize = 500
        return try context.fetch(request)
    }
    
}


// MARK: - Error handling

extension PersistedObvOwnedDevice {
    
    enum ObvError: Error {
        case noContextProvided
        case unexpectedOwnedCryptoId
        case unexpectedIdentifier
        case ownedIdentityIsNil
        
        var localizedDescription: String {
            switch self {
            case .noContextProvided:
                return "No context provided"
            case .unexpectedOwnedCryptoId:
                return "Unexpected owned cryptoId"
            case .unexpectedIdentifier:
                return "Unexpected owned device identifier"
            case .ownedIdentityIsNil:
                return "Owned identity is nil"
            }
        }
        
    }
}

