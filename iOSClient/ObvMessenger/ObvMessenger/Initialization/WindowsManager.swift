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
import os.log


final class WindowsManager {
    
    private(set) var appWindow: UIWindow
    private(set) var initializerWindow: UIWindow
    private(set) var privacyWindow: UIWindow
    private(set) var callWindow: UIWindow
    private(set) var initializationFailureWindow: UIWindow

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: WindowsManager.self))

    private var allWindows: [UIWindow] {
        return [appWindow, privacyWindow, callWindow, initializerWindow, initializationFailureWindow]
    }

    var currentKeyWindow: UIWindow {
        if let keyWindow = allWindows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        // In case we a running previews, it can happen that the key window cannot be found, so we bypass the assertion in that case.
#if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            /* Do nothing */
        } else {
            assertionFailure("Cannot find the keyWindow")
        }
        return appWindow
#else
        assertionFailure("Cannot find the keyWindow")
        return appWindow
#endif
    }
    
    private var nonCallKitIncomingCallToShow: GenericCall?
    private var keepCallWindowUntilNonCallKitIncomingCallIsHandled = false
    
    private var preferAppViewOverCallView = false
    private var currentState = AppState.justLaunched(iOSAppState: .notActive, authenticateAutomaticallyNextTime: true, callInProgress: nil, aCallRequiresNetworkConnection: false)

    private var observationTokens = [NSObjectProtocol]()
    
    
    private let initializerWindowLevel: UIWindow.Level = .alert + 2
    private let privacyWindowLevel: UIWindow.Level = .alert + 1
    private let fadeOutWindowLevel: UIWindow.Level = .alert
    
    init(initializerViewController: InitializerViewController) {
        appWindow = UIWindow(frame: UIScreen.main.bounds)
        appWindow.alpha = 0
        
        callWindow = UIWindow(frame: UIScreen.main.bounds)
        callWindow.alpha = 0

        initializationFailureWindow = UIWindow(frame: UIScreen.main.bounds)
        initializationFailureWindow.alpha = 0

        privacyWindow = UIWindow(frame: UIScreen.main.bounds)
        privacyWindow.alpha = 0
        privacyWindow.windowLevel = privacyWindowLevel

        initializerWindow = UIWindow(frame: UIScreen.main.bounds)
        initializerWindow.rootViewController = initializerViewController
        initializerWindow.alpha = 1
        initializerWindow.windowLevel = initializerWindowLevel
        initializerWindow.makeKeyAndVisible()

        observeNotifications()
    }
    
    func setWindowsRootViewControllers(localAuthenticationViewController: LocalAuthenticationViewController, appRootViewController: UIViewController) {
        assert(Thread.isMainThread)
        assert(appWindow.rootViewController == nil)
        appWindow.rootViewController = appRootViewController
        assert(privacyWindow.rootViewController == nil)
        privacyWindow.rootViewController = localAuthenticationViewController
    }
    
    
    func showInitializationFailureViewController(error: Error) {
        assert(Thread.isMainThread)
        let vc = InitializationFailureViewController()
        vc.error = error
        let nav = UINavigationController(rootViewController: vc)
        initializationFailureWindow.rootViewController = nav
        self.transitionToAppropriateWindow()
    }

    
    private func observeNotifications() {
        observationTokens.append(VoIPNotification.observeShowCallViewControllerForAnsweringNonCallKitIncomingCall(queue: OperationQueue.main) { [weak self] (incomingCall) in
            assert(!incomingCall.usesCallKit)
            assert(self?.nonCallKitIncomingCallToShow == nil)
            self?.nonCallKitIncomingCallToShow = incomingCall
            self?.transitionToAppropriateWindow()
        })
        observationTokens.append(ObvMessengerInternalNotification.observeAppStateChanged { (_, currentState) in
            Task { [weak self] in await self?.processAppStateChangedNotification(currentState: currentState) }
        })
        observationTokens.append(ObvMessengerInternalNotification.observeToggleCallView(queue: OperationQueue.main) { [weak self] in
            self?.toggleCallView()
        })
        observationTokens.append(ObvMessengerInternalNotification.observeHideCallView(queue: OperationQueue.main) { [weak self] in
            self?.hideCallView()
        })
        observationTokens.append(ObvMessengerInternalNotification.observeNoMoreCallInProgress(queue: OperationQueue.main) { [weak self] in
            self?.preferAppViewOverCallView = false
            guard self?.keepCallWindowUntilNonCallKitIncomingCallIsHandled == true else { return }
            self?.keepCallWindowUntilNonCallKitIncomingCallIsHandled = false
            self?.transitionToAppropriateWindow()
        })
    }
    
    
    @MainActor
    private func processAppStateChangedNotification(currentState: AppState) async {

        assert(Thread.isMainThread)

        let previousState = self.currentState
        self.currentState = currentState

        os_log("🪟 We received an AppStateChanged notification (%{public}@ --> %{public}@) ", log: log, type: .info, previousState.debugDescription, currentState.debugDescription)

        if let callInProgress = currentState.callInProgress, let genericCall = await AppStateManager.shared.callStateDelegate?.getGenericCallWithUuid(callInProgress.uuid) {
            if (callWindow.rootViewController as? CallViewHostingController)?.callUUID != genericCall.uuid {
                callWindow.rootViewController = makeCallViewController(call: genericCall)
            }
        }

        transitionToAppropriateWindow()
        
    }
    
    
    private func descriptionOfWindow(_ window: UIWindow) -> String {
        switch window {
        case appWindow:
            return "appWindow"
        case initializerWindow:
            return "initializerWindow"
        case privacyWindow:
            return "privacyWindow"
        case callWindow:
            return "callWindow"
        case initializationFailureWindow:
            return "initializationFailureWindow"
        default:
            return "Unknown - This is a bug"
        }
    }
    
}


// MARK: - Transitioning between the app window, the call window, and the privacy window

extension WindowsManager {
        
    private func transitionToAppropriateWindow() {

        assert(Thread.isMainThread)
        
        os_log("🪟 Call to transitionToAppropriateWindow", log: log, type: .info)

        guard initializationFailureWindow.rootViewController == nil else {
            transitionCurrentWindowTo(window: initializationFailureWindow, animated: true)
            return
        }
        
        /* We deal with the very special case when we receive an incoming call that is not using CallKit.
         * In that case, we immediately give the user an opportunity to answer/handup.
         * We do not expect this to happen if a call is already in progress (the call coordinator takes care
         * of rejecting the new incoming call in that case).
         */
        if let nonCallKitIncomingCallToShow = nonCallKitIncomingCallToShow {
            self.nonCallKitIncomingCallToShow = nil
            if callWindow.rootViewController == nil {
                callWindow.rootViewController = makeCallViewController(call: nonCallKitIncomingCallToShow)
            }
            transitionCurrentWindowTo(window: callWindow, animated: true)
            keepCallWindowUntilNonCallKitIncomingCallIsHandled = true
            return
        }
        
        if keepCallWindowUntilNonCallKitIncomingCallIsHandled {
            guard let call = currentState.callInProgress else {
                return
            }
            guard call.state != .initial else {
                return
            }
            keepCallWindowUntilNonCallKitIncomingCallIsHandled = false
        }
        
        switch currentState {
        
        case .justLaunched(iOSAppState: _, authenticateAutomaticallyNextTime: _, callInProgress: _, aCallRequiresNetworkConnection: _):
            transitionCurrentWindowTo(window: initializerWindow, animated: true)

        case .initializing(iOSAppState: _, authenticateAutomaticallyNextTime: _, callInProgress: _, aCallRequiresNetworkConnection: _):
            transitionCurrentWindowTo(window: initializerWindow, animated: true)

        case .initialized(iOSAppState: let iOSAppState, authenticated: let authenticated, authenticateAutomaticallyNextTime: let autoAuth, callInProgress: let callInProgress, aCallRequiresNetworkConnection: _):
            
            switch iOSAppState {
            case .inBackground:
                transitionCurrentWindowTo(window: initializerWindow, animated: true)
            case .notActive:
                preferAppViewOverCallView = false
                if let call = callInProgress, !call.state.isFinalState {
                    if call.state == .initial && ObvMessengerSettings.VoIP.isCallKitEnabled && call.direction == .incoming {
                        // Don't show call view since CallKit shows its own view.
                    } else {
                        assert(callWindow.rootViewController != nil)
                        transitionCurrentWindowTo(window: callWindow, animated: false)
                    }
                } else if ObvMessengerSettings.Privacy.lockScreen {
                    transitionCurrentWindowTo(window: privacyWindow, animated: false)
                }
            case .mayResignActive:
                if let call = callInProgress, !call.state.isFinalState {
                    if call.state == .initial && ObvMessengerSettings.VoIP.isCallKitEnabled && call.direction == .incoming {
                        // Don't show call view since CallKit shows its own view.
                    } else {
                        if preferAppViewOverCallView {
                            showAppWindowIfAllowedToOrShowPrivacyWindow(authenticated: authenticated, authenticateAutomaticallyNextTime: autoAuth)
                        } else {
                            assert(callWindow.rootViewController != nil)
                            transitionCurrentWindowTo(window: callWindow, animated: false)
                        }
                    }
                } else {
                    if ObvMessengerSettings.Privacy.lockScreen {
                        transitionCurrentWindowTo(window: privacyWindow, animated: false)
                    } else {
                        // Do nothing
                    }
                }
            case .active:
                os_log("🪟 The iOSAppState is active", log: log, type: .info)
                if let call = callInProgress, !call.state.isFinalState {
                    os_log("🪟 There is a call in progress and its state is not final", log: log, type: .info)
                    if call.state == .initial && ObvMessengerSettings.VoIP.isCallKitEnabled && call.direction == .incoming && ObvMessengerSettings.Privacy.lockScreen {
                        // Don't show call view since CallKit shows its own view.
                        return
                    } else if preferAppViewOverCallView {
                        os_log("🪟 Prefer App view over call view", log: log, type: .info)
                        showAppWindowIfAllowedToOrShowPrivacyWindow(authenticated: authenticated, authenticateAutomaticallyNextTime: autoAuth)
                    } else {
                        // This is the line called when accepting a call that we received while Olvid was in foreground.
                        // This is also the line called when making an outgoing call. So we distinguish both cases.
                        switch call.direction {
                        case .incoming:
                            guard call.userAnsweredIncomingCall || !ObvMessengerSettings.VoIP.isCallKitEnabled else { return } // Do nothing
                            assert(callWindow.rootViewController != nil)
                            transitionCurrentWindowTo(window: callWindow, animated: true)
                        case .outgoing:
                            assert(callWindow.rootViewController != nil)
                            transitionCurrentWindowTo(window: callWindow, animated: true)
                        }
                    }
                } else {
                    os_log("🪟 No call in progress, we show the app window if allowed, or the privacy window.", log: log, type: .info)
                    showAppWindowIfAllowedToOrShowPrivacyWindow(authenticated: authenticated, authenticateAutomaticallyNextTime: autoAuth)
                }
            }
        }

        appWindow.rootViewController?.setNeedsStatusBarAppearanceUpdate()

    }
    
    
    private func showAppWindowIfAllowedToOrShowPrivacyWindow(authenticated: Bool, authenticateAutomaticallyNextTime: Bool) {
        os_log("🪟 Call to showAppWindowIfAllowedToOrShowPrivacyWindow", log: log, type: .info)
        if authenticated || !ObvMessengerSettings.Privacy.lockScreen {
            os_log("🪟 Call to transitionCurrentWindowTo(window: appWindow, animated: true) from showAppWindowIfAllowedToOrShowPrivacyWindow", log: log, type: .info)
            transitionCurrentWindowTo(window: appWindow, animated: true)
        } else {
            os_log("🪟 Call to transitionCurrentWindowTo(window: privacyWindow, animated: true) from showAppWindowIfAllowedToOrShowPrivacyWindow", log: log, type: .info)
            transitionCurrentWindowTo(window: privacyWindow, animated: true)
            if authenticateAutomaticallyNextTime {
                (privacyWindow.rootViewController as? LocalAuthenticationViewController)?.performLocalAuthentication()
            } else {
                (privacyWindow.rootViewController as? LocalAuthenticationViewController)?.shouldPerformLocalAuthentication()
            }
        }
    }
    
    
    private func toggleCallView() {
        preferAppViewOverCallView.toggle()
        if !preferAppViewOverCallView, callWindow.rootViewController == nil, let call = currentState.callInProgress {
            Task {
                guard let genericCall = await AppStateManager.shared.callStateDelegate?.getGenericCallWithUuid(call.uuid) else { assertionFailure(); return }
                DispatchQueue.main.async { [weak self] in
                    guard let _self = self else { return }
                    _self.callWindow.rootViewController = _self.makeCallViewController(call: genericCall)
                    _self.transitionToAppropriateWindow()
                }
            }
        } else {
            transitionToAppropriateWindow()
        }
    }

    private func hideCallView() {
        guard currentState.callInProgress != nil else { return }
        guard !preferAppViewOverCallView else { return }
        toggleCallView()
    }
    
    private func transitionCurrentWindowTo(window: UIWindow, animated: Bool) {
        assert(Thread.isMainThread)
        os_log("🪟 Call to transitionCurrentWindowTo %{public}@", log: log, type: .info, descriptionOfWindow(window))
        guard allWindows.contains(window) else {
            os_log("🪟 The requested window (%{public}@) is not part of the allWindows array", log: log, type: .fault)
            assertionFailure(); return
        }
        guard currentKeyWindow != window else {
            os_log("🪟 The current key window is already the one requested", log: log, type: .info)
            return
        }
        let previousKeyWindow = currentKeyWindow
        // In case the previous window is not the privacy window, we "elevate" it (to the fadeOutWindowLevel), insert the new window underneath, and fade out the previous window.
        if previousKeyWindow != privacyWindow {
            previousKeyWindow.windowLevel = fadeOutWindowLevel
        }
        if window != privacyWindow {
            window.windowLevel = .normal
        }
        window.alpha = 1
        window.makeKey()
        window.isHidden = false
        if animated {
            UIView.animate(withDuration: 0.3, animations: { [weak self] in
                previousKeyWindow.alpha = 0
                if previousKeyWindow == self?.callWindow {
                    previousKeyWindow.rootViewController = nil
                }
            })
        } else {
            previousKeyWindow.alpha = 0
            if previousKeyWindow == callWindow {
                previousKeyWindow.rootViewController = nil
            }
        }
    }

}


// MARK: Call View and Banner View Management

extension WindowsManager {
    
    private func makeCallViewController(call: GenericCall) -> UIViewController {
        CallViewHostingController(call: call)
    }
    
}
