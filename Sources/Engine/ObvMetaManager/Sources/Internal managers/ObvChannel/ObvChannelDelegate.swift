/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvEncoder
import OlvidUtils

public protocol ObvChannelDelegate: ObvManager {
    
    // Posting a channel message to send

    /// The returned set contains all the crypto identities to which the message was successfully posted.
    func postChannelMessage(_: ObvChannelMessageToSend, randomizedWith: PRNGService, within: ObvContext) throws -> [ObvMessageIdentifier: Set<ObvCryptoIdentity>]
    
    // Decrypting a user notification
    
    func decryptUserNotification(_: ObvNetworkReceivedMessageEncrypted, within: FlowIdentifier) throws -> ReceivedApplicationOrProtocolMessage
    
    // Oblivious Channels management
        
    func deleteObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andTheRemoteDeviceWithUid: UID, ofRemoteIdentity: ObvCryptoIdentity, within: ObvContext) throws
    
    func deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: UID, andTheRemoteDeviceWithUid remoteDeviceUid: UID, ofRemoteIdentity remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws
    
    func deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andTheDevicesOfContactIdentity: ObvCryptoIdentity, within: ObvContext) throws
    
    func createObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, with: Seed, cryptoSuiteVersion: Int, within: ObvContext) throws
    
    func confirmObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, within: ObvContext) throws
    
    func updateSendSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, with: Seed, within: ObvContext) throws
    
    func updateReceiveSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, with: Seed, within: ObvContext) throws
    
    /// Method used in both channel creation protocols. Used at bootstrap as well, to possibly restart a channel creation with the remote device
    func anObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, within: ObvContext) throws -> Bool
    
    /// Method used during bootstrap to possibly restart a channel creation with a remote **owned** device
    func anObliviousChannelExistsBetweenCurrentDeviceUid(_ currentDeviceUid: UID, andRemoteDeviceUid remoteDeviceUid: UID, of remoteIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws -> Bool

    func aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, withRemoteDeviceUid: UID, within: ObvContext) throws -> Bool

    func aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ObvCryptoIdentity, andRemoteIdentity: ObvCryptoIdentity, within: ObvContext) throws -> Bool

    func getRemoteDeviceUidsOfRemoteIdentity(_: ObvCryptoIdentity, forWhichAConfirmedObliviousChannelExistsWithTheCurrentDeviceOfOwnedIdentity ownedIdentity: ObvCryptoIdentity, within: ObvContext) throws -> [UID]
    
    func getDeviceUidsOfRemoteIdentitiesHavingConfirmedObliviousChannelWithTheCurrentDeviceOfOwnedIdentity(_ ownedIdentity: ObvCryptoIdentity, remoteIdentities: Set<ObvCryptoIdentity>, within obvContext: ObvContext) throws -> [ObvCryptoIdentity: Set<UID>]

    /// Method used when determining which Oblivious channels are obsolete.
    func getAllRemoteDeviceUidsAssociatedToAnObliviousChannel(within: ObvContext) throws -> Set<ObliviousChannelIdentifier>
    
    // Preparing for an owned identity deletion
    
    func deleteAllObliviousChannelsWithTheCurrentDeviceUid(_ currentDeviceUid: UID, within obvContext: ObvContext) throws

}
