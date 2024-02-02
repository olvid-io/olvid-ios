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
import ObvTypes


// MARK: - Protocol Messages

extension ContactMutualIntroductionProtocol {

    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initial = 0
        case mediatorInvitation = 1
        case acceptMediatorInviteDialog = 2
        case propagateConfirmation = 3
        case notifyContactOfAcceptedInvitation = 4
        case propagateContactNotificationOfAcceptedInvitation = 5
        case ack = 6
        case dialogInformative = 7
        case trustLevelIncreased = 8
        case propagatedInitial = 9
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial                                          : return InitialMessage.self
            case .mediatorInvitation                               : return MediatorInvitationMessage.self
            case .acceptMediatorInviteDialog                       : return AcceptMediatorInviteDialogMessage.self
            case .propagateConfirmation                            : return PropagateConfirmationMessage.self
            case .notifyContactOfAcceptedInvitation                : return NotifyContactOfAcceptedInvitationMessage.self
            case .propagateContactNotificationOfAcceptedInvitation : return PropagateContactNotificationOfAcceptedInvitationMessage.self
            case .ack                                              : return AckMessage.self
            case .dialogInformative                                : return DialogInformativeMessage.self
            case .trustLevelIncreased                              : return TrustLevelIncreasedMessage.self
            case .propagatedInitial                                : return PropagatedInitialMessage.self
            }
        }
    }
    

    // MARK: - InitialMessage
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initial
        let coreProtocolMessage: CoreProtocolMessage

        let contactIdentityA: ObvCryptoIdentity
        let contactIdentityB: ObvCryptoIdentity

        var encodedInputs: [ObvEncoded] {
            get throws {
                return [contactIdentityA.obvEncode(), contactIdentityB.obvEncode()]
            }
        }
        
        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            (contactIdentityA, contactIdentityB) = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentityA: ObvCryptoIdentity, contactIdentityB: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentityA = contactIdentityA
            self.contactIdentityB = contactIdentityB
        }

    }
    
    
    // MARK: - MediatorInvitationMessage
    
    struct MediatorInvitationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.mediatorInvitation
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        
        var encodedInputs: [ObvEncoded] {
            get throws {
                let encodedContactIdentityDetails = try contactIdentityCoreDetails.jsonEncode()
                return [contactIdentity.obvEncode(), encodedContactIdentityDetails.obvEncode()]
            }
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedContactIdentityCoreDetails: Data
            (contactIdentity, encodedContactIdentityCoreDetails) = try message.encodedInputs.obvDecode()
            self.contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
        }

    }
    
    
    // MARK: - AcceptMediatorInviteDialogMessage
    
    struct AcceptMediatorInviteDialogMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.acceptMediatorInviteDialog
        let coreProtocolMessage: CoreProtocolMessage
        
        let dialogUuid: UUID // Only used when this protocol receives this message
        let invitationAccepted: Bool // Only used when this protocol receives this message

        var encodedInputs: [ObvEncoded] { return [invitationAccepted.obvEncode()] }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else {
                throw ContactMutualIntroductionProtocol.makeError(message: "Could not get encodedUserDialogResponse in AcceptMediatorInviteDialogMessage")
            }
            invitationAccepted = try encodedUserDialogResponse.obvDecode()
            guard let userDialogUuid = message.userDialogUuid else {
                throw ContactMutualIntroductionProtocol.makeError(message: "Could not get userDialogUuid in AcceptMediatorInviteDialogMessage")
            }
            dialogUuid = userDialogUuid
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = false // Not used
            dialogUuid = UUID() // Not used
        }
        
    }

    
    // MARK: - PropagateConfirmation
    
    struct PropagateConfirmationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateConfirmation
        let coreProtocolMessage: CoreProtocolMessage

        let invitationAccepted: Bool
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let mediatorIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            get throws {
                let encodedContactIdentityDetails = try contactIdentityCoreDetails.jsonEncode()
                return [invitationAccepted.obvEncode(), contactIdentity.obvEncode(), encodedContactIdentityDetails.obvEncode(), mediatorIdentity.obvEncode()]
            }
        }

        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedContactIdentityCoreDetails: Data
            (invitationAccepted, contactIdentity, encodedContactIdentityCoreDetails, mediatorIdentity) = try message.encodedInputs.obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, invitationAccepted: Bool, contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, mediatorIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = invitationAccepted
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.mediatorIdentity = mediatorIdentity
        }

    }
    
    
    // MARK: - NotifyContactOfAcceptedInvitationMessage
    
    struct NotifyContactOfAcceptedInvitationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.notifyContactOfAcceptedInvitation
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactDeviceUids: [UID]
        let signature: Data
        
        var encodedInputs: [ObvEncoded] {
            let listOfEncodedUids = contactDeviceUids.map { $0.obvEncode() }
            return [listOfEncodedUids.obvEncode(), signature.obvEncode()]
            
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 2 else {
                throw ContactMutualIntroductionProtocol.makeError(message: "Unexpected number of encoded elements in NotifyContactOfAcceptedInvitationMessage")
            }
            guard let listOfEncodedUids = [ObvEncoded](encodedElements[0]) else {
                throw ContactMutualIntroductionProtocol.makeError(message: "Could not get listOfEncodedUids in NotifyContactOfAcceptedInvitationMessage")
            }
            var uids = [UID]()
            for encodedUid in listOfEncodedUids {
                guard let uid = UID(encodedUid) else {
                    throw ContactMutualIntroductionProtocol.makeError(message: "Could not decode UID in NotifyContactOfAcceptedInvitationMessage")
                }
                uids.append(uid)
            }
            self.contactDeviceUids = uids
            guard let signature = Data(encodedElements[1]) else {
                throw ContactMutualIntroductionProtocol.makeError(message: "Could not decode signature in NotifyContactOfAcceptedInvitationMessage")
            }
            self.signature = signature
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactDeviceUids: [UID], signature: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactDeviceUids = contactDeviceUids
            self.signature = signature
        }
        
    }
    
    
    // MARK: - PropagateContactNotificationOfAcceptedInvitationMessage
    
    struct PropagateContactNotificationOfAcceptedInvitationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateContactNotificationOfAcceptedInvitation
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactDeviceUids: [UID]
        
        var encodedInputs: [ObvEncoded] {
            let listOfEncodedUids = contactDeviceUids.map { $0.obvEncode() }
            return [listOfEncodedUids.obvEncode()]
            
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else {
                throw ContactMutualIntroductionProtocol.makeError(message: "Unexpected number of encoded elements in PropagateContactNotificationOfAcceptedInvitationMessage")
            }
            guard let listOfEncodedUids = [ObvEncoded](encodedElements[0]) else {
                throw ContactMutualIntroductionProtocol.makeError(message: "Could not get listOfEncodedUids in PropagateContactNotificationOfAcceptedInvitationMessage")
            }
            var uids = [UID]()
            for encodedUid in listOfEncodedUids {
                guard let uid = UID(encodedUid) else {
                    throw ContactMutualIntroductionProtocol.makeError(message: "Could not get uid in PropagateContactNotificationOfAcceptedInvitationMessage")
                }
                uids.append(uid)
            }
            self.contactDeviceUids = uids
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactDeviceUids: [UID]) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactDeviceUids = contactDeviceUids
        }
        
    }
    
    
    // MARK: - AckMessage
    
    struct AckMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.ack
        let coreProtocolMessage: CoreProtocolMessage
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
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

    
    // MARK: - TrustLevelIncreasedMessage
    
    struct TrustLevelIncreasedMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.trustLevelIncreased
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else {
                throw ContactMutualIntroductionProtocol.makeError(message: "Unexpected number of encoded elements in TrustLevelIncreasedMessage")
            }
            self.contactIdentity = try encodedElements.first!.obvDecode()
        }
        
        // Not used
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }
        
    }
    
    
    // MARK: - PropagatedInitialMessage
    
    struct PropagatedInitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagatedInitial
        let coreProtocolMessage: CoreProtocolMessage

        let contactIdentityA: ObvCryptoIdentity
        let contactIdentityB: ObvCryptoIdentity

        var encodedInputs: [ObvEncoded] {
            get throws {
                return [contactIdentityA.obvEncode(), contactIdentityB.obvEncode()]
            }
        }
        
        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            (contactIdentityA, contactIdentityB) = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentityA: ObvCryptoIdentity, contactIdentityB: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentityA = contactIdentityA
            self.contactIdentityB = contactIdentityB
        }

    }

}
