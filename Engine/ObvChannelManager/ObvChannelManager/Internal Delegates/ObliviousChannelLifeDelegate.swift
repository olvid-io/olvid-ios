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
import ObvCrypto
import ObvTypes
import OlvidUtils


protocol ObliviousChannelLifeDelegate {
    
    func finalizeInitialization(within: ObvContext) throws
    
    func deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andTheDevicesOfContactIdentity: ObvCryptoIdentity, within: ObvContext) throws

    func deleteObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andTheRemoteDeviceWithUid: UID, ofRemoteIdentity: ObvCryptoIdentity, within: ObvContext) throws

    func deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: UID, andTheRemoteDeviceWithUid remoteDeviceUid: UID, ofRemoteIdentity remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws

    func createObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, with: Seed, cryptoSuiteVersion: Int, within: ObvContext) throws

    func confirmObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, within: ObvContext) throws

    func updateSendSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, with: Seed, within: ObvContext) throws

    func updateReceiveSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, with: Seed, within: ObvContext) throws

    func anObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, within: ObvContext) throws -> Bool

    func aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, within: ObvContext) throws -> Bool

    func aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, within: ObvContext) throws -> Bool
    
    func getAllConfirmedObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andTheDevicesOfTheRemoteIdentity: ObvCryptoIdentity, within: ObvContext) throws -> [UID]

}
