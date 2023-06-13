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
import os.log
import ObvTypes
import ObvCrypto
import ObvEncoder
import ObvMetaManager
import OlvidUtils


@objc(OwnedIdentityDetailsPublished)
final class OwnedIdentityDetailsPublished: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "OwnedIdentityDetailsPublished"
    private static let serializedIdentityCoreDetailsKey = "serializedIdentityCoreDetails"
    private static let errorDomain = String(describing: OwnedIdentityDetailsPublished.self)
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    // MARK: Attributes
    
    @NSManaged private var photoServerKeyEncoded: Data?
    @NSManaged private var rawPhotoServerLabel: Data?
    @NSManaged private var photoFilename: String?
    @NSManaged private(set) var serializedIdentityCoreDetails: Data
    @NSManaged private(set) var version: Int

    // MARK: Relationships
    
    // Expected to be non nil, except when the owned identity gets deleted
    @NSManaged private(set) var ownedIdentity: OwnedIdentity?
    
    // MARK: Other variables
    
    private var notificationRelatedChanges: NotificationRelatedChanges = []
    private var labelToDelete: UID?

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
    
    func getPhotoURL(identityPhotosDirectory: URL) -> URL? {
        guard let photoFilename = photoFilename else { return nil }
        let url = identityPhotosDirectory.appendingPathComponent(photoFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { assertionFailure(); return nil }
        return url
    }

    var delegateManager: ObvIdentityDelegateManager? {
        return ownedIdentity?.delegateManager ?? delegateManagerOnDeletion
    }

    var obvContext: ObvContext?
    
    private var delegateManagerOnDeletion: ObvIdentityDelegateManager?
    private var ownedCryptoIdOnDeletion: ObvCryptoIdentity?

    var photoServerKeyAndLabel: PhotoServerKeyAndLabel? {
        guard let photoServerKeyEncoded = self.photoServerKeyEncoded else { return nil }
        let obvEncoded = ObvEncoded(withRawData: photoServerKeyEncoded)!
        guard let key = try? AuthenticatedEncryptionKeyDecoder.decode(obvEncoded) else { return nil }
        guard let label = photoServerLabel else { return nil }
        return PhotoServerKeyAndLabel(key: key, label: label)
    }
    
    func getIdentityDetails(identityPhotosDirectory: URL) -> ObvIdentityDetails {
        let data = kvoSafePrimitiveValue(forKey: OwnedIdentityDetailsPublished.serializedIdentityCoreDetailsKey) as! Data
        let coreDetails = try! ObvIdentityCoreDetails(data)
        let photoURL = getPhotoURL(identityPhotosDirectory: identityPhotosDirectory)
        return ObvIdentityDetails(coreDetails: coreDetails, photoURL: photoURL)
    }

    func getIdentityDetailsElements(identityPhotosDirectory: URL) -> IdentityDetailsElements {
        let coreDetails = getIdentityDetails(identityPhotosDirectory: identityPhotosDirectory).coreDetails
        return IdentityDetailsElements(version: version, coreDetails: coreDetails, photoServerKeyAndLabel: photoServerKeyAndLabel)
    }
    
    // MARK: - Initializer
    
    convenience init?(ownedIdentity: OwnedIdentity, identityDetails: ObvIdentityDetails, version: Int, delegateManager: ObvIdentityDelegateManager) {
        
        guard let obvContext = ownedIdentity.obvContext else { return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentityDetailsPublished.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        self.ownedIdentity = ownedIdentity
        
        do {
            _ = try setOwnedIdentityPhoto(with: identityDetails.photoURL, delegateManager: delegateManager)
        } catch {
            return nil
        }
        do { self.serializedIdentityCoreDetails = try identityDetails.coreDetails.jsonEncode() } catch { return nil }
        self.version = version
        self.photoServerKeyEncoded = nil
        self.photoServerLabel = nil
        
    }

    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: OwnedIdentityDetailsPublishedBackupItem, with obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: OwnedIdentityDetailsPublished.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.photoServerKeyEncoded = backupItem.photoServerKeyEncoded
        self.photoServerLabel = backupItem.photoServerLabel
        self.photoFilename = nil // This is ok
        self.serializedIdentityCoreDetails = backupItem.serializedIdentityCoreDetails
        self.version = backupItem.version
    }
    
    
    func delete(delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        self.delegateManagerOnDeletion = delegateManager
        self.ownedCryptoIdOnDeletion = ownedIdentity?.cryptoIdentity
        if let currentPhotoURL = self.getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory) {
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                if FileManager.default.fileExists(atPath: currentPhotoURL.path) {
                    try? FileManager.default.removeItem(at: currentPhotoURL)
                }
            }
        }
        obvContext.delete(self)
    }

    
    func setOwnedIdentityPhoto(data: Data, delegateManager: ObvIdentityDelegateManager) throws {
        guard let photoURLInEngine = freshPath(in: delegateManager.identityPhotosDirectory) else { throw makeError(message: "Could not get fresh path for photo") }
        try data.write(to: photoURLInEngine)
        _ = try setOwnedIdentityPhoto(with: photoURLInEngine, delegateManager: delegateManager)
        try FileManager.default.removeItem(at: photoURLInEngine) // The previous call created another hard link so we can delete the file we just created
    }

    
    private func setOwnedIdentityPhoto(with newPhotoURL: URL?, delegateManager: ObvIdentityDelegateManager) throws -> Bool {
        
        guard let notificationDelegate = delegateManager.notificationDelegate else { assertionFailure(); throw makeError(message: "The notification delegate is not set") }
        let currentPhotoURL = getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory) // Can be nil

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
        assert(getPhotoURL(identityPhotosDirectory: delegateManager.identityPhotosDirectory) == nil)

        // If there is a new photo URL, we move it to the engine if required, or simply make a hard link if it is already within the engine.
        // Creating a hard link prevents the deletion of a photo referenced by another ContactGroupDetails instance.
        if let newPhotoURL = newPhotoURL {
            assert(FileManager.default.fileExists(atPath: newPhotoURL.path))
            guard let newPhotoURLInEngine = freshPath(in: delegateManager.identityPhotosDirectory) else { throw makeError(message: "Could not get fresh path for photo") }
            if newPhotoURL.deletingLastPathComponent() == delegateManager.identityPhotosDirectory {
                try FileManager.default.linkItem(at: newPhotoURL, to: newPhotoURLInEngine)
            } else {
                try FileManager.default.moveItem(at: newPhotoURL, to: newPhotoURLInEngine)
            }
            self.photoFilename = newPhotoURLInEngine.lastPathComponent
        }
        
        // Notify of the change
        guard let obvContext = self.obvContext else { assertionFailure(); return true }
        guard let ownedCryptoIdentity = self.ownedIdentity?.cryptoIdentity else { assertionFailure(); return true }
        try obvContext.addContextDidSaveCompletionHandler { error in
            guard error == nil else { return }
            ObvIdentityNotificationNew.publishedPhotoOfOwnedIdentityHasBeenUpdated(ownedIdentity: ownedCryptoIdentity)
                .postOnBackgroundQueue(within: notificationDelegate)
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

}


// MARK: - Publishing new details

extension OwnedIdentityDetailsPublished {
    
    private struct NotificationRelatedChanges: OptionSet {
        let rawValue: UInt8
        static let photoServerLabel = NotificationRelatedChanges(rawValue: 1 << 1)
    }
    

    func updateWithNewIdentityDetails(_ newIdentityDetails: ObvIdentityDetails, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        var detailsWereUpdated = false
        let currentCoreDetails = self.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory).coreDetails
        let newCoreDetails = newIdentityDetails.coreDetails
        if newCoreDetails != currentCoreDetails {
            self.serializedIdentityCoreDetails = try newIdentityDetails.coreDetails.jsonEncode()
            detailsWereUpdated = true
        }
        if try setOwnedIdentityPhoto(with: newIdentityDetails.photoURL, delegateManager: delegateManager) {
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
            case rawPhotoServerLabel = "rawPhotoServerLabel"
            case photoServerKeyEncoded = "photoServerKeyEncoded"
            case photoFilename = "photoFilename"
            case ownedIdentity = "ownedIdentity"
        }
        static var withoutPhotoFilename: NSPredicate {
            NSPredicate(withNilValueForKey: Key.photoFilename)
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
    
    static func getAllWithMissingPhotoFilename(within obvContext: ObvContext) throws -> [OwnedIdentityDetailsPublished] {
        let request: NSFetchRequest<OwnedIdentityDetailsPublished> = OwnedIdentityDetailsPublished.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withoutPhotoFilename,
            Predicate.withPhotoServerKeyAndLabel,
        ])
        let items = try obvContext.fetch(request)
        return items
    }
    
    static func getAllPhotoURLs(identityPhotosDirectory: URL, with obvContext: ObvContext) throws -> Set<URL> {
        let request: NSFetchRequest<OwnedIdentityDetailsPublished> = OwnedIdentityDetailsPublished.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.photoFilename.rawValue]
        let details = try obvContext.fetch(request)
        let photoURLs = Set(details.compactMap({ $0.getPhotoURL(identityPhotosDirectory: identityPhotosDirectory) }))
        return photoURLs
    }
    
    
    static func getAllPhotoServerLabels(ownedIdentity: OwnedIdentity) throws -> Set<UID> {
        guard let obvContext = ownedIdentity.obvContext else { throw makeError(message: "ObvContext is not set on owned identity") }
        let request: NSFetchRequest<OwnedIdentityDetailsPublished> = OwnedIdentityDetailsPublished.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withPhotoServerLabel,
            Predicate.forOwnedIdentity(ownedIdentity: ownedIdentity),
        ])
        request.propertiesToFetch = [Predicate.Key.rawPhotoServerLabel.rawValue]
        let details = try obvContext.fetch(request)
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
    
    override func didSave() {
        super.didSave()
        
        defer { notificationRelatedChanges = [] }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: OwnedIdentityDetailsPublished.entityName)
            os_log("The delegate manager is not set", log: log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: OwnedIdentityDetailsPublished.entityName)
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        if notificationRelatedChanges.contains(.photoServerLabel) || isDeleted {
            if let labelToDelete = self.labelToDelete, let ownedCryptoIdentity = self.ownedIdentity?.cryptoIdentity ?? ownedCryptoIdOnDeletion {
                let notification = ObvIdentityNotificationNew.serverLabelHasBeenDeleted(ownedIdentity: ownedCryptoIdentity, label: labelToDelete)
                notification.postOnBackgroundQueue(within: delegateManager.notificationDelegate)
            }
        }

        if !isInserted && !isDeleted, let ownedCryptoIdentity = self.ownedIdentity?.cryptoIdentity {
            
            let NotificationType = ObvIdentityNotification.OwnedIdentityDetailsPublicationInProgress.self
            let userInfo = [NotificationType.Key.ownedCryptoIdentity: ownedCryptoIdentity]
            notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            
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
    
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let ownedIdentityDetailsPublished = OwnedIdentityDetailsPublished(backupItem: self, with: obvContext)
        try associations.associate(ownedIdentityDetailsPublished, to: self)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing to do here
    }

}
