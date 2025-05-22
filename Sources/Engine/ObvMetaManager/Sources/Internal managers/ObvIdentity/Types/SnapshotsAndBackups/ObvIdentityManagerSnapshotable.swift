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
import OlvidUtils
import ObvTypes


/// Implemented by the identity manager
public protocol ObvIdentityManagerSnapshotable: ObvSnapshotable {
    
    func getAdditionalInfosFromIdentityManagerForProfileBackup(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws -> AdditionalInfosFromIdentityManagerForProfileBackup
    func parseDeviceSnapshotNode(identityNode: any ObvSyncSnapshotNode, version: Int, flowId: FlowIdentifier) throws -> ObvDeviceBackupFromServer
    func parseProfileSnapshotNode(identityNode: any ObvSyncSnapshotNode, flowId: FlowIdentifier) async throws -> ObvProfileBackupFromServer.DataObtainedByParsingIdentityNode
    func ownedIdentityExistsOnThisDevice(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws -> Bool

}


