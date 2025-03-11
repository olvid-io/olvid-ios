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
import ObvEncoder

/// When performing a keycloak restricted profile transfer, the user must authenticate on the target device.
///
/// This structure holds two pieces of information:
/// - Authentication Proof: Sent to the source device to verify authentication.
/// - Authentication State: Saved within the identity manager to prevent subsequent authentication requests after the transfer is complete.
public struct ObvKeycloakTransferProofAndAuthState {
    
    public let proof: ObvKeycloakTransferProof
    public let rawAuthState: Data
    
    public init(proof: ObvKeycloakTransferProof, rawAuthState: Data) {
        self.proof = proof
        self.rawAuthState = rawAuthState
    }
    
}


extension ObvKeycloakTransferProofAndAuthState: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        [
            proof,
            rawAuthState,
        ].obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let encodeds = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); return nil }
        do {
            let proof: ObvKeycloakTransferProof = try encodeds[0].obvDecode()
            let rawAuthState: Data = try encodeds[1].obvDecode()
            self.init(proof: proof, rawAuthState: rawAuthState)
        } catch {
            assertionFailure()
            return nil
        }
    }
    
}
