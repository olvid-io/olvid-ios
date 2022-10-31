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
import CoreData
import ObvEngine
import ObvCrypto
import ObvTypes
import SwiftUI
import AVFAudio

@MainActor
final class MetaFlowController: UIViewController, OlvidURLHandler {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MetaFlowController.self))

    var observationTokens = [NSObjectProtocol]()
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }
    
    private let queueForSynchronizingFyleCreation = DispatchQueue(label: "queueForSynchronizingFyleCreation")
    
    private static let errorDomain = "MetaFlowController"
    private func makeError(message: String) -> Error { NSError(domain: MetaFlowController.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // Coordinators and Services
    
    private var mainFlowViewController: MainFlowViewController?
    private var onboardingFlowViewController: OnboardingFlowViewController?

    private weak var createPasscodeDelegate: CreatePasscodeDelegate?

    private let callBannerView = CallBannerView()
    private let viewOnTopOfCallBannerView = UIView()
    
    private var mainFlowViewControllerConstraintsWithoutCallBannerView = [NSLayoutConstraint]()
    private var mainFlowViewControllerConstraintsWithCallBannerView = [NSLayoutConstraint]()

    private var currentOwnedCryptoId: ObvCryptoId? = nil
    
    private var viewDidLoadWasCalled = false

    private var viewDidAppearWasCalled = false
    private var completionHandlersToCallOnViewDidAppear = [() -> Void]()

    // Shall only be accessed on the main thread
    private var automaticallyNavigateToCreatedDisplayedContactGroup = false
    
    private let obvEngine: ObvEngine
    
    init(obvEngine: ObvEngine, createPasscodeDelegate: CreatePasscodeDelegate) {
        
        self.obvEngine = obvEngine
        self.createPasscodeDelegate = createPasscodeDelegate
        
        super.init(nibName: nil, bundle: nil)
        
        // Internal notifications
        
        observeUserWantsToRefreshDiscussionsNotifications()
        observeUserTriedToAccessCameraButAccessIsDeniedNotifications()
        observeUserWantsToDeleteOwnedContactGroupNotifications()
        observeUserWantsToLeaveJoinedContactGroupNotifications()
        observeUserWantsToIntroduceContactToAnotherContactNotifications()
        observeOutgoingCallFailedBecauseUserDeniedRecordPermissionNotifications()
        observeVoiceMessageFailedBecauseUserDeniedRecordPermissionNotifications()
        observeRejectedIncomingCallBecauseUserDeniedRecordPermissionNotifications()
        observePastedStringIsNotValidOlvidURLNotifications()
        observeUserDidTapOnMissedMessageBubbleNotifications()
        observeUserWantsToNavigateToDeepLinkNotifications()
        observeRequestUserDeniedRecordPermissionAlertNotifications()
        observeInstalledOlvidAppIsOutdatedNotification()

        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserOwnedIdentityWasRevokedByKeycloak(queue: OperationQueue.main) { [weak self] ownedCryptoId in
                self?.processUserOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ownedCryptoId)
            },
        ])
        
        // Listening to ObvEngine Notification
        
        observationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeWellKnownDownloadedSuccess(within: NotificationCenter.default) { [weak self] _, appInfo in
                self?.processWellKnownAppInfo(appInfo)
            },
            ObvEngineNotificationNew.observeWellKnownUpdatedSuccess(within: NotificationCenter.default) { [weak self] _, appInfo in
                self?.processWellKnownAppInfo(appInfo)
            },
        ])
        
        // App notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserWantsToRestartChannelEstablishmentProtocol { [weak self] (contactCryptoId, ownedCryptoId) in
                self?.processUserWantsToRestartChannelEstablishmentProtocol(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToReCreateChannelEstablishmentProtocol() { [weak self] (contactCryptoId, ownedCryptoId) in
                self?.processUserWantsToReCreateChannelEstablishmentProtocol(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToCreateNewGroupV1(queue: OperationQueue.main) { [weak self] (groupName, groupDescription, groupMembersCryptoIds, ownedCryptoId, photoURL) in
                self?.processUserWantsToCreateNewGroupV1(groupName: groupName, groupDescription: groupDescription, groupMembersCryptoIds: groupMembersCryptoIds, ownedCryptoId: ownedCryptoId, photoURL: photoURL)
            },
            ObvMessengerInternalNotification.observeUserWantsToCreateNewGroupV2(queue: OperationQueue.main) { [weak self] (groupCoreDetails, ownPermissions, otherGroupMembers, ownedCryptoId, photoURL) in
                self?.processUserWantsToCreateNewGroupV2(groupCoreDetails: groupCoreDetails, ownPermissions: ownPermissions, otherGroupMembers: otherGroupMembers, ownedCryptoId: ownedCryptoId, photoURL: photoURL)
            },
            ObvMessengerGroupV2Notifications.observeDisplayedContactGroupWasJustCreated(queue: OperationQueue.main) { [weak self] objectID in
                self?.processDisplayedContactGroupWasJustCreated(objectID: objectID)
            },
        ])
        
        // VoIP notifications
        
        observationTokens.append(contentsOf: [
            VoIPNotification.observeShowCallViewControllerForAnsweringNonCallKitIncomingCall(queue: .main) { [weak self] _ in
                self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: true)
            },
            VoIPNotification.observeNewOutgoingCall(queue: .main) { [weak self] _ in
                self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: true)
            },
            VoIPNotification.observeAnIncomingCallShouldBeShownToUser(queue: .main) { [weak self] _ in
                self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: true)
            },
            VoIPNotification.observeNoMoreCallInProgress(queue: .main) { [weak self] in
                self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: false)
            }
        ])

                
    }
    
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    private struct AppInfoKey {
        static let minimumAppVersion = "min_ios"
        static let latestAppVersion = "latest_ios"
    }
    
    private func processWellKnownAppInfo(_ appInfo: [String: AppInfo]) {
        switch appInfo[AppInfoKey.minimumAppVersion] {
        case .int(let version):
            ObvMessengerSettings.AppVersionAvailable.minimum = version
        default:
            assertionFailure()
        }
        switch appInfo[AppInfoKey.latestAppVersion] {
        case .int(let version):
            ObvMessengerSettings.AppVersionAvailable.latest = version
        default:
            assertionFailure()
        }
        os_log("Minimum recommended app build version from server: %{public}@", log: log, type: .info, String(describing: ObvMessengerSettings.AppVersionAvailable.minimum))
        os_log("Latest recommended app build version from server: %{public}@", log: log, type: .info, String(describing: ObvMessengerSettings.AppVersionAvailable.latest))
        os_log("Installed app build version: %{public}@", log: log, type: .info, ObvMessengerConstants.bundleVersion)
    }

    private func observePastedStringIsNotValidOlvidURLNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observePastedStringIsNotValidOlvidURL(queue: OperationQueue.main) { [weak self] in
            self?.showAlertWhenPastedStringIsNotValidOlvidURL()
        })
    }
    
    private func observeOutgoingCallFailedBecauseUserDeniedRecordPermissionNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeOutgoingCallFailedBecauseUserDeniedRecordPermission(queue: OperationQueue.main) { [weak self] in
            self?.presentUserDeniedRecordPermissionAlert(message: Strings.AlertOutgoingCallFailedBecauseUserDeniedRecordPermission.message)
        })
    }

    private func observeVoiceMessageFailedBecauseUserDeniedRecordPermissionNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeVoiceMessageFailedBecauseUserDeniedRecordPermission(queue: OperationQueue.main) { [weak self] in
            self?.presentUserDeniedRecordPermissionAlert(message: Strings.AlertVoiceMessageFailedBecauseUserDeniedRecordPermission.message)
        })
    }

    
    private func observeRejectedIncomingCallBecauseUserDeniedRecordPermissionNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeRejectedIncomingCallBecauseUserDeniedRecordPermission(queue: OperationQueue.main) { [weak self] in
            self?.presentUserDeniedRecordPermissionAlert(message: Strings.AlertRejectedIncomingCallBecauseUserDeniedRecordPermission.message)
        })
    }
    
    
    private func observeRequestUserDeniedRecordPermissionAlertNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeRequestUserDeniedRecordPermissionAlert(queue: OperationQueue.main) { [weak self] in
            self?.presentUserDeniedRecordPermissionAlert(message: Strings.AlertRejectedIncomingCallBecauseUserDeniedRecordPermission.message)
        })
    }
    
    
    private func observeUserDidTapOnMissedMessageBubbleNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserDidTapOnMissedMessageBubble(queue: OperationQueue.main) { [weak self] in
            let alert = UIAlertController(title: NSLocalizedString("DIALOG_MISSING_MESSAGES_TITLE", comment: ""),
                                          message: NSLocalizedString("DIALOG_MISSING_MESSAGES_MESSAGE", comment: ""),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .cancel, handler: nil))
            self?.present(alert, animated: true)
        })
    }
    
    
    private func processUserOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ObvCryptoId) {
        assert(Thread.isMainThread)
        let alert = UIAlertController(title: NSLocalizedString("DIALOG_OWNED_IDENTITY_WAS_REVOKED_BY_KEYCLOAK_TITLE", comment: ""),
                                      message: NSLocalizedString("DIALOG_OWNED_IDENTITY_WAS_REVOKED_BY_KEYCLOAK_MESSAGE", comment: ""),
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .cancel, handler: nil))
        self.present(alert, animated: true)
    }
    
    
    private func observeInstalledOlvidAppIsOutdatedNotification() {
        observationTokens.append(ObvMessengerInternalNotification.observeInstalledOlvidAppIsOutdated(queue: OperationQueue.main) { [weak self] presentingViewController in
            let menu = UIAlertController(
                title: Strings.AppDialogOutdatedAppVersion.title,
                message: Strings.AppDialogOutdatedAppVersion.message,
                preferredStyle: UIDevice.current.actionSheetIfPhoneAndAlertOtherwise)
            let updateAction = UIAlertAction(title: Strings.AppDialogOutdatedAppVersion.positiveButtonTitle, style: .default) { _ in
                guard UIApplication.shared.canOpenURL(ObvMessengerConstants.shortLinkToOlvidAppIniTunes) else { assertionFailure(); return }
                UIApplication.shared.open(ObvMessengerConstants.shortLinkToOlvidAppIniTunes, options: [:], completionHandler: nil)
            }
            let laterAction = UIAlertAction(title: Strings.AppDialogOutdatedAppVersion.negativeButtonTitle, style: .cancel)
            menu.addAction(updateAction)
            menu.addAction(laterAction)
            guard let presentingViewController: UIViewController = presentingViewController ?? self else { return }
            presentingViewController.present(menu, animated: true)
        })
    }

    
    private func presentUserDeniedRecordPermissionAlert(message: String) {
        assert(Thread.isMainThread)
        guard AVAudioSession.sharedInstance().recordPermission != .granted else { return }
        let alert = UIAlertController(title: nil,
                                      message: message,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel, handler: nil))
        if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            alert.addAction(UIAlertAction(title: Strings.goToSettingsButtonTitle, style: .default, handler: { (_) in
                UIApplication.shared.open(appSettings, options: [:])
            }))
        }
        if let presentedViewController = presentedViewController {
            presentedViewController.present(alert, animated: true)
        } else {
            present(alert, animated: true)
        }
    }

    
    private func observeUserWantsToNavigateToDeepLinkNotifications() {
        let log = self.log
        os_log("🥏🏁 We observe UserWantsToNavigateToDeepLink notifications", log: log, type: .info)
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToNavigateToDeepLink(queue: OperationQueue.main) { [weak self] (deepLink) in
            os_log("🥏🏁 We received a UserWantsToNavigateToDeepLink notification", log: log, type: .info)
            guard let _self = self else { return }
            let toExecuteAfterViewDidAppear = { [weak self] in
                guard let _self = self else { return }
                VoIPNotification.hideCallView.postOnDispatchQueue()
                assert(_self.mainFlowViewController != nil)
                _self.mainFlowViewController?.performCurrentDeepLinkInitialNavigation(deepLink: deepLink)
            }
            if _self.viewDidAppearWasCalled {
                toExecuteAfterViewDidAppear()
            } else {
                _self.completionHandlersToCallOnViewDidAppear.append(toExecuteAfterViewDidAppear)
            }
        })
    }

}


// MARK: - Implementing MetaFlowDelegate

extension MetaFlowController: OnboardingFlowViewControllerDelegate {
            
    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadWasCalled = true
        
        self.view.addSubview(callBannerView)
        callBannerView.translatesAutoresizingMaskIntoConstraints = false
        callBannerView.isHidden = true
        
        self.view.addSubview(viewOnTopOfCallBannerView)
        viewOnTopOfCallBannerView.translatesAutoresizingMaskIntoConstraints = false
        viewOnTopOfCallBannerView.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        viewOnTopOfCallBannerView.isHidden = true
        
        do {
            try setupAndShowAppropriateChildViewControllers()
        } catch {
            os_log("Could not determine which child view controller to show", log: log, type: .fault)
            assertionFailure()
            return
        }
        
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // We send the metaFlowControllerViewDidAppear notification here.
        // This notification is fundamental as it eventually triggers many bootstrap methods waiting for this view controller to appear.
        // We need to register to the UIApplication.didBecomeActiveNotification so as to send the metaFlowControllerViewDidAppear when the app is launched while it still was in the background since, in that case, the viewDidAppear method is not called.
        observationTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard self?.viewDidAppearWasCalled == true else { return }
            ObvMessengerInternalNotification.metaFlowControllerViewDidAppear
                .postOnDispatchQueue()
        })
        ObvMessengerInternalNotification.metaFlowControllerViewDidAppear
            .postOnDispatchQueue()
        
        viewDidAppearWasCalled = true
        
        while let completion = completionHandlersToCallOnViewDidAppear.popLast() {
            completion()
        }
        
    }
    
    
    /// Called by the SceneDelegate
    @MainActor
    func sceneDidBecomeActive(_ scene: UIScene) {
        assert(viewDidAppearWasCalled)
        mainFlowViewController?.sceneDidBecomeActive(scene)
    }
    
    
    /// Called by the SceneDelegate
    @MainActor
    func sceneWillResignActive(_ scene: UIScene) {
        assert(viewDidAppearWasCalled)
        mainFlowViewController?.sceneWillResignActive(scene)
    }
    
    
    func onboardingIsFinished(olvidURLScannedDuringOnboarding: OlvidURL?) {
        let log = self.log
        do {
            try setupAndShowAppropriateChildViewControllers() { result in
                assert(Thread.isMainThread)
                switch result {
                case .failure(let error):
                    assertionFailure(error.localizedDescription)
                case .success:
                    os_log("Did setup and show the appropriate child view controller", log: log, type: .info)
                }
                // In all cases, we handle the OlvidURL scanned during the onboarding
                if let olvidURL = olvidURLScannedDuringOnboarding {
                    Task { await NewAppStateManager.shared.handleOlvidURL(olvidURL) }
                }
            }
        } catch {
            assertionFailure()
        }
    }


    @MainActor
    private func setupAndShowAppropriateCallBanner(shouldShowCallBanner: Bool) {
        assert(Thread.isMainThread)
        guard viewDidLoadWasCalled else { return }
        
        if shouldShowCallBanner {
            
            setupMainFlowViewControllerConstraintsWithCallBannerViewIfNecessary()
            NSLayoutConstraint.deactivate(mainFlowViewControllerConstraintsWithoutCallBannerView)
            NSLayoutConstraint.activate(mainFlowViewControllerConstraintsWithCallBannerView)
            callBannerView.isHidden = false
            
        } else {

            setupMainFlowViewControllerConstraintsWithoutCallBannerViewIfNecessary()
            NSLayoutConstraint.deactivate(mainFlowViewControllerConstraintsWithCallBannerView)
            NSLayoutConstraint.activate(mainFlowViewControllerConstraintsWithoutCallBannerView)
            callBannerView.isHidden = true

        }
        
        view.setNeedsUpdateConstraints()
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.view.layoutIfNeeded()
        }

    }
    
    
    @MainActor
    private func setupAndShowAppropriateChildViewControllers(completion: (@MainActor (Result<Void,Error>) -> Void)? = nil) throws {
        
        assert(viewDidLoadWasCalled)
        
        let internalCompletion = { (result: Result<Void,Error>) -> Void in
            Task { [weak self] in
                assert(Thread.isMainThread)
                guard let _self = self else { return }
                if await NewAppStateManager.shared.olvidURLHandler == nil {
                    await NewAppStateManager.shared.setOlvidURLHandler(to: _self)
                }
                completion?(result)
            }
        }
        
        let ownedIdentities = try obvEngine.getOwnedIdentities()
        
        if let ownedIdentity = ownedIdentities.first {
            
            currentOwnedCryptoId = ownedIdentity.cryptoId

            if mainFlowViewController == nil {
                guard let createPasscodeDelegate = self.createPasscodeDelegate else {
                    assertionFailure(); return
                }
                mainFlowViewController = MainFlowViewController(ownedCryptoId: ownedIdentity.cryptoId, obvEngine: obvEngine, createPasscodeDelegate: createPasscodeDelegate)
            }

            guard let mainFlowViewController = mainFlowViewController else {
                assertionFailure()
                internalCompletion(.failure(makeError(message: "No main flow view controller")))
                return
            }
            
            if let currentFirstChild = children.first {
                            
                guard currentFirstChild != mainFlowViewController else {
                    internalCompletion(.failure(makeError(message: "First child is not the main flow view controller")))
                    return
                }
                
                // The current first child view controller is not the mainFlowViewController.
                // We will transition to it.
                
                if currentFirstChild == onboardingFlowViewController {
                    mainFlowViewController.anOwnedIdentityWasJustCreatedOrRestored = true
                }
                
                if mainFlowViewController.parent == nil {
                    addChild(mainFlowViewController)
                }
                                
                transition(from: currentFirstChild, to: mainFlowViewController, duration: 0.9, options: [.transitionFlipFromLeft]) { [weak self] in
                    // Animation block
                    guard let _self = self else { return }
                    _self.setupMainFlowViewControllerConstraintsWithoutCallBannerViewIfNecessary()
                    NSLayoutConstraint.activate(_self.mainFlowViewControllerConstraintsWithoutCallBannerView)
                    _self.callBannerView.isHidden = true
                } completion: { _ in
                    currentFirstChild.view.removeFromSuperview()
                    currentFirstChild.removeFromParent() // Automatic call to didMove(...) ?
                    mainFlowViewController.didMove(toParent: self)
                    internalCompletion(.success(()))
                }
                         
            } else {
                
                // This view controller has no child view controller.
                // We set this first child to the mainFlowViewController
                
                addChild(mainFlowViewController) // automatically calls willMove(toParent: self)
                mainFlowViewController.didMove(toParent: self)
                
                view.addSubview(mainFlowViewController.view)
                mainFlowViewController.view.translatesAutoresizingMaskIntoConstraints = false
                setupMainFlowViewControllerConstraintsWithoutCallBannerViewIfNecessary()
                NSLayoutConstraint.activate(mainFlowViewControllerConstraintsWithoutCallBannerView)
                callBannerView.isHidden = true
                
                internalCompletion(.success(()))

            }
            
        } else {

            if onboardingFlowViewController == nil {
                onboardingFlowViewController = OnboardingFlowViewController(obvEngine: obvEngine)
                onboardingFlowViewController?.delegate = self
            }
            
            guard let onboardingFlowViewController = onboardingFlowViewController else {
                assertionFailure()
                internalCompletion(.failure(makeError(message: "No onboarding flow view controller")))
                return
            }

            if let currentFirstChild = children.first {
                
                assert(currentFirstChild == onboardingFlowViewController)
                internalCompletion(.success(()))
                
            } else {
                
                // This view controller has no child view controller.
                // We set this first child to the onboardingFlowViewController

                addChild(onboardingFlowViewController)
                onboardingFlowViewController.didMove(toParent: self)
                
                view.addSubview(onboardingFlowViewController.view)
                onboardingFlowViewController.view.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    onboardingFlowViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
                    onboardingFlowViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                    onboardingFlowViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                    onboardingFlowViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                ])

                internalCompletion(.success(()))
                
            }

        }

    }
    
    
    @MainActor
    private func setupMainFlowViewControllerConstraintsWithoutCallBannerViewIfNecessary() {
        guard let mainFlowViewController = self.mainFlowViewController else { return }
        guard mainFlowViewControllerConstraintsWithoutCallBannerView.isEmpty else { return }
        mainFlowViewControllerConstraintsWithoutCallBannerView = [
            mainFlowViewController.view.topAnchor.constraint(equalTo: view.topAnchor),
            mainFlowViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainFlowViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainFlowViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ]
    }
    
    
    private func setupMainFlowViewControllerConstraintsWithCallBannerViewIfNecessary() {
        assert(Thread.isMainThread)
        guard let mainFlowViewController = self.mainFlowViewController else { assertionFailure(); return }
        guard mainFlowViewControllerConstraintsWithCallBannerView.isEmpty else { return }
        mainFlowViewControllerConstraintsWithCallBannerView = [
            viewOnTopOfCallBannerView.topAnchor.constraint(equalTo: view.topAnchor),
            viewOnTopOfCallBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            viewOnTopOfCallBannerView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            viewOnTopOfCallBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            callBannerView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            callBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            callBannerView.bottomAnchor.constraint(equalTo: mainFlowViewController.view.topAnchor),
            callBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainFlowViewController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mainFlowViewController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainFlowViewController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        ]
    }
    
}

// MARK: - Feeding the contact database

extension MetaFlowController {
    
    
    private func observeUserWantsToDeleteOwnedContactGroupNotifications() {
        let NotificationType = MessengerInternalNotification.UserWantsToDeleteOwnedContactGroup.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
            guard let (groupUid, ownedCryptoId) = NotificationType.parse(notification) else { return }
            guard self?.currentOwnedCryptoId == ownedCryptoId else { return }
            self?.deleteOwnedContactGroup(groupUid: groupUid, ownedCryptoId: ownedCryptoId, confirmed: false)
        }
        observationTokens.append(token)
    }

    
    private func deleteOwnedContactGroup(groupUid: UID, ownedCryptoId: ObvCryptoId, confirmed: Bool) {
        
        if confirmed {

            do {
                try obvEngine.deleteOwnedContactGroup(ownedCryptoId: ownedCryptoId, groupUid: groupUid)
            } catch {
                // We could not delete the group owned. For now, we just display an alert indicating that a non-empty owned group cannot be deleted

                let uiAlert = UIAlertController(title: Strings.AlertDeleteOwnedGroupFailed.title, message: Strings.AlertDeleteOwnedGroupFailed.message, preferredStyle: .alert)
                let okAction = UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: nil)
                uiAlert.addAction(okAction)
                
                if let presentedViewController = presentedViewController {
                    presentedViewController.present(uiAlert, animated: true)
                } else {
                    present(uiAlert, animated: true)
                }
                
            }
            
        } else {
            
            let alert = UIAlertController(title: CommonString.Title.deleteGroup,
                                          message: Strings.deleteGroupExplanation,
                                          preferredStyleForTraitCollection: self.traitCollection)
            alert.addAction(UIAlertAction(title: CommonString.AlertButton.performDeletionAction, style: .destructive, handler: { [weak self] (action) in
                self?.deleteOwnedContactGroup(groupUid: groupUid, ownedCryptoId: ownedCryptoId, confirmed: true)
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            
            if let presentedViewController = presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                present(alert, animated: true)
            }
            
        }
        
    }
    
    
    private func observeUserWantsToLeaveJoinedContactGroupNotifications() {
        let NotificationType = MessengerInternalNotification.UserWantsToLeaveJoinedContactGroup.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let (groupOwner, groupUid, ownedCryptoId, sourceView) = NotificationType.parse(notification) else { return }
            guard _self.currentOwnedCryptoId == ownedCryptoId else { return }
            _self.leaveJoinedContactGroup(groupOwner: groupOwner, groupUid: groupUid, ownedCryptoId: ownedCryptoId, sourceView: sourceView, confirmed: false)
        }
        observationTokens.append(token)
    }

    
    private func leaveJoinedContactGroup(groupOwner: ObvCryptoId, groupUid: UID, ownedCryptoId: ObvCryptoId, sourceView: UIView, confirmed: Bool) {
        
        if confirmed {
            
            let log = self.log
            DispatchQueue(label: "Background queue for requesting leaveContactGroupJoined to engine").async { [weak self] in
                do {
                    try self?.obvEngine.leaveContactGroupJoined(ownedCryptoId: ownedCryptoId, groupUid: groupUid, groupOwner: groupOwner)
                } catch {
                    os_log("Could not leave contact group joined", log: log, type: .error)
                }
            }

        } else {
            let alert = UIAlertController(title: CommonString.Title.leaveGroup,
                                          message: Strings.leaveGroupExplanation,
                                          preferredStyleForTraitCollection: self.traitCollection)
            alert.addAction(UIAlertAction(title: CommonString.Title.leaveGroup, style: .destructive, handler: { [weak self] (action) in
                if let presentedViewController = self?.presentedViewController {
                    presentedViewController.dismiss(animated: true, completion: {
                        self?.leaveJoinedContactGroup(groupOwner: groupOwner, groupUid: groupUid, ownedCryptoId: ownedCryptoId, sourceView: sourceView, confirmed: true)
                    })
                } else {
                    self?.leaveJoinedContactGroup(groupOwner: groupOwner, groupUid: groupUid, ownedCryptoId: ownedCryptoId, sourceView: sourceView, confirmed: true)
                }
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            DispatchQueue.main.async { [weak self] in
                guard let _self = self else { return }
                alert.popoverPresentationController?.sourceView = sourceView
                if let presentedViewController = _self.presentedViewController {
                    presentedViewController.present(alert, animated: true)
                } else {
                    _self.present(alert, animated: true)
                }
            }
            
        }

    }
    
    
    private func observeUserWantsToIntroduceContactToAnotherContactNotifications() {
        let token = ObvMessengerInternalNotification.observeUserWantsToIntroduceContactToAnotherContact() { [weak self] (ownedCryptoId, contactCryptoId, otherContactCryptoIds) in
            guard let _self = self else { return }
            guard !otherContactCryptoIds.isEmpty else { assertionFailure(); return }
            guard _self.currentOwnedCryptoId == ownedCryptoId else { return }
            guard !otherContactCryptoIds.contains(contactCryptoId) else { assertionFailure(); return }
            ObvStack.shared.performBackgroundTask { [weak self] (context) in
                guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else { return }
                guard let contactFromEngine = try? self?.obvEngine.getContactIdentity(with: contactCryptoId, ofOwnedIdentityWith: ownedIdentity.cryptoId) else { assertionFailure(); return }
                let contactCoreDetails = contactFromEngine.publishedIdentityDetails?.coreDetails ?? contactFromEngine.trustedIdentityDetails.coreDetails
                let otherContactsFromEngine = otherContactCryptoIds.compactMap {
                    try? self?.obvEngine.getContactIdentity(with: $0, ofOwnedIdentityWith: ownedIdentity.cryptoId)
                }
                guard otherContactsFromEngine.count == otherContactCryptoIds.count else { assertionFailure(); return }
                let otherContactsWithCoreDetails = otherContactsFromEngine.map { ($0.cryptoId, $0.publishedIdentityDetails?.coreDetails ?? $0.trustedIdentityDetails.coreDetails) }
                Task { [weak self] in
                    await self?.introduceContact(contactCryptoId, withCoreDetails: contactCoreDetails, to: otherContactsWithCoreDetails, forOwnedCryptoId: ownedCryptoId, confirmed: false)
                }
            }
        }
        observationTokens.append(token)
    }
    
    
    @MainActor
    private func introduceContact(_ contactCryptoId: ObvCryptoId, withCoreDetails contactCoreDetails: ObvIdentityCoreDetails, to otherContacts: [(cryptoId: ObvCryptoId, coreDetails: ObvIdentityCoreDetails)], forOwnedCryptoId ownedCryptoId: ObvCryptoId, confirmed: Bool) async {
        
        
        guard !otherContacts.isEmpty else { assertionFailure(); return }
        
        if confirmed {

            let log = self.log
            let obvEngine = self.obvEngine

            DispatchQueue(label: "Dispatching a call to the engine of the main thread").async {

                do {
                    try obvEngine.startContactMutualIntroductionProtocol(of: contactCryptoId, with: Set(otherContacts.map({ $0.cryptoId })), forOwnedId: ownedCryptoId)
                } catch {
                    os_log("Could not start ContactMutualIntroductionProtocol", log: log, type: .fault)
                    return
                }
                
                let other = otherContacts.first!
                let message = Strings.AlertMutualIntroductionPerformedSuccessfully.message(contactCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                                           other.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                                           otherContacts.count-1)
                
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: Strings.AlertMutualIntroductionPerformedSuccessfully.title,
                                                  message: message,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                    DispatchQueue.main.async { [weak self] in
                        if let presentedViewController = self?.presentedViewController {
                            presentedViewController.present(alert, animated: true)
                        } else {
                            self?.present(alert, animated: true)
                        }
                    }
                }
                
            }
            
            
        } else {
            
            assert(Thread.current == Thread.main)
            
            let other = otherContacts.first!
            let message = Strings.AlertMutualIntroduction.message(contactCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                  other.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                  otherContacts.count-1)
            
            let alert = UIAlertController(title: Strings.AlertMutualIntroduction.title,
                                          message: message,
                                          preferredStyleForTraitCollection: self.traitCollection)            
            alert.addAction(UIAlertAction(title: Strings.AlertMutualIntroduction.actionPerformIntroduction, style: .default, handler: { (action) in
                Task { [weak self] in await self?.introduceContact(contactCryptoId, withCoreDetails: contactCoreDetails, to: otherContacts, forOwnedCryptoId: ownedCryptoId, confirmed: true) }
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            if let presentedViewController = self.presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                present(alert, animated: true)
            }
            
        }
    }
    
    
    private func showAlertWhenPastedStringIsNotValidOlvidURL() {
        assert(Thread.isMainThread)
        let alert = UIAlertController(title: CommonString.Word.Oups,
                                      message: Strings.pastedStringIsNotValidOlvidURL,
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
        present(alert, animated: true)
    }
    
    
}


// MARK: - Exchanging messages

extension MetaFlowController {
    
    private func observeUserWantsToRefreshDiscussionsNotifications() {
        let NotificationType = MessengerInternalNotification.UserWantsToRefreshDiscussions.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let completionHandler = NotificationType.parse(notification) else { return }
            _self.obvEngine.downloadAllMessagesForOwnedIdentities()
            completionHandler()
        }
        observationTokens.append(token)
    }
    
}


// MARK: - Misc and protocols starters

extension MetaFlowController {
    
    private func processUserWantsToRestartChannelEstablishmentProtocol(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        do {
            try obvEngine.restartAllOngoingChannelEstablishmentProtocolsWithContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId)
        } catch {
            DispatchQueue.main.async { [weak self] in
                let alert = UIAlertController(title: Strings.AlertChannelEstablishementRestartedFailed.title, message: "", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                self?.present(alert, animated: true)
            }
            return
        }
        
        // Display a feedback alert
        DispatchQueue.main.async { [weak self] in
            let alert = UIAlertController(title: Strings.AlertChannelEstablishementRestarted.title, message: "", preferredStyle: .alert)
            alert.addAction(UIAlertAction.init(title: CommonString.Word.Ok, style: .default))
            self?.present(alert, animated: true)
        }

    }
    

    private func observeUserTriedToAccessCameraButAccessIsDeniedNotifications() {
        let NotificationType = MessengerInternalNotification.UserTriedToAccessCameraButAccessIsDenied.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            let alert = UIAlertController(title: Strings.authorizationRequired, message: Strings.cameraAccessDeniedExplanation, preferredStyle: .alert)
            if let appSettings = URL(string: UIApplication.openSettingsURLString) {
                alert.addAction(UIAlertAction(title: Strings.goToSettingsButtonTitle, style: .default, handler: { (_) in
                    UIApplication.shared.open(appSettings, options: [:])
                }))
            }
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel, handler: nil))
            DispatchQueue.main.async {
                if let presentedViewController = _self.presentedViewController {
                    presentedViewController.present(alert, animated: true)
                } else {
                    _self.present(alert, animated: true)
                }
            }
        }
        observationTokens.append(token)
    }
    
    
    private func processUserWantsToReCreateChannelEstablishmentProtocol(contactCryptoId: ObvCryptoId, ownedCryptoId: ObvCryptoId) {
        let obvEngine = self.obvEngine
        DispatchQueue(label: "Background queue for recreating secure channel with contact").async {
            do {
                try obvEngine.reCreateAllChannelEstablishmentProtocolsWithContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    let alert = UIAlertController(title: Strings.AlertChannelEstablishementRestartedFailed.title, message: "", preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                    self?.present(alert, animated: true)
                }
            }
            // No feedback alert in case of success
        }
    }

    
    private func processUserWantsToCreateNewGroupV1(groupName: String, groupDescription: String?, groupMembersCryptoIds: Set<ObvCryptoId>, ownedCryptoId: ObvCryptoId, photoURL: URL?) {
        assert(Thread.isMainThread) // Required because we access automaticallyNavigateToCreatedDisplayedContactGroup
        automaticallyNavigateToCreatedDisplayedContactGroup = true
        let obvEngine = self.obvEngine
        let log = self.log
        DispatchQueue(label: "Background queue for calling obvEngine.startGroupCreationProtocol").async {
            do {
                try obvEngine.startGroupCreationProtocol(groupName: groupName, groupDescription: groupDescription, groupMembers: groupMembersCryptoIds, ownedCryptoId: ownedCryptoId, photoURL: photoURL)
            } catch {
                os_log("Failed to create GroupV1: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
    }
    
    
    private func processUserWantsToCreateNewGroupV2(groupCoreDetails: GroupV2CoreDetails, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?) {
        assert(Thread.isMainThread) // Required because we access automaticallyNavigateToCreatedDisplayedContactGroup
        automaticallyNavigateToCreatedDisplayedContactGroup = true
        let obvEngine = self.obvEngine
        let log = self.log
        DispatchQueue(label: "Background queue for calling obvEngine.startGroupV2CreationProtocol").async {
            do {
                let serializedGroupCoreDetails = try groupCoreDetails.jsonEncode()
                try obvEngine.startGroupV2CreationProtocol(serializedGroupCoreDetails: serializedGroupCoreDetails,
                                                           ownPermissions: ownPermissions,
                                                           otherGroupMembers: otherGroupMembers,
                                                           ownedCryptoId: ownedCryptoId,
                                                           photoURL: photoURL)
            } catch {
                os_log("Failed to create GroupV2: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
    }

    
    private func processDisplayedContactGroupWasJustCreated(objectID: TypeSafeManagedObjectID<DisplayedContactGroup>) {
        assert(Thread.isMainThread) // Required because we access automaticallyNavigateToCreatedDisplayedContactGroup
        guard automaticallyNavigateToCreatedDisplayedContactGroup else { return }
        guard let displayedContactGroup = try? DisplayedContactGroup.get(objectID: objectID.objectID, within: ObvStack.shared.viewContext) else { return }
        // We only automatically navigate to groups we juste created, where we are admin
        guard displayedContactGroup.ownPermissionAdmin else { return }
        // Navigate to the group
        automaticallyNavigateToCreatedDisplayedContactGroup = false
        let deepLink = ObvDeepLink.contactGroupDetails(displayedContactGroupURI: objectID.uriRepresentation().url)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }

}

// MARK: OlvidURLHandler

extension MetaFlowController {

    nonisolated func handleOlvidURL(_ olvidURL: OlvidURL) {
        DispatchQueue.main.async { [weak self] in
            guard let _self = self else { return }
            guard let olvidURLHandler = _self.children.compactMap({ $0 as? OlvidURLHandler }).first else { assertionFailure(); return }
            olvidURLHandler.handleOlvidURL(olvidURL)
        }
    }

}
