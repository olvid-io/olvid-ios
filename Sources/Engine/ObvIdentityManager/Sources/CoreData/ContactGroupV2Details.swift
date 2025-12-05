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
import OSLog
import CoreData
import OlvidUtils
import ObvMetaManager
import ObvCrypto
import ObvEncoder
import ObvTypes


@objc(ContactGroupV2Details)
final class ContactGroupV2Details: NSManagedObject, ObvErrorMaker {

    private static let entityName = "ContactGroupV2Details"
    static let errorDomain = "ContactGroupV2Details"
    
    static weak var delegateManager: ObvIdentityDelegateManager?
    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactGroupV2Details.logSubsystem, category: "ContactGroupV2Details") }()

    // Attributes
    
    @NSManaged private var photoFilename: String?
    @NSManaged private var rawPhotoServerIdentity: Data? // Part of GroupV2.ServerPhotoInfo
    @NSManaged private var rawPhotoServerKeyEncoded: Data? // Part of GroupV2.ServerPhotoInfo
    @NSManaged private var rawPhotoServerLabel: Data? // Part of GroupV2.ServerPhotoInfo
    @NSManaged private(set) var serializedCoreDetails: Data

    // Relationships
    
    // We expect either trustedDetailsOfContactGroup or publishedDetailsOfContactGroup to be non nil
    @NSManaged private var contactGroupInCaseTheDetailsArePublished: ContactGroupV2?
    @NSManaged private var contactGroupInCaseTheDetailsAreTrusted: ContactGroupV2?

    // Accessors

    var serverPhotoInfo: GroupV2.ServerPhotoInfo? {
        get {
            guard let group = contactGroupInCaseTheDetailsArePublished ?? contactGroupInCaseTheDetailsAreTrusted else {
                assertionFailure()
                return nil
            }
            guard let groupIdentifier = group.groupIdentifier else {
                assertionFailure()
                return nil
            }
            switch groupIdentifier.category {
            case .server:
                guard let rawPhotoServerIdentity = rawPhotoServerIdentity,
                      let photoServerIdentity = ObvCryptoIdentity(from: rawPhotoServerIdentity),
                      let rawPhotoServerKeyEncoded = rawPhotoServerKeyEncoded,
                      let photoServerKeyEncoded = ObvEncoded(withRawData: rawPhotoServerKeyEncoded),
                      let photoServerKey = try? AuthenticatedEncryptionKeyDecoder.decode(photoServerKeyEncoded),
                      let photoServerLabel = photoServerLabel else {
                          return nil
                      }
                return GroupV2.ServerPhotoInfo(key: photoServerKey, label: photoServerLabel, identity: photoServerIdentity)
            case .keycloak:
                guard let rawPhotoServerKeyEncoded = rawPhotoServerKeyEncoded,
                      let photoServerKeyEncoded = ObvEncoded(withRawData: rawPhotoServerKeyEncoded),
                      let photoServerKey = try? AuthenticatedEncryptionKeyDecoder.decode(photoServerKeyEncoded),
                      let photoServerLabel = photoServerLabel else {
                          return nil
                      }
                return GroupV2.ServerPhotoInfo(key: photoServerKey, label: photoServerLabel, identity: nil)
            }
        }
        set {
            self.rawPhotoServerIdentity = newValue?.identity?.getIdentity()
            self.rawPhotoServerKeyEncoded = newValue?.photoServerKeyAndLabel.key.obvEncode().rawData
            self.photoServerLabel = newValue?.photoServerKeyAndLabel.label
        }
    }
    
    private var photoServerLabel: UID? {
        get {
            guard let rawValue = rawPhotoServerLabel else { return nil }
            guard let value = UID(uid: rawValue) else { assertionFailure(); return nil }
            return value
        }
        set {
            self.rawPhotoServerLabel = newValue?.raw
        }
    }
    
    // Other variables

    private var isRestoringBackup = false
    private var changedKeys = Set<String>()
    private var photoURLsToDeleteOnDidSave = Set<URL>()

    // MARK: - Initializer
    
    convenience init(serverPhotoInfo: GroupV2.ServerPhotoInfo?, serializedCoreDetails: Data, photoURL: URL?, within context: NSManagedObjectContext) {
        
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2Details.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.serverPhotoInfo = serverPhotoInfo
        self.serializedCoreDetails = serializedCoreDetails
        do {
            try self.setGroupPhoto(with: photoURL)
        } catch {
            Self.logger.fault("Could not set group photo: \(error.localizedDescription)")
            assertionFailure() // Continue anyway
        }
        
    }
    
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: ContactGroupV2DetailsBackupItem, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2Details.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.rawPhotoServerIdentity = backupItem.rawPhotoServerIdentity
        self.rawPhotoServerKeyEncoded = backupItem.rawPhotoServerKeyEncoded
        self.photoServerLabel = backupItem.photoServerLabel
        self.serializedCoreDetails = backupItem.serializedCoreDetails
        self.isRestoringBackup = true
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreated in a second step
    fileprivate convenience init(snapshotNode: ContactGroupV2DetailsSyncSnapshotNode, within context: NSManagedObjectContext) throws {
        let entityDescription = NSEntityDescription.entity(forEntityName: ContactGroupV2Details.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.rawPhotoServerIdentity = snapshotNode.rawPhotoServerIdentity
        self.rawPhotoServerKeyEncoded = snapshotNode.rawPhotoServerKeyEncoded
        self.photoServerLabel = snapshotNode.photoServerLabel
        guard let serializedCoreDetails = snapshotNode.serializedCoreDetails else {
            assertionFailure()
            throw ContactGroupV2DetailsSyncSnapshotNode.ObvError.tryingToRestoreIncompleteNode
        }
        self.serializedCoreDetails = serializedCoreDetails
        self.isRestoringBackup = true
    }

    
    func delete() throws {
        guard let context = self.managedObjectContext else { assertionFailure(); throw ObvIdentityManagerError.contextIsNil }
        do {
            if let currentPhotoURL = try self.getPhotoURL() {
                photoURLsToDeleteOnDidSave.insert(currentPhotoURL)
            }
        } catch {
            assertionFailure()
        }
        context.delete(self)
    }

    
    // MARK: - Photo
    
    private func deletePhotoFilename() {
        if self.photoFilename != nil {
            self.photoFilename = nil
        }
    }
    
    func getPhotoURL() throws -> URL? {
        guard let url = try getRawPhotoURL() else { return nil }
        guard FileManager.default.fileExists(atPath: url.path) else {
            //assertionFailure()
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

    
    func getPhotoURLAndUploader() throws -> (url: URL, uploader: ObvCryptoIdentity)? {
        guard let identityPhotosDirectory = Self.delegateManager?.identityPhotosDirectory else {
            assertionFailure()
            throw ObvIdentityManagerError.delegateManagerIsNotSet
        }
        guard let photoFilename, let rawPhotoServerIdentity = rawPhotoServerIdentity else { return nil }
        let url = identityPhotosDirectory.appendingPathComponent(photoFilename)
        guard FileManager.default.fileExists(atPath: url.path) else { assertionFailure(); return nil }
        guard let uploader = ObvCryptoIdentity(from: rawPhotoServerIdentity) else { assertionFailure(); return nil }
        return (url, uploader)
    }

    
    func getPhotoURLAndServerPhotoInfo() throws -> (photoURL: URL, serverPhotoInfo: GroupV2.ServerPhotoInfo)? {
        guard let identityPhotosDirectory = Self.delegateManager?.identityPhotosDirectory else {
            assertionFailure()
            throw ObvIdentityManagerError.delegateManagerIsNotSet
        }
        guard let photoFilename, let rawPhotoServerIdentity = rawPhotoServerIdentity, let rawPhotoServerKeyEncoded, let photoServerLabel else { return nil }
        let url = identityPhotosDirectory.appendingPathComponent(photoFilename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            assertionFailure()
            return nil
        }
        guard let uploader = ObvCryptoIdentity(from: rawPhotoServerIdentity) else { assertionFailure(); return nil }
        guard let encodedKey = ObvEncoded(withRawData: rawPhotoServerKeyEncoded) else { assertionFailure(); return nil }
        let key = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
        let serverPhotoInfo = GroupV2.ServerPhotoInfo(key: key, label: photoServerLabel, identity: uploader)
        return (url, serverPhotoInfo)
    }

    
    func setGroupPhoto(data: Data) throws {
        guard let identityPhotosDirectory = Self.delegateManager?.identityPhotosDirectory else {
            assertionFailure()
            throw ObvIdentityManagerError.delegateManagerIsNotSet
        }
        guard let photoURLInEngine = freshPath(in: identityPhotosDirectory) else { throw Self.makeError(message: "Could not get fresh path for photo") }
        try data.write(to: photoURLInEngine)
        try setGroupPhoto(with: photoURLInEngine)
        try FileManager.default.removeItem(at: photoURLInEngine) // The previous call created another hard link so we can delete the file we just created
    }
    
    
    /// Compare `self` to other details. If everything is identical (including the bytes of the photo) excepted for the `serverPhotoInfo`, this method returns `true`. Otherwise, it returns `false`.
    ///
    /// This is usefull when comparing trusted details to published details. If comparing these details with this method returns `true` then we can replace trusted details by the published details as it makes no difference to the user.
    func trustedDetailsAreIdenticalToOtherDetailsExceptForTheServerPhotoInfo(publishedDetails: ContactGroupV2Details) throws -> Bool {
        
        // Make sure we are comparing trusted details to published details, and make sure the corresponding group is the same
        
        guard self.contactGroupInCaseTheDetailsAreTrusted != nil else { assertionFailure(); return false }
        guard publishedDetails.contactGroupInCaseTheDetailsArePublished != nil else { assertionFailure(); return false }
        guard self.contactGroupInCaseTheDetailsAreTrusted == publishedDetails.contactGroupInCaseTheDetailsArePublished else { assertionFailure(); return false }
        
        // Compare the serialized core details.
        // Note that this test is not very robust since the serialization process can be non deterministic.
        // Still, if the serializations are identical, we know we can continue.
        
        guard self.serializedCoreDetails == publishedDetails.serializedCoreDetails else { return false }
        
        // Compare the photos bytes
        
        switch (try self.getPhotoURL(), try publishedDetails.getPhotoURL()) {
        case (.some(let trustedPhotoURL), .some(let publishedPhotoURL)):
            guard FileManager.default.fileExists(atPath: trustedPhotoURL.path) && FileManager.default.fileExists(atPath: publishedPhotoURL.path) else { assertionFailure(); return false }
            guard FileManager.default.contentsEqual(atPath: trustedPhotoURL.path, andPath: publishedPhotoURL.path) else { return false }
        case (.none, .none):
            break
        default:
            return false
        }
        
        // If we reach this point, the published details are "equivalent" to the trusted ones
        
        return true
        
    }
    
    
    private func setGroupPhoto(with newPhotoURL: URL?) throws {
        
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
        
        if let newPhotoURL {
            assert(FileManager.default.fileExists(atPath: newPhotoURL.path))
            if FileManager.default.fileExists(atPath: newPhotoURL.path) {
                guard let newPhotoURLInEngine = freshPath(in: identityPhotosDirectory) else { assertionFailure(); throw Self.makeError(message: "Could not get fresh path for photo") }
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


    func hasPhotoForServerPhotoInfo(_ serverPhotoInfo: GroupV2.ServerPhotoInfo) throws -> Bool {
        guard self.serverPhotoInfo == serverPhotoInfo else { return false }
        guard let photoURL = try getPhotoURL() else { return false }
        guard FileManager.default.fileExists(atPath: photoURL.path) else { return false }
        return true
    }
    
    
    // MARK: - Creating or updating (trusted) details of a keycloak group
    
    /// Returns ServerPhotoInfo if a photo needs to be downloaded
    static func createOrUpdateContactGroupV2Details(for contactGroupV2: ContactGroupV2, keycloakGroupBlob: KeycloakGroupBlob, within context: NSManagedObjectContext) throws -> GroupV2.ServerPhotoInfo? {
        
        let serverPhotoInfoIfPhotoNeedsToBeDownloaded: GroupV2.ServerPhotoInfo?

        if let self = contactGroupV2.trustedDetails {
            serverPhotoInfoIfPhotoNeedsToBeDownloaded = try self.updateKeycloakContactGroupV2Details(
                keycloakGroupBlob: keycloakGroupBlob,
                within: context)
        } else {
            serverPhotoInfoIfPhotoNeedsToBeDownloaded = createKeycloakContactGroupV2Details(
                for: contactGroupV2,
                keycloakGroupBlob: keycloakGroupBlob,
                within: context)
        }
        
        return serverPhotoInfoIfPhotoNeedsToBeDownloaded
        
    }
    
    
    /// Returns ServerPhotoInfo if a photo needs to be downloaded
    private static func createKeycloakContactGroupV2Details(for contactGroupV2: ContactGroupV2, keycloakGroupBlob: KeycloakGroupBlob, within context: NSManagedObjectContext) ->  GroupV2.ServerPhotoInfo? {
        
        assert(contactGroupV2.trustedDetails == nil)
        
        let trustedDetails = ContactGroupV2Details(serverPhotoInfo: keycloakGroupBlob.serverPhotoInfo,
                                                   serializedCoreDetails: keycloakGroupBlob.serializedGroupCoreDetails,
                                                   photoURL: nil,
                                                   within: context)
        
        trustedDetails.contactGroupInCaseTheDetailsAreTrusted = contactGroupV2

        return trustedDetails.serverPhotoInfo
        
    }
    
    
    /// Returns ServerPhotoInfo if a photo needs to be downloaded
    private func updateKeycloakContactGroupV2Details(keycloakGroupBlob: KeycloakGroupBlob, within context: NSManagedObjectContext) throws -> GroupV2.ServerPhotoInfo? {
        
        let serverPhotoInfoIfPhotoNeedsToBeDownloaded: GroupV2.ServerPhotoInfo?

        // Deal with the photo
        
        if self.serverPhotoInfo != keycloakGroupBlob.serverPhotoInfo {
            serverPhotoInfoIfPhotoNeedsToBeDownloaded = keycloakGroupBlob.serverPhotoInfo
            // If there is a photo, delete it as a new one will be downloaded from the server
            if let currentPhotoURL = try self.getPhotoURL() {
                self.photoURLsToDeleteOnDidSave.insert(currentPhotoURL)
            }
            self.deletePhotoFilename()
            // The new serverPhotoInfo
            self.serverPhotoInfo = keycloakGroupBlob.serverPhotoInfo
        } else if try self.getPhotoURL() == nil {
            // The server photo infos did not changed, but the photo is still not available. We need to download it.
            serverPhotoInfoIfPhotoNeedsToBeDownloaded = keycloakGroupBlob.serverPhotoInfo
        } else {
            serverPhotoInfoIfPhotoNeedsToBeDownloaded = nil
        }
        
        // Deal with the serializedCoreDetails
        
        if self.serializedCoreDetails != keycloakGroupBlob.serializedGroupCoreDetails {
            self.serializedCoreDetails = keycloakGroupBlob.serializedGroupCoreDetails
        }
        
        return serverPhotoInfoIfPhotoNeedsToBeDownloaded
        
    }

    
    // MARK: - Convenience DB getters

    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactGroupV2Details> {
        return NSFetchRequest<ContactGroupV2Details>(entityName: ContactGroupV2Details.entityName)
    }

    
    struct Predicate {
        enum Key: String {
            case photoFilename = "photoFilename"
            case rawPhotoServerIdentity = "rawPhotoServerIdentity"
            case rawPhotoServerKeyEncoded = "rawPhotoServerKeyEncoded"
            case rawPhotoServerLabel = "rawPhotoServerLabel"
            case serializedCoreDetails = "serializedCoreDetails"
            case contactGroupInCaseTheDetailsArePublished = "contactGroupInCaseTheDetailsArePublished"
            case contactGroupInCaseTheDetailsAreTrusted = "contactGroupInCaseTheDetailsAreTrusted"

        }
        static var withoutPhotoFilename: NSPredicate {
            NSPredicate(withNilValueForKey: Key.photoFilename)
        }
        static var withPhotoFilename: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.photoFilename)
        }
        static var withoutContactGroup: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNilValueForKey: Key.contactGroupInCaseTheDetailsArePublished),
                NSPredicate(withNilValueForKey: Key.contactGroupInCaseTheDetailsAreTrusted),
            ])
        }
    }

    
    static func getInfosAboutGroupsHavingPhotoFilename(within context: NSManagedObjectContext) throws -> [(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverPhotoInfo: GroupV2.ServerPhotoInfo, photoURL: URL)] {
        
        let request: NSFetchRequest<ContactGroupV2Details> = ContactGroupV2Details.fetchRequest()
        request.predicate = Predicate.withPhotoFilename
        let items = try context.fetch(request)
        let results: [(ownedIdentity: ObvCryptoIdentity, groupIdentifier: GroupV2.Identifier, serverPhotoInfo: GroupV2.ServerPhotoInfo, photoURL: URL)] = try items.compactMap { details in
            
            guard let photoURL = try details.getRawPhotoURL(),
                  let group = details.contactGroupInCaseTheDetailsArePublished ?? details.contactGroupInCaseTheDetailsAreTrusted,
                  let ownedIdentity = try group.ownedIdentity?.cryptoIdentity,
                  let groupIdentifier = group.groupIdentifier,
                  let serverPhotoInfo = details.serverPhotoInfo
            else {
                return nil
            }
            return (ownedIdentity, groupIdentifier, serverPhotoInfo, photoURL)
        }
        return results
    }
    
    
    static func getAllPhotoURLs(within context: NSManagedObjectContext) throws -> Set<URL> {
        let request: NSFetchRequest<ContactGroupV2Details> = ContactGroupV2Details.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.photoFilename.rawValue]
        let details = try context.fetch(request)
        let photoURLs = try Set(details.compactMap({ try $0.getPhotoURL() }))
        return photoURLs
    }

    
    static func deleteOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = ContactGroupV2Details.fetchRequest()
        request.predicate = Predicate.withoutContactGroup
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        batchDeleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(batchDeleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
    
    // MARK: - Sending notifications

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
            isRestoringBackup = false
            photoURLsToDeleteOnDidSave.removeAll()
        }
        
        guard !isRestoringBackup else { assert(isInserted); return }
        
        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is not set")
            assertionFailure()
            return
        }

        // Send a backupableManagerDatabaseContentChanged notification
        if isInserted || isDeleted || isUpdated {
            ObvBackupNotification.backupableManagerDatabaseContentChanged
                .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
        }
        
        for photoURLToDeleteOnDidSave in self.photoURLsToDeleteOnDidSave {
            if FileManager.default.fileExists(atPath: photoURLToDeleteOnDidSave.path) {
                try? FileManager.default.removeItem(at: photoURLToDeleteOnDidSave)
            }
        }

        if !isDeleted {
                        
            // Potentially notify that the previous backed up profile snapshot is obsolete
            // For a list of all the entities that can perform a similar notification, see `OwnedIdentity`

            let previousBackedUpProfileSnapShotIsObsolete: Bool
            if isInserted {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else if changedKeys.contains(Predicate.Key.rawPhotoServerIdentity.rawValue) ||
                        changedKeys.contains(Predicate.Key.rawPhotoServerKeyEncoded.rawValue) ||
                        changedKeys.contains(Predicate.Key.rawPhotoServerLabel.rawValue) ||
                        changedKeys.contains(Predicate.Key.serializedCoreDetails.rawValue) {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else {
                previousBackedUpProfileSnapShotIsObsolete = false
            }
            if previousBackedUpProfileSnapShotIsObsolete {
                if let contactGroup = self.contactGroupInCaseTheDetailsAreTrusted ?? self.contactGroupInCaseTheDetailsArePublished, let ownedCryptoIdentity = try? contactGroup.ownedIdentity?.cryptoIdentity {
                    let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedCryptoIdentity)
                    Task { await Self.observersHolder.previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2DetailsChanged(ownedCryptoId: ownedCryptoId) }
                } else {
                    assertionFailure()
                }
            }

        }
        
        if !isDeleted && !isInserted && !changedKeys.isEmpty {
            if let group = self.contactGroupInCaseTheDetailsAreTrusted ?? self.contactGroupInCaseTheDetailsArePublished, let obvGroupV2 = try? group.getObvGroupV2() {
                let creationOrUpdateInitiator = group.creationOrUpdateInitiator
                ObvIdentityNotificationNew.groupV2WasUpdated(obvGroupV2: obvGroupV2, initiator: creationOrUpdateInitiator)
                    .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
            }
        }
        
    }
    
    // MARK: - Observers
    
    private static var observersHolder = ObserversHolder()
    
    static func addObvObserver(_ newObserver: ContactGroupV2DetailsObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}


// MARK: - For Backup purposes

extension ContactGroupV2Details {
    
    var backupItem: ContactGroupV2DetailsBackupItem {
        return ContactGroupV2DetailsBackupItem(rawPhotoServerIdentity: self.rawPhotoServerIdentity,
                                               rawPhotoServerKeyEncoded: self.rawPhotoServerKeyEncoded,
                                               photoServerLabel: self.photoServerLabel,
                                               serializedCoreDetails: self.serializedCoreDetails)
    }

}


struct ContactGroupV2DetailsBackupItem: Codable, Hashable, ObvErrorMaker {
    
    fileprivate let rawPhotoServerIdentity: Data?
    fileprivate let rawPhotoServerKeyEncoded: Data?
    fileprivate let photoServerLabel: UID?
    fileprivate let serializedCoreDetails: Data

    // Allows to prevent association failures in two items have identical variables
    private let transientUuid = UUID()

    static let errorDomain = "ContactGroupV2DetailsBackupItem"

    fileprivate init(rawPhotoServerIdentity: Data?, rawPhotoServerKeyEncoded: Data?, photoServerLabel: UID?, serializedCoreDetails: Data) {
        if let rawPhotoServerIdentity = rawPhotoServerIdentity, let rawPhotoServerKeyEncoded = rawPhotoServerKeyEncoded, let photoServerLabel = photoServerLabel {
            self.rawPhotoServerIdentity = rawPhotoServerIdentity
            self.rawPhotoServerKeyEncoded = rawPhotoServerKeyEncoded
            self.photoServerLabel = photoServerLabel
        } else {
            self.rawPhotoServerIdentity = nil
            self.rawPhotoServerKeyEncoded = nil
            self.photoServerLabel = nil
        }
        self.serializedCoreDetails = serializedCoreDetails
    }

    enum CodingKeys: String, CodingKey {
        case rawPhotoServerIdentity = "photo_server_identity"
        case rawPhotoServerKeyEncoded = "photo_server_key"
        case photoServerLabel = "photo_server_label"
        case serializedCoreDetails = "serialized_details"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        guard let serializedCoreDetailsAsString = String(data: serializedCoreDetails, encoding: .utf8) else {
            throw Self.makeError(message: "Could not represent serializedCoreDetails as String")
        }
        try container.encode(serializedCoreDetailsAsString, forKey: .serializedCoreDetails)
        try container.encodeIfPresent(rawPhotoServerIdentity, forKey: .rawPhotoServerIdentity)
        try container.encodeIfPresent(rawPhotoServerKeyEncoded, forKey: .rawPhotoServerKeyEncoded)
        try container.encodeIfPresent(photoServerLabel?.raw, forKey: .photoServerLabel)
    }
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let serializedCoreDetailsAsString = try values.decode(String.self, forKey: .serializedCoreDetails)
        guard let serializedCoreDetailsAsData = serializedCoreDetailsAsString.data(using: .utf8) else {
            throw Self.makeError(message: "Could not represent serializedCoreDetails as Data")
        }
        self.serializedCoreDetails = serializedCoreDetailsAsData

        if values.allKeys.contains(.photoServerLabel) && values.allKeys.contains(.rawPhotoServerKeyEncoded) && values.allKeys.contains(.rawPhotoServerIdentity) {
            do {
                self.rawPhotoServerIdentity = try values.decode(Data.self, forKey: .rawPhotoServerIdentity)
                self.rawPhotoServerKeyEncoded = try values.decode(Data.self, forKey: .rawPhotoServerKeyEncoded)
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
            self.rawPhotoServerIdentity = nil
            self.rawPhotoServerKeyEncoded = nil
            self.photoServerLabel = nil
        }

    }
    
    func restoreInstance(within context: NSManagedObjectContext, associations: inout BackupItemObjectAssociations) throws {
        let contactGroupV2Details = ContactGroupV2Details(backupItem: self, within: context)
        try associations.associate(contactGroupV2Details, to: self)
    }
    
    func restoreRelationships(associations: BackupItemObjectAssociations, within context: NSManagedObjectContext) throws {
        // Nothing to do here
    }

}



// MARK: - For Snapshot purposes


extension ContactGroupV2Details {
    
    var snapshotNode: ContactGroupV2DetailsSyncSnapshotNode {
        .init(rawPhotoServerIdentity: self.rawPhotoServerIdentity,
              rawPhotoServerKeyEncoded: self.rawPhotoServerKeyEncoded,
              photoServerLabel: self.photoServerLabel,
              serializedCoreDetails: self.serializedCoreDetails)
    }
    
}


struct ContactGroupV2DetailsSyncSnapshotNode: ObvSyncSnapshotNode, Equatable, Hashable {
    
    private let domain: Set<CodingKeys>
    fileprivate let rawPhotoServerIdentity: Data?
    fileprivate let rawPhotoServerKeyEncoded: Data?
    fileprivate let photoServerLabel: UID?
    fileprivate let serializedCoreDetails: Data?

    let id = Self.generateIdentifier()

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))
    
    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case rawPhotoServerIdentity = "photo_server_identity"
        case rawPhotoServerKeyEncoded = "photo_server_key"
        case photoServerLabel = "photo_server_label"
        case serializedCoreDetails = "serialized_details"
        case domain = "domain"
    }

    
    fileprivate init(rawPhotoServerIdentity: Data?, rawPhotoServerKeyEncoded: Data?, photoServerLabel: UID?, serializedCoreDetails: Data) {
        if let rawPhotoServerKeyEncoded = rawPhotoServerKeyEncoded, let photoServerLabel = photoServerLabel {
            self.rawPhotoServerKeyEncoded = rawPhotoServerKeyEncoded
            self.photoServerLabel = photoServerLabel
        } else {
            self.rawPhotoServerKeyEncoded = nil
            self.photoServerLabel = nil
        }
        self.rawPhotoServerIdentity = rawPhotoServerIdentity // Nil for keycloak groups
        self.serializedCoreDetails = serializedCoreDetails
        self.domain = Self.defaultDomain
    }

    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        if let serializedCoreDetails {
            guard let serializedCoreDetailsAsString = String(data: serializedCoreDetails, encoding: .utf8) else {
                throw ObvError.couldNotSerializeCoreDetails
            }
            try container.encode(serializedCoreDetailsAsString, forKey: .serializedCoreDetails)
        }
        try container.encodeIfPresent(rawPhotoServerIdentity, forKey: .rawPhotoServerIdentity)
        try container.encodeIfPresent(rawPhotoServerKeyEncoded, forKey: .rawPhotoServerKeyEncoded)
        try container.encodeIfPresent(photoServerLabel?.raw, forKey: .photoServerLabel)
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))

        if let serializedCoreDetailsAsString = try values.decodeIfPresent(String.self, forKey: .serializedCoreDetails) {
            guard let serializedCoreDetailsAsData = serializedCoreDetailsAsString.data(using: .utf8) else {
                throw ObvError.couldNotDeserializeCoreDetails
            }
            self.serializedCoreDetails = serializedCoreDetailsAsData
        } else {
            self.serializedCoreDetails = nil
        }

        if values.allKeys.contains(.photoServerLabel) && values.allKeys.contains(.rawPhotoServerKeyEncoded) && values.allKeys.contains(.rawPhotoServerIdentity) {
            do {
                self.rawPhotoServerIdentity = try values.decodeIfPresent(Data.self, forKey: .rawPhotoServerIdentity)
                self.rawPhotoServerKeyEncoded = try values.decodeIfPresent(Data.self, forKey: .rawPhotoServerKeyEncoded)
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
                    throw ObvError.couldNotDecodePhotoServerLabel
                }
            } catch {
                assertionFailure()
                throw error
            }
        } else {
            self.rawPhotoServerIdentity = nil
            self.rawPhotoServerKeyEncoded = nil
            self.photoServerLabel = nil
        }

    }
    
    
    func restoreInstance(within context: NSManagedObjectContext, associations: inout SnapshotNodeManagedObjectAssociations) throws {

        let minimumDomain: Set<CodingKeys> = Set([.serializedCoreDetails])
        guard minimumDomain.isSubset(of: domain) else {
            assertionFailure()
            throw ObvError.tryingToRestoreIncompleteNode
        }
                
        let contactGroupV2Details = try ContactGroupV2Details(snapshotNode: self, within: context)
        try associations.associate(contactGroupV2Details, to: self)
        
    }
    
    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within context: NSManagedObjectContext) throws {
        // Nothing to do here
    }

    
    enum ObvError: Error {
        case couldNotSerializeCoreDetails
        case couldNotDeserializeCoreDetails
        case couldNotDecodePhotoServerLabel
        case tryingToRestoreIncompleteNode
    }
    
}


// MARK: - ContactGroupV2Details observers

protocol ContactGroupV2DetailsObserver: AnyObject {
    func previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2DetailsChanged(ownedCryptoId: ObvCryptoId) async
}


private actor ObserversHolder: ContactGroupV2DetailsObserver {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: ContactGroupV2DetailsObserver?
        init(value: ContactGroupV2DetailsObserver?) {
            self.value = value
        }
    }

    func addObserver(_ newObserver: ContactGroupV2DetailsObserver) {
        self.observers.append(.init(value: newObserver))
    }

    // Implementing OwnedIdentityObserver

    func previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2DetailsChanged(ownedCryptoId: ObvCryptoId) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.previousBackedUpProfileSnapShotIsObsoleteAsContactGroupV2DetailsChanged(ownedCryptoId: ownedCryptoId) }
            }
        }
    }
    
}
