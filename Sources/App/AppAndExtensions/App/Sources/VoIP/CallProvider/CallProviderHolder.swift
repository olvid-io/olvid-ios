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
import CallKit
import AVFoundation
import os
import ObvSettings


protocol CallProviderHolderDelegate: AnyObject {

    // Handling Provider Events
    // func providerDidBegin(_ provider: CallProviderHolder) async
    func providerDidReset(_ provider: CallProviderHolder) async

    // Determining the Execution of Transactions
    // func provider(_ provider: CallProviderHolder, execute transaction: CXTransaction) -> Bool

    // Handling Call Actions
    func provider(_ provider: CallProviderHolder, perform: CXStartCallAction) async
    func provider(_ provider: CallProviderHolder, perform: CXAnswerCallAction) async
    func provider(_ provider: CallProviderHolder, perform: CXEndCallAction) async
    //func provider(_ provider: CallProviderHolder, perform: CXSetHeldCallAction) async
    func provider(_ provider: CallProviderHolder, perform: CXSetMutedCallAction) async
    //func provider(_ provider: CallProviderHolder, perform: CXSetGroupCallAction) async
    //func provider(_ provider: CallProviderHolder, perform: CXPlayDTMFCallAction) async
    func provider(_ provider: CallProviderHolder, timedOutPerforming action: CXAction) async

    // Handling Changes to Audio Session Activation State
    func provider(_ provider: CallProviderHolder, didActivate audioSession: AVAudioSession) async
    func provider(_ provider: CallProviderHolder, didDeactivate audioSession: AVAudioSession) async
}


/// Subclass of `NSObject` as this class implements `CXProviderDelegate`.
final class CallProviderHolder: NSObject {
    
    private let cxProvider: CXProvider
    private let nxProvider: NCXProvider

    /// The reports that open or end a call in CallKit are written to the in-app logs.
    var provider: CallProviderProtocol {
        InAppLoggingCallProvider(wrapped: ObvUICoreDataConstants.useCallKit ? cxProvider : nxProvider)
    }

    /// The number of times CallKit has activated the audio session in this process, so that an activation that does not come can be noticed.
    var numberOfCallKitAudioSessionActivations: Int {
        callKitAudioSessionActivations.withLock { $0 }
    }

    private let callKitAudioSessionActivations = OSAllocatedUnfairLock(initialState: 0)
    
    var ncxCallControllerDelegate: NCXCallControllerDelegate {
        nxProvider
    }
    
    private weak var delegate: CallProviderHolderDelegate?
    
    /// The app's provider configuration, representing its CallKit capabilities
    /// A `CXProviderConfiguration` object controls the native call UI for incoming and outgoing calls.
    private static let providerConfiguration: CXProviderConfiguration = {
        let providerConfiguration = CXProviderConfiguration()
        providerConfiguration.iconTemplateImageData = UIImage(named: "olvid-callkit-logo")?.pngData()
        providerConfiguration.maximumCallGroups = 1
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.generic]
        providerConfiguration.supportsVideo = true
        providerConfiguration.includesCallsInRecents = ObvMessengerSettings.VoIP.isIncludesCallsInRecentsEnabled
        return providerConfiguration
    }()

    
    override init() {
        self.cxProvider = .init(configuration: Self.providerConfiguration)
        self.nxProvider = NCXProvider()
        super.init()
        self.cxProvider.setDelegate(self, queue: nil)
        self.nxProvider.setDelegate(self)
    }
    
    
    func setDelegate(_ delegate: CallProviderHolderDelegate?) {
        self.delegate = delegate
    }
    
}


// MARK: - Implementing CXProviderDelegate

extension CallProviderHolder: CXProviderDelegate {
    
    // Handling Provider Events

    // The in-app lines written by the three callbacks that follow are written where CallKit calls them, before the hop to the delegate.

    func providerDidReset(_ provider: CXProvider) {
        OlvidCallInAppLog.log(call: nil, "CallKit reset the provider")
        genericProviderDidReset(provider)
    }
    
    // Handling Call Actions
    
    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        genericProvider(provider, perform: action)
    }

    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        genericProvider(provider, perform: action)
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        genericProvider(provider, perform: action)
    }
    
    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        genericProvider(provider, perform: action)
    }

    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        guard let delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate.provider(self, timedOutPerforming: action)
        }
    }

    // Handling Changes to Audio Session Activation State

    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        callKitAudioSessionActivations.withLock { $0 += 1 }
        OlvidCallInAppLog.log(call: nil, "CallKit called didActivate")
        genericProvider(provider, didActivate: audioSession)
    }

    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        OlvidCallInAppLog.log(call: nil, "CallKit called didDeactivate")
        genericProvider(provider, didDeactivate: audioSession)
    }

}


// MARK: - Writing the reports to CallKit to the in-app logs

/// Writes each report that opens or ends a call in CallKit to the in-app logs, then hands it to the wrapped provider.
private struct InAppLoggingCallProvider: CallProviderProtocol {

    let wrapped: CallProviderProtocol

    func reportNewIncomingCall(with uuid: UUID, update: CXCallUpdate, completion: @escaping @Sendable (Error?) -> Void) {
        OlvidCallInAppLog.log(call: uuid, "reporting a new incoming call to CallKit")
        wrapped.reportNewIncomingCall(with: uuid, update: update) { error in
            if let error {
                OlvidCallInAppLog.log(call: uuid, "CallKit refused the new incoming call: \(error.localizedDescription)")
            } else {
                OlvidCallInAppLog.log(call: uuid, "CallKit accepted the new incoming call")
            }
            completion(error)
        }
    }

    func reportOutgoingCall(with uuid: UUID, startedConnectingAt date: Date?) {
        wrapped.reportOutgoingCall(with: uuid, startedConnectingAt: date)
    }

    func reportOutgoingCall(with uuid: UUID, connectedAt date: Date?) {
        wrapped.reportOutgoingCall(with: uuid, connectedAt: date)
    }

    func reportCall(with uuid: UUID, updated update: CXCallUpdate) {
        wrapped.reportCall(with: uuid, updated: update)
    }

    func reportCall(with uuid: UUID, endedAt date: Date?, reason: CXCallEndedReason) {
        OlvidCallInAppLog.log(call: uuid, "reporting to CallKit that the call ended, reason: \(OlvidCallInAppLog.description(of: reason))")
        wrapped.reportCall(with: uuid, endedAt: date, reason: reason)
    }

}


// MARK: - Implementing NCXProviderDelegate

extension CallProviderHolder: NCXProviderDelegate {
        
    // Handling Call Actions
    
    func provider(_ provider: NCXProvider, perform action: CXStartCallAction) {
        genericProvider(provider, perform: action)
    }
    
    func provider(_ provider: NCXProvider, perform action: CXAnswerCallAction) {
        genericProvider(provider, perform: action)
    }
    
    func provider(_ provider: NCXProvider, perform action: CXEndCallAction) {
        genericProvider(provider, perform: action)
    }
    
    func provider(_ provider: NCXProvider, perform action: CXSetMutedCallAction) {
        genericProvider(provider, perform: action)
    }

    
    // Handling Changes to Audio Session Activation State
    
    func provider(_ provider: NCXProvider, didActivate audioSession: AVAudioSession) {
        genericProvider(provider, didActivate: audioSession)
    }
    
    func provider(_ provider: NCXProvider, didDeactivate audioSession: AVAudioSession) {
        genericProvider(provider, didDeactivate: audioSession)
    }
    
}


// MARK: - For both CXProviderDelegate and NCXProviderDelegate

extension CallProviderHolder {
    
    // Handling Provider Events
    
    private func genericProviderDidReset(_ provider: CallProviderProtocol) {
        guard let delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate.providerDidReset(self)
        }
    }

    // Handling Call Actions
    
    private func genericProvider(_ provider: CallProviderProtocol, perform action: CXStartCallAction) {
        guard let delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate.provider(self, perform: action)
        }
    }
    
    
    private func genericProvider(_ provider: CallProviderProtocol, perform action: CXAnswerCallAction) {
        guard let delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate.provider(self, perform: action)
        }
    }
    
    
    private func genericProvider(_ provider: CallProviderProtocol, perform action: CXEndCallAction) {
        guard let delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate.provider(self, perform: action)
        }
    }
    
    
    private func genericProvider(_ provider: CallProviderProtocol, perform action: CXSetMutedCallAction) {
        guard let delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate.provider(self, perform: action)
        }
    }

    
    // Handling Changes to Audio Session Activation State
    
    private func genericProvider(_ provider: CallProviderProtocol, didActivate audioSession: AVAudioSession) {
        guard let delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate.provider(self, didActivate: audioSession)
        }
    }
    
    
    private func genericProvider(_ provider: CallProviderProtocol, didDeactivate audioSession: AVAudioSession) {
        guard let delegate else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate.provider(self, didDeactivate: audioSession)
        }
    }

}
