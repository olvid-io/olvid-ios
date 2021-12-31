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
import ObvCrypto
import ObvEncoder
import ObvTypes


extension TrustEstablishmentWithMutualScanProtocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        case Initial = 0
        case AliceSendsSignatureToBob = 1
        case AlicePropagatesQRCode = 2
        case BobSendsConfirmationAndDetailsToAlice = 3
        case BobPropagatesSignature = 4

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .Initial                               : return InitialMessage.self
            case .AliceSendsSignatureToBob              : return AliceSendsSignatureToBobMessage.self
            case .AlicePropagatesQRCode                 : return AlicePropagatesQRCodeMessage.self
            case .BobSendsConfirmationAndDetailsToAlice : return BobSendsConfirmationAndDetailsToAliceMessage.self
            case .BobPropagatesSignature                : return BobPropagatesSignatureMessage.self
            }
        }

    }

    
    // MARK: - InitialMessage

    struct InitialMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.Initial
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let contactIdentity: ObvCryptoIdentity
        let signature: Data

        var encodedInputs: [ObvEncoded] {
            return [contactIdentity.encode(), signature.encode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { throw NSError() }
            self.contactIdentity = try message.encodedInputs[0].decode()
            self.signature = try message.encodedInputs[1].decode()
        }

        init(coreProtocolMessage: CoreProtocolMessage, contactIdentity: ObvCryptoIdentity, signature: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.contactIdentity = contactIdentity
            self.signature = signature
        }

    }

    
    // MARK: - AliceSendsSignatureToBobMessage

    struct AliceSendsSignatureToBobMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.AliceSendsSignatureToBob
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let aliceIdentity: ObvCryptoIdentity
        let signature: Data
        let aliceCoreDetails: ObvIdentityCoreDetails
        let aliceDeviceUids: [UID]

        var encodedInputs: [ObvEncoded] {
            let encodedAliceCoreDetails = try! aliceCoreDetails.encode()

            return [aliceIdentity.encode(),
                    signature.encode(),
                    encodedAliceCoreDetails.encode(),
                    (aliceDeviceUids as [ObvEncodable]).encode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 4 else { throw NSError() }
            aliceIdentity = try encodedElements[0].decode()
            signature = try encodedElements[1].decode()
            let encodedAliceCoreDetails: Data = try encodedElements[2].decode()
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

        let id: ConcreteProtocolMessageId = MessageId.AlicePropagatesQRCode
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let bobIdentity: ObvCryptoIdentity
        let signature: Data

        var encodedInputs: [ObvEncoded] {
            return [bobIdentity.encode(), signature.encode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { throw NSError() }
            self.bobIdentity = try message.encodedInputs[0].decode()
            self.signature = try message.encodedInputs[1].decode()
        }

        init(coreProtocolMessage: CoreProtocolMessage, bobIdentity: ObvCryptoIdentity, signature: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.bobIdentity = bobIdentity
            self.signature = signature
        }

    }

    
    // MARK: - BobSendsConfirmationAndDetailsToAliceMessage

    struct BobSendsConfirmationAndDetailsToAliceMessage: ConcreteProtocolMessage {

        let id: ConcreteProtocolMessageId = MessageId.BobSendsConfirmationAndDetailsToAlice
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let bobCoreDetails: ObvIdentityCoreDetails
        let bobDeviceUids: [UID]

        var encodedInputs: [ObvEncoded] {
            let encodedBobCoreDetails = try! bobCoreDetails.encode()
            return [encodedBobCoreDetails.encode(),
                    (bobDeviceUids as [ObvEncodable]).encode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard message.encodedInputs.count == 2 else { throw NSError() }
            let encodedBobCoreDetails: Data = try encodedElements[0].decode()
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

        let id: ConcreteProtocolMessageId = MessageId.BobPropagatesSignature
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let aliceIdentity: ObvCryptoIdentity
        let signature: Data
        let aliceCoreDetails: ObvIdentityCoreDetails
        let aliceDeviceUids: [UID]

        var encodedInputs: [ObvEncoded] {
            let encodedAliceCoreDetails = try! aliceCoreDetails.encode()

            return [aliceIdentity.encode(),
                    signature.encode(),
                    encodedAliceCoreDetails.encode(),
                    (aliceDeviceUids as [ObvEncodable]).encode()]
        }

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            guard encodedElements.count == 4 else { throw NSError() }
            aliceIdentity = try encodedElements[0].decode()
            signature = try encodedElements[1].decode()
            let encodedAliceCoreDetails: Data = try encodedElements[2].decode()
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
        guard let listOfEncodedUids = [ObvEncoded](obvEncoded) else { throw NSError() }
        return try listOfEncodedUids.map { try $0.decode() }
    }
    
}
