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
import ObvMetaManager
import ObvTypes
import OlvidUtils


@objc(PendingGroupMember)
final class PendingGroupMember: NSManagedObject {
        
    private static let entityName = "PendingGroupMember"
    private static let errorDomain = String(describing: PendingGroupMember.self)
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    static weak var delegateManager: ObvIdentityDelegateManager?
    
    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: PendingGroupMember.logSubsystem, category: "PendingGroupMember") }()

    // MARK: Attributes
    
    @NSManaged private(set) var declined: Bool
    @NSManaged private var rawCryptoIdentity: Data? // Non-optional in the model
    @NSManaged private var serializedIdentityCoreDetails: Data
    
    // MARK: Relationships
    
    @NSManaged private(set) var contactGroup: ContactGroup
    
    // MARK: Other variables
    
    var cryptoIdentity: ObvCryptoIdentity {
        get throws(ObvError) {
            guard let rawCryptoIdentity else { assertionFailure(); throw .unexpectedNilValue }
            guard let cryptoIdentity = ObvCryptoIdentity(from: rawCryptoIdentity) else { assertionFailure(); throw .couldNotParseValue }
            return cryptoIdentity
        }
    }
    
    private var changedKeys = Set<String>()
    
    var identityCoreDetails: ObvIdentityCoreDetails {
        let data = kvoSafePrimitiveValue(forKey: Predicate.Key.serializedIdentityCoreDetails.rawValue) as! Data
        return try! ObvIdentityCoreDetails(data)
    }
        
    // MARK: - Initializer
    
    convenience init(contactGroup: ContactGroup, cryptoIdentityWithCoreDetails: CryptoIdentityWithCoreDetails) throws {
        guard let context = contactGroup.managedObjectContext else {
            throw ObvIdentityManagerError.contextIsNil
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: PendingGroupMember.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.rawCryptoIdentity = cryptoIdentityWithCoreDetails.cryptoIdentity.getIdentity()
        self.declined = false
        self.serializedIdentityCoreDetails = try cryptoIdentityWithCoreDetails.coreDetails.jsonEncode()
        self.contactGroup = contactGroup
    }

    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: PendingGroupMemberBackupItem, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PendingGroupMember.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.rawCryptoIdentity = backupItem.cryptoIdentity.getIdentity()
        self.declined = backupItem.declined
        self.serializedIdentityCoreDetails = backupItem.serializedIdentityCoreDetails
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(cryptoIdentity: ObvCryptoIdentity, snapshotItem: PendingGroupMemberSyncSnapshotItem, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PendingGroupMember.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.rawCryptoIdentity = cryptoIdentity.getIdentity()
        self.declined = snapshotItem.declined
        self.serializedIdentityCoreDetails = snapshotItem.serializedIdentityCoreDetails
    }

    enum ObvError: Error {
        case unexpectedNilValue
        case couldNotParseValue
    }
    
}


// MARK: - Convenience methods

extension PendingGroupMember {
    
    func markAsDeclined() {
        if !self.declined {
            self.declined = true
        }
    }
    
    func unmarkAsDeclined() {
        if self.declined {
            self.declined = false
        }
    }

}


// MARK: - Convenience DB getters

extension PendingGroupMember {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case declined = "declined"
            case rawCryptoIdentity = "rawCryptoIdentity"
            case serializedIdentityCoreDetails = "serializedIdentityCoreDetails"
            // Relationships
            case contactGroup = "contactGroup"
        }
        static func withObvCryptoIdentity(_ cryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawCryptoIdentity, EqualToData: cryptoIdentity.getIdentity())
        }
        static func withContactGroup(_ contactGroup: ContactGroup) -> NSPredicate {
            NSPredicate(Key.contactGroup, equalTo: contactGroup)
        }
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PendingGroupMember> {
        return NSFetchRequest<PendingGroupMember>(entityName: entityName)
    }

    
    static func get(cryptoIdentity: ObvCryptoIdentity, contactGroup: ContactGroup) throws -> PendingGroupMember? {
        guard let context = contactGroup.managedObjectContext else {
            throw Self.makeError(message: "No context")
        }
        let request: NSFetchRequest<PendingGroupMember> = PendingGroupMember.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withObvCryptoIdentity(cryptoIdentity),
            Predicate.withContactGroup(contactGroup),
        ])
        request.fetchLimit = 1
        let obj = try context.fetch(request).first
        return obj
    }
    
    
    static func delete(cryptoIdentity: ObvCryptoIdentity, contactGroup: ContactGroup) throws {
        guard let context = contactGroup.managedObjectContext else {
            throw Self.makeError(message: "No context")
        }
        guard let obj = try get(cryptoIdentity: cryptoIdentity, contactGroup: contactGroup) else { return }
        context.delete(obj)
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
        
        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is not set (7)")
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            Self.logger.fault("The notification delegate is not set")
            return
        }
        
        
        if changedKeys.contains(Predicate.Key.declined.rawValue) {
            if let ownedGroup = self.contactGroup as? ContactGroupOwned {
                
                if self.declined {
                    
                    do {
                        let NotificationType = ObvIdentityNotification.PendingGroupMemberDeclinedInvitationToOwnedGroup.self
                        let userInfo = [NotificationType.Key.groupUid: try contactGroup.groupUid,
                                        NotificationType.Key.ownedIdentity: try ownedGroup.ownedIdentity.cryptoIdentity,
                                        NotificationType.Key.contactIdentity: try self.cryptoIdentity] as [String: Any]
                        notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    } catch {
                        assertionFailure()
                    }
                    
                } else {
                    
                    do {
                        let NotificationType = ObvIdentityNotification.DeclinedPendingGroupMemberWasUndeclinedForOwnedGroup.self
                        let userInfo = [NotificationType.Key.groupUid: try contactGroup.groupUid,
                                        NotificationType.Key.ownedIdentity: try ownedGroup.ownedIdentity.cryptoIdentity,
                                        NotificationType.Key.contactIdentity: try self.cryptoIdentity] as [String: Any]
                        notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
                    } catch {
                        assertionFailure()
                    }

                }
                
            }
        }
        
        
    }
}


// MARK: - Encodable (for Backup purposes)

extension PendingGroupMember {
    
    var backupItem: PendingGroupMemberBackupItem {
        get throws {
            return PendingGroupMemberBackupItem(cryptoIdentity: try cryptoIdentity,
                                                declined: declined,
                                                serializedIdentityCoreDetails: serializedIdentityCoreDetails)
        }
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
    
    func restoreInstance(within context: NSManagedObjectContext, associations: inout BackupItemObjectAssociations) throws {
        let pendingGroupMember = PendingGroupMember(backupItem: self, within: context)
        try associations.associate(pendingGroupMember, to: self)
    }
    
    func restoreRelationships(associations: BackupItemObjectAssociations, within context: NSManagedObjectContext) throws {
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

    
    func restoreInstance(within context: NSManagedObjectContext, cryptoIdentity: ObvCryptoIdentity, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        let pendingGroupMember = PendingGroupMember(cryptoIdentity: cryptoIdentity, snapshotItem: self, within: context)
        try associations.associate(pendingGroupMember, to: self)
    }
    
    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within context: NSManagedObjectContext) throws {
        // Nothing to do here
    }

    
    enum ObvError: Error {
        case couldNotSerializeCoreDetails
        case couldNotDeserializeCoreDetails
    }
    
}
