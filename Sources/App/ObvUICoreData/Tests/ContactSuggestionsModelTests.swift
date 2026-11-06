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
import CoreData
import ObvCrypto
import ObvTypes
@testable import ObvUICoreData


/// The two flags the contacts suggestions keep on a contact, and the predicates built on them.
final class ContactSuggestionsModelTests: XCTestCase {

    /// Held for the length of a test: a managed object loses its context once nothing else holds it.
    private var context: NSManagedObjectContext?

    override func tearDown() {
        context = nil
        super.tearDown()
    }

    /// Every contact that exists before the migration must read as never set aside and never shown, which is what a non-optional attribute
    /// with a default of `NO` gives a lightweight migration.
    func testTheModelCarriesBothFlagsAsNonOptionalBooleansDefaultingToNo() throws {
        let context = try FetchedResultsControllerSortDescriptorTests.makeInMemoryObvMessengerContext()
        let model = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectModel)
        let entity = try XCTUnwrap(model.entitiesByName["PersistedObvContactIdentity"])
        for key in [PersistedObvContactIdentity.Predicate.Key.stopSuggesting, .suggestionSeen] {
            let attribute = try XCTUnwrap(entity.attributesByName[key.rawValue], "\(key.rawValue) is missing from the model")
            XCTAssertEqual(attribute.attributeType, .booleanAttributeType, key.rawValue)
            XCTAssertFalse(attribute.isOptional, key.rawValue)
            XCTAssertEqual(attribute.defaultValue as? Bool, false, key.rawValue)
        }
    }


    /// Every invitation that exists before the migration must read as never seen in a deck, as the contacts do.
    func testTheModelCarriesTheSeenFlagOfAnInvitationAsANonOptionalBooleanDefaultingToNo() throws {
        let context = try FetchedResultsControllerSortDescriptorTests.makeInMemoryObvMessengerContext()
        let model = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectModel)
        let entity = try XCTUnwrap(model.entitiesByName["PersistedInvitation"])
        let key = PersistedInvitation.Predicate.Key.suggestionSeen.rawValue
        let attribute = try XCTUnwrap(entity.attributesByName[key], "\(key) is missing from the model")
        XCTAssertEqual(attribute.attributeType, .booleanAttributeType)
        XCTAssertFalse(attribute.isOptional)
        XCTAssertEqual(attribute.defaultValue as? Bool, false)
    }


    /// The predicates are executed against SQLite, which is what resolves their key paths: a misspelled key fails here rather than in the app.
    func testTheSuggestionPredicatesResolveAgainstTheStore() throws {
        let context = try FetchedResultsControllerSortDescriptorTests.makeInMemoryObvMessengerContext()
        let ownedCryptoId = FetchedResultsControllerSortDescriptorTests.ownedCryptoId
        for predicate in [PersistedObvContactIdentity.Predicate.isSuggestable(ownedCryptoId: ownedCryptoId),
                          PersistedObvContactIdentity.Predicate.couldBeInvited(ownedCryptoId: ownedCryptoId)] {
            let request: NSFetchRequest<PersistedObvContactIdentity> = PersistedObvContactIdentity.fetchRequest()
            request.predicate = predicate
            XCTAssertEqual(try context.count(for: request), 0)
        }
    }


    /// A contact removed from the one-to-one contacts, by us or by them, is set aside: it is not offered back as a suggestion. Both sides of a
    /// removal reach the app the same way, as the engine's contact turning not one-to-one.
    func testAContactThatStopsBeingOneToOneIsSetAside() throws {
        let ownedIdentity = try makeOwnedIdentity()
        let contact = try addOrUpdateContact(isOneToOne: true, of: ownedIdentity)
        XCTAssertFalse(contact.stopSuggesting)
        _ = try addOrUpdateContact(isOneToOne: false, of: ownedIdentity)
        XCTAssertFalse(contact.isOneToOne)
        XCTAssertTrue(contact.stopSuggesting)
    }


    /// A contact known through a group, and never one-to-one, stays suggestable whatever else changes about them.
    func testAContactThatWasNeverOneToOneIsNotSetAside() throws {
        let ownedIdentity = try makeOwnedIdentity()
        let contact = try addOrUpdateContact(isOneToOne: false, of: ownedIdentity)
        _ = try addOrUpdateContact(isOneToOne: false, isActive: false, of: ownedIdentity)
        XCTAssertFalse(contact.stopSuggesting)
    }


    /// Becoming one-to-one sets nothing aside.
    func testAContactThatBecomesOneToOneIsNotSetAside() throws {
        let ownedIdentity = try makeOwnedIdentity()
        let contact = try addOrUpdateContact(isOneToOne: false, of: ownedIdentity)
        _ = try addOrUpdateContact(isOneToOne: true, of: ownedIdentity)
        XCTAssertTrue(contact.isOneToOne)
        XCTAssertFalse(contact.stopSuggesting)
    }

}


// MARK: - The save hooks

extension ContactSuggestionsModelTests {

    /// A save that changes only the flags of the contacts suggestions skips the contact's other save hooks: the group memberships, the title of
    /// the discussion, the notification of an update. Any other key, alone or with them, runs the hooks as before.
    func testOnlyTheFlagsOfTheSuggestionsSkipTheSaveHooks() {
        typealias Key = PersistedObvContactIdentity.Predicate.Key
        XCTAssertTrue(PersistedObvContactIdentity.onlyTheFlagsOfTheSuggestionsChanged([Key.suggestionSeen.rawValue]))
        XCTAssertTrue(PersistedObvContactIdentity.onlyTheFlagsOfTheSuggestionsChanged([Key.stopSuggesting.rawValue]))
        XCTAssertTrue(PersistedObvContactIdentity.onlyTheFlagsOfTheSuggestionsChanged([Key.suggestionSeen.rawValue, Key.stopSuggesting.rawValue]))
        XCTAssertFalse(PersistedObvContactIdentity.onlyTheFlagsOfTheSuggestionsChanged([Key.stopSuggesting.rawValue, Key.isOneToOne.rawValue]))
        XCTAssertFalse(PersistedObvContactIdentity.onlyTheFlagsOfTheSuggestionsChanged([Key.customDisplayName.rawValue]))
        XCTAssertFalse(PersistedObvContactIdentity.onlyTheFlagsOfTheSuggestionsChanged([]))
    }

}


// MARK: - Many contacts at once

extension ContactSuggestionsModelTests {

    /// More contacts than one fetch may ask about: each request runs once per slice, and the slices together cover every contact.
    func testTheRequestsOnManyContactsCoverEverySlice() throws {
        let ownedIdentity = try makeOwnedIdentity()
        let context = try XCTUnwrap(self.context)
        let ownedCryptoId = FetchedResultsControllerSortDescriptorTests.ownedCryptoId
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        let serverURL = try XCTUnwrap(URL(string: "https://server.olvid.io"))
        let cryptoIds = Set((0..<250).map { _ in
            ObvCryptoId(cryptoIdentity: ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng).getObvCryptoIdentity())
        })
        for cryptoId in cryptoIds {
            _ = try addOrUpdateContact(cryptoId: cryptoId, isOneToOne: false, of: ownedIdentity)
        }

        try PersistedObvContactIdentity.markSuggestionsAsSeen(ownedCryptoId: ownedCryptoId, contactCryptoIds: cryptoIds, within: context)

        let contacts = try PersistedObvContactIdentity.getContacts(ownedCryptoId: ownedCryptoId, contactCryptoIds: cryptoIds, within: context)
        XCTAssertEqual(contacts.count, cryptoIds.count)
        XCTAssertTrue(contacts.allSatisfy(\.suggestionSeen))
        let nonOneToOne = try PersistedObvContactIdentity.getAllContactsWithCryptoId(in: cryptoIds, ofOwnedIdentity: ownedCryptoId, whereOneToOneStatusIs: .nonOneToOne, within: context)
        XCTAssertEqual(nonOneToOne.count, cryptoIds.count)
        XCTAssertTrue(try PersistedObvContactIdentity.getContacts(ownedCryptoId: ownedCryptoId, contactCryptoIds: [], within: context).isEmpty)
    }

}


// MARK: - Fixtures

extension ContactSuggestionsModelTests {

    private func makeOwnedIdentity() throws -> PersistedObvOwnedIdentity {
        let context = try FetchedResultsControllerSortDescriptorTests.makeInMemoryObvMessengerContext()
        self.context = context
        let coreDetails = try ObvIdentityCoreDetails(firstName: "Owned", lastName: "Identity", company: nil, position: nil, signedUserDetails: nil)
        let ownedIdentity = ObvOwnedIdentity(cryptoId: FetchedResultsControllerSortDescriptorTests.ownedCryptoId,
                                             publishedIdentityDetails: ObvIdentityDetails(coreDetails: coreDetails, photoURL: nil),
                                             isActive: true,
                                             isKeycloakManaged: false)
        return try XCTUnwrap(PersistedObvOwnedIdentity(ownedIdentity: ownedIdentity, isRestoringSyncSnapshotOrBackup: true, within: context))
    }


    /// The contact as the engine would report it, created the first time and updated after.
    private func addOrUpdateContact(cryptoId: ObvCryptoId = FetchedResultsControllerSortDescriptorTests.contactCryptoId, isOneToOne: Bool, isActive: Bool = true, of ownedIdentity: PersistedObvOwnedIdentity) throws -> PersistedObvContactIdentity {
        let coreDetails = try ObvIdentityCoreDetails(firstName: "Alice", lastName: "Martin", company: nil, position: nil, signedUserDetails: nil)
        let contactIdentity = ObvContactIdentity(contactCryptoId: cryptoId,
                                                 trustedIdentityDetails: ObvIdentityDetails(coreDetails: coreDetails, photoURL: nil),
                                                 publishedIdentityDetails: nil,
                                                 ownedCryptoId: FetchedResultsControllerSortDescriptorTests.ownedCryptoId,
                                                 isCertifiedByOwnKeycloak: false,
                                                 isActive: isActive,
                                                 isRevokedAsCompromised: false,
                                                 isOneToOne: isOneToOne,
                                                 wasRecentlyOnline: false)
        return try ownedIdentity.addOrUpdateContact(with: contactIdentity, isRestoringSyncSnapshotOrBackup: false).contact
    }

}
