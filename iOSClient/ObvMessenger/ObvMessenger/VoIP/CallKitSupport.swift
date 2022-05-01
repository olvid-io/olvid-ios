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
import os.log
import CallKit
import AVKit

class CXCallManager: ObvCallManager {

    var isCallKit: Bool { true }

    private let callController = CXCallController()
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: CXCallManager.self))

    func requestEndCallAction(call: Call) async throws {
        let endCallAction = CXEndCallAction(call: call.uuid)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)
        try await requestTransaction(transaction)
    }

    func requestAnswerCallAction(incomingCall: Call) async throws {
        let answerCallAction = CXAnswerCallAction(call: incomingCall.uuid)
        let transaction = CXTransaction()
        transaction.addAction(answerCallAction)
        try await requestTransaction(transaction)
    }

    func requestMuteCallAction(call: Call) async throws {
        let muteCallAction = CXSetMutedCallAction(call: call.uuid, muted: true)
        let transaction = CXTransaction()
        transaction.addAction(muteCallAction)
        try await requestTransaction(transaction)
    }

    func requestUnmuteCallAction(call: Call) async throws {
        let muteCallAction = CXSetMutedCallAction(call: call.uuid, muted: false)
        let transaction = CXTransaction()
        transaction.addAction(muteCallAction)
        try await requestTransaction(transaction)
    }

    func requestStartCallAction(call: Call, contactIdentifier: String, handleValue: String) async throws {
        let handle = CXHandle(type: .generic, value: handleValue)

        let startCallAction = CXStartCallAction(call: call.uuid, handle: handle)
        startCallAction.contactIdentifier = contactIdentifier

        let transaction = CXTransaction()
        transaction.addAction(startCallAction)
        try await requestTransaction(transaction)
    }

    
    private func requestTransaction(_ transaction: CXTransaction) async throws {
        os_log("☎️ Requesting transaction with %{public}d action(s). The first is: %{public}@", log: log, type: .error, transaction.actions.count, transaction.actions.first ?? "nil")
        try await callController.request(transaction)
    }

}

extension ObvHandleType {
    var cxHandleType: CXHandle.HandleType { CXHandle.HandleType(rawValue: rawValue) ?? .generic }
}

extension CXHandle.HandleType {
    var obvHandleType: ObvHandleType { ObvHandleType(rawValue: rawValue) ?? .generic }
}


extension CXProviderConfiguration: ObvProviderConfiguration {
    var supportedHandleTypes_: Set<ObvHandleType> {
        get { Set(supportedHandleTypes.map { $0.obvHandleType }) }
        set { supportedHandleTypes = Set(newValue.map { $0.cxHandleType }) }
    }
}

extension ObvProviderConfiguration {
    var cxProviderConfiguration: CXProviderConfiguration {
        var configuration: CXProviderConfiguration
        if #available(iOS 14.0, *) {
            configuration = CXProviderConfiguration()
        } else {
            assert(localizedName != nil)
            configuration = CXProviderConfiguration(localizedName: localizedName ?? "CXProviderConfiguration")
        }
        configuration.ringtoneSound = ringtoneSound
        configuration.iconTemplateImageData = iconTemplateImageData
        configuration.maximumCallGroups = maximumCallGroups
        configuration.maximumCallsPerCallGroup = maximumCallsPerCallGroup
        configuration.includesCallsInRecents = includesCallsInRecents
        configuration.supportsVideo = supportsVideo
        configuration.supportedHandleTypes_ = supportedHandleTypes_
        return configuration
    }
}

extension ObvCallEndedReason {
    var cxReason: CXCallEndedReason {
        switch self {
        case .failed: return .failed
        case .remoteEnded: return .remoteEnded
        case .unanswered: return .unanswered
        case .answeredElsewhere: return .answeredElsewhere
        case .declinedElsewhere: return .declinedElsewhere
        }
    }

}

extension ObvErrorCodeRequestTransactionError {
    var cxError: CXErrorCodeRequestTransactionError {
        var code: CXErrorCodeRequestTransactionError.Code?
        switch self {
        case .unknown: code = .unknown
        case .unentitled: code = .unentitled
        case .unknownCallProvider: code = .unknownCallProvider
        case .emptyTransaction: code = .emptyTransaction
        case .unknownCallUUID: code = .unknownCallUUID
        case .callUUIDAlreadyExists: code = .callUUIDAlreadyExists
        case .invalidAction: code = .invalidAction
        case .maximumCallGroupsReached: code = .maximumCallGroupsReached
        }
        return CXErrorCodeRequestTransactionError(code ?? .unknown)
    }
}

extension CXErrorCodeRequestTransactionError {
    var obvError: ObvErrorCodeRequestTransactionError {
        switch self.code {
        case .unknown: return .unknown
        case .unentitled: return .unentitled
        case .unknownCallProvider: return .unknownCallProvider
        case .emptyTransaction: return .emptyTransaction
        case .unknownCallUUID: return .unknownCallUUID
        case .callUUIDAlreadyExists: return .callUUIDAlreadyExists
        case .invalidAction: return .invalidAction
        case .maximumCallGroupsReached: return .maximumCallGroupsReached
        @unknown default: assertionFailure(); return .unknown
        }
    }
}

extension CXErrorCodeIncomingCallError {
    var obvError: ObvErrorCodeIncomingCallError {
        switch self.code {
        case .unknown: return .unknown
        case .unentitled: return .unentitled
        case .callUUIDAlreadyExists: return .callUUIDAlreadyExists
        case .filteredByDoNotDisturb: return .filteredByDoNotDisturb
        case .filteredByBlockList: return .filteredByBlockList
        @unknown default: return .unknown
        }
    }
}

class CXObvProvider: ObvProvider {

    var isCallKit: Bool { true }

    private var provider: CXProvider

    init(configuration: ObvProviderConfiguration) {
        self.provider = CXProvider(configuration: configuration.cxProviderConfiguration)
    }

    /// Allows to keep a strong ref on delegate since setDelegate keeps a weak ref and CallKitProviderDelegate is a local variable
    private var delegate: CXProviderDelegate?

    func setDelegate(_ delegate: ObvProviderDelegate?, queue: DispatchQueue?) {
        self.delegate = CXObvProviderDelegate(delegate: delegate)
        self.provider.setDelegate(self.delegate, queue: queue)
    }

    func reportNewIncomingCall(with UUID: UUID, update: ObvCallUpdate, completion: @escaping (Result<Void,Error>) -> Void) {
        provider.reportNewIncomingCall(with: UUID, update: update.cxCallUpdate) { error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(()))
            }
        }
    }

    func reportCall(with UUID: UUID, updated update: ObvCallUpdate) {
        provider.reportCall(with: UUID, updated: update.cxCallUpdate)
    }

    func reportCall(with UUID: UUID, endedAt dateEnded: Date?, reason endedReason: ObvCallEndedReason) {
        provider.reportCall(with: UUID, endedAt: dateEnded, reason: endedReason.cxReason)
    }

    func reportOutgoingCall(with UUID: UUID, startedConnectingAt dateStartedConnecting: Date?) {
        provider.reportOutgoingCall(with: UUID, startedConnectingAt: dateStartedConnecting)
    }

    func reportOutgoingCall(with UUID: UUID, connectedAt dateConnected: Date?) {
        provider.reportOutgoingCall(with: UUID, connectedAt: dateConnected)
    }

    var configuration_: ObvProviderConfiguration {
        get { provider.configuration }
        set { provider.configuration = newValue.cxProviderConfiguration }
    }

    func invalidate() {
        provider.invalidate()
    }


    func reportNewCancelledIncomingCall() {
        let uuid = UUID()
        let update = ObvCallUpdateImpl(remoteHandle_: nil,
                                       localizedCallerName: "...",
                                       supportsHolding: false,
                                       supportsGrouping: false,
                                       supportsUngrouping: false,
                                       supportsDTMF: false,
                                       hasVideo: false)
        provider.reportNewIncomingCall(with: uuid, update: update.cxCallUpdate) { [weak self] _ in
            self?.endReportedIncomingCall(with: uuid, inSeconds: 2)
        }
    }
    
    
    func endReportedIncomingCall(with uuid: UUID, inSeconds: Int) {
        let callController = CXCallController()
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction()
        transaction.addAction(endCallAction)
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(inSeconds)) {
            Task { try await callController.request(transaction) }
        }
    }

}

extension CXHandle: ObvHandle {
    var type_: ObvHandleType { type.obvHandleType }
}
extension ObvHandle {
    var cxHandle: CXHandle { CXHandle(type: type_.cxHandleType, value: value) }
}

extension CXCallUpdate: ObvCallUpdate {
    var remoteHandle_: ObvHandle? {
        get { remoteHandle }
        set { remoteHandle = newValue?.cxHandle }
    }
}
extension ObvCallUpdate {
    var cxCallUpdate: CXCallUpdate {
        let update = CXCallUpdate()
        update.remoteHandle = remoteHandle_?.cxHandle
        update.localizedCallerName = localizedCallerName
        update.supportsHolding = supportsHolding
        update.supportsGrouping = supportsGrouping
        update.supportsUngrouping = supportsUngrouping
        update.supportsDTMF = supportsDTMF
        update.hasVideo = hasVideo
        return update
    }
}


extension CXStartCallAction: ObvStartCallAction {
    var handle_: ObvHandle { self.handle }
}
extension CXAnswerCallAction: ObvAnswerCallAction { }
extension CXEndCallAction: ObvEndCallAction { }
extension CXSetHeldCallAction: ObvSetHeldCallAction { }
extension CXSetMutedCallAction: ObvSetMutedCallAction { }
extension CXPlayDTMFCallAction.ActionType {
    var obvType: ObvPlayDTMFCallActionType {
        switch self {
        case .singleTone: return .singleTone
        case .softPause: return .softPause
        case .hardPause: return .hardPause
        @unknown default: return .unknown
        }
    }
}
extension CXPlayDTMFCallAction: ObvPlayDTMFCallAction {
    var type_: ObvPlayDTMFCallActionType { type.obvType }
}
class CXObvProviderDelegate: NSObject, CXProviderDelegate {

    let delegate: ObvProviderDelegate?

    init(delegate: ObvProviderDelegate?) {
        self.delegate = delegate
        super.init()
    }

    func providerDidBegin(_ provider: CXProvider) {
        Task { [weak self] in await self?.delegate?.providerDidBegin() }
    }
    func providerDidReset(_ provider: CXProvider) {
        Task { [weak self] in await self?.delegate?.providerDidReset() }
    }
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        guard let delegate = delegate else { assertionFailure(); action.fail(); return }
        Task { await delegate.provider(perform: action) }
    }
    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let delegate = delegate else { assertionFailure(); action.fail(); return }
        Task { await delegate.provider(perform: action) }
    }
    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let delegate = delegate else { assertionFailure(); action.fail(); return }
        Task { await delegate.provider(perform: action) }
    }
    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        Task { [weak self] in await self?.delegate?.provider(perform: action) }
    }
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        Task { [weak self] in await self?.delegate?.provider(perform: action) }
    }
    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        Task { [weak self] in await self?.delegate?.provider(perform: action) }
    }
    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        if let obvAction = action as? ObvAction {
            Task { [weak self] in await self?.delegate?.provider(timedOutPerforming: obvAction) }
        } else {
            assertionFailure()
            action.fail()
        }
    }
    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        Task { [weak self] in await self?.delegate?.provider(didActivate: audioSession) }
    }
    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        Task { [weak self] in await self?.delegate?.provider(didDeactivate: audioSession) }
    }
}

extension CXCall: ObvCall { }

class CXObvCallObserverDelegate: NSObject, CXCallObserverDelegate {

    let delegate: ObvCallObserverDelegate?

    init(delegate: ObvCallObserverDelegate?) {
        self.delegate = delegate
        super.init()
    }
    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        delegate?.callObserver(callChanged: call)
    }
}

class CXObvCallObserver: CXCallObserver, ObvCallObserver {
    var calls_: [ObvCall] { calls }

    private var delegate: CXObvCallObserverDelegate?

    func setDelegate(_ delegate: ObvCallObserverDelegate?, queue: DispatchQueue?) {
        self.delegate = CXObvCallObserverDelegate(delegate: delegate)
        super.setDelegate(self.delegate, queue: queue)
    }

}

/// CXCallObserverDelegate Exemple
class CXCallObserverTest: NSObject, CXCallObserverDelegate {

    private let callObserver = CXObvCallObserver()

    override init() {
        super.init()
        callObserver.setDelegate(self, queue: DispatchQueue.main)
    }

    func callObserver(_ callObserver: CXCallObserver, callChanged call: CXCall) {
        print("☎️ CX Observe call changed uuid=", call.uuid, " isOutgoing=", call.isOutgoing, " isOnHold=", call.isOnHold, " hasConnected=", call.hasConnected, " hasEnded=", call.hasEnded)
        print("☎️ CX Number of ObvCall=", callObserver.calls.count)
    }
}



// MARK: - ObvErrorCodeRequestTransactionError

enum ObvErrorCodeRequestTransactionError: Int {
    case unknown = 0
    case unentitled = 1
    case unknownCallProvider = 2
    case emptyTransaction = 3
    case unknownCallUUID = 4
    case callUUIDAlreadyExists = 5
    case invalidAction = 6
    case maximumCallGroupsReached = 7

    var localizedDescription: String {
        switch self {
        case .unknown: return "unknown"
        case .unentitled: return "unentitled"
        case .unknownCallProvider: return "unknownCallProvider"
        case .emptyTransaction: return "emptyTransaction"
        case .unknownCallUUID: return "unknownCallUUID"
        case .callUUIDAlreadyExists: return "callUUIDAlreadyExists"
        case .invalidAction: return "invalidAction"
        case .maximumCallGroupsReached: return "maximumCallGroupsReached"
        }
    }
}
