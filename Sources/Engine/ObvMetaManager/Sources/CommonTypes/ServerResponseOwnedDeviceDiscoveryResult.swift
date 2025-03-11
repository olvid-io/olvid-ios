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
import ObvCrypto


/// This type is used for a specific type of response of a server query, namely for the `ownedDeviceDiscovery` response.
public enum ServerResponseOwnedDeviceDiscoveryResult: ObvCodable {
    
    case failure
    case success(encryptedOwnedDeviceDiscoveryResult: EncryptedData)
    
    private enum RawKind: Int, CaseIterable, ObvCodable {
        
        case failure = 0
        case success = 1
        
        func obvEncode() -> ObvEncoder.ObvEncoded {
            self.rawValue.obvEncode()
        }

        init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
            guard let rawValue = Int(obvEncoded) else { assertionFailure(); return nil }
            guard let rawKind = RawKind(rawValue: rawValue) else { assertionFailure(); return nil }
            self = rawKind
        }
        
    }
    
    private var rawKind: RawKind {
        switch self {
        case .failure:
            return .failure
        case .success:
            return .success
        }
    }
        
    public func obvEncode() -> ObvEncoded {
        switch self {
        case .failure:
            return [rawKind.obvEncode()].obvEncode()
        case .success(encryptedOwnedDeviceDiscoveryResult: let encryptedOwnedDeviceDiscoveryResult):
            return [rawKind.obvEncode(), encryptedOwnedDeviceDiscoveryResult.obvEncode()].obvEncode()
        }
    }
    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
        guard let encodedRawKind = listOfEncoded.first else { return nil }
        guard let rawKind = RawKind(encodedRawKind) else { return nil }
        switch rawKind {
        case .failure:
            self = .failure
        case .success:
            guard listOfEncoded.count == 2 else { assertionFailure(); return nil }
            guard let encryptedOwnedDeviceDiscoveryResult = EncryptedData(listOfEncoded[1]) else { assertionFailure(); return nil }
            self = .success(encryptedOwnedDeviceDiscoveryResult: encryptedOwnedDeviceDiscoveryResult)
        }
    }

}

