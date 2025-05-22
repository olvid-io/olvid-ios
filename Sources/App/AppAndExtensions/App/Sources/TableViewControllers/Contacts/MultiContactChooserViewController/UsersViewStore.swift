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

import SwiftUI
import Combine
import CoreData
import ObvTypes
import ObvUICoreData
import ObvSettings
import ObvSystemIcon
import ObvUIObvCircledInitials


protocol ContactsViewStoreDelegate: AnyObject {
    @MainActor func userWantsToSeeContactDetails(of contact: PersistedObvContactIdentity)
}


@MainActor
final class UsersViewStore: NSObject, ObservableObject, VerticalUsersViewModelProtocol, HorizontalAndVerticalUsersViewModelProtocol {

    @Published var users = [PersistedUser]()
    @Published var selectedUsers = Set<PersistedUser>()
    @Published var selectedUsersOrdered = [PersistedUser]()
    @Published var searchInProgress: Bool = false
    @Published var userToScrollTo: PersistedUser? = nil
    @Published var scrollToTop: Bool = false
    //@Published var nsFetchRequest: NSFetchRequest<PersistedObvContactIdentity>
    @Published var showSortingSpinner: Bool = false
    @Published var tappedUser: PersistedUser? = nil
    let configuration: HorizontalAndVerticalUsersViewConfigurationProtocol
    private var notificationTokens = [NSObjectProtocol]()
    private let ownedCryptoId: ObvCryptoId
    private let mode: MultipleUsersHostingViewController.Mode
    private let groupMembersMode: MultipleUsersHostingViewController.GroupMembersMode

    private let initialPredicateForContacts: NSPredicate
    private let initialPredicateForGroupMembers: NSPredicate?
    
    private let frcForContacts: NSFetchedResultsController<PersistedObvContactIdentity>
    private let frcForGroupMembers: NSFetchedResultsController<PersistedGroupV2Member>?

    weak var delegate: ContactsViewStoreDelegate?
    
    init(ownedCryptoId: ObvCryptoId, mode: MultipleUsersHostingViewController.Mode, groupMembersMode: MultipleUsersHostingViewController.GroupMembersMode, configuration: HorizontalAndVerticalUsersViewConfigurationProtocol) {

        self.ownedCryptoId = ownedCryptoId

        self.mode = mode
        self.initialPredicateForContacts = mode.predicate(with: ownedCryptoId)
        let fetchRequestForContacts = PersistedObvContactIdentity.getFetchRequestForAllContactsOfOwnedIdentity(
            with: ownedCryptoId,
            predicate: self.initialPredicateForContacts,
            whereOneToOneStatusIs: mode.oneToOneStatus)
        self.frcForContacts = NSFetchedResultsController(fetchRequest: fetchRequestForContacts, managedObjectContext: ObvStack.shared.viewContext, sectionNameKeyPath: nil, cacheName: nil)

        self.groupMembersMode = groupMembersMode
        self.initialPredicateForGroupMembers = groupMembersMode.predicate(with: ownedCryptoId)
        if let initialPredicateForGroupMembers {
            let fetchRequestForGroupMembers = PersistedGroupV2Member.getFetchRequest(withPredicate: initialPredicateForGroupMembers)
            self.frcForGroupMembers = NSFetchedResultsController(fetchRequest: fetchRequestForGroupMembers, managedObjectContext: ObvStack.shared.viewContext, sectionNameKeyPath: nil, cacheName: nil)
        } else {
            self.frcForGroupMembers = nil
        }

        self.configuration = configuration
        
        super.init()
        
        self.frcForContacts.delegate = self
        self.frcForGroupMembers?.delegate = self

        try? self.frcForContacts.performFetch()
        try? self.frcForGroupMembers?.performFetch()

    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    
    /// Typically used to pre-select certain users when showing the user selection UI
    func resetSelectedUsers(to newSelectedUsers: Set<PersistedUser>) {
        self.selectedUsers = newSelectedUsers
        self.selectedUsersOrdered = newSelectedUsers.sorted()
    }


    /// This method allows to make sure that the contacts are properly sorted. It is only required for long list of contacts.
    /// Indeed, when the list is short, the change on the sort key performed by the sorting operations forces the request to update
    /// the loaded contacts and thus to display these contacts in the appropriate order. But with a long list of contact this is not enough.
    /// Since there is no way to force the request to refresh itself, we "hack" it here: when a new sort order is observed, we hide the list of contacts,
    /// and perform a search that is likely to return no result. Soon after we cancel the search and display the list again. This seems to work, but
    /// this is clearely an ugly hack.
    private func refreshFetchRequestWhenSortOrderChanges() {
        notificationTokens.append(ObvMessengerSettingsNotifications.observeContactsSortOrderDidChange { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                assert(Thread.isMainThread)
                withAnimation {
                    self.showSortingSpinner = true
                }
                try? await Task.sleep(milliseconds: 300)
                self.refreshFetchRequest(searchText: String(repeating: " ", count: 100))
                try? await Task.sleep(milliseconds: 300)
                self.refreshFetchRequest(searchText: nil)
                withAnimation {
                    self.showSortingSpinner = false
                }
            }
        })
    }


    func selectRowOfUser(_ user: PersistedUser) {
        self.userToScrollTo = user
        self.tappedUser = user
    }

    
    func scrollToTopNow() {
        self.scrollToTop.toggle()
    }
    
}


// MARK: - NSFetchedResultsControllerDelegate

extension UsersViewStore: NSFetchedResultsControllerDelegate {
 
    nonisolated
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {
        
        Task {
            await self.updateUsers()
        }
        
    }
    
    private func updateUsers() {
        
        let contacts = self.frcForContacts.fetchedObjects ?? []
        let usersFromContacts: [PersistedUser] = contacts.compactMap({ try? .init(contact: $0) })
        
        let groupMembers = self.frcForGroupMembers?.fetchedObjects ?? []
        let usersFromGroupMembers: [PersistedUser] = groupMembers.compactMap({ try? .init(groupMember: $0) })
        
        let users = (usersFromContacts + usersFromGroupMembers).sorted()
        
        withAnimation {
            self.users = users
        }
    }
    

}



// MARK: - VerticalUsersViewActionsProtocol

extension UsersViewStore: VerticalUsersViewActionsProtocol {
    
    func userWantsToNavigateToSingleContactIdentityView(user: any ManagedUserViewForVerticalUsersLayoutModelProtocol) {
        guard let user = user as? PersistedUser else { assertionFailure(); return }
        switch user.kind {
        case .contact(contact: let contact):
            assert(delegate != nil)
            delegate?.userWantsToSeeContactDetails(of: contact)
        case .groupMember(groupMember: _):
            assertionFailure()
        }
    }

    
    func userDidToggleSelectionOfUser(_ user: any ManagedUserViewForVerticalUsersLayoutModelProtocol, newIsSelected: Bool) async {
        guard let user = user as? PersistedUser else { assertionFailure(); return }
        if newIsSelected {
            selectedUsers.insert(user)
            if selectedUsersOrdered.first(where: { $0.cryptoId == user.cryptoId }) == nil {
                selectedUsersOrdered.insert(user, at: 0)
            }
        } else {
            selectedUsers.remove(user)
            selectedUsersOrdered.removeAll(where: { $0.cryptoId == user.cryptoId })
        }
    }

}




// MARK: - UISearchResultsUpdating

extension UsersViewStore: UISearchResultsUpdating {
    
    public func updateSearchResults(for searchController: UISearchController) {
        if let searchedText = searchController.searchBar.text, !searchedText.isEmpty {
            refreshFetchRequest(searchText: searchedText)
        } else {
            refreshFetchRequest(searchText: nil)
        }
        self.searchInProgress = searchController.isActive
    }

    
    private func refreshFetchRequest(searchText: String?) {
        refreshFetchRequestForContacts(searchText: searchText)
        refreshFetchRequestForGroupMembers(searchText: searchText)
    }
    
    
    private func refreshFetchRequestForContacts(searchText: String?) {
        
        var andPredicates: [NSPredicate] = [initialPredicateForContacts]
        
        if let searchText {
            let searchPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K != nil", PersistedObvContactIdentity.Predicate.Key.sortDisplayName.rawValue),
                NSPredicate(format: "%K contains[cd] %@", PersistedObvContactIdentity.Predicate.Key.sortDisplayName.rawValue, searchText),
            ])
            andPredicates.append(searchPredicate)
        }

        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
        
        self.frcForContacts.fetchRequest.predicate = finalPredicate

        do {
            try frcForContacts.performFetch()
        } catch {
            assertionFailure()
        }

    }
    
    
    private func refreshFetchRequestForGroupMembers(searchText: String?) {
        
        guard let initialPredicateForGroupMembers, let frcForGroupMembers else { return }
        
        var andPredicates: [NSPredicate] = [initialPredicateForGroupMembers]
        
        if let searchText {
            let searchPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K != nil", PersistedGroupV2Member.Predicate.Key.normalizedSearchKey.rawValue),
                NSPredicate(format: "%K contains[cd] %@", PersistedGroupV2Member.Predicate.Key.normalizedSearchKey.rawValue, searchText),
            ])
            andPredicates.append(searchPredicate)
        }

        let finalPredicate = NSCompoundPredicate(andPredicateWithSubpredicates: andPredicates)
        
        frcForGroupMembers.fetchRequest.predicate = finalPredicate

        do {
            try frcForGroupMembers.performFetch()
        } catch {
            assertionFailure()
        }

    }

}




// MARK: - HorizontalAndVerticalUsersViewActionsProtocol

extension UsersViewStore: HorizontalAndVerticalUsersViewActionsProtocol {
    
    func userWantsToDeleteUser(cryptoId: ObvTypes.ObvCryptoId) async {
        guard let user = users.first(where: { $0.cryptoId == cryptoId }) else { assertionFailure(); return }
        await userDidToggleSelectionOfUser(user, newIsSelected: false)
    }
    
}


// MARK: - Helper structs for passing configurations

struct VerticalUsersViewConfiguration: VerticalUsersViewConfigurationProtocol {
    let showExplanation: Bool
    let disableUsersWithoutDevice: Bool
    let allowMultipleSelection: Bool
    let textAboveUserList: String?
    let selectionStyle: SelectionStyle
}

struct HorizontalUsersViewConfiguration: HorizontalUsersViewConfigurationProtocol {
    let textOnEmptySetOfUsers: String
    let canEditUsers: Bool
}

struct HorizontalAndVerticalUsersViewButtonConfiguration: HorizontalAndVerticalUsersViewButtonConfigurationProtocol {
    let title: String
    let systemIcon: ObvSystemIcon.SystemIcon
    let action: (Set<ObvTypes.ObvCryptoId>) -> Void
    let allowEmptySetOfContacts: Bool
}

struct HorizontalAndVerticalUsersViewConfiguration: HorizontalAndVerticalUsersViewConfigurationProtocol {
    let verticalConfiguration: any VerticalUsersViewConfigurationProtocol
    let horizontalConfiguration: (any HorizontalUsersViewConfigurationProtocol)?
    let buttonConfiguration: (any HorizontalAndVerticalUsersViewButtonConfigurationProtocol)?
}


// MARK: - PersistedUser implements ManagedContactViewForVerticalContactsLayoutModelProtocol and SingleContactViewForHorizontalContactsLayoutModelProtocol

extension PersistedUser: SingleUserViewForHorizontalUsersLayoutModelProtocol {
    
    var cryptoId: ObvTypes.ObvCryptoId {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.cryptoId
        case .groupMember(groupMember: let groupMember):
            return groupMember.cryptoId
        }
    }
    
    var firstName: String? {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.firstName
        case .groupMember(groupMember: let groupMember):
            return groupMember.firstName
        }
    }
    
    var lastName: String? {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.lastName
        case .groupMember(groupMember: let groupMember):
            return groupMember.lastName
        }
    }
    
}


extension PersistedUser: ManagedUserViewForVerticalUsersLayoutModelProtocol {
    
    var userHasNoDevice: Bool {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.userHasNoDevice
        case .groupMember(groupMember: let groupMember):
            return groupMember.userHasNoDevice
        }
    }
    
    
    var atLeastOneDeviceAllowsThisUserToReceiveMessages: Bool {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.atLeastOneDeviceAllowsThisUserToReceiveMessages
        case .groupMember(groupMember: let groupMember):
            return groupMember.atLeastOneDeviceAllowsThisUserToReceiveMessages
        }
    }

    
    var detailsStatus: UserCellViewTypes.UserDetailsStatus {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.detailsStatus
        case .groupMember(groupMember: let groupMember):
            return groupMember.detailsStatus
        }
    }
    
    var contactHasNoDevice: Bool {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.contactHasNoDevice
        case .groupMember(groupMember: let groupMember):
            return groupMember.contactHasNoDevice
        }
    }
    
    var isActive: Bool {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.isActive
        case .groupMember(groupMember: let groupMember):
            return groupMember.isActive
        }
    }
    
    var atLeastOneDeviceAllowsThisContactToReceiveMessages: Bool {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.atLeastOneDeviceAllowsThisContactToReceiveMessages
        case .groupMember(groupMember: let groupMember):
            return groupMember.atLeastOneDeviceAllowsThisContactToReceiveMessages
        }
    }
    
    var customDisplayName: String? {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.customDisplayName
        case .groupMember(groupMember: let groupMember):
            return groupMember.customDisplayName
        }
    }
    
    var displayedPosition: String? {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.displayedPosition
        case .groupMember(groupMember: let groupMember):
            return groupMember.displayedPosition
        }
    }
    
    var displayedCompany: String? {
        switch self.kind {
        case .contact(contact: let contact):
            return contact.displayedCompany
        case .groupMember(groupMember: let groupMember):
            return groupMember.displayedCompany
        }
    }
    
}

// MARK: - PersistedObvContactIdentity implements ManagedContactViewForVerticalContactsLayoutModelProtocol and SingleContactViewForHorizontalContactsLayoutModelProtocol

extension PersistedObvContactIdentity: SingleUserViewForHorizontalUsersLayoutModelProtocol {}
extension PersistedObvContactIdentity: ManagedUserViewForVerticalUsersLayoutModelProtocol {}


// MARK: - PersistedGroupV2Member implements ManagedContactViewForVerticalContactsLayoutModelProtocol and SingleContactViewForHorizontalContactsLayoutModelProtocol

extension PersistedGroupV2Member: ManagedUserViewForVerticalUsersLayoutModelProtocol, SingleUserViewForHorizontalUsersLayoutModelProtocol {
    
    var cryptoId: ObvTypes.ObvCryptoId {
        self.forcedUnwrapCryptoId
    }
    
    var detailsStatus: UserCellViewTypes.UserDetailsStatus {
        return .noNewPublishedDetails
    }
    
    var contactHasNoDevice: Bool {
        return false
    }
    
    var isActive: Bool {
        return true
    }
    
    var atLeastOneDeviceAllowsThisContactToReceiveMessages: Bool {
        return true
    }
    
    var customDisplayName: String? {
        return nil
    }
    
    var userHasNoDevice: Bool {
        return false
    }
    
    var atLeastOneDeviceAllowsThisUserToReceiveMessages: Bool {
        return true
    }

}
