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
import ObvCrypto
import ObvMetaManager

// MARK: - Protocol Messages

extension OwnedIdentityDeletionProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initiateOwnedIdentityDeletion = 0
        case contactOwnedIdentityWasDeleted = 1
        case propagateGlobalOwnedIdentityDeletion = 2
        case deactivateOwnedDeviceServerQuery = 106
        case finalizeOwnedIdentityDeletion = 107
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initiateOwnedIdentityDeletion        : return InitiateOwnedIdentityDeletionMessage.self
            case .contactOwnedIdentityWasDeleted       : return ContactOwnedIdentityWasDeletedMessage.self
            case .deactivateOwnedDeviceServerQuery     : return DeactivateOwnedDeviceServerQueryMessage.self
            case .propagateGlobalOwnedIdentityDeletion : return PropagateGlobalOwnedIdentityDeletionMessage.self
            case .finalizeOwnedIdentityDeletion        : return FinalizeOwnedIdentityDeletionMessage.self
            }
        }
    }
    
    
    // MARK: - InitiateOwnedIdentityDeletionMessage
    
    struct InitiateOwnedIdentityDeletionMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateOwnedIdentityDeletion
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let globalOwnedIdentityDeletion: Bool
        
        // Init when sending this message
        
        init(coreProtocolMessage: CoreProtocolMessage, globalOwnedIdentityDeletion: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.globalOwnedIdentityDeletion = globalOwnedIdentityDeletion
        }
        
        var encodedInputs: [ObvEncoded] {
            [globalOwnedIdentityDeletion.obvEncode()]
        }
        
        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.globalOwnedIdentityDeletion = try message.encodedInputs[0].obvDecode()
        }
        
    }

    
    // MARK: - PropagateGlobalOwnedIdentityDeletionMessage

    struct PropagateGlobalOwnedIdentityDeletionMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateGlobalOwnedIdentityDeletion
        let coreProtocolMessage: CoreProtocolMessage
                
        // Init when sending this message
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }
        
        var encodedInputs: [ObvEncoded] {
            []
        }
        
        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
    }

    
    // MARK: - FinalizeOwnedIdentityDeletionMessage
    
    struct FinalizeOwnedIdentityDeletionMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.finalizeOwnedIdentityDeletion
        let coreProtocolMessage: CoreProtocolMessage
        
        // Init when sending this message
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }
        
        var encodedInputs: [ObvEncoded] {
            []
        }
        
        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
    }

    
    // MARK: - ContactOwnedIdentityWasDeletedMessage

    /// Sent by the owned identity that is deleted to each contact, so that they can make sure they also properly delete it (remove it from groups, etc.)
    struct ContactOwnedIdentityWasDeletedMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.contactOwnedIdentityWasDeleted
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let deletedContactOwnedIdentity: ObvCryptoIdentity
        let signature: Data

        // Init when sending this message
        
        init(coreProtocolMessage: CoreProtocolMessage, deletedContactOwnedIdentity: ObvCryptoIdentity, signature: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.deletedContactOwnedIdentity = deletedContactOwnedIdentity
            self.signature = signature
        }
        
        var encodedInputs: [ObvEncoded] {
            [deletedContactOwnedIdentity.obvEncode(), signature.obvEncode()]
        }
        
        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.deletedContactOwnedIdentity = try message.encodedInputs[0].obvDecode()
            self.signature = try message.encodedInputs[1].obvDecode()
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

}
