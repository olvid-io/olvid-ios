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
import UI_CircledInitialsView_CircledInitialsConfiguration

@objc(PersistedObvOwnedIdentity)
public final class PersistedObvOwnedIdentity: NSManagedObject, Identifiable, ObvErrorMaker, ObvIdentifiableManagedObject {
    
    public static let entityName = "PersistedObvOwnedIdentity"
    public static let errorDomain = "PersistedObvOwnedIdentity"
    private let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedObvOwnedIdentity")

    // MARK: Properties

    @NSManaged public private(set) var apiKeyExpirationDate: Date?
    @NSManaged public private(set) var badgeCountForDiscussionsTab: Int // Does not take into account new messages from muted discussions (was numberOfNewMessages)
    @NSManaged public private(set) var badgeCountForInvitationsTab: Int
    @NSManaged private var capabilityGroupsV2: Bool
    @NSManaged private var capabilityOneToOneContacts: Bool
    @NSManaged private var capabilityWebrtcContinuousICE: Bool
    @NSManaged public private(set) var customDisplayName: String?
    @NSManaged public var fullDisplayName: String
    @NSManaged private(set) var identity: Data
    @NSManaged public private(set) var isActive: Bool
    @NSManaged public private(set) var isKeycloakManaged: Bool
    @NSManaged private var permanentUUID: UUID
    @NSManaged public private(set) var photoURL: URL?
    @NSManaged private var rawAPIKeyStatus: Int
    @NSManaged private var rawAPIPermissions: Int
    @NSManaged private var serializedIdentityCoreDetails: Data
    @NSManaged private var hiddenProfileHash: Data?
    @NSManaged private var hiddenProfileSalt: Data?
    
    // MARK: Relationships

    @NSManaged private(set) var contactGroups: Set<PersistedContactGroup>
    @NSManaged private(set) var contactGroupsV2: Set<PersistedGroupV2>
    @NSManaged public private(set) var contacts: Set<PersistedObvContactIdentity>
    @NSManaged private(set) var invitations: Set<PersistedInvitation>

    // MARK: Variables
    
    public var isHidden: Bool {
        hiddenProfileHash != nil && hiddenProfileSalt != nil
    }
    
    public var identityCoreDetails: ObvIdentityCoreDetails {
        return try! ObvIdentityCoreDetails(serializedIdentityCoreDetails)
    }

    public var cryptoId: ObvCryptoId {
        return try! ObvCryptoId(identity: identity)
    }

    var customOrFullDisplayName: String {
        customDisplayName ?? fullDisplayName
    }

    private var changedKeys = Set<String>()

    public private(set) var apiKeyStatus: APIKeyStatus {
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
    
    public private(set) var apiPermissions: APIPermissions {
        get { APIPermissions(rawValue: rawAPIPermissions) }
        set { rawAPIPermissions = newValue.rawValue }
    }
    
    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedObvOwnedIdentity> {
        ObvManagedObjectPermanentID<PersistedObvOwnedIdentity>(uuid: self.permanentUUID)
    }
    
    
    public var circledInitialsConfiguration: CircledInitialsConfiguration {
        .contact(initial: customDisplayName ?? fullDisplayName,
                 photoURL: photoURL,
                 showGreenShield: isKeycloakManaged,
                 showRedShield: false,
                 cryptoId: cryptoId,
                 tintAdjustementMode: .normal)
    }

    public var totalBadgeCount: Int {
        return badgeCountForDiscussionsTab + badgeCountForInvitationsTab
    }
    
    // MARK: - Initializer
    
    public convenience init?(ownedIdentity: ObvOwnedIdentity, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedObvOwnedIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        do { self.serializedIdentityCoreDetails = try ownedIdentity.currentIdentityDetails.coreDetails.jsonEncode() } catch { return nil }
        self.fullDisplayName = ownedIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
        self.identity = ownedIdentity.cryptoId.getIdentity()
        self.isActive = true
        self.capabilityWebrtcContinuousICE = false
        self.isKeycloakManaged = ownedIdentity.isKeycloakManaged
        self.customDisplayName = nil
        self.badgeCountForDiscussionsTab = 0
        self.badgeCountForInvitationsTab = 0
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

    
    public func update(with ownedIdentity: ObvOwnedIdentity) throws {
        guard self.identity == ownedIdentity.cryptoId.getIdentity() else {
            throw Self.makeError(message: "Trying to update an owned identity with the data of another owned identity")
        }
        self.serializedIdentityCoreDetails = try ownedIdentity.currentIdentityDetails.coreDetails.jsonEncode()
        self.fullDisplayName = ownedIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
        self.isActive = ownedIdentity.isActive
        self.isKeycloakManaged = ownedIdentity.isKeycloakManaged
        self.photoURL = ownedIdentity.currentIdentityDetails.photoURL
    }

    
    public func updatePhotoURL(with url: URL?) {
        self.photoURL = url
    }

    public func deactivate() {
        self.isActive = false
    }
    
    public func activate() {
        self.isActive = true
    }
    
    public func delete() throws {
        guard let context = managedObjectContext else {
            throw Self.makeError(message: "Could not delete owned identity as we could not find any context")
        }
        context.delete(self)
    }
        
    public func setOwnedCustomDisplayName(to newCustomDisplayName: String?) {
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

    public func setContactCapabilities(to newCapabilities: Set<ObvCapability>) {
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
    
    
    public func supportsCapability(_ capability: ObvCapability) -> Bool {
        allCapabilitites.contains(capability)
    }

}


// MARK: - Hide/Unhide profile

extension PersistedObvOwnedIdentity {
    
    public func hideProfileWithPassword(_ password: String) throws {
        guard password.count >= ObvUICoreDataConstants.minimumLengthOfPasswordForHiddenProfiles else {
            throw Self.makeError(message: "Password is too short to hide profile")
        }
        guard try !anotherPasswordIfAPrefixOfThisPassword(password: password) else {
            throw Self.makeError(message: "Another password is the prefix of this password")
        }
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        let newHiddenProfileSalt = prng.genBytes(count: ObvUICoreDataConstants.seedLengthForHiddenProfiles)
        let newHiddenProfileHash = try Self.computehiddenProfileHash(password, salt: newHiddenProfileSalt)
        self.hiddenProfileSalt = newHiddenProfileSalt
        self.hiddenProfileHash = newHiddenProfileHash
    }
    
    
    public func unhideProfile() {
        self.hiddenProfileHash = nil
        self.hiddenProfileSalt = nil
    }
    
    
    private func anotherPasswordIfAPrefixOfThisPassword(password: String) throws -> Bool {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let allHiddenOwnedIdentities = try Self.getAllHiddenOwnedIdentities(within: context)
        for hiddenOwnedIdentity in allHiddenOwnedIdentities {
            guard let hiddenProfileSalt = hiddenOwnedIdentity.hiddenProfileSalt, let hiddenProfileHash = hiddenOwnedIdentity.hiddenProfileHash else { assertionFailure(); continue }
            for length in ObvUICoreDataConstants.minimumLengthOfPasswordForHiddenProfiles...password.count {
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
    
    
    public static func passwordCanUnlockSomeHiddenOwnedIdentity(password: String, within context: NSManagedObjectContext) throws -> Bool {
        guard password.count >= ObvUICoreDataConstants.minimumLengthOfPasswordForHiddenProfiles else { return false }
        let hiddenOwnedIdentities = try Self.getAllHiddenOwnedIdentities(within: context)
        for hiddenOwnedIdentity in hiddenOwnedIdentities {
            if try hiddenOwnedIdentity.isUnlockedUsingPassword(password) {
                return true
            }
        }
        return false
    }
    
    
    public var isLastUnhiddenOwnedIdentity: Bool {
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
    
    public func set(apiKeyStatus: APIKeyStatus, apiPermissions: APIPermissions, apiKeyExpirationDate: Date?) {
        self.apiKeyStatus = apiKeyStatus
        self.apiPermissions = apiPermissions
        self.apiKeyExpirationDate = apiKeyExpirationDate
    }
        
}


// MARK: - Handling badge counts for tabs

extension PersistedObvOwnedIdentity {
    
    /// Refreshes the badge count for the discussions tab. Called during bootstrap.
    /// Note that this **cannot** be called in a context including pending changes since those will **not** be taken into account (this is a limitation of Core Data, see https://developer.apple.com/documentation/coredata/nsfetchrequest/1506724-includespendingchanges).
    public func refreshBadgeCountForDiscussionsTab() throws {
        guard self.managedObjectContext != nil else { assertionFailure(); throw Self.makeError(message: "Cannot find context") }
        let newNumberOfNewMessages = try PersistedDiscussion.countSumOfNewMessagesWithinUnmutedDiscussionsForOwnedIdentity(self)
        let numberOfMutedDiscussionsMentioningOwnedIdentity = try PersistedDiscussion.countNumberOfMutedDiscussionsWithNewMessageMentioningOwnedIdentity(self)
        let newBadgeCountForDiscussionsTab = newNumberOfNewMessages + numberOfMutedDiscussionsMentioningOwnedIdentity
        if self.badgeCountForDiscussionsTab != newBadgeCountForDiscussionsTab {
            self.badgeCountForDiscussionsTab = newBadgeCountForDiscussionsTab
        }
    }
    
    
    /// Refreshes the badge count for the discussions tab. Called during bootstrap and each time a significant change occurs at the ``PersistedInvitation`` level.
    /// To the contrary of ``PersistedObvOwnedIdentity.refreshBadgeCountForDiscussionsTab()``, this method can be called within the context that updated a ``PersistedInvitation`` since the count method we used does take pending changes into account.
    public func refreshBadgeCountForInvitationsTab() throws {
        guard self.managedObjectContext != nil else { assertionFailure(); throw Self.makeError(message: "Cannot find context") }
        let newBadgeCountForInvitationsTab = try PersistedInvitation.computeBadgeCountForInvitationsTab(of: self)
        if self.badgeCountForInvitationsTab != newBadgeCountForInvitationsTab {
            self.badgeCountForInvitationsTab = newBadgeCountForInvitationsTab
        }
    }
    

    /// Called exclusively by a persisted discussion of this owned identity, when it updates its own number of new messages, or when it updates the Boolean indicating that a new message mentions an this owned identity.
    /// This method is required as ``PersistedObvOwnedIdentity.refreshBadgeCountForDiscussionsTab()`` cannot be called atomically with changes made at the ``PersistedDiscussion`` level.
    func incrementBadgeCountForDiscussionsTab(by value: Int) {
        guard value != 0 else { return }
        self.badgeCountForDiscussionsTab = max(0, self.badgeCountForDiscussionsTab + value)
    }
    
}


// MARK: - Convenience DB getters

extension PersistedObvOwnedIdentity {
    
    struct Predicate {
        enum Key: String {
            // Properties
            case apiKeyExpirationDate = "apiKeyExpirationDate"
            case badgeCountForDiscussionsTab = "badgeCountForDiscussionsTab"
            case badgeCountForInvitationsTab = "badgeCountForInvitationsTab"
            case capabilityGroupsV2 = "capabilityGroupsV2"
            case capabilityOneToOneContacts = "capabilityOneToOneContacts"
            case capabilityWebrtcContinuousICE = "capabilityWebrtcContinuousICE"
            case customDisplayName = "customDisplayName"
            case fullDisplayName = "fullDisplayName"
            case identity = "identity"
            case isActive = "isActive"
            case isKeycloakManaged = "isKeycloakManaged"
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

    
    public static func get(cryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(cryptoId)
        return try context.fetch(request).first
    }

    
    public static func getHiddenOwnedIdentity(password: String, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let allHiddenOwnedIdentities = try Self.getAllHiddenOwnedIdentities(within: context)
        return try allHiddenOwnedIdentities.first(where: { try $0.isUnlockedUsingPassword(password) })
    }
    
    static func get(identity: Data, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withOwnedIdentityIdentity(identity)
        return try context.fetch(request).first
    }

    
    public static func get(persisted obvOwnedIdentity: ObvOwnedIdentity, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoId(obvOwnedIdentity.cryptoId)
        return try context.fetch(request).first
    }

    
    public static func getAll(within context: NSManagedObjectContext) throws -> [PersistedObvOwnedIdentity] {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        return try context.fetch(request)
    }
    
    
    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        return try context.existingObject(with: objectID) as? PersistedObvOwnedIdentity
    }

    
    public static func get(objectID: TypeSafeManagedObjectID<PersistedObvOwnedIdentity>, within context: NSManagedObjectContext) throws -> PersistedObvOwnedIdentity? {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.persistedObvOwnedIdentity(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    public static func getAllNonHiddenOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedObvOwnedIdentity] {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.isHidden(false)
        request.sortDescriptors = [
            NSSortDescriptor(key: Predicate.Key.customDisplayName.rawValue, ascending: true),
            NSSortDescriptor(key: Predicate.Key.fullDisplayName.rawValue, ascending: true),
        ]
        return try context.fetch(request)
    }

    
    public static func getAllHiddenOwnedIdentities(within context: NSManagedObjectContext) throws -> [PersistedObvOwnedIdentity] {
        let request: NSFetchRequest<PersistedObvOwnedIdentity> = PersistedObvOwnedIdentity.fetchRequest()
        request.predicate = Predicate.isHidden(true)
        return try context.fetch(request)
    }


    /// Internal type used in ``static PersistedObvOwnedIdentity.countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId:badgesToSum:within:)``.
    private enum BadgeTypeForSum {
        case discussions
        case invitations
    }
    
    /// This method uses aggregate functions to return the sum of the number of new messages or new invitations for owned identities but the one excluded.
    ///
    /// This is used when computing the app badge (in which case, `excludedOwnedCryptoId` is nil) and when evaluating if a red dot should be shown in the top left owned profile picture view (in which case, we want to exclude that owned identity).
    private static func countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId: ObvCryptoId?, badgesToSum: BadgeTypeForSum, within context: NSManagedObjectContext) throws -> Int {
        
        // Create an expression description that will allow to aggregate the values of the numberOfNewMessages column
        let expressionDescription = NSExpressionDescription()
        expressionDescription.name = "sumOfBadgeCounts"
        
        switch badgesToSum {
        case .discussions:
            expressionDescription.expression = NSExpression(format: "@sum.\(Predicate.Key.badgeCountForDiscussionsTab.rawValue)")
        case .invitations:
            expressionDescription.expression = NSExpression(format: "@sum.\(Predicate.Key.badgeCountForInvitationsTab.rawValue)")
        }
        
        expressionDescription.expressionResultType = .integer64AttributeType
        
        // Create a predicate that will restrict to the discussions of the owned identity
        let excludingOwnedCryptoIdPredicate: NSPredicate
        if let excludedOwnedCryptoId {
            excludingOwnedCryptoIdPredicate = Predicate.excludingOwnedCryptoId(excludedOwnedCryptoId)
        } else {
            excludingOwnedCryptoIdPredicate = NSPredicate(value: true)
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            excludingOwnedCryptoIdPredicate,
            Predicate.isHidden(false),
        ])
        
        // Create the fetch request
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.predicate = predicate
        request.propertiesToFetch = [expressionDescription]
        request.includesPendingChanges = true
        guard let results = try context.fetch(request).first as? [String: Int] else { throw makeError(message: "Could cast fetched result") }
        guard let sumOfNumberOfNewMessages = results["sumOfBadgeCounts"] else { throw makeError(message: "Could not get sumOfBadgeCounts") }
        return sumOfNumberOfNewMessages
    }
    
    
    public static func computeAppBadgeValue(within context: NSManagedObjectContext) throws -> Int {
        let sumOfBadgeCountsOfDiscussionsTabs = try countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId: nil, badgesToSum: .discussions, within: context)
        let sumOfBadgeCountsOfInvitationsTabs = try countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId: nil, badgesToSum: .invitations, within: context)
        return sumOfBadgeCountsOfDiscussionsTabs + sumOfBadgeCountsOfInvitationsTabs
    }
    
    
    public static func shouldShowRedDotOnTheProfilePictureView(of ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> Bool {
        let sumOfBadgeCountsOfDiscussionsTabs = try countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId: ownedCryptoId, badgesToSum: .discussions, within: context)
        let sumOfBadgeCountsOfInvitationsTabs = try countSumOfBadgeCountForUnhiddenOwnedIdentites(excludedOwnedCryptoId: ownedCryptoId, badgesToSum: .invitations, within: context)
        let sum = sumOfBadgeCountsOfDiscussionsTabs + sumOfBadgeCountsOfInvitationsTabs
        return sum > 0
    }
}


// MARK: - Sending notifications on change

extension PersistedObvOwnedIdentity {
    
    public override func willSave() {
        super.willSave()
        if !isInserted && isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }

    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
        }

        if isInserted {
            let notification = ObvMessengerCoreDataNotification.newPersistedObvOwnedIdentity(ownedCryptoId: self.cryptoId, isActive: self.isActive)
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
            
            if changedKeys.contains(Predicate.Key.badgeCountForDiscussionsTab.rawValue) || changedKeys.contains(Predicate.Key.badgeCountForInvitationsTab.rawValue) {
                ObvMessengerCoreDataNotification.badgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity(ownedCryptoId: cryptoId)
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

// MARK: - MentionableIdentity

/// Allows a `PersistedObvOwnedIdentity` to be displayed in the views showing mentions.
extension PersistedObvOwnedIdentity: MentionableIdentity {
    
    public var mentionnedCryptoId: ObvCryptoId? {
        return self.cryptoId
    }
    
    public var mentionSearchMatcher: String {
        return mentionPersistedName
    }

    public var mentionPickerTitle: String {
        return mentionPersistedName
    }

    public var mentionPickerSubtitle: String? {
        return nil
    }

    public var mentionPersistedName: String {
        return PersonNameComponentsFormatter.localizedString(from: identityCoreDetails.personNameComponents,
                                                             style: .default)
    }

    public var innerIdentity: MentionableIdentityTypes.InnerIdentity {
        return .owned(typedObjectID)
    }
}
