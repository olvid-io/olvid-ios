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
import ObvEncoder
import ObvTypes
import ObvCrypto

/// This internal structure's purpose is to parse the encoded elements contained in an `ObvProtocolReceivedMessage`. This allows to recover the protocol instance UID that this protocol message targets. If a matching protocol instance is found in DB, we will be able to recover its type. Given this type and the protocolMessageRawId, we will be able to instantiate a concrete received message (in which the `encodedInputs` will be decoded to specific types, specified within the concrete received message class). Given this specific protocol message and the state the protocol instance is currently in, we will be able so determine if this message allows to execute a new step for this protocol instance or not.
struct GenericReceivedProtocolMessage {
    
    let receptionChannelInfo: ObvProtocolReceptionChannelInfo
    let toOwnedIdentity: ObvCryptoIdentity
    let timestamp: Date

    let protocolInstanceUid: UID
    let protocolMessageRawId: Int
    let cryptoProtocolId: CryptoProtocolId
    let encodedInputs: [ObvEncoded]
    let encodedUserDialogResponse: ObvEncoded? // Only set when the message is the response to a UI dialog
    let userDialogUuid: UUID? // Only set when the message is the response to a UI dialog
    let receivedMessageUID: UID? // When instantiated with an ObvProtocolReceivedMessage, this is the UID of its MessageIdentifier. Otherwise it's nil
    
    // Instantiating a `GenericProtocolMessage` when receiving an `ObvProtocolReceivedMessage`

    init?(with obvProtocolReceivedMessage: ObvProtocolReceivedMessage) {
        guard let (cryptoProtocolId, protocolInstanceUid, protocolMessageRawId, encodedInputs) = GenericReceivedProtocolMessage.decode(obvProtocolReceivedMessage.encodedElements) else {
            return nil
        }
        self.encodedInputs = encodedInputs
        self.receptionChannelInfo = obvProtocolReceivedMessage.receptionChannelInfo
        self.toOwnedIdentity = obvProtocolReceivedMessage.messageId.ownedCryptoIdentity
        self.protocolInstanceUid = protocolInstanceUid
        self.protocolMessageRawId = protocolMessageRawId
        self.cryptoProtocolId = cryptoProtocolId
        self.encodedUserDialogResponse = nil
        self.userDialogUuid = nil
        self.timestamp = obvProtocolReceivedMessage.timestamp
        self.receivedMessageUID = obvProtocolReceivedMessage.messageId.uid
    }
    
    init?(with obvProtocolReceivedDialogResponse: ObvProtocolReceivedDialogResponse) {
        guard let (cryptoProtocolId, protocolInstanceUid, protocolMessageRawId, encodedInputs) = GenericReceivedProtocolMessage.decode(obvProtocolReceivedDialogResponse.encodedElements) else {
            return nil
        }
        self.encodedInputs = encodedInputs
        self.receptionChannelInfo = obvProtocolReceivedDialogResponse.receptionChannelInfo
        self.toOwnedIdentity = obvProtocolReceivedDialogResponse.toOwnedIdentity
        self.protocolInstanceUid = protocolInstanceUid
        self.protocolMessageRawId = protocolMessageRawId
        self.cryptoProtocolId = cryptoProtocolId
        self.encodedUserDialogResponse = obvProtocolReceivedDialogResponse.encodedUserDialogResponse
        self.userDialogUuid = obvProtocolReceivedDialogResponse.dialogUuid
        self.timestamp = obvProtocolReceivedDialogResponse.timestamp
        self.receivedMessageUID = nil
    }
    
    init?(with obvProtocolReceivedServerResponse: ObvProtocolReceivedServerResponse) {
        guard let (cryptoProtocolId, protocolInstanceUid, protocolMessageRawId, encodedInputs) = GenericReceivedProtocolMessage.decode(obvProtocolReceivedServerResponse.encodedElements) else {
            return nil
        }
        self.encodedInputs = encodedInputs +  obvProtocolReceivedServerResponse.serverResponseType.getEncodedInputs()
        self.receptionChannelInfo = obvProtocolReceivedServerResponse.receptionChannelInfo
        self.toOwnedIdentity = obvProtocolReceivedServerResponse.toOwnedIdentity
        self.protocolInstanceUid = protocolInstanceUid
        self.protocolMessageRawId = protocolMessageRawId
        self.cryptoProtocolId = cryptoProtocolId
        self.encodedUserDialogResponse = nil
        self.userDialogUuid = nil
        self.timestamp = obvProtocolReceivedServerResponse.serverTimestamp
        self.receivedMessageUID = nil
    }

    
    private static func decode(_ encodedElements: ObvEncoded) -> (CryptoProtocolId, UID, Int, [ObvEncoded])? {
        guard let listOfEncoded = [ObvEncoded](encodedElements, expectedCount: 4) else { return nil }
        guard let cryptoProtocolRawId = Int(listOfEncoded[0]) else { return nil }
        guard let cryptoProtocolId = CryptoProtocolId(rawValue: cryptoProtocolRawId) else { return nil }
        guard let protocolInstanceUid = UID(listOfEncoded[1]) else { return nil }
        guard let protocolMessageRawId = Int(listOfEncoded[2]) else { return nil }
        guard let encodedInputs = [ObvEncoded](listOfEncoded[3]) else { return nil }
        return (cryptoProtocolId, protocolInstanceUid, protocolMessageRawId, encodedInputs)
    }
    
    init?(with message: ConcreteProtocolMessage) {
        guard let receptionChannelInfo = message.receptionChannelInfo else { return nil }
        guard let toOwnedIdentity = message.toOwnedIdentity else { return nil }
        self.timestamp = message.timestamp
        self.receptionChannelInfo = receptionChannelInfo
        self.toOwnedIdentity = toOwnedIdentity
        self.protocolInstanceUid = message.coreProtocolMessage.protocolInstanceUid
        self.protocolMessageRawId = message.id.rawValue
        self.cryptoProtocolId = message.cryptoProtocolId
        self.encodedInputs = message.encodedInputs
        self.encodedUserDialogResponse = nil
        self.userDialogUuid = nil
        self.receivedMessageUID = nil
    }
    
}


/// Within a protocol step, we often have to send a message to another party. This is always done by transmitting the message through a channel. This struct makes it easier to generate a `ObvChannelProtocolMessageToSend`.
struct GenericProtocolMessageToSend {
    
    // Instantiating a `GenericProtocolMessageToSend` so as to easily generate a `ObvChannelProtocolMessageToSend`

    public let channelType: ObvChannelSendChannelType
    
    public let encodedElements: ObvEncoded
    public let partOfFullRatchetProtocolOfTheSendSeed: Bool
    public let timestamp: Date

    init(channelType: ObvChannelSendChannelType, cryptoProtocolId: CryptoProtocolId, protocolInstanceUid: UID, protocolMessageRawId: Int, encodedInputs: [ObvEncoded], partOfFullRatchetProtocolOfTheSendSeed: Bool = false) {
        self.channelType = channelType
        self.encodedElements = GenericProtocolMessageToSend.encode(cryptoProtocolId: cryptoProtocolId,
                                                                   protocolInstanceUid: protocolInstanceUid,
                                                                   protocolMessageRawId: protocolMessageRawId,
                                                                   encodedInputs: encodedInputs)
        self.partOfFullRatchetProtocolOfTheSendSeed = partOfFullRatchetProtocolOfTheSendSeed
        self.timestamp = Date()
    }
 
    private static func encode(cryptoProtocolId: CryptoProtocolId, protocolInstanceUid: UID, protocolMessageRawId: Int, encodedInputs: [ObvEncoded]) -> ObvEncoded {
        let encodedElements = [cryptoProtocolId.rawValue.obvEncode(),
                               protocolInstanceUid.obvEncode(),
                               protocolMessageRawId.obvEncode(),
                               encodedInputs.obvEncode()].obvEncode()
        return encodedElements
    }
    
    func generateObvChannelProtocolMessageToSend(with prng: PRNGService) -> ObvChannelProtocolMessageToSend? {
        switch channelType {
        case .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity,
             .AllConfirmedObliviousChannelsWithContactIdentities,
             .AsymmetricChannel,
             .AsymmetricChannelBroadcast,
             .Local,
             .ObliviousChannel:
            return ObvChannelProtocolMessageToSend(channelType: channelType,
                                                   timestamp: timestamp,
                                                   encodedElements: encodedElements,
                                                   partOfFullRatchetProtocolOfTheSendSeed: partOfFullRatchetProtocolOfTheSendSeed)
        case .UserInterface,
             .ServerQuery:
            return nil
        }
    }
    
    func generateObvChannelDialogMessageToSend() -> ObvChannelDialogMessageToSend? {
        switch channelType {
        case .UserInterface(uuid: let uuid, ownedIdentity: let ownedIdentity, dialogType: let dialogType):
            return ObvChannelDialogMessageToSend(uuid: uuid,
                                                 ownedIdentity: ownedIdentity,
                                                 dialogType: dialogType,
                                                 encodedElements: encodedElements)
        default:
            return nil
        }
    }
    
    func generateObvChannelServerQueryMessageToSend(serverQueryType: ObvChannelServerQueryMessageToSend.QueryType) -> ObvChannelServerQueryMessageToSend? {
        switch channelType {
        case .ServerQuery(ownedIdentity: let ownedIdentity):
            return ObvChannelServerQueryMessageToSend(ownedIdentity: ownedIdentity,
                                                      serverQueryType: serverQueryType,
                                                      encodedElements: encodedElements)
        default:
            return nil
        }
    }
}
