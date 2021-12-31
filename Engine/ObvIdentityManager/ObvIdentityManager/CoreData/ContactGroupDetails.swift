/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


@objc(ContactGroupDetails)
class ContactGroupDetails: NSManagedObject, ObvManagedObject {
    
    // MARK: - Internal constants

    private static let entityName = "ContactGroupDetails"
    private static let errorDomain = String(describing: ContactGroupDetails.self)
    private static let photoURLKey = "photoURL"
    private static let photoServerKeyEncodedKey = "photoServerKeyEncoded"
    private static let photoServerLabelKey = "photoServerLabel"

    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    // MARK: - Attributes
    
    @NSManaged private var photoServerKeyEncoded: Data?
    @NSManaged private(set) var photoServerLabel: String?
    @NSManaged private(set) var photoURL: URL?
    @NSManaged private var serializedCoreDetails: Data
    @NSManaged private(set) var version: Int

    // MARK: - Relationships
    
    // MARK: - Computed variables
    
    var photoServerKeyAndLabel: PhotoServerKeyAndLabel? {
        get {
            guard let photoServerKeyEncoded = self.photoServerKeyEncoded else { return nil }
            guard let obvEncoded = ObvEncoded(withRawData: photoServerKeyEncoded) else { return nil }
            guard let key = try? AuthenticatedEncryptionKeyDecoder.decode(obvEncoded) else { assertionFailure(); return nil }
            guard let label = photoServerLabel else { return nil }
            return PhotoServerKeyAndLabel(key: key, label: label)
        }
        set {
            self.photoServerKeyEncoded = newValue?.key.encode().rawData
            self.photoServerLabel = newValue?.label
        }
    }
    
    // MARK: - Other properties
    
    var obvContext: ObvContext?
}


// MARK: - Initializer and deleting

extension ContactGroupDetails {
    
    convenience init(groupDetailsElementsWithPhoto: GroupDetailsElementsWithPhoto, identityPhotosDirectory: URL, notificationDelegate: ObvNotificationDelegate, forEntityName entityName: String, within obvContext: ObvContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.photoServerKeyAndLabel = groupDetailsElementsWithPhoto.photoServerKeyAndLabel
        try setPhotoURL(with: groupDetailsElementsWithPhoto.photoURL, creatingNewFileIn: identityPhotosDirectory, notificationDelegate: notificationDelegate)
        self.serializedCoreDetails = try groupDetailsElementsWithPhoto.coreDetails.encode()
        self.version = groupDetailsElementsWithPhoto.version
        try notifyThatThePhotoURLDidChange(within: obvContext, notificationDelegate: notificationDelegate)
    }

    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(backupItem: ContactGroupDetailsBackupItem, forEntityName entityName: String, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        if let photoServerKeyEncodedRaw = backupItem.photoServerKeyEncoded,
           let photoServerKeyEncoded = ObvEncoded(withRawData: photoServerKeyEncodedRaw),
           let label = backupItem.photoServerLabel,
           let key = try? AuthenticatedEncryptionKeyDecoder.decode(photoServerKeyEncoded) {
            self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: label)
        } else {
            self.photoServerKeyAndLabel = nil
        }
        self.photoURL = nil // It is ok not to call setPhotoURL(...) here
        self.serializedCoreDetails = backupItem.serializedCoreDetails
        self.version = backupItem.version
    }

    
    func delete(within obvContext: ObvContext) throws {
        if let currentPhotoURL = self.photoURL {
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { return }
                if FileManager.default.fileExists(atPath: currentPhotoURL.path) {
                    try? FileManager.default.removeItem(at: currentPhotoURL)
                }
            }
        }
        obvContext.delete(self)
    }

}

// MARK: - Setting the photo and the server key/label

extension ContactGroupDetails {

    func setPhotoURL(with newPhotoURL: URL?, creatingNewFileIn directory: URL, notificationDelegate: ObvNotificationDelegate) throws {
        
        guard self.photoURL != newPhotoURL else { return }
        if let currentPhotoURL = self.photoURL, let _newPhotoURL = newPhotoURL {
            guard !FileManager.default.contentsEqual(atPath: currentPhotoURL.path, andPath: _newPhotoURL.path) else {
                return
            }
        }

        // Whatever the new photo URL, we delete the previous version if there is one.
        if let previousPhotoURL = self.photoURL {
            if FileManager.default.fileExists(atPath: previousPhotoURL.path) {
                try FileManager.default.removeItem(at: previousPhotoURL)
            }
            self.photoURL = nil
        }

        assert(self.photoURL == nil)
        
        // If there is a new photo URL, we create a fresh new hard link to it.
        // Creating a hard link prevents the deletion of a photo referenced by another ContactGroupDetails instance.
        if let newPhotoURL = newPhotoURL {
            assert(FileManager.default.fileExists(atPath: newPhotoURL.path))
            guard let newPhotoURLInEngine = freshPath(in: directory) else { assertionFailure(); throw makeError(message: "Could not get fresh path for photo") }
            do {
                try FileManager.default.linkItem(at: newPhotoURL, to: newPhotoURLInEngine)
            } catch {
                assertionFailure()
                debugPrint(error.localizedDescription)
                throw error
            }
            self.photoURL = newPhotoURLInEngine
        }

        // Notify of the change
        guard let obvContext = self.obvContext else { assertionFailure(); return }
        try notifyThatThePhotoURLDidChange(within: obvContext, notificationDelegate: notificationDelegate)
    }
    
    
    private func notifyThatThePhotoURLDidChange(within obvContext: ObvContext, notificationDelegate: ObvNotificationDelegate) throws {
        
        try obvContext.addContextDidSaveCompletionHandler { error in
            guard error == nil else { return }
            if let latestDetails = self as? ContactGroupDetailsLatest {
                ObvIdentityNotificationNew.latestPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: latestDetails.contactGroupOwned.groupUid,
                                                                                        ownedIdentity: latestDetails.contactGroupOwned.ownedIdentity.cryptoIdentity)
                    .postOnBackgroundQueue(within: notificationDelegate)
            } else if let trustedDetails = self as? ContactGroupDetailsTrusted {
                ObvIdentityNotificationNew.trustedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: trustedDetails.contactGroupJoined.groupUid,
                                                                                          ownedIdentity: trustedDetails.contactGroupJoined.ownedIdentity.cryptoIdentity,
                                                                                          groupOwner: trustedDetails.contactGroupJoined.groupOwner.cryptoIdentity)
                    .postOnBackgroundQueue(within: notificationDelegate)
            } else if let publishedDetails = self as? ContactGroupDetailsPublished {
                if let ownedGroup = publishedDetails.contactGroup as? ContactGroupOwned {
                    ObvIdentityNotificationNew.publishedPhotoOfContactGroupOwnedHasBeenUpdated(groupUid: ownedGroup.groupUid,
                                                                                               ownedIdentity: ownedGroup.ownedIdentity.cryptoIdentity)
                        .postOnBackgroundQueue(within: notificationDelegate)
                } else if let joinedGroup = publishedDetails.contactGroup as? ContactGroupJoined {
                    ObvIdentityNotificationNew.publishedPhotoOfContactGroupJoinedHasBeenUpdated(groupUid: joinedGroup.groupUid,
                                                                                                ownedIdentity: joinedGroup.ownedIdentity.cryptoIdentity,
                                                                                                groupOwner: joinedGroup.groupOwner.cryptoIdentity)
                        .postOnBackgroundQueue(within: notificationDelegate)
                } else {
                    assertionFailure()
                }
            } else {
                assertionFailure()
            }
            
        }

    }

    
    func setPhoto(data: Data, creatingNewFileIn directory: URL, notificationDelegate: ObvNotificationDelegate) throws {
        guard let photoURLInEngine = freshPath(in: directory) else { throw makeError(message: "Could not get fresh path for photo") }
        try data.write(to: photoURLInEngine)
        try setPhotoURL(with: photoURLInEngine, creatingNewFileIn: directory, notificationDelegate: notificationDelegate)
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
        static var withoutPhotoURL: NSPredicate {
            NSPredicate(format: "%K == NIL", ContactGroupDetails.photoURLKey)
        }
        static var withPhotoServerKey: NSPredicate {
            NSPredicate(format: "%K != NIL", ContactGroupDetails.photoServerKeyEncodedKey)
        }
        static var withPhotoServerLabel: NSPredicate {
            NSPredicate(format: "%K != NIL", ContactGroupDetails.photoServerLabelKey)
        }
        static var withPhotoServerKeyAndLabel: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withPhotoServerKey,
                withPhotoServerLabel,
            ])
        }
    }

    static func getAllPhotoURLs(with obvContext: ObvContext) throws -> Set<URL> {
        let request: NSFetchRequest<ContactGroupDetails> = ContactGroupDetails.fetchRequest()
        request.propertiesToFetch = [ContactGroupDetails.photoURLKey]
        let details = try obvContext.fetch(request)
        let photoURLs = Set(details.compactMap({ $0.photoURL }))
        return photoURLs
    }
    
    static func getAllWithMissingPhotoURL(within obvContext: ObvContext) throws -> [ContactGroupDetails] {
        let request: NSFetchRequest<ContactGroupDetails> = ContactGroupDetails.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withoutPhotoURL,
            Predicate.withPhotoServerKeyAndLabel,
        ])
        let items = try obvContext.fetch(request)
        return items
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
    fileprivate let photoServerLabel: String?
    fileprivate let serializedCoreDetails: Data
    fileprivate let version: Int

    // The following private type allows to "specialize" a ContactGroupDetailsBackupItem instance before it is associated to an instance of NSManagedObject. This is required because the association does not allow duplicates (i.e., two identical ContactGroupDetailsBackupItem), and we sometimes have identical trusted and published details).
    private let transientUuid = UUID()
    
    private static let errorDomain = String(describing: Self.self)
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(photoServerKeyEncoded: Data?, photoServerLabel: String?, serializedCoreDetails: Data, version: Int) {
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
        try container.encodeIfPresent(photoServerLabel, forKey: .photoServerLabel)
        guard let serializedCoreDetailsAsString = String(data: serializedCoreDetails, encoding: .utf8) else {
            throw ContactGroupDetailsBackupItem.makeError(message: "Could not represent serializedCoreDetails as String")
        }
        try container.encode(serializedCoreDetailsAsString, forKey: .serializedCoreDetails)
        try container.encode(version, forKey: .version)
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.photoServerKeyEncoded = try values.decodeIfPresent(Data.self, forKey: .photoServerKeyEncoded)
        self.photoServerLabel = try values.decodeIfPresent(String.self, forKey: .photoServerLabel)
        let serializedCoreDetailsAsString = try values.decode(String.self, forKey: .serializedCoreDetails)
        guard let serializedCoreDetailsAsData = serializedCoreDetailsAsString.data(using: .utf8) else {
            throw ContactGroupDetailsBackupItem.makeError(message: "Could not represent serializedCoreDetails as Data")
        }
        self.serializedCoreDetails = serializedCoreDetailsAsData
        self.version = try values.decode(Int.self, forKey: .version)
    }

    func restoreContactGroupDetailsLatestInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupDetailsLatest = ContactGroupDetailsLatest(backupItem: self, within: obvContext)
        try associations.associate(contactGroupDetailsLatest, to: self)
    }
    
    func restoreContactGroupDetailsPublishedInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupDetailsPublished = ContactGroupDetailsPublished(backupItem: self, with: obvContext)
        try associations.associate(contactGroupDetailsPublished, to: self)
    }

    func restoreContactGroupDetailsTrustedInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupDetailsTrusted = ContactGroupDetailsTrusted(backupItem: self, within: obvContext)
        try associations.associate(contactGroupDetailsTrusted, to: self)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing to do
    }

}
