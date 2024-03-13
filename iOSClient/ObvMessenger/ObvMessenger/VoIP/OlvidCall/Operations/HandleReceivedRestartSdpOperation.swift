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


protocol HandleReceivedRestartSdpOperationDelegate: AnyObject {
    func setReconnectAnswerCounter(op: HandleReceivedRestartSdpOperation, newReconnectAnswerCounter: Int) async
    func getReconnectAnswerCounter(op: HandleReceivedRestartSdpOperation) async -> Int
    func getReconnectOfferCounter(op: HandleReceivedRestartSdpOperation) async -> Int
}


final class HandleReceivedRestartSdpOperation: AsyncOperationWithSpecificReasonForCancel<HandleReceivedRestartSdpOperation.ReasonForCancel> {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "AddIceCandidateOperation")

    private let peerConnection: ObvPeerConnection
    private let sessionDescription: RTCSessionDescription
    private let receivedReconnectCounter: Int
    private let receivedPeerReconnectCounterToOverride: Int
    private let shouldISendTheOfferToCallParticipant: Bool
    private weak var delegate: HandleReceivedRestartSdpOperationDelegate?
    
    init(peerConnection: ObvPeerConnection, sessionDescription: RTCSessionDescription, receivedReconnectCounter: Int, receivedPeerReconnectCounterToOverride: Int, shouldISendTheOfferToCallParticipant: Bool, delegate: HandleReceivedRestartSdpOperationDelegate) {
        self.peerConnection = peerConnection
        self.sessionDescription = sessionDescription
        self.receivedReconnectCounter = receivedReconnectCounter
        self.receivedPeerReconnectCounterToOverride = receivedPeerReconnectCounterToOverride
        self.shouldISendTheOfferToCallParticipant = shouldISendTheOfferToCallParticipant
        self.delegate = delegate
    }
    
    private(set) var shouldCreateAndSetLocalDescription = false
    
    override func main() async {

        os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Finish", log: Self.log, type: .info) }

        guard let delegate else {
            assertionFailure()
            return finish()
        }

        let reconnectAnswerCounter = await delegate.getReconnectAnswerCounter(op: self)
        let reconnectOfferCounter = await delegate.getReconnectOfferCounter(op: self)
        
        os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] receivedReconnectCounter=%d receivedPeerReconnectCounterToOverride=%d reconnectAnswerCounter=%d reconnectOfferCounter=%d", log: Self.log, type: .info, receivedReconnectCounter, receivedPeerReconnectCounterToOverride, reconnectAnswerCounter, reconnectOfferCounter)


        do {
            
            switch sessionDescription.type {
                
            case .offer:
                
                os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] The received SDP is an offer", log: Self.log, type: .info)
                
                // If we receive an offer with a counter smaller than another offer we previously received, we can ignore it.
                guard receivedReconnectCounter >= reconnectAnswerCounter else {
                    os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Received restart offer with counter too low %{public}@ vs. %{public}@", log: Self.log, type: .info, String(receivedReconnectCounter), String(reconnectAnswerCounter))
                    return finish()
                }
                
                switch peerConnection.signalingState {
                    
                case .haveRemoteOffer:
                    os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Received restart offer while already having one --> rollback", log: Self.log, type: .info)
                    try await peerConnection.rollback()
                    
                case .haveLocalOffer:
                    // We already sent an offer.
                    // If we are the offer sender, do nothing, otherwise rollback and process the new offer
                    if shouldISendTheOfferToCallParticipant {
                        if receivedPeerReconnectCounterToOverride == reconnectOfferCounter {
                            os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Received restart offer while already having created an offer. It specifies to override my current offer --> rollback", log: Self.log, type: .info)
                            try await peerConnection.rollback()
                        } else {
                            os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Received restart offer while already having created an offer. I am the offerer --> ignore this new offer", log: Self.log, type: .info)
                            return finish()
                        }
                    } else {
                        os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Received restart offer while already having created an offer. I am not the offerer --> rollback", log: Self.log, type: .info)
                        try await peerConnection.rollback()
                    }
                    
                case .stable:
                    // Make sure we send an answer after setting an offer
                    shouldCreateAndSetLocalDescription = true

                case .haveLocalPrAnswer,
                        .haveRemotePrAnswer,
                        .closed:
                    break

                @unknown default:
                    assertionFailure()
                    break
                }
                                
                os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Setting our stored reconnectAnswerCounter to %d", log: Self.log, type: .info, receivedReconnectCounter)
                await delegate.setReconnectAnswerCounter(op: self, newReconnectAnswerCounter: receivedReconnectCounter)
                
                // Before setting the remote description, we check if it contains a video track.
                // If it is the case, we make sure we do have a video track too
                if try videoMediaExistsIn(sessionDescription: sessionDescription.sdp) {
                    os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Creating and adding a local video and screencast tracks", log: Self.log, type: .info)
                    await peerConnection.createAndAddLocalVideoAndScreencastTracks()
                }
                
                os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Setting remote description", log: Self.log, type: .info)
                try await peerConnection.setRemoteDescription(sessionDescription)
                                
            case .answer:
                
                os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] The received SDP is an answer", log: Self.log, type: .info)

                guard receivedReconnectCounter == reconnectOfferCounter else {
                    os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Received restart answer with bad counter %{public}@ vs. %{public}@", log: Self.log, type: .info, String(receivedReconnectCounter), String(reconnectOfferCounter))
                    return finish()
                }

                guard peerConnection.signalingState == .haveLocalOffer else {
                    os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Received restart answer while not in the haveLocalOffer state --> ignore this answer", log: Self.log, type: .info)
                    return finish()
                }

                os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Setting the answer", log: Self.log, type: .info)
                try await peerConnection.setRemoteDescription(sessionDescription)
                
            default:
                
                assertionFailure()
                
            }
            
            return finish()
            
        } catch {
            assertionFailure()
            return cancel(withReason: .failed(error: error))
        }
        
    }
    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        case rollbackFailed(error: Error)
        case setRemoteDescriptionFailed(error: Error)
        case failed(error: Error)
        var logType: OSLogType {
            return .fault
        }
    }
    
    
    private func videoMediaExistsIn(sessionDescription: String) throws -> Bool {
        let mediaStartVideo = try NSRegularExpression(pattern: "^m=video\\s+", options: .anchorsMatchLines)
        let lines = sessionDescription.split(whereSeparator: { $0.isNewline }).map({String($0)})
        for line in lines {
            let isFirstLineOfVideoSection = mediaStartVideo.numberOfMatches(in: line, options: [], range: NSRange(location: 0, length: line.count)) > 0
            if isFirstLineOfVideoSection {
                return true
            }
        }
        return false
    }
    
    
}
