/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


public protocol ObvBackupDelegate: ObvManager {

    var isBackupRequired: Bool { get }
    func registerAllBackupableManagers(_ allBackupableManagers: [ObvBackupableManager])
    func registerAppBackupableObject(_ appBackupableObject: ObvBackupable)
    func generateNewBackupKey(flowId: FlowIdentifier)
    func verifyBackupKey(backupSeedString: String, flowId: FlowIdentifier, completion: @escaping (Result<Void,Error>) -> Void)
    func initiateBackup(forExport: Bool, backupRequestIdentifier: FlowIdentifier) throws
    func getBackupKeyInformation(flowId: FlowIdentifier) throws -> BackupKeyInformation?
    func markBackupAsExported(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws
    func markBackupAsUploaded(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws
    func markBackupAsFailed(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws
    func recoverBackupData(_: Data, withBackupKey: String, backupRequestIdentifier: FlowIdentifier, completion: @escaping (Result<(backupRequestIdentifier: UUID, backupDate: Date),BackupRestoreError>) -> Void)
    func restoreFullBackup(backupRequestIdentifier: FlowIdentifier, completionHandler: @escaping ((Result<Void,Error>) -> Void))
    func userJustActivatedAutomaticBackup()

}