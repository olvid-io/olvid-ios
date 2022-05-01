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
import os.log
import WebRTC


protocol CallDataChannelWorkerDelegate: AnyObject {
    func dataChannel(didReceiveMessage message: WebRTCDataChannelMessageJSON) async
    func dataChannel(didChangeState state: RTCDataChannelState) async
}


/// This class allows to create an object that conforms to the `RTCDataChannelDelegate` protocol. It is typically instanciated as call local variable so
/// as to receive and post messages/data within the data channel corresponding to the peer connection holder of the call.
final class DataChannelWorker: NSObject, RTCDataChannelDelegate {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: DataChannelWorker.self))
    private static func makeError(message: String) -> Error {
        NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }
    private func makeError(message: String) -> Error {
        DataChannelWorker.makeError(message: message)
    }

    weak var delegate: CallDataChannelWorkerDelegate?

    private let peerConnection: ObvPeerConnection

    init(with peerConnection: ObvPeerConnection) async throws {
        self.peerConnection = peerConnection
        super.init()

        let configuration = RTCDataChannelConfiguration()
        configuration.isOrdered = true
        configuration.isNegotiated = true
        configuration.channelId = 1
        await peerConnection.createDataChannel(for: "data0", with: configuration, delegate: self)
    }
    
    
    func sendDataChannelMessage(_ message: WebRTCDataChannelMessageJSON) async throws {
        let data = try message.encode()
        let buffer = RTCDataBuffer(data: data, isBinary: false)
        guard await peerConnection.sendData(buffer: buffer) else {
            throw makeError(message: "☎️ Failed to send message of type \(message.messageType.description) on webrtc data channel")
        }
    }
        
}


// MARK: - RTCDataChannelDelegate

extension DataChannelWorker {
    
    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        os_log("☎️ Data Channel %{public}@ has a new state: %{public}@", log: log, type: .info, dataChannel.debugDescription, dataChannel.readyState.description)
        assert(delegate != nil)
        Task {
            await delegate?.dataChannel(didChangeState: dataChannel.readyState)
        }
    }
    
    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        os_log("☎️ Data Channel %{public}@ did receive message with buffer", log: log, type: .info, dataChannel.debugDescription)
        assert(!buffer.isBinary)
        let webRTCDataChannelMessageJSON: WebRTCDataChannelMessageJSON
        do {
            webRTCDataChannelMessageJSON = try WebRTCDataChannelMessageJSON.decode(data: buffer.data)
        } catch {
            os_log("☎️ Could not decode message received on the RTC data channel as a WebRTCMessageJSON: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
        assert(delegate != nil)
        Task { await delegate?.dataChannel(didReceiveMessage: webRTCDataChannelMessageJSON) }
    }
    
}


// MARK: - RTCDataChannelState+CustomStringConvertible

extension  RTCDataChannelState: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .connecting: return "connecting"
        case .closed: return "closed"
        case .closing: return "closing"
        case .open: return "open"
        default:
            assertionFailure()
            return "unknown"
        }
    }
    
}
