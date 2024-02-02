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



final class HandleReceivedRestartSdpOperation: AsyncOperationWithSpecificReasonForCancel<HandleReceivedRestartSdpOperation.ReasonForCancel> {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "AddIceCandidateOperation")

    private let peerConnection: ObvPeerConnection
    private let sessionDescription: RTCSessionDescription
    private let receivedReconnectCounter: Int
    private let receivedPeerReconnectCounterToOverride: Int
    private let reconnectAnswerCounter: Int
    private let reconnectOfferCounter: Int
    private let shouldISendTheOfferToCallParticipant: Bool
    
    init(peerConnection: ObvPeerConnection, sessionDescription: RTCSessionDescription, receivedReconnectCounter: Int, receivedPeerReconnectCounterToOverride: Int, reconnectAnswerCounter: Int, reconnectOfferCounter: Int, shouldISendTheOfferToCallParticipant: Bool) {
        self.peerConnection = peerConnection
        self.sessionDescription = sessionDescription
        self.receivedReconnectCounter = receivedReconnectCounter
        self.receivedPeerReconnectCounterToOverride = receivedPeerReconnectCounterToOverride
        self.reconnectAnswerCounter = reconnectAnswerCounter
        self.reconnectOfferCounter = reconnectOfferCounter
        self.shouldISendTheOfferToCallParticipant = shouldISendTheOfferToCallParticipant
        self.newReconnectAnswerCounter = reconnectAnswerCounter // Will be modified in the main() method of this operation
    }
    
    
    private(set) var newReconnectAnswerCounter: Int?

    
    override func main() async {

        os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️ [WebRTCOperation][HandleReceivedRestartSdpOperation] Finish", log: Self.log, type: .info) }

        do {
            
            switch sessionDescription.type {
                
            case .offer:
                
                // If we receive an offer with a counter smaller than another offer we previously received, we can ignore it.
                guard receivedReconnectCounter >= reconnectAnswerCounter else {
                    os_log("☎️ Received restart offer with counter too low %{public}@ vs. %{public}@", log: Self.log, type: .info, String(receivedReconnectCounter), String(reconnectAnswerCounter))
                    return finish()
                }
                
                switch peerConnection.signalingState {
                case .haveRemoteOffer:
                    os_log("☎️ Received restart offer while already having one --> rollback", log: Self.log, type: .info)
                    try await peerConnection.rollback()
                    
                case .haveLocalOffer:
                    // We already sent an offer.
                    // If we are the offer sender, do nothing, otherwise rollback and process the new offer
                    if shouldISendTheOfferToCallParticipant {
                        if receivedPeerReconnectCounterToOverride == reconnectOfferCounter {
                            os_log("☎️ Received restart offer while already having created an offer. It specifies to override my current offer --> rollback", log: Self.log, type: .info)
                            try await peerConnection.rollback()
                        } else {
                            os_log("☎️ Received restart offer while already having created an offer. I am the offerer --> ignore this new offer", log: Self.log, type: .info)
                            return finish()
                        }
                    } else {
                        os_log("☎️ Received restart offer while already having created an offer. I am not the offerer --> rollback", log: Self.log, type: .info)
                        try await peerConnection.rollback()
                    }
                    
                default:
                    break
                }
                
                newReconnectAnswerCounter = receivedReconnectCounter
                
                os_log("☎️ Setting remote description", log: Self.log, type: .info)
                try await peerConnection.setRemoteDescription(sessionDescription)
                
                await peerConnection.restartIce()

            case .answer:
                
                guard receivedReconnectCounter == reconnectOfferCounter else {
                    os_log("☎️ Received restart answer with bad counter %{public}@ vs. %{public}@", log: Self.log, type: .info, String(receivedReconnectCounter), String(reconnectOfferCounter))
                    return finish()
                }

                guard peerConnection.signalingState == .haveLocalOffer else {
                    os_log("☎️ Received restart answer while not in the haveLocalOffer state --> ignore this answer", log: Self.log, type: .info)
                    return finish()
                }

                os_log("☎️ Applying received restart answer", log: Self.log, type: .info)
                os_log("☎️ Setting remote description", log: Self.log, type: .info)
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
    
}
