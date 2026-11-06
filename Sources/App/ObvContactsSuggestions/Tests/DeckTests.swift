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

import XCTest
import ObvCrypto
import ObvTypes
@testable import ObvContactsSuggestions


final class DeckTests: XCTestCase {

    private static func cryptoId(_ hexString: String) -> ObvCryptoId {
        try! ObvCryptoId(identity: Data(hexString: hexString)!)
    }

    private static let ownedCryptoId = cryptoId("68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")
    private static let alice = cryptoId("68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")
    private static let bob = cryptoId("68747470733a2f2f7365727665722e6465762e6f6c7669642e696f00002d459c378a0bbc54c8be3e87e82d02347c046c4a50a6db25fe15751d8148671401054f3b14bbd7319a1f6d71746d6345332b92e193a9ea00880dd67b2f10352831")
    private static let carol = cryptoId("68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000089aebda5ddb3a59942d4fe6e00720b851af1c2d70b6e24e41ac8da94793a6eb70136a23bf11bcd1ccc244ab3477545cc5fee6c60c2b89b8ff2fb339f7ed2ff1f0a")

    private static func invitation(from person: ObvCryptoId, ownedCryptoId: ObvCryptoId = DeckTests.ownedCryptoId) -> ContactSuggestion.Identifier {
        .invitation(ownedCryptoId: ownedCryptoId, invitationUUID: UUID(), contactCryptoId: person)
    }

    private static func contact(_ person: ObvCryptoId) -> ContactSuggestion.Identifier {
        .contact(ObvContactIdentifier(contactCryptoId: person, ownedCryptoId: ownedCryptoId))
    }

    private let a = DeckTests.invitation(from: DeckTests.alice)
    private let b = DeckTests.invitation(from: DeckTests.bob)
    private let c = DeckTests.invitation(from: DeckTests.carol)

    func testTheCardOnTopStaysOnTopWhenTheDeckIsSortedAnew() {
        let deck = ContactSuggestion.Deck(identifiers: [a, b, c], hasANewCard: true)
        let kept = deck.keepingOnTop(c)
        XCTAssertEqual(kept.identifiers, [c, a, b])
        XCTAssertTrue(kept.hasANewCard)
    }

    func testAPersonNoLongerInTheDeckChangesNothing() {
        let deck = ContactSuggestion.Deck(identifiers: [a, b], hasANewCard: false)
        XCTAssertEqual(deck.keepingOnTop(c), deck)
        XCTAssertEqual(deck.keepingOnTop(nil), deck)
        XCTAssertEqual(deck.keepingOnTop(a), deck)
        XCTAssertFalse(deck.hasACard(aboutTheSamePersonAs: c))
        XCTAssertFalse(deck.hasACard(aboutTheSamePersonAs: Self.contact(Self.carol)))
    }

    /// Carol was suggested, and invites us while the reader is on her card: her card is now the invitation, and it stays on top.
    func testThePersonOnTopStaysOnTopWhenTheirCardBecomesAnInvitation() {
        let deck = ContactSuggestion.Deck(identifiers: [a, b, c], hasANewCard: false)
        let cardOnTop = Self.contact(Self.carol)
        XCTAssertTrue(deck.hasACard(aboutTheSamePersonAs: cardOnTop))
        XCTAssertEqual(deck.keepingOnTop(cardOnTop).identifiers, [c, a, b])
    }

    /// The invitation shown for Carol gives way to another one of hers: the new one takes the top.
    func testThePersonOnTopStaysOnTopWhenAnotherOfTheirInvitationsIsShown() {
        let cardOnTop = Self.invitation(from: Self.carol)
        let deck = ContactSuggestion.Deck(identifiers: [a, b, c], hasANewCard: false)
        XCTAssertNotEqual(cardOnTop, c)
        XCTAssertTrue(deck.hasACard(aboutTheSamePersonAs: cardOnTop))
        XCTAssertEqual(deck.keepingOnTop(cardOnTop).identifiers, [c, a, b])
    }

    /// Carol, whom we invited, is the same person whichever card the deck holds for her: the one of our invitation, or her suggestion once we
    /// cancel it. A hidden card stays hidden across that change.
    func testAnInvitationWeSentIsAboutThePersonWeInvited() {
        let invitationSent = ContactSuggestion.Identifier.invitationSent(ownedCryptoId: Self.ownedCryptoId, invitationUUID: UUID(), contactCryptoId: Self.carol)
        XCTAssertEqual(invitationSent.kind, .invitationSent)
        XCTAssertTrue(invitationSent.isAboutTheSamePerson(as: Self.contact(Self.carol)))
        XCTAssertFalse(invitationSent.isAboutTheSamePerson(as: Self.contact(Self.bob)))
    }

    /// The same person seen from another profile is another card.
    func testThePersonOfAnotherProfileIsNotTheSamePerson() {
        let deck = ContactSuggestion.Deck(identifiers: [a, b, c], hasANewCard: false)
        let cardOfAnotherProfile = Self.invitation(from: Self.carol, ownedCryptoId: Self.alice)
        XCTAssertFalse(deck.hasACard(aboutTheSamePersonAs: cardOfAnotherProfile))
        XCTAssertEqual(deck.keepingOnTop(cardOfAnotherProfile), deck)
    }

    /// Every card counts, a suggestion as well as an invitation.
    func testTheEntryShowsFromThreeCards() {
        let two = ContactSuggestion.Deck(identifiers: [a, Self.contact(Self.carol)], hasANewCard: false)
        XCTAssertFalse(two.isEntryVisible(entryWasVisible: false))
        let three = ContactSuggestion.Deck(identifiers: [a, b, Self.contact(Self.carol)], hasANewCard: false)
        XCTAssertTrue(three.isEntryVisible(entryWasVisible: false))
    }

    /// Once shown, the entry stays down to the last card, then goes with it.
    func testTheEntryStaysUntilTheDeckIsEmpty() {
        let oneCard = ContactSuggestion.Deck(identifiers: [c], hasANewCard: false)
        XCTAssertTrue(oneCard.isEntryVisible(entryWasVisible: true))
        XCTAssertFalse(ContactSuggestion.Deck.empty.isEntryVisible(entryWasVisible: true))
    }

    /// After the deck was empty, the entry needs three cards again.
    func testTheEntryComesBackFromThreeCards() {
        let empty = ContactSuggestion.Deck.empty
        let entryWasVisible = empty.isEntryVisible(entryWasVisible: true)
        let oneCard = ContactSuggestion.Deck(identifiers: [c], hasANewCard: true)
        XCTAssertFalse(oneCard.isEntryVisible(entryWasVisible: entryWasVisible))
    }

    /// The badge shows the number of cards whenever the entry shows, and never otherwise.
    func testTheBadgeCountsTheCardsWhileTheEntryShows() {
        let deck = ContactSuggestion.Deck(identifiers: [a, b, Self.contact(Self.carol)], hasANewCard: false)
        XCTAssertEqual(deck.badgeCount(isEntryVisible: true), 3)
        XCTAssertEqual(deck.badgeCount(isEntryVisible: false), 0)
        let oneCard = ContactSuggestion.Deck(identifiers: [c], hasANewCard: false)
        XCTAssertEqual(oneCard.badgeCount(isEntryVisible: oneCard.isEntryVisible(entryWasVisible: true)), 1)
        XCTAssertEqual(ContactSuggestion.Deck.empty.badgeCount(isEntryVisible: false), 0)
    }

}
