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

extension GroupInvitationProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initial = 0
        case groupInvitation = 1
        case dialogAcceptGroupInvitation = 2
        case invitationResponse = 3
        case propagateInvitationResponse = 4
        // We remove the TrustLevelIncreased case on 2022-01-27 when implementing the two-level address bool
        case dialogInformative = 6

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial                     : return InitialMessage.self
            case .groupInvitation             : return GroupInvitationMessage.self
            case .dialogAcceptGroupInvitation : return DialogAcceptGroupInvitationMessage.self
            case .invitationResponse          : return InvitationResponseMessage.self
            case .propagateInvitationResponse : return PropagateInvitationResponseMessage.self
            case .dialogInformative           : return DialogInformativeMessage.self
            }
        }
    }

    
    // MARK: - InitialMessage
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initial
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity
        let groupInformation: GroupInformation
        let membersAndPendingGroupMembers: Set<CryptoIdentityWithCoreDetails>
        
        var encodedInputs: [ObvEncoded] {
            let encodedMembers = (membersAndPendingGroupMembers.map { $0.obvEncode() }).obvEncode()
            return [contactIdentity.obvEncode(),
                    groupInformation.obvEncode(),
                    encodedMembers]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 3 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.contactIdentity = try message.encodedInputs[0].obvDecode()
            self.groupInformation = try message.encodedInputs[1].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[2]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded members") }
            self.membersAndPendingGroupMembers = try Set(listOfEncodedMembers.map { try $0.obvDecode() })
            
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, groupInformation: GroupInformation, membersAndPendingGroupMembers: Set<CryptoIdentityWithCoreDetails>) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.groupInformation = groupInformation
            self.membersAndPendingGroupMembers = membersAndPendingGroupMembers
        }

    }
    
    
    // MARK: - GroupInvitationMessage
    
    struct GroupInvitationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.groupInvitation
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupInformation: GroupInformation
        let pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>
        
        var encodedInputs: [ObvEncoded] {
            let encodedMembers = (pendingGroupMembers.map { $0.obvEncode() }).obvEncode()
            return [groupInformation.obvEncode(),
                    encodedMembers]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupInformation = try message.encodedInputs[0].obvDecode()
            guard let listOfEncodedMembers = [ObvEncoded](message.encodedInputs[1]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded members") }
            self.pendingGroupMembers = try Set(listOfEncodedMembers.map { try $0.obvDecode() })
            
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupInformation: GroupInformation, pendingGroupMembers: Set<CryptoIdentityWithCoreDetails>) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInformation = groupInformation
            self.pendingGroupMembers = pendingGroupMembers
        }
        
    }


    // MARK: - DialogAcceptGroupInvitationMessage
    
    struct DialogAcceptGroupInvitationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.dialogAcceptGroupInvitation
        let coreProtocolMessage: CoreProtocolMessage
        
        let dialogUuid: UUID // Only used when this protocol receives this message
        let invitationAccepted: Bool // Only used when this protocol receives this message
        
        var encodedInputs: [ObvEncoded] {
            return [invitationAccepted.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else { assertionFailure(); throw Self.makeError(message: "Failed to obtain encoded dialog response") }
            invitationAccepted = try encodedUserDialogResponse.obvDecode()
            guard let userDialogUuid = message.userDialogUuid else { assertionFailure(); throw Self.makeError(message: "Could not fin user dialog UUID") }
            dialogUuid = userDialogUuid
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = false // Not used
            dialogUuid = UUID() // Not used
        }
        
    }

    
    // MARK: - InvitationResponseMessage
    
    struct InvitationResponseMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.invitationResponse
        let coreProtocolMessage: CoreProtocolMessage
        
        let groupUid: UID
        let invitationAccepted: Bool

        var encodedInputs: [ObvEncoded] {
            return [groupUid.obvEncode(),
                    invitationAccepted.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.groupUid = try message.encodedInputs[0].obvDecode()
            self.invitationAccepted = try message.encodedInputs[1].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupUid: UID, invitationAccepted: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupUid = groupUid
            self.invitationAccepted = invitationAccepted
        }
        
    }

    
    // MARK: - InvitationResponseMessage
    
    struct PropagateInvitationResponseMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateInvitationResponse
        let coreProtocolMessage: CoreProtocolMessage
        
        let invitationAccepted: Bool
        
        var encodedInputs: [ObvEncoded] {
            return [invitationAccepted.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.invitationAccepted = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, invitationAccepted: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = invitationAccepted
        }
        
    }
    
    // MARK: - DialogInformativeMessage
    // This message is always sent from this protocol, never to this protocol
    
    struct DialogInformativeMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.dialogInformative
        let coreProtocolMessage: CoreProtocolMessage
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            // Never used
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }
    }

}
