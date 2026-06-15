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

@objc(ContactIdentityDetailsPublished)
final class ContactIdentityDetailsPublished: ContactIdentityDetails, ObvErrorMaker {

    // MARK: Internal constants
    
    private static let entityName = "ContactIdentityDetailsPublished"
    static let errorDomain = String(describing: ContactIdentityDetailsPublished.self)
    
    private static var logSubsystem: String { delegateManager?.logSubsystem ?? ObvIdentityDelegateManager.defaultLogSubsystem }
    private static var logger: Logger = { Logger(subsystem: ContactIdentityDetailsPublished.logSubsystem, category: "ContactIdentityDetailsPublished") }()

    // MARK: Attributes
    
    
    // MARK: Other variables
        
    private var isInsertedWhileRestoringSyncSnapshot = false
    
    // MARK: - Initializer
    
    convenience init?(contactIdentity: ContactIdentity, contactIdentityDetailsElements: IdentityDetailsElements) {
        
        self.init(contactIdentity: contactIdentity,
                  coreDetails: contactIdentityDetailsElements.coreDetails,
                  version: contactIdentityDetailsElements.version,
                  photoServerKeyAndLabel: contactIdentityDetailsElements.photoServerKeyAndLabel,
                  entityName: ContactIdentityDetailsPublished.entityName)
        
    }

    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: ContactIdentityDetailsPublishedBackupItem, within context: NSManagedObjectContext) {
        self.init(serializedIdentityCoreDetails: backupItem.serializedIdentityCoreDetails,
                  version: backupItem.version,
                  photoServerKeyAndLabel: backupItem.photoServerKeyAndLabel,
                  entityName: ContactIdentityDetailsPublished.entityName,
                  within: context)
    }

    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(snapshotNode: ContactIdentityDetailsPublishedSyncSnapshotNode, within context: NSManagedObjectContext) {
        self.init(serializedIdentityCoreDetails: snapshotNode.serializedIdentityCoreDetails,
                  version: snapshotNode.version,
                  photoServerKeyAndLabel: snapshotNode.photoServerKeyAndLabel,
                  entityName: ContactIdentityDetailsPublished.entityName,
                  within: context)
        self.isInsertedWhileRestoringSyncSnapshot = true
    }

    // MARK: - Observers
    
    private static var observersHolder = ObserversHolder()
    
    static func addObvContactIdentityDetailsPublishedObserver(_ newObserver: ContactIdentityDetailsPublishedObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}


// MARK: - Updating

extension ContactIdentityDetailsPublished {
    
    /// This method should *only* be called from the `updatePublishedDetails` method of the `ContactIdentity` entity.
    func updateWithNewContactIdentityDetailsElements(_ newContactIdentityDetailsElements: IdentityDetailsElements) throws {

        self.version = newContactIdentityDetailsElements.version
        
        let storedPublishedCoreDetails = try self.getIdentityDetails().coreDetails
        
        if newContactIdentityDetailsElements.coreDetails != storedPublishedCoreDetails {
            self.serializedIdentityCoreDetails = try newContactIdentityDetailsElements.coreDetails.jsonEncode()
        }
        
        if self.photoServerKeyAndLabel != newContactIdentityDetailsElements.photoServerKeyAndLabel {
            self.photoServerKeyAndLabel = newContactIdentityDetailsElements.photoServerKeyAndLabel
            try setContactPhoto(with: nil)
        }
        
    }
    
}


// MARK: - Convenience DB getters

extension ContactIdentityDetailsPublished {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<ContactIdentityDetailsPublished> {
        return NSFetchRequest<ContactIdentityDetailsPublished>(entityName: ContactIdentityDetailsPublished.entityName)
    }

    static func getFetchedResultsController(contactIdentifier: ObvContactIdentifier, within context: NSManagedObjectContext) -> NSFetchedResultsController<ContactIdentityDetailsPublished> {
        let request: NSFetchRequest<ContactIdentityDetailsPublished> = ContactIdentityDetailsPublished.fetchRequest()
        request.predicate = ContactIdentityDetails.Predicate.withContactIdentifier(contactIdentifier)
        request.sortDescriptors = []
        request.fetchLimit = 1
        request.propertiesToFetch = []
        let frc = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil)
        return frc
    }
    
}


// MARK: - Reacting to changes

extension ContactIdentityDetailsPublished {
    
    override func didSave() {
        super.didSave()
        
        defer {
            isInsertedWhileRestoringSyncSnapshot = false
        }
        
        
        guard !isInsertedWhileRestoringSyncSnapshot else {
            assert(isInserted)
            Self.logger.info("Insertion during a snapshot restore --> we don't send any notification")
            return
        }
        
        guard !isDeleted else {
            return
        }

        if !isDeleted {
            
            do {
                let contactIdentity = try ObvContactIdentity(contactIdentity: self.contactIdentity)
                Task { await Self.observersHolder.newPublishedContactIdentityDetails(contactIdentity: contactIdentity) }
            } catch {
                Self.logger.fault("Could not notify about the new published contact identity details")
                assertionFailure()
            }

        }
    }
    
}


// MARK: - For Backup purposes

extension ContactIdentityDetailsPublished {
    
    var backupItem: ContactIdentityDetailsPublishedBackupItem {
        return ContactIdentityDetailsPublishedBackupItem(serializedIdentityCoreDetails: serializedIdentityCoreDetails,
                                                         photoServerKeyAndLabel: photoServerKeyAndLabel,
                                                         version: version)
    }

}


struct ContactIdentityDetailsPublishedBackupItem: Codable, Hashable {
    
    fileprivate let serializedIdentityCoreDetails: Data
    fileprivate let photoServerKeyAndLabel: PhotoServerKeyAndLabel?
    fileprivate let version: Int

    // Allows to prevent association failures in two items have identical variables
    private let transientUuid = UUID()

    private static let errorDomain = String(describing: Self.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    static func == (lhs: ContactIdentityDetailsPublishedBackupItem, rhs: ContactIdentityDetailsPublishedBackupItem) -> Bool {
        return lhs.transientUuid == rhs.transientUuid
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(transientUuid)
    }

    fileprivate init(serializedIdentityCoreDetails: Data, photoServerKeyAndLabel: PhotoServerKeyAndLabel?, version: Int) {
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
        self.photoServerKeyAndLabel = photoServerKeyAndLabel
        self.version = version
    }
    
    enum CodingKeys: String, CodingKey {
        // Attributes inherited from OwnedIdentityDetails
        case serializedIdentityCoreDetails = "serialized_details"
        case version = "version"
        // Local attributes
        case photoServerKeyEncoded = "photo_server_key"
        case photoServerLabel = "photo_server_label"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Attributes inherited from OwnedIdentityDetails
        guard let serializedIdentityCoreDetailsAsString = String(data: serializedIdentityCoreDetails, encoding: .utf8) else {
            throw ContactIdentityDetailsPublishedBackupItem.makeError(message: "Could not serialize serializedIdentityCoreDetails to a String")
        }
        try container.encode(serializedIdentityCoreDetailsAsString, forKey: .serializedIdentityCoreDetails)
        try container.encode(version, forKey: .version)
        // Local attributes
        let photoServerKeyEncoded = photoServerKeyAndLabel?.key.obvEncode().rawData
        try container.encodeIfPresent(photoServerKeyEncoded, forKey: .photoServerKeyEncoded)
        try container.encodeIfPresent(photoServerKeyAndLabel?.label.raw, forKey: .photoServerLabel)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let serializedIdentityCoreDetailsAsString = try values.decode(String.self, forKey: .serializedIdentityCoreDetails)
        guard let serializedIdentityCoreDetailsAsData = serializedIdentityCoreDetailsAsString.data(using: .utf8) else {
            throw ContactIdentityDetailsPublishedBackupItem.makeError(message: "Could not create Data from serializedIdentityCoreDetailsAsString")
        }
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetailsAsData
        self.version = try values.decode(Int.self, forKey: .version)

        if values.allKeys.contains(.photoServerLabel) && values.allKeys.contains(.photoServerKeyEncoded) {
            do {
                let photoServerKeyEncodedRaw = try values.decode(Data.self, forKey: .photoServerKeyEncoded)
                guard let photoServerKeyEncoded = ObvEncoded(withRawData: photoServerKeyEncodedRaw) else {
                    throw Self.makeError(message: "Could not parse photo server key in ContactIdentityDetailsPublishedBackupItem")
                }
                let key = try AuthenticatedEncryptionKeyDecoder.decode(photoServerKeyEncoded)
                if let photoServerLabelAsData = try? values.decodeIfPresent(Data.self, forKey: .photoServerLabel),
                   let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    // Expected
                    self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: photoServerLabelAsUID)
                } else if let photoServerLabelAsUID = try values.decodeIfPresent(UID.self, forKey: .photoServerLabel) {
                    assertionFailure()
                    self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: photoServerLabelAsUID)
                } else if let photoServerLabelAsString = try? values.decode(String.self, forKey: .photoServerLabel),
                          let photoServerLabelAsData = Data(base64Encoded: photoServerLabelAsString),
                          let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    assertionFailure()
                    self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: photoServerLabelAsUID)
                } else if let photoServerLabelAsString = try? values.decode(String.self, forKey: .photoServerLabel),
                          let photoServerLabelAsData = Data(hexString: photoServerLabelAsString),
                          let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    assertionFailure()
                    self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: photoServerLabelAsUID)
                } else {
                    throw Self.makeError(message: "Could not decode photoServerLabel in the decoder of OwnedIdentityDetailsPublishedBackupItem")
                }
            } catch {
                assertionFailure()
                throw error
            }
        } else {
            self.photoServerKeyAndLabel = nil
        }

    }

    func restoreInstance(within context: NSManagedObjectContext, associations: inout BackupItemObjectAssociations) throws {
        let contactIdentityDetailsPublished = ContactIdentityDetailsPublished(backupItem: self, within: context)
        try associations.associate(contactIdentityDetailsPublished, to: self)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within context: NSManagedObjectContext) throws {
        // Nothing do to here
    }

}


// MARK: - For Snapshot purposes

extension ContactIdentityDetailsPublished {
    
    var snapshotNode: ContactIdentityDetailsPublishedSyncSnapshotNode {
        return ContactIdentityDetailsPublishedSyncSnapshotNode(
            serializedIdentityCoreDetails: serializedIdentityCoreDetails,
            photoServerKeyAndLabel: photoServerKeyAndLabel,
            version: self.version)
    }
    
}


struct ContactIdentityDetailsPublishedSyncSnapshotNode: ObvSyncSnapshotNode {

    fileprivate let serializedIdentityCoreDetails: Data
    fileprivate let photoServerKeyAndLabel: PhotoServerKeyAndLabel?
    fileprivate let version: Int
    
    private let domain: Set<CodingKeys>

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    let id = Self.generateIdentifier()
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        // Attributes inherited from OwnedIdentityDetails
        case serializedIdentityCoreDetails = "serialized_details"
        case version = "version"
        // Local attributes
        case photoServerKeyEncoded = "photo_server_key"
        case photoServerLabel = "photo_server_label"
        // Domain
        case domain = "domain"
    }

    fileprivate init(serializedIdentityCoreDetails: Data, photoServerKeyAndLabel: PhotoServerKeyAndLabel?, version: Int) {
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
        self.photoServerKeyAndLabel = photoServerKeyAndLabel
        self.version = version
        self.domain = Self.defaultDomain
    }

    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Attributes inherited from OwnedIdentityDetails
        guard let serializedIdentityCoreDetailsAsString = String(data: serializedIdentityCoreDetails, encoding: .utf8) else {
            throw ObvError.couldNotSerializeCoreDetails
        }
        try container.encode(serializedIdentityCoreDetailsAsString, forKey: .serializedIdentityCoreDetails)
        try container.encode(version, forKey: .version)
        // Local attributes
        let photoServerKeyEncoded = photoServerKeyAndLabel?.key.obvEncode().rawData
        try container.encodeIfPresent(photoServerKeyEncoded, forKey: .photoServerKeyEncoded)
        try container.encodeIfPresent(photoServerKeyAndLabel?.label.raw, forKey: .photoServerLabel)
        // Domain
        try container.encode(domain, forKey: .domain)
    }

    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        
        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
        guard domain.contains(.version) && domain.contains(.serializedIdentityCoreDetails) else { throw ObvError.tryingToRestoreIncompleteSnapshot }
        
        let serializedIdentityCoreDetailsAsString = try values.decode(String.self, forKey: .serializedIdentityCoreDetails)
        guard let serializedIdentityCoreDetailsAsData = serializedIdentityCoreDetailsAsString.data(using: .utf8) else {
            throw ObvError.couldNotDeserializeCoreDetails
        }
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetailsAsData
        self.version = try values.decode(Int.self, forKey: .version)

        if domain.contains(.photoServerLabel) && domain.contains(.photoServerKeyEncoded) && values.allKeys.contains(.photoServerLabel) && values.allKeys.contains(.photoServerKeyEncoded) {
            do {
                let photoServerKeyEncodedRaw = try values.decode(Data.self, forKey: .photoServerKeyEncoded)
                guard let photoServerKeyEncoded = ObvEncoded(withRawData: photoServerKeyEncodedRaw) else {
                    throw ObvError.couldNotParsePhotoServerKey
                }
                let key = try AuthenticatedEncryptionKeyDecoder.decode(photoServerKeyEncoded)
                if let photoServerLabelAsData = try? values.decodeIfPresent(Data.self, forKey: .photoServerLabel),
                   let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    // Expected
                    self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: photoServerLabelAsUID)
                } else if let photoServerLabelAsUID = try values.decodeIfPresent(UID.self, forKey: .photoServerLabel) {
                    assertionFailure()
                    self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: photoServerLabelAsUID)
                } else if let photoServerLabelAsString = try? values.decode(String.self, forKey: .photoServerLabel),
                          let photoServerLabelAsData = Data(base64Encoded: photoServerLabelAsString),
                          let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    assertionFailure()
                    self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: photoServerLabelAsUID)
                } else if let photoServerLabelAsString = try? values.decode(String.self, forKey: .photoServerLabel),
                          let photoServerLabelAsData = Data(hexString: photoServerLabelAsString),
                          let photoServerLabelAsUID = UID(uid: photoServerLabelAsData) {
                    assertionFailure()
                    self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: photoServerLabelAsUID)
                } else {
                    throw ObvError.couldNotDecodePhotoServerLabel
                }
            } catch {
                assertionFailure() // In production, continue anyway
                self.photoServerKeyAndLabel = nil
            }
        } else {
            self.photoServerKeyAndLabel = nil
        }
        
    }
    
    
    func restoreInstance(within context: NSManagedObjectContext, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        let contactIdentityDetailsPublished = ContactIdentityDetailsPublished(snapshotNode: self, within: context)
        try associations.associate(contactIdentityDetailsPublished, to: self)
    }

    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within context: NSManagedObjectContext) throws {
        // Nothing do to here
    }

    
    enum ObvError: Error {
        case couldNotSerializeCoreDetails
        case couldNotDeserializeCoreDetails
        case tryingToRestoreIncompleteSnapshot
        case couldNotParsePhotoServerKey
        case couldNotDecodePhotoServerLabel
    }
}


// MARK: - ContactIdentityDetailsPublished observers

protocol ContactIdentityDetailsPublishedObserver: AnyObject {
    func newPublishedContactIdentityDetails(contactIdentity: ObvContactIdentity) async
}


private actor ObserversHolder: ContactIdentityDetailsPublishedObserver {
    
    private var observers = [WeakObserver]()
    
    private final class WeakObserver {
        private(set) weak var value: ContactIdentityDetailsPublishedObserver?
        init(value: ContactIdentityDetailsPublishedObserver?) {
            self.value = value
        }
    }

    func addObserver(_ newObserver: ContactIdentityDetailsPublishedObserver) {
        self.observers.append(.init(value: newObserver))
    }

    // Implementing OwnedIdentityObserver

    func newPublishedContactIdentityDetails(contactIdentity: ObvContactIdentity) async {
        await withTaskGroup(of: Void.self) { taskGroup in
            for observer in observers.compactMap(\.value) {
                taskGroup.addTask { await observer.newPublishedContactIdentityDetails(contactIdentity: contactIdentity) }
            }
        }
    }
    
}
