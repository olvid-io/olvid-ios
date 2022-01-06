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
import ObvEncoder

/// Public structure that will be used within the protocol manager
public struct ObvChannelProtocolMessageToSend: ObvChannelMessageToSend {
    
    public let messageId: MessageIdentifier
    public let messageType = ObvChannelMessageType.ProtocolMessage
    public let timestamp: Date
    
    public let channelType: ObvChannelSendChannelType
    
    public let encodedElements: ObvEncoded
    public let partOfFullRatchetProtocolOfTheSendSeed: Bool
    
    public init(messageId: MessageIdentifier, channelType: ObvChannelSendChannelType, timestamp: Date, encodedElements: ObvEncoded, partOfFullRatchetProtocolOfTheSendSeed: Bool = false) {
        self.messageId = messageId
        self.channelType = channelType
        self.encodedElements = encodedElements
        self.timestamp = timestamp
        self.partOfFullRatchetProtocolOfTheSendSeed = partOfFullRatchetProtocolOfTheSendSeed
    }
    
}
