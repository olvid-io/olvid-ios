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
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
import OlvidUtils


@objc(ContactGroupDetails)
class ContactGroupDetails: NSManagedObject {
    
    // MARK: - Internal constants
    
    static weak var delegateManager: ObvIdentityDelegateManager?

    private static let entityName = "ContactGroupDetails"

    private static func makeError(message: String) -> Error { NSError(domain: String(describing: ContactGroupDetails.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactGroupDetails.logSubsystem, category: "ContactGroupDetails") }()

    // MARK: - Attributes
    
    @NSManaged private var photoServerKeyEncoded: Data?
    @NSManaged private(set) var rawPhotoServerLabel: Data?
    @NSManaged private var photoFilename: String?
    @NSManaged private var serializedCoreDetails: Data
    @NSManaged private(set) var version: Int

    // MARK: - Relationships
    
    // MARK: - Computed variables
    
    private(set) var photoServerLabel: UID? {
        get {
            guard let rawPhotoServerLabel = rawPhotoServerLabel else { return nil }
            guard let uid = UID(uid: rawPhotoServerLabel) else { assertionFailure(); return nil }
            return uid
        }
        set {
            self.rawPhotoServerLabel = newValue?.raw
        }
    }
    
    var photoServerKeyAndLabel: PhotoServerKeyAndLabel? {
        get {
            guard let photoServerKeyEncoded = self.photoServerKeyEncoded else { return nil }
            guard let obvEncoded = ObvEncoded(withRawData: photoServerKeyEncoded) else { return nil }
            guard let key = try? AuthenticatedEncryptionKeyDecoder.decode(obvEncoded) else { assertionFailure(); return nil }
            guard let label = photoServerLabel else { return nil }
            return PhotoServerKeyAndLabel(key: key, label: label)
        }
        set {
            self.photoServerKeyEncoded = newValue?.key.obvEncode().rawData
            self.photoServerLabel = newValue?.label
        }
    }
    
    // MARK: - Other properties
    
    private var photoURLsToDeleteOnDidSave = Set<URL>()

    private var changedKeys = Set<String>()

    func getPhotoURL() throws -> URL? {
        guard let url = try getRawPhotoURL() else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            assertionFailure()
            return nil
        }
        return url
    }
    
    
    private func getRawPhotoURL() throws -> URL? {
        guard let identityPhotosDirectory = Self.delegateManager?.identityPhotosDirectory else {
            assertionFailure()
            throw ObvIdentityManagerError.delegateManagerIsNotSet
        }
        guard let photoFilename else { return nil }
        let url = identityPhotosDirectory.appendingPathComponent(photoFilename)
        return url
    }

}


// MARK: - Initializer and deleting

extension ContactGroupDetails {
    
    convenience init(groupDetailsElementsWithPhoto: GroupDetailsElementsWithPhoto, forEntityName entityName: String, within context: NSManagedObjectContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.photoServerKeyAndLabel = groupDetailsElementsWithPhoto.photoServerKeyAndLabel
        try setGroupPhoto(with: groupDetailsElementsWithPhoto.photoURL)
        self.serializedCoreDetails = try groupDetailsElementsWithPhoto.coreDetails.jsonEncode()
        self.version = groupDetailsElementsWithPhoto.version
    }

    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(backupItem: ContactGroupDetailsBackupItem, forEntityName entityName: String, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        if let photoServerKeyEncodedRaw = backupItem.photoServerKeyEncoded,
           let photoServerKeyEncoded = ObvEncoded(withRawData: photoServerKeyEncodedRaw),
           let label = backupItem.photoServerLabel,
           let key = try? AuthenticatedEncryptionKeyDecoder.decode(photoServerKeyEncoded) {
            self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: label)
        } else {
            self.photoServerKeyAndLabel = nil
        }
        self.photoFilename = nil // It is ok not to call setPhotoURL(...) here
        self.serializedCoreDetails = backupItem.serializedCoreDetails
        self.version = backupItem.version
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    convenience init(snapshotNode: ContactGroupDetailsSyncSnapshotNode, forEntityName entityName: String, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        if let photoServerKeyEncodedRaw = snapshotNode.photoServerKeyEncoded,
           let photoServerKeyEncoded = ObvEncoded(withRawData: photoServerKeyEncodedRaw),
           let label = snapshotNode.photoServerLabel,
           let key = try? AuthenticatedEncryptionKeyDecoder.decode(photoServerKeyEncoded) {
            self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: label)
        } else {
            self.photoServerKeyAndLabel = nil
        }
        self.photoFilename = nil // It is ok not to call setPhotoURL(...) here
        self.serializedCoreDetails = snapshotNode.serializedCoreDetails
        self.version = snapshotNode.version
    }
    
    func delete() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvIdentityManagerError.contextIsNil
        }
        context.delete(self)
        do {
            if let currentPhotoURL = try self.getPhotoURL() {
                photoURLsToDeleteOnDidSave.insert(currentPhotoURL)
            }
        } catch {
            assertionFailure() // Continue anyway
        }
    }

}

// MARK: - Setting the photo and the server key/label

extension ContactGroupDetails {

    func setGroupPhoto(with newPhotoURL: URL?) throws {
        
        guard let identityPhotosDirectory = Self.delegateManager?.identityPhotosDirectory else {
            assertionFailure()
            throw ObvIdentityManagerError.delegateManagerIsNotSet
        }
        
        let currentPhotoURL = try getPhotoURL() // Can be nil
        
        guard currentPhotoURL != newPhotoURL else { return }

        if let currentPhotoURL = currentPhotoURL, let newPhotoURL = newPhotoURL {
            guard !FileManager.default.contentsEqual(atPath: currentPhotoURL.path, andPath: newPhotoURL.path) else {
                return
            }
        }

        // Whatever the new photo URL, we delete the previous version if there is one.
        if let currentPhotoURL = currentPhotoURL {
            if FileManager.default.fileExists(atPath: currentPhotoURL.path) {
                try FileManager.default.removeItem(at: currentPhotoURL)
            }
            self.photoFilename = nil
        }

        assert((try? getPhotoURL()) == nil)

        // If there is a new photo URL, we create a fresh new hard link to it.
        // Creating a hard link prevents the deletion of a photo referenced by another ContactGroupDetails instance.
        if let newPhotoURL = newPhotoURL {
            assert(FileManager.default.fileExists(atPath: newPhotoURL.path))
            guard let newPhotoURLInEngine = freshPath(in: identityPhotosDirectory) else { assertionFailure(); throw makeError(message: "Could not get fresh path for photo") }
            do {
                try FileManager.default.linkItem(at: newPhotoURL, to: newPhotoURLInEngine)
            } catch {
                assertionFailure()
                debugPrint(error.localizedDescription)
                throw error
            }
            self.photoFilename = newPhotoURLInEngine.lastPathComponent
        }

    }
    
    
    func setGroupPhoto(data: Data) throws {
        guard let identityPhotosDirectory = Self.delegateManager?.identityPhotosDirectory else {
            assertionFailure()
            throw ObvIdentityManagerError.delegateManagerIsNotSet
        }
        guard let photoURLInEngine = freshPath(in: identityPhotosDirectory) else { throw makeError(message: "Could not get fresh path for photo") }
        try data.write(to: photoURLInEngine)
        try setGroupPhoto(with: photoURLInEngine)
        try FileManager.default.removeItem(at: photoURLInEngine) // The previous call created another hard link so we can delete the file we just created
    }
    

    private func freshPath(in directory: URL) -> URL? {
        guard directory.hasDirectoryPath else { assertionFailure(); return nil }
        var path: URL?
        repeat {
            let uuid = UUID().uuidString
            path = directory.appendingPathComponent(uuid)
        } while (FileManager.default.fileExists(atPath: path!.path))
        return path
    }

    
}


// MARK: - Convenience methods

extension ContactGroupDetails {

    func getGroupDetailsElements() throws -> GroupDetailsElements {
        let coreDetails = try ObvGroupCoreDetails(serializedCoreDetails)
        return GroupDetailsElements(version: version, coreDetails: coreDetails, photoServerKeyAndLabel: photoServerKeyAndLabel)
    }

    func getGroupDetailsElementsWithPhoto() throws -> GroupDetailsElementsWithPhoto {
        let groupDetailsElements = try getGroupDetailsElements()
        let photoURL = try getPhotoURL()
        return GroupDetailsElementsWithPhoto(groupDetailsElements: groupDetailsElements, photoURL: photoURL)
    }
 
    func getContactGroup() throws -> ContactGroup {
        if let latest = self as? ContactGroupDetailsLatest {
            return latest.contactGroupOwned
        } else if let trusted = self as? ContactGroupDetailsTrusted {
            return trusted.contactGroupJoined
        } else if let published = self as? ContactGroupDetailsPublished {
            return published.contactGroup
        } else {
            throw makeError(message: "Unknown ContactGroupDetails subclass. This is a bug.")
        }
    }
}

// MARK: - Convenience DB getters

extension ContactGroupDetails {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactGroupDetails> {
        return NSFetchRequest<ContactGroupDetails>(entityName: ContactGroupDetails.entityName)
    }

    struct Predicate {
        enum Key: String {
            case photoFilename = "photoFilename"
            case photoServerKeyEncoded = "photoServerKeyEncoded"
            case rawPhotoServerLabel = "rawPhotoServerLabel"
        }
        static var withoutPhotoFilename: NSPredicate {
            NSPredicate(withNilValueForKey: Key.photoFilename)
        }
        static var withPhotoFilename: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.photoFilename)
        }
        static var withPhotoServerKey: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.photoServerKeyEncoded)
        }
        static var withPhotoServerLabel: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.rawPhotoServerLabel)
        }
        static var withPhotoServerKeyAndLabel: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withPhotoServerKey,
                withPhotoServerLabel,
            ])
        }
    }
    
    
    static func getInfosAboutGroupsHavingPhotoFilename(within context: NSManagedObjectContext) throws -> [(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation, photoURL: URL)] {
        let request: NSFetchRequest<ContactGroupDetails> = ContactGroupDetails.fetchRequest()
        request.predicate = Predicate.withPhotoFilename
        let items = try context.fetch(request)
        let results: [(ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation, photoURL: URL)] = try items.compactMap { details in
            
            guard let photoURL = try details.getRawPhotoURL(),
                  let contactGroup = try? details.getContactGroup(),
                  let coreDetails = try? ObvGroupCoreDetails(details.serializedCoreDetails),
                  let photoServerKeyAndLabel = details.photoServerKeyAndLabel else {
                return nil
            }

            guard let ownedIdentity = try? contactGroup.ownedIdentity.cryptoIdentity else {
                assertionFailure()
                return nil
            }

            let groupDetailsElements = GroupDetailsElements(
                version: details.version,
                coreDetails: coreDetails,
                photoServerKeyAndLabel: photoServerKeyAndLabel)
            
            if let contactGroupOwned = contactGroup as? ContactGroupOwned {
                
                guard let groupInformation = try? GroupInformation(
                    groupOwnerIdentity: contactGroupOwned.ownedIdentity.cryptoIdentity,
                    groupUid: contactGroupOwned.groupUid,
                    groupDetailsElements: groupDetailsElements) else {
                    return nil
                }
                return (ownedIdentity, groupInformation, photoURL)
                
            } else if let contactGroupJoined = contactGroup as? ContactGroupJoined {
                
                guard let groupOwnerIdentity = contactGroupJoined.groupOwner.cryptoIdentity else { return nil }
                guard let groupInformation = try? GroupInformation(
                    groupOwnerIdentity: groupOwnerIdentity,
                    groupUid: contactGroupJoined.groupUid,
                    groupDetailsElements: groupDetailsElements) else {
                    return nil
                }
                return (ownedIdentity, groupInformation, photoURL)
                
            } else {
                assertionFailure()
                return nil
            }
        }
        return results
    }


    static func getAllPhotoURLs(within context: NSManagedObjectContext) throws -> Set<URL> {
        let request: NSFetchRequest<ContactGroupDetails> = ContactGroupDetails.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.photoFilename.rawValue]
        let details = try context.fetch(request)
        let photoURLs = try Set(details.compactMap({ try $0.getPhotoURL() }))
        return photoURLs
    }
    
    static func getAllWithMissingPhotoURL(within context: NSManagedObjectContext) throws -> [ContactGroupDetails] {
        let request: NSFetchRequest<ContactGroupDetails> = ContactGroupDetails.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withoutPhotoFilename,
            Predicate.withPhotoServerKeyAndLabel,
        ])
        let items = try context.fetch(request)
        return items
    }

}


// MARK: - On save

extension ContactGroupDetails {
    
    override func willSave() {
        super.willSave()
        changedKeys = Set<String>(self.changedValues().keys)
    }

    override func didSave() {
        super.didSave()
        
        defer {
            photoURLsToDeleteOnDidSave.removeAll()
            changedKeys.removeAll()
        }
        
        for photoURLToDeleteOnDidSave in self.photoURLsToDeleteOnDidSave {
            if FileManager.default.fileExists(atPath: photoURLToDeleteOnDidSave.path) {
                try? FileManager.default.removeItem(at: photoURLToDeleteOnDidSave)
            }
        }
        
        if !isDeleted {
            
            guard let delegateManager = Self.delegateManager else {
                assertionFailure()
                return
            }
            
            if changedKeys.contains(Predicate.Key.photoFilename.rawValue) {
                
                // Notify that the photo URL did change
                
                do {
                    if let latestDetails = self as? ContactGroupDetailsLatest {
                        ObvIdentityNotificationNew.latestPhotoOfContactGroupOwnedHasBeenUpdated(
                            groupUid: try latestDetails.contactGroupOwned.groupUid,
                            ownedIdentity: try latestDetails.contactGroupOwned.ownedIdentity.cryptoIdentity)
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                    } else if let trustedDetails = self as? ContactGroupDetailsTrusted, let groupOwner = trustedDetails.contactGroupJoined.groupOwner.cryptoIdentity {
                        ObvIdentityNotificationNew.trustedPhotoOfContactGroupJoinedHasBeenUpdated(
                            groupUid: try trustedDetails.contactGroupJoined.groupUid,
                            ownedIdentity: try trustedDetails.contactGroupJoined.ownedIdentity.cryptoIdentity,
                            groupOwner: groupOwner)
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                    } else if let publishedDetails = self as? ContactGroupDetailsPublished {
                        if let ownedGroup = publishedDetails.contactGroup as? ContactGroupOwned {
                            ObvIdentityNotificationNew.publishedPhotoOfContactGroupOwnedHasBeenUpdated(
                                groupUid: try ownedGroup.groupUid,
                                ownedIdentity: try ownedGroup.ownedIdentity.cryptoIdentity)
                            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                        } else if let joinedGroup = publishedDetails.contactGroup as? ContactGroupJoined, let groupOwner = joinedGroup.groupOwner.cryptoIdentity {
                            ObvIdentityNotificationNew.publishedPhotoOfContactGroupJoinedHasBeenUpdated(
                                groupUid: try joinedGroup.groupUid,
                                ownedIdentity: try joinedGroup.ownedIdentity.cryptoIdentity,
                                groupOwner: groupOwner)
                            .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                        } else {
                            assertionFailure()
                        }
                    } else {
                        assertionFailure()
                    }
                } catch {
                    assertionFailure(error.localizedDescription)
                }

                
            }
            
        }
        
    }
    
}


// MARK: - For Backup purposes

extension ContactGroupDetails {
    
    var backupItem: ContactGroupDetailsBackupItem {
        return ContactGroupDetailsBackupItem(photoServerKeyEncoded: photoServerKeyEncoded,
                                             photoServerLabel: photoServerLabel,
                                             serializedCoreDetails: serializedCoreDetails,
                                             version: version)
    }

}

struct ContactGroupDetailsBackupItem: Codable, Hashable {
    
    fileprivate let photoServerKeyEncoded: Data?
    fileprivate let photoServerLabel: UID?
    fileprivate let serializedCoreDetails: Data
    fileprivate let version: Int

    // The following private type allows to "specialize" a ContactGroupDetailsBackupItem instance before it is associated to an instance of NSManagedObject. This is required because the association does not allow duplicates (i.e., two identical ContactGroupDetailsBackupItem), and we sometimes have identical trusted and published details).
    private let transientUuid = UUID()
    
    private static let errorDomain = String(describing: Self.self)
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(photoServerKeyEncoded: Data?, photoServerLabel: UID?, serializedCoreDetails: Data, version: Int) {
        self.photoServerKeyEncoded = photoServerKeyEncoded
        self.photoServerLabel = photoServerLabel
        self.serializedCoreDetails = serializedCoreDetails
        self.version = version
    }
    
    /// This method allows to duplicate a ContactGroupDetailsBackupItem, with a distinct `transientUuid`.
    /// This is used to use trusted details to populate published details.
    func duplicate() -> ContactGroupDetailsBackupItem {
        return ContactGroupDetailsBackupItem(photoServerKeyEncoded: photoServerKeyEncoded,
                                             photoServerLabel: photoServerLabel,
                                             serializedCoreDetails: serializedCoreDetails,
                                             version: version)
    }
 
    enum CodingKeys: String, CodingKey {
        case photoServerKeyEncoded = "photo_server_key"
        case photoServerLabel = "photo_server_label"
        case serializedCoreDetails = "serialized_details"
        case version = "version"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(photoServerKeyEncoded, forKey: .photoServerKeyEncoded)
        try container.encodeIfPresent(photoServerLabel?.raw, forKey: .photoServerLabel)
        guard let serializedCoreDetailsAsString = String(data: serializedCoreDetails, encoding: .utf8) else {
            throw ContactGroupDetailsBackupItem.makeError(message: "Could not represent serializedCoreDetails as String")
        }
        try container.encode(serializedCoreDetailsAsString, forKey: .serializedCoreDetails)
        try container.encode(version, forKey: .version)
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        if values.allKeys.contains(.photoServerLabel) && values.allKeys.contains(.photoServerKeyEncoded) {
            do {
                self.photoServerKeyEncoded = try values.decode(Data.self, forKey: .photoServerKeyEncoded)
                if let photoServerLabelAsData = try? values.decodeIfPresent(Data.self, forKey: .photoServerLabel),
                   let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    // Expected
                    self.photoServerLabel = photoServerLabelAsUID
                } else if let photoServerLabelAsUID = try values.decodeIfPresent(UID.self, forKey: .photoServerLabel) {
                    assertionFailure()
                    self.photoServerLabel = photoServerLabelAsUID
                } else if let photoServerLabelAsString = try? values.decode(String.self, forKey: .photoServerLabel),
                          let photoServerLabelAsData = Data(base64Encoded: photoServerLabelAsString),
                          let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    assertionFailure()
                    self.photoServerLabel = photoServerLabelAsUID
                } else if let photoServerLabelAsString = try? values.decode(String.self, forKey: .photoServerLabel),
                          let photoServerLabelAsData = Data(hexString: photoServerLabelAsString),
                          let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    assertionFailure()
                    self.photoServerLabel = photoServerLabelAsUID
                } else {
                    throw Self.makeError(message: "Could not decode photoServerLabel in the decoder of OwnedIdentityDetailsPublishedBackupItem")
                }
            } catch {
                assertionFailure()
                throw error
            }
        } else {
            self.photoServerKeyEncoded = nil
            self.photoServerLabel = nil
        }

        let serializedCoreDetailsAsString = try values.decode(String.self, forKey: .serializedCoreDetails)
        guard let serializedCoreDetailsAsData = serializedCoreDetailsAsString.data(using: .utf8) else {
            throw ContactGroupDetailsBackupItem.makeError(message: "Could not represent serializedCoreDetails as Data")
        }
        self.serializedCoreDetails = serializedCoreDetailsAsData
        self.version = try values.decode(Int.self, forKey: .version)
    }

    func restoreContactGroupDetailsLatestInstance(within context: NSManagedObjectContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupDetailsLatest = ContactGroupDetailsLatest(backupItem: self, within: context)
        try associations.associate(contactGroupDetailsLatest, to: self)
    }
    
    func restoreContactGroupDetailsPublishedInstance(within context: NSManagedObjectContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupDetailsPublished = ContactGroupDetailsPublished(backupItem: self, with: context)
        try associations.associate(contactGroupDetailsPublished, to: self)
    }

    func restoreContactGroupDetailsTrustedInstance(within context: NSManagedObjectContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupDetailsTrusted = ContactGroupDetailsTrusted(backupItem: self, within: context)
        try associations.associate(contactGroupDetailsTrusted, to: self)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within context: NSManagedObjectContext) throws {
        // Nothing to do
    }

}


// MARK: - For Snapshot purposes

extension ContactGroupDetails {
    
    var syncSnapshot: ContactGroupDetailsSyncSnapshotNode {
        return .init(photoServerKeyEncoded: photoServerKeyEncoded,
                     photoServerLabel: photoServerLabel,
                     serializedCoreDetails: serializedCoreDetails,
                     version: version)
    }

}


struct ContactGroupDetailsSyncSnapshotNode: ObvSyncSnapshotNode {
    
    fileprivate let version: Int
    fileprivate let serializedCoreDetails: Data
    fileprivate let photoServerLabel: UID?
    fileprivate let photoServerKeyEncoded: Data?
    private let domain: Set<CodingKeys>
    
    let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case photoServerKeyEncoded = "photo_server_key"
        case photoServerLabel = "photo_server_label"
        case serializedCoreDetails = "serialized_details"
        case version = "version"
        case domain = "domain"
    }

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    
    fileprivate init(photoServerKeyEncoded: Data?, photoServerLabel: UID?, serializedCoreDetails: Data, version: Int) {
        self.photoServerKeyEncoded = photoServerKeyEncoded
        self.photoServerLabel = photoServerLabel
        self.serializedCoreDetails = serializedCoreDetails
        self.version = version
        self.domain = Self.defaultDomain
    }
    
    
    /// Sometimes, we use (e.g.) published snapshoted details to create published details *and* trusted details. In that case, we want two distinct nodes (different ids), but with identical other values.
    /// This method allows to create such a copy.
    func copyWithNewId() -> ContactGroupDetailsSyncSnapshotNode {
        .init(photoServerKeyEncoded: photoServerKeyEncoded,
              photoServerLabel: photoServerLabel,
              serializedCoreDetails: serializedCoreDetails,
              version: version)
    }
    

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(photoServerKeyEncoded, forKey: .photoServerKeyEncoded)
        try container.encodeIfPresent(photoServerLabel?.raw, forKey: .photoServerLabel)
        guard let serializedCoreDetailsAsString = String(data: serializedCoreDetails, encoding: .utf8) else {
            throw ObvError.couldNotRepresentSerializedCoreDetailsAsString
        }
        try container.encode(serializedCoreDetailsAsString, forKey: .serializedCoreDetails)
        try container.encode(version, forKey: .version)
        try container.encode(domain, forKey: .domain)
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)

        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))

        guard domain.contains(.version) && domain.contains(.serializedCoreDetails) else {
            assertionFailure()
            throw ObvError.tryingToRestoreIncompleteSnapshot
        }
        
        if domain.contains(.photoServerLabel) && domain.contains(.photoServerKeyEncoded) && values.allKeys.contains(.photoServerLabel) && values.allKeys.contains(.photoServerKeyEncoded) {
            do {
                self.photoServerKeyEncoded = try values.decode(Data.self, forKey: .photoServerKeyEncoded)
                if let photoServerLabelAsData = try? values.decodeIfPresent(Data.self, forKey: .photoServerLabel),
                   let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    // Expected
                    self.photoServerLabel = photoServerLabelAsUID
                } else if let photoServerLabelAsUID = try values.decodeIfPresent(UID.self, forKey: .photoServerLabel) {
                    assertionFailure()
                    self.photoServerLabel = photoServerLabelAsUID
                } else if let photoServerLabelAsString = try? values.decode(String.self, forKey: .photoServerLabel),
                          let photoServerLabelAsData = Data(base64Encoded: photoServerLabelAsString),
                          let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    assertionFailure()
                    self.photoServerLabel = photoServerLabelAsUID
                } else if let photoServerLabelAsString = try? values.decode(String.self, forKey: .photoServerLabel),
                          let photoServerLabelAsData = Data(hexString: photoServerLabelAsString),
                          let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    assertionFailure()
                    self.photoServerLabel = photoServerLabelAsUID
                } else {
                    assertionFailure()
                    throw ObvError.couldNotDecodePhotoServerLabel
                }
            } catch {
                assertionFailure()
                throw error
            }
        } else {
            self.photoServerKeyEncoded = nil
            self.photoServerLabel = nil
        }

        let serializedCoreDetailsAsString = try values.decode(String.self, forKey: .serializedCoreDetails)
        guard let serializedCoreDetailsAsData = serializedCoreDetailsAsString.data(using: .utf8) else {
            throw ObvError.couldNotRepresentSerializedCoreDetailsAsData
        }
        self.serializedCoreDetails = serializedCoreDetailsAsData
        self.version = try values.decode(Int.self, forKey: .version)
    }

    
    func restoreContactGroupDetailsLatestInstance(within context: NSManagedObjectContext, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        let contactGroupDetailsLatest = ContactGroupDetailsLatest(snapshotNode: self, within: context)
        try associations.associate(contactGroupDetailsLatest, to: self)
    }
    
    
    func restoreContactGroupDetailsPublishedInstance(within context: NSManagedObjectContext, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        let contactGroupDetailsPublished = ContactGroupDetailsPublished(snapshotNode: self, with: context)
        try associations.associate(contactGroupDetailsPublished, to: self)
    }

    
    func restoreContactGroupDetailsTrustedInstance(within context: NSManagedObjectContext, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        let contactGroupDetailsTrusted = ContactGroupDetailsTrusted(snapshotNode: self, within: context)
        try associations.associate(contactGroupDetailsTrusted, to: self)
    }

    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within context: NSManagedObjectContext) throws {
        // Nothing to do
    }

    
    enum ObvError: Error {
        case couldNotRepresentSerializedCoreDetailsAsString
        case tryingToRestoreIncompleteSnapshot
        case couldNotDecodePhotoServerLabel
        case couldNotRepresentSerializedCoreDetailsAsData
    }
    
}
