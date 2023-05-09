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
import ObvTypes
import AVFoundation
import LinkPresentation
import SwiftUI
import ObvCrypto


final class MainFlowViewController: UISplitViewController, OlvidURLHandler, ObvFlowControllerDelegate {
    
    private(set) var currentOwnedCryptoId: ObvCryptoId
    private let obvEngine: ObvEngine
    var anOwnedIdentityWasJustCreatedOrRestored = false

    private let splitDelegate: MainFlowViewControllerSplitDelegate // Strong reference to the delegate
    private weak var createPasscodeDelegate: CreatePasscodeDelegate?
    private weak var appBackupDelegate: AppBackupDelegate?

    fileprivate let mainTabBarController = ObvSubTabBarController()

    private let discussionsFlowViewController: DiscussionsFlowViewController
    private let contactsFlowViewController: ContactsFlowViewController
    private let groupsFlowViewController: GroupsFlowViewController
    private let invitationsFlowViewController: InvitationsFlowViewController

    private var shouldPopViewController = false
    private var shouldScrollToTop = false
    
    private var observationTokens = [NSObjectProtocol]()
    
    private var ownedIdentityIsNotActiveViewControllerWasShowAtLeastOnce = false
    
    private var secureCallsInBetaModalWasShown = false
    
    /// This variable is set when Olvid is started because an invite or configuration link was opened.
    /// When this happens, this link is processed as soon as this view controller's view appears.
    private var externallyScannedOrTappedOlvidURL: OlvidURL?
    private var viewDidAppearWasCalled = false
    
    private var externallyScannedOrTappedOlvidURLExpectingAnOwnedIdentityToBeChosen: OlvidURL?
    
    struct ChildTypes {
        static let latestDiscussions = 0
        static let contacts = 1
        // We skip 2 since it corresponds to a "hidden" button
        static let groups = 3
        static let invitations = 4
    }
    
    // When an AirDrop deeplink is performed at a time no discussion is presented, we keep the file URL here so as to insert the file in the chosen discussion.
    private var airDroppedFileURLs = [URL]()
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: MainFlowViewController.self))
    
    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, createPasscodeDelegate: CreatePasscodeDelegate, appBackupDelegate: AppBackupDelegate) {
                
        os_log("🥏🏁 Call to the initializer of MainFlowViewController", log: log, type: .info)
        
        self.obvEngine = obvEngine
        self.currentOwnedCryptoId = ownedCryptoId
        self.createPasscodeDelegate = createPasscodeDelegate
        self.appBackupDelegate = appBackupDelegate
        self.splitDelegate = MainFlowViewControllerSplitDelegate()
        
        discussionsFlowViewController = DiscussionsFlowViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        mainTabBarController.addChild(discussionsFlowViewController)

        contactsFlowViewController = ContactsFlowViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        mainTabBarController.addChild(contactsFlowViewController)
                
        groupsFlowViewController = GroupsFlowViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        mainTabBarController.addChild(groupsFlowViewController)

        invitationsFlowViewController = InvitationsFlowViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        mainTabBarController.addChild(invitationsFlowViewController)

        super.init(nibName: nil, bundle: nil)

        self.delegate = splitDelegate
        self.preferredDisplayMode = .allVisible
        
        let navForDetailsView = UINavigationController()
        navForDetailsView.delegate = ObvUserActivitySingleton.shared
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navForDetailsView.navigationBar.standardAppearance = appearance
        self.viewControllers = [mainTabBarController, navForDetailsView]
        
        mainTabBarController.delegate = self
        mainTabBarController.obvDelegate = self
        discussionsFlowViewController.flowDelegate = self
        contactsFlowViewController.flowDelegate = self
        groupsFlowViewController.flowDelegate = self
        invitationsFlowViewController.flowDelegate = self
        
        // If the user has no contact, go to the contact tab
        
        if let contactCount = try? PersistedObvContactIdentity.countContactsOfOwnedIdentity(ownedCryptoId, whereOneToOneStatusIs: .oneToOne, within: ObvStack.shared.viewContext), contactCount == 0 {
            mainTabBarController.selectedIndex = ChildTypes.contacts
        }
                
        // Listen to notifications
        
        observeUserWantsToShareOwnPublishedDetailsNotifications()
        observeUserWantsToCallNotifications()
        observeServerDoesNotSupportCall()
        observeUserWantsToSelectAndCallContactsNotifications()
        observeCallHasBeenUpdated()

        observationTokens.append(contentsOf: [

            // ObvMessengerCoreDataNotification
            ObvMessengerCoreDataNotification.observeOwnedIdentityWasDeactivated(queue: .main) { [weak self] _ in
                self?.presentOwnedIdentityIsNotActiveViewControllerIfRequired()
            },
            
            // ObvEngineNotificationNew
            ObvEngineNotificationNew.observeNetworkOperationFailedSinceOwnedIdentityIsNotActive(within: NotificationCenter.default, queue: .main) { [weak self] (_) in
                self?.presentOwnedIdentityIsNotActiveViewControllerIfRequired()
            },
            
            // ObvMessengerInternalNotification
            ObvMessengerInternalNotification.observeUserWantsToDisplayContactIntroductionScreen(queue: .main) { [weak self] contactObjectID, viewController in
                self?.processUserWantsToDisplayContactIntroductionScreen(contactObjectID: contactObjectID, viewController: viewController)
            },
            ObvMessengerInternalNotification.observeOlvidSnackBarShouldBeShown(queue: .main) { [weak self] ownedCryptoId, category in
                self?.showSnackBarOnAllTabBarChildren(with: category, forOwnedIdentity: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeOlvidSnackBarShouldBeHidden(queue: .main) { [weak self] ownedCryptoId in
                self?.hideSnackBarOnAllTabBarChildren(forOwnedIdentity: ownedCryptoId)
            },
            ObvMessengerInternalNotification.observeUserWantsToSeeDetailedExplanationsOfSnackBar(queue: .main) { [weak self] ownedCryptoId, snackBarCategory in
                self?.processUserWantsToSeeDetailedExplanationsOfSnackBar(ownedCryptoId: ownedCryptoId, snackBarCategory: snackBarCategory)
            },
            ObvMessengerInternalNotification.observeUserWantsToSendInvite { [weak self] (ownedIdentity, urlIdentity) in
                self?.sendInvite(to: urlIdentity.cryptoId, withFullDisplayName: urlIdentity.fullDisplayName, for: ownedIdentity.cryptoId)
            },
            ObvMessengerInternalNotification.observeBadgeForNewMessagesHasBeenUpdated(queue: OperationQueue.main) { [weak self] ownedCryptoId, newCount in
                self?.processBadgeForNewMessagesHasBeenUpdated(ownCryptoId: ownedCryptoId, newCount: newCount)
            },
            ObvMessengerInternalNotification.observeBadgeForInvitationsHasBeenUpdated(queue: OperationQueue.main) { [weak self] ownedCryptoId, newCount in
                self?.processBadgeForInvitationsHasBeenUpdated(ownCryptoId: ownedCryptoId, newCount: newCount)
            },
            ObvMessengerInternalNotification.observeUserWantsToDeleteOwnedIdentityButHasNotConfirmedYet { [weak self] ownedCryptoId in
                Task { await self?.processUserWantsToDeleteOwnedIdentityButHasNotConfirmedYet(ownedCryptoId: ownedCryptoId) }
            },
        ])
    }
    
    
    /// Called by the MetaFlowController (itself called by the SceneDelegate).
    @MainActor
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        if viewDidAppearWasCalled == true {
            presentOneOfTheModalViewControllersIfRequired()
        }
        presentOwnedIdentityIsNotActiveViewControllerIfRequired()
    }

    
    /// Called by the MetaFlowController (itself called by the SceneDelegate).
    @MainActor
    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        airDroppedFileURLs.removeAll()
    }

    
    /// Called when the user tap the button shown on the snackbar view.
    @MainActor
    private func processUserWantsToSeeDetailedExplanationsOfSnackBar(ownedCryptoId: ObvCryptoId, snackBarCategory: OlvidSnackBarCategory) {
        guard self.currentOwnedCryptoId == ownedCryptoId else { return }
        
        let vc = OlvidAlertViewController()
        vc.configure(
            title: snackBarCategory.detailsTitle,
            body: snackBarCategory.detailsBody,
            primaryActionTitle: snackBarCategory.primaryActionTitle,
            primaryAction: { [weak self] in
                (self?.presentedViewController as? OlvidAlertViewController)?.dismiss(animated: true) {
                    switch snackBarCategory {
                    case .createBackupKey, .shouldPerformBackup, .shouldVerifyBackupKey, .lastUploadBackupHasFailed:
                        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .backupSettings)
                            .postOnDispatchQueue()
                    case .grantPermissionToRecord:
                        AVAudioSession.sharedInstance().requestRecordPermission { _ in
                            ObvMessengerInternalNotification.displayedSnackBarShouldBeRefreshed.postOnDispatchQueue()
                        }
                    case .grantPermissionToRecordInSettings:
                        guard let appSettings = URL(string: UIApplication.openSettingsURLString) else { assertionFailure(); return }
                        guard UIApplication.shared.canOpenURL(appSettings) else { assertionFailure(); return }
                        UIApplication.shared.open(appSettings, options: [:])
                    case .upgradeIOS:
                        break
                    case .newerAppVersionAvailable:
                        guard UIApplication.shared.canOpenURL(ObvMessengerConstants.shortLinkToOlvidAppIniTunes) else { assertionFailure(); return }
                        UIApplication.shared.open(ObvMessengerConstants.shortLinkToOlvidAppIniTunes, options: [:], completionHandler: nil)
                    case .announceGroupsV2:
                        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .allGroups(ownedCryptoId: ownedCryptoId))
                            .postOnDispatchQueue()
                    }
                }
            },
            secondaryActionTitle: snackBarCategory.secondaryActionTitle,
            secondaryAction: { [weak self] in
                (self?.presentedViewController as? OlvidAlertViewController)?.dismiss(animated: true) {
                    switch snackBarCategory {
                    case .createBackupKey, .shouldPerformBackup, .shouldVerifyBackupKey, .grantPermissionToRecord, .grantPermissionToRecordInSettings, .lastUploadBackupHasFailed:
                        ObvMessengerInternalNotification.UserDismissedSnackBarForLater(ownedCryptoId: ownedCryptoId, snackBarCategory: snackBarCategory)
                            .postOnDispatchQueue()
                    case .upgradeIOS:
                        ObvMessengerInternalNotification.UserDismissedSnackBarForLater(ownedCryptoId: ownedCryptoId, snackBarCategory: snackBarCategory)
                            .postOnDispatchQueue()
                    case .newerAppVersionAvailable:
                        ObvMessengerInternalNotification.UserDismissedSnackBarForLater(ownedCryptoId: ownedCryptoId, snackBarCategory: snackBarCategory)
                            .postOnDispatchQueue()
                    case .announceGroupsV2:
                        ObvMessengerSettings.Alert.AnnouncingGroupsV2.wasShownAndPermanentlyDismissedByUser = true
                        ObvMessengerInternalNotification.displayedSnackBarShouldBeRefreshed.postOnDispatchQueue()
                    }
                }
            })
        vc.modalPresentationStyle = .pageSheet
        if #available(iOS 15, *) {
            if let sheet = vc.sheetPresentationController {
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16.0
            }
        }
        self.present(vc, animated: true)
        
    }
    
    
    /// The current `ObvFlowController` currently on screen, if there is one.
    fileprivate var currentFlow: ObvFlowController? {
        switch mainTabBarController.selectedIndex {
        case ChildTypes.latestDiscussions:
            return discussionsFlowViewController
        case ChildTypes.contacts:
            return contactsFlowViewController
        case ChildTypes.groups:
            return groupsFlowViewController
        case ChildTypes.invitations:
            return invitationsFlowViewController
        default:
            assertionFailure()
            return nil
        }
    }
    
    private var alreadyPushingDiscussionViewController = false
    
    override func showDetailViewController(_ vc: UIViewController, sender: Any?) {
        guard !alreadyPushingDiscussionViewController else { return }
        alreadyPushingDiscussionViewController = true
        assert(Thread.isMainThread)
        guard let singleDiscussionVC = vc as? DiscussionViewController else {
            assertionFailure()
            super.showDetailViewController(vc, sender: sender)
            return
        }
        guard let flow = sender as? ObvFlowController else {
            assertionFailure()
            super.showDetailViewController(vc, sender: sender)
            return
        }
        if isCollapsed {
            // This is required to give time to the collection view to layout itself while scrolling to the bottom
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(33)) { [weak self] in
                flow.pushViewController(vc, animated: true)
                self?.alreadyPushingDiscussionViewController = false
            }
        } else {
            defer { alreadyPushingDiscussionViewController = false }
            guard viewControllers.count == 2 && viewControllers.last is UINavigationController else {
                let detailsNav = UINavigationController(rootViewController: vc)
                super.showDetailViewController(detailsNav, sender: sender)
                return
            }
            let detailsNav = viewControllers.last as! UINavigationController
            if flow is DiscussionsFlowViewController {
                if (detailsNav.viewControllers.first as? SingleDiscussionViewController)?.discussion.typedObjectID == singleDiscussionVC.discussionObjectID {
                    detailsNav.popToRootViewController(animated: true)
                } else {
                    detailsNav.setViewControllers([vc], animated: false)
                }
            } else {
                for vc in detailsNav.viewControllers {
                    if (vc as? SingleDiscussionViewController)?.discussion.typedObjectID == singleDiscussionVC.discussionObjectID {
                        detailsNav.popToViewController(vc, animated: true)
                        return
                    }
                }
                detailsNav.pushViewController(singleDiscussionVC, animated: true)
            }
        }
    }


    private func showSnackBarOnAllTabBarChildren(with category: OlvidSnackBarCategory, forOwnedIdentity ownedCryptoId: ObvCryptoId) {
        guard self.currentOwnedCryptoId == ownedCryptoId else { return }
        mainTabBarController.children.compactMap({ $0 as? ObvFlowController }).forEach { flowViewController in
            flowViewController.showSnackBar(with: category, currentOwnedCryptoId: ownedCryptoId, completion: {})
        }
    }
    
    
    private func hideSnackBarOnAllTabBarChildren(forOwnedIdentity ownedCryptoId: ObvCryptoId) {
        guard self.currentOwnedCryptoId == ownedCryptoId else { return }
        mainTabBarController.children.compactMap({ $0 as? ObvFlowController }).forEach { flowViewController in
            flowViewController.removeSnackBar(completion: {})
        }
    }
    
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    deinit {
        observationTokens.forEach {
            NotificationCenter.default.removeObserver($0)
        }
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearWasCalled = true
        if let olvidURL = externallyScannedOrTappedOlvidURL {
            os_log("Processing the URL of an external invitation or configuration link...", log: log, type: .info)
            externallyScannedOrTappedOlvidURL = nil
            Task { await processExternallyScannedOrTappedOlvidURL(olvidURL: olvidURL) }
        }
        if !ownedIdentityIsNotActiveViewControllerWasShowAtLeastOnce {
            presentOwnedIdentityIsNotActiveViewControllerIfRequired()
        }
        guard let obvOwnedIdentity = try? obvEngine.getOwnedIdentity(with: currentOwnedCryptoId) else { assertionFailure(); return }
        if obvOwnedIdentity.isKeycloakManaged {
            Task {
                await KeycloakManagerSingleton.shared.registerKeycloakManagedOwnedIdentity(ownedCryptoId: currentOwnedCryptoId, firstKeycloakBinding: false)
            }
        }
    }
    
    
    @MainActor
    private func presentOwnedIdentityIsNotActiveViewControllerIfRequired() {
        guard viewDidAppearWasCalled else { return }
        guard !anOwnedIdentityWasJustCreatedOrRestored else { return }
        let log = self.log
        ObvStack.shared.performBackgroundTask { [weak self] (context) in
            guard let _self = self else { return }
            guard let ownedIdentityObv = try? PersistedObvOwnedIdentity.get(cryptoId: _self.currentOwnedCryptoId, within: context) else {
                os_log("Could not find persisted owned identity", log: log, type: .fault)
                return
            }
            guard !ownedIdentityObv.isActive else { return }
            // If we reach this point, the current owned identity is not active. So we should present the appropriate view controller.
            DispatchQueue.main.async {
                // Check that we are not presenting an OwnedIdentityIsNotActiveViewController already
                if let presentedVC = self?.presentedViewController as? UINavigationController, presentedVC.children.filter({ $0 is OwnedIdentityIsNotActiveViewController }).isEmpty {
                    return
                }
                let ownedIdentityIsNotActiveVC = OwnedIdentityIsNotActiveViewController()
                let nav = ObvNavigationController(rootViewController: ownedIdentityIsNotActiveVC)
                self?.present(nav, animated: true)
                self?.ownedIdentityIsNotActiveViewControllerWasShowAtLeastOnce = true
            }
        }
    }
    
    
    @MainActor
    private func processUserWantsToDisplayContactIntroductionScreen(contactObjectID: TypeSafeManagedObjectID<PersistedObvContactIdentity>, viewController: UIViewController) {
        assert(Thread.isMainThread)
        
        guard let persistedContact = try? PersistedObvContactIdentity.get(objectID: contactObjectID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
        guard let ownedIdentity = persistedContact.ownedIdentity else {
            os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
            return
        }
        let contactsPresentationVC = ContactsPresentationViewController(ownedCryptoId: ownedIdentity.cryptoId, presentedContactCryptoId: persistedContact.cryptoId) {
            viewController.presentedViewController?.dismiss(animated: true)
        }
        guard let contactFromEngine = try? obvEngine.getContactIdentity(with: persistedContact.cryptoId, ofOwnedIdentityWith: ownedIdentity.cryptoId) else {
            assertionFailure()
            return
        }
        contactsPresentationVC.title = CommonString.Title.introduceTo(contactFromEngine.publishedIdentityDetails?.coreDetails.getDisplayNameWithStyle(.short) ?? persistedContact.shortOriginalName)
        viewController.present(contactsPresentationVC, animated: true)

    }

    
    private func presentOneOfTheModalViewControllersIfRequired() {
        // This shall be the last possible alert we check, since we can only do this asynchronously
        UNUserNotificationCenter.current().getNotificationSettings(completionHandler: { [weak self] (userNotificationSettings) in
            DispatchQueue.main.async {
                switch userNotificationSettings.authorizationStatus {
                case .notDetermined:
                    Task { await
                        self?.presentUserNotificationsSubscriberHostingController()
                    }
                default:
                    self?.presentOneOfTheOtherModalViewControllersIfRequired()
                }
            }
        })
        
    }
    
    
    @MainActor
    private func presentUserNotificationsSubscriberHostingController() async {
        self.dismiss(animated: true) { [weak self] in
            guard let _self = self else { return }
            let vc = AutorisationRequesterHostingController(autorisationCategory: .localNotifications, delegate: _self)
            _self.present(vc, animated: true)
        }
    }
    
    
    /// Shall only be called from `presentOneOfTheModalViewControllersIfRequired`
    @MainActor
    private func presentOneOfTheOtherModalViewControllersIfRequired() {
        assert(Thread.isMainThread)
        // Once the appropriate view controller has been displayed, check the user's device configuration. If something bad happens, present a view controller asking the user to update her configuration.
        let configChecker = DeviceConfigurationChecker()
        guard configChecker.currentConfigurationIsValid(application: UIApplication.shared) else {
            let badConfigurationViewController = BadConfigurationViewController()
            let nav = ObvNavigationController(rootViewController: badConfigurationViewController)
            present(nav, animated: true)
            return
        }
        guard (ObvMessengerSettings.AppVersionAvailable.minimum ?? 0) <= ObvMessengerConstants.bundleVersionAsInt else {
            let vc = OlvidAlertViewController()
            vc.configure(
                title: Strings.AlertInstalledAppIsOutDated.title,
                body: Strings.AlertInstalledAppIsOutDated.body,
                primaryActionTitle: Strings.AlertInstalledAppIsOutDated.primaryActionTitle,
                primaryAction: {
                    guard UIApplication.shared.canOpenURL(ObvMessengerConstants.shortLinkToOlvidAppIniTunes) else { assertionFailure(); return }
                    UIApplication.shared.open(ObvMessengerConstants.shortLinkToOlvidAppIniTunes, options: [:], completionHandler: nil)
                },
                secondaryActionTitle: CommonString.Word.Later,
                secondaryAction: { [weak self] in
                    self?.dismissPresentedViewController()
                })
            vc.modalPresentationStyle = .pageSheet
            if #available(iOS 15, *) {
                if let sheet = vc.sheetPresentationController {
                    sheet.detents = [.large()]
                    sheet.prefersGrabberVisible = true
                    sheet.preferredCornerRadius = 16.0
                }
            }
            self.present(vc, animated: true)
            return
        }
    }

}


// MARK: - Switching current owned identity

extension MainFlowViewController {
    
    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        guard self.currentOwnedCryptoId != newOwnedCryptoId else { return }
        self.currentOwnedCryptoId = newOwnedCryptoId
        await discussionsFlowViewController.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        await contactsFlowViewController.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        await groupsFlowViewController.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        await invitationsFlowViewController.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
    }
    
}


// MARK: - AutorisationRequesterHostingControllerDelegate

extension MainFlowViewController: AutorisationRequesterHostingControllerDelegate {
    
    @MainActor
    func requestAutorisation(now: Bool, for autorisationCategory: AutorisationRequesterHostingController.AutorisationCategory) async {
        assert(Thread.isMainThread)
        switch autorisationCategory {
        case .localNotifications:
            if now {
                let center = UNUserNotificationCenter.current()
                do {
                    try await center.requestAuthorization(options: [.alert, .sound, .badge])
                } catch {
                    os_log("Could not request authorization for notifications: %@", log: log, type: .error, error.localizedDescription)
                }
            }
            dismiss(animated: true)
        case .recordPermission:
            if now {
                let granted = await AVAudioSession.sharedInstance().requestRecordPermission()
                os_log("User granted access to audio: %@", log: log, type: .error, String(describing: granted))
            }
            dismiss(animated: true)
        }
    }

}


// MARK: - Setting/refreshing badges on the tabbar

extension MainFlowViewController {
    
    @MainActor
    private func processBadgeForNewMessagesHasBeenUpdated(ownCryptoId: ObvCryptoId, newCount: Int) {
        assert(Thread.isMainThread)
        guard ownCryptoId == self.currentOwnedCryptoId else { return }
        if let tabbarItem = mainTabBarController.viewControllers?[ChildTypes.latestDiscussions].tabBarItem {
            tabbarItem.badgeValue = newCount > 0 ? "\(newCount)" : nil
        }
    }
    
    
    @MainActor
    private func processBadgeForInvitationsHasBeenUpdated(ownCryptoId: ObvCryptoId, newCount: Int) {
        assert(Thread.isMainThread)
        guard ownCryptoId == self.currentOwnedCryptoId else { return }
        if let tabbarItem = mainTabBarController.viewControllers?[ChildTypes.invitations].tabBarItem {
            tabbarItem.badgeValue = newCount > 0 ? "\(newCount)" : nil
        }
    }
    
}


// MARK: - Deleting an owned profile

extension MainFlowViewController {
    
    @MainActor
    private func processUserWantsToDeleteOwnedIdentityButHasNotConfirmedYet(ownedCryptoId: ObvCryptoId) async {
        
        assert(Thread.isMainThread)
        dismissPresentedViewController()
        let traitCollection = self.traitCollection
        
        // Request deletion confirmation (it depends whether the profile to delete is the last visible profile or not)
        
        let alert: UIAlertController
        
        guard let ownedIdentityToDelete = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { return }
        ObvStack.shared.viewContext.refresh(ownedIdentityToDelete, mergeChanges: true)
        let profileName = ownedIdentityToDelete.customDisplayName ?? ownedIdentityToDelete.identityCoreDetails.getFullDisplayName()
        do {
            if try ownedIdentityToDelete.isLastUnhiddenOwnedIdentity {
                alert = UIAlertController(title: Strings.AlertConfirmLastUnhiddenProfileDeletion.title,
                                          message: Strings.AlertConfirmLastUnhiddenProfileDeletion.message,
                                          preferredStyleForTraitCollection: traitCollection)
            } else {
                alert = UIAlertController(title: Strings.AlertConfirmProfileDeletion.title(profileName),
                                          message: Strings.AlertConfirmProfileDeletion.message,
                                          preferredStyleForTraitCollection: traitCollection)
            }
        } catch {
            assertionFailure()
            return
        }
        let deleteAction = UIAlertAction(title: Strings.AlertConfirmProfileDeletion.actionDeleteProfile, style: .destructive) { [weak self] _ in
            
            let alert = UIAlertController(title: Strings.AlertNotifyContactsOnOwnedIdentityDeletion.title,
                                          message: Strings.AlertNotifyContactsOnOwnedIdentityDeletion.message,
                                          preferredStyleForTraitCollection: traitCollection)
            
            let notifyContactsAction = UIAlertAction(title: Strings.AlertNotifyContactsOnOwnedIdentityDeletion.notifyContactsAction, style: .default) { _ in
                self?.processUserWantsToDeleteOwnedIdentityAfterHavingConfirmed(ownedCryptoId: ownedCryptoId, notifyContacts: true)
            }
            let doNotNotifyContactsAction = UIAlertAction(title: Strings.AlertNotifyContactsOnOwnedIdentityDeletion.doNotNotifyContactsAction, style: .default) { _ in
                self?.processUserWantsToDeleteOwnedIdentityAfterHavingConfirmed(ownedCryptoId: ownedCryptoId, notifyContacts: false)
            }
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .default)
            alert.addAction(notifyContactsAction)
            alert.addAction(doNotNotifyContactsAction)
            alert.addAction(cancelAction)
            self?.present(alert, animated: true)
            
        }
        let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .default)
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)
        present(alert, animated: true)
        
    }
    
    
    /// This method is called last during the UI process allowing to delete an owned identity. It allows to make sure that the does want to delete her owned identity by asking her to write the DELETE word.
    private func processUserWantsToDeleteOwnedIdentityAfterHavingConfirmed(ownedCryptoId: ObvCryptoId, notifyContacts: Bool) {
        guard let ownedIdentityToDelete = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { return }
        let profileName = ownedIdentityToDelete.customDisplayName ?? ownedIdentityToDelete.identityCoreDetails.getFullDisplayName()

        let alert = UIAlertController(title: Strings.AlertTypeDeleteToProceedWithOwnedIdentityDeletion.title(profileName),
                                      message: Strings.AlertTypeDeleteToProceedWithOwnedIdentityDeletion.message,
                                      preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = NSLocalizedString("", comment: "")
            textField.autocapitalizationType = .allCharacters
        }
        alert.addAction(UIAlertAction(title: Strings.AlertTypeDeleteToProceedWithOwnedIdentityDeletion.doDelete, style: .destructive, handler: { [unowned alert] _ in
            guard let textField = alert.textFields?.first else { assertionFailure(); return }
            guard textField.text?.trimmingWhitespacesAndNewlines() == Strings.AlertTypeDeleteToProceedWithOwnedIdentityDeletion.wordToType else { return }
            ObvMessengerInternalNotification.userWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ownedCryptoId, notifyContacts: notifyContacts)
                .postOnDispatchQueue()
        }))
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
        present(alert, animated: true)

        
    }

}


// MARK: - ObvFlowControllerDelegate

extension MainFlowViewController {

    
    func userSelectedURL(_ url: URL, within viewController: UIViewController) {
        userSelectedURL(url, within: viewController, confirmed: false)
    }
    
    
    @MainActor
    private func userSelectedURL(_ url: URL, within viewController: UIViewController, confirmed: Bool) {

        if confirmed {

            UIApplication.shared.open(url, options: [:], completionHandler: nil)

        } else {

            let alert = UIAlertController(title: Strings.AlertOpenURL.title,
                                          message: Strings.AlertOpenURL.message(url),
                                          preferredStyleForTraitCollection: viewController.traitCollection)

            alert.addAction(UIAlertAction(title: Strings.AlertOpenURL.openButton, style: .default, handler: { [weak self] (action) in
                self?.userSelectedURL(url, within: viewController, confirmed: true)
            }))

            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            DispatchQueue.main.async {
                viewController.present(alert, animated: true, completion: nil)
            }

        }

    }

    
    func performTrustEstablishmentProtocolOfRemoteIdentity(remoteCryptoId: ObvCryptoId, remoteFullDisplayName: String) {
         self.performTrustEstablishmentProtocolOfRemoteIdentity(contactCryptoId: remoteCryptoId, contactFullDisplayName: remoteFullDisplayName, ownedCryptoId: currentOwnedCryptoId, confirmed: false)
    }
    
    
    func rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: ObvCryptoId, contactFullDisplayName: String) {
        self.rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: contactCryptoId, contactFullDisplayName: contactFullDisplayName, ownedCryptoId: currentOwnedCryptoId, confirmed: false)
    }
    
    @MainActor
    private func userWantsToAddContact(sourceView: UIView, alreadyScannedOrTappedURL: OlvidURL?) {
        
        assert(Thread.isMainThread)
        
        let obvOwnedIdentity: ObvOwnedIdentity
        do {
            obvOwnedIdentity = try obvEngine.getOwnedIdentity(with: currentOwnedCryptoId)
        } catch {
            os_log("Could not get Owned Identity from Engine", log: log, type: .fault)
            assertionFailure()
            return
        }
        guard let vc = AddContactHostingViewController(
            obvOwnedIdentity: obvOwnedIdentity,
            alreadyScannedOrTappedURL: alreadyScannedOrTappedURL,
            dismissAction: { [weak self] in self?.dismissPresentedViewController() },
            checkSignatureMutualScanUrl: { [weak self] mutualScanUrl in
                guard let _self = self else { return false }
                return _self.checkSignatureMutualScanUrl(mutualScanUrl)
            })
        else {
            assertionFailure()
            return
        }
        dismiss(animated: true) {
            self.present(vc, animated: true)
        }
        
    }
    

    private func checkAuthorizationStatusThenSetupAndPresentQRCodeScanner() {
        assert(Thread.isMainThread)
        switch AVCaptureDevice.authorizationStatus(for: AVMediaType.video) {
        case .authorized:
            setupAndPresentQRCodeScanner()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupAndPresentQRCodeScanner()
                    }
                }
            }
        case .denied,
             .restricted:
            let NotificationType = MessengerInternalNotification.UserTriedToAccessCameraButAccessIsDenied.self
            NotificationCenter.default.post(name: NotificationType.name, object: nil)
        @unknown default:
            assertionFailure("A recent AVCaptureDevice.authorizationStatus is not properly handled")
            return
        }
    }
    

    /// Do not call this function directly. Use ``func checkAuthorizationStatusThenSetupAndPresentQRCodeScanner()`` instead.
    @MainActor
    private func setupAndPresentQRCodeScanner() {
        assert(Thread.isMainThread)
        let vc = ScannerHostingView(buttonType: .back, delegate: self)
        let nav = UINavigationController(rootViewController: vc)
        // Configure the ScannerHostingView properly for the navigation controller
        vc.title = NSLocalizedString("SCAN_QR_CODE", comment: "")
        dismiss(animated: false) { [weak self] in
            self?.present(nav, animated: true)
        }
    }
    
    
    func userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(with contactCryptoId: ObvCryptoId, using newContactIdentityDetails: ObvIdentityDetails) {
        do {
            try obvEngine.updateTrustedIdentityDetailsOfContactIdentity(with: contactCryptoId, ofOwnedIdentityWithCryptoId: currentOwnedCryptoId, with: newContactIdentityDetails)
        } catch {
            os_log("Could not update trusted identity details of a contact", log: log, type: .error)
        }
    }
    
    
    @objc private func dismissDisplayNameChooserViewController() {
        presentedViewController?.view.endEditing(true)
        presentedViewController?.dismiss(animated: true)
    }

    
    @MainActor
    @objc func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

    private func checkSignatureMutualScanUrl(_ mutualScanUrl: ObvMutualScanUrl) -> Bool {
        return obvEngine.verifyMutualScanUrl(ownedCryptoId: currentOwnedCryptoId, mutualScanUrl: mutualScanUrl)
    }
    
    func userAskedToRefreshDiscussions(completionHandler: @escaping () -> Void) {
        let NotificationType = MessengerInternalNotification.UserWantsToRefreshDiscussions.self
        let userInfo = [NotificationType.Key.completionHandler: completionHandler]
        NotificationCenter.default.post(name: NotificationType.name, object: nil, userInfo: userInfo)
    }

}


// MARK: - UITabBarControllerDelegate && ObvSubTabBarControllerDelegate

extension MainFlowViewController: UITabBarControllerDelegate, ObvSubTabBarControllerDelegate {

    
    func middleButtonTapped(sourceView: UIView) {
        userWantsToAddContact(sourceView: sourceView, alreadyScannedOrTappedURL: nil)
    }
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        
        // If the user taps on the tab of the currently selected view controller, we unwind the controllers of the current navigation controller
        
        guard let selectedViewController = tabBarController.selectedViewController as? ObvFlowController else { assertionFailure(); return true }

        if viewController == selectedViewController {
            if selectedViewController.viewControllers.count > 1 {
                shouldPopViewController = true
            } else {
                shouldScrollToTop = true
            }
        }
        
        return true
        
    }
    
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        
        guard shouldPopViewController || shouldScrollToTop else { return }
        defer {
            shouldPopViewController = false
            shouldScrollToTop = false
        }
        
        guard let selectedFlowController = tabBarController.selectedViewController as? ObvFlowController else { return }

        if shouldPopViewController {
            selectedFlowController.popToRootViewController(animated: true)
        }
        
        if shouldScrollToTop {
            // Scroll to the top of the table view (if there is one) displayed by root view controller
            if let currentViewController = selectedFlowController.viewControllers.first, let vc = currentViewController as? CanScrollToTop {
                vc.scrollToTop()
            }
        }
        
    }
    
}


// MARK: - Handling DeepLinks

extension MainFlowViewController {
        
    
    private func observeUserWantsToShareOwnPublishedDetailsNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToShareOwnPublishedDetails { [weak self] (ownedCryptoId, sourceView) in
            guard self?.currentOwnedCryptoId == ownedCryptoId else { return }
            self?.presentUIActivityViewControllerForSharingOwnPublishedDetails(sourceView: sourceView)
        })
    }
    
    
    /// When the user wants to emit a call, an internal notification is sent and catched here. We check that the user is allowed to make this call.
    /// If this is the case, we send an appropriate notification that will be catched by the call manager.
    /// Otherwise, we show the subscription plans.
    private func observeUserWantsToCallNotifications() {
        os_log("📲 Observing UserWantsToCall notifications", log: log, type: .info)
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToCallButWeShouldCheckSheIsAllowedTo(queue: .main) { [weak self] (contactIDs, groupId) in
            self?.processUserWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: contactIDs, groupId: groupId)
        })
    }
    
    
    @MainActor
    private func processUserWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: [TypeSafeManagedObjectID<PersistedObvContactIdentity>], groupId: GroupIdentifierBasedOnObjectID?) {
        assert(Thread.isMainThread)
        
        // Check access to the microphone
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.processUserWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: contactIDs, groupId: groupId)
                    }
                } else {
                    ObvMessengerInternalNotification.requestUserDeniedRecordPermissionAlert.postOnDispatchQueue()
                }
            }
            return
        }

        guard !contactIDs.isEmpty else { assertionFailure(); return }
        let contacts = contactIDs.compactMap({try? PersistedObvContactIdentity.get(objectID: $0, within: ObvStack.shared.viewContext)})
        guard contacts.count == contactIDs.count else {
            os_log("One of the contacts to be called could not be fetched from database", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        // Make sure we have a channel with all contacts
        let contactWithoutChannel = contacts.first(where: { $0.devices.isEmpty })
        guard contactWithoutChannel == nil else {
            let contactName = contactWithoutChannel!.customOrNormalDisplayName
            let alert = UIAlertController(title: Strings.MissingChannelForCallAlert.title(contactName),
                                          message: Strings.MissingChannelForCallAlert.message(contactName),
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: nil))
            present(alert, animated: true)
            return
        }
        
        // Make sure all the contacts concern the same owned identity
        let ownedIdentities = Set(contacts.compactMap({ $0.ownedIdentity }))
        guard ownedIdentities.count == 1 else {
            os_log("Trying to call contacts from distinct owned identities. This is a bug.", log: log, type: .fault)
            assertionFailure()
            return
        }
        let ownedIdentity = ownedIdentities.first!
        
        let contactIds = contacts.map({ OlvidUserId.known(contactObjectID: $0.typedObjectID, ownCryptoId: ownedIdentity.cryptoId, remoteCryptoId: $0.cryptoId, displayName: $0.fullDisplayName) })

        // If the owned identity is allowed to make outgoing calls, we use it to request turn credentials. If it is not, we look for another owned identity that is allowed to and use it (exclusively) to request turn credentials.
        // This way, if one identity it allowed to make outgoing calls, all other owned identity are as well.
        let ownedIdentityForRequestingTurnCredentials: ObvCryptoId?
        if ownedIdentity.apiPermissions.contains(.canCall) {
            ownedIdentityForRequestingTurnCredentials = ownedIdentity.cryptoId
        } else if let ownedIdentityAllowedToCall = try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext).first(where: { $0.apiPermissions.contains(.canCall) }) {
            ownedIdentityForRequestingTurnCredentials = ownedIdentityAllowedToCall.cryptoId
        } else {
            ownedIdentityForRequestingTurnCredentials = nil
        }
        
        if let ownedIdentityForRequestingTurnCredentials {
            ObvMessengerInternalNotification.userWantsToCallAndIsAllowedTo(contactIds: contactIds, ownedIdentityForRequestingTurnCredentials: ownedIdentityForRequestingTurnCredentials, groupId: groupId)
                .postOnDispatchQueue()
        } else {
            let vc = UserTriesToAccessPaidFeatureHostingController(requestedPermission: .canCall, ownedCryptoId: ownedIdentity.cryptoId)
            dismiss(animated: true) { [weak self] in
                self?.present(vc, animated: true)
            }
        }
    }
    

    private func observeUserWantsToSelectAndCallContactsNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToSelectAndCallContacts(queue: OperationQueue.main) { [weak self] (allContactsID, groupId)  in
            guard !allContactsID.isEmpty else { return }
            var contacts: [PersistedObvContactIdentity] = []
            for contactID in allContactsID {
                guard let contact = try? PersistedObvContactIdentity.get(objectID: contactID, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
                guard !contact.devices.isEmpty else { continue }
                contacts += [contact]
            }
            guard !contacts.isEmpty else { return }
            guard let ownedIdentity = contacts.first?.ownedIdentity else { assertionFailure(); return }

            var contactCryptoIds = Set<ObvCryptoId>()
            if let groupId = groupId {
                switch groupId {
                case .groupV1(let objectID):
                    if let contactGroup = try? PersistedContactGroup.get(objectID: objectID.objectID, within: ObvStack.shared.viewContext) {
                        contactGroup.contactIdentities.forEach { contactCryptoIds.insert($0.cryptoId) }
                    }
                case .groupV2(let objectID):
                    if let group = try? PersistedGroupV2.get(objectID: objectID, within: ObvStack.shared.viewContext) {
                        group.contactsAmongNonPendingOtherMembers.forEach { contactCryptoIds.insert($0.cryptoId) }
                    }
                }
            } else {
                contacts.forEach { contactCryptoIds.insert($0.cryptoId) }
            }

            let button = MultipleContactsButton.floating(title: CommonString.Word.Call, systemIcon: .phoneFill)

            let vc = MultipleContactsViewController(ownedCryptoId: ownedIdentity.cryptoId,
                                                    mode: .restricted(to: contactCryptoIds, oneToOneStatus: .any),
                                                    button: button, defaultSelectedContacts: Set(contacts),
                                                    disableContactsWithoutDevice: true,
                                                    allowMultipleSelection: true,
                                                    showExplanation: false,
                                                    allowEmptySetOfContacts: false,
                                                    textAboveContactList: nil,
                                                    selectionStyle: .checkmark) { selectedContacts in

                ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: selectedContacts.map({ $0.typedObjectID }), groupId: groupId).postOnDispatchQueue()

                self?.dismiss(animated: true)
            } dismissAction: {
                self?.dismiss(animated: true)
            }
            let nav = ObvNavigationController(rootViewController: vc)

            if let presentedViewController = self?.presentedViewController {
                presentedViewController.present(nav, animated: true)
            } else {
                self?.present(nav, animated: true)
            }
        })
    }

    private func observeServerDoesNotSupportCall() {
        observationTokens.append(VoIPNotification.observeServerDoesNotSupportCall(queue: OperationQueue.main) { [weak self] in
            let alert = UIAlertController(title: Strings.ServerDoesNotSupportCallAlert.title, message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
            if let presentedViewController = self?.presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                self?.present(alert, animated: true)
            }
        })
    }

    private func observeCallHasBeenUpdated() {
        observationTokens.append(VoIPNotification.observeCallHasBeenUpdated(queue: OperationQueue.main) { [weak self] _, updateKind in
            guard case .state(let newState) = updateKind else { return }
            guard newState == .kicked else { return }

            let alert = UIAlertController(title: Strings.UserHasBeenKilled.title, message: nil, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
            if let presentedViewController = self?.presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                self?.present(alert, animated: true)
            }
        })
    }
    
    @MainActor
    private func presentUIActivityViewControllerForSharingOwnPublishedDetails(sourceView: UIView) {
        guard let obvOwnedIdentity = try? obvEngine.getOwnedIdentity(with: currentOwnedCryptoId) else { return }
        let genericIdentityForSharing = ObvGenericIdentityForSharing(genericIdentity: obvOwnedIdentity.getGenericIdentity())
        let activityItems: [Any] = [genericIdentityForSharing]
        let uiActivityVC = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        uiActivityVC.excludedActivityTypes = [.addToReadingList, .openInIBooks, .markupAsPDF]
        uiActivityVC.popoverPresentationController?.sourceView = sourceView
        if let presentedViewController = self.presentedViewController {
            presentedViewController.present(uiActivityVC, animated: true)
        } else {
            self.present(uiActivityVC, animated: true)
        }
    }
    
    
    /// This method shall only be called from the MetaFlowController. The reason we do not listen to notifications in this class is that it is
    /// initialized late in the app initialization process and thus, we could miss deep link navigation notifications sent earlier.
    @MainActor
    func performCurrentDeepLinkInitialNavigation(deepLink: ObvDeepLink) async {
        assert(Thread.isMainThread)
        os_log("🥏 Performing deep link initial navigation to %{public}@", log: log, type: .info, deepLink.description)
        
        /* Before performing the navigation, we switch to the appropriate owned cryptoId if appropriate. If the ownedCryptoId concerns a hidden profile,
         * we do *not* switch to it and only continue the navigation if the current owned identity corresponds to this hiddent profile.
         * If not, we do not perform navigation.
         */
        if let ownedCryptoId = deepLink.ownedCryptoId {
            guard let persistedOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { return }
            if persistedOwnedIdentity.isHidden {
                guard currentOwnedCryptoId == ownedCryptoId else {
                    // We do not switch to a hidden profile simply by receiving a deeplink
                    return
                }
            } else {
                await switchCurrentOwnedCryptoId(to: ownedCryptoId)
            }
        }
        
        switch deepLink {
            
        case .myId(ownedCryptoId: let ownedCryptoId):
            os_log("🥏 The current deep link is a myId", log: log, type: .info)
            guard let ownedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { assertionFailure(); return }
            presentedViewController?.dismiss(animated: true)
            let vc = SingleOwnedIdentityFlowViewController(ownedIdentity: ownedIdentity, obvEngine: obvEngine)
            let nav = UINavigationController(rootViewController: vc)
            vc.delegate = self
            present(nav, animated: true)
            
        case .latestDiscussions:
            mainTabBarController.selectedIndex = ChildTypes.latestDiscussions
            presentedViewController?.dismiss(animated: true)
            
        case .allGroups:
            mainTabBarController.selectedIndex = ChildTypes.groups
            presentedViewController?.dismiss(animated: true)

        case .qrCodeScan:
            os_log("🥏 The current deep link is a qrCodeScan", log: log, type: .info)
            // We do not need to navigate anywhere. We just show the QR code scanner.
            presentedViewController?.dismiss(animated: true)
            checkAuthorizationStatusThenSetupAndPresentQRCodeScanner()

        case .singleDiscussion(ownedCryptoId: _, objectPermanentID: let discussionPermanentID):
            mainTabBarController.selectedIndex = ChildTypes.latestDiscussions
            presentedViewController?.dismiss(animated: true)
            guard let discussion = try? PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: ObvStack.shared.viewContext) else { return }
            discussionsFlowViewController.userWantsToDisplay(persistedDiscussion: discussion)

        case .invitations:
            mainTabBarController.selectedIndex = ChildTypes.invitations
            presentedViewController?.dismiss(animated: true)
            
        case .contactGroupDetails(ownedCryptoId: _, objectPermanentID: let displayedContactGroupPermanentID):
            _ = groupsFlowViewController.popToRootViewController(animated: false)
            mainTabBarController.selectedIndex = ChildTypes.groups
            presentedViewController?.dismiss(animated: true)
            guard let displayedContactGroup = try? DisplayedContactGroup.getManagedObject(withPermanentID: displayedContactGroupPermanentID, within: ObvStack.shared.viewContext) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let _self = self else { return }
                if let allGroupsViewController = _self.groupsFlowViewController.topViewController as? NewAllGroupsViewController {
                    allGroupsViewController.selectRowOfDisplayedContactGroup(displayedContactGroup)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let _self = self else { return }
                    _self.groupsFlowViewController.userWantsToNavigateToSingleGroupView(displayedContactGroup, within: _self.groupsFlowViewController)
                }
            }
            
        case .contactIdentityDetails(ownedCryptoId: _, objectPermanentID: let contactPermanentID):
            _ = contactsFlowViewController.popToRootViewController(animated: false)
            mainTabBarController.selectedIndex = ChildTypes.contacts
            presentedViewController?.dismiss(animated: true)
            guard let contactIdentity = try? PersistedObvContactIdentity.getManagedObject(withPermanentID: contactPermanentID, within: ObvStack.shared.viewContext) else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let _self = self else { return }
                if let allContactsViewController = _self.contactsFlowViewController.topViewController as? AllContactsViewController {
                    allContactsViewController.selectRowOfContactIdentity(contactIdentity)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let _self = self else { return }
                    _self.contactsFlowViewController.userWantsToDisplay(persistedContact: contactIdentity
                        , within: _self.contactsFlowViewController)
                }
            }
            
        case .airDrop(fileURL: let fileURL):
            if let discussionVC = currentDiscussionViewControllerShownToUser() {
                // The user is currently within a discussion. We add the AirDrop'ed files within that discussion
                discussionVC.addAttachmentFromAirDropFile(at: fileURL)
            } else {
                // The user is not within a discussion. Go to the list of latest discussions and wait until a discussion is chosen
                // We save the file URL
                mainTabBarController.selectedIndex = ChildTypes.latestDiscussions
                _ = discussionsFlowViewController.children.first?.navigationController?.popViewController(animated: true)
                DispatchQueue.main.async { [weak self] in
                    guard let _self = self else { return }
                    _self.airDroppedFileURLs.append(fileURL)
                    guard !_self.hudIsShown() else { return }
                    _self.showHUD(type: ObvHUDType.text(text: Strings.chooseDiscussion), completionHandler: nil)
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { [weak self] in
                        self?.hideHUD()
                    }
                 }
            }
        case .requestRecordPermission:
            switch AVAudioSession.sharedInstance().recordPermission {
            case .undetermined:
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    guard granted else {
                        ObvMessengerInternalNotification.rejectedIncomingCallBecauseUserDeniedRecordPermission
                            .postOnDispatchQueue()
                        return
                    }
                }
            case .denied:
                ObvMessengerInternalNotification.rejectedIncomingCallBecauseUserDeniedRecordPermission
                    .postOnDispatchQueue()
            case .granted:
                break
            @unknown default:
                break
            }

        case .settings:
            assert(Thread.isMainThread)
            if let presentedViewController = self.presentedViewController {
                presentedViewController.dismiss(animated: true) { [weak self] in
                    self?.presentSettingsFlowViewController()
                }
            } else {
                presentSettingsFlowViewController()
            }
            
        case .backupSettings:
            assert(Thread.isMainThread)
            if let presentedViewController = self.presentedViewController {
                presentedViewController.dismiss(animated: true) { [weak self] in
                    self?.presentSettingsFlowViewController(specificSetting: .backup)
                }
            } else {
                presentSettingsFlowViewController(specificSetting: .backup)
            }
            
        case .privacySettings:
            assert(Thread.isMainThread)
            if let presentedViewController = self.presentedViewController {
                presentedViewController.dismiss(animated: true) { [weak self] in
                    self?.presentSettingsFlowViewController(specificSetting: .privacy)
                }
            } else {
                presentSettingsFlowViewController(specificSetting: .privacy)
            }

        case .message(ownedCryptoId: _, objectPermanentID: let objectPermanentID):
            mainTabBarController.selectedIndex = ChildTypes.latestDiscussions
            presentedViewController?.dismiss(animated: true)
            guard let message = try? PersistedMessage.getManagedObject(withPermanentID: objectPermanentID, within: ObvStack.shared.viewContext) else { return }
            discussionsFlowViewController.userWantsToDisplay(persistedMessage: message)
        }
        
    }

    
    @MainActor
    private func presentSettingsFlowViewController() {
        assert(Thread.isMainThread)
        guard let createPasscodeDelegate = self.createPasscodeDelegate else {
            assertionFailure(); return
        }
        guard let appBackupDelegate = self.appBackupDelegate else {
            assertionFailure(); return
        }
        let vc = SettingsFlowViewController(ownedCryptoId: currentOwnedCryptoId, obvEngine: obvEngine, createPasscodeDelegate: createPasscodeDelegate, appBackupDelegate: appBackupDelegate)
        let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(dismissPresentedViewController))
        vc.viewControllers.first?.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(vc, animated: true)
    }


    @MainActor
    private func presentSettingsFlowViewController(specificSetting: AllSettingsTableViewController.Setting) {
        assert(Thread.isMainThread)
        guard let createPasscodeDelegate = self.createPasscodeDelegate else {
            assertionFailure(); return
        }
        guard let appBackupDelegate = self.appBackupDelegate else {
            assertionFailure(); return
        }
        let vc = SettingsFlowViewController(ownedCryptoId: currentOwnedCryptoId, obvEngine: obvEngine, createPasscodeDelegate: createPasscodeDelegate, appBackupDelegate: appBackupDelegate)
        let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(dismissPresentedViewController))
        vc.viewControllers.first?.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(vc, animated: true) {
            vc.pushSetting(specificSetting)
        }
    }

    
    func getAndRemoveAirDroppedFileURLs() -> [URL] {
        let urls = airDroppedFileURLs
        airDroppedFileURLs.removeAll()
        return urls
    }
    
    
    private func currentDiscussionViewControllerShownToUser() -> DiscussionViewController? {
        let currentNavigation: UINavigationController?
        if self.isCollapsed {
            // Typical on iPhone
            switch mainTabBarController.selectedIndex {
            case ChildTypes.latestDiscussions:
                currentNavigation = discussionsFlowViewController
            case ChildTypes.contacts:
                currentNavigation = contactsFlowViewController
            case ChildTypes.groups:
                currentNavigation = groupsFlowViewController
            default:
                currentNavigation = nil
            }
        } else {
            // Typical on iPad
            guard self.viewControllers.count > 1 else { assertionFailure(); return nil }
            currentNavigation = self.viewControllers[1] as? UINavigationController
        }
        guard let discussionVC = currentNavigation?.viewControllers.last as? DiscussionViewController else { return nil }
        guard discussionVC.viewIfLoaded?.window != nil else { assertionFailure(); return nil }
        return discussionVC
    }
    
}

// MARK: - OlvidURLHandler

extension MainFlowViewController {
    
    func handleOlvidURL(_ olvidURL: OlvidURL) {
        // When receiving an OlvidURL, we store it in the externallyScannedOrTappedOlvidURL variable. This URL will be processed when the viewDidAppear lifecycle method is called.
        // We do not process the URL here to prevent a race condition between the alert presented to process the link, and the alert presented when authenticating (when the user decided to activate this option).
        // This only exception to the above is when viewDidAppear was already called, in which case we process the link immediately.
        assert(Thread.isMainThread)
        assert(externallyScannedOrTappedOlvidURL == nil)
        if viewDidAppearWasCalled {
            Task { await processExternallyScannedOrTappedOlvidURL(olvidURL: olvidURL) }
        } else {
            externallyScannedOrTappedOlvidURL = olvidURL
        }
    }
    
    
    /// Lets the user choose which of her identities she wants to use before proceeding with the processing of an an external OlvidURL.
    @MainActor private func processExternallyScannedOrTappedOlvidURL(olvidURL: OlvidURL) async {
        os_log("Processing an externally scanned or tapped Olvid URL", log: log, type: .info)
        do {
            let ownedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: ObvStack.shared.viewContext)
            switch ownedIdentities.count {
            case 0:
                assertionFailure()
                return
            case 1:
                guard let ownedIdentity = ownedIdentities.first else { assertionFailure(); return }
                await processExternallyScannedOrTappedOlvidURL(olvidURL: olvidURL, for: ownedIdentity.cryptoId)
            default:
                switch olvidURL.category {
                case .invitation, .mutualScan, .configuration:
                    // We cannot process the OlvidURL until the user chooses the most appropriate owned identity
                    await requestAppropriateOwnedIdentityToProcessExternallyScannedOrTappedOlvidURL(olvidURL: olvidURL)
                case .openIdRedirect:
                    // Special case: the user previously chose the appropriate owned identity, and thus the "current" one is the one to use
                    await processExternallyScannedOrTappedOlvidURL(olvidURL: olvidURL, for: currentOwnedCryptoId)
                }
            }
        } catch {
            os_log("Could not process externally scanned or tapped OlvidURL: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
    
    
    /// Shows the owned identity switcher sheet, allowing the user to choose the most appropriate profile to use in order to process the external `OlvidURL`.
    @MainActor private func requestAppropriateOwnedIdentityToProcessExternallyScannedOrTappedOlvidURL(olvidURL: OlvidURL) async {

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

        let ownedIdentityChooserVC = OwnedIdentityChooserViewController(currentOwnedCryptoId: currentOwnedCryptoId,
                                                                        ownedIdentities: ownedIdentities,
                                                                        delegate: self)
        ownedIdentityChooserVC.modalPresentationStyle = .popover
        if let popover = ownedIdentityChooserVC.popoverPresentationController {
            if #available(iOS 15, *) {
                let sheet = popover.adaptiveSheetPresentationController
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16.0
            }
        }
        // In case the OwnedIdentityChooserViewController gets dismissed without choosing a profile, we simply want to discard the externallyScannedOrTappedOlvidURLExpectingAnOwnedIdentityToBeChosen
        ownedIdentityChooserVC.callbackOnViewDidDisappear = { [weak self] in
            self?.externallyScannedOrTappedOlvidURLExpectingAnOwnedIdentityToBeChosen = nil
        }
        assert(externallyScannedOrTappedOlvidURLExpectingAnOwnedIdentityToBeChosen == nil)
        externallyScannedOrTappedOlvidURLExpectingAnOwnedIdentityToBeChosen = olvidURL
        present(ownedIdentityChooserVC, animated: true)

    }
    
    
    /// When receiving an externally scanned or tapped OlvidURL, we let the user choose her profile before processing the URL. Once the profile is chosen, this method is called.
    @MainActor private func processExternallyScannedOrTappedOlvidURL(olvidURL: OlvidURL, for ownedIdentity: ObvCryptoId) async {
        
        switch olvidURL.category {
        case .openIdRedirect:
            Task {
                do {
                    _ = try await KeycloakManagerSingleton.shared.resumeExternalUserAgentFlow(with: olvidURL.url)
                    os_log("Successfully resumed the external user agent flow", log: log, type: .info)
                } catch {
                    os_log("Failed to resume external user agent flow: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
            }
        case .configuration, .invitation, .mutualScan:
            userWantsToAddContact(sourceView: UIView(), alreadyScannedOrTappedURL: olvidURL)
        }

    }

}


// MARK: - OwnedIdentityChooserViewControllerDelegate

extension MainFlowViewController: OwnedIdentityChooserViewControllerDelegate {
    
    func userUsedTheOwnedIdentityChooserViewControllerToChoose(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        
        // Start by switching to the chosen ownedCryptoId
        assert(parent is MetaFlowController)
        await (parent as? MetaFlowController)?.processUserWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: ownedCryptoId)
        
        // Process the externally scanned or tapped OlvidURL found in `externallyScannedOrTappedOlvidURLExpectingAnOwnedIdentityToBeChosen`
        guard let olvidURL = externallyScannedOrTappedOlvidURLExpectingAnOwnedIdentityToBeChosen else { assertionFailure(); return }
        externallyScannedOrTappedOlvidURLExpectingAnOwnedIdentityToBeChosen = nil
        await processExternallyScannedOrTappedOlvidURL(olvidURL: olvidURL, for: ownedCryptoId)
        
    }
    
    
    func userWantsToEditCurrentOwnedIdentity(ownedCryptoId: ObvTypes.ObvCryptoId) async {
        // Since the OwnedIdentityChooserViewController was shown because we had an OlvidURL to process, we do not expect it to show any edit button.
        assertionFailure()
    }
    
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityDeletion: Bool {
        false
    }
    
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityEdition: Bool {
        false
    }
    
    var ownedIdentityChooserViewControllerShouldAllowOwnedIdentityCreation: Bool {
        false
    }
    
    var ownedIdentityChooserViewControllerExplanationString: String? {
        return NSLocalizedString("PLEASE_CHOOSE_PROFILE_TO_PROCESS_OLVID_URL", comment: "")
    }
    
}

// MARK: - QRCodeScannerViewControllerDelegate

extension MainFlowViewController: ScannerHostingViewDelegate {

    func qrCodeWasScanned(olvidURL: OlvidURL) {
        // Since we are scanning an OlvidURL from within Olvid, we consider that the user wants to process this URL with her current identity.
        Task { await processExternallyScannedOrTappedOlvidURL(olvidURL: olvidURL, for: currentOwnedCryptoId) }
    }
    
    
    func scannerViewActionButtonWasTapped() {
        presentedViewController?.dismiss(animated: true)
    }
    
    private func sendInvite(to remoteCryptoId: ObvCryptoId, withFullDisplayName fullDisplayName: String, for ownedCryptoId: ObvCryptoId) {
        do {
            // Launch a trust establishment protocol with the contact
            try obvEngine.startTrustEstablishmentProtocolOfRemoteIdentity(with: remoteCryptoId,
                                                                          withFullDisplayName: fullDisplayName,
                                                                          forOwnedIdentyWith: ownedCryptoId)
            // Switch to the Invitations tab
            DispatchQueue.main.async { [weak self] in
                self?.mainTabBarController.selectedIndex = ChildTypes.invitations
                self?.dismiss(animated: true)
            }

        } catch {
            os_log("Could not start trust establishment protocol with %@", log: log, type: .error, fullDisplayName)
        }
    }
        

    @MainActor
    private func presentBadScannedQRCodeAlert() {
        let alert = UIAlertController(title: Strings.BadScannedQRCodeAlert.title, message: Strings.BadScannedQRCodeAlert.message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
        self.present(alert, animated: true)
    }
    
    
    @MainActor
    private func rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: ObvCryptoId, contactFullDisplayName: String, ownedCryptoId: ObvCryptoId, confirmed: Bool) {
        
        guard confirmed else {
            let invitationAlert = UIAlertController(title: Strings.alertInvitationTitle, message: Strings.alertInvitationScanedIsAlreadtPart, preferredStyle: .alert)
            invitationAlert.addAction(UIAlertAction(title: CommonString.Word.Proceed, style: .default) { [weak self] _ in
                self?.rePerformTrustEstablishmentProtocolOfContactIdentity(contactCryptoId: contactCryptoId,
                                                                           contactFullDisplayName: contactFullDisplayName,
                                                                           ownedCryptoId: ownedCryptoId,
                                                                           confirmed: true)
            })
            invitationAlert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            present(invitationAlert, animated: true)
            return
        }
        
        sendInvite(to: contactCryptoId, withFullDisplayName: contactFullDisplayName, for: ownedCryptoId)

    }
    
    
    @MainActor
    private func performTrustEstablishmentProtocolOfRemoteIdentity(contactCryptoId: ObvCryptoId, contactFullDisplayName: String, ownedCryptoId: ObvCryptoId, confirmed: Bool) {
        
        guard confirmed else {
            let invitationAlert = UIAlertController(title: Strings.alertInvitationTitle, message: Strings.alertInvitationWantToSend(contactFullDisplayName), preferredStyle: .alert)
            invitationAlert.addAction(UIAlertAction(title: CommonString.Word.Proceed, style: .default) { [weak self] _ in
                    self?.performTrustEstablishmentProtocolOfRemoteIdentity(contactCryptoId: contactCryptoId,
                                                                                  contactFullDisplayName: contactFullDisplayName,
                                                                                  ownedCryptoId: ownedCryptoId,
                                                                                  confirmed: true)
            })
            invitationAlert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            present(invitationAlert, animated: true)
            return
        }
        
        sendInvite(to: contactCryptoId, withFullDisplayName: contactFullDisplayName, for: ownedCryptoId)

    }

    
}


// MARK: - Processing external OlvidURLs

extension MainFlowViewController {
    
    

}


// MARK: - SingleOwnedIdentityFlowViewControllerDelegate

extension MainFlowViewController: SingleOwnedIdentityFlowViewControllerDelegate {
    
    func userWantsToDismissSingleOwnedIdentityFlowViewController() {
        assert(Thread.isMainThread)
        dismiss(animated: true)
    }
    
}


// MARK: - ObvGenericIdentityForSharing

final class ObvGenericIdentityForSharing: NSObject, UIActivityItemSource {
        
    private let genericIdentity: ObvGenericIdentity
    
    init(genericIdentity: ObvGenericIdentity) {
        self.genericIdentity = genericIdentity
        super.init()
    }
    
    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        let displayName = genericIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
        let url = genericIdentity.getObvURLIdentity().urlRepresentation
        return MainFlowViewController.Strings.ShareOwnedIdentity.body(displayName, url)
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        let displayName = genericIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
        let url = genericIdentity.getObvURLIdentity().urlRepresentation
        return MainFlowViewController.Strings.ShareOwnedIdentity.body(displayName, url)
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        return MainFlowViewController.Strings.ShareOwnedIdentity.subject(genericIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full))
    }

    
    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = NSLocalizedString("HOW_DO_YOU_WANT_TO_SHARE_ID", comment: "")
        return metadata
    }
}


// MARK: - MainFlowViewControllerSplitDelegate

private final class MainFlowViewControllerSplitDelegate: UISplitViewControllerDelegate {
    
    func splitViewController(_ splitViewController: UISplitViewController, separateSecondaryFrom primaryViewController: UIViewController) -> UIViewController? {
        /* This happens when transioning from compact to regular width.
         * In case a SingleDiscussionViewController is on screen, we want to transfer this view controller from the main view controller
         * of the split view controller to the detail view controller. We do this by looking for the *first* SingleDiscussionViewController
         * within the navigation view controller of the main split view, pop this SingleViewController (as well as the next SingleViewControllers), embedd
         * them in a UINavigationController, that we return. This new UINavigationController containing one or more SingleDiscussionViewControllers will
         * then show in the detail view controller of the split view controller.
         */
        
        // We expect to be the delegate of the MainFlowViewController (which is a UISplitViewController)
        guard let mainFlowViewController = splitViewController as? MainFlowViewController else {
            assertionFailure()
            return nil
        }
                
        // Find the current flow controller
        guard let currentFlow = mainFlowViewController.currentFlow else {
            // This typically happens when showing the settings
            return nil
        }
    
        // Find the ViewController to pop to on the current flow. Its the last view controller that is not a SingleDiscussionViewController
        guard !currentFlow.viewControllers.isEmpty else {
            assertionFailure()
            return nil
        }
        var vcToPopTo: UIViewController?
        for (index, vc) in currentFlow.viewControllers.enumerated() {
            guard index > 0 else { continue }
            if vc is SingleDiscussionViewController {
                vcToPopTo = currentFlow.viewControllers[index-1]
                break
            }
        }
        guard vcToPopTo != nil else { return nil }
                
        
        // Pop the single discussion view controllers from the flow
        guard let singleDiscussionViewControllers = currentFlow.popToViewController(vcToPopTo!, animated: false) else { return nil }
        guard !singleDiscussionViewControllers.isEmpty else { return nil }
        
        // We expect all the popped VC to be SingleDiscussionViewControllers. We check this
        for vc in singleDiscussionViewControllers {
            assert(vc is SingleDiscussionViewController)
        }
        
        // We embedd the SingleDiscussionViewControllers in a new navigation stack
        let nav = UINavigationController(rootViewController: singleDiscussionViewControllers.first!)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        nav.navigationBar.standardAppearance = appearance
        for (index, vc) in singleDiscussionViewControllers.enumerated() {
            guard index > 0 else { continue }
            nav.pushViewController(vc, animated: false)
        }
        
        // We return the new navigation stack so that it is shown on the details side of the split view controller
        return nav

    }
        
    
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        /* This happens when transioning from regular to compact width.
         * In case a SingleDiscussionViewController is on screen (or a stack of SingleDiscussionViewControllers),
         * we want to transfer this (or these) view controller(s) from the detail view controller
         * of the split view controller to the main view controller. To do so, we push this SingleDiscussionViewController onto the appropriate
         * flow, i.e., the flow corresponding to the select tab of the tab bar controller. In case the selected tab has no associated flow (e.g., for the
         * invitation or settings tab), we programmatically select the discussion tab before pushing the SingleDiscussionViewController.
         */

        // We expect to be the delegate of the MainFlowViewController (which is a UISplitViewController)
        guard let mainFlowViewController = splitViewController as? MainFlowViewController else {
            assertionFailure()
            return false
        }

        // Perform a few sanity checks
        
        guard primaryViewController == mainFlowViewController.mainTabBarController else {
            assertionFailure()
            return false
        }
        
        let mainTabBarController = mainFlowViewController.mainTabBarController
        
        guard let secondaryNav = secondaryViewController as? UINavigationController else {
            assertionFailure()
            return false
        }
        
        // Pop the stack of all discussions shown on the secondary nav
        
        guard !secondaryNav.viewControllers.isEmpty else {
            return false
        }
        guard secondaryNav.viewControllers is [SingleDiscussionViewController] else { assertionFailure(); return false }
        var discussionViewControllers = secondaryNav.popToRootViewController(animated: false) as? [SingleDiscussionViewController] ?? [SingleDiscussionViewController]()
        let rootVC = secondaryNav.viewControllers.first! as! SingleDiscussionViewController
        rootVC.willMove(toParent: nil)
        rootVC.view.removeFromSuperview()
        rootVC.removeFromParent()
        discussionViewControllers.insert(rootVC, at: 0)
        
        // If the array of discussion view controllers is empty, return false since we have nothing more to do in order to display an appropriate primary view controller
        guard !discussionViewControllers.isEmpty else { return false }
        
        // If we reach this point, we have an non-empty array of discussions to push onto an appropriate flow.
        // We look for this flow, and force the "latest discussions" tab if we cannot find an appropriate flow.
        let currentFlow: ObvFlowController
        if let cf = mainFlowViewController.currentFlow {
            currentFlow = cf
        } else {
            mainTabBarController.selectedIndex = MainFlowViewController.ChildTypes.latestDiscussions
            if let cf = mainFlowViewController.currentFlow {
                currentFlow = cf
            } else {
                assertionFailure()
                return false
            }
        }
        
        // We push the discussion on the current flow
        for vc in discussionViewControllers {
            currentFlow.pushViewController(vc, animated: false)
        }
        
        // We return false since we manually did the job of collapsing the secondary view controller onto the primary view controller
        return false
    }
    
}


// Strings

extension MainFlowViewController {
    
    struct Strings {
        
        static let contactsTVCTitle = { (groupDiscussionTitle: String) in
            String.localizedStringWithFormat(NSLocalizedString("Members of %@", comment: "Title of the table listing all members of a discussion group."), groupDiscussionTitle)
        }
        
        struct AlertOpenURL {
            static let title = NSLocalizedString("Open in Safari?", comment: "Alert title")
            static let message = { (url: URL) in
                String.localizedStringWithFormat(NSLocalizedString("Do you wish to open %@ in Safari?", comment: "Alert message"), url.absoluteString)
            }
            static let openButton = NSLocalizedString("Open", comment: "Aloert button title")
        }
        
        struct BadScannedQRCodeAlert {
            static let title = NSLocalizedString("Bad QR code", comment: "Alert title")
            static let message = NSLocalizedString("The scanned QR code does not appear to be an Olvid identity.", comment: "Alert message")
        }

        static let alertInvitationTitle = NSLocalizedString("Invitation", comment: "Alert title")

        static let alertInvitationScanedIsOwnedMessage = NSLocalizedString("The scanned identity is one of your own 😇.", comment: "Alert message")
        static let alertInvitationScanedIsAlreadtPart = NSLocalizedString("The scanned identity is already part of your trusted contacts 🙌. Do you still wish to proceed?", comment: "Alert message")
        static let alertInvitationWantToSend = { (displayName: String) in
            String.localizedStringWithFormat(NSLocalizedString("Do you want to send an invitation to %@?", comment: "Alert message"), displayName)
        }

        struct AddInviteAlert {
            static let title = NSLocalizedString("Invite another Olvid user", comment: "Title of an alert")
            static let message = NSLocalizedString("In order to invite another Olvid user, you can either scan their QR code or show them your own QR code.", comment: "Message of an alert")
            static let actionShowMyQRCode = NSLocalizedString("Show my QR code", comment: "Title of an alert action")
            static let actionScanQRCode = NSLocalizedString("Scan another user's QR code", comment: "Title of an alert action")
            static let messageAdvanced = NSLocalizedString("In order to invite another Olvid user, you can copy your identity in order to paste it in an email, sms, and so forth. If you receive an identity, you can paste it here.", comment: "Message of an alert")
            static let copyYourIdentity = NSLocalizedString("Copy your Id", comment: "Action of an alert")
            static let pastAnotherIdentity = NSLocalizedString("Paste an Id", comment: "Action of an alert")
        }
        
        struct OwnedIdentityCopiedAlert {
            static let title = NSLocalizedString("YOUR_ID_WAS_COPIED", comment: "Alert title")
            static let message = NSLocalizedString("YOUR_ID_WAS_COPIED_TO_CLIPBOARD_YOU_CAN_WRITE_EMAIL_AND_COPY_IT_THERE", comment: "Alert message")
        }

        static let sendInvitation = NSLocalizedString("Send invite", comment: "title of an alert")
        
        static let moreAction = NSLocalizedString("More...", comment: "UIAlert action title")
        
        struct ShareOwnedIdentity {
            static let subject = { (ownedDisplaName: String) in
                String.localizedStringWithFormat(NSLocalizedString("%@ invites you to discuss on Olvid", comment: "Subject used when inviting another user to Olvid, i.e., when sharing ones owned identity using, e.g., an email"), ownedDisplaName)
            }
            static let body = { (ownedDisplaName: String, ownedIdentityURL: URL) in
                String.localizedStringWithFormat(NSLocalizedString("%@ invites you to discuss on Olvid. To accept, please click the link below:\n\n%@", comment: "Body used when inviting another user to Olvid, i.e., when sharing ones owned identity using, e.g., an email or message"), ownedDisplaName, ownedIdentityURL.absoluteString)
            }
        }

        static let chooseDiscussion = NSLocalizedString("Choose Discussion", comment: "Used within a HUD to indicate to the user that she should choose a discussion for AirDrop'ed files")

        struct ServerDoesNotSupportCallAlert {
            static let title = NSLocalizedString("SERVER_DOES_NOT_SUPPORT_CALLS", comment: "Alert title")
        }

        struct UserHasBeenKilled {
            static let title = NSLocalizedString("USER_HAS_BEEN_KICKED", comment: "Alert title")
        }

        struct MissingChannelForCallAlert {
            static let title = { (contactName: String) in
                String.localizedStringWithFormat(NSLocalizedString("MISSING_CHANNEL_FOR_CALL_TITLE_%@", comment: "Alert title"), contactName)
            }
            static let message = { (contactName: String) in
                String.localizedStringWithFormat(NSLocalizedString("MISSING_CHANNEL_FOR_CALL_MESSAGE_%@", comment: "Alert message"), contactName)
            }
        }
        
        struct AlertInstalledAppIsOutDated {
            static let title = NSLocalizedString("INSTALLED_APP_IS_OUTDATED_ALERT_TITLE", comment: "Alert title")
            static let body = NSLocalizedString("INSTALLED_APP_IS_OUTDATED_ALERT_BODY", comment: "Alert title")
            static let primaryActionTitle = NSLocalizedString("UPGRADE_NOW", comment: "Alert title")
        }

        struct AlertConfirmProfileDeletion {
            static let title = { (profileName: String) in
                String.localizedStringWithFormat(NSLocalizedString("DELETE_THIS_IDENTITY_QUESTION_TITLE_%@", comment: ""), profileName)
            }
            static let message = NSLocalizedString("DELETE_THIS_IDENTITY_QUESTION_MESSAGE", comment: "")
            static let actionDeleteProfile = NSLocalizedString("DELETE_THIS_IDENTITY_BUTTON", comment: "")
        }
        
        struct AlertConfirmLastUnhiddenProfileDeletion {
            static let title = NSLocalizedString("DELETE_THIS_LAST_UNHIDDEN_IDENTITY_QUESTION_TITLE", comment: "")
            static let message = NSLocalizedString("DELETE_THIS_LAST_UNHIDDEN_IDENTITY_QUESTION_MESSAGE", comment: "")
        }
        
        struct AlertNotifyContactsOnOwnedIdentityDeletion {
            static let title = NSLocalizedString("NOTIFY_CONTACTS_ON_OWNED_IDENTITY_DELETION_TITLE", comment: "")
            static let message = NSLocalizedString("NOTIFY_CONTACTS_ON_OWNED_IDENTITY_DELETION_MESSAGE", comment: "")
            static let notifyContactsAction = NSLocalizedString("NOTIFY_CONTACTS_ON_OWNED_IDENTITY_DELETION_DO_NOTIFY_CONTACTS_ACTION", comment: "")
            static let doNotNotifyContactsAction = NSLocalizedString("NOTIFY_CONTACTS_ON_OWNED_IDENTITY_DELETION_DO_NOT_NOTIFY_CONTACTS_ACTION", comment: "")
        }

        struct AlertTypeDeleteToProceedWithOwnedIdentityDeletion {
            static let title = { (profileName: String) in
                String.localizedStringWithFormat(NSLocalizedString("TYPE_DELETE_TO_PROCEED_WITH_OWNED_IDENTITY_DELETION_TITLE_%@", comment: ""), profileName)
            }
            static let message = NSLocalizedString("TYPE_DELETE_TO_PROCEED_WITH_OWNED_IDENTITY_DELETION_MESSAGE", comment: "")
            static let doDelete = NSLocalizedString("TYPE_DELETE_TO_PROCEED_WITH_OWNED_IDENTITY_DELETION_DO_DELETE_ACTION", comment: "")
            static let wordToType = NSLocalizedString("TYPE_DELETE_TO_PROCEED_WITH_OWNED_IDENTITY_DELETION_WORD_TO_TYPE", comment: "")
        }
        
    }
        
}
