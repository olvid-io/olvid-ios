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

public struct CryptoIdentityWithCoreDetailsAndDevices {
    
    public let cryptoIdentity: ObvCryptoIdentity
    public let coreDetails: ObvIdentityCoreDetails
    public let deviceUids: Set<UID>
    
    public init(cryptoIdentity: ObvCryptoIdentity, coreDetails: ObvIdentityCoreDetails, deviceUids: Set<UID>) {
        self.cryptoIdentity = cryptoIdentity
        self.coreDetails = coreDetails
        self.deviceUids = deviceUids
    }
    
}


// MARK: - ObvCodable

extension CryptoIdentityWithCoreDetailsAndDevices: ObvCodable {
    
    public func obvEncode() -> ObvEncoded {
        let listOfEncodedDeviceUids = deviceUids.map { $0.obvEncode() }
        let encodedListOfDeviceUids = listOfEncodedDeviceUids.obvEncode()
        let encodedCoreDetails = try! coreDetails.jsonEncode()
        return [cryptoIdentity.obvEncode(), encodedCoreDetails.obvEncode(), encodedListOfDeviceUids].obvEncode()
    }

    
    public init?(_ encoded: ObvEncoded) {
        guard let encodedElements = [ObvEncoded](encoded, expectedCount: 3) else { return nil }
        do {
            self.cryptoIdentity = try encodedElements[0].obvDecode()
            let encodedCoreDetails: Data = try encodedElements[1].obvDecode()
            self.coreDetails = try ObvIdentityCoreDetails(encodedCoreDetails)
            guard let encodedDeviceUids = [ObvEncoded](encodedElements[2]) else { return nil }
            self.deviceUids = try Set(encodedDeviceUids.map { try $0.obvDecode() })
        } catch {
            return nil
        }
    }
    
    
}


// MARK: - Hashable

extension CryptoIdentityWithCoreDetailsAndDevices: Hashable {
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.cryptoIdentity.getIdentity())
    }
    
}


// MARK: - Equatable

extension CryptoIdentityWithCoreDetailsAndDevices: Equatable {
    
    public static func == (lhs: CryptoIdentityWithCoreDetailsAndDevices, rhs: CryptoIdentityWithCoreDetailsAndDevices) -> Bool {
        return lhs.cryptoIdentity == rhs.cryptoIdentity
    }
    
}
