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
import ObvEncoder
import ObvCrypto

/// Simple structure allowing to embed a device backup seed and the URL of the server where the backup are saved.
/// When saving this struct to the keychain, the device backup seed is stored in the `kSecValueData` of the
/// keychain item.
public struct ObvBackupSeedAndStorageServerURL: Hashable, Sendable {
    
    public let backupSeed: BackupSeed
    public let serverURLForStoringDeviceBackup: URL
    
    
    public init(backupSeed: BackupSeed, serverURLForStoringDeviceBackup: URL) {
        self.backupSeed = backupSeed
        self.serverURLForStoringDeviceBackup = serverURLForStoringDeviceBackup
    }

}
