/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import StoreKit
import ObvEngine
import ObvCrypto
import ObvTypes
import SwiftUI
import AVFAudio
import ObvUI
import ObvUICoreData
import UniformTypeIdentifiers
import ObvSettings
import ObvDesignSystem
import JWS
import AppAuth
import Contacts


@MainActor
final class MetaFlowController: UIViewController, OlvidURLHandler, MainFlowViewControllerDelegate {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MetaFlowController.self))
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MetaFlowController.self))

    var observationTokens = [NSObjectProtocol]()
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }
    
    private let queueForSynchronizingFyleCreation = DispatchQueue(label: "queueForSynchronizingFyleCreation")
    
    private static let errorDomain = "MetaFlowController"
    private func makeError(message: String) -> Error { NSError(domain: MetaFlowController.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    
    // Coordinators and Services
    
    private var mainFlowViewController: MainFlowViewController?
    private var onboardingFlowViewController: NewOnboardingFlowViewController?

    private weak var createPasscodeDelegate: CreatePasscodeDelegate?
    private weak var localAuthenticationDelegate: LocalAuthenticationDelegate?
    private weak var appBackupDelegate: AppBackupDelegate?
    private weak var storeKitDelegate: StoreKitDelegate?
    private weak var singleOwnedIdentityStoreKitDelegate: StoreKitDelegate?

    /// To ensure a smooth transistion during a cold boot, we add the launcscreen's view as the first child view.
    /// Once the other child views are show, we hide this view to prevent glitches (e.g., when switch back and forth between the call and the main view).
    /// So we keep a reference to it to make this hiding easy.
    private var launchView: UIView?

    private let callBannerView = CallBannerView()
    private let viewOnTopOfCallBannerView = UIView()
    
    private var mainFlowViewControllerConstraintsWithoutCallBannerView = [NSLayoutConstraint]()
    private var mainFlowViewControllerConstraintsWithCallBannerView = [NSLayoutConstraint]()

    private var currentOwnedCryptoId: ObvCryptoId? = nil
    
    private var viewDidLoadWasCalled = false
    private var shouldShowCallBannerOnViewDidLoad = false

    private var viewDidAppearWasCalledAtLeastOnce = false
    private var completionHandlersToCallOnViewDidAppear = [() -> Void]()

    // Shall only be accessed on the main thread
    private var automaticallyNavigateToCreatedDisplayedContactGroup = false
    
    private let obvEngine: ObvEngine
    
    init(obvEngine: ObvEngine, createPasscodeDelegate: CreatePasscodeDelegate, localAuthenticationDelegate: LocalAuthenticationDelegate, appBackupDelegate: AppBackupDelegate, storeKitDelegate: StoreKitDelegate, shouldShowCallBanner: Bool) {
        
        self.obvEngine = obvEngine
        self.createPasscodeDelegate = createPasscodeDelegate
        self.localAuthenticationDelegate = localAuthenticationDelegate
        self.appBackupDelegate = appBackupDelegate
        self.storeKitDelegate = storeKitDelegate

        super.init(nibName: nil, bundle: nil)
        
        // If the RootViewController indicates that there is a call in progress, show the call banner.
        // This happens when the app was force quitted before receiving a CallKit incoming call. In that case,
        // if the user launches the app from the CallKit UI, this MetFlowController is not instantiated during launch
        // as the in-hous call view is shown instead. As a consequence, this MetaFlowController did not receive the
        // notification about the call. So we need to have the information about this call at init time.
        
        shouldShowCallBannerOnViewDidLoad = shouldShowCallBanner
                
        observeDidBecomeActiveNotifications()
        
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
            ObvEngineNotificationNew.observeAnOwnedIdentityTransferProtocolFailed(within: NotificationCenter.default) { [weak self] ownedCryptoId, protocolInstanceUID, error in
                Task { [weak self] in await self?.processAnOwnedIdentityTransferProtocolFailed(ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, error: error) }
            },
        ])
        
        // App notifications
        
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserWantsToRestartChannelEstablishmentProtocol { [weak self] (contactCryptoId, ownedCryptoId) in
                self?.processUserWantsToRestartChannelEstablishmentProtocol(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToCreateNewGroupV1(queue: OperationQueue.main) { [weak self] (groupName, groupDescription, groupMembersCryptoIds, ownedCryptoId, photoURL) in
                self?.processUserWantsToCreateNewGroupV1(groupName: groupName, groupDescription: groupDescription, groupMembersCryptoIds: groupMembersCryptoIds, ownedCryptoId: ownedCryptoId, photoURL: photoURL)
            },
            ObvMessengerInternalNotification.observeUserWantsToCreateNewGroupV2(queue: OperationQueue.main) { [weak self] (groupCoreDetails, ownPermissions, otherGroupMembers, ownedCryptoId, photoURL) in
                self?.processUserWantsToCreateNewGroupV2(groupCoreDetails: groupCoreDetails, ownPermissions: ownPermissions, otherGroupMembers: otherGroupMembers, ownedCryptoId: ownedCryptoId, photoURL: photoURL)
            },
            ObvMessengerCoreDataNotification.observeDisplayedContactGroupWasJustCreated { [weak self] permanentID in
                Task { await self?.processDisplayedContactGroupWasJustCreated(permanentID: permanentID) }
            },
            ObvMessengerInternalNotification.observeUserWantsToAddOwnedProfile { [weak self] in
                Task { await self?.processUserWantsToAddOwnedProfileNotification() }
            },
            ObvMessengerInternalNotification.observeUserWantsToSwitchToOtherOwnedIdentity { [weak self] ownedCryptoId in
                Task { await self?.processUserWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: ownedCryptoId) }
            },
            ObvMessengerInternalNotification.observeUserWantsToSwitchToOtherHiddenOwnedIdentity { [weak self] password in
                Task { await self?.processUserWantsToSwitchToOtherHiddenOwnedIdentity(password: password) }
            },
            ObvMessengerCoreDataNotification.observePersistedObvOwnedIdentityWasDeleted { [weak self] in
                Task { try? await self?.setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: nil) }
            },
            ObvMessengerCoreDataNotification.observeOwnedIdentityHiddenStatusChanged { [weak self] _, isHidden in
                guard isHidden else { return }
                Task { await self?.askUserToChooseHiddenProfileClosePolicyIfItIsNotSetYet() }
            },
            ObvMessengerInternalNotification.observeCloseAnyOpenHiddenOwnedIdentity { [weak self] in
                Task { await self?.switchToNonHiddenOwnedIdentityIfCurrentIsHidden() }
            },
            ObvMessengerCoreDataNotification.observePersistedContactWasUpdated { [weak self] contactObjectID in
                Task { await self?.refreshViewContextsRegisteredObjectsOnUpdateOfPersistedObvContactIdentity(with: contactObjectID) }
            },
            ObvMessengerCoreDataNotification.observeFyleMessageJoinWithStatusWasInserted { [weak self] fyleMessageJoinObjectID in
                Task { await self?.refreshViewContextsRegisteredObjectsOnUpdateOfFyleMessageJoinWithStatus(with: fyleMessageJoinObjectID) }
            },
            ObvMessengerCoreDataNotification.observeFyleMessageJoinWithStatusWasUpdated { [weak self] fyleMessageJoinObjectID in
                Task { await self?.refreshViewContextsRegisteredObjectsOnUpdateOfFyleMessageJoinWithStatus(with: fyleMessageJoinObjectID) }
            },
        ])
        
        // VoIP notifications
        
        observationTokens.append(contentsOf: [
//            VoIPNotification.observeShowCallViewControllerForAnsweringNonCallKitIncomingCall(queue: .main) { [weak self] _ in
//                self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: true)
//            },
            VoIPNotification.observeNewCallToShow { [weak self] _ in
                Task { [weak self] in await self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: true, animate: true) }
            },
//            VoIPNotification.observeNewOutgoingCall { [weak self] _ in
//                self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: true)
//            },
//            VoIPNotification.observeAnIncomingCallShouldBeShownToUser(queue: .main) { [weak self] _ in
//                self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: true)
//            },
            VoIPNotification.observeNoMoreCallInProgress { [weak self] in
                Task(priority: .userInitiated) { [weak self] in
                    os_log("☎️🔚 Observed observeNoMoreCallInProgress notification", log: Self.log, type: .info)
                    await self?.setupAndShowAppropriateCallBanner(shouldShowCallBanner: false, animate: true)
                }
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
    
    
    private func processAnOwnedIdentityTransferProtocolFailed(ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID, error: Error) async {
        if let onboardingFlowViewController {
            await onboardingFlowViewController.anOwnedIdentityTransferProtocolFailed(ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, error: error)
        } else if let onboardingFlowViewController = presentedViewController as? NewOnboardingFlowViewController {
            await onboardingFlowViewController.anOwnedIdentityTransferProtocolFailed(ownedCryptoId: ownedCryptoId, protocolInstanceUID: protocolInstanceUID, error: error)
        } else {
            debugPrint("Could not find onboarding")
        }
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
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToNavigateToDeepLink { [weak self] (deepLink) in
            DispatchQueue.main.async {
                os_log("🥏🏁 We received a UserWantsToNavigateToDeepLink notification", log: log, type: .info)
                guard let _self = self else { return }
                let toExecuteAfterViewDidAppear = { [weak self] in
                    guard let _self = self else { return }
                    VoIPNotification.hideCallView.postOnDispatchQueue()
                    Task {
                        await _self.mainFlowViewController?.performCurrentDeepLinkInitialNavigation(deepLink: deepLink)
                    }
                }
                if _self.viewDidAppearWasCalledAtLeastOnce {
                    toExecuteAfterViewDidAppear()
                } else {
                    _self.completionHandlersToCallOnViewDidAppear.append(toExecuteAfterViewDidAppear)
                }
            }
        })
    }

}


// MARK: - Implementing MetaFlowDelegate

extension MetaFlowController: NewOnboardingFlowViewControllerDelegate {
            
    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadWasCalled = true
        
        // Since  ``MetaFlowController.setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding:completion:)`` is async,
        // we need to add an appropriate background view identical to the one shown in the ``InitializerViewController`` to prevent a quick transition
        // through a black screen.
        let launchScreenStoryBoard = UIStoryboard(name: "LaunchScreen", bundle: nil)
        guard let launchViewController = launchScreenStoryBoard.instantiateInitialViewController() else { assertionFailure(); return }
        self.launchView = launchViewController.view
        self.view.addSubview(launchViewController.view)
        launchViewController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.pinAllSidesToSides(of: launchViewController.view)

        self.view.addSubview(callBannerView)
        callBannerView.translatesAutoresizingMaskIntoConstraints = false
        callBannerView.isHidden = true
        
        self.view.addSubview(viewOnTopOfCallBannerView)
        viewOnTopOfCallBannerView.translatesAutoresizingMaskIntoConstraints = false
        viewOnTopOfCallBannerView.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        viewOnTopOfCallBannerView.isHidden = true
        
        Task {
            do {
                try await setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: nil)
            } catch {
                os_log("Could not determine which child view controller to show", log: log, type: .fault)
                assertionFailure()
                return
            }
            
            // See the comment in the initializer
            if shouldShowCallBannerOnViewDidLoad {
                await setupAndShowAppropriateCallBanner(shouldShowCallBanner: true, animate: false)
            }
        }
        
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !viewDidAppearWasCalledAtLeastOnce {
            ObvMessengerInternalNotification.metaFlowControllerViewDidAppear
                .postOnDispatchQueue()
        } else {
            // The notification is sent from the observeDidBecomeActiveNotifications()method
        }
        
        viewDidAppearWasCalledAtLeastOnce = true
        
        while let completion = completionHandlersToCallOnViewDidAppear.popLast() {
            completion()
        }
        
    }
    
    
    // We send the metaFlowControllerViewDidAppear notification when the application becomes active, but only of viewDidAppearWasCalled is true.
    //
    // When the app is launched after a cold boot, the metaFlowControllerViewDidAppear notification is not called here, but in the viewDidAppear method.
    // When the app is re-launched from the background, the viewDidAppear is not called, and the metaFlowControllerViewDidAppear notification is sent anyway, thanks to this method.
    private func observeDidBecomeActiveNotifications() {
        debugPrint("observeDidBecomeActiveNotifications")
        observationTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            DispatchQueue.main.async {
                guard self?.viewDidAppearWasCalledAtLeastOnce == true else { return }
                ObvMessengerInternalNotification.metaFlowControllerViewDidAppear
                    .postOnDispatchQueue()
            }
        })
    }
    
    
    /// Called by the SceneDelegate
    @MainActor
    func sceneDidBecomeActive(_ scene: UIScene) {
        assert(viewDidAppearWasCalledAtLeastOnce)
        mainFlowViewController?.sceneDidBecomeActive(scene)
    }
    
    
    /// Called by the SceneDelegate
    @MainActor
    func sceneWillResignActive(_ scene: UIScene) {
        assert(viewDidAppearWasCalledAtLeastOnce)
        mainFlowViewController?.sceneWillResignActive(scene)
    }
    

    @MainActor
    private func setupAndShowAppropriateCallBanner(shouldShowCallBanner: Bool, animate: Bool) async {
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
        if animate {
            UIView.animate(withDuration: 0.3) { [weak self] in
                self?.view.layoutIfNeeded()
            }
        }

    }
    
    /// When deleting the last owned identity, we want to restart all over: show the onboarding screen and remove the main flow from the hierarchy
    private func destroyCurrentMainFlowViewController() {
        if let mainFlowViewController {
            mainFlowViewController.view.removeFromSuperview()
            mainFlowViewController.willMove(toParent: nil)
            mainFlowViewController.removeFromParent()
            mainFlowViewController.didMove(toParent: nil)
        }
        mainFlowViewController = nil
        mainFlowViewControllerConstraintsWithoutCallBannerView.removeAll()
        mainFlowViewControllerConstraintsWithCallBannerView.removeAll()
    }

    
    private func destroyCurrentOnboardingFlowViewController() {
        if let onboardingFlowViewController {
            onboardingFlowViewController.view.removeFromSuperview()
            onboardingFlowViewController.willMove(toParent: nil)
            onboardingFlowViewController.removeFromParent()
            onboardingFlowViewController.didMove(toParent: nil)
        }
        onboardingFlowViewController  = nil
    }
    
    
    /// Asks the user to choose a hidding policy if it is not set yet.
    ///
    /// This is typically called each time an owned identity becomes hidden.
    @MainActor
    func askUserToChooseHiddenProfileClosePolicyIfItIsNotSetYet() async {
        let traitCollection = self.traitCollection
        guard ObvMessengerSettings.Privacy.hiddenProfileClosePolicyHasYetToBeSet else { return }
        let alert = UIAlertController(title: Strings.AlertChooseHiddenProfileClosePolicy.title,
                                      message: Strings.AlertChooseHiddenProfileClosePolicy.message,
                                      preferredStyleForTraitCollection: traitCollection)
        alert.addAction(.init(title: Strings.AlertChooseHiddenProfileClosePolicy.actionManualSwitching, style: .default) { _ in
            ObvMessengerSettings.Privacy.hiddenProfileClosePolicy = .manualSwitching
        })
        alert.addAction(.init(title: Strings.AlertChooseHiddenProfileClosePolicy.actionScreenLock, style: .default) { [weak self] _ in
            ObvMessengerSettings.Privacy.hiddenProfileClosePolicy = .screenLock
            Task { await self?.askUserToActivateScreenLockIfNoneExists() }
        })
        alert.addAction(.init(title: Strings.AlertChooseHiddenProfileClosePolicy.actionBackground, style: .default) { [weak self] _ in
            ObvMessengerSettings.Privacy.hiddenProfileClosePolicy = .background
            // Show another alert allowing to choose the time interval allowed in background
            let alert = UIAlertController(title: Strings.AlertTimeIntervalForBackgroundHiddenProfileClosePolicy.title,
                                          message: nil,
                                          preferredStyleForTraitCollection: traitCollection)
            for timeInterval in ObvMessengerSettings.Privacy.TimeIntervalForBackgroundHiddenProfileClosePolicy.allCases {
                alert.addAction(.init(title: Strings.AlertTimeIntervalForBackgroundHiddenProfileClosePolicy.actionTitle(for: timeInterval), style: .default) { _ in
                    ObvMessengerSettings.Privacy.timeIntervalForBackgroundHiddenProfileClosePolicy = timeInterval
                })
            }
            if let presentedViewController = self?.presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                self?.present(alert, animated: true)
            }
        })
        if let presentedViewController {
            presentedViewController.present(alert, animated: true)
        } else {
            present(alert, animated: true)
        }
    }
    
    
    /// When a user creates a hidden profile with a `.screenLock` close policy, we make sure she actually has a screen lock activated.
    /// If not, we recommend to activate a screen lock and provide a way to navigate to the appropriate settings screen.
    @MainActor func askUserToActivateScreenLockIfNoneExists() async {
        guard ObvMessengerSettings.Privacy.localAuthenticationPolicy == .none else { return }
        // The user has no screen lock (i.e., no local authentication policy), we recommend to activate one now.
        let alert = UIAlertController(title: Strings.AlertShouldActivateScreenLockAfterCreatingHiddenProfile.title,
                                      message: Strings.AlertShouldActivateScreenLockAfterCreatingHiddenProfile.message,
                                      preferredStyleForTraitCollection: traitCollection)
        alert.addAction(.init(title: Strings.AlertShouldActivateScreenLockAfterCreatingHiddenProfile.actionGotToPrivacySettings, style: .default) { _ in
            let deepLink = ObvDeepLink.privacySettings
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
        })
        alert.addAction(.init(title: CommonString.Word.Later, style: .cancel))
        if let presentedViewController = presentedViewController {
            presentedViewController.present(alert, animated: true)
        } else {
            present(alert, animated: true)
        }
    }

    
    @MainActor
    private func setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: ObvCryptoId?, completion: (@MainActor (Result<Void,Error>) -> Void)? = nil) async throws {
        
        assert(viewDidLoadWasCalled)
        assert(Thread.isMainThread)
        
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
        
        // Determine the most appropriate owned identity to show

        let appropriateOwnedCryptoIdToShow: ObvCryptoId?
        if let ownedCryptoIdGeneratedDuringOnboarding {
            appropriateOwnedCryptoIdToShow = ownedCryptoIdGeneratedDuringOnboarding
        } else {
            appropriateOwnedCryptoIdToShow = await getMostAppropriateOwnedCryptoIdToShow()
        }
        
        if let ownedCryptoId = appropriateOwnedCryptoIdToShow {
                        
            if mainFlowViewController == nil {
                guard let createPasscodeDelegate, let appBackupDelegate, let localAuthenticationDelegate, let storeKitDelegate else {
                    assertionFailure(); return
                }
                mainFlowViewController = MainFlowViewController(
                    ownedCryptoId: ownedCryptoId,
                    obvEngine: obvEngine,
                    createPasscodeDelegate: createPasscodeDelegate,
                    localAuthenticationDelegate: localAuthenticationDelegate,
                    appBackupDelegate: appBackupDelegate,
                    mainFlowViewControllerDelegate: self,
                    storeKitDelegate: storeKitDelegate)
            }

            guard let mainFlowViewController else {
                assertionFailure()
                internalCompletion(.failure(makeError(message: "No main flow view controller")))
                return
            }
                        
            if let currentFirstChild = children.first {
                            
                guard currentFirstChild != mainFlowViewController else {
                    presentedViewController?.dismiss(animated: true)
                    await processUserWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: ownedCryptoId)
                    return
                }
                
                // The current first child view controller is not the mainFlowViewController.
                // We will transition to it.
                
                if currentFirstChild == onboardingFlowViewController {
                    mainFlowViewController.anOwnedIdentityWasJustCreatedOrRestored = true
                }
                
                if mainFlowViewController.parent == nil {
                    mainFlowViewController.willMove(toParent: self)
                    addChild(mainFlowViewController)
                    mainFlowViewController.didMove(toParent: self)
                }
                                
                transition(from: currentFirstChild, to: mainFlowViewController, duration: 0.9, options: [.transitionFlipFromLeft]) { [weak self] in
                    // Animation block
                    guard let _self = self else { return }
                    _self.setupMainFlowViewControllerConstraintsWithoutCallBannerViewIfNecessary()
                    NSLayoutConstraint.activate(_self.mainFlowViewControllerConstraintsWithoutCallBannerView)
                    _self.callBannerView.isHidden = true
                } completion: { [weak self] _ in
                    currentFirstChild.view.removeFromSuperview()
                    currentFirstChild.removeFromParent() // Automatic call to didMove(...) ?
                    mainFlowViewController.didMove(toParent: self)
                    internalCompletion(.success(()))
                    self?.destroyCurrentOnboardingFlowViewController()
                    Task {
                        await self?.switchToOwnedIdentity(ownedCryptoId: ownedCryptoId)
                    }
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
                launchView?.removeFromSuperview()
                launchView = nil
                
                internalCompletion(.success(()))

                await switchToOwnedIdentity(ownedCryptoId: ownedCryptoId)

            }
            
        } else {
            
            destroyCurrentMainFlowViewController()

            if let onboardingFlowViewController {
                if onboardingFlowViewController.parent != nil {
                    // Nothing left to do
                    return
                } else {
                    assertionFailure()
                }
            } else {
                //onboardingFlowViewController = OnboardingFlowViewController(obvEngine: obvEngine, appBackupDelegate: appBackupDelegate)
                let mdmConfig = getMDMConfigurationForOnboarding()
                onboardingFlowViewController = NewOnboardingFlowViewController(
                    logSubsystem: ObvMessengerConstants.logSubsystem,
                    directoryForTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
                    mode: .initialOnboarding(mdmConfig: mdmConfig))
                onboardingFlowViewController?.delegate = self
            }
            
            guard let onboardingFlowViewController else {
                assertionFailure()
                internalCompletion(.failure(makeError(message: "No onboarding flow view controller")))
                return
            }
            
            if let currentFirstChild = children.first {
                
                if currentFirstChild != onboardingFlowViewController {
                    // Happens when deleting the last owned identity
                    currentFirstChild.view.removeFromSuperview()
                    currentFirstChild.willMove(toParent: nil)
                    currentFirstChild.removeFromParent()
                    currentFirstChild.didMove(toParent: nil)
                } else {
                    internalCompletion(.success(()))
                    return
                }
                
            }
                
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
    
    
    /// Helper method called to configure the very first onboarding
    private func getMDMConfigurationForOnboarding() -> Onboarding.MDMConfiguration? {
        
        if ObvMessengerSettings.MDM.isConfiguredFromMDM,
           let mdmConfigurationURI = ObvMessengerSettings.MDM.Configuration.uri,
           let olvidURL = OlvidURL(urlRepresentation: mdmConfigurationURI) {
            
            switch olvidURL.category {
            case .configuration(_, _, let keycloakConfig):
                guard let keycloakConfig else { return nil }
                return .init(keycloakConfiguration: .init(keycloakServerURL: keycloakConfig.serverURL, clientId: keycloakConfig.clientId, clientSecret: keycloakConfig.clientSecret))
            default:
                assertionFailure()
                return nil
            }
        }
        
        return nil
        
    }
    
    
    /// Returns the most appropriate owned identity to show. Returns `nil` if no owned identity exists.
    @MainActor private func getMostAppropriateOwnedCryptoIdToShow() async -> ObvCryptoId? {
        guard let latestCurrentOWnedIdentityStored = await LatestCurrentOwnedIdentityStorage.shared.getLatestCurrentOwnedIdentityStored() else {
            // Return a random non hidden owned identity if one can be found
            return await getRandomExistingNonHiddenOwnedCryptoId()
        }
        guard let hiddenCryptoId = latestCurrentOWnedIdentityStored.hiddenCryptoId else {
            let nonHiddenCryptoId = latestCurrentOWnedIdentityStored.nonHiddenCryptoId
            // Make sure the identity still exists, otherwise, return a random non hidden owned identity
            guard (try? PersistedObvOwnedIdentity.get(cryptoId: nonHiddenCryptoId, within: ObvStack.shared.viewContext)) != nil else {
                return await getRandomExistingNonHiddenOwnedCryptoId()
            }
            return nonHiddenCryptoId
        }
        // If we reach this point, we are in the complex situation where the latest current identity was a hidden one. We must determine if it is appropriate to show it.
        guard (try? PersistedObvOwnedIdentity.get(cryptoId: hiddenCryptoId, within: ObvStack.shared.viewContext)) != nil else {
            return await getRandomExistingNonHiddenOwnedCryptoId()
        }
        switch ObvMessengerSettings.Privacy.hiddenProfileClosePolicy {
        case .manualSwitching:
            return hiddenCryptoId
        case .screenLock, .background:
            assertionFailure("The hidden cryptoId should have been cleared by now")
            return latestCurrentOWnedIdentityStored.nonHiddenCryptoId
        }
    }
    
    
    @MainActor private func getRandomExistingNonHiddenOwnedCryptoId() async -> ObvCryptoId? {
        guard let ownedIdentities = try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext) else { assertionFailure(); return nil }
        return ownedIdentities.first?.cryptoId
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


// MARK: - NewOnboardingFlowViewControllerDelegate

extension MetaFlowController {

    func onboardingRequiresKeycloakToSyncAllManagedIdentities() async {
        do {
            try await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }
    
    
    @MainActor
    func userWantsToDismissOnboardingAfterSuccessfulOwnedIdentityTransferOnThisTargetDevice(onboardingFlow: NewOnboardingFlowViewController, transferredOwnedCryptoId: ObvCryptoId, userWantsToAddAnotherProfile: Bool) async {
        if mainFlowViewController != nil {
            await switchToOwnedIdentity(ownedCryptoId: transferredOwnedCryptoId)
            onboardingFlow.dismiss(animated: true)
        } else {
            do {
                try await setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: transferredOwnedCryptoId) { result in
                    switch result {
                    case .success:
                        onboardingFlow.dismiss(animated: true) {
                            if userWantsToAddAnotherProfile {
                                ObvMessengerInternalNotification.userWantsToAddOwnedProfile
                                    .postOnDispatchQueue()
                            }
                        }
                    case .failure:
                        assertionFailure()
                    }
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }
        }
    }

    
    func onboardingRequiresToPerformOwnedDeviceDiscoveryNow(for ownedCryptoId: ObvCryptoId) async throws -> (ownedDeviceDiscoveryResult: ObvOwnedDeviceDiscoveryResult, currentDeviceIdentifier: Data) {
        let ownedDeviceDiscoveryResult = try await obvEngine.performOwnedDeviceDiscoveryNow(ownedCryptoId: ownedCryptoId)
        let currentDeviceIdentifier = try await obvEngine.getCurrentDeviceIdentifier(ownedCryptoId: ownedCryptoId)
        return (ownedDeviceDiscoveryResult, currentDeviceIdentifier)
    }
    
    
    
    
    func onboardingIsShowingSasAndExpectingEndOfProtocol(onboardingFlow: NewOnboardingFlowViewController, protocolInstanceUID: UID, onSyncSnapshotReception: @escaping () -> Void, onSuccessfulTransfer: @escaping (ObvCryptoId, Error?) -> Void) async {
        await obvEngine.appIsShowingSasAndExpectingEndOfProtocol(
            protocolInstanceUID: protocolInstanceUID,
            onSyncSnapshotReception: onSyncSnapshotReception,
            onSuccessfulTransfer: onSuccessfulTransfer)
    }
    
    
    func onboardingRequiresToInitiateOwnedIdentityTransferProtocolOnTargetDevice(onboardingFlow: NewOnboardingFlowViewController, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, currentDeviceName: String, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void) async throws {
        try await obvEngine.initiateOwnedIdentityTransferProtocolOnTargetDevice(
            currentDeviceName: currentDeviceName,
            transferSessionNumber: transferSessionNumber,
            onIncorrectTransferSessionNumber: onIncorrectTransferSessionNumber,
            onAvailableSas: onAvailableSas)
    }
    
    
    func onboardingRequiresToInitiateOwnedIdentityTransferProtocolOnSourceDevice(onboardingFlow: NewOnboardingFlowViewController, ownedCryptoId: ObvCryptoId, onAvailableSessionNumber: @escaping (ObvOwnedIdentityTransferSessionNumber) -> Void, onAvailableSASExpectedOnInput: @escaping (ObvOwnedIdentityTransferSas, String, UID) -> Void) async throws {
        try await obvEngine.initiateOwnedIdentityTransferProtocolOnSourceDevice(
            ownedCryptoId: ownedCryptoId,
            onAvailableSessionNumber: onAvailableSessionNumber,
            onAvailableSASExpectedOnInput: onAvailableSASExpectedOnInput)
    }
    
    
    func userWishesToFinalizeOwnedIdentityTransferFromSourceDevice(onboardingFlow: NewOnboardingFlowViewController, enteredSAS: ObvOwnedIdentityTransferSas, deviceToKeepActive: UID?, ownedCryptoId: ObvCryptoId, protocolInstanceUID: UID) async throws {
        try await obvEngine.userEnteredValidSASOnSourceDeviceForOwnedIdentityTransferProtocol(
            enteredSAS: enteredSAS,
            deviceToKeepActive: deviceToKeepActive,
            ownedCryptoId: ownedCryptoId,
            protocolInstanceUID: protocolInstanceUID)
        onboardingFlow.dismiss(animated: true)
    }
    
    
    func userWantsToCloseOnboardingAndCancelAnyOwnedTransferProtocol(onboardingFlow: NewOnboardingFlowViewController) async {
        do {
            try await obvEngine.userWantsToCancelAllOwnedIdentityTransferProtocols()
        } catch {
            assertionFailure()
        }
        
        onboardingFlow.dismiss(animated: true)

    }


    func onboardingRequiresToRegisterAndUploadOwnedIdentityToKeycloakServer(ownedCryptoId: ObvCryptoId) async throws {
        await KeycloakManagerSingleton.shared.registerKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId, firstKeycloakBinding: true)
        try await KeycloakManagerSingleton.shared.uploadOwnIdentity(ownedCryptoId: ownedCryptoId)
    }

    
    func onboardingRequiresKeycloakAuthentication(onboardingFlow: NewOnboardingFlowViewController, keycloakConfiguration: Onboarding.KeycloakConfiguration, keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration)) async throws -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, keycloakState: ObvKeycloakState) {
        let authState = try await KeycloakManagerSingleton.shared.authenticate(configuration: keycloakServerKeyAndConfig.serviceConfig,
                                                                               clientId: keycloakConfiguration.clientId,
                                                                               clientSecret: keycloakConfiguration.clientSecret,
                                                                               ownedCryptoId: nil)
        let keycloakConfig = KeycloakConfiguration(serverURL: keycloakConfiguration.keycloakServerURL, clientId: keycloakConfiguration.clientId, clientSecret: keycloakConfiguration.clientSecret)
        return try await getOwnedDetailsAfterSucessfullAuthentication(keycloakConfiguration: keycloakConfig, keycloakServerKeyAndConfig: keycloakServerKeyAndConfig, authState: authState)
    }
    
    
    @MainActor
    private func getOwnedDetailsAfterSucessfullAuthentication(keycloakConfiguration: KeycloakConfiguration, keycloakServerKeyAndConfig: (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration), authState: OIDAuthState) async throws -> (keycloakUserDetailsAndStuff: KeycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff: KeycloakServerRevocationsAndStuff, keycloakState: ObvKeycloakState) {
        
        let (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff) = try await KeycloakManagerSingleton.shared.getOwnDetails(
            keycloakServer: keycloakConfiguration.serverURL,
            authState: authState,
            clientSecret: keycloakConfiguration.clientSecret,
            jwks: keycloakServerKeyAndConfig.jwks,
            latestLocalRevocationListTimestamp: nil)
        
        if let minimumBuildVersion = keycloakServerRevocationsAndStuff.minimumIOSBuildVersion {
            guard ObvMessengerConstants.bundleVersionAsInt >= minimumBuildVersion else {
                throw ObvError.installedOlvidAppIsOutdated
            }
        }

        let rawAuthState = try authState.serialize()
        
        let keycloakState = ObvKeycloakState(
            keycloakServer: keycloakConfiguration.serverURL,
            clientId: keycloakConfiguration.clientId,
            clientSecret: keycloakConfiguration.clientSecret,
            jwks: keycloakServerKeyAndConfig.jwks,
            rawAuthState: rawAuthState,
            signatureVerificationKey: keycloakUserDetailsAndStuff.serverSignatureVerificationKey,
            latestLocalRevocationListTimestamp: nil,
            latestGroupUpdateTimestamp: nil)
        
        return (keycloakUserDetailsAndStuff, keycloakServerRevocationsAndStuff, keycloakState)
        
    }

    
    func onboardingRequiresToDiscoverKeycloakServer(onboardingFlow: NewOnboardingFlowViewController, keycloakServerURL: URL) async throws -> (jwks: ObvJWKSet, serviceConfig: OIDServiceConfiguration) {
        return try await KeycloakManagerSingleton.shared.discoverKeycloakServer(for: keycloakServerURL)
    }
    

    func userWantsToEnableAutomaticBackup(onboardingFlow: NewOnboardingFlowViewController) async throws {

        guard !ObvMessengerSettings.Backup.isAutomaticBackupEnabled else { return }

        guard let appBackupDelegate else {
            throw ObvError.theAppBackupDelegateIsNotSet
        }
        
        // The user wants to activate automatic backup.
        // We must check whether it's possible.
        let defaultTitleAndMessageOnError = (title: "AUTOMATIC_BACKUP_COULD_NOT_BE_ENABLED_TITLE", message: "PLEASE_TRY_AGAIN_LATER")
        do {
            let accountStatus = try await appBackupDelegate.getAccountStatus()
            if case .available = accountStatus {
                obvEngine.userJustActivatedAutomaticBackup()
                ObvMessengerSettings.Backup.isAutomaticBackupEnabled = true
                return
            } else {
                let titleAndMessage = AppBackupManager.CKAccountStatusMessage(accountStatus) ?? AppBackupManager.CKAccountStatusMessage(.couldNotDetermine) ?? defaultTitleAndMessageOnError
                throw ObvError.ckAccountStatusError(title: titleAndMessage.title, message: titleAndMessage.message)
            }
        } catch {
            let titleAndMessage = AppBackupManager.CKAccountStatusMessage(.noAccount) ?? defaultTitleAndMessageOnError
            throw ObvError.ckAccountStatusError(title: titleAndMessage.title, message: titleAndMessage.message)
        }
        
    }
    
    
    @MainActor
    func onboardingRequiresToRestoreBackup(onboardingFlow: NewOnboardingFlowViewController, backupRequestIdentifier: UUID) async throws -> ObvCryptoId {
        let ownedDeviceName = UIDevice.current.preciseModel
        let cryptoIdsOfRestoredOwnedIdentities = try await obvEngine.restoreFullBackup(backupRequestIdentifier: backupRequestIdentifier, nameToGiveToCurrentDevice: ownedDeviceName)
        guard let randomCryptoId = cryptoIdsOfRestoredOwnedIdentities.first else {
            assertionFailure()
            throw ObvError.couldNotFindOwnedIdentity
        }
        // We obtained a list of restored owned identities. We only need to return one. We search for a non-hidden one
        do {
            let nonHiddenOwnedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext)
            let cryptoIdsOfNonHiddenOwnedIdentities = Set(nonHiddenOwnedIdentities.map { $0.cryptoId })
            return cryptoIdsOfNonHiddenOwnedIdentities.intersection(cryptoIdsOfRestoredOwnedIdentities).first ?? randomCryptoId
        } catch {
            // If something goes wrong, we return a "random" restored owned identity
            assertionFailure()
            return randomCryptoId
        }
    }
    
    
    func onboardingRequiresToRecoverBackupFromEncryptedBackup(onboardingFlow: NewOnboardingFlowViewController, encryptedBackup: Data, backupKey: String) async throws -> (backupRequestIdentifier: UUID, backupDate: Date) {
        return try await obvEngine.recoverBackupData(encryptedBackup, withBackupKey: backupKey)
    }
    
    
    func onboardingRequiresAcceptableCharactersForBackupKeyString() async -> CharacterSet {
        return obvEngine.getAcceptableCharactersForBackupKeyString()
    }
    
    
    func onboardingRequiresToGenerateOwnedIdentity(onboardingFlow: NewOnboardingFlowViewController, identityDetails: ObvIdentityDetails, nameForCurrentDevice: String, keycloakState: ObvKeycloakState?, customServerAndAPIKey: ServerAndAPIKey?) async throws -> ObvCryptoId {
        let usedCustomServerAndAPIKey: ServerAndAPIKey?
        if keycloakState != nil {
            usedCustomServerAndAPIKey = nil
        } else {
            usedCustomServerAndAPIKey = customServerAndAPIKey // nil, most of the time
        }
        let generatedOwnedCryptoId = try await obvEngine.generateOwnedIdentity(
            onServerURL: usedCustomServerAndAPIKey?.server ?? ObvMessengerConstants.serverURL,
            with: identityDetails,
            nameForCurrentDevice: nameForCurrentDevice,
            keycloakState: keycloakState)
        if let apiKey = usedCustomServerAndAPIKey?.apiKey {
            _ = try await obvEngine.registerOwnedAPIKeyOnServerNow(ownedCryptoId: generatedOwnedCryptoId, apiKey: apiKey)
        }
        return generatedOwnedCryptoId
    }

    
    func onboardingIsFinished(onboardingFlow: NewOnboardingFlowViewController, ownedCryptoIdGeneratedDuringOnboarding: ObvTypes.ObvCryptoId) async {
        let log = self.log
        do {
            try await setupAndShowAppropriateChildViewControllers(ownedCryptoIdGeneratedDuringOnboarding: ownedCryptoIdGeneratedDuringOnboarding) { result in
                assert(Thread.isMainThread)
                switch result {
                case .failure(let error):
                    assertionFailure(error.localizedDescription)
                case .success:
                    os_log("Did setup and show the appropriate child view controller", log: log, type: .info)
                }
            }
        } catch {
            assertionFailure()
        }
    }

    
    func onboardingNeedsToPreventPrivacyWindowSceneFromShowingOnNextWillResignActive(onboardingFlow: NewOnboardingFlowViewController) async {
        preventPrivacyWindowSceneFromShowingOnNextWillResignActive()
    }
    
    
    func onboardingRequiresToSyncAppDatabasesWithEngine(onboardingFlow: NewOnboardingFlowViewController) async throws {
        try await requestSyncAppDatabasesWithEngine()
    }

    
    @MainActor
    private func requestSyncAppDatabasesWithEngine() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ObvMessengerInternalNotification.requestSyncAppDatabasesWithEngine(queuePriority: .veryHigh) { result in
                switch result {
                case .failure(let error):
                    continuation.resume(throwing: error)
                case .success:
                    continuation.resume()
                }
            }.postOnDispatchQueue()
        }
    }

}


// MARK: - SubscriptionPlansViewActionsProtocol (required for NewOnboardingFlowViewControllerDelegate)

extension MetaFlowController {

    func fetchSubscriptionPlans(for ownedCryptoId: ObvCryptoId, alsoFetchFreePlan: Bool) async throws -> (freePlanIsAvailable: Bool, products: [Product]) {
        
        // Step 1: Ask the engine (i.e., Olvid's server) whether a free trial is still available for this identity
        let freePlanIsAvailable: Bool
        if alsoFetchFreePlan {
            freePlanIsAvailable = try await obvEngine.queryServerForFreeTrial(for: ownedCryptoId)
        } else {
            freePlanIsAvailable = false
        }

        // Step 2: As StoreKit about available products
        assert(storeKitDelegate != nil)
        let products = try await storeKitDelegate?.userRequestedListOfSKProducts() ?? []

        return (freePlanIsAvailable, products)
    }
    
    
    func userWantsToStartFreeTrialNow(ownedCryptoId: ObvCryptoId) async throws -> APIKeyElements {
        let newAPIKeyElements = try await obvEngine.startFreeTrial(for: ownedCryptoId)
        return newAPIKeyElements
    }
    
    
    func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult {
        guard let storeKitDelegate else { assertionFailure(); throw ObvError.storeKitDelegateIsNil }
        return try await storeKitDelegate.userWantsToBuy(product)
    }
    
    
    func userWantsToRestorePurchases() async throws {
        guard let storeKitDelegate else { assertionFailure(); throw ObvError.storeKitDelegateIsNil }
        return try await storeKitDelegate.userWantsToRestorePurchases()
    }
    
}


// MARK: - MainFlowViewControllerDelegate

extension MetaFlowController {
    
    func userWantsToAddNewDevice(_ viewController: MainFlowViewController, ownedCryptoId: ObvCryptoId) async {
        guard let ownedDetails = try? await getOwnedIdentityDetails(ownedCryptoId: ownedCryptoId) else { assertionFailure(); return }
        let newOnboardingFlowViewController = NewOnboardingFlowViewController(
            logSubsystem: ObvMessengerConstants.logSubsystem,
            directoryForTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
            mode: .addNewDevice(ownedCryptoId: ownedCryptoId, ownedDetails: ownedDetails))
        newOnboardingFlowViewController.delegate = self
        present(newOnboardingFlowViewController, animated: true)
    }

    
    private func getOwnedIdentityDetails(ownedCryptoId: ObvCryptoId) async throws -> CNContact? {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CNContact?, Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context)
                    let ownedDetails = ownedIdentity?.asCNContact
                    continuation.resume(returning: ownedDetails)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    
}


// MARK: - Feeding the contact database

extension MetaFlowController {
    
    
    private func observeUserWantsToDeleteOwnedContactGroupNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToDeleteOwnedContactGroup { [weak self] ownedCryptoId, groupUid in
            Task { await self?.deleteOwnedContactGroup(groupUid: groupUid, ownedCryptoId: ownedCryptoId, confirmed: false) }
        })
    }

    
    @MainActor
    private func deleteOwnedContactGroup(groupUid: UID, ownedCryptoId: ObvCryptoId, confirmed: Bool) async {
        
        if confirmed {

            do {
                try await obvEngine.disbandGroupV1(groupUid: groupUid, ownedCryptoId: ownedCryptoId)
            } catch {
                let uiAlert = UIAlertController(title: Strings.AlertDeleteOwnedGroupFailed.title, message: Strings.AlertDeleteOwnedGroupFailed.message, preferredStyle: .alert)
                let okAction = UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: nil)
                uiAlert.addAction(okAction)
                
                if let presentedViewController {
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
                Task { await self?.deleteOwnedContactGroup(groupUid: groupUid, ownedCryptoId: ownedCryptoId, confirmed: true) }
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
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToRefreshDiscussions { [weak self] completionHandler in
            // Request the download of all messages to the engine
            self?.obvEngine.downloadAllMessagesForOwnedIdentities()
            // If one of the owned identities is keycloak managed, resync
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let ownedIdentities = try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: context) else { return }
                    let keycloakManagedOwnedIdentities = ownedIdentities.filter { $0.isKeycloakManaged }
                    guard !keycloakManagedOwnedIdentities.isEmpty else { return }
                    Task {
                        try? await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
                    }
                }
            }
            // Call the completion (yes, even if the other tasks are not over yet. This shall be improved)
            completionHandler()
        })
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

    
    @MainActor
    private func processDisplayedContactGroupWasJustCreated(permanentID: ObvManagedObjectPermanentID<DisplayedContactGroup>) async {
        assert(Thread.isMainThread) // Required because we access automaticallyNavigateToCreatedDisplayedContactGroup
        guard automaticallyNavigateToCreatedDisplayedContactGroup else { return }
        guard let currentOwnedCryptoId else { return }
        guard let displayedContactGroup = try? DisplayedContactGroup.getManagedObject(withPermanentID: permanentID, within: ObvStack.shared.viewContext) else { return }
        guard let ownedCryptoId = try? displayedContactGroup.ownedCryptoId else { assertionFailure(); return }
        guard currentOwnedCryptoId == ownedCryptoId else { return }
        // We only automatically navigate to groups we juste created, where we are admin
        guard displayedContactGroup.ownPermissionAdmin else { return }
        // Navigate to the group
        automaticallyNavigateToCreatedDisplayedContactGroup = false
        let deepLink = ObvDeepLink.contactGroupDetails(ownedCryptoId: currentOwnedCryptoId, objectPermanentID: permanentID)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }

    
    @MainActor
    private func processUserWantsToAddOwnedProfileNotification() async {
        presentedViewController?.dismiss(animated: true)
        let newOnboardingFlowViewController = NewOnboardingFlowViewController(
            logSubsystem: ObvMessengerConstants.logSubsystem,
            directoryForTempFiles: ObvUICoreDataConstants.ContainerURL.forTempFiles.url,
            mode: .addProfile)
        newOnboardingFlowViewController.delegate = self
        present(newOnboardingFlowViewController, animated: true)
    }
    
}


// MARK: - Switching current owned identity

extension MetaFlowController {
    
    /// Changes the current owned identity of the user. Called as a response to the corresponding notification and from the MainFlowViewController as well, when processing an externally tapped or scanned `OlvidURL`.
    @MainActor func processUserWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: ObvCryptoId) async {
        presentedViewController?.dismiss(animated: true)
        await switchToOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }
    
    
    @MainActor
    private func processUserWantsToSwitchToOtherHiddenOwnedIdentity(password: String) async {
        let ownedCryptoId: ObvCryptoId
        do {
            guard let unlockedOwnedIdentity = try PersistedObvOwnedIdentity.getHiddenOwnedIdentity(password: password, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
            ownedCryptoId = unlockedOwnedIdentity.cryptoId
        } catch {
            assertionFailure(error.localizedDescription)
            return
        }
        await switchToOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }
    
    
    /// Certain events trigger the immediate closing of a hidden owned identity if one is open. For example, when using a custom passcode, we should close any open hidden identity.
    /// When this is required, a `CloseAnyOpenHiddenOwnedIdentity` notification is sent, and we process it here, where we simply switch to any non-hidden identity.
    @MainActor func switchToNonHiddenOwnedIdentityIfCurrentIsHidden() async {
        guard let currentOwnedCryptoId else { return }
        guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: currentOwnedCryptoId, within: ObvStack.shared.viewContext) else {
            await switchToNonHiddenOwnedIdentity()
            return
        }
        guard ownedIdentity.isHidden else { return }
        // If we reach this point, the current owned identity is hidden. We close it, as requested.
        await switchToNonHiddenOwnedIdentity()
    }
    
    
    /// Alows to switch to the most appropriate non-hidden owned identity
    @MainActor private func switchToNonHiddenOwnedIdentity() async {
        let ownedCryptoId: ObvCryptoId
        if let _ownedCryptoId = await LatestCurrentOwnedIdentityStorage.shared.getLatestCurrentOwnedIdentityStored()?.nonHiddenCryptoId {
            ownedCryptoId = _ownedCryptoId
        } else {
            guard let ownedIdentity = try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext).first else { assertionFailure(); return }
            ownedCryptoId = ownedIdentity.cryptoId
        }
        await switchToOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }
    
    
    /// Called from the other aboves methods when they need to switch identity.
    @MainActor private func switchToOwnedIdentity(ownedCryptoId: ObvCryptoId) async {
        let isHidden: Bool
        do {
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { return }
            isHidden = ownedIdentity.isHidden
        } catch {
            assertionFailure(error.localizedDescription)
            return
        }
        guard let mainFlowViewController else { assertionFailure(); return }
        self.currentOwnedCryptoId = ownedCryptoId
        await LatestCurrentOwnedIdentityStorage.shared.storeLatestCurrentOwnedCryptoId(ownedCryptoId, isHidden: isHidden)
        await mainFlowViewController.switchCurrentOwnedCryptoId(to: ownedCryptoId)
        
        ObvMessengerInternalNotification.metaFlowControllerDidSwitchToOwnedIdentity(ownedCryptoId: ownedCryptoId)
            .postOnDispatchQueue()
    }
    
}


// MARK: OlvidURLHandler

extension MetaFlowController {

    func handleOlvidURL(_ olvidURL: OlvidURL) async {
        // If the OlvidURL is an openId redirect, we handle it immediately.
        // Otherwise, we passe it down to the olvidURLHandler
        if let opendIdRedirectURL = olvidURL.isOpenIdRedirectWithURL {
            do {
                _ = try await KeycloakManagerSingleton.shared.resumeExternalUserAgentFlow(with: opendIdRedirectURL)
                os_log("Successfully resumed the external user agent flow", log: Self.log, type: .info)
            } catch {
                os_log("Failed to resume external user agent flow: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        } else {
            if let olvidURLHandler = self.presentedViewController as? OlvidURLHandler {
                // When the onboarding is presented (e.g., to create a second profile), this allows to pass any scanned URL to it (in particular, keycloak configurations)
                await olvidURLHandler.handleOlvidURL(olvidURL)
            } else {
                guard let olvidURLHandler = self.children.compactMap({ $0 as? OlvidURLHandler }).first else { assertionFailure(); return }
                await olvidURLHandler.handleOlvidURL(olvidURL)
            }
        }
    }

}


// MARK: - Refreshing the view context on certain Core Data notifications


extension MetaFlowController {
    
    @MainActor
    private func refreshViewContextsRegisteredObjectsOnUpdateOfPersistedObvContactIdentity(with contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>) async {
        guard let contact = ObvStack.shared.viewContext.registeredObject(for: contactObjectID.objectID) as? PersistedObvContactIdentity else { return }
        ObvStack.shared.viewContext.refresh(contact, mergeChanges: true)
        guard let oneToOneDiscussionObjectID = contact.oneToOneDiscussion?.objectID else { return }
        guard let oneToOneDiscussion = ObvStack.shared.viewContext.registeredObject(for: oneToOneDiscussionObjectID) as? PersistedOneToOneDiscussion else { return }
        ObvStack.shared.viewContext.refresh(oneToOneDiscussion, mergeChanges: true)
    }
 
    
    @MainActor
    private func refreshViewContextsRegisteredObjectsOnUpdateOfFyleMessageJoinWithStatus(with fyleMessageJoinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) async {
        guard let join = ObvStack.shared.viewContext.registeredObject(for: fyleMessageJoinObjectID.objectID) as? FyleMessageJoinWithStatus else { return }
        ObvStack.shared.viewContext.refresh(join, mergeChanges: true)
        guard let messageObjectID = join.message?.objectID else { return }
        guard let message = ObvStack.shared.viewContext.registeredObject(for: messageObjectID) as? PersistedMessage else { return }
        ObvStack.shared.viewContext.refresh(message, mergeChanges: true)
    }
    
}


// MARK: - Errors

extension MetaFlowController {
    
    enum ObvError: LocalizedError {
        case couldNotFindOwnedIdentity
        case couldNotCompressImage
        case theAppBackupDelegateIsNotSet
        case ckAccountStatusError(title: String, message: String?)
        case installedOlvidAppIsOutdated
        case storeKitDelegateIsNil
        
        var errorDescription: String? {
            switch self {
            case .couldNotFindOwnedIdentity:
                return "Could not find owned identity"
            case .couldNotCompressImage:
                return "Could not compress image"
            case .theAppBackupDelegateIsNotSet:
                return "The app backup delegate is not set"
            case .ckAccountStatusError(title: let title, message: _):
                return title
            case .installedOlvidAppIsOutdated:
                return "The installed Olvid App is outdated"
            case .storeKitDelegateIsNil:
                return "The store kit delegate is nil"
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .couldNotFindOwnedIdentity:
                return nil
            case .couldNotCompressImage:
                return nil
            case .theAppBackupDelegateIsNotSet:
                return nil
            case .ckAccountStatusError(_, let message):
                return message
            case .installedOlvidAppIsOutdated:
                return nil
            case .storeKitDelegateIsNil:
                return nil
            }
        }
        
    }
    
}
