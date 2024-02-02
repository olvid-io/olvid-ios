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
import ObvTypes
import JWS

// MARK: - Protocol Messages

extension KeycloakBindingAndUnbindingProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case ownedIdentityKeycloakBinding = 0
        case ownedIdentityKeycloakUnbinding = 1
        case propagateKeycloakBinding = 2
        case propagateKeycloakUnbinding = 3
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .ownedIdentityKeycloakBinding   : return OwnedIdentityKeycloakBindingMessage.self
            case .ownedIdentityKeycloakUnbinding : return OwnedIdentityKeycloakUnbindingMessage.self
            case .propagateKeycloakBinding       : return PropagateKeycloakBindingMessage.self
            case .propagateKeycloakUnbinding     : return PropagateKeycloakUnbindingMessage.self
            }
        }

    }
    
    
    // MARK: - OwnedIdentityKeycloakBindingMessage
    
    struct OwnedIdentityKeycloakBindingMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.ownedIdentityKeycloakBinding
        let coreProtocolMessage: CoreProtocolMessage

        let keycloakState: ObvKeycloakState
        let keycloakUserId: String
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, keycloakState: ObvKeycloakState, keycloakUserId: String) {
            self.coreProtocolMessage = coreProtocolMessage
            self.keycloakState = keycloakState
            self.keycloakUserId = keycloakUserId
        }

        var encodedInputs: [ObvEncoded] {
            get throws {
                return [try keycloakState.obvEncode(), keycloakUserId.obvEncode()]
            }
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (keycloakState, keycloakUserId) = try encodedElements.obvDecode()
        }

    }

    
    // MARK: - OwnedIdentityKeycloakUnbindingMessage
    
    struct OwnedIdentityKeycloakUnbindingMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.ownedIdentityKeycloakUnbinding
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

    
    // MARK: - PropagateKeycloakBindingMessage
    
    struct PropagateKeycloakBindingMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateKeycloakBinding
        let coreProtocolMessage: CoreProtocolMessage

        let keycloakState: ObvKeycloakState
        let keycloakUserId: String

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, keycloakUserId: String, keycloakState: ObvKeycloakState) {
            assert(keycloakState.signatureVerificationKey != nil, "signatureVerificationKey is expected to be non-nil during a binding process")
            self.coreProtocolMessage = coreProtocolMessage
            self.keycloakState = keycloakState
            self.keycloakUserId = keycloakUserId
        }

        var encodedInputs: [ObvEncoded] {
            get throws {
                guard let signatureVerificationKey = keycloakState.signatureVerificationKey else {
                    assertionFailure()
                    throw Self.makeError(message: "The signatureVerificationKey is expected to be non nil")
                }
                return [
                    keycloakUserId.obvEncode(),
                    keycloakState.keycloakServer.obvEncode(),
                    keycloakState.clientId.obvEncode(),
                    keycloakState.clientSecret?.obvEncode() ?? "".obvEncode(),
                    try keycloakState.jwks.obvEncode(),
                    try signatureVerificationKey.obvEncode(),
                ]
            }
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 6 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.keycloakUserId = try message.encodedInputs[0].obvDecode()
            let keycloakServer: URL = try message.encodedInputs[1].obvDecode()
            let clientId: String = try message.encodedInputs[2].obvDecode()
            let clientSecret: String = try message.encodedInputs[3].obvDecode()
            let jwks: ObvJWKSet = try message.encodedInputs[4].obvDecode()
            let signatureVerificationKey: ObvJWK  = try message.encodedInputs[5].obvDecode()
            self.keycloakState = ObvKeycloakState(
                keycloakServer: keycloakServer,
                clientId: clientId,
                clientSecret: clientSecret.isEmpty ? nil : clientSecret,
                jwks: jwks,
                rawAuthState: nil,
                signatureVerificationKey: signatureVerificationKey,
                latestLocalRevocationListTimestamp: nil,
                latestGroupUpdateTimestamp: nil)
        }

    }

    
    // MARK: - PropagateKeycloakUnbindingMessage
    
    struct PropagateKeycloakUnbindingMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateKeycloakUnbinding
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
