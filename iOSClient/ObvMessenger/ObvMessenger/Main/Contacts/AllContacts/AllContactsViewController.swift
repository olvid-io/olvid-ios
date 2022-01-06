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
import ObvEngine
import CoreData

final class AllContactsViewController: ShowOwnedIdentityButtonUIViewController, OlvidMenuProvider, ViewControllerWithEllipsisCircleRightBarButtonItem {

    // Variables
    
    private var notificationTokens = [NSObjectProtocol]()
    private var sortButtonItem: UIBarButtonItem?
    private var sortButtonItemTimer: Timer?

    // Delegates
    
    weak var delegate: AllContactsViewControllerDelegate?
    
    // MARK: - Initializer
    
    init(ownedCryptoId: ObvCryptoId) {
        super.init(ownedCryptoId: ownedCryptoId, logCategory: "AllContactsViewController")
        self.title = CommonString.Word.Contacts
        observeContactsSortOrderDidChangeNotifications()
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


// MARK: - View Controller Lifecycle

extension AllContactsViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        addAndConfigureContactsTableViewController()
        definesPresentationContext = true

        if #available(iOS 14, *) {
            navigationItem.rightBarButtonItem = getConfiguredEllipsisCircleRightBarButtonItem()
        } else if #available(iOS 13.0, *) {
            navigationItem.rightBarButtonItem = getConfiguredEllipsisCircleRightBarButtonItem(selector: #selector(ellipsisButtonTappedSelector))
        }

    }

    
    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    @objc private func ellipsisButtonTappedSelector() {
        ellipsisButtonTapped(sourceBarButtonItem: navigationItem.rightBarButtonItem)
    }

    
    @available(iOS 13.0, *)
    func provideMenu() -> UIMenu {
        
        // Update the parents menu
        var menuElements = [UIMenuElement]()
        if let parentMenu = parent?.getFirstMenuAvailable() {
            menuElements.append(contentsOf: parentMenu.children)
        }
        
        let ownedCryptoId = self.ownedCryptoId
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

        return UIMenu(title: "", image: nil, identifier: nil, options: .displayInline, children: menuElements)
    }
    
    
    @available(iOS, introduced: 13, deprecated: 14, message: "Use getFirstParentMenuAvailable() instead")
    func provideAlertActions() -> [UIAlertAction] {

        // Update the parents alerts
        var alertActions = [UIAlertAction]()
        if let parentAlertActions = parent?.getFirstAlertActionsAvailable() {
            alertActions.append(contentsOf: parentAlertActions)
        }

        // We do not provide the option to change the sort order under iOS 13

        return alertActions

    }
    

    private func observeContactsSortOrderDidChangeNotifications() {
        if #available(iOS 14.0, *) {
            let token = ObvMessengerInternalNotification.observeContactsSortOrderDidChange(queue: OperationQueue.main) { [weak self] in
                guard let _self = self else { return }
                _self.sortButtonItemTimer?.invalidate()
                _self.sortButtonItem?.menu = _self.provideMenu()
                _self.sortButtonItem?.isEnabled = true
            }
            notificationTokens.append(token)
        }
    }

    
    private func addAndConfigureContactsTableViewController() {
        
        let viewController: UIViewController
        let mode: MultipleContactsMode = .all
        if #available(iOS 13.0, *) {
            guard let vc = try? MultipleContactsHostingViewController(ownedCryptoId: ownedCryptoId, mode: mode, disableContactsWithoutDevice: false, allowMultipleSelection: false, showExplanation: true, floatingButtonModel: nil) else { assertionFailure(); return }
            vc.delegate = self
            viewController = vc
            navigationItem.searchController = vc.searchController
            viewController.willMove(toParent: self)
            self.addChild(viewController)
            viewController.didMove(toParent: self)
            viewController.view.translatesAutoresizingMaskIntoConstraints = false
            self.view.insertSubview(viewController.view, at: 0)
            self.view.pinAllSidesToSides(of: viewController.view)
        } else {
            let predicate = mode.predicate(with: ownedCryptoId)
            let contactsTVC = ContactsTableViewController(showOwnedIdentityWithCryptoId: nil, disableContactsWithoutDevice: false)
            contactsTVC.predicate = predicate
            contactsTVC.delegate = self
            contactsTVC.extraBottomInset = 56 + 16 // Fab height plus bottom margin
            navigationItem.searchController = contactsTVC.searchController
            viewController = contactsTVC
            viewController.willMove(toParent: self)
            self.addChild(viewController)
            viewController.didMove(toParent: self)
            viewController.view.frame = self.view.bounds
            self.view.insertSubview(viewController.view, at: 0)
        }
        
        navigationItem.hidesSearchBarWhenScrolling = false
    }
    
    
    /// This method is used when deeplinks need to navigate through the hierarchy
    func selectRowOfContactIdentity(_ contactIdentity: PersistedObvContactIdentity) {
        if let vc = children.first as? ContactsTableViewController {
            vc.selectRowOfContactIdentity(contactIdentity)
        } else if #available(iOS 13.0, *) {
            if let vc = children.first as? MultipleContactsHostingViewController {
                vc.selectRowOfContactIdentity(contactIdentity)
            }
        }
        
    }

}

// MARK: - MultipleContactsHostingViewController

@available(iOS 13.0, *)
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
    
    func userDidSelectOwnedIdentity() {
        delegate?.userDidSelectOwnedIdentity()
    }
    
    func userDidSelect(_ contact: PersistedObvContactIdentity) {
        delegate?.userDidSelect(contact, within: self.navigationController)
    }
    
    func userDidDeselect(_ contact: PersistedObvContactIdentity) {
        delegate?.userDidDeselect(contact)
    }
    
}


// MARK: - OwnedIdentityViewDelegate

extension AllContactsViewController: OwnedIdentityViewDelegate {
    
    func ownedIdentityViewWasSelected() {
        delegate?.userDidSelectOwnedIdentity()
    }
    
}


// MARK: - CanScrollToTop

extension AllContactsViewController: CanScrollToTop {
    
    func scrollToTop() {
        if let vc = children.first as? ContactsTableViewController {
            guard vc.tableView.numberOfSections > 0 && vc.tableView.numberOfRows(inSection: 0) > 0 else { return }
            vc.tableView.scrollToRow(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
        } else if #available(iOS 13.0, *) {
            if let vc = children.first as? MultipleContactsHostingViewController {
                vc.scrollToTop()
            }
        }
    }
    
}
