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

import ObvMetaManager
import ObvCrypto
import ObvTypes

struct CoreProtocolMessage {
    
    let channelType: ObvChannelSendChannelType?                // Non nil when instantiating a message to send, nil otherwise
    let receptionChannelInfo: ObvProtocolReceptionChannelInfo? // Non nil when instantiating a received message, nil otherwise
    let toOwnedIdentity: ObvCryptoIdentity? // Non nil for received message, nil otherwise
    let cryptoProtocolId: CryptoProtocolId
    let protocolInstanceUid: UID
    let partOfFullRatchetProtocolOfTheSendSeed: Bool
    let timestamp: Date
    
    init(with message: ReceivedMessage) {
        self.channelType = nil
        self.receptionChannelInfo = message.receptionChannelInfo
        self.toOwnedIdentity = message.messageId.ownedCryptoIdentity
        self.protocolInstanceUid = message.protocolInstanceUid
        self.partOfFullRatchetProtocolOfTheSendSeed = false // Always false for received message, because this information only concerns the sending oblivious channel
        self.cryptoProtocolId = message.cryptoProtocolId
        self.timestamp = message.timestamp
    }
    
    init(channelType: ObvChannelSendChannelType, cryptoProtocolId: CryptoProtocolId, protocolInstanceUid: UID, partOfFullRatchetProtocolOfTheSendSeed: Bool = false) {
        self.channelType = channelType
        self.receptionChannelInfo = nil
        self.toOwnedIdentity = nil
        self.protocolInstanceUid = protocolInstanceUid
        self.partOfFullRatchetProtocolOfTheSendSeed = partOfFullRatchetProtocolOfTheSendSeed
        self.cryptoProtocolId = cryptoProtocolId
        self.timestamp = Date()
    }
}
