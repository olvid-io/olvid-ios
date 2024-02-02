/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

extension ChannelCreationWithOwnedDeviceProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        case initial = 0
        case ping = 1
        case aliceIdentityAndEphemeralKey = 2
        case bobEphemeralKeyAndK1 = 3
        case k2 = 4
        case firstAck = 5
        case secondAck = 6
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial                      : return InitialMessage.self
            case .ping                         : return PingMessage.self
            case .aliceIdentityAndEphemeralKey : return AliceIdentityAndEphemeralKeyMessage.self
            case .bobEphemeralKeyAndK1         : return BobEphemeralKeyAndK1Message.self
            case .k2                           : return K2Message.self
            case .firstAck                     : return FirstAckMessage.self
            case .secondAck                    : return SecondAckMessage.self
            }
        }
    }

    
    // MARK: - InitialMessage
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initial
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let remoteDeviceUid: UID
        
        var encodedInputs: [ObvEncoded] {
            return [remoteDeviceUid.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            self.remoteDeviceUid = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, remoteDeviceUid: UID) {
            self.coreProtocolMessage = coreProtocolMessage
            self.remoteDeviceUid = remoteDeviceUid
        }
    }

    
    // MARK: - PingMessage
    
    struct PingMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.ping
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let remoteDeviceUid: UID
        let signature: Data
        
        var encodedInputs: [ObvEncoded] {
            return [remoteDeviceUid.obvEncode(), signature.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (remoteDeviceUid, signature) = try encodedElements.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, remoteDeviceUid: UID, signature: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.remoteDeviceUid = remoteDeviceUid
            self.signature = signature
        }
    }

    
    // MARK: - AliceIdentityAndEphemeralKeyMessage
    
    struct AliceIdentityAndEphemeralKeyMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.aliceIdentityAndEphemeralKey
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let remoteDeviceUid: UID
        let signature: Data
        let remoteEphemeralPublicKey: PublicKeyForPublicKeyEncryption
        
        var encodedInputs: [ObvEncoded] {
            return [remoteDeviceUid.obvEncode(), signature.obvEncode(), remoteEphemeralPublicKey.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 3 else {
                throw ChannelCreationWithOwnedDeviceProtocol.makeError(message: "Expecting 3 encoded elements in AliceIdentityAndEphemeralKeyMessage, got \(encodedElements.count)")
            }
            remoteDeviceUid = try encodedElements[0].obvDecode()
            signature = try encodedElements[1].obvDecode()
            guard let pk = PublicKeyForPublicKeyEncryptionDecoder.obvDecode(encodedElements[2]) else {
                throw Self.makeError(message: "Could not decode public key in AliceIdentityAndEphemeralKeyMessage")
            }
            remoteEphemeralPublicKey = pk
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, remoteDeviceUid: UID, signature: Data, remoteEphemeralPublicKey: PublicKeyForPublicKeyEncryption) {
            self.coreProtocolMessage = coreProtocolMessage
            self.remoteDeviceUid = remoteDeviceUid
            self.signature = signature
            self.remoteEphemeralPublicKey = remoteEphemeralPublicKey
        }
    }

    
    // MARK: - BobEphemeralKeyAndK1Message
    
    struct BobEphemeralKeyAndK1Message: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.bobEphemeralKeyAndK1
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let remoteEphemeralPublicKey: PublicKeyForPublicKeyEncryption
        let c1: EncryptedData
        
        var encodedInputs: [ObvEncoded] {
            return [remoteEphemeralPublicKey.obvEncode(), c1.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 2 else {
                throw ChannelCreationWithOwnedDeviceProtocol.makeError(message: "Expecting 2 encoded elements in BobEphemeralKeyAndK1Message, got \(encodedElements.count)")
            }
            guard let pk = PublicKeyForPublicKeyEncryptionDecoder.obvDecode(encodedElements[0]) else {
                throw Self.makeError(message: "Could not decode public key in BobEphemeralKeyAndK1Message")
            }
            remoteEphemeralPublicKey = pk
            c1 = try encodedElements[1].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, remoteEphemeralPublicKey: PublicKeyForPublicKeyEncryption, c1: EncryptedData) {
            self.coreProtocolMessage = coreProtocolMessage
            self.remoteEphemeralPublicKey = remoteEphemeralPublicKey
            self.c1 = c1
        }
    }

    
    // MARK: - K2Message
    
    struct K2Message: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.k2
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let c2: EncryptedData
        
        var encodedInputs: [ObvEncoded] {
            return [c2.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            c2 = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, c2: EncryptedData) {
            self.coreProtocolMessage = coreProtocolMessage
            self.c2 = c2
        }
    }

    
    // MARK: - FirstAckMessage
    
    struct FirstAckMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.firstAck
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let remoteIdentityDetailsElements: IdentityDetailsElements
        
        var encodedInputs: [ObvEncoded] {
            get throws {
                let encodedContactIdentityDetailsElements = try remoteIdentityDetailsElements.jsonEncode()
                return [encodedContactIdentityDetailsElements.obvEncode()]
            }
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedRemoteIdentityDetailsElements: Data = try message.encodedInputs.obvDecode()
            self.remoteIdentityDetailsElements = try IdentityDetailsElements(encodedRemoteIdentityDetailsElements)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, remoteIdentityDetailsElements: IdentityDetailsElements) {
            self.coreProtocolMessage = coreProtocolMessage
            self.remoteIdentityDetailsElements = remoteIdentityDetailsElements
        }
    }

    
    // MARK: - SecondAckMessage
    
    struct SecondAckMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.secondAck
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let remoteIdentityDetailsElements: IdentityDetailsElements

        var encodedInputs: [ObvEncoded] {
            get throws {
                let encodedContactIdentityDetailsElements = try remoteIdentityDetailsElements.jsonEncode()
                return [encodedContactIdentityDetailsElements.obvEncode()]
            }
        }

        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedRemoteIdentityDetailsElements: Data = try message.encodedInputs.obvDecode()
            self.remoteIdentityDetailsElements = try IdentityDetailsElements(encodedRemoteIdentityDetailsElements)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, remoteIdentityDetailsElements: IdentityDetailsElements) {
            self.coreProtocolMessage = coreProtocolMessage
            self.remoteIdentityDetailsElements = remoteIdentityDetailsElements
        }
    }

}

