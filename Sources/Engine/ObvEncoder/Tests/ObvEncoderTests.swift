//
//  Olvid for iOS
//  Copyright © 2019-2024 Olvid SAS
//
//  This file is part of Olvid for iOS.
//
//  Olvid is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License, version 3,
//  as published by the Free Software Foundation.
//
//  Olvid is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with Olvid.  If not, see  &lt;https://www.gnu.org/licenses/>.
//

import XCTest
import CoreData
import ObvBigInt
@testable import ObvEncoder


class ObvEncoderTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    
    func testEncodeBigUInt() {
        
        // 72399060075591592624572526114977173298662156850259520786814677005338978386724
        // -->
        // [0x80, 0x00, 0x00, 0x00, 0x20, 0xa0, 0x10, 0x6a, 0x75, 0x5d,
        //  0x1d, 0x0e, 0x97, 0x28, 0x5c, 0x2a, 0x7a, 0x5c, 0x0f, 0x7d,
        //  0x07, 0xc1, 0x95, 0x73, 0xf9, 0x14, 0x57, 0x47, 0xb1, 0x40,
        //  0xbe, 0xd4, 0x16, 0xdc, 0x11, 0x83, 0x24]
        // (on 32 bytes)
        var bigUInt = try! BigInt("72399060075591592624572526114977173298662156850259520786814677005338978386724")
        var expectedEncodedData = Data([0x80, 0x00, 0x00, 0x00, 0x20, 0xa0, 0x10, 0x6a, 0x75, 0x5d,
                                        0x1d, 0x0e, 0x97, 0x28, 0x5c, 0x2a, 0x7a, 0x5c, 0x0f, 0x7d,
                                        0x07, 0xc1, 0x95, 0x73, 0xf9, 0x14, 0x57, 0x47, 0xb1, 0x40,
                                        0xbe, 0xd4, 0x16, 0xdc, 0x11, 0x83, 0x24])
        var encodedBigUInt = bigUInt.encode(withInnerLength: 32)!
        XCTAssertEqual(encodedBigUInt.rawData, expectedEncodedData)
        XCTAssertEqual(encodedBigUInt.byteId, .unsignedBigInt)
        XCTAssertEqual(encodedBigUInt.innerLength, 32)
        XCTAssertEqual(encodedBigUInt.innerData, expectedEncodedData[expectedEncodedData.startIndex+5..<expectedEncodedData.endIndex])
        
        // 59370277011258412601622539077162503415510402938343119375943754216280422553279 --> [0x80, 0x0, 0x0, 0x0, 0x20, 0x83, 0x42, 0x62, 0xce, 0x94, 0xee, 0xa, 0x6e, 0x6e, 0xa4, 0x2, 0xcb, 0x32, 0xd0, 0xca, 0x63, 0xc, 0xf7, 0x3f, 0xd4, 0x1a, 0xd1, 0x41, 0x0, 0x53, 0xaf, 0x2d, 0xc7, 0xeb, 0x23, 0x16, 0xbf] (on 32 bytes)
        bigUInt = try! BigInt("59370277011258412601622539077162503415510402938343119375943754216280422553279")
        expectedEncodedData = Data([0x80, 0x0, 0x0, 0x0, 0x20, 0x83, 0x42, 0x62, 0xce, 0x94, 0xee, 0xa, 0x6e, 0x6e, 0xa4, 0x2, 0xcb, 0x32, 0xd0, 0xca, 0x63, 0xc, 0xf7, 0x3f, 0xd4, 0x1a, 0xd1, 0x41, 0x0, 0x53, 0xaf, 0x2d, 0xc7, 0xeb, 0x23, 0x16, 0xbf])
        encodedBigUInt = bigUInt.obvEncode() // Given the big int, the expected inner length is 32
        XCTAssertEqual(encodedBigUInt.rawData, expectedEncodedData)
        XCTAssertEqual(encodedBigUInt.byteId, .unsignedBigInt)
        XCTAssertEqual(encodedBigUInt.innerLength, 32)
        XCTAssertEqual(encodedBigUInt.innerData, expectedEncodedData[expectedEncodedData.startIndex+5..<expectedEncodedData.endIndex])
        
        // 59370277011258412601622539077162503415510402938343119375943754216280422553279 does not fit 31 bytes
        bigUInt = try! BigInt("59370277011258412601622539077162503415510402938343119375943754216280422553279")
        if let _ = bigUInt.encode(withInnerLength: 31) {
            XCTFail() // encode should fail since 31 is too short
        }
        
        // 106876946424785803459796743605700683520045764932744458309366185345474129141241 --> [0x80, 0x0, 0x0, 0x0, 0x28, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xec, 0x4a, 0x35, 0x3e, 0x74, 0x7e, 0x7e, 0x3f, 0x87, 0x8a, 0x52, 0x1d, 0x43, 0xe9, 0xff, 0x7f, 0x6f, 0x13, 0x66, 0x44, 0xef, 0xb, 0x52, 0xa7, 0x30, 0xc, 0x12, 0x6, 0x5c, 0x49, 0x9d, 0xf9] (on 40 bytes)
        bigUInt = try! BigInt("106876946424785803459796743605700683520045764932744458309366185345474129141241")
        expectedEncodedData = Data([0x80, 0x0, 0x0, 0x0, 0x28, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0xec, 0x4a, 0x35, 0x3e, 0x74, 0x7e, 0x7e, 0x3f, 0x87, 0x8a, 0x52, 0x1d, 0x43, 0xe9, 0xff, 0x7f, 0x6f, 0x13, 0x66, 0x44, 0xef, 0xb, 0x52, 0xa7, 0x30, 0xc, 0x12, 0x6, 0x5c, 0x49, 0x9d, 0xf9])
        encodedBigUInt = bigUInt.encode(withInnerLength: 40)!
        XCTAssertEqual(encodedBigUInt.rawData, expectedEncodedData)
        XCTAssertEqual(encodedBigUInt.byteId, .unsignedBigInt)
        XCTAssertEqual(encodedBigUInt.innerLength, 40)
        XCTAssertEqual(encodedBigUInt.innerData, expectedEncodedData[expectedEncodedData.startIndex+5..<expectedEncodedData.endIndex])
        
    }
    
    func testEncodeThenDecodeBigUInt() {
        
        var bigUInt = try! BigInt("72399060075591592624572526114977173298662156850259520786814677005338978386724")
        var encodedBigUInt = bigUInt.obvEncode()
        var decodedBigUInt = BigInt(encodedBigUInt)!
        XCTAssertEqual(bigUInt, decodedBigUInt)
        
        bigUInt = try! BigInt("59370277011258412601622539077162503415510402938343119375943754216280422553279")
        encodedBigUInt = bigUInt.obvEncode()
        decodedBigUInt = BigInt(encodedBigUInt)!
        XCTAssertEqual(bigUInt, decodedBigUInt)
        
        bigUInt = try! BigInt("106876946424785803459796743605700683520045764932744458309366185345474129141241")
        encodedBigUInt = bigUInt.encode(withInnerLength: 40)!
        decodedBigUInt = BigInt(encodedBigUInt)!
        XCTAssertEqual(bigUInt, decodedBigUInt)
    }
    
    func testInitWithBytesAndDecodeObvEncodedBytes() {
        
        var data = Data([0x00])
        var encodedData = data.obvEncode()
        var expectedEncodedData = Data([0x00, 0x00, 0x00, 0x00, 0x01, 0x00])
        XCTAssertEqual(encodedData.rawData, expectedEncodedData)
        
        data = Data([1, 2, 3, 4, 5, 6])
        encodedData = data.obvEncode()
        expectedEncodedData = Data([0x00, 0x00, 0x00, 0x00, 0x06, 1, 2, 3, 4, 5, 6])
        XCTAssertEqual(encodedData.rawData, expectedEncodedData)
        
    }
    
    func testEncodeList() {
        
        // We create a simple list made of one element
        var encodedData = Data([1,2,3,4]).obvEncode()
        var encodedList = [encodedData].obvEncode()
        var expectedEncodedListData = Data([0x03, 0, 0, 0, 9, 0x00, 0, 0, 0, 4, 1, 2, 3, 4])
        XCTAssertEqual(encodedList.rawData, expectedEncodedListData)
        
        // We encode a list made of two encoded elements (encoded bytes, then encoded big int)
        encodedData = Data([1,2,3,4]).obvEncode()
        let bigInt = try! BigInt("72399060075591592624572526114977173298662156850259520786814677005338978386724")
        let encodedBigInt = bigInt.encode(withInnerLength: 32)!
        XCTAssert(encodedBigInt.isEncodingOf(.unsignedBigInt))
        encodedList = [encodedData, encodedBigInt].obvEncode()
        XCTAssert(encodedList.isEncodingOf(.list))
        expectedEncodedListData = Data([0x3, 0x0, 0x0, 0x0, 0x2e, 0x0, 0x0, 0x0, 0x0, 0x4, 0x1, 0x2, 0x3, 0x4, 0x80, 0x0, 0x0, 0x0, 0x20, 0xa0, 0x10, 0x6a, 0x75, 0x5d, 0x1d, 0xe, 0x97, 0x28, 0x5c, 0x2a, 0x7a, 0x5c, 0xf, 0x7d, 0x7, 0xc1, 0x95, 0x73, 0xf9, 0x14, 0x57, 0x47, 0xb1, 0x40, 0xbe, 0xd4, 0x16, 0xdc, 0x11, 0x83, 0x24])
        XCTAssertEqual(encodedList.rawData, expectedEncodedListData)
    }
    
    func testEncodeThenDecodeList() {
        let encodedBytes = Data([1,2,3,4]).obvEncode()
        let bigInt = try! BigInt("72399060075591592624572526114977173298662156850259520786814677005338978386724")
        let encodedBigUInt = bigInt.encode(withInnerLength: 32)!
        let encodedList = [encodedBytes, encodedBigUInt].obvEncode()
        XCTAssert(encodedList.isEncodingOf(.list))
        XCTAssert(!encodedList.isEncodingOf(.unsignedBigInt))
        let decodedList = [ObvEncoded](encodedList)!
        XCTAssertEqual(decodedList, [encodedBytes, encodedBigUInt])
    }
    
    
    func testEncodeObvDictionary() {
        
        let key = "myBigInt".data(using: .utf8)!
        let val = try! BigInt("123456789123456789012345")
        let encodedVal = val.encode(withInnerLength: 10)!
        let obvDict: ObvDictionary = [key: encodedVal]
        let encodedDict = obvDict.obvEncode()
        
        // Compute the expected encoded dictionary data "by hand"
        let sizeOfEncodedKey = UInt8(1 + 4 + 8)
        let bytesOfEncodedKey: [UInt8] = [0x00, 0, 0, 0, 8, 109, 121, 66, 105, 103, 73, 110, 116]
        let sizeofEncodedVal = UInt8(1 + 4 + 10)
        var expectedEncodedData = Data([0x04, 0, 0, 0, sizeOfEncodedKey + sizeofEncodedVal])
        expectedEncodedData.append(Data(bytesOfEncodedKey))
        expectedEncodedData.append(encodedVal.rawData)
        // Compare
        XCTAssertEqual(encodedDict.rawData, expectedEncodedData)
    }
    
    func testEncodeThenDecodeAnObvDictonaryContainingAnEncodedArray() {
        
        let encodedBytes = Data([1, 2, 3, 4, 5]).obvEncode()
        let encodedBigInt = (try! BigInt("1234567890")).obvEncode()
        let encodedList = [encodedBytes, encodedBigInt].obvEncode()
        let otherEncodedBytes = Data([1, 2, 3, 4, 5, 6, 7, 8, 9]).obvEncode()
        let obvDict = ["myList".data(using: .utf8)!: encodedList,
                       "myOtherBytes".data(using: .utf8)!: otherEncodedBytes]
        let encodedDict = obvDict.obvEncode()
        // We decode the dictionary then compare
        let decodedDict = ObvDictionary(encodedDict)!
        XCTAssertEqual(decodedDict, obvDict)
        
    }
    
    func testEncodeThenDecodeObvDictionary() {
        let key1 = "myBigInt".data(using: .utf8)!
        let val1 = try! BigInt("123456789123456789012345")
        let encodedVal1 = val1.encode(withInnerLength: 10)!
        let key2 = "myByteArray".data(using: .utf8)!
        let val2 = Data([0x00, 0x01, 0xff, 0x43])
        let encodedVal2 = val2.obvEncode()
        let obvDict: ObvDictionary = [key1: encodedVal1,
                                      key2: encodedVal2]
        let encodedObvDict = obvDict.obvEncode()
        guard var decodedObvDict = ObvDictionary(encodedObvDict) else { XCTFail(); return }
        XCTAssertEqual(obvDict, decodedObvDict)
        decodedObvDict.removeValue(forKey: key1)
        XCTAssertNotEqual(obvDict, decodedObvDict)
    }
    
    func testTransformer() {
        let encodedBigInt = (try! BigInt("1234567890")).obvEncode()
        let transformer = ObvEncodedTransformer()
        let transformed = transformer.transformedValue(encodedBigInt) as! Data
        let recoveredEncodedBigInt = transformer.reverseTransformedValue(transformed) as! ObvEncoded
        XCTAssertEqual(encodedBigInt, recoveredEncodedBigInt)
    }
    
    func testLengthEncode() {
        // Encoding a length should be identical to encode a big uint over 8 bytes, and to change the byte id from 0x80 to 0x01
        for _ in 0..<100 {
            let length: Int = Int(arc4random()) // 32 bits
            let encodedLength = length.obvEncode()
            let encodeLengthAsEncodedBigInt = BigInt(Int(length)).encode(withInnerLength: 8)!
            XCTAssertEqual(encodedLength.rawData.count, encodeLengthAsEncodedBigInt.rawData.count)
            for i in 1..<encodedLength.rawData.count {
                XCTAssertEqual(encodedLength.rawData[i], encodeLengthAsEncodedBigInt.rawData[i])
            }
        }
    }
    
    func testLengthEncodeThenDecode() {
        for _ in 0..<100 {
            let length: Int = Int(arc4random()) // 32 bits
            let encodedLength = length.obvEncode()
            XCTAssertEqual(length, Int(encodedLength)!)
        }
        for testLength in 0..<100 {
            let length: Int = Int(testLength)
            let encodedLength = length.obvEncode()
            XCTAssertEqual(length, Int(encodedLength)!)
        }
    }
    
    func testEncodeBool() {
        for b in [true, false] {
            let obvEncoded = b.obvEncode()
            XCTAssertEqual(b, Bool(obvEncoded))
        }
    }
    
    
    func testEncodeArrayUsingConditionalConformance() {
        
        let encodableObj1 = "testing".data(using: .utf8)!
        let encodableObj2 = try! BigInt.init("4573657843265978436582658473658946578346584638256486598648256438926584639854365239")
        let encodableObj3 = 13
        
        let arrayOfObvEncodable: [ObvEncodable] = [encodableObj1, encodableObj2, encodableObj3]
        let encodedArray1 = arrayOfObvEncodable.obvEncode()
        
        let arrayOfObvEncoded = [encodableObj1.obvEncode(), encodableObj2.obvEncode(), encodableObj3.obvEncode()]
        let encodedArray2 = arrayOfObvEncoded.obvEncode()
        
        XCTAssertEqual(encodedArray1, encodedArray2)
        
        // We try a shorter way, using type inference
        let encodedArray3 = [encodableObj1, encodableObj2, encodableObj3].obvEncode()
        
        XCTAssertEqual(encodedArray1, encodedArray3)
    }


    func testTypedDecoderWithTwoTypes() {
        let val1 = 5
        let val2 = "Coucou".data(using: .utf8)!
        let encoded = [val1, val2].obvEncode()
        
        do {
            let decodedVal1: Int
            let decodedVal2: Data
            do {
                (decodedVal1, decodedVal2) = try encoded.obvDecode()
            } catch { XCTFail(); return }
            XCTAssertEqual(val1, decodedVal1)
            XCTAssertEqual(val2, decodedVal2)
        }
        
        // Try with a list of ObvEncoded
        let listOfEncoded = ([val1, val2] as [ObvEncodable]).map { $0.obvEncode() }
        do {
            let decodedVal1: Int
            let decodedVal2: Data
            do {
                (decodedVal1, decodedVal2) = try listOfEncoded.obvDecode()
            } catch { XCTFail(); return }
            XCTAssertEqual(val1, decodedVal1)
            XCTAssertEqual(val2, decodedVal2)
        }
        
    }

    func testTypedDecoderWithThreeTypes() {
        let val1 = 5
        let val2 = "Coucou".data(using: .utf8)!
        let val3 = true
        let encoded = [val1, val2, val3].obvEncode()
        let decodedVal1: Int
        let decodedVal2: Data
        let decodedVal3: Bool
        do {
            (decodedVal1, decodedVal2, decodedVal3) = try encoded.obvDecode()
        } catch { XCTFail(); return }
        XCTAssertEqual(val1, decodedVal1)
        XCTAssertEqual(val2, decodedVal2)
        XCTAssertEqual(val3, decodedVal3)
    }

    func testTypedDecoderWithFourTypes() {
        let val1 = 5
        let val2 = "Coucou".data(using: .utf8)!
        let val3 = true
        let val4 = 13
        let encoded = [val1, val2, val3, val4].obvEncode()
        let decodedVal1: Int
        let decodedVal2: Data
        let decodedVal3: Bool
        let decodedVal4: Int
        do {
            (decodedVal1, decodedVal2, decodedVal3, decodedVal4) = try encoded.obvDecode()
        } catch { XCTFail(); return }
        XCTAssertEqual(val1, decodedVal1)
        XCTAssertEqual(val2, decodedVal2)
        XCTAssertEqual(val3, decodedVal3)
        XCTAssertEqual(val4, decodedVal4)
    }
    
    
    func testEncodePaddedData() {
        for i in 0..<5000 {
            let dataToEncode = Data(repeating: 0xaa, count: i)
            let encoded = dataToEncode.obvEncode()
            for paddingLength in [1, 10, 100, 1_000, 10_000] {
                let paddedRawData = encoded.rawData + Data(repeating: 0x00, count: paddingLength)
                // Check that the normal ObvEncoded init fails
                XCTAssertNil(ObvEncoded(withRawData: paddedRawData))
                // Check that the ObvEncoded init that accepts padded data does not fail
                let obvEncoded = ObvEncoded(withPaddedRawData: paddedRawData)
                XCTAssertNotNil(obvEncoded)
                // Check the decoded data matches
                let decodedData = Data(obvEncoded!)
                XCTAssertNotNil(decodedData)
                XCTAssertEqual(dataToEncode, decodedData)
            }
        }
    }
}
