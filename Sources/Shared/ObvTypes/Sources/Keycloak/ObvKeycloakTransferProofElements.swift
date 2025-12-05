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


/// During the transfer of a keycloak profile, the source device may request from the target device a proof that it can authenticate to the keycloak server.
/// This structure represents the elements needed to request a proof on the target device.
public struct ObvKeycloakTransferProofElements {
    
    public let sessionNumber: ObvOwnedIdentityTransferSessionNumber
    public let sas: ObvOwnedIdentityTransferSas
    
    public init(sessionNumber: ObvOwnedIdentityTransferSessionNumber, sas: ObvOwnedIdentityTransferSas) {
        self.sessionNumber = sessionNumber
        self.sas = sas
    }
    
}


/// Conform to `ObvCodable`, as `ObvKeycloakTransferProofElements` can be serialized in a protocol state.
extension ObvKeycloakTransferProofElements: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        [
            self.sessionNumber,
            self.sas,
        ].obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let arrayOfEncoded = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); return nil }
        do {
            self.sessionNumber = try arrayOfEncoded[0].obvDecode()
            self.sas = try arrayOfEncoded[1].obvDecode()
        } catch {
            assertionFailure()
            return nil
        }
    }
    
}
