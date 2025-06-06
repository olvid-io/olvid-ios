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
import ObvTypes
import OlvidUtils
import ObvCrypto

public protocol ObvLegacyBackupDelegate: ObvManager {

    var isBackupRequired: Bool { get }
    func registerAllBackupableManagers(_ allBackupableManagers: [ObvBackupableManager])
    func registerAppBackupableObject(_ appBackupableObject: ObvBackupable)
    func initiateBackup(forExport: Bool, backupRequestIdentifier: FlowIdentifier) async throws -> (backupKeyUid: UID, version: Int, encryptedContent: Data)
    func getBackupKeyInformation(flowId: FlowIdentifier) async throws -> BackupKeyInformation?
    func markLegacyBackupAsExported(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) async throws
    func markLegacyBackupAsUploaded(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) async throws
    func markLegacyBackupAsFailed(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) async throws
    func recoverBackupData(_: Data, withBackupKey: String, backupRequestIdentifier: FlowIdentifier) async throws -> (backupRequestIdentifier: UUID, backupDate: Date)
    func restoreFullBackup(backupRequestIdentifier: FlowIdentifier) async throws
    func userJustActivatedAutomaticBackup()
    func deleteAllAsUserMigratesToNewBackups(flowId: FlowIdentifier) async throws

}
