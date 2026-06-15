/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvCrypto
import ObvAppTypes


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
    @NSManaged private var rawPreKeyAvailable: Bool // Always false for the current device
    @NSManaged private(set) var rawSecureChannelStatus: Int
    @NSManaged private var specifiedName: String?

    // MARK: Relationships

    // If nil, the following entity is eventually cascade-deleted
    @NSManaged private var rawOwnedIdentity: PersistedObvOwnedIdentity? // *Never* accessed directly, except from ``PersistedObvOwnedDevice.getter:ownedIdentity``
    @NSManaged public private(set) var location: PersistedLocationContinuousSent? // Non-nil when the owned identity is currently sharing her location from this device

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
            guard let newValue else { assertionFailure(); return }
            self.rawOwnedIdentityIdentity = newValue.cryptoId.getIdentity()
            self.rawOwnedIdentity = newValue
        }
    }

    public var ownedIdentityIsActive: Bool {
        ownedIdentity?.isActive ?? false
    }

    public var deviceUID: UID {
        get throws {
            guard let deviceUID = UID(uid: self.identifier) else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotParseContactDeviceUID
            }
            return deviceUID
        }
    }
    
    public var deviceIdentifier: Data {
        self.identifier
    }

    enum SecureChannelStatusRaw: Int {
        case currentDevice = 0
        case creationInProgress = 1
        case created = 2
    }

    public enum SecureChannelStatus: Equatable {
        
        case currentDevice
        case creationInProgress(preKeyAvailable: Bool)
        case created(preKeyAvailable: Bool)
        
        fileprivate var rawValue: Int {
            switch self {
            case .currentDevice:
                return SecureChannelStatusRaw.currentDevice.rawValue
            case .creationInProgress:
                return SecureChannelStatusRaw.creationInProgress.rawValue
            case .created:
                return SecureChannelStatusRaw.created.rawValue
            }
        }
        
        public var isPreKeyAvailable: Bool? {
            switch self {
            case .currentDevice:
                return nil
            case .creationInProgress(preKeyAvailable: let preKeyAvailable),
                    .created(preKeyAvailable: let preKeyAvailable):
                return preKeyAvailable
            }
        }

        public var isReachable: Bool {
            switch self {
            case .currentDevice:
                return true
            case .creationInProgress(preKeyAvailable: let preKeyAvailable):
                return preKeyAvailable
            case .created:
                return true
            }
        }


        init(_ status: ObvOwnedDevice.SecureChannelStatus) {
            switch status {
            case .currentDevice:
                self = .currentDevice
            case .creationInProgress(preKeyAvailable: let preKeyAvailable):
                self = .creationInProgress(preKeyAvailable: preKeyAvailable)
            case .created(preKeyAvailable: let preKeyAvailable):
                self = .created(preKeyAvailable: preKeyAvailable)
            }
        }
    }
    
    public var isCurrentDevice: Bool {
        self.secureChannelStatus == .currentDevice
    }

    // Expected to be non-nil
    public private(set) var secureChannelStatus: SecureChannelStatus? {
        get {
            guard let secureChannelStatusRaw = SecureChannelStatusRaw(rawValue: rawSecureChannelStatus) else { assertionFailure(); return nil }
            let preKeyAvailable = self.rawPreKeyAvailable
            switch secureChannelStatusRaw {
            case .currentDevice:
                return .currentDevice
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
            if self.rawPreKeyAvailable != newValue.isPreKeyAvailable ?? false {
                self.rawPreKeyAvailable = newValue.isPreKeyAvailable ?? false
            }
        }
    }
    
    
    public var ownedDeviceIdentifier: ObvOwnedDeviceIdentifier {
        get throws {
            let deviceUID = try self.deviceUID
            let ownedCryptoId = try self.ownedCryptoId
            return ObvOwnedDeviceIdentifier(ownedCryptoId: ownedCryptoId, deviceUID: deviceUID)
        }
    }
    
    
    public var obvDeviceIdentifier: ObvDeviceIdentifier {
        get throws {
            let ownedDeviceIdentifier = try self.ownedDeviceIdentifier
            let isCurrentDevice = secureChannelStatus == .currentDevice
            return .ownedDevice(ownedDeviceIdentifier, isCurrentDevice: isCurrentDevice)
        }
    }

    
    // MARK: - Initializer
    
    private convenience init(identifier: Data, secureChannelStatus: SecureChannelStatus, name: String?, expirationDate: Date?, latestRegistrationDate: Date?, ownedIdentity: PersistedObvOwnedIdentity) throws {
        
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        
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
    static func createIfRequired(obvOwnedDevice: ObvOwnedDevice, ownedIdentity: PersistedObvOwnedIdentity) throws -> PersistedObvOwnedDevice {
        
        guard let context = ownedIdentity.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        guard obvOwnedDevice.ownedCryptoId == ownedIdentity.cryptoId else { assertionFailure(); throw ObvUICoreDataError.unexpectedOwnedCryptoId }
        
        if let ownedDevice = try Self.fetchPersistedObvOwnedDevice(obvOwnedDevice: obvOwnedDevice, within: context) {
            return ownedDevice
        } else {
            return try self.init(
                identifier: obvOwnedDevice.identifier,
                secureChannelStatus: SecureChannelStatus(obvOwnedDevice.secureChannelStatus),
                name: obvOwnedDevice.name,
                expirationDate: obvOwnedDevice.expirationDate,
                latestRegistrationDate: obvOwnedDevice.latestRegistrationDate,
                ownedIdentity: ownedIdentity)
        }

    }

    
    public func updatePersistedObvOwnedDevice(with obvOwnedDevice: ObvOwnedDevice) throws {
        
        guard let ownedIdentity else { assertionFailure(); throw ObvUICoreDataError.ownedIdentityIsNil }
        guard obvOwnedDevice.ownedCryptoId == ownedIdentity.cryptoId else { assertionFailure(); throw ObvUICoreDataError.unexpectedOwnedCryptoId }
        guard obvOwnedDevice.identifier == identifier else { assertionFailure(); throw ObvUICoreDataError.unexpectedOwnedDeviceIdentifier }
        
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
        case .creationInProgress(preKeyAvailable: let preKeyAvailable):
            return .creationInProgress(preKeyAvailable: preKeyAvailable)
        case .created(preKeyAvailable: let preKeyAvailable):
            return .created(preKeyAvailable: preKeyAvailable)
        }
    }
    
    
    func deletePersistedObvOwnedDevice() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        context.delete(self)
    }
    
}

// MARK: - Sharing a continuous location for the current device

extension PersistedObvOwnedDevice {
    
    func createOrUpdatePersistedLocationContinuousSent(locationData: ObvLocationData, expirationDate: ObvLocationSharingExpirationDate) throws -> PersistedLocationContinuousSent {
        
        if let location = self.location, !location.isDeleted {
            _ = try location.updatePersistedLocationContinuousSent(with: locationData, updatedExpirationDate: expirationDate)
            return location
        } else {
            let location = try PersistedLocationContinuousSent(locationData: locationData, sharingExpiration: expirationDate, ownedDevice: self)
            return location
        }
        
    }

    
    func updatePersistedLocationContinuousSent(locationData: ObvLocationData) throws -> (unprocessedMessagesToSend: [MessageSentPermanentID], updatedSentMessages: Set<PersistedMessageSent>) {
        guard let location else { return ([], []) }
        // We pass nil as the updatedExpirationDate as we don't need to update the expiration
        return try location.updatePersistedLocationContinuousSent(with: locationData, updatedExpirationDate: nil)
    }
    
    
    func endPersistedLocationContinuousSentInDiscussion(discussion: PersistedDiscussion) throws -> Set<PersistedMessageSent> {
        guard let location else { return [] }
        return try location.sentLocationNoLongerNeeded(by: discussion)
    }
    
    
    func endPersistedLocationContinuousSentInAllDiscussions() throws -> Set<PersistedMessageSent> {
        guard let location else { return [] }
        return try location.sentLocationNoLongerNeededByAnyDiscussion()
    }
    
}


// MARK: - Convenience DB getters

extension PersistedObvOwnedDevice {
    
    struct Predicate {
        enum Key: String {
            // Properties
            case expirationDate = "expirationDate"
            case identifier = "identifier"
            case rawOwnedIdentityIdentity = "rawOwnedIdentityIdentity"
            case specifiedName = "specifiedName"
            case rawSecureChannelStatus = "rawSecureChannelStatus"
            // Relationships
            case rawOwnedIdentity = "rawOwnedIdentity"
            case location = "location"
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
        static func withSecureChannelStatusDistinctFrom(_ secureChannelStatus: SecureChannelStatus) -> NSPredicate {
            NSPredicate(Key.rawSecureChannelStatus, DistinctFromInt: secureChannelStatus.rawValue)
        }
        static func withObvOwnedDeviceIdentifier(_ obvOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withIdentifier(obvOwnedDeviceIdentifier.deviceUID.raw),
                withOwnedCryptoId(obvOwnedDeviceIdentifier.ownedCryptoId),
            ])
        }
        static func isExpiring(laterThan date: Date) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.expirationDate),
                NSPredicate(Key.expirationDate, laterThan: date),
            ])
        }

    }
    

    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedObvOwnedDevice> {
        return NSFetchRequest<PersistedObvOwnedDevice>(entityName: self.entityName)
    }

    
    /// Returns an expiring `PersistedObvOwnedDevice` of the `ownedCryptoId`, or nil if there is no expiring device. The expiration must be in the future.
    ///
    /// If the current device is expiring, this method returns this device. Otherwise, it returns the device that has the smallest expiration date.
    public static func getOwnedDeviceExpiringSoon(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedObvOwnedDevice? {
        
        do {
            let request = self.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withOwnedCryptoId(ownedCryptoId),
                Predicate.withSecureChannelStatus(.currentDevice),
                Predicate.isExpiring(laterThan: .now),
            ])
            request.fetchLimit = 1
            if let device = try context.fetch(request).first {
                return device
            }
        }
        
        do {
            let request = self.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withOwnedCryptoId(ownedCryptoId),
                Predicate.withSecureChannelStatusDistinctFrom(.currentDevice),
                Predicate.isExpiring(laterThan: .now),
            ])
            request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.expirationDate.rawValue, ascending: true)]
            request.fetchLimit = 1
            if let device = try context.fetch(request).first {
                return device
            }
        }
        
        // If we reach this point, the user has no expiring device
        
        return nil
        
    }
    
    
    public static func delete(identifier: Data, ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        guard let ownedDevice = try Self.fetchPersistedObvOwnedDevice(identifier: identifier, ownedCryptoId: ownedCryptoId, within: context) else { return }
        try ownedDevice.deletePersistedObvOwnedDevice()
    }

    
    public static func getAllOwnedDeviceIdentifiers(within context: NSManagedObjectContext) throws -> Set<ObvOwnedDeviceIdentifier> {
        
        let request: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        request.fetchBatchSize = 500
        request.propertiesToFetch = [
            Predicate.Key.identifier.rawValue,
            Predicate.Key.rawOwnedIdentityIdentity.rawValue,
        ]
        let results = try context.fetch(request)
        return Set(results.compactMap { device in
            guard let deviceUID = UID(uid: device.identifier) else { assertionFailure(); return nil }
            guard let ownedCryptoId = try? ObvCryptoId(identity: device.rawOwnedIdentityIdentity) else { assertionFailure(); return nil }
            return ObvOwnedDeviceIdentifier(ownedCryptoId: ownedCryptoId, deviceUID: deviceUID)
        })
        
    }

    
    public static func getAllOwnedDeviceIdentifiersOfOwnedCryptoId(_ ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Set<ObvOwnedDeviceIdentifier> {
        
        let request: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        request.fetchBatchSize = 500
        request.propertiesToFetch = [
            Predicate.Key.identifier.rawValue,
            Predicate.Key.rawOwnedIdentityIdentity.rawValue,
        ]
        let results = try context.fetch(request)
        return Set(results.compactMap { device in
            guard let deviceUID = UID(uid: device.identifier) else { assertionFailure(); return nil }
            guard let ownedCryptoId = try? ObvCryptoId(identity: device.rawOwnedIdentityIdentity) else { assertionFailure(); return nil }
            return ObvOwnedDeviceIdentifier(ownedCryptoId: ownedCryptoId, deviceUID: deviceUID)
        })
        
    }

    
    public static func getPersistedObvOwnedDevice(with obvOwnedDeviceIdentifier: ObvOwnedDeviceIdentifier, within context: NSManagedObjectContext) throws -> PersistedObvOwnedDevice? {
        let request: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        request.fetchLimit = 1
        request.predicate = Predicate.withObvOwnedDeviceIdentifier(obvOwnedDeviceIdentifier)
        return try context.fetch(request).first
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
    
    
    public static func getFetchedResultsControllerForCurrentOwnedDevice(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedObvOwnedDevice> {
        let fetchRequest: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.withSecureChannelStatus(.currentDevice),
        ])
        fetchRequest.fetchLimit = 1
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.specifiedName.rawValue, ascending: true)]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: context,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }
    
    public static func getFetchedResultsController(ownedDeviceIdentifier: ObvOwnedDeviceIdentifier, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedObvOwnedDevice> {
        let fetchRequest: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        fetchRequest.predicate = Predicate.withObvOwnedDeviceIdentifier(ownedDeviceIdentifier)
        fetchRequest.fetchLimit = 1
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.specifiedName.rawValue, ascending: true)]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: context,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }
    
    /// Returns a `NSFetchedResultsController` for all owned devices of an owned identity.
    public static func getFetchedResultsController(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedObvOwnedDevice> {
        let fetchRequest: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        fetchRequest.predicate = Predicate.withOwnedCryptoId(ownedCryptoId)
        fetchRequest.fetchBatchSize = 100
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.specifiedName.rawValue, ascending: true)]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: context,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }

    
    public static func getFetchedResultsController(within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedObvOwnedDevice> {
        let fetchRequest: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        fetchRequest.fetchBatchSize = 100
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.specifiedName.rawValue, ascending: true)]
        return NSFetchedResultsController(fetchRequest: fetchRequest,
                                          managedObjectContext: context,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }

    
    public static func getNameOfPersistedObvOwnedDevice(ownedDeviceIdentifier: ObvOwnedDeviceIdentifier, within context: NSManagedObjectContext) throws -> String? {
        let request: NSFetchRequest<PersistedObvOwnedDevice> = self.fetchRequest()
        request.predicate = Predicate.withObvOwnedDeviceIdentifier(ownedDeviceIdentifier)
        request.fetchLimit = 1
        request.propertiesToFetch = [Predicate.Key.specifiedName.rawValue]
        let item = try context.fetch(request).first
        return item?.name
    }
    
}


extension PersistedObvOwnedDevice {
    
    public func isSharingLocation(to discussion: PersistedDiscussion) -> Bool {
        guard let location = self.location else { return false }
        
        return location.sentMessages.compactMap(\.discussion).contains(discussion)
    }
}
