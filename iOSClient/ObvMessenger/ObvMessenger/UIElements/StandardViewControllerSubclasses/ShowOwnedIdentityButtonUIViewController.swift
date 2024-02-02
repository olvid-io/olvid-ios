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
import ObvEngine
import os.log
import ObvTypes
import Combine
import OlvidUtils
import ObvUI
import ObvUICoreData
import UI_ObvCircledInitials


class ShowOwnedIdentityButtonUIViewController: UIViewController, OwnedIdentityChooserViewControllerDelegate {
    
    private(set) var currentOwnedCryptoId: ObvCryptoId
    let log: OSLog
    private let titleLabel = UILabel()
    private var observationTokens = [NSObjectProtocol]()
    private static func makeError(message: String) -> Error { NSError(domain: "ShowOwnedIdentityButtonUIViewController", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private var profilePictureBarButtonItem: ProfilePictureBarButtonItem?
    
    private var viewDidLoadWasCalled = false
    private var barButtonItemToShowInsteadOfProfilePicture: UIBarButtonItem?
    
    init(ownedCryptoId: ObvCryptoId, logCategory: String, barButtonItemToShowInsteadOfProfilePicture: UIBarButtonItem? = nil) {
        self.currentOwnedCryptoId = ownedCryptoId
        self.log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: logCategory)
        self.barButtonItemToShowInsteadOfProfilePicture = barButtonItemToShowInsteadOfProfilePicture
        super.init(nibName: nil, bundle: nil)
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func setTitle(_ title: String?) {
        self.titleLabel.text = title
        self.navigationItem.title = title
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadWasCalled = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 20.0, weight: .heavy)
        titleLabel.text = self.navigationItem.title
        self.navigationItem.titleView = titleLabel
        if let appearance = self.navigationController?.navigationBar.standardAppearance.copy() {
            appearance.configureWithTransparentBackground()
            appearance.shadowColor = .clear
            appearance.backgroundEffect = UIBlurEffect(style: .regular)
            navigationItem.standardAppearance = appearance
        }
        
        if let barButtonItem = barButtonItemToShowInsteadOfProfilePicture {
            self.navigationItem.leftBarButtonItem = barButtonItem
        } else {
            let profilePictureBarButtonItem = ProfilePictureBarButtonItem.makeWithInitialConfiguration(.icon(.person))
            profilePictureBarButtonItem.addTarget(self, action: #selector(ownedCircledInitialsBarButtonItemWasTapped), for: .touchUpInside)
            profilePictureBarButtonItem.setUILongPressGestureRecognizer(target: self, action: #selector(ownedCircledInitialsBarButtonItemWasLongPressed))
            profilePictureBarButtonItem.setUISwipeGestureRecognizer(target: self, action: #selector(ownedCircledInitialsBarButtonItemWasSwiped))
            self.navigationItem.leftBarButtonItem = profilePictureBarButtonItem
            observeChangesOfOwnedCircledInitialsConfiguration()
            if let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: currentOwnedCryptoId, within: ObvStack.shared.viewContext) {
                profilePictureBarButtonItem.configureWith(ownedIdentity.circledInitialsConfiguration)
            } else {
                assertionFailure()
            }
            self.profilePictureBarButtonItem = profilePictureBarButtonItem
        }
        continuouslyUpdateTheRedDotOnTheProfilePictureView()
    }
    
    
    // MARK: - Switching current owned identity
    
    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        self.currentOwnedCryptoId = newOwnedCryptoId
        guard let profilePictureBarButtonItem = navigationItem.leftBarButtonItem as? ProfilePictureBarButtonItem else { return }
        do {
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: newOwnedCryptoId, within: ObvStack.shared.viewContext) else {
                throw Self.makeError(message: "Could not find owned identity in database")
            }
            profilePictureBarButtonItem.configureWith(ownedIdentity.circledInitialsConfiguration)
            updateTheRedDotOnTheProfilePictureView()
        } catch {
            assertionFailure(error.localizedDescription)
            profilePictureBarButtonItem.configureWith(.icon(.person))
            profilePictureBarButtonItem.configureRedDot(isHidden: true)
        }
    }
    
    
    // MARK: - Updating the profile picture view
    
    private func observeChangesOfOwnedCircledInitialsConfiguration() {
        assert(Thread.isMainThread)
        observationTokens.append(ObvMessengerCoreDataNotification.observeOwnedCircledInitialsConfigurationDidChange { [weak self] _, ownedCryptoId, newOwnedCircledInitialsConfiguration in
            DispatchQueue.main.async {
                guard self?.currentOwnedCryptoId == ownedCryptoId else { return }
                guard let profilePictureBarButtonItem = self?.navigationItem.leftBarButtonItem as? ProfilePictureBarButtonItem else { assertionFailure(); return }
                profilePictureBarButtonItem.configureWith(newOwnedCircledInitialsConfiguration)
            }
        })
    }
    
    
    private func continuouslyUpdateTheRedDotOnTheProfilePictureView() {
        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observeBadgeCountForDiscussionsOrInvitationsTabChangedForOwnedIdentity { [weak self] concernedOwnedIdentity in
                // If the number of new messages changed for the current owned identity, no need to updae the red dot
                guard self?.currentOwnedCryptoId != concernedOwnedIdentity else { return }
                self?.updateTheRedDotOnTheProfilePictureView()
            },
            ObvMessengerCoreDataNotification.observePersistedObvOwnedIdentityWasDeleted { [weak self] in
                self?.updateTheRedDotOnTheProfilePictureView()
            },
        ])
        // Do it once now
        updateTheRedDotOnTheProfilePictureView()
    }
    
    
    private func updateTheRedDotOnTheProfilePictureView() {
        let currentOwnedCryptoId = self.currentOwnedCryptoId
        ObvStack.shared.performBackgroundTask { [weak self] context in
            do {
                let redDotShouldShow = try PersistedObvOwnedIdentity.shouldShowRedDotOnTheProfilePictureView(of: currentOwnedCryptoId, within: context)
                DispatchQueue.main.async {
                    guard let profilePictureBarButtonItem = self?.navigationItem.leftBarButtonItem as? ProfilePictureBarButtonItem else { return }
                    profilePictureBarButtonItem.configureRedDot(isHidden: !redDotShouldShow)
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }
    
    
    // MARK: - Handling interaction with profile picture
    
    @objc func ownedCircledInitialsBarButtonItemWasTapped() {
        assert(Thread.isMainThread)
        let ownedIdentities: [PersistedObvOwnedIdentity]
        do {
            let notHiddenOwnedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext)
            if let currentOwnedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: currentOwnedCryptoId, within: ObvStack.shared.viewContext), currentOwnedIdentity.isHidden {
                ownedIdentities = [currentOwnedIdentity] + notHiddenOwnedIdentities
            } else {
                ownedIdentities = notHiddenOwnedIdentities
            }
        } catch {
            os_log("Could not get all owned identities: %{public}@", log: log, type: .fault)
            assertionFailure()
            return
        }
        let ownedIdentityChooserVC = OwnedIdentityChooserViewController(currentOwnedCryptoId: currentOwnedCryptoId, ownedIdentities: ownedIdentities, delegate: self)
        ownedIdentityChooserVC.modalPresentationStyle = .popover
        if let popover = ownedIdentityChooserVC.popoverPresentationController {
            let sheet = popover.adaptiveSheetPresentationController
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16.0
            assert(profilePictureBarButtonItem != nil)
            if #available(iOS 16, *) {
                popover.sourceItem = profilePictureBarButtonItem
            } else {
                popover.barButtonItem = profilePictureBarButtonItem
            }
        }
        ObvMessengerInternalNotification.recomputeRecomputeBadgeCountForDiscussionsTabForAllOwnedIdentities
            .postOnDispatchQueue()
        present(ownedIdentityChooserVC, animated: true)
    }
    
    
    @objc func ownedCircledInitialsBarButtonItemWasLongPressed() {
        assert(Thread.isMainThread)
        showAlertForUnlockingHiddenOwnedIdentity()
    }
    
    
    @objc func ownedCircledInitialsBarButtonItemWasSwiped(gestureRecognizer: UIPanGestureRecognizer) {
        assert(Thread.isMainThread)
        // Determine the appropriate owned identity to show
        let nextOwnedCryptoId: ObvCryptoId
        guard let currentOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: currentOwnedCryptoId, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        guard let nonHiddenOwnedIdentities = try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        if currentOwnedIdentity.isHidden {
            guard let nextOwnedIdentity = nonHiddenOwnedIdentities.first else { assertionFailure(); return }
            nextOwnedCryptoId = nextOwnedIdentity.cryptoId
        } else {
            guard nonHiddenOwnedIdentities.contains(currentOwnedIdentity) else { assertionFailure(); return }
            let list = nonHiddenOwnedIdentities + nonHiddenOwnedIdentities
            guard let index = list.firstIndex(of: currentOwnedIdentity) else { assertionFailure(); return }
            guard index-1 < list.count else { assertionFailure(); return }
            let nextOwnedIdentity = list[index+1]
            nextOwnedCryptoId = nextOwnedIdentity.cryptoId
        }
        
        guard nextOwnedCryptoId != currentOwnedCryptoId else { return }

        profilePictureBarButtonItem?.doAnimateNextCircledInitialsConfigurationChange()
        
        ObvMessengerInternalNotification.userWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: nextOwnedCryptoId)
            .postOnDispatchQueue()
        

    }
    
    
    // MARK: - Unlocking hidden owned identity
    
    private func showAlertForUnlockingHiddenOwnedIdentity() {
        let alert = UIAlertController(title: Strings.OpenHiddenProfileAlert.title,
                                      message: Strings.OpenHiddenProfileAlert.message,
                                      preferredStyle: .alert)
        alert.addTextField { textField in
            textField.passwordRules = UITextInputPasswordRules(descriptor: "minlength: \(ObvMessengerConstants.minimumLengthOfPasswordForHiddenProfiles);")
            textField.text = ""
            textField.isSecureTextEntry = true
            textField.addTarget(self, action: #selector(self.textFieldForUnlockingHiddenProfileDidChange(textField:)), for: .editingChanged)
        }
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
        present(alert, animated: true)
    }
    
    
    @objc final private func textFieldForUnlockingHiddenProfileDidChange(textField: UITextField) {
        guard let presentedAlert = presentedViewController as? UIAlertController else { return }
        guard let presentedTextField = presentedAlert.textFields?.first else { return }
        guard textField == presentedTextField else { return }
        guard let currentText = textField.text, currentText.count >= ObvMessengerConstants.minimumLengthOfPasswordForHiddenProfiles else { return }
        ObvStack.shared.performBackgroundTask { context in
            do {
                guard try PersistedObvOwnedIdentity.passwordCanUnlockSomeHiddenOwnedIdentity(password: currentText, within: context) else { return }
            } catch {
                assertionFailure(error.localizedDescription)
                return
            }
            // If we reach this point, the current text is a proper password for unlocking a hidden owned identity
            DispatchQueue.main.async {
                presentedAlert.dismiss(animated: true)
                ObvMessengerInternalNotification.userWantsToSwitchToOtherHiddenOwnedIdentity(password: currentText)
                    .postOnDispatchQueue()
            }
        }
    }
    
}


// MARK: - OwnedIdentityChooserViewControllerDelegate

extension ShowOwnedIdentityButtonUIViewController {
    
    @MainActor func userUsedTheOwnedIdentityChooserViewControllerToChoose(ownedCryptoId: ObvCryptoId) async {
        if currentOwnedCryptoId == ownedCryptoId {
            await userWantsToEditCurrentOwnedIdentity(ownedCryptoId: ownedCryptoId)
        } else {
            ObvMessengerInternalNotification.userWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: ownedCryptoId)
                .postOnDispatchQueue()
        }
    }
    
    
    @MainActor func userWantsToEditCurrentOwnedIdentity(ownedCryptoId: ObvCryptoId) async {
        guard currentOwnedCryptoId == ownedCryptoId else { assertionFailure(); return }
        let deepLink = ObvDeepLink.myId(ownedCryptoId: currentOwnedCryptoId)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }

    
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityDeletion: Bool {
        true
    }
    
    
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityEdition: Bool {
        true
    }
    
    
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityCreation: Bool {
        true
    }

    
    var ownedIdentityChooserViewControllerExplanationString: String? {
        return nil
    }

}


// MARK: Strings

extension ShowOwnedIdentityButtonUIViewController {
    struct Strings {
        struct OpenHiddenProfileAlert {
            static let title = NSLocalizedString("OPEN_HIDDEN_PROFILE_ALERT_TITLE", comment: "")
            static let message = NSLocalizedString("OPEN_HIDDEN_PROFILE_ALERT_MESSAGE", comment: "")
        }
    }
}



// MARK: - ProfilePictureBarButtonItem


fileprivate class ProfilePictureBarButtonItem: UIBarButtonItem {

    private var profilePictureView: NewCircledInitialsView?
    private var profilePictureViewsContainer: UIView?
    private var buttonView: UIButton?
    private var longPressGestureRecognizer: UILongPressGestureRecognizer?
    private var swipeGestureRecognizer: UISwipeGestureRecognizer?
    private var redDotView: DotView?
    private var animateNextCircledInitialsConfigurationChange = false
    private let generator = UINotificationFeedbackGenerator()

    
    static func makeWithInitialConfiguration(_ initialConfiguration: CircledInitialsConfiguration) -> ProfilePictureBarButtonItem {
        
        let buttonView = UIButton()
        buttonView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            buttonView.widthAnchor.constraint(equalTo: buttonView.heightAnchor),
        ])
        
        let profilePictureViewsContainer = UIView()
        profilePictureViewsContainer.translatesAutoresizingMaskIntoConstraints = false
        profilePictureViewsContainer.isUserInteractionEnabled = false
        profilePictureViewsContainer.clipsToBounds = true
        buttonView.addSubview(profilePictureViewsContainer)
        
        let profilePictureView = NewCircledInitialsView()
        profilePictureView.translatesAutoresizingMaskIntoConstraints = false
        profilePictureView.isUserInteractionEnabled = false
        profilePictureViewsContainer.addSubview(profilePictureView)
        
        let redDotView = DotView()
        redDotView.translatesAutoresizingMaskIntoConstraints = false
        redDotView.isHidden = true
        redDotView.isUserInteractionEnabled = false
        buttonView.addSubview(redDotView)
        
        NSLayoutConstraint.activate([
            profilePictureViewsContainer.centerXAnchor.constraint(equalTo: buttonView.centerXAnchor),
            profilePictureViewsContainer.centerYAnchor.constraint(equalTo: buttonView.centerYAnchor),
            profilePictureViewsContainer.heightAnchor.constraint(equalTo: profilePictureViewsContainer.widthAnchor),
            profilePictureViewsContainer.heightAnchor.constraint(equalTo: buttonView.heightAnchor, multiplier: 0.8),

            profilePictureView.centerXAnchor.constraint(equalTo: profilePictureViewsContainer.centerXAnchor),
            profilePictureView.centerYAnchor.constraint(equalTo: profilePictureViewsContainer.centerYAnchor),
            profilePictureView.heightAnchor.constraint(equalTo: profilePictureViewsContainer.heightAnchor),
            
            redDotView.widthAnchor.constraint(equalTo: redDotView.heightAnchor),
            redDotView.widthAnchor.constraint(equalTo: buttonView.widthAnchor, multiplier: 0.25),
            redDotView.trailingAnchor.constraint(equalTo: buttonView.trailingAnchor, constant: -4),
            redDotView.topAnchor.constraint(equalTo: buttonView.topAnchor, constant: 4),
        ])
        
        profilePictureView.configure(with: initialConfiguration)
        let buttonItem = ProfilePictureBarButtonItem(customView: buttonView)
        buttonItem.profilePictureView = profilePictureView
        buttonItem.buttonView = buttonView
        buttonItem.redDotView = redDotView
        return buttonItem
    }
    
    
    func configureWith(_ configuration: CircledInitialsConfiguration) {
        guard let profilePictureView else { assertionFailure(); return }
        defer { animateNextCircledInitialsConfigurationChange = false }
        
        if animateNextCircledInitialsConfigurationChange, let currentConfiguration = profilePictureView.currentConfiguration, let superview = profilePictureView.superview {
            // We create a temporary NewCircledInitialsView for the animation (we will slide it down)
            let tempProfilePictureView = NewCircledInitialsView()
            tempProfilePictureView.isUserInteractionEnabled = false
            tempProfilePictureView.configure(with: currentConfiguration)
            superview.addSubview(tempProfilePictureView)
            tempProfilePictureView.frame = profilePictureView.frame
            
            // Now that the temporary NewCircledInitialsView hides the profilePictureView, we can scale it down and configure it with the new received configuration
            profilePictureView.transform = .init(scaleX: 0, y: 0)
            profilePictureView.configure(with: configuration)
            
            // We launch two animations in parallel:
            // - the first slides the temporary NewCircledInitialsView and removes it at the end
            // - the second scales back the profilePictureView (after a short delay)
            let typicalAnimationTime: TimeInterval = 0.2
            UIView.animate(withDuration: typicalAnimationTime, delay: 0, animations: {
                tempProfilePictureView.center = CGPoint(x: tempProfilePictureView.center.x, y: tempProfilePictureView.center.y + tempProfilePictureView.frame.height * 1.1)
            }) { _ in
                tempProfilePictureView.removeFromSuperview()
            }
            UIView.animate(withDuration: typicalAnimationTime, delay: typicalAnimationTime/2, animations: { [weak self] in
                profilePictureView.transform = .init(scaleX: 1, y: 1)
                self?.generator.notificationOccurred(.success)
            })
        } else {
            profilePictureView.configure(with: configuration)
        }
    }
    
    
    func doAnimateNextCircledInitialsConfigurationChange() {
        animateNextCircledInitialsConfigurationChange = true
    }
    
    
    func configureRedDot(isHidden: Bool) {
        assert(redDotView != nil)
        redDotView?.isHidden = isHidden
    }
    
    
    func addTarget(_ target: Any?, action: Selector, for controlEvents: UIControl.Event) {
        guard let buttonView else { assertionFailure(); return }
        buttonView.addTarget(target, action: action, for: controlEvents)
    }
    
    
    func setUILongPressGestureRecognizer(target: Any?, action: Selector?) {
        guard let buttonView else { assertionFailure(); return }
        assert(Thread.isMainThread)
        if let longPressGestureRecognizer {
            buttonView.removeGestureRecognizer(longPressGestureRecognizer)
        }
        longPressGestureRecognizer = nil
        longPressGestureRecognizer = UILongPressGestureRecognizer(target: target, action: action)
        buttonView.addGestureRecognizer(longPressGestureRecognizer!)
    }
    
    
    func setUISwipeGestureRecognizer(target: Any?, action: Selector?) {
        guard let buttonView else { assertionFailure(); return }
        assert(Thread.isMainThread)
        if let swipeGestureRecognizer {
            buttonView.removeGestureRecognizer(swipeGestureRecognizer)
        }
        swipeGestureRecognizer = nil
        swipeGestureRecognizer = UISwipeGestureRecognizer(target: target, action: action)
        swipeGestureRecognizer?.direction = .down
        buttonView.addGestureRecognizer(swipeGestureRecognizer!)
    }
        
}


fileprivate final class DotView: UIView {
    
    private let redView = UIView()
    private let padding = CGFloat(4.0)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.addSubview(redView)
        redView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            self.centerXAnchor.constraint(equalTo: redView.centerXAnchor),
            self.centerYAnchor.constraint(equalTo: redView.centerYAnchor),
            self.widthAnchor.constraint(equalTo: redView.widthAnchor, constant: padding),
            self.heightAnchor.constraint(equalTo: redView.heightAnchor, constant: padding),
        ])
        redView.backgroundColor = .systemRed
        self.backgroundColor = .systemBackground
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = min(bounds.width, bounds.height) / 2.0
        redView.layer.cornerRadius = min(bounds.width - padding, bounds.height - padding) / 2.0
    }
}
