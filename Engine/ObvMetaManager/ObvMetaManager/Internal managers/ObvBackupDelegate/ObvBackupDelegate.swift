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
import OlvidUtils
import ObvCrypto

public protocol ObvBackupDelegate: ObvManager {

    var isBackupRequired: Bool { get }
    func registerAllBackupableManagers(_ allBackupableManagers: [ObvBackupableManager])
    func registerAppBackupableObject(_ appBackupableObject: ObvBackupable)
    func generateNewBackupKey(flowId: FlowIdentifier)
    func verifyBackupKey(backupSeedString: String, flowId: FlowIdentifier) async throws -> Bool
    func initiateBackup(forExport: Bool, backupRequestIdentifier: FlowIdentifier) async throws -> (backupKeyUid: UID, version: Int, encryptedContent: Data)
    func getBackupKeyInformation(flowId: FlowIdentifier) throws -> BackupKeyInformation?
    func markBackupAsExported(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws
    func markBackupAsUploaded(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws
    func markBackupAsFailed(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws
    func recoverBackupData(_: Data, withBackupKey: String, backupRequestIdentifier: FlowIdentifier) async throws -> (backupRequestIdentifier: UUID, backupDate: Date)
    func restoreFullBackup(backupRequestIdentifier: FlowIdentifier) async throws
    func userJustActivatedAutomaticBackup()

}
