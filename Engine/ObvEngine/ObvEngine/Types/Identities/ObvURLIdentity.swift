/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


public struct ObvURLIdentity {
    
    public let cryptoId: ObvCryptoId
    public let fullDisplayName: String
    
    init(cryptoId: ObvCryptoId, fullDisplayName: String) {
        self.cryptoId = cryptoId
        self.fullDisplayName = fullDisplayName
    }
    
    
    init(cryptoIdentity: ObvCryptoIdentity, fullDisplayName: String) {
        self.init(cryptoId: ObvCryptoId.init(cryptoIdentity: cryptoIdentity),
                  fullDisplayName: fullDisplayName)
    }

}


// MARK: - Equatable

extension ObvURLIdentity: Equatable {
    
    public static func == (lhs: ObvURLIdentity, rhs: ObvURLIdentity) -> Bool {
        return lhs.cryptoId == rhs.cryptoId
    }
    
}

// MARK: - Implementing ObvCodable

extension ObvURLIdentity: ObvCodable {
    
    public init?(_ obvEncoded: ObvEncoded) {
        let cryptoIdentity: ObvCryptoIdentity
        let fullDisplayName: String
        do { (cryptoIdentity, fullDisplayName) = try obvEncoded.decode() } catch { return nil }
        self.init(cryptoId: ObvCryptoId(cryptoIdentity: cryptoIdentity), fullDisplayName: fullDisplayName)
    }
    
    public func encode() -> ObvEncoded {
        return [self.cryptoId.cryptoIdentity, fullDisplayName].encode()
    }
}


// MARK: - Implementing CustomStringConvertible

extension ObvURLIdentity: CustomStringConvertible {
    public var description: String {
        return "ObvURLIdentity<\(self.fullDisplayName)>"
    }
}


// MARK: - Export/import as an URL (for QR codes)

extension ObvURLIdentity {
    
    public var urlRepresentation: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "invitation.olvid.io"
        components.path = "/"
        components.fragment = self.encode().rawData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return components.url!
    }
    
    public init?(urlRepresentation: URL) {
        guard let components = URLComponents(url: urlRepresentation, resolvingAgainstBaseURL: false) else { return nil }
        guard components.scheme == "https" else { return nil }
        guard components.host == "invitation.olvid.io" else { return nil }
        let rawBase64: String
        do {
            if let fragment = components.fragment {
                rawBase64 = fragment
            } else {
                var path = components.path
                path.removeFirst()
                rawBase64 = path
            }
        }
        let base64EncodedString = rawBase64
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
            .padding(toLength: ((rawBase64.count+3)/4)*4, withPad: "====", startingAt: 0)
        guard let rawEncoded = Data(base64Encoded: base64EncodedString) else { return nil }
        guard let encoded = ObvEncoded(withRawData: rawEncoded) else { return nil }
        guard let qrIdentity = ObvURLIdentity(encoded) else { return nil }
        self = qrIdentity
    }
}
