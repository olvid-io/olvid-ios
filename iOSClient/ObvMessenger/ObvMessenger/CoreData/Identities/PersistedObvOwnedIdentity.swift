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
import ObvUI

@objc(PersistedObvOwnedIdentity)
final class PersistedObvOwnedIdentity: NSManagedObject, Identifiable, ObvErrorMaker, ObvIdentifiableManagedObject {
    
    static let entityName = "PersistedObvOwnedIdentity"
    static let errorDomain = "PersistedObvOwnedIdentity"
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedObvOwnedIdentity")

    // MARK: Properties

    @NSManaged private(set) var apiKeyExpirationDate: Date?
    @NSManaged private var capabilityGroupsV2: Bool
    @NSManaged private var capabilityOneToOneContacts: Bool
    @NSManaged private var capabilityWebrtcContinuousICE: Bool
    @NSManaged private(set) var customDisplayName: String?
    @NSManaged private var fullDisplayName: String
    @NSManaged private(set) var identity: Data
    @NSManaged private(set) var isActive: Bool
    @NSManaged private(set) var isKeycloakManaged: Bool
    @NSManaged private(set) var numberOfNewMessages: Int
    @NSManaged private var permanentUUID: UUID
    @NSManaged private(set) var photoURL: URL?
    @NSManaged private var rawAPIKeyStatus: Int
    @NSManaged private var rawAPIPermissions: Int
    @NSManaged private var serializedIdentityCoreDetails: Data
    @NSManaged private var hiddenProfileHash: Data?
    @NSManaged private var hiddenProfileSalt: Data?
    
    // MARK: Relationships

    @NSManaged private(set) var contactGroups: Set<PersistedContactGroup>
    @NSManaged private(set) var contactGroupsV2: Set<PersistedGroupV2>
    @NSManaged private(set) var contacts: Set<PersistedObvContactIdentity>
    @NSManaged private(set) var invitations: Set<PersistedInvitation>
    
    // MARK: Variables
    
    var isHidden: Bool {
        hiddenProfileHash != nil && hiddenProfileSalt != nil
    }
    
    var identityCoreDetails: ObvIdentityCoreDetails {
        return try! ObvIdentityCoreDetails(serializedIdentityCoreDetails)
    }

    var cryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: identity)
    }

    private var changedKeys = Set<String>()

    private(set) var apiKeyStatus: APIKeyStatus {
        get {
            let localStatus = APIKeyStatus(rawValue: rawAPIKeyStatus) ?? .free
            switch localStatus {
            case .valid, .freeTrial, .anotherOwnedIdentityHasValidAPIKey:
                return localStatus
            case .unknown, .licensesExhausted, .expired, .free, .awaitingPaymentGracePeriod, .awaitingPaymentOnHold, .freeTrialExpired:
                if let context = managedObjectContext, (localStatus == .free || localStatus == .unknown) {
                    let anotherProfileHasValiAPIKey = (try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: context).first(where: { $0.rawAPIKeyStatus == APIKeyStatus.valid.rawValue })) != nil
                    if anotherProfileHasValiAPIKey {
                        return .anotherOwnedIdentityHasValidAPIKey
                    }
                }
                return localStatus
            }
        }
        set {
            rawAPIKeyStatus = newValue.rawValue
        }
    }
    
    private(set) var apiPermissions: APIPermissions {
        get { APIPermissions(rawValue: rawAPIPermissions) }
        set { rawAPIPermissions = newValue.rawValue }
    }
    
    var objectPermanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity> {
        ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>(uuid: self.permanentUUID)
    }
    
    var circledInitialsConfiguration: CircledInitialsConfiguration {
        .contact(initial: customDisplayName ?? fullDisplayName,
                 photoURL: photoURL,
                 showGreenShield: isKeycloakManaged,
                 showRedShield: false,
                 colors: cryptoId.colors)
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
        self.customDisplayName = nil
        self.numberOfNewMessages = 0
        self.permanentUUID = UUID()
        self.apiKeyExpirationDate = nil
        self.apiKeyStatus = APIKeyStatus.free
        self.apiPermissions = APIPermissions()
        self.contacts = Set<PersistedObvContactIdentity>()
        self.invitations = Set<PersistedInvitation>()
        self.photoURL = ownedIdentity.currentIdentityDetails.photoURL
        self.hiddenProfileHash = nil
        self.hiddenProfileSalt = nil
    }

    
    func update(with ownedIdentity: ObvOwnedIdentity) throws {
        guard self.identity == ownedIdentity.cryptoId.getIdentity() else {
            throw Self.makeError(message: "Trying to update an owned identity with the data of another owned identity")
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
    
    func delete() throws {
        guard let context = managedObjectContext else {
            throw Self.makeError(message: "Could not delete owned identity as we could not find any context")
        }
        context.delete(self)
    }
        
    func setOwnedCustomDisplayName(to newCustomDisplayName: String?) {
        guard self.customDisplayName != newCustomDisplayName else { return }
        self.customDisplayName = newCustomDisplayName?.trimmingWhitespacesAndNewlinesAndMapToNilIfZeroLength()
    }
    
    // MARK: - Helpers for backups

    var hiddenProfileHashAndSaltForBackup: (hash: Data, salt: Data)? {
        guard let hiddenProfileHash, let hiddenProfileSalt else { return nil }
        return (hiddenProfileHash, hiddenProfileSalt)
    }
     
    func setHiddenProfileHashAndSaltDuringBackupRestore(hash: Data, salt: Data) {
        self.hiddenProfileHash = hash
        self.hiddenProfileSalt = salt
    }

    
    var isBeingRestoredFromBackup = false
    
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


// MARK: - Hide/Unhide profile

extension PersistedObvOwnedIdentity {
    
    func hideProfileWithPassword(_ password: String) throws {
        guard password.count >= ObvMessengerConstants.minimumLengthOfPasswordForHiddenProfiles else {
            throw Self.makeError(message: "Password is too short to hide profile")
        }
        guard try !anotherPasswordIfAPrefixOfThisPassword(password: password) else {
            throw Self.makeError(message: "Another password is the prefix of this password")
        }
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        let newHiddenProfileSalt = prng.genBytes(count: ObvMessengerConstants.seedLengthForHiddenProfiles)
        let newHiddenProfileHash = try Self.computehiddenProfileHash(password, salt: newHiddenProfileSalt)
        self.hiddenProfileSalt = newHiddenProfileSalt
        self.hiddenProfileHash = newHiddenProfileHash
    }
    
    
    func unhideProfile() {
        self.hiddenProfileHash = nil
        self.hiddenProfileSalt = nil
    }
    
    
    private func anotherPasswordIfAPrefixOfThisPassword(password: String) throws -> Bool {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let allHiddenOwnedIdentities = try Self.getAllHiddenOwnedIdentities(within: context)
        for hiddenOwnedIdentity in allHiddenOwnedIdentities {
            guard let hiddenProfileSalt = hiddenOwnedIdentity.hiddenProfileSalt, let hiddenProfileHash = hiddenOwnedIdentity.hiddenProfileHash else { assertionFailure(); continue }
            for length in ObvMessengerConstants.minimumLengthOfPasswordForHiddenProfiles...password.count {
                let prefix = String(password.prefix(length))
                let hashObtained = try Self.computehiddenProfileHash(prefix, salt: hiddenProfileSalt)
                if hashObtained == hiddenProfileHash {
                    return true
                }
            }
        }
        return false
    }
    
    
    private static func computehiddenProfileHash(_ password: String, salt: Data) throws -> Data {
        return try PBKDF.pbkdf2sha1(password: password, salt: salt, rounds: 1000, derivedKeyLength: 20)
    }
    
    
    private func isUnlockedUsingPassword(_ password: String) throws -> Bool {
        guard let hiddenProfileHash, let hiddenProfileSalt else { return false }
        let computedHash = try Self.computehiddenProfileHash(password, salt: hiddenProfileSalt)
        return hiddenProfileHash == computedHash
    }
    
    
    static func passwordCanUnlockSomeHiddenOwnedIdentity(password: String, within context: NSManagedObjectContext) throws -> Bool {
        guard password.count >= ObvMessengerConstants.minimumLengthOfPasswordForHiddenProfiles else { return false }
        let hiddenOwnedIdentities = try Self.getAllHiddenOwnedIdentities(within: context)
        for hiddenOwnedIdentity in hiddenOwnedIdentities {
            if try hiddenOwnedIdentity.isUnlockedUsingPassword(password) {
                return true
            }
        }
        return false
    }
    
    
    var isLastUnhiddenOwnedIdentity: Bool {
        get throws {
            guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find owned identity") }
            if isHidden { return false }
            let unhiddenOwnedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: context)
            assert(unhiddenOwnedIdentities.contains(self))
            return unhiddenOwnedIdentities.count <= 1
        }
    }

}


// MARK: - Utils

extension PersistedObvOwnedIdentity {
    
    func set(apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?) {
        self.apiKeyStatus = apiKeyStatus
        self.apiPermissions = apiPermissions
        self.apiKeyExpirationDate = apiKeyExpirationDate
    }
    

    /// Refreshes the number of new messages of the owned identity. Called during bootstrap.
    func refreshNumberOfNewMessages() throws {
        guard self.managedObjectContext != nil else { assertionFailure(); throw Self.makeError(message: "Cannot find context") }
        let newNumberOfNewMessages = try PersistedDiscussion.countSumOfNewMessagesWithinDiscussionsForOwnedIdentity(self)
        if self.numberOfNewMessages != newNumberOfNewMessages {
            self.numberOfNewMessages = newNumberOfNewMessages
        }
    }
    

    /// Called exclusively by a persisted discussion of this owned identity, when it updates its own number of new messages.
    func incrementNumberOfNewMessages(by value: Int) {
        guard value != 0 else { return }
        self.numberOfNewMessages += value
        self.numberOfNewMessages = max(0, self.numberOfNewMessages)
    }
    
}


// MARK: - Convenience DB getters

extension PersistedObvOwnedIdentity {
    
    struct Predicate {
        enum Key: String {
            // Properties
            case apiKeyExpirationDate = "apiKeyExpirationDate"
            case capabilityGroupsV2 = "capabilityGroupsV2"
            case capabilityOneToOneContacts = "capabilityOneToOneContacts"
            case capabilityWebrtcContinuousICE = "capabilityWebrtcContinuousICE"
            case customDisplayName = "customDisplayName"
            case fullDisplayName = "fullDisplayName"
            case identity = "identity"
            case isActive = "isActive"
            case isKeycloakManaged = "isKeycloakManaged"
            case numberOfNewMessages = "numberOfNewMessages"
            case permanentUUID = "permanentUUID"
            case photoURL = "photoURL"
            case rawAPIKeyStatus = "rawAPIKeyStatus"
            case rawAPIPermissions = "rawAPIPermissions"
            case serializedIdentityCoreDetails = "serializedIdentityCoreDetails"
            case hiddenProfileHash = "hiddenProfileHash"
            case hiddenProfileSalt = "hiddenProfileSalt"
            // Relationships
            case contactGroups = "contactGroups"
            case contactGroupsV2 = "contactGroupsV2"
            case contacts = "contacts"
            case invitations = "invitations"
        }
        static func persistedObvOwnedIdentity(withObjectID typedObjectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>) -> NSPredicate {
            NSPredicate(withObjectID: typedObjectID.objectID)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.identity, EqualToData: ownedCryptoId.getIdentity())
        }
        static func excludingOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            NSCompoundPredicate(notPredicateWithSubpredicate: NSPredicate(Key.identity, EqualToData: ownedCryptoId.getIdentity()))
        }
        static func withOwnedIdentityIdentity(_ ownedIdentityIdentity: Data) -> NSPredicate {
            NSPredicate(Key.identity, EqualToData: ownedIdentityIdentity)
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>) -> NSPredicate {
            NSPredicate(Key.permanentUUID, EqualToUuid: permanentID.uuid)
        }
        static func isHidden(_ value: Bool) -> NSPredicate {
            let isHiddenPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.hiddenProfileHash),
                NSPredicate(withNonNilValueForKey: Key.hiddenProfileSalt),
            ])
            return value ? isHiddenPredicate : NSCompoundPredicate(notPredicateWithSubpredicate: isHiddenPredicate)
        }
    }

    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedObvOwnedIdentity> {
        return NSFetchRequest<PersistedObvOwnedIdentity>(entityName: self.entityName)
    }

    
    static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func get(cryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(cryptoId)
        return try context.fetch(request).first
    }

    
    static func getHiddenOwnedIdentity(password: String, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let allHiddenOwnedIdentities = try Self.getAllHiddenOwnedIdentities(within: context)
        return try allHiddenOwnedIdentities.first(where: { try $0.isUnlockedUsingPassword(password) })
    }
    
    static func get(identity: Data, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withOwnedIdentityIdentity(identity)
        return try context.fetch(request).first
    }

    
    static func get(persisted obvOwnedIdentity: ObvOwnedIdentity, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(obvOwnedIdentity.cryptoId)
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
    
    
    static func getAllNonHiddenOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedObvOwnedIdentity] {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.isHidden(false)
        request.sortDescriptors = [
            NSSortDescriptor(key: Predicate.Key.customDisplayName.rawValue, ascending: true),
            NSSortDescriptor(key: Predicate.Key.fullDisplayName.rawValue, ascending: true),
        ]
        return try context.fetch(request)
    }

    
    static func getAllHiddenOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedObvOwnedIdentity] {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.isHidden(true)
        return try context.fetch(request)
    }

    
    /// This method uses aggregate functions to return the sum of the number of new messages for owned identities but the one excluded
    static func countSumOfNewMessagesForUnhiddenOwnedIdentites(excludedOwnedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Int {
        // Create an expression description that will allow to aggregate the values of the numberOfNewMessages column
        let expressionDescription = NSExpressionDescription()
        expressionDescription.name = "sumOfNumberOfNewMessages"
        expressionDescription.expression = NSExpression(format: "@sum.\(Predicate.Key.numberOfNewMessages.rawValue)")
        expressionDescription.expressionResultType = .integer64AttributeType
        // Create a predicate that will restrict to the discussions of the owned identity
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.excludingOwnedCryptoId(excludedOwnedCryptoId),
            Predicate.isHidden(false),
        ])
        // Create the fetch request
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.predicate = predicate
        request.propertiesToFetch = [expressionDescription]
        request.includesPendingChanges = true
        guard let results = try context.fetch(request).first as? [String: Int] else { throw makeError(message: "Could cast fetched result") }
        guard let sumOfNumberOfNewMessages = results["sumOfNumberOfNewMessages"] else { throw makeError(message: "Could not get uploadedByteCount") }
        return sumOfNumberOfNewMessages
    }

}


// MARK: - Thread safe structure

extension PersistedObvOwnedIdentity {
    
    struct Structure {
        
        let objectPermanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>
        let cryptoId: ObvCryptoId
        let fullDisplayName: String
        let identityCoreDetails: ObvIdentityCoreDetails
        let photoURL: URL?
        let isHidden: Bool
        
        private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedObvOwnedIdentity.Structure")
        
    }
    
    func toStruct() throws -> Structure {
        return Structure(objectPermanentID: self.objectPermanentID,
                         cryptoId: self.cryptoId,
                         fullDisplayName: self.fullDisplayName,
                         identityCoreDetails: self.identityCoreDetails,
                         photoURL: self.photoURL,
                         isHidden: self.isHidden)
    }
    
}


// MARK: - Sending notifications on change

extension PersistedObvOwnedIdentity {
    
    override func willSave() {
        super.willSave()
        if !isInserted && isUpdated {
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
        
        if !isDeleted {
            
            if changedKeys.contains(Predicate.Key.isActive.rawValue) {
                if self.isActive {
                    let notification = ObvMessengerCoreDataNotification.ownedIdentityWasReactivated(ownedIdentityObjectID: self.objectID)
                    notification.postOnDispatchQueue()
                } else {
                    let notification = ObvMessengerCoreDataNotification.ownedIdentityWasDeactivated(ownedIdentityObjectID: self.objectID)
                    notification.postOnDispatchQueue()
                }
            }
            
            if changedKeys.contains(Predicate.Key.fullDisplayName.rawValue) ||
                changedKeys.contains(Predicate.Key.photoURL.rawValue) ||
                changedKeys.contains(Predicate.Key.customDisplayName.rawValue) ||
                changedKeys.contains(Predicate.Key.isKeycloakManaged.rawValue) {
                ObvMessengerCoreDataNotification.ownedCircledInitialsConfigurationDidChange(
                    ownedIdentityPermanentID: objectPermanentID,
                    ownedCryptoId: cryptoId,
                    newOwnedCircledInitialsConfiguration: circledInitialsConfiguration)
                .postOnDispatchQueue()
            }
            
            if !isBeingRestoredFromBackup && (changedKeys.contains(Predicate.Key.hiddenProfileSalt.rawValue) || changedKeys.contains(Predicate.Key.hiddenProfileHash.rawValue)) {
                ObvMessengerCoreDataNotification.ownedIdentityHiddenStatusChanged(ownedCryptoId: cryptoId, isHidden: isHidden)
                    .postOnDispatchQueue()
            }
            
            if changedKeys.contains(Predicate.Key.numberOfNewMessages.rawValue) {
                ObvMessengerCoreDataNotification.numberOfNewMessagesChangedForOwnedIdentity(ownedCryptoId: cryptoId, numberOfNewMessages: numberOfNewMessages)
                    .postOnDispatchQueue()
            }
            
        } else {
            
            ObvMessengerCoreDataNotification.persistedObvOwnedIdentityWasDeleted
                .postOnDispatchQueue()
            
        }

    }
    
}


// MARK: - OwnedIdentityPermanentID

typealias OwnedIdentityPermanentID = ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>
