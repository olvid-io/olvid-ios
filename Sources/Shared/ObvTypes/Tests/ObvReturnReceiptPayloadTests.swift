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
import XCTest
@testable import ObvTypes


/// The bytes of a return receipt's payload, frozen.
///
/// This format is not ours alone: the receipt we write is read by a contact's device, which may be an Android or a
/// desktop that this repository does not rebuild, and the receipt we read was written by one. So a change here is a
/// protocol change however innocent it looks, and it fails on somebody else's phone rather than in this file.
///
/// The literals were captured on 2026-09-18, from the encoder that shipped before this type existed — that is, from
/// the two copies of the format this type replaced. They are the evidence that the move changed nothing.
final class ObvReturnReceiptPayloadTests: XCTestCase {

    /// A real identity's bytes, kept verbatim so that nothing here depends on how a key pair is generated.
    private static let authorHex = "68747470733a2f2f7365727665722e6f6e652e746573740000989694f173f8ca5334f153bf82790283342f3e28db8e048e1e4780301628c78200c521dcd56c05305a1b5f8c9dfd69ad6204f38ff725b285d62d0724bd5852ef2e"

    /// A *delivered* receipt about a message: a list of the identity and the status, and nothing else.
    private static let messageReceiptHex = "030000006c000000005a68747470733a2f2f7365727665722e6f6e652e746573740000989694f173f8ca5334f153bf82790283342f3e28db8e048e1e4780301628c78200c521dcd56c05305a1b5f8c9dfd69ad6204f38ff725b285d62d0724bd5852ef2e01000000080000000000000001"

    /// A *read* receipt about attachment 3: the same, with a third element.
    private static let attachmentReceiptHex = "0300000079000000005a68747470733a2f2f7365727665722e6f6e652e746573740000989694f173f8ca5334f153bf82790283342f3e28db8e048e1e4780301628c78200c521dcd56c05305a1b5f8c9dfd69ad6204f38ff725b285d62d0724bd5852ef2e0100000008000000000000000201000000080000000000000003"

    private func author() throws -> ObvCryptoId {
        try ObvCryptoId(identity: XCTUnwrap(Data(hexString: Self.authorHex)))
    }

    // MARK: - The bytes we write

    func testAMessageReceiptEncodesToTheBytesThatHaveAlwaysBeenSent() throws {
        let payload = ObvReturnReceiptPayload(author: try author(), status: .delivered, attachmentNumber: nil)
        XCTAssertEqual(payload.obvEncode().rawData.hexString(), Self.messageReceiptHex)
    }


    func testAnAttachmentReceiptEncodesToTheBytesThatHaveAlwaysBeenSent() throws {
        let payload = ObvReturnReceiptPayload(author: try author(), status: .read, attachmentNumber: 3)
        XCTAssertEqual(payload.obvEncode().rawData.hexString(), Self.attachmentReceiptHex)
    }

    // MARK: - The bytes we read

    /// The same literals from the other side. A receipt sent by a device older than this type must still be read, so
    /// this direction is frozen too, and not merely round-tripped against our own encoder.
    func testTheBytesOfAMessageReceiptAreReadAsTheyHaveAlwaysBeenRead() throws {
        let encoded = try XCTUnwrap(ObvEncoded(withRawData: XCTUnwrap(Data(hexString: Self.messageReceiptHex))))
        let payload = try XCTUnwrap(ObvReturnReceiptPayload(encoded))
        XCTAssertEqual(payload.author, try author())
        XCTAssertEqual(payload.status, .delivered)
        XCTAssertNil(payload.attachmentNumber)
    }


    func testTheBytesOfAnAttachmentReceiptAreReadAsTheyHaveAlwaysBeenRead() throws {
        let encoded = try XCTUnwrap(ObvEncoded(withRawData: XCTUnwrap(Data(hexString: Self.attachmentReceiptHex))))
        let payload = try XCTUnwrap(ObvReturnReceiptPayload(encoded))
        XCTAssertEqual(payload.author, try author())
        XCTAssertEqual(payload.status, .read)
        XCTAssertEqual(payload.attachmentNumber, 3)
    }

    // MARK: - The two directions agree

    /// Cheap, and it covers what the frozen literals cannot: every status, and an attachment number that is not 3.
    func testWhateverIsWrittenIsReadBack() throws {
        for status in [ObvReturnReceiptStatus.delivered, .read] {
            for attachmentNumber in [nil, 0, 1, 7, 4095] as [Int?] {
                let payload = ObvReturnReceiptPayload(author: try author(), status: status, attachmentNumber: attachmentNumber)
                let readBack = try XCTUnwrap(ObvReturnReceiptPayload(payload.obvEncode()))
                XCTAssertEqual(readBack.author, payload.author, "status \(status), attachment \(String(describing: attachmentNumber))")
                XCTAssertEqual(readBack.status, payload.status, "status \(status), attachment \(String(describing: attachmentNumber))")
                XCTAssertEqual(readBack.attachmentNumber, payload.attachmentNumber, "status \(status), attachment \(String(describing: attachmentNumber))")
            }
        }
    }

    // MARK: - What is refused

    /// Note what is *not* tested here: a well-formed list carrying an unknown status. `ObvReturnReceiptStatus`'s own
    /// decoding asserts on one, and an assertion stops a debug build, so no test can walk that path. The shapes below
    /// are the ones reachable without tripping it.
    func testSomethingThatIsNotAPayloadIsRefusedRatherThanRead() throws {

        let author = try author()

        let notAList = 42.obvEncode()
        XCTAssertNil(ObvReturnReceiptPayload(notAList))

        let tooFewElements = [author.getIdentity().obvEncode()].obvEncode()
        XCTAssertNil(ObvReturnReceiptPayload(tooFewElements))

        let fourElements: [ObvEncodable] = [author.getIdentity(), ObvReturnReceiptStatus.read, 3, 4]
        let tooManyElements = fourElements.obvEncode()
        XCTAssertNil(ObvReturnReceiptPayload(tooManyElements))

        let aBadAuthor: [ObvEncodable] = [Data([0x00, 0x01]), ObvReturnReceiptStatus.read]
        let anAuthorThatIsNotAnIdentity = aBadAuthor.obvEncode()
        XCTAssertNil(ObvReturnReceiptPayload(anAuthorThatIsNotAnIdentity))

    }

}
