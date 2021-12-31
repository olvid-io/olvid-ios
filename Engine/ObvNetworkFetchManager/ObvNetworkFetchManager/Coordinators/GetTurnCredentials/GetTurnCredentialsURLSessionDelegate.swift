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
import CoreData
import ObvMetaManager
import ObvTypes
import ObvServerInterface
import ObvCrypto
import OlvidUtils

final class GetTurnCredentialsURLSessionDelegate: NSObject {
 
    private let uuid = UUID()
    private let flowId: FlowIdentifier
    private let log: OSLog
    private var dataReceived = Data()
    private let ownedIdentity: ObvCryptoIdentity
    private let callUuid: UUID
    private let logCategory = String(describing: GetTurnCredentialsURLSessionDelegate.self)

    private weak var tracker: GetTurnCredentialsTracker?
    private(set) var turnCredentials: TurnCredentials?

    enum ErrorForTracker: Error {
        case aTaskDidBecomeInvalidWithError(error: Error)
        case couldNotParseServerResponse
        case generalErrorFromServer
        case noOutputAvailable
        case invalidSession
        case permissionDenied
        case wellKnownNotCached
        case serverDoesNotSupportCalls

        var localizedDescription: String {
            switch self {
            case .aTaskDidBecomeInvalidWithError(error: let error):
                return "A task did become invalid with error (\(error.localizedDescription)"
            case .couldNotParseServerResponse:
                return "Could not parse the server response"
            case .generalErrorFromServer:
                return "The server returned a general error"
            case .noOutputAvailable:
                return "Internal error"
            case .invalidSession:
                return "The session is invalid"
            case .permissionDenied:
                return "Permission denied by server"
            case .wellKnownNotCached:
                return "Well Known is not cached"
            case .serverDoesNotSupportCalls:
                return "Server does not support calls"
            }
        }
    }

    // First error "wins"
    private var _error: ErrorForTracker?
    private var errorForTracker: ErrorForTracker? {
        get { _error }
        set {
            guard _error == nil && newValue != nil else { return }
            _error = newValue
        }
    }

    init(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, flowId: FlowIdentifier, logSubsystem: String, tracker: GetTurnCredentialsTracker) {
        self.flowId = flowId
        self.ownedIdentity = ownedIdentity
        self.callUuid = callUuid
        self.log = OSLog(subsystem: logSubsystem, category: logCategory)
        self.tracker = tracker
        super.init()
    }

}

protocol GetTurnCredentialsTracker: AnyObject {
    func getTurnCredentialsSuccess(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, turnCredentials: TurnCredentials, flowId: FlowIdentifier)
    func getTurnCredentialsFailure(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, withError: GetTurnCredentialsURLSessionDelegate.ErrorForTracker, flowId: FlowIdentifier)
}

// MARK: - URLSessionDataDelegate

extension GetTurnCredentialsURLSessionDelegate: URLSessionDataDelegate {

    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        dataReceived.append(data)
    }

    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                
        guard error == nil else {
            os_log("The GetTurnCredentialsURLSessionDelegate task failed: %@", log: log, type: .error, error!.localizedDescription)
            self.errorForTracker = .aTaskDidBecomeInvalidWithError(error: error!)
            return
        }
        
        // If we reach this point, the data task did complete without error
        
        guard let (status, turnCredentials) = GetTurnCredentialsServerMethod.parseObvServerResponse(responseData: dataReceived, using: log) else {
            os_log("Could not parse the server response for the GetTurnCredentialsServerMethod", log: log, type: .fault)
            self.errorForTracker = .couldNotParseServerResponse
            return
        }
        
        switch status {
        case .ok:
            assert(self.turnCredentials == nil)
            self.turnCredentials = turnCredentials!
            os_log("We successfully set new Turn credentials", log: log, type: .info)
            
        case .invalidSession:
            self.errorForTracker = .invalidSession
            return
            
        case .permissionDenied:
            self.errorForTracker = .permissionDenied
            return

        case .generalError:
            os_log("Server reported general error during the GetTurnCredentialsURLSessionDelegate", log: log, type: .fault)
            self.errorForTracker = .generalErrorFromServer
            return
        }
        
    }

    
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) {
        
        let tracker = self.tracker
        let flowId = self.flowId
        let ownedIdentity = self.ownedIdentity
        let callUuid = self.callUuid
        
        if let turnCredentials = self.turnCredentials {
            DispatchQueue(label: "Queue for calling getTurnCredentialsURLSessionDidBecomeInvalid").async {
                tracker?.getTurnCredentialsSuccess(ownedIdentity: ownedIdentity, callUuid: callUuid, turnCredentials: turnCredentials, flowId: flowId)
            }
        } else {
            let errorForTracker: ErrorForTracker = self.errorForTracker ?? .noOutputAvailable
            DispatchQueue(label: "Queue for calling getTurnCredentialsURLSessionDidBecomeInvalid").async {
                tracker?.getTurnCredentialsFailure(ownedIdentity: ownedIdentity, callUuid: callUuid, withError: errorForTracker, flowId: flowId)
            }
        }
        
    }

}
