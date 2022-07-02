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
import ObvCrypto
import ObvEncoder
import ObvTypes


public struct ObvGenericIdentity: ObvIdentity {
    
    public let cryptoId: ObvCryptoId
    public let currentIdentityDetails: ObvIdentityDetails
        
    init(cryptoIdentity: ObvCryptoIdentity, currentIdentityDetails: ObvIdentityDetails) {
        self.cryptoId = ObvCryptoId(cryptoIdentity: cryptoIdentity)
        self.currentIdentityDetails = currentIdentityDetails
    }
    
    public init(cryptoId: ObvCryptoId, currentIdentityDetails: ObvIdentityDetails) {
        self.cryptoId = cryptoId
        self.currentIdentityDetails = currentIdentityDetails
    }
    
    init(cryptoIdentity: ObvCryptoIdentity, currentCoreIdentityDetails: ObvIdentityCoreDetails) {
        self.cryptoId = ObvCryptoId(cryptoIdentity: cryptoIdentity)
        self.currentIdentityDetails = ObvIdentityDetails(coreDetails: currentCoreIdentityDetails, photoURL: nil)
    }
    
    init?(userDetails: UserDetails) {
        guard let identity = userDetails.identity else { return nil }
        guard let cryptoId = try? ObvCryptoId(identity: identity) else { return nil }
        guard let coreDetails = try? userDetails.getCoreDetails() else { return nil }
        let detail = ObvIdentityDetails(coreDetails: coreDetails, photoURL: nil)
        self.init(cryptoId: cryptoId, currentIdentityDetails: detail)
    }
}


// MARK: - Implementing CustomStringConvertible

extension ObvGenericIdentity: CustomStringConvertible {
    public var description: String {
        return "ObvGenericIdentity<\(currentIdentityDetails.coreDetails.getFullDisplayName())>"
    }
}


// MARK: - Implementing ObvCodable

extension ObvGenericIdentity: ObvCodable {

    public init?(_ obvEncoded: ObvEncoded) {
        let encodedIdentityDetails: Data
        let cryptoIdentity: ObvCryptoIdentity
        do { (cryptoIdentity, encodedIdentityDetails) = try obvEncoded.obvDecode() } catch { return nil }
        let identityDetails: ObvIdentityDetails
        do { identityDetails = try ObvIdentityDetails(encodedIdentityDetails) } catch { return nil }
        self.init(cryptoIdentity: cryptoIdentity, currentIdentityDetails: identityDetails)
    }
    
    public func obvEncode() -> ObvEncoded {
        let encodedIdentityDetails = try! currentIdentityDetails.jsonEncode()
        return [self.cryptoId.cryptoIdentity, encodedIdentityDetails].obvEncode()
    }
}


extension ObvGenericIdentity {
    
    public func getObvURLIdentity() -> ObvURLIdentity {
        return ObvURLIdentity(cryptoId: self.cryptoId,
                              fullDisplayName: self.currentIdentityDetails.coreDetails.getFullDisplayName())
    }
    
}
