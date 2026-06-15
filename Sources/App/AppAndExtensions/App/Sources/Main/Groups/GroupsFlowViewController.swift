/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvEngine
import ObvTypes
import ObvUI
import ObvUICoreData
import ObvSettings
import ObvDesignSystem
import ObvAppCoreConstants
import ObvUIGroupV1
import ObvUIGroupV2
import ObvSharedDataSources
import ObvGroupsList
import ObvProfilePictureBarButtonItem
import ObvCells
import ObvAppNavigation


final class GroupsFlowViewController: ObvFlowController {
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "GroupsFlowViewController")
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: GroupsFlowViewController.self))

    private var observationTokens = [NSObjectProtocol]()

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, dataSources: ObvDataSources) {

        super.init(ownedCryptoId: ownedCryptoId,
                   obvEngine: obvEngine,
                   dataSources: dataSources,
                   doAddFloatingButton: false)
        
        let groupsListViewController = ObvGroupsListViewController(
            currentOwnedCryptoId: ownedCryptoId,
            dataSource: dataSources.groupsListViewDataSource,
            groupCellViewDataSource: dataSources.groupCellViewDataSource,
            profilePictureBarButtonItemViewDataSource: dataSources.profilePictureBarButtonItemViewDataSource,
            avatarViewDataSource: dataSources.avatarViewDataSource,
            ownedIdentityChooserViewDataSource: dataSources.ownedIdentityChooserViewDataSource,
            navigation: self,
            actions: self)
        
        self.setViewControllers([groupsListViewController], animated: false)
        
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    required init?(coder aDecoder: NSCoder) { fatalError("die") }

}


// MARK: - View controller lifecycle

extension GroupsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Note: Do not set the title here.
        // The title is managed by `ObvGroupsListView`, and explicitly setting it would override the tab bar title
        // on iOS 17 and less.
        
        if #available(iOS 18, *) {
            // The tabbar is configured with iOS 18 APIs, we don't need to specify a tabBarItem
        } else {
            let image = UIImage(systemIcon: .person3)
            tabBarItem = UITabBarItem(title: CommonString.Word.Groups, image: image, tag: 2)
        }

        if #available(iOS 26, *) {
            // We don't change the appearance under iOS 26
        } else {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            navigationBar.standardAppearance = appearance
        }

        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        
        //observeNotificationsImpactingTheNavigationStack()
        
        // This is required to activate the interactive pop gesture recognizer. Activating this interactive gesture also requires
        // to override gestureRecognizerShouldBegin(_:).
        // See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
        if #available(iOS 17, *) {
            interactivePopGestureRecognizer?.delegate = self
        }

    }
    
}


// MARK: - UIGestureRecognizerDelegate

extension GroupsFlowViewController: UIGestureRecognizerDelegate {
    
    /// This is only used under iOS18+, in order to be the delegate of the `interactivePopGestureRecognizer`, allowing to activate the interactive pop gesture recognizer.
    /// See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
    @objc func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
    }
    
}


// MARK: - Implementing ObvGroupsListViewActions

extension GroupsFlowViewController: ObvGroupsListViewActions {
    
    func userWantsToCreateNewGroup(_ view: ObvGroupsList.ObvGroupsListView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        flowDelegate?.userWantsToCreateNewGroup(self, ownedCryptoId: ownedCryptoId)
    }
    
    
    /// This method is called when the user changes the current profile from the profile switcher implemented in SwiftUI. We need to propagate this in the rest of the app.
    func userDidSwitchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvTypes.ObvCryptoId) async {
        ObvMessengerInternalNotification.userWantsToSwitchToOtherOwnedIdentity(ownedCryptoId: newOwnedCryptoId)
            .postOnDispatchQueue()
    }

    // The following method is implemented in ObvFlowController
    // func userDidPressOnObvGroupCellView(_ view: ObvGroupCellView, groupIdentifier: ObvGroupCellViewModel.GroupIdentifier, expectedNavigation: ObvGroupCellView.ExpectedNavigation) throws {
    
    func userDidLongPressOnProfilePicture(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView) {
        guard let flowDelegate else { assertionFailure(); return }
        flowDelegate.showAlertForUnlockingHiddenOwnedIdentity(self)
    }

    
    func userWantsToEditOwnedIdentity(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView, ownedCryptoId: ObvTypes.ObvCryptoId) async {
        guard currentOwnedCryptoId == ownedCryptoId else { assertionFailure(); return }
        let deepLink = ObvDeepLink.myId(ownedCryptoId: ownedCryptoId)
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: deepLink)
            .postOnDispatchQueue()
    }
    
    
    func userWantsToAddNewProfile(_ view: ObvProfilePictureBarButtonItem.ObvProfilePictureBarButtonItemView) async {
        ObvMessengerInternalNotification.userWantsToAddOwnedProfile
            .postOnDispatchQueue()
    }
    
    
    func userWantsToNavigateToSettings(_ view: ObvGroupsList.ObvGroupsListView.MainMenu) {
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .settings)
            .postOnDispatchQueue()
    }
    
    
    func userWantsToNavigateToStorageManagement(_ view: ObvGroupsList.ObvGroupsListView.MainMenu) {
        ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .storageManagementSettings)
            .postOnDispatchQueue()
    }

    
    func userTappedObvPlusButton() {
        guard let flowDelegate else { assertionFailure(); return }
        flowDelegate.userTappedObvPlusButton(self)
    }
    
}


// MARK: - Errors

extension GroupsFlowViewController {
    
    enum ObvError: Error {
        case unexpectedGroupIdentifier
        case couldNotFindDisplayedContactGroup
        case couldNotFindConcreteGroup
    }
    
}


// MARK: - ObvGroupsListViewController implements CanScrollToTop

extension ObvGroupsListViewController: CanScrollToTop {
    // Method already implemented in ObvGroupsListViewController
}
