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
import os.log
import ObvEncoder
import ObvCrypto
import ObvMetaManager
import ObvTypes
import OlvidUtils

public protocol ObvServerMethod {

    var serverURL: URL { get }
    var pathComponent: String { get }
    var isActiveOwnedIdentityRequired: Bool { get }
    var ownedIdentity: ObvCryptoIdentity { get }
    var identityDelegate: ObvIdentityDelegate? { get set }
    var flowId: FlowIdentifier { get }
    
}


public extension ObvServerMethod {

    func getURLRequest(dataToSend: Data?) throws -> URLRequest {
        guard let identityDelegate = self.identityDelegate else {
            throw ObvServerMethodError.ownedIdentityIsActiveCheckerDelegateIsNotSet
        }
        if isActiveOwnedIdentityRequired {
            guard try identityDelegate.isOwnedIdentityActive(ownedIdentity: self.ownedIdentity, flowId: flowId) else {
                throw ObvServerMethodError.ownedIdentityIsNotActive
            }
        }
        var request = URLRequest(url: serverURL.appendingPathComponent(pathComponent))
        request.httpMethod = "POST"
        request.httpBody = dataToSend
        request.setValue("application/bytes", forHTTPHeaderField: "Content-Type")
        request.setValue("\(ObvServerInterfaceConstants.serverAPIVersion)", forHTTPHeaderField: "Olvid-API-Version")
        request.allowsCellularAccess = true
        return request
    }
    
    static func genericParseObvServerResponse(responseData: Data, using log: OSLog) -> (UInt8, [ObvEncoded])? {
        
        guard let encodedResponse = ObvEncoded(withRawData: responseData) else {
            os_log("Could not parse the returned data as ObvData", log: log, type: .error)
            return nil
        }
        guard var listOfReturnedData = [ObvEncoded](encodedResponse) else {
            os_log("Could not decode the ObvData as a list", log: log, type: .error)
            return nil
        }
        guard !listOfReturnedData.isEmpty else {
            os_log("Expecting at least 1 element in the list returned by the server, got 0", log: log, type: .error)
            return nil
        }
        
        let encodedServerReturnedStatus = listOfReturnedData.removeFirst()
        guard let decodedServerReturnedStatus = Data(encodedServerReturnedStatus),
            decodedServerReturnedStatus.count == 1 else {
                os_log("The returned data does not start with an encoded status", log: log, type: .error)
                return nil
        }
        let rawServerReturnedStatus: UInt8 = decodedServerReturnedStatus[decodedServerReturnedStatus.startIndex]
        
        return (rawServerReturnedStatus, listOfReturnedData)
        
    }

}

public enum ObvServerMethodError: Error {
    case ownedIdentityIsActiveCheckerDelegateIsNotSet
    case ownedIdentityIsNotActive
    
    var localizedDescription: String {
        switch self {
        case .ownedIdentityIsActiveCheckerDelegateIsNotSet: return "The (identity) delegate allowing to check whether the owned identity is active has not been set"
        case .ownedIdentityIsNotActive: return "The owned identity is not active but is required to be active for this server method"
        }
    }
}
