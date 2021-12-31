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

@objc(ContactIdentityDetails)
class ContactIdentityDetails: NSManagedObject, ObvManagedObject {
    
    private static let entityName = "ContactIdentityDetails"
    private static let serializedIdentityCoreDetails = "serializedIdentityCoreDetails"
    private static let photoURLKey = "photoURL"
    private static let photoServerKeyEncodedKey = "photoServerKeyEncoded"
    private static let photoServerLabelKey = "photoServerLabel"
    
    private static let errorDomain = String(describing: ContactIdentityDetails.self)
    
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    // MARK: - Attributes
    
    @NSManaged var photoURL: URL?
    @NSManaged internal var serializedIdentityCoreDetails: Data // Shall *not* be called from outside this class (but cannot be made private, since the setter must remain accessible to its subclasses. I miss the protected keyword...)
    @NSManaged var version: Int
    @NSManaged private var photoServerKeyEncoded: Data?
    @NSManaged private var photoServerLabel: String?

    // MARK: - Relationships
    
    @NSManaged private(set) var contactIdentity: ContactIdentity
    
    
    // MARK: - Other variables
    
    weak var delegateManager: ObvIdentityDelegateManager?

    var identityDetails: ObvIdentityDetails {
        let data = kvoSafePrimitiveValue(forKey: ContactIdentityDetails.serializedIdentityCoreDetails) as! Data
        let coreDetails = try! ObvIdentityCoreDetails(data)
        return ObvIdentityDetails(coreDetails: coreDetails, photoURL: photoURL)
    }
    
    var identityDetailsElements: IdentityDetailsElements {
        IdentityDetailsElements(version: version, coreDetails: identityDetails.coreDetails, photoServerKeyAndLabel: photoServerKeyAndLabel)
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
                self.photoServerKeyEncoded = photoServerKeyAndLabel.key.encode().rawData
                self.photoServerLabel = photoServerKeyAndLabel.label
            } else {
                self.photoServerKeyEncoded = nil
                self.photoServerLabel = nil
            }
        }
    }

    var obvContext: ObvContext?

}


// MARK: - Initializer

extension ContactIdentityDetails {
    
    convenience init?(contactIdentity: ContactIdentity, coreDetails: ObvIdentityCoreDetails, photoURL: URL?, version: Int, photoServerKeyAndLabel: PhotoServerKeyAndLabel?, entityName: String, delegateManager: ObvIdentityDelegateManager) {
        
        guard let obvContext = contactIdentity.obvContext else { return nil }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        do { self.serializedIdentityCoreDetails = try coreDetails.encode() } catch { return nil }
        self.photoURL = photoURL
        self.version = version
        self.photoServerKeyAndLabel = photoServerKeyAndLabel
        
        self.contactIdentity = contactIdentity
        
        self.delegateManager = delegateManager
        
    }
 
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    convenience init(serializedIdentityCoreDetails: Data, version: Int, photoServerKeyAndLabel: PhotoServerKeyAndLabel?, entityName: String, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.photoURL = nil // This is ok
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

    func setPhoto(data: Data, creatingNewFileIn directory: URL, notificationDelegate: ObvNotificationDelegate) throws {
        assert(photoServerKeyAndLabel != nil)
        guard let photoURLInEngine = freshPath(in: directory) else { throw makeError(message: "Could not get fresh path for photo") }
        try data.write(to: photoURLInEngine)
        try setPhotoURL(with: photoURLInEngine, creatingNewFileIn: directory, notificationDelegate: notificationDelegate)
        try FileManager.default.removeItem(at: photoURLInEngine) // The previous call created another hard link so we can delete the file we just created
    }
    
    func setPhotoURL(with newPhotoURL: URL?, creatingNewFileIn directory: URL, notificationDelegate: ObvNotificationDelegate) throws {
        
        guard self.photoURL != newPhotoURL else { return }
        if let currentPhotoURL = self.photoURL, let _newPhotoURL = newPhotoURL {
            guard !FileManager.default.contentsEqual(atPath: currentPhotoURL.path, andPath: _newPhotoURL.path) else {
                return
            }
        }
        
        // Whatever the new photo URL, we delete the previous version
        if let previousPhotoURL = self.photoURL {
            if FileManager.default.fileExists(atPath: previousPhotoURL.path) {
                try FileManager.default.removeItem(at: previousPhotoURL)
            }
            self.photoURL = nil
        }
        assert(self.photoURL == nil)
        
        // If there is a new photo URL, we move it to the engine if required, or simply make a hard link if it is already within the engine.
        // Creating a hard link prevents the deletion of a photo referenced by another ContactGroupDetails instance.
        if let newPhotoURL = newPhotoURL {
            assert(photoServerKeyAndLabel != nil)
            assert(FileManager.default.fileExists(atPath: newPhotoURL.path))
            guard let newPhotoURLInEngine = freshPath(in: directory) else { throw makeError(message: "Could not get fresh path for photo") }
            if newPhotoURL.deletingLastPathComponent() == directory {
                try FileManager.default.linkItem(at: newPhotoURL, to: newPhotoURLInEngine)
            } else {
                try FileManager.default.moveItem(at: newPhotoURL, to: newPhotoURLInEngine)
            }
            self.photoURL = newPhotoURLInEngine
        }
        
        // Notify of the change
        guard let obvContext = self.obvContext else { assertionFailure(); return }
        let ownedCryptoIdentity = self.contactIdentity.ownedIdentity.cryptoIdentity
        let contactCryptoIdentity = self.contactIdentity.cryptoIdentity
        try obvContext.addContextDidSaveCompletionHandler { error in
            guard error == nil else { assertionFailure(); return }
            if self is ContactIdentityDetailsPublished {
                ObvIdentityNotificationNew.publishedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity)
                    .postOnBackgroundQueue(within: notificationDelegate)
            } else if self is ContactIdentityDetailsTrusted {
                ObvIdentityNotificationNew.trustedPhotoOfContactIdentityHasBeenUpdated(ownedIdentity: ownedCryptoIdentity, contactIdentity: contactCryptoIdentity)
                    .postOnBackgroundQueue(within: notificationDelegate)
            } else {
                assertionFailure()
            }
        }
    }
}

// MARK: - Convenience DB getters

extension ContactIdentityDetails {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<ContactIdentityDetails> {
        return NSFetchRequest<ContactIdentityDetails>(entityName: ContactIdentityDetails.entityName)
    }

    struct Predicate {
        static var withoutPhotoURL: NSPredicate {
            NSPredicate(format: "%K == NIL", ContactIdentityDetails.photoURLKey)
        }
        static var withPhotoServerKey: NSPredicate {
            NSPredicate(format: "%K != NIL", ContactIdentityDetails.photoServerKeyEncodedKey)
        }
        static var withPhotoServerLabel: NSPredicate {
            NSPredicate(format: "%K != NIL", ContactIdentityDetails.photoServerLabelKey)
        }
        static var withPhotoServerKeyAndLabel: NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withPhotoServerKey,
                withPhotoServerLabel,
            ])
        }
    }

    static func getAllPhotoURLs(with obvContext: ObvContext) throws -> Set<URL> {
        let request: NSFetchRequest<ContactIdentityDetails> = ContactIdentityDetails.fetchRequest()
        request.propertiesToFetch = [ContactIdentityDetails.photoURLKey]
        let details = try obvContext.fetch(request)
        let photoURLs = Set(details.compactMap({ $0.photoURL }))
        return photoURLs
    }
    
    
    static func getAllWithMissingPhotoURL(within obvContext: ObvContext) throws -> [ContactIdentityDetails] {
        let request: NSFetchRequest<ContactIdentityDetails> = ContactIdentityDetails.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withoutPhotoURL,
            Predicate.withPhotoServerKeyAndLabel,
        ])
        let items = try obvContext.fetch(request)
        return items
    }

}

extension ContactIdentityDetails {
    
    override func didSave() {
        super.didSave()
        
        // Send a backupableManagerDatabaseContentChanged notification
        do {
            
            guard let delegateManager = delegateManager else {
                let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: String(describing: Self.self))
                os_log("The delegate manager is not set", log: log, type: .fault)
                return
            }
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: String(describing: Self.self))

            guard let flowId = obvContext?.flowId else {
                os_log("Could not notify that this backupable manager database content changed", log: log, type: .fault)
                assertionFailure()
                return
            }
            let notification = ObvBackupNotification.backupableManagerDatabaseContentChanged(flowId: flowId)
            notification.postOnDispatchQueue(withLabel: "Queue for sending a backupableManagerDatabaseContentChanged notification", within: delegateManager.notificationDelegate)
        }

        
    }
    
}
