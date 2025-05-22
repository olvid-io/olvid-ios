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
@preconcurrency import ObvCrypto
import ObvEncoder


/// Structure sent from the engine to the App when the user requests the download of a profile backup from the server.
public struct ObvProfileBackupFromServer: Sendable, Identifiable {
    
    public let id: Data
    public let ownedCryptoId: ObvCryptoId
    public let profileExistsOnThisDevice: Bool
    public let parsedData: DataObtainedByParsingIdentityNode
    public let identityNode: any ObvSyncSnapshotNode // In practice, an ObvIdentityManagerSyncSnapshotNode which is a type known to the identity manager only
    public let appNode: (any ObvSyncSnapshotNode)
    public let additionalInfosForProfileBackup: AdditionalInfosForProfileBackup
    public let creationDate: Date
    public let infoForDeletion: InfoForDeletion
    public let backupMadeByThisDevice: Bool
    
    public struct InfoForDeletion: Sendable, Identifiable {
        public let ownedCryptoId: ObvCryptoId
        public let backupSeed: BackupSeed
        public let threadUID: UID
        public let backupVersion: Int
        public var serverURL: URL { ownedCryptoId.cryptoIdentity.serverURL }
        public var id: Data {
            [
                ownedCryptoId.obvEncode(),
                backupSeed.obvEncode(),
                threadUID.obvEncode(),
                backupVersion.obvEncode(),
            ].obvEncode().rawData
        }
    }
    
    var serverURL: URL {
        ownedCryptoId.cryptoIdentity.serverURL
    }

    public struct DataObtainedByParsingIdentityNode: Sendable {
        public let numberOfGroups: Int
        public let numberOfContacts: Int
        public let isKeycloakManaged: IsKeycloakManaged
        public let encodedPhotoServerKeyAndLabel: Data?
        public let ownedCryptoIdentity: ObvOwnedCryptoIdentity
        public let coreDetails: ObvIdentityCoreDetails

        public enum IsKeycloakManaged: Sendable {
            case no
            case yes(keycloakConfiguration: ObvKeycloakConfiguration, isTransferRestricted: Bool)
        }
        
        public init(numberOfGroups: Int, numberOfContacts: Int, isKeycloakManaged: IsKeycloakManaged, encodedPhotoServerKeyAndLabel: Data?, ownedCryptoIdentity: ObvOwnedCryptoIdentity, coreDetails: ObvIdentityCoreDetails) {
            self.numberOfGroups = numberOfGroups
            self.numberOfContacts = numberOfContacts
            self.isKeycloakManaged = isKeycloakManaged
            self.encodedPhotoServerKeyAndLabel = encodedPhotoServerKeyAndLabel
            self.ownedCryptoIdentity = ownedCryptoIdentity
            self.coreDetails = coreDetails
        }
        
    }
    
    public init(ownedCryptoId: ObvCryptoId, profileExistsOnThisDevice: Bool, parsedData: DataObtainedByParsingIdentityNode, identityNode: any ObvSyncSnapshotNode, appNode: any ObvSyncSnapshotNode, additionalInfosForProfileBackup: AdditionalInfosForProfileBackup, creationDate: Date, backupSeed: BackupSeed, threadUID: UID, backupVersion: Int, backupMadeByThisDevice: Bool) {
        self.profileExistsOnThisDevice = profileExistsOnThisDevice
        self.parsedData = parsedData
        self.identityNode = identityNode
        self.appNode = appNode
        self.additionalInfosForProfileBackup = additionalInfosForProfileBackup
        self.creationDate = creationDate
        self.ownedCryptoId = ownedCryptoId
        self.infoForDeletion = InfoForDeletion(
            ownedCryptoId: ownedCryptoId,
            backupSeed: backupSeed,
            threadUID: threadUID,
            backupVersion: backupVersion)
        self.id = infoForDeletion.id
        self.backupMadeByThisDevice = backupMadeByThisDevice
    }

}
