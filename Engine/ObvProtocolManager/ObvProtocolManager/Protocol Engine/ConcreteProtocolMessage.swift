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
import ObvCrypto

protocol ConcreteProtocolMessage: GenericProtocolMessageToSendGenerator {
    
    var cryptoProtocolId: CryptoProtocolId { get }
    var id: ConcreteProtocolMessageId { get }
    
    // Initializer used when receiving a message
    init(with: ReceivedMessage) throws
    
    var coreProtocolMessage: CoreProtocolMessage { get }
    var receptionChannelInfo: ObvProtocolReceptionChannelInfo? { get }
    var toOwnedIdentity: ObvCryptoIdentity? { get }
    var timestamp: Date { get }
    
    // Used to easily implement a function generating a message to send
    var encodedInputs: [ObvEncoded] { get }
}

extension ConcreteProtocolMessage {
    
    var cryptoProtocolId: CryptoProtocolId {
        return coreProtocolMessage.cryptoProtocolId
    }
    
    var receptionChannelInfo: ObvProtocolReceptionChannelInfo? {
        return coreProtocolMessage.receptionChannelInfo
    }
    
    var toOwnedIdentity: ObvCryptoIdentity? {
        return coreProtocolMessage.toOwnedIdentity
    }
        
    var timestamp: Date {
        return coreProtocolMessage.timestamp
    }
    
    func generateGenericProtocolMessageToSend() -> GenericProtocolMessageToSend? {
        guard let channelType = coreProtocolMessage.channelType else { return nil }
        let genericProtocolMessageToSend =  GenericProtocolMessageToSend(channelType: channelType,
                                                                         cryptoProtocolId: cryptoProtocolId,
                                                                         protocolInstanceUid: coreProtocolMessage.protocolInstanceUid,
                                                                         protocolMessageRawId: id.rawValue,
                                                                         encodedInputs: encodedInputs,
                                                                         partOfFullRatchetProtocolOfTheSendSeed: coreProtocolMessage.partOfFullRatchetProtocolOfTheSendSeed)
        return genericProtocolMessageToSend
    }
    
    var description: String {
        return "<ConcreteProtocolMessage: [CryptoProtocolId: \(cryptoProtocolId.debugDescription)], [id: \(id.rawValue)], [receptionChannelInfo: \(receptionChannelInfo.debugDescription)]>"
    }
    
    static func makeError(message: String) -> Error { NSError(domain: String(describing: Self.self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

}

protocol ConcreteProtocolMessageId {
    
    var rawValue: Int { get }
    
    var concreteProtocolMessageType: ConcreteProtocolMessage.Type { get }
    
    func getConcreteProtocolMessage(with message: ReceivedMessage) -> ConcreteProtocolMessage?
}

extension ConcreteProtocolMessageId {
    
    func getConcreteProtocolMessage(with message: ReceivedMessage) -> ConcreteProtocolMessage? {
        return try? concreteProtocolMessageType.init(with: message)
    }
    
}
