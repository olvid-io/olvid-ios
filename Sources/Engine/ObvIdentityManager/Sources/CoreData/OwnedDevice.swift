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
import ObvMetaManager
import ObvCrypto
import ObvTypes
import OlvidUtils

@objc(OwnedDevice)
final class OwnedDevice: NSManagedObject {

    private static let entityName = "OwnedDevice"
    
    static weak var delegateManager: ObvIdentityDelegateManager?
    
    // MARK: Attributes
    
    @NSManaged private var expirationDate: Date?
    @NSManaged private(set) var latestChannelCreationPingTimestamp: Date? // Always nil for the current device, may be non-nil for a remote owned device
    @NSManaged private var latestRegistrationDate: Date?
    @NSManaged private(set) var name: String?
    @NSManaged private var rawCapabilities: String?
    @NSManaged private var rawUID: Data? // Non-optional in the model, unique (not enforced), raw value of an UID

    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: OwnedDevice.logSubsystem, category: "OwnedDevice") }()

    // MARK: Relationships
    
    @NSManaged private var preKeyForRemoteOwnedDevice: PreKeyForRemoteOwnedDevice? // Always nil for the current device, may be non-nil for a remote owned device. Set in the init of PreKeyForRemoteOwnedDevice
    @NSManaged private var preKeysForCurrentDevice: Set<PreKeyForCurrentOwnedDevice> // Always empty for a remote owned device. New elements are added by calling ``static createPreKeyForCurrentOwnedDevice(forCurrentOwnedDevice:withExpirationTimestamp:prng:)`` on ``PreKeyForCurrentOwnedDevice``
    
    /// If this device the current device of an owned identity, then currentDeviceIdentity is not nil and remoteDeviceIdentity is nil. If this device is a remote device of an owned identity (thus the current device of this identity on some other physical device), then currentDeviceIdentity is nil and remoteDeviceIdentity is not nil. In both cases, one (and only one) of these two relationships is not nil. This is captured by the computed variable `identity`.
    @NSManaged private(set) var currentDeviceIdentity: OwnedIdentity?
    @NSManaged private(set) var remoteDeviceIdentity: OwnedIdentity?

    private var isCurrentDevice: Bool {
        get throws {
            if currentDeviceIdentity != nil && remoteDeviceIdentity == nil {
                return true
            } else  if currentDeviceIdentity == nil && remoteDeviceIdentity != nil {
                return false
            } else {
                throw ObvError.unexpectedValuesForCurrentDevice
            }
        }
    }
    
    var infos: (name: String?, expirationDate: Date?, latestRegistrationDate: Date?) {
        return (self.name, self.expirationDate, self.latestRegistrationDate)
    }
    
    // MARK: Other variables
    
    var uid: UID {
        get throws(ObvError) {
            guard let rawUID else { assertionFailure(); throw .unexpectedNilValue }
            guard let uid = UID(uid: rawUID) else { assertionFailure(); throw .couldNotParseValue }
            return uid
        }
    }
    
    var identity: OwnedIdentity? {
        if let currentDeviceIdentity {
            return currentDeviceIdentity
        } else if let remoteDeviceIdentity {
            return remoteDeviceIdentity
        } else {
            // Happens if the device was just deleted
            return nil
        }
    }
    private var ownedCryptoIdentityOnDeletion: ObvCryptoIdentity?

    private var changedKeys = Set<String>()
    
    var remoteOwnedDeviceHasPrekey: Bool {
        preKeyForRemoteOwnedDevice != nil
    }

    /// This is only set while inserting a new `OwnedDevice`. This is `true` iff the inserted instance was performed during a `ChannelCreationWithOwnedDeviceProtocol`.
    ///
    /// This value is used in the notification sent to the engine. When receiving the notification, the engine starts a new `ChannelCreationWithOwnedDeviceProtocol` *unless* this Boolean is `true`.
    private var createdDuringChannelCreation: Bool?
    
    // MARK: - Initializers
    
    /// This initializer creates the current device of the owned identity. It should only be called at the time we create an owned identity.
    private convenience init?(ownedIdentity: OwnedIdentity, name: String, with prng: PRNGService) {
        guard let context = ownedIdentity.managedObjectContext else {
            Self.logger.fault("Could not get a context")
            assertionFailure()
            return nil
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedDevice.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.expirationDate = nil // Set later
        self.latestRegistrationDate = nil // Set later
        let trimmedName = name.trimmingWhitespacesAndNewlines()
        self.name = trimmedName.isEmpty ? nil : trimmedName
        self.rawCapabilities = nil // Set bellow
        self.rawUID = UID.gen(with: prng).raw
        
        self.currentDeviceIdentity = ownedIdentity
        self.remoteDeviceIdentity = nil

        self.createdDuringChannelCreation = false // As we are creating the current device
        
        let capabilitiesForCurrentDevice: Set<ObvCapability> = Set(ObvCapability.allCases.filter { capability in
            switch capability {
            case .webrtcContinuousICE: return true
            case .groupsV2: return true
            case .oneToOneContacts: return true
            }
        })
        self.setCapabilities(newCapabilities: capabilitiesForCurrentDevice)
        
    }
    
    
    static func createCurrentOwnedDevice(ownedIdentity: OwnedIdentity, name: String, with prng: PRNGService) -> OwnedDevice? {
        let currentOwnedDevice = Self.init(ownedIdentity: ownedIdentity, name: name, with: prng)
        return currentOwnedDevice
    }

    
    /// This device adds a remote device to the owned identity.
    convenience init?(remoteDeviceUid: UID, ownedIdentity: OwnedIdentity, createdDuringChannelCreation: Bool) {
        guard let context = ownedIdentity.managedObjectContext else {
            Self.logger.fault("Could not get a context")
            assertionFailure()
            return nil
        }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedDevice.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.expirationDate = nil // Set later
        self.latestRegistrationDate = nil // Set later
        self.name = nil // Set later
        self.rawCapabilities = nil // Set later
        self.rawUID = remoteDeviceUid.raw
        
        self.currentDeviceIdentity = nil
        self.remoteDeviceIdentity = ownedIdentity
        
        self.createdDuringChannelCreation = createdDuringChannelCreation
    }

    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreated in a second step
    fileprivate convenience init(backupItem: OwnedDeviceBackupItem, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedDevice.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.expirationDate = nil // Set later
        self.latestRegistrationDate = nil // Set bellow
        self.name = nil // Set later by the engine, using `setCurrentDeviceNameAfterBackupRestore(newName:)`, right after backup restore
        self.rawCapabilities = nil // Set later
        self.rawUID = backupItem.uid.raw
        
        self.createdDuringChannelCreation = false
        
        let capabilitiesForCurrentDevice: Set<ObvCapability> = Set(ObvCapability.allCases.filter { capability in
            switch capability {
            case .webrtcContinuousICE: return true
            case .groupsV2: return true
            case .oneToOneContacts: return true
            }
        })
        self.setCapabilities(newCapabilities: capabilitiesForCurrentDevice)

    }
    

    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreated in a second step
    fileprivate convenience init(snapshotItem: OwnedDeviceSnapshotItem, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedDevice.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
                
        self.expirationDate = nil // Set later
        self.latestRegistrationDate = nil // Set bellow
        let trimmedName = snapshotItem.customDeviceName.trimmingWhitespacesAndNewlines()
        self.name = trimmedName.isEmpty ? nil : trimmedName
        self.rawCapabilities = nil // Set later
        self.rawUID = snapshotItem.uid.raw
        
        self.createdDuringChannelCreation = false
        
        let capabilitiesForCurrentDevice: Set<ObvCapability> = Set(ObvCapability.allCases.filter { capability in
            switch capability {
            case .webrtcContinuousICE: return true
            case .groupsV2: return true
            case .oneToOneContacts: return true
            }
        })
        self.setCapabilities(newCapabilities: capabilitiesForCurrentDevice)

    }

    
    func setCurrentDeviceNameAfterBackupRestore(newName: String) {
        assert(self.name == nil)
        if self.name != newName {
            self.name = newName
        }
    }
    

    func updateThisDevice(with device: OwnedDeviceDiscoveryResult.Device, serverCurrentTimestamp: Date) throws -> DevicePreKey? {
        
        guard try self.uid == device.uid else {
            assertionFailure()
            throw ObvError.unexpectedUID
        }

        if self.expirationDate != device.expirationDate {
            self.expirationDate = device.expirationDate
        }

        if self.name != device.name {
            self.name = device.name
        }
        
        if self.latestRegistrationDate != device.latestRegistrationDate {
            self.latestRegistrationDate = device.latestRegistrationDate
        }
        
        // If self is a remote owned device, we save the current pre-key value if the server returned one
        
        if try self.isCurrentDevice {
            
            let preKeyToUploadForCurrentDevice = try updateThisCurrentOwnedDevicePreKey(device: device,
                                                                                        serverCurrentTimestamp: serverCurrentTimestamp)
            return preKeyToUploadForCurrentDevice
                        
        } else {
            
            updateThisRemoteOwnedDevicePreKey(device: device, serverCurrentTimestamp: serverCurrentTimestamp)
            
            return nil
            
        }
        
    }
    
    
    /// Helper method for ``updateThisDevice(with:serverCurrentTimestamp:delegateManager:)``. It is called during the processing of a ``OwnedDeviceDiscoveryResult.Device`` in case the concerned device is a remote owned device.
    private func updateThisRemoteOwnedDevicePreKey(device: OwnedDeviceDiscoveryResult.Device, serverCurrentTimestamp: Date) {
        
        deleteThisRemoteOwnedDevicePreKeyIfExpired(serverCurrentTimestamp: serverCurrentTimestamp)
        
        if let deviceBlobOnServer = device.deviceBlobOnServer {
            
            // Note that the signature on the deviceBlobOnServer has already been verified

            if deviceBlobOnServer.deviceBlob.devicePreKey.expirationTimestamp > serverCurrentTimestamp {
                do {
                    let devicePreKey = deviceBlobOnServer.deviceBlob.devicePreKey
                    // If the prekey is identical to the one we already have, do nothing. Otherwise, delete the current one and create a new one.
                    if self.preKeyForRemoteOwnedDevice?.cryptoKeyId == devicePreKey.keyId {
                        // Do nothing
                    } else {
                        try self.preKeyForRemoteOwnedDevice?.deletePreKeyForRemoteOwnedDevice()
                        _ = try PreKeyForRemoteOwnedDevice(deviceBlobOnServer: deviceBlobOnServer, forRemoteOwnedDevice: self)
                    }
                } catch {
                    Self.logger.fault("Failed to save preKey on server for a remote owned device: \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                }
            } else {
                do {
                    try self.preKeyForRemoteOwnedDevice?.deletePreKeyForRemoteOwnedDevice()
                } catch {
                    Self.logger.fault("Failed to delete preKey on server for a remote owned device: \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                }
            }
            
            if self.rawCapabilities == nil {
                setCapabilities(newCapabilities: deviceBlobOnServer.deviceBlob.deviceCapabilities)
            }
            
        }
                        
    }
    
    
    /// Helper method for ``updateThisDevice(with:serverCurrentTimestamp:delegateManager:)``. It is called during the processing of a ``OwnedDeviceDiscoveryResult.Device`` in case the concerned device is the current owned device.
    /// This method returns a `DevicePreKey` iff it should be uploaded to the server.
    private func updateThisCurrentOwnedDevicePreKey(device: OwnedDeviceDiscoveryResult.Device, serverCurrentTimestamp: Date) throws -> DevicePreKey? {

        // Note that we do not delete expired pre-keys for the current device. This is not performed during the processing of an owned device discovery, but only after a successful
        // not-truncated list on the server.

        enum CreateOrReturnPreKeyForCurrentOwnedDevice {
            case no
            case createPreKey
            case returnPreKey(devicePreKey: DevicePreKey)
        }

        // Check whether we locally have a pre-key for the server
        let appropriateKeyForServer = self.preKeysForCurrentDevice
            .filter({ !$0.isDeleted })
            .filter({ $0.serverTimestampOnCreation.addingTimeInterval(ObvConstants.preKeyForCurrentDeviceRenewTimeInterval) > serverCurrentTimestamp }) // keep keys that don't need to be renewed
            .compactMap(\.preKey)
            .filter({ $0.expirationTimestamp > serverCurrentTimestamp }) // keep non-expired keys
            .max(by: { $0.expirationTimestamp < $1.expirationTimestamp })

        let createOrReturnPreKeyForCurrentOwnedDevice: CreateOrReturnPreKeyForCurrentOwnedDevice
        
        if let deviceBlobOnServer = device.deviceBlobOnServer {
            
            let devicePreKey = deviceBlobOnServer.deviceBlob.devicePreKey
            
            // There is a pre-key on the server. We check if it is appropriate.
            
            if let appropriateKeyForServer {
                
                if appropriateKeyForServer.keyId == devicePreKey.keyId {
                    // We already created an appropriate key for the server, and it corresponds to the one on the server. There is nothing to do
                    createOrReturnPreKeyForCurrentOwnedDevice = .no
                } else {
                    // We already created an appropriate key for the server, but it does not correspond to the one on the server. We should update the key on the server.
                    if appropriateKeyForServer.expirationTimestamp > devicePreKey.expirationTimestamp {
                        createOrReturnPreKeyForCurrentOwnedDevice = .returnPreKey(devicePreKey: appropriateKeyForServer)
                    } else {
                        createOrReturnPreKeyForCurrentOwnedDevice = .createPreKey
                    }
                }
                
            } else {
                
                // We don't have an (local) appropriate key for the server, we need to create a new one as the one on the server cannot be appropriate
                
                createOrReturnPreKeyForCurrentOwnedDevice = .createPreKey
                
            }
            
        } else {
            
            // There is no pre-key on the server
            
            if let appropriateKeyForServer {
                createOrReturnPreKeyForCurrentOwnedDevice = .returnPreKey(devicePreKey: appropriateKeyForServer)
            } else {
                createOrReturnPreKeyForCurrentOwnedDevice = .createPreKey
            }
            
        }
        
        // Depending on createOrReturnPreKeyForCurrentOwnedDevice, we might need to create a pre-key or to return an existing one
        
        switch createOrReturnPreKeyForCurrentOwnedDevice {

        case .no:
            
            return nil
            
        case .createPreKey:
            
            guard let delegateManager = Self.delegateManager else {
                assertionFailure()
                throw ObvError.delegateManagerNotSet
            }
            
            let devicePreKey = try PreKeyForCurrentOwnedDevice.createPreKeyForCurrentOwnedDevice(
                forCurrentOwnedDevice: self,
                serverCurrentTimestamp: serverCurrentTimestamp,
                prng: delegateManager.prng)
            
            return devicePreKey

        case .returnPreKey(devicePreKey: let devicePreKey):
            
            return devicePreKey
            
        }
        
    }
    
    
    /// Helper method for ``updateThisRemoteOwnedDevicePreKey(device:serverCurrentTimestamp:log:)``
    private func deleteThisRemoteOwnedDevicePreKeyIfExpired(serverCurrentTimestamp: Date) {
        assert((try? isCurrentDevice) == false)
        guard let expirationTimestamp = self.preKeyForRemoteOwnedDevice?.expirationTimestamp else { return }
        if expirationTimestamp < serverCurrentTimestamp {
            do {
                try self.preKeyForRemoteOwnedDevice?.deletePreKeyForRemoteOwnedDevice()
                self.preKeyForRemoteOwnedDevice = nil
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    func deleteThisCurrentOwnedDeviceExpiredPreKeys(downloadTimestampFromServer: Date) throws {
        assert((try? isCurrentDevice) == true)
        try PreKeyForCurrentOwnedDevice.deleteExpiredPreKeysForCurrentOwnedDevice(self, downloadTimestampFromServer: downloadTimestampFromServer)
    }
    
        
    func deleteThisDevice() throws {
        guard let context = managedObjectContext else { assertionFailure(); throw ObvError.noContext }
        ownedCryptoIdentityOnDeletion = try? identity?.cryptoIdentity
        context.delete(self)
    }
    
}


// MARK: - Latest Channel Creation Ping Timestamp

extension OwnedDevice {
    
    func setLatestChannelCreationPingTimestamp(to newValue: Date) {
        if self.latestChannelCreationPingTimestamp != newValue {
            self.latestChannelCreationPingTimestamp = newValue
        }
    }
    
}


// MARK: - Using pre-keys for encryption

extension OwnedDevice {
    
    func wrapForRemoteOwnedDevice(_ messageKey: any AuthenticatedEncryptionKey, with ownedPrivateKeyForAuthentication: any PrivateKeyForAuthentication, and ownedPublicKeyForAuthentication: any PublicKeyForAuthentication, prng: any PRNGService) throws -> EncryptedData? {

        guard let preKeyForRemoteOwnedDevice else { return nil }
        
        let wrappedMessageKey = try preKeyForRemoteOwnedDevice.wrap(messageKey,
                                                                    with: ownedPrivateKeyForAuthentication,
                                                                    and: ownedPublicKeyForAuthentication,
                                                                    prng: prng)
        
        return wrappedMessageKey

    }
    
    
    func unwrapForCurrentOwnedDevice(_ wrappedMessageKey: EncryptedData) throws -> (messageKey: any AuthenticatedEncryptionKey, remoteCryptoId: ObvCryptoIdentity, remoteDeviceUID: UID)? {
        
        guard try isCurrentDevice else { assertionFailure(); return nil }
        
        return try PreKeyForCurrentOwnedDevice.unwrapMessageKey(wrappedMessageKey, forCurrentOwnedDevice: self)
        
    }
    
}


// MARK: - Errors

extension OwnedDevice {
    
    enum ObvError: Error {
        case unexpectedValuesForCurrentDevice
        case unexpectedNilValue
        case couldNotParseValue
        case noContext
        case unexpectedUID
        case delegateManagerNotSet
    }
    
}

// MARK: - Capabilities

extension OwnedDevice {
    
    /// Returns `nil` if the device capabilities were never set yet
    var allCapabilities: Set<ObvCapability>? {
        guard let rawCapabilities = self.rawCapabilities else { return nil }
        let split = rawCapabilities.split(separator: "|")
        return Set(split.compactMap({ ObvCapability(rawValue: String($0)) }))
    }

    func setCapabilities(newCapabilities: Set<ObvCapability>) {
        let newRawCapabilities = Set(newCapabilities.map({ $0.rawValue }))
        self.setRawCapabilities(newRawCapabilities: newRawCapabilities)
    }
    
    func setRawCapabilities(newRawCapabilities: Set<String>) {
        self.rawCapabilities = newRawCapabilities.joined(separator: "|")
    }
    
}


// MARK: - Convenience DB getters

extension OwnedDevice {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<OwnedDevice> {
        return NSFetchRequest<OwnedDevice>(entityName: OwnedDevice.entityName)
    }
    
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case latestChannelCreationPingTimestamp = "latestChannelCreationPingTimestamp"
            case rawCapabilities = "rawCapabilities"
            case rawUID = "rawUID"
            // Relationships
            case currentDeviceIdentity = "currentDeviceIdentity"
            case remoteDeviceIdentity = "remoteDeviceIdentity"
        }
        static func withUid(_ uid: UID) -> NSPredicate {
            NSPredicate(Key.rawUID, EqualToData: uid.raw)
        }
        fileprivate static func withLatestChannelCreationPingTimestamp(earlierThan date: Date) -> NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(withNilValueForKey: Key.latestChannelCreationPingTimestamp),
                NSPredicate(Key.latestChannelCreationPingTimestamp, earlierThan: date),
            ])
        }
    }

    
    /// This class method returns an OwnedDevice, but only if it is the current device.
    static func get(currentDeviceUid: UID, within context: NSManagedObjectContext) throws -> OwnedDevice? {
        let request: NSFetchRequest<OwnedDevice> = OwnedDevice.fetchRequest()
        request.predicate = Predicate.withUid(currentDeviceUid)
        let item = try context.fetch(request).first
        if item?.currentDeviceIdentity == nil {
            return nil
        }
        return item
    }

    /// This class method returns an OwnedDevice, but only if it is *not* the current device.
    static func get(remoteDeviceUid: UID, within context: NSManagedObjectContext) throws -> OwnedDevice? {
        let request: NSFetchRequest<OwnedDevice> = OwnedDevice.fetchRequest()
        request.predicate = Predicate.withUid(remoteDeviceUid)
        let item = try context.fetch(request).first
        if item?.remoteDeviceIdentity == nil {
            return nil
        }
        return item
    }
    
    
    static func getAllOwnedRemoteDeviceUids(within context: NSManagedObjectContext) throws -> Set<ObliviousChannelIdentifier> {
        let request: NSFetchRequest<OwnedDevice> = OwnedDevice.fetchRequest()
        let items = try context.fetch(request)
        let values: Set<ObliviousChannelIdentifier> = try Set(items.compactMap {
            guard let identity = $0.identity, try identity.currentDeviceUid != $0.uid else { return nil }
            return ObliviousChannelIdentifier(currentDeviceUid: try identity.currentDeviceUid,
                                              remoteCryptoIdentity: try identity.cryptoIdentity,
                                              remoteDeviceUid: try $0.uid)
        })
        return values
    }
    
    
    static func getAllOwnedRemoteDeviceUidsWithLatestChannelCreationPingTimestamp(earlierThan date: Date, within context: NSManagedObjectContext) throws -> Set<ObliviousChannelIdentifier> {
        let request: NSFetchRequest<OwnedDevice> = OwnedDevice.fetchRequest()
        request.predicate = Predicate.withLatestChannelCreationPingTimestamp(earlierThan: date)
        request.fetchBatchSize = 500
        let items = try context.fetch(request)
        let values: Set<ObliviousChannelIdentifier> = try Set(items.compactMap {
            guard let identity = $0.identity, try identity.currentDeviceUid != $0.uid else { return nil }
            return ObliviousChannelIdentifier(currentDeviceUid: try identity.currentDeviceUid,
                                              remoteCryptoIdentity: try identity.cryptoIdentity,
                                              remoteDeviceUid: try $0.uid)
        })
        return values
    }
    
}


// MARK: - Notify on changes

extension OwnedDevice {
    
    override func willSave() {
        super.willSave()
        
        changedKeys = Set<String>(self.changedValues().keys)

    }

    override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
        }

        guard let delegateManager = Self.delegateManager else {
            Self.logger.error("The delegate manager is not set (1) - Ok during a backup restore or when deleting the corresponding profile")
            assertionFailure()
            return
        }

        if !isDeleted && changedKeys.contains(Predicate.Key.rawCapabilities.rawValue), let identity = self.identity {
            // We do *not* send the device's capabilities. Eventually, the app will request the capabilities of the owned identity that will compute her capabilities on the basis of the capabilities of all her owned devices.
            do {
                ObvIdentityNotificationNew.ownedIdentityCapabilitiesWereUpdated(ownedIdentity: try identity.cryptoIdentity)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            } catch {
                assertionFailure()
            }
        }
        
        if !isDeleted && !changedKeys.isEmpty, let identity = self.identity {
            do {
                ObvIdentityNotificationNew.anOwnedDeviceWasUpdated(ownedCryptoId: try identity.cryptoIdentity)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            } catch {
                assertionFailure()
            }
        }
        
        if isInserted {
            if let remoteDeviceIdentity, let remoteDeviceUid = try? self.uid {
                assert(createdDuringChannelCreation != nil)
                let createdDuringChannelCreation = self.createdDuringChannelCreation ?? false
                do {
                    ObvIdentityNotificationNew.newRemoteOwnedDevice(ownedCryptoId: try remoteDeviceIdentity.cryptoIdentity,
                                                                    remoteDeviceUid: remoteDeviceUid,
                                                                    createdDuringChannelCreation: createdDuringChannelCreation)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                } catch {
                    assertionFailure()
                }
            }
        }
        
        if isDeleted, let ownedCryptoIdentityOnDeletion {
            ObvIdentityNotificationNew.anOwnedDeviceWasDeleted(ownedCryptoId: ownedCryptoIdentityOnDeletion)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
        }
        
    }
}


// MARK: - For Backup purposes

extension OwnedDevice {
    
    var backupItem: OwnedDeviceBackupItem {
        get throws {
            return OwnedDeviceBackupItem(uid: try self.uid)
        }
    }
    
}


struct OwnedDeviceBackupItem: Codable, Hashable {
    
    fileprivate let uid: UID
    
    fileprivate init(uid: UID) {
        self.uid = uid
    }
    
    enum CodingKeys: String, CodingKey {
        case uid = "uid"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uid.raw, forKey: .uid)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawUid = try values.decode(Data.self, forKey: .uid)
        guard let uid = UID(uid: rawUid) else {
            throw ObvError.couldNotRecoverUID
        }
        self.uid = uid
    }
    
    func restoreRelationships(associations: BackupItemObjectAssociations, within context: NSManagedObjectContext) throws {
        // Nothing do to here
    }

    static func generateNewCurrentDevice(prng: PRNGService, within context: NSManagedObjectContext) -> OwnedDevice {
        let uid = UID.gen(with: prng)
        let dummyBackupItem = OwnedDeviceBackupItem(uid: uid)
        let currentDevice = OwnedDevice(backupItem: dummyBackupItem, within: context)
        return currentDevice
    }
    
    enum ObvError: Error {
        case couldNotRecoverUID
    }
}


// For snapshot purposes

struct OwnedDeviceSnapshotItem {
    
    let uid: UID
    let customDeviceName: String
    
    private init(uid: UID, customDeviceName: String) {
        self.uid = uid
        self.customDeviceName = customDeviceName
    }
    
    static func generateNewCurrentDevice(prng: PRNGService, customDeviceName: String, within context: NSManagedObjectContext) -> OwnedDevice {
        let uid = UID.gen(with: prng)
        let dummySnapshotItem = Self.init(uid: uid, customDeviceName: customDeviceName)
        return .init(snapshotItem: dummySnapshotItem, within: context)
    }
    
}
