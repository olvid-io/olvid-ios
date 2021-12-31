/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
        
        case Initial = 0
        case MediatorInvitation = 1
        case AcceptMediatorInviteDialog = 2
        case PropagateConfirmation = 3
        case NotifyContactOfAcceptedInvitation = 4
        case PropagateContactNotificationOfAcceptedInvitation = 5
        case Ack = 6
        case DialogInformative = 7
        case TrustLevelIncreased = 8
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .Initial                                          : return InitialMessage.self
            case .MediatorInvitation                               : return MediatorInvitationMessage.self
            case .AcceptMediatorInviteDialog                       : return AcceptMediatorInviteDialogMessage.self
            case .PropagateConfirmation                            : return PropagateConfirmationMessage.self
            case .NotifyContactOfAcceptedInvitation                : return NotifyContactOfAcceptedInvitationMessage.self
            case .PropagateContactNotificationOfAcceptedInvitation : return PropagateContactNotificationOfAcceptedInvitationMessage.self
            case .Ack                                              : return AckMessage.self
            case .DialogInformative                                : return DialogInformativeMessage.self
            case .TrustLevelIncreased                              : return TrustLevelIncreasedMessage.self
            }
        }
    }
    

    // MARK: - InitialMessage
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.Initial
        let coreProtocolMessage: CoreProtocolMessage

        let contactIdentityA: ObvCryptoIdentity
        let contactIdentityCoreDetailsA: ObvIdentityCoreDetails
        let contactIdentityB: ObvCryptoIdentity
        let contactIdentityCoreDetailsB: ObvIdentityCoreDetails

        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityCoreDetailsA = try! contactIdentityCoreDetailsA.encode()
            let encodedContactIdentityCoreDetailsB = try! contactIdentityCoreDetailsB.encode()
            return [contactIdentityA.encode(), encodedContactIdentityCoreDetailsA.encode(), contactIdentityB.encode(), encodedContactIdentityCoreDetailsB.encode()]
        }
        
        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedContactIdentityCoreDetailsA: Data
            let encodedContactIdentityCoreDetailsB: Data
            (contactIdentityA, encodedContactIdentityCoreDetailsA, contactIdentityB, encodedContactIdentityCoreDetailsB) = try message.encodedInputs.decode()
            self.contactIdentityCoreDetailsA = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetailsA)
            self.contactIdentityCoreDetailsB = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetailsB)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentityA: ObvCryptoIdentity, contactIdentityCoreDetailsA: ObvIdentityCoreDetails, contactIdentityB: ObvCryptoIdentity, contactIdentityCoreDetailsB: ObvIdentityCoreDetails) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentityA = contactIdentityA
            self.contactIdentityCoreDetailsA = contactIdentityCoreDetailsA
            self.contactIdentityB = contactIdentityB
            self.contactIdentityCoreDetailsB = contactIdentityCoreDetailsB
        }

    }
    
    
    // MARK: - MediatorInvitationMessage
    
    struct MediatorInvitationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.MediatorInvitation
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        
        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity.encode(), encodedContactIdentityDetails.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedContactIdentityCoreDetails: Data
            (contactIdentity, encodedContactIdentityCoreDetails) = try message.encodedInputs.decode()
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
        
        let id: ConcreteProtocolMessageId = MessageId.AcceptMediatorInviteDialog
        let coreProtocolMessage: CoreProtocolMessage
        
        let dialogUuid: UUID // Only used when this protocol receives this message
        let invitationAccepted: Bool // Only used when this protocol receives this message

        var encodedInputs: [ObvEncoded] { return [invitationAccepted.encode()] }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else { throw NSError() }
            invitationAccepted = try encodedUserDialogResponse.decode()
            guard let userDialogUuid = message.userDialogUuid else { throw NSError() }
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
        
        let id: ConcreteProtocolMessageId = MessageId.PropagateConfirmation
        let coreProtocolMessage: CoreProtocolMessage

        let invitationAccepted: Bool
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let mediatorIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityDetails = try! contactIdentityCoreDetails.encode()
            return [invitationAccepted.encode(), contactIdentity.encode(), encodedContactIdentityDetails.encode(), mediatorIdentity.encode()]
        }

        // Initializers

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedContactIdentityCoreDetails: Data
            (invitationAccepted, contactIdentity, encodedContactIdentityCoreDetails, mediatorIdentity) = try message.encodedInputs.decode()
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
        
        let id: ConcreteProtocolMessageId = MessageId.NotifyContactOfAcceptedInvitation
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactDeviceUids: [UID]
        let signature: Data
        
        var encodedInputs: [ObvEncoded] {
            let listOfEncodedUids = contactDeviceUids.map { $0.encode() }
            return [listOfEncodedUids.encode(), signature.encode()]
            
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 2 else { throw NSError() }
            guard let listOfEncodedUids = [ObvEncoded](encodedElements[0]) else { throw NSError() }
            var uids = [UID]()
            for encodedUid in listOfEncodedUids {
                guard let uid = UID(encodedUid) else { throw NSError() }
                uids.append(uid)
            }
            self.contactDeviceUids = uids
            guard let signature = Data(encodedElements[1]) else { throw NSError() }
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
        
        let id: ConcreteProtocolMessageId = MessageId.PropagateContactNotificationOfAcceptedInvitation
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactDeviceUids: [UID]
        
        var encodedInputs: [ObvEncoded] {
            let listOfEncodedUids = contactDeviceUids.map { $0.encode() }
            return [listOfEncodedUids.encode()]
            
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else { throw NSError() }
            guard let listOfEncodedUids = [ObvEncoded](encodedElements[0]) else { throw NSError() }
            var uids = [UID]()
            for encodedUid in listOfEncodedUids {
                guard let uid = UID(encodedUid) else { throw NSError() }
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
        
        let id: ConcreteProtocolMessageId = MessageId.Ack
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

    
    // MARK: - TrustLevelIncreasedMessage
    
    struct TrustLevelIncreasedMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.TrustLevelIncreased
        let coreProtocolMessage: CoreProtocolMessage
        
        let contactIdentity: ObvCryptoIdentity
        
        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 1 else { throw NSError() }
            self.contactIdentity = try encodedElements.first!.decode()
        }
        
        // Not used
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
        }
        
    }
}
