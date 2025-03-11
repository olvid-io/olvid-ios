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


final class SendDataThroughPeerConnectionOperation: AsyncOperationWithSpecificReasonForCancel<SendDataThroughPeerConnectionOperation.ReasonForCancel>, @unchecked Sendable {
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "SendDataThroughPeerConnectionOperation")

    private let peerConnection: ObvPeerConnection
    private let message: WebRTCDataChannelMessageJSON
    
    init(peerConnection: ObvPeerConnection, message: WebRTCDataChannelMessageJSON) {
        self.peerConnection = peerConnection
        self.message = message
    }
    
    
    override func main() async {
     
        os_log("☎️ [WebRTCOperation][SendDataThroughPeerConnectionOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️ [WebRTCOperation][SendDataThroughPeerConnectionOperation] Finish", log: Self.log, type: .info) }

        let buffer: RTCDataBuffer
        do {
            let data = try message.jsonEncode()
            buffer = RTCDataBuffer(data: data, isBinary: false)
        } catch {
            return cancel(withReason: .messageEncodingFailed(error: error))
        }
        
        let isSuccess = await peerConnection.sendData(buffer: buffer)
        
        guard isSuccess else {
            return cancel(withReason: .sendDataThroughPeerConnectionFailed)
        }

        return finish()
    }
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case sendDataThroughPeerConnectionFailed
        case messageEncodingFailed(error: Error)
        
        var logType: OSLogType {
            return .fault
        }
    }

}
