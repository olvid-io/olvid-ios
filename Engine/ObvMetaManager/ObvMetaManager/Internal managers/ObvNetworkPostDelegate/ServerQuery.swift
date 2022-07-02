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

public struct ServerQuery {
    
    public let ownedIdentity: ObvCryptoIdentity
    public let encodedElements: ObvEncoded
    public let queryType: QueryType
    
    public init(ownedIdentity: ObvCryptoIdentity, queryType: QueryType, encodedElements: ObvEncoded) {
        self.ownedIdentity = ownedIdentity
        self.queryType = queryType
        self.encodedElements = encodedElements
    }
}

extension ServerQuery {
    
    public enum QueryType {
        case deviceDiscovery(of: ObvCryptoIdentity)
        case putUserData(label: String, dataURL: URL, dataKey: AuthenticatedEncryptionKey)
        case getUserData(of: ObvCryptoIdentity, label: String)
        case checkKeycloakRevocation(keycloakServerUrl: URL, signedContactDetails: String)

        private var rawValue: Int {
            switch self {
            case .deviceDiscovery:
                return 0
            case .putUserData:
                return 1
            case .getUserData:
                return 2
            case .checkKeycloakRevocation:
                return 3
            }
        }
        
        public func obvEncode() -> ObvEncoded {
            switch self {
            case .deviceDiscovery(of: let identity):
                return [rawValue, identity].obvEncode()
            case .putUserData(label: let label, dataURL: let dataURL, dataKey: let dataKey):
                return [rawValue, label, dataURL, dataKey].obvEncode()
            case .getUserData(of: let identity, label: let label):
                return [rawValue, identity, label].obvEncode()
            case .checkKeycloakRevocation(keycloakServerUrl: let keycloakServerUrl, signedContactDetails: let signedContactDetails):
                return [rawValue, keycloakServerUrl, signedContactDetails].obvEncode()
            }
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
            guard let encodedRawValue = listOfEncoded.first else { return nil }
            guard let rawValue = Int(encodedRawValue) else { return nil }
            switch rawValue {
            case 0:
                guard listOfEncoded.count == 2 else { return nil }
                guard let identity = ObvCryptoIdentity(listOfEncoded[1]) else { return nil }
                self = .deviceDiscovery(of: identity)
            case 1:
                guard listOfEncoded.count == 4 else { return nil }
                guard let label = String(listOfEncoded[1]) else { return nil }
                guard let dataURL = URL(listOfEncoded[2]) else { return nil }
                guard let dataKey = try? AuthenticatedEncryptionKeyDecoder.decode(listOfEncoded[3]) else { return nil }
                self = .putUserData(label: label, dataURL: dataURL, dataKey: dataKey)
            case 2:
                guard listOfEncoded.count == 3 else { return nil }
                guard let identity = ObvCryptoIdentity(listOfEncoded[1]) else { return nil }
                guard let label = String(listOfEncoded[2]) else { return nil }
                self = .getUserData(of: identity, label: label)
            case 3:
                guard listOfEncoded.count == 3 else { return nil }
                guard let keycloakServerUrl = URL(listOfEncoded[1]) else { return nil }
                guard let signedContactDetails = String(listOfEncoded[2]) else { return nil }
                self = .checkKeycloakRevocation(keycloakServerUrl: keycloakServerUrl, signedContactDetails: signedContactDetails)
            default:
                return nil
            }
        }
        
    }

}
