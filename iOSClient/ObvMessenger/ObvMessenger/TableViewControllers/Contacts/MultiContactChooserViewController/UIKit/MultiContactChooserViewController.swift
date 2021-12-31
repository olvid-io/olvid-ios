/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import ObvEngine

class MultiContactChooserViewController: UIViewController {

    // Views
    
    private var contactsTVC: ContactsTableViewController!
    
    // Vars
    
    let ownedCryptoId: ObvCryptoId
    var customSelectionStyle = ContactsTableViewController.CustomSelectionStyle.checkmark
    private let mode: MultipleContactsMode
    private let disableContactsWithoutDevice: Bool

    weak var delegate: MultiContactChooserViewControllerDelegate?
    
    // Initializer
    
    init(ownedCryptoId: ObvCryptoId, mode: MultipleContactsMode, disableContactsWithoutDevice: Bool) {
        self.ownedCryptoId = ownedCryptoId
        self.mode = mode
        self.disableContactsWithoutDevice = disableContactsWithoutDevice
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}


// MARK: - View Controller Lifecycle

extension MultiContactChooserViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        definesPresentationContext = true
        setup()
    }
    
    
    private func setup() {
        
        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        
        contactsTVC = ContactsTableViewController(showOwnedIdentityWithCryptoId: nil, disableContactsWithoutDevice: disableContactsWithoutDevice, allowDeletion: false)
        contactsTVC.predicate = mode.predicate(with: ownedCryptoId)
        contactsTVC.view.translatesAutoresizingMaskIntoConstraints = false
        contactsTVC.tableView.allowsMultipleSelection = true
        contactsTVC.customSelectionStyle = self.customSelectionStyle
        contactsTVC.delegate = self
        contactsTVC.willMove(toParent: self)
        navigationItem.searchController = contactsTVC.searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        self.addChild(contactsTVC)
        contactsTVC.didMove(toParent: self)
        view.addSubview(contactsTVC.view)
        
        setupConstraints()
    }
    
    
    private func setupConstraints() {
        let guide = view.safeAreaLayoutGuide
        let constraints = [
            contactsTVC.view.topAnchor.constraint(equalTo: guide.topAnchor, constant: 0),
            contactsTVC.view.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 0),
            contactsTVC.view.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: 0),
            contactsTVC.view.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: 0),
        ]
        NSLayoutConstraint.activate(constraints)
    }

}


// MARK: - ContactsTableViewControllerDelegate

extension MultiContactChooserViewController: ContactsTableViewControllerDelegate {
    
    func userDidSelect(_ contactIdentity: PersistedObvContactIdentity) {
        delegate?.userDidSelect(contactIdentity)
    }
    
    func userDidDeselect(_ contactIdentity: PersistedObvContactIdentity) {
        delegate?.userDidDeselect(contactIdentity)
    }
    
    func userDidSelectOwnedIdentity() {
        assertionFailure("Should never be called within this view controller")
    }
    
    func userWantsToDeleteContact(with: ObvCryptoId, forOwnedCryptoId: ObvCryptoId, completionHandler: @escaping (Bool) -> Void) {
        assertionFailure("Should never be called within this view controller")
    }
    
}
