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
import LocalAuthentication

class LocalAuthenticationViewController: UIViewController {

    private enum AuthenticationStatus {
        case initial
        case shouldPerformLocalAuthentication
        case authenticated
        case authenticationFailed
    }
    
    private var authenticationStatus = AuthenticationStatus.initial
    private let imageView = UIImageView()
    private var observationTokens = [NSObjectProtocol]()
    private var isAuthenticating = false
    private var isAuthenticated = !ObvMessengerSettings.Privacy.lockScreen
    private let authenticateButton = UIButton()
    private var uptimeAtTheTimeOfChangeoverToNotActiveState: TimeInterval?
    var usedByShareExtension = false

    
    weak var delegate: LocalAuthenticationViewControllerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Use the LaunchScreen's view to ensure a smooth transition
        let launchScreenStoryBoard = UIStoryboard(name: "LaunchScreen", bundle: nil)
        guard let launchViewController = launchScreenStoryBoard.instantiateInitialViewController() else { assertionFailure(); return }
        self.view.addSubview(launchViewController.view)
        self.view.pinAllSidesToSides(of: launchViewController.view)
        authenticateButton.translatesAutoresizingMaskIntoConstraints = false
        authenticateButton.addTarget(self, action: #selector(authenticateButtonTapped), for: .touchUpInside)
        authenticateButton.setTitle(Strings.authenticate, for: .normal)
        self.view.addSubview(authenticateButton)
        let constraints = [
            authenticateButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor, constant: 0.0),
            authenticateButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: 100.0),
        ]
        NSLayoutConstraint.activate(constraints)
        configure()
        setUptimeAtTheTimeOfChangeoverToNotActiveStateWhenAppropriate()
    }
    
    
    private func setUptimeAtTheTimeOfChangeoverToNotActiveStateWhenAppropriate() {
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeAppStateChanged(queue: .main) { [weak self] previousState, currentState in
                guard let _self = self else { return }
                if previousState.isAuthenticated && previousState.isInitialized && previousState.iOSAppState == .mayResignActive && currentState.iOSAppState == .inBackground {
                    _self.uptimeAtTheTimeOfChangeoverToNotActiveState = _self.getUptime()
                }
            },
        ])
    }
    
        
    private func setAuthenticationStatus(to newAuthenticationStatus: AuthenticationStatus) {
        assert(Thread.isMainThread)
        authenticationStatus = newAuthenticationStatus
        if authenticationStatus == .authenticated {
            delegate?.userLocalAuthenticationDidSucceedOrWasNotRequired()
            authenticationStatus = .initial
        }
        configure()
    }
    
    private func configure() {
        switch authenticationStatus {
        case .initial:
            authenticateButton.isHidden = true
            authenticateButton.isEnabled = false
        case .shouldPerformLocalAuthentication:
            authenticateButton.isHidden = false
            authenticateButton.isEnabled = true
        case .authenticated:
            authenticateButton.isHidden = true
            authenticateButton.isEnabled = false
        case .authenticationFailed:
            authenticateButton.isHidden = false
            authenticateButton.isEnabled = true
        }
    }
    
    @objc func authenticateButtonTapped() {
        performLocalAuthentication()
    }
    
    func shouldPerformLocalAuthentication() {
        setAuthenticationStatus(to: .shouldPerformLocalAuthentication)
    }

    private func getUptime() -> TimeInterval {
        var uptime = timespec()
        if clock_gettime(CLOCK_MONOTONIC_RAW, &uptime) != 0 {
            return 0
        }
        return TimeInterval(uptime.tv_sec)
    }
    
    func performLocalAuthentication(completion: ((Bool) -> Void)? = nil) {
        assert(Thread.isMainThread)
        let userIsAlreadyAuthenticated: Bool
        if let uptimeAtTheTimeOfChangeoverToNotActiveState = uptimeAtTheTimeOfChangeoverToNotActiveState {
            let timeIntervalSinceLastChangeoverToNotActiveState = getUptime() - uptimeAtTheTimeOfChangeoverToNotActiveState
            assert(0 <= timeIntervalSinceLastChangeoverToNotActiveState)
            userIsAlreadyAuthenticated = (timeIntervalSinceLastChangeoverToNotActiveState < ObvMessengerSettings.Privacy.lockScreenGracePeriod)
        } else {
            userIsAlreadyAuthenticated = false
        }
        if userIsAlreadyAuthenticated {
            setAuthenticationStatus(to: .authenticated)
            completion?(true)
            return
        } else {
            // We only check whether the window is key under iOS 13+.
            // Under iOS 12 and less, we check that we are not running the share extension. Otherwise the test is always false.
            if #available(iOS 13, *) {
                guard self.view.window?.isKeyWindow == true else { assertionFailure(); return }
            } else if !usedByShareExtension {
                guard self.view.window?.isKeyWindow == true else { assertionFailure(); return }
            }
            let laContext = LAContext()
            var error: NSError?
            laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            guard error == nil else {
                if error!.code == LAError.Code.passcodeNotSet.rawValue {
                    ObvMessengerSettings.Privacy.lockScreen = false
                    setAuthenticationStatus(to: .authenticated)
                    completion?(true)
                    return
                }
                setAuthenticationStatus(to: .authenticationFailed)
                completion?(false)
                return
            }
            assert(Thread.isMainThread)
            delegate?.userWillTryToAuthenticate()
            laContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: Strings.startOlvid) { [weak self] (success, error) in
                DispatchQueue.main.sync {
                    self?.delegate?.userDidTryToAuthenticated()
                    if success {
                        self?.setAuthenticationStatus(to: .authenticated)
                        completion?(true)
                    } else {
                        self?.setAuthenticationStatus(to: .authenticationFailed)
                        completion?(false)
                    }
                }
            }
        }
    }
    
}



private extension LocalAuthenticationViewController {
    
    struct Strings {
        
        static let startOlvid = NSLocalizedString("Please authenticate to start Olvid", comment: "")
        static let authenticate = NSLocalizedString("BUTTON_TITLE_AUTHENTICATE", comment: "")
        
    }
    
}
