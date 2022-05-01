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
import AVKit

protocol ObvCallManager {

    var isCallKit: Bool { get }

    func requestEndCallAction(call: Call) async throws
    func requestAnswerCallAction(incomingCall: Call) async throws
    func requestMuteCallAction(call: Call) async throws
    func requestUnmuteCallAction(call: Call) async throws
    func requestStartCallAction(call: Call, contactIdentifier: String, handleValue: String) async throws
}

protocol ObvCallUpdate {
    var remoteHandle_: ObvHandle? { get set }
    var localizedCallerName: String? { get set }
    var supportsHolding: Bool { get set  }
    var supportsGrouping: Bool { get set  }
    var supportsUngrouping: Bool { get set  }
    var supportsDTMF: Bool { get set  }
    var hasVideo: Bool { get set  }
}
struct ObvCallUpdateImpl: ObvCallUpdate {
    var remoteHandle_: ObvHandle?
    var localizedCallerName: String?
    var supportsHolding: Bool = false
    var supportsGrouping: Bool = false
    var supportsUngrouping: Bool = false
    var supportsDTMF: Bool = false
    var hasVideo: Bool = false
}


enum ObvCallEndedReason {
    case failed
    case remoteEnded
    case unanswered
    case answeredElsewhere
    case declinedElsewhere
}

protocol ObvProviderConfiguration {
    var localizedName: String? { get }
    var ringtoneSound: String? { get set }
    var iconTemplateImageData: Data? { get set }
    var maximumCallGroups: Int { get set }
    var maximumCallsPerCallGroup: Int { get set }
    var includesCallsInRecents: Bool { get set }
    var supportsVideo: Bool { get set }
    var supportedHandleTypes_: Set<ObvHandleType> { get set }
}

struct ObvProviderConfigurationImpl: ObvProviderConfiguration {
    var localizedName: String?
    var ringtoneSound: String?
    var iconTemplateImageData: Data?
    var maximumCallGroups: Int = 2
    var maximumCallsPerCallGroup: Int = 5
    var includesCallsInRecents: Bool = true
    var supportsVideo: Bool = false
    var supportedHandleTypes_: Set<ObvHandleType> = Set()
}

enum ObvErrorCodeIncomingCallError: Int {
    case unknown = 0
    case unentitled = 1
    case callUUIDAlreadyExists = 2
    case filteredByDoNotDisturb = 3
    case filteredByBlockList = 4

    case maximumCallGroupsReached = 5 // For NCX
}

protocol ObvProvider: AnyObject {

    var isCallKit: Bool { get }

    func setDelegate(_ delegate: ObvProviderDelegate?, queue: DispatchQueue?)

    /// Report a cancelled incoming call.
    func reportNewCancelledIncomingCall()

    /// Report a new incoming call to the system.
    /// If completion is invoked with a non-nil `error`, the incoming call has been disallowed by the system and will not be displayed, so the provider should not proceed with the call.
    /// Completion block will be called on delegate queue, if specified, otherwise on a private serial queue.
    func reportNewIncomingCall(with UUID: UUID, update: ObvCallUpdate, completion: @escaping (Result<Void,Error>) -> Void)

    /// Report an update to call information.
    func reportCall(with UUID: UUID, updated update: ObvCallUpdate)

    /// Report that a call ended. A nil value for `dateEnded` results in the ended date being set to now.
    func reportCall(with UUID: UUID, endedAt dateEnded: Date?, reason endedReason: ObvCallEndedReason)

    /// Report that an outgoing call started connecting. A nil value for `dateStartedConnecting` results in the started connecting date being set to now.
    func reportOutgoingCall(with UUID: UUID, startedConnectingAt dateStartedConnecting: Date?)

    /// Report that an outgoing call connected. A nil value for `dateConnected` results in the connected date being set to now.
    func reportOutgoingCall(with UUID: UUID, connectedAt dateConnected: Date?)

    var configuration_: ObvProviderConfiguration { get set }

    /// Invalidate the receiver. All existing calls will be marked as ended in failure. The provider must be invalidated before it is deallocated.
    func invalidate()
}

enum ObvHandleType: Int {
    case generic = 1
    case phoneNumber = 2
    case emailAddress = 3
}

protocol ObvHandle {
    var type_: ObvHandleType { get }
    var value: String { get }
}
struct ObvHandleImpl: ObvHandle {
    var type_: ObvHandleType
    var value: String
}
protocol ObvAction {

    var debugDescription: String { get }

    var isComplete: Bool { get }

    /// Report successful execution of the receiver.
    func fulfill()

    /// Report failed execution of the receiver.
    func fail()
}

enum ObvActionKind {
    case start
    case answer
    case end
    case held
    case mute
    case playDTMF
}

protocol ObvCallAction: ObvAction {
    var callUUID: UUID { get }
}

protocol ObvStartCallAction: ObvCallAction {
    var handle_: ObvHandle { get }
    var contactIdentifier: String? { get }
    var isVideo: Bool { get }

    func fulfill(withDateStarted: Date)
}

protocol ObvAnswerCallAction: ObvCallAction {
    func fulfill(withDateConnected: Date)
}

protocol ObvEndCallAction: ObvCallAction {
    func fulfill(withDateEnded: Date)
}

protocol ObvSetHeldCallAction: ObvCallAction {
    var isOnHold: Bool { get }
}

protocol ObvSetMutedCallAction: ObvCallAction {
    var isMuted: Bool { get }
}

enum ObvPlayDTMFCallActionType: Int {
    case singleTone = 1
    case softPause = 2
    case hardPause = 3
    case unknown = 100
}

protocol ObvPlayDTMFCallAction: ObvCallAction {
    var digits: String { get }
    var type_: ObvPlayDTMFCallActionType { get }
}

protocol ObvProviderDelegate: AnyObject {
    func providerDidBegin() async
    func providerDidReset() async
    func provider(perform action: ObvStartCallAction) async
    func provider(perform action: ObvAnswerCallAction) async
    func provider(perform action: ObvEndCallAction) async
    func provider(perform action: ObvSetHeldCallAction) async
    func provider(perform action: ObvSetMutedCallAction) async
    func provider(perform action: ObvPlayDTMFCallAction) async
    func provider(timedOutPerforming action: ObvAction) async
    func provider(didActivate audioSession: AVAudioSession) async
    func provider(didDeactivate audioSession: AVAudioSession) async
}

protocol ObvCall: AnyObject {
    var uuid: UUID { get }
    var isOutgoing: Bool { get }
    var isOnHold: Bool { get }
    var hasConnected: Bool { get }
    var hasEnded: Bool { get }
}

protocol ObvCallObserverDelegate: AnyObject {
    func callObserver(callChanged call: ObvCall)
}
protocol ObvCallObserver {
    /// Retrieve the current call list, blocking on initial state retrieval if necessary
    var calls_: [ObvCall] { get }
    /// Set delegate and optional queue for delegate callbacks to be performed on.
    /// A nil queue implies that delegate callbacks should happen on the main queue. The delegate is stored weakly
    func setDelegate(_ delegate: ObvCallObserverDelegate?, queue: DispatchQueue?)
}
