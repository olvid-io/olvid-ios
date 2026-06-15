/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvJWS
import ObvEncoder
import OlvidUtils

public struct ObvKeycloakState: ObvErrorMaker {
    
    public static let errorDomain = "ObvKeycloakState"

    
    public let keycloakServer: URL
    public let supportedAuthenticationMethods: SupportedAuthenticationMethods
    public let jwks: ObvJWKSet
    public let rawAuthState: Data?
    public let signatureVerificationKey: ObvJWK?
    public let latestLocalRevocationListTimestamp: Date? // Server timestamp, only set at the engine level when informing the app of latest known (locally stored) revocation list timestamp
    public let latestGroupUpdateTimestamp: Date? // Server timestamp, only set at the engine level when informing the app of latest known (locally stored) group update timestamp
    public let isTransferRestricted: Bool

    public init(keycloakServer: URL,
                supportedAuthenticationMethods: SupportedAuthenticationMethods,
                jwks: ObvJWKSet,
                rawAuthState: Data?,
                signatureVerificationKey: ObvJWK?,
                latestLocalRevocationListTimestamp: Date?,
                latestGroupUpdateTimestamp: Date?,
                isTransferRestricted: Bool) {
        self.keycloakServer = keycloakServer
        self.supportedAuthenticationMethods = supportedAuthenticationMethods
        self.jwks = jwks
        self.rawAuthState = rawAuthState
        self.signatureVerificationKey = signatureVerificationKey
        self.latestLocalRevocationListTimestamp = latestLocalRevocationListTimestamp
        self.latestGroupUpdateTimestamp = latestGroupUpdateTimestamp
        self.isTransferRestricted = isTransferRestricted
    }
    
    /// Convenience accessor for the OIDC client ID. Preserved for backward compatibility.
    public var clientId: String {
        supportedAuthenticationMethods.openIdConnect.clientId
    }
    
    /// Convenience accessor for the OIDC client secret. Preserved for backward compatibility.
    public var clientSecret: String? {
        supportedAuthenticationMethods.openIdConnect.clientSecret
    }
    
    public var keycloakConfiguration: ObvKeycloakConfiguration {
        .init(keycloakServerURL: keycloakServer,
              clientId: clientId,
              clientSecret: clientSecret)
    }

}


/// Implements `ObvFailableCodable` as `ObvKeycloakState` is used within protocol messages.
/// Note that `latestLocalRevocationListTimestamp` and `latestGroupUpdateTimestamp` are lost in the encoding process.
extension ObvKeycloakState: ObvFailableCodable {

    private enum ObvCodingKeys: String, CaseIterable, CodingKey {
        
        case keycloakServer = "ks"
        case idBased = "ida"
        case clientId = "ci"
        case clientSecret = "cs"
        case jwks = "jwks"
        case rawAuthState = "sas"
        case signatureVerificationKey = "sk"
        case isTransferRestricted = "tp"

        var key: Data { rawValue.data(using: .utf8)! }
        
    }

    public func obvEncode() throws -> ObvEncoded {
        var obvDict = [Data: ObvEncoded]()
        for codingKey in ObvCodingKeys.allCases {
            switch codingKey {
            case .keycloakServer:
                try obvDict.obvEncode(keycloakServer, forKey: codingKey)
            case .idBased:
                if self.supportedAuthenticationMethods.idBased != nil {
                    try obvDict.obvEncode(true, forKey: codingKey)
                }
            case .clientId:
                try obvDict.obvEncode(self.supportedAuthenticationMethods.openIdConnect.clientId, forKey: codingKey)
            case .clientSecret:
                try obvDict.obvEncodeIfPresent(self.supportedAuthenticationMethods.openIdConnect.clientSecret, forKey: codingKey)
            case .jwks:
                try obvDict.obvEncode(jwks, forKey: codingKey)
            case .rawAuthState:
                try obvDict.obvEncodeIfPresent(rawAuthState, forKey: codingKey)
            case .signatureVerificationKey:
                try obvDict.obvEncodeIfPresent(signatureVerificationKey, forKey: codingKey)
            case .isTransferRestricted:
                try obvDict.obvEncodeIfPresent(isTransferRestricted, forKey: codingKey)
            }
        }
        return obvDict.obvEncode()
    }

    
    public init?(_ obvEncoded: ObvEncoder.ObvEncoded) {
        guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
        do {
            let keycloakServer = try obvDict.obvDecode(URL.self, forKey: ObvCodingKeys.keycloakServer)
            
            let clientId = try obvDict.obvDecode(String.self, forKey: ObvCodingKeys.clientId)
            let clientSecret = try obvDict.obvDecodeIfPresent(String.self, forKey: ObvCodingKeys.clientSecret)
            let openIdConnect = ObvKeycloakAuthOIDC(clientId: clientId, clientSecret: clientSecret)

            let idBased: ObvKeycloakAuthIdBased?
            if try obvDict.obvDecodeIfPresent(Bool.self, forKey: ObvCodingKeys.idBased) == true {
                idBased = .init()
            } else {
                idBased = nil
            }
            
            let supportedAuthenticationMethods = SupportedAuthenticationMethods(openIdConnect: openIdConnect, idBased: idBased)
            
            let jwks = try obvDict.obvDecode(ObvJWKSet.self, forKey: ObvCodingKeys.jwks)
            let rawAuthState = try obvDict.obvDecodeIfPresent(Data.self, forKey: ObvCodingKeys.rawAuthState)
            let signatureVerificationKey = try obvDict.obvDecodeIfPresent(ObvJWK.self, forKey: ObvCodingKeys.signatureVerificationKey)
            let isTransferRestricted = try obvDict.obvDecodeIfPresent(Bool.self, forKey: ObvCodingKeys.isTransferRestricted) ?? false
            self.init(
                keycloakServer: keycloakServer,
                supportedAuthenticationMethods: supportedAuthenticationMethods,
                jwks: jwks,
                rawAuthState: rawAuthState,
                signatureVerificationKey: signatureVerificationKey,
                latestLocalRevocationListTimestamp: nil,
                latestGroupUpdateTimestamp: nil,
                isTransferRestricted: isTransferRestricted)
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }
    
}
