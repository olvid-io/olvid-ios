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
    func update(with signedUserDetails: SignedUserDetails, delegateManager: ObvIdentityDelegateManager) throws {
        self.serializedIdentityCoreDetails = try signedUserDetails.getObvIdentityCoreDetails().encode()
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

        if !isDeleted {
            
            if let trustedIdentityDetails = self.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory) {
                let NotificationType = ObvIdentityNotification.NewTrustedContactIdentityDetails.self
                let userInfo = [NotificationType.Key.contactCryptoIdentity: self.contactIdentity.cryptoIdentity,
                                NotificationType.Key.ownedCryptoIdentity: self.contactIdentity.ownedIdentity.cryptoIdentity,
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
        let photoServerKeyEncoded = photoServerKeyAndLabel?.key.encode().rawData
        try container.encodeIfPresent(photoServerKeyEncoded, forKey: .photoServerKeyEncoded)
        try container.encodeIfPresent(photoServerKeyAndLabel?.label, forKey: .photoServerLabel)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let serializedIdentityCoreDetailsAsString = try values.decode(String.self, forKey: .serializedIdentityCoreDetails)
        guard let serializedIdentityCoreDetailsAsData = serializedIdentityCoreDetailsAsString.data(using: .utf8) else {
            throw ContactIdentityDetailsTrustedBackupItem.makeError(message: "Could not create Data from serializedIdentityCoreDetailsAsString")
        }
        self.serializedIdentityCoreDetails = serializedIdentityCoreDetailsAsData
        if let photoServerKeyEncodedRaw = try values.decodeIfPresent(Data.self, forKey: .photoServerKeyEncoded),
           let photoServerKeyEncoded = ObvEncoded(withRawData: photoServerKeyEncodedRaw),
           let key = try? AuthenticatedEncryptionKeyDecoder.decode(photoServerKeyEncoded),
           let label = try values.decodeIfPresent(String.self, forKey: .photoServerLabel) {
            self.photoServerKeyAndLabel = PhotoServerKeyAndLabel(key: key, label: label)
        } else {
            self.photoServerKeyAndLabel = nil
        }
        self.version = try values.decode(Int.self, forKey: .version)
    }
    
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let contactIdentityDetailsTrusted = ContactIdentityDetailsTrusted(backupItem: self, within: obvContext)
        try associations.associate(contactIdentityDetailsTrusted, to: self)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing do to here
    }

}
