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
import ObvEngine
import ObvUICoreData

enum CallReport {
    case missedIncomingCall(caller: OlvidCallParticipantInfo?,  participantCount: Int?)
    case filteredIncomingCall(caller: OlvidCallParticipantInfo?,  participantCount: Int?)
    case rejectedIncomingCall(caller: OlvidCallParticipantInfo?, participantCount: Int?)
    case rejectedIncomingCallBecauseOfDeniedRecordPermission(caller: OlvidCallParticipantInfo?, participantCount: Int?)
    case rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse(caller: OlvidCallParticipantInfo)
    case acceptedIncomingCall(caller: OlvidCallParticipantInfo?)
    case newParticipantInIncomingCall(_: OlvidCallParticipantInfo?)
    case answeredOrRejectedOnOtherDevice(caller: OlvidCallParticipantInfo?, answered: Bool)

    case acceptedOutgoingCall(from: OlvidCallParticipantInfo?)
    case rejectedOutgoingCall(from: OlvidCallParticipantInfo?)
    case busyOutgoingCall(from: OlvidCallParticipantInfo?)
    case unansweredOutgoingCall(with: [OlvidCallParticipantInfo?])
    case uncompletedOutgoingCall(with: [OlvidCallParticipantInfo?])
    case newParticipantInOutgoingCall(_: OlvidCallParticipantInfo?)
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
        case .answeredOrRejectedOnOtherDevice(caller: _, answered: let answered):
            return answered ? .answeredOnOtherDevice : .rejectedOnOtherDevice
        case .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse:
            return .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse
        }
    }

    var participantInfos: [OlvidCallParticipantInfo?] {
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
        case .answeredOrRejectedOnOtherDevice(caller: let caller, answered: _):
            return [caller]
        case .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse(caller: let caller):
            return [caller]
        }

    }

    var isIncoming: Bool {
        switch self {
        case .missedIncomingCall, .filteredIncomingCall, .rejectedIncomingCall, .acceptedIncomingCall, .newParticipantInIncomingCall, .rejectedIncomingCallBecauseOfDeniedRecordPermission, .answeredOrRejectedOnOtherDevice, .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse:
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
        case .answeredOrRejectedOnOtherDevice: return "answeredOrRejectedOnOtherDevice"
        case .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse: return "rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse"
        }
    }

}
