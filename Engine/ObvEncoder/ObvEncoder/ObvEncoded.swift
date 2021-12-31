/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import BigInt
import ObvTypes
import os.log

public enum ByteIdOfObvEncoded: UInt8 {
    case bytes = 0x00
    case int = 0x01
    case bool = 0x02
    case unsignedBigInt = 0x80
    case list = 0x03
    case dictionary = 0x04
    case symmetricKey = 0x90
    case publicKey = 0x91
    case privateKey = 0x92
}


final public class ObvEncoded: NSObject, Decodable {
    
    private static let lengthOfInnerLength = 4
    public static let lengthOverhead = 1 + ObvEncoded.lengthOfInnerLength
    
    public let byteId: ByteIdOfObvEncoded
    public let innerData: Data
    var innerLength: Int {
        return innerData.count
    }
    
    public var rawData: Data {
        let innerDataCount = innerData.count
        var encodedData = Data(count: 5 + innerDataCount)
        
        encodedData.withUnsafeMutableBytes { (encodedDataBufferPtr) in
            encodedDataBufferPtr[0] = byteId.rawValue
            encodedDataBufferPtr[1] = UInt8((innerLength >> 24) & 0xFF)
            encodedDataBufferPtr[2] = UInt8((innerLength >> 16) & 0xFF)
            encodedDataBufferPtr[3] = UInt8((innerLength >> 8) & 0xFF)
            encodedDataBufferPtr[4] = UInt8((innerLength) & 0xFF)
            let ptr = encodedDataBufferPtr.baseAddress!.bindMemory(to: UInt8.self, capacity: 5 + innerDataCount)
            innerData.copyBytes(to: ptr.advanced(by: 5), count: innerDataCount)
        }
        
        return encodedData
    }
    
    public static func == (lhs: ObvEncoded, rhs: ObvEncoded) -> Bool {
        return [UInt8](lhs.rawData) == [UInt8](rhs.rawData)
    }
    
    public static func != (lhs: ObvEncoded, rhs: ObvEncoded) -> Bool {
        return [UInt8](lhs.rawData) != [UInt8](rhs.rawData)
    }
    
    public override func isEqual(_ object: Any?) -> Bool {
        if let o = object as? ObvEncoded {
            return self == o
        } else {
            return false
        }
    }

    
    public init(byteId: ByteIdOfObvEncoded, innerData: Data) {
        self.byteId = byteId
        self.innerData = innerData
    }
    
    static let log = OSLog(subsystem: "io.olvid.ObvEncoder.ObvEncoded", category: "Encoder")
    
    public init?(withRawData data: Data) {
        guard data.count >= ObvEncoded.lengthOverhead else { return nil }
        guard let byteId = ByteIdOfObvEncoded(rawValue: data.first!) else { return nil }
        self.byteId = byteId
        let rangeOfInnerLength = data.startIndex+1..<data.startIndex+1+ObvEncoded.lengthOfInnerLength
        let innerLength = ObvEncoded.lengthFrom(lengthAsData: data[rangeOfInnerLength])
        guard ObvEncoded.lengthOverhead + innerLength == data.count else { return nil }        
        self.innerData = data[data.startIndex+ObvEncoded.lengthOverhead..<data.endIndex]
    }
    
    public func isEncodingOf(_ byteId: ByteIdOfObvEncoded) -> Bool {
        return self.byteId == byteId
    }
}

// MARK: Strongly type generic `decode` methods. These methods leverages the similar methods declared for the type `[ObvEncoded]` within the corresponding type extension.
extension ObvEncoded {
    
    public func decode<DecodedType: ObvDecodable>() throws -> DecodedType {
        guard let decodedValue: DecodedType = DecodedType(self) else { throw NSError() }
        return decodedValue
    }
    
    public func decode<T0: ObvDecodable, T1: ObvDecodable>() throws -> (T0, T1) {
        guard let encodedElements = [ObvEncoded](self, expectedCount: 2) else { throw NSError() }
        return try encodedElements.decode()
    }

    public func decode<T0: ObvDecodable, T1: ObvDecodable, T2: ObvDecodable>() throws -> (T0, T1, T2) {
        guard let encodedElements = [ObvEncoded](self, expectedCount: 3) else { throw NSError() }
        return try encodedElements.decode()
    }

    public func decode<T0: ObvDecodable, T1: ObvDecodable, T2: ObvDecodable, T3: ObvDecodable>() throws -> (T0, T1, T2, T3) {
        guard let encodedElements = [ObvEncoded](self, expectedCount: 4) else { throw NSError() }
        return try encodedElements.decode()
    }

    public func decode<T0: ObvDecodable, T1: ObvDecodable, T2: ObvDecodable, T3: ObvDecodable, T4: ObvDecodable>() throws -> (T0, T1, T2, T3, T4) {
        guard let encodedElements = [ObvEncoded](self, expectedCount: 5) else { throw NSError() }
        return try encodedElements.decode()
    }

    public func decode<T0: ObvDecodable, T1: ObvDecodable, T2: ObvDecodable, T3: ObvDecodable, T4: ObvDecodable, T5: ObvDecodable>() throws -> (T0, T1, T2, T3, T4, T5) {
        guard let encodedElements = [ObvEncoded](self, expectedCount: 6) else { throw NSError() }
        return try encodedElements.decode()
    }

    public func decode<T0: ObvDecodable, T1: ObvDecodable, T2: ObvDecodable, T3: ObvDecodable, T4: ObvDecodable, T5: ObvDecodable, T6: ObvDecodable>() throws -> (T0, T1, T2, T3, T4, T5, T6) {
        guard let encodedElements = [ObvEncoded](self, expectedCount: 7) else { throw NSError() }
        return try encodedElements.decode()
    }

}

// MARK: Pack and unpack
extension ObvEncoded {
    
    /// Returns an ObvEncoded instance that "packs" all the encoded elements passed in parameter in one large encoded element. The byte identifier of this "packed" element must be specified when calling this function.
    ///
    /// - Parameters:
    ///   - _: The array of all the encoded elements to pack.
    ///   - usingByteId: The byte identifier of the resulting encoded value returned by this method.
    /// - Returns: An encoded element that "packs" all the encoded element into one encoded element.
    public static func pack(_ encodedElements: [ObvEncoded], usingByteId byteId: ByteIdOfObvEncoded) -> ObvEncoded {
        
        let innerDataLength = encodedElements.reduce(0) { $0 + $1.rawData.count }
        var innerData = Data(count: innerDataLength)
        
        innerData.withUnsafeMutableBytes { (innerDataBufferPtr) in
            let ptr = innerDataBufferPtr.baseAddress!.bindMemory(to: UInt8.self, capacity: innerDataLength)
            var offset = 0
            encodedElements.forEach { (encodedElement) in
                let count = encodedElement.rawData.count
                encodedElement.rawData.copyBytes(to: ptr.advanced(by: offset), count: count)
                offset += count
            }
        }

        return ObvEncoded(byteId: byteId, innerData: innerData)
    }
    
    /// Returns the byte identifier of the encoded value, as well as all the encoded elements contained within the supposly packed structure.
    ///
    /// - Parameter encodedPack: An encoded element that is expected to contain several "packed" encoded elements.
    /// - Returns: A list of all the encoded elements contained within the "packed" structure.
    /// - Throws: An error if the inner data of the structure is not a proper "pack" of several encoded elements.
    public static func unpack(_ encodedPack: ObvEncoded) -> [ObvEncoded]? {
        var listOfEncodedElements = [ObvEncoded]()
        var remainingInnerData = encodedPack.innerData
        while remainingInnerData.count > 0 {
            guard let (encodedElement, remainingData) = ObvEncoded.getNextEncodedElementAndRemainingInnerData(fromInnerData: remainingInnerData) else { return nil }
            listOfEncodedElements.append(encodedElement)
            remainingInnerData = remainingData
        }
        return listOfEncodedElements
    }
    
    private static func getNextEncodedElementAndRemainingInnerData(fromInnerData data: Data) -> (encodedElement: ObvEncoded, data: Data)? {
        guard data.count >= ObvEncoded.lengthOverhead else {
            os_log("Expecting at least 5 bytes of inner data, got %d", log: ObvEncoded.log, type: .error)
            return nil
        }
        let rangeOfInnerLength = data.startIndex+1..<data.startIndex+1+ObvEncoded.lengthOfInnerLength
        let innerLengthOfNextContainer = ObvEncoded.lengthFrom(lengthAsData: data[rangeOfInnerLength])
        if data.count < ObvEncoded.lengthOverhead + innerLengthOfNextContainer {
            os_log("Unexpected data count during unpack", log: ObvEncoded.log, type: .error)
            return nil
        }
        let byteId = ByteIdOfObvEncoded(rawValue: data[data.startIndex])
        guard byteId != nil else {
            os_log("Could not recover the encoded byte id", log: ObvEncoded.log, type: .error)
            return nil
        }
        let rangeOfInnerDataOfNextContainer = data.startIndex+ObvEncoded.lengthOverhead..<data.startIndex+ObvEncoded.lengthOverhead+innerLengthOfNextContainer
        let nextContainer = ObvEncoded(byteId: byteId!, innerData: data[rangeOfInnerDataOfNextContainer])
        let rangeOfRemainingInnerData = data.startIndex+ObvEncoded.lengthOverhead+innerLengthOfNextContainer..<data.endIndex
        let remainingInnerData = data[rangeOfRemainingInnerData]
        return (nextContainer, remainingInnerData)
    }
    
    static func lengthFrom(lengthAsData: Data) -> Int {
        var length = 0
        for i in lengthAsData.startIndex..<lengthAsData.endIndex {
            length = (length << 8) | Int(lengthAsData[i])
        }
        return length
    }
    
}


// MARK: ObvEncoded implements Decodable (for Json parsing)
extension ObvEncoded {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let encodedDataAsString = try container.decode(String.self)
        if let encodedDataAsRawData = encodedDataAsString.dataFromHexString(),
            ObvEncoded(withRawData: encodedDataAsRawData) != nil {
            self.init(withRawData: encodedDataAsRawData)!
        } else {
            throw NSError()
        }
    }
}
