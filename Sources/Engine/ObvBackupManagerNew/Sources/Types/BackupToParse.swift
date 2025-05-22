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
import ObvServerInterface
import ObvMetaManager
import ObvEncoder
import ObvCrypto


public struct BackupToParse {
        
    private let item: BackupToDownloadAndDecrypt
    public let encodedSnapshotNode: ObvEncoded
    public let backupSeed: BackupSeed

    public var threadUID: UID { item.threadUID }
    public var version: Int { item.version }

    
    init(item: BackupToDownloadAndDecrypt, encodedSnapshotNode: ObvEncoded, backupSeed: BackupSeed) {
        self.item = item
        self.encodedSnapshotNode = encodedSnapshotNode
        self.backupSeed = backupSeed
    }

}
