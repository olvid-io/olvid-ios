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
import os.log
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils


@objc(ContactDevice)
final class ContactDevice: NSManagedObject, ObvManagedObject {
    
    private static let entityName = "ContactDevice"
    private static func makeError(message: String) -> Error { NSError(domain: "ContactDevice", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }


    // MARK: Attributes
    
    @NSManaged private(set) var uid: UID
    @NSManaged private var rawCapabilities: String?


    // MARK: Relationships
    
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
    
    var obvContext: ObvContext?
    weak var delegateManager: ObvIdentityDelegateManager?
    private var ownedCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var contactCryptoIdentityOnDeletion: ObvCryptoIdentity?
    
    private var changedKeys = Set<String>()

    // MARK: - Initializer
    
    /// This initializer makes sure that we do not insert a contact device if another one with the same (`uid`, `contactIdentity`) already exists. Note that a `contactIdentity` is identified by its cryptoIdentity and its ownedIdentity. If a previous entity exists, this initializer fails.
    ///
    /// - Parameters:
    ///   - uid: The `UID` of the device
    ///   - contactIdentity: The `ContactIdentity` that owns this device
    ///   - delegateManager: The `ObvIdentityDelegateManager`
    convenience init?(uid: UID, contactIdentity: ContactIdentity, flowId: FlowIdentifier, delegateManager: ObvIdentityDelegateManager) {
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
    }

    
    func delete() throws {
        guard let obvContext = self.obvContext else {
            assertionFailure()
            throw ContactDevice.makeError(message: "Could not find contact --> could not delete device")
        }
        obvContext.delete(self)
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
        self.rawCapabilities = newRawCapabilities.sorted().joined(separator: "|")
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
        }
    }

    
    static func getAllContactDeviceUids(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifier> {
        let request: NSFetchRequest<ContactDevice> = ContactDevice.fetchRequest()
        let items = try obvContext.fetch(request)
        let values: Set<ObliviousChannelIdentifier> = Set(items.compactMap {
            guard let contactIdentity = $0.contactIdentity else { return nil }
            return ObliviousChannelIdentifier(currentDeviceUid: contactIdentity.ownedIdentity.currentDeviceUid, remoteCryptoIdentity: contactIdentity.cryptoIdentity, remoteDeviceUid: $0.uid)
        })
        return values
    }

}

// MARK: - Managing Change Events

extension ContactDevice {

    override func prepareForDeletion() {
        super.prepareForDeletion()
        if let contactIdentity = self.contactIdentity {
            self.contactCryptoIdentityOnDeletion = contactIdentity.cryptoIdentity
            self.ownedCryptoIdentityOnDeletion = contactIdentity.ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity()
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
            
            guard let contactIdentity = self.contactIdentity else {
                assertionFailure()
                return
            }
            ObvIdentityNotificationNew.newContactDevice(ownedIdentity: contactIdentity.ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity(),
                                                        contactIdentity: contactIdentity.cryptoIdentity,
                                                        contactDeviceUid: uid,
                                                        flowId: flowId)
                .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
            
        } else if isDeleted {
            
            guard let ownedCryptoIdentityOnDeletion = self.ownedCryptoIdentityOnDeletion, let contactCryptoIdentityOnDeletion = self.contactCryptoIdentityOnDeletion else {
                os_log("ownedCryptoIdentityOnDeletion or contactCryptoIdentityOnDeletion is nil on deletion which is unexpected", log: log, type: .fault)
                return
            }
            
            let notification = ObvIdentityNotificationNew.deletedContactDevice(ownedIdentity: ownedCryptoIdentityOnDeletion,
                                                                               contactIdentity: contactCryptoIdentityOnDeletion,
                                                                               contactDeviceUid: uid,
                                                                               flowId: flowId)
            notification.postOnBackgroundQueue(within: delegateManager.notificationDelegate)
            
        } else {
            
            guard let contactIdentity = self.contactIdentity else { assertionFailure(); return }
            if changedKeys.contains(Predicate.Key.rawCapabilities.rawValue) {
                ObvIdentityNotificationNew.contactObvCapabilitiesWereUpdated(
                    ownedIdentity: contactIdentity.ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity(),
                    contactIdentity: contactIdentity.cryptoIdentity,
                    flowId: flowId)
                    .postOnBackgroundQueue(within: delegateManager.notificationDelegate)
            }
            
        }
    }
}
