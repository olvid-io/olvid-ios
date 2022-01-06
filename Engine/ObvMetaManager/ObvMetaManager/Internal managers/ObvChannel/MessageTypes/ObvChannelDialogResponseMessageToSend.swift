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

import ObvEncoder
import ObvCrypto

/// Public structure that is intended to be used by the User Interface to report back on the choice made by the user to a previous `ObvChannelDialogMessageToSend`
public struct ObvChannelDialogResponseMessageToSend: ObvChannelMessageToSend {
    
    public let messageType = ObvChannelMessageType.DialogResponseMessage
    
    public let channelType: ObvChannelSendChannelType
    
    public let encodedElements: ObvEncoded

    public let uuid: UUID

    public let encodedUserDialogResponse: ObvEncoded
    
    public let timestamp: Date
        
    public init(uuid: UUID, toOwnedIdentity ownedIdentity: ObvCryptoIdentity, timestamp: Date, encodedUserDialogResponse: ObvEncoded, encodedElements: ObvEncoded) {
        self.channelType = .Local(ownedIdentity: ownedIdentity)
        self.encodedUserDialogResponse = encodedUserDialogResponse
        self.encodedElements = encodedElements
        self.uuid = uuid
        self.timestamp = timestamp
    }
}
