/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import WebRTC
import OlvidUtils



final class RestartIceIfRequiredOperation: AsyncOperationWithSpecificReasonForCancel<RestartIceIfRequiredOperation.ReasonForCancel> {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "RestartIceIfRequiredOperation")

    private let peerConnection: ObvPeerConnection
    private let shouldISendTheOfferToCallParticipant: Bool
    
    init(peerConnection: ObvPeerConnection, shouldISendTheOfferToCallParticipant: Bool) {
        self.peerConnection = peerConnection
        self.shouldISendTheOfferToCallParticipant = shouldISendTheOfferToCallParticipant
    }
    

    override func main() async {
        
        os_log("☎️❄️ [WebRTCOperation][RestartIceIfRequiredOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️❄️ [WebRTCOperation][RestartIceIfRequiredOperation] Finish", log: Self.log, type: .info) }

        guard isRestartICENeeded else {
            return finish()
        }
        
        if isRollbackNeeded {
            let rollbackSessionDescription = RTCSessionDescription(type: .rollback, sdp: "")
            do {
                try await peerConnection.setLocalDescription(rollbackSessionDescription)
            } catch {
                return cancel(withReason: .rollbackFailed(error: error))
            }
        }
        
        await peerConnection.restartIce()
        
        return finish()

    }
    
    
    private var isRestartICENeeded: Bool {
        switch peerConnection.signalingState {
        case .haveRemoteOffer:
            return shouldISendTheOfferToCallParticipant
        default:
            return true
        }
    }
    
    private var isRollbackNeeded: Bool {
        switch peerConnection.signalingState {
        case .haveLocalOffer:
            return true
        case .haveRemoteOffer:
            return shouldISendTheOfferToCallParticipant
        case .stable, .haveLocalPrAnswer, .haveRemotePrAnswer, .closed:
            return false
        @unknown default:
            assertionFailure()
            return false
        }
    }
    
        
    enum ReasonForCancel: LocalizedErrorWithLogType {
        case rollbackFailed(error: Error)
        var logType: OSLogType {
            return .fault
        }
    }
    
}
