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
import ObvEncoder
import ObvCrypto
import ObvTypes

// MARK: - Protocol States

extension KeycloakContactAdditionProtocol {

    enum StateId: Int, ConcreteProtocolStateId {

        case InitialState = 0
        case WaitingForDeviceDiscovery = 1
        case WaitingForConfirmation = 2
        case CheckingForRevocation = 3
        case Finished = 4

        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState              : return ConcreteProtocolInitialState.self
            case .WaitingForDeviceDiscovery : return WaitingForDeviceDiscoveryState.self
            case .WaitingForConfirmation    : return WaitingForConfirmationState.self
            case .CheckingForRevocation     : return CheckingForRevocationState.self
            case .Finished                  : return FinishedState.self
            }
        }

    }

    struct WaitingForDeviceDiscoveryState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.WaitingForDeviceDiscovery

        let contactIdentity: ObvCryptoIdentity
        let identityCoreDetails: ObvIdentityCoreDetails
        let keycloakServerURL: URL
        let signedOwnedDetails: String // This is a JWS

        func encode() -> ObvEncoded {
            let encodedIdentityCoreDetails = try! identityCoreDetails.encode()
            return [contactIdentity, encodedIdentityCoreDetails, keycloakServerURL, signedOwnedDetails].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded].init(encoded, expectedCount: 4) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].decode()
            let encodedIdentityCoreDetails: Data = try encodedElements[1].decode()
            self.identityCoreDetails = try ObvIdentityCoreDetails(encodedIdentityCoreDetails)
            self.keycloakServerURL = try encodedElements[2].decode()
            self.signedOwnedDetails = try encodedElements[3].decode()
        }

        init(contactIdentity: ObvCryptoIdentity, identityCoreDetails: ObvIdentityCoreDetails, keycloakServerURL: URL, signedOwnedDetails: String) {
            self.contactIdentity = contactIdentity
            self.identityCoreDetails = identityCoreDetails
            self.keycloakServerURL = keycloakServerURL
            self.signedOwnedDetails = signedOwnedDetails
        }


    }

    struct WaitingForConfirmationState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.WaitingForConfirmation

        let contactIdentity: ObvCryptoIdentity
        let keycloakServerURL: URL

        func encode() -> ObvEncoded {
            return [contactIdentity, keycloakServerURL].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded].init(encoded, expectedCount: 2) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].decode()
            self.keycloakServerURL = try encodedElements[1].decode()
        }

        init(contactIdentity: ObvCryptoIdentity, keycloakServerUrl: URL) {
            self.contactIdentity = contactIdentity
            self.keycloakServerURL = keycloakServerUrl
        }

    }

    struct CheckingForRevocationState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.CheckingForRevocation

        let contactIdentity: ObvCryptoIdentity
        let identityCoreDetails: ObvIdentityCoreDetails
        let contactDeviceUids: [UID]
        let keycloakServerURL: URL

        func encode() -> ObvEncoded {
            let encodedIdentityCoreDetails = try! identityCoreDetails.encode()
            return [contactIdentity, encodedIdentityCoreDetails, contactDeviceUids as [ObvEncodable], keycloakServerURL].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded].init(encoded, expectedCount: 4) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].decode()
            let encodedIdentityCoreDetails: Data = try encodedElements[1].decode()
            self.identityCoreDetails = try ObvIdentityCoreDetails(encodedIdentityCoreDetails)
            guard let listOfEncodedDeviceUids = [ObvEncoded](encodedElements[2]) else { throw NSError() }
            contactDeviceUids = try listOfEncodedDeviceUids.map { return try $0.decode() }
            self.keycloakServerURL = try encodedElements[3].decode()
        }

        init(contactIdentity: ObvCryptoIdentity, identityCoreDetails: ObvIdentityCoreDetails, contactDeviceUids: [UID], keycloakServerURL: URL) {
            self.contactIdentity = contactIdentity
            self.identityCoreDetails = identityCoreDetails
            self.contactDeviceUids = contactDeviceUids
            self.keycloakServerURL = keycloakServerURL
        }

    }

    struct FinishedState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.Finished

        init(_: ObvEncoded) {}

        init() {}

        func encode() -> ObvEncoded { return 0.encode() }

    }
}
