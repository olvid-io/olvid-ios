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

// MARK: - Protocol States

extension KeycloakContactAdditionProtocol {

    enum StateId: Int, ConcreteProtocolStateId {

        case initialState = 0
        case waitingForDeviceDiscovery = 1
        case waitingForConfirmation = 2
        case checkingForRevocation = 3
        case finished = 4

        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState              : return ConcreteProtocolInitialState.self
            case .waitingForDeviceDiscovery : return WaitingForDeviceDiscoveryState.self
            case .waitingForConfirmation    : return WaitingForConfirmationState.self
            case .checkingForRevocation     : return CheckingForRevocationState.self
            case .finished                  : return FinishedState.self
            }
        }

    }

    struct WaitingForDeviceDiscoveryState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.waitingForDeviceDiscovery

        let contactIdentity: ObvCryptoIdentity
        let identityCoreDetails: ObvIdentityCoreDetails
        let keycloakServerURL: URL
        let signedOwnedDetails: String // This is a JWS

        func obvEncode() -> ObvEncoded {
            let encodedIdentityCoreDetails = try! identityCoreDetails.jsonEncode()
            return [contactIdentity, encodedIdentityCoreDetails, keycloakServerURL, signedOwnedDetails].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 4) else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded elements") }
            self.contactIdentity = try encodedElements[0].obvDecode()
            let encodedIdentityCoreDetails: Data = try encodedElements[1].obvDecode()
            self.identityCoreDetails = try ObvIdentityCoreDetails(encodedIdentityCoreDetails)
            self.keycloakServerURL = try encodedElements[2].obvDecode()
            self.signedOwnedDetails = try encodedElements[3].obvDecode()
        }

        init(contactIdentity: ObvCryptoIdentity, identityCoreDetails: ObvIdentityCoreDetails, keycloakServerURL: URL, signedOwnedDetails: String) {
            self.contactIdentity = contactIdentity
            self.identityCoreDetails = identityCoreDetails
            self.keycloakServerURL = keycloakServerURL
            self.signedOwnedDetails = signedOwnedDetails
        }


    }

    struct WaitingForConfirmationState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.waitingForConfirmation

        let contactIdentity: ObvCryptoIdentity
        let keycloakServerURL: URL

        func obvEncode() -> ObvEncoded {
            return [contactIdentity, keycloakServerURL].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 2) else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded elements") }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.keycloakServerURL = try encodedElements[1].obvDecode()
        }

        init(contactIdentity: ObvCryptoIdentity, keycloakServerUrl: URL) {
            self.contactIdentity = contactIdentity
            self.keycloakServerURL = keycloakServerUrl
        }

    }

    struct CheckingForRevocationState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.checkingForRevocation

        let contactIdentity: ObvCryptoIdentity
        let identityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let keycloakServerURL: URL

        func obvEncode() -> ObvEncoded {
            let encodedIdentityCoreDetails = try! identityCoreDetails.jsonEncode()
            return [contactIdentity, encodedIdentityCoreDetails, contactDeviceUids as [ObvEncodable], keycloakServerURL].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 4) else { assertionFailure(); throw Self.makeError(message: "Could not obtain encoded elements") }
            self.contactIdentity = try encodedElements[0].obvDecode()
            let encodedIdentityCoreDetails: Data = try encodedElements[1].obvDecode()
            self.identityCoreDetails = try ObvIdentityCoreDetails(encodedIdentityCoreDetails)
            guard let listOfEncodedDeviceUids = [ObvEncoded](encodedElements[2]) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded device uids") }
            contactDeviceUids = try listOfEncodedDeviceUids.map { return try $0.obvDecode() }
            self.keycloakServerURL = try encodedElements[3].obvDecode()
        }

        init(contactIdentity: ObvCryptoIdentity, identityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], keycloakServerURL: URL) {
            self.contactIdentity = contactIdentity
            self.identityCoreDetails = identityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.keycloakServerURL = keycloakServerURL
        }

    }

    struct FinishedState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.finished

        init(_: ObvEncoded) {}

        init() {}

        func obvEncode() -> ObvEncoded { return 0.obvEncode() }

    }
}
