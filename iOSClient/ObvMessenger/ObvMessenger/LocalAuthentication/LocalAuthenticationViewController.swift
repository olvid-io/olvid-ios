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


class LocalAuthenticationViewController: UIViewController {

    private enum AuthenticationStatus {
        case initial
        case shouldPerformLocalAuthentication
        case authenticated
        case authenticationFailed
        case lockedOut

        var isLockedOut: Bool {
            self == .lockedOut
        }
    }
    
    private var authenticationStatus = AuthenticationStatus.initial
    private var observationTokens = [NSObjectProtocol]()
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

    override func viewDidLoad() {
        super.viewDidLoad()
        // Use the LaunchScreen's view to ensure a smooth transition
        let launchScreenStoryBoard = UIStoryboard(name: "LaunchScreen", bundle: nil)
        guard let launchViewController = launchScreenStoryBoard.instantiateInitialViewController() else { assertionFailure(); return }
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

        configure()
    }

    private func setAuthenticationStatus(to newAuthenticationStatus: AuthenticationStatus) {
        assert(Thread.isMainThread)
        authenticationStatus = newAuthenticationStatus
        switch authenticationStatus {
        case .initial:
            break
        case .shouldPerformLocalAuthentication:
            break
        case .authenticated:
            delegate?.userLocalAuthenticationDidSucceedOrWasNotRequired()
            authenticationStatus = .initial
        case .authenticationFailed:
            break
        case .lockedOut:
            delegate?.tooManyWrongPasscodeAttemptsCausedLockOut()
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
                DispatchQueue.main.async {
                    self.setAuthenticationStatus(to: .authenticationFailed)
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
    
    @MainActor
    @objc func authenticateButtonTapped() {
        performLocalAuthentication()
    }
    
    @MainActor
    func shouldPerformLocalAuthentication() {
        setAuthenticationStatus(to: .shouldPerformLocalAuthentication)
    }

    @MainActor
    func performLocalAuthentication() {
        guard let localAuthenticationDelegate = self.localAuthenticationDelegate else {
            assertionFailure()
            return
        }
        Task {
            let laResult = await localAuthenticationDelegate.performLocalAuthentication(viewController: self, localizedReason: Strings.startOlvid)
            DispatchQueue.main.async { [ weak self] in
                switch laResult {
                case .authenticated:
                    self?.setAuthenticationStatus(to: .authenticated)
                case .cancelled:
                    self?.setAuthenticationStatus(to: .authenticationFailed)
                case .lockedOut:
                    self?.setAuthenticationStatus(to: .lockedOut)
                }
            }
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
