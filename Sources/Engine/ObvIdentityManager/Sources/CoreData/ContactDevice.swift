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
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvEncoder


@objc(ContactDevice)
final class ContactDevice: NSManagedObject {
    
    private static let entityName = "ContactDevice"
    static weak var delegateManager: ObvIdentityDelegateManager?

    private static func makeError(message: String) -> Error { NSError(domain: "ContactDevice", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactDevice.logSubsystem, category: "ContactDevice") }()
    
    // MARK: Attributes
    
    @NSManaged private(set) var latestChannelCreationPingTimestamp: Date?
    @NSManaged private var rawCapabilities: String?
    @NSManaged private var rawUID: Data? // Non-optional in the model, raw value of an UID


    // MARK: Relationships
    
    @NSManaged private var preKeyForContactDevice: PreKeyForContactDevice? // May be non-nil. Set in the init of PreKeyForContactDevice
    @NSManaged private(set) var contactIdentity: ContactIdentity?
    

    // MARK: Other variables
    
    private var ownedCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var contactCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var uidOnDeletion: UID?
    
    private var changedKeys = Set<String>()
    
    var uid: UID {
        get throws(ObvError) {
            guard let rawUID else { assertionFailure(); throw .unexpectedNilValue }
            guard let uid = UID(uid: rawUID) else { assertionFailure(); throw .couldNotParseValue }
            return uid
        }
    }
    
    var hasPreKey: Bool {
        preKeyForContactDevice != nil
    }

    /// This is only set while inserting a new `ContactDevice`. This is `true` iff the inserted instance was performed during a `ChannelCreationWithContactDeviceProtocol`.
    ///
    /// This value is used in the notification sent to the engine. When receiving the notification, the engine starts a new `ChannelCreationWithContactDeviceProtocol` *unless* this Boolean is `true`.
    private var createdDuringChannelCreation: Bool?

    // MARK: - Initializer
    
    /// This initializer makes sure that we do not insert a contact device if another one with the same (`uid`, `contactIdentity`) already exists. Note that a `contactIdentity` is identified by its cryptoIdentity and its ownedIdentity. If a previous entity exists, this initializer fails.
    ///
    /// - Parameters:
    ///   - uid: The `UID` of the device
    ///   - contactIdentity: The `ContactIdentity` that owns this device
    convenience init?(uid: UID, contactIdentity: ContactIdentity, createdDuringChannelCreation: Bool) throws {
        
        guard let context = contactIdentity.managedObjectContext else {
            Self.logger.fault("Could not get a context")
            return nil
        }
        
        // Check that no entry with the same `uid` and `contactIdentity` exists
        guard try contactIdentity.devices.first(where: { try $0.uid == uid }) == nil else {
            Self.logger.error("Cannot add the same contact device twice")
            return nil
        }
        
        // An entity can be created
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactDevice.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.rawUID = uid.raw
        self.rawCapabilities = nil // Set later
        self.contactIdentity = contactIdentity
        self.createdDuringChannelCreation = createdDuringChannelCreation
        
    }

    
    func deleteContactDevice() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ContactDevice.makeError(message: "Could not find context --> could not delete device")
        }
        context.delete(self)
    }
    
}


// MARK: - Updating using a contact device discovery result

extension ContactDevice {
    
    func updateWithContactDeviceDiscoveryResultDevice(_ deviceOnServer: ContactDeviceDiscoveryResult.Device, serverCurrentTimestamp: Date) throws {
        
        // No need to delete expired pre-keys, it will be deleted anyway if the key on server is expired
        
        guard try self.uid == deviceOnServer.uid else {
            assertionFailure()
            throw ObvError.unexpectedUID
        }
        
        if let deviceBlobOnServer = deviceOnServer.deviceBlobOnServer {
            
            // Note that the signature on the deviceBlobOnServer has already been verified
            
            if deviceBlobOnServer.deviceBlob.devicePreKey.expirationTimestamp > serverCurrentTimestamp {
                let devicePreKey = deviceBlobOnServer.deviceBlob.devicePreKey
                do {
                    // If the prekey is identical to the one we already have, do nothing. Otherwise, delete the current one and create a new one.
                    if self.preKeyForContactDevice?.cryptoKeyId == devicePreKey.keyId {
                        // Do nothing
                    } else {
                        try self.preKeyForContactDevice?.deletePreKeyForContactDevice()
                        _ = try PreKeyForContactDevice(deviceBlobOnServer: deviceBlobOnServer, forContactDevice: self)
                    }
                } catch {
                    Self.logger.fault("Failed to save preKey on server for a contact device: \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                }
            } else {
                do {
                    try self.preKeyForContactDevice?.deletePreKeyForContactDevice()
                } catch {
                    Self.logger.fault("Failed to delete preKey on server for a contact device: \(error.localizedDescription, privacy: .public)")
                    assertionFailure()
                }
            }
            
            let deviceCapabilitiesFromServer = deviceBlobOnServer.deviceBlob.deviceCapabilities
            if self.rawCapabilities == nil {
                self.setRawCapabilities(newRawCapabilities: Set(deviceCapabilitiesFromServer.map(\.rawValue)))
            }
            
        }
        
    }
    
}


// MARK: - Latest Channel Creation Ping Timestamp

extension ContactDevice {
    
    func setLatestChannelCreationPingTimestamp(to newValue: Date) {
        if self.latestChannelCreationPingTimestamp != newValue {
            self.latestChannelCreationPingTimestamp = newValue
        }
    }
    
}


// MARK: - Encryption leveraging the preKey

extension ContactDevice {
    
    func wrap(_ messageKey: any AuthenticatedEncryptionKey, with ownedPrivateKeyForAuthentication: any PrivateKeyForAuthentication, and ownedPublicKeyForAuthentication: any PublicKeyForAuthentication, prng: any PRNGService) throws -> EncryptedData? {
        
        guard let preKeyForContactDevice else { return nil }
        
        let wrappedMessageKey = try preKeyForContactDevice.wrap(messageKey,
                                                                with: ownedPrivateKeyForAuthentication,
                                                                and: ownedPublicKeyForAuthentication,
                                                                prng: prng)
        
        return wrappedMessageKey
        
    }
    
}


// MARK: - Errors

extension ContactDevice {
    
    enum ObvError: Error {
        case unexpectedUID
        case unexpectedNilValue
        case couldNotParseValue
    }
    
}


// MARK: - Capabilities

extension ContactDevice {
    
    /// Returns `nil` if the device capabilities were never set yet
    var allCapabilities: Set<ObvCapability>? {
        guard let rawCapabilities = self.rawCapabilities else { return nil }
        let split = rawCapabilities.split(separator: "|")
        return Set(split.compactMap({ ObvCapability(rawValue: String($0)) }))
    }

    func setRawCapabilities(newRawCapabilities: Set<String>) {
        let newCapabilitiesJoined = newRawCapabilities.sorted().joined(separator: "|")
        if self.rawCapabilities != newCapabilitiesJoined {
            self.rawCapabilities = newCapabilitiesJoined
        }
    }
    
}

// MARK: - Convenience DB getters

extension ContactDevice {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactDevice> {
        return NSFetchRequest<ContactDevice>(entityName: self.entityName)
    }

    
    struct Predicate {
        enum Key: String {
            // Attributes
            case latestChannelCreationPingTimestamp = "latestChannelCreationPingTimestamp"
            case rawCapabilities = "rawCapabilities"
            case rawUID = "rawUID"
            // Relationships
            case contactIdentity = "contactIdentity"
            case preKeyForContactDevice = "preKeyForContactDevice"
        }
        fileprivate static func withLatestChannelCreationPingTimestamp(earlierThan date: Date) -> NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(withNilValueForKey: Key.latestChannelCreationPingTimestamp),
                NSPredicate(Key.latestChannelCreationPingTimestamp, earlierThan: date),
            ])
        }
    }

    
    static func getAllContactDeviceUids(within context: NSManagedObjectContext) throws -> Set<ObliviousChannelIdentifier> {
        let request: NSFetchRequest<ContactDevice> = ContactDevice.fetchRequest()
        let items = try context.fetch(request)
        let values: Set<ObliviousChannelIdentifier> = try Set(items.compactMap {
            guard let contactIdentity = $0.contactIdentity else { return nil }
            guard let ownedIdentity = contactIdentity.ownedIdentity else { return nil }
            guard let remoteCryptoIdentity = contactIdentity.cryptoIdentity else { assertionFailure(); return nil }
            return try ObliviousChannelIdentifier(currentDeviceUid: ownedIdentity.currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: $0.uid)
        })
        return values
    }
    
    
    static func getAllContactDeviceUidsWithLatestChannelCreationPingTimestamp(earlierThan date: Date, within context: NSManagedObjectContext) throws -> Set<ObliviousChannelIdentifier> {
        let request: NSFetchRequest<ContactDevice> = ContactDevice.fetchRequest()
        request.predicate = Predicate.withLatestChannelCreationPingTimestamp(earlierThan: date)
        request.fetchBatchSize = 500
        let items = try context.fetch(request)
        let values: Set<ObliviousChannelIdentifier> = try Set(items.compactMap {
            guard let contactIdentity = $0.contactIdentity else { return nil }
            guard let ownedIdentity = contactIdentity.ownedIdentity else { return nil }
            guard let remoteCryptoIdentity = contactIdentity.cryptoIdentity else { assertionFailure(); return nil }
            return try ObliviousChannelIdentifier(currentDeviceUid: ownedIdentity.currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: $0.uid)
        })
        return values
    }

}

// MARK: - Managing Change Events

extension ContactDevice {

    override func prepareForDeletion() {
        super.prepareForDeletion()
        
        if let contactIdentity = self.contactIdentity, let ownedIdentity = contactIdentity.ownedIdentity {
            self.contactCryptoIdentityOnDeletion = contactIdentity.cryptoIdentity
            self.ownedCryptoIdentityOnDeletion = try? ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity()
        }
        if let uid = try? self.uid {
            self.uidOnDeletion = uid
        }
        
    }
    
    override func willSave() {
        super.willSave()
        changedKeys = Set<String>(self.changedValues().keys)
    }
    
    
    override func didSave() {
        super.didSave()
        
        defer {
            ownedCryptoIdentityOnDeletion = nil
            contactCryptoIdentityOnDeletion = nil
            changedKeys.removeAll()
        }
        
        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is not set (1)")
            return
        }
        
        if isInserted {
            
            guard let contactIdentity, let ownedIdentity = try? contactIdentity.ownedIdentity?.ownedCryptoIdentity.getObvCryptoIdentity(), let contactIdentity = contactIdentity.cryptoIdentity, let uid = try? self.uid else {
                assertionFailure()
                return
            }
            assert(createdDuringChannelCreation != nil)
            let createdDuringChannelCreation = self.createdDuringChannelCreation ?? false
            ObvIdentityNotificationNew.newContactDevice(ownedIdentity: ownedIdentity,
                                                        contactIdentity: contactIdentity,
                                                        contactDeviceUid: uid,
                                                        createdDuringChannelCreation: createdDuringChannelCreation,
                                                        flowId: FlowIdentifier())
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            
        } else if isDeleted {
            
            guard let ownedCryptoIdentityOnDeletion = self.ownedCryptoIdentityOnDeletion else {
                Self.logger.fault("ownedCryptoIdentityOnDeletion is nil on deletion which is unexpected")
                return
            }

            guard let contactCryptoIdentityOnDeletion = self.contactCryptoIdentityOnDeletion else {
                Self.logger.fault("contactCryptoIdentityOnDeletion is nil on deletion which is unexpected")
                return
            }
            
            guard let uidOnDeletion else {
                Self.logger.fault("uidOnDeletion is nil on deletion which is unexpected")
                return
            }

            ObvIdentityNotificationNew.deletedContactDevice(ownedIdentity: ownedCryptoIdentityOnDeletion,
                                                            contactIdentity: contactCryptoIdentityOnDeletion,
                                                            contactDeviceUid: uidOnDeletion)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)

        } else if let ownedIdentity = try? contactIdentity?.ownedIdentity?.ownedCryptoIdentity.getObvCryptoIdentity() {
            
            guard let contactIdentity = self.contactIdentity else { assertionFailure(); return }
            
            if changedKeys.contains(Predicate.Key.rawCapabilities.rawValue), let contactIdentity = contactIdentity.cryptoIdentity {
                ObvIdentityNotificationNew.contactObvCapabilitiesWereUpdated(
                    ownedIdentity: ownedIdentity,
                    contactIdentity: contactIdentity)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            }
            
            if changedKeys.contains(Predicate.Key.preKeyForContactDevice.rawValue), let contactIdentity = contactIdentity.cryptoIdentity, let uid = try? self.uid {
                let contactDeviceIdentifier = ObvContactDeviceIdentifier(
                    ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedIdentity),
                    contactCryptoId: ObvCryptoId(cryptoIdentity: contactIdentity),
                    deviceUID: uid)
                ObvIdentityNotificationNew.updatedContactDevice(deviceIdentifier: contactDeviceIdentifier)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            }
            
        }
    }
}
