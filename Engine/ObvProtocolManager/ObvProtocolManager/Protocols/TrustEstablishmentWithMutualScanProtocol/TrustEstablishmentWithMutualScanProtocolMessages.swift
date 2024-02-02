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
import ObvCrypto
import ObvEncoder
import ObvTypes


extension TrustEstablishmentWithMutualScanProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initial = 0
        case aliceSendsSignatureToBob = 1
        case alicePropagatesQRCode = 2
        case bobSendsConfirmationAndDetailsToAlice = 3
        case bobPropagatesSignature = 4

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initial                               : return InitialMessage.self
            case .aliceSendsSignatureToBob              : return AliceSendsSignatureToBobMessage.self
            case .alicePropagatesQRCode                 : return AlicePropagatesQRCodeMessage.self
            case .bobSendsConfirmationAndDetailsToAlice : return BobSendsConfirmationAndDetailsToAliceMessage.self
            case .bobPropagatesSignature                : return BobPropagatesSignatureMessage.self
            }
        }

    }

    
    // MARK: - InitialMessage

    struct InitialMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.initial
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let contactIdentity: ObvCryptoIdentity
        let signature: Data

        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.obvEncode(), signature.obvEncode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.contactIdentity = try message.encodedInputs[0].obvDecode()
            self.signature = try message.encodedInputs[1].obvDecode()
        }

        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, signature: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.signature = signature
        }

    }

    
    // MARK: - AliceSendsSignatureToBobMessage

    struct AliceSendsSignatureToBobMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.aliceSendsSignatureToBob
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let aliceIdentity: ObvCryptoIdentity
        let signature: Data
        let aliceCoreDetails: ObvIdentityCoreDetails
        let aliceDeviceUids: [UID]

        var encodedInputs: [ObvEncoded] {
            let encodedAliceCoreDetails = try! aliceCoreDetails.jsonEncode()

            return [aliceIdentity.obvEncode(),
                    signature.obvEncode(),
                    encodedAliceCoreDetails.obvEncode(),
                    (aliceDeviceUids as [ObvEncodable]).obvEncode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 4 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            aliceIdentity = try encodedElements[0].obvDecode()
            signature = try encodedElements[1].obvDecode()
            let encodedAliceCoreDetails: Data = try encodedElements[2].obvDecode()
            aliceCoreDetails = try ObvIdentityCoreDetails(encodedAliceCoreDetails)
            aliceDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[3])
        }

        init(coreProtocolMessage: CoreProtocolMessage, aliceIdentity: ObvCryptoIdentity, signature: Data, aliceCoreDetails: ObvIdentityCoreDetails, aliceDeviceUids: [UID]) {
            self.coreProtocolMessage = coreProtocolMessage
            self.aliceIdentity = aliceIdentity
            self.signature = signature
            self.aliceCoreDetails = aliceCoreDetails
            self.aliceDeviceUids = aliceDeviceUids
        }

    }

    
    
    // MARK: - AlicePropagatesQRCodeMessage

    struct AlicePropagatesQRCodeMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.alicePropagatesQRCode
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let bobIdentity: ObvCryptoIdentity
        let signature: Data

        var encodedInputs: [ObvEncoded] {
            return [bobIdentity.obvEncode(), signature.obvEncode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            self.bobIdentity = try message.encodedInputs[0].obvDecode()
            self.signature = try message.encodedInputs[1].obvDecode()
        }

        init(coreProtocolMessage: CoreProtocolMessage, bobIdentity: ObvCryptoIdentity, signature: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.bobIdentity = bobIdentity
            self.signature = signature
        }

    }

    
    // MARK: - BobSendsConfirmationAndDetailsToAliceMessage

    struct BobSendsConfirmationAndDetailsToAliceMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.bobSendsConfirmationAndDetailsToAlice
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let bobCoreDetails: ObvIdentityCoreDetails
        let bobDeviceUids: [UID]

        var encodedInputs: [ObvEncoded] {
            let encodedBobCoreDetails = try! bobCoreDetails.jsonEncode()
            return [encodedBobCoreDetails.obvEncode(),
                    (bobDeviceUids as [ObvEncodable]).obvEncode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            let encodedBobCoreDetails: Data = try encodedElements[0].obvDecode()
            bobCoreDetails = try ObvIdentityCoreDetails(encodedBobCoreDetails)
            bobDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[1])
        }

        init(coreProtocolMessage: CoreProtocolMessage, bobCoreDetails: ObvIdentityCoreDetails, bobDeviceUids: [UID]) {
            self.coreProtocolMessage = coreProtocolMessage
            self.bobCoreDetails = bobCoreDetails
            self.bobDeviceUids = bobDeviceUids
        }

    }

    
    // MARK: - BobPropagatesSignatureMessage

    struct BobPropagatesSignatureMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.bobPropagatesSignature
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let aliceIdentity: ObvCryptoIdentity
        let signature: Data
        let aliceCoreDetails: ObvIdentityCoreDetails
        let aliceDeviceUids: [UID]

        var encodedInputs: [ObvEncoded] {
            let encodedAliceCoreDetails = try! aliceCoreDetails.jsonEncode()

            return [aliceIdentity.obvEncode(),
                    signature.obvEncode(),
                    encodedAliceCoreDetails.obvEncode(),
                    (aliceDeviceUids as [ObvEncodable]).obvEncode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 4 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            aliceIdentity = try encodedElements[0].obvDecode()
            signature = try encodedElements[1].obvDecode()
            let encodedAliceCoreDetails: Data = try encodedElements[2].obvDecode()
            aliceCoreDetails = try ObvIdentityCoreDetails(encodedAliceCoreDetails)
            aliceDeviceUids = try TrustEstablishmentWithSASProtocol.decodeEncodedListOfDeviceUids(encodedElements[3])
        }

        init(coreProtocolMessage: CoreProtocolMessage, aliceIdentity: ObvCryptoIdentity, signature: Data, aliceCoreDetails: ObvIdentityCoreDetails, aliceDeviceUids: [UID]) {
            self.coreProtocolMessage = coreProtocolMessage
            self.aliceIdentity = aliceIdentity
            self.signature = signature
            self.aliceCoreDetails = aliceCoreDetails
            self.aliceDeviceUids = aliceDeviceUids
        }

    }

}


// MARK: - Helpers

extension TrustEstablishmentWithMutualScanProtocol {
    
    static func decodeEncodedListOfDeviceUids(_ obvEncoded: ObvEncoded) throws -> [UID] {
        guard let listOfEncodedUids = [ObvEncoded](obvEncoded) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
        return try listOfEncodedUids.map { try $0.obvDecode() }
    }
    
}
