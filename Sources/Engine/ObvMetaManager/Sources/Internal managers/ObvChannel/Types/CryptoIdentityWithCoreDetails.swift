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

public struct CryptoIdentityWithCoreDetails {
    
    public let cryptoIdentity: ObvCryptoIdentity
    public let coreDetails: ObvIdentityCoreDetails
    
    public init(cryptoIdentity: ObvCryptoIdentity, coreDetails: ObvIdentityCoreDetails) {
        self.cryptoIdentity = cryptoIdentity
        self.coreDetails = coreDetails
    }
    
}


// MARK: - ObvCodable

extension CryptoIdentityWithCoreDetails: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        let encodedCoreDetails = try! coreDetails.jsonEncode()
        return [cryptoIdentity, encodedCoreDetails].obvEncode()
    }

    
    public init?(_ encoded: ObvEncoded) {
        guard let encodedElements = [ObvEncoded](encoded, expectedCount: 2) else { return nil }
        do {
            self.cryptoIdentity = try encodedElements[0].obvDecode()
            let encodedCoreDetails: Data = try encodedElements[1].obvDecode()
            self.coreDetails = try ObvIdentityCoreDetails(encodedCoreDetails)
        } catch {
            return nil
        }
    }
    
    
}


// MARK: - Equatable

extension CryptoIdentityWithCoreDetails: Equatable {
    
    public static func == (lhs: CryptoIdentityWithCoreDetails, rhs: CryptoIdentityWithCoreDetails) -> Bool {
        return lhs.cryptoIdentity == rhs.cryptoIdentity
    }
    
}

// MARK: - Hashable

extension CryptoIdentityWithCoreDetails: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.cryptoIdentity.getIdentity())
    }
    
}


// MARK: - Comparable

extension CryptoIdentityWithCoreDetails: Comparable {
    
    public static func < (lhs: CryptoIdentityWithCoreDetails, rhs: CryptoIdentityWithCoreDetails) -> Bool {
        return ObvCryptoId(cryptoIdentity: lhs.cryptoIdentity) < ObvCryptoId(cryptoIdentity: rhs.cryptoIdentity)
    }
    
}
