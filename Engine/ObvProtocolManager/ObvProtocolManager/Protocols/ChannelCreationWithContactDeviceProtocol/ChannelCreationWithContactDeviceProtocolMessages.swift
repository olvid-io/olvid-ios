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
import CoreData
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import ObvMetaManager


// MARK: - Protocol Messages

extension ChannelCreationWithContactDeviceProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        case Initial = 0
        case Ping = 1
        case AliceIdentityAndEphemeralKey = 2
        case BobEphemeralKeyAndK1 = 3
        case K2 = 4
        case FirstAck = 5
        case SecondAck = 6
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .Initial                      : return InitialMessage.self
            case .Ping                         : return PingMessage.self
            case .AliceIdentityAndEphemeralKey : return AliceIdentityAndEphemeralKeyMessage.self
            case .BobEphemeralKeyAndK1         : return BobEphemeralKeyAndK1Message.self
            case .K2                           : return K2Message.self
            case .FirstAck                     : return FirstAckMessage.self
            case .SecondAck                    : return SecondAckMessage.self
            }
        }
    }

    
    // MARK: - InitialMessage
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.Initial
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        
        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.encode(), contactDeviceUid.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            (contactIdentity, contactDeviceUid) = try message.encodedInputs.decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
        }
    }

    
    // MARK: - ContactMightNowBeTrustedMessage
    
    struct PingMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.Ping
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let signature: Data
        
        var encodedInputs: [ObvEncoded] { return [contactIdentity.encode(), contactDeviceUid.encode(), signature.encode()] }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (contactIdentity, contactDeviceUid, signature) = try encodedElements.decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, signature: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.signature = signature
        }
    }

    
    // MARK: - AliceIdentityAndEphemeralKeyMessage
    
    struct AliceIdentityAndEphemeralKeyMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.AliceIdentityAndEphemeralKey
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let signature: Data
        let contactEphemeralPublicKey: PublicKeyForPublicKeyEncryption
        
        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.encode(), contactDeviceUid.encode(), signature.encode(), contactEphemeralPublicKey.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 4 else { throw NSError() }
            contactIdentity = try encodedElements[0].decode()
            contactDeviceUid = try encodedElements[1].decode()
            signature = try encodedElements[2].decode()
            guard let pk = PublicKeyForPublicKeyEncryptionDecoder.decode(encodedElements[3]) else { throw NSError() }
            contactEphemeralPublicKey = pk
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, signature: Data, contactEphemeralPublicKey: PublicKeyForPublicKeyEncryption) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.signature = signature
            self.contactEphemeralPublicKey = contactEphemeralPublicKey
        }
    }

    
    // MARK: - BobEphemeralKeyAndK1Message
    
    struct BobEphemeralKeyAndK1Message: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.BobEphemeralKeyAndK1
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactEphemeralPublicKey: PublicKeyForPublicKeyEncryption
        let c1: EncryptedData
        
        var encodedInputs: [ObvEncoded] {
            return [contactEphemeralPublicKey.encode(), c1.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 2 else { throw NSError() }
            guard let pk = PublicKeyForPublicKeyEncryptionDecoder.decode(encodedElements[0]) else { throw NSError() }
            contactEphemeralPublicKey = pk
            c1 = try encodedElements[1].decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactEphemeralPublicKey: PublicKeyForPublicKeyEncryption, c1: EncryptedData) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactEphemeralPublicKey = contactEphemeralPublicKey
            self.c1 = c1
        }
    }

    
    // MARK: - K2Message
    
    struct K2Message: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.K2
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let c2: EncryptedData
        
        var encodedInputs: [ObvEncoded] {
            return [c2.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            c2 = try message.encodedInputs.decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, c2: EncryptedData) {
            self.coreProtocolMessage = coreProtocolMessage
            self.c2 = c2
        }
    }

    
    // MARK: - FirstAckMessage
    
    struct FirstAckMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.FirstAck
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentityDetailsElements: IdentityDetailsElements
        
        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityDetailsElements = try! contactIdentityDetailsElements.encode()
            return [encodedContactIdentityDetailsElements.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedContactIdentityDetailsElements: Data = try message.encodedInputs.decode()
            self.contactIdentityDetailsElements = try IdentityDetailsElements(encodedContactIdentityDetailsElements)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentityDetailsElements: IdentityDetailsElements) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentityDetailsElements = contactIdentityDetailsElements
        }
    }

    
    // MARK: - SecondAckMessage
    
    struct SecondAckMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.SecondAck
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentityDetailsElements: IdentityDetailsElements

        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityDetailsElements = try! contactIdentityDetailsElements.encode()
            return [encodedContactIdentityDetailsElements.encode()]
        }

        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedContactIdentityDetailsElements: Data = try message.encodedInputs.decode()
            self.contactIdentityDetailsElements = try IdentityDetailsElements(encodedContactIdentityDetailsElements)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentityDetailsElements: IdentityDetailsElements) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentityDetailsElements = contactIdentityDetailsElements
        }
    }

}
