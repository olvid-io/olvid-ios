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
import ObvEngine
import ObvTypes
import os.log
import OlvidUtils
import Platform_Base
import UI_CircledInitialsView_CircledInitialsConfiguration

@objc(PersistedObvContactIdentity)
public final class PersistedObvContactIdentity: NSManagedObject, ObvErrorMaker, ObvIdentifiableManagedObject {

    public static let entityName = "PersistedObvContactIdentity"
    public static let errorDomain = "PersistedObvContactIdentity"
    public let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: PersistedObvContactIdentity.self))

    // MARK: - Attributes

    @NSManaged private var capabilityGroupsV2: Bool
    @NSManaged private var capabilityOneToOneContacts: Bool
    @NSManaged private var capabilityWebrtcContinuousICE: Bool
    @NSManaged public private(set) var customDisplayName: String?
    @NSManaged public var customPhotoFilename: String?
    @NSManaged public private(set) var fullDisplayName: String
    @NSManaged private(set) var identity: Data
    @NSManaged public private(set) var isActive: Bool
    @NSManaged public private(set) var isCertifiedByOwnKeycloak: Bool
    @NSManaged public private(set) var isOneToOne: Bool
    @NSManaged private(set) var note: String?
    @NSManaged private var permanentUUID: UUID
    @NSManaged public private(set) var photoURL: URL?
    @NSManaged private var rawOwnedIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var rawStatus: Int
    @NSManaged private var serializedIdentityCoreDetails: Data
    @NSManaged public private(set) var sortDisplayName: String // Should be renamed normalizedSortAndSearchKey

    // MARK: - Relationships

    @NSManaged private var asGroupV2Member: Set<PersistedGroupV2Member>
    @NSManaged public private(set) var contactGroups: Set<PersistedContactGroup>
    @NSManaged public private(set) var devices: Set<PersistedObvContactDevice>
    @NSManaged private var rawOneToOneDiscussion: PersistedOneToOneDiscussion?
    @NSManaged private var rawOwnedIdentity: PersistedObvOwnedIdentity? // If nil, this entity is eventually cascade-deleted

    // MARK: - Variables

    /// Can be nil, if the entity is to be deleted
    ///
    /// - SeeAlso: ``rawOwnedIdentity``
    public private(set) var ownedIdentity: PersistedObvOwnedIdentity? {
        get {
            return self.rawOwnedIdentity
        }
        set {
            assert(newValue != nil)
            if let value = newValue {
                self.rawOwnedIdentityIdentity = value.cryptoId.getIdentity()
            }
            self.rawOwnedIdentity = newValue
        }
    }
    
    public var sortedDevices: [PersistedObvContactDevice] {
        devices.sorted(by: { $0.identifier < $1.identifier })
    }
    
    public var identityCoreDetails: ObvIdentityCoreDetails? {
        return try? ObvIdentityCoreDetails(serializedIdentityCoreDetails)
    }
    
    public var personNameComponents: PersonNameComponents? {
        var pnc = identityCoreDetails?.personNameComponents
        pnc?.nickname = customDisplayName
        return pnc
    }
    
    public lazy var cryptoId: ObvCryptoId = {
        return try! ObvCryptoId(identity: identity)
    }()

    private var changedKeys = Set<String>()
    
    public enum Status: Int {
        case noNewPublishedDetails = 0
        case unseenPublishedDetails = 1
        case seenPublishedDetails = 2
    }

    public var status: Status {
        return Status(rawValue: self.rawStatus)!
    }
    
    var sortedContactGroups: [PersistedContactGroup] {
        contactGroups.sorted { $0.groupName < $1.groupName }
    }
    
    var nameForSettingOneToOneDiscussionTitle: String {
        customOrNormalDisplayName
    }

    public var nameForContactNameInGroupDiscussion: String {
        customOrNormalDisplayName
    }
    
    public func resetOneToOneDiscussionTitle() throws {
        try self.oneToOneDiscussion?.resetTitle(to: self.nameForSettingOneToOneDiscussionTitle)
    }

    public var customOrFullDisplayName: String {
        customDisplayName ?? fullDisplayName
    }
    
    public var customOrNormalDisplayName: String {
        return customDisplayName ?? mediumOriginalName
    }
    
    public var customOrShortDisplayName: String {
        return customDisplayName ?? shortOriginalName
    }
    
    public var shortOriginalName: String {
        guard let personNameComponents else { assertionFailure(); return fullDisplayName }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        return formatter.string(from: personNameComponents)
    }

    var mediumOriginalName: String {
        guard let personNameComponents else { assertionFailure(); return fullDisplayName }
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .medium
        return formatter.string(from: personNameComponents)
    }

    /// Returns `nil` iff `isOneToOne` is `false`.
    public var oneToOneDiscussion: PersistedOneToOneDiscussion? {
        if isOneToOne {
            // In case the contact is OneToOne, we expect the discussion to be non-nil and active.
            assert(rawOneToOneDiscussion != nil && rawOneToOneDiscussion?.status == .active)
            return rawOneToOneDiscussion
        } else {
            // In case the contact is not OneToOne, the discussion is likely to be nil.
            // It can be non-nil if the contact was demoted from OneToOne to "other user".
            // In that case, we expect it to be locked or preDiscussion
            if let discussion = rawOneToOneDiscussion, managedObjectContext?.concurrencyType == .privateQueueConcurrencyType {
                assert(discussion.status == .locked || discussion.status == .preDiscussion)
            }
            return rawOneToOneDiscussion
        }
    }
    
    
    public var customPhotoURL: URL? {
        guard let customPhotoFilename = customPhotoFilename else { return nil }
        return ObvUICoreDataConstants.ContainerURL.forCustomContactProfilePictures.appendingPathComponent(customPhotoFilename)
    }

    
    public var displayedProfilePicture: UIImage? {
        guard let photoURL = customPhotoURL ?? photoURL else { return nil }
        guard FileManager.default.fileExists(atPath: photoURL.path) else { assertionFailure(); return nil }
        return UIImage(contentsOfFile: photoURL.path)
    }

    
    public var displayPhotoURL: URL? {
        customPhotoURL ?? photoURL
    }

    
    public func hasAtLeastOneRemoteContactDevice() -> Bool {
        return !self.devices.isEmpty
    }
    
    var displayedFirstName: String? {
        guard customDisplayName == nil else { return nil }
        return identityCoreDetails?.firstName
    }
    
    var firstName: String? {
        return identityCoreDetails?.firstName
    }
    
    var lastName: String? {
        return identityCoreDetails?.lastName
    }

    var displayedCustomDisplayNameOrLastName: String? {
        customDisplayName ?? identityCoreDetails?.lastName
    }

    public var displayedCustomDisplayNameOrFirstNameOrLastName: String? {
        customDisplayName ?? identityCoreDetails?.firstName ?? identityCoreDetails?.lastName
    }

    public var displayedCompany: String? {
        return identityCoreDetails?.company
    }

    public var displayedPosition: String? {
        return identityCoreDetails?.position
    }

    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity> {
        ObvManagedObjectPermanentID<PersistedObvContactIdentity>(uuid: self.permanentUUID)
    }

    public var circledInitialsConfiguration: CircledInitialsConfiguration {
        .contact(initial: customOrFullDisplayName,
                 photoURL: customPhotoURL ?? photoURL,
                 showGreenShield: isCertifiedByOwnKeycloak,
                 showRedShield: !isActive,
                 cryptoId: cryptoId,
                 tintAdjustementMode: .normal)
    }
                

    public func setCustomPhotoURL(with url: URL?) {
        guard url != self.customPhotoURL else { return }
        if let currentCustomPhotoURL = self.customPhotoURL {
            do {
                try FileManager.default.removeItem(at: currentCustomPhotoURL)
                self.customPhotoFilename = nil
            } catch {
                os_log("Cannot delete unused photo: %{public}@", log: self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
        if let url = url {
            assert(url.deletingLastPathComponent() == ObvUICoreDataConstants.ContainerURL.forCustomContactProfilePictures.url)
            self.customPhotoFilename = url.lastPathComponent
        } else {
            self.customPhotoFilename = nil
        }
    }

    
    public static func getAllCustomPhotoURLs(within context: NSManagedObjectContext) throws -> Set<URL> {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = Predicate.withCustomPhotoFilename
        request.propertiesToFetch = [Predicate.Key.customPhotoFilename.rawValue]
        let details = try context.fetch(request)
        let photoURLs = Set(details.compactMap({ $0.customPhotoURL }))
        return photoURLs
    }

}


// MARK: - Initializer

extension PersistedObvContactIdentity {
    
    public convenience init(contactIdentity: ObvContactIdentity, within context: NSManagedObjectContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedObvContactIdentity.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        guard let persistedObvOwnedIdentity = try PersistedObvOwnedIdentity.get(persisted: contactIdentity.ownedIdentity, within: context) else {
            throw Self.makeError(message: "Could not find PersistedObvOwnedIdentity")
        }
        self.customDisplayName = nil
        guard !contactIdentity.trustedIdentityDetails.coreDetails.getDisplayNameWithStyle(.full).isEmpty else {
            throw Self.makeError(message: "The full display name of the contact is empty")
        }
        self.fullDisplayName = contactIdentity.trustedIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
        self.serializedIdentityCoreDetails = try contactIdentity.trustedIdentityDetails.coreDetails.jsonEncode()
        self.identity = contactIdentity.cryptoId.getIdentity()
        self.isActive = true
        self.isOneToOne = contactIdentity.isOneToOne
        self.isCertifiedByOwnKeycloak = contactIdentity.isCertifiedByOwnKeycloak
        self.note = nil
        self.permanentUUID = UUID()
        self.rawStatus = Status.noNewPublishedDetails.rawValue
        self.sortDisplayName = getNormalizedSortAndSearchKey(with: ObvMessengerSettings.Interface.contactsSortOrder)
        self.photoURL = contactIdentity.currentIdentityDetails.photoURL
        self.devices = Set<PersistedObvContactDevice>()
        self.contactGroups = Set<PersistedContactGroup>()
        self.rawOwnedIdentityIdentity = persistedObvOwnedIdentity.cryptoId.getIdentity()
        self.ownedIdentity = persistedObvOwnedIdentity
        if contactIdentity.isOneToOne {
            if let discussion = try PersistedOneToOneDiscussion.getWithContactCryptoId(contactIdentity.cryptoId, ofOwnedCryptoId: contactIdentity.ownedIdentity.cryptoId, within: context) {
                try discussion.setStatus(to: .active)
                self.rawOneToOneDiscussion = discussion
            } else {
                self.rawOneToOneDiscussion = try PersistedOneToOneDiscussion(contactIdentity: self, status: .active)
            }
        } else {
            if let discussion = try PersistedOneToOneDiscussion.getWithContactCryptoId(contactIdentity.cryptoId, ofOwnedCryptoId: contactIdentity.ownedIdentity.cryptoId, within: context) {
                try discussion.setStatus(to: .locked)
                self.rawOneToOneDiscussion = discussion
            } else {
                self.rawOneToOneDiscussion = nil
            }
        }
        
        /* When a contact is inserted, we look for Group v2 instances where this user is a member. More precisely, we look for PersistedGroupV2Member instances corresponding to this new contact identity, for this owned identity. When found, we update these PersistedGroupV2Member instances so that they point to this new PersistedObvContactIdentity instance. */
        
        let membersCorrespondingToThisNewContact = try PersistedGroupV2Member.getAllPersistedGroupV2MemberOfOwnedIdentity(
            with: contactIdentity.ownedIdentity.cryptoId,
            withIdentity: self.cryptoId,
            within: context)
        for member in membersCorrespondingToThisNewContact {
            try member.updateWith(persistedContact: self)
        }

    }
    
    
    public func deleteAndLockOneToOneDiscussion() throws {
        guard let context = self.managedObjectContext else { throw PersistedObvContactIdentity.makeError(message: "No context found") }
        
        // When deleting a contact, we lock the one to one discussion we have with her
        do {
            try self.rawOneToOneDiscussion?.setStatus(to: .locked)
        } catch {
            os_log("Could not lock the persisted oneToOne discussion", log: log, type: .fault)
            throw Self.makeError(message: "Could not lock the persisted oneToOne discussion")
        }
        context.delete(self)
    }


    private func getNormalizedSortAndSearchKey(with sortOrder: ContactsSortOrder) -> String {
        guard let coreDetails = self.identityCoreDetails else {
            assertionFailure()
            return sortOrder.computeNormalizedSortAndSearchKey(customDisplayName: fullDisplayName, firstName: nil, lastName: nil, position: nil, company: nil)
        }
        return sortOrder.computeNormalizedSortAndSearchKey(
            customDisplayName: self.customDisplayName,
            firstName: coreDetails.firstName,
            lastName: coreDetails.lastName,
            position: coreDetails.position,
            company: coreDetails.company)
    }
        

    public func updateSortOrder(with newSortOrder: ContactsSortOrder) {
        let newSortDisplayName = getNormalizedSortAndSearchKey(with: newSortOrder)
        if self.sortDisplayName != newSortDisplayName {
            self.sortDisplayName = newSortDisplayName
            do {
                try rawOneToOneDiscussion?.updateNormalizedSearchKey()
            } catch {
                os_log("Failed to update normalized search key on discussion: %{public}@", log: self.log, type: .fault, error.localizedDescription)
            }
        }
    }


    public func updateContact(with contactIdentity: ObvContactIdentity) throws {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let newCoreDetails = contactIdentity.trustedIdentityDetails.coreDetails
        let newSerializedIdentityCoreDetails = try newCoreDetails.jsonEncode()
        if self.serializedIdentityCoreDetails != newSerializedIdentityCoreDetails {
            self.serializedIdentityCoreDetails = newSerializedIdentityCoreDetails
        }
        self.updatePhotoURL(with: contactIdentity.trustedIdentityDetails.photoURL)
        let newFullDisplayName = newCoreDetails.getDisplayNameWithStyle(.full)
        if self.fullDisplayName != newFullDisplayName {
            self.fullDisplayName = newFullDisplayName
        }
        if self.isCertifiedByOwnKeycloak != contactIdentity.isCertifiedByOwnKeycloak {
            self.isCertifiedByOwnKeycloak = contactIdentity.isCertifiedByOwnKeycloak
        }
        self.updateSortOrder(with: ObvMessengerSettings.Interface.contactsSortOrder)
        if self.isActive != contactIdentity.isActive {
            self.isActive = contactIdentity.isActive
        }
        if self.isOneToOne != contactIdentity.isOneToOne {
            self.isOneToOne = contactIdentity.isOneToOne
        }
        if self.isOneToOne {
            if let discussion = self.rawOneToOneDiscussion {
                try discussion.setStatus(to: .active)
            } else if let discussion = try PersistedOneToOneDiscussion.getWithContactCryptoId(contactIdentity.cryptoId, ofOwnedCryptoId: contactIdentity.ownedIdentity.cryptoId, within: context) {
                try discussion.setStatus(to: .active)
                if self.rawOneToOneDiscussion != discussion {
                    self.rawOneToOneDiscussion = discussion
                }
            } else {
                self.rawOneToOneDiscussion = try PersistedOneToOneDiscussion(contactIdentity: self, status: .active)
            }
        } else {
            try self.rawOneToOneDiscussion?.setStatus(to: .locked)
        }
        // Note that we do not reset the discussion title.
        // Instead, we send a notification in the didSave method that will be catched by the appropriate coordinator, allowing to properly synchronize the title change.
    }

    
    public func markAsCertifiedByOwnKeycloak() {
        isCertifiedByOwnKeycloak = true
    }

    public func updatePhotoURL(with url: URL?) {
        if self.photoURL != url {
            self.photoURL = url
        }
    }
    
    public func setCustomDisplayName(to displayName: String?) throws {
        if let newCustomDisplayName = displayName, !newCustomDisplayName.isEmpty {
            if self.customDisplayName != newCustomDisplayName {
                self.customDisplayName = newCustomDisplayName
            }
        } else {
            if self.customDisplayName != nil {
                self.customDisplayName = nil
            }
        }
        try self.oneToOneDiscussion?.resetTitle(to: self.customDisplayName ?? self.fullDisplayName)
        self.updateSortOrder(with: ObvMessengerSettings.Interface.contactsSortOrder)
    }

    func setNote(to newNote: String?) {
        self.note = newNote
    }
}


// MARK: - Managing Contact Devices

extension PersistedObvContactIdentity {
    
    public func insert(_ device: ObvContactDevice) throws {
        guard let context = self.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        guard device.contactIdentity.cryptoId == self.cryptoId, device.contactIdentity.ownedIdentity.cryptoId.getIdentity() == self.rawOwnedIdentityIdentity else {
            throw Self.makeError(message: "Unexpected contact identity") }
        let knownDeviceIdentifiers: Set<Data> = Set(self.devices.compactMap { $0.identifier })
        if !knownDeviceIdentifiers.contains(device.identifier) {
            _ = try PersistedObvContactDevice(obvContactDevice: device, within: context)
        }
    }
    
}


// MARK: - Capabilities

extension PersistedObvContactIdentity {
    
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


// MARK: - Other functions

extension PersistedObvContactIdentity {

    public func setContactStatus(to newStatus: Status) {
        if self.rawStatus != newStatus.rawValue {
            self.rawStatus = newStatus.rawValue
        }
    }

}


// MARK: - Convenience DB getters

extension PersistedObvContactIdentity {
    
    @nonobjc public class func fetchRequest() -> NSFetchRequest<PersistedObvContactIdentity> {
        return NSFetchRequest<PersistedObvContactIdentity>(entityName: self.entityName)
    }
    
    public enum OneToOneStatus {
        case oneToOne
        case nonOneToOne
        case any
    }

    public struct Predicate {
        public enum Key: String {
            // Attributes
            case capabilityGroupsV2 = "capabilityGroupsV2"
            case capabilityOneToOneContacts = "capabilityOneToOneContacts"
            case capabilityWebrtcContinuousICE = "capabilityWebrtcContinuousICE"
            case customDisplayName = "customDisplayName"
            case customPhotoFilename = "customPhotoFilename"
            case fullDisplayName = "fullDisplayName"
            case identity = "identity"
            case isActive = "isActive"
            case isCertifiedByOwnKeycloak = "isCertifiedByOwnKeycloak"
            case isOneToOne = "isOneToOne"
            case permanentUUID = "permanentUUID"
            case rawOwnedIdentity = "rawOwnedIdentity"
            case rawStatus = "rawStatus"
            case sortDisplayName = "sortDisplayName" // Should be renamed normalizedSortAndSearchKey
            // Relationships
            case contactGroups = "contactGroups"
            case devices = "devices"
            // Others
            static let ownedIdentityIdentity = [rawOwnedIdentity.rawValue, PersistedObvOwnedIdentity.Predicate.Key.identity.rawValue].joined(separator: ".")
        }
        static func withCryptoId(_ cryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.identity, EqualToData: cryptoId.getIdentity())
        }
        static func withCryptoIdIn(_ cryptoIds: Set<ObvCryptoId>) -> NSPredicate {
            let identities = cryptoIds.map { $0.getIdentity() as NSData }
            return NSPredicate(format: "%K IN %@", Key.identity.rawValue, identities)
        }
        static func ofOwnedIdentity(_ ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            NSPredicate(Key.rawOwnedIdentity, equalTo: ownedIdentity)
        }
        static func ofOwnedIdentityWithCryptoId(_ ownedIdentityCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownedIdentityCryptoId.getIdentity())
        }
        static func correspondingToObvContactIdentity(_ obvContactIdentity: ObvContactIdentity) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withCryptoId(obvContactIdentity.cryptoId),
                ofOwnedIdentityWithCryptoId(obvContactIdentity.ownedIdentity.cryptoId),
            ])
        }
        static func excludedContactCryptoIds(excludedIdentities: Set<ObvCryptoId>) -> NSPredicate {
            let excludedIdentities: [NSData] = excludedIdentities.map { $0.getIdentity() as NSData }
            return NSPredicate(format: "NOT %K IN %@", Key.identity.rawValue, excludedIdentities)
        }
        static func restrictedToContactCryptoIds(identities: Set<ObvCryptoId>) -> NSPredicate {
            let identities: [NSData] = identities.map { $0.getIdentity() as NSData }
            return NSPredicate(format: "%K IN %@", Key.identity.rawValue, identities)
        }
        static var isCertifiedByOwnKeycloakIsTrue: NSPredicate {
            NSPredicate(Key.isCertifiedByOwnKeycloak, is: true)
        }
        static func inPersistedContactGroup(_ persistedContactGroup: PersistedContactGroup) -> NSPredicate {
            NSPredicate(format: "%@ IN %K", persistedContactGroup, Key.contactGroups.rawValue)
        }
        static func isOneToOneIs(_ value: Bool) -> NSPredicate {
            NSPredicate(Key.isOneToOne, is: value)
        }
        static func forOneToOneStatus(_ mode: OneToOneStatus) -> NSPredicate {
            switch mode {
            case .oneToOne:
                return Predicate.isOneToOneIs(true)
            case .nonOneToOne:
                return Predicate.isOneToOneIs(false)
            case .any:
                return NSPredicate(value: true)
            }
        }
        static func requiredCapability(_ capability: ObvCapability) -> NSPredicate {
            switch capability {
            case .webrtcContinuousICE:
                return NSPredicate(Key.capabilityWebrtcContinuousICE, is: true)
            case .groupsV2:
                return NSPredicate(Key.capabilityGroupsV2, is: true)
            case .oneToOneContacts:
                return NSPredicate(Key.capabilityOneToOneContacts, is: true)
            }
        }
        static func requiredCapabilities(_ capabilities: [ObvCapability]) -> NSPredicate {
            guard !capabilities.isEmpty else { return NSPredicate(value: true) }
            return NSCompoundPredicate(andPredicateWithSubpredicates: capabilities.map({ Self.requiredCapability($0) }))
        }
        public static var withCustomPhotoFilename: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.customPhotoFilename)
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>) -> NSPredicate {
            NSPredicate(Key.permanentUUID, EqualToUuid: permanentID.uuid)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
    }
    
    
    public static func get(cryptoId: ObvCryptoId, ownedIdentity: PersistedObvOwnedIdentity, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus) throws -> PersistedObvContactIdentity? {
        guard let context = ownedIdentity.managedObjectContext else { throw makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCryptoId(cryptoId),
            Predicate.ofOwnedIdentity(ownedIdentity),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    public static func get(contactCryptoId: ObvCryptoId, ownedIdentityCryptoId: ObvCryptoId, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) throws -> PersistedObvContactIdentity? {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCryptoId(contactCryptoId),
            Predicate.ofOwnedIdentityWithCryptoId(ownedIdentityCryptoId),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(persisted obvContactIdentity: ObvContactIdentity, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) throws -> PersistedObvContactIdentity? {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = Predicate.correspondingToObvContactIdentity(obvContactIdentity)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    public static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<PersistedObvContactIdentity>, within context: NSManagedObjectContext) throws -> PersistedObvContactIdentity? {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func getAllContactOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) throws -> [PersistedObvContactIdentity] {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortDisplayName.rawValue, ascending: true)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    

    public static func markAllContactOfOwnedIdentityAsNotCertifiedBySameKeycloak(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isCertifiedByOwnKeycloakIsTrue,
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
        ])
        request.fetchBatchSize = 1_000
        let contacts = try context.fetch(request)
        for contact in contacts {
            contact.isCertifiedByOwnKeycloak = false
        }
    }
    
    
    static func getAllContactsWithCryptoId(in cryptoIds: Set<ObvCryptoId>, ofOwnedIdentity ownedCryptoId: ObvCryptoId, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) throws -> Set<PersistedObvContactIdentity> {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCryptoIdIn(cryptoIds),
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
        request.fetchBatchSize = 1_000
        let contacts = Set(try context.fetch(request))
        return contacts
    }

    
    public static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedObvContactIdentity? {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    

    public static func get(objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, within context: NSManagedObjectContext) throws -> PersistedObvContactIdentity? {
        return try context.existingObject(with: objectID.objectID) as? PersistedObvContactIdentity
    }
    

    public static func getAll(within context: NSManagedObjectContext) throws -> [PersistedObvContactIdentity] {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        return try context.fetch(request)
    }

    
    public static func countContactsOfOwnedIdentity(_ ownedIdentityCryptoId: ObvCryptoId, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.ofOwnedIdentityWithCryptoId(ownedIdentityCryptoId),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
        request.resultType = .countResultType
        let count = try context.count(for: request)
        return count
    }
}


// MARK: - Convenience NSFetchedResultsController creators

extension PersistedObvContactIdentity {
            
    public static func getPredicateForAllContactsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, requiredCapabilities: [ObvCapability]?) -> NSPredicate {
        let predicateOnCapabilities: NSPredicate
        if let requiredCapabilities = requiredCapabilities {
            predicateOnCapabilities = Predicate.requiredCapabilities(requiredCapabilities)
        } else {
            predicateOnCapabilities = NSPredicate(value: true)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
            Predicate.forOneToOneStatus(oneToOneStatus),
            predicateOnCapabilities,
        ])
    }

    
    public static func getPredicateForAllContactsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, excludedContactCryptoIds: Set<ObvCryptoId>, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, requiredCapabilities: [ObvCapability]) -> NSPredicate {
        let predicateOnCapabilities: NSPredicate
        if requiredCapabilities.isEmpty {
            predicateOnCapabilities = NSPredicate(value: true)
        } else {
            predicateOnCapabilities = Predicate.requiredCapabilities(requiredCapabilities)
        }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
            Predicate.excludedContactCryptoIds(excludedIdentities: excludedContactCryptoIds),
            Predicate.forOneToOneStatus(oneToOneStatus),
            predicateOnCapabilities,
        ])
    }

    
    public static func getPredicateForAllContactsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, restrictedToContactCryptoIds: Set<ObvCryptoId>, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
            Predicate.restrictedToContactCryptoIds(identities: restrictedToContactCryptoIds),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
    }
    
    
    public static func getPredicateForContactGroup(_ persistedContactGroup: PersistedContactGroup) -> NSPredicate {
        Predicate.inPersistedContactGroup(persistedContactGroup)
    }
    
    
    public static func getFetchRequestForAllContactsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, predicate: NSPredicate, and andPredicate: NSPredicate? = nil, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus) -> NSFetchRequest<PersistedObvContactIdentity> {

        var predicates = [
            predicate,
            Predicate.forOneToOneStatus(oneToOneStatus),
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
        ]
        if let andPredicate {
            predicates.append(andPredicate)
        }

        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortDisplayName.rawValue, ascending: true)]
        request.fetchBatchSize = 1_000
        return request
    }
    
    
    static func getFetchedResultsControllerForContactGroup(_ persistedContactGroup: PersistedContactGroup, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus) throws -> NSFetchedResultsController<PersistedObvContactIdentity> {
        guard let context = persistedContactGroup.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let predicate = getPredicateForContactGroup(persistedContactGroup)
        return getFetchedResultsController(predicate: predicate, whereOneToOneStatusIs: oneToOneStatus, within: context)
    }

    
    public static func getFetchedResultsController(predicate: NSPredicate, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedObvContactIdentity> {
        let fetchRequest: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortDisplayName.rawValue, ascending: true)]
        fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate,
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
    
}


// MARK: - Sending notifications on change

extension PersistedObvContactIdentity {
    
    public override func willSave() {
        super.willSave()
        
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
        
        if !changedKeys.isEmpty {
            asGroupV2Member.forEach { $0.updateWhenPersistedObvContactIdentityIsUpdated() }
        }

        // When updating a contact, we try to update the oneToOne discussion title.
        if isUpdated && !self.changedValues().isEmpty {
            oneToOneDiscussion?.resetDiscussionTitleWithContactIfAppropriate()
        }
    }

    public override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
        }
        
        if isInserted {
            
            ObvMessengerCoreDataNotification.persistedContactWasInserted(contactPermanentID: objectPermanentID)
                .postOnDispatchQueue()

        } else if isDeleted {
            
            let notification = ObvMessengerCoreDataNotification.persistedContactWasDeleted(objectID: objectID, identity: identity)
            notification.postOnDispatchQueue()
                        
        } else {
          
            if changedKeys.contains(Predicate.Key.customDisplayName.rawValue) {
                ObvMessengerCoreDataNotification.persistedContactHasNewCustomDisplayName(contactCryptoId: cryptoId)
                    .postOnDispatchQueue()
            }
            
            if changedKeys.contains(Predicate.Key.rawStatus.rawValue), let ownedCryptoId = ownedIdentity?.cryptoId {
                ObvMessengerCoreDataNotification.persistedContactHasNewStatus(contactCryptoId: cryptoId, ownedCryptoId: ownedCryptoId)
                    .postOnDispatchQueue()
            }
            
            if changedKeys.contains(Predicate.Key.isActive.rawValue) {
                ObvMessengerCoreDataNotification.persistedContactIsActiveChanged(contactID: typedObjectID)
                    .postOnDispatchQueue()
            }

            // Last but not least, if the one2one discussion with this contact is loaded in the view context, we refresh it.
            // This what makes it possible, e.g., to see the contact profile picture in the discussion list as soon as possible
            // 2023-03-09: We used to perform the refresh here. We now send a notification and let the meta manager perform the refresh.
            if !changedKeys.isEmpty {
                ObvMessengerCoreDataNotification.persistedContactWasUpdated(contactObjectID: typedObjectID)
                    .postOnDispatchQueue()
            }

        }
    }
}


// MARK: - ContactPermanentID

public typealias ContactPermanentID = ObvManagedObjectPermanentID<PersistedObvContactIdentity>

// MARK: - MentionableIdentity

/// Allows a `PersistedObvContactIdentity` to be displayed in the views showing mentions.
extension PersistedObvContactIdentity: MentionableIdentity {
    
    public var mentionnedCryptoId: ObvCryptoId? {
        return self.cryptoId
    }
    
    public var mentionSearchMatcher: String {
        return sortDisplayName
    }

    public var mentionPickerTitle: String {
        if let customDisplayName {
            return customDisplayName
        }

        return mentionPersistedName
    }

    public var mentionPickerSubtitle: String? {
        if customDisplayName == nil {
            return nil
        }

        return mentionPersistedName
    }

    public var mentionPersistedName: String {
        guard identityCoreDetails != nil else {
            assertionFailure("not linked identityCoreDetails, assuming this has been cascade deleted?")

            return ""
        }

        let components = PersonNameComponents()..{
            $0.givenName = firstName
            $0.familyName = lastName
        }

        return PersonNameComponentsFormatter.localizedString(from: components,
                                                             style: .default)
    }

    public var innerIdentity: MentionableIdentityTypes.InnerIdentity {
        return .contact(typedObjectID)
    }
}
