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
import CoreData
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import ObvMetaManager


// MARK: - Protocol Messages

extension TrustEstablishmentProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        case Initial = 0
        case AliceSendsCommitment = 1
        case AlicePropagatesHerInviteToOtherDevices = 2
        /* case AliceDialogInvitationSent = 3 */
        case BobPropagatesCommitmentToOtherDevices = 4
        case BobDialogInvitationConfirmation = 5
        case BobPropagatesConfirmationToOtherDevices = 6
        /* case BobDialogInvitationAccepted = 7 */
        case BobSendsSeed = 8
        case AliceSendsDecommitment = 9
        case DialogSasExchange = 10
        /* case DialogSasConfirmed = 11 */
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
            let encodedOwnIdentityCoreDetails = try! ownIdentityCoreDetails.jsonEncode()
            return [contactIdentity.obvEncode(), contactIdentityFullDisplayName.obvEncode(), encodedOwnIdentityCoreDetails.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedOwnIdentityCoreDetails: Data
            (contactIdentity, contactIdentityFullDisplayName, encodedOwnIdentityCoreDetails) = try message.encodedInputs.obvDecode()
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
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity.obvEncode(), encodedContactIdentityCoreDetails.obvEncode(), (contactDeviceUids as [ObvEncodable]).obvEncode(), commitment.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 4 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            contactIdentity = try encodedElements[0].obvDecode()
            let encodedContactIdentityCoreDetails: Data = try encodedElements[1].obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            commitment = try encodedElements[3].obvDecode()
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
        let seedForSas: Seed
        let dialogUuid: UUID
        
        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.obvEncode(), contactIdentityFullDisplayName.obvEncode(), decommitment.obvEncode(), seedForSas.obvEncode(), dialogUuid.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (contactIdentity, contactIdentityFullDisplayName, decommitment, seedForSas, dialogUuid) = try encodedElements.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, contactIdentityFullDisplayName: String, decommitment: Data, seedForSas: Seed, dialogUuid: UUID) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.contactIdentityFullDisplayName = contactIdentityFullDisplayName
            self.decommitment = decommitment
            self.seedForSas = seedForSas
            self.dialogUuid = dialogUuid
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
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactIdentity.obvEncode(), encodedContactIdentityCoreDetails.obvEncode(), (contactDeviceUids as [ObvEncodable]).obvEncode(), commitment.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 4 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            contactIdentity = try encodedElements[0].obvDecode()
            let encodedContactIdentityCoreDetails: Data = try encodedElements[1].obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            contactDeviceUids = try TrustEstablishmentProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
            commitment = try encodedElements[3].obvDecode()
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
        
        var encodedInputs: [ObvEncoded] { return [invitationAccepted.obvEncode()] }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded user dialog response") }
            invitationAccepted = try encodedUserDialogResponse.obvDecode()
            guard let userDialogUuid = message.userDialogUuid else { assertionFailure(); throw Self.makeError(message: "Could not obtain user dialog uuid") }
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
            return [invitationAccepted.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            invitationAccepted = try message.encodedInputs.obvDecode()
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
        
        let contactSeedForSas: Seed
        let contactDeviceUids: [UID]
        let contactIdentityCoreDetails: ObvIdentityCoreDetails

        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [contactSeedForSas.obvEncode(), (contactDeviceUids as [ObvEncodable]).obvEncode(), encodedContactIdentityCoreDetails.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 3 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            contactSeedForSas = try encodedElements[0].obvDecode()
            contactDeviceUids = try TrustEstablishmentProtocol.decodeEncodedListOfDeviceUids(encodedElements[1])
            let encodedContactIdentityCoreDetails: Data = try encodedElements[2].obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactSeedForSas: Seed, contactIdentityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID]) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactSeedForSas = contactSeedForSas
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
            return [decommitment.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            decommitment = try message.encodedInputs.obvDecode()
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
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded user dialog response") }
            sasEnteredByUser = try encodedUserDialogResponse.obvDecode()
            guard let uuid = message.userDialogUuid else { assertionFailure(); throw Self.makeError(message: "Could not obtain user dialog uuid") }
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
        
        let sasEnteredByUser: Data
        
        var encodedInputs: [ObvEncoded] {
            return [sasEnteredByUser.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            sasEnteredByUser = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, sasEnteredByUser: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.sasEnteredByUser = sasEnteredByUser
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
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [encodedContactIdentityCoreDetails.obvEncode(), contactIdentity.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else { assertionFailure(); throw Self.makeError(message: "Could not obtain user dialog response") }
            let encodedContactIdentityCoreDetails: Data
            (encodedContactIdentityCoreDetails, contactIdentity) = try encodedUserDialogResponse.obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            guard let userDialogUuid = message.userDialogUuid else { assertionFailure(); throw Self.makeError(message: "Could not obtain user dialog uuid") }
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
