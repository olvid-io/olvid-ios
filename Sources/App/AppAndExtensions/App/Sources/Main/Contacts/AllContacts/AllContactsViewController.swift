/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import os.log
import ObvUI
import ObvTypes
import UIKit
import ObvUICoreData
import ObvSettings
import ObvDesignSystem


final class AllContactsViewController: ShowOwnedIdentityButtonUIViewController, OlvidMenuProvider, ViewControllerWithEllipsisCircleRightBarButtonItem {

    // Variables
    
    private var notificationTokens = [NSObjectProtocol]()
    private var sortButtonItem: UIBarButtonItem?
    private var sortButtonItemTimer: Timer?
    private let oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus
    private let showExplanation: Bool
    private let textAboveContactList: String?
    private var viewDidLoadWasCalled = false

    // Delegates
    
    weak var delegate: AllContactsViewControllerDelegate?
    
    // MARK: - Initializer
    
    init(ownedCryptoId: ObvCryptoId, oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus, title: String = CommonString.Word.Contacts, showExplanation: Bool, textAboveContactList: String?, barButtonItemToShowInsteadOfProfilePicture: UIBarButtonItem? = nil) {
        self.oneToOneStatus = oneToOneStatus
        self.showExplanation = showExplanation
        self.textAboveContactList = textAboveContactList
        super.init(ownedCryptoId: ownedCryptoId, logCategory: "AllContactsViewController", barButtonItemToShowInsteadOfProfilePicture: barButtonItemToShowInsteadOfProfilePicture)
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

    @MainActor
    override func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) async {
        await super.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
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

        navigationItem.rightBarButtonItem = getConfiguredEllipsisCircleRightBarButtonItem()

    }

    
    func provideMenu() -> UIMenu {
        
        // Update the parents menu
        var menuElements = [UIMenuElement]()
        if let parentMenu = parent?.getFirstMenuAvailable() {
            menuElements.append(contentsOf: parentMenu.children)
        }
        
        let ownedCryptoId = self.currentOwnedCryptoId
        func buildAction(sortOrder: ContactsSortOrder) -> UIAction {
            .init(title: sortOrder.description,
                  image: nil,
                  identifier: nil,
                  discoverabilityTitle: nil,
                  attributes: .init(),
                  state: ObvMessengerSettings.Interface.contactsSortOrder == sortOrder ? .on : .off) { [weak self ] (action) in
                guard let _self = self else { return }
                _self.sortButtonItemTimer?.invalidate()
                DispatchQueue.main.async {
                    _self.sortButtonItem?.isEnabled = false
                }
                ObvMessengerInternalNotification.userWantsToChangeContactsSortOrder(ownedCryptoId: ownedCryptoId, sortOrder: sortOrder).postOnDispatchQueue()
                _self.sortButtonItemTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        _self.sortButtonItem?.isEnabled = true
                    }
                }
            }
        }

        let sortActions = ContactsSortOrder.allCases.map({ buildAction(sortOrder: $0) })
        let sortMenu = UIMenu(
            title: NSLocalizedString("CONTACT_SORT_ORDER", comment: ""),
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
        
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
        let image = UIImage(systemIcon: .xmarkCircleFill, withConfiguration: symbolConfiguration)
        let barButtonItem = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(dismissViewControllerOfAllNonOneToOneContacts))
        barButtonItem.tintColor = AppTheme.shared.colorScheme.olvidLight

        let vc = AllContactsViewController(ownedCryptoId: currentOwnedCryptoId,
                                           oneToOneStatus: .nonOneToOne,
                                           title: NSLocalizedString("OTHER_KNOWN_USERS", comment: ""),
                                           showExplanation: false,
                                           textAboveContactList: CommonString.explanationNonOneToOneContact,
                                           barButtonItemToShowInsteadOfProfilePicture: barButtonItem)
        vc.delegate = self.delegate
                
        let nav = UINavigationController(rootViewController: vc)
        self.present(nav, animated: true)
    }
    
    @objc
    private func dismissViewControllerOfAllNonOneToOneContacts() {
        presentedViewController?.dismiss(animated: true)
    }
    
    
    private func observeContactsSortOrderDidChangeNotifications() {
        let token = ObvMessengerSettingsNotifications.observeContactsSortOrderDidChange(queue: OperationQueue.main) { [weak self] in
            guard let _self = self else { return }
            _self.sortButtonItemTimer?.invalidate()
            _self.sortButtonItem?.menu = _self.provideMenu()
            _self.sortButtonItem?.isEnabled = true
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
        delegate?.userDidSelect(contact, within: self.navigationController)
    }
    
}

// MARK: - ContactsTableViewControllerDelegate

extension AllContactsViewController: ContactsTableViewControllerDelegate {
    
    func userWantsToDeleteContact(with: ObvCryptoId, forOwnedCryptoId: ObvCryptoId, completionHandler: @escaping (Bool) -> Void) {
        assert(false, "Not implemented")
    }

    func userDidSelect(_ contact: PersistedObvContactIdentity) {
        delegate?.userDidSelect(contact, within: self.navigationController)
    }
    
    func userDidDeselect(_ contact: PersistedObvContactIdentity) {
        delegate?.userDidDeselect(contact)
    }
    
}


// MARK: - CanScrollToTop

extension AllContactsViewController: CanScrollToTop {
    
    func scrollToTop() {
        if let vc = children.first as? ContactsTableViewController {
            guard vc.tableView.numberOfSections > 0 && vc.tableView.numberOfRows(inSection: 0) > 0 else { return }
            vc.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
        } else if let vc = children.first as? MultipleUsersHostingViewController {
            vc.scrollToTop()
        }
    }
    
}
