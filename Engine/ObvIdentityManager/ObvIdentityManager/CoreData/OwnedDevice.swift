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
import ObvMetaManager
import ObvCrypto
import ObvTypes
import OlvidUtils

@objc(OwnedDevice)
final class OwnedDevice: NSManagedObject, ObvManagedObject {

    private static let errorDomain = "OwnedDevice"

    // MARK: Internal constants
    
    private static let entityName = "OwnedDevice"
    private static let uidKey = "uid"
    private static let currentDeviceIdentityKey = "currentDeviceIdentity"
    private static let remoteDeviceIdentityKey = "remoteDeviceIdentity"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Attributes
    
    @NSManaged private(set) var uid: UID // Unique (not enforced)
    
    // MARK: Relationships
    
    /// If this device the current device of an owned identity, then currentDeviceIdentity is not nil and remoteDeviceIdentity is nil. If this device is a remote device of an owned identity (thus the current device of this identity on some other physical device), then currentDeviceIdentity is nil and remoteDeviceIdentity is not nil. In both cases, one (and only one) of these two relationships is not nil. This is captured by the computed variable `identity`.
    private(set) var currentDeviceIdentity: OwnedIdentity? {
        get {
            let item = kvoSafePrimitiveValue(forKey: OwnedDevice.currentDeviceIdentityKey) as! OwnedIdentity?
            item?.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OwnedDevice.currentDeviceIdentityKey)
        }
    }
    
    private(set) var remoteDeviceIdentity: OwnedIdentity? {
        get {
            let item = kvoSafePrimitiveValue(forKey: OwnedDevice.remoteDeviceIdentityKey) as! OwnedIdentity?
            item?.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: OwnedDevice.remoteDeviceIdentityKey)
        }
    }
    
    // MARK: Other variables
    
    var obvContext: ObvContext?
    weak var delegateManager: ObvIdentityDelegateManager?
    var identity: OwnedIdentity {
        if currentDeviceIdentity != nil {
            currentDeviceIdentity!.delegateManager = delegateManager
            return currentDeviceIdentity!
        } else {
            remoteDeviceIdentity!.delegateManager = delegateManager
            return remoteDeviceIdentity!
        }
    }

    
    // MARK: - Initializers
    
    /// This initializer creates the current device of the owned identity. It should only be called at the time we create an owned identity
    convenience init?(ownedIdentity: OwnedIdentity, with prng: PRNGService, delegateManager: ObvIdentityDelegateManager) {
        guard let obvContext = ownedIdentity.obvContext else {
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: "OwnedDevice")
            os_log("Could not get a context", log: log, type: .fault)
            return nil
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedDevice.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        uid = UID.gen(with: prng)
        currentDeviceIdentity = ownedIdentity
        remoteDeviceIdentity = nil
        self.delegateManager = delegateManager
    }
    
    /// This device adds a remote device to the owned identity.
    convenience init?(remoteDeviceUid: UID, ownedIdentity: OwnedIdentity, delegateManager: ObvIdentityDelegateManager) {
        guard let obvContext = ownedIdentity.obvContext else {
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: "OwnedDevice")
            os_log("Could not get a context", log: log, type: .fault)
            return nil
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedDevice.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.uid = remoteDeviceUid
        currentDeviceIdentity = nil
        remoteDeviceIdentity = ownedIdentity
        self.delegateManager = delegateManager
    }

    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: OwnedDeviceBackupItem, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedDevice.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.uid = backupItem.uid
    }
    
}


// MARK: - Convenience DB getters

extension OwnedDevice {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<OwnedDevice> {
        return NSFetchRequest<OwnedDevice>(entityName: OwnedDevice.entityName)
    }
    
    /// This class method returns an OwnedDevice, but only if it is the current device.
    static func get(currentDeviceUid: UID, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) -> OwnedDevice? {
        let request: NSFetchRequest<OwnedDevice> = OwnedDevice.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", OwnedDevice.uidKey, currentDeviceUid)
        let item = (try? obvContext.fetch(request))?.first
        if item?.currentDeviceIdentity == nil {
            return nil
        }
        item?.delegateManager = delegateManager
        return item
    }

    /// This class method returns an OwnedDevice, but only if it is *not* the current device.
    static func get(remoteDeviceUid: UID, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) -> OwnedDevice? {
        let request: NSFetchRequest<OwnedDevice> = OwnedDevice.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", OwnedDevice.uidKey, remoteDeviceUid)
        let item = (try? obvContext.fetch(request))?.first
        if item?.remoteDeviceIdentity == nil {
            return nil
        }
        item?.delegateManager = delegateManager
        return item
    }
    
    
    static func getAllOwnedRemoteDeviceUids(within obvContext: ObvContext) throws -> Set<ObliviousChannelIdentifier> {
        let request: NSFetchRequest<OwnedDevice> = OwnedDevice.fetchRequest()
        let items = try obvContext.fetch(request)
        let values: Set<ObliviousChannelIdentifier> = Set(items.compactMap {
            guard $0.identity.currentDeviceUid != $0.uid else { return nil }
            return ObliviousChannelIdentifier(currentDeviceUid: $0.identity.currentDeviceUid, remoteCryptoIdentity: $0.identity.cryptoIdentity, remoteDeviceUid: $0.uid)
        })
        return values
    }
    
}


// MARK: - For Backup purposes

extension OwnedDevice {
    
    var backupItem: OwnedDeviceBackupItem {
        return OwnedDeviceBackupItem(uid: self.uid)
    }
    
}


struct OwnedDeviceBackupItem: Codable, Hashable {
    
    fileprivate let uid: UID
    
    fileprivate init(uid: UID) {
        self.uid = uid
    }
    
    private static let errorDomain = String(describing: Self.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
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
            throw OwnedDeviceBackupItem.makeError(message: "Could not recover uid")
        }
        self.uid = uid
    }
    
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let ownedDevice = OwnedDevice(backupItem: self, within: obvContext)
        try associations.associate(ownedDevice, to: self)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing do to here
    }

    static func generateNewCurrentDevice(prng: PRNGService, within obvContext: ObvContext) -> OwnedDevice {
        let uid = UID.gen(with: prng)
        let dummyBackupItem = OwnedDeviceBackupItem(uid: uid)
        let currentDevice = OwnedDevice(backupItem: dummyBackupItem, within: obvContext)
        return currentDevice
    }
}
