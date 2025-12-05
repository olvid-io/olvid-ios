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

@objc(ContactIdentityDetails)
class ContactIdentityDetails: NSManagedObject {
    
    static weak var delegateManager: ObvIdentityDelegateManager?
    
    private static let entityName = "ContactIdentityDetails"
    
    private static let errorDomain = String(describing: ContactIdentityDetails.self)
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactIdentityDetails.logSubsystem, category: "ContactIdentityDetails") }()

    // MARK: - Attributes
    
    @NSManaged private var photoFilename: String?
    @NSManaged internal var serializedIdentityCoreDetails: Data // Shall *not* be called from outside this class (but cannot be made private, since the setter must remain accessible to its subclasses. I miss the protected keyword...)
    @NSManaged var version: Int
    @NSManaged private var photoServerKeyEncoded: Data?
    @NSManaged private var rawPhotoServerLabel: Data?

    // MARK: - Relationships
    
    @NSManaged private(set) var contactIdentity: ContactIdentity
    
    // MARK: - Other variables
    
    private var changedKeys = Set<String>()
    
    private var photoURLsToDeleteOnDidSave = Set<URL>()

    private var photoServerLabel: UID? {
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
        guard let photoFilename = photoFilename else { return nil }
        let url = identityPhotosDirectory.appendingPathComponent(photoFilename)
        return url
    }
    
    
    func getIdentityDetails() throws -> ObvIdentityDetails {
        let data = self.serializedIdentityCoreDetails
        let coreDetails = try ObvIdentityCoreDetails(data)
        let photoURL = try getPhotoURL()
        return ObvIdentityDetails(coreDetails: coreDetails, photoURL: photoURL)
    }
    
    func getIdentityDetailsElements() throws -> IdentityDetailsElements {
        let coreDetails = try getIdentityDetails().coreDetails
        return IdentityDetailsElements(version: version, coreDetails: coreDetails, photoServerKeyAndLabel: photoServerKeyAndLabel)
    }

    /// The setter should only be called from one of the `ContactIdentityDetails` subclasses
    var photoServerKeyAndLabel: PhotoServerKeyAndLabel? {
        get {
            guard let photoServerKeyEncoded = self.photoServerKeyEncoded else { return nil }
            let obvEncoded = ObvEncoded(withRawData: photoServerKeyEncoded)!
            let key = try! AuthenticatedEncryptionKeyDecoder.decode(obvEncoded)
            guard let label = photoServerLabel else { return nil }
            return PhotoServerKeyAndLabel(key: key, label: label)
        }
        set {
            if let photoServerKeyAndLabel = newValue {
                self.photoServerKeyEncoded = photoServerKeyAndLabel.key.obvEncode().rawData
                self.photoServerLabel = photoServerKeyAndLabel.label
            } else {
                self.photoServerKeyEncoded = nil
                self.photoServerLabel = nil
            }
        }
    }

    // MARK: - Observers
    
    private static var observersHolder = ObserversHolder()
    
    static func addObvObserver(_ newObserver: ContactIdentityDetailsObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}


// MARK: - Initializer

extension ContactIdentityDetails {
    
    convenience init?(contactIdentity: ContactIdentity, coreDetails: ObvIdentityCoreDetails, version: Int, photoServerKeyAndLabel: PhotoServerKeyAndLabel?, entityName: String) {
        
        guard let context = contactIdentity.managedObjectContext else { assertionFailure(); return nil }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        
        do { self.serializedIdentityCoreDetails = try coreDetails.jsonEncode() } catch { return nil }
        self.photoFilename = nil // When creating a contact, we don't have her photo. It will come later.
        self.version = version
        self.photoServerKeyAndLabel = photoServerKeyAndLabel
        
        self.contactIdentity = contactIdentity

    }
 
    /// Used *exclusively* during a backup restore for creating an instance, relationships are recreated in a second step
    convenience init(serializedIdentityCoreDetails: Data, version: Int, photoServerKeyAndLabel: PhotoServerKeyAndLabel?, entityName: String, within context: NSManagedObjectContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.photoFilename = nil // This is ok
        self.photoServerKeyAndLabel = photoServerKeyAndLabel
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
        self.version = version
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

    func delete() throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvIdentityManagerError.contextIsNil
        }
        do {
            if let currentPhotoURL = try getPhotoURL() {
                photoURLsToDeleteOnDidSave.insert(currentPhotoURL)
            }
        } catch {
            assertionFailure() // Continue anyway
        }
        context.delete(self)
    }

    
    func setContactPhoto(data: Data) throws {
        guard let identityPhotosDirectory = Self.delegateManager?.identityPhotosDirectory else {
            assertionFailure()
            throw ObvIdentityManagerError.delegateManagerIsNotSet
        }
        guard let photoURLInEngine = freshPath(in: identityPhotosDirectory) else { throw makeError(message: "Could not get fresh path for photo") }
        try data.write(to: photoURLInEngine)
        try setContactPhoto(with: photoURLInEngine)
        try FileManager.default.removeItem(at: photoURLInEngine) // The previous call created another hard link so we can delete the file we just created
    }
    
    
    /// Updates the photo of the contact on the basis of the new URL. If the new URL is identical to the current one, this method does nothing. Otherwise,
    /// the file referenced by the old URL is deleted. At that point, if the new URL is non `nil`, the file at this URL is copied into the `diretory` passed as parameter, using
    /// a random filename, and this new filename is saved.
    func setContactPhoto(with newPhotoURL: URL?) throws {
        
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
        
    }
}

// MARK: - Convenience DB getters

extension ContactIdentityDetails {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<ContactIdentityDetails> {
        return NSFetchRequest<ContactIdentityDetails>(entityName: ContactIdentityDetails.entityName)
    }

    struct Predicate {
        enum Key: String {
            // Attributes
            case serializedIdentityCoreDetails = "serializedIdentityCoreDetails"
            case photoFilename = "photoFilename"
            case photoServerKeyEncoded = "photoServerKeyEncoded"
            case rawPhotoServerLabel = "rawPhotoServerLabel"
            // Relationships
            case contactIdentity = "contactIdentity"
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
        private static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            let key: String = [Key.contactIdentity.rawValue, ContactIdentity.Predicate.Key.ownedIdentityIdentity.rawValue].joined(separator: ".")
            return NSPredicate(key, EqualToData: ownedCryptoId.getIdentity())
        }
        private static func withContactCryptoId(_ contactCryptoId: ObvCryptoId) -> NSPredicate {
            let key: String = [Key.contactIdentity.rawValue, ContactIdentity.Predicate.Key.rawIdentity.rawValue].joined(separator: ".")
            return NSPredicate(key, EqualToData: contactCryptoId.getIdentity())
        }
        static func withContactIdentifier(_ contactIdentifier: ObvContactIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                Self.withOwnedCryptoId(contactIdentifier.ownedCryptoId),
                Self.withContactCryptoId(contactIdentifier.contactCryptoId),
            ])
        }
    }
    
    
    static func getAllPhotoFilenames(within context: NSManagedObjectContext) throws -> Set<String> {
        let request: NSFetchRequest<ContactIdentityDetails> = ContactIdentityDetails.fetchRequest()
        request.propertiesToFetch = [Predicate.Key.photoFilename.rawValue]
        let details = try context.fetch(request)
        let photoFilenames = Set(details.compactMap({ $0.photoFilename }))
        return photoFilenames
    }

    
    static func getInfosAboutContactsHavingPhotoFilename(within context: NSManagedObjectContext) throws -> [(ownedCryptoId: ObvCryptoIdentity, contactCryptoId: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements, photoURL: URL)] {
        let request: NSFetchRequest<ContactIdentityDetails> = ContactIdentityDetails.fetchRequest()
        request.predicate = Predicate.withPhotoFilename
        let items = try context.fetch(request)
        let results: [(ownedCryptoId: ObvCryptoIdentity, contactCryptoId: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements, photoURL: URL)] = try items.compactMap { details in
            guard let contactCryptoId = details.contactIdentity.cryptoIdentity,
                  let ownedCryptoId = try details.contactIdentity.ownedIdentity?.cryptoIdentity,
                  let contactIdentityDetailsElements = try? details.getIdentityDetailsElements(),
                  let photoURL = try details.getRawPhotoURL() else {
                return nil
            }
            return (ownedCryptoId, contactCryptoId, contactIdentityDetailsElements, photoURL)
        }
        return results
    }
    

    static func getAllWithMissingPhotoFilename(within context: NSManagedObjectContext) throws -> [ContactIdentityDetails] {
        let request: NSFetchRequest<ContactIdentityDetails> = ContactIdentityDetails.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withoutPhotoFilename,
            Predicate.withPhotoServerKeyAndLabel,
        ])
        let items = try context.fetch(request)
        return items
    }

}

extension ContactIdentityDetails {
    
    override func willSave() {
        super.willSave()
        if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }
    

    override func didSave() {
        super.didSave()
        
        defer {
            photoURLsToDeleteOnDidSave.removeAll()
            changedKeys.removeAll()
        }

        guard let delegateManager = Self.delegateManager else {
            Self.logger.fault("The delegate manager is not set")
            return
        }
        
        // Send a backupableManagerDatabaseContentChanged notification
        do {
            
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
            } else if changedKeys.contains(Predicate.Key.serializedIdentityCoreDetails.rawValue) ||
                        changedKeys.contains(Predicate.Key.photoServerKeyEncoded.rawValue) ||
                        changedKeys.contains(Predicate.Key.rawPhotoServerLabel.rawValue) {
                previousBackedUpProfileSnapShotIsObsolete = true
            } else {
                previousBackedUpProfileSnapShotIsObsolete = false
            }
            if previousBackedUpProfileSnapShotIsObsolete {
                let ownedIdentity = self.contactIdentity.ownedIdentityIdentity
                if let ownedCryptoId = try? ObvCryptoId(identity: ownedIdentity) {
                    Task { await Self.observersHolder.previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityDetailsChanged(ownedCryptoId: ownedCryptoId) }
                } else {
                    assertionFailure()
                }
            }

        }
        
        if !isInserted && !isDeleted && self.changedKeys.contains(Predicate.Key.photoFilename.rawValue) {
            
            if let contactCryptoIdentity = self.contactIdentity.cryptoIdentity,
               let ownedIdentity = self.contactIdentity.ownedIdentity,
               let ownedCryptoIdentity = try? ownedIdentity.cryptoIdentity {
                
                if self is ContactIdentityDetailsPublished {
                    ObvIdentityNotificationNew.publishedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity)
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                } else if self is ContactIdentityDetailsTrusted {
                    ObvIdentityNotificationNew.trustedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity)
                        .postOnBackgroundQueue(delegateManager.queueForPostingNotifications, within: delegateManager.notificationDelegate)
                } else {
                    assertionFailure()
                }
                
            } else {
                assertionFailure()
            }
            
        }

    }
    
}


// MARK: - ContactIdentityDetails observers

protocol ContactIdentityDetailsObserver: AnyObject {
    func previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityDetailsChanged(ownedCryptoId: ObvCryptoId) async
}


private actor ObserversHolder: ContactIdentityDetailsObserver {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: ContactIdentityDetailsObserver?
        init(value: ContactIdentityDetailsObserver?) {
            self.value = value
        }
    }

    func addObserver(_ newObserver: ContactIdentityDetailsObserver) {
        self.observers.append(.init(value: newObserver))
    }

    // Implementing OwnedIdentityObserver

    func previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityDetailsChanged(ownedCryptoId: ObvCryptoId) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.previousBackedUpProfileSnapShotIsObsoleteAsContactIdentityDetailsChanged(ownedCryptoId: ownedCryptoId) }
            }
        }
    }
    
}
