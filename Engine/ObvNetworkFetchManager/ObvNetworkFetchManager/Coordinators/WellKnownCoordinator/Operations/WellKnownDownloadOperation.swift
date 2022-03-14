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
import OlvidUtils
import os.log
import ObvCrypto
import ObvTypes


protocol WellKnownDownloadOperationDelegate: AnyObject {
    func wellKnownWasDownloaded(server: URL, flowId: FlowIdentifier, wellKnownData: Data)
    func wellKnownWasDownloadFailed(server: URL, flowId: FlowIdentifier)
}


/// This operation launches all the network tasks allowing to download the Well Known of each server passed as a parameter.
/// Each download results in a call to the delegate method.
final class WellKnownDownloadOperation: OperationWithSpecificReasonForCancel<WellKnownDownloadOperationReasonForCancel> {
    
    let servers: Set<URL>
    let flowId: FlowIdentifier
    weak var delegate: WellKnownDownloadOperationDelegate?
    
    init(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier, delegate: WellKnownDownloadOperationDelegate) {
        self.servers = Set(ownedIdentities.map({ $0.serverURL }))
        self.delegate = delegate
        self.flowId = flowId
        super.init()
    }

    init(servers: Set<URL>, flowId: FlowIdentifier, delegate: WellKnownDownloadOperationDelegate) {
        self.servers = servers
        self.delegate = delegate
        self.flowId = flowId
        super.init()
    }

    private let wellKnownPath = "/.well-known"
    private let serverConfigName = "server-config.json"

    override func main() {
        
        let flowId = self.flowId
        guard let delegate = self.delegate else {
            return cancel(withReason: .delegateIsNotSet)
        }

        for server in servers {
            
            let url = server
                .appendingPathComponent(wellKnownPath)
                .appendingPathComponent(serverConfigName)
            
            var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 60)
            urlRequest.allowsCellularAccess = true
            urlRequest.allowsConstrainedNetworkAccess = true
            urlRequest.allowsExpensiveNetworkAccess = true
            
            
            let task = URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    delegate.wellKnownWasDownloadFailed(server: server, flowId: flowId)
                    return
                }
                guard let data = data, (try? WellKnownJSON.decode(data)) != nil else {
                    delegate.wellKnownWasDownloadFailed(server: server, flowId: flowId)
                    return
                }
                delegate.wellKnownWasDownloaded(server: server, flowId: flowId, wellKnownData: data)
            }
            
            task.resume()
        }
        
    }
    
}


public enum WellKnownDownloadOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case delegateIsNotSet

    public var logType: OSLogType {
        switch self {
        case .coreDataError,
             .delegateIsNotSet:
            return .fault
        }
    }

    public var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .delegateIsNotSet:
            return "Delegate is not set"
        }
    }

}
