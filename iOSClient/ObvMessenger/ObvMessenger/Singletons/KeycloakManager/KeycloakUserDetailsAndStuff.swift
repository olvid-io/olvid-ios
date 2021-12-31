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
import ObvEngine
import ObvTypes
import JWS


public struct KeycloakUserDetailsAndStuff {
    
    public let signedUserDetails: SignedUserDetails
    public let server: URL
    public let apiKey: UUID?
    public let pushTopics: Set<String>
    public let selfRevocationTestNonce: String?
    public let serverSignatureVerificationKey: ObvJWK

    public init(signedUserDetails: SignedUserDetails, serverSignatureVerificationKey: ObvJWK, server: URL, apiKey: UUID?, pushTopics: Set<String>, selfRevocationTestNonce: String?) {
        self.signedUserDetails = signedUserDetails
        self.server = server
        self.apiKey = apiKey
        self.pushTopics = pushTopics
        self.selfRevocationTestNonce = selfRevocationTestNonce
        self.serverSignatureVerificationKey = serverSignatureVerificationKey
    }
    
    public func getObvIdentityCoreDetails() throws -> ObvIdentityCoreDetails {
        try signedUserDetails.getObvIdentityCoreDetails()
    }

    public var id: String { self.signedUserDetails.id }
    public var identity: Data? { self.signedUserDetails.identity }
    public var username: String? { self.signedUserDetails.username }
    public var firstName: String? { self.signedUserDetails.firstName }
    public var lastName: String? { self.signedUserDetails.lastName }
    public var position: String? { self.signedUserDetails.position }
    public var company: String? { self.signedUserDetails.company }
    public var descriptiveCharacter: String? { self.signedUserDetails.descriptiveCharacter }

}
