/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


@objc(ContactIdentityDetailsTrusted)
final class ContactIdentityDetailsTrusted: ContactIdentityDetails {
 
    // MARK: Internal constants
    
    private static let entityName = "ContactIdentityDetailsTrusted"
    
    private static let errorDomain = String(describing: ContactIdentityDetailsTrusted.self)
    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { Self.makeError(message: message) }

    // MARK: - Initializer
    
    convenience init?(contactIdentity: ContactIdentity, identityCoreDetails: ObvIdentityCoreDetails, version: Int, delegateManager: ObvIdentityDelegateManager) {
        self.init(contactIdentity: contactIdentity,
                  coreDetails: identityCoreDetails,
                  version: version,
                  photoServerKeyAndLabel: nil,
                  entityName: ContactIdentityDetailsTrusted.entityName,
                  delegateManager: delegateManager)
    }

    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: ContactIdentityDetailsTrustedBackupItem, within obvContext: ObvContext) {
        self.init(serializedIdentityCoreDetails: backupItem.serializedIdentityCoreDetails,
                  version: backupItem.version,
                  photoServerKeyAndLabel: backupItem.photoServerKeyAndLabel,
                  entityName: ContactIdentityDetailsTrusted.entityName,
                  within: obvContext)
    }
    
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(snapshotNode: ContactIdentityDetailsTrustedSyncSnapShotNode, within obvContext: ObvContext) {
        self.init(serializedIdentityCoreDetails: snapshotNode.serializedIdentityCoreDetails,
                  version: snapshotNode.version,
                  photoServerKeyAndLabel: snapshotNode.photoServerKeyAndLabel,
                  entityName: ContactIdentityDetailsTrusted.entityName,
                  within: obvContext)
    }

}


// MARK: - Updating the trusted details

extension ContactIdentityDetailsTrusted {
    
    /// This method should *only* be called from the `updateTrustedDetailsWithPublishedDetails` and the `refreshCertifiedByOwnKeycloakAndTrustedDetails` methods of the `ContactIdentity` entity.
    func updateWithContactIdentityDetailsPublished(_ contactIdentityDetailsPublished: ContactIdentityDetailsPublished, delegateManager: ObvIdentityDelegateManager) throws {

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: "ContactIdentityDetailsTrusted")

        guard let managedObjectContext = self.managedObjectContext, contactIdentityDetailsPublished.managedObjectContext == managedObjectContext else {
            throw makeError(message: "Inappropriate context")
        }
        
        self.version = contactIdentityDetailsPublished.version
        let identityPhotosDirectory = delegateManager.identityPhotosDirectory
        
        if let publishedCoreDetails = contactIdentityDetailsPublished.getIdentityDetails(identityPhotosDirectory: identityPhotosDirectory)?.coreDetails,
           let trustedCoreDetails = self.getIdentityDetails(identityPhotosDirectory: identityPhotosDirectory)?.coreDetails {
            if publishedCoreDetails != trustedCoreDetails {
                self.serializedIdentityCoreDetails = contactIdentityDetailsPublished.serializedIdentityCoreDetails
            }
        } else {
            os_log("Could not update trusted details using published details", log: log, type: .fault)
            assertionFailure()
        }

        self.photoServerKeyAndLabel = contactIdentityDetailsPublished.photoServerKeyAndLabel

        let photoURLOfPublishedDetails = contactIdentityDetailsPublished.getPhotoURL(identityPhotosDirectory: identityPhotosDirectory)
        try setContactPhoto(with: photoURLOfPublishedDetails, delegateManager: delegateManager)
    }

    // This method assumes that the signature on the signed details is valid. It replace the values of the trusted details with that found in the signed details
    func update(with signedUserDetails: SignedObvKeycloakUserDetails, delegateManager: ObvIdentityDelegateManager) throws {
        let newSerializedIdentityCoreDetails = try signedUserDetails.getObvIdentityCoreDetails().jsonEncode()
        if self.serializedIdentityCoreDetails != newSerializedIdentityCoreDetails {
            self.serializedIdentityCoreDetails = newSerializedIdentityCoreDetails
        }
    }
    
    func resetVersionNumber() {
        self.version = 0
    }
}


// MARK: - Reacting to changes

extension ContactIdentityDetailsTrusted {
    
    override func didSave() {
        super.didSave()

        let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: ContactIdentityDetailsTrusted.entityName)

        guard let delegateManager = delegateManager else {
            os_log("The delegate manager is not set", log: log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        if !isDeleted, let ownedIdentity = contactIdentity.ownedIdentity {
            
            if let trustedIdentityDetails = self.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory), let contactCryptoIdentity = self.contactIdentity.cryptoIdentity {
                let NotificationType = ObvIdentityNotification.NewTrustedContactIdentityDetails.self
                let userInfo = [NotificationType.Key.contactCryptoIdentity: contactCryptoIdentity,
                                NotificationType.Key.ownedCryptoIdentity: ownedIdentity.cryptoIdentity,
                                NotificationType.Key.trustedIdentityDetails: trustedIdentityDetails] as [String: Any]
                notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)
            } else {
                os_log("Could not notify about the new trusted contact identity details", log: log, type: .fault)
                assertionFailure()
            }
            
        }
        
    }
    
}


// MARK: - For Backup purposes

extension ContactIdentityDetailsTrusted {
    
    var backupItem: ContactIdentityDetailsTrustedBackupItem {
        return ContactIdentityDetailsTrustedBackupItem(serializedIdentityCoreDetails: serializedIdentityCoreDetails,
                                                       photoServerKeyAndLabel: photoServerKeyAndLabel,
                                                       version: self.version)
    }
    
}


struct ContactIdentityDetailsTrustedBackupItem: Codable, Hashable {
    
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

    static func == (lhs: ContactIdentityDetailsTrustedBackupItem, rhs: ContactIdentityDetailsTrustedBackupItem) -> Bool {
        return lhs.transientUuid == rhs.transientUuid
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(transientUuid)
    }

    fileprivate init(serializedIdentityCoreDetails: Data, photoServerKeyAndLabel: PhotoServerKeyAndLabel?, version: Int) {
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
        self.photoServerKeyAndLabel = photoServerKeyAndLabel
        self.version = version
        debugPrint(self, self.version)
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
            throw ContactIdentityDetailsTrustedBackupItem.makeError(message: "Could not serialize serializedIdentityCoreDetails to a String")
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
            throw ContactIdentityDetailsTrustedBackupItem.makeError(message: "Could not create Data from serializedIdentityCoreDetailsAsString")
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
    
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let contactIdentityDetailsTrusted = ContactIdentityDetailsTrusted(backupItem: self, within: obvContext)
        try associations.associate(contactIdentityDetailsTrusted, to: self)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing do to here
    }

}


// MARK: - For Snapshot purposes

extension ContactIdentityDetailsTrusted {
    
    var snapshotNode: ContactIdentityDetailsTrustedSyncSnapShotNode {
        return ContactIdentityDetailsTrustedSyncSnapShotNode(
            serializedIdentityCoreDetails: serializedIdentityCoreDetails,
            photoServerKeyAndLabel: photoServerKeyAndLabel,
            version: self.version)
    }
    
}


struct ContactIdentityDetailsTrustedSyncSnapShotNode: ObvSyncSnapshotNode {

    fileprivate let serializedIdentityCoreDetails: Data
    fileprivate let photoServerKeyAndLabel: PhotoServerKeyAndLabel?
    fileprivate let version: Int
    private let domain: Set<CodingKeys>

    let id = Self.generateIdentifier()

    private static let defaultDomain = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    // Allows to prevent association failures in two items have identical variables
    private let transientUuid = UUID()

    static func == (lhs: ContactIdentityDetailsTrustedSyncSnapShotNode, rhs: ContactIdentityDetailsTrustedSyncSnapShotNode) -> Bool {
        return lhs.transientUuid == rhs.transientUuid
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(transientUuid)
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
            if let photoServerKeyEncodedRaw = try values.decodeIfPresent(Data.self, forKey: .photoServerKeyEncoded),
               let photoServerKeyEncoded = ObvEncoded(withRawData: photoServerKeyEncodedRaw),
               let key = try? AuthenticatedEncryptionKeyDecoder.decode(photoServerKeyEncoded),
               let photoServerLabelRaw = try? values.decodeIfPresent(Data.self, forKey: .photoServerLabel),
               let photoServerLabelAsUID = UID(uid: photoServerLabelRaw) {
                self.photoServerKeyAndLabel = .init(key: key, label: photoServerLabelAsUID)
            } else {
                assert(!values.allKeys.contains(where: { $0 == .photoServerLabel }), "The key is present, but we did not manage to decode the value")
                assert(!values.allKeys.contains(where: { $0 == .photoServerKeyEncoded }), "The key is present, but we did not manage to decode the value")
                self.photoServerKeyAndLabel = nil
            }
        } else {
            self.photoServerKeyAndLabel = nil
        }
        
    }
    
    
    func restoreInstance(within obvContext: ObvContext, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        let contactIdentityDetailsTrusted = ContactIdentityDetailsTrusted(snapshotNode: self, within: obvContext)
        try associations.associate(contactIdentityDetailsTrusted, to: self)
    }

    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within obvContext: ObvContext) throws {
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
