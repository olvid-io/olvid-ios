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
import Foundation
import ObvCrypto
import ObvMetaManager
import ObvTypes
import OlvidUtils
import XCTest
@testable import ObvReturnReceiptSendManager


/// The sweep: what it picks up, when it stops, and what happens to a receipt old enough to be given up on.
///
/// These rows are written straight into the store rather than posted, which is what a sweep meets in life: rows a
/// process that died left behind.
final class DrainAndAgeCapTests: ReturnReceiptStoreTestCase {

    private var manager: ObvReturnReceiptSendManager!
    private var delegate: FakeReturnReceiptSendManagerDelegate!
    private var network: FakeReturnReceiptUploadNetwork!

    private let firstServer = URL(string: "https://server.one.test")!
    private let secondServer = URL(string: "https://server.two.test")!

    /// Comfortably past the thirty days a receipt is given up on after.
    private let longAgo = Date.now.addingTimeInterval(-40 * 24 * 60 * 60)
    private let aMinuteAgo = Date.now.addingTimeInterval(-60)

    /// A deadline no sweep in these tests will reach.
    private var noDeadline: Date { Date.now.addingTimeInterval(60) }

    override func setUpWithError() throws {
        try super.setUpWithError()
        delegate = FakeReturnReceiptSendManagerDelegate()
    }

    override func tearDownWithError() throws {
        manager = nil
        delegate = nil
        network = nil
        try super.tearDownWithError()
    }

    private func makeManager(appType: AppType = .mainApp, answering answer: FakeReturnReceiptUploadNetwork.Answer = .theServerSaysOk) async -> ObvReturnReceiptSendManager {
        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: answer)
        self.network = network
        let manager = ObvReturnReceiptSendManager(appType: appType, containerURL: containerURL, runningLog: RunningLogError(), uploader: .init(network: network))
        try? await manager.finalizeInitialization(delegate: delegate)
        self.manager = manager
        return manager
    }

    /// Writes a row straight into the store, as a process that died would have left it.
    @discardableResult
    private func insertRow(onServer serverURL: URL, createdAt: Date) throws -> ReturnReceiptIdentifier {
        let receipt = ReturnReceiptTestFactory.receipt(
            contactIdentifier: ReturnReceiptTestFactory.contactIdentifier(contactServerURL: serverURL, ownedServerURL: serverURL),
            nonce: ReturnReceiptTestFactory.nonce())
        let coordinator = try makeCoordinator()
        try write(on: coordinator) { context in
            _ = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: createdAt, within: context)
        }
        return .init(returnReceiptToSend: receipt)
    }

    /// Writes a row whose attachment number is one no initializer would accept — as a build with a bug could have
    /// left behind — set through KVC, the column being private and guarded everywhere else.
    ///
    /// The row fetches back perfectly well, and its identifier cannot be turned into a predicate, so the delete of
    /// any page holding it throws before anything is saved. That is a real save failure, arrived at through the
    /// module's own code.
    private func insertRowWhoseIdentifierCannotBeTurnedIntoAPredicate(onServer serverURL: URL, createdAt: Date) throws {
        let receipt = ReturnReceiptTestFactory.receipt(
            contactIdentifier: ReturnReceiptTestFactory.contactIdentifier(contactServerURL: serverURL, ownedServerURL: serverURL),
            nonce: ReturnReceiptTestFactory.nonce())
        let coordinator = try makeCoordinator()
        try write(on: coordinator) { context in
            let row = try PersistedReturnReceiptToSend(returnReceiptToSend: receipt, createdAt: createdAt, within: context)
            row.setValue(NSNumber(value: Int32(-2)), forKey: "rawAttachmentNumber")
        }
    }


    private func rowsLeft(onServer serverURL: URL) throws -> Set<ReturnReceiptIdentifier> {
        let coordinator = try makeCoordinator()
        let values = try read(on: coordinator) { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: serverURL, fetchLimit: 1000, within: context)
        }
        return Set(values.map { $0.identifier })
    }

    private func noncesUploaded() -> Set<Data> {
        Set(network.requests.flatMap { $0.nonces })
    }

    // MARK: - What a sweep picks up

    /// A row nothing in this process posted is found, sent, and deleted. This is the case the store exists for: a
    /// receipt an interrupted process left behind.
    func testASweepSendsARowThisProcessNeverPosted() async throws {
        let identifier = try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        let manager = await makeManager()

        await manager.drain(until: noDeadline)

        XCTAssertEqual(network.requests.count, 1)
        XCTAssertTrue(try rowsLeft(onServer: firstServer).isEmpty, "The row of a receipt the server took must go")
        XCTAssertFalse(noncesUploaded().isEmpty)
        _ = identifier
    }


    /// Every server is swept, not just the first one found.
    func testASweepReachesEveryServer() async throws {
        try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        try insertRow(onServer: secondServer, createdAt: aMinuteAgo)
        let manager = await makeManager()

        await manager.drain(until: noDeadline)

        XCTAssertEqual(network.requests.count, 2)
        XCTAssertTrue(try rowsLeft(onServer: firstServer).isEmpty)
        XCTAssertTrue(try rowsLeft(onServer: secondServer).isEmpty)
    }


    /// More rows than a page holds are swept in several pages, and a page is never larger than a cycle.
    func testMoreRowsThanAPageAreSweptInSeveralPages() async throws {
        for _ in 0..<60 {
            try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        }
        let manager = await makeManager()

        await manager.drain(until: noDeadline)

        XCTAssertEqual(delegate.sizesOfTheSeedCalls.count, 2, "Sixty rows are two pages")
        XCTAssertEqual(delegate.sizesOfTheSeedCalls.max(), 50, "A page must not be larger than a cycle")
        XCTAssertTrue(try rowsLeft(onServer: firstServer).isEmpty)
    }

    // MARK: - When a sweep stops

    /// Deletion is what advances a sweep, so a page that settles nothing must end that server's run. Otherwise the
    /// next fetch returns the same rows and the sweep reads them for ever.
    func testAPageThatFailsEndsThatServersRunWithoutARefetchLoop() async throws {
        for _ in 0..<60 {
            try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        }
        let manager = await makeManager(answering: .theServerSaysGeneralError)

        await manager.drain(until: noDeadline)

        XCTAssertEqual(network.requests.count, 1, "One page was attempted, and the run ended rather than looping")
        XCTAssertEqual(try rowsLeft(onServer: firstServer).count, 60, "A refused page deletes nothing")
    }


    /// A sweep steps over the rows it cannot settle, rather than meeting them again as the whole of every page.
    ///
    /// Deletion is what advances a sweep, so a page of receipts whose contacts the identity database will not answer
    /// for settles nothing. A sweep that ended there would make no progress at all for as long as those rows lived —
    /// as long as thirty days — while everything queued behind them waited.
    func testASweepStepsOverAPageItCannotSettleAndReachesWhatIsBehindIt() async throws {

        // A page's worth, and all of them older than the receipt behind them, so that they are what the first fetch
        // comes back with.
        var strandedContacts = Set<ObvContactIdentifier>()
        for index in 0..<50 {
            let identifier = try insertRow(onServer: firstServer, createdAt: Date.now.addingTimeInterval(-3600 + Double(index)))
            strandedContacts.insert(identifier.contactIdentifier)
        }
        let behindThem = try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        let manager = await makeManager()
        for contactIdentifier in strandedContacts {
            delegate.setDeviceAnswer(.theContactCannotBeLookedUp, for: contactIdentifier)
        }

        await manager.drain(until: noDeadline)

        XCTAssertEqual(noncesUploaded(), [behindThem.nonce], "The receipt behind a page of stranded rows was never reached")
        XCTAssertEqual(try rowsLeft(onServer: firstServer).count, 50, "The stranded rows are kept, and nothing else is")
    }


    /// One server refusing says nothing about another. Its run ends; the other's carries on.
    func testAServerRefusingDoesNotStopTheOtherServersRun() async throws {
        try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        try insertRow(onServer: secondServer, createdAt: aMinuteAgo)
        let refused = try rowsLeft(onServer: secondServer)
        let network = FakeReturnReceiptUploadNetwork(answering: { request in
            request.url?.absoluteString.hasPrefix(self.secondServer.absoluteString) == true ? .theServerSaysGeneralError : .theServerSaysOk
        })
        self.network = network
        let manager = ObvReturnReceiptSendManager(appType: .mainApp, containerURL: containerURL, runningLog: RunningLogError(), uploader: .init(network: network))
        try await manager.finalizeInitialization(delegate: delegate)
        self.manager = manager

        await manager.drain(until: noDeadline)

        XCTAssertTrue(try rowsLeft(onServer: firstServer).isEmpty, "The server that took its receipts keeps none")
        XCTAssertEqual(try rowsLeft(onServer: secondServer), refused, "The server that refused keeps all of them")
    }


    /// Deletion is the only thing that advances a sweep, so a delete that could not be committed must not be reported
    /// as rows that went. Believing it, the sweep read the same page again and re-uploaded the same fifty receipts,
    /// with no backoff, for as long as the deadline allowed — up to five minutes on the foreground sweep.
    ///
    /// The failure is arranged with a row no insert would ever write. Taking the store away instead does not work:
    /// a store coordinator with no store raises `NSInternalInconsistencyException`, which is an Objective-C exception
    /// rather than an error, so it is not caught and the process dies. Every way a save fails in life — a full disk,
    /// an unreadable file — comes back as an `NSError`, which is what this reproduces.
    func testAPageWhoseRowsCannotBeDeletedIsNotReportedAsSettled() async throws {
        // The oldest, so that it is certainly in the first page.
        try insertRowWhoseIdentifierCannotBeTurnedIntoAPredicate(onServer: firstServer, createdAt: longAgo)
        for _ in 0..<59 {
            try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        }
        let manager = await makeManager()

        await manager.drain(until: noDeadline)

        XCTAssertEqual(network.requests.count, 1, "The sweep read another page although not one row of the first could be deleted")
        XCTAssertEqual(try rowsLeft(onServer: firstServer).count, 60, "Nothing was deleted, which is the premise this test rests on")
    }


    /// A deadline already past means nothing is attempted at all.
    func testADeadlineAlreadyPastSweepsNothing() async throws {
        try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        let manager = await makeManager()

        await manager.drain(until: Date.now.addingTimeInterval(-1))

        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertEqual(try rowsLeft(onServer: firstServer).count, 1)
    }

    // MARK: - Not re-entrant

    /// A foreground and the inbox-drain window can ask for a sweep at once. The second must wait for the first
    /// rather than page over the same rows — and must not return before the sweep is done, since a caller holding a
    /// background-task window would otherwise close it too early.
    func testASecondSweepAwaitsTheOneInFlightRatherThanPagingTheSameRows() async throws {
        for _ in 0..<10 {
            try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        }
        let manager = await makeManager()
        network.holdRequests()

        async let first: Void = manager.drain(until: noDeadline)
        async let second: Void = manager.drain(until: noDeadline)

        // Both are now waiting on the one request that the first sweep has in flight.
        network.releaseRequests()
        _ = await (first, second)

        XCTAssertEqual(network.requests.count, 1, "The same rows were paged twice")
        XCTAssertTrue(try rowsLeft(onServer: firstServer).isEmpty, "The second caller returned before the sweep had finished")
    }

    /// A caller waiting for a sweep it did not start may shorten it to its own deadline.
    ///
    /// Otherwise a window holding a background task for a few seconds could be held by a sweep a foreground started
    /// with minutes to spare — waiting past the deadline it was given, which is what the deadline exists to prevent.
    /// The running sweep gives up what it has not reached; the next one takes it.
    func testACallerWaitingForASweepMayShortenItToItsOwnDeadline() async throws {
        for _ in 0..<60 {
            try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        }
        let manager = await makeManager()
        network.holdRequests()

        let longSweep = Task { await manager.drain(until: self.noDeadline) }
        try await waitUntilTheFirstRequestIsInFlight()

        // Arrives while the first page is parked at the network, with a deadline of its own that is short and has not
        // yet passed. A caller with none left is turned away instead and shortens nothing, which is its own test.
        let shortDeadline = Date.now.addingTimeInterval(0.3)
        let shortSweep = Task { await manager.drain(until: shortDeadline) }

        // Waited for rather than slept through: the second caller reaching the actor is what this test needs to have
        // happened, and a length of time is not evidence that it did.
        try await waitUntilTheSweepInFlightIsShortened(to: shortDeadline, on: manager)
        // Now a sleep is exactly right, the thing being waited for being the clock passing an instant already known.
        try await Task.sleep(seconds: 0.4)

        network.releaseRequests()
        _ = await (longSweep.value, shortSweep.value)

        XCTAssertEqual(network.requests.count, 1, "The sweep carried on past the deadline it was shortened to")
        XCTAssertEqual(try rowsLeft(onServer: firstServer).count, 10, "The first page was still settled")
    }


    /// A caller with no time left is turned away rather than allowed to shorten the sweep in flight.
    ///
    /// The drain window asks for a sweep when its loop ends, and one of the ways that loop ends *is* its own
    /// deadline — so the commonest caller here has nothing left to spend. Letting it shorten would stop a sweep that
    /// still had minutes, on behalf of a caller that only wanted to return at once.
    func testACallerWithNoTimeLeftDoesNotStopTheSweepInFlight() async throws {
        for _ in 0..<60 {
            try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        }
        let manager = await makeManager()
        network.holdRequests()

        let longSweep = Task { await manager.drain(until: self.noDeadline) }
        try await waitUntilTheFirstRequestIsInFlight()
        let callerWithNoTimeLeft = Task { await manager.drain(until: Date.now.addingTimeInterval(-1)) }

        network.releaseRequests()
        _ = await (longSweep.value, callerWithNoTimeLeft.value)

        XCTAssertEqual(network.requests.count, 2, "The sweep in flight was stopped by a caller with no time to give it")
        XCTAssertTrue(try rowsLeft(onServer: firstServer).isEmpty, "The sweep did not finish what it had started")
    }


    /// Fails rather than hanging if the sweep in flight is never shortened.
    private func waitUntilTheSweepInFlightIsShortened(to deadline: Date, on manager: ObvReturnReceiptSendManager, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if await manager.currentDrain?.deadline == deadline { return }
            try await Task.sleep(seconds: 0.01)
        }
        XCTFail("The sweep in flight was never shortened to the second caller's deadline", file: file, line: line)
    }


    /// Fails rather than hanging if the sweep never reaches the network.
    private func waitUntilTheFirstRequestIsInFlight(file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if !network.requests.isEmpty { return }
            try await Task.sleep(seconds: 0.01)
        }
        XCTFail("No request was made, so the sweep never got as far as the network", file: file, line: line)
    }

    // MARK: - Only the app sweeps

    /// An extension has thirty seconds and must never walk a backlog. The rule is enforced here, not left to callers.
    func testOnlyTheAppSweeps() async throws {
        for appType in [AppType.notificationExtension, .shareExtension, .intentExtension] {
            try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
            let manager = await makeManager(appType: appType)

            await manager.drain(until: noDeadline)

            XCTAssertTrue(network.requests.isEmpty, "\(appType.transactionAuthor) swept the store")
        }
        XCTAssertEqual(try rowsLeft(onServer: firstServer).count, 3, "Nothing was deleted either")
    }

    // MARK: - The age cap

    /// An over-age receipt is **uploaded** before it is given up on. The commonest way a row gets to be thirty days
    /// old is a phone that was off or abroad, so deleting ahead of the attempt would destroy a backlog that was
    /// about to be delivered.
    func testAnOverAgeReceiptIsUploadedBeforeItIsDeleted() async throws {
        try insertRow(onServer: firstServer, createdAt: longAgo)
        let manager = await makeManager()

        await manager.drain(until: noDeadline)

        XCTAssertEqual(network.requests.count, 1, "The over-age receipt was deleted without being tried")
        XCTAssertEqual(network.requests.first?.nonces.count, 1)
        XCTAssertTrue(try rowsLeft(onServer: firstServer).isEmpty)
    }


    /// Once an attempt has left the device, an over-age receipt is given up on whatever the server answered — or it
    /// is not a cap at all, and an undeliverable receipt takes a last chance on every sweep for ever. A receipt that
    /// is not over-age is kept, as any refused receipt is.
    func testAnOverAgeReceiptIsGivenUpOnAfterAFailureThatLeftTheDevice() async throws {
        try insertRow(onServer: firstServer, createdAt: longAgo)
        let inAge = try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        let manager = await makeManager(answering: .theServerSaysGeneralError)

        await manager.drain(until: noDeadline)

        XCTAssertEqual(network.requests.count, 1)
        XCTAssertEqual(try rowsLeft(onServer: firstServer), [inAge], "The over-age row goes, the in-age row stays")
    }


    /// The exception the whole rule turns on: a request that never left the device is not an attempt. Without this,
    /// one launch in airplane mode destroys a backlog that was about to go out.
    func testAnOverAgeReceiptSurvivesARequestThatNeverLeftTheDevice() async throws {
        let overAge = try insertRow(onServer: firstServer, createdAt: longAgo)
        let noConnection = NSError(domain: NSURLErrorDomain, code: Int(CFNetworkErrors.cfurlErrorNotConnectedToInternet.rawValue), userInfo: nil)
        let manager = await makeManager(answering: .theRequestThrows(error: noConnection))

        await manager.drain(until: noDeadline)

        XCTAssertEqual(try rowsLeft(onServer: firstServer), [overAge], "An over-age receipt was destroyed by a launch with no network")
    }


    /// The cap must reach a receipt that never gets as far as a request, or nothing ever deletes it: a contact
    /// deleted while a receipt was owed to it would be owed that receipt for the life of the install, and fifty such
    /// rows on one server would stop that server's sweep for good.
    func testAnOverAgeReceiptWhoseContactCannotBeLookedUpIsGivenUpOn() async throws {
        try insertRow(onServer: firstServer, createdAt: longAgo)
        let inAge = try insertRow(onServer: firstServer, createdAt: aMinuteAgo)
        let manager = await makeManager()
        delegate.setDeviceAnswerByDefault(.theContactCannotBeLookedUp)

        await manager.drain(until: noDeadline)

        XCTAssertTrue(network.requests.isEmpty, "Nothing can be uploaded for a contact that cannot be looked up")
        XCTAssertEqual(try rowsLeft(onServer: firstServer), [inAge], "The over-age row goes, the in-age row stays")
    }


    /// A lookup that throws says nothing about any contact in the batch, so nothing is given up on — not even a
    /// receipt old enough to be capped. This is the difference between a contact that is gone and a database that
    /// would not answer, and only the first is a receipt's fault.
    func testADeviceLookupThatThrowsKeepsEvenAnOverAgeReceipt() async throws {
        let overAge = try insertRow(onServer: firstServer, createdAt: longAgo)
        let manager = await makeManager()
        delegate.errorThrownByTheDeviceLookup = NSError(domain: "a.test", code: 1, userInfo: nil)

        await manager.drain(until: noDeadline)

        XCTAssertEqual(try rowsLeft(onServer: firstServer), [overAge])
    }


    /// Five weeks abroad with data roaming off is the case the cap was written to survive, and it is not one of the
    /// codes airplane mode gives. No request left the device, so no attempt was made.
    func testAnOverAgeReceiptSurvivesAPhoneWithDataRoamingOff() async throws {
        let overAge = try insertRow(onServer: firstServer, createdAt: longAgo)
        let roamingOff = NSError(domain: NSURLErrorDomain, code: Int(CFNetworkErrors.cfurlErrorInternationalRoamingOff.rawValue), userInfo: nil)
        let manager = await makeManager(answering: .theRequestThrows(error: roamingOff))

        await manager.drain(until: noDeadline)

        XCTAssertEqual(try rowsLeft(onServer: firstServer), [overAge], "A backlog no server ever saw was destroyed")
    }


    /// An over-age receipt the sweep never reached is not deleted: the next sweep gives it its chance. Deletion is
    /// the direction to be reluctant in.
    func testAnOverAgeReceiptTheSweepNeverReachedIsNotDeleted() async throws {
        let overAge = try insertRow(onServer: firstServer, createdAt: longAgo)
        let manager = await makeManager()

        await manager.drain(until: Date.now.addingTimeInterval(-1))

        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertEqual(try rowsLeft(onServer: firstServer), [overAge])
    }

    // MARK: - flush

    /// `flush` waits for what this process posted, and for nothing else.
    func testFlushWaitsForWhatThisProcessPosted() async throws {
        let manager = await makeManager()
        let receipt = ReturnReceiptTestFactory.receipt(
            contactIdentifier: ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer),
            nonce: ReturnReceiptTestFactory.nonce())

        await manager.post([receipt], flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertEqual(network.requests.count, 1, "flush returned before the upload had been made")
        XCTAssertTrue(try rowsLeft(onServer: firstServer).isEmpty, "flush returned before the row had been settled")
    }

}
