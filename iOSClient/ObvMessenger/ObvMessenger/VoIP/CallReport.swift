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
import ObvUICoreData

enum CallReport {
    case missedIncomingCall(caller: ParticipantInfo?,  participantCount: Int?)
    case filteredIncomingCall(caller: ParticipantInfo?,  participantCount: Int?)
    case rejectedIncomingCall(caller: ParticipantInfo?, participantCount: Int?)
    case rejectedIncomingCallBecauseOfDeniedRecordPermission(caller: ParticipantInfo?, participantCount: Int?)
    case acceptedIncomingCall(caller: ParticipantInfo?)
    case newParticipantInIncomingCall(_: ParticipantInfo?)

    case acceptedOutgoingCall(from: ParticipantInfo?)
    case rejectedOutgoingCall(from: ParticipantInfo?)
    case busyOutgoingCall(from: ParticipantInfo?)
    case unansweredOutgoingCall(with: [ParticipantInfo?])
    case uncompletedOutgoingCall(with: [ParticipantInfo?])
    case newParticipantInOutgoingCall(_: ParticipantInfo?)
}

extension CallReport: CustomStringConvertible {

    var toCallReportKind: CallReportKind {
        switch self {
        case .missedIncomingCall: return .missedIncomingCall
        case .filteredIncomingCall: return .filteredIncomingCall
        case .rejectedIncomingCall: return .rejectedIncomingCall
        case .acceptedIncomingCall: return .acceptedIncomingCall
        case .acceptedOutgoingCall: return .acceptedOutgoingCall
        case .rejectedOutgoingCall: return .rejectedOutgoingCall
        case .rejectedIncomingCallBecauseOfDeniedRecordPermission: return .rejectedIncomingCallBecauseOfDeniedRecordPermission
        case .busyOutgoingCall: return .busyOutgoingCall
        case .unansweredOutgoingCall: return .unansweredOutgoingCall
        case .uncompletedOutgoingCall: return .uncompletedOutgoingCall
        case .newParticipantInIncomingCall: return .newParticipantInIncomingCall
        case .newParticipantInOutgoingCall: return .newParticipantInOutgoingCall
        }
    }

    var participantInfos: [ParticipantInfo?] {
        switch self {
        case .missedIncomingCall(caller: let caller, _):
            return [caller]
        case .filteredIncomingCall(caller: let caller, _):
            return [caller]
        case .rejectedIncomingCall(caller: let caller, _):
            return [caller]
        case .rejectedIncomingCallBecauseOfDeniedRecordPermission(caller: let caller, _):
            return [caller]
        case .acceptedIncomingCall(caller: let caller):
            return [caller]
        case .acceptedOutgoingCall(from: let from):
            return [from]
        case .rejectedOutgoingCall(from: let from):
            return [from]
        case .busyOutgoingCall(from: let from):
            return [from]
        case .unansweredOutgoingCall(with: let with):
            return with
        case .uncompletedOutgoingCall(with: let with):
            return with
        case .newParticipantInIncomingCall(let participant):
            return [participant]
        case .newParticipantInOutgoingCall(let participant):
            return [participant]
        }

    }

    var isIncoming: Bool {
        switch self {
        case .missedIncomingCall, .filteredIncomingCall, .rejectedIncomingCall, .acceptedIncomingCall, .newParticipantInIncomingCall, .rejectedIncomingCallBecauseOfDeniedRecordPermission:
            return true
        case .acceptedOutgoingCall, .rejectedOutgoingCall, .busyOutgoingCall, .unansweredOutgoingCall,  .uncompletedOutgoingCall, .newParticipantInOutgoingCall:
            return false
        }
    }

    var description: String {
        switch self {
        case .missedIncomingCall: return "missedIncomingCall"
        case .filteredIncomingCall: return "filteredIncomingCall"
        case .acceptedOutgoingCall: return "acceptedOutgoingCall"
        case .acceptedIncomingCall: return "acceptedIncomingCall"
        case .rejectedOutgoingCall: return "rejectedOutgoingCall"
        case .rejectedIncomingCall: return "rejectedIncomingCall"
        case .rejectedIncomingCallBecauseOfDeniedRecordPermission: return "rejectedIncomingCallBecauseOfDeniedRecordPermission"
        case .busyOutgoingCall: return "busyOutgoingCall"
        case .unansweredOutgoingCall: return "unansweredOutgoingCall"
        case .uncompletedOutgoingCall: return "uncompletedOutgoingCall"
        case .newParticipantInIncomingCall: return "newParticipantInIncomingCall"
        case .newParticipantInOutgoingCall: return "newParticipantInOutgoingCall"
        }
    }

}
