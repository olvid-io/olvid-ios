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
import ObvCrypto
import ObvEncoder
import ObvTypes
import OlvidUtils
import XCTest
@testable import ObvReturnReceiptSendManager


/// The uploader on its own: what it puts in one request, and what it says about each request afterwards.
///
/// No store and no engine: the uploader is handed its receipts and their seeds, and its network is a fake. The paths
/// worth testing are the failures — a lost connection, a status other than 200, an answer that cannot be read — and a
/// real server offers none of them on demand. What is reported about each one is what decides, later, whether a row
/// is deleted or kept, so these are the tests that stand between a failed upload and a lost receipt.
final class ReturnReceiptUploaderTests: XCTestCase {

    private let firstServer = URL(string: "https://server.one.test")!
    private let secondServer = URL(string: "https://server.two.test")!

    private let flowId = FlowIdentifier()

    /// How many receipts one request may carry. Named here rather than read from the uploader, so that the two have to
    /// agree: a test that read the constant it is testing would pass whatever it became.
    private let expectedNumberOfReceiptsPerRequest = 50

    // MARK: - Helpers

    /// The URL a request to one server is addressed to, built as the server method builds it.
    private func uploadURL(forServer serverURL: URL) -> URL {
        serverURL.appendingPathComponent("/uploadReturnReceipt")
    }

    /// Receipts for one contact, each with a nonce of its own so that a request can be told apart from another.
    ///
    /// One contact identifier for all of them, and not one each: generating an identity generates key pairs, and what
    /// makes two rows different here is the nonce.
    private func receiptsAndSeeds(count: Int, contactIdentifier: ObvContactIdentifier, contactDeviceUIDs: Set<UID>? = nil, key: Data? = nil) -> [ReturnReceiptReadyToUpload] {
        (0..<count).map { _ in
            ReturnReceiptTestFactory.receiptReadyToUpload(
                contactIdentifier: contactIdentifier,
                nonce: ReturnReceiptTestFactory.nonce(),
                key: key,
                contactDeviceUIDs: contactDeviceUIDs)
        }
    }

    /// The requests the fake recorded, having first failed if there was one it could not read.
    ///
    /// Read through this rather than off the fake: the fake reports its own trouble instead of throwing, because a
    /// throw would come back as something the server did.
    private func requests(recordedBy network: FakeReturnReceiptUploadNetwork, file: StaticString = #filePath, line: UInt = #line) -> [FakeReturnReceiptUploadNetwork.Request] {
        for problem in network.problems {
            XCTFail("The fake network could not read a request: \(problem)", file: file, line: line)
        }
        return network.requests
    }

    private func nonces(of receiptsAndSeeds: [ReturnReceiptReadyToUpload]) -> Set<Data> {
        Set(receiptsAndSeeds.map { $0.returnReceipt.identifier.nonce })
    }

    private func identifiers(of receiptsAndSeeds: [ReturnReceiptReadyToUpload]) -> Set<ReturnReceiptIdentifier> {
        Set(receiptsAndSeeds.map { $0.returnReceipt.identifier })
    }

    private func lostConnection(code: CFNetworkErrors) -> Error {
        NSError(domain: NSURLErrorDomain, code: Int(code.rawValue), userInfo: nil)
    }

    // MARK: - Grouping

    func testTheReceiptsOfOneServerMakeOneRequest() async throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let receiptsAndSeeds = receiptsAndSeeds(count: 5, contactIdentifier: contactIdentifier)
        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: .theServerSaysOk)

        let report = await ReturnReceiptUploader(network: network).upload(receiptsAndSeeds, flowId: flowId)

        let requests = requests(recordedBy: network)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url, uploadURL(forServer: firstServer))
        XCTAssertEqual(Set(requests.first?.nonces ?? []), nonces(of: receiptsAndSeeds))

        XCTAssertEqual(report.outcomes.count, 1)
        XCTAssertEqual(report.outcomes.first?.outcome, .theUploadSucceeded)
        XCTAssertEqual(report.outcomes.first?.serverURL, firstServer)
        XCTAssertEqual(Set(report.outcomes.first?.identifiers ?? []), identifiers(of: receiptsAndSeeds))
        XCTAssertTrue(report.identifiersThatCanNeverBeSent.isEmpty)
    }


    /// Two servers make two requests, each carrying only its own. The receipts are interleaved on the way in, so a
    /// grouping that merely preserved the order given would fail here.
    func testTheReceiptsOfTwoServersMakeOneRequestEach() async throws {
        let onFirst = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let onSecond = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: secondServer, ownedServerURL: firstServer)
        let forFirstServer = receiptsAndSeeds(count: 3, contactIdentifier: onFirst)
        let forSecondServer = receiptsAndSeeds(count: 2, contactIdentifier: onSecond)
        let interleaved = [forFirstServer[0], forSecondServer[0], forFirstServer[1], forSecondServer[1], forFirstServer[2]]
        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: .theServerSaysOk)

        let report = await ReturnReceiptUploader(network: network).upload(interleaved, flowId: flowId)

        let requests = requests(recordedBy: network)
        XCTAssertEqual(requests.count, 2)
        let noncesByURL = Dictionary(uniqueKeysWithValues: requests.map { ($0.url, Set($0.nonces)) })
        XCTAssertEqual(noncesByURL[uploadURL(forServer: firstServer)], nonces(of: forFirstServer))
        XCTAssertEqual(noncesByURL[uploadURL(forServer: secondServer)], nonces(of: forSecondServer))

        XCTAssertEqual(report.outcomes.count, 2)
        let identifiersByServer = Dictionary(uniqueKeysWithValues: report.outcomes.map { ($0.serverURL, Set($0.identifiers)) })
        XCTAssertEqual(identifiersByServer[firstServer], identifiers(of: forFirstServer))
        XCTAssertEqual(identifiersByServer[secondServer], identifiers(of: forSecondServer))
    }


    /// The server of the **contact** is what groups a batch, not the server of the owned identity. The two differ on
    /// self-hosted servers, and a batch sent to the wrong one goes nowhere.
    func testTheServerOfTheContactIsWhatDecidesWhereABatchGoes() async throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: secondServer)
        let receiptsAndSeeds = receiptsAndSeeds(count: 2, contactIdentifier: contactIdentifier)
        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: .theServerSaysOk)

        _ = await ReturnReceiptUploader(network: network).upload(receiptsAndSeeds, flowId: flowId)

        let requests = requests(recordedBy: network)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url, uploadURL(forServer: firstServer))
    }

    // MARK: - Slicing

    /// A hundred and twenty receipts for one server make three requests, not a hundred and twenty.
    func testAServersReceiptsAreCutIntoRequestsOfFiftyAtMost() async throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let receiptsAndSeeds = receiptsAndSeeds(count: 120, contactIdentifier: contactIdentifier)
        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: .theServerSaysOk)

        let report = await ReturnReceiptUploader(network: network).upload(receiptsAndSeeds, flowId: flowId)

        let requests = requests(recordedBy: network)
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requests.map { $0.nonces.count }.sorted(), [20, expectedNumberOfReceiptsPerRequest, expectedNumberOfReceiptsPerRequest])

        // Every receipt travelled, and none of them travelled twice: a request carrying a receipt a second time would
        // be a row deleted by one request and sent again by another.
        let noncesSent = requests.flatMap { $0.nonces }
        XCTAssertEqual(noncesSent.count, 120)
        XCTAssertEqual(Set(noncesSent), nonces(of: receiptsAndSeeds))

        XCTAssertEqual(report.outcomes.count, 3)
        let identifiersReported = report.outcomes.flatMap { $0.identifiers }
        XCTAssertEqual(identifiersReported.count, 120)
        XCTAssertEqual(Set(identifiersReported), identifiers(of: receiptsAndSeeds))
    }

    // MARK: - What is reported about a request

    func testAGeneralErrorFromTheServerIsReportedAsAFailure() async throws {
        let report = await uploadOneReceipt(answering: .theServerSaysGeneralError)
        XCTAssertEqual(report.outcomes.first?.outcome, .theUploadFailed)
    }


    func testAStatusOtherThan200IsReportedAsAFailure() async throws {
        let report = await uploadOneReceipt(answering: .theServerAnswers(statusCode: 500))
        XCTAssertEqual(report.outcomes.first?.outcome, .theUploadFailed)
    }


    func testAnAnswerThatCannotBeReadIsReportedAsAFailure() async throws {
        let report = await uploadOneReceipt(answering: .theBodyCannotBeParsed)
        XCTAssertEqual(report.outcomes.first?.outcome, .theUploadFailed)
    }


    /// The two failures are not the same failure, and the difference is what saves a backlog: a receipt old enough to
    /// be given up on is deleted once an attempt has been answered, so a device that could not reach a server at all
    /// must not count as an attempt.
    ///
    /// The cases below are the ones that destroy a backlog when they are read as a refusal — a phone abroad with data
    /// roaming off is the five weeks the age cap was written for, and no request ever left it.
    func testEveryErrorMeaningNoServerSawTheRequestIsReportedApartFromARefusal() async throws {

        let cases: [(what: String, error: Error, expected: ReturnReceiptUploadOutcome.Outcome)] = [
            ("not connected to the internet", lostConnection(code: .cfurlErrorNotConnectedToInternet), .theRequestNeverLeftTheDevice),
            ("the network connection was lost", lostConnection(code: .cfurlErrorNetworkConnectionLost), .theRequestNeverLeftTheDevice),
            ("the host cannot be connected to", lostConnection(code: .cfurlErrorCannotConnectToHost), .theRequestNeverLeftTheDevice),
            ("the host cannot be found", lostConnection(code: .cfurlErrorCannotFindHost), .theRequestNeverLeftTheDevice),
            ("the DNS lookup failed", lostConnection(code: .cfurlErrorDNSLookupFailed), .theRequestNeverLeftTheDevice),
            ("it timed out", lostConnection(code: .cfurlErrorTimedOut), .theRequestNeverLeftTheDevice),
            ("data roaming is off", lostConnection(code: .cfurlErrorInternationalRoamingOff), .theRequestNeverLeftTheDevice),
            ("cellular data is not allowed", lostConnection(code: .cfurlErrorDataNotAllowed), .theRequestNeverLeftTheDevice),
            ("a call is active", lostConnection(code: .cfurlErrorCallIsActive), .theRequestNeverLeftTheDevice),
            ("the secure connection failed", lostConnection(code: .cfurlErrorSecureConnectionFailed), .theRequestNeverLeftTheDevice),
            ("it was cancelled", lostConnection(code: .cfurlErrorCancelled), .theRequestNeverLeftTheDevice),
            ("the URL is unsupported", lostConnection(code: .cfurlErrorUnsupportedURL), .theUploadFailed),
            ("an error of another domain", NSError(domain: "a.domain.of.our.own", code: 1, userInfo: nil), .theUploadFailed),
        ]

        for (what, error, expected) in cases {
            let report = await uploadOneReceipt(answering: .theRequestThrows(error: error))
            XCTAssertEqual(report.outcomes.first?.outcome, expected, "When the upload fails because \(what)")
        }

    }


    /// One server failing says nothing about another. Each request is settled on its own answer.
    func testAServerFailingLeavesWhatAnotherServerTookReportedAsSent() async throws {
        let onFirst = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let onSecond = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: secondServer, ownedServerURL: firstServer)
        let forFirstServer = receiptsAndSeeds(count: 2, contactIdentifier: onFirst)
        let forSecondServer = receiptsAndSeeds(count: 2, contactIdentifier: onSecond)
        let noncesForTheSecondServer = nonces(of: forSecondServer)
        let network = FakeReturnReceiptUploadNetwork { request in
            guard let nonce = request.nonces.first else { return .theServerSaysOk }
            return noncesForTheSecondServer.contains(nonce) ? .theServerSaysGeneralError : .theServerSaysOk
        }

        let report = await ReturnReceiptUploader(network: network).upload(forFirstServer + forSecondServer, flowId: flowId)

        XCTAssertEqual(requests(recordedBy: network).count, 2)
        XCTAssertEqual(report.outcomes.count, 2)
        let outcomesByServer = Dictionary(uniqueKeysWithValues: report.outcomes.map { ($0.serverURL, $0.outcome) })
        XCTAssertEqual(outcomesByServer[firstServer], .theUploadSucceeded)
        XCTAssertEqual(outcomesByServer[secondServer], .theUploadFailed)
    }

    // MARK: - The receipts that can never be sent

    /// A receipt with no contact device to send to reaches no request, and must be reported all the same: unreported,
    /// its row is never deleted and every drain from now on reads it again.
    func testAReceiptWithNoContactDeviceIsReportedAsOneThatCanNeverBeSent() async throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let receiptsAndSeeds = receiptsAndSeeds(count: 1, contactIdentifier: contactIdentifier, contactDeviceUIDs: [])
        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: .theServerSaysOk)

        let report = await ReturnReceiptUploader(network: network).upload(receiptsAndSeeds, flowId: flowId)

        XCTAssertTrue(requests(recordedBy: network).isEmpty, "Nothing is uploaded for a receipt with no device")
        XCTAssertTrue(report.outcomes.isEmpty)
        XCTAssertEqual(Set(report.identifiersThatCanNeverBeSent), identifiers(of: receiptsAndSeeds))
    }


    /// Same for a receipt whose key cannot be read. The row is unusable, and deleting it is the only way it stops
    /// being read.
    func testAReceiptWhoseKeyCannotBeReadIsReportedAsOneThatCanNeverBeSent() async throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let receiptsAndSeeds = receiptsAndSeeds(count: 1, contactIdentifier: contactIdentifier, key: Data([0xff]))
        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: .theServerSaysOk)

        let report = await ReturnReceiptUploader(network: network).upload(receiptsAndSeeds, flowId: flowId)

        XCTAssertTrue(requests(recordedBy: network).isEmpty)
        XCTAssertTrue(report.outcomes.isEmpty)
        XCTAssertEqual(Set(report.identifiersThatCanNeverBeSent), identifiers(of: receiptsAndSeeds))
    }


    /// Every receipt handed in is reported exactly once, whichever way it went. This is what lets a caller account for
    /// a whole batch: what is not reported as sent, and not reported as unsendable, is kept.
    func testEveryReceiptIsReportedExactlyOnce() async throws {
        let onFirst = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let onSecond = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: secondServer, ownedServerURL: firstServer)
        let taken = receiptsAndSeeds(count: 2, contactIdentifier: onFirst)
        let refused = receiptsAndSeeds(count: 2, contactIdentifier: onSecond)
        let withoutADevice = receiptsAndSeeds(count: 1, contactIdentifier: onFirst, contactDeviceUIDs: [])
        let all = taken + refused + withoutADevice
        let noncesRefused = nonces(of: refused)
        let network = FakeReturnReceiptUploadNetwork { request in
            guard let nonce = request.nonces.first else { return .theServerSaysOk }
            return noncesRefused.contains(nonce) ? .theServerAnswers(statusCode: 503) : .theServerSaysOk
        }

        let report = await ReturnReceiptUploader(network: network).upload(all, flowId: flowId)

        let reported = report.outcomes.flatMap { $0.identifiers } + report.identifiersThatCanNeverBeSent
        XCTAssertEqual(reported.count, all.count, "A receipt reported twice, or not at all")
        XCTAssertEqual(Set(reported), identifiers(of: all))

        let succeeded = report.outcomes.filter { $0.outcome == .theUploadSucceeded }.flatMap { $0.identifiers }
        XCTAssertEqual(Set(succeeded), identifiers(of: taken))
        let failed = report.outcomes.filter { $0.outcome != .theUploadSucceeded }.flatMap { $0.identifiers }
        XCTAssertEqual(Set(failed), identifiers(of: refused))
        XCTAssertEqual(Set(report.identifiersThatCanNeverBeSent), identifiers(of: withoutADevice))
    }

    // MARK: - The bytes that leave

    /// The payload is what the receiving side reads back: the owned identity, the status, and the attachment number
    /// when there is one. This encoding belongs to the contact's device as much as to us, so moving this code must not
    /// have changed a byte of it.
    func testThePayloadIsTheOneTheReceivingSideReads() async throws {

        for attachmentNumber in [nil, 3] as [Int?] {

            let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
            let key = ReturnReceiptTestFactory.key()
            let deviceUID = ReturnReceiptTestFactory.deviceUID()
            let nonce = ReturnReceiptTestFactory.nonce()
            let receiptReadyToUpload = ReturnReceiptTestFactory.receiptReadyToUpload(
                contactIdentifier: contactIdentifier,
                nonce: nonce,
                status: .read,
                attachmentNumber: attachmentNumber,
                key: key,
                contactDeviceUIDs: [deviceUID])
            let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: .theServerSaysOk)

            _ = await ReturnReceiptUploader(network: network).upload([receiptReadyToUpload], flowId: flowId)

            let request = try XCTUnwrap(requests(recordedBy: network).first)
            let receipt = try XCTUnwrap(request.receipts.first)
            XCTAssertEqual(receipt.toIdentity, contactIdentifier.contactCryptoId.getIdentity())
            XCTAssertEqual(receipt.deviceUids, [deviceUID.raw])
            XCTAssertEqual(receipt.nonce, nonce)

            // Decrypted and decoded the way the receiving side does it.
            let encodedKey = try XCTUnwrap(ObvEncoded(withRawData: key))
            let authenticatedEncryptionKey = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
            let payload = try ObvCryptoSuite.sharedInstance.authenticatedEncryption().decrypt(receipt.encryptedPayload, with: authenticatedEncryptionKey)
            let encodedPayload = try XCTUnwrap(ObvEncoded(withRawData: payload))
            let fields = try XCTUnwrap([ObvEncoded](encodedPayload))

            XCTAssertEqual(fields.count, attachmentNumber == nil ? 2 : 3)
            XCTAssertEqual(Data(fields[0]), contactIdentifier.ownedCryptoId.getIdentity())
            XCTAssertEqual(ObvReturnReceiptStatus(fields[1]), .read)
            if let attachmentNumber {
                XCTAssertEqual(Int(fields[2]), attachmentNumber)
            }

        }

    }


    /// The encryption is seeded rather than random, so that a receipt produced twice — by two owned devices, or by two
    /// processes of this one — encrypts to the same bytes and the server sees the second for the duplicate it is. This
    /// design pays in duplicates instead of in machinery to prevent them, so a random nonce here would cost the
    /// sender's phone the redundant work on every one.
    func testTheSameReceiptAndSeedGiveTheSameBytesTwice() async throws {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let returnReceipt = ReturnReceiptToUpload(
            returnReceiptToSend: ReturnReceiptTestFactory.receipt(contactIdentifier: contactIdentifier, nonce: ReturnReceiptTestFactory.nonce()),
            createdAt: Date.now)
        let seed = ReturnReceiptTestFactory.seed()
        let anotherSeed = ReturnReceiptTestFactory.seed()

        let first = try await encryptedPayload(of: returnReceipt, seed: seed)
        let second = try await encryptedPayload(of: returnReceipt, seed: seed)
        let withAnotherSeed = try await encryptedPayload(of: returnReceipt, seed: anotherSeed)

        XCTAssertEqual(first, second, "The same receipt and the same seed must encrypt to the same bytes")
        XCTAssertNotEqual(first, withAnotherSeed, "Two seeds that differ must not give the same bytes, or the seed is not being used")
    }

    // MARK: - Smaller helpers

    private func uploadOneReceipt(answering answer: FakeReturnReceiptUploadNetwork.Answer) async -> ReturnReceiptUploadReport {
        let contactIdentifier = ReturnReceiptTestFactory.contactIdentifier(contactServerURL: firstServer, ownedServerURL: firstServer)
        let receiptsAndSeeds = receiptsAndSeeds(count: 1, contactIdentifier: contactIdentifier)
        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: answer)
        let report = await ReturnReceiptUploader(network: network).upload(receiptsAndSeeds, flowId: flowId)
        XCTAssertEqual(report.outcomes.count, 1, "One receipt makes one request, whatever the answer to it")
        XCTAssertEqual(Set(report.outcomes.first?.identifiers ?? []), identifiers(of: receiptsAndSeeds), "A failed request must still say what it carried")
        return report
    }


    private func encryptedPayload(of returnReceipt: ReturnReceiptToUpload, seed: Seed) async throws -> Data {
        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: .theServerSaysOk)
        let readyToUpload = ReturnReceiptReadyToUpload(returnReceipt: returnReceipt, contactDeviceUIDs: [ReturnReceiptTestFactory.deviceUID()], seed: seed)
        _ = await ReturnReceiptUploader(network: network).upload([readyToUpload], flowId: flowId)
        let request = try XCTUnwrap(requests(recordedBy: network).first)
        let receipt = try XCTUnwrap(request.receipts.first)
        return receipt.encryptedPayload.raw
    }

}
