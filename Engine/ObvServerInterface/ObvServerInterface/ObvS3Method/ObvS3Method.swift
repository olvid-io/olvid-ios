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
import ObvMetaManager
import ObvTypes
import OlvidUtils

public protocol ObvS3Method {
    
    var signedURL: URL { get }
    
    var isActiveOwnedIdentityRequired: Bool { get }
    var ownedIdentity: ObvCryptoIdentity { get }
    var identityDelegate: ObvIdentityDelegate? { get }
    var flowId: FlowIdentifier { get }

}


public extension ObvS3Method {
    
    func getURLRequest(httpMethod: String, dataToSend: Data?) throws -> URLRequest {
        guard let identityDelegate = self.identityDelegate else {
            throw ObvServerMethodError.ownedIdentityIsActiveCheckerDelegateIsNotSet
        }
        if isActiveOwnedIdentityRequired {
            guard try identityDelegate.isOwnedIdentityActive(ownedIdentity: self.ownedIdentity, flowId: flowId) else {
                throw ObvServerMethodError.ownedIdentityIsNotActive
            }
        }
        var request = URLRequest(url: signedURL)
        request.httpMethod = httpMethod
        request.httpBody = dataToSend
        request.setValue("application/bytes", forHTTPHeaderField: "Content-Type")
        request.setValue("\(ObvServerInterfaceConstants.serverAPIVersion)", forHTTPHeaderField: "Olvid-API-Version")
        request.allowsCellularAccess = true
        return request
    }

}
