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

import CoreData
import OSLog
import ObvUI
import ObvTypes
import UIKit
import ObvUICoreData
import ObvSettings
import ObvDesignSystem
import ObvSystemIcon
import ObvSharedDataSources
import ObvOwnedIdentityChooser
import ObvAppTypes


final class AllContactsViewController: ShowOwnedIdentityButtonUIViewController, ViewControllerWithEllipsisCircleRightBarButtonItem {

    // Variables
    
    private var notificationTokens = [NSObjectProtocol]()
    private let oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus
    private let showExplanation: Bool
    private let textAboveContactList: String?
    private var viewDidLoadWasCalled = false
    private let avatarViewDataSource: ObvAvatarViewDataSource
    private let ownedIdentityChooserViewDataSource: OwnedIdentityChooserViewDataSource
    
    // Delegates
    
    weak var delegate: AllContactsViewControllerDelegate?
    
    // MARK: - Initializer
    
    init(ownedCryptoId: ObvCryptoId, oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus, title: String = CommonString.Word.Contacts, showExplanation: Bool, textAboveContactList: String?, barButtonItemToShowInsteadOfProfilePicture: UIBarButtonItem? = nil, avatarViewDataSource: ObvAvatarViewDataSource, ownedIdentityChooserViewDataSource: OwnedIdentityChooserViewDataSource) {
        self.avatarViewDataSource = avatarViewDataSource
        self.ownedIdentityChooserViewDataSource = ownedIdentityChooserViewDataSource
        self.oneToOneStatus = oneToOneStatus
        self.showExplanation = showExplanation
        self.textAboveContactList = textAboveContactList
        super.init(ownedCryptoId: ownedCryptoId,
                   logCategory: "AllContactsViewController",
                   barButtonItemToShowInsteadOfProfilePicture: barButtonItemToShowInsteadOfProfilePicture,
                   avatarViewDataSource: avatarViewDataSource,
                   ownedIdentityChooserViewDataSource: ownedIdentityChooserViewDataSource)
        self.title = title
        observeContactsSortOrderDidChangeNotifications()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    // MARK: - Switching current owned identity

    override func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) {
        super.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        guard viewDidLoadWasCalled else { return }
        for multipleContactsHostingViewController in children.compactMap({ $0 as? MultipleUsersHostingViewController }) {
            multipleContactsHostingViewController.view.removeFromSuperview()
            multipleContactsHostingViewController.willMove(toParent: nil)
            multipleContactsHostingViewController.removeFromParent()
            multipleContactsHostingViewController.didMove(toParent: nil)
        }
        addAndConfigureContactsTableViewController()
    }
        
}


// MARK: - View Controller Lifecycle

extension AllContactsViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        viewDidLoadWasCalled = true
        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        addAndConfigureContactsTableViewController()
        definesPresentationContext = true
        
        navigationItem.rightBarButtonItem = getConfiguredEllipsisCircleRightBarButtonItem(menu: provideMenu())

    }

    
    func provideMenu() -> UIMenu {

        let parentMenu = self.defaultMenu()

        // Update the parents menu
        var menuElements = [UIMenuElement]()
        menuElements.append(contentsOf: parentMenu.children)
        
        let ownedCryptoId = self.currentOwnedCryptoId
        func buildAction(sortOrder: ContactsSortOrder) -> UIAction {
            return .init(title: sortOrder.description,
                  image: nil,
                  identifier: nil,
                  discoverabilityTitle: nil,
                  attributes: .init(),
                  state: ObvMessengerSettings.Interface.contactsSortOrder == sortOrder ? .on : .off) { _ in
                ObvMessengerInternalNotification.userWantsToChangeContactsSortOrder(ownedCryptoId: ownedCryptoId, sortOrder: sortOrder).postOnDispatchQueue()
            }
        }

        let sortActions = ContactsSortOrder.allCases.map({ buildAction(sortOrder: $0) })
        let sortMenu = UIMenu(
            title: String(localized: "CONTACT_SORT_ORDER"),
            image: UIImage(systemIcon: .arrowUpArrowDownCircle),
            children: sortActions)
        
        menuElements.append(sortMenu)
        
        switch oneToOneStatus {
        case .nonOneToOne:
            break
        default:
            let showOtherKnownUserAction = UIAction(title: NSLocalizedString("OTHER_KNOWN_USERS", comment: ""),
                                                    image: UIImage(systemIcon: .personCropCircleBadgeQuestionmark)) { [weak self] _ in
                self?.presentViewControllerOfAllNonOneToOneContacts()
            }

            menuElements.append(showOtherKnownUserAction)
        }

        return UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: menuElements)
    }
    
    
    private func presentViewControllerOfAllNonOneToOneContacts() {
        assert(Thread.isMainThread)
        
        let barButtonItem: UIBarButtonItem
        if #available(iOS 26, *) {
            barButtonItem = UIBarButtonItem(image: UIImage(systemIcon: .xmark), style: .plain, target: self, action: #selector(dismissViewControllerOfAllNonOneToOneContacts))
        } else {
            barButtonItem = UIBarButtonItem(image: UIImage(systemIcon: .xmarkCircleFill), style: .plain, target: self, action: #selector(dismissViewControllerOfAllNonOneToOneContacts))
            barButtonItem.tintColor = AppTheme.shared.colorScheme.olvidLight
        }

        let vc = AllContactsViewController(ownedCryptoId: currentOwnedCryptoId,
                                           oneToOneStatus: .nonOneToOne,
                                           title: NSLocalizedString("OTHER_KNOWN_USERS", comment: ""),
                                           showExplanation: false,
                                           textAboveContactList: CommonString.explanationNonOneToOneContact,
                                           barButtonItemToShowInsteadOfProfilePicture: barButtonItem,
                                           avatarViewDataSource: self.avatarViewDataSource,
                                           ownedIdentityChooserViewDataSource: self.ownedIdentityChooserViewDataSource)
        vc.delegate = self.delegate
        vc.unlockingHiddenProfileDelegate = self.unlockingHiddenProfileDelegate
                
        let nav = UINavigationController(rootViewController: vc)
        self.present(nav, animated: true)
    }
    
    @objc
    private func dismissViewControllerOfAllNonOneToOneContacts() {
        presentedViewController?.dismiss(animated: true)
    }
    
    
    private func observeContactsSortOrderDidChangeNotifications() {
        let token = ObvMessengerSettingsNotifications.observeContactsSortOrderDidChange { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                navigationItem.rightBarButtonItem = getConfiguredEllipsisCircleRightBarButtonItem(menu: provideMenu())
            }
        }
        notificationTokens.append(token)
    }

    
    private func addAndConfigureContactsTableViewController() {
        
        let verticalConfiguration = VerticalUsersViewConfiguration(
            showExplanation: showExplanation,
            disableUsersWithoutDevice: false,
            allowMultipleSelection: false,
            textAboveUserList: textAboveContactList,
            selectionStyle: .checkmark)
        let configuration = HorizontalAndVerticalUsersViewConfiguration(
            verticalConfiguration: verticalConfiguration,
            horizontalConfiguration: nil,
            buttonConfiguration: nil)
        
        let viewController = MultipleUsersHostingViewController(
            ownedCryptoId: currentOwnedCryptoId,
            mode: .all(oneToOneStatus: self.oneToOneStatus, requiredCapabilitites: nil),
            configuration: configuration,
            delegate: self)
        
        navigationItem.searchController = viewController.searchController
        navigationItem.hidesSearchBarWhenScrolling = false
                
        viewController.willMove(toParent: self)
        self.addChild(viewController)
        viewController.didMove(toParent: self)
        viewController.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.insertSubview(viewController.view, at: 0)
        self.view.pinAllSidesToSides(of: viewController.view)

    }
    
    
    /// This method is used when deeplinks need to navigate through the hierarchy
    func selectRowOfContactIdentity(_ contactIdentity: PersistedObvContactIdentity) {
        if let vc = children.first as? MultipleUsersHostingViewController {
            vc.selectRowOfContactIdentity(contactIdentity)
        }
    }

}

// MARK: - MultipleContactsHostingViewController

extension AllContactsViewController: MultipleContactsHostingViewControllerDelegate {

    func userWantsToSeeContactDetails(of contact: PersistedObvContactIdentity) {
        guard let contactIdentifier = try? contact.obvContactIdentifier else {
            assertionFailure()
            return
        }
        delegate?.userDidSelectContact(self, withContactIdentifier: contactIdentifier, within: self.navigationController)
    }
    
}

// MARK: - CanScrollToTop

extension AllContactsViewController: CanScrollToTop {
    
    func scrollToTop() {
        if let vc = children.first as? MultipleUsersHostingViewController {
            vc.scrollToTop()
        }
    }
    
}
