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
import ObvEngine
import ObvTypes
import ObvUI
import ObvUICoreData
import SwiftUI
import ObvSystemIcon
import ObvDesignSystem
import ObvSettings
import ObvAppCoreConstants


final class MultipleUsersHostingViewController: UIHostingController<HorizontalAndVerticalUsersView<UsersViewStore>> {

    enum Mode {
        case restricted(to: Set<ObvCryptoId>, oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus)
        case excluded(from: Set<ObvCryptoId>, oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus, requiredCapabilitites: [ObvCapability]?)
        case all(oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus, requiredCapabilitites: [ObvCapability]?)
    }
    
    enum GroupMembersMode {
        case none
        case notContact(groupIdentifier: GroupV2Identifier)
    }
    
    /// To provide search, the parent of this view controller must use this `UISearchController` with an appropriate `navigationItem.searchController`.
    let searchController: UISearchController
    private let store: UsersViewStore
    
    private weak var delegate: MultipleContactsHostingViewControllerDelegate?
    
    init(ownedCryptoId: ObvCryptoId, mode: Mode, groupMembersMode: GroupMembersMode = .none, configuration: HorizontalAndVerticalUsersViewConfiguration, delegate: MultipleContactsHostingViewControllerDelegate?) {
        
        let store = UsersViewStore(ownedCryptoId: ownedCryptoId, mode: mode, groupMembersMode: groupMembersMode, configuration: configuration)
        self.store = store
        
        let searchController = UISearchController(searchResultsController: nil)
        searchController.searchResultsUpdater = store
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = true
        self.searchController = searchController

        let view = HorizontalAndVerticalUsersView(model: store, actions: store, configuration: configuration)
        
        super.init(rootView: view)
        
        definesPresentationContext = true

        store.delegate = self
        self.delegate = delegate
        
    }
    

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    

    func selectRowOfContactIdentity(_ contactIdentity: PersistedObvContactIdentity) {
        guard let user = store.users.first(where: { $0.cryptoId == contactIdentity.cryptoId }) else { assertionFailure(); return }
        store.selectRowOfUser(user)
    }

    
    func scrollToTop() {
        store.scrollToTopNow()
    }

    
    /// Access to the current ordered list of selected contacts and, in case of a group edition, of pending group members
    var orderedSelectedUsers: [PersistedUser] {
        store.selectedUsersOrdered
    }
    
    
    func resetSelectedUsers(to newSelectedUsers: Set<PersistedUser>) {
        store.resetSelectedUsers(to: newSelectedUsers)
    }
    
}


// MARK: - ContactsViewStoreDelegate

extension MultipleUsersHostingViewController: ContactsViewStoreDelegate {
    
    func userWantsToSeeContactDetails(of contact: PersistedObvContactIdentity) {
        assert(Thread.isMainThread)
        delegate?.userWantsToSeeContactDetails(of: contact)
    }

}


// MARK: - Extension for MultipleContactsHostingViewController.Mode

extension MultipleUsersHostingViewController.Mode {

    var oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus {
        switch self {
        case .restricted(to: _, oneToOneStatus: let oneToOneStatus),
                .excluded(from: _, oneToOneStatus: let oneToOneStatus, requiredCapabilitites: _),
                .all(oneToOneStatus: let oneToOneStatus, requiredCapabilitites: _):
            return oneToOneStatus
        }
    }

    
    func predicate(with ownedCryptoId: ObvCryptoId) -> NSPredicate {
        switch self {
        case .restricted(to: let restrictedToContactCryptoIds, oneToOneStatus: let oneToOneStatus):
            return PersistedObvContactIdentity.getPredicateForAllContactsOfOwnedIdentity(with: ownedCryptoId, restrictedToContactCryptoIds: restrictedToContactCryptoIds, whereOneToOneStatusIs: oneToOneStatus)
        case .excluded(from: let excludedContactCryptoIds, oneToOneStatus: let oneToOneStatus, requiredCapabilitites: let requiredCapabilitites):
            if excludedContactCryptoIds.isEmpty { /// Should be .all
                return PersistedObvContactIdentity.getPredicateForAllContactsOfOwnedIdentity(
                    with: ownedCryptoId,
                    whereOneToOneStatusIs: oneToOneStatus,
                    requiredCapabilities: requiredCapabilitites)
            } else {
                return PersistedObvContactIdentity.getPredicateForAllContactsOfOwnedIdentity(
                    with: ownedCryptoId,
                    excludedContactCryptoIds: excludedContactCryptoIds,
                    whereOneToOneStatusIs: oneToOneStatus,
                    requiredCapabilities: requiredCapabilitites ?? [])
            }
        case .all(oneToOneStatus: let oneToOneStatus, requiredCapabilitites: let requiredCapabilitites):
            return PersistedObvContactIdentity.getPredicateForAllContactsOfOwnedIdentity(
                with: ownedCryptoId,
                whereOneToOneStatusIs: oneToOneStatus,
                requiredCapabilities: requiredCapabilitites)
        }
    }
}


// MARK: - Extension for MultipleUsersHostingViewController.GroupMembersMode

extension MultipleUsersHostingViewController.GroupMembersMode {
    
    func predicate(with ownedCryptoId: ObvCryptoId) -> NSPredicate? {
        switch self {
        case .none:
            return nil
        case .notContact(groupIdentifier: let groupIdentifier):
            return PersistedGroupV2Member.getPredicateForAllPersistedGroupV2MemberWithNoAssociatedContactOfGroup(ownedCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier)
        }
    }
    
}
