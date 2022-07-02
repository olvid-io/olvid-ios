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
import ObvTypes
import ObvEncoder
import ObvCrypto

extension OneToOneContactInvitationProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {

        case Initial = 0
        case OneToOneInvitation = 1
        case DialogInvitationSent = 2
        case PropagateOneToOneInvitation = 3
        case DialogAcceptOneToOneInvitation = 4
        case OneToOneResponse = 5
        case PropagateOneToOneResponse = 6
        case Abort = 7
        case ContactUpgradedToOneToOne = 8
        case PropagateAbort = 9
        case InitialOneToOneStatusSyncRequest = 10
        case OneToOneStatusSyncRequest = 11
        case DialogInformative = 100

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .Initial                          : return InitialMessage.self
            case .OneToOneInvitation               : return OneToOneInvitationMessage.self
            case .DialogInvitationSent             : return DialogInvitationSentMessage.self
            case .PropagateOneToOneInvitation      : return PropagateOneToOneInvitationMessage.self
            case .DialogAcceptOneToOneInvitation   : return DialogAcceptOneToOneInvitationMessage.self
            case .OneToOneResponse                 : return OneToOneResponseMessage.self
            case .PropagateOneToOneResponse        : return PropagateOneToOneResponseMessage.self
            case .Abort                            : return AbortMessage.self
            case .ContactUpgradedToOneToOne        : return ContactUpgradedToOneToOneMessage.self
            case .PropagateAbort                   : return PropagateAbortMessage.self
            case .InitialOneToOneStatusSyncRequest : return InitialOneToOneStatusSyncRequestMessage.self
            case .OneToOneStatusSyncRequest        : return OneToOneStatusSyncRequestMessage.self
            case .DialogInformative                : return DialogInformativeMessage.self
            }
        }

    }

 
    // MARK: - InitialMessage

    struct InitialMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.Initial
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
                
        let contactIdentity: ObvCryptoIdentity

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }

        var encodedInputs: [ObvEncoded] { return [contactIdentity.obvEncode()] }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactIdentity = try message.encodedInputs.obvDecode()
        }

    }

    
    // MARK: - DialogInvitationSentMessage

    struct DialogInvitationSentMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.DialogInvitationSent
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
                
        let cancelInvitation: Bool // Only used when the protocol receives the message
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.cancelInvitation = false
        }

        var encodedInputs: [ObvEncoded] { return [cancelInvitation.obvEncode()] }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else {
                assertionFailure()
                throw Self.makeError(message: "Could not get encoded user dialog response")
            }
            self.cancelInvitation = try encodedUserDialogResponse.obvDecode()
            assert(self.cancelInvitation) // The only reason for this protocol to receive this message is to cancel an invitation sent.
        }

    }


    // MARK: - OneToOneInvitationMessage

    struct OneToOneInvitationMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.OneToOneInvitation
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
                
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] {
            return []
        }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
    }

    
    // MARK: - PropagateOneToOneInvitationMessage

    struct PropagateOneToOneInvitationMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.PropagateOneToOneInvitation
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }

        var encodedInputs: [ObvEncoded] { return [contactIdentity.obvEncode()] }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactIdentity = try message.encodedInputs.obvDecode()
        }

    }

    
    // MARK: - DialogAcceptOneToOneInvitationMessage

    struct DialogAcceptOneToOneInvitationMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.DialogAcceptOneToOneInvitation
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let dialogUuid: UUID // Only used when this protocol receives this message
        let invitationAccepted: Bool // Only used when this protocol receives this message

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = false // Not used
            dialogUuid = UUID() // Not used
        }

        var encodedInputs: [ObvEncoded] { return [invitationAccepted.obvEncode()] }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else {
                assertionFailure()
                throw Self.makeError(message: "Could not get encoded user dialog response")
            }
            invitationAccepted = try encodedUserDialogResponse.obvDecode()
            guard let userDialogUuid = message.userDialogUuid else {
                assertionFailure()
                throw Self.makeError(message: "Could not get dialog UUID")
            }
            dialogUuid = userDialogUuid

        }
        
    }

    
    // MARK: - OneToOneResponseMessage

    struct OneToOneResponseMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.OneToOneResponse
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
        
        let invitationAccepted: Bool
                
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, invitationAccepted: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = invitationAccepted
        }

        var encodedInputs: [ObvEncoded] {
            return [invitationAccepted.obvEncode()]
        }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            self.invitationAccepted = try message.encodedInputs.obvDecode()
        }
        
    }

    
    // MARK: - PropagateOneToOneResponseMessage

    struct PropagateOneToOneResponseMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.PropagateOneToOneResponse
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
                
        let invitationAccepted: Bool
                
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, invitationAccepted: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = invitationAccepted
        }

        var encodedInputs: [ObvEncoded] {
            return [invitationAccepted.obvEncode()]
        }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            self.invitationAccepted = try message.encodedInputs.obvDecode()
        }

    }

    
    // MARK: - AbortMessage

    struct AbortMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.Abort
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
                
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { return [] }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
    }

    
    // MARK: - ContactUpgradedToOneToOneMessage

    struct ContactUpgradedToOneToOneMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.ContactUpgradedToOneToOne
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
                
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { return [] }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
    }


    // MARK: - DialogInformativeMessage
    // This message is always sent from this protocol, never to this protocol

    struct DialogInformativeMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.DialogInformative
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

    
    // MARK: - PropagateAbortMessage

    struct PropagateAbortMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.PropagateAbort
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
                
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { return [] }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
    }

    
    // MARK: - InitialOneToOneStatusSyncRequestMessage

    struct InitialOneToOneStatusSyncRequestMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.InitialOneToOneStatusSyncRequest
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
                
        let contactsToSync: Set<ObvCryptoIdentity>
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, contactsToSync: Set<ObvCryptoIdentity>) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactsToSync = contactsToSync
        }

        var encodedInputs: [ObvEncoded] { return contactsToSync.map({ $0.obvEncode() }) }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            self.contactsToSync = Set(message.encodedInputs.compactMap({ ObvCryptoIdentity($0) }))
            guard self.contactsToSync.count == message.encodedInputs.count else {
                assertionFailure()
                throw Self.makeError(message: "Decoding error")
            }
        }
        
    }

    
    // MARK: - OneToOneStatusSyncRequestMessage

    struct OneToOneStatusSyncRequestMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.OneToOneStatusSyncRequest
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message
                
        let aliceConsidersBobAsOneToOne: Bool

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, aliceConsidersBobAsOneToOne: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.aliceConsidersBobAsOneToOne = aliceConsidersBobAsOneToOne
        }

        var encodedInputs: [ObvEncoded] { return [aliceConsidersBobAsOneToOne.obvEncode()] }

        // Init when receiving this message
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            self.aliceConsidersBobAsOneToOne = try message.encodedInputs.obvDecode()
        }
        
    }
    
}
