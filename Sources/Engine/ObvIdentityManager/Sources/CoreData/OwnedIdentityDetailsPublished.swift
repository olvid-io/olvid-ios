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


@objc(OwnedIdentityDetailsPublished)
final class OwnedIdentityDetailsPublished: NSManagedObject {
    
    // MARK: Internal constants
    
    static weak var delegateManager: ObvIdentityDelegateManager?
    
    private static let entityName = "OwnedIdentityDetailsPublished"
    
    private static let errorDomain = String(describing: OwnedIdentityDetailsPublished.self)
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: OwnedIdentityDetailsPublished.logSubsystem, category: "OwnedIdentityDetailsPublished") }()

    // MARK: Attributes
    
    @NSManaged private var photoFilename: String?
    @NSManaged private var photoServerKeyEncoded: Data?
    @NSManaged private var rawPhotoServerLabel: Data?
    @NSManaged private(set) var serializedIdentityCoreDetails: Data
    @NSManaged private(set) var version: Int

    // MARK: Relationships
    
    // Expected to be non nil, except when the owned identity gets deleted
    @NSManaged private(set) var ownedIdentity: OwnedIdentity?
    
    // MARK: Other variables
    
    private var notificationRelatedChanges: NotificationRelatedChanges = []
    private var labelToDelete: UID?
    private var photoURLsToDeleteOnDidSave = Set<URL>()

    private var changedKeys = Set<String>()

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
    
    func getPhotoURL() throws -> URL? {
        guard let url = try getRawPhotoURL() else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else { assertionFailure(); return nil }
        return url
    }

    private func getRawPhotoURL() throws -> URL? {
        guard let identityPhotosDirectory = Self.delegateManager?.identityPhotosDirectory else {
            assertionFailure()
            throw ObvIdentityManagerError.delegateManagerIsNotSet
        }
        guard let photoFilename = photoFilename else { return nil }
        let url = identityPhotosDirectory.appendingPathComponent(photoFilename)
        return url
    }

    private var ownedCryptoIdOnDeletion: ObvCryptoIdentity?

    var photoServerKeyAndLabel: PhotoServerKeyAndLabel? {
        guard let photoServerKeyEncoded = self.photoServerKeyEncoded,
              let obvEncoded = ObvEncoded(withRawData: photoServerKeyEncoded),
              let key = try? AuthenticatedEncryptionKeyDecoder.decode(obvEncoded),
              let label = photoServerLabel else {
            return nil
        }
        return PhotoServerKeyAndLabel(key: key, label: label)
    }
    
    func getIdentityDetails() throws -> ObvIdentityDetails {
        let data = kvoSafePrimitiveValue(forKey: Predicate.Key.serializedIdentityCoreDetails.rawValue) as! Data
        let coreDetails = try! ObvIdentityCoreDetails(data)
        let photoURL = try getPhotoURL()
        return ObvIdentityDetails(coreDetails: coreDetails, photoURL: photoURL)
    }
    
    var coreDetails: ObvIdentityCoreDetails {
        get throws {
            let data = kvoSafePrimitiveValue(forKey: Predicate.Key.serializedIdentityCoreDetails.rawValue) as! Data
            return try ObvIdentityCoreDetails(data)
        }
    }

    func getIdentityDetailsElements() throws -> IdentityDetailsElements {
        let coreDetails = try getIdentityDetails().coreDetails
        return IdentityDetailsElements(version: version, coreDetails: coreDetails, photoServerKeyAndLabel: photoServerKeyAndLabel)
    }
    
    // MARK: - Initializer
    
    convenience init?(ownedIdentity: OwnedIdentity, identityDetails: ObvIdentityDetails, version: Int) {
        
        guard let context = ownedIdentity.managedObjectContext else { return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentityDetailsPublished.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        self.ownedIdentity = ownedIdentity
        
        do {
            _ = try setOwnedIdentityPhoto(with: identityDetails.photoURL)
        } catch {
            return nil
        }
        do { self.serializedIdentityCoreDetails = try identityDetails.coreDetails.jsonEncode() } catch { return nil }
        self.version = version
        self.photoServerKeyEncoded = nil
        self.photoServerLabel = nil
        
    }

    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: OwnedIdentityDetailsPublishedBackupItem, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentityDetailsPublished.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.photoServerKeyEncoded = backupItem.photoServerKeyEncoded
        self.photoServerLabel = backupItem.photoServerLabel
        self.photoFilename = nil // This is ok
        self.serializedIdentityCoreDetails = backupItem.serializedIdentityCoreDetails
        self.version = backupItem.version
    }
    
    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(snapshotNode: OwnedIdentityDetailsPublishedSyncSnapshotNode, within context: NSManagedObjectContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentityDetailsPublished.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.photoServerKeyEncoded = snapshotNode.photoServerKeyEncoded
        self.photoServerLabel = snapshotNode.photoServerLabel
        self.photoFilename = nil // This is ok
        guard let serializedIdentityCoreDetails = snapshotNode.serializedIdentityCoreDetails,
              let version = snapshotNode.version else {
            throw OwnedIdentityDetailsPublishedSyncSnapshotNode.ObvError.tryingToRestoreIncompleteSnapshot
        }
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
        self.version = version
    }

    
    func delete(within context: NSManagedObjectContext) throws {
        self.ownedCryptoIdOnDeletion = try? ownedIdentity?.cryptoIdentity
        if let currentPhotoURL = try self.getPhotoURL() {
            photoURLsToDeleteOnDidSave.insert(currentPhotoURL)
        }
        context.delete(self)
    }

    
    func setOwnedIdentityPhoto(data: Data) throws {
        guard let identityPhotosDirectory = Self.delegateManager?.identityPhotosDirectory else {
            assertionFailure()
            throw ObvIdentityManagerError.delegateManagerIsNotSet
        }
        guard let photoURLInEngine = freshPath(in: identityPhotosDirectory) else { throw makeError(message: "Could not get fresh path for photo") }
        try data.write(to: photoURLInEngine)
        _ = try setOwnedIdentityPhoto(with: photoURLInEngine)
        try FileManager.default.removeItem(at: photoURLInEngine) // The previous call created another hard link so we can delete the file we just created
    }

    
    private func setOwnedIdentityPhoto(with newPhotoURL: URL?) throws -> Bool {
        
        guard let identityPhotosDirectory = Self.delegateManager?.identityPhotosDirectory else {
            assertionFailure()
            throw ObvIdentityManagerError.delegateManagerIsNotSet
        }

        let currentPhotoURL = try getPhotoURL() // Can be nil

        guard currentPhotoURL != newPhotoURL else { return false }
        
        if let currentPhotoURL = currentPhotoURL, let newPhotoURL = newPhotoURL {
            guard !FileManager.default.contentsEqual(atPath: currentPhotoURL.path, andPath: newPhotoURL.path) else {
                return false
            }
        }
        
        // Whatever the new photo URL, we delete the previous version
        if let currentPhotoURL = currentPhotoURL {
            if FileManager.default.fileExists(atPath: currentPhotoURL.path) {
                try FileManager.default.removeItem(at: currentPhotoURL)
            }
            self.photoFilename = nil
        }
        assert((try? getPhotoURL()) == nil)

        // If there is a new photo URL, we move it to the engine if required, or simply make a hard link if it is already within the engine.
        // Creating a hard link prevents the deletion of a photo referenced by another ContactGroupDetails instance.
        if let newPhotoURL = newPhotoURL {
            assert(FileManager.default.fileExists(atPath: newPhotoURL.path))
            guard let newPhotoURLInEngine = freshPath(in: identityPhotosDirectory) else { throw makeError(message: "Could not get fresh path for photo") }
            if newPhotoURL.deletingLastPathComponent() == identityPhotosDirectory {
                try FileManager.default.linkItem(at: newPhotoURL, to: newPhotoURLInEngine)
            } else {
                try FileManager.default.moveItem(at: newPhotoURL, to: newPhotoURLInEngine)
            }
            self.photoFilename = newPhotoURLInEngine.lastPathComponent
        }
        
        return true
        
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
    
    
    // MARK: - Observers

    private static var observersHolder = ObserversHolder()

    static func addObvObserver(_ newObserver: OwnedIdentityDetailsPublishedObServer) async {
        await observersHolder.addObserver(newObserver)
    }

}


// MARK: - Publishing new details

extension OwnedIdentityDetailsPublished {
    
    private struct NotificationRelatedChanges: OptionSet {
        let rawValue: UInt8
        static let photoServerLabel = NotificationRelatedChanges(rawValue: 1 << 1)
    }
    

    func updateWithNewIdentityDetails(_ newIdentityDetails: ObvIdentityDetails) throws {
        var detailsWereUpdated = false
        let currentCoreDetails = try self.getIdentityDetails().coreDetails
        let newCoreDetails = newIdentityDetails.coreDetails
        if newCoreDetails != currentCoreDetails {
            self.serializedIdentityCoreDetails = try newIdentityDetails.coreDetails.jsonEncode()
            detailsWereUpdated = true
        }
        if try setOwnedIdentityPhoto(with: newIdentityDetails.photoURL) {
            self.photoServerKeyEncoded = nil
            self.labelToDelete = self.photoServerLabel
            notificationRelatedChanges.insert(.photoServerLabel)
            self.photoServerLabel = nil
            detailsWereUpdated = true
        }
        if detailsWereUpdated {
            self.version += 1
        }
    }
    
    
    /// Returns `true` if we need to download a new profile picture
    func updateWithOtherDetailsIfNewer(otherDetails: IdentityDetailsElements) throws -> Bool {
                
        // first, check the received details are newer than our own details
        
        guard otherDetails.version > self.version else {
            return false
        }
        
        // The other details are more recent -> update the current details
        
        let currentCoreDetails = try self.getIdentityDetails().coreDetails
        if otherDetails.coreDetails != currentCoreDetails {
            self.serializedIdentityCoreDetails = try otherDetails.coreDetails.jsonEncode()
        }

        let photoDownloadNeeded: Bool
        if otherDetails.photoServerKeyAndLabel != self.photoServerKeyAndLabel {
            // The current photoServerKeyAndLabel must be discarded
            if let newPhotoServerKeyAndLabel = otherDetails.photoServerKeyAndLabel {
                // We have new photoServerKeyAndLabel. We keep them.
                // We will request a download of the corresponding photo (for now, we keep the old one, it will soon be replaced)
                set(photoServerKeyAndLabel: newPhotoServerKeyAndLabel)
                photoDownloadNeeded = true
            } else {
                // The new photoServerKeyAndLabel are nil, meaning we should remove the current one and remove the photo
                self.photoServerKeyEncoded = nil
                self.labelToDelete = self.photoServerLabel
                notificationRelatedChanges.insert(.photoServerLabel)
                self.photoServerLabel = nil
                _ = try setOwnedIdentityPhoto(with: nil)
                photoDownloadNeeded = false
            }
        } else {
            // The new photoServerKeyAndLabel are identical to the ones we have
            photoDownloadNeeded = false
        }
        
        self.version = otherDetails.version
        
        return photoDownloadNeeded
    }

    
    func set(photoServerKeyAndLabel: PhotoServerKeyAndLabel) {
        self.photoServerKeyEncoded = photoServerKeyAndLabel.key.obvEncode().rawData
        self.labelToDelete = self.photoServerLabel
        notificationRelatedChanges.insert(.photoServerLabel)
        self.photoServerLabel = photoServerKeyAndLabel.label
    }
    
}


// MARK: - Queries

extension OwnedIdentityDetailsPublished {

    @nonobjc class func fetchRequest() -> NSFetchRequest<OwnedIdentityDetailsPublished> {
        return NSFetchRequest<OwnedIdentityDetailsPublished>(entityName: entityName)
    }

    struct Predicate {
        enum Key: String {
            // Attributes
            case photoFilename = "photoFilename"
            case photoServerKeyEncoded = "photoServerKeyEncoded"
            case rawPhotoServerLabel = "rawPhotoServerLabel"
            case serializedIdentityCoreDetails = "serializedIdentityCoreDetails"
            case version = "version"
            // Relationships
            case ownedIdentity = "ownedIdentity"
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
        static func forOwnedIdentity(ownedIdentity: OwnedIdentity) -> NSPredicate {
            NSPredicate(format: "%K == %@", Key.ownedIdentity.rawValue, ownedIdentity)
        }
    }
    
    
    static func getInfosAboutOwnedIdentitiesHavingPhotoFilename(within context: NSManagedObjectContext) throws -> [(ownedCryptoId: ObvCryptoIdentity, ownedIdentityDetailsElements: IdentityDetailsElements, photoURL: URL)] {
        let request: NSFetchRequest<OwnedIdentityDetailsPublished> = OwnedIdentityDetailsPublished.fetchRequest()
        request.predicate = Predicate.withPhotoFilename
        let items = try context.fetch(request)
        let results: [(ownedCryptoId: ObvCryptoIdentity, ownedIdentityDetailsElements: IdentityDetailsElements, photoURL: URL)] = try items.compactMap { details in
            guard let ownedCryptoId = try details.ownedIdentity?.cryptoIdentity,
                  let photoURL = try details.getRawPhotoURL() else {
                return nil
            }
            let ownedIdentityDetailsElements = try details.getIdentityDetailsElements()
            return (ownedCryptoId, ownedIdentityDetailsElements, photoURL)
        }
        return results
    }

    
    static func getAllWithMissingPhotoFilename(within context: NSManagedObjectContext) throws -> [OwnedIdentityDetailsPublished] {
        let request: NSFetchRequest<OwnedIdentityDetailsPublished> = OwnedIdentityDetailsPublished.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withoutPhotoFilename,
            Predicate.withPhotoServerKeyAndLabel,
        ])
        let items = try context.fetch(request)
        return items
    }
    
    static func getAllPhotoURLs(within context: NSManagedObjectContext) throws -> Set<URL> {
        let request: NSFetchRequest<OwnedIdentityDetailsPublished> = OwnedIdentityDetailsPublished.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.photoFilename.rawValue]
        let details = try context.fetch(request)
        let photoURLs = try Set(details.compactMap({ try $0.getPhotoURL() }))
        return photoURLs
    }
    
    
    static func getAllPhotoServerLabels(ownedIdentity: OwnedIdentity) throws -> Set<UID> {
        guard let context = ownedIdentity.managedObjectContext else { throw makeError(message: "context is not set on owned identity") }
        let request: NSFetchRequest<OwnedIdentityDetailsPublished> = OwnedIdentityDetailsPublished.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPhotoServerLabel,
            Predicate.forOwnedIdentity(ownedIdentity: ownedIdentity),
        ])
        request.propertiesToFetch = [Predicate.Key.rawPhotoServerLabel.rawValue]
        let details = try context.fetch(request)
        let photoServerLabels = Set(details.compactMap({ $0.photoServerLabel }))
        assert(photoServerLabels.count == details.count)
        return photoServerLabels
    }

}


// MARK: - Reacting to changes

extension OwnedIdentityDetailsPublished {

    override func prepareForDeletion() {
        super.prepareForDeletion()
        guard let managedObjectContext else { assertionFailure(); return }
        guard managedObjectContext.concurrencyType != .mainQueueConcurrencyType else { return }
        labelToDelete = self.photoServerLabel
    }
    
    override func willSave() {
        super.willSave()
        if !isInserted {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }

    
    override func didSave() {
        super.didSave()
        
        defer {
            notificationRelatedChanges = []
            changedKeys.removeAll()
            photoURLsToDeleteOnDidSave.removeAll()
        }
        
        for photoURLToDeleteOnDidSave in self.photoURLsToDeleteOnDidSave {
            if FileManager.default.fileExists(atPath: photoURLToDeleteOnDidSave.path) {
                try? FileManager.default.removeItem(at: photoURLToDeleteOnDidSave)
            }
        }
        
        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is not set")
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            Self.logger.fault("The notification delegate is not set")
            return
        }

        if notificationRelatedChanges.contains(.photoServerLabel) || isDeleted {
            if let labelToDelete = self.labelToDelete, let ownedCryptoIdentity = try? self.ownedIdentity?.cryptoIdentity ?? ownedCryptoIdOnDeletion {
                ObvIdentityNotificationNew.serverLabelHasBeenDeleted(ownedIdentity: ownedCryptoIdentity, label: labelToDelete)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            }
        }
        
        if !isDeleted && !isInserted && changedKeys.contains(Predicate.Key.photoFilename.rawValue), let ownedCryptoIdentity = try? self.ownedIdentity?.cryptoIdentity {
            ObvIdentityNotificationNew.publishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: ownedCryptoIdentity)
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
        }

        if !isInserted && !isDeleted, let ownedCryptoIdentity = try? self.ownedIdentity?.cryptoIdentity {
            
            let NotificationType = ObvIdentityNotification.OwnedIdentityDetailsPublicationInProgress.self
            let userInfo = [NotificationType.Key.ownedCryptoIdentity: ownedCryptoIdentity]
            notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            
        }
        
        // Potentially notify that the previous backed up device snapshot is obsolete
        // Other entities can also notify:
        // - OwnedIdentity
        // - KeycloakServer

        let previousBackedUpDeviceSnapShotIsObsolete: Bool
        if isInserted || isDeleted {
            previousBackedUpDeviceSnapShotIsObsolete = true
        } else if changedKeys.contains(Predicate.Key.serializedIdentityCoreDetails.rawValue) ||
                    changedKeys.contains(Predicate.Key.photoServerKeyEncoded.rawValue) ||
                    changedKeys.contains(Predicate.Key.rawPhotoServerLabel.rawValue) ||
                    changedKeys.contains(Predicate.Key.version.rawValue) {
            previousBackedUpDeviceSnapShotIsObsolete = true
        } else {
            previousBackedUpDeviceSnapShotIsObsolete = false
        }
        if previousBackedUpDeviceSnapShotIsObsolete {
            Task { await Self.observersHolder.previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged() }
        }
        
        // Potentially notify that the previous backed up profile snapshot is obsolete
        // For a list of all the entities that can perform a similar notification, see `OwnedIdentity`

        if !isDeleted && !isInserted {
            let previousBackedUpProfileSnapShotIsObsolete: Bool
            if isInserted {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else if changedKeys.contains(Predicate.Key.serializedIdentityCoreDetails.rawValue) ||
                        changedKeys.contains(Predicate.Key.photoServerKeyEncoded.rawValue) ||
                        changedKeys.contains(Predicate.Key.rawPhotoServerLabel.rawValue) ||
                        changedKeys.contains(Predicate.Key.version.rawValue) {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else {
                previousBackedUpProfileSnapShotIsObsolete = false
            }
            if previousBackedUpProfileSnapShotIsObsolete {
                if let ownedCryptoIdentity = try? self.ownedIdentity?.cryptoIdentity {
                    let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)
                    Task { await Self.observersHolder.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged(ownedCryptoId: ownedCryptoId) }
                } else {
                    assertionFailure()
                }
            }
        }

    }
    
}


// MARK: - For Backup purposes

extension OwnedIdentityDetailsPublished {
    
    var backupItem: OwnedIdentityDetailsPublishedBackupItem {
        return OwnedIdentityDetailsPublishedBackupItem(serializedIdentityCoreDetails: serializedIdentityCoreDetails,
                                                       photoServerKeyEncoded: photoServerKeyEncoded,
                                                       photoServerLabel: photoServerLabel,
                                                       version: version)
    }
    
}


struct OwnedIdentityDetailsPublishedBackupItem: Codable, Hashable {
    
    fileprivate let serializedIdentityCoreDetails: Data
    fileprivate let photoServerKeyEncoded: Data?
    fileprivate let photoServerLabel: UID?
    fileprivate let version: Int

    // Allows to prevent association failures in two items have identical variables
    private let transientUuid = UUID()

    var identityDetails: ObvIdentityDetails? {
        guard let coreDetails = try? ObvIdentityCoreDetails(serializedIdentityCoreDetails) else { return nil }
        return ObvIdentityDetails(coreDetails: coreDetails,
                                  photoURL: nil)
    }
    
    private static let errorDomain = String(describing: Self.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(serializedIdentityCoreDetails: Data, photoServerKeyEncoded: Data?, photoServerLabel: UID?, version: Int) {
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
        self.photoServerKeyEncoded = photoServerKeyEncoded
        self.photoServerLabel = photoServerLabel
        self.version = version
    }
    
    enum CodingKeys: String, CodingKey {
        // Attributes inherited from OwnedIdentityDetails
        case serializedIdentityCoreDetails = "serialized_details"
        // Local attributes
        case photoServerKeyEncoded = "photo_server_key"
        case photoServerLabel = "photo_server_label"
        case version = "version"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Attributes inherited from OwnedIdentityDetails
        guard let serializedIdentityCoreDetailsAsString = String(data: serializedIdentityCoreDetails, encoding: .utf8) else {
            throw OwnedIdentityDetailsPublishedBackupItem.makeError(message: "Could not serialize serializedIdentityCoreDetails to a String")
        }
        try container.encode(serializedIdentityCoreDetailsAsString, forKey: .serializedIdentityCoreDetails)
        // Local attributes
        try container.encodeIfPresent(photoServerKeyEncoded, forKey: .photoServerKeyEncoded)
        try container.encodeIfPresent(photoServerLabel?.raw, forKey: .photoServerLabel)
        try container.encode(version, forKey: .version)
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let serializedIdentityCoreDetailsAsString = try values.decode(String.self, forKey: .serializedIdentityCoreDetails)
        guard let serializedIdentityCoreDetailsAsData = serializedIdentityCoreDetailsAsString.data(using: .utf8) else {
            throw OwnedIdentityDetailsPublishedBackupItem.makeError(message: "Could not create Data from serializedIdentityCoreDetailsAsString")
        }
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetailsAsData
        
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
        
        self.version = try values.decode(Int.self, forKey: .version)
    }
    
    func restoreInstance(within context: NSManagedObjectContext, associations: inout BackupItemObjectAssociations) throws {
        let ownedIdentityDetailsPublished = OwnedIdentityDetailsPublished(backupItem: self, within: context)
        try associations.associate(ownedIdentityDetailsPublished, to: self)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within context: NSManagedObjectContext) throws {
        // Nothing to do here
    }

}


// MARK: - For snapshot purposes

extension OwnedIdentityDetailsPublished {
    
    var snapshotNode: OwnedIdentityDetailsPublishedSyncSnapshotNode {
        return OwnedIdentityDetailsPublishedSyncSnapshotNode(serializedIdentityCoreDetails: serializedIdentityCoreDetails,
                                                             photoServerKeyEncoded: photoServerKeyEncoded,
                                                             photoServerLabel: photoServerLabel,
                                                             version: version)
    }
    
}


struct OwnedIdentityDetailsPublishedSyncSnapshotNode: ObvSyncSnapshotNode {
    
    private let domain: Set<CodingKeys>
    fileprivate let serializedIdentityCoreDetails: Data?
    fileprivate let photoServerKeyEncoded: Data?
    let photoServerLabel: UID?
    fileprivate let version: Int?
    
    let id = Self.generateIdentifier()

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))


    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        // Attributes inherited from OwnedIdentityDetails
        case serializedIdentityCoreDetails = "serialized_details"
        // Local attributes
        case photoServerKeyEncoded = "photo_server_key"
        case photoServerLabel = "photo_server_label"
        case version = "version"
        // Domain
        case domain = "domain"
    }

    
    fileprivate init(serializedIdentityCoreDetails: Data, photoServerKeyEncoded: Data?, photoServerLabel: UID?, version: Int) {
        self.domain = Self.defaultDomain
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
        self.photoServerKeyEncoded = photoServerKeyEncoded
        self.photoServerLabel = photoServerLabel
        self.version = version
    }
    

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Domain
        try container.encode(domain, forKey: .domain)
        // Attributes inherited from OwnedIdentityDetails
        if let serializedIdentityCoreDetails {
            guard let serializedIdentityCoreDetailsAsString = String(data: serializedIdentityCoreDetails, encoding: .utf8) else {
                throw ObvError.couldNotSerializeCoreDetails
            }
            try container.encode(serializedIdentityCoreDetailsAsString, forKey: .serializedIdentityCoreDetails)
        }
        // Local attributes
        try container.encodeIfPresent(photoServerKeyEncoded, forKey: .photoServerKeyEncoded)
        try container.encodeIfPresent(photoServerLabel?.raw, forKey: .photoServerLabel)
        try container.encode(version, forKey: .version)
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))

        // Attributes inherited from OwnedIdentityDetails
        
        if let serializedIdentityCoreDetailsAsString = try values.decodeIfPresent(String.self, forKey: .serializedIdentityCoreDetails) {
            guard let serializedIdentityCoreDetailsAsData = serializedIdentityCoreDetailsAsString.data(using: .utf8) else {
                throw ObvError.couldNotDeserializeCoreDetails
            }
            self.serializedIdentityCoreDetails = serializedIdentityCoreDetailsAsData
        } else {
            self.serializedIdentityCoreDetails = nil
        }
        
        if let photoServerKeyEncoded = try? values.decodeIfPresent(Data.self, forKey: .photoServerKeyEncoded),
           let photoServerLabelAsData = try? values.decodeIfPresent(Data.self, forKey: .photoServerLabel),
           let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
            self.photoServerKeyEncoded = photoServerKeyEncoded
            self.photoServerLabel = photoServerLabelAsUID
        } else {
            assert(!values.allKeys.contains(where: { $0 == .photoServerKeyEncoded }), "The key is present, but we did not manage to decode the value")
            assert(!values.allKeys.contains(where: { $0 == .photoServerLabel }), "The key is present, but we did not manage to decode the value")
            self.photoServerKeyEncoded = nil
            self.photoServerLabel = nil
        }
        
        self.version = try values.decodeIfPresent(Int.self, forKey: .version)
    }
    
    
    func restoreInstance(within context: NSManagedObjectContext, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        guard domain.contains(.serializedIdentityCoreDetails) && domain.contains(.version) else {
            throw ObvError.tryingToRestoreIncompleteSnapshot
        }
        let ownedIdentityDetailsPublished = try OwnedIdentityDetailsPublished(snapshotNode: self, within: context)
        try associations.associate(ownedIdentityDetailsPublished, to: self)
    }

    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within context: NSManagedObjectContext) throws {
        // Nothing to do here
    }

    
    enum ObvError: Error {
        case tryingToRestoreIncompleteSnapshot
        case couldNotSerializeCoreDetails
        case couldNotDeserializeCoreDetails
        case couldNotDeserializePhotoServerLabel
        case serializedIdentityCoreDetailsIsNil
    }
    
    /// Called when parsing a device backup downloaded from the server
    func toObvIdentityCoreDetails() throws -> ObvIdentityCoreDetails {
        guard let serializedIdentityCoreDetails else {
            assertionFailure()
            throw ObvError.serializedIdentityCoreDetailsIsNil
        }
        return try ObvIdentityCoreDetails(serializedIdentityCoreDetails)
    }
    
    var photoServerKeyAndLabel: PhotoServerKeyAndLabel? {
        guard let photoServerKeyEncoded = self.photoServerKeyEncoded,
              let obvEncoded = ObvEncoded(withRawData: photoServerKeyEncoded),
              let key = try? AuthenticatedEncryptionKeyDecoder.decode(obvEncoded),
              let label = photoServerLabel else {
            return nil
        }
        return PhotoServerKeyAndLabel(key: key, label: label)
    }

}


// MARK: - OwnedIdentityDetailsPublished observers

protocol OwnedIdentityDetailsPublishedObServer: AnyObject {
    func previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged() async
    func previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged(ownedCryptoId: ObvCryptoId) async
}


private actor ObserversHolder: OwnedIdentityDetailsPublishedObServer {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: OwnedIdentityDetailsPublishedObServer?
        init(value: OwnedIdentityDetailsPublishedObServer?) {
            self.value = value
        }
    }

    func addObserver(_ newObserver: OwnedIdentityDetailsPublishedObServer) {
        self.observers.append(.init(value: newObserver))
    }

    // Implementing KeycloakServerObServer

    func previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged() async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.previousBackedUpDeviceSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged() }
            }
        }
    }
    
    func previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged(ownedCryptoId: ObvCryptoId) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.previousBackedUpProfileSnapShotIsObsoleteAsOwnedIdentityDetailsPublishedChanged(ownedCryptoId: ownedCryptoId) }
            }
        }
    }

}
