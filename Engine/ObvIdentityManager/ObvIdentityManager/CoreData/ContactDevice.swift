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
import os.log
import ObvCrypto
import ObvTypes
import ObvMetaManager
import OlvidUtils


@objc(ContactDevice)
final class ContactDevice: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "ContactDevice"
    private static let uidKey = "uid"
    private static let contactIdentityKey = "contactIdentity"
    private static let contactIdentityCryptoIdentityKey = [contactIdentityKey, ContactIdentity.cryptoIdentityKey].joined(separator: ".")
    private static let contactIdentityOwnedIdentityCryptoIdentityKey = [contactIdentityKey, ContactIdentity.ownedIdentityKey, OwnedIdentity.cryptoIdentityKey].joined(separator: ".")
    
    private static let errorDomain = "ContactDevice"
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: Attributes
    
    @NSManaged private(set) var uid: UID
    
    // MARK: Relationships
    
    private(set) var contactIdentity: ContactIdentity? {
        get {
            guard let res = kvoSafePrimitiveValue(forKey: ContactDevice.contactIdentityKey) as? ContactIdentity else { return nil }
            res.obvContext = self.obvContext
            res.delegateManager = delegateManager
            return res
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: ContactDevice.contactIdentityKey)
        }
    }
    
    // MARK: Other variables
    
    var obvContext: ObvContext?
    weak var delegateManager: ObvIdentityDelegateManager?
    private var ownedCryptoIdentityOnDeletion: ObvCryptoIdentity?
    private var contactCryptoIdentityOnDeletion: ObvCryptoIdentity?
    
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
        do {
            guard try !ContactDevice.exists(uid: uid, contactIdentity: contactIdentity, within: obvContext) else {
                os_log("Cannot add the same contact device twice", log: log, type: .error)
                return nil
            }
        } catch let error {
            os_log("%@", log: log, type: .fault, error.localizedDescription)
            return nil
        }
        // An entity can be created
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactDevice.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.uid = uid
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

// MARK: - Convenience DB getters
extension ContactDevice {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactDevice> {
        return NSFetchRequest<ContactDevice>(entityName: self.entityName)
    }
 
    /// This getter tries to fetch the ContactDevice for the given `uid` and contact identity identified by its `ObvCryptoIdentity`. There can be at most one.
    ///
    /// - Parameters:
    ///   - uid: The `UID` of the contact device to get.
    ///   - cryptoIdentity: The crypto identity of the contact identity to whom the device must belong.
    ///   - delegateManager: The `ObvIdentityDelegateManager`.
    ///   - obvContext: The `ObvContext` where to perform the fetch.
    /// - Returns: The `ContactDevice` instance if one was found, `nil` otherwise.
    static func get(uid: UID, contactIdentity: ContactIdentity, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) -> ContactDevice? {
        let request: NSFetchRequest<ContactDevice> = ContactDevice.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                                        self.uidKey, uid,
                                        self.contactIdentityCryptoIdentityKey, contactIdentity.cryptoIdentity,
                                        self.contactIdentityOwnedIdentityCryptoIdentityKey, contactIdentity.ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity())
        let item = (try? obvContext.fetch(request))?.filter { $0.contactIdentity?.cryptoIdentity == contactIdentity }.first
        item?.delegateManager = delegateManager
        return item
    }
    
    static func exists(uid: UID, contactIdentity: ContactIdentity, within obvContext: ObvContext) throws -> Bool {
        let request: NSFetchRequest<ContactDevice> = ContactDevice.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@ AND %K == %@",
                                        self.uidKey, uid,
                                        self.contactIdentityCryptoIdentityKey, contactIdentity.cryptoIdentity,
                                        self.contactIdentityOwnedIdentityCryptoIdentityKey, contactIdentity.ownedIdentity.ownedCryptoIdentity.getObvCryptoIdentity())
        return try obvContext.count(for: request) != 0
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
    
    
    override func didSave() {
        super.didSave()
        
        defer {
            ownedCryptoIdentityOnDeletion = nil
            contactCryptoIdentityOnDeletion = nil
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
            
        }
    }
}
