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
import ObvEncoder
import ObvCrypto
import ObvMetaManager

// MARK: - Protocol Messages

extension OwnedDeviceManagementProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initiateOwnedDeviceManagement = 0
        case setOwnedDeviceNameServerQuery = 1
        case deactivateOwnedDeviceServerQuery = 2
        case setUnexpiringOwnedDeviceServerQuery = 3
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initiateOwnedDeviceManagement      : return InitiateOwnedDeviceManagementMessage.self
            case .setOwnedDeviceNameServerQuery      : return SetOwnedDeviceNameServerQueryMessage.self
            case .deactivateOwnedDeviceServerQuery   : return DeactivateOwnedDeviceServerQueryMessage.self
            case .setUnexpiringOwnedDeviceServerQuery: return SetUnexpiringOwnedDeviceServerQueryMessage.self
            }
        }

    }
    
    
    // MARK: - InitiateOwnedDeviceManagementMessage
    
    struct InitiateOwnedDeviceManagementMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateOwnedDeviceManagement
        let coreProtocolMessage: CoreProtocolMessage

        let request: ObvOwnedDeviceManagementRequest
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, request: ObvOwnedDeviceManagementRequest) {
            self.coreProtocolMessage = coreProtocolMessage
            self.request = request
        }

        var encodedInputs: [ObvEncoded] {
            return [request.obvEncode()]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            request = try message.encodedInputs.obvDecode()
        }

    }

    
    struct SetOwnedDeviceNameServerQueryMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.setOwnedDeviceNameServerQuery
        let coreProtocolMessage: CoreProtocolMessage

        let success: Bool // Only meaningfull when the message is sent to this protocol

        var encodedInputs: [ObvEncoded] { return [] }

        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            let encodedSuccess = encodedElements[0]
            guard let success = Bool(encodedSuccess) else {
                assertionFailure()
                throw Self.makeError(message: "Failed to decode")
            }
            self.success = success
        }

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.success = true
        }
    }


    struct DeactivateOwnedDeviceServerQueryMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.deactivateOwnedDeviceServerQuery
        let coreProtocolMessage: CoreProtocolMessage

        let success: Bool // Only meaningfull when the message is sent to this protocol

        var encodedInputs: [ObvEncoded] { return [] }

        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            let encodedSuccess = encodedElements[0]
            guard let success = Bool(encodedSuccess) else {
                assertionFailure()
                throw Self.makeError(message: "Failed to decode")
            }
            self.success = success
        }

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.success = true
        }
    }
    
    
    struct SetUnexpiringOwnedDeviceServerQueryMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.setUnexpiringOwnedDeviceServerQuery
        let coreProtocolMessage: CoreProtocolMessage

        let success: Bool // Only meaningfull when the message is sent to this protocol

        var encodedInputs: [ObvEncoded] { return [] }

        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            let encodedSuccess = encodedElements[0]
            guard let success = Bool(encodedSuccess) else {
                assertionFailure()
                throw Self.makeError(message: "Failed to decode")
            }
            self.success = success
        }

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.success = true
        }
    }

}
