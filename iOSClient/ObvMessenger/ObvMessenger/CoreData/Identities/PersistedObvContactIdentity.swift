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
import Intents
import os.log
import OlvidUtils

@objc(PersistedObvContactIdentity)
final class PersistedObvContactIdentity: NSManagedObject {

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: PersistedObvContactIdentity.self))
    
    private static let entityName = "PersistedObvContactIdentity"
        
    private static func makeError(message: String) -> Error { NSError(domain: "PersistedObvContactIdentity", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: - Attributes

    @NSManaged private(set) var customDisplayName: String?
    @NSManaged private(set) var fullDisplayName: String
    @NSManaged private(set) var identity: Data
    @NSManaged private(set) var isActive: Bool
    @NSManaged private(set) var isCertifiedByOwnKeycloak: Bool
    @NSManaged private(set) var isOneToOne: Bool
    @NSManaged private(set) var note: String?
    @NSManaged private var rawOwnedIdentityIdentity: Data // Required for core data constraints
    @NSManaged private var rawStatus: Int
    @NSManaged private var serializedIdentityCoreDetails: Data
    @NSManaged private(set) var sortDisplayName: String // Should be renamed normalizedSortAndSearchKey
    @NSManaged private(set) var photoURL: URL?
    @NSManaged private(set) var customPhotoFilename: String?
    @NSManaged private var capabilityWebrtcContinuousICE: Bool
    @NSManaged private var capabilityOneToOneContacts: Bool
    @NSManaged private var capabilityGroupsV2: Bool

    // MARK: - Relationships

    @NSManaged private(set) var contactGroups: Set<PersistedContactGroup>
    @NSManaged private(set) var devices: Set<PersistedObvContactDevice>
    @NSManaged private var rawOneToOneDiscussion: PersistedOneToOneDiscussion?
    @NSManaged private var rawOwnedIdentity: PersistedObvOwnedIdentity? // If nil, this entity is eventually cascade-deleted
    
    // MARK: - Variables
    
    private(set) var ownedIdentity: PersistedObvOwnedIdentity? {
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
    
    var sortedDevices: [PersistedObvContactDevice] {
        devices.sorted(by: { $0.identifier < $1.identifier })
    }
    
    var identityCoreDetails: ObvIdentityCoreDetails {
        return try! ObvIdentityCoreDetails(serializedIdentityCoreDetails)
    }
    
    var personNameComponents: PersonNameComponents {
        var pnc = identityCoreDetails.personNameComponents
        pnc.nickname = customDisplayName
        return pnc
    }
    
    lazy var cryptoId: ObvCryptoId = {
        return try! ObvCryptoId(identity: identity)
    }()

    private var changedKeys = Set<String>()
    
    enum Status: Int {
        case noNewPublishedDetails = 0
        case unseenPublishedDetails = 1
        case seenPublishedDetails = 2
    }

    var status: Status {
        return Status(rawValue: self.rawStatus)!
    }
    
    var sortedContactGroups: [PersistedContactGroup] {
        contactGroups.sorted { $0.groupName < $1.groupName }
    }
    
    var nameForSettingOneToOneDiscussionTitle: String {
        // If this changes, we should also update the notification sent in the `didSave` method.
        customOrFullDisplayName
    }
    
    func resetOneToOneDiscussionTitle() throws {
        try self.oneToOneDiscussion?.resetTitle(to: self.nameForSettingOneToOneDiscussionTitle)
    }

    var customOrFullDisplayName: String {
        customDisplayName ?? fullDisplayName
    }
    
    var customOrNormalDisplayName: String {
        return customDisplayName ?? mediumOriginalName
    }

    var customPhotoURL: URL? {
        guard let customPhotoFilename = customPhotoFilename else { return nil }
        return ObvMessengerConstants.containerURL.forCustomContactProfilePictures.appendingPathComponent(customPhotoFilename)
    }
    
    var displayPhotoURL: URL? {
        customPhotoURL ?? photoURL
    }
    
    var shortOriginalName: String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .short
        return formatter.string(from: personNameComponents)
    }

    var mediumOriginalName: String {
        let formatter = PersonNameComponentsFormatter()
        formatter.style = .medium
        return formatter.string(from: personNameComponents)
    }

    /// Returns `nil` iff `isOneToOne` is `false`.
    var oneToOneDiscussion: PersistedOneToOneDiscussion? {
        if isOneToOne {
            // In case the contact is OneToOne, we expect the discussion to be non-nil and active.
            assert(rawOneToOneDiscussion != nil && rawOneToOneDiscussion?.status == .active)
            return rawOneToOneDiscussion
        } else {
            // In case the contact is not OneToOne, the discussion is likely to be nil.
            // It can be non-nil if the contact was demoted from OneToOne to "other user".
            // In that case, we expect it to be locked or preDiscussion
            if let discussion = rawOneToOneDiscussion {
                assert(discussion.status == .locked || discussion.status == .preDiscussion)
            }
            return rawOneToOneDiscussion
        }
    }
    
    
    func hasAtLeastOneRemoteContactDevice() -> Bool {
        return !self.devices.isEmpty
    }
}


// MARK: - Initializer

extension PersistedObvContactIdentity {
    
    convenience init(contactIdentity: ObvContactIdentity, within context: NSManagedObjectContext) throws {
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
    }
    
    
    func deleteAndLockOneToOneDiscussion() throws {
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
        let coreDetails = self.identityCoreDetails

        var allComponents: [String?] = [self.customDisplayName]
        switch sortOrder {
        case .byFirstName:
            allComponents += [coreDetails.firstName, coreDetails.lastName]
        case .byLastName:
            allComponents += [coreDetails.lastName, coreDetails.firstName]
        }
        allComponents += [coreDetails.position, coreDetails.company]

        let components = allComponents.compactMap { $0 }
        return components.map({
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
        }).joined(separator: "_")
    }

    func updateSortOrder(with newSortOrder: ContactsSortOrder) {
        self.sortDisplayName = getNormalizedSortAndSearchKey(with: newSortOrder)
    }

    
    func updateContact(with contactIdentity: ObvContactIdentity) throws {
        guard let context = self.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let coreDetails = contactIdentity.trustedIdentityDetails.coreDetails
        self.serializedIdentityCoreDetails = try coreDetails.jsonEncode()
        self.updatePhotoURL(with: contactIdentity.trustedIdentityDetails.photoURL)
        self.fullDisplayName = coreDetails.getDisplayNameWithStyle(.full)
        self.isCertifiedByOwnKeycloak = contactIdentity.isCertifiedByOwnKeycloak
        self.updateSortOrder(with: ObvMessengerSettings.Interface.contactsSortOrder)
        self.isActive = contactIdentity.isActive
        self.isOneToOne = contactIdentity.isOneToOne
        if self.isOneToOne {
            if let discussion = self.rawOneToOneDiscussion {
                try discussion.setStatus(to: .active)
            } else if let discussion = try PersistedOneToOneDiscussion.getWithContactCryptoId(contactIdentity.cryptoId, ofOwnedCryptoId: contactIdentity.ownedIdentity.cryptoId, within: context) {
                try discussion.setStatus(to: .active)
                self.rawOneToOneDiscussion = discussion
            } else {
                self.rawOneToOneDiscussion = try PersistedOneToOneDiscussion(contactIdentity: self, status: .active)
            }
        } else {
            try self.rawOneToOneDiscussion?.setStatus(to: .locked)
        }
        // Note that we do not reset the discussion title.
        // Instead, we send a notification in the didSave method that will be catched by the appropriate coordinator, allowing to properly synchronize the title change.
    }

    
    func markAsCertifiedByOwnKeycloak() {
        isCertifiedByOwnKeycloak = true
    }

    func updatePhotoURL(with url: URL?) {
        self.photoURL = url
    }
    
    func setCustomDisplayName(to displayName: String?) throws {
        if let newCustomDisplayName = displayName, !newCustomDisplayName.isEmpty {
            self.customDisplayName = newCustomDisplayName
        } else {
            self.customDisplayName = nil
        }
        try self.oneToOneDiscussion?.resetTitle(to: self.customDisplayName ?? self.fullDisplayName)
        self.updateSortOrder(with: ObvMessengerSettings.Interface.contactsSortOrder)
    }

    func setCustomPhotoURL(with url: URL?) {
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
            assert(url.deletingLastPathComponent() == ObvMessengerConstants.containerURL.forCustomContactProfilePictures)
            self.customPhotoFilename = url.lastPathComponent
        } else {
            self.customPhotoFilename = nil
        }
    }
    
    func setNote(to newNote: String?) {
        self.note = newNote
    }

}


// MARK: - Managing Contact Devices

extension PersistedObvContactIdentity {
    
    func insert(_ device: ObvContactDevice) throws {
        guard device.contactIdentity.cryptoId == self.cryptoId else { throw NSError() }
        guard let context = self.managedObjectContext else { throw NSError() }
        let knownDeviceIdentifiers: Set<Data> = Set(self.devices.compactMap { $0.identifier })
        if !knownDeviceIdentifiers.contains(device.identifier) {
            _ = try PersistedObvContactDevice(obvContactDevice: device, within: context)
        }
    }
    
    func set(_ newContactDevices: Set<ObvContactDevice>) throws {
        guard let context = self.managedObjectContext else { throw NSError() }
        let currentDeviceIdentifiers: Set<Data> = Set(self.devices.compactMap { $0.identifier })
        let newDeviceIdentifiers = Set(newContactDevices.map { $0.identifier })
        let devicesToAdd = newContactDevices.filter { !currentDeviceIdentifiers.contains($0.identifier) }
        let devicesToRemove = self.devices.filter { !newDeviceIdentifiers.contains($0.identifier) }
        for device in devicesToAdd {
            try insert(device)
        }
        for device in devicesToRemove {
            context.delete(device)
        }
    }
    
}


// MARK: - Capabilities

extension PersistedObvContactIdentity {
    
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


// MARK: - Other functions

extension PersistedObvContactIdentity {

    func setContactStatus(to newStatus: Status) {
        self.rawStatus = newStatus.rawValue
    }

}


// MARK: - Convenience DB getters

extension PersistedObvContactIdentity {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedObvContactIdentity> {
        return NSFetchRequest<PersistedObvContactIdentity>(entityName: self.entityName)
    }
    
    enum OneToOneStatus {
        case oneToOne
        case nonOneToOne
        case any
    }

    struct Predicate {
        enum Key: String {
            case customDisplayName = "customDisplayName"
            case identity = "identity"
            case sortDisplayName = "sortDisplayName" // Should be renamed normalizedSortAndSearchKey
            case devices = "devices"
            case fullDisplayName = "fullDisplayName"
            case rawOwnedIdentity = "rawOwnedIdentity"
            case rawStatus = "rawStatus"
            case customPhotoFilename = "customPhotoFilename"
            case contactGroups = "contactGroups"
            case isActive = "isActive"
            case isCertifiedByOwnKeycloak = "isCertifiedByOwnKeycloak"
            case capabilityWebrtcContinuousICE = "capabilityWebrtcContinuousICE"
            case isOneToOne = "isOneToOne"
            static var ownedIdentityIdentity: String {
                [Key.rawOwnedIdentity.rawValue, PersistedObvOwnedIdentity.identityKey].joined(separator: ".")
            }
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
    }
    
    
    static func get(cryptoId: ObvCryptoId, ownedIdentity: PersistedObvOwnedIdentity, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus) throws -> PersistedObvContactIdentity? {
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
    
    
    static func get(contactCryptoId: ObvCryptoId, ownedIdentityCryptoId: ObvCryptoId, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) throws -> PersistedObvContactIdentity? {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withCryptoId(contactCryptoId),
            Predicate.ofOwnedIdentityWithCryptoId(ownedIdentityCryptoId),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func get(persisted obvContactIdentity: ObvContactIdentity, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) throws -> PersistedObvContactIdentity? {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = Predicate.correspondingToObvContactIdentity(obvContactIdentity)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    static func getAllContactOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) throws -> [PersistedObvContactIdentity] {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortDisplayName.rawValue, ascending: true)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
        request.fetchBatchSize = 1_000
        return try context.fetch(request)
    }
    

    static func markAllContactOfOwnedIdentityAsNotCertifiedBySameKeycloak(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
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

    
    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedObvContactIdentity? {
        return try context.existingObject(with: objectID) as? PersistedObvContactIdentity
    }
    

    static func get(objectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, within context: NSManagedObjectContext) throws -> PersistedObvContactIdentity? {
        return try context.existingObject(with: objectID.objectID) as? PersistedObvContactIdentity
    }
    

    static func getAll(within context: NSManagedObjectContext) throws -> [PersistedObvContactIdentity] {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        return try context.fetch(request)
    }

    
    static func countContactsOfOwnedIdentity(_ ownedIdentityCryptoId: ObvCryptoId, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.ofOwnedIdentityWithCryptoId(ownedIdentityCryptoId),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
        request.resultType = .countResultType
        let count = try context.count(for: request)
        return count
    }

    
    static func getAllCustomPhotoURLs(within context: NSManagedObjectContext) throws -> Set<URL> {
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.customPhotoFilename.rawValue]
        let details = try context.fetch(request)
        let photoURLs = Set(details.compactMap({ $0.customPhotoURL }))
        return photoURLs
    }

}


// MARK: - Convenience NSFetchedResultsController creators

extension PersistedObvContactIdentity {
            
    static func getPredicateForAllContactsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
    }

    
    static func getPredicateForAllContactsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, excludedContactCryptoIds: Set<ObvCryptoId>, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus) -> NSPredicate {
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
            Predicate.excludedContactCryptoIds(excludedIdentities: excludedContactCryptoIds),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
    }

    
    static func getPredicateForAllContactsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, restrictedToContactCryptoIds: Set<ObvCryptoId>, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus) -> NSPredicate {
        NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.ofOwnedIdentityWithCryptoId(ownedCryptoId),
            Predicate.restrictedToContactCryptoIds(identities: restrictedToContactCryptoIds),
            Predicate.forOneToOneStatus(oneToOneStatus),
        ])
    }
    
    
    static func getPredicateForContactGroup(_ persistedContactGroup: PersistedContactGroup) -> NSPredicate {
        Predicate.inPersistedContactGroup(persistedContactGroup)
    }
    
    
    static func getFetchRequestForAllContactsOfOwnedIdentity(with ownedCryptoId: ObvCryptoId, predicate: NSPredicate, and andPredicate: NSPredicate? = nil, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus) -> NSFetchRequest<PersistedObvContactIdentity> {
        let _predicate: NSPredicate
        if let andPredicate = andPredicate {
            _predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                andPredicate,
                Predicate.forOneToOneStatus(oneToOneStatus),
            ])
        } else {
            _predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                predicate,
                Predicate.forOneToOneStatus(oneToOneStatus),
            ])
        }
        let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
        request.predicate = _predicate
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.sortDisplayName.rawValue, ascending: true)]
        request.fetchBatchSize = 1_000
        return request
    }
    
    
    static func getFetchedResultsControllerForContactGroup(_ persistedContactGroup: PersistedContactGroup, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus) throws -> NSFetchedResultsController<PersistedObvContactIdentity> {
        guard let context = persistedContactGroup.managedObjectContext else { throw NSError() }
        let predicate = getPredicateForContactGroup(persistedContactGroup)
        return getFetchedResultsController(predicate: predicate, whereOneToOneStatusIs: oneToOneStatus, within: context)
    }

    
    static func getFetchedResultsController(predicate: NSPredicate, whereOneToOneStatusIs oneToOneStatus: OneToOneStatus, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedObvContactIdentity> {
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


// MARK: - Thread safe struct

extension PersistedObvContactIdentity {
    
    struct Structure: Hashable, Equatable {
        
        let typedObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>
        let cryptoId: ObvCryptoId
        let fullDisplayName: String
        let customOrFullDisplayName: String
        let displayPhotoURL: URL?
        let personNameComponents: PersonNameComponents
        let ownedIdentity: PersistedObvOwnedIdentity.Structure
        
        private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedObvContactIdentity.Structure")

        // Hashable and equatable
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(typedObjectID)
        }
        
        static func == (lhs: Structure, rhs: Structure) -> Bool {
            lhs.typedObjectID == rhs.typedObjectID
        }

        // Siri and Intent integration

        var personHandle: INPersonHandle {
            INPersonHandle(value: typedObjectID.objectID.uriRepresentation().absoluteString, type: .unknown)
        }

        @available(iOS 15.0, *)
        func createINImage(storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INImage? {

            let pngData: Data?
            if let url = displayPhotoURL,
               let cgImage = UIImage(contentsOfFile: url.path)?.cgImage?.downsizeToSize(CGSize(width: thumbnailSide, height: thumbnailSide)),
               let _pngData = UIImage(cgImage: cgImage).pngData() {
                pngData = _pngData
            } else {
                let fillColor = cryptoId.colors.background
                let characterColor = cryptoId.colors.text
                pngData = UIImage.makeCircledCharacter(fromString: fullDisplayName,
                                                       circleDiameter: thumbnailSide,
                                                       fillColor: fillColor,
                                                       characterColor: characterColor)?.pngData()
            }
            
            let image: INImage?
            if let pngData = pngData {
                if let thumbnailURL = thumbnailURL {
                    do {
                        try pngData.write(to: thumbnailURL)
                        image = INImage(url: thumbnailURL)
                    } catch {
                        os_log("Could not create PNG thumbnail file for contact", log: log, type: .fault)
                        image = INImage(imageData: pngData)
                    }
                } else {
                    image = INImage(imageData: pngData)
                }
            } else {
                image = nil
            }
            return image
        }

        @available(iOS 15.0, *)
        func createINPerson(storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INPerson {

            let image = createINImage(storingPNGPhotoThumbnailAtURL: thumbnailURL, thumbnailSide: thumbnailSide)
            
            return INPerson(personHandle: personHandle,
                            nameComponents: personNameComponents,
                            displayName: customOrFullDisplayName,
                            image: image,
                            contactIdentifier: nil,
                            customIdentifier: typedObjectID.objectID.uriRepresentation().absoluteString,
                            isMe: false,
                            suggestionType: .none)
        }

    }
    
    func toStruct() throws -> Structure {
        guard let ownedIdentity = self.ownedIdentity else {
            throw Self.makeError(message: "Could not extract required relationships")
        }
        return Structure(typedObjectID: self.typedObjectID,
                         cryptoId: self.cryptoId,
                         fullDisplayName: self.fullDisplayName,
                         customOrFullDisplayName: self.customOrFullDisplayName,
                         displayPhotoURL: self.displayPhotoURL,
                         personNameComponents: self.personNameComponents,
                         ownedIdentity: try ownedIdentity.toStruct())
    }
    
}


// MARK: - Sending notifications on change

extension PersistedObvContactIdentity {
    
    override func willSave() {
        super.willSave()
        
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
        
    }
    
    override func didSave() {
        super.didSave()
        
        defer {
            changedKeys.removeAll()
        }
        
        if isInserted {
            
            let notification = ObvMessengerCoreDataNotification.persistedContactWasInserted(objectID: objectID, contactCryptoId: cryptoId)
            notification.postOnDispatchQueue()

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
                let typedObjectID = self.typedObjectID
                DispatchQueue.main.async {
                    // We refresh the object in the view context (if it exists) prior sending the notification
                    if let contact = try? ObvStack.shared.viewContext.existingObject(with: typedObjectID.objectID) as? PersistedObvContactIdentity {
                        ObvStack.shared.viewContext.refresh(contact, mergeChanges: true)
                    }
                    ObvMessengerCoreDataNotification.persistedContactIsActiveChanged(contactID: typedObjectID)
                        .postOnDispatchQueue()
                }
            }

            // Since the discussion title depends on both the custom name and the full display name of the contact, we send an appropriate notification if one of two changed.
            if changedKeys.contains(Predicate.Key.customDisplayName.rawValue) || changedKeys.contains(Predicate.Key.fullDisplayName.rawValue) {
                guard let ownedIdentityObjectID = self.ownedIdentity?.typedObjectID else { return }
                ObvMessengerCoreDataNotification.aOneToOneDiscussionTitleNeedsToBeReset(ownedIdentityObjectID: ownedIdentityObjectID)
                    .postOnDispatchQueue()
            }
            
            // Last but not least, if the one2one discussion with this contact is loaded in the view context, we refresh it.
            // This what makes it possible, e.g., to see the contact profile picture in the discussion list as soon as possible
            do {
                if let oneToOneDiscussionObjectID = self.oneToOneDiscussion?.typedObjectID {
                    DispatchQueue.main.async {
                        guard let contact = ObvStack.shared.viewContext.registeredObject(for: self.objectID) as? PersistedObvContactIdentity else { return }
                        ObvStack.shared.viewContext.refresh(contact, mergeChanges: true)
                        guard let oneToOneDiscussion = ObvStack.shared.viewContext.registeredObject(for: oneToOneDiscussionObjectID.objectID) as? PersistedOneToOneDiscussion else { return }
                        ObvStack.shared.viewContext.refresh(oneToOneDiscussion, mergeChanges: true)
                    }
                }
            }

        }
    }
    
}
