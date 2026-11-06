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
@testable import ObvEncoder


/// Checks that an encoded value decodes only when its elements use exactly the bytes it declares.
///
/// An encoded value is a byte identifier, a 4-byte big-endian inner length, and the inner data. A list or a dictionary
/// packs its elements, each encoded the same way, in its inner data. These tests check that bytes after the last element
/// are refused, at the top level and inside a list or a dictionary; that an element declaring more bytes than remain is
/// refused, up to the largest length 4 bytes can hold; and that a padded value still decodes when the padding comes after
/// the declared length, and only then.
final class ObvEncodedStrictDecodingTests: XCTestCase {

    private let listOfTwo = [Data([0x01, 0x02, 0x03]).obvEncode(), 42.obvEncode()]


    // MARK: - The top level

    func testAWellFormedValueDecodes() throws {
        let raw = listOfTwo.obvEncode().rawData
        let encoded = try XCTUnwrap(ObvEncoded(withRawData: raw))
        XCTAssertEqual([ObvEncoded](encoded)?.count, 2)
    }


    func testBytesAfterTheDeclaredLengthAreRefused() {
        let raw = listOfTwo.obvEncode().rawData
        XCTAssertNil(ObvEncoded(withRawData: raw + Data([0x00])))
        XCTAssertNil(ObvEncoded(withRawData: raw + Data(repeating: 0x00, count: 5)))
    }


    func testAValueShorterThanItsDeclaredLengthIsRefused() {
        let raw = listOfTwo.obvEncode().rawData
        XCTAssertNil(ObvEncoded(withRawData: raw.dropLast()))
        XCTAssertNil(ObvEncoded(withRawData: Data([ByteIdOfObvEncoded.list.rawValue, 0x00, 0x00])))
    }


    func testTheLargestDeclaredLengthIsRefusedWithoutCrashing() {
        let raw = Data([ByteIdOfObvEncoded.bytes.rawValue, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x02])
        XCTAssertNil(ObvEncoded(withRawData: raw))
        XCTAssertNil(ObvEncoded(withPaddedRawData: raw))
    }


    // MARK: - Inside a list

    func testTrailingBytesInsideAListAreRefused() {
        for junkCount in 1...4 {
            let list = listWithInnerData(packedInnerData(listOfTwo) + Data(repeating: 0x00, count: junkCount))
            XCTAssertNil([ObvEncoded](list), "\(junkCount) trailing bytes")
        }
    }


    /// The second element declares 4 bytes of inner data where only 3 remain in the list.
    func testAnElementLongerThanTheListIsRefused() {
        let overlongElement = Data([ByteIdOfObvEncoded.bytes.rawValue, 0x00, 0x00, 0x00, 0x04, 0x01, 0x02, 0x03])
        let inner = listOfTwo[0].rawData + overlongElement
        XCTAssertNil([ObvEncoded](listWithInnerData(inner)))
        let fittingElement = Data([ByteIdOfObvEncoded.bytes.rawValue, 0x00, 0x00, 0x00, 0x03, 0x01, 0x02, 0x03])
        XCTAssertEqual([ObvEncoded](listWithInnerData(listOfTwo[0].rawData + fittingElement))?.count, 2)
    }


    func testAnElementDeclaringTheLargestLengthIsRefusedWithoutCrashing() {
        let inner = Data([ByteIdOfObvEncoded.bytes.rawValue, 0xFF, 0xFF, 0xFF, 0xFF, 0x01, 0x02, 0x03])
        XCTAssertNil([ObvEncoded](listWithInnerData(inner)))
    }


    // MARK: - Inside a dictionary

    func testAWellFormedDictionaryDecodes() throws {
        let dictionary: ObvDictionary = [Data("a".utf8): 1.obvEncode(), Data("b".utf8): 2.obvEncode()]
        let decoded = try XCTUnwrap(ObvDictionary(dictionary.obvEncode()))
        XCTAssertEqual(decoded.count, 2)
    }


    func testTrailingBytesInsideADictionaryAreRefused() {
        let dictionary: ObvDictionary = [Data("a".utf8): 1.obvEncode()]
        let inner = dictionary.obvEncode().innerData
        for junkCount in 1...4 {
            let encoded = ObvEncoded(byteId: .dictionary, innerData: inner + Data(repeating: 0x00, count: junkCount))
            XCTAssertNil(ObvDictionary(encoded), "\(junkCount) trailing bytes")
        }
    }


    func testADictionaryWithAKeyAndNoValueIsRefused() {
        let dictionary: ObvDictionary = [Data("a".utf8): 1.obvEncode()]
        let inner = dictionary.obvEncode().innerData + Data("b".utf8).obvEncode().rawData
        XCTAssertNil(ObvDictionary(ObvEncoded(byteId: .dictionary, innerData: inner)))
    }


    // MARK: - Padding

    func testPaddingAfterTheDeclaredLengthIsAccepted() throws {
        let raw = listOfTwo.obvEncode().rawData
        let encoded = try XCTUnwrap(ObvEncoded(withPaddedRawData: raw + Data(repeating: 0x00, count: 37)))
        XCTAssertEqual(encoded.rawData, raw)
    }


    func testPaddingDoesNotExcuseTrailingBytesInsideTheList() throws {
        let raw = listWithInnerData(packedInnerData(listOfTwo) + Data([0x00, 0x00])).rawData
        let encoded = try XCTUnwrap(ObvEncoded(withPaddedRawData: raw + Data(repeating: 0x00, count: 37)))
        XCTAssertNil([ObvEncoded](encoded))
    }


    /// The padded bytes are a slice that starts at index 7. A slice keeps the indices of the data it was cut from, so a
    /// decoder that sliced from index 0 would trap here: index 0 is outside the slice.
    func testAPaddedValueDecodesFromASliceThatDoesNotStartAtZero() throws {
        let raw = listOfTwo.obvEncode().rawData
        let container = Data(repeating: 0xAA, count: 7) + raw + Data(repeating: 0x00, count: 37)
        let slice = container[container.startIndex+7..<container.endIndex]
        XCTAssertEqual(slice.startIndex, 7)
        let encoded = try XCTUnwrap(ObvEncoded(withPaddedRawData: slice))
        XCTAssertEqual(encoded.rawData, raw)
        XCTAssertEqual([ObvEncoded](encoded)?.count, 2)
    }


    func testPaddedValueShorterThanItsDeclaredLengthIsRefused() {
        let raw = listOfTwo.obvEncode().rawData
        XCTAssertNil(ObvEncoded(withPaddedRawData: raw.dropLast()))
    }


    // MARK: - Helpers

    private func packedInnerData(_ elements: [ObvEncoded]) -> Data {
        elements.reduce(into: Data()) { $0.append($1.rawData) }
    }


    /// A list whose inner data is given as is, with a header that declares exactly its length.
    private func listWithInnerData(_ innerData: Data) -> ObvEncoded {
        ObvEncoded(byteId: .list, innerData: innerData)
    }

}
