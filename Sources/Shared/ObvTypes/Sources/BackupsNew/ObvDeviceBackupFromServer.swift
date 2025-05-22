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
import ObvCrypto


/// Structure sent from the engine to the App when the user requests the download of a device backup from the server.
///
/// Under the hood, this is a merge between the `ObvIdentityManagerDeviceSnapshotNode` produced by the identity manager, and the `AppDeviceSnapshotNode` produced by the app.
///
/// Equivalent of the ObvDeviceBackupForRestore structure on Android.
public struct ObvDeviceBackupFromServer: Sendable, Identifiable {

    public var version: Int
    public let profiles: [Profile]
    public let appNode: (any ObvSyncSnapshotNode)? // In practice, this is a AppDeviceSnapshotNode, which is a type known to the app only

    public let id = UUID()
    
    public struct Profile: Sendable, Identifiable {
        public let ownedCryptoId: ObvCryptoId
        public let isKeycloakManaged: Bool
        public let backupSeed: BackupSeed
        public let coreDetails: ObvIdentityCoreDetails
        public let encodedPhotoServerKeyAndLabel: Data?
        
        public var id: Data { ownedCryptoId.getIdentity() }
        
        public init(ownedCryptoId: ObvCryptoId, isKeycloakManaged: Bool, backupSeed: BackupSeed, coreDetails: ObvIdentityCoreDetails, encodedPhotoServerKeyAndLabel: Data?) {
            self.ownedCryptoId = ownedCryptoId
            self.isKeycloakManaged = isKeycloakManaged
            self.backupSeed = backupSeed
            self.coreDetails = coreDetails
            self.encodedPhotoServerKeyAndLabel = encodedPhotoServerKeyAndLabel
        }
        
    }
    
    
    private init(version: Int, profiles: [Profile], appNode: (any ObvSyncSnapshotNode)?) {
        self.version = version
        self.profiles = profiles
        self.appNode = appNode
    }
    
    
    public init(version: Int, profiles: [Profile]) {
        self.init(version: version, profiles: profiles, appNode: nil)
    }

    public func withAppNode(_ appNode: any ObvSyncSnapshotNode) -> Self {
        assert(self.appNode == nil)
        return .init(version: version,
                     profiles: self.profiles,
                     appNode: appNode)
    }

}


public enum ObvDeviceBackupFromServerKind: Sendable {
    // Device backup key found on this physical device
    case thisPhysicalDeviceHasNoBackupSeed
    case errorOccuredForFetchingBackupOfThisPhysicalDevice(error: Error)
    case thisPhysicalDevice(ObvDeviceBackupFromServer)
    // Device backup key found in the keychain
    case keychain(ObvDeviceBackupFromServer)
    case errorOccuredForFetchingBackupsFromKeychain(error: Error)
}
