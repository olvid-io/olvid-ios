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

public struct BackupKeyInformation {
    
    public let uid: UID
    public let keyGenerationTimestamp: Date
    public let lastSuccessfulKeyVerificationTimestamp: Date?
    public let successfulVerificationCount: Int
    public let lastBackupExportTimestamp: Date?
    public let lastBackupUploadTimestamp: Date?
    public let lastBackupUploadFailureTimestamp: Date?
    
    public init(uid: UID, keyGenerationTimestamp: Date, lastSuccessfulKeyVerificationTimestamp: Date?, successfulVerificationCount: Int, lastBackupExportTimestamp: Date?, lastBackupUploadTimestamp: Date?, lastBackupUploadFailureTimestamp: Date?) {
        self.uid = uid
        self.keyGenerationTimestamp = keyGenerationTimestamp
        self.lastSuccessfulKeyVerificationTimestamp = lastSuccessfulKeyVerificationTimestamp
        self.successfulVerificationCount = successfulVerificationCount
        self.lastBackupExportTimestamp = lastBackupExportTimestamp
        self.lastBackupUploadTimestamp = lastBackupUploadTimestamp
        self.lastBackupUploadFailureTimestamp = lastBackupUploadFailureTimestamp
    }
    
}
