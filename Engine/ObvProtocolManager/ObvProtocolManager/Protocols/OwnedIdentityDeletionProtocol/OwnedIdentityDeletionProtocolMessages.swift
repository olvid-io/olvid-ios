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
import ObvMetaManager

// MARK: - Protocol Messages

extension OwnedIdentityDeletionProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initiateOwnedIdentityDeletion = 0
        case contactOwnedIdentityWasDeleted = 1
        case continueOwnedIdentityDeletion = 100
        case processOtherProtocolInstances = 101
        case processGroupsV1 = 102
        case processGroupsV2 = 103
        case processContacts = 104
        case processChannels = 105
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initiateOwnedIdentityDeletion  : return InitiateOwnedIdentityDeletionMessage.self
            case .continueOwnedIdentityDeletion  : return ContinueOwnedIdentityDeletionMessage.self
            case .processOtherProtocolInstances  : return ProcessOtherProtocolInstancesMessage.self
            case .processGroupsV1                : return ProcessGroupsV1Message.self
            case .processGroupsV2                : return ProcessGroupsV2Message.self
            case .processContacts                : return ProcessContactsMessage.self
            case .contactOwnedIdentityWasDeleted : return ContactOwnedIdentityWasDeletedMessage.self
            case .processChannels                : return ProcessChannelsMessage.self
            }
        }
    }
    
    
    // MARK: - InitiateOwnedIdentityDeletionMessage
    
    struct InitiateOwnedIdentityDeletionMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateOwnedIdentityDeletion
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let ownedCryptoIdentityToDelete: ObvCryptoIdentity
        let notifyContacts: Bool
        
        // Init when sending this message
        
        init(coreProtocolMessage: CoreProtocolMessage, ownedCryptoIdentityToDelete: ObvCryptoIdentity, notifyContacts: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.ownedCryptoIdentityToDelete = ownedCryptoIdentityToDelete
            self.notifyContacts = notifyContacts
        }
        
        var encodedInputs: [ObvEncoded] {
            [ownedCryptoIdentityToDelete.obvEncode(), notifyContacts.obvEncode()]
        }
        
        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.ownedCryptoIdentityToDelete = try message.encodedInputs[0].obvDecode()
            self.notifyContacts = try message.encodedInputs[1].obvDecode()
        }
        
    }
    
    
    // MARK: - ContinueOwnedIdentityDeletionMessage
    
    struct ContinueOwnedIdentityDeletionMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.continueOwnedIdentityDeletion
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
    
    
    // MARK: - ProcessOtherProtocolInstancesMessage
    
    struct ProcessOtherProtocolInstancesMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.processOtherProtocolInstances
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
    
    
    // MARK: - ProcessGroupsV1Message
    
    struct ProcessGroupsV1Message: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.processGroupsV1
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
    
    
    // MARK: - ProcessGroupsV2Message
    
    struct ProcessGroupsV2Message: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.processGroupsV2
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
    
    
    // MARK: - ProcessContactsMessage
    
    struct ProcessContactsMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.processContacts
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
    
    
    // MARK: - ProcessChannelsMessage
    
    struct ProcessChannelsMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.processChannels
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
