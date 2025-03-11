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
import ObvTypes
import ObvEncoder
import ObvCrypto

extension OneToOneContactInvitationProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {

        case initial = 0
        case oneToOneInvitation = 1
        case dialogInvitationSent = 2
        case propagateOneToOneInvitation = 3
        case dialogAcceptOneToOneInvitation = 4
        case oneToOneResponse = 5
        case propagateOneToOneResponse = 6
        case abort = 7
        case contactUpgradedToOneToOne = 8
        case propagateAbort = 9
        case initialOneToOneStatusSyncRequest = 10
        case oneToOneStatusSyncRequest = 11
        case dialogInformative = 100

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial                          : return InitialMessage.self
            case .oneToOneInvitation               : return OneToOneInvitationMessage.self
            case .dialogInvitationSent             : return DialogInvitationSentMessage.self
            case .propagateOneToOneInvitation      : return PropagateOneToOneInvitationMessage.self
            case .dialogAcceptOneToOneInvitation   : return DialogAcceptOneToOneInvitationMessage.self
            case .oneToOneResponse                 : return OneToOneResponseMessage.self
            case .propagateOneToOneResponse        : return PropagateOneToOneResponseMessage.self
            case .abort                            : return AbortMessage.self
            case .contactUpgradedToOneToOne        : return ContactUpgradedToOneToOneMessage.self
            case .propagateAbort                   : return PropagateAbortMessage.self
            case .initialOneToOneStatusSyncRequest : return InitialOneToOneStatusSyncRequestMessage.self
            case .oneToOneStatusSyncRequest        : return OneToOneStatusSyncRequestMessage.self
            case .dialogInformative                : return DialogInformativeMessage.self
            }
        }

    }

 
    // MARK: - InitialMessage

    struct InitialMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.initial
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

        let id: ConcreteProtocolMessageId = MessageId.dialogInvitationSent
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

        let id: ConcreteProtocolMessageId = MessageId.oneToOneInvitation
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

        let id: ConcreteProtocolMessageId = MessageId.propagateOneToOneInvitation
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

        let id: ConcreteProtocolMessageId = MessageId.dialogAcceptOneToOneInvitation
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

        let id: ConcreteProtocolMessageId = MessageId.oneToOneResponse
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

        let id: ConcreteProtocolMessageId = MessageId.propagateOneToOneResponse
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

        let id: ConcreteProtocolMessageId = MessageId.abort
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

        let id: ConcreteProtocolMessageId = MessageId.contactUpgradedToOneToOne
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

    
    // MARK: - PropagateAbortMessage

    struct PropagateAbortMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.propagateAbort
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

        let id: ConcreteProtocolMessageId = MessageId.initialOneToOneStatusSyncRequest
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

        let id: ConcreteProtocolMessageId = MessageId.oneToOneStatusSyncRequest
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
