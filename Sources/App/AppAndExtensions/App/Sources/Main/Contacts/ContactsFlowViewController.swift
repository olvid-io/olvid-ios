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
import ObvUICoreData
import ObvAppCoreConstants
import ObvUIGroupV1
import ObvUIGroupV2
import ObvSharedDataSources
import ObvSingleContact
import ObvAppNavigation
import ObvContactsSuggestions
import ObvSettings
import SwiftUI


final class ContactsFlowViewController: ObvFlowController {
        
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "ContactsFlowViewController")
    private let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ContactsFlowViewController.self))

    private var observationTokens = [NSObjectProtocol]()

    /// Follows the contacts suggestions of the current owned identity, for the entry above the list and the badge of this tab.
    private var contactsSuggestionsObservation: Task<Void, Never>?
    private var latestContactsSuggestionsDeck = ContactSuggestion.Deck.empty
    /// Decided by each deck the stream sends, never by the empty deck shown until the first one arrives.
    private var isContactsSuggestionsEntryVisible = false
    /// The actions of the screen of suggestions. Created once, and kept for as long as this flow: see ``ContactsSuggestionsAppActions``.
    private let contactsSuggestionsActions: ContactsSuggestionsAppActions

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, dataSources: ObvDataSources) {
        
        self.contactsSuggestionsActions = ContactsSuggestionsAppActions(obvEngine: obvEngine)
        
        super.init(ownedCryptoId: ownedCryptoId, obvEngine: obvEngine, dataSources: dataSources, doAddFloatingButton: true)

        contactsSuggestionsActions.delegate = self
        
        let allContactsVC = AllContactsViewController(ownedCryptoId: ownedCryptoId,
                                                      whereOneToOneStatusIs: .oneToOne,
                                                      showExplanation: true,
                                                      avatarViewDataSource: dataSources.avatarViewDataSource,
                                                      ownedIdentityChooserViewDataSource: dataSources.ownedIdentityChooserViewDataSource,
                                                      contactsSuggestionsViewDataSource: dataSources.contactsSuggestionsViewDataSource)
        
        allContactsVC.delegate = self
        allContactsVC.unlockingHiddenProfileDelegate = self
        
        self.setViewControllers([allContactsVC], animated: false)

        observeContactsSuggestions()

    }

    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        contactsSuggestionsObservation?.cancel()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("die") }

    // MARK: - Switching current owned identity

    override func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId) {
        // The suggestions on screen belong to the profile we are leaving.
        if presentedViewController is ContactsSuggestionsNavigationController {
            dismiss(animated: false)
        }
        popToRootViewController(animated: false)
        self.currentOwnedCryptoId = newOwnedCryptoId
        guard let allContactsVC = viewControllers.first as? AllContactsViewController else { assertionFailure(); return }
        allContactsVC.switchCurrentOwnedCryptoId(to: newOwnedCryptoId)
        observeContactsSuggestions()
    }
        
}


// MARK: - View controller lifecycle

extension ContactsFlowViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = CommonString.Word.Contacts
        
        if #available(iOS 18, *) {
            // The tabbar is configured with iOS 18 APIs, we don't need to specify a tabBarItem
        } else {
            let image = UIImage(systemIcon: .person)
            tabBarItem = UITabBarItem(title: String(localized: "Contacts"), image: image, tag: 1)
            // A new item has no badge, and the suggestions may have been counted before this view loaded.
            applyContactsSuggestionsBadge()
        }

        if #available(iOS 26, *) {
            // We don't change the appearance under iOS 26
        } else {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            navigationBar.standardAppearance = appearance
        }
        
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

extension ContactsFlowViewController: UIGestureRecognizerDelegate {
    
    /// This is only used under iOS18+, in order to be the delegate of the `interactivePopGestureRecognizer`, allowing to activate the interactive pop gesture recognizer.
    /// See ``https://stackoverflow.com/questions/18946302/uinavigationcontroller-interactive-pop-gesture-not-working``.
    @objc func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return theInteractivePopMayBegin()
    }
    
}

// MARK: - AllContactsViewControllerDelegate

extension ContactsFlowViewController: AllContactsViewControllerDelegate {

    func userDidSelectContact(_ vc: AllContactsViewController, withContactIdentifier contactIdentifier: ObvContactIdentifier, within navigationController: UINavigationController?) {
        assert(navigationController == nil || navigationController == self || self.presentedViewController == navigationController, "We simplified the underlying API. The navigationController is now discarded.")
        self.userWantsToNavigateToSingleContactView(contactIdentifier: contactIdentifier)
    }

    func userDidDeselectContact(_ vc: AllContactsViewController, withContactIdentifier contactIdentifier: ObvContactIdentifier) {
        // We do nothing
    }

    func userWantsToSeeContactsSuggestions(_ vc: AllContactsViewController) {
        presentContactsSuggestions(scope: .suggestions, initialDeck: latestContactsSuggestionsDeck)
    }


    /// The list of the other known users goes first, and the deck opens over the contacts tab, as the other deck does. Opened over that list, it would
    /// hide the details of a contact: the router pushes them onto the first navigation controller presented, which would be the list.
    func userWantsToSeeAllOtherKnownUsersSuggestions(_ vc: AllContactsViewController, initialDeck: ContactSuggestion.Deck) {
        dismiss(animated: true) { [weak self] in
            self?.presentContactsSuggestions(scope: .allOtherKnownUsers, initialDeck: initialDeck)
        }
    }

    @objc
    func dismissPresentedViewController() {
        presentedViewController?.dismiss(animated: true)
    }

}


// MARK: - Contacts suggestions

extension ContactsFlowViewController {
    
    /// Follows the deck of the current owned identity: the entry above the list and the badge of the tab show from enough cards, and stay until the
    /// deck is empty.
    private func observeContactsSuggestions() {
        contactsSuggestionsObservation?.cancel()
        latestContactsSuggestionsDeck = .empty
        isContactsSuggestionsEntryVisible = false
        applyContactsSuggestionsDeck()
        let ownedCryptoId = currentOwnedCryptoId
        let stream = dataSources.contactsSuggestionsViewDataSource.deckStream(ownedCryptoId: ownedCryptoId, scope: .suggestions)
        contactsSuggestionsObservation = Task { [weak self] in
            for await deck in stream {
                guard let self else { return }
                // A deck of the profile we just left may still arrive after the switch: it must not reach the entry nor the badge.
                guard !Task.isCancelled, ownedCryptoId == currentOwnedCryptoId else { return }
                latestContactsSuggestionsDeck = deck
                let entryWasVisible = ObvMessengerSettings.ContactsSuggestions.entryIsShown(ownedCryptoId: ownedCryptoId)
                isContactsSuggestionsEntryVisible = deck.isEntryVisible(entryWasVisible: entryWasVisible)
                ObvMessengerSettings.ContactsSuggestions.setEntryIsShown(isContactsSuggestionsEntryVisible, ownedCryptoId: ownedCryptoId)
                applyContactsSuggestionsDeck()
            }
        }
    }


    private func applyContactsSuggestionsDeck() {
        applyContactsSuggestionsBadge()
        (viewControllers.first as? AllContactsViewController)?.setContactsSuggestionsEntryVisible(isContactsSuggestionsEntryVisible)
    }


    /// Badges the tab and the entry, and passes the badge on for the sidebar, which shows instead of the tabs in a regular width. The badge is red
    /// while the deck holds a card the user has not seen in an opened deck, and grey otherwise.
    private func applyContactsSuggestionsBadge() {
        let badgeCount = latestContactsSuggestionsDeck.badgeCount(isEntryVisible: isContactsSuggestionsEntryVisible)
        let hasANewCard = latestContactsSuggestionsDeck.hasANewCard
        let badgeValue = badgeCount > 0 ? "\(badgeCount)" : nil
        let badgeColor: UIColor = hasANewCard ? .systemRed : .systemGray
        if tabBarItem.badgeValue != badgeValue || tabBarItem.badgeColor != badgeColor {
            tabBarItem.badgeColor = badgeColor
            tabBarItem.badgeValue = badgeValue
        }
        (viewControllers.first as? AllContactsViewController)?.setContactsSuggestionsBadge(count: badgeCount, hasANewCard: hasANewCard)
        flowDelegate?.contactsSuggestionsBadgeWasRecounted(self, badgeCount: badgeCount, hasANewCard: hasANewCard)
    }
    
    
    /// Presents the deck of `scope` in a sheet with a navigation controller of its own, which is where the details of a contact are pushed: the
    /// navigation router pushes onto a navigation controller this one presents.
    private func presentContactsSuggestions(scope: ContactSuggestion.Scope, initialDeck: ContactSuggestion.Deck) {
        // A second tap while the sheet is coming up, or a tap as another sheet goes away: UIKit would refuse the presentation, and the code that
        // closes the suggestions expects them to be presented by this controller.
        guard presentedViewController == nil else { return }
        let rootView = ContactsSuggestionsView(
            ownedCryptoId: currentOwnedCryptoId,
            scope: scope,
            initialDeck: initialDeck,
            showsOnboarding: !ObvMessengerSettings.ContactsSuggestions.onboardingWasShown,
            dataSources: dataSources.contactsSuggestionsViewDataSources,
            actions: contactsSuggestionsActions)
        let hostingController = UIHostingController(rootView: rootView)
        let navigationController = ContactsSuggestionsNavigationController(rootViewController: hostingController)
        navigationController.modalPresentationStyle = .pageSheet
        if let sheet = navigationController.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        present(navigationController, animated: true)
    }
    
}


// MARK: - ContactsSuggestionsAppActionsDelegate

extension ContactsFlowViewController: ContactsSuggestionsAppActionsDelegate {
    
    func userWantsToInviteContact(_ actions: ContactsSuggestionsAppActions, contactIdentifier: ObvContactIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToInviteContactsToOneToOne(self, ownedCryptoId: contactIdentifier.ownedCryptoId, users: [(contactIdentifier.contactCryptoId, nil)])
    }
    
    
    func userWantsToStopSuggestingContact(_ actions: ContactsSuggestionsAppActions, contactIdentifier: ObvContactIdentifier) async throws {
        guard let flowDelegate else { assertionFailure(); throw ObvFlowControllerError.delegateIsNil }
        try await flowDelegate.userWantsToStopSuggestingContact(self, contactIdentifier: contactIdentifier)
    }
    
    
    func contactSuggestionsWereSeen(_ actions: ContactsSuggestionsAppActions, ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, invitationUUIDs: Set<UUID>) {
        flowDelegate?.contactSuggestionsWereSeen(self, ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, invitationUUIDs: invitationUUIDs)
    }
    
    
    func userWantsToSeeDetails(_ actions: ContactsSuggestionsAppActions, of contactIdentifier: ObvContactIdentifier) {
        userWantsToNavigateToSingleContactView(contactIdentifier: contactIdentifier)
    }
    
    
    func userWantsToSeeOtherKnownUsers(_ actions: ContactsSuggestionsAppActions) {
        guard let allContactsVC = viewControllers.first as? AllContactsViewController else { assertionFailure(); return }
        dismiss(animated: true) {
            allContactsVC.presentViewControllerOfAllNonOneToOneContacts()
        }
    }
    
    
    func userWantsToClose(_ actions: ContactsSuggestionsAppActions) {
        dismiss(animated: true)
    }
    
}


// MARK: - ContactsSuggestionsNavigationController

/// The navigation controller of the suggestions sheet, a type of its own so the flow can tell it apart from anything else it presents.
private final class ContactsSuggestionsNavigationController: UINavigationController {}
