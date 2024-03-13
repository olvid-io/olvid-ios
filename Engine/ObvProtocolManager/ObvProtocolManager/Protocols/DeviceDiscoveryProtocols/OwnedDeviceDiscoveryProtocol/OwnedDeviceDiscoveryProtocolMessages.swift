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
import ObvEncoder
import ObvCrypto
import ObvMetaManager

// MARK: - Protocol Messages

extension OwnedDeviceDiscoveryProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initiateOwnedDeviceDiscovery = 0
        case serverQuery = 1
        case initiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDevice = 2
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initiateOwnedDeviceDiscovery                             : return InitiateOwnedDeviceDiscoveryMessage.self
            case .serverQuery                                              : return ServerQueryMessage.self
            case .initiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDevice: return InitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage.self
            }
        }

    }
    
    
    // MARK: - InitiateOwnedDeviceDiscoveryMessage
    
    struct InitiateOwnedDeviceDiscoveryMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateOwnedDeviceDiscovery
        let coreProtocolMessage: CoreProtocolMessage

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }

    }

    
    struct ServerQueryMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.serverQuery
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let ownedDeviceDiscoveryResult: ServerResponseOwnedDeviceDiscoveryResult? // Only set when the message is sent to this protocol, not when sending this message to the server
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            
            if let result = ServerResponseOwnedDeviceDiscoveryResult(encodedElements[0]) {
                self.ownedDeviceDiscoveryResult = result
            } else {
                // Try the legacy decoding
                let encodedEncryptedOwnedDeviceDiscoveryResult = encodedElements[0]
                guard let encryptedOwnedDeviceDiscoveryResult = EncryptedData(encodedEncryptedOwnedDeviceDiscoveryResult) else {
                    assertionFailure()
                    throw Self.makeError(message: "Failed to decode the encrypted result of the owned device discovery")
                }
                ownedDeviceDiscoveryResult = .success(encryptedOwnedDeviceDiscoveryResult: encryptedOwnedDeviceDiscoveryResult)
            }
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.ownedDeviceDiscoveryResult = nil
        }
    }
    
    
    // MARK: - InitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage
    
    struct InitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDevice
        let coreProtocolMessage: CoreProtocolMessage

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }

    }

}
