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

class AllGroupsViewController: ShowOwnedIdentityButtonUIViewController, ViewControllerWithEllipsisCircleRightBarButtonItem {

    // Delegates
    
    weak var delegate: AllGroupsViewControllerDelegate?
    
    // MARK: - Initializer
    
    init(ownedCryptoId: ObvCryptoId) {
        super.init(ownedCryptoId: ownedCryptoId, logCategory: "AllGroupsViewController")
        self.title = CommonString.Word.Groups
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


// MARK: - View Controller Lifecycle

extension AllGroupsViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        addAndConfigureContactGroupsTableViewController()
        if #available(iOS 13, *) {

            var rightBarButtonItems = [UIBarButtonItem]()

            if #available(iOS 14, *) {
                let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem()
                rightBarButtonItems.append(ellipsisButton)
            } else {
                let ellipsisButton = getConfiguredEllipsisCircleRightBarButtonItem(selector: #selector(ellipsisButtonTappedSelector))
                rightBarButtonItems.append(ellipsisButton)
            }

            let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 20.0, weight: .bold)
            let image = UIImage(systemIcon: .plusCircle, withConfiguration: symbolConfiguration)
            let buttonItem = UIBarButtonItem(image: image, style: .plain, target: self, action: #selector(addContactGroupButtonItemTapped))
            buttonItem.tintColor = AppTheme.shared.colorScheme.olvidLight
            rightBarButtonItems.append(buttonItem)
            
            navigationItem.rightBarButtonItems = rightBarButtonItems

        } else {
            
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addContactGroupButtonItemTapped))
            
        }
    }
    
    
    @available(iOS, introduced: 13.0, deprecated: 14.0, message: "Used because iOS 13 does not support UIMenu on UIBarButtonItem")
    @objc private func ellipsisButtonTappedSelector() {
        ellipsisButtonTapped(sourceBarButtonItem: navigationItem.rightBarButtonItem)
    }

    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        extendedLayoutIncludesOpaqueBars = true
    }
    
    
    private func addAndConfigureContactGroupsTableViewController() {
        
        if #available(iOS 13.0, *) {
            let vc = ContactGroupsHostingViewController(ownedCryptoId: ownedCryptoId, delegate: self)
            vc.delegate = self
            navigationItem.searchController = vc.searchController
            vc.willMove(toParent: self)
            self.addChild(vc)
            vc.didMove(toParent: self)
            vc.view.translatesAutoresizingMaskIntoConstraints = false
            self.view.insertSubview(vc.view, at: 0)
            self.view.pinAllSidesToSides(of: vc.view)
        } else {
            let frc = PersistedContactGroup.getFetchedResultsControllerForAllContactGroupsOfOwnedIdentity(with: self.ownedCryptoId, within: ObvStack.shared.viewContext)
            let groupsTVC = ContactGroupsTableViewController(fetchedResultsController: frc)
            groupsTVC.delegate = self
            groupsTVC.willMove(toParent: self)
            self.addChild(groupsTVC)
            groupsTVC.didMove(toParent: self)
            groupsTVC.view.frame = self.view.bounds
            self.view.insertSubview(groupsTVC.view, at: 0)
        }
        
        navigationItem.hidesSearchBarWhenScrolling = false

    }
    
    /// This method is used when deeplinks need to navigate through the hierarchy
    func selectRowOfContactGroup(_ contactGroup: PersistedContactGroup) {
        if let vc = children.first as? ContactGroupsTableViewController {
            vc.selectRowOfContactGroup(contactGroup)
        } else if #available(iOS 13.0, *) {
            if let vc = children.first as? ContactGroupsHostingViewController {
                vc.selectRowOfContactGroup(contactGroup)
            }
        }
    }
}


// MARK: - Actions

extension AllGroupsViewController {
    
    @objc func addContactGroupButtonItemTapped() {
        delegate?.userWantsToAddContactGroup()
    }
    
}


// MARK: - ContactGroupsHostingViewControllerDelegate

@available(iOS 13.0, *)
extension AllGroupsViewController: ContactGroupsHostingViewControllerDelegate {
    
    func userWantsToSeeContactGroupDetails(of group: PersistedContactGroup) {
        delegate?.userDidSelect(group, within: navigationController)
    }

}


// MARK: - ContactGroupsTableViewControllerDelegate
extension AllGroupsViewController: ContactGroupsTableViewControllerDelegate {
    
    func userDidSelect(_ contactGroup: PersistedContactGroup) {
        delegate?.userDidSelect(contactGroup, within: navigationController)
    }
    
}


// MARK: - CanScrollToTop

extension AllGroupsViewController: CanScrollToTop {
    
    func scrollToTop() {
        if let vc = children.first as? ContactGroupsTableViewController {
            guard vc.tableView.numberOfSections > 0 && vc.tableView.numberOfRows(inSection: 0) > 0 else { return }
            vc.tableView.scrollToRow(at: IndexPath.init(row: 0, section: 0), at: .top, animated: true)
        } else if #available(iOS 13.0, *) {
            if let vc = children.first as? ContactGroupsHostingViewController {
                vc.scrollToTop()
            }
        }
    }
    
}
