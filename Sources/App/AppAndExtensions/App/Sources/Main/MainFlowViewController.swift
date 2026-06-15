/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import OSLog
import StoreKit
import CoreData
import Combine
import Intents
import ObvEngine
import ObvTypes
import AVFoundation
import LinkPresentation
import SwiftUI
import ObvCrypto
import ObvUICoreData
import ObvUI
import ObvSettings
import ObvAppCoreConstants
import ObvKeycloakManager
import ObvScannerHostingView
import ObvAppTypes
import ObvOnboarding
import ObvSubscription
import ObvAppBackup
import ObvDesignSystem
import ObvSidebar
import ObvSystemIcon
import ObvProfilePictureBarButtonItem
import ObvGroupsList
import ObvSharedDataSources
import ObvOwnedIdentityChooser
import ObvInvitationFlow
import ObvUIGroupV1
import ObvUIGroupV2
import ObvCells
import ObvUIGroupSharedBetweenV1AndV2
import ObvSingleOwnedIdentity
import ObvHistoryTransfer


@MainActor
protocol MainFlowViewControllerActions: OlvidShopViewActions, UserTriesToAccessPaidFeatureViewActions {
    // Nothing to add for now
}

final class MainFlowViewController: UISplitViewController {
    
    private(set) var currentOwnedCryptoId: ObvCryptoId
    private let obvEngine: ObvEngine
    var anOwnedIdentityWasJustCreatedOrRestored = false
    private let actions: any MainFlowViewControllerActions

    private let splitDelegate: MainFlowViewControllerSplitDelegate // Strong reference to the delegate
    private weak var createPasscodeDelegate: CreatePasscodeDelegate?
    private weak var localAuthenticationDelegate: LocalAuthenticationDelegate?
    private weak var appBackupDelegate: AppBackupDelegate?
    private weak var mainFlowViewControllerDelegate: MainFlowViewControllerDelegate?
    private weak var storeKitDelegate: StoreKitDelegate?

    fileprivate let mainTabBarController: ObvSubTabBarController
    fileprivate let mainTabBarControllerDelegate: UITabBarControllerDelegateWithinMainFlowViewController
    fileprivate let navForDetailsView = UINavigationController(rootViewController: OlvidPlaceholderViewController())

    fileprivate let allFlowControllersForUITabBarController: AllObvFlowViewControllers
    fileprivate let allFlowControllersForUISplitViewController: AllObvFlowViewControllers

    private lazy var allFlowControllers: [ObvFlowController] = {
        allFlowControllersForUITabBarController.allFlowControllers + allFlowControllersForUISplitViewController.allFlowControllers
    }()
        
    private var observationTokens = [NSObjectProtocol]()
    
    private var secureCallsInBetaModalWasShown = false

    private let dataSources: ObvDataSources

    private var viewDidAppearWasCalled = false
    
    /// Allows to track if the scene corresponding to the view controller is active.
    /// This makes it possible to filter out certain calls made to the `UISplitViewControllerDelegate`
    /// and to prevent a bug under iPad, where the secondary view controller would otherwise be collapsed on the primary one
    /// when the user puts the app in the background.
    fileprivate var sceneIsActive = false
    
    private var savedViewControllersForNavForDetailsView = [ObvCryptoId: [UIViewController]]()
        
    // When an AirDrop deeplink is performed at a time no discussion is presented, we keep the file URL here so as to insert the file in the chosen discussion.
    private var airDroppedFileURLs = [URL]()
    
    /// This router allows to present the flow allowing to create a new group v2.
    /// It is expected to be set only once.
    /// The delegate methods are implemented in an extension of `ObvFlowController`.
    private(set) lazy var routerForGroupV2Creation: ObvGroupV2CreationRouter = {
        .init(dataSources: dataSources.groupV2RouterDataSources, actions: self)
    }()
    
    private(set) lazy var routerForGroupV1Creation: ObvGroupV1CreationRouter = {
        .init(dataSources: dataSources.groupV1RouterDataSources, actions: self)
    }()

    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: MainFlowViewController.self))
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: MainFlowViewController.self))
    
    init(ownedCryptoId: ObvCryptoId,
         obvEngine: ObvEngine,
         createPasscodeDelegate: CreatePasscodeDelegate,
         localAuthenticationDelegate: LocalAuthenticationDelegate,
         appBackupDelegate: AppBackupDelegate,
         mainFlowViewControllerDelegate: MainFlowViewControllerDelegate,
         storeKitDelegate: StoreKitDelegate,
         dataSources: ObvDataSources,
         actions: any MainFlowViewControllerActions) {
                
        Self.logger.info("🥏🏁 Call to the initializer of MainFlowViewController")
                
        self.obvEngine = obvEngine
        self.currentOwnedCryptoId = ownedCryptoId
        self.createPasscodeDelegate = createPasscodeDelegate
        self.localAuthenticationDelegate = localAuthenticationDelegate
        self.appBackupDelegate = appBackupDelegate
        self.storeKitDelegate = storeKitDelegate
        self.mainFlowViewControllerDelegate = mainFlowViewControllerDelegate
        self.splitDelegate = MainFlowViewControllerSplitDelegate()
        self.dataSources = dataSources
        self.actions = actions
        self.allFlowControllersForUITabBarController = Self.createAllObvFlowControllers(
            ownedCryptoId: ownedCryptoId,
            obvEngine: obvEngine,
            dataSources: dataSources)
        self.allFlowControllersForUISplitViewController = Self.createAllObvFlowControllers(
            ownedCryptoId: ownedCryptoId,
            obvEngine: obvEngine,
            dataSources: dataSources)

        let mainTabBarController = ObvSubTabBarController()
        self.mainTabBarController = mainTabBarController
        if #available(iOS 18, *) {
            self.mainTabBarControllerDelegate = UITabBarControllerDelegateNew()
        } else {
            self.mainTabBarControllerDelegate = UITabBarControllerDelegateOld()
        }
        
        super.init(style: .tripleColumn)
        
        self.delegate = splitDelegate
                
        addObvFlowControllersToUITabBarController()
        addObvFlowControllersToUISplitViewController()
        
        self.mainTabBarControllerDelegate.mfvc = self
        mainTabBarController.delegate = self.mainTabBarControllerDelegate
        allFlowControllers.forEach { $0.flowDelegate = self }

        //self.appDataSourceForObvUIGroupV2Router.setDelegate(to: self)
        self.dataSources.sideBarViewAppDataSource.delegate = self
                
        if #available(iOS 26, *) {
            // We don't change the appearance under iOS 26
        } else {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            navForDetailsView.navigationBar.standardAppearance = appearance
        }

        // If the user has no discussion to show in the latestDiscussions tab, show the contacts tab
        
        if let countOfUnarchivedDiscussions = try? PersistedDiscussion.countUnarchivedDiscussionsOfOwnedIdentity(ownedCryptoId: ownedCryptoId, within: ObvStack.shared.viewContext), countOfUnarchivedDiscussions == 0 {
            switchToFlow(.contacts)
        }
                
        // Listen to notifications
        
        observeUserWantsToShareOwnPublishedDetailsNotifications()
        observeUserWantsToCallNotifications()
        observeServerDoesNotSupportCall()
        observeUserWantsToSelectAndCallContactsNotifications()

        observationTokens.append(contentsOf: [

            // ObvMessengerInternalNotification
            ObvMessengerInternalNotification.observeOlvidSnackBarShouldBeShown { [weak self] ownedCryptoId, category in
                Task { await self?.showSnackBarOnAllTabBarChildren(with: category, forOwnedIdentity: ownedCryptoId) }
            },
            ObvMessengerInternalNotification.observeOlvidSnackBarShouldBeHidden { [weak self] ownedCryptoId in
                Task { await self?.hideSnackBarOnAllTabBarChildren(forOwnedIdentity: ownedCryptoId) }
            },
            ObvMessengerInternalNotification.observeUserWantsToSeeDetailedExplanationsOfSnackBar { [weak self] ownedCryptoId, snackBarCategory in
                Task { await self?.processUserWantsToSeeDetailedExplanationsOfSnackBar(ownedCryptoId: ownedCryptoId, snackBarCategory: snackBarCategory) }
            },
            ObvMessengerInternalNotification.observeBadgeForNewMessagesHasBeenUpdated { [weak self] ownedCryptoId, newCount in
                Task { await self?.processBadgeForNewMessagesHasBeenUpdated(ownCryptoId: ownedCryptoId, newCount: newCount) }
            },
            ObvMessengerInternalNotification.observeBadgeForInvitationsHasBeenUpdated { [weak self] ownedCryptoId, newCount in
                Task { await self?.processBadgeForInvitationsHasBeenUpdated(ownCryptoId: ownedCryptoId, newCount: newCount) }
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
    

    private static func createAllObvFlowControllers(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, dataSources: ObvDataSources) -> AllObvFlowViewControllers {
        let discussionsFlowViewController = DiscussionsFlowViewController(
            ownedCryptoId: ownedCryptoId,
            obvEngine: obvEngine,
            dataSources: dataSources)
        let contactsFlowViewController = ContactsFlowViewController(
            ownedCryptoId: ownedCryptoId,
            obvEngine: obvEngine,
            dataSources: dataSources)
        let groupsFlowViewController = GroupsFlowViewController(
            ownedCryptoId: ownedCryptoId,
            obvEngine: obvEngine,
            dataSources: dataSources)
        let invitationsFlowViewController = NewInvitationsFlowViewController(
            ownedCryptoId: ownedCryptoId,
            obvEngine: obvEngine,
            dataSources: dataSources)
        return AllObvFlowViewControllers(
            discussionsFlowViewController: discussionsFlowViewController,
            contactsFlowViewController: contactsFlowViewController,
            groupsFlowViewController: groupsFlowViewController,
            invitationsFlowViewController: invitationsFlowViewController)
    }
    
  
    fileprivate func addObvFlowControllersToUITabBarController() {
        
        if #available(iOS 18, *) {
            
            mainTabBarController.tabs = ObvFlow.allCases.map { flow in
                UITab(title: Self.tabTitleForFlow(flow),
                      image: UIImage(systemIcon: Self.tabSystemIcon(flow)),
                      identifier: flow.rawValue,
                      viewControllerProvider: { _ in
                          self.allFlowControllersForUITabBarController.flowControllerForFlow(flow)
                      })
            }
            
        } else {

            for flow in ObvFlow.allCases {
                mainTabBarController.addChild(self.allFlowControllersForUITabBarController.flowControllerForFlow(flow))
            }
            
        }

    }
    

    /// Helper method for `addObvFlowControllersToUITabBarController()`.
    private static func tabTitleForFlow(_ flow: ObvFlow) -> String {
        switch flow {
        case .latestDiscussions: return String(localized: "UI_TAB_TITLE_DISCUSSIONS", comment: "UITab tab title")
        case .contacts: return String(localized: "UI_TAB_TITLE_CONTACTS", comment: "UITab tab title")
        case .groups: return String(localized: "UI_TAB_TITLE_GROUPS", comment: "UITab tab title")
        case .invitations: return String(localized: "UI_TAB_TITLE_INVITATIONS", comment: "UITab tab title")
        }
    }
    

    /// Helper method for `addObvFlowControllersToUITabBarController()`.
    private static func tabSystemIcon(_ flow: ObvFlow) -> SystemIcon {
        switch flow {
        case .latestDiscussions: return .bubbleLeftAndBubbleRight
        case .contacts: return .person
        case .groups: return .person3
        case .invitations: return .trayAndArrowDown
        }
    }
    
    
    fileprivate func addObvFlowControllersToUISplitViewController() {
        
        let initialFlow: ObvFlow = .latestDiscussions

        // Specify the view controllers to show when the UISplitViewController is expanded
        self.setViewController(ObvSideBarViewController(actions: self, dataSource: self.dataSources.sideBarViewAppDataSource), for: .primary)
        self.setViewController(self.allFlowControllersForUISplitViewController.flowControllerForFlow(initialFlow), for: .supplementary)
        self.setViewController(self.navForDetailsView, for: .secondary)

        // Specify the view controllers to show when the UISplitViewController is compact
        self.setViewController(self.mainTabBarController, for: .compact)
        
        configureColumnsGeometry()
        
        OlvidUserActivitySingleton.shared.switchCurrentFlow(to: initialFlow, currentOwnedCryptoId: self.currentOwnedCryptoId, viewController: self)
        
    }
    
    
    
    /// Configure the geometry of the primary, supplementary, and secondary columns of this UISplitViewController.
    private func configureColumnsGeometry() {
        
        // Fix the size of the .primary column
        self.preferredPrimaryColumnWidth = ObvSideBarView.Constants.idealColumnWidth
        
        // Under certain versions of iOS, we must tweak the display mode to achieve an acceptable result
        if #available(iOS 26, *) {
            #if targetEnvironment(macCatalyst)
            self.preferredSupplementaryColumnWidthFraction = 0.25
            // Ensures the "Add group" nav button is never clipped
            self.minimumSupplementaryColumnWidth = 375
            #else
            self.preferredSupplementaryColumnWidthFraction = 0.37
            self.minimumSupplementaryColumnWidth = 320
            #endif
        } else {
            self.preferredSplitBehavior = .tile
            self.preferredDisplayMode = .twoBesideSecondary
            #if targetEnvironment(macCatalyst)
            self.preferredSupplementaryColumnWidthFraction = 0.40
            #else
            self.preferredSupplementaryColumnWidthFraction = 0.37
            #endif
        }

    }
    
    
    /// Called by the MetaFlowController (itself called by the SceneDelegate).
    @MainActor
    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        sceneIsActive = true
        if viewDidAppearWasCalled == true {
            presentOneOfTheModalViewControllersIfRequired()
        }
    }

    
    /// Called by the MetaFlowController (itself called by the SceneDelegate).
    @MainActor
    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        sceneIsActive = false
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
    private func processUserWantsToSeeDetailedExplanationsOfSnackBar(ownedCryptoId: ObvCryptoId, snackBarCategory: OlvidSnackBarCategory) async {
        assert(Thread.isMainThread)
        guard self.currentOwnedCryptoId == ownedCryptoId else { return }
        
        let vc = OlvidAlertViewController()
        vc.configure(
            title: snackBarCategory.detailsTitle,
            body: snackBarCategory.detailsBody,
            primaryActionTitle: snackBarCategory.primaryActionTitle,
            primaryAction: { [weak self] in
                (self?.presentedViewController as? OlvidAlertViewController)?.dismiss(animated: true) {
                    switch snackBarCategory {
                    case .grantPermissionToRecord:
                        AVAudioSession.sharedInstance().requestRecordPermission { _ in
                            ObvMessengerInternalNotification.displayedSnackBarShouldBeRefreshed.postOnDispatchQueue()
                        }
                    case .grantPermissionToRecordInSettings:
                        guard let appSettings = URL(string: UIApplication.openRecordSettingsURLString) else { assertionFailure(); return }
                        guard UIApplication.shared.canOpenURL(appSettings) else { assertionFailure(); return }
                        UIApplication.shared.open(appSettings, options: [:])
                    case .newerAppVersionAvailable:
                        guard UIApplication.shared.canOpenURL(ObvMessengerConstants.shortLinkToOlvidAppIniTunes) else { assertionFailure(); return }
                        UIApplication.shared.open(ObvMessengerConstants.shortLinkToOlvidAppIniTunes, options: [:], completionHandler: nil)
                    }
                }
            },
            secondaryActionTitle: snackBarCategory.secondaryActionTitle,
            secondaryAction: { [weak self] in
                (self?.presentedViewController as? OlvidAlertViewController)?.dismiss(animated: true) {
                    switch snackBarCategory {
                    case .grantPermissionToRecord, .grantPermissionToRecordInSettings:
                        ObvMessengerInternalNotification.UserDismissedSnackBarForLater(ownedCryptoId: ownedCryptoId, snackBarCategory: snackBarCategory)
                            .postOnDispatchQueue()
                    case .newerAppVersionAvailable:
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
    fileprivate var currentFlowController: ObvFlowController? {
        if self.isCollapsed {
            assert(mainTabBarController.selectedObvTab == OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow)
            guard let currentFlow = mainTabBarController.selectedObvTab ?? OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow else { assertionFailure(); return nil }
            return self.allFlowControllersForUITabBarController.flowControllerForFlow(currentFlow)
        } else {
            guard let supplementaryViewController = self.viewController(for: .supplementary) as? ObvFlowController else { assertionFailure(); return nil }
            return supplementaryViewController
        }
    }
    

    private var alreadyPushingDiscussionViewController = false
    

    @MainActor
    private func showSnackBarOnAllTabBarChildren(with category: OlvidSnackBarCategory, forOwnedIdentity ownedCryptoId: ObvCryptoId) async {
        assert(Thread.isMainThread)
        guard self.currentOwnedCryptoId == ownedCryptoId else { return }
        allFlowControllers.forEach { flowViewController in
            flowViewController.showSnackBar(with: category, currentOwnedCryptoId: ownedCryptoId, completion: {})
        }
    }
    
    
    @MainActor
    private func hideSnackBarOnAllTabBarChildren(forOwnedIdentity ownedCryptoId: ObvCryptoId) async {
        assert(Thread.isMainThread)
        guard self.currentOwnedCryptoId == ownedCryptoId else { return }
        allFlowControllers.forEach { flowViewController in
            flowViewController.removeSnackBar(completion: {})
        }
    }
    
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()

        /// At launch, always display the primary column
        self.show(.primary)

    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        viewDidAppearWasCalled = true
        Task {
            await OlvidUserActivitySingleton.shared.switchCurrentOwnedCryptoId(to: currentOwnedCryptoId, viewController: self)
        }
        guard let obvOwnedIdentity = try? obvEngine.getOwnedIdentity(with: currentOwnedCryptoId) else {
            assertionFailure()
            return
        }
        if obvOwnedIdentity.isKeycloakManaged {
            Task {
                do {
                    try await KeycloakManagerSingleton.shared.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: currentOwnedCryptoId, ignoreSynchronizationInterval: false)
                } catch let error as KeycloakManager.ObvSynchronizeError {
                    switch error {
                    case .userHasCancelled:
                        Self.logger.error("🧥 User cancelled")
                        return
                    }
                }
            }
        }
        
        // This is required for the MainFlowViewController.find(_:) and other methods to be called when the user types the default key command for search.
        becomeFirstResponder()
        
    }
    
    
    @MainActor
    private func presentOneOfTheModalViewControllersIfRequired() {
        assert(Thread.isMainThread)
        guard (ObvMessengerSettings.AppVersionAvailable.minimum ?? 0) <= ObvAppCoreConstants.bundleVersionAsInt else {
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


// MARK: - Implementing ObvSideBarViewAppDataSourceDelegate

extension MainFlowViewController: ObvSideBarViewAppDataSourceDelegate {
    
    func getCurrentOwnedCryptoId(_ dataSource: ObvSideBarViewAppDataSource) -> ObvTypes.ObvCryptoId? {
        self.currentOwnedCryptoId
    }
    
}


// MARK: - Implementing ObvSideBarViewActions

extension MainFlowViewController: ObvSideBarViewActions {
    
    func userDidTapOnSidebarItem(_ view: ObvSidebar.ObvSideBarView, _ flow: ObvAppTypes.ObvFlow) async throws {
        switchToFlow(flow)
    }
    
}


// MARK: - Keyboard shortcuts

extension MainFlowViewController {
    
    override var canBecomeFirstResponder: Bool {
        // This is required for the MainFlowViewController.find(_:) and other methods to be called when the user types the default key command for search.
        return true
    }
    
    
    /// Resets the navigation stack to the root view controller (showing the Olvid logo) in response to a keyboard shortcut.
    ///
    /// This method is automatically called when the user presses **Cmd+0**, as defined by the `UIKeyCommand`
    /// in `ObvMenuController`. It pops all discussions from the navigation stack, returning the app to its initial state.
    @objc func processUIKeyCommandForHome() {
        navForDetailsView.popToRootViewController(animated: true)
    }
    
    
    /// Navigates to the list of recent discussions in response to a keyboard shortcut.
    ///
    /// This method is automatically called when the user presses **Cmd+1**, as defined by the `UIKeyCommand`
    /// in `ObvMenuController`. It updates the navigation stack to display the recents discussions list.
    @objc func processUIKeyCommandForSwitchingToFlowLatestDiscussions() {
        self.switchToFlow(.latestDiscussions)
    }

    
    /// Navigates to the list of contacts in response to a keyboard shortcut.
    ///
    /// This method is automatically called when the user presses **Cmd+2**, as defined by the `UIKeyCommand`
    /// in `ObvMenuController`. It updates the navigation stack to display the contacts list.
    @objc func processUIKeyCommandForSwitchingToFlowContacts() {
        self.switchToFlow(.contacts)
    }

    
    /// Navigates to the list of groups in response to a keyboard shortcut.
    ///
    /// This method is automatically called when the user presses **Cmd+3**, as defined by the `UIKeyCommand`
    /// in `ObvMenuController`. It updates the navigation stack to display the groups list.
    @objc func processUIKeyCommandForSwitchingToFlowGroups() {
        self.switchToFlow(.groups)
    }

    
    /// Navigates to the list of invitations in response to a keyboard shortcut.
    ///
    /// This method is automatically called when the user presses **Cmd+4**, as defined by the `UIKeyCommand`
    /// in `ObvMenuController`. It updates the navigation stack to display the invitations list.
    @objc func processUIKeyCommandForSwitchingToFlowInvitations() {
        self.switchToFlow(.invitations)
    }
    
    
    /// Opens the invitation flow.
    ///
    /// This method is automatically called when the user presses **Cmd+N**, as defined by the `UIKeyCommand`
    /// in `ObvMenuController`.
    @objc func processUIKeyCommandForNewMessage() {
        self.userWantsPresentInvitationFlow()
    }

    
    /// Overriding this method allows to be called when the user types the standard keyboard shortcut (Cmd+F) for search.
    ///
    /// We pass this information to the most appropriate `NewSingleDiscussionViewController`.
    override func find(_ sender: Any?) {
        if let discussionVC = navForDetailsView.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.find(sender)
        } else if let discussionVC = currentFlowController?.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.find(sender)
        }
    }
    
    
    /// Overriding this method allows to be called when the user types the standard keyboard shortcut (Cmd+G) for "Find next".
    ///
    /// We pass this information to the most appropriate `NewSingleDiscussionViewController`.
    override func findNext(_ sender: Any?) {
        if let discussionVC = navForDetailsView.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.findNext(sender)
        } else if let discussionVC = currentFlowController?.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.findNext(sender)
        }
    }
    
    
    /// Overriding this method allows to be called when the user types the standard keyboard shortcut (Shift+Cmd+G) for "Find previous".
    ///
    /// We pass this information to the most appropriate `NewSingleDiscussionViewController`.
    override func findPrevious(_ sender: Any?) {
        if let discussionVC = navForDetailsView.topViewController as? NewSingleDiscussionViewController {
            return discussionVC.findPrevious(sender)
        } else if let discussionVC = currentFlowController?.topViewController as? NewSingleDiscussionViewController {
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
        for obvFlowController in allFlowControllers {
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
                    return try currentFlowController?.getNewSingleDiscussionViewController(discussionObjectID: discussion.typedObjectID, initialScroll: .newMessageSystemOrLastMessage)
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
        for obvFlowController in self.allFlowControllers {
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

        guard self.currentOwnedCryptoId != newOwnedCryptoId else {
            return
        }

        let oldOwnedCryptoId = self.currentOwnedCryptoId
        self.currentOwnedCryptoId = newOwnedCryptoId
        
        for flow in self.allFlowControllers {
            flow.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
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
        
        await OlvidUserActivitySingleton.shared.switchCurrentOwnedCryptoId(to: newOwnedCryptoId, viewController: self)
        
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
                await requestLocalNotificationsAuthorization()
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
    
    
    /// Presents the system notification-authorization dialog. Safe to call even if authorization has already been decided —
    /// `requestAuthorization` is a no-op in that case.
    private func requestLocalNotificationsAuthorization() async {
        let center = UNUserNotificationCenter.current()
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Self.logger.error("Could not request authorization for notifications: \(error, privacy: .public)")
        }
    }

}


// MARK: - Setting/refreshing badges on the tabbar

extension MainFlowViewController {
    
    @MainActor
    private func processBadgeForNewMessagesHasBeenUpdated(ownCryptoId: ObvCryptoId, newCount: Int) async {
        assert(Thread.isMainThread)
        guard ownCryptoId == self.currentOwnedCryptoId else { return }
        if let tabbarItem = allFlowControllersForUITabBarController.flowControllerForFlow(.latestDiscussions).tabBarItem {
            tabbarItem.badgeValue = newCount > 0 ? "\(newCount)" : nil
        }
    }
    
    
    @MainActor
    private func processBadgeForInvitationsHasBeenUpdated(ownCryptoId: ObvCryptoId, newCount: Int) async {
        assert(Thread.isMainThread)
        guard ownCryptoId == self.currentOwnedCryptoId else { return }
        if let tabbarItem = allFlowControllersForUITabBarController.flowControllerForFlow(.invitations).tabBarItem {
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
        alert.addAction(UIAlertAction(title: Strings.AlertTypeDeleteToProceedWithOwnedIdentityDeletion.doDelete, style: .destructive, handler: { [weak self, unowned alert] _ in
            guard let textField = alert.textFields?.first else { assertionFailure(); return }
            guard textField.text?.trimmingWhitespacesAndNewlines() == Strings.AlertTypeDeleteToProceedWithOwnedIdentityDeletion.wordToType else { return }
            Task { await self?.userWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ownedCryptoId, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion) }
        }))
        alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
        present(alert, animated: true)
    }

    
    @MainActor
    private func userWantsToDeleteOwnedIdentityAndHasConfirmed(ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) async {
        do {
            guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
            try await mainFlowViewControllerDelegate.userWantsToDeleteOwnedIdentityAndHasConfirmed(self, ownedCryptoId: ownedCryptoId, globalOwnedIdentityDeletion: globalOwnedIdentityDeletion)
        } catch {
            await showThenHideHUD(type: .xmark)
        }
    }
    
}

// MARK: - Implementing AppListOfGroupMembersViewDataSourceDelegate

//extension MainFlowViewController: AppListOfGroupMembersViewDataSourceDelegate {
//    
//    func fetchAvatarImage(_ dataSource: AppDataSourceForObvUIGroupV2Router, localPhotoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
//        return try await self.dataSources.fetchAvatarImage(localPhotoURL: localPhotoURL, avatarSize: avatarSize)
//    }
//    
//}


// MARK: - Implementing ObvFlowControllerDelegate

extension MainFlowViewController: ObvFlowControllerDelegate {
    
    func userWantsToRequestNotificationsAuthorization(_ vc: ObvFlowController) {
        Task { await requestLocalNotificationsAuthorization() }
    }
    
    func userWantsToForwardMessage(_ vc: ObvFlowController, identifierOfMessageToForwad: ObvMessageAppIdentifier, identifiersOfDiscussionsWhereMessageShouldBeForwarded: Set<ObvDiscussionIdentifier>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToForwardMessage(self, identifierOfMessageToForwad: identifierOfMessageToForwad, identifiersOfDiscussionsWhereMessageShouldBeForwarded: identifiersOfDiscussionsWhereMessageShouldBeForwarded)
    }
    
    func userWantsToUpdateDiscussionLocalConfiguration(_ vc: ObvFlowController, value: ObvUICoreData.PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedDiscussionLocalConfiguration>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToUpdateDiscussionLocalConfiguration(self, value: value, localConfigurationObjectID: localConfigurationObjectID)
    }
    
    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ flowController: ObvFlowController) {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        mainFlowViewControllerDelegate.userWantsToDismissOlvidPlusSuccessfulSubscriptionView(self)
    }
    
    func userWantsToDiscoverOlvidPlus(_ flowController: ObvFlowController) {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        mainFlowViewControllerDelegate.userWantsToDiscoverOlvidPlus(self)
    }
    
    func userWantsToUpdateGroupNameAndPicture(_ flowController: ObvFlowController, groupV1Identifier: ObvGroupV1Identifier, changes: Set<EditGroupNameAndPictureView.Change>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        try await mainFlowViewControllerDelegate.userWantsToUpdateGroupNameAndPicture(self, groupV1Identifier: groupV1Identifier, changes: changes)
    }
    
    func userWantsToAddSelectedUsersToExistingGroup(_ flowController: ObvFlowController, groupV1Identifier: ObvGroupV1Identifier, newGroupMembers: Set<ObvCryptoId>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        try await mainFlowViewControllerDelegate.userWantsToAddSelectedUsersToExistingGroup(self, groupV1Identifier: groupV1Identifier, newGroupMembers: newGroupMembers)
    }
    
    func userWantsToRemoveMembersFromGroupV1(_ flowController: ObvFlowController, groupV1Identifier: ObvGroupV1Identifier, removedGroupMembers: Set<ObvCryptoId>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        try await mainFlowViewControllerDelegate.userWantsToRemoveMembersFromGroupV1(self, groupV1Identifier: groupV1Identifier, removedGroupMembers: removedGroupMembers)
    }
    
    
    func userDidSeeNewDetailsOfContact(_ flowController: ObvFlowController, contactIdentifier: ObvContactIdentifier) {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        mainFlowViewControllerDelegate.userDidSeeNewDetailsOfContact(self, contactIdentifier: contactIdentifier)
    }
    
    
    func userWantsToUpdatePersonalNote(_ flowController: ObvFlowController, with newText: String?, about: PersonalNoteEditorView.Model.About) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToUpdatePersonalNote(self, with: newText, about: about)
    }
    
    
    func userWantsToRemoveOneToOneInvitationSent(_ flowController: ObvFlowController, contactIdentifier: ObvContactIdentifier) async throws {
        try await self.userWantsToRemoveOneToOneInvitationSent(ownedCryptoId: contactIdentifier.ownedCryptoId, contactCryptoId: contactIdentifier.contactCryptoId)
    }
    
    func userWantsToReblockContact(_ flowController: ObvFlowController, contactIdentifier: ObvContactIdentifier) async throws {
        try await obvEngine.reblockContactIdentity(contactIdentifier: contactIdentifier)
    }
    

    func userWantsToCreateNewGroup(_ flowController: ObvFlowController, ownedCryptoId: ObvTypes.ObvCryptoId) {
        userWantsToAddContactGroup(ownedCryptoId: ownedCryptoId)
    }

    
    /// Returns the most appropriate `UINavigationController` for displaying a discussion.
    ///
    /// - Returns: The `UINavigationController` where the discussion should be presented.
    ///
    /// This method is called by `ObvFlowController` when it needs to show a discussion.
    ///
    /// - Note:
    ///   - In a **compact environment**, the current flow (corresponding to the selected tab in the `UITabBarController`) is returned.
    ///   - In an **expanded environment**, the navigation stack of the **secondary column** of this `UISplitViewController` is returned.
    func appropriateUINavigationControllerToPushOrPopDiscussion(_ flowController: ObvFlowController) throws -> UINavigationController {

        if self.isCollapsed {

            assert(OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow == mainTabBarController.selectedObvTab)
            guard let currentFlow = mainTabBarController.selectedObvTab ?? OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow else { assertionFailure(); throw ObvError.couldNotDetermineCurrentFlow }
            return self.allFlowControllersForUITabBarController.flowControllerForFlow(currentFlow)

        } else {

            return navForDetailsView

        }

    }
    
    
    func appropriateViewControllerToPresentViewController(_ flowController: ObvFlowController) throws -> UIViewController {
        return self
    }

    /// Called when the user taps the "plus" button implemented in SwiftUI
    func userTappedObvPlusButton(_ flowController: ObvFlowController) {
        userWantsPresentInvitationFlow()
    }
    
    func userWantsToProcessReceiptsStoredForLater(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, returnReceiptElements: Set<ObvReturnReceiptElements>) async {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        await mainFlowViewControllerDelegate.userWantsToProcessReceiptsStoredForLater(self, ownedCryptoId: ownedCryptoId, returnReceiptElements: returnReceiptElements)
    }
    
    func showAlertForUnlockingHiddenOwnedIdentity(_ flowController: ObvFlowController) {
        showAlertForUnlockingHiddenOwnedIdentity()
    }
    
    func userWantsToDeleteDiscussionsAndHasConfirmed(_ flowController: ObvFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>], deletionType: DeletionType) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToDeleteDiscussionsAndHasConfirmed(self, discussionObjectIDs: discussionObjectIDs, deletionType: deletionType)
    }
    
    func userWantsToArchiveDiscussions(_ flowController: ObvFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToArchiveDiscussions(self, discussionObjectIDs: discussionObjectIDs)
    }
    
    
    func userWantsToUnarchiveDiscussions(_ flowController: ObvFlowController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToUnarchiveDiscussions(self, discussionObjectIDs: discussionObjectIDs)
    }
    
    
    func userWantsToReorderPinnedDiscussions(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, objectIDOfPinnedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToReorderPinnedDiscussions(self, ownedCryptoId: ownedCryptoId, objectIDOfPinnedDiscussions: objectIDOfPinnedDiscussions)
    }
    
    
    func userWantsToMarkAllMessagesAsReadInDiscussion(_ flowController: ObvFlowController, discussionObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedDiscussion>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToMarkAllMessagesAsReadInDiscussion(self, discussionObjectID: discussionObjectID)
    }
    
    
    func userWantsToDisplayBackupKey(_ flowController: ObvFlowController) {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        mainFlowViewControllerDelegate.userWantsToDisplayBackupKey(self)
    }
    
    
    func userWantsToSetupNewBackups(_ flowController: ObvFlowController) {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        mainFlowViewControllerDelegate.userWantsToConfigureNewBackups(self, context: .afterOnboardingWithoutMigratingFromLegacyBackups)
    }
    
    func userWantsToShowMapToConsultLocationSharedContinously(_ flowController: ObvFlowController, presentingViewController: UIViewController, ownedCryptoId: ObvCryptoId) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToShowMapToConsultLocationSharedContinously(self, presentingViewController: presentingViewController, ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToShowMapToConsultLocationSharedContinously(_ flowController: ObvFlowController, presentingViewController: UIViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToShowMapToConsultLocationSharedContinously(self, presentingViewController: presentingViewController, messageObjectID: messageObjectID)
    }

    
    func userWantsToShowMapToSendOrShareLocationContinuously(_ flowController: ObvFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToShowMapToSendOrShareLocationContinuously(self, presentingViewController: presentingViewController, discussionIdentifier: discussionIdentifier)
    }
    
    
    func userWantsToStopSharingLocationInDiscussion(_ flowController: ObvFlowController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToStopSharingLocationInDiscussion(self, discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToCreatePoll(_ flowController: ObvFlowController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToCreatePoll(self, presentingViewController: presentingViewController, discussionIdentifier: discussionIdentifier)
    }
    
    func userWantsToDisplayPollView(_ flowController: ObvFlowController, presentingViewController: UIViewController, pollObjectID: TypeSafeManagedObjectID<PersistedPoll>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToDisplayPollView(self, presentingViewController: presentingViewController, pollObjectID: pollObjectID)
    }
    
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ flowController: ObvFlowController) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(self)
    }
    
    func userWantsToUpdateReaction(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToUpdateReaction(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, newEmoji: newEmoji)
    }
    
    func userWantsToUpdatePollVote(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, voted: Bool, version: Int) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToUpdatePollVote(self, ownedCryptoId: ownedCryptoId, messageObjectID: messageObjectID, pollVoteCandidateUuid: pollVoteCandidateUuid, voted: voted, version: version)
    }

    
    func messagesAreNotNewAnymore(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.messagesAreNotNewAnymore(self, ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageIds: messageIds)
    }
    
    
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ flowController: ObvFlowController, discussionPermanentID: ObvUICoreData.ObvManagedObjectPermanentID<ObvUICoreData.PersistedDiscussion>, messagePermanentIDs: Set<ObvUICoreData.ObvManagedObjectPermanentID<ObvUICoreData.PersistedMessage>>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(self, discussionPermanentID: discussionPermanentID, messagePermanentIDs: messagePermanentIDs)
    }
    
    
    func userWantsToReadReceivedMessageThatRequiresUserAction(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToReadReceivedMessageThatRequiresUserAction(self, ownedCryptoId: ownedCryptoId, discussionId: discussionId, messageId: messageId)
    }
    
    
    func userWantsToUpdateDraftExpiration(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToUpdateDraftExpiration(self, draftObjectID: draftObjectID, value: value)
    }
    
    
    func insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(_ flowController: ObvFlowController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(self, discussionObjectID: discussionObjectID, markAsRead: markAsRead)
    }
    
    
    func userWantsToRemoveReplyToMessage(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToRemoveReplyToMessage(self, draftObjectID: draftObjectID)
    }
    
    
    func userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ flowController: ObvFlowController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(self, sentJoinObjectID: sentJoinObjectID)
    }
    
    
    func userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ flowController: ObvFlowController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(self, sentJoinObjectID: sentJoinObjectID)
    }
    
    
    func userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(_ flowController: ObvFlowController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(self, receivedJoinObjectID: receivedJoinObjectID)
    }
    
    
    func userWantsToDownloadReceivedFyleMessageJoinWithStatus(_ flowController: ObvFlowController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToDownloadReceivedFyleMessageJoinWithStatus(self, receivedJoinObjectID: receivedJoinObjectID)
    }
    
    
    func userWantsToReplyToMessage(_ flowController: ObvFlowController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToReplyToMessage(self, messageObjectID: messageObjectID, draftObjectID: draftObjectID)
    }
    
    
    func userWantsToDeleteDraftAttachment(_ flowController: ObvFlowController, draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToDeleteDraftAttachment(self, draftFyleJoinObjectID: draftFyleJoinObjectID)
    }
    
    func userWantsToUpdateDraftBodyAndMentions(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: AttributedString) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToUpdateDraftBodyAndMentions(self, draftObjectID: draftObjectID, body: body)
    }
    
    
    func userWantsToAddAttachmentsToDraftFromURLs(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL]) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToAddAttachmentsToDraftFromURLs(self, draftObjectID: draftObjectID, urls: urls)
    }
    
    
    func userWantsToAddAttachmentsToDraft(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], source: LoadItemProviderHelper.ItemProviderProviderSource) async throws -> [LoadedItemProviderToPaste] {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsToAddAttachmentsToDraft(self, draftObjectID: draftObjectID, itemProviders: itemProviders, source: source)
    }
    
    func userWantsToSendDraft(_ flowController: ObvFlowController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: AttributedString) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToSendDraft(mainFlowViewController: self, draftObjectID: draftObjectID, textBody: textBody)
    }
    
    /// Called when the user taps the "plus" button implemented in UIKit
    func floatingButtonTapped(flow: ObvFlowController) {
        userWantsPresentInvitationFlow()
    }
    
    
    func userWantsToPublishGroupV2Modification(_ flowController: ObvFlowController, groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToPublishGroupV2Modification(self, groupObjectID: groupObjectID, changeset: changeset)
    }
    
    
    @MainActor
    private func userWantsPresentInvitationFlow() {
        assert(Thread.isMainThread)
        
        let fullDisplayName: String
        let ownedIdentityIsManagedByKeycloak: Bool
        do {
            (fullDisplayName, ownedIdentityIsManagedByKeycloak) = try PersistedObvOwnedIdentity.getFullDisplayNameAndIsKeycloakManaged(ownedCryptoId: self.currentOwnedCryptoId, within: ObvStack.shared.viewContext)
        } catch {
            return
        }
        let ownedURLIdentity = ObvURLIdentity(cryptoId: currentOwnedCryptoId, fullDisplayName: fullDisplayName)
        let vc = InvitationFlowHostingController(
            ownedURLIdentity: ownedURLIdentity,
            ownedIdentityIsManagedByKeycloak: ownedIdentityIsManagedByKeycloak,
            routerMode: .listOfContactsAndGroups,
            invitationFlowHostingControllerDataSources: dataSources.invitationFlowHostingControllerDataSources,
            actions: self,
            navigation: self)
        dismiss(animated: true) {
            self.present(vc, animated: true)
        }

    }
    
    
    private func userWantsToAddContactGroup(ownedCryptoId: ObvTypes.ObvCryptoId) {
        assert(Thread.isMainThread)
        
        if ObvMessengerConstants.developmentMode {
            
            let alert = UIAlertController(title: NSLocalizedString("CHOOSE_GROUP_TYPE_TITLE", comment: ""),
                                          message: NSLocalizedString("CHOOSE_GROUP_TYPE_MESSAGE", comment: ""),
                                          preferredStyleForTraitCollection: self.traitCollection)
            alert.addAction(UIAlertAction(title: NSLocalizedString("CHOOSE_GROUP_V1", comment: ""), style: .default, handler: { [weak self] (action) in
                guard let self else { return }
                routerForGroupV1Creation.presentInitialViewControllerForGroupV1Creation(
                    ownedCryptoId: currentOwnedCryptoId,
                    presentingViewController: self,
                    navigation: self)                
            }))
            alert.addAction(UIAlertAction(title: NSLocalizedString("CHOOSE_GROUP_V2", comment: ""), style: .default, handler: { [weak self] (action) in
                guard let self else { return }
                routerForGroupV2Creation.presentInitialViewControllerForGroupV2Creation(
                    ownedCryptoId: currentOwnedCryptoId,
                    creationMode: .fromScratch,
                    presentingViewController: self,
                    navigation: self,
                    uiKitDelegateForSwiftUISheet: self)
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .cancel))
            
            if let presentedViewController = self.presentedViewController {
                presentedViewController.present(alert, animated: true)
            } else {
                self.present(alert, animated: true)
            }

        } else {
            
            // Starting with version 0.12.0, we only allow the creation of groups v2.
            // The group creation flow was completely refactored in version 2.4
            // 2025-04-21: the group creation flow was re-coded from scratch.
            routerForGroupV2Creation.presentInitialViewControllerForGroupV2Creation(
                ownedCryptoId: currentOwnedCryptoId,
                creationMode: .fromScratch,
                presentingViewController: self,
                navigation: self,
                uiKitDelegateForSwiftUISheet: self)

        }
    }
    
    
    func userWantsToCloneGroup(_ flowController: ObvFlowController, valuesOfGroupToClone: ObvGroupV2CreationRouter.ValuesOfClonedGroup) async throws {
        assert(Thread.isMainThread)
        routerForGroupV2Creation.presentInitialViewControllerForGroupV2Creation(
            ownedCryptoId: currentOwnedCryptoId,
            creationMode: .cloneExistingGroup(valuesOfGroupToClone: valuesOfGroupToClone),
            presentingViewController: self,
            navigation: self,
            uiKitDelegateForSwiftUISheet: self)
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
        let fullDisplayName: String
        let ownedIdentityIsManagedByKeycloak: Bool
        do {
            (fullDisplayName, ownedIdentityIsManagedByKeycloak) = try PersistedObvOwnedIdentity.getFullDisplayNameAndIsKeycloakManaged(ownedCryptoId: self.currentOwnedCryptoId, within: ObvStack.shared.viewContext)
        } catch {
            return
        }
        let ownedURLIdentity = ObvURLIdentity(cryptoId: currentOwnedCryptoId, fullDisplayName: fullDisplayName)
        let vc = InvitationFlowHostingController(
            ownedURLIdentity: ownedURLIdentity,
            ownedIdentityIsManagedByKeycloak: ownedIdentityIsManagedByKeycloak,
            routerMode: .scanner,
            invitationFlowHostingControllerDataSources: dataSources.invitationFlowHostingControllerDataSources,
            actions: self,
            navigation: self)
        dismiss(animated: true) {
            self.present(vc, animated: true)
        }
    }
    
    
    func userWantsToUpdateTrustedIdentityDetailsOfContactIdentity(_ flowController: ObvFlowController, contactIdentifier: ObvContactIdentifier, using newContactIdentityDetails: ObvIdentityDetails) async throws {
        let obvEngine = self.obvEngine
        do {
            try await obvEngine.updateTrustedIdentityDetailsOfContactIdentity(contactIdentifier: contactIdentifier, with: newContactIdentityDetails)
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


    func userAskedToRefreshDiscussions() async throws {
        // Request the download of all messages to the engine
        try await obvEngine.downloadAllMessagesForOwnedIdentities()
        // If one of the owned identities is keycloak managed, resync
        do {
            if try await atLeastOneOwnedIdentityIsKeycloakManaged() {
                try await KeycloakManagerSingleton.shared.syncAllManagedIdentities()
            }
        } catch {
            assertionFailure(error.localizedDescription)
        }
    }

    
    private func atLeastOneOwnedIdentityIsKeycloakManaged() async throws -> Bool {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    let ownedIdentities = try PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: context)
                    let result = ownedIdentities.first(where: { $0.isKeycloakManaged }) != nil
                    return continuation.resume(returning: result)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
    }

    
    /// Helper enum used in ``userWantsToInviteContactsToOneToOne(ownedCryptoId:users:)``
    private enum OneToOneInvitationKind {
        case oneToOneInvitationProtocol(ownedCryptoId: ObvCryptoId, userCryptoId: ObvCryptoId)
        case keycloak(ownedCryptoId: ObvCryptoId, userCryptoId: ObvCryptoId, userIdOrSignedDetails: KeycloakAddContactInfo)
    }

    
    func userWantsToInviteContactsToOneToOne(_ flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)]) async throws {
        try await self.userWantsToInviteContactsToOneToOne(ownedCryptoId: ownedCryptoId, users: users)
    }
    
    
    /// Central method to call to invite a contact to be one2one. In most cases, this only triggers a `OneToOneContactInvitationProtocol`. In the case the owned identity is keycloak managed by the same server as the contact, this *also* triggers a Keycloak invitation.
    private func userWantsToInviteContactsToOneToOne(ownedCryptoId: ObvCryptoId, users: [(cryptoId: ObvCryptoId, keycloakDetails: ObvKeycloakUserDetails?)]) async throws {

        guard !users.isEmpty else { assertionFailure(); return }
        
        let invitationsToSend = try await computeListOfOneToOneInvitationsToSend(ownedCryptoId: ownedCryptoId, users: users)
        
        guard !invitationsToSend.isEmpty else { return }
        
        for invitationToSend in invitationsToSend {
            
            switch invitationToSend {

            case .oneToOneInvitationProtocol(ownedCryptoId: let ownedCryptoId, userCryptoId: let userCryptoId):
                
                do {
                    try await obvEngine.sendOneToOneInvitation(ownedIdentity: ownedCryptoId, contactIdentity: userCryptoId)
                } catch {
                    assertionFailure(error.localizedDescription)
                    if users.count == 1 {
                        throw error
                    } else {
                        continue // In production, do not fail the whole process because something went wrong for one invitation
                    }
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
                            
                            // Make sure no invitation exists for this contact: we don't want to spam the user
                            let oneToOneInvitationPreviouslySent = try PersistedInvitationOneToOneInvitationSent.get(fromOwnedIdentity: ownedCryptoId, toContact: user.cryptoId, within: context)
                            guard oneToOneInvitationPreviouslySent == nil else { continue }
                            
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
    
    private func userWantsToRemoveOneToOneInvitationSent(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws {
        let log = self.log
        let obvEngine = self.obvEngine
        let dialog = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvDialog?, any Error>) in
            ObvStack.shared.performBackgroundTask { context in
                do {
                    guard let oneToOneInvitationSent = try PersistedInvitationOneToOneInvitationSent.get(fromOwnedIdentity: ownedCryptoId,
                                                                                                         toContact: contactCryptoId,
                                                                                                         within: context) else {
                        assertionFailure()
                        return continuation.resume(returning: nil)
                    }
                    let dialog = oneToOneInvitationSent.obvDialog
                    return continuation.resume(returning: dialog)
                } catch {
                    os_log("Could not cancel OneToOne invitation: %{public}@", log: log, type: .fault, error.localizedDescription)
                    return continuation.resume(throwing: error)
                }
            }
        }
        guard var dialog else { return }
        try dialog.cancelOneToOneInvitationSent()
        let dialogForEngine = dialog
        try await obvEngine.respondTo(dialogForEngine)
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

    func userHasSeenPublishedDetails(_ flowController: ObvFlowController, publishedDetails: PublishedDetailsValidationViewModel) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userHasSeenPublishedDetails(self, publishedDetails: publishedDetails)
    }
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ flowController: ObvFlowController, groupIdentifier: ObvGroupV1Identifier) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsToReplaceTrustedDetailsByPublishedDetails(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ flowController: ObvFlowController, groupIdentifier: ObvGroupV2Identifier) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsToReplaceTrustedDetailsByPublishedDetails(self, groupIdentifier: groupIdentifier)
    }
 
    
    func userWantsToLeaveGroup(_ flowController: ObvFlowController, groupIdentifier: ObvGroupIdentifier) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsToLeaveGroup(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToDisbandGroup(_ flowController: ObvFlowController, groupIdentifier: ObvGroupIdentifier) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsToDisbandGroup(self, groupIdentifier: groupIdentifier)
    }
    
    
    func userWantsToSelectAndCallContacts(flowController: ObvFlowController, ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, groupId: GroupIdentifier?) {
        self.processUserWantsToSelectAndCallContacts(ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, groupId: groupId)
    }
    
    func userWantsObtainAvatar(_ flowController: ObvFlowController, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsObtainAvatar(self, avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
}


// MARK: - Implementing InvitationFlowRouterNavigation

extension MainFlowViewController: InvitationFlowRouterNavigation {
    
    func userDidPressOnObvGroupCellView(_ view: ObvCells.ObvGroupCellView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier, expectedNavigation: ObvCells.ObvGroupCellView.ExpectedNavigation) throws {
        
        assert(Thread.isMainThread)
        
        guard let displayedContactGroup = try DisplayedContactGroup.getDisplayedContactGroup(groupIdentifier: groupIdentifier, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            throw ObvError.couldNotFindDisplayedContactGroup
        }

        switch expectedNavigation {
            
        case .groupDiscussion:
            
            guard let discussionIdentifier = displayedContactGroup.discussionIdentifier else { assertionFailure(); return }
            let deepLink = ObvDeepLink.singleDiscussion(discussionIdentifier: discussionIdentifier)
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
                .postOnDispatchQueue()
            
        case .groupDetails:
            
            // For now, this case cannot occur in practice
            assertionFailure()

        }
    }
    
}

// MARK: - Implementing GroupV1CreationNavigationStackNavigation

extension MainFlowViewController: GroupV1CreationNavigationStackNavigation {
    
    func presentedGroupCreationFlowShouldBeDismissed(_ view: ObvUIGroupV1.GroupV1CreationNavigationStack) {
        self.presentedViewController?.dismiss(animated: true)
    }
    
}

// MARK: - Implementing GroupCreationNavigationStackNavigation

extension MainFlowViewController: GroupCreationNavigationStackNavigation {
    
    func presentedGroupCreationFlowShouldBeDismissed(_ view: ObvUIGroupV2.GroupV2CreationNavigationStack) {
        self.presentedViewController?.dismiss(animated: true)
    }
    
}

// MARK: - Implementing GroupV1CreationNavigationStackActions

extension MainFlowViewController: GroupV1CreationNavigationStackActions {
    
    func userWantsObtainAvatarDuringGroupV1Creation(_ view: ObvUIGroupV1.GroupV1CreationNavigationStack, avatarSource: ObvAppTypes.ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsObtainAvatar(self, avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    func userWantsToSaveImageToTempFileDuringGroupV1Creation(_ view: ObvUIGroupV1.GroupV1CreationNavigationStack, image: UIImage) async throws -> URL {
        try await self.userWantsToSaveImageToTempFile(image: image)
    }
    
    func userWantsToPublishCreatedGroupV1(_ view: ObvUIGroupV1.GroupV1CreationNavigationStack, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails, otherGroupMembers: Set<ObvTypes.ObvCryptoId>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToPublishGroupV1Creation(self, ownedCryptoId: ownedCryptoId, groupDetails: groupDetails, otherGroupMembers: otherGroupMembers)
    }
    
}


// MARK: - Implementing GroupCreationNavigationStackActions

extension MainFlowViewController: GroupV2CreationNavigationStackActions {
    
    func userWantsObtainAvatarDuringGroupCreation(_ view: ObvUIGroupV2.GroupV2CreationNavigationStack, avatarSource: ObvAppTypes.ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsObtainAvatar(self, avatarSource: avatarSource, avatarSize: avatarSize)
    }
    
    func userWantsToSaveImageToTempFileDuringGroupCreation(_ view: ObvUIGroupV2.GroupV2CreationNavigationStack, image: UIImage) async throws -> URL {
        try await self.userWantsToSaveImageToTempFile(image: image)
    }
    
    func userWantsToPublishCreatedGroupV2(_ view: ObvUIGroupV2.GroupV2CreationNavigationStack, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails, groupType: ObvAppTypes.ObvGroupType, otherGroupMembers: Set<ObvTypes.ObvGroupV2.IdentityAndPermissions>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        
        let groupCoreDetails = GroupV2CoreDetails(groupName: groupDetails.coreDetails.name,
                                                  groupDescription: groupDetails.coreDetails.description)
        
        let ownPermissions: Set<ObvGroupV2.Permission> = ObvGroupType.exactPermissions(of: .admin, forGroupType: groupType)
        
        try await mainFlowViewControllerDelegate.userWantsToPublishGroupV2Creation(
            self,
            groupCoreDetails: groupCoreDetails,
            ownPermissions: ownPermissions,
            otherGroupMembers: otherGroupMembers,
            ownedCryptoId: ownedCryptoId,
            photoURL: groupDetails.photoURL,
            groupType: groupType)
    }
    
}


// MARK: - Implementing ObvExternalInvitationHandlerViewActions

extension MainFlowViewController: ObvExternalInvitationHandlerViewActions {
    
    func userWantsToStartTrustEstablishmentProtocolOfRemoteIdentity(_ view: ObvInvitationFlow.ExternalInvitationHandlerView, ownedCryptoId: ObvTypes.ObvCryptoId, remoteURLIdentity: ObvTypes.ObvURLIdentity) {
        Task {
            await sendInvite(to: remoteURLIdentity.cryptoId, withFullDisplayName: remoteURLIdentity.fullDisplayName, for: ownedCryptoId)
        }
    }
    
}


// MARK: - Implementing ObvScannerViewActions

extension MainFlowViewController: ObvInvitationFlow.ObvScannerViewActions {
    
    func userScannedOrPastedAnOlvidURL(_ view: NewScannerView, scannedOlvidURL: OlvidURL) -> (remoteURLIdentity: ObvURLIdentity, mutualScanURLToShow: ObvMutualScanUrl)? {
        return userScannedOrPastedAnOlvidURL(olvidURL: scannedOlvidURL)
    }
    
    func userWantsToStartTrustEstablishmentProtocolOfRemoteIdentity(_ view: ObvInvitationFlow.NewScannerView, ownedCryptoId: ObvTypes.ObvCryptoId, remoteURLIdentity: ObvTypes.ObvURLIdentity) {
        Task {
            await sendInvite(to: remoteURLIdentity.cryptoId, withFullDisplayName: remoteURLIdentity.fullDisplayName, for: ownedCryptoId)
        }
    }
    
}


// MARK: - Implementing ObvCopyPasteMenuActions

extension MainFlowViewController: ObvInvitationFlow.ObvCopyPasteMenuActions {
    
    func userWantsToPasteOlvidURLFromClipboard(_ view: CopyPasteMenu, ownedCryptoId: ObvCryptoId) throws -> OlvidURL {
        guard let pastedText = UIPasteboard.general.string else {
            throw ObvError.couldNotPasteStringFromPasteboard
        }
        // Find all the URLs within the pasted text. The first one "wins".
        let urls = pastedText.extractURLs()
        guard let olvidURL = urls.compactMap({ OlvidURL(urlRepresentation: $0) }).first else {
            throw ObvError.couldNotFindAnyOlvidURLInPastedText
        }
        return olvidURL
    }
    

    func userWantsToCopyOwnedIdentityToClipboard(_ view: CopyPasteMenu, ownedCryptoId: ObvCryptoId) throws {
        let obvOwnedIdentity = try obvEngine.getOwnedIdentity(with: ownedCryptoId)
        let genericIdentity = obvOwnedIdentity.getGenericIdentity()
        let urlIdentityRepresentation = genericIdentity.getObvURLIdentity().urlRepresentation(for: .sharing)
        UIPasteboard.general.string = urlIdentityRepresentation.absoluteString
    }
    
}


// MARK: - Implementing ObvScanValidationViewActions

extension MainFlowViewController: ObvInvitationFlow.ObvScanValidationViewActions {
    
    func userWantsToNavigateToOneToOneDiscussion(_ view: ScanValidationView, obvContactIdentifier: ObvContactIdentifier) {
        userWantsToDiscussWith(contactIdentifier: obvContactIdentifier)
    }
    
}

// MARK: - Implementing ObvContactInvitationViewAction

extension MainFlowViewController: ObvInvitationFlow.ObvContactInvitationViewAction {
        
    func userWantsToInviteContactsToOneToOne(_ view: ObvInvitationFlow.ContactInvitationView, ownedCryptoId: ObvTypes.ObvCryptoId, users: [(cryptoId: ObvTypes.ObvCryptoId, keycloakDetails: ObvTypes.ObvKeycloakUserDetails?)]) async throws {
        try await self.userWantsToInviteContactsToOneToOne(ownedCryptoId: ownedCryptoId, users: users)
    }
    
    func userWantsToDiscussWith(_ view: ObvInvitationFlow.ContactInvitationView, obvContactIdentifier: ObvTypes.ObvContactIdentifier) {
        userWantsToDiscussWith(contactIdentifier: obvContactIdentifier)
    }
    
    func userWantsToRemoveOneToOneInvitationSent(_ view: ObvInvitationFlow.ContactInvitationView, contactIdentifier: ObvTypes.ObvContactIdentifier) async throws {
        try await userWantsToRemoveOneToOneInvitationSent(ownedCryptoId: contactIdentifier.ownedCryptoId, contactCryptoId: contactIdentifier.contactCryptoId)
    }

    private func userWantsToDiscussWith(contactIdentifier: ObvTypes.ObvContactIdentifier) {
        guard let oneToOneDiscussion = try? PersistedOneToOneDiscussion.getPersistedDiscussionOneToOne(contactId: contactIdentifier, within: ObvStack.shared.viewContext) else { return }
        guard oneToOneDiscussion.contactIdentity?.cryptoId == contactIdentifier.contactCryptoId else { return }
        guard let discussionIdentifier = try? oneToOneDiscussion.discussionIdentifier else { assertionFailure(); return }
        let deepLink = ObvDeepLink.singleDiscussion(discussionIdentifier: discussionIdentifier)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink).postOnDispatchQueue()
    }
    
}


// MARK: - Implementing

extension MainFlowViewController: ObvInvitationFlow.ListOfContactsAndGroupsViewActions {
    
    func userWantsToDismissInvitationFlow(_ view: ObvInvitationFlow.ListOfContactsAndGroupsView) {
        self.presentedViewController?.dismiss(animated: true)
    }
    
    
    func userWantsToPerformKeycloakAuthentication(_ view: ObvInvitationFlow.ListOfContactsAndGroupsView.ListOfDirectoryContactsView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws(ListOfContactsAndGroupsView.ListOfDirectoryContactsView.KeycloakError) {
        do {
            try await KeycloakManagerSingleton.shared.synchronizeOwnedIdentityWithKeycloakServer(ownedCryptoId: ownedCryptoId, ignoreSynchronizationInterval: true)
        } catch {
            switch error {
            case .userHasCancelled:
                throw .userHasCancelled
            }
        }
    }
    
    
    func userPastedAnOlvidURL(_ view: ListOfContactsAndGroupsView, scannedOlvidURL: OlvidURL) -> (remoteURLIdentity: ObvURLIdentity, mutualScanURLToShow: ObvMutualScanUrl)? {
        return userScannedOrPastedAnOlvidURL(olvidURL: scannedOlvidURL)
    }
    
    /// Handles a scanned or pasted `OlvidURL` in the `ObvInvitationFlow`.
    ///
    /// This method processes the URL based on its category:
    /// - For `.invitation` URLs, computes and returns an `ObvMutualScanUrl` to enable the second scan in a double-scan invitation flow.
    /// - For all other categories (e.g., Keycloak configuration), returns `nil` and delegates routing to the `NewAppStateManager`.
    ///
    /// - Note:
    ///   The URL can be scanned or pasted via the QR scanner or pasted from the contacts list.
    ///
    /// - Returns:
    ///   An `ObvMutualScanUrl` if the URL is an invitation, otherwise `nil`.
    private func userScannedOrPastedAnOlvidURL(olvidURL: OlvidURL) -> (remoteURLIdentity: ObvURLIdentity, mutualScanURLToShow: ObvMutualScanUrl)? {
        switch olvidURL.category {
        case .invitation(urlIdentity: let remoteURLIdentity):
            guard let mutualScanUrl = try? obvEngine.computeMutualScanUrl(remoteIdentity: remoteURLIdentity.cryptoId.getIdentity(), ownedCryptoId: self.currentOwnedCryptoId) else { assertionFailure(); return nil }
            return (remoteURLIdentity, mutualScanUrl)
        default:
            Task {
                await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
                await NewAppStateManager.shared.routeOlvidURL(olvidURL)
            }
            return nil
        }
    }
    
    func userWantsToCreateGroup(_ view: ListOfContactsAndGroupsView.InvitationsContactsListContentView, ownedCryptoId: ObvCryptoId) {
        let deepLink = ObvDeepLink.groupCreation
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink).postOnDispatchQueue()
    }
    
    
    func persistedObvContactIdentityTapped(_ view: ListOfContactsAndGroupsView.ListOfContactsCellForKeyView, currentCryptoId: ObvCryptoId, with objectID: NSManagedObjectID) async -> InvitationContactsListNavigationType {
        return await persistedObvContactIdentityTapped(currentCryptoId: currentCryptoId, with: objectID)
    }
    
    
    private func persistedObvContactIdentityTapped(currentCryptoId: ObvCryptoId, with objectID: NSManagedObjectID) async -> InvitationContactsListNavigationType {
        guard let persistedContactIdentity = try? PersistedObvContactIdentity.get(objectID: objectID, within: ObvStack.shared.viewContext) else { return .none }
        let obvContactIdentifier = ObvContactIdentifier(contactCryptoId: persistedContactIdentity.cryptoId, ownedCryptoId: currentCryptoId)
        if persistedContactIdentity.isOneToOne {
            let deeplink = ObvDeepLink.singleDiscussion(discussionIdentifier: .oneToOne(id: obvContactIdentifier))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deeplink).postOnDispatchQueue()
        } else {
            return .showInvitation(obvContactIdentifier: obvContactIdentifier, keycloakUserDetails: nil)
        }
        return .none
    }
    
    
    func keycloakContactIdentifierTapped(_ view: ListOfContactsAndGroupsView.ListOfContactsCellForKeyView, currentCryptoId: ObvCryptoId, with keycloakUserDetails: ObvKeycloakUserDetails) async -> InvitationContactsListNavigationType {
        guard let identity = keycloakUserDetails.identity, let contactCryptoId = try? ObvCryptoId(identity: identity) else { return .none }
        let obvContactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: currentCryptoId)
        if let persistedContactIdentity = try? PersistedObvContactIdentity.get(contactCryptoId: contactCryptoId, ownedIdentityCryptoId: currentCryptoId, whereOneToOneStatusIs: .oneToOne, within: ObvStack.shared.viewContext) {
            return await persistedObvContactIdentityTapped(currentCryptoId: currentCryptoId, with: persistedContactIdentity.objectID)
        } else {
            return .showInvitation(obvContactIdentifier: obvContactIdentifier,
                                   keycloakUserDetails: keycloakUserDetails)
        }
    }
    
    
}


// MARK: - Unlocking hidden profile

extension MainFlowViewController {
    
    private func showAlertForUnlockingHiddenOwnedIdentity() {
        let alert = UIAlertController(title: String(localized: "OPEN_HIDDEN_PROFILE_ALERT_TITLE"),
                                      message: String(localized: "OPEN_HIDDEN_PROFILE_ALERT_MESSAGE"),
                                      preferredStyle: .alert)
        alert.addTextField { textField in
            textField.passwordRules = UITextInputPasswordRules(descriptor: "minlength: \(ObvAppCoreConstants.minimumLengthOfPasswordForHiddenProfiles);")
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
        guard let currentText = textField.text, currentText.count >= ObvAppCoreConstants.minimumLengthOfPasswordForHiddenProfiles else { return }
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
        
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo { ownedCryptoId, contactCryptoIds, groupId, startCallIntent in
            Task { [weak self] in await self?.processUserWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, groupId: groupId, startCallIntent: startCallIntent) }
        })
        
    }
    
    
    @MainActor
    private func processUserWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, groupId: GroupIdentifier?, startCallIntent: INStartCallIntent?) async {
        assert(Thread.isMainThread)
        
        // Check access to the microphone
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                if granted {
                    Task { [weak self] in
                        await self?.processUserWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, groupId: groupId, startCallIntent: startCallIntent)
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
                ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityAndIsAllowedTo(
                    ownedCryptoId: ownedCryptoId,
                    contactCryptoIds: contactCryptoIds,
                    ownedIdentityForRequestingTurnCredentials: ownedIdentityForRequestingTurnCredentials,
                    groupId: groupId,
                    startCallIntent: startCallIntent)
                .postOnDispatchQueue()
            }
        } else {
            let vc = UserTriesToAccessPaidFeatureHostingController(
                requestedPermission: .canCall,
                ownedCryptoId: ownedIdentity.cryptoId,
                actions: actions,
                navigation: self)
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            self.present(vc, animated: true)
        }
    }
    
    
    private func observeUserWantsToSelectAndCallContactsNotifications() {
        observationTokens.append(ObvMessengerInternalNotification.observeUserWantsToSelectAndCallContacts { ownedCryptoId, contactCryptoIds, groupId in
            Task { [weak self] in self?.processUserWantsToSelectAndCallContacts(ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, groupId: groupId) }
        })
    }
    

    @MainActor
    private func processUserWantsToSelectAndCallContacts(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, groupId: GroupIdentifier?) {
        guard !contactCryptoIds.isEmpty else { return }
        
        let persistedContacts = contactCryptoIds
            .compactMap { try? PersistedObvContactIdentity.get(contactCryptoId: $0, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) }
            .filter { !$0.devices.isEmpty }
        
        guard !persistedContacts.isEmpty else { return }
        
        let verticalConfiguration = VerticalUsersViewConfiguration(
            showExplanation: false,
            disableUsersWithoutDevice: true,
            allowMultipleSelection: true,
            textAboveUserList: nil,
            selectionStyle: .checkmark)
        let horizontalConfiguration = HorizontalUsersViewConfiguration(
            textOnEmptySetOfUsers: Strings.selectTheContactsToCall,
            canEditUsers: true)
        let buttonConfiguration = HorizontalAndVerticalUsersViewButtonConfiguration(
            title: CommonString.Word.Call,
            systemIcon: .phoneFill,
            action: { [weak self] selectedContactCryptoIs in
                ObvMessengerInternalNotification.userWantsToCallOrUpdateCallCapabilityButWeShouldCheckSheIsAllowedTo(ownedCryptoId: ownedCryptoId, contactCryptoIds: Set(selectedContactCryptoIs), groupId: groupId, startCallIntent: nil)
                    .postOnDispatchQueue()
                self?.dismiss(animated: true)
            },
            allowEmptySetOfContacts: false)
        let configuration = HorizontalAndVerticalUsersViewConfiguration(
            verticalConfiguration: verticalConfiguration,
            horizontalConfiguration: horizontalConfiguration,
            buttonConfiguration: buttonConfiguration)

        let vc = MultipleUsersHostingViewController(
            ownedCryptoId: ownedCryptoId,
            mode: .restricted(to: contactCryptoIds, oneToOneStatus: .any),
            configuration: configuration,
            delegate: nil)
        
        vc.title = CommonString.Word.Call

        let nav = ObvNavigationController(rootViewController: vc)
        
        vc.navigationItem.searchController = vc.searchController
        vc.navigationItem.hidesSearchBarWhenScrolling = false

        vc.navigationItem.rightBarButtonItem = .init(systemItem: .cancel, primaryAction: .init(handler: { [weak self] _ in
            guard let self else { return }
            presentedViewController?.dismiss(animated: true)
        }))
        
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
    
    
    /// Returns the `ObvFlowController` corresponding to the requested `flow`, depending on whether
    /// this `UISplitViewController` is currently collapsed or expanded.
    private func flowControllerForFlow(_ flow: ObvFlow) -> ObvFlowController {
        if self.isCollapsed {
            return self.allFlowControllersForUITabBarController.flowControllerForFlow(flow)
        } else {
            return self.allFlowControllersForUISplitViewController.flowControllerForFlow(flow)
        }
    }
    

    /// This method shall only be called from the MetaFlowController. The reason we do not listen to notifications in this class is that it is
    /// initialized late in the app initialization process and thus, we could miss deep link navigation notifications sent earlier.
    @MainActor
    func performCurrentDeepLinkInitialNavigation(deepLink: ObvDeepLink) async {

        Self.logger.info("🥏 Performing deep link initial navigation to \(deepLink.description, privacy: .public)")
        
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
            Self.logger.info("🥏 The current deep link is a myId")
            await presentedViewController?.dismissAndAwaitCompletion(animated: true)
            let vc = ObvSingleOwnedIdentityViewStackViewController(
                ownedCryptoId: ownedCryptoId,
                dataSources: self.dataSources.singleOwnedIdentityViewStackDataSources,
                actions: self,
                navigation: self,
                uiKitDelegateForSwiftUISheet: self)
            
            present(vc, animated: true)
            
        case .latestDiscussions(ownedCryptoId: let ownedCryptoId):
            if let ownedCryptoId {
                await switchCurrentOwnedCryptoId(to: ownedCryptoId)
            }
            switchToFlow(.latestDiscussions)
            presentedViewController?.dismiss(animated: true)
            
        case .allGroups(ownedCryptoId: let ownedCryptoId):
            await switchCurrentOwnedCryptoId(to: ownedCryptoId)
            switchToFlow(.groups)
            presentedViewController?.dismiss(animated: true)

        case .qrCodeScan:
            Self.logger.info("🥏 The current deep link is a qrCodeScan")
            // We do not need to navigate anywhere. We just show the QR code scanner.
            presentedViewController?.dismiss(animated: true)
            checkAuthorizationStatusThenSetupAndPresentQRCodeScanner()

        case .singleDiscussion(discussionIdentifier: let discussionIdentifier):
            await switchCurrentOwnedCryptoId(to: discussionIdentifier.ownedCryptoId)
            switchToFlow(.latestDiscussions)
            presentedViewController?.dismiss(animated: true)
            guard let discussion = try? PersistedDiscussion.getPersistedDiscussion(discussionIdentifier: discussionIdentifier, within: ObvStack.shared.viewContext) else { return }
            let discussionFlow = flowControllerForFlow(.latestDiscussions)
            discussionFlow.userWantsToDisplay(persistedDiscussion: discussion)

        case .invitations(ownedCryptoId: let ownedCryptoId):
            await presentedViewController?.dismissAndAwaitCompletion(animated: true)
            await switchCurrentOwnedCryptoId(to: ownedCryptoId)
            switchToFlow(.invitations)
            presentedViewController?.dismiss(animated: true)
            
        case .groupV1Details(ownedCryptoId: let ownedCryptoId, objectPermanentID: let displayedContactGroupPermanentID):
            await switchCurrentOwnedCryptoId(to: ownedCryptoId)
            let groupsFlow: ObvFlowController = self.flowControllerForFlow(.groups)
            groupsFlow.popToRootViewController(animated: false)
            switchToFlow(.groups)
            await presentedViewController?.dismissAndAwaitCompletion(animated: true)
            guard let displayedContactGroup = try? DisplayedContactGroup.getManagedObject(withPermanentID: displayedContactGroupPermanentID, within: ObvStack.shared.viewContext) else { return }
            if let groupsListVC = groupsFlow.topViewController as? ObvGroupsListViewController {
                groupsListVC.scrollToItem(.objectIDOfDisplayedContactGroup(displayedContactGroup.objectID))
            }
            try? await Task.sleep(seconds: 1.3) // Time required for the scroll + chevron animation
            groupsFlow.userWantsToNavigateToSingleGroupView(displayedContactGroup, within: groupsFlow)
            
        case .groupV2Details(groupIdentifier: let groupIdentifier):
            await switchCurrentOwnedCryptoId(to: groupIdentifier.ownedCryptoId)
            let groupsFlow: ObvFlowController = self.flowControllerForFlow(.groups)
            _ = groupsFlow.popToRootViewController(animated: false)
            switchToFlow(.groups)
            await presentedViewController?.dismissAndAwaitCompletion(animated: true)
            guard let persistedGroupV2 = try? PersistedGroupV2.get(ownIdentity: groupIdentifier.ownedCryptoId, appGroupIdentifier: groupIdentifier.identifier.appGroupIdentifier, within: ObvStack.shared.viewContext) else { return }
            guard let displayedContactGroup = persistedGroupV2.displayedContactGroup else { return }
            if let groupsListVC = groupsFlow.topViewController as? ObvGroupsListViewController {
                groupsListVC.scrollToItem(.objectIDOfDisplayedContactGroup(displayedContactGroup.objectID))
            }
            try? await Task.sleep(seconds: 1.3) // Time required for the scroll + chevron animation
            groupsFlow.userWantsToNavigateToSingleGroupView(displayedContactGroup, within: groupsFlow)
            
        case .contactIdentityDetails(contactIdentifier: let contactIdentifier):
            await switchCurrentOwnedCryptoId(to: contactIdentifier.ownedCryptoId)
            let contactFlow = self.flowControllerForFlow(.contacts)
            _ = contactFlow.popToRootViewController(animated: false)
            switchToFlow(.contacts)
            await presentedViewController?.dismissAndAwaitCompletion(animated: true)
            guard let contactIdentity = try? PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) else { return }
            try? await Task.sleep(milliseconds: 300)
            if let allContactsViewController = contactFlow.topViewController as? AllContactsViewController {
                allContactsViewController.selectRowOfContactIdentity(contactIdentity)
            }
            try? await Task.sleep(milliseconds: 300)
            contactFlow.userWantsToNavigateToSingleContactView(contactIdentifier: contactIdentifier)
            
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
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            presentSettingsFlowViewController()
            
        case .backupSettings:
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            presentSettingsFlowViewController(specificSetting: .backup)
            
        case .voipSettings:
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            presentSettingsFlowViewController(specificSetting: .voip)

        case .privacySettings:
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            presentSettingsFlowViewController(specificSetting: .privacy)
            
        case .discussionsSettings:
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            presentSettingsFlowViewController(specificSetting: .discussions)

        case .interfaceSettings:
            await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
            presentSettingsFlowViewController(specificSetting: .interface)

        case .storageManagementSettings:
            assert(Thread.isMainThread)
            if #available(iOS 17.0, *) {
                await self.presentedViewController?.dismissAndAwaitCompletion(animated: true)
                presentStorageManagementViewController()
            }
            
        case .message(let messageAppIdentifier):
            switchToFlow(.latestDiscussions)
            await presentedViewController?.dismissAndAwaitCompletion(animated: true)
            guard let message = try? PersistedMessage.getMessage(messageAppIdentifier: messageAppIdentifier, within: ObvStack.shared.viewContext) else {
                // If we can't find the message, we try to navigate to the discussion
                await performCurrentDeepLinkInitialNavigation(deepLink: .singleDiscussion(discussionIdentifier: messageAppIdentifier.discussionIdentifier))
                return
            }
            let discussionFlow = self.flowControllerForFlow(.latestDiscussions)
            discussionFlow.userWantsToDisplay(persistedMessage: message)
            
        case .olvidCallView:
            VoIPNotification.showCallView
                .postOnDispatchQueue()
            
        case .groupCreation:
            userWantsToAddContactGroup(ownedCryptoId: currentOwnedCryptoId)
            
        case .webRTCHistoryTransferConfirmation(sourceDeviceIdentifier: let sourceDeviceIdentifier, transferId: let transferId):
            await self.presentProgressHistoryImportHostingView(sourceDeviceIdentifier: sourceDeviceIdentifier, transferId: transferId)
            
        }
        
    }
    
    
    private func presentProgressHistoryImportHostingView(sourceDeviceIdentifier: ObvOwnedDeviceIdentifier, transferId: String) async {
        while let presentedViewController = self.presentedViewController {
            await presentedViewController.dismissAndAwaitCompletion(animated: true)
        }
        do {
            let sourceDeviceName = try await Self.getNameOfPersistedObvOwnedDevice(ownedDeviceIdentifier: sourceDeviceIdentifier)
            let vc = ProgressImportHostingView(
                sourceDeviceName: sourceDeviceName,
                sourceDeviceIdentifier: sourceDeviceIdentifier,
                transferIdFromSource: transferId,
                actions: self)
            self.present(vc, animated: true)
        } catch {
            Self.logger.fault("Could not present view: \(error.localizedDescription)")
        }
    }
    
    
    /// The designated method for updating the `.supplementary` column content of this `UISplitViewController`
    /// and changing the selected tab of the `UITabBarController`.
    ///
    /// This method ensures proper tracking of the current user activity within the app, which is critical for:
    /// - Highlighting the correct sidebar item in expanded environments (e.g., on Mac).
    /// - Maintaining a consistent user experience across different platforms and states.
    ///
    /// **Important:** Directly modifying the `.supplementary` column or `UITabBarController` outside of this method
    /// may result in incorrect user activity tracking and UI inconsistencies.
    fileprivate func switchToFlow(_ flow: ObvAppTypes.ObvFlow) {
        if self.isCollapsed {
            mainTabBarController.selectedObvTab = flow
        } else {
            self.setViewController(self.allFlowControllersForUISplitViewController.flowControllerForFlow(flow), for: .supplementary)
        }
        self.updateOlvidUserActivityFlow(to: flow)
    }

    
    fileprivate func updateOlvidUserActivityFlow(to newFlow: ObvAppTypes.ObvFlow) {
        OlvidUserActivitySingleton.shared.switchCurrentFlow(to: newFlow, currentOwnedCryptoId: self.currentOwnedCryptoId, viewController: self)
    }
    

    @MainActor
    private func addAttachmentFromFile(at fileURL: URL) {
        if let discussionVC = currentDiscussionViewControllerShownToUser() {
            // The user is currently within a discussion. We add the AirDrop'ed files within that discussion
            discussionVC.addAttachmentFromAirDropFile(at: fileURL)
        } else {
            // The user is not within a discussion. Go to the list of latest discussions and wait until a discussion is chosen
            // We save the file URL
            switchToFlow(.latestDiscussions)
            let discussionFlow = flowControllerForFlow(.latestDiscussions)
            _ = discussionFlow.children.first?.navigationController?.popViewController(animated: true)
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
        let vc = SettingsFlowViewController(ownedCryptoId: currentOwnedCryptoId,
                                            obvEngine: obvEngine,
                                            createPasscodeDelegate: createPasscodeDelegate,
                                            localAuthenticationDelegate: localAuthenticationDelegate,
                                            appBackupDelegate: appBackupDelegate,
                                            settingsFlowViewControllerDelegate: self,
                                            dataSources: dataSources.historyTransferNavigationStackDataSources)
        let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(dismissPresentedViewController))
        vc.viewControllers.first?.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(vc, animated: true)
    }

    @available(iOS 17.0, *)
    @MainActor
    private func presentStorageManagementViewController() {
        assert(Thread.isMainThread)
        let vc = StorageManagementHostingController(currentOwnedCryptoId: currentOwnedCryptoId)
        present(vc, animated: true)
    }
    

    @MainActor
    private func presentSettingsFlowViewController(specificSetting: AllSettingsTableViewController.Setting) {
        assert(Thread.isMainThread)
        guard let createPasscodeDelegate, let appBackupDelegate, let localAuthenticationDelegate else {
            assertionFailure(); return
        }
        let vc = SettingsFlowViewController(ownedCryptoId: currentOwnedCryptoId,
                                            obvEngine: obvEngine,
                                            createPasscodeDelegate: createPasscodeDelegate,
                                            localAuthenticationDelegate: localAuthenticationDelegate,
                                            appBackupDelegate: appBackupDelegate,
                                            settingsFlowViewControllerDelegate: self,
                                            dataSources: dataSources.historyTransferNavigationStackDataSources)
        let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(dismissPresentedViewController))
        vc.viewControllers.first?.navigationItem.setLeftBarButton(closeButton, animated: false)
        present(vc, animated: true) {
            Task {
                await vc.pushSetting(specificSetting, tableView: nil, didSelectRowAt: nil)
            }
        }
    }

    
    func getAndRemoveAirDroppedFileURLs() -> [URL] {
        let urls = airDroppedFileURLs
        airDroppedFileURLs.removeAll()
        return urls
    }
    
    
    private func currentDiscussionViewControllerShownToUser() -> SomeSingleDiscussionViewController? {
        guard let discussionVC = currentFlowController?.viewControllers.last as? SomeSingleDiscussionViewController else { return nil }
        guard discussionVC.viewIfLoaded?.window != nil else { assertionFailure(); return nil }
        return discussionVC
    }
    
}


// MARK: - Implementing LocalNetworkImportViewActions

extension MainFlowViewController: LocalNetworkImportViewActions {
        
    func userWantsToDismissView(_ view: ObvHistoryTransfer.LocalNetworkImportView) {
        (self.presentedViewController as? ProgressImportHostingView)?.dismiss(animated: true)
    }
    
    func userRequiresMessageHistoryTransferService(_ view: ObvHistoryTransfer.LocalNetworkImportView) async throws -> any ObvHistoryTransfer.TransferServiceForLocalNetworkImportView {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userRequiresMessageHistoryTransferService(self)
    }

}


// MARK: - Implementing UserTriesToAccessPaidFeatureViewNavigation

extension MainFlowViewController: UserTriesToAccessPaidFeatureViewNavigation {
    
    func userWantsToNavigateToTheMyProfilePage(_ view: ObvSubscription.UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvCryptoId) {
        let deepLink = ObvDeepLink.myId(ownedCryptoId: ownedCryptoId)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }
    
    func userTriesToAccessPaidFeatureViewShouldBeDismissed(_ view: ObvSubscription.UserTriesToAccessPaidFeatureView) {
        self.presentedViewController?.dismiss(animated: true)
    }
    
}


// MARK: - Implementing UIKitDelegateForSwiftUISheet

extension MainFlowViewController: UIKitDelegateForSwiftUISheet {
    
    func userWantsToPresentView<Content>(_ view: some View, content: @escaping () -> Content) async where Content : View {
        let hostingController = UIHostingController(rootView: content())
        await self.presentOnTopAndAwaitCompletion(hostingController, animated: true)
    }
    
    func userWantsToDismissPresentedView(_ view: some View) async {
        await self.dismissTopPresentedViewControllerAndAwaitCompletion(animated: true)
    }
    
}


// MARK: - OlvidURLHandler

extension MainFlowViewController {
    
    func handleOlvidURLOfTypeMutualScan(mutualScanURL: ObvMutualScanUrl) async throws {

        // The following call also check the signature of the `ObvMutualScanUrl`. This fails if the `currentOwnedCryptoId` is not
        // the appropriate one.
        try await obvEngine.startTrustEstablishmentWithMutualScanProtocol(ownedIdentity: self.currentOwnedCryptoId, mutualScanUrl: mutualScanURL)
        
        let contactIdentifier = ObvContactIdentifier(contactCryptoId: mutualScanURL.cryptoId, ownedCryptoId: self.currentOwnedCryptoId)
        let initalScanViewModel: ScanValidationViewModel
        if let existingContact = try PersistedObvContactIdentity.get(persisted: contactIdentifier, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext) {
            initalScanViewModel = try .init(persistedContactIdentity: existingContact)
        } else {
            initalScanViewModel = .init(contactStatus: .contactNotAddedYet,
                                        contactAvatarModel: .init(contactCryptoId: mutualScanURL.cryptoId, contactFullDisplayName: mutualScanURL.fullDisplayName),
                                        contactFullDisplayName: mutualScanURL.fullDisplayName,
                                        contactIdentifier: contactIdentifier)
        }
        
        let invitationFlowHostingController: InvitationFlowHostingController
        if let vc = self.presentedViewController as? InvitationFlowHostingController {
            // Typical case, the is already presented
            invitationFlowHostingController = vc
        } else {
            // This happens if the `mutualScanURL` is scanned from outside of the app (not frequent)
            let fullDisplayName: String
            let ownedIdentityIsManagedByKeycloak: Bool
            do {
                (fullDisplayName, ownedIdentityIsManagedByKeycloak) = try PersistedObvOwnedIdentity.getFullDisplayNameAndIsKeycloakManaged(ownedCryptoId: self.currentOwnedCryptoId, within: ObvStack.shared.viewContext)
            } catch {
                return
            }
            let ownedURLIdentity = ObvURLIdentity(cryptoId: currentOwnedCryptoId, fullDisplayName: fullDisplayName)
            let vc = InvitationFlowHostingController(
                ownedURLIdentity: ownedURLIdentity,
                ownedIdentityIsManagedByKeycloak: ownedIdentityIsManagedByKeycloak,
                routerMode: .listOfContactsAndGroups,
                invitationFlowHostingControllerDataSources: dataSources.invitationFlowHostingControllerDataSources,
                actions: self,
                navigation: self)
            await self.dismissAndAwaitCompletion(animated: true)
            self.present(vc, animated: true)
            invitationFlowHostingController = vc
            
        }
        
        invitationFlowHostingController.mutualScanURLWasHandled(initalScanViewModel: initalScanViewModel)
        
    }
    
    
    func handleExternalInvitation(remoteURLIdentity: ObvURLIdentity) async {
        
        guard let mutualScanUrl = try? obvEngine.computeMutualScanUrl(remoteIdentity: remoteURLIdentity.cryptoId.getIdentity(), ownedCryptoId: self.currentOwnedCryptoId) else { assertionFailure(); return }

        let invitationFlowHostingController: InvitationFlowHostingController
        
        if let _invitationFlowHostingController = self.presentedViewController as? InvitationFlowHostingController {
            invitationFlowHostingController = _invitationFlowHostingController
        } else {
            let fullDisplayName: String
            let ownedIdentityIsManagedByKeycloak: Bool
            do {
                (fullDisplayName, ownedIdentityIsManagedByKeycloak) = try PersistedObvOwnedIdentity.getFullDisplayNameAndIsKeycloakManaged(ownedCryptoId: self.currentOwnedCryptoId, within: ObvStack.shared.viewContext)
            } catch {
                return
            }
            let ownedURLIdentity = ObvURLIdentity(cryptoId: currentOwnedCryptoId, fullDisplayName: fullDisplayName)
            let vc = InvitationFlowHostingController(
                ownedURLIdentity: ownedURLIdentity,
                ownedIdentityIsManagedByKeycloak: ownedIdentityIsManagedByKeycloak,
                routerMode: .listOfContactsAndGroups,
                invitationFlowHostingControllerDataSources: dataSources.invitationFlowHostingControllerDataSources,
                actions: self,
                navigation: self)
            await self.dismissAndAwaitCompletion(animated: true)
            self.present(vc, animated: true)
            invitationFlowHostingController = vc
        }
        
        invitationFlowHostingController.handleExternalInvitation(mutualScanURLToShow: mutualScanUrl, remoteURLIdentity: remoteURLIdentity)

    }

}


// MARK: - QRCodeScannerViewControllerDelegate

extension MainFlowViewController: ObvScannerHostingViewDelegate {

    func qrCodeWasScanned(olvidURL: OlvidURL) {
        Task { await NewAppStateManager.shared.routeOlvidURL(olvidURL) }
    }
    
    
    func scannerViewActionButtonWasTapped() {
        presentedViewController?.dismiss(animated: true)
    }
    
    /// This method is typically called when an owned identity want to remotely invite a contact after scanning their "invitation" QR code.
    private func sendInvite(to remoteCryptoId: ObvCryptoId, withFullDisplayName fullDisplayName: String, for ownedCryptoId: ObvCryptoId) async {
        do {
            // Launch a trust establishment protocol with the contact
            try await obvEngine.startTrustEstablishmentProtocolOfRemoteIdentity(with: remoteCryptoId,
                                                                                withFullDisplayName: fullDisplayName,
                                                                                forOwnedIdentyWith: ownedCryptoId)
            // Switch to the Invitations tab
            DispatchQueue.main.async { [weak self] in
                self?.switchToFlow(.invitations)
                self?.dismiss(animated: true)
            }

            // Switch to the Invitations tab
            mainTabBarController.selectedObvTab = .invitations
            dismiss(animated: true)
            
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
        let url = genericIdentity.getObvURLIdentity().urlRepresentation(for: .sharing)
        return MainFlowViewController.Strings.ShareOwnedIdentity.body(displayName, url)
    }
    
    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        let url = genericIdentity.getObvURLIdentity().urlRepresentation(for: .sharing)
        if activityType == .airDrop {
            // This allows you to share the invitation URL via AirDrop or use Apple's nearby sharing feature to achieve the same result.
            // Once the link is received, the other phone will respond as if it had scanned the initial QR code: it will automatically navigate to
            // the second QR code. Despite our best efforts, this is the most effective solution we've managed to find (all tests involving
            // activityItemsConfiguration unfortunately yielded no success).
            return url
        } else {
            let displayName = genericIdentity.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.full)
            return MainFlowViewController.Strings.ShareOwnedIdentity.body(displayName, url)
        }
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
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "MainFlowViewControllerSplitDelegate")
    
    /// Manages consistency between highlighted tabs, sidebar items, the discussion stack, and the current user activity
    /// during transitions between `compact` and `expanded` modes of the `UISplitViewController`.
    ///
    /// - In `expanded` mode, the split view controller displays three columns (`.primary`, `.supplementary`, and `.secondary`).
    /// - In `compact` mode, it presents a `UITabBarController` (either `ObvSubTabBarControllerNew` or `ObvSubTabBarController`,
    ///   depending on the OS version).
    func splitViewController(
        _ svc: UISplitViewController,
        willHide column: UISplitViewController.Column
    ) {
        
        guard let svc = svc as? MainFlowViewController else { assertionFailure(); return }
       
        Self.logger.debug("Calling splitViewController(_:willHide:). Will hide column \(column.rawValue)")
        
        switch column {

        case .compact:

            // The compact column will hide, meaning the UISplitViewController will expand.
            
            assert(OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow != nil)
            
            // Determine the current flow of the user
            
            let currentFlow = OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow ?? .latestDiscussions
            
            // The `ObvSideBarView` has not yet appeared, so setting its highlighted item here would have no effect
            // (SwiftUI would not persist the change). The sidebar will request the current highlight state when it appears.

            // Migrate all the discussions found in the current flow of the UITabBarController to the navForDetailsView (which is the secondary
            // column of the UISplitViewController)
            
            let discussionVCsToMigrate: [SomeSingleDiscussionViewController] = svc.allFlowControllersForUITabBarController.getAllDiscussionsInFlow(currentFlow)
            svc.allFlowControllersForUITabBarController.flowControllerForFlow(currentFlow).popToRootViewController(animated: false)
            svc.navForDetailsView.setViewControllers([OlvidPlaceholderViewController()] + discussionVCsToMigrate, animated: false)
            
            // Make sure the supplementary (middle) column of the UISplitViewController displayes the correct (current) flow
            // This is do asynchronously to prevent a crash on certain devices (e.g., iPhone 14 Pro Max).
            // Calling `switchToFlow` ensure the current OlvidUserActivity is properly updated.

            DispatchQueue.main.async {
                svc.switchToFlow(currentFlow)
            }
            
        case .secondary:

            // The secondary column will hide, meaning the UISplitViewController will collapse to compact mode.

            assert(OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow != nil)

            // Determine the current flow of the user
            
            let currentFlow = OlvidUserActivitySingleton.shared.currentUserActivity?.currentFlow ?? .latestDiscussions
                        
            // Migrate all the discussions found in the navForDetailsView to the appropriate flow of the UITabBarController
                        
            let discussionVCsToMigrate: [SomeSingleDiscussionViewController] = svc.navForDetailsView.viewControllers.compactMap { $0 as? SomeSingleDiscussionViewController }
            svc.navForDetailsView.popToRootViewController(animated: false)
            svc.allFlowControllersForUITabBarController.flowControllerForFlow(currentFlow).popToRootViewController(animated: false)
            let firstViewController = svc.allFlowControllersForUITabBarController.flowControllerForFlow(currentFlow).viewControllers
            svc.allFlowControllersForUITabBarController.flowControllerForFlow(currentFlow).setViewControllers(firstViewController + discussionVCsToMigrate, animated: false)

            // Ensure the currently selected tab of the UITabBarController matches the current flow
            // Calling `switchToFlow` ensure the current OlvidUserActivity is properly updated.

            DispatchQueue.main.async {
                svc.switchToFlow(currentFlow)
            }

        case .primary:
            return
        case .supplementary:
            return
        case .inspector:
            return
        @unknown default:
            return
        }
        

    }
    
    
    /// Implementing this method to ensure the tabbar is shown when appropriate.
    ///
    /// - Note: This is required because of what appears to be a bug in iOS 26.0.
    func splitViewControllerDidCollapse(_ svc: UISplitViewController) {
        
        Self.logger.debug("Calling splitViewControllerDidCollapse(_:)")
        
        guard let svc = svc as? MainFlowViewController else { assertionFailure(); return }
        
        // For some reason, this is required, otherwise the tabbar stays hidden forever.
        if #available(iOS 18, *) {
            svc.mainTabBarController.isTabBarHidden = false
        } else {
            svc.mainTabBarController.tabBar.isHidden = false
        }
        
        
    }
        
}


// Strings

extension MainFlowViewController {
    
    struct Strings {
        
        static let selectTheContactsToCall = NSLocalizedString("SELECT_THE_CONTACTS_TO_CALL", comment: "")
        
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


// MARK: - Implementing SettingsFlowViewControllerDelegate

extension MainFlowViewController: SettingsFlowViewControllerDelegate {
    
    func historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(_ vc: SettingsFlowViewController, transferId: String, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws -> ObvHistoryTransfer.DestinationOwnedDeviceDecision {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(self, transferId: transferId, otherOwnedDeviceIdentifier: otherOwnedDeviceIdentifier)
    }
    
    func userRequiresMessageHistoryTransferService(_ settingsFlowViewController: SettingsFlowViewController) async throws -> ObvHistoryTransfer.TransferService {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userRequiresMessageHistoryTransferService(self)
    }

    func userWantsToUpdateDiscussionLocalConfiguration(_ vc: SettingsFlowViewController, value: ObvUICoreData.PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedDiscussionLocalConfiguration>) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToUpdateDiscussionLocalConfiguration(self, value: value, localConfigurationObjectID: localConfigurationObjectID)
    }
    
    
    func userWantsToBeRemindedToWriteDownBackupKey(_ settingsFlowViewController: SettingsFlowViewController) async {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        await mainFlowViewControllerDelegate.userWantsToBeRemindedToWriteDownBackupKey(self)
    }
    
    
    func getDeviceDeactivationConsequencesOfRestoringBackup(_ settingsFlowViewController: SettingsFlowViewController, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.getDeviceDeactivationConsequencesOfRestoringBackup(self, ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ settingsFlowViewController: SettingsFlowViewController, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsToKeepAllDevicesActiveThanksToOlvidPlus(self, ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    
    func fetchAvatarImage(_ settingsFlowViewController: SettingsFlowViewController, profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        return await self.dataSources.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
    
    func userWantsToDeleteProfileBackupFromSettings(_ settingsFlowViewController: SettingsFlowViewController, infoForDeletion: ObvProfileBackupFromServer.InfoForDeletion) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToDeleteProfileBackupFromSettings(self, infoForDeletion: infoForDeletion)
    }
    
    
    func userWantsToResetThisDeviceSeedAndBackups(_ settingsFlowViewController: SettingsFlowViewController) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToResetThisDeviceSeedAndBackups(self)
    }
    
    
    func userWantsToAddDevice(_ settingsFlowViewController: SettingsFlowViewController) {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        mainFlowViewControllerDelegate.userWantsToAddDevice(self)
    }
    
    
    func userWantsToSubscribeOlvidPlus(_ settingsFlowViewController: SettingsFlowViewController) {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        mainFlowViewControllerDelegate.userWantsToSubscribeOlvidPlus(self)
    }
    
    
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(_ settingsFlowViewController: SettingsFlowViewController, keycloakConfiguration: ObvTypes.ObvKeycloakConfiguration) async throws -> Data {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(self, keycloakConfiguration: keycloakConfiguration)
    }
    
    
    func restoreProfileBackupFromServerNow(_ settingsFlowViewController: SettingsFlowViewController, profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.restoreProfileBackupFromServerNow(self,
                                                                                          profileBackupFromServerToRestore: profileBackupFromServerToRestore,
                                                                                          rawAuthState: rawAuthState)
    }
    
    
    func userWantsToFetchAllProfileBackupsFromServer(_ settingsFlowViewController: SettingsFlowViewController, profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer] {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        let profileBackupsFromServer = try await mainFlowViewControllerDelegate.userWantsToFetchAllProfileBackupsFromServer(self, profileCryptoId: profileCryptoId, profileBackupSeed: profileBackupSeed)
        return profileBackupsFromServer
    }
    
    
    func userWantsToUseDeviceBackupSeed(_ settingsFlowViewController: SettingsFlowViewController, deviceBackupSeed: ObvCrypto.BackupSeed) async throws -> ObvAppBackup.ObvListOfDeviceBackupProfiles {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsToUseDeviceBackupSeed(self, deviceBackupSeed: deviceBackupSeed)
    }
    

    func userWantsToFetchDeviceBakupFromServer(_ settingsFlowViewController: SettingsFlowViewController) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind> {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsToFetchDeviceBakupFromServer(self, currentOwnedCryptoId: self.currentOwnedCryptoId)
    }

    
    func userWantsToPerformBackupNow(_ settingsFlowViewController: SettingsFlowViewController) async throws {
        try await obvEngine.userWantsToPerformBackupNow()
    }
    
    
    func userRequestedAppDatabaseSyncWithEngine(settingsFlowViewController: SettingsFlowViewController) async throws {
        assert(mainFlowViewControllerDelegate != nil)
        try await mainFlowViewControllerDelegate?.userRequestedAppDatabaseSyncWithEngine(mainFlowViewController: self)
    }

    
    func userWantsToConfigureNewBackups(_ settingsFlowViewController: SettingsFlowViewController, context: ObvAppBackupSetupContext) {
        assert(mainFlowViewControllerDelegate != nil)
        mainFlowViewControllerDelegate?.userWantsToConfigureNewBackups(self, context: context)
    }

    
    func usersWantsToGetBackupParameterIsSynchronizedWithICloud(_ settingsFlowViewController: SettingsFlowViewController) async throws -> Bool {
        return try await obvEngine.usersWantsToGetBackupParameterIsSynchronizedWithICloud()
    }

    
    func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(_ settingsFlowViewController: SettingsFlowViewController, newIsSynchronizedWithICloud: Bool) async throws {
        try await obvEngine.usersWantsToChangeBackupParameterIsSynchronizedWithICloud(newIsSynchronizedWithICloud: newIsSynchronizedWithICloud)
    }
    
    
    func userWantsToEraseAndGenerateNewDeviceBackupSeed(_ settingsFlowViewController: SettingsFlowViewController) async throws -> ObvCrypto.BackupSeed {
        let serverURLForStoringDeviceBackup = ObvAppCoreConstants.serverURLForStoringDeviceBackup
        return try await obvEngine.userWantsToEraseAndGenerateNewDeviceBackupSeed(serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup)
    }
    
}


// MARK: - UITabBarControllerDelegateWithinMainFlowViewController

protocol UITabBarControllerDelegateWithinMainFlowViewController: UITabBarControllerDelegate {
    var mfvc: MainFlowViewController? { get set }
}

/// A protocol defining the behavior for handling `UITabBarController` delegate events.
///
/// Two separate classes conform to this protocol:
/// - One for **iOS 18+**, implementing delegate methods available in newer versions.
/// - One for **pre-iOS 18**, implementing delegate methods for backward compatibility.
///
/// Both implementations share the same core responsibilities:
/// - Tracking the user's current activity within the app.
/// - Handling double-taps on the same tab by either popping to the root view controller or scrolling to the top of the current list.
extension UITabBarControllerDelegateWithinMainFlowViewController {
    
    func updateOlvidUserActivityFlow(to newFlow: ObvAppTypes.ObvFlow) {
        
        guard let mfvc else {
            assertionFailure("The mfvc should be set during the initialisation of the MainFlowViewController")
            return
        }

        mfvc.updateOlvidUserActivityFlow(to: newFlow)
        
    }
    
    func scrollToTop(flow: ObvAppTypes.ObvFlow) {
        
        guard let mfvc else {
            assertionFailure("The mfvc should be set during the initialisation of the MainFlowViewController")
            return
        }

        let flowController = mfvc.allFlowControllersForUITabBarController.flowControllerForFlow(flow)

        if flowController.viewControllers.count == 1 {
            (flowController.viewControllers.first as? CanScrollToTop)?.scrollToTop()
        }
        
    }
    
    
    func shouldScrollToTop(flow: ObvAppTypes.ObvFlow) -> Bool {
        
        guard let mfvc else {
            assertionFailure("The mfvc should be set during the initialisation of the MainFlowViewController")
            return false
        }

        let flowController = mfvc.allFlowControllersForUITabBarController.flowControllerForFlow(flow)

        let shouldScrollToTop = flowController.children.count == 1
        
        return shouldScrollToTop
        
    }
        
}

@available(iOS 18.0, *)
private final class UITabBarControllerDelegateNew: NSObject, UITabBarControllerDelegateWithinMainFlowViewController {
    
    weak var mfvc: MainFlowViewController?
    
    private var shouldScrollToTop: Bool = false
    
    func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
                
        guard let flow = ObvFlow(rawValue: tab.identifier) else {
            assertionFailure("The identifier of a tab must be an ObvFlow raw value")
            self.shouldScrollToTop = false
            return true
        }

        self.shouldScrollToTop = self.shouldScrollToTop(flow: flow)

        return true
        
    }
    
        
    func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
                
        // Ensure the user activity within the app is properly updated
        
        guard let newFlow = ObvFlow(rawValue: selectedTab.identifier) else {
            assertionFailure("The identifier of a tab must be an ObvFlow raw value")
            return
        }
        
        self.updateOlvidUserActivityFlow(to: newFlow)

        // If the selected tab is the same as the previously selected tab:
        // - Pop to the root view controller, or
        // - If the root view controller is already visible, request it to scroll to the top of its list.

        if selectedTab == previousTab && shouldScrollToTop {
            self.scrollToTop(flow: newFlow)
        }
        
    }
    
}


@available(iOS, deprecated: 18.0, message: "This class is deprecated. Use UITabBarControllerDelegateNew instead.")
private final class UITabBarControllerDelegateOld: NSObject, UITabBarControllerDelegateWithinMainFlowViewController {
    
    weak var mfvc: MainFlowViewController?
    
    private var previousFlow: ObvFlow?
    private var newFlow: ObvFlow?
    
    private var shouldScrollToTop: Bool = false

    @available(iOS, deprecated: 18.0, message: "This class is deprecated. Use UITabBarControllerDelegateNew instead.")
    override init() {
        super.init()
    }

    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
        
        self.previousFlow = nil
        self.newFlow = nil
        self.shouldScrollToTop = false

        guard let mfvc else {
            assertionFailure("The identifier of a tab must be an ObvFlow raw value")
            return false
        }
        
        if let previousFlowController = tabBarController.selectedViewController as? ObvFlowController,
           let previousFlow = mfvc.allFlowControllersForUITabBarController.flowForFlowController(previousFlowController) {
            self.previousFlow = previousFlow
        }
        
        if let newFlowController = viewController as? ObvFlowController,
           let newFlow = mfvc.allFlowControllersForUITabBarController.flowForFlowController(newFlowController) {
            self.newFlow = newFlow
            self.shouldScrollToTop = self.shouldScrollToTop(flow: newFlow)
        } else {
            assertionFailure()
        }

        return true
        
    }
    
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
        
        defer {
            self.previousFlow = nil
            self.newFlow = nil
        }
        
        // Ensure the user activity within the app is properly updated
        
        guard let newFlow = self.newFlow else {
            assertionFailure("The new flow should have been set in tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController)")
            return
        }

        self.updateOlvidUserActivityFlow(to: newFlow)

        // If the selected tab is the same as the previously selected tab:
        // - Pop to the root view controller, or
        // - If the root view controller is already visible, request it to scroll to the top of its list.

        if newFlow == previousFlow && shouldScrollToTop {
            self.scrollToTop(flow: newFlow)
        }

    }
    
}


// MARK: - Implementing OlvidShopViewActions (simple forward to the MetaFlowController)

extension MainFlowViewController: OlvidShopViewActions {
    
    func refreshSubscriptionStatus() async throws {
        try await actions.refreshSubscriptionStatus()
    }
    
    
    func userWantsToBuy(_ view: ObvSubscription.OlvidShopView, product: Product) async throws -> ObvAppTypes.StoreKitDelegatePurchaseResult {
        return try await actions.userWantsToBuy(view, product: product)
    }

    func getCurrentActiveSubscriptionPublisher(_ view: ObvSubscription.OlvidShopView) throws -> Published<Product?>.Publisher {
        try actions.getCurrentActiveSubscriptionPublisher(view)
    }
    
}


// MARK: - Implementing ObvChooseDeviceToReactivateViewActions

extension MainFlowViewController: ObvChooseDeviceToReactivateViewActions {
    
    func userWantsToActivateCurrentDevice(_ view: ObvSingleOwnedIdentity.ObvChooseDeviceToReactivateView, ownedCryptoId: ObvTypes.ObvCryptoId, currentDeviceIdentifier: Data, deviceIdentifierOfOtherDeviceToDeactivate: Data?) async throws {
        try await ObvPushNotificationManager.shared.userRequestedReactivationOf(ownedCryptoId: ownedCryptoId, replacedDeviceIdentifier: deviceIdentifierOfOtherDeviceToDeactivate)
    }

}


// MARK: - Implementing OwnedDeviceViewActions

extension MainFlowViewController: ObvSingleOwnedIdentity.OwnedDeviceViewActions {
    
    func userWantsToUpdateOwnedDeviceName(_ view: ObvSingleOwnedIdentity.OwnedDeviceView, ownedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier, newName: String) async throws {
        try await obvEngine.requestChangeOfOwnedDeviceName(ownedCryptoId: ownedDeviceIdentifier.ownedCryptoId, deviceIdentifier: ownedDeviceIdentifier.deviceUID.raw, ownedDeviceName: newName)
    }
    
    func userWantsToDeactivateOtherOwnedDevice(_ view: ObvSingleOwnedIdentity.OwnedDeviceView, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws {
        try await obvEngine.requestDeactivationOfOtherOwnedDevice(ownedCryptoId: otherOwnedDeviceIdentifier.ownedCryptoId, deviceIdentifier: otherOwnedDeviceIdentifier.deviceUID.raw)
    }
    
    func userRequestedSettingUnexpiringDevice(_ view: ObvSingleOwnedIdentity.OwnedDeviceView, identifierOfOwnedDeviceToKeepActive: ObvOwnedDeviceIdentifier) async throws {
        try await obvEngine.requestSettingUnexpiringDevice(
            ownedCryptoId: identifierOfOwnedDeviceToKeepActive.ownedCryptoId,
            deviceIdentifier: identifierOfOwnedDeviceToKeepActive.deviceUID.raw)
    }
    
    func userWantsToRestartChannelCreationWithOtherOwnedDevice(_ view: ObvSingleOwnedIdentity.OwnedDeviceView, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws {
        try await obvEngine.restartChannelEstablishmentProtocolsWithOwnedDevice(ownedCryptoId: otherOwnedDeviceIdentifier.ownedCryptoId, deviceIdentifier: otherOwnedDeviceIdentifier.deviceUID.raw)
    }
    
}


// MARK: - Implementing OwnedDevicesListViewActions

extension MainFlowViewController: ObvSingleOwnedIdentity.OwnedDevicesListViewActions {
    
    func userWantsToSearchForNewOwnedDevices(_ view: ObvSingleOwnedIdentity.OwnedDevicesListView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws {
        try await obvEngine.performOwnedDeviceDiscovery(ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToClearAllOtherOwnedDevicesAndHasConfirmed(_ view: ObvSingleOwnedIdentity.OwnedDevicesListView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws {
        try await obvEngine.deleteAllOtherOwnedDevicesAndChannelsThenPerformOwnedDeviceDiscovery(ownedCryptoId: ownedCryptoId)
    }
    
}


// MARK: - Implementing EditOwnedDetailsViewActions

extension MainFlowViewController: ObvSingleOwnedIdentity.EditOwnedDetailsViewActions {
    
    func userWantsObtainAvatar(_ view: ObvSingleOwnedIdentity.EditOwnedDetailsView, avatarSource: ObvAppTypes.ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsObtainAvatar(self, avatarSource: avatarSource, avatarSize: avatarSize)
    }

    func userWantsToSaveImageToTempFile(_ view: ObvSingleOwnedIdentity.EditOwnedDetailsView, image: UIImage) async throws -> URL {
        try await self.userWantsToSaveImageToTempFile(image: image)
    }

    func userWantsToPublishNewOwnedDetails(_ view: ObvSingleOwnedIdentity.EditOwnedDetailsView, ownedCryptoId: ObvTypes.ObvCryptoId, newIdentityDetails: ObvTypes.ObvIdentityDetails) async throws {
        try await obvEngine.updatePublishedIdentityDetailsOfOwnedIdentity(with: ownedCryptoId, with: newIdentityDetails)
    }
    
    func userWantsToUnbindOwnedIdentityFromKeycloak(_ view: EditOwnedDetailsView, ownedCryptoId: ObvCryptoId) async throws {
        try await KeycloakManagerSingleton.shared.unregisterKeycloakManagedOwnedIdentity(ownedCryptoId: ownedCryptoId)
    }
    
}


// MARK: - Implementing ObvSingleOwnedIdentityViewStackActions

extension MainFlowViewController: ObvSingleOwnedIdentityViewStackActions {
        
    func userWantsToUpdateOwnedCustomDisplayName(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId, newCustomDisplayName: String?) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsToUpdateOwnedCustomDisplayName(self, ownedCryptoId: ownedCryptoId, newCustomDisplayName: newCustomDisplayName)
    }
    
    func userWantsToRefreshSubscriptionStatus(_ view: ObvSingleOwnedIdentity.ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> [ObvAppTypes.StoreKitDelegatePurchaseResult] {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        return try await mainFlowViewControllerDelegate.userWantsToRefreshSubscriptionStatus(self, ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToDeleteOwnedIdentityButHasNotConfirmedYet(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId) {
        Task {
            await self.processUserWantsToDeleteOwnedIdentityButHasNotConfirmedYet(ownedCryptoId: ownedCryptoId)
        }
    }
    
    func userWantsToAddOwnedProfile(_ view: ObvSingleOwnedIdentityView) {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        mainFlowViewControllerDelegate.userWantsToAddOwnedProfile(self)
    }
    
    func userWantsToHideOwnedIdentity(_ view: ObvSingleOwnedIdentity.HiddenProfilePasswordChooserView, ownedCryptoId: ObvCryptoId, password: String) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToHideOwnedIdentity(self, ownedCryptoId: ownedCryptoId, password: password)
    }
    
    func userWantsToUnhideOwnedIdentity(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId) async throws {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); throw ObvError.mainFlowViewControllerDelegateIsNil }
        try await mainFlowViewControllerDelegate.userWantsToUnhideOwnedIdentity(self, ownedCryptoId: ownedCryptoId)
    }
    
}


// MARK: - Implementing ObvSingleOwnedIdentityViewStackNavigation

extension MainFlowViewController: ObvSingleOwnedIdentityViewStackNavigation {
    
    func userWantsToDismissPresentedNavigationStack(_ view: ObvSingleOwnedIdentity.ObvSingleOwnedIdentityViewStack) {
        self.presentedViewController?.dismiss(animated: true)
    }

    func userWantsToNavigateToViewAllowingToAddNewDevice(_ view: ObvSingleOwnedIdentityViewStack, ownedCryptoId: ObvCryptoId) {
        guard let mainFlowViewControllerDelegate else { assertionFailure(); return }
        Task { await mainFlowViewControllerDelegate.userWantsToAddNewDevice(self, ownedCryptoId: ownedCryptoId) }
    }
    
}


// MARK: - Private helper methods

extension MainFlowViewController {
    
    private func userWantsToSaveImageToTempFile(image: UIImage) async throws -> URL {
        guard let jpegData = image.jpegData(compressionQuality: 1.0) else { assertionFailure(); throw ObvFlowControllerError.couldNotGenerateJPEGData }
        let filename = [UUID().uuidString, UTType.jpeg.preferredFilenameExtension ?? "jpeg"].joined(separator: ".")
        let directoryForTempFiles = ObvUICoreDataConstants.ContainerURL.forTempFiles.url
        let filepath = directoryForTempFiles.appendingPathComponent(filename)
        try jpegData.write(to: filepath)
        return filepath
    }
    
    
    private static func getNameOfPersistedObvOwnedDevice(ownedDeviceIdentifier: ObvOwnedDeviceIdentifier) async throws -> String? {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<String?, any Error>, context: NSManagedObjectContext) in
            let name = try PersistedObvOwnedDevice.getNameOfPersistedObvOwnedDevice(ownedDeviceIdentifier: ownedDeviceIdentifier, within: context)
            return continuation.resume(returning: name)
        }
    }

}


// MARK: - Errors

extension MainFlowViewController {
    
    enum ObvError: Error {
        case storeKitDelegateIsNil
        case mainFlowViewControllerDelegateIsNil
        case couldNotDetermineCurrentFlow
        case couldNotPasteStringFromPasteboard
        case couldNotFindAnyOlvidURLInPastedText
        case unexpectedGroupIdentifier
        case couldNotFindDisplayedContactGroup
    }
    
}


// MARK: Helper struct: AllObvFlowViewControllers

fileprivate struct AllObvFlowViewControllers {
    
    private let discussionsFlowViewController: DiscussionsFlowViewController
    private let contactsFlowViewController: ContactsFlowViewController
    private let groupsFlowViewController: GroupsFlowViewController
    private let invitationsFlowViewController: NewInvitationsFlowViewController
    
    init(discussionsFlowViewController: DiscussionsFlowViewController, contactsFlowViewController: ContactsFlowViewController, groupsFlowViewController: GroupsFlowViewController, invitationsFlowViewController: NewInvitationsFlowViewController) {
        self.discussionsFlowViewController = discussionsFlowViewController
        self.contactsFlowViewController = contactsFlowViewController
        self.groupsFlowViewController = groupsFlowViewController
        self.invitationsFlowViewController = invitationsFlowViewController
    }
    
    func flowControllerForFlow(_ flow: ObvAppTypes.ObvFlow) -> ObvFlowController {
        switch flow {
        case .latestDiscussions: return discussionsFlowViewController
        case .contacts: return contactsFlowViewController
        case .groups: return groupsFlowViewController
        case .invitations: return invitationsFlowViewController
        }
    }
    
    func getAllDiscussionsInFlow(_ flow: ObvAppTypes.ObvFlow) -> [SomeSingleDiscussionViewController] {
        flowControllerForFlow(flow).viewControllers.compactMap { $0 as? SomeSingleDiscussionViewController }
    }
    
    func flowForFlowController(_ flowController: ObvFlowController) -> ObvFlow? {
        switch flowController {
        case discussionsFlowViewController: return .latestDiscussions
        case contactsFlowViewController: return .contacts
        case groupsFlowViewController: return .groups
        case invitationsFlowViewController: return .invitations
        default: assertionFailure(); return nil
        }
    }
    
    var allFlowControllers: [ObvFlowController] {
        ObvFlow.allCases.map { flowControllerForFlow($0) }
    }
}




// MARK: - MainFlowViewControllerDelegate


protocol MainFlowViewControllerDelegate: AnyObject {
    func userWantsToAddNewDevice(_ viewController: MainFlowViewController, ownedCryptoId: ObvCryptoId) async
    func userWantsToPublishGroupV2Creation(_ mainFlowViewController: MainFlowViewController, groupCoreDetails: GroupV2CoreDetails, ownPermissions: Set<ObvGroupV2.Permission>, otherGroupMembers: Set<ObvGroupV2.IdentityAndPermissions>, ownedCryptoId: ObvCryptoId, photoURL: URL?, groupType: ObvAppTypes.ObvGroupType) async throws
    func userWantsToPublishGroupV2Modification(_ mainFlowViewController: MainFlowViewController, groupObjectID: TypeSafeManagedObjectID<PersistedGroupV2>, changeset: ObvGroupV2.Changeset) async throws
    func userRequestedAppDatabaseSyncWithEngine(mainFlowViewController: MainFlowViewController) async throws
    func userWantsToSendDraft(mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, textBody: AttributedString) async throws
    func userWantsToAddAttachmentsToDraft(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, itemProviders: [NSItemProvider], source: LoadItemProviderHelper.ItemProviderProviderSource) async throws -> [LoadedItemProviderToPaste]
    func userWantsToAddAttachmentsToDraftFromURLs(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, urls: [URL]) async throws
    func userWantsToUpdateDraftBodyAndMentions(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, body: AttributedString) async throws
    func userWantsToDeleteDraftAttachment(_ mainFlowViewController: MainFlowViewController, draftFyleJoinObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) async throws
    func userWantsToReplyToMessage(_ mainFlowViewController: MainFlowViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
    func userWantsToDownloadReceivedFyleMessageJoinWithStatus(_ mainFlowViewController: MainFlowViewController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws
    func userWantsToPauseDownloadReceivedFyleMessageJoinWithStatus(_ mainFlowViewController: MainFlowViewController, receivedJoinObjectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) async throws
    func userWantsToPauseSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ mainFlowViewController: MainFlowViewController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws
    func userWantsToDownloadSentFyleMessageJoinWithStatusFromOtherOwnedDevice(_ mainFlowViewController: MainFlowViewController, sentJoinObjectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) async throws
    func userWantsToRemoveReplyToMessage(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) async throws
    func insertDiscussionIsEndToEndEncryptedSystemMessageIntoDiscussionIfEmpty(_ mainFlowViewController: MainFlowViewController, discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, markAsRead: Bool) async throws
    func userWantsToUpdateDraftExpiration(_ mainFlowViewController: MainFlowViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws
    func userWantsToReadReceivedMessageThatRequiresUserAction(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageId: ReceivedMessageIdentifier) async throws
    func updatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(_ mainFlowViewController: MainFlowViewController, discussionPermanentID: ObvUICoreData.ObvManagedObjectPermanentID<ObvUICoreData.PersistedDiscussion>, messagePermanentIDs: Set<ObvUICoreData.ObvManagedObjectPermanentID<ObvUICoreData.PersistedMessage>>) async throws
    func messagesAreNotNewAnymore(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, discussionId: DiscussionIdentifier, messageIds: [MessageIdentifier]) async throws
    func userWantsToUpdateReaction(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, newEmoji: String?) async throws
    func userWantsToUpdatePollVote(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>, pollVoteCandidateUuid: UUID, voted: Bool, version: Int) async throws
    func userWantsToStopAllContinuousSharingFromCurrentPhysicalDevice(_ mainFlowViewController: MainFlowViewController) async throws
    func userWantsToStopSharingLocationInDiscussion(_ mainFlowViewController: MainFlowViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToFetchDeviceBakupFromServer(_ mainFlowViewController: MainFlowViewController, currentOwnedCryptoId: ObvCryptoId) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind>
    func userWantsToUseDeviceBackupSeed(_ mainFlowViewController: MainFlowViewController, deviceBackupSeed: ObvCrypto.BackupSeed) async throws -> ObvAppBackup.ObvListOfDeviceBackupProfiles
    func userWantsToFetchAllProfileBackupsFromServer(_ mainFlowViewController: MainFlowViewController, profileCryptoId: ObvCryptoId, profileBackupSeed: ObvCrypto.BackupSeed) async throws -> [ObvProfileBackupFromServer]
    func restoreProfileBackupFromServerNow(_ mainFlowViewController: MainFlowViewController, profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos
    func userNeedsToProveCapacityToAuthenticateOnKeycloakServerAsTransferIsRestricted(_ mainFlowViewController: MainFlowViewController, keycloakConfiguration: ObvKeycloakConfiguration) async throws -> Data
    @MainActor func userWantsToSubscribeOlvidPlus(_ mainFlowViewController: MainFlowViewController)
    @MainActor func userWantsToAddDevice(_ mainFlowViewController: MainFlowViewController)
    func userWantsToResetThisDeviceSeedAndBackups(_ mainFlowViewController: MainFlowViewController) async throws
    func userWantsToDeleteProfileBackupFromSettings(_ mainFlowViewController: MainFlowViewController, infoForDeletion: ObvProfileBackupFromServer.InfoForDeletion) async throws
    func getDeviceDeactivationConsequencesOfRestoringBackup(_ mainFlowViewController: MainFlowViewController, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ mainFlowViewController: MainFlowViewController, ownedCryptoIdentity: ObvCrypto.ObvOwnedCryptoIdentity) async throws -> ObvAppBackup.ObvDeviceDeactivationConsequence
    @MainActor func userWantsToConfigureNewBackups(_ mainFlowViewController: MainFlowViewController, context: ObvAppBackupSetupContext)
    @MainActor func userWantsToBeRemindedToWriteDownBackupKey(_ mainFlowViewController: MainFlowViewController) async
    @MainActor func userWantsToDisplayBackupKey(_ mainFlowViewController: MainFlowViewController)
    @MainActor func userWantsToRefreshSubscriptionStatus(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvTypes.ObvCryptoId?) async throws -> [ObvAppTypes.StoreKitDelegatePurchaseResult]
    
    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupV2Identifier) async throws
    func userWantsToLeaveGroup(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupIdentifier) async throws
    func userWantsToDisbandGroup(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupIdentifier) async throws
    func userWantsObtainAvatar(_ mainFlowViewController: MainFlowViewController, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    @MainActor func userWantsToDeleteOwnedIdentityAndHasConfirmed(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, globalOwnedIdentityDeletion: Bool) async throws
    
    func userWantsToShowMapToSendOrShareLocationContinuously(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToShowMapToConsultLocationSharedContinously(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, messageObjectID: TypeSafeManagedObjectID<PersistedMessage>) async throws
    func userWantsToShowMapToConsultLocationSharedContinously(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, ownedCryptoId: ObvCryptoId) async throws

    func userWantsToCreatePoll(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, discussionIdentifier: ObvDiscussionIdentifier) async throws
    func userWantsToDisplayPollView(_ mainFlowViewController: MainFlowViewController, presentingViewController: UIViewController, pollObjectID: TypeSafeManagedObjectID<PersistedPoll>) async throws
    func userWantsToMarkAllMessagesAsReadInDiscussion(_ mainFlowViewController: MainFlowViewController, discussionObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedDiscussion>) async throws
    func userWantsToReorderPinnedDiscussions(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, objectIDOfPinnedDiscussions: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws

    func userWantsToArchiveDiscussions(_ mainFlowViewController: MainFlowViewController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws
    func userWantsToUnarchiveDiscussions(_ mainFlowViewController: MainFlowViewController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>]) async throws

    func userWantsToDeleteDiscussionsAndHasConfirmed(_ mainFlowViewController: MainFlowViewController, discussionObjectIDs: [TypeSafeManagedObjectID<PersistedDiscussion>], deletionType: DeletionType) async throws

    func userWantsToProcessReceiptsStoredForLater(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, returnReceiptElements: Set<ObvReturnReceiptElements>) async

    func userWantsToUpdatePersonalNote(_ mainFlowViewController: MainFlowViewController, with newText: String?, about: PersonalNoteEditorView.Model.About) async throws
    func userDidSeeNewDetailsOfContact(_ mainFlowViewController: MainFlowViewController, contactIdentifier: ObvContactIdentifier)

    func userWantsToReplaceTrustedDetailsByPublishedDetails(_ mainFlowViewController: MainFlowViewController, groupIdentifier: ObvGroupV1Identifier) async throws
    func userHasSeenPublishedDetails(_ mainFlowViewController: MainFlowViewController, publishedDetails: PublishedDetailsValidationViewModel) async throws
    func userWantsToPublishGroupV1Creation(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails, otherGroupMembers: Set<ObvTypes.ObvCryptoId>) async throws

    func userWantsToRemoveMembersFromGroupV1(_ mainFlowViewController: MainFlowViewController, groupV1Identifier: ObvGroupV1Identifier, removedGroupMembers: Set<ObvCryptoId>) async throws
    func userWantsToAddSelectedUsersToExistingGroup(_ mainFlowViewController: MainFlowViewController, groupV1Identifier: ObvGroupV1Identifier, newGroupMembers: Set<ObvCryptoId>) async throws
    func userWantsToUpdateGroupNameAndPicture(_ mainFlowViewController: MainFlowViewController, groupV1Identifier: ObvGroupV1Identifier, changes: Set<EditGroupNameAndPictureView.Change>) async throws

    func userWantsToAddOwnedProfile(_ mainFlowViewController: MainFlowViewController)

    func userWantsToHideOwnedIdentity(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, password: String) async throws
    func userWantsToUnhideOwnedIdentity(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId) async throws

    func userWantsToUpdateOwnedCustomDisplayName(_ mainFlowViewController: MainFlowViewController, ownedCryptoId: ObvCryptoId, newCustomDisplayName: String?) async throws
    func historySourceDeviceWantsToSendTransferConfirmationRequestToDestinationOwnedDevice(_ mainFlowViewController: MainFlowViewController, transferId: String, otherOwnedDeviceIdentifier: ObvTypes.ObvOwnedDeviceIdentifier) async throws -> ObvHistoryTransfer.DestinationOwnedDeviceDecision
    
    func userWantsToDiscoverOlvidPlus(_ mainFlowViewController: MainFlowViewController)
    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ mainFlowViewController: MainFlowViewController)
    func userRequiresMessageHistoryTransferService(_ mainFlowViewController: MainFlowViewController) async throws -> ObvHistoryTransfer.TransferService

    func userWantsToUpdateDiscussionLocalConfiguration(_ vc: MainFlowViewController, value: ObvUICoreData.PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedDiscussionLocalConfiguration>) async throws

    func userWantsToForwardMessage(_ mainFlowViewController: MainFlowViewController, identifierOfMessageToForwad: ObvMessageAppIdentifier, identifiersOfDiscussionsWhereMessageShouldBeForwarded: Set<ObvDiscussionIdentifier>) async throws

}


protocol StoreKitDelegate: AnyObject {
    func userRequestedListOfSKProducts() async throws -> [Product]
    func userWantsToBuy(_ product: Product) async throws -> StoreKitDelegatePurchaseResult
    func userWantsToRestorePurchases() async throws
    func userWantsToKnowIfMultideviceSubscriptionIsActive() async throws -> Bool
    func refreshSubscriptionStatus() async throws -> [ObvAppTypes.StoreKitDelegatePurchaseResult]
    func getCurrentActiveSubscriptionPublisher() throws -> Published<Product?>.Publisher
    func getCurrentActiveSubscription() throws -> Product?
    func getOwnershipTypeForTipNotificationOfJustMadeSubscription() async throws -> ObvOwnershipType?
}
