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
import ObvTypes
import XCTest
@testable import ObvReturnReceiptSendManager


/// What happens when two processes write the same receipt.
///
/// This is why the module is a module: an app-side version of these cases was identified by reading and never
/// reproduced. Here they are deterministic.
final class TwoCoordinatorsOverOneStoreTests: ReturnReceiptStoreTestCase {

    private let server = URL(string: "https://server.one.test")!

    private var contactIdentifier: ObvContactIdentifier!

    override func setUpWithError() throws {
        try super.setUpWithError()
        contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: server, ownedServerURL: server)
    }

    private func receipt(nonce: Data, attachmentNumber: Int? = nil) -> ObvReturnReceiptToSend {
        ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: nonce, attachmentNumber: attachmentNumber)
    }

    // MARK: - The control

    /// Run first, because every other test here passes for the wrong reason if the two coordinators are addressing
    /// two different files. What one writes, the other must read.
    func testTheTwoCoordinatorsReallyShareOneStore() throws {
        let nse = try makeCoordinator(appType: .notificationExtension)
        let app = try makeCoordinator(appType: .mainApp)

        try write(on: nse) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: ReturnReceiptTestFactory.nonce()), createdAt: Date(), within: context)
        }

        XCTAssertEqual(try countOfRows(on: app), 1, "The app does not see what the extension wrote: these are two stores, not one")
    }

    // MARK: - Insert

    /// The case of the plan's example D: a message arrives by push while the app is awake, so both produce a receipt
    /// for it. The uniqueness constraint must leave one row.
    func testTheSameReceiptInsertedByTwoCoordinatorsLeavesOneRow() throws {
        let nse = try makeCoordinator(appType: .notificationExtension)
        let app = try makeCoordinator(appType: .mainApp)
        let nonce = ReturnReceiptTestFactory.nonce()

        try write(on: nse) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce), createdAt: Date(), within: context)
        }
        try write(on: app) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce), createdAt: Date(), within: context)
        }

        XCTAssertEqual(try countOfRows(on: app), 1)
        XCTAssertEqual(try countOfRows(on: nse), 1)
    }

    /// The same, with both inserts made before either save. The constraint is then met at a different moment: the
    /// second save meets a row that was not there when its own object was made.
    func testTwoInsertsMadeBeforeEitherSaveAlsoLeaveOneRow() throws {
        let nse = try makeCoordinator(appType: .notificationExtension)
        let app = try makeCoordinator(appType: .mainApp)
        let nonce = ReturnReceiptTestFactory.nonce()

        let nseContext = nse.newBackgroundContext()
        let appContext = app.newBackgroundContext()

        nseContext.performAndWait {
            _ = try? PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce), createdAt: Date(), within: nseContext)
        }
        appContext.performAndWait {
            _ = try? PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce), createdAt: Date(), within: appContext)
        }

        var thrown: Error?
        nseContext.performAndWait { do { try nseContext.save() } catch { thrown = error } }
        XCTAssertNil(thrown, "The first save has nothing to conflict with")
        appContext.performAndWait { do { try appContext.save() } catch { thrown = error } }
        XCTAssertNil(thrown, "The merge policy must resolve the conflict rather than fail the save")

        XCTAssertEqual(try countOfRows(on: app), 1)
    }

    /// A message receipt and the receipts of its attachments share everything but the attachment number, so the
    /// constraint must keep them apart. Written from two coordinators, because that is how they meet in the field.
    func testReceiptsOfOneMessageAreNotCollapsedIntoEachOther() throws {
        let nse = try makeCoordinator(appType: .notificationExtension)
        let app = try makeCoordinator(appType: .mainApp)
        let nonce = ReturnReceiptTestFactory.nonce()

        try write(on: nse) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce), createdAt: Date(), within: context)
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce, attachmentNumber: 0), createdAt: Date(), within: context)
        }
        try write(on: app) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce), createdAt: Date(), within: context)
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce, attachmentNumber: 0), createdAt: Date(), within: context)
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce, attachmentNumber: 1), createdAt: Date(), within: context)
        }

        XCTAssertEqual(try countOfRows(on: app), 3)
        let values = try read(on: app) { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.server, fetchLimit: 50, within: context)
        }
        XCTAssertEqual(Set(values.map { $0.identifier.attachmentNumber }), [nil, 0, 1])
    }

    /// Which of the two dates the surviving row keeps. The age cap is computed from this column, so it is worth
    /// knowing rather than assuming. `mergeByPropertyObjectTrump` means the values being saved win over the ones in
    /// the store, so the row carries the date of the **second** writer.
    func testTheSurvivingRowKeepsTheDateOfTheSecondWriter() throws {
        let nse = try makeCoordinator(appType: .notificationExtension)
        let app = try makeCoordinator(appType: .mainApp)
        let nonce = ReturnReceiptTestFactory.nonce()
        let firstDate = Date(timeIntervalSince1970: 1_000_000)
        let secondDate = Date(timeIntervalSince1970: 2_000_000)

        try write(on: nse) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce), createdAt: firstDate, within: context)
        }
        try write(on: app) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce), createdAt: secondDate, within: context)
        }

        let values = try read(on: app) { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.server, fetchLimit: 50, within: context)
        }
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.createdAt, secondDate)
    }

    // MARK: - Delete

    /// Both processes send the receipt and both then delete the row. Whichever settles second finds nothing, and that
    /// must be an ordinary no-op: it is what happens every time the other process was quicker.
    func testDeletingTheSameRowFromTwoCoordinatorsIsANoOpTheSecondTime() throws {
        let nse = try makeCoordinator(appType: .notificationExtension)
        let app = try makeCoordinator(appType: .mainApp)
        let nonce = ReturnReceiptTestFactory.nonce()
        let receipt = self.receipt(nonce: nonce)

        try write(on: nse) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: Date(), within: context)
        }
        XCTAssertEqual(try countOfRows(on: app), 1)

        let identifier = ReturnReceiptIdentifier(returnReceiptToSend: receipt)
        try write(on: nse) { context in
            try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: [identifier], within: context)
        }
        try write(on: app) { context in
            try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: [identifier], within: context)
        }

        XCTAssertEqual(try countOfRows(on: app), 0)
        XCTAssertEqual(try countOfRows(on: nse), 0)
    }

    /// The identifier is the handle precisely because it survives a collapse. One coordinator inserts, the other
    /// inserts the same receipt and collapses into that row, and the identifier it built still names the row that
    /// survived — which an `NSManagedObjectID` would not be guaranteed to do.
    func testAnIdentifierBuiltByOneCoordinatorDeletesTheRowTheOtherInserted() throws {
        let nse = try makeCoordinator(appType: .notificationExtension)
        let app = try makeCoordinator(appType: .mainApp)
        let nonce = ReturnReceiptTestFactory.nonce()

        try write(on: nse) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: self.receipt(nonce: nonce), createdAt: Date(), within: context)
        }
        let receiptAccordingToTheApp = self.receipt(nonce: nonce)
        try write(on: app) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receiptAccordingToTheApp, createdAt: Date(), within: context)
        }
        XCTAssertEqual(try countOfRows(on: app), 1)

        try write(on: app) { context in
            try PersistedReturnReceiptToSend.deleteReturnReceipts(withIdentifiers: [.init(returnReceiptToSend: receiptAccordingToTheApp)], within: context)
        }

        XCTAssertEqual(try countOfRows(on: nse), 0, "The row the merge kept was not the one the identifier named")
    }

}
