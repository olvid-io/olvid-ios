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



final class AddIceCandidateOperation: AsyncOperationWithSpecificReasonForCancel<AddIceCandidateOperation.ReasonForCancel> {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "AddIceCandidateOperation")

    enum InputType {
        case peerConnection(peerConnection: ObvPeerConnection)
        case operation(op: CreatePeerConnectionOperation)
    }
    
    private let input: InputType
    private let iceCandidate: RTCIceCandidate
    
    init(input: InputType, iceCandidate: RTCIceCandidate) {
        self.input = input
        self.iceCandidate = iceCandidate
    }
    

    override func main() async {
        os_log("☎️❄️ [WebRTCOperation][AddIceCandidateOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️❄️ [WebRTCOperation][AddIceCandidateOperation] Finish", log: Self.log, type: .info) }
        
        let peerConnection: ObvPeerConnection
        switch input {
        case .peerConnection(let _peerConnection):
            peerConnection = _peerConnection
        case .operation(let op):
            guard let _peerConnection = op.peerConnection else {
                assertionFailure()
                return cancel(withReason: .noRTCPeerConnectionProvided)
            }
            peerConnection = _peerConnection
        }
        
        do {
            try await peerConnection.addIceCandidate(iceCandidate)
        } catch {
            assertionFailure()
            return cancel(withReason: .addIceCandidateFailed(error: error))
        }
        return finish()
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        case noRTCPeerConnectionProvided
        case addIceCandidateFailed(error: Error)
        var logType: OSLogType {
            return .fault
        }
    }
    
}


//final class AddIceCandidateOperation: OperationWithSpecificReasonForCancel<AddIceCandidateOperation.ReasonForCancel> {
//
//    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "AddIceCandidateOperation")
//
//    private let peerConnection: RTCPeerConnection
//    private let iceCandidate: RTCIceCandidate
//    
//    init(peerConnection: RTCPeerConnection, iceCandidate: RTCIceCandidate) {
//        self.peerConnection = peerConnection
//        self.iceCandidate = iceCandidate
//    }
//    
//    
//    private var _isFinished = false {
//        willSet { willChangeValue(for: \.isFinished) }
//        didSet { didChangeValue(for: \.isFinished) }
//    }
//    
//    
//    final public override var isFinished: Bool { _isFinished }
//
//    
//    final public override func cancel(withReason reason: ReasonForCancel) {
//        super.cancel(withReason: reason)
//        _isFinished = true
//    }
//    
//
//    final public func finish() {
//        _isFinished = true
//    }
//
//
//    override func main() {
//        os_log("☎️❄️ [WebRTCOperation][AddIceCandidateOperation] Start", log: Self.log, type: .info)
//        defer { os_log("☎️❄️ [WebRTCOperation][AddIceCandidateOperation] Finish", log: Self.log, type: .info) }
//        
//        peerConnection.add(iceCandidate) { [weak self] error in
//            guard let self else { return }
//            if let error {
//                return cancel(withReason: .addIceCandidateFailed(error: error))
//            } else {
//                return finish()
//            }
//        }
//    }
//    
//    
//    enum ReasonForCancel: LocalizedErrorWithLogType {
//        case addIceCandidateFailed(error: Error)
//        var logType: OSLogType {
//            return .fault
//        }
//    }
//    
//}
//
