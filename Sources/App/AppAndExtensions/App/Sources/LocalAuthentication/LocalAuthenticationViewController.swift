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
import ObvUI
import ObvUICoreData
import ObvSettings


class LocalAuthenticationViewController: UIViewController {
    
    private enum AuthenticationStatus {
        case initial
        case shouldPerformLocalAuthentication
        case authenticated(authenticationWasPerformed: Bool)
        case authenticationFailed
        case lockedOut

        var isLockedOut: Bool {
            switch self {
            case .lockedOut:
                return true
            default:
                return false
            }
        }
    }
    
    private var authenticationStatus = AuthenticationStatus.initial
    private var explanationLabel = UILabel()
    private let authenticateButton = ObvImageButton()
    private var lockoutTimer: Timer?

    private let durationFormatter = DurationFormatter()

    private(set) weak var delegate: LocalAuthenticationViewControllerDelegate?
    private(set) weak var localAuthenticationDelegate: LocalAuthenticationDelegate?

    init(localAuthenticationDelegate: LocalAuthenticationDelegate, delegate: LocalAuthenticationViewControllerDelegate) {
        self.localAuthenticationDelegate = localAuthenticationDelegate
        self.delegate = delegate
        super.init(nibName: nil, bundle: nil)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var canBecomeFirstResponder: Bool { true }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Use the LaunchScreen's view to ensure a smooth transition
        let launchScreenStoryBoard = UIStoryboard(name: "LaunchScreen", bundle: nil)
        guard let launchViewController = launchScreenStoryBoard.instantiateInitialViewController() else { assertionFailure(); return }
        launchViewController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.addSubview(launchViewController.view)
        self.view.pinAllSidesToSides(of: launchViewController.view)

        self.view.addSubview(authenticateButton)
        authenticateButton.translatesAutoresizingMaskIntoConstraints = false
        authenticateButton.addTarget(self, action: #selector(authenticateButtonTapped), for: .touchUpInside)
        authenticateButton.setTitle(Strings.authenticate, for: .normal)

        self.view.addSubview(explanationLabel)
        explanationLabel.translatesAutoresizingMaskIntoConstraints = false
        explanationLabel.text = Strings.lockedOutExplanation
        explanationLabel.textColor = .white
        explanationLabel.font = UIFont.preferredFont(forTextStyle: .callout)
        explanationLabel.numberOfLines = 0
        explanationLabel.textAlignment = .center

        let constraints = [
            authenticateButton.centerXAnchor.constraint(equalTo: self.view.centerXAnchor, constant: 0.0),
            authenticateButton.centerYAnchor.constraint(equalTo: self.view.centerYAnchor, constant: 100.0),
            explanationLabel.centerXAnchor.constraint(equalTo: self.view.centerXAnchor, constant: 0.0),
            explanationLabel.bottomAnchor.constraint(equalTo: authenticateButton.topAnchor, constant: -16.0),
            explanationLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 273),
            authenticateButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 273),
        ]
        NSLayoutConstraint.activate(constraints)

        view.backgroundColor = .red
        
        configure()
    }

    @MainActor
    private func setAuthenticationStatus(to newAuthenticationStatus: AuthenticationStatus) async {
        assert(Thread.isMainThread)
        authenticationStatus = newAuthenticationStatus
        switch authenticationStatus {
        case .initial:
            break
        case .shouldPerformLocalAuthentication:
            break
        case .authenticated(authenticationWasPerformed: let authenticationWasPerformed):
            await delegate?.userLocalAuthenticationDidSucceed(authenticationWasPerformed: authenticationWasPerformed)
            authenticationStatus = .initial
        case .authenticationFailed:
            break
        case .lockedOut:
            await delegate?.tooManyWrongPasscodeAttemptsCausedLockOut()
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
        case .lockedOut:
            authenticateButton.isHidden = false
            authenticateButton.isEnabled = false
        }

        if authenticationStatus.isLockedOut {
            explanationLabel.isHidden = false
            configureLockoutTimer()
            refreshButton()
        } else {
            explanationLabel.isHidden = true
            invalidateLockoutTimer()
            authenticateButton.setTitle(Strings.authenticate, for: .normal)
        }
    }

    private func configureLockoutTimer() {
        guard lockoutTimer == nil else { return }
        lockoutTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(refreshButton), userInfo: nil, repeats: true)
    }

    private func invalidateLockoutTimer() {
        lockoutTimer?.invalidate()
        self.lockoutTimer = nil
    }

    @objc(refreshButton)
    private func refreshButton() {
        guard let localAuthenticationDelegate = self.localAuthenticationDelegate else {
            return
        }
        Task {
            guard await localAuthenticationDelegate.isLockedOut else {
                Task {
                    await setAuthenticationStatus(to: .authenticationFailed)
                }
                return
            }

            guard let remainingLockoutTime = await localAuthenticationDelegate.remainingLockoutTime else {
                return
            }

            if let duration = durationFormatter.string(from: remainingLockoutTime) {
                DispatchQueue.main.async {
                    self.authenticateButton.setTitle(duration, for: .normal)
                }
            }
        }
    }
    
    @objc private func authenticateButtonTapped() {
        Task {
            await performLocalAuthentication(
                customPasscodePresentingViewController: self,
                uptimeAtTheTimeOfChangeoverToNotActiveState: nil)
        }
    }
    
    @MainActor
    func shouldPerformLocalAuthentication() async {
        await setAuthenticationStatus(to: .shouldPerformLocalAuthentication)
    }

    @MainActor
    func performLocalAuthentication(customPasscodePresentingViewController: UIViewController, uptimeAtTheTimeOfChangeoverToNotActiveState: TimeInterval?) async {
        guard let localAuthenticationDelegate = self.localAuthenticationDelegate else {
            assertionFailure()
            return
        }
        let policy = ObvMessengerSettings.Privacy.localAuthenticationPolicy
        let laResult = await localAuthenticationDelegate.performLocalAuthentication(
            customPasscodePresentingViewController: customPasscodePresentingViewController,
            uptimeAtTheTimeOfChangeoverToNotActiveState: uptimeAtTheTimeOfChangeoverToNotActiveState,
            localizedReason: Strings.startOlvid,
            policy: policy)
        switch laResult {
        case .authenticated(let authenticationWasPerformed):
            await setAuthenticationStatus(to: .authenticated(authenticationWasPerformed: authenticationWasPerformed))
        case .cancelled:
            await setAuthenticationStatus(to: .authenticationFailed)
        case .lockedOut:
            await setAuthenticationStatus(to: .lockedOut)
        }
    }
    
}



private extension LocalAuthenticationViewController {
    
    struct Strings {
        
        static let startOlvid = NSLocalizedString("Please authenticate to start Olvid", comment: "")
        static let authenticate = NSLocalizedString("BUTTON_TITLE_AUTHENTICATE", comment: "")
        static let lockedOutExplanation = NSLocalizedString("LOCKED_OUT_EXPLANATION", comment: "")

    }
    
}
