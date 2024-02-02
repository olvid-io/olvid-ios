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
import os.log
import ObvCrypto
import ObvMetaManager
import ObvTypes
import OlvidUtils


@objc(PendingGroupMember)
final class PendingGroupMember: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "PendingGroupMember"
    private static let errorDomain = String(describing: PendingGroupMember.self)
    private static let cryptoIdentityKey = "cryptoIdentity"
    private static let serializedIdentityCoreDetails = "serializedIdentityCoreDetails"
    private static let contactGroupKey = "contactGroup"
    private static let declinedKey = "declined"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    // MARK: Attributes
    
    @NSManaged private(set) var cryptoIdentity: ObvCryptoIdentity
    @NSManaged private(set) var declined: Bool
    @NSManaged private var serializedIdentityCoreDetails: Data
    
    // MARK: Relationships
    
    private(set) var contactGroup: ContactGroup {
        get {
            let item = kvoSafePrimitiveValue(forKey: PendingGroupMember.contactGroupKey) as! ContactGroup
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: PendingGroupMember.contactGroupKey)
        }
    }
    
    // MARK: Other variables
    
    private var changedKeys = Set<String>()
    
    weak var delegateManager: ObvIdentityDelegateManager?
    
    var identityCoreDetails: ObvIdentityCoreDetails {
        let data = kvoSafePrimitiveValue(forKey: PendingGroupMember.serializedIdentityCoreDetails) as! Data
        return try! ObvIdentityCoreDetails(data)
    }
    
    var obvContext: ObvContext?
    
    // MARK: - Initializer
    
    convenience init(contactGroup: ContactGroup, cryptoIdentityWithCoreDetails: CryptoIdentityWithCoreDetails, delegateManager: ObvIdentityDelegateManager) throws {
        guard let obvContext = contactGroup.obvContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: PendingGroupMember.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.cryptoIdentity = cryptoIdentityWithCoreDetails.cryptoIdentity
        self.declined = false
        self.serializedIdentityCoreDetails = try cryptoIdentityWithCoreDetails.coreDetails.jsonEncode()
        self.contactGroup = contactGroup
        self.delegateManager = delegateManager
    }

    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: PendingGroupMemberBackupItem, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PendingGroupMember.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.cryptoIdentity = backupItem.cryptoIdentity
        self.declined = backupItem.declined
        self.serializedIdentityCoreDetails = backupItem.serializedIdentityCoreDetails
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(cryptoIdentity: ObvCryptoIdentity, snapshotItem: PendingGroupMemberSyncSnapshotItem, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PendingGroupMember.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.cryptoIdentity = cryptoIdentity
        self.declined = snapshotItem.declined
        self.serializedIdentityCoreDetails = snapshotItem.serializedIdentityCoreDetails
    }

}


// MARK: - Convenience methods

extension PendingGroupMember {
    
    func markAsDeclined(delegateManager: ObvIdentityDelegateManager?) {
        self.delegateManager = delegateManager
        if !self.declined {
            self.declined = true
        }
    }
    
    func unmarkAsDeclined(delegateManager: ObvIdentityDelegateManager?) {
        self.delegateManager = delegateManager
        if self.declined {
            self.declined = false
        }
    }

}


// MARK: - Convenience DB getters

extension PendingGroupMember {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PendingGroupMember> {
        return NSFetchRequest<PendingGroupMember>(entityName: entityName)
    }

    
    static func get(cryptoIdentity: ObvCryptoIdentity, contactGroup: ContactGroup, delegateManager: ObvIdentityDelegateManager) throws -> PendingGroupMember? {
        guard let obvContext = contactGroup.obvContext else {
            throw Self.makeError(message: "No obvContext")
        }
        let request: NSFetchRequest<PendingGroupMember> = PendingGroupMember.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        cryptoIdentityKey, cryptoIdentity,
                                        contactGroupKey, contactGroup)
        request.fetchLimit = 1
        let obj = try obvContext.fetch(request).first
        obj?.delegateManager = delegateManager
        return obj
    }
    
    
    static func delete(cryptoIdentity: ObvCryptoIdentity, contactGroup: ContactGroup, delegateManager: ObvIdentityDelegateManager) throws {
        guard let obvContext = contactGroup.obvContext else {
            throw Self.makeError(message: "No obvContext")
        }
        guard let obj = try get(cryptoIdentity: cryptoIdentity, contactGroup: contactGroup, delegateManager: delegateManager) else { return }
        obvContext.delete(obj)
    }
    
}


// MARK: - Sending notifications on change

extension PendingGroupMember {
    
    override func willSave() {
        super.willSave()
        
        if !isInserted {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }

    override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
        }
        
        guard !isDeleted else { return }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: PendingGroupMember.entityName)
            os_log("The delegate manager is not set (7)", log: log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: PendingGroupMember.entityName)
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        
        if changedKeys.contains(PendingGroupMember.declinedKey) {
            if let ownedGroup = self.contactGroup as? ContactGroupOwned {
                
                if self.declined {
                    
                    let NotificationType = ObvIdentityNotification.PendingGroupMemberDeclinedInvitationToOwnedGroup.self
                    let userInfo = [NotificationType.Key.groupUid: contactGroup.groupUid,
                                    NotificationType.Key.ownedIdentity: ownedGroup.ownedIdentity.cryptoIdentity,
                                    NotificationType.Key.contactIdentity: self.cryptoIdentity] as [String: Any]
                    notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    
                } else {
                    
                    let NotificationType = ObvIdentityNotification.DeclinedPendingGroupMemberWasUndeclinedForOwnedGroup.self
                    let userInfo = [NotificationType.Key.groupUid: contactGroup.groupUid,
                                    NotificationType.Key.ownedIdentity: ownedGroup.ownedIdentity.cryptoIdentity,
                                    NotificationType.Key.contactIdentity: self.cryptoIdentity] as [String: Any]
                    notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    
                }
                
            }
        }
        
        
    }
}


// MARK: - Encodable (for Backup purposes)

extension PendingGroupMember {
    
    var backupItem: PendingGroupMemberBackupItem {
        return PendingGroupMemberBackupItem(cryptoIdentity: cryptoIdentity,
                                            declined: declined,
                                            serializedIdentityCoreDetails: serializedIdentityCoreDetails)
    }

}


struct PendingGroupMemberBackupItem: Codable, Hashable {
    
    fileprivate let cryptoIdentity: ObvCryptoIdentity
    fileprivate let declined: Bool
    fileprivate let serializedIdentityCoreDetails: Data
    
    // Allows to prevent association failures in two items have identical variables
    private let transientUuid = UUID()

    private static let errorDomain = String(describing: PendingGroupMemberBackupItem.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(cryptoIdentity: ObvCryptoIdentity, declined: Bool, serializedIdentityCoreDetails: Data) {
        self.cryptoIdentity = cryptoIdentity
        self.declined = declined
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
    }

    enum CodingKeys: String, CodingKey {
        case cryptoIdentity = "contact_identity"
        case declined = "declined"
        case serializedIdentityCoreDetails = "serialized_details"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cryptoIdentity.getIdentity(), forKey: .cryptoIdentity)
        try container.encode(declined, forKey: .declined)
        guard let serializedIdentityCoreDetailsAsString = String(data: serializedIdentityCoreDetails, encoding: .utf8) else {
            throw PendingGroupMemberBackupItem.makeError(message: "Could not serialize serializedIdentityCoreDetails to a String")
        }
        try container.encode(serializedIdentityCoreDetailsAsString, forKey: .serializedIdentityCoreDetails)
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let identity = try values.decode(Data.self, forKey: .cryptoIdentity)
        guard let cryptoIdentity = ObvCryptoIdentity(from: identity) else {
            throw PendingGroupMemberBackupItem.makeError(message: "Could not parse identity")
        }
        self.cryptoIdentity = cryptoIdentity
        self.declined = try values.decode(Bool.self, forKey: .declined)
        let serializedIdentityCoreDetailsAsString = try values.decode(String.self, forKey: .serializedIdentityCoreDetails)
        guard let serializedIdentityCoreDetailsAsData = serializedIdentityCoreDetailsAsString.data(using: .utf8) else {
            throw PendingGroupMemberBackupItem.makeError(message: "Could not create Data from serializedIdentityCoreDetailsAsString")
        }
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetailsAsData
    }
    
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let pendingGroupMember = PendingGroupMember(backupItem: self, within: obvContext)
        try associations.associate(pendingGroupMember, to: self)
    }
    
    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing to do here
    }

}


// MARK: - For Snapshot purposes

extension PendingGroupMember {
    
    var syncSnapshot: PendingGroupMemberSyncSnapshotItem {
        .init(declined: declined,
              serializedIdentityCoreDetails: serializedIdentityCoreDetails)
    }

}


struct PendingGroupMemberSyncSnapshotItem: Codable, Hashable, Identifiable {
    
    fileprivate let declined: Bool
    fileprivate let serializedIdentityCoreDetails: Data
    
    let id = ObvSyncSnapshotNodeUtils.generateIdentifier()
    
    enum CodingKeys: String, CodingKey {
        case declined = "declined"
        case serializedIdentityCoreDetails = "serialized_details"
    }
    
    
    fileprivate init(declined: Bool, serializedIdentityCoreDetails: Data) {
        self.declined = declined
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
    }


    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(declined, forKey: .declined)
        guard let serializedIdentityCoreDetailsAsString = String(data: serializedIdentityCoreDetails, encoding: .utf8) else {
            throw ObvError.couldNotSerializeCoreDetails
        }
        try container.encode(serializedIdentityCoreDetailsAsString, forKey: .serializedIdentityCoreDetails)
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.declined = try values.decodeIfPresent(Bool.self, forKey: .declined) ?? false
        let serializedIdentityCoreDetailsAsString = try values.decode(String.self, forKey: .serializedIdentityCoreDetails)
        guard let serializedIdentityCoreDetailsAsData = serializedIdentityCoreDetailsAsString.data(using: .utf8) else {
            throw ObvError.couldNotDeserializeCoreDetails
        }
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetailsAsData
    }

    
    func restoreInstance(within obvContext: ObvContext, cryptoIdentity: ObvCryptoIdentity, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        let pendingGroupMember = PendingGroupMember(cryptoIdentity: cryptoIdentity, snapshotItem: self, within: obvContext)
        try associations.associate(pendingGroupMember, to: self)
    }
    
    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing to do here
    }

    
    enum ObvError: Error {
        case couldNotSerializeCoreDetails
        case couldNotDeserializeCoreDetails
    }
    
}
