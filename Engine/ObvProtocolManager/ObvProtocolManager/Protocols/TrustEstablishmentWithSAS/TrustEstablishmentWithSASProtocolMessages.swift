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
import CoreData
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import ObvMetaManager


// MARK: - Protocol Messages

extension TrustEstablishmentWithSASProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        case Initial = 0
        case AliceSendsCommitment = 1
        case AlicePropagatesHerInviteToOtherDevices = 2
        case BobPropagatesCommitmentToOtherDevices = 4
        case BobDialogInvitationConfirmation = 5
        case BobPropagatesConfirmationToOtherDevices = 6
        case BobSendsSeed = 8
        case AliceSendsDecommitment = 9
        case DialogSasExchange = 10
        case PropagateEnteredSasToOtherDevices = 12
        case MutualTrustConfirmation = 13
        case DialogForMutualTrustConfirmation = 14
        case DialogInformative = 15
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .Initial                                 : return InitialMessage.self
            case .AliceSendsCommitment                    : return AliceSendsCommitmentMessage.self
            case .AlicePropagatesHerInviteToOtherDevices  : return AlicePropagatesHerInviteToOtherDevicesMessage.self
            case .BobPropagatesCommitmentToOtherDevices   : return BobPropagatesCommitmentToOtherDevicesMessage.self
            case .BobDialogInvitationConfirmation         : return BobDialogInvitationConfirmationMessage.self
            case .BobPropagatesConfirmationToOtherDevices : return BobPropagatesConfirmationToOtherDevicesMessage.self
            case .BobSendsSeed                            : return BobSendsSeedMessage.self
            case .AliceSendsDecommitment                  : return AliceSendsDecommitmentMessage.self
            case .DialogSasExchange                       : return DialogSasExchangeMessage.self
            case .PropagateEnteredSasToOtherDevices       : return PropagateEnteredSasToOtherDevicesMessage.self
            case .MutualTrustConfirmation                 : return MutualTrustConfirmationMessageMessage.self
            case .DialogForMutualTrustConfirmation        : return DialogForMutualTrustConfirmationMessage.self
            case .DialogInformative                       : return DialogInformativeMessage.self
            }
        }
    }
    
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.Initial
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        /// The `contactIdentity` is the cryptographic identity we seek to trust. This protocol expects that this identity is already present within the contact database of the identity manager
        let contactIdentity: ObvCryptoIdentity
        /// This is Alice's identity details as it will appear on Bob's screen, allowing him to decide whether he wants to accept or reject the invitation. Typically, these details are identical to the default one that are found within the owned identity database of the identity manager for the owned identity that runs this protocol, but it does not have to be the case. This is the reason why we have this display name as an input of this protocol.
        let contactIdentityFullDisplayName: String
        let ownIdentityCoreDetails: ObvIdentityCoreDetails
        
        var encodedInputs: [ObvEncoded] {
            let encodedOwnIdentityCoreDetails = try! ownIdentityCoreDetails.encode()
            return [contactIdentity.encode(), contactIdentityFullDisplayName.encode(), encodedOwnIdentityCoreDetails.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedOwnIdentityCoreDetails: Data
            (contactIdentity, contactIdentityFullDisplayName, encodedOwnIdentityCoreDetails) = try message.encodedInputs.decode()
            ownIdentityCoreDetails = try ObvIdentityCoreDetails(encodedOwnIdentityCoreDetails)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, contactIdentityFullDisplayName: String, ownIdentityCoreDetails: ObvIdentityCoreDetails) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.contactIdentityFullDisplayName = contactIdentityFullDisplayName
            self.ownIdentityCoreDetails = ownIdentityCoreDetails
        }
    }
    
    
    struct AliceSendsCommitmentMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.AliceSendsCommitment
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let commitment: Data
        
        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity.encode(), encodedContactIdentityCoreDetails.encode(), (contactDeviceUids as [ObvEncodable]).encode(), commitment.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 4 else { throw NSError() }
            contactIdentity = try encodedElements[0].decode()
            let encodedContactIdentityCoreDetails: Data = try encodedElements[1].decode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            commitment = try encodedElements[3].decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactIdentity: ObvCryptoIdentity, contactDeviceUids: [UID], commitment: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactIdentity = contactIdentity
            self.contactDeviceUids = contactDeviceUids
            self.commitment = commitment
        }
    }
    
    
    struct AlicePropagatesHerInviteToOtherDevicesMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.AlicePropagatesHerInviteToOtherDevices
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityFullDisplayName: String
        let decommitment: Data
        let seedAliceForSas: Seed
        
        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.encode(), contactIdentityFullDisplayName.encode(), decommitment.encode(), seedAliceForSas.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (contactIdentity, contactIdentityFullDisplayName, decommitment, seedAliceForSas) = try encodedElements.decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, contactIdentityFullDisplayName: String, decommitment: Data, seedAliceForSas: Seed) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.contactIdentityFullDisplayName = contactIdentityFullDisplayName
            self.decommitment = decommitment
            self.seedAliceForSas = seedAliceForSas
        }
    }
    

    struct BobPropagatesCommitmentToOtherDevicesMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.BobPropagatesCommitmentToOtherDevices
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let commitment: Data
        
        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.encode()
            return [contactIdentity.encode(), encodedContactIdentityCoreDetails.encode(), (contactDeviceUids as [ObvEncodable]).encode(), commitment.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 4 else { throw NSError() }
            contactIdentity = try encodedElements[0].decode()
            let encodedContactIdentityCoreDetails: Data = try encodedElements[1].decode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            commitment = try encodedElements[3].decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], commitment: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.commitment = commitment
        }
    }
    
    
    struct BobDialogInvitationConfirmationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.BobDialogInvitationConfirmation
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let dialogUuid: UUID // Only used when this protocol receives this message
        let invitationAccepted: Bool
        
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
            self.invitationAccepted = false
            dialogUuid = UUID() // Not used
        }
    }
    
    
    struct BobPropagatesConfirmationToOtherDevicesMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.BobPropagatesConfirmationToOtherDevices
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let invitationAccepted: Bool
        
        var encodedInputs: [ObvEncoded] {
            return [invitationAccepted.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            invitationAccepted = try message.encodedInputs.decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, invitationAccepted: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = invitationAccepted
        }
    }
    
    
    struct BobSendsSeedMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.BobSendsSeed
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let seedBobForSas: Seed
        let contactDeviceUids: [UID]
        let contactIdentityCoreDetails: ObvIdentityCoreDetails

        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.encode()
            return [seedBobForSas.encode(), (contactDeviceUids as [ObvEncodable]).encode(), encodedContactIdentityCoreDetails.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 3 else { throw NSError() }
            seedBobForSas = try encodedElements[0].decode()
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[1])
            let encodedContactIdentityCoreDetails: Data = try encodedElements[2].decode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, seedBobForSas: Seed, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID]) {
            self.coreProtocolMessage = coreProtocolMessage
            self.seedBobForSas = seedBobForSas
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactDeviceUids = contactDeviceUids
        }
    }
    
    
    struct AliceSendsDecommitmentMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.AliceSendsDecommitment
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let decommitment: Data
        
        var encodedInputs: [ObvEncoded] {
            return [decommitment.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            decommitment = try message.encodedInputs.decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, decommitment: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.decommitment = decommitment
        }
    }
    
    
    struct DialogSasExchangeMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.DialogSasExchange
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let sasEnteredByUser: Data? // Only set when the message is sent to this protocol, not when sending this message to the UI
        let dialogUuid: UUID?  // Only set when the message is sent to this protocol, not when sending this message to the UI
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else { throw NSError() }
            sasEnteredByUser = try encodedUserDialogResponse.decode()
            guard let uuid = message.userDialogUuid else { throw NSError() }
            self.dialogUuid = uuid
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.sasEnteredByUser = nil
            self.dialogUuid = nil
        }
    }
    
    
    struct PropagateEnteredSasToOtherDevicesMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.PropagateEnteredSasToOtherDevices
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactSas: Data
        
        var encodedInputs: [ObvEncoded] {
            return [contactSas.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactSas = try message.encodedInputs.decode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactSas: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactSas = contactSas
        }
    }
    
    
    struct MutualTrustConfirmationMessageMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.MutualTrustConfirmation
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }
        
    }
    
    
    struct DialogForMutualTrustConfirmationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.DialogForMutualTrustConfirmation
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityCoreDetails: ObvIdentityCoreDetails
        let dialogUuid: UUID? // Only set when the message is sent to this protocol, not when sending this message to the UI
        
        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.encode()
            return [encodedContactIdentityCoreDetails.encode(), contactIdentity.encode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else { throw NSError() }
            let encodedContactIdentityCoreDetails: Data
            (encodedContactIdentityCoreDetails, contactIdentity) = try encodedUserDialogResponse.decode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            guard let userDialogUuid = message.userDialogUuid else { throw NSError() }
            dialogUuid = userDialogUuid
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentityCoreDetails = contactIdentityCoreDetails
            self.contactIdentity = contactIdentity
            dialogUuid = UUID()
        }
    }
    
    
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

}
