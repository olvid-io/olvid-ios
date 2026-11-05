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
import ObvTypes
import ObvAppTypes
@testable import ObvUICoreData


/// Regression tests for the duplication of messages on the destination device during a history transfer.
///
/// A user reported a discussion in which every message appeared several times on the destination device. The fix makes
/// `PersistedMessage.createDuringHistoryTransfer(_:within:)` idempotent: presenting the same message more than once (e.g.
/// because the source enumerated the same discussion twice, or because a transfer was replayed) must not create a second
/// copy of the message, nor duplicate its reactions.
final class PersistedMessageHistoryTransferDoubleInsertionTests: XCTestCase {

    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        context = try Self.makeInMemoryObvMessengerContext()
    }

    override func tearDownWithError() throws {
        context = nil
        try super.tearDownWithError()
    }


    /// Inserting the very same received history message twice must result in a single `PersistedMessageReceived`, and in a
    /// single reaction (reactions are created unconditionally by the history-transfer code, so a non-idempotent insertion
    /// would duplicate them).
    func testInsertingTheSameReceivedHistoryMessageTwiceInsertsItOnlyOnce() throws {

        // Given an owned identity on this destination device

        try insertOwnedIdentity(cryptoId: Self.ownedCryptoId, in: context)

        // And a received history message (carrying a single reaction) belonging to a one-to-one discussion that does not
        // exist yet on this destination device (it will be created in a "locked" state during the transfer).

        let message = Self.makeReceivedHistoryMessage(
            ownedCryptoId: Self.ownedCryptoId,
            contactCryptoId: Self.contactCryptoId,
            senderSequenceNumber: 1)

        // When the same message is presented twice to the history-transfer creation method

        _ = try PersistedMessage.createDuringHistoryTransfer(message, within: context)
        _ = try PersistedMessage.createDuringHistoryTransfer(message, within: context)

        // Then a single received message exists, with a single reaction.

        XCTAssertEqual(try count(entityName: PersistedMessageReceived.entityName, in: context), 1, "The same received message must not be inserted twice")
        XCTAssertEqual(try count(entityName: "PersistedMessageReactionSent", in: context), 1, "The reaction of an already-known message must not be duplicated")
    }


    /// Two *distinct* received messages of the same discussion must both be inserted (a sanity check ensuring the
    /// idempotency guard does not wrongly discard genuinely new messages).
    func testInsertingTwoDistinctReceivedHistoryMessagesInsertsBoth() throws {

        try insertOwnedIdentity(cryptoId: Self.ownedCryptoId, in: context)

        let message1 = Self.makeReceivedHistoryMessage(ownedCryptoId: Self.ownedCryptoId, contactCryptoId: Self.contactCryptoId, senderSequenceNumber: 1)
        let message2 = Self.makeReceivedHistoryMessage(ownedCryptoId: Self.ownedCryptoId, contactCryptoId: Self.contactCryptoId, senderSequenceNumber: 2)

        _ = try PersistedMessage.createDuringHistoryTransfer(message1, within: context)
        _ = try PersistedMessage.createDuringHistoryTransfer(message2, within: context)

        XCTAssertEqual(try count(entityName: PersistedMessageReceived.entityName, in: context), 2)
    }

}


// MARK: - Fixtures

extension PersistedMessageHistoryTransferDoubleInsertionTests {

    /// Two distinct sample cryptographic identities (real Olvid dev-server identities, reused from the history-transfer tests).
    static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    static let contactCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!)

    /// A fixed thread identifier, so that two history messages with the same sequence number resolve to the same message identifier.
    static let senderThreadIdentifier = UUID(uuidString: "00000000-0000-0000-0000-0000000000AA")!


    func insertOwnedIdentity(cryptoId: ObvCryptoId, in context: NSManagedObjectContext) throws {
        let coreDetails = try ObvIdentityCoreDetails(firstName: "Owned", lastName: "Identity", company: nil, position: nil, signedUserDetails: nil)
        let details = ObvIdentityDetails(coreDetails: coreDetails, photoURL: nil)
        let ownedIdentity = ObvOwnedIdentity(cryptoId: cryptoId, publishedIdentityDetails: details, isActive: true, isKeycloakManaged: false)
        let persisted = PersistedObvOwnedIdentity(ownedIdentity: ownedIdentity, isRestoringSyncSnapshotOrBackup: true, within: context)
        XCTAssertNotNil(persisted, "Could not insert the owned identity fixture")
    }


    static func makeReceivedHistoryMessage(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId, senderSequenceNumber: Int) -> ObvHistoryReceivedMessage {

        let discussionIdentifier: ObvDiscussionIdentifier = .oneToOne(id: ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId))

        let receivedIdentifier = ObvMessageReceivedAppIdentifier(
            discussionIdentifier: discussionIdentifier,
            senderIdentifier: contactCryptoId.getIdentity(),
            senderThreadIdentifier: senderThreadIdentifier,
            senderSequenceNumber: senderSequenceNumber)

        let reaction = ObvHistoryReceivedMessage.Reaction(
            emoji: "👍",
            sender: ownedCryptoId, // A reaction sent by the owned identity, so no contact needs to exist on the destination
            timestamp: Date(timeIntervalSince1970: 1_700_000_000))

        return ObvHistoryReceivedMessage(
            kind: .received(messageIdentifier: receivedIdentifier),
            messageIdentifierFromEngine: .known(Data(repeating: 0x01, count: 32)),
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            bodyAndMentions: nil,
            replyTo: nil,
            expirationLimitedExistence: nil,
            forwarded: false,
            edited: false,
            location: nil,
            poll: nil,
            reactions: [reaction],
            pollVotes: [],
            attachments: [],
            suggestedDiscussionTitle: "Sample discussion")
    }

}


// MARK: - In-memory Core Data stack

extension PersistedMessageHistoryTransferDoubleInsertionTests {

    /// Builds an in-memory `NSManagedObjectContext` backed by the compiled `ObvMessenger` model.
    ///
    /// The model is compiled into the `ObvAppDatabase` framework bundle (as `ObvMessenger.momd`); we locate it among the
    /// loaded bundles rather than depending on `ObvAppDatabase` directly. We use a `/dev/null` SQLite store so the database
    /// lives only in memory. The tests intentionally never call `save()`, relying instead on the fact that fetch requests
    /// see pending (unsaved) insertions in the same context — this keeps the fixtures minimal.
    static func makeInMemoryObvMessengerContext() throws -> NSManagedObjectContext {

        let momdURL = (Bundle.allFrameworks + Bundle.allBundles)
            .compactMap { $0.url(forResource: "ObvMessenger", withExtension: "momd") }
            .first

        guard let momdURL, let model = NSManagedObjectModel(contentsOf: momdURL) else {
            throw TestError.couldNotLoadObvMessengerModel
        }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: URL(fileURLWithPath: "/dev/null"),
            options: nil)

        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    enum TestError: Error {
        case couldNotLoadObvMessengerModel
    }


    /// Counts the objects of the given entity, *including* pending (unsaved) insertions. We must use `fetch` rather than
    /// `count(for:)` here, because the latter executes against the persistent store and would ignore the unsaved objects
    /// created by the history transfer (the tests intentionally never call `save()`).
    func count(entityName: String, in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.includesPendingChanges = true
        return try context.fetch(request).count
    }

}
