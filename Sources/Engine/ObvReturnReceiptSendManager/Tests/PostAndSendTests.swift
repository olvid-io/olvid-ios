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


/// What `post` does, and what becomes of a row afterwards.
///
/// The rule every one of these checks a corner of: a row is deleted only when an upload carrying it succeeded, or
/// when the receipt can never be sent. Every other direction leaves it where it is, to be sent again.
final class PostAndSendTests: ReturnReceiptStoreTestCase {

    private var manager: ObvReturnReceiptSendManager!
    private var delegate: FakeReturnReceiptSendManagerDelegate!
    private var network: FakeReturnReceiptUploadNetwork!

    private let server = URL(string: "https://server.one.test")!

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

    /// - Parameter containerURL: nil puts the manager in the degraded mode it uses when it has no store.
    private func makeManager(answering answer: FakeReturnReceiptUploadNetwork.Answer = .theServerSaysOk, withAStore: Bool = true) async -> ObvReturnReceiptSendManager {
        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: answer)
        self.network = network
        let manager = ObvReturnReceiptSendManager(
            appType: .mainApp,
            containerURL: withAStore ? containerURL : nil,
            runningLog: RunningLogError(),
            uploader: .init(network: network))
        try? await manager.finalizeInitialization(delegate: delegate)
        self.manager = manager
        return manager
    }

    private func receipt(status: ObvReturnReceiptStatus = .delivered, attachmentNumber: Int? = nil) -> ObvReturnReceiptToSend {
        ReturnReceiptTestFactory.receipt(
            contactIdentifier: ReturnReceiptTestFactory.contactIdentifier(contactServerURL: server, ownedServerURL: server),
            nonce: ReturnReceiptTestFactory.nonce(),
            status: status,
            attachmentNumber: attachmentNumber)
    }

    /// The rows left in the store, by identifier.
    private func rowsLeft() throws -> Set<ReturnReceiptIdentifier> {
        let coordinator = try makeCoordinator()
        let values = try read(on: coordinator) { context in
            try PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: self.server, fetchLimit: 1000, within: context)
        }
        return Set(values.map { $0.identifier })
    }

    private func identifiers(of receipts: [ObvReturnReceiptToSend]) -> Set<ReturnReceiptIdentifier> {
        Set(receipts.map { ReturnReceiptIdentifier(returnReceiptToSend: $0) })
    }

    // MARK: - The happy path

    /// A posted receipt is written down, uploaded, and its row goes.
    func testAPostedReceiptIsUploadedAndItsRowGoes() async throws {
        let manager = await makeManager()
        let receipts = [receipt()]

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertEqual(network.requests.count, 1)
        XCTAssertEqual(Set(network.requests.first?.nonces ?? []), Set(receipts.map { $0.elements.nonce }))
        XCTAssertTrue(try rowsLeft().isEmpty, "A receipt the server took leaves no row")
    }


    /// `post` returns before the upload, so the row has to be written before it returns — otherwise a caller that
    /// heard "taken on" would have nothing on disk.
    ///
    /// The network is held, so the send cannot have deleted anything by the time the store is read. This says
    /// nothing about whether the *upload* waits for the row; that is the test below.
    func testPostDoesNotReturnBeforeItsRowsAreWritten() async throws {
        let manager = await makeManager()
        network.holdRequests()
        let receipts = [receipt(), receipt()]

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)

        // Read through a coordinator of its own, so this is the store and not something left in a context.
        XCTAssertEqual(try rowsLeft(), identifiers(of: receipts), "post returned before its rows were written")

        network.releaseRequests()
        await manager.flush()

        XCTAssertTrue(try rowsLeft().isEmpty)
    }


    /// The rows a request carries are in the store **at the moment the request is made**.
    ///
    /// This is the invariant the whole design rests on: an upload interrupted by the process dying is a retry, and
    /// it is only a retry if the row was written first. The store is read from inside the network's own answer, so
    /// it is read at exactly that moment and not afterwards — read afterwards, a save that landed in between would
    /// look the same.
    func testTheRowsOfARequestAreAlreadyInTheStoreWhenItIsMade() async throws {

        let probe = try makeCoordinator()
        let server = self.server
        let rowsWhenTheRequestWasMade = LockedValue<Set<ReturnReceiptIdentifier>>([])

        let network = FakeReturnReceiptUploadNetwork(answering: { _ in
            let context = probe.newBackgroundContext()
            var identifiers = Set<ReturnReceiptIdentifier>()
            context.performAndWait {
                let values = (try? PersistedReturnReceiptToSend.getReturnReceiptsToUpload(forServer: server, fetchLimit: 1000, within: context)) ?? []
                identifiers = Set(values.map { $0.identifier })
            }
            rowsWhenTheRequestWasMade.value = identifiers
            return .theServerSaysOk
        })
        self.network = network
        let manager = ObvReturnReceiptSendManager(appType: .mainApp, containerURL: containerURL, runningLog: RunningLogError(), uploader: .init(network: network))
        try await manager.finalizeInitialization(delegate: delegate)
        self.manager = manager

        let receipts = [receipt(), receipt()]
        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertEqual(network.requests.count, 1, "The probe below means nothing if no request was made")
        XCTAssertEqual(rowsWhenTheRequestWasMade.value, identifiers(of: receipts), "A receipt was uploaded before its row existed")
        XCTAssertTrue(try rowsLeft().isEmpty)

    }


    /// Two receipts of one message — the message and one of its attachments — are two rows and travel together.
    func testTheReceiptsOfOneMessageAndItsAttachmentAreBothSent() async throws {
        let manager = await makeManager()
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: server, ownedServerURL: server)
        let nonce = ReturnReceiptTestFactory.nonce()
        let forTheMessage = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: nonce)
        let forTheAttachment = ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: nonce, attachmentNumber: 0)

        await manager.post([forTheMessage, forTheAttachment], flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertEqual(network.requests.count, 1)
        XCTAssertEqual(network.requests.first?.nonces.count, 2, "Both receipts travel in one request")
        XCTAssertTrue(try rowsLeft().isEmpty)
    }

    // MARK: - An upload that fails

    /// The whole reason for the store. A refused upload leaves the rows, so a later drain can send them again.
    func testRowsSurviveAnUploadTheServerRefused() async throws {
        let manager = await makeManager(answering: .theServerSaysGeneralError)
        let receipts = [receipt(), receipt()]

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertEqual(network.requests.count, 1, "The upload was attempted")
        XCTAssertEqual(try rowsLeft(), identifiers(of: receipts), "A refused upload deletes nothing")
    }


    func testRowsSurviveARequestThatNeverLeftTheDevice() async throws {
        let noConnection = NSError(domain: NSURLErrorDomain, code: Int(CFNetworkErrors.cfurlErrorNotConnectedToInternet.rawValue), userInfo: nil)
        let manager = await makeManager(answering: .theRequestThrows(error: noConnection))
        let receipts = [receipt()]

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertEqual(try rowsLeft(), identifiers(of: receipts))
    }

    // MARK: - The contact's devices, resolved when the receipt is about to leave

    /// A contact with no device: the receipt can never be sent, so the row goes rather than being read by every
    /// drain from now on. Nothing is uploaded for it.
    func testAContactWithNoDeviceHasItsRowDeletedAndNothingUploaded() async throws {
        let manager = await makeManager()
        delegate.setDeviceAnswerByDefault(.theContactHasNoDevice)
        let receipts = [receipt()]

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertTrue(network.requests.isEmpty, "Nothing is uploaded for a receipt with no device to send it to")
        XCTAssertTrue(try rowsLeft().isEmpty, "The row goes: this receipt can never be sent")
    }


    /// A contact that could not be looked up is not the same answer, and must not delete anything: the row stays and
    /// is asked about again later.
    func testAContactThatCannotBeLookedUpKeepsItsRow() async throws {
        let manager = await makeManager()
        delegate.setDeviceAnswerByDefault(.theContactCannotBeLookedUp)
        let receipts = [receipt()]

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertEqual(try rowsLeft(), identifiers(of: receipts), "Not knowing is not the same as knowing there is none")
    }


    /// A lookup that throws says nothing about any contact in the batch, so the whole batch stays.
    func testADeviceLookupThatThrowsKeepsEveryRow() async throws {
        let manager = await makeManager()
        delegate.errorThrownByTheDeviceLookup = NSError(domain: "a.test", code: 1, userInfo: nil)
        let receipts = [receipt(), receipt()]

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertEqual(try rowsLeft(), identifiers(of: receipts))
    }


    /// One contact with no device does not take the others down with it: its row goes, and the rest are uploaded.
    func testOneContactWithoutADeviceDoesNotStopTheOthers() async throws {
        let manager = await makeManager()
        let withoutADevice = receipt()
        let withADevice = receipt()
        delegate.setDeviceAnswer(.theContactHasNoDevice, for: withoutADevice.contactIdentifier)

        await manager.post([withoutADevice, withADevice], flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertEqual(Set(network.requests.flatMap { $0.nonces }), [withADevice.elements.nonce])
        XCTAssertTrue(try rowsLeft().isEmpty, "One row was sent, the other can never be sent — neither stays")
    }

    // MARK: - The seeds

    /// A receipt the identity manager returns no seed for cannot be encrypted, now or ever, so its row goes. This is
    /// the drop the old code made silently, and a row left behind would be read by every drain for ever.
    func testAReceiptWithNoSeedHasItsRowDeleted() async throws {
        let manager = await makeManager()
        let receipts = [receipt()]
        delegate.contactsWithNoSeed = Set(receipts.map { $0.contactIdentifier })

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertTrue(try rowsLeft().isEmpty)
    }


    /// A seed lookup that throws is not an answer about any receipt, so every row stays.
    func testASeedLookupThatThrowsKeepsEveryRow() async throws {
        let manager = await makeManager()
        delegate.errorThrownByTheSeedLookup = NSError(domain: "a.test", code: 1, userInfo: nil)
        let receipts = [receipt(), receipt()]

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertTrue(network.requests.isEmpty)
        XCTAssertEqual(try rowsLeft(), identifiers(of: receipts))
    }

    // MARK: - The sender batches what arrives behind it

    /// Nothing is held back to build a batch, and nothing is sent twice. Several posts made in a row leave in as few
    /// requests as the sender can manage, and every receipt appears exactly once across them.
    func testEverythingPostedIsSentExactlyOnce() async throws {
        let manager = await makeManager()
        var posted = [ObvReturnReceiptToSend]()

        for _ in 0..<10 {
            let receipts = [receipt(), receipt()]
            posted += receipts
            await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        }
        await manager.flush()

        let noncesSent = network.requests.flatMap { $0.nonces }
        XCTAssertEqual(noncesSent.count, posted.count, "A receipt was sent twice, or not at all")
        XCTAssertEqual(Set(noncesSent), Set(posted.map { $0.elements.nonce }))
        XCTAssertLessThan(network.requests.count, posted.count, "The sender batched nothing at all")
        XCTAssertTrue(try rowsLeft().isEmpty)
    }


    /// A cycle takes at most a page's worth, however much was posted at once.
    ///
    /// The post path is bounded by the same number as the sweep, and by the same constant: everything downstream of a
    /// cycle follows from it — what is encrypted before anything is uploaded, and how many requests go at once — and
    /// the path on the receiving side of every message should not be the less bounded of the two.
    func testACycleTakesAtMostAPageEvenWhenMuchMoreIsPostedAtOnce() async throws {
        let manager = await makeManager()
        let receipts = (0..<120).map { _ in receipt() }

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertEqual(delegate.sizesOfTheSeedCalls.max(), 50, "A cycle took more than a page")
        XCTAssertEqual(delegate.sizesOfTheSeedCalls.reduce(0, +), 120, "Every receipt went through a cycle")
        XCTAssertTrue(try rowsLeft().isEmpty)
    }


    /// The same receipt posted twice is **one row**, the store's uniqueness constraint collapsing the two inserts.
    ///
    /// It may leave in one upload or in two, depending on whether the second post arrives before the sender has
    /// taken the first, and that is deliberate: a duplicate costs the server nothing, where holding a receipt back
    /// long enough to notice one is the machinery this design exists without.
    func testTheSameReceiptPostedTwiceIsOneRow() async throws {
        // A server that refuses, so that the rows are still there to be counted.
        let manager = await makeManager(answering: .theServerSaysGeneralError)
        let receipts = [receipt()]

        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.post(receipts, flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertEqual(try rowsLeft(), identifiers(of: receipts))
        XCTAssertEqual(try countOfRows(on: makeCoordinator()), 1, "The uniqueness constraint collapses the two inserts")
    }

    // MARK: - With no store

    /// Degraded, a receipt still goes out. There is no row, so a failed upload loses it — which is what this app did
    /// before the store existed, and is why this mode is a fallback rather than a second guarantee.
    func testWithNoStoreAReceiptIsStillSent() async throws {
        let manager = await makeManager(withAStore: false)
        let canPersist = await manager.receiptsCanBePersisted
        XCTAssertFalse(canPersist)

        await manager.post([receipt()], flowId: FlowIdentifier(), waitUntilSent: false)
        await manager.flush()

        XCTAssertEqual(network.requests.count, 1)
        XCTAssertTrue(try rowsLeft().isEmpty, "There was never a row to leave behind")
    }

}


/// A value written from the network's answer and read from the test. Small enough not to need an actor, and an actor
/// could not be read from a synchronous closure anyway.
final class LockedValue<T>: @unchecked Sendable {

    private let lock = NSLock()
    private var stored: T

    init(_ value: T) {
        self.stored = value
    }

    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

}
