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



final class CreatePeerConnectionOperation: AsyncOperationWithSpecificReasonForCancel<CreatePeerConnectionOperation.ReasonForCancel> {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "CreatePeerConnectionOperation")

    static let labelForDataChannel = "data0"
    
    private let turnCredentials: TurnCredentials
    private let gatheringPolicy: OlvidCallGatheringPolicy
    private let obvPeerConnectionDelegate: ObvPeerConnectionDelegate
    private let obvDataChannelDelegate: ObvDataChannelDelegate
    private let isAudioTrackEnabled: Bool
    
    // If this operation finishes without cancelling, this is set
    private(set) var peerConnection: ObvPeerConnection?

    init(turnCredentials: TurnCredentials, gatheringPolicy: OlvidCallGatheringPolicy, isAudioTrackEnabled: Bool, obvPeerConnectionDelegate: ObvPeerConnectionDelegate, obvDataChannelDelegate: ObvDataChannelDelegate) {
        self.turnCredentials = turnCredentials
        self.gatheringPolicy = gatheringPolicy
        self.obvPeerConnectionDelegate = obvPeerConnectionDelegate
        self.obvDataChannelDelegate = obvDataChannelDelegate
        self.isAudioTrackEnabled = isAudioTrackEnabled
    }
    
    
    override func main() async {
        
        os_log("☎️ [WebRTCOperation][CreatePeerConnectionOperation] Start", log: Self.log, type: .info)
        defer { os_log("☎️ [WebRTCOperation][CreatePeerConnectionOperation] Finish", log: Self.log, type: .info) }

        let rtcConfiguration = Self.createRTCConfiguration(turnCredentials: turnCredentials, gatheringPolicy: gatheringPolicy)
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        os_log("☎️ Create Peer Connection with %{public}@ policy", log: Self.log, type: .info, gatheringPolicy.localizedDescription)

        do {
            peerConnection = try await ObvPeerConnection(with: rtcConfiguration, constraints: constraints, delegate: obvPeerConnectionDelegate)
        } catch {
            return cancel(withReason: .peerConnectionCreationFailed)
        }
        
        guard let peerConnection else {
            assertionFailure()
            return cancel(withReason: .peerConnectionCreationFailed)
        }

        os_log("☎️ Add Olvid audio tracks", log: Self.log, type: .info)
        do {
            try await peerConnection.addAudioTrack(isEnabled: isAudioTrackEnabled)
        } catch {
            assertionFailure()
            return cancel(withReason: .audiotrackCreationFailed)
        }
        
        os_log("☎️ Create Data Channel", log: Self.log, type: .info)
        do {
            try await peerConnection.addDataChannel(dataChannelDelegate: obvDataChannelDelegate)
        } catch {
            return cancel(withReason: .dataChannelCreationFailed)
        }
        
        return finish()
        
    }
    
    
    private static func createRTCConfiguration(turnCredentials: TurnCredentials, gatheringPolicy: OlvidCallGatheringPolicy) -> RTCConfiguration {
    
        // 2022-03-11, we used to use the servers indicated in the turn credentials.
        // We do not do that anymore and use the (user) preferred servers.
        let iceServer = WebRTC.RTCIceServer(urlStrings: ObvMessengerConstants.ICEServerURLs.preferred,
                                            username: turnCredentials.turnUserName,
                                            credential: turnCredentials.turnPassword,
                                            tlsCertPolicy: .insecureNoCheck)

        let rtcConfiguration = RTCConfiguration()
        rtcConfiguration.iceServers = [iceServer]
        rtcConfiguration.iceTransportPolicy = .relay
        rtcConfiguration.sdpSemantics = .unifiedPlan
        rtcConfiguration.continualGatheringPolicy = gatheringPolicy.rtcPolicy
        
        return rtcConfiguration
        
    }

    
    enum ReasonForCancel: LocalizedErrorWithLogType {
        
        case peerConnectionCreationFailed
        case dataChannelCreationFailed
        case audiotrackCreationFailed
        
        var logType: OSLogType {
            return .fault
        }
    }
    
}
