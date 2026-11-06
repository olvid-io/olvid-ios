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


/// The bytes this device puts inside a return receipt, frozen.
///
/// The payload is read by the contact's device, and by Android and by the desktop, none of which are rebuilt when
/// this repository is. So these bytes are not ours to change: a refactor that looks harmless and shifts one of them
/// is a protocol change, and it fails on somebody else's phone rather than here. The literals below were captured
/// from the shipping encoder before the encoding was moved into a type of its own, and they are what makes that move
/// checkable rather than merely reviewable.
///
/// This walks the whole upload path — encrypt, encode, group, and the body of the request — and then decrypts what
/// would have been sent. The payload of the type on its own is frozen in `ObvTypes`, next to the type; this is about
/// what leaves the device.
final class ReturnReceiptPayloadOnTheWireTests: XCTestCase {

    /// Captured on 2026-09-18. A real identity's bytes, kept verbatim so that nothing here depends on how a key pair
    /// is generated.
    private static let ownedIdentityHex = "68747470733a2f2f7365727665722e6f6e652e746573740000989694f173f8ca5334f153bf82790283342f3e28db8e048e1e4780301628c78200c521dcd56c05305a1b5f8c9dfd69ad6204f38ff725b285d62d0724bd5852ef2e"

    /// The payload of a *delivered* receipt about a message: a list of the identity and the status, and nothing else.
    private static let payloadOfAMessageReceiptHex = "030000006c000000005a68747470733a2f2f7365727665722e6f6e652e746573740000989694f173f8ca5334f153bf82790283342f3e28db8e048e1e4780301628c78200c521dcd56c05305a1b5f8c9dfd69ad6204f38ff725b285d62d0724bd5852ef2e01000000080000000000000001"

    /// The payload of a *read* receipt about attachment 3: the same, with a third element.
    private static let payloadOfAnAttachmentReceiptHex = "0300000079000000005a68747470733a2f2f7365727665722e6f6e652e746573740000989694f173f8ca5334f153bf82790283342f3e28db8e048e1e4780301628c78200c521dcd56c05305a1b5f8c9dfd69ad6204f38ff725b285d62d0724bd5852ef2e0100000008000000000000000201000000080000000000000003"


    func testTheBytesOfAMessageReceiptAreTheOnesThatHaveAlwaysBeenSent() async throws {
        let payload = try await payloadThatWouldHaveBeenSent(status: .delivered, attachmentNumber: nil)
        XCTAssertEqual(payload.hexString(), Self.payloadOfAMessageReceiptHex)
    }


    func testTheBytesOfAnAttachmentReceiptAreTheOnesThatHaveAlwaysBeenSent() async throws {
        let payload = try await payloadThatWouldHaveBeenSent(status: .read, attachmentNumber: 3)
        XCTAssertEqual(payload.hexString(), Self.payloadOfAnAttachmentReceiptHex)
    }


    /// Uploads one receipt through the real uploader, takes the body the request would have carried, and decrypts it.
    private func payloadThatWouldHaveBeenSent(status: ObvReturnReceiptStatus, attachmentNumber: Int?) async throws -> Data {

        let ownedCryptoId = try ObvCryptoId(identity: XCTUnwrap(Data(hexString: Self.ownedIdentityHex)))
        // The contact decides where the batch goes and appears nowhere in the payload, so it can be any identity.
        let contactCryptoId = ReturnReceiptTestFactory.cryptoId(onServer: URL(string: "https://server.one.test")!)
        let key = ReturnReceiptTestFactory.key()
        let receiptReadyToUpload = ReturnReceiptTestFactory.receiptReadyToUpload(
            contactIdentifier: .init(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId),
            nonce: ReturnReceiptTestFactory.nonce(),
            status: status,
            attachmentNumber: attachmentNumber,
            key: key)

        let network = FakeReturnReceiptUploadNetwork(alwaysAnswering: .theServerSaysOk)
        _ = await ReturnReceiptUploader(network: network).upload([receiptReadyToUpload], flowId: FlowIdentifier())

        XCTAssertTrue(network.problems.isEmpty, "The fake network could not read the request: \(network.problems)")
        let encryptedPayload = try XCTUnwrap(network.requests.first?.receipts.first?.encryptedPayload)
        let encodedKey = try XCTUnwrap(ObvEncoded(withRawData: key))
        let authenticatedEncryptionKey = try AuthenticatedEncryptionKeyDecoder.decode(encodedKey)
        return try ObvCryptoSuite.sharedInstance.authenticatedEncryption().decrypt(encryptedPayload, with: authenticatedEncryptionKey)

    }

}
