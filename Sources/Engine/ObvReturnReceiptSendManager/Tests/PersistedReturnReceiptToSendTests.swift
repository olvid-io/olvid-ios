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
import ObvMetaManager
import ObvTypes
import OlvidUtils
import XCTest
@testable import ObvReturnReceiptSendManager


/// Inserts, fetches by predicate, deletes. One coordinator: what two of them do to each other is in
/// ``TwoCoordinatorsOverOneStoreTests``.
final class PersistedReturnReceiptToSendTests: ReturnReceiptStoreTestCase {

    private var databaseCoordinator: ReturnReceiptSendDatabaseCoordinator!

    private let firstServer = URL(string: "https://server.one.test")!
    private let secondServer = URL(string: "https://server.two.test")!

    override func setUpWithError() throws {
        try super.setUpWithError()
        databaseCoordinator = try makeCoordinator()
    }

    @discardableResult
    private func write<T>(_ block: (NSManagedObjectContext) throws -> T) throws -> T {
        try write(on: databaseCoordinator, block)
    }

    private func countOfRows() throws -> Int {
        try countOfRows(on: databaseCoordinator)
    }

    // MARK: - Insert

    func testAnInsertedReceiptComesBackWithEveryFieldItWentInWith() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let nonce = ReturnReceiptTestFactory.nonce()
        let receipt = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: nonce, status: .read, attachmentNumber: 3)
        let createdAt = Date(timeIntervalSince1970: 1_000_000)

        try write { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: createdAt, within: context)
        }

        let values = try write { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.firstServer, fetchLimit: 50, within: context)
        }
        XCTAssertEqual(values.count, 1)
        let value = try XCTUnwrap(values.first)
        XCTAssertEqual(value.identifier.contactIdentifier, contactIdentifier)
        XCTAssertEqual(value.identifier.nonce, nonce)
        XCTAssertEqual(value.identifier.status, .read)
        XCTAssertEqual(value.identifier.attachmentNumber, 3)
        XCTAssertEqual(value.key, receipt.elements.key)
        XCTAssertEqual(value.serverURL, firstServer)
        XCTAssertEqual(value.createdAt, createdAt)
    }

    /// A message receipt has no attachment number. It is stored as a sentinel, and must come back as nil.
    func testAMessageReceiptComesBackWithNoAttachmentNumber() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let receipt = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: ReturnReceiptTestFactory.nonce())
        try write { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: Date(), within: context)
        }
        let values = try write { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.firstServer, fetchLimit: 50, within: context)
        }
        XCTAssertEqual(values.count, 1)
        XCTAssertNil(values.first?.identifier.attachmentNumber)
    }

    /// The stored server is the one of the contact, who receives the receipt. Taking the one of the owned identity
    /// would send the batch to the wrong server, and only a self-hosted server would show it.
    func testTheStoredServerIsTheOneOfTheContact() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: secondServer)
        let receipt = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: ReturnReceiptTestFactory.nonce())
        try write { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: Date(), within: context)
        }
        let servers = try write { context in
            try PersistedReturnReceiptToSend.getDistinctServerURLs(within: context)
        }
        XCTAssertEqual(servers, [firstServer])
    }

    func testANegativeAttachmentNumberIsRefusedRatherThanReadAsNoAttachment() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let receipt = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: ReturnReceiptTestFactory.nonce(), attachmentNumber: -1)
        XCTAssertThrowsError(try write { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: Date(), within: context)
        })
        XCTAssertEqual(try countOfRows(), 0, "A refused insert must leave nothing behind")
    }

    // MARK: - Fetch

    func testAPageHoldsOneServerOnly() throws {
        let onFirst = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let onSecond = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: secondServer, ownedServerURL: firstServer)
        try write { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: .init(from: onFirst), createdAt: Date(), within: context)
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: .init(from: onSecond), createdAt: Date(), within: context)
        }
        let first = try write { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.firstServer, fetchLimit: 50, within: context)
        }
        let second = try write { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.secondServer, fetchLimit: 50, within: context)
        }
        XCTAssertEqual(first.map(\.serverURL), [firstServer])
        XCTAssertEqual(second.map(\.serverURL), [secondServer])
        let servers = try write { context in
            try PersistedReturnReceiptToSend.getDistinctServerURLs(within: context)
        }
        XCTAssertEqual(servers, [firstServer, secondServer])
    }

    func testAPageGivesTheOldestFirstAndStopsAtTheLimit() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let dates = (0..<5).map { Date(timeIntervalSince1970: 2_000_000 + Double($0)) }
        try write { context in
            // Inserted newest first, so that the order of the fetch cannot come from the order of the inserts.
            for date in dates.reversed() {
                let receipt = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: ReturnReceiptTestFactory.nonce())
                _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: date, within: context)
            }
        }
        let values = try write { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.firstServer, fetchLimit: 3, within: context)
        }
        XCTAssertEqual(values.map(\.createdAt), Array(dates.prefix(3)))
    }

    func testTheDistinctServersFetchGivesEachServerOnce() throws {
        try write { context in
            for _ in 0..<3 {
                let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: self.firstServer, ownedServerURL: self.firstServer)
                _ = try PersistedReturnReceiptToSend(returnReceiptToSend: .init(from: contactIdentifier), createdAt: Date(), within: context)
            }
        }
        let servers = try write { context in
            try PersistedReturnReceiptToSend.getDistinctServerURLs(within: context)
        }
        XCTAssertEqual(servers, [firstServer])
        XCTAssertEqual(try countOfRows(), 3)
    }

    // MARK: - Delete

    /// The row must really be gone. This is the test that catches a sentinel written one way and read another: the
    /// delete would then match nothing, which this design treats as normal, so nothing else would notice.
    func testAMessageReceiptIsReallyDeletedByItsIdentifier() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let nonce = ReturnReceiptTestFactory.nonce()
        let messageReceipt = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: nonce)
        let attachmentReceipt = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: nonce, attachmentNumber: 0)
        try write { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: messageReceipt, createdAt: Date(), within: context)
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: attachmentReceipt, createdAt: Date(), within: context)
        }
        XCTAssertEqual(try countOfRows(), 2)

        try write { context in
            try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: [.init(returnReceiptToSend: messageReceipt)], within: context)
        }

        XCTAssertEqual(try countOfRows(), 1, "The message receipt should be gone")
        let left = try write { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.firstServer, fetchLimit: 50, within: context)
        }
        XCTAssertEqual(left.first?.identifier.attachmentNumber, 0, "The attachment receipt should be the one left")
    }

    /// Two receipts of one message differ by their attachment number alone. Deleting one must not delete the other.
    func testDeletingOneOfTwoReceiptsSharingANonceLeavesTheOther() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let nonce = ReturnReceiptTestFactory.nonce()
        let receipts = [0, 1, 2].map { ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: nonce, attachmentNumber: $0) }
        try write { context in
            for receipt in receipts {
                _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: Date(), within: context)
            }
        }
        try write { context in
            try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: [.init(returnReceiptToSend: receipts[1])], within: context)
        }
        let left = try write { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.firstServer, fetchLimit: 50, within: context)
        }
        XCTAssertEqual(Set(left.compactMap(\.identifier.attachmentNumber)), [0, 2])
    }

    /// Two receipts differing by their status alone. The status belongs to the identity of a row.
    func testDeletingTheDeliveredReceiptLeavesTheReadOne() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let nonce = ReturnReceiptTestFactory.nonce()
        let delivered = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: nonce, status: .delivered)
        let read = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: nonce, status: .read)
        try write { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: delivered, createdAt: Date(), within: context)
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: read, createdAt: Date(), within: context)
        }
        try write { context in
            try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: [.init(returnReceiptToSend: delivered)], within: context)
        }
        let left = try write { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.firstServer, fetchLimit: 50, within: context)
        }
        XCTAssertEqual(left.map(\.identifier.status), [.read])
    }

    func testDeletingAPageOfSeveralIdentifiersEmptiesTheTable() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let receipts = (0..<10).map { _ in ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: ReturnReceiptTestFactory.nonce()) }
        try write { context in
            for receipt in receipts {
                _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: Date(), within: context)
            }
        }
        try write { context in
            try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: receipts.map { .init(returnReceiptToSend: $0) }, within: context)
        }
        XCTAssertEqual(try countOfRows(), 0)
    }

    /// A list far longer than a drain page. Each identifier adds five terms to the predicate, and a single fetch
    /// naming a thousand of them is refused by SQLite — measured, before the delete was cut into several fetches.
    /// The error it gives says the store file cannot be opened, so nothing about it would have pointed here.
    func testAVeryLongListOfIdentifiersIsDeletedWithoutFailing() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let receipts = (0..<1_000).map { _ in
            ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: ReturnReceiptTestFactory.nonce())
        }
        try write { context in
            for receipt in receipts {
                _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: Date(), within: context)
            }
        }
        XCTAssertEqual(try countOfRows(), 1_000)

        try write { context in
            try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: receipts.map { .init(returnReceiptToSend: $0) }, within: context)
        }
        XCTAssertEqual(try countOfRows(), 0)
    }


    /// Deleting a row that is not there is normal: another process may have sent the same receipt first.
    func testDeletingARowThatIsNotThereChangesNothing() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let kept = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: ReturnReceiptTestFactory.nonce())
        let neverInserted = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: ReturnReceiptTestFactory.nonce())
        try write { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: kept, createdAt: Date(), within: context)
        }
        try write { context in
            try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: [.init(returnReceiptToSend: neverInserted)], within: context)
        }
        XCTAssertEqual(try countOfRows(), 1)
    }

    /// An empty batch must delete nothing. An AND over no subpredicates would be true, and would empty the table.
    func testDeletingAnEmptyBatchDeletesNothing() throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        try write { context in
            for _ in 0..<3 {
                _ = try PersistedReturnReceiptToSend(returnReceiptToSend: .init(from: contactIdentifier), createdAt: Date(), within: context)
            }
        }
        try write { context in
            try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: [], within: context)
        }
        XCTAssertEqual(try countOfRows(), 3)
    }

}


private extension ObvReturnReceiptToSend {
    /// A delivered receipt for a message, with a nonce of its own.
    init(from contactIdentifier: ObvContactIdentifier) {
        self = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: ReturnReceiptTestFactory.nonce())
    }
}
