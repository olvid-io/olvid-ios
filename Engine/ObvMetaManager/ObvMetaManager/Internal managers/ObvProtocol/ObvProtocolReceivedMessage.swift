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
import ObvTypes
import ObvCrypto

public struct ObvProtocolReceivedMessage {
    
    public let receptionChannelInfo: ObvProtocolReceptionChannelInfo
    public let encodedElements: ObvEncoded // An encoded list containing three encoded items : the protocol instance UID, the protocol message raw id, and the encodedProtocolInstanceInputs
    public let messageId: ObvMessageIdentifier
    public let timestamp: Date // Either the messageUploadTimestampFromServer for messages received from the network, or a local timestamp otherwise

    public init(messageId: ObvMessageIdentifier, timestamp: Date, receptionChannelInfo: ObvProtocolReceptionChannelInfo, encodedElements: ObvEncoded) {
        self.receptionChannelInfo = receptionChannelInfo
        self.encodedElements = encodedElements
        self.messageId = messageId
        self.timestamp = timestamp
    }
}

public struct ObvProtocolReceivedDialogResponse {
    
    public let receptionChannelInfo: ObvProtocolReceptionChannelInfo
    public let encodedElements: ObvEncoded // An encoded list containing three encoded items : the protocol instance UID, the protocol message raw id, and the encodedProtocolInstanceInputs
    public let toOwnedIdentity: ObvCryptoIdentity
    public let encodedUserDialogResponse: ObvEncoded
    public let dialogUuid: UUID
    public let timestamp: Date

    public init(toOwnedIdentity: ObvCryptoIdentity, timestamp: Date, receptionChannelInfo: ObvProtocolReceptionChannelInfo, encodedElements: ObvEncoded, encodedUserDialogResponse: ObvEncoded, dialogUuid: UUID) {
        self.receptionChannelInfo = receptionChannelInfo
        self.encodedElements = encodedElements
        self.toOwnedIdentity = toOwnedIdentity
        self.encodedUserDialogResponse = encodedUserDialogResponse
        self.dialogUuid = dialogUuid
        self.timestamp = timestamp
    }
}

public struct ObvProtocolReceivedServerResponse {
    
    public let receptionChannelInfo: ObvProtocolReceptionChannelInfo
    public let encodedElements: ObvEncoded // An encoded list containing three encoded items : the protocol instance UID, the protocol message raw id, and the encodedProtocolInstanceInputs (from the server query)
    public let serverResponseType: ObvChannelServerResponseMessageToSend.ResponseType
    public let toOwnedIdentity: ObvCryptoIdentity
    public let serverTimestamp: Date
    
    public init(toOwnedIdentity: ObvCryptoIdentity, serverTimestamp: Date, receptionChannelInfo: ObvProtocolReceptionChannelInfo, encodedElements: ObvEncoded, serverResponseType: ObvChannelServerResponseMessageToSend.ResponseType) {
        self.receptionChannelInfo = receptionChannelInfo
        self.encodedElements = encodedElements
        self.serverResponseType = serverResponseType
        self.toOwnedIdentity = toOwnedIdentity
        self.serverTimestamp = serverTimestamp
    }
    
}
