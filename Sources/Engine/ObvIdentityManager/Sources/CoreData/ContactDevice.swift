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
import CoreData
import os.log
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils
import ObvEncoder


@objc(ContactDevice)
final class ContactDevice: NSManagedObject, ObvManagedObject {
    
    private static let entityName = "ContactDevice"
    private static func makeError(message: String) -> Error { NSError(domain: "ContactDevice", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }


    // MARK: Attributes
    
    @NSManaged private(set) var latestChannelCreationPingTimestamp: Date?
    @NSManaged private(set) var uid: UID
    @NSManaged private var rawCapabilities: String?


    // MARK: Relationships
    
    @NSManaged private var preKeyForContactDevice: PreKeyForContactDevice? // May be non-nil. Set in the init of PreKeyForContactDevice
    
    private(set) var contactIdentity: ContactIdentity? {
        get {
            guard let res = kvoSafePrimitiveValue(forKey: Predicate.Key.contactIdentity.rawValue) as? ContactIdentity else { return nil }
            res.obvContext = self.obvContext
            res.delegateManager = delegateManager
            return res
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: Predicate.Key.contactIdentity.rawValue)
        }
    }
    

    // MARK: Other variables
    
    weak var obvContext: ObvContext?
    weak var delegateManager: ObvIdentityDelegateManager?
    private var ownedCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var contactCryptoIdentityOnDeletion: ObvCryptoIdentity?
    
    private var changedKeys = Set<String>()
    
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
    ///   - delegateManager: The `ObvIdentityDelegateManager`
    convenience init?(uid: UID, contactIdentity: ContactIdentity, createdDuringChannelCreation: Bool, flowId: FlowIdentifier, delegateManager: ObvIdentityDelegateManager) {
        let log = OSLog(subsystem: delegateManager.logSubsystem, category: "ContactDevice")
        guard let obvContext = contactIdentity.obvContext else {
            os_log("Could not get a context", log: log, type: .fault)
            return nil
        }
        // Check that no entry with the same `uid` and `contactIdentity` exists
        guard contactIdentity.devices.first(where: { $0.uid == uid }) == nil else {
            os_log("Cannot add the same contact device twice", log: log, type: .error)
            return nil
        }
        // An entity can be created
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactDevice.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.uid = uid
        self.rawCapabilities = nil // Set later
        self.contactIdentity = contactIdentity
        self.delegateManager = delegateManager
        self.createdDuringChannelCreation = createdDuringChannelCreation
    }

    
    func deleteContactDevice() throws {
        guard let obvContext = self.obvContext else {
            assertionFailure()
            throw ContactDevice.makeError(message: "Could not find context --> could not delete device")
        }
        obvContext.delete(self)
    }
}


// MARK: - Updating using a contact device discovery result

extension ContactDevice {
    
    func updateWithContactDeviceDiscoveryResultDevice(_ deviceOnServer: ContactDeviceDiscoveryResult.Device, serverCurrentTimestamp: Date, log: OSLog) throws {
        
        // No need to delete expired pre-keys, it will be deleted anyway if the key on server is expired
        
        guard self.uid == deviceOnServer.uid else {
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
                    os_log("Failed to save preKey on server for a contact device: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                }
            } else {
                do {
                    try self.preKeyForContactDevice?.deletePreKeyForContactDevice()
                } catch {
                    os_log("Failed to delete preKey on server for a contact device: %{public}@", log: log, type: .fault, error.localizedDescription)
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
            case uid = "uid"
            case rawCapabilities = "rawCapabilities"
            case contactIdentity = "contactIdentity"
            case preKeyForContactDevice = "preKeyForContactDevice"
            case latestChannelCreationPingTimestamp = "latestChannelCreationPingTimestamp"
        }
        fileprivate static func withLatestChannelCreationPingTimestamp(earlierThan date: Date) -> NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(withNilValueForKey: Key.latestChannelCreationPingTimestamp),
                NSPredicate(Key.latestChannelCreationPingTimestamp, earlierThan: date),
            ])
        }
    }

    
    static func getAllContactDeviceUids(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifier> {
        let request: NSFetchRequest<ContactDevice> = ContactDevice.fetchRequest()
        let items = try obvContext.fetch(request)
        let values: Set<ObliviousChannelIdentifier> = Set(items.compactMap {
            guard let contactIdentity = $0.contactIdentity else { return nil }
            guard let ownedIdentity = contactIdentity.ownedIdentity else { return nil }
            guard let remoteCryptoIdentity = contactIdentity.cryptoIdentity else { assertionFailure(); return nil }
            return ObliviousChannelIdentifier(currentDeviceUid: ownedIdentity.currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: $0.uid)
        })
        return values
    }
    
    
    static func getAllContactDeviceUidsWithLatestChannelCreationPingTimestamp(earlierThan date: Date, within context: NSManagedObjectContext) throws -> Set<ObliviousChannelIdentifier> {
        let request: NSFetchRequest<ContactDevice> = ContactDevice.fetchRequest()
        request.predicate = Predicate.withLatestChannelCreationPingTimestamp(earlierThan: date)
        request.fetchBatchSize = 500
        let items = try context.fetch(request)
        let values: Set<ObliviousChannelIdentifier> = Set(items.compactMap {
            guard let contactIdentity = $0.contactIdentity else { return nil }
            guard let ownedIdentity = contactIdentity.ownedIdentity else { return nil }
            guard let remoteCryptoIdentity = contactIdentity.cryptoIdentity else { assertionFailure(); return nil }
            return ObliviousChannelIdentifier(currentDeviceUid: ownedIdentity.currentDeviceUid, remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: $0.uid)
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
            self.ownedCryptoIdentityOnDeletion = ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity()
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
        
        guard let delegateManager = delegateManager else {
            let log = OSLog.init(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: ContactDevice.entityName)
            os_log("The delegate manager is not set (1)", log: log, type: .fault)
            return
        }
        
        let log = OSLog.init(subsystem: delegateManager.logSubsystem, category: ContactDevice.entityName)

        guard let flowId = obvContext?.flowId else {
            os_log("The obvContext is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        if isInserted {
            
            guard let contactIdentity, let ownedIdentity = contactIdentity.ownedIdentity, let contactIdentity = contactIdentity.cryptoIdentity else {
                assertionFailure()
                return
            }
            assert(createdDuringChannelCreation != nil)
            let createdDuringChannelCreation = self.createdDuringChannelCreation ?? false
            ObvIdentityNotificationNew.newContactDevice(ownedIdentity: ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity(),
                                                        contactIdentity: contactIdentity,
                                                        contactDeviceUid: uid,
                                                        createdDuringChannelCreation: createdDuringChannelCreation,
                                                        flowId: flowId)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            
        } else if isDeleted {
            
            guard let ownedCryptoIdentityOnDeletion = self.ownedCryptoIdentityOnDeletion else {
                os_log("ownedCryptoIdentityOnDeletion is nil on deletion which is unexpected", log: log, type: .fault)
                return
            }

            guard let contactCryptoIdentityOnDeletion = self.contactCryptoIdentityOnDeletion else {
                os_log("contactCryptoIdentityOnDeletion is nil on deletion which is unexpected", log: log, type: .fault)
                return
            }

            ObvIdentityNotificationNew.deletedContactDevice(ownedIdentity: ownedCryptoIdentityOnDeletion,
                                                            contactIdentity: contactCryptoIdentityOnDeletion,
                                                            contactDeviceUid: uid,
                                                            flowId: flowId)
            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)

        } else if let ownedIdentity = contactIdentity?.ownedIdentity {
            
            guard let contactIdentity = self.contactIdentity else { assertionFailure(); return }
            
            if changedKeys.contains(Predicate.Key.rawCapabilities.rawValue), let contactIdentity = contactIdentity.cryptoIdentity {
                ObvIdentityNotificationNew.contactObvCapabilitiesWereUpdated(
                    ownedIdentity: ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity(),
                    contactIdentity: contactIdentity,
                    flowId: flowId)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            }
            
            if changedKeys.contains(Predicate.Key.preKeyForContactDevice.rawValue), let contactIdentity = contactIdentity.cryptoIdentity {
                let contactDeviceIdentifier = ObvContactDeviceIdentifier(ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedIdentity.cryptoIdentity), contactCryptoId: ObvCryptoId(cryptoIdentity: contactIdentity), deviceUID: self.uid)
                ObvIdentityNotificationNew.updatedContactDevice(deviceIdentifier: contactDeviceIdentifier, flowId: flowId)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            }
            
        }
    }
}
