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
import ObvMetaManager
import ObvTypes
import ObvCrypto
import ObvServerInterface
import OlvidUtils


final class GetTurnCredentialsOperation: Operation {

    enum ReasonForCancel {
        case identityDelegateIsNotSet
        case serverSessionRequired
        case serverSessionHasNoToken
        case getTurnCredentialsTrackerNotSet
        case failedToCreateTask(error: Error)
    }

    private let ownedIdentity: ObvCryptoIdentity
    private let callUuid: UUID
    private let username1: String
    private let username2: String
    private let obvContext: ObvContext
    private let logSubsystem: String

    private weak var identityDelegate: ObvIdentityDelegate?
    private weak var tracker: GetTurnCredentialsTracker?
    private weak var wellKnownCacheDelegate: WellKnownCacheDelegate?
    
    var flowId: FlowIdentifier { obvContext.flowId }

    init(ownedIdentity: ObvCryptoIdentity, callUuid: UUID, username1: String, username2: String, obvContext: ObvContext, logSubsystem: String, identityDelegate: ObvIdentityDelegate, tracker: GetTurnCredentialsTracker, wellKnownCacheDelegate: WellKnownCacheDelegate) {
        self.ownedIdentity = ownedIdentity
        self.callUuid = callUuid
        self.username1 = username1
        self.username2 = username2
        self.obvContext = obvContext
        self.identityDelegate = identityDelegate
        self.tracker = tracker
        self.wellKnownCacheDelegate = wellKnownCacheDelegate
        self.logSubsystem = logSubsystem
        super.init()
    }
    
    private(set) var reasonForCancel: ReasonForCancel?

    private func cancel(withReason reason: ReasonForCancel) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }


    override func main() {

        guard let identityDelegate = identityDelegate else {
            cancel(withReason: .identityDelegateIsNotSet)
            return
        }

        guard let tracker = self.tracker else {
            return cancel(withReason: .getTurnCredentialsTrackerNotSet)
        }

        guard let wellKnownCacheDelegate = self.wellKnownCacheDelegate else {
            tracker.getTurnCredentialsFailure(ownedIdentity: self.ownedIdentity, callUuid: self.callUuid, withError: .wellKnownNotCached, flowId: self.flowId)
            return cancel(withReason: .failedToCreateTask(error: GetTurnCredentialsURLSessionDelegate.ErrorForTracker.wellKnownNotCached))
        }

        guard case .success(let turnServerURLs) = wellKnownCacheDelegate.getTurnURLs(for: ownedIdentity.serverURL, flowId: self.flowId) else {
            tracker.getTurnCredentialsFailure(ownedIdentity: self.ownedIdentity, callUuid: self.callUuid, withError: .wellKnownNotCached, flowId: self.flowId)
            return cancel(withReason: .failedToCreateTask(error: GetTurnCredentialsURLSessionDelegate.ErrorForTracker.wellKnownNotCached))
        }

        guard !turnServerURLs.isEmpty else {
            tracker.getTurnCredentialsFailure(ownedIdentity: self.ownedIdentity, callUuid: self.callUuid, withError: .serverDoesNotSupportCalls, flowId: self.flowId)
            return cancel(withReason: .failedToCreateTask(error: GetTurnCredentialsURLSessionDelegate.ErrorForTracker.serverDoesNotSupportCalls))
        }

        obvContext.performAndWait {
            
            guard let serverSession = try? ServerSession.get(within: obvContext, withIdentity: ownedIdentity) else {
                cancel(withReason: .serverSessionRequired)
                return
            }

            guard let token = serverSession.token else {
                cancel(withReason: .serverSessionHasNoToken)
                return
            }
            
            let sessionDelegate = GetTurnCredentialsURLSessionDelegate(ownedIdentity: ownedIdentity, callUuid: callUuid, flowId: flowId, logSubsystem: logSubsystem, tracker: tracker)
            let sessionConfiguration = URLSessionConfiguration.ephemeral
            let session = URLSession(configuration: sessionConfiguration, delegate: sessionDelegate, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }

            let method = GetTurnCredentialsServerMethod(ownedIdentity: ownedIdentity,
                                                        token: token,
                                                        username1: username1,
                                                        username2: username2,
                                                        flowId: flowId,
                                                        identityDelegate: identityDelegate)
            
            let task: URLSessionDataTask
            do {
                task = try method.dataTask(within: session)
            } catch let error {
                return cancel(withReason: .failedToCreateTask(error: error))
            }
            task.resume()
            
        }
        
    }
}
