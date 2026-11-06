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

import Foundation
import ObvTypes
import ObvDesignSystem


/// A card of the contacts suggestions deck.
public enum ContactSuggestion {

    /// Identifies a card. The deck streams these only, and asks for the ``Model`` of the few cards on screen.
    public enum Identifier: Hashable, Sendable {
        /// A user known through a group, not yet a one-to-one contact. Accepting invites them.
        case contact(ObvContactIdentifier)
        /// An invitation awaiting an answer: a one-to-one invitation received, or an introduction by a contact. Accepting accepts it.
        /// When it comes from a user already known through a group, this card replaces that user's ``contact(_:)`` card.
        /// `contactCryptoId` is the person the invitation is about: the one who invited us, or the one introduced to us, never the contact who
        /// introduced them. It is here so that what is done for that person needs no look-up of the invitation.
        case invitation(ownedCryptoId: ObvCryptoId, invitationUUID: UUID, contactCryptoId: ObvCryptoId)
        /// A one-to-one invitation we sent to a contact, still pending. Only the deck of all the other known users has such cards, so that the user
        /// finds there everyone that list shows. The right ("Uninvite") cancels the invitation; the left ("OK") changes nothing, as the left only
        /// skips cards on the others.
        case invitationSent(ownedCryptoId: ObvCryptoId, invitationUUID: UUID, contactCryptoId: ObvCryptoId)

        /// What answering the card does, which decides the titles and the colours of the buttons.
        enum Kind {
            case suggestion
            case invitationToAnswer
            case invitationSent
        }

        /// The profile this card belongs to.
        public var ownedCryptoId: ObvCryptoId {
            switch self {
            case .contact(let contactIdentifier): return contactIdentifier.ownedCryptoId
            case .invitation(let ownedCryptoId, _, _): return ownedCryptoId
            case .invitationSent(let ownedCryptoId, _, _): return ownedCryptoId
            }
        }

        var kind: Kind {
            switch self {
            case .contact: return .suggestion
            case .invitation: return .invitationToAnswer
            case .invitationSent: return .invitationSent
            }
        }

        /// The person this card is about. The deck holds one card per person, but which card changes over time: a ``contact(_:)`` card becomes
        /// an ``invitation(ownedCryptoId:invitationUUID:contactCryptoId:)`` card when that person invites us, and one invitation may give way
        /// to another. The person stays the same.
        var personCryptoId: ObvCryptoId {
            switch self {
            case .contact(let contactIdentifier): return contactIdentifier.contactCryptoId
            case .invitation(_, _, let contactCryptoId): return contactCryptoId
            case .invitationSent(_, _, let contactCryptoId): return contactCryptoId
            }
        }

        func isAboutTheSamePerson(as other: Identifier) -> Bool {
            ownedCryptoId == other.ownedCryptoId && personCryptoId == other.personCryptoId
        }
    }


    /// Which people a deck offers.
    public enum Scope: Sendable {
        /// The deck of the contacts tab: the invitations awaiting an answer, then the people we can suggest. A person the user set aside, or who
        /// was removed from the one-to-one contacts, is not suggested.
        case suggestions
        /// The deck opened from the list of the other known users: the same invitations, then everyone who could be invited, including the people
        /// the user set aside and the people removed from the one-to-one contacts. This is how the user finds again somebody they swiped away. The
        /// people we invited are there too, as ``Identifier/invitationSent(ownedCryptoId:invitationUUID:contactCryptoId:)`` cards.
        case allOtherKnownUsers
    }


    /// What the deck shows: the cards, in order, and whether one of them is new, which decides the colour of the badge of the contacts tab.
    public struct Deck: Sendable, Equatable {
        public let identifiers: [Identifier]
        /// Whether one of the cards was not in the deck the last time the user opened it. The badge is then red, and grey otherwise.
        public let hasANewCard: Bool
        public init(identifiers: [Identifier], hasANewCard: Bool) {
            self.identifiers = identifiers
            self.hasANewCard = hasANewCard
        }
        public static let empty = Deck(identifiers: [], hasANewCard: false)

        /// How many cards it takes for the contacts tab to show the entry to the suggestions.
        static let numberOfCardsThatShowTheEntry = 3

        /// Whether the contacts tab shows the entry to the suggestions, given whether it showed it before this deck.
        ///
        /// The entry shows from ``numberOfCardsThatShowTheEntry`` cards, invitations included. Then it stays until the deck is empty: otherwise it
        /// would go in the middle of a swipe through the deck. After that, it shows again only from ``numberOfCardsThatShowTheEntry`` cards.
        public func isEntryVisible(entryWasVisible: Bool) -> Bool {
            if identifiers.count >= Self.numberOfCardsThatShowTheEntry {
                return true
            } else if identifiers.isEmpty {
                return false
            } else {
                return entryWasVisible
            }
        }

        /// The number on the badge of the contacts tab and of the entry: the number of cards while the entry shows, and 0, which hides the badge,
        /// otherwise.
        public func badgeCount(isEntryVisible: Bool) -> Int {
            isEntryVisible ? identifiers.count : 0
        }

        /// The same deck with the card of the person `identifier` is about moved to the front, when that person is still in it. That card is the
        /// deck's own, which may not be `identifier`: the person may have invited us since.
        func keepingOnTop(_ identifier: Identifier?) -> Deck {
            guard let identifier, let index = identifiers.firstIndex(where: { $0.isAboutTheSamePerson(as: identifier) }), index > 0 else { return self }
            var identifiers = self.identifiers
            let card = identifiers.remove(at: index)
            identifiers.insert(card, at: 0)
            return Deck(identifiers: identifiers, hasANewCard: hasANewCard)
        }

        /// Whether the deck still holds a card about the person `identifier` is about, whichever card it is.
        func hasACard(aboutTheSamePersonAs identifier: Identifier) -> Bool {
            identifiers.contains(where: { $0.isAboutTheSamePerson(as: identifier) })
        }
    }


    public struct Model: Sendable, Equatable {

        public enum Badge: Sendable, Equatable {
            case none
            case invitationReceived
            case introducedBy(mediatorName: String)
            case invitationSent
        }

        /// The groups the user shares with this person, as shown under their name.
        public struct CommonGroups: Sendable, Equatable {
            /// The picture of one group, with what identifies the group, as two groups may well have the same picture.
            public struct Picture: Sendable, Equatable, Identifiable {
                public let id: String
                public let avatar: ObvAvatarViewModel
                public init(id: String, avatar: ObvAvatarViewModel) {
                    self.id = id
                    self.avatar = avatar
                }
            }

            /// At most three, the first group first, overlapping under the person's name.
            public let pictures: [Picture]
            public let nameOfFirstGroup: String
            /// All the groups we share with this person, including the ones whose picture is shown.
            public let numberOfGroups: Int
            public init(pictures: [Picture], nameOfFirstGroup: String, numberOfGroups: Int) {
                self.pictures = Array(pictures.prefix(3))
                self.nameOfFirstGroup = nameOfFirstGroup
                self.numberOfGroups = numberOfGroups
            }
        }

        public let avatar: ObvAvatarViewModel
        public let name: String
        /// "Position @ Company", when known.
        public let positionAtCompany: String?
        public let badge: Badge
        public let commonGroups: CommonGroups?
        /// The contact whose details "More info" shows, or `nil` when there is no contact behind the card.
        public let contactForDetails: ObvContactIdentifier?

        public init(avatar: ObvAvatarViewModel, name: String, positionAtCompany: String?, badge: Badge, commonGroups: CommonGroups?, contactForDetails: ObvContactIdentifier?) {
            self.avatar = avatar
            self.name = name
            self.positionAtCompany = positionAtCompany
            self.badge = badge
            self.commonGroups = commonGroups
            self.contactForDetails = contactForDetails
        }

    }

}


// MARK: - Data source and actions

@MainActor
public protocol ContactsSuggestionsViewDataSource: AnyObject {
    /// The cards of the deck of `scope`, in order. A new value is sent whenever the deck changes.
    func deckStream(ownedCryptoId: ObvCryptoId, scope: ContactSuggestion.Scope) -> AsyncStream<ContactSuggestion.Deck>
    /// The model of one card, or `nil` when the card no longer exists.
    func model(for identifier: ContactSuggestion.Identifier) async -> ContactSuggestion.Model?
    /// The user's own picture, which the onboarding links to the people suggested.
    func ownedAvatar(ownedCryptoId: ObvCryptoId) async -> ObvAvatarViewModel?
}


@MainActor
public protocol ContactsSuggestionsViewActions: AnyObject {
    /// Swipe to the right, the right button or the → key: invite the user, or accept the invitation. For an invitation we sent, cancel it.
    func userAccepted(_ identifier: ContactSuggestion.Identifier) async throws
    /// Swipe to the left, the left button or the ← key: stop suggesting the user, or decline the invitation. For an invitation we sent, nothing.
    func userDeclined(_ identifier: ContactSuggestion.Identifier) async throws
    /// The deck appeared or went away, with these cards in it: they are no longer new. Called again when the deck appears again, for example after
    /// the details of a contact were shown; must be safe to receive twice.
    func cardsWereSeen(_ identifiers: [ContactSuggestion.Identifier])
    func userWantsToSeeDetails(of contactIdentifier: ObvContactIdentifier)
    func userWantsToSeeOtherKnownUsers()
    func userWantsToClose()
    /// The onboarding was shown and dismissed, by finishing it, skipping it, or closing the sheet over it: it is not to be shown again.
    func onboardingWasShown()
}
