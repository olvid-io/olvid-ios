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



final class RemoveIceCandidatesOperation: AsyncOperationWithSpecificReasonForCancel<RemoveIceCandidatesOperation.ReasonForCancel>, @unchecked Sendable {

    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "RemoveIceCandidatesOperation")

    private let peerConnection: ObvPeerConnection
    private let iceCandidates: [RTCIceCandidate]
    
    init(peerConnection: ObvPeerConnection, iceCandidates: [RTCIceCandidate]) {
        self.peerConnection = peerConnection
        self.iceCandidates = iceCandidates
    }
    

    override func main() async {
        os_log("☎️❄️ [WebRTCOperation][RemoveIceCandidatesOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️❄️ [WebRTCOperation][RemoveIceCandidatesOperation] Finish", log: Self.log, type: .info) }
        await peerConnection.removeIceCandidates(iceCandidates)
        return finish()
    }
    

    enum ReasonForCancel: LocalizedErrorWithLogType {
        var logType: OSLogType {
            return .fault
        }
    }
    
}
