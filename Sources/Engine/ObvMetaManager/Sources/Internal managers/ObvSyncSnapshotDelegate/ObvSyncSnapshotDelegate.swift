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
import ObvEncoder
import ObvCrypto
import OlvidUtils


public protocol ObvSyncSnapshotDelegate: ObvManager {
    
    func registerAppSnapshotableObject(_ appSnapshotableObject: ObvAppSnapshotable)
    func registerIdentitySnapshotableObject(_ identitySnapshotableObject: ObvIdentityManagerSnapshotable)

    func getSyncSnapshotNodeAsObvDictionary(context: ObvSyncSnapshot.Context) throws -> ObvDictionary

    func decodeSyncSnapshot(from obvDictionary: ObvDictionary, context: ObvSyncSnapshot.Context) throws -> ObvSyncSnapshot

    func syncEngineDatabaseThenUpdateAppDatabase(using obvSyncSnapshotNode: any ObvSyncSnapshotNode) async throws
    func requestServerToKeepDeviceActive(ownedCryptoId: ObvCryptoId, deviceUidToKeepActive: UID) async throws
    
    func getAdditionalInfosForProfileBackup(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws -> AdditionalInfosForProfileBackup

    func parseDeviceBackup(deviceBackupToParse: DeviceBackupToParse, flowId: OlvidUtils.FlowIdentifier) throws -> ObvTypes.ObvDeviceBackupFromServer
    func parseProfileBackup(profileCryptoId: ObvCryptoId, profileBackupToParse: ProfileBackupToParse, flowId: FlowIdentifier) async throws -> ObvProfileBackupFromServer

    // func makeObvSyncSnapshot(within obvContext: ObvContext) throws -> ObvSyncSnapshot
    
    // func newSyncDiffsToProcessOrShowToUser(_ diffs: Set<ObvSyncDiff>, withOtherOwnedDeviceUid: UID)

}
