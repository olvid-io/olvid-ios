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
import ObvTypes
import ObvEngine
import os.log
import OlvidUtils
import ObvCrypto

@objc(PersistedObvOwnedIdentity)
final class PersistedObvOwnedIdentity: NSManagedObject {
    
    static let entityName = "PersistedObvOwnedIdentity"
    static let identityKey = "identity"
    private static let isActiveKey = "isActive"

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedObvOwnedIdentity")

    private static let errorDomain = "PersistedObvOwnedIdentity"
    private func makeError(message: String) -> Error { NSError(domain: PersistedObvOwnedIdentity.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: - Properties

    @NSManaged private(set) var apiKeyExpirationDate: Date?
    @NSManaged private var capabilityWebrtcContinuousICE: Bool
    @NSManaged private var capabilityOneToOneContacts: Bool
    @NSManaged private var capabilityGroupsV2: Bool
    @NSManaged private var fullDisplayName: String
    @NSManaged private(set) var identity: Data
    @NSManaged private(set) var isActive: Bool
    @NSManaged private(set) var isKeycloakManaged: Bool
    @NSManaged private var rawAPIKeyStatus: Int
    @NSManaged private var rawAPIPermissions: Int
    @NSManaged private var serializedIdentityCoreDetails: Data
    @NSManaged private(set) var photoURL: URL?

    @NSManaged private(set) var contactGroups: Set<PersistedContactGroup>
    @NSManaged private(set) var contactGroupsV2: Set<PersistedGroupV2>
    @NSManaged private(set) var contacts: Set<PersistedObvContactIdentity>
    @NSManaged private(set) var invitations: Set<PersistedInvitation>
    
    // MARK: - Variables
    
    var identityCoreDetails: ObvIdentityCoreDetails {
        return try! ObvIdentityCoreDetails(serializedIdentityCoreDetails)
    }

    var cryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: identity)
    }

    private var changedKeys = Set<String>()

    private(set) var apiKeyStatus: APIKeyStatus {
        get { APIKeyStatus(rawValue: rawAPIKeyStatus) ?? .free }
        set { rawAPIKeyStatus = newValue.rawValue }
    }
    
    private(set) var apiPermissions: APIPermissions {
        get { APIPermissions(rawValue: rawAPIPermissions) }
        set { rawAPIPermissions = newValue.rawValue }
    }
    
    // MARK: - Initializer
    
    convenience init?(ownedIdentity: ObvOwnedIdentity, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedObvOwnedIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        do { self.serializedIdentityCoreDetails = try ownedIdentity.currentIdentityDetails.coreDetails.jsonEncode() } catch { return nil }
        self.fullDisplayName = ownedIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
        self.identity = ownedIdentity.cryptoId.getIdentity()
        self.isActive = true
        self.capabilityWebrtcContinuousICE = false
        self.isKeycloakManaged = ownedIdentity.isKeycloakManaged
        self.apiKeyExpirationDate = nil
        self.apiKeyStatus = APIKeyStatus.free
        self.apiPermissions = APIPermissions()
        self.contacts = Set<PersistedObvContactIdentity>()
        self.invitations = Set<PersistedInvitation>()
        self.photoURL = ownedIdentity.currentIdentityDetails.photoURL
    }

    
    func update(with ownedIdentity: ObvOwnedIdentity) throws {
        guard self.identity == ownedIdentity.cryptoId.getIdentity() else {
            throw makeError(message: "Trying to update an owned identity with the data of another owned identity")
        }
        self.serializedIdentityCoreDetails = try ownedIdentity.currentIdentityDetails.coreDetails.jsonEncode()
        self.fullDisplayName = ownedIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
        self.isActive = ownedIdentity.isActive
        self.isKeycloakManaged = ownedIdentity.isKeycloakManaged
        self.photoURL = ownedIdentity.currentIdentityDetails.photoURL
    }

    
    func updatePhotoURL(with url: URL?) {
        self.photoURL = url
    }

    func deactivate() {
        self.isActive = false
    }
    
    func activate() {
        self.isActive = true
    }
}


// MARK: - Capabilities

extension PersistedObvOwnedIdentity {

    func setContactCapabilities(to newCapabilities: Set<ObvCapability>) {
        for capability in ObvCapability.allCases {
            switch capability {
            case .webrtcContinuousICE:
                self.capabilityWebrtcContinuousICE = newCapabilities.contains(capability)
            case .oneToOneContacts:
                self.capabilityOneToOneContacts = newCapabilities.contains(capability)
            case .groupsV2:
                self.capabilityGroupsV2 = newCapabilities.contains(capability)
            }
        }
    }
    
    
    var allCapabilitites: Set<ObvCapability> {
        var capabilitites = Set<ObvCapability>()
        for capability in ObvCapability.allCases {
            switch capability {
            case .webrtcContinuousICE:
                if self.capabilityWebrtcContinuousICE {
                    capabilitites.insert(capability)
                }
            case .oneToOneContacts:
                if self.capabilityOneToOneContacts {
                    capabilitites.insert(capability)
                }
            case .groupsV2:
                if self.capabilityGroupsV2 {
                    capabilitites.insert(capability)
                }
            }
        }
        return capabilitites
    }
    
    
    func supportsCapability(_ capability: ObvCapability) -> Bool {
        allCapabilitites.contains(capability)
    }

}


// MARK: - Utils

extension PersistedObvOwnedIdentity {
    
    func set(apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?) {
        self.apiKeyStatus = apiKeyStatus
        self.apiPermissions = apiPermissions
        self.apiKeyExpirationDate = apiKeyExpirationDate
    }
    
}


// MARK: - Convenience DB getters

extension PersistedObvOwnedIdentity {
    
    private struct Predicate {
        static func persistedObvOwnedIdentity(withObjectID typedObjectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>) -> NSPredicate {
            NSPredicate(format: "SELF == %@", typedObjectID.objectID)
        }
    }

    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedObvOwnedIdentity> {
        return NSFetchRequest<PersistedObvOwnedIdentity>(entityName: self.entityName)
    }

    static func get(cryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@",
                                        self.identityKey, cryptoId.getIdentity() as NSData)
        return try context.fetch(request).first
    }

    static func get(identity: Data, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@",
                                        self.identityKey, identity as NSData)
        return try context.fetch(request).first
    }

    static func get(persisted obvOwnedIdentity: ObvOwnedIdentity, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@",
                                        self.identityKey, obvOwnedIdentity.cryptoId.getIdentity() as NSData)
        return try context.fetch(request).first
    }
    
    static func getAll(within context: NSManagedObjectContext) throws -> [PersistedObvOwnedIdentity] {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        return try context.fetch(request)
    }
    
    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        return try context.existingObject(with: objectID) as? PersistedObvOwnedIdentity
    }

    
    static func get(objectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.persistedObvOwnedIdentity(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}


// MARK: - Thread safe structure

extension PersistedObvOwnedIdentity {
    
    struct Structure: Hashable, Equatable {
        
        let typedObjectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>
        let cryptoId: ObvCryptoId
        let fullDisplayName: String
        let identityCoreDetails: ObvIdentityCoreDetails
        let photoURL: URL?
        
        private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedObvOwnedIdentity.Structure")
        
        // Hashable and equatable
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(typedObjectID)
        }
        
        static func == (lhs: Structure, rhs: Structure) -> Bool {
            lhs.typedObjectID == rhs.typedObjectID
        }

    }
    
    func toStruct() throws -> Structure {
        return Structure(typedObjectID: self.typedObjectID,
                         cryptoId: self.cryptoId,
                         fullDisplayName: self.fullDisplayName,
                         identityCoreDetails: self.identityCoreDetails,
                         photoURL: self.photoURL)
    }
    
}


// MARK: - Sending notifications on change

extension PersistedObvOwnedIdentity {
    
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

        if isInserted {
            let notification = ObvMessengerCoreDataNotification.newPersistedObvOwnedIdentity(ownedCryptoId: self.cryptoId)
            notification.postOnDispatchQueue()
        }
        
        if changedKeys.contains(PersistedObvOwnedIdentity.isActiveKey) {
            if self.isActive {
                let notification = ObvMessengerCoreDataNotification.ownedIdentityWasReactivated(ownedIdentityObjectID: self.objectID)
                notification.postOnDispatchQueue()
            } else {
                let notification = ObvMessengerCoreDataNotification.ownedIdentityWasDeactivated(ownedIdentityObjectID: self.objectID)
                notification.postOnDispatchQueue()
            }
        }
    }
    
}
