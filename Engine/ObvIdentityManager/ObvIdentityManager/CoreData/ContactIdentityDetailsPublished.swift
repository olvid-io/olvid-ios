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

@objc(ContactIdentityDetailsPublished)
final class ContactIdentityDetailsPublished: ContactIdentityDetails {

    // MARK: Internal constants
    
    private static let entityName = "ContactIdentityDetailsPublished"
    static let errorDomain = String(describing: ContactIdentityDetailsPublished.self)
    
    // MARK: Attributes
    
    
    // MARK: Other variables
        
    // MARK: - Initializer
    
    convenience init?(contactIdentity: ContactIdentity, contactIdentityDetailsElements: IdentityDetailsElements, delegateManager: ObvIdentityDelegateManager) {
        
        self.init(contactIdentity: contactIdentity,
                  coreDetails: contactIdentityDetailsElements.coreDetails,
                  version: contactIdentityDetailsElements.version,
                  photoServerKeyAndLabel: contactIdentityDetailsElements.photoServerKeyAndLabel,
                  entityName: ContactIdentityDetailsPublished.entityName,
                  delegateManager: delegateManager)
        
    }

    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: ContactIdentityDetailsPublishedBackupItem, within obvContext: ObvContext) {
        self.init(serializedIdentityCoreDetails: backupItem.serializedIdentityCoreDetails,
                  version: backupItem.version,
                  photoServerKeyAndLabel: backupItem.photoServerKeyAndLabel,
                  entityName: ContactIdentityDetailsPublished.entityName,
                  within: obvContext)
    }

}


// MARK: - Updating

extension ContactIdentityDetailsPublished {
    
    /// This method should *only* be called from the `updatePublishedDetails` method of the `ContactIdentity` entity.
    func updateWithNewContactIdentityDetailsElements(_ newContactIdentityDetailsElements: IdentityDetailsElements, delegateManager: ObvIdentityDelegateManager) throws {

        self.version = newContactIdentityDetailsElements.version
        
        if newContactIdentityDetailsElements.coreDetails != self.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory).coreDetails {
            self.serializedIdentityCoreDetails = try newContactIdentityDetailsElements.coreDetails.encode()
        }
        
        if newContactIdentityDetailsElements.photoServerKeyAndLabel != self.photoServerKeyAndLabel {
            self.photoServerKeyAndLabel = newContactIdentityDetailsElements.photoServerKeyAndLabel
            try setContactPhoto(with: nil, delegateManager: delegateManager)
        }
        
    }
    
}


// MARK: - Reacting to changes

extension ContactIdentityDetailsPublished {
    
    override func didSave() {
        super.didSave()
        
        guard !isDeleted else {
            return
        }
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: ContactIdentityDetailsPublished.entityName)
            os_log("The delegate manager is not set", log: log, type: .fault)
            return
        }
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            let log = OSLog(subsystem: ObvIdentityDelegateManager.defaultLogSubsystem, category: ContactIdentityDetailsPublished.entityName)
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }

        
        if !isDeleted {
            
            let publishedIdentityDetails = self.getIdentityDetails(identityPhotosDirectory: delegateManager.identityPhotosDirectory)
            let NotificationType = ObvIdentityNotification.NewPublishedContactIdentityDetails.self
            let userInfo = [NotificationType.Key.contactCryptoIdentity: self.contactIdentity.cryptoIdentity,
                            NotificationType.Key.ownedCryptoIdentity: self.contactIdentity.ownedIdentity.cryptoIdentity,
                            NotificationType.Key.publishedIdentityDetails: publishedIdentityDetails] as [String: Any]
            notificationDelegate.post(name: NotificationType.name, userInfo: userInfo)

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
        let photoServerKeyEncoded = photoServerKeyAndLabel?.key.encode().rawData
        try container.encodeIfPresent(photoServerKeyEncoded, forKey: .photoServerKeyEncoded)
        try container.encodeIfPresent(photoServerKeyAndLabel?.label, forKey: .photoServerLabel)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let serializedIdentityCoreDetailsAsString = try values.decode(String.self, forKey: .serializedIdentityCoreDetails)
        guard let serializedIdentityCoreDetailsAsData = serializedIdentityCoreDetailsAsString.data(using: .utf8) else {
            throw ContactIdentityDetailsPublishedBackupItem.makeError(message: "Could not create Data from serializedIdentityCoreDetailsAsString")
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
        let contactIdentityDetailsPublished = ContactIdentityDetailsPublished(backupItem: self, within: obvContext)
        try associations.associate(contactIdentityDetailsPublished, to: self)
    }

    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing do to here
    }

}
