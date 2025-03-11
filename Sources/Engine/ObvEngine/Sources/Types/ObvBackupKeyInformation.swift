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
import ObvTypes
import ObvMetaManager
import ObvCrypto


public struct ObvBackupKeyInformation {
    
    public let uid: UID
    public let keyGenerationTimestamp: Date
    public let lastSuccessfulKeyVerificationTimestamp: Date?
    public let successfulVerificationCount: Int
    public let lastBackupExportTimestamp: Date?
    public let lastBackupUploadTimestamp: Date?
    public let lastBackupUploadFailureTimestamp: Date?

    init(backupKeyInformation: BackupKeyInformation) {
        self.uid = backupKeyInformation.uid
        self.keyGenerationTimestamp = backupKeyInformation.keyGenerationTimestamp
        self.lastSuccessfulKeyVerificationTimestamp = backupKeyInformation.lastSuccessfulKeyVerificationTimestamp
        self.successfulVerificationCount = backupKeyInformation.successfulVerificationCount
        self.lastBackupExportTimestamp = backupKeyInformation.lastBackupExportTimestamp
        self.lastBackupUploadTimestamp = backupKeyInformation.lastBackupUploadTimestamp
        self.lastBackupUploadFailureTimestamp = backupKeyInformation.lastBackupUploadFailureTimestamp
    }
    
}
