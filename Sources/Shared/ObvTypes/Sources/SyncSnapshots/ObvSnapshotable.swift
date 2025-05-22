/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

/// Equivalent of ObvBackupAndSyncDelegate in the Android code
/// See also `ObvBackupable` in `OlvidUtils`
public protocol ObvSnapshotable: AnyObject {
    
    func getSyncSnapshotNode(for context: ObvSyncSnapshot.Context) throws -> any ObvSyncSnapshotNode
    func serializeObvSyncSnapshotNode(_ syncSnapshotNode: any ObvSyncSnapshotNode) throws -> Data
    func deserializeObvSyncSnapshotNode(_ serializedSyncSnapshotNode: Data, context: ObvSyncSnapshot.Context) throws -> any ObvSyncSnapshotNode
    
}


/// Note: the `ObvIdentityManagerSnapshotable` (implemented by the identity manager) is declared in the meta manager

/// Implemented by the app
public protocol ObvAppSnapshotable: ObvSnapshotable {
    
    func syncEngineDatabaseThenUpdateAppDatabase(using syncSnapshotNode: any ObvSyncSnapshotNode) async throws
    func requestServerToKeepDeviceActive(ownedCryptoId: ObvCryptoId, deviceUidToKeepActive: UID) async throws
    func getAdditionalInfosFromAppForProfileBackup(ownedCryptoId: ObvCryptoId) async throws -> AdditionalInfosFromAppForProfileBackup

}
