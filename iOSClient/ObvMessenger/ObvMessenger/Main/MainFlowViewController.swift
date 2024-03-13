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
import StoreKit
import CoreData
import ObvEngine
import ObvTypes
import AVFoundation
import LinkPresentation
import SwiftUI
import ObvCrypto
import ObvUICoreData
import ObvUI
import ObvSettings


protocol MainFlowViewControllerDelegate: AnyObject {
    func userWantsToAddNewDevice(_ viewController: MainFlowViewController, ownedCryptoId: ObvCryptoId) async
}


final class MainFlowViewController: UISplitViewController, OlvidURLHandler, ObvFlowControllerDelegate {
    
    private(set) var currentOwnedCryptoId: ObvCryptoId
    private let obvEngine: ObvEngine
    var anOwnedIdentityWasJustCreatedOrRestored = false

    private let splitDelegate: MainFlowViewControllerSplitDelegate // Strong reference to the delegate
    private weak var createPasscodeDelegate: CreatePasscodeDelegate?
    private weak var localAuthenticationDelegate: LocalAuthenticationDelegate?
    private weak var appBackupDelegate: AppBackupDelegate?
    private weak var mainFlowViewControllerDelegate: MainFlowViewControllerDelegate?
    private weak var storeKitDelegate: StoreKitDelegate?

    fileprivate let mainTabBarController = ObvSubTabBarController()
    fileprivate let navForDetailsView = UINavigationController(rootViewController: OlvidPlaceholderViewController())

    fileprivate let discussionsFlowViewController: DiscussionsFlowViewController
    private let contactsFlowViewController: ContactsFlowViewController
    private let groupsFlowViewController: GroupsFlowViewController
    private let invitationsFlowViewController: NewInvitationsFlowViewController

    private var shouldPopViewController = false
    private var shouldScrollToTop = false
    
    private var observationTokens = [NSObjectProtocol]()
    
    private var secureCallsInBetaModalWasShown = false
    
    /// This variable is set when Olvid is started because an invite or configuration link was opened.
    /// When this happens, this link is processed as soon as this view controller's view appears.
    private var externallyScannedOrTappedOlvidURL: OlvidURL?
    private var viewDidAppearWasCalled = false
    
    private var externallyScannedOrTappedOlvidURLExpectingAnOwnedIdentityToBeChosen: OlvidURL?
    
    private var savedViewControllersForNavForDetailsView = [ObvCryptoId: [UIViewController]]()
        
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
    
    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, createPasscodeDelegate: CreatePasscodeDelegate, localAuthenticationDelegate: LocalAuthenticationDelegate, appBackupDelegate: AppBackupDelegate, mainFlowViewControllerDelegate: MainFlowViewControllerDelegate, storeKitDelegate: StoreKitDelegate) {
                
        os_log("🥏🏁 Call to the initializer of MainFlowViewController", log: log, type: .info)
        
        self.obvEngine = obvEngine
        self.currentOwnedCryptoId = ownedCryptoId
        self.createPasscodeDelegate = createPasscodeDelegate
        self.localAuthenticationDelegate = localAuthenticationDelegate
        self.appBackupDelegate = appBackupDelegate
        self.storeKitDelegate = storeKitDelegate
        self.mainFlowViewControllerDelegate = mainFlowViewControllerDelegate
        self.splitDelegate = MainFlowViewControllerSplitDelegate()
        
        discussionsFlowViewController = DiscussionsFlowViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        mainTabBarController.addChild(discussionsFlowViewController)

        contactsFlowViewController = ContactsFlowViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        mainTabBarController.addChild(contactsFlowViewController)
                
        groupsFlowViewController = GroupsFlowViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        mainTabBarController.addChild(groupsFlowViewController)

        //invitationsFlowViewController = InvitationsFlowViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        invitationsFlowViewController = NewInvitationsFlowViewController(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine)
        mainTabBarController.addChild(invitationsFlowViewController)

        super.init(nibName: nil, bundle: nil)

        self.delegate = splitDelegate
        #warning("This single discussion view controller looks bad in split view under iPad. It looked ok when using .allVisible")
        self.preferredDisplayMode = .oneBesideSecondary // .allVisible
        
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
        
        // If the user has no discussion to show in the latestDiscussions tab, show the contacts tab
        
        if let countOfUnarchivedDiscussions = try? PersistedDiscussion.countUnarchivedDiscussionsOfOwnedIdentity(ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext), countOfUnarchivedDiscussions == 0 {
            mainTabBarController.selectedIndex = ChildTypes.contacts
        }
                
        // Listen to notifications
        
        observeUserWantsToShareOwnPublishedDetailsNotifications()
        observeUserWantsToCallNotifications()
        observeServerDoesNotSupportCall()
        observeUserWantsToSelectAndCallContactsNotifications()

        observationTokens.append(contentsOf: [

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
            ObvMessengerInternalNotification.observeBetaUserWantsToSeeLogString { [weak self] logString in
                Task { await self?.processBetaUserWantsToSeeLogString(logString: logString) }
            },
            ObvMessengerCoreDataNotification.observePersistedDiscussionWasDeleted { [weak self] discussionPermanentID, _ in
                Task { await self?.processPersistedDiscussionWasDeletedOrArchived(discussionPermanentID: discussionPermanentID) }
            },
            ObvMessengerCoreDataNotification.observePersistedDiscussionWasArchived { [weak self] discussionPermanentID in
                Task { await self?.processPersistedDiscussionWasDeletedOrArchived(discussionPermanentID: discussionPermanentID) }
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
    }

    
    /// Called by the MetaFlowController (itself called by the SceneDelegate).
    @MainActor
    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        airDroppedFileURLs.removeAll()
    }

    
    @MainActor
    private func processBetaUserWantsToSeeLogString(logString: String) async {
        let vc = DebugLogStringViewerViewController(logString: logString)
        if let presentedViewController {
            presentedViewController.present(vc, animated: true)
        } else {
            present(vc, animated: true)
        }
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
                    case .ownedIdentityIsInactive:
                        let deepLink = ObvDeepLink.myId(ownedCryptoId: ownedCryptoId)
                        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
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
                    case .ownedIdentityIsInactive:
                        ObvMessengerInternalNotification.UserDismissedSnackBarForLater(ownedCryptoId: ownedCryptoId, snackBarCategory: snackBarCategory)
                            .postOnDispatchQueue()
                    }
                }
            })
        vc.modalPresentationStyle = .pageSheet
        if let sheet = vc.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 16.0
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
    
    
    fileprivate var allFlows: [ObvFlowController] {
        mainTabBarController.viewControllers?.compactMap({ $0 as? ObvFlowController }) ?? []
    }
    
    private var alreadyPushingDiscussionViewController = false
    

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
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearWasCalled = true
        if let olvidURL = externallyScannedOrTappedOlvidURL {
            os_log("Processing the URL of an external invitation or configuration link...", log: log, type: .info)
            externallyScannedOrTappedOlvidURL = nil
            Task { await processExternallyScannedOrTappedOlvidURL(olvidURL: olvidURL) }
        }
        guard let obvOwnedIdentity = try? obvEngine.getOwnedIdentity(with: currentOwnedCryptoId) else {
            assertionFailure()
            return
        }
        if obvOwnedIdentity.isKeycloakManaged {
            Task {
                await KeycloakManagerSingleton.shared.registerKeycloakManagedOwnedIdentity(ownedCryptoId: currentOwnedCryptoId, firstKeycloakBinding: false)
            }
        }
        
        // This is required for the MainFlowViewController.find(_:) and other methods to be called when the user types the default key command for search.
        becomeFirstResponder()
        
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
        guard presentedViewController == nil else {
            // We are already presengtin a view controller (e.g., a keycloak authentication view controller)
            // We do not present the NewAutorisationRequesterViewController
            return
        }
        let vc = NewAutorisationRequesterViewController(autorisationCategory: .localNotifications, delegate: self)
        present(vc, animated: true)
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
            if let sheet = vc.sheetPresentationController {
                sheet.detents = [.large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16.0
            }
            self.present(vc, animated: true)
            return
        }
    }

}


// MARK: - Keyboard shortcuts

extension MainFlowViewController {
    
    override var canBecomeFirstResponder: Bool {
        // This is required for the MainFlowViewController.find(_:) and other methods to be called when the user types the default key command for search.
        return true
    }
    
    
    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(title: String(localized: "Home"), action: #selector(processUIKeyCommandForHome), input: UIKeyCommand.inputHome, modifierFlags: .command),
        ]
    }
    

    /// When the user types Cmd+Home, we want to pop all the discussions shown on the navigation of the details view controller, back to the first view controller (that shows the Olvid logo).
    @objc private func processUIKeyCommandForHome() {
        navForDetailsView.popToRootViewController(animated: true)
    }
    
    
    /// Overriding this method allows to be called when the user types the standard keyboard shortcut (Cmd+F) for search.
    ///
    /// We pass this information to the most appropriate `NewSingleDiscussionViewController`.
    override func find(_ sender: Any?) {
        if let discussionVC = navForDetailsView.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.find(sender)
        } else if let discussionVC = currentFlow?.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.find(sender)
        }
    }
    
    
    /// Overriding this method allows to be called when the user types the standard keyboard shortcut (Cmd+G) for "Find next".
    ///
    /// We pass this information to the most appropriate `NewSingleDiscussionViewController`.
    override func findNext(_ sender: Any?) {
        if let discussionVC = navForDetailsView.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.findNext(sender)
        } else if let discussionVC = currentFlow?.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.findNext(sender)
        }
    }
    
    
    /// Overriding this method allows to be called when the user types the standard keyboard shortcut (Shift+Cmd+G) for "Find previous".
    ///
    /// We pass this information to the most appropriate `NewSingleDiscussionViewController`.
    override func findPrevious(_ sender: Any?) {
        if let discussionVC = navForDetailsView.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.findPrevious(sender)
        } else if let discussionVC = currentFlow?.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.findPrevious(sender)
        }
    }
    
}


// MARK: - Dealing with deleted discussions

extension MainFlowViewController {
    
    @MainActor
    func processPersistedDiscussionWasDeletedOrArchived(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
        
        if let persistedDiscussion = try? PersistedDiscussion.getManagedObject(withPermanentID: discussionPermanentID, within: ObvStack.shared.viewContext), !persistedDiscussion.isDeleted {
            
            if persistedDiscussion.isArchived {
                await removeFromTheObvFlowControllersAllSomeSingleDiscussionViewControllerForDiscussionWithPermanentID(discussionPermanentID)
                await removeFromTheDetailsViewAllSomeSingleDiscussionViewControllerForDiscussionWithPermanentID(discussionPermanentID)
            } else {
                await refreshFromTheObvFlowControllersAllSomeSingleDiscussionViewControllerForDiscussion(persistedDiscussion)
                await refreshTheDetailsViewAllSomeSingleDiscussionViewControllerForDiscussion(persistedDiscussion)
            }
            
        } else {
            
            await removeFromTheObvFlowControllersAllSomeSingleDiscussionViewControllerForDiscussionWithPermanentID(discussionPermanentID)
            await removeFromTheDetailsViewAllSomeSingleDiscussionViewControllerForDiscussionWithPermanentID(discussionPermanentID)
            
        }
        
    }
    
    
    /// Helper method for `processPersistedDiscussionWasInserted()`
    @MainActor
    private func removeFromTheDetailsViewAllSomeSingleDiscussionViewControllerForDiscussionWithPermanentID(_ discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
        var newStack = self.navForDetailsView.viewControllers.compactMap { viewController in
            guard let someSingleDiscussionVC = viewController as? SomeSingleDiscussionViewController else { return viewController }
            return (someSingleDiscussionVC.discussionPermanentID == discussionPermanentID) ? nil : someSingleDiscussionVC
        }
        if newStack.isEmpty {
            newStack = [OlvidPlaceholderViewController()]
        }
        self.navForDetailsView.setViewControllers(newStack, animated: false)
    }
    
    
    /// Helper method
    @MainActor
    private func removeFromTheObvFlowControllersAllSomeSingleDiscussionViewControllerForDiscussionWithPermanentID(_ discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>) async {
        let allFlowViewControllers = self.mainTabBarController.viewControllers?.compactMap { $0 as? ObvFlowController } ?? []
        assert(!allFlowViewControllers.isEmpty)
        for obvFlowController in allFlowViewControllers {
            await obvFlowController.removeAllSomeSingleDiscussionViewControllerForDiscussionWithPermanentID(discussionPermanentID)
        }
    }
    
    
    /// Helper method for `processPersistedDiscussionWasInserted()`
    @MainActor
    private func refreshTheDetailsViewAllSomeSingleDiscussionViewControllerForDiscussion(_ discussion: PersistedDiscussion) async {
        var newStack = self.navForDetailsView.viewControllers.compactMap { viewController in
            guard let someSingleDiscussionVC = viewController as? SomeSingleDiscussionViewController else { return viewController }
            if someSingleDiscussionVC.discussionPermanentID != discussion.discussionPermanentID {
                return someSingleDiscussionVC
            } else {
                do {
                    return try currentFlow?.getNewSingleDiscussionViewController(for: discussion, initialScroll: .newMessageSystemOrLastMessage)
                } catch {
                    assertionFailure(error.localizedDescription) // In production, continue anyway
                    return nil
                }
            }
        }
        if newStack.isEmpty {
            newStack = [OlvidPlaceholderViewController()]
        }
        self.navForDetailsView.setViewControllers(newStack, animated: false)
    }
    
    
    @MainActor
    private func refreshFromTheObvFlowControllersAllSomeSingleDiscussionViewControllerForDiscussion(_ discussion: PersistedDiscussion) async {
        let allFlowViewControllers = self.mainTabBarController.viewControllers?.compactMap { $0 as? ObvFlowController } ?? []
        assert(!allFlowViewControllers.isEmpty)
        for obvFlowController in allFlowViewControllers {
            do {
                try await obvFlowController.refreshAllSingleDiscussionViewControllerForDiscussion(discussion)
            } catch {
                assertionFailure(error.localizedDescription) // In production, continue anyway
            }
        }
    }
    
}


// MARK: - Switching current owned identity

extension MainFlowViewController {
    
    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {

        guard self.currentOwnedCryptoId != newOwnedCryptoId else { return }

        let oldOwnedCryptoId = self.currentOwnedCryptoId
        self.currentOwnedCryptoId = newOwnedCryptoId
        
        for flow in allFlows {
            await flow.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        }
        
        if !isCollapsed {
            // The split view controller shows a "details" view. We save its view controller's stack in order to restore it when the user switches back to that profile
            savedViewControllersForNavForDetailsView[oldOwnedCryptoId] = navForDetailsView.viewControllers
            if let viewControllersToRestore = savedViewControllersForNavForDetailsView.removeValue(forKey: newOwnedCryptoId), !viewControllersToRestore.isEmpty  {
                // Make are about to restore view controllers showing discussions. We filter out
                let updatedViewControllersToRestore = viewControllersToRestore.compactMap { viewController in
                    guard let someSingleDiscussionVC = viewController as? SomeSingleDiscussionViewController else { return viewController }
                    if (try? PersistedDiscussion.getManagedObject(withPermanentID: someSingleDiscussionVC.discussionPermanentID, within: ObvStack.shared.viewContext)) != nil {
                        return viewController
                    } else {
                        return nil
                    }
                }
                navForDetailsView.viewControllers = updatedViewControllersToRestore
            } else {
                navForDetailsView.viewControllers = [OlvidPlaceholderViewController()]
            }
        }
    }
    
}


// MARK: - NewAutorisationRequesterViewControllerDelegate

extension MainFlowViewController: NewAutorisationRequesterViewControllerDelegate {
    
    @MainActor
    func requestAutorisation(autorisationRequester: NewAutorisationRequesterViewController, now: Bool, for autorisationCategory: NewAutorisationRequesterViewController.AutorisationCategory) async {
        preventPrivacyWindowSceneFromShowingOnNextWillResignActive()
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
                os_log("User granted access to audio: %@", log: log, type: .info, String(describing: granted))
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
            Task { [weak self] in await self?.processUserWantsToDeleteOwnedIdentityButMustChooseBetweenLocalAndGlobalDeletion(ownedCryptoId: ownedCryptoId) }
        }
        
        let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .default)
        
        alert.addAction(deleteAction)
        alert.addAction(cancelAction)
        
        present(alert, animated: true)
        
    }
    
    
    @MainActor
    private func processUserWantsToDeleteOwnedIdentityButMustChooseBetweenLocalAndGlobalDeletion(ownedCryptoId: ObvCryptoId) async {
        
        assert(Thread.isMainThread)
        dismissPresentedViewController()
        let traitCollection = self.traitCollection

        guard let ownedIdentityToDelete = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { return }

        if ownedIdentityToDelete.isActive {
            
            let alert = UIAlertController(
                title: Strings.AlertChooseBetweenGlobalAndLocalOnOwnedIdentityDeletion.title,
                message: Strings.AlertChooseBetweenGlobalAndLocalOnOwnedIdentityDeletion.message,
                preferredStyleForTraitCollection: traitCollection)
            
            let globalDeletionAction = UIAlertAction(
                title: Strings.AlertChooseBetweenGlobalAndLocalOnOwnedIdentityDeletion.globalDeletionAction, style: .destructive)
            { [weak self] _ in
                Task { [weak self] in await self?.processUserWantsToDeleteOwnedIdentityAfterHavingConfirmed(ownedCryptoId: ownedCryptoId, globalOwnedIdentityDeletion: true) }
            }
            let localDeletionAction = UIAlertAction(
                title: Strings.AlertChooseBetweenGlobalAndLocalOnOwnedIdentityDeletion.localDeletionAction, style: .destructive)
            { [weak self] _ in
                Task { [weak self] in await self?.processUserWantsToDeleteOwnedIdentityAfterHavingConfirmed(ownedCryptoId: ownedCryptoId, globalOwnedIdentityDeletion: false) }
            }
            let cancelAction = UIAlertAction(title: CommonString.Word.Cancel, style: .default)
            alert.addAction(globalDeletionAction)
            alert.addAction(localDeletionAction)
            alert.addAction(cancelAction)
            present(alert, animated: true)
            
        } else {
            
            // Since the identity is not active, a global delete makes no sense.
            // We immediately go to the last step, assuming a local delete.
            
            await processUserWantsToDeleteOwnedIdentityAfterHavingConfirmed(ownedCryptoId: ownedCryptoId, globalOwnedIdentityDeletion: false)
            
        }
        
    }
    
    
    /// This method is called last during the UI process allowing to delete an owned identity. It allows to make sure that the does want to delete her owned identity by asking her to write the DELETE word.
    @MainActor
    private func processUserWantsToDeleteOwnedIdentityAfterHavingConfirmed(ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) async {
        guard let ownedIdentityToDelete = try? PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: ObvStack.shared.viewContext) else { return }
        let profileName = ownedIdentityToDelete.customDisplayName ?? ownedIdentityToDelete.identityCoreDetails.getFullDisplayName()

        let alert = UIAlertController(title: Strings.AlertTypeDeleteToProceedWithOwnedIdentityDeletion.title(profileName),
                                      message: Strings.AlertTypeDeleteToProceedWithOwnedIdentityDeletion.message,
                                      preferredStyle: .alert)
        alert.addTextField { textField in
            textField.text = ""
            textField.autocapitalizationType = .allCharacters
        }
        alert.addAction(UIAlertAction(title: Strings.AlertTypeDeleteToProceedWithOwnedIdentityDeletion.doDelete, style: .destructive, handler: { [unowned alert] _ in
            guard let textField = alert.textFields?.first else { assertionFailure(); return }
            guard textField.text?.trimmingWhitespacesAndNewlines() == Strings.AlertTypeDeleteToProceedWithOwnedIdentityDeletion.wordToType else { return }
            ObvMessengerInternalNotification.userWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ownedCryptoId, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
                .postOnDispatchQueue()
        }))
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
        present(alert, animated: true)
    }

    
}


// MARK: - ObvFlowControllerDelegate

extension MainFlowViewController {

    
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
            },
            obvEngine: obvEngine,
            delegate: self)
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
        let obvEngine = self.obvEngine
        let log = self.log
        let currentOwnedCryptoId = self.currentOwnedCryptoId
        Task.detached {
            do {
                try await obvEngine.updateTrustedIdentityDetailsOfContactIdentity(with: contactCryptoId, ofOwnedIdentityWithCryptoId: currentOwnedCryptoId, with: newContactIdentityDetails)
            } catch {
                os_log("Could not update trusted identity details of a contact", log: log, type: .error)
            }
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
        ObvMessengerInternalNotification.userWantsToRefreshDiscussions(completionHandler: completionHandler)
            .postOnDispatchQueue()
    }

    
    /// Helper enum used in ``userWantsToInviteContactsToOneToOne(ownedCryptoId:users:)``
    private enum OneToOneInvitationKind {
        case oneToOneInvitationProtocol(ownedCryptoId: ObvCryptoId, userCryptoId: ObvCryptoId)
        case keycloak(ownedCryptoId: ObvCryptoId, userCryptoId: ObvCryptoId, userIdOrSignedDetails: KeycloakAddContactInfo)
    }

    
    /// Central method to call to invite a contact to be one2one. In most cases, this only triggers a `OneToOneContactInvitationProtocol`. In the case the owned identity is keycloak managed by the same server as the contact, this *also* triggers a Keycloak invitation.
    func userWantsToInviteContactsToOneToOne(ownedCryptoId: ObvCryptoId, users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)]) async throws {

        let invitationsToSend = try await computeListOfOneToOneInvitationsToSend(ownedCryptoId: ownedCryptoId, users: users)
        
        for invitationToSend in invitationsToSend {
            
            switch invitationToSend {

            case .oneToOneInvitationProtocol(ownedCryptoId: let ownedCryptoId, userCryptoId: let userCryptoId):
                
                do {
                    try obvEngine.sendOneToOneInvitation(ownedIdentity: ownedCryptoId, contactIdentity: userCryptoId)
                } catch {
                    assertionFailure(error.localizedDescription)
                    continue // In production, do not fail the whole process because something went wrong for one invitation
                }

            case .keycloak(ownedCryptoId: let ownedCryptoId, userCryptoId: let userCryptoId, userIdOrSignedDetails: let userIdOrSignedDetails):

                do {
                    try await KeycloakManagerSingleton.shared.addContact(ownedCryptoId: ownedCryptoId, userIdOrSignedDetails: userIdOrSignedDetails, userIdentity: userCryptoId.getIdentity())
                } catch let addContactError as KeycloakManager.AddContactError {
                    switch addContactError {
                    case .authenticationRequired,
                            .ownedIdentityNotManaged,
                            .badResponse,
                            .userHasCancelled,
                            .keycloakApiRequest,
                            .invalidSignature,
                            .unkownError:
                        throw addContactError
                    case .willSyncKeycloakServerSignatureKey:
                        break
                    case .ownedIdentityWasRevoked:
                        ObvMessengerInternalNotification.userOwnedIdentityWasRevokedByKeycloak(ownedCryptoId: ownedCryptoId)
                            .postOnDispatchQueue()
                    }
                } catch {
                    assertionFailure(error.localizedDescription)
                    continue // In production, do not fail the whole process because something went wrong for one invitation
                }
                
            }
            
        }

    }
    
    
    /// Helper methods for ``userWantsToInviteContactsToOneToOne(ownedCryptoId:users:)``. Returns a list of one2one invitations to send. Note that we might return two invitation types for the same user. This is intended.
    ///
    /// If the owned identity is Keycloak managed and the contact is managed by the same keycloak:
    /// - if there is a corresponding PersistedObvContactIdentity:
    ///   - if one2one, don't start a keycloak invitation
    ///   - otherwise, check whether she's keycloak managed. In that case, start a keycloak invitation.
    /// - If there is no contact and this method caller provided JSON signed details, start a keycloak invitation.
    private func computeListOfOneToOneInvitationsToSend(ownedCryptoId: ObvCryptoId, users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)]) async throws -> [OneToOneInvitationKind] {
        
        // In case the owned identity is keycloak managed, we augment the received list of users using the keycloak details available from the engine
        
        let usersWithAllKeyclakInfos: [(cryptoId: ObvCryptoId, userIdOrSignedDetails: KeycloakAddContactInfo?)]
        
        if try await ownedIdentityIsKeycloakManaged(ownedCryptoId: ownedCryptoId) {
            
            var constructedListOfUsers = [(cryptoId: ObvCryptoId, userIdOrSignedDetails: KeycloakAddContactInfo?)]()
            for user in users {
                if let userId = user.keycloakDetails?.id {
                    constructedListOfUsers.append((user.cryptoId, .userId(userId: userId)))
                } else if let keycloakSignedDetails = try? await obvEngine.getSignedContactDetailsAsync(ownedIdentity: ownedCryptoId, contactIdentity: user.cryptoId) {
                    constructedListOfUsers.append((user.cryptoId, .signedDetails(signedDetails: keycloakSignedDetails)))
                } else {
                    constructedListOfUsers.append((user.cryptoId, nil))
                }
            }
            
            usersWithAllKeyclakInfos = constructedListOfUsers
            
        } else {
            
            usersWithAllKeyclakInfos = users.map { ($0.cryptoId, nil) }
            
        }
        
        // Now that we have a list of users to invite (and all the available info concerning their keycloak details), we can compute a list of one2one invitations to send.

        return await withCheckedContinuation { (continuation: CheckedContinuation<[OneToOneInvitationKind], Never>) in

            ObvStack.shared.performBackgroundTask { context in

                var invitationsToPerform = [OneToOneInvitationKind]()

                for user in usersWithAllKeyclakInfos {
                    
                    do {
                        
                        if let contact = try PersistedObvContactIdentity.get(contactCryptoId: user.cryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: context) {
                            
                            if !contact.isOneToOne && contact.isActive && contact.hasAtLeastOneRemoteContactDevice() {
                                invitationsToPerform.append(.oneToOneInvitationProtocol(ownedCryptoId: ownedCryptoId, userCryptoId: user.cryptoId))
                            }
                            
                            if !contact.isOneToOne && contact.isActive, let userIdOrSignedDetails = user.userIdOrSignedDetails {
                                invitationsToPerform.append(.keycloak(ownedCryptoId: ownedCryptoId, userCryptoId: user.cryptoId, userIdOrSignedDetails: userIdOrSignedDetails))
                            }
                            
                        } else if let userIdOrSignedDetails = user.userIdOrSignedDetails {
                            
                            invitationsToPerform.append(.keycloak(ownedCryptoId: ownedCryptoId, userCryptoId: user.cryptoId, userIdOrSignedDetails: userIdOrSignedDetails))

                        }
                        
                    } catch {
                        assertionFailure(error.localizedDescription)
                        continue
                    }
                    
                }
                
                continuation.resume(returning: invitationsToPerform)
            }
            
        }
        
    }
    
    
    /// Helper method for ``computeListOfOneToOneInvitationsToSend(ownedCryptoId:users:)``
    private func ownedIdentityIsKeycloakManaged(ownedCryptoId: ObvCryptoId) async throws -> Bool {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                        throw ObvFlowControllerError.couldNotFindOwnedIdentity
                    }
                    continuation.resume(returning: ownedIdentity.isKeycloakManaged)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
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


// MARK: - AddContactHostingViewControllerDelegate

extension MainFlowViewController: AddContactHostingViewControllerDelegate {
    
    func userWantsToAddNewContactViaKeycloak(ownedCryptoId: ObvCryptoId, keycloakUserDetails: ObvKeycloakUserDetails, userCryptoId: ObvCryptoId) async throws {
        try await userWantsToInviteContactsToOneToOne(ownedCryptoId: ownedCryptoId, users: [(userCryptoId, keycloakUserDetails)])
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
        
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToCallButWeShouldCheckSheIsAllowedTo { ownedCryptoId, contactCryptoIds, groupId in
            Task { [weak self] in await self?.processUserWantsToCallButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, groupId: groupId) }
        })
        
    }
    
    
    @MainActor
    private func processUserWantsToCallButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, groupId: GroupIdentifier?) async {
        assert(Thread.isMainThread)
        
        // Check access to the microphone
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                if granted {
                    Task { [weak self] in
                        await self?.processUserWantsToCallButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, groupId: groupId)
                    }
                } else {
                    ObvMessengerInternalNotification.outgoingCallFailedBecauseUserDeniedRecordPermission.postOnDispatchQueue()
                }
            }
            return
        }

        guard !contactCryptoIds.isEmpty else { assertionFailure(); return }
        let contacts = contactCryptoIds.compactMap({try? PersistedObvContactIdentity.get(contactCryptoId: $0, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) })
        guard contacts.count == contactCryptoIds.count else {
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
        
        let contactCryptoIds = Set(contacts.map({ $0.cryptoId }))

        // If the owned identity is allowed to make outgoing calls, we use it to request turn credentials. If it is not, we look for another owned identity that is allowed to and use it (exclusively) to request turn credentials.
        // This way, if one identity it allowed to make outgoing calls, all other owned identity are as well.
        let ownedIdentityForRequestingTurnCredentials = ownedIdentity.ownedCryptoIdAllowedToEmitSecureCall
        
        if let ownedIdentityForRequestingTurnCredentials {
            do {
                ObvMessengerInternalNotification.userWantsToCallAndIsAllowedTo(
                    ownedCryptoId: ownedCryptoId,
                    contactCryptoIds: contactCryptoIds,
                    ownedIdentityForRequestingTurnCredentials: ownedIdentityForRequestingTurnCredentials,
                    groupId: groupId)
                .postOnDispatchQueue()
            }
        } else {
            let vc = UserTriesToAccessPaidFeatureHostingController(requestedPermission: .canCall, ownedCryptoId: ownedIdentity.cryptoId)
            dismiss(animated: true) { [weak self] in
                self?.present(vc, animated: true)
            }
        }
    }
    
    
    private func observeUserWantsToSelectAndCallContactsNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToSelectAndCallContacts { ownedCryptoId, contactCryptoIds, groupId in
            Task { [weak self] in await self?.processUserWantsToSelectAndCallContacts(ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, groupId: groupId) }
        })
    }
    
    
    @MainActor
    private func processUserWantsToSelectAndCallContacts(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, groupId: GroupIdentifier?) async {
        guard !contactCryptoIds.isEmpty else { return }
        
        let persistedContacts = contactCryptoIds
            .compactMap { try? PersistedObvContactIdentity.get(contactCryptoId: $0, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) }
            .filter { !$0.devices.isEmpty }
        
        guard !persistedContacts.isEmpty else { return }
        
        let button = MultipleContactsButton.floating(title: CommonString.Word.Call, systemIcon: .phoneFill)

        let vc = MultipleContactsViewController(ownedCryptoId: ownedCryptoId,
                                                mode: .restricted(to: contactCryptoIds, oneToOneStatus: .any),
                                                button: button, 
                                                defaultSelectedContacts: Set(persistedContacts),
                                                disableContactsWithoutDevice: true,
                                                allowMultipleSelection: true,
                                                showExplanation: false,
                                                allowEmptySetOfContacts: false,
                                                textAboveContactList: nil,
                                                selectionStyle: .checkmark) { [weak self] selectedContacts in

            let selectedContactCryptoIs = selectedContacts.map { $0.cryptoId }
            ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set(selectedContactCryptoIs), groupId: groupId)
                .postOnDispatchQueue()

            self?.dismiss(animated: true)
        } dismissAction: { [weak self] in
            self?.dismiss(animated: true)
        }
        let nav = ObvNavigationController(rootViewController: vc)

        if let presentedViewController {
            presentedViewController.present(nav, animated: true)
        } else {
            present(nav, animated: true)
        }
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
            let vc = SingleOwnedIdentityFlowViewController(ownedIdentity: ownedIdentity, obvEngine: obvEngine, delegate: self)
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
            
            #if targetEnvironment(macCatalyst)
            
            // For catalyst, we copy the file to a tmp folder in order to prevent it to be deleted by future operations
            
            let targetFileURL = ObvUICoreDataConstants.ContainerURL.forTemporaryDroppedItems.appendingPathComponent(fileURL.lastPathComponent)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: fileURL.path) {
                // copy the file
                do {
                    try fileManager.copyItem(at: fileURL, to: targetFileURL)
                    addAttachmentFromFile(at: targetFileURL)
                } catch {
                    os_log("Unable to copy file to tmp Folder", log: log, type: .info)
                }
            }
            
            #else
            
            let targetFileURL = fileURL
            addAttachmentFromFile(at: targetFileURL)
            
            #endif
            
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
            
        case .voipSettings:
            assert(Thread.isMainThread)
            if let presentedViewController = self.presentedViewController {
                presentedViewController.dismiss(animated: true) { [weak self] in
                    self?.presentSettingsFlowViewController(specificSetting: .voip)
                }
            } else {
                presentSettingsFlowViewController(specificSetting: .voip)
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
    private func addAttachmentFromFile(at fileURL: URL) {
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
    }
    
    @MainActor
    private func presentSettingsFlowViewController() {
        assert(Thread.isMainThread)
        guard let createPasscodeDelegate, let appBackupDelegate, let localAuthenticationDelegate else {
            assertionFailure(); return
        }
        let vc = SettingsFlowViewController(ownedCryptoId: currentOwnedCryptoId, obvEngine: obvEngine, createPasscodeDelegate: createPasscodeDelegate, localAuthenticationDelegate: localAuthenticationDelegate, appBackupDelegate: appBackupDelegate)
        let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(dismissPresentedViewController))
        vc.viewControllers.first?.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(vc, animated: true)
    }


    @MainActor
    private func presentSettingsFlowViewController(specificSetting: AllSettingsTableViewController.Setting) {
        assert(Thread.isMainThread)
        guard let createPasscodeDelegate, let appBackupDelegate, let localAuthenticationDelegate else {
            assertionFailure(); return
        }
        let vc = SettingsFlowViewController(ownedCryptoId: currentOwnedCryptoId, obvEngine: obvEngine, createPasscodeDelegate: createPasscodeDelegate, localAuthenticationDelegate: localAuthenticationDelegate, appBackupDelegate: appBackupDelegate)
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
    
    
    private func currentDiscussionViewControllerShownToUser() -> SomeSingleDiscussionViewController? {
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
        guard let discussionVC = currentNavigation?.viewControllers.last as? SomeSingleDiscussionViewController else { return nil }
        guard discussionVC.viewIfLoaded?.window != nil else { assertionFailure(); return nil }
        return discussionVC
    }
    
}

// MARK: - OlvidURLHandler

extension MainFlowViewController {
    
    @MainActor
    func handleOlvidURL(_ olvidURL: OlvidURL) async {
        // When receiving an OlvidURL, we store it in the externallyScannedOrTappedOlvidURL variable. This URL will be processed when the viewDidAppear lifecycle method is called.
        // We do not process the URL here to prevent a race condition between the alert presented to process the link, and the alert presented when authenticating (when the user decided to activate this option).
        // This only exception to the above is when viewDidAppear was already called, in which case we process the link immediately.
        assert(externallyScannedOrTappedOlvidURL == nil)
        if viewDidAppearWasCalled {
            await processExternallyScannedOrTappedOlvidURL(olvidURL: olvidURL)
        } else {
            externallyScannedOrTappedOlvidURL = olvidURL
        }
    }
    
    
    /// Lets the user choose which of her identities she wants to use before proceeding with the processing of an an external OlvidURL.
    @MainActor 
    private func processExternallyScannedOrTappedOlvidURL(olvidURL: OlvidURL) async {
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
        
        // Under iPhone, we use a popover presentation style. Since we have no source view, we cannot do the same under iPad or mac.
        // Note that this method gets also called when the user taps an invitation link in a Safari window. In that case, we cannot have a source view anyway.
        if traitCollection.userInterfaceIdiom == .phone {
            ownedIdentityChooserVC.modalPresentationStyle = .popover
            if let popover = ownedIdentityChooserVC.popoverPresentationController {
                let sheet = popover.adaptiveSheetPresentationController
                sheet.detents = [.medium(), .large()]
                sheet.prefersGrabberVisible = true
                sheet.preferredCornerRadius = 16.0
            }
        } else {
            ownedIdentityChooserVC.modalPresentationStyle = .formSheet
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


// MARK: - SingleOwnedIdentityFlowViewControllerDelegate

extension MainFlowViewController: SingleOwnedIdentityFlowViewControllerDelegate {
        
    func userWantsToDismissSingleOwnedIdentityFlowViewController(_ viewController: SingleOwnedIdentityFlowViewController) {
        assert(Thread.isMainThread)
        viewController.dismiss(animated: true)
    }
    
    
    @MainActor
    func userWantsToAddNewDevice(_ viewController: SingleOwnedIdentityFlowViewController, ownedCryptoId: ObvCryptoId) async {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        viewController.dismiss(animated: true) {
            Task { await mainFlowViewControllerDelegate.userWantsToAddNewDevice(self, ownedCryptoId: ownedCryptoId) }
        }
    }
    
    
    func userRequestedListOfSKProducts() async throws -> [Product] {
        assert(storeKitDelegate != nil)
        return try await storeKitDelegate?.userRequestedListOfSKProducts() ?? []
    }
    
    
    func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult {
        guard let storeKitDelegate else {
            throw ObvError.storeKitDelegateIsNil
        }
        return try await storeKitDelegate.userWantsToBuy(product)
    }
    
    
    func userWantsToRestorePurchases() async throws {
        guard let storeKitDelegate else {
            throw ObvError.storeKitDelegateIsNil
        }
        return try await storeKitDelegate.userWantsToRestorePurchases()
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
    
    
    func splitViewController(_ splitViewController: UISplitViewController, showDetail vc: UIViewController, sender: Any?) -> Bool {
        /* When its showDetailViewController(_:sender:) method is called, the split view controller calls this method to see if your delegate will handle the presentation of the specified view controller.
         * If you implement this method and ultimately return true, your implementation is responsible for presenting the specified view controller in the secondary position of the split view interface.
         */
        assert(Thread.isMainThread)
        guard let mainFlow = splitViewController as? MainFlowViewController else {
            assertionFailure("We expect to be the delegate of MainFlowViewController")
            return false
        }
        guard let singleDiscussionVC = vc as? SomeSingleDiscussionViewController else {
            assertionFailure("The only VC that we may push on the detail view are expected to be instances of SomeSingleDiscussionViewController")
            return false
        }
        guard let flow = sender as? ObvFlowController else {
            assertionFailure()
            return false
        }
        
        if splitViewController.isCollapsed {
            // iPhone case
            if let singleDiscussionVCToShow = flow.viewControllers.compactMap({ $0 as? SomeSingleDiscussionViewController }).first(where: { $0.discussionPermanentID == singleDiscussionVC.discussionPermanentID }) {
                flow.popToViewController(singleDiscussionVCToShow, animated: true)
            } else {
                flow.pushViewController(singleDiscussionVC, animated: true)
            }
        } else {
            // iPad case
            if let singleDiscussionVCToShow = mainFlow.navForDetailsView.viewControllers.compactMap({ $0 as? SomeSingleDiscussionViewController }).first(where: { $0.discussionPermanentID == singleDiscussionVC.discussionPermanentID }) {
                mainFlow.navForDetailsView.popToViewController(singleDiscussionVCToShow, animated: true)
            } else {
                mainFlow.navForDetailsView.pushViewController(singleDiscussionVC, animated: true)
            }
        }
        return true
    }
    
    
    func splitViewController(_ splitViewController: UISplitViewController, separateSecondaryFrom primaryViewController: UIViewController) -> UIViewController? {
        /* This happens when transioning from compact to regular width.
         * In case a SingleDiscussionViewController is on screen, we want this vc to show on screen after the transition.
         * In practice, we do two things:
         * - We take all the SingleDiscussionViewController instances, embed them in the navigation controller of the secondary view controller
         * - We remove all the SingleDiscussionViewController instances from the flows
         * We then return the navigation controller of the secondary view controller.
         */
        
        // We expect to be the delegate of the MainFlowViewController (which is a UISplitViewController)
        guard let mainFlowViewController = splitViewController as? MainFlowViewController else {
            assertionFailure()
            return nil
        }
                
        // Find the current flow controller
        guard let currentFlow = mainFlowViewController.currentFlow else {
            assertionFailure()
            mainFlowViewController.navForDetailsView.setViewControllers([OlvidPlaceholderViewController()], animated: false)
            return mainFlowViewController.navForDetailsView
        }

        // Get all the SomeSingleDiscussionViewController instances of the current flow and use them to set the stack of the navigation of the secondary view
        let singleDiscussionViewControllers = currentFlow.viewControllers.compactMap({ $0 as? SomeSingleDiscussionViewController })
        mainFlowViewController.navForDetailsView.setViewControllers([OlvidPlaceholderViewController()] + singleDiscussionViewControllers, animated: false)
        
        // Remove all SomeSingleDiscussionViewController instances from all flows
        mainFlowViewController.allFlows.forEach { obvFlowController in
            let allVCsButDiscussionViewControllers = obvFlowController.viewControllers.filter({ !($0 is SomeSingleDiscussionViewController) })
            obvFlowController.setViewControllers(allVCsButDiscussionViewControllers, animated: false)
        }
        
        // We are done, we can return the navigation controller of the secondary view controller
        return mainFlowViewController.navForDetailsView
        
    }
        
    
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool {
        /* This happens when transioning from regular to compact width.
         * In case a SomeSingleDiscussionViewController is on screen (or a stack of SomeSingleDiscussionViewController),
         * we want to transfer this (or these) view controller(s) from the detail view controller
         * of the split view controller to the main view controller. To do so, we push this SingleDiscussionViewController onto the appropriate
         * flow, i.e., the flow corresponding to the select tab of the tab bar controller. In case the selected tab has no associated flow (e.g., for the
         * invitation or settings tab), we programmatically select the discussion tab before pushing the SingleDiscussionViewController.
         */

        // We expect to be the delegate of the MainFlowViewController (which is a UISplitViewController)
        guard let mainFlowViewController = splitViewController as? MainFlowViewController else {
            assertionFailure()
            return false // Let the split view controller try to incorporate the secondary view controller’s content into the collapsed interface
        }

        // Perform a few sanity checks
        
        guard primaryViewController == mainFlowViewController.mainTabBarController else {
            assertionFailure()
            return false // Let the split view controller try to incorporate the secondary view controller’s content into the collapsed interface
        }
        
        // Look for SomeSingleDiscussionViewController to keep
        
        let discussionsVCs = mainFlowViewController.navForDetailsView.viewControllers.compactMap({ $0 as? SomeSingleDiscussionViewController })
        
        // Remove all SomeSingleDiscussionViewController instances from all flows
        mainFlowViewController.allFlows.forEach { obvFlowController in
            let allVCsButDiscussionViewControllers = obvFlowController.viewControllers.filter({ !($0 is SomeSingleDiscussionViewController) })
            obvFlowController.setViewControllers(allVCsButDiscussionViewControllers, animated: false)
        }

        // If we have no SomeSingleDiscussionViewController to keep, we are done
        
        guard !discussionsVCs.isEmpty else {
            return false // Let the split view controller try to incorporate the secondary view controller’s content into the collapsed interface
        }
        
        // If the selected tab corresponds to a flow, use this flow to preserve discussionsVCs. Otherwise, use the discussion flow
        
        let obvFlowViewController: ObvFlowController
        if let obvFlow = mainFlowViewController.currentFlow {
            obvFlowViewController = obvFlow
        } else {
            obvFlowViewController = mainFlowViewController.discussionsFlowViewController
            mainFlowViewController.mainTabBarController.selectedIndex = MainFlowViewController.ChildTypes.latestDiscussions
        }
        
        // Push the discussionsVCs onto the stack of the flow:
        // Remove the discussionsVCs from their parent, then add them to the flow.
        // We perform this last step asynchronously as failing to do so leads to a crash under certain iPhones (e.g., iPhone XR).
        
        for vc in discussionsVCs {
            vc.view.removeFromSuperview()
            vc.willMove(toParent: nil)
            vc.removeFromParent()
            vc.didMove(toParent: nil)
        }

        DispatchQueue.main.async {
            obvFlowViewController.setViewControllers(obvFlowViewController.viewControllers + discussionsVCs, animated: false)
        }

        // We dealt with the discussionsVCs, we do not want the split view controller to do anything with the secondary view controller so we return true
        
        return true
        
    }
    
}


// Strings

extension MainFlowViewController {
    
    struct Strings {
        
        static let contactsTVCTitle = { (groupDiscussionTitle: String) in
            String.localizedStringWithFormat(NSLocalizedString("Members of %@", comment: "Title of the table listing all members of a discussion group."), groupDiscussionTitle)
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
            static let messageAdvanced = NSLocalizedString("In order to invite another Olvid user, you can copy your identity in order to paste it in an email, SMS, and so forth. If you receive an identity, you can paste it here.", comment: "Message of an alert")
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
        
        struct AlertChooseBetweenGlobalAndLocalOnOwnedIdentityDeletion {
            static let title = NSLocalizedString("CHOOSE_BETWEEN_GLOBAL_AND_LOCAL_OWNED_IDENTITY_DELETION_TITLE", comment: "")
            static let message = NSLocalizedString("CHOOSE_BETWEEN_GLOBAL_AND_LOCAL_OWNED_IDENTITY_DELETION_MESSAGE", comment: "")
            static let globalDeletionAction = NSLocalizedString("CHOOSE_GLOBAL_OWNED_IDENTITY_DELETION_BUTTON_TITLE", comment: "")
            static let localDeletionAction = NSLocalizedString("CHOOSE_LOCAL_OWNED_IDENTITY_DELETION_BUTTON_TITLE", comment: "")
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


// MARK: - Errors

extension MainFlowViewController {
    
    enum ObvError: Error {
        case storeKitDelegateIsNil
    }
    
}
