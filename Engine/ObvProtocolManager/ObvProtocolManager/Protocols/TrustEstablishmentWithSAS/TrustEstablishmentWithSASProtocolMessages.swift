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
        
        case initial = 0
        case aliceSendsCommitment = 1
        case alicePropagatesHerInviteToOtherDevices = 2
        case bobPropagatesCommitmentToOtherDevices = 4
        case bobDialogInvitationConfirmation = 5
        case bobPropagatesConfirmationToOtherDevices = 6
        case bobSendsSeed = 8
        case aliceSendsDecommitment = 9
        case dialogSasExchange = 10
        case propagateEnteredSasToOtherDevices = 12
        case mutualTrustConfirmation = 13
        case dialogForMutualTrustConfirmation = 14
        case dialogInformative = 15
        
        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial                                 : return InitialMessage.self
            case .aliceSendsCommitment                    : return AliceSendsCommitmentMessage.self
            case .alicePropagatesHerInviteToOtherDevices  : return AlicePropagatesHerInviteToOtherDevicesMessage.self
            case .bobPropagatesCommitmentToOtherDevices   : return BobPropagatesCommitmentToOtherDevicesMessage.self
            case .bobDialogInvitationConfirmation         : return BobDialogInvitationConfirmationMessage.self
            case .bobPropagatesConfirmationToOtherDevices : return BobPropagatesConfirmationToOtherDevicesMessage.self
            case .bobSendsSeed                            : return BobSendsSeedMessage.self
            case .aliceSendsDecommitment                  : return AliceSendsDecommitmentMessage.self
            case .dialogSasExchange                       : return DialogSasExchangeMessage.self
            case .propagateEnteredSasToOtherDevices       : return PropagateEnteredSasToOtherDevicesMessage.self
            case .mutualTrustConfirmation                 : return MutualTrustConfirmationMessageMessage.self
            case .dialogForMutualTrustConfirmation        : return DialogForMutualTrustConfirmationMessage.self
            case .dialogInformative                       : return DialogInformativeMessage.self
            }
        }
    }
    
    
    struct InitialMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initial
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
        
        let id: ConcreteProtocolMessageId = MessageId.aliceSendsCommitment
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
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
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
        
        let id: ConcreteProtocolMessageId = MessageId.alicePropagatesHerInviteToOtherDevices
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityFullDisplayName: String
        let decommitment: Data
        let seedAliceForSas: Seed
        
        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.obvEncode(), contactIdentityFullDisplayName.obvEncode(), decommitment.obvEncode(), seedAliceForSas.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (contactIdentity, contactIdentityFullDisplayName, decommitment, seedAliceForSas) = try encodedElements.obvDecode()
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
        
        let id: ConcreteProtocolMessageId = MessageId.bobPropagatesCommitmentToOtherDevices
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
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[2])
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
        
        let id: ConcreteProtocolMessageId = MessageId.bobDialogInvitationConfirmation
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
            guard let userDialogUuid = message.userDialogUuid else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded user dialog uuid") }
            dialogUuid = userDialogUuid
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = false
            dialogUuid = UUID() // Not used
        }
    }
    
    
    struct BobPropagatesConfirmationToOtherDevicesMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.bobPropagatesConfirmationToOtherDevices
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
        
        let id: ConcreteProtocolMessageId = MessageId.bobSendsSeed
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let seedBobForSas: Seed
        let contactDeviceUids: [UID]
        let contactIdentityCoreDetails: ObvIdentityCoreDetails

        var encodedInputs: [ObvEncoded] {
            let encodedContactIdentityCoreDetails = try! contactIdentityCoreDetails.jsonEncode()
            return [seedBobForSas.obvEncode(), (contactDeviceUids as [ObvEncodable]).obvEncode(), encodedContactIdentityCoreDetails.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 3 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            seedBobForSas = try encodedElements[0].obvDecode()
            contactDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[1])
            let encodedContactIdentityCoreDetails: Data = try encodedElements[2].obvDecode()
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
        
        let id: ConcreteProtocolMessageId = MessageId.aliceSendsDecommitment
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
        
        let id: ConcreteProtocolMessageId = MessageId.dialogSasExchange
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
            guard let uuid = message.userDialogUuid else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded user dialog uuid") }
            self.dialogUuid = uuid
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.sasEnteredByUser = nil
            self.dialogUuid = nil
        }
    }
    
    
    struct PropagateEnteredSasToOtherDevicesMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateEnteredSasToOtherDevices
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let contactSas: Data
        
        var encodedInputs: [ObvEncoded] {
            return [contactSas.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            contactSas = try message.encodedInputs.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, contactSas: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactSas = contactSas
        }
    }
    
    
    struct MutualTrustConfirmationMessageMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.mutualTrustConfirmation
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
        
        let id: ConcreteProtocolMessageId = MessageId.dialogForMutualTrustConfirmation
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
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded user dialog response") }
            let encodedContactIdentityCoreDetails: Data
            (encodedContactIdentityCoreDetails, contactIdentity) = try encodedUserDialogResponse.obvDecode()
            contactIdentityCoreDetails = try ObvIdentityCoreDetails(encodedContactIdentityCoreDetails)
            guard let userDialogUuid = message.userDialogUuid else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded user dialog uuid") }
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
