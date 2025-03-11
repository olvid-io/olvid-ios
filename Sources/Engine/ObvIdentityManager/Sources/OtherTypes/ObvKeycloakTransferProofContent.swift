/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvCrypto


/// If the transfer of a keycloak managed profile is "restricted", the target device must provide a keycloak authentication proof to the source device.
/// The proof itself is represented by the ``ObvType.ObvKeycloakTransferProof`` type. On reception, the source device checks the proof (i.e., check the signature) against the keycloak signature verification
/// key. If the signature is valid, the returned payload is represented by this structure.
struct ObvKeycloakTransferProofContent {

    let ownedCryptoId: ObvCryptoIdentity
    let keycloakId: String
    let sessionNumber: ObvOwnedIdentityTransferSessionNumber
    let sas: ObvOwnedIdentityTransferSas
    
}


extension ObvKeycloakTransferProofContent: Decodable {
    
    enum CodingKeys: String, CodingKey {
        case ownedCryptoId = "identity"
        case keycloakId = "keycloak_id"
        case sessionNumber = "session_id"
        case sas = "sas"
    }
    
    static func jsonDecode(payload: Data) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: payload)
    }


    init(from decoder: any Decoder) throws {

        let values = try decoder.container(keyedBy: CodingKeys.self)

        // ownedCryptoId

        let ownedIdentity = try values.decode(Data.self, forKey: .ownedCryptoId)
        guard let ownedCryptoIdentity = ObvCryptoIdentity(from: ownedIdentity) else {
            assertionFailure()
            throw ObvError.decodingError
        }
        
        // sessionNumber
        
        guard let rawSessionNumber = Int(try values.decode(String.self, forKey: .sessionNumber)) else {
            assertionFailure()
            throw ObvError.decodingError
        }
        let sessionNumber = try ObvOwnedIdentityTransferSessionNumber(sessionNumber: rawSessionNumber)
        
        // sas
        
        guard let rawSas = try values.decode(String.self, forKey: .sas).data(using: .utf8) else {
            assertionFailure()
            throw ObvError.decodingError
        }
        let sas = try ObvOwnedIdentityTransferSas.init(fullSas: rawSas)
        
        // keycloakId
        
        let keycloakId = try values.decode(String.self, forKey: .keycloakId)

        self = ObvKeycloakTransferProofContent(ownedCryptoId: ownedCryptoIdentity, keycloakId: keycloakId, sessionNumber: sessionNumber, sas: sas)
        
    }
    
}


extension ObvKeycloakTransferProofContent {
    
    /// If a keycloak profil transfer is restricted by the keycloak server, the target must provide a proof (signature) to the source. If valid, the signature verification returns a payload, represented by this `ObvKeycloakTransferProofContent` structure.
    /// Once the signature is verified, we still must check that the payload is valid against the elements that we expect to be signed. The verification is made by this method.
    func isValid(ownedCryptoId: ObvCryptoIdentity, keycloakId: String, keycloakTransferProofElements: ObvKeycloakTransferProofElements) -> Bool {
        return self.ownedCryptoId == ownedCryptoId &&
        self.keycloakId == keycloakId &&
        self.sessionNumber == keycloakTransferProofElements.sessionNumber &&
        self.sas == keycloakTransferProofElements.sas
    }
    
}


extension ObvKeycloakTransferProofContent {
    
    enum ObvError: Error {
        case decodingError
    }
    
}
