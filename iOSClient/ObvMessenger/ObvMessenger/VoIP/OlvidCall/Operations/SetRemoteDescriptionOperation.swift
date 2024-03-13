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



final class SetRemoteDescriptionOperation: AsyncOperationWithSpecificReasonForCancel<SetRemoteDescriptionOperation.ReasonForCancel> {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "SetRemoteDescriptionOperation")

    enum Input {
        case peerConnection(peerConnection: ObvPeerConnection)
        case createPeerConnectionOperation(operation: CreatePeerConnectionOperation)
    }
    
    private let input: Input
    private let remoteSessionDescription: RTCSessionDescription
    
    init(input: Input, remoteSessionDescription: RTCSessionDescription) {
        self.input = input
        self.remoteSessionDescription = remoteSessionDescription
    }
    

    override func main() async {
        
        os_log("☎️ [WebRTCOperation][SetRemoteDescriptionOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️ [WebRTCOperation][SetRemoteDescriptionOperation] Finish", log: Self.log, type: .info) }

        do {
            if try countSdpMedia(sessionDescription: remoteSessionDescription.sdp) != 2 {
                assertionFailure()
                return cancel(withReason: .unexpectedNumberOfMediaLinesInSessionDescription)
            }
        } catch {
            assertionFailure()
            return cancel(withReason: .unableToCheckSDP)
        }

        let peerConnection: ObvPeerConnection
        
        switch input {
        case .peerConnection(let _peerConnection):
            peerConnection = _peerConnection
        case .createPeerConnectionOperation(let operation):
            guard let _peerConnection = operation.peerConnection else {
                return cancel(withReason: .noPeerConnectionProvidedByOperation)
            }
            peerConnection = _peerConnection
        }
        
        do {
            debugPrint(remoteSessionDescription.sdp)
            try await peerConnection.setRemoteDescription(remoteSessionDescription)
        } catch {
            return cancel(withReason: .setRemoteDescriptionFailed(error: error))
        }

        return finish()
        
    }
    
    
    private func countSdpMedia(sessionDescription: String) throws -> Int {
        var counter = 0
        let mediaStart = try NSRegularExpression(pattern: "^m=", options: .anchorsMatchLines)
        let lines = sessionDescription.split(whereSeparator: { $0.isNewline }).map({String($0)})
        for line in lines {
            let isFirstLineOfAnotherMediaSection = mediaStart.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) > 0
            if isFirstLineOfAnotherMediaSection {
                counter += 1
            }
        }
        return counter
    }
    
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        case noPeerConnectionProvidedByOperation
        case unableToCheckSDP
        case unexpectedNumberOfMediaLinesInSessionDescription
        case setRemoteDescriptionFailed(error: Error)
        var logType: OSLogType {
            return .fault
        }
    }
    
}
