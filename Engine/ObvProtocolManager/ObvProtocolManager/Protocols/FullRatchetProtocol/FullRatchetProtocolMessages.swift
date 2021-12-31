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
import ObvEncoder
import ObvTypes
import ObvCrypto

// MARK: - Protocol Messages

extension FullRatchetProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        case Initial = 0
        case AliceEphemeralKey = 1
        case BobEphemeralKeyAndK1 = 2
        case AliceK2 = 3
        case BobAck = 4
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .Initial              : return InitialMessage.self
            case .AliceEphemeralKey    : return AliceEphemeralKeyMessage.self
            case .BobEphemeralKeyAndK1 : return BobEphemeralKeyAndK1Message.self
            case .AliceK2              : return AliceK2Message.self
            case .BobAck               : return BobAckMessage.self
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
    
    
    // MARK: - AliceEphemeralKeyMessage
    
    struct AliceEphemeralKeyMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.AliceEphemeralKey
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactEphemeralPublicKey: PublicKeyForPublicKeyEncryption
        let restartCounter: Int
        
        var encodedInputs: [ObvEncoded] {
            return [contactEphemeralPublicKey.encode(), restartCounter.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 2 else { assertionFailure(); throw NSError() }
            guard let pk = PublicKeyForPublicKeyEncryptionDecoder.decode(encodedElements[0]) else { assertionFailure(); throw NSError() }
            contactEphemeralPublicKey = pk
            restartCounter = try encodedElements[1].decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactEphemeralPublicKey: PublicKeyForPublicKeyEncryption, restartCounter: Int) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactEphemeralPublicKey = contactEphemeralPublicKey
            self.restartCounter = restartCounter
        }
        
    }
    
    
    // MARK: - BobEphemeralKeyAndK1Message
    
    struct BobEphemeralKeyAndK1Message: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.BobEphemeralKeyAndK1
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactEphemeralPublicKey: PublicKeyForPublicKeyEncryption
        let c1: EncryptedData
        let restartCounter: Int

        var encodedInputs: [ObvEncoded] {
            return [contactEphemeralPublicKey.encode(), c1.encode(), restartCounter.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 3 else { assertionFailure(); throw NSError() }
            guard let pk = PublicKeyForPublicKeyEncryptionDecoder.decode(encodedElements[0]) else { assertionFailure(); throw NSError() }
            contactEphemeralPublicKey = pk
            c1 = try encodedElements[1].decode()
            restartCounter = try encodedElements[2].decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactEphemeralPublicKey: PublicKeyForPublicKeyEncryption, c1: EncryptedData, restartCounter: Int) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactEphemeralPublicKey = contactEphemeralPublicKey
            self.c1 = c1
            self.restartCounter = restartCounter
        }

    }
    
    
    // MARK: - AliceK2Message
    
    struct AliceK2Message: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.AliceK2
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let c2: EncryptedData
        let restartCounter: Int

        var encodedInputs: [ObvEncoded] {
            return [c2.encode(), restartCounter.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 2 else { assertionFailure(); throw NSError() }
            c2 = try encodedElements[0].decode()
            restartCounter = try encodedElements[1].decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, c2: EncryptedData, restartCounter: Int) {
            self.coreProtocolMessage = coreProtocolMessage
            self.c2 = c2
            self.restartCounter = restartCounter
        }

    }
    
    
    // MARK: - BobAckMessage
    
    struct BobAckMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.BobAck
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let restartCounter: Int

        var encodedInputs: [ObvEncoded] {
            return [restartCounter.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            restartCounter = try message.encodedInputs.decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, restartCounter: Int) {
            self.coreProtocolMessage = coreProtocolMessage
            self.restartCounter = restartCounter
        }

    }
    
}
