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
import ObvEngine
import ObvTypes


// MARK: - GenericCall protocol

protocol GenericCall: AnyObject {
    
    var direction: CallDirection { get }
    var uuid: UUID { get }
    var usesCallKit: Bool { get }

    func getCallParticipants() async -> [CallParticipant]

    var state: CallState { get async }
    func getStateDates() async -> [CallState: Date]

    var isMuted: Bool { get async }
    
    func userRequestedToToggleAudio() async
    func userRequestedToEndCall() // Called from the Olvid UI when the user taps the end call button
    func userRequestedToAnswerCall() async // Throws if called on anything else than an incoming call

    func userDidAnsweredIncomingCall() async -> Bool // Only makes sense for an incoming call

    var initialParticipantCount: Int { get }

}


// MARK: - Call State

enum CallState: Hashable, CustomDebugStringConvertible {
    case initial
    case userAnsweredIncomingCall
    case gettingTurnCredentials // Only for outgoing calls
    case initializingCall
    case ringing
    case callInProgress

    case hangedUp
    case kicked
    case callRejected

    case permissionDeniedByServer
    case unanswered
    case callInitiationNotSupported
    case failed

    var debugDescription: String {
        switch self {
        case .kicked: return "kicked"
        case .userAnsweredIncomingCall: return "userAnsweredIncomingCall"
        case .gettingTurnCredentials: return "gettingTurnCredentials"
        case .initializingCall: return "initializingCall"
        case .ringing: return "ringing"
        case .initial: return "initial"
        case .callRejected: return "callRejected"
        case .callInProgress: return "callInProgress"
        case .hangedUp: return "hangedUp"
        case .permissionDeniedByServer: return "permissionDeniedByServer"
        case .unanswered: return "unanswered"
        case .callInitiationNotSupported: return "callInitiationNotSupported"
        case .failed: return "failed"
        }
    }

    var isFinalState: Bool {
        switch self {
        case .callRejected, .hangedUp, .unanswered, .callInitiationNotSupported, .kicked, .permissionDeniedByServer, .failed: return true
        case .gettingTurnCredentials, .userAnsweredIncomingCall, .initializingCall, .ringing, .initial, .callInProgress: return false
        }
    }

    var localizedString: String {
        switch self {
        case .initial: return NSLocalizedString("CALL_STATE_NEW", comment: "")
        case .gettingTurnCredentials: return NSLocalizedString("CALL_STATE_GETTING_TURN_CREDENTIALS", comment: "")
        case .kicked: return NSLocalizedString("CALL_STATE_KICKED", comment: "")
        case .userAnsweredIncomingCall, .initializingCall: return NSLocalizedString("CALL_STATE_INITIALIZING_CALL", comment: "")
        case .ringing: return NSLocalizedString("CALL_STATE_RINGING", comment: "")
        case .callRejected: return NSLocalizedString("CALL_STATE_CALL_REJECTED", comment: "")
        case .callInProgress: return NSLocalizedString("SECURE_CALL_IN_PROGRESS", comment: "")
        case .hangedUp: return NSLocalizedString("CALL_STATE_HANGED_UP", comment: "")
        case .permissionDeniedByServer: return NSLocalizedString("CALL_STATE_PERMISSION_DENIED_BY_SERVER", comment: "")
        case .unanswered: return NSLocalizedString("UNANSWERED", comment: "")
        case .callInitiationNotSupported: return NSLocalizedString("CALL_INITIALISATION_NOT_SUPPORTED", comment: "")
        case .failed: return NSLocalizedString("CALL_FAILED", comment: "")
        }
    }
}


enum CallDirection {
    case incoming
    case outgoing
}
