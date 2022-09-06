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

final class MetaFlowController: UIViewController, OlvidURLHandler {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MetaFlowController.self))

    var observationTokens = [NSObjectProtocol]()
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }
    
    private let queueForSynchronizingFyleCreation = DispatchQueue(label: "queueForSynchronizingFyleCreation")
    
    private static let errorDomain = "MetaFlowController"
    private func makeError(message: String) -> Error { NSError(domain: MetaFlowController.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // Coordinators and Services
    
    private let userNotificationsCoordinator = UserNotificationsCoordinator()
    private let userNotificationsBadgesCoordinator = UserNotificationsBadgesCoordinator()
    private let fileSystemService: FileSystemService
    private var persistedDiscussionsUpdatesCoordinator: PersistedDiscussionsUpdatesCoordinator!
    private var bootstrapCoordinator: BootstrapCoordinator!
    private var obvOwnedIdentityCoordinator: ObvOwnedIdentityCoordinator!
    private var contactIdentityCoordinator: ContactIdentityCoordinator!
    private var contactGroupCoordinator: ContactGroupCoordinator!
    private var hardLinksToFylesCoordinator: HardLinksToFylesCoordinator!
    private var thumbnailCoordinator: ThumbnailCoordinator!
    private var appBackupCoordinator: AppBackupCoordinator!
    private var expirationMessagesCoordinator: ExpirationMessagesCoordinator!
    private var retentionMessagesCoordinator: RetentionMessagesCoordinator!
    private var callManager: CallCoordinator!
    private var subscriptionCoordinator: SubscriptionCoordinator!
    private var profilePictureCoordinator: ProfilePictureCoordinator!
    private var muteDiscussionCoordinator: MuteDiscussionCoordinator!
    private var snackBarCoordinator: SnackBarCoordinator!

    private var mainFlowViewController: MainFlowViewController?
    private var onboardingFlowViewController: OnboardingFlowViewController?
    
    private let callBannerView = CallBannerView()
    
    private var mainFlowViewControllerConstraintsWithoutCallBannerView = [NSLayoutConstraint]()
    private var mainFlowViewControllerConstraintsWithCallBannerView = [NSLayoutConstraint]()

    private var currentOwnedCryptoId: ObvCryptoId? = nil
    
    private var viewDidLoadWasCalled = false

    private var viewDidAppearWasCalled = false
    private var completionHandlersToCallOnViewDidAppear = [() -> Void]()

    init(fileSystemService: FileSystemService) {
        
        self.fileSystemService = fileSystemService
        
        super.init(nibName: nil, bundle: nil)

        let queueSharedAmongCoordinators = OperationQueue.createSerialQueue(name: "Queue shared among coordinators", qualityOfService: .userInitiated)
        
        self.persistedDiscussionsUpdatesCoordinator = PersistedDiscussionsUpdatesCoordinator(obvEngine: obvEngine, operationQueue: queueSharedAmongCoordinators)
        self.obvOwnedIdentityCoordinator = ObvOwnedIdentityCoordinator(obvEngine: obvEngine, operationQueue: queueSharedAmongCoordinators)
        self.contactIdentityCoordinator = ContactIdentityCoordinator(obvEngine: obvEngine, operationQueue: queueSharedAmongCoordinators)
        self.bootstrapCoordinator = BootstrapCoordinator(obvEngine: obvEngine, operationQueue: queueSharedAmongCoordinators)
        self.contactGroupCoordinator = ContactGroupCoordinator(obvEngine: obvEngine, operationQueue: queueSharedAmongCoordinators)
        
        self.hardLinksToFylesCoordinator = HardLinksToFylesCoordinator(appType: .mainApp)
        self.thumbnailCoordinator = ThumbnailCoordinator(appType: .mainApp)
        self.appBackupCoordinator = AppBackupCoordinator(obvEngine: obvEngine)
        self.expirationMessagesCoordinator = ExpirationMessagesCoordinator()
        self.retentionMessagesCoordinator = RetentionMessagesCoordinator()
        self.callManager = CallCoordinator(obvEngine: obvEngine)
        self.subscriptionCoordinator = SubscriptionCoordinator(obvEngine: obvEngine)
        self.profilePictureCoordinator = ProfilePictureCoordinator()
        self.muteDiscussionCoordinator = MuteDiscussionCoordinator()
        self.snackBarCoordinator = SnackBarCoordinator(obvEngine: obvEngine)

        self.appBackupCoordinator.vcDelegate = self
        AppStateManager.shared.callStateDelegate = self.callManager
        Task.detached { [weak self] in await self?.callManager.finalizeInitialisation() }
        
        // Internal notifications
        
        observeUserWantsToRefreshDiscussionsNotifications()
        observeUserWantsToRestartChannelEstablishmentProtocolNotifications()
        observeUserTriedToAccessCameraButAccessIsDeniedNotifications()
        observeUserWantsToReCreateChannelEstablishmentProtocolNotifications()
        observeCreateNewGroupNotifications()
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
        observeRequestHardLinkToFyle()
        observeRequestAllHardLinksToFyles()

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

        // Observe changes of the App State
        observeAppStateChangedNotifications()
        
        // Listen to StoreKit transactions
        self.subscriptionCoordinator.listenToSKPaymentTransactions()
        
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
    
    private func observeAppStateChangedNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeAppStateChanged() { [weak self] (_, currentState) in
            guard currentState.isInitializedAndActive else { return }
            self?.obvEngine.replayTransactionsHistory()
            self?.obvEngine.downloadAllMessagesForOwnedIdentities()
            if AppStateManager.shared.currentState.isInitializedAndActive {
                DispatchQueue.main.async { [weak self] in
                    self?.setupAndShowAppropriateCallBanner()
                }
            }
        })
    }
    

    private func observeUserWantsToNavigateToDeepLinkNotifications() {
        let log = self.log
        os_log("🥏🏁 We observe UserWantsToNavigateToDeepLink notifications", log: log, type: .info)
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToNavigateToDeepLink(queue: OperationQueue.main) { [weak self] (deepLink) in
            os_log("🥏🏁 We received a UserWantsToNavigateToDeepLink notification", log: log, type: .info)
            guard let _self = self else { return }
            let toExecuteAfterViewDidAppear = { [weak self] in
                guard let _self = self else { return }
                ObvMessengerInternalNotification.hideCallView.postOnDispatchQueue()
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

    private func observeRequestHardLinkToFyle() {
        observationTokens.append(
            ObvMessengerInternalNotification.observeRequestHardLinkToFyle() { (fyleElement, completionHandler) in
                self.hardLinksToFylesCoordinator.requestHardLinkToFyle(fyleElement: fyleElement, completionHandler: completionHandler)
            })
    }

    private func observeRequestAllHardLinksToFyles() {
        observationTokens.append(
            ObvMessengerInternalNotification.observeRequestAllHardLinksToFyles() { (fyleElements, completionHandler) in
                self.hardLinksToFylesCoordinator.requestAllHardLinksToFyles(fyleElements: fyleElements, completionHandler: completionHandler)
            })
    }

}


// MARK: - Implementing MetaFlowDelegate

extension MetaFlowController: OnboardingFlowViewControllerDelegate {
            
    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadWasCalled = true
        
        view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        
        self.view.addSubview(callBannerView)
        callBannerView.translatesAutoresizingMaskIntoConstraints = false
        
        do {
            try setupAndShowAppropriateChildViewControllers()
        } catch {
            os_log("Could not determine which child view controller to show", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        setupAndShowAppropriateCallBanner()

    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearWasCalled = true
        while let completion = completionHandlersToCallOnViewDidAppear.popLast() {
            completion()
        }
    }
    
    
    func onboardingIsFinished(olvidURLScannedDuringOnboarding: OlvidURL?) {
        let log = self.log
        do {
            try setupAndShowAppropriateChildViewControllers() { result in
                switch result {
                case .failure(let error):
                    assertionFailure(error.localizedDescription)
                case .success:
                    os_log("Did setup and show the appropriate child view controller", log: log, type: .info)
                }
                // In all cases, we handle the OlvidURL scanned during the onboarding
                if let olvidURL = olvidURLScannedDuringOnboarding {
                    AppStateManager.shared.handleOlvidURL(olvidURL)
                }
            }
        } catch {
            assertionFailure()
        }
    }

    
    private var shouldShowCallBanner: Bool {
        guard let call = AppStateManager.shared.currentState.callInProgress else { return false }
        guard call.state != .initial else { return false }
        return true
    }

    
    private func setupAndShowAppropriateCallBanner() {
        assert(Thread.isMainThread)
        guard viewDidLoadWasCalled else { return }
        guard AppStateManager.shared.currentState.isInitializedAndActive else { return }
        
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
    
    
    private func setupAndShowAppropriateChildViewControllers(completion: ((Result<Void,Error>) -> Void)? = nil) throws {
        
        assert(Thread.isMainThread)
        
        assert(viewDidLoadWasCalled)
        assert(AppStateManager.shared.currentState.isInitializedAndActive)
        
        let internalCompletion = { (result: Result<Void,Error>) in
            if AppStateManager.shared.olvidURLHandler == nil {
                AppStateManager.shared.setOlvidURLHandler(to: self)
            }
            completion?(result)
        }
        
        let ownedIdentities = try obvEngine.getOwnedIdentities()
        
        if let ownedIdentity = ownedIdentities.first {
            
            currentOwnedCryptoId = ownedIdentity.cryptoId

            if mainFlowViewController == nil {
                mainFlowViewController = MainFlowViewController(ownedCryptoId: ownedIdentity.cryptoId)
                mainFlowViewController?.badgesDelegate = userNotificationsBadgesCoordinator
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
                    currentFirstChild.removeFromParent() // Automatic class to didMove(...) ?
                    mainFlowViewController.didMove(toParent: self)
                    internalCompletion(.success(()))
                }
                         
            } else {
                
                // This view controller has no child view controller.
                // We set this first child to the mainFlowViewController
                
                addChild(mainFlowViewController)
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
                onboardingFlowViewController = OnboardingFlowViewController()
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
    
    
    private func setupMainFlowViewControllerConstraintsWithoutCallBannerViewIfNecessary() {
        assert(Thread.isMainThread)
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
        
    private func observeCreateNewGroupNotifications() {
        let NotificationType = MessengerInternalNotification.CreateNewGroup.self
        let token = NotificationCenter.default.addObserver(forName: NotificationType.name, object: nil, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let (groupName, groupDescription, groupMembersCryptoIds, ownedCryptoId, photoURL) = NotificationType.parse(notification) else { return }
            do {
                try _self.obvEngine.startGroupCreationProtocol(groupName: groupName, groupDescription: groupDescription, groupMembers: groupMembersCryptoIds, ownedCryptoId: ownedCryptoId, photoURL: photoURL)
            } catch {
                os_log("Could not start group creation protocol", log: _self.log, type: .fault)
                return
            }
            
            do {
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: Strings.AlertGroupCreated.title,
                                                  message: Strings.AlertGroupCreated.message,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: nil))
                    self?.present(alert, animated: true)
                }
            }
            
        }
        observationTokens.append(token)
    }
    
    
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
            
            do {
                try obvEngine.leaveContactGroupJoined(ownedCryptoId: ownedCryptoId, groupUid: groupUid, groupOwner: groupOwner)
            } catch {
                os_log("Could not leave contact group joined", log: log, type: .error)
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
                DispatchQueue.main.async {
                    self?.introduceContact(contactCryptoId, withCoreDetails: contactCoreDetails, to: otherContactsWithCoreDetails, forOwnedCryptoId: ownedCryptoId, confirmed: false)
                }
            }
        }
        observationTokens.append(token)
    }
    
    
    private func introduceContact(_ contactCryptoId: ObvCryptoId, withCoreDetails contactCoreDetails: ObvIdentityCoreDetails, to otherContacts: [(cryptoId: ObvCryptoId, coreDetails: ObvIdentityCoreDetails)], forOwnedCryptoId ownedCryptoId: ObvCryptoId, confirmed: Bool) {
        
        guard !otherContacts.isEmpty else { assertionFailure(); return }
        
        if confirmed {
            
            DispatchQueue(label: "NewContactMutualIntroductionQueue").async { [weak self] in
                
                do {
                    try self?.obvEngine.startContactMutualIntroductionProtocol(of: contactCryptoId, with: Set(otherContacts.map({ $0.cryptoId })), forOwnedId: ownedCryptoId)
                } catch {
                    if let log = self?.log {
                        os_log("Could not start ContactMutualIntroductionProtocol", log: log, type: .fault)
                    }
                    return
                }
                
                let other = otherContacts.first!
                let message = Strings.AlertMutualIntroductionPerformedSuccessfully.message(contactCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                                           other.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                                           otherContacts.count-1)
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
            
        } else {
            
            assert(Thread.current == Thread.main)
            
            let other = otherContacts.first!
            let message = Strings.AlertMutualIntroduction.message(contactCoreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                  other.coreDetails.getDisplayNameWithStyle(.firstNameThenLastName),
                                                                  otherContacts.count-1)
            
            let alert = UIAlertController(title: Strings.AlertMutualIntroduction.title,
                                          message: message,
                                          preferredStyleForTraitCollection: self.traitCollection)            
            alert.addAction(UIAlertAction(title: Strings.AlertMutualIntroduction.actionPerformIntroduction, style: .default, handler: { [weak self] (action) in
                self?.introduceContact(contactCryptoId, withCoreDetails: contactCoreDetails, to: otherContacts, forOwnedCryptoId: ownedCryptoId, confirmed: true)
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
    
    private func observeUserWantsToRestartChannelEstablishmentProtocolNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToRestartChannelEstablishmentProtocol() { [weak self] (contactCryptoId, ownedCryptoId) in
            guard let _self = self else { return }

            do {
                try _self.obvEngine.restartAllOngoingChannelEstablishmentProtocolsWithContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId)
            } catch {
                let alert = UIAlertController(title: Strings.AlertChannelEstablishementRestartedFailed.title, message: "", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                DispatchQueue.main.async {
                    _self.present(alert, animated: true)
                }
                return
            }
            
            // Display a feedback alert
            let alert = UIAlertController(title: Strings.AlertChannelEstablishementRestarted.title, message: "", preferredStyle: .alert)
            alert.addAction(UIAlertAction.init(title: CommonString.Word.Ok, style: .default))
            DispatchQueue.main.async {
                _self.present(alert, animated: true)
            }
        })
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
    
    
    private func observeUserWantsToReCreateChannelEstablishmentProtocolNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToReCreateChannelEstablishmentProtocol() { [weak self] (contactCryptoId, ownedCryptoId) in
            guard let _self = self else { return }
            
            do {
                try _self.obvEngine.reCreateAllChannelEstablishmentProtocolsWithContactIdentity(with: contactCryptoId, ofOwnedIdentyWith: ownedCryptoId)
            } catch {
                let alert = UIAlertController(title: Strings.AlertChannelEstablishementRestartedFailed.title, message: "", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                DispatchQueue.main.async {
                    _self.present(alert, animated: true)
                }
                return
            }

            // No feedback alert in case of success
            
        })
    }

}

// MARK: OlvidURLHandler

extension MetaFlowController {

    func handleOlvidURL(_ olvidURL: OlvidURL) {
        guard let olvidURLHandler = self.children.compactMap({ $0 as? OlvidURLHandler }).first else { assertionFailure(); return }
        olvidURLHandler.handleOlvidURL(olvidURL)
    }

}
