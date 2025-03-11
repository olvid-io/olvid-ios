/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvAppCoreConstants



final class ClosePeerConnectionOperation: AsyncOperationWithSpecificReasonForCancel<ClosePeerConnectionOperation.ReasonForCancel>, @unchecked Sendable {

    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "ClosePeerConnectionOperation")

    let peerConnection: ObvPeerConnection
    
    init(peerConnection: ObvPeerConnection) {
        self.peerConnection = peerConnection
    }
    
    
    override func main() async {
        
        os_log("☎️ [WebRTCOperation][ClosePeerConnectionOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️ [WebRTCOperation][ClosePeerConnectionOperation] Finish", log: Self.log, type: .info) }

        let currentConnectionState = peerConnection.connectionState
        
        guard currentConnectionState != .closed else {
            os_log("☎️🛑 Trying to close a peer connection whose connection state is already closed. We do nothing.", log: Self.log, type: .info)
            return finish()
        }
        
        os_log("☎️🛑 Closing peer connection. State before closing: %{public}@", log: Self.log, type: .info, currentConnectionState.debugDescription)
        
        await peerConnection.close()

        assert(peerConnection.connectionState == .closed)
        
        return finish()

    }
    
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        var logType: OSLogType {
            return .fault
        }
    }
    
}
