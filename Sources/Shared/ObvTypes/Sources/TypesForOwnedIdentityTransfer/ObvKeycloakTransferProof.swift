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
/// This structure represents the proof sent back by the keycloak server upon successful authentication on the target device.
public struct ObvKeycloakTransferProof {

    public let signature: String

    public init(signature: String) {
        self.signature = signature
    }
    
}


extension ObvKeycloakTransferProof: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        self.signature.obvEncode()
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let signature = String(obvEncoded) else { assertionFailure(); return nil }
        self.init(signature: signature)
    }
    
}
