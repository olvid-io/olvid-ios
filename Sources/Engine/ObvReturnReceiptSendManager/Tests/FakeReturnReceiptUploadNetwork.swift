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
@testable import ObvReturnReceiptSendManager


/// A network that answers whatever a test asks it to, and records what it was given to send.
///
/// It reads each request back off the wire rather than being told what is in it: the server it is addressed to comes
/// from the request's own URL, and what it carries is decoded from the body. So a test of the grouping and of the
/// slicing is a test of the bytes that would have left the device, and not of a counter the uploader was kind enough
/// to keep.
///
/// It never throws when it cannot read a body, and that is deliberate: the uploader turns every error into a failed
/// upload, so a fake that threw would report its own confusion as something the server did. It records the trouble
/// instead, under ``problems``, and a test reads the requests through a helper that fails on a non-empty list.
final class FakeReturnReceiptUploadNetwork: ReturnReceiptUploadNetwork, @unchecked Sendable {

    /// One receipt, as it appeared in the body of a request.
    struct Receipt {
        let toIdentity: Data
        let deviceUids: [Data]
        let nonce: Data
        let encryptedPayload: EncryptedData
    }

    /// One request, as this fake read it.
    struct Request {
        /// The URL the request was addressed to, path included.
        let url: URL?
        /// What the body carried, in the order it carried it.
        let receipts: [Receipt]
        /// A test gives every receipt a nonce of its own, so this says exactly which receipts travelled together.
        var nonces: [Data] { receipts.map { $0.nonce } }
    }

    /// What the fake answers to one request.
    enum Answer {
        case theServerSaysOk
        case theServerSaysGeneralError
        case theServerAnswers(statusCode: Int)
        /// A 200 whose body is not an encoding at all.
        ///
        /// Note that this is *not* a well-formed answer carrying an unknown status byte: the server method asserts on
        /// that, and an assertion stops a debug build.
        case theBodyCannotBeParsed
        /// The call throws, as it does when the request never leaves the device.
        case theRequestThrows(error: Error)
    }

    private let lock = NSLock()
    private var requestsRecorded = [Request]()
    private var problemsFound = [String]()
    private var requestsAreHeld = false
    private var heldRequests = [CheckedContinuation<Void, Never>]()
    private let answer: @Sendable (Request) -> Answer

    /// - Parameter answer: consulted per request, so that a test can have one server answer and another fail.
    init(answering answer: @escaping @Sendable (Request) -> Answer) {
        self.answer = answer
    }

    convenience init(alwaysAnswering answer: Answer) {
        self.init(answering: { _ in answer })
    }

    /// Every request made, in the order the fake was called. Requests are uploaded concurrently, so a test must not
    /// read anything into that order.
    var requests: [Request] {
        lock.withLock { requestsRecorded }
    }

    /// Whatever this fake could not make sense of. A test that reads the requests must check that this is empty, or
    /// it is reading nothing and passing.
    var problems: [String] {
        lock.withLock { problemsFound }
    }

    /// Makes every upload wait before it answers, so that a test can look at the store while a send is in flight.
    func holdRequests() {
        lock.withLock { requestsAreHeld = true }
    }


    func releaseRequests() {
        let toResume: [CheckedContinuation<Void, Never>] = lock.withLock {
            requestsAreHeld = false
            let held = heldRequests
            heldRequests = []
            return held
        }
        toResume.forEach { $0.resume() }
    }


    private func waitIfRequestsAreHeld() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let isHeld: Bool = lock.withLock {
                guard requestsAreHeld else { return false }
                heldRequests.append(continuation)
                return true
            }
            // Resumed outside the lock, which is the one thing a continuation must never be resumed inside.
            if !isHeld { continuation.resume() }
        }
    }


    func upload(_ request: URLRequest, from dataToSend: Data) async throws -> (Data, URLResponse) {

        let recorded = Request(url: request.url, receipts: receipts(in: dataToSend))
        lock.withLock { requestsRecorded.append(recorded) }

        await waitIfRequestsAreHeld()

        let url = request.url ?? URL(string: "https://a.request.without.a.url")!

        switch answer(recorded) {
        case .theServerSaysOk:
            return (Self.answerOfTheServer(rawStatus: 0x00), Self.httpResponse(url: url, statusCode: 200))
        case .theServerSaysGeneralError:
            return (Self.answerOfTheServer(rawStatus: 0xff), Self.httpResponse(url: url, statusCode: 200))
        case .theServerAnswers(statusCode: let statusCode):
            return (Self.answerOfTheServer(rawStatus: 0x00), Self.httpResponse(url: url, statusCode: statusCode))
        case .theBodyCannotBeParsed:
            return (Data([0x01, 0x02, 0x03]), Self.httpResponse(url: url, statusCode: 200))
        case .theRequestThrows(error: let error):
            throw error
        }

    }


    /// What the body carries, decoded from the bytes themselves.
    private func receipts(in dataToSend: Data) -> [Receipt] {

        guard let encoded = ObvEncoded(withRawData: dataToSend) else {
            note("A body that is not an encoding")
            return []
        }
        guard let encodedReceipts = [ObvEncoded](encoded) else {
            note("A body that is not a list of receipts")
            return []
        }

        var receipts = [Receipt]()
        for encodedReceipt in encodedReceipts {
            guard let fields = [ObvEncoded](encodedReceipt), fields.count == 4 else {
                note("A receipt that is not a list of four fields")
                continue
            }
            guard let toIdentity = Data(fields[0]),
                  let encodedDeviceUids = [ObvEncoded](fields[1]),
                  let nonce = Data(fields[2]),
                  let encryptedPayload = EncryptedData(fields[3]) else {
                note("A receipt whose fields are not the expected ones")
                continue
            }
            let deviceUids = encodedDeviceUids.compactMap { Data($0) }
            guard deviceUids.count == encodedDeviceUids.count else {
                note("A receipt with a device UID that cannot be read")
                continue
            }
            receipts.append(.init(toIdentity: toIdentity, deviceUids: deviceUids, nonce: nonce, encryptedPayload: encryptedPayload))
        }
        return receipts

    }


    private func note(_ problem: String) {
        lock.withLock { problemsFound.append(problem) }
    }


    /// What the server answers: a list whose first element is the one-byte status.
    private static func answerOfTheServer(rawStatus: UInt8) -> Data {
        [Data([rawStatus]).obvEncode()].obvEncode().rawData
    }


    private static func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }

}
