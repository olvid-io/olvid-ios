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

import UIKit
import os.log


final class AppStateManager: LocalAuthenticationViewControllerDelegate {
    
    static let shared = AppStateManager()
    
    var appType: ObvMessengerConstants.AppType?

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "AppStateManager")
    
    private var userIsAuthenticating = false
    private var _ignoreNextResignActiveTransition = false
    
    private var completionHandlersToExecuteWhenInitializedAndActive = [() -> Void]()
    private var completionHandlersToExecuteWhenInitialized = [() -> Void]()

    private(set) weak var olvidURLHandler: OlvidURLHandler?
    private var olvidURLsOnHold = [OlvidURL]()
    
    var ignoreNextResignActiveTransition: Bool {
        get {
            assert(Thread.isMainThread)
            return _ignoreNextResignActiveTransition
        }
        set {
            assert(Thread.isMainThread)
            _ignoreNextResignActiveTransition = newValue
        }
    }
    

    private let queueForPostingAppStateChangedNotifications = DispatchQueue(label: "Queue for posting all appStateChanged notifications")
    

    private var observationTokens = [NSObjectProtocol]()
    fileprivate let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "AppStateManager internal queue"
        return queue
    }()
    
    // Multiple simultaneous readers, single writer
    private var _currentState = AppState.justLaunched(iOSAppState: .notActive, authenticateAutomaticallyNextTime: true, callInProgress: nil)
    private let queueForAccessingCurrentState = DispatchQueue(label: "Queue for accessing _currentState", attributes: .concurrent)
    

    var currentState: AppState {
        queueForAccessingCurrentState.sync { _currentState }
    }
    
        
    private init() {
        observeNotifications()
        os_log("🏁 App State Manager was initialized", log: log, type: .info)
    }
    
    
    fileprivate func setState(to newState: AppState) {
        assert(OperationQueue.current == AppStateManager.shared.internalQueue)
        
        guard currentState != newState else { return }
        
        let previousState = currentState
        queueForAccessingCurrentState.sync(flags: .barrier) {
            _currentState = newState
        }

        os_log("🏁 App State will change: %{public}@ --> %{public}@", log: log, type: .info, currentState.debugDescription, newState.debugDescription)

        let log = self.log
        
        if currentState.isInitialized {
            DispatchQueue.main.async { [weak self] in
                guard let _self = self else { return }
                for completionHandler in _self.completionHandlersToExecuteWhenInitialized {
                    os_log("🏁 Executing a completion handler that was stored until the app is initialized", log: log, type: .info)
                    completionHandler()
                }
                _self.completionHandlersToExecuteWhenInitialized.removeAll()
            }
        }

        if currentState.isInitializedAndActive {
            DispatchQueue.main.async { [weak self] in
                guard let _self = self else { return }
                for completionHandler in _self.completionHandlersToExecuteWhenInitializedAndActive {
                    os_log("🏁 Executing a completion handler that was stored until the app is initialized and active", log: log, type: .info)
                    completionHandler()
                }
                _self.completionHandlersToExecuteWhenInitializedAndActive.removeAll()
            }
        }
        
        os_log("🏁 Posting an appStateChanged notification with previousState: %{public}@ and currentState: %{public}@", log: log, type: .info, previousState.debugDescription, currentState.debugDescription)
        ObvMessengerInternalNotification.appStateChanged(previousState: previousState, currentState: currentState)
            .postOnDispatchQueue(queueForPostingAppStateChangedNotifications)

    }
    
    
    func setStateToInitializing() {
        assert(OperationQueue.current != AppStateManager.shared.internalQueue)
        assert(currentState.isJustLaunched)
        let op = UpdateCurrentAppStateOperation(newRawAppState: .initializing)
        internalQueue.addOperation(op)
        op.waitUntilFinished()
    }
    
    
    private func observeNotifications() {
        let log = self.log
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeCallHasBeenUpdated(queue: OperationQueue.main) { [weak self] (call, _) in
                let op = UpdateStateWithCurrentCallChangesOperation(newCall: call)
                self?.internalQueue.addOperation(op)
            },
            ObvMessengerInternalNotification.observeNoMoreCallInProgress(queue: OperationQueue.main) { [weak self] in
                let op = RemoveCallInProgressOperation()
                self?.internalQueue.addOperation(op)
            },
            ObvMessengerInternalNotification.observeAppInitializationEnded(queue: OperationQueue.main) { [weak self] in
                os_log("🏁 Receiving an AppInitializationEnded notification", log: log, type: .info)
                let op = UpdateCurrentAppStateOperation(newRawAppState: .initialized)
                self?.internalQueue.addOperation(op)
            },
            NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] (notification) in
                self?.ignoreNextResignActiveTransition = false
                let op = UpdateCurrentIOSAppStateOperation(newIOSAppState: .active)
                self?.internalQueue.addOperation(op)
            },
            NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] (notification) in
                self?.ignoreNextResignActiveTransition = false
                let op = UpdateCurrentIOSAppStateOperation(newIOSAppState: .inBackground)
                self?.internalQueue.addOperation(op)
            },
            NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] (notification) in
                self?.ignoreNextResignActiveTransition = false
                let op = UpdateCurrentIOSAppStateOperation(newIOSAppState: .notActive)
                self?.internalQueue.addOperation(op)
            },
            NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] (notification) in
                guard self?.userIsAuthenticating == false else { return }
                guard self?.ignoreNextResignActiveTransition == false else {
                    self?.ignoreNextResignActiveTransition = false
                    return
                }
                let op = UpdateCurrentIOSAppStateOperation(newIOSAppState: .mayResignActive)
                self?.internalQueue.addOperation(op)
            },
        ])
    }
    
    func userWillTryToAuthenticate() {
        assert(Thread.isMainThread)
        userIsAuthenticating = true
    }
    
    func userDidTryToAuthenticated() {
        assert(Thread.isMainThread)
        userIsAuthenticating = false
    }
    
    func userLocalAuthenticationDidSucceedOrWasNotRequired() {
        assert(Thread.isMainThread)
        let op = UpdateStateAfterUserLocalAuthenticationSuccessOperation()
        self.internalQueue.addOperation(op)
    }
    
    func setOlvidURLHandler(to olvidURLHandler: OlvidURLHandler) {
        assert(Thread.isMainThread)
        assert(self.olvidURLHandler == nil)
        self.olvidURLHandler = olvidURLHandler
        olvidURLsOnHold.forEach {
            _ = olvidURLHandler.handleOlvidURL($0)
        }
        olvidURLsOnHold.removeAll()
    }
    
    /// Can be called from anywhere within the app. This methods forwards the `OlvidURL` to the appropriate handler,
    /// at the appropriate time (i.e., when a handler is available).
    func handleOlvidURL(_ olvidURL: OlvidURL) {
        assert(Thread.isMainThread)
        if let olvidURLHandler = self.olvidURLHandler {
            olvidURLHandler.handleOlvidURL(olvidURL)
        } else {
            olvidURLsOnHold.append(olvidURL)
        }
    }
    
}


// MARK: - Helpers for completion handlers to execute when app becomes initialized and active

extension AppStateManager {
    
    func addCompletionHandlerToExecuteWhenInitializedAndActive(completionHandler: @escaping () -> Void) {
        assert(Thread.isMainThread)
        guard !currentState.isInitializedAndActive else {
            os_log("🏁 Executing a completion handler immediately as the app is already initialized and active", log: log, type: .info)
            completionHandler()
            return
        }
        // If we reach this point, the app is either not initialized or not active, we store the completion handler for later
        os_log("🏁 Storing a completion handler until the app is initialized and active", log: log, type: .info)
        completionHandlersToExecuteWhenInitializedAndActive.append(completionHandler)
    }

    func addCompletionHandlerToExecuteWhenInitialized(completionHandler: @escaping () -> Void) {
        assert(Thread.isMainThread)
        guard !currentState.isInitialized else {
            os_log("🏁 Executing a completion handler immediately as the app is already initialized", log: log, type: .info)
            completionHandler()
            return
        }
        // If we reach this point, the app is not initialized, we store the completion handler for later
        os_log("🏁 Storing a completion handler until the app is initialized and active", log: log, type: .info)
        completionHandlersToExecuteWhenInitialized.append(completionHandler)
    }

}


// MARK: - Operations that change the current App State

fileprivate final class UpdateCurrentAppStateOperation: Operation {
    
    let newRawAppState: RawAppState
    
    init(newRawAppState: RawAppState) {
        self.newRawAppState = newRawAppState
    }

    override func main() {
        
        assert(OperationQueue.current == AppStateManager.shared.internalQueue)
        
        let updatedState: AppState
        
        switch AppStateManager.shared.currentState {
        case .justLaunched(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: let callInProgress):
            switch newRawAppState {
            case .justLaunched:
                updatedState = .justLaunched(iOSAppState: iOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            case .initializing:
                updatedState = .initializing(iOSAppState: iOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            case .initialized:
                updatedState = .initialized(iOSAppState: iOSAppState, authenticated: false, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            }
        case .initializing(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: let callInProgress):
            switch newRawAppState {
            case .justLaunched:
                updatedState = .justLaunched(iOSAppState: iOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            case .initializing:
                updatedState = .initializing(iOSAppState: iOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            case .initialized:
                updatedState = .initialized(iOSAppState: iOSAppState, authenticated: false, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            }
        case .initialized(iOSAppState: let iOSAppState, authenticated: let authenticated, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: let callInProgress):
            switch newRawAppState {
            case .justLaunched:
                updatedState = .justLaunched(iOSAppState: iOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            case .initializing:
                updatedState = .initializing(iOSAppState: iOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            case .initialized:
                updatedState = .initialized(iOSAppState: iOSAppState, authenticated: authenticated, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            }
        }

        AppStateManager.shared.setState(to: updatedState)

    }
    
}

fileprivate final class UpdateCurrentIOSAppStateOperation: Operation {
    
    let newIOSAppState: IOSAppState
    
    init(newIOSAppState: IOSAppState) {
        self.newIOSAppState = newIOSAppState
    }
    
    override func main() {
        
        assert(OperationQueue.current == AppStateManager.shared.internalQueue)
        
        let updatedState: AppState
        
        switch AppStateManager.shared.currentState {

        case .justLaunched(iOSAppState: _, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: let callInProgress):
            updatedState = .justLaunched(iOSAppState: newIOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)

        case .initializing(iOSAppState: _, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: let callInProgress):
            updatedState = .initializing(iOSAppState: newIOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)

        case .initialized(iOSAppState: _, authenticated: let authenticated, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: let callInProgress):
            switch newIOSAppState {
            case .inBackground:
                updatedState = .initialized(iOSAppState: newIOSAppState, authenticated: false, authenticateAutomaticallyNextTime: autoAuth || callInProgress == nil, callInProgress: callInProgress)
            case .notActive:
                updatedState = .initialized(iOSAppState: newIOSAppState, authenticated: false, authenticateAutomaticallyNextTime: autoAuth || callInProgress == nil, callInProgress: callInProgress)
            case .mayResignActive:
                updatedState = .initialized(iOSAppState: newIOSAppState, authenticated: authenticated, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            case .active:
                updatedState = .initialized(iOSAppState: newIOSAppState, authenticated: authenticated, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callInProgress)
            }
        }
        
        AppStateManager.shared.setState(to: updatedState)
        
    }
}



fileprivate final class RemoveCallInProgressOperation: Operation {
    override func main() {
        
        assert(OperationQueue.current == AppStateManager.shared.internalQueue)

        let updatedState: AppState

        switch AppStateManager.shared.currentState {
        case .justLaunched(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: let call):
            assert(call == nil || call!.state.isFinalState)
            updatedState = .justLaunched(iOSAppState: iOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: nil)
        case .initializing(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: let call):
            assert(call == nil || call!.state.isFinalState)
            updatedState = .initializing(iOSAppState: iOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: nil)
        case .initialized(iOSAppState: let iOSAppState, authenticated: let authenticated, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: let call):
            assert(call == nil || call!.state.isFinalState)
            updatedState = .initialized(iOSAppState: iOSAppState, authenticated: authenticated, authenticateAutomaticallyNextTime: autoAuth, callInProgress: nil)
        }
        
        AppStateManager.shared.setState(to: updatedState)

    }
}

fileprivate final class UpdateStateWithCurrentCallChangesOperation: Operation {

    let newCall: Call

    init(newCall: Call) {
        self.newCall = newCall
    }

    override func main() {
        
        assert(OperationQueue.current == AppStateManager.shared.internalQueue)

        var appropriateCall = determineAppropriateCallForState(call1: AppStateManager.shared.currentState.callInProgress, call2: newCall)
        if let _appropriateCall = appropriateCall, _appropriateCall.state.isFinalState {
            appropriateCall = nil
        }

        var callAndState: CallAndState?
        if let appropriateCall = appropriateCall {
            callAndState = (appropriateCall, appropriateCall.state)
        }

        // If we reach this point, the call is worth changing the App state.

        let updatedState: AppState

        switch AppStateManager.shared.currentState {
        
        case .justLaunched(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: _):
            updatedState = .justLaunched(iOSAppState: iOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callAndState)
        case .initializing(iOSAppState: let iOSAppState, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: _):
            updatedState = .initializing(iOSAppState: iOSAppState, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callAndState)
        case .initialized(iOSAppState: let iOSAppState, authenticated: let authenticated, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: _):
            updatedState = .initialized(iOSAppState: iOSAppState, authenticated: authenticated, authenticateAutomaticallyNextTime: autoAuth, callInProgress: callAndState)

        }
        
        AppStateManager.shared.setState(to: updatedState)

    }

    private func determineAppropriateCallForState(call1: Call?, call2: Call?) -> Call? {
        // If only one of the two calls is non nil, we return it if it is not in a final state, or nil otherwise
        guard let call1 = call1 else {
            guard let call2 = call2 else {
                return nil
            }
            return call2.state.isFinalState ? nil : call2
        }
        guard let call2 = call2 else {
            return call1.state.isFinalState ? nil : call1
        }
        // If both call are identical we return "the" call if it is not in a final state, or nil otherwise
        guard call1.uuid != call2.uuid else {
            return call1.state.isFinalState ? nil : call1
        }
        // At this point, we have two distinct non-nil calls and we must choose the one to keep within the state.
        // If both calls are in a final state, we return nil.
        guard !call1.state.isFinalState || !call2.state.isFinalState else {
            return nil
        }
        // At this point, at least of call is not in a final state. If other is in a final state, we know which one to return
        if call1.state.isFinalState {
            return call2
        }
        if call2.state.isFinalState {
            return call1
        }
        // At this point, none of the calls are in a final state.
        // If both are new, we return nil.
        guard call1.state != .initial || call2.state != .initial else {
            return nil
        }
        // At this point, at least one call is not new.
        // If one call is new, we return the call that is not new
        guard call1.state != .initial else {
            assert(call2.state != .initial)
            return call2
        }
        guard call2.state != .initial else {
            assert(call1.state != .initial)
            return call1
        }
        // At this point, none of the calls are in a final state and none is new.
        // If only one call is in progress, we return it
        if call1.state == .callInProgress && call2.state != .callInProgress {
            return call1
        }
        if call2.state == .callInProgress && call1.state != .callInProgress {
            return call2
        }
        // This point should not be reached
        assertionFailure()
        return nil
    }

}


fileprivate final class UpdateStateAfterUserLocalAuthenticationSuccessOperation: Operation {
    override func main() {
        let updatedState: AppState
        switch AppStateManager.shared.currentState {
        case .justLaunched, .initializing:
            assertionFailure()
            updatedState = AppStateManager.shared.currentState
        case .initialized(iOSAppState: let iOSAppState, authenticated: _, authenticateAutomaticallyNextTime: _, callInProgress: let call):
            updatedState = .initialized(iOSAppState: iOSAppState, authenticated: true, authenticateAutomaticallyNextTime: false, callInProgress: call)
        }
        AppStateManager.shared.setState(to: updatedState)
    }
}


protocol OlvidURLHandler: AnyObject {
    func handleOlvidURL(_ olvidURL: OlvidURL)
}