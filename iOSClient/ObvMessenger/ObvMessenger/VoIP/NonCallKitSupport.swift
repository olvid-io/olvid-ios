/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import AudioToolbox

class NCXCallManager: ObvCallManager {

    var isCallKit: Bool { false }
    private var callController = NCXCallController.instance

    func requestEndCallAction(call: Call, completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) {
        let endCallAction = NCXEndCallAction(call: call.uuid)
        callController.request(action: endCallAction, completion: completion)
    }

    func requestAnswerCallAction(call: Call, completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) {
        guard let incomingCall = call as? IncomingCall else { assertionFailure(); return }
        guard !incomingCall.userAnsweredIncomingCall else { return }
        let answerCallAction = NCXAnswerCallAction(call: call.uuid)
        callController.request(action: answerCallAction, completion: completion)
    }

    func requestMuteCallAction(call: Call, completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) {
        let muteCallAction = NCXSetMutedCallAction(call: call.uuid, muted: true)
        callController.request(action: muteCallAction, completion: completion)
    }

    func requestUnmuteCallAction(call: Call, completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) {
        let umuteCallAction = NCXSetMutedCallAction(call: call.uuid, muted: false)
        callController.request(action: umuteCallAction, completion: completion)
    }

    func requestStartCallAction(call: Call, contactIdentifier: String, handleValue: String, completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) {
        let handle = ObvHandleImpl(type_: .generic, value: handleValue)

        let startCallAction = NCXStartCallAction(call: call.uuid, handle: handle)
        startCallAction.contactIdentifier = contactIdentifier
        callController.request(action: startCallAction, completion: completion)
    }
}

class NCXAction: ObvAction {
    var debugDescription: String { String(describing: Self.self) }
    var isComplete: Bool = false
    func fulfill() { }

    func fail() { }
}

class NCXCallAction: NCXAction, ObvCallAction {
    var kind: ObvActionKind

    var callUUID: UUID
    init(call: UUID, kind: ObvActionKind) {
        self.kind = kind
        self.callUUID = call
    }
}

class NCXStartCallAction: NCXCallAction, ObvStartCallAction {
    var handle_: ObvHandle
    var contactIdentifier: String?
    var isVideo: Bool = false

    init(call: UUID, handle: ObvHandle) {
        self.handle_ = handle
        super.init(call: call, kind: .start)
    }
    func fulfill(withDateStarted: Date) { }
}

class NCXAnswerCallAction: NCXCallAction, ObvAnswerCallAction {
    init(call: UUID) {
        super.init(call: call, kind: .answer)
    }
    func fulfill(withDateConnected: Date) { }

}

class NCXEndCallAction: NCXCallAction, ObvEndCallAction {
    init(call: UUID) {
        super.init(call: call, kind: .end)
    }
    func fulfill(withDateEnded: Date) { }
}

class NCXSetHeldCallAction: NCXCallAction, ObvSetHeldCallAction {
    var isOnHold: Bool
    init(call: UUID, onHold: Bool) {
        self.isOnHold = onHold
        super.init(call: call, kind: .held)
    }
}

class NCXSetMutedCallAction: NCXCallAction, ObvSetMutedCallAction {
    var isMuted: Bool
    init(call: UUID, muted: Bool) {
        self.isMuted = muted
        super.init(call: call, kind: .mute)
    }
}
class NCXPlayDTMFCallAction: NCXCallAction, ObvPlayDTMFCallAction {
    var digits: String
    var type_: ObvPlayDTMFCallActionType
    init(call: UUID, digits: String, type_: ObvPlayDTMFCallActionType) {
        self.digits = digits
        self.type_ = type_
        super.init(call: call, kind: .playDTMF)
    }
}

class NCXCall: ObvCall {
    var uuid: UUID
    var isOutgoing: Bool
    var isOnHold: Bool = false
    var hasConnected: Bool = false
    var hasEnded: Bool = false

    init(uuid: UUID, isOutgoing: Bool) {
        self.uuid = uuid
        self.isOutgoing = isOutgoing
    }
}

class NCXCallController {

    private static var _instance: NCXCallController? = nil
    private init() { /* You shall not pass */ }
    static var instance: NCXCallController {
        Concurrency.sync(lock: "NCXCallController.instance") {
            if _instance == nil { _instance = NCXCallController() }
            return _instance!
        }
    }

    private var callObserver = NCXCallObserver.instance

    private var delegate: ObvProviderDelegate?
    private var delegateQueue: DispatchQueue?
    func setDelegate(_ delegate: ObvProviderDelegate?, queue: DispatchQueue?) {
        self.delegate = delegate
        self.delegateQueue = queue
    }

    private var configuration: ObvProviderConfiguration!
    fileprivate func setConfiguration(_ configuration: ObvProviderConfiguration) {
        self.configuration = configuration
    }

    fileprivate func request(action: NCXCallAction, completion: ((ObvErrorCodeRequestTransactionError?) -> Void)? = nil) {
        guard let delegate = self.delegate else {
            completion?(.unknownCallProvider)
            return
        }
        switch action.kind {
        case .start:
            if let action = action as? ObvStartCallAction {
                guard callObserver.calls_.first(where: { $0.uuid == action.callUUID }) == nil else {
                    completion?(.callUUIDAlreadyExists); return
                }
                guard callObserver.calls_.count < configuration.maximumCallGroups else {
                    completion?(.maximumCallGroupsReached); return
                }
                let block = { delegate.provider(perform: action) }
                delegateQueue?.async { block() } ?? block()
                completion?(nil)
            }
        case .answer:
            if let action = action as? ObvAnswerCallAction {
                guard callObserver.calls_.count <= configuration.maximumCallGroups else {
                    completion?(.maximumCallGroupsReached); return
                }
                let block = { delegate.provider(perform: action) }
                delegateQueue?.async { block() } ?? block()
                completion?(nil)

                if let call = self.callObserver.calls_.first(where: { $0.uuid == action.callUUID }) as? NCXCall {
                    if !call.hasConnected {
                        call.hasConnected = true
                        self.callObserver.callObserver(callChanged: call)
                    }
                }
            }
        case .end:
            if let action = action as? ObvEndCallAction {
                guard callObserver.calls_.first(where: { $0.uuid == action.callUUID }) != nil else {
                    completion?(.unknownCallUUID); return
                }
                let block = { delegate.provider(perform: action) }
                delegateQueue?.async { block() } ?? block()
                completion?(nil)

                if let call = self.callObserver.calls_.first(where: { $0.uuid == action.callUUID }) as? NCXCall {
                    if !call.hasEnded {
                        call.hasEnded = true
                        self.callObserver.callObserver(callChanged: call)
                    }
                }
            }
        case .held:
            if let action = action as? ObvSetHeldCallAction {
                guard callObserver.calls_.first(where: { $0.uuid == action.callUUID }) != nil else {
                    completion?(.unknownCallUUID); return
                }
                let block = { delegate.provider(perform: action) }
                delegateQueue?.async { block() } ?? block()
            }
        case .mute:
            if let action = action as? ObvSetMutedCallAction {
                guard callObserver.calls_.first(where: { $0.uuid == action.callUUID }) != nil else {
                    completion?(.unknownCallUUID); return
                }
                let block = { delegate.provider(perform: action) }
                delegateQueue?.async { block() } ?? block()
                completion?(nil)
            }
        case .playDTMF:
            if let action = action as? ObvPlayDTMFCallAction {
                guard callObserver.calls_.first(where: { $0.uuid == action.callUUID }) != nil else {
                    completion?(.unknownCallUUID); return
                }
                let block = { delegate.provider(perform: action) }
                delegateQueue?.async { block() } ?? block()
                completion?(nil)
            }
        }
    }

}

class NCXObvProvider: ObvProvider {

    private static var _instance: NCXObvProvider? = nil
    private init() { /* You shall not pass */ }
    static var instance: NCXObvProvider {
        Concurrency.sync(lock: "NCXObvProvider.instance") {
            if _instance == nil { _instance = NCXObvProvider() }
            return _instance!
        }
    }

    private var configuration: ObvProviderConfiguration!
    private var callObserver = NCXCallObserver.instance
    private var callController = NCXCallController.instance

    func setConfiguration(_ configuration: ObvProviderConfiguration) {
        self.configuration = configuration
        self.callController.setConfiguration(configuration)
    }

    var isCallKit: Bool { false }

    private var notificationTokens = [NSObjectProtocol]()

    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInteractive
        return queue
    }()

    func setDelegate(_ delegate: ObvProviderDelegate?, queue: DispatchQueue?) {
        callController.setDelegate(delegate, queue: queue)
    }

    private var startedConnectingDates: [UUID: Date] = [:]
    private var connectedDates: [UUID: Date] = [:]
    private var callUpdates: [UUID: ObvCallUpdate] = [:]

    func reportNewIncomingCall(with UUID: UUID, update: ObvCallUpdate, completion: @escaping (ObvErrorCodeIncomingCallError?) -> Void) {
        print("☎️ NCX reportNewIncomingCall with ", UUID)

        guard callObserver.calls_.first(where: { $0.uuid == UUID }) == nil else {
            print("☎️ NCX reportNewIncomingCall -> callUUIDAlreadyExists")
            completion(.callUUIDAlreadyExists)
            return
        }

        /// REMARK It is not like in CX but it simplify a lot of code to have this test here
        guard callObserver.calls_.count < configuration.maximumCallGroups else {
            print("☎️ NCX reportNewIncomingCall -> maximumCallGroupsReached")
            completion(.maximumCallGroupsReached)
            return
        }

        let call = NCXCall(uuid: UUID, isOutgoing: false)
        callObserver.calls_.append(call)
        print("☎️ NCX reportNewIncomingCall -> OK!")
        completion(nil)

        callObserver.callObserver(callChanged: call)

        // REMARK ? We should deal with do not disturb
    }

    func reportCall(with UUID: UUID, updated update: ObvCallUpdate) {
        print("☎️ NCX reportCall with ", update, UUID)

        if var current = callUpdates[UUID] {
            current.remoteHandle_ = update.remoteHandle_
            current.localizedCallerName = update.localizedCallerName
            current.supportsHolding = update.supportsHolding
            current.supportsGrouping = update.supportsGrouping
            current.supportsUngrouping = update.supportsUngrouping
            current.supportsDTMF = update.supportsDTMF
            current.hasVideo = update.hasVideo
        } else {
            callUpdates[UUID] = update
        }
    }

    func reportCall(with UUID: UUID, endedAt dateEnded: Date?, reason endedReason: ObvCallEndedReason) {
        print("☎️ NCX reportCall", endedReason, UUID)

        guard let call = callObserver.calls_.first(where: { $0.uuid == UUID }) as? NCXCall else {
            print("☎️ NCX reportCall (1): the given call does not exists ", UUID); return
        }
        if call.isOutgoing {
            guard let dateStartedConnecting = startedConnectingDates.removeValue(forKey: UUID) else {
                print("☎️ NCX reportCall (2): the given call does not exists ", UUID); assertionFailure(); return
            }
            if let dateConnected = connectedDates.removeValue(forKey: UUID) {
                guard dateStartedConnecting < dateConnected else {
                    print("☎️ NCX reportCall (4): dates are incoherents ", UUID); assertionFailure(); return
                }
            }
        }
        callObserver.calls_.removeAll(where: { $0.uuid == UUID })

        if !call.hasEnded {
            call.hasEnded = true
            callObserver.callObserver(callChanged: call)
        }
    }

    func reportOutgoingCall(with UUID: UUID, startedConnectingAt dateStartedConnecting: Date?) {
        print("☎️ NCX reportOutgoingCall startedConnectingAt")
        guard callObserver.calls_.first(where: { $0.uuid == UUID }) == nil else {
            print("☎️ NCX reportOutgoingCall startedConnectingAt -> callUUIDAlreadyExists"); return
        }
        let call = NCXCall(uuid: UUID, isOutgoing: true)
        callObserver.calls_.append(call)
        startedConnectingDates[UUID] = dateStartedConnecting ?? Date()

        callObserver.callObserver(callChanged: call)
    }

    func reportOutgoingCall(with UUID: UUID, connectedAt dateConnected: Date?) {
        print("☎️ NCX reportOutgoingCall connectedAt")
        guard let call = callObserver.calls_.first(where: { $0.uuid == UUID }) as? NCXCall else {
            print("☎️ NCX reportOutgoingCall connectedAt: the given call does not exists ", UUID); assertionFailure(); return
        }

        assert(startedConnectingDates.keys.contains(UUID))
        connectedDates[UUID] = dateConnected ?? Date()

        call.hasConnected = true
        callObserver.callObserver(callChanged: call)
    }

    var configuration_: ObvProviderConfiguration {
        get { configuration }
        set { configuration = newValue }
    }

    func invalidate() {
        print("☎️ NCX invalidate")
        for call in callObserver.calls_ {
            reportCall(with: call.uuid, endedAt: Date(), reason: .failed)
        }
        callObserver.calls_.removeAll()
        startedConnectingDates.removeAll()
        connectedDates.removeAll()
        callUpdates.removeAll()
    }

    func reportNewCancelledIncomingCall(completionHandler: @escaping () -> Void) {
        /// Nothing to call we do not have to present something to the user in case of error
    }

}

class NCXCallObserver: ObvCallObserver {

    private static var _instance: NCXCallObserver? = nil

    private init() { /* You shall not pass */ }

    static var instance: NCXCallObserver {
        Concurrency.sync(lock: "NCXCallObserver.instance") {
            if _instance == nil { _instance = NCXCallObserver() }
            return _instance!
        }
    }

    var calls_: [ObvCall] = []

    private weak var delegate: ObvCallObserverDelegate?
    private var queue: DispatchQueue?

    func setDelegate(_ delegate: ObvCallObserverDelegate?, queue: DispatchQueue?) {
        self.delegate = delegate
        self.queue = queue
    }

    func callObserver(callChanged call: ObvCall) {
        queue?.async { self.delegate?.callObserver(callChanged: call) } ?? self.delegate?.callObserver(callChanged: call)
    }

}

/// NCXCallObserverDelegate Exemple
class NCXCallObserverTest: NSObject, ObvCallObserverDelegate {

    private let callObserver: ObvCallObserver = NCXCallObserver.instance

    override init() {
        super.init()
        callObserver.setDelegate(self, queue: DispatchQueue(label: "Queue for observing call"))
    }

    func callObserver(callChanged call: ObvCall) {
        print("☎️ NCX Observe call changed uuid=", call.uuid, " isOutgoing=", call.isOutgoing, " isOnHold=", call.isOnHold, " hasConnected=", call.hasConnected, " hasEnded=", call.hasEnded)
        print("☎️ NCX Number of ObvCall=", callObserver.calls_.count)
    }
}
