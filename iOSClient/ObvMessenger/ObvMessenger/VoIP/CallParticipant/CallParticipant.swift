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
  

import UIKit
import ObvTypes
import ObvEngine
import ObvUICoreData


protocol CallParticipant: AnyObject {

    var uuid: UUID { get }
    var role: Role { get }
    func getPeerState() async -> PeerState
    func getContactIsMuted() async -> Bool
    
    var userId: OlvidUserId { get }
    var info: ParticipantInfo? { get }
    var ownedIdentity: ObvCryptoId { get }
    var remoteCryptoId: ObvCryptoId { get }
    var gatheringPolicy: GatheringPolicy? { get async }

    /// Use to be sent to others participants, we do not want to send the displayName that can include custom name
    var fullDisplayName: String { get }
    var displayName: String { get }
    var photoURL: URL? { get }
    var identityColors: (background: UIColor, text: UIColor)? { get }
    func setTurnCredentials(to turnCredentials: TurnCredentials) async

    func setPeerState(to state: PeerState) async throws

    func localUserAcceptedIncomingCallFromThisCallParticipant() async throws
    func setTurnCredentialsAndCreateUnderlyingPeerConnection(turnCredentials: TurnCredentials) async throws

    func updateRecipient(newParticipantOfferMessage: NewParticipantOfferMessageJSON, turnCredentials: TurnCredentials) async throws

    func restartIceIfAppropriate() async throws
    func closeConnection() async throws

    func sendUpdateParticipantsMessageJSON(callParticipants: [CallParticipant]) async throws
    func sendDataChannelMessage(_ message: WebRTCDataChannelMessageJSON) async throws

    var isMuted: Bool { get async }
    func mute() async
    func unmute() async

    func processIceCandidatesJSON(message: IceCandidateJSON) async throws
    func processRemoveIceCandidatesMessageJSON(message: RemoveIceCandidatesMessageJSON) async
}


// MARK: - Role

enum Role {
    case none
    case caller
    case recipient
}


// MARK: - PeerState

enum PeerState: Hashable, CustomDebugStringConvertible {
    case initial
    // States for the caller only (during this time, the recipient stays in the initial state)
    case startCallMessageSent
    case ringing
    case busy
    case callRejected
    // States common to the caller and the recipient
    case connectingToPeer
    case connected
    case reconnecting
    case hangedUp
    case kicked
    case failed

    var debugDescription: String {
        switch self {
        case .initial: return "initial"
        case .startCallMessageSent: return "startCallMessageSent"
        case .busy: return "busy"
        case .reconnecting: return "reconnecting"
        case .ringing: return "ringing"
        case .callRejected: return "callRejected"
        case .connectingToPeer: return "connectingToPeer"
        case .connected: return "connected"
        case .hangedUp: return "hangedUp"
        case .kicked: return "kicked"
        case .failed: return "failed"
        }
    }

    var isFinalState: Bool {
        switch self {
        case .callRejected, .hangedUp, .kicked, .failed: return true
        case .initial, .startCallMessageSent, .ringing, .busy, .connectingToPeer, .connected, .reconnecting: return false
        }
    }

    var localizedString: String {
        switch self {
        case .initial: return NSLocalizedString("CALL_STATE_NEW", comment: "")
        case .startCallMessageSent: return NSLocalizedString("CALL_STATE_INCOMING_CALL_MESSAGE_WAS_POSTED", comment: "")
        case .ringing: return NSLocalizedString("CALL_STATE_RINGING", comment: "")
        case .busy: return NSLocalizedString("CALL_STATE_BUSY", comment: "")
        case .callRejected: return NSLocalizedString("CALL_STATE_CALL_REJECTED", comment: "")
        case .connectingToPeer: return NSLocalizedString("CALL_STATE_CONNECTING_TO_PEER", comment: "")
        case .connected: return NSLocalizedString("SECURE_CALL_IN_PROGRESS", comment: "")
        case .reconnecting: return NSLocalizedString("CALL_STATE_RECONNECTING", comment: "")
        case .hangedUp: return NSLocalizedString("CALL_STATE_HANGED_UP", comment: "")
        case .kicked: return NSLocalizedString("CALL_STATE_KICKED", comment: "")
        case .failed: return NSLocalizedString("FAILED", comment: "")
        }
    }

}


// MARK: - TurnCredentials and extension

struct TurnCredentials {
    let turnUserName: String
    let turnPassword: String
    let turnServers: [String]?
}


extension ObvTurnCredentials {
    
    var turnCredentialsForCaller: TurnCredentials {
        TurnCredentials(turnUserName: callerUsername,
                        turnPassword: callerPassword,
                        turnServers: turnServersURL)
    }
    
    var turnCredentialsForRecipient: TurnCredentials {
        TurnCredentials(turnUserName: recipientUsername,
                        turnPassword: recipientPassword,
                        turnServers: turnServersURL)
    }

}

extension StartCallMessageJSON {
    
    var turnCredentials: TurnCredentials {
        TurnCredentials(turnUserName: turnUserName,
                        turnPassword: turnPassword,
                        turnServers: turnServers)
    }
    
}


// MARK: - ParticipantInfo

struct ParticipantInfo {
    let contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>
    let isCaller: Bool
}


// MARK: - GatheringPolicy

enum GatheringPolicy: Int {
    case gatherOnce = 1
    case gatherContinually = 2

    var localizedDescription: String {
        switch self {
        case .gatherOnce: return "gatherOnce"
        case .gatherContinually: return "gatherContinually"
        }
    }
}
