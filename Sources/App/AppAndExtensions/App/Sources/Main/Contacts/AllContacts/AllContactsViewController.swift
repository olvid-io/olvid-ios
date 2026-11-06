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

import CoreData
import OSLog
import ObvUI
import ObvTypes
import UIKit
import SwiftUI
import ObvUICoreData
import ObvSettings
import ObvDesignSystem
import ObvSystemIcon
import ObvSharedDataSources
import ObvOwnedIdentityChooser
import ObvAppTypes
import ObvContactsSuggestions


final class AllContactsViewController: ShowOwnedIdentityButtonUIViewController, ViewControllerWithEllipsisCircleRightBarButtonItem {

    // Variables
    
    private var notificationTokens = [NSObjectProtocol]()
    private let oneToOneStatusOfListedContacts: PersistedObvContactIdentity.OneToOneStatus
    private let showExplanation: Bool
    private var viewDidLoadWasCalled = false
    private let avatarViewDataSource: ObvAvatarViewDataSource
    private let ownedIdentityChooserViewDataSource: OwnedIdentityChooserViewDataSource
    private let contactsSuggestionsViewDataSource: ContactsSuggestionsViewDataSource
    /// True for the copy presented for the other known users, which is given a close button in place of the profile picture, and false in the contacts tab.
    private let isPresentedWithACloseButton: Bool
    /// What leads to the contacts suggestions above the list: the entry above the one-to-one contacts, or the card above the other known users.
    private var contactsSuggestionsEntry: ContactsSuggestionsEntryState?
    /// Follows the deck of all the other known users, for the row of the card that opens it. Only the copy presented for them has one.
    private var allOtherKnownUsersDeckObservation: Task<Void, Never>?
    private var latestAllOtherKnownUsersDeck = ContactSuggestion.Deck.empty

    // Delegates
    
    weak var delegate: AllContactsViewControllerDelegate?
    
    // MARK: - Initializer
    
    init(ownedCryptoId: ObvCryptoId,
         whereOneToOneStatusIs oneToOneStatusOfListedContacts: PersistedObvContactIdentity.OneToOneStatus,
         title: String = CommonString.Word.Contacts,
         showExplanation: Bool,
         barButtonItemToShowInsteadOfProfilePicture: UIBarButtonItem? = nil,
         avatarViewDataSource: ObvAvatarViewDataSource,
         ownedIdentityChooserViewDataSource: OwnedIdentityChooserViewDataSource,
         contactsSuggestionsViewDataSource: ContactsSuggestionsViewDataSource
    ) {
        self.avatarViewDataSource = avatarViewDataSource
        self.ownedIdentityChooserViewDataSource = ownedIdentityChooserViewDataSource
        self.contactsSuggestionsViewDataSource = contactsSuggestionsViewDataSource
        self.oneToOneStatusOfListedContacts = oneToOneStatusOfListedContacts
        self.showExplanation = showExplanation
        self.isPresentedWithACloseButton = barButtonItemToShowInsteadOfProfilePicture != nil
        super.init(ownedCryptoId: ownedCryptoId,
                   logCategory: "AllContactsViewController",
                   barButtonItemToShowInsteadOfProfilePicture: barButtonItemToShowInsteadOfProfilePicture,
                   avatarViewDataSource: avatarViewDataSource,
                   ownedIdentityChooserViewDataSource: ownedIdentityChooserViewDataSource)
        self.title = title
        switch (oneToOneStatusOfListedContacts, isPresentedWithACloseButton) {
        case (.oneToOne, false):
            // The contacts flow follows the deck of the suggestions and shows this entry.
            self.contactsSuggestionsEntry = ContactsSuggestionsEntryState(kind: .entryAboveTheContacts) { [weak self] in
                guard let self else { return }
                delegate?.userWantsToSeeContactsSuggestions(self)
            }
        case (.nonOneToOne, true):
            self.contactsSuggestionsEntry = ContactsSuggestionsEntryState(kind: .cardAboveTheOtherKnownUsers) { [weak self] in
                guard let self else { return }
                delegate?.userWantsToSeeAllOtherKnownUsersSuggestions(self, initialDeck: latestAllOtherKnownUsersDeck)
            }
            observeAllOtherKnownUsersDeck()
        default:
            break
        }
        observeContactsSortOrderDidChangeNotifications()
    }


    /// Shows the row of the card that opens the deck of all the other known users while that deck has a card.
    private func observeAllOtherKnownUsersDeck() {
        let stream = contactsSuggestionsViewDataSource.deckStream(ownedCryptoId: currentOwnedCryptoId, scope: .allOtherKnownUsers)
        allOtherKnownUsersDeckObservation = Task { [weak self] in
            for await deck in stream {
                guard let self, !Task.isCancelled else { return }
                latestAllOtherKnownUsersDeck = deck
                setContactsSuggestionsEntryVisible(!deck.identifiers.isEmpty)
            }
        }
    }


    /// Shows the entry to the contacts suggestions while there is something to suggest, or the row of the card that opens the deck of all the other
    /// known users while that deck has a card.
    func setContactsSuggestionsEntryVisible(_ isVisible: Bool) {
        guard let contactsSuggestionsEntry, contactsSuggestionsEntry.isVisible != isVisible else { return }
        withAnimation {
            contactsSuggestionsEntry.isVisible = isVisible
        }
    }


    /// Repeats the badge of the tab on the entry, its count and its colour.
    func setContactsSuggestionsBadge(count: Int, hasANewCard: Bool) {
        guard let contactsSuggestionsEntry else { return }
        if contactsSuggestionsEntry.badgeCount != count {
            contactsSuggestionsEntry.badgeCount = count
        }
        if contactsSuggestionsEntry.hasANewCard != hasANewCard {
            contactsSuggestionsEntry.hasANewCard = hasANewCard
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        allOtherKnownUsersDeckObservation?.cancel()
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
        
        switch oneToOneStatusOfListedContacts {
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
    
    
    func presentViewControllerOfAllNonOneToOneContacts() {
        assert(Thread.isMainThread)
        
        let barButtonItem: UIBarButtonItem
        if #available(iOS 26, *) {
            barButtonItem = UIBarButtonItem(image: UIImage(systemIcon: .xmark), style: .plain, target: self, action: #selector(dismissViewControllerOfAllNonOneToOneContacts))
        } else {
            barButtonItem = UIBarButtonItem(image: UIImage(systemIcon: .xmarkCircleFill), style: .plain, target: self, action: #selector(dismissViewControllerOfAllNonOneToOneContacts))
            barButtonItem.tintColor = AppTheme.shared.colorScheme.olvidLight
        }

        let vc = AllContactsViewController(ownedCryptoId: currentOwnedCryptoId,
                                           whereOneToOneStatusIs: .nonOneToOne,
                                           title: NSLocalizedString("OTHER_KNOWN_USERS", comment: ""),
                                           showExplanation: false,
                                           barButtonItemToShowInsteadOfProfilePicture: barButtonItem,
                                           avatarViewDataSource: self.avatarViewDataSource,
                                           ownedIdentityChooserViewDataSource: self.ownedIdentityChooserViewDataSource,
                                           contactsSuggestionsViewDataSource: self.contactsSuggestionsViewDataSource)
        vc.delegate = self.delegate
        vc.unlockingHiddenProfileDelegate = self.unlockingHiddenProfileDelegate
                
        let nav = UINavigationController(rootViewController: vc)
        self.present(nav, animated: true)
    }
    
    @objc
    private func dismissViewControllerOfAllNonOneToOneContacts() {
        presentedViewController?.dismiss(animated: true)
    }


    // MARK: - The Esc key

    /// Esc leaves a search first, and otherwise closes the screen as its close button does. Offered only by the copy presented for the other known users; in the
    /// contacts tab there is nothing to close. This screen is UIKit throughout, its close button a bar item, so no SwiftUI shortcut can carry the key. The
    /// selector is named after this class, UIKit sending a key command's action to the first responder in the chain that implements it rather than to the
    /// controller that offered it.
    override var keyCommands: [UIKeyCommand]? {
        guard isPresentedWithACloseButton else { return super.keyCommands }
        return (super.keyCommands ?? []) + [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(allContactsAnswersTheEscapeKey))]
    }

    @objc private func allContactsAnswersTheEscapeKey() {
        if let searchController = navigationItem.searchController, searchController.isActive || !(searchController.searchBar.text ?? "").isEmpty {
            searchController.searchBar.text = ""
            searchController.isActive = false
        } else {
            dismiss(animated: true)
        }
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
            textAboveUserList: nil,
            selectionStyle: .checkmark,
            contactsSuggestionsEntry: contactsSuggestionsEntry)
        let configuration = HorizontalAndVerticalUsersViewConfiguration(
            verticalConfiguration: verticalConfiguration,
            horizontalConfiguration: nil,
            buttonConfiguration: nil)
        
        let viewController = MultipleUsersHostingViewController(
            ownedCryptoId: currentOwnedCryptoId,
            mode: .all(oneToOneStatus: oneToOneStatusOfListedContacts, requiredCapabilitites: nil),
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
