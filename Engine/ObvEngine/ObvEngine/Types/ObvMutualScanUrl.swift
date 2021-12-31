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


public struct ObvMutualScanUrl {
    
    static let scheme = "https"
    static let host = "invitation.olvid.io"
    static let path = "/2"
    
    public let cryptoId: ObvCryptoId
    public let fullDisplayName: String
    public let signature: Data

    var identity: Data { cryptoId.getIdentity() }
    
    init(cryptoId: ObvCryptoId, fullDisplayName: String, signature: Data) {
        self.cryptoId = cryptoId
        self.fullDisplayName = fullDisplayName
        self.signature = signature
    }
    
    public var urlRepresentation: URL {
        var components = URLComponents()
        components.scheme = ObvMutualScanUrl.scheme
        components.host = ObvMutualScanUrl.host
        components.path = ObvMutualScanUrl.path
        components.fragment = self.encode().rawData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return components.url!
    }

    public init?(urlRepresentation: URL) {
        guard let components = URLComponents(url: urlRepresentation, resolvingAgainstBaseURL: false) else { return nil }
        guard components.scheme == ObvMutualScanUrl.scheme else { return nil }
        guard components.host == ObvMutualScanUrl.host else { return nil }
        guard components.path == ObvMutualScanUrl.path else { return nil }
        guard let rawBase64 = components.fragment else { return nil }
        let base64EncodedString = rawBase64
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "-", with: "+")
            .padding(toLength: ((rawBase64.count+3)/4)*4, withPad: "====", startingAt: 0)
        guard let rawEncoded = Data(base64Encoded: base64EncodedString) else { return nil }
        guard let encoded = ObvEncoded(withRawData: rawEncoded) else { return nil }
        guard let mutualScanUrl = ObvMutualScanUrl(encoded) else { return nil }
        self = mutualScanUrl
    }

}


// MARK: - Implementing ObvCodable

extension ObvMutualScanUrl: ObvCodable {
    
    public init?(_ obvEncoded: ObvEncoded) {
        let cryptoIdentity: ObvCryptoIdentity
        let fullDisplayName: String
        let signature: Data
        do { (cryptoIdentity, fullDisplayName, signature) = try obvEncoded.decode() } catch { return nil }
        self.init(cryptoId: ObvCryptoId(cryptoIdentity: cryptoIdentity),
                  fullDisplayName: fullDisplayName,
                  signature: signature)
    }
    
    public func encode() -> ObvEncoded {
        return [self.cryptoId.cryptoIdentity, fullDisplayName, signature].encode()
    }
}
