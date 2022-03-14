/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

import Darwin
import CoreFoundation
import ObvEncoder


public final class EncryptedData: NSObject, Sequence, Xorable, Authenticable, Decodable, ObvCodable {
    
    static func makeError(message: String) -> Error { NSError(domain: "EncryptedData", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    public typealias Index = Data.Index

    fileprivate let _data: Data

    // MARK: Creating Populated Encrypted Data
    
    public init(bytes: [UInt8]) {
        _data = Data(bytes)
    }
    
    public init(encryptedData: EncryptedData) {
        _data = encryptedData._data
    }
    
    public init(data: Data) {
        _data = data
    }
    
    public convenience init(byte: UInt8) {
        self.init(bytes: [byte])
    }
    
    public static func byAppending(c1: EncryptedData, c2: EncryptedData) -> EncryptedData {
        let resLength = c1.count + c2.count
        guard resLength > 0 else { return EncryptedData(bytes: []) }
        var res = Data(count: resLength)
        res.withUnsafeMutableBytes { (bufferPtr) in
            let ptr = bufferPtr.baseAddress!.bindMemory(to: UInt8.self, capacity: resLength)
            c1._data.copyBytes(to: ptr, count: c1.count)
            c2._data.copyBytes(to: ptr.advanced(by: c1.count), count: c2.count)
        }
        return EncryptedData(data: res)
    }
    

    func removingLast(_ n: Int) -> EncryptedData {
        let nbrToRemove = Swift.min(n, self._data.count)
        let range = self._data.startIndex..<self._data.endIndex-nbrToRemove
        let data = self._data[range]
        return EncryptedData(data: data)
    }

    
    // MARK: Interfacing Encrypted Bytes
    
    public var first: UInt8? {
        return _data.first
    }
    
    public var startIndex: EncryptedData.Index {
        return _data.startIndex
    }
    
    public var endIndex: EncryptedData.Index {
        return _data.endIndex
    }
    
    public var count: Int {
        return _data.count
    }
    
    public subscript(bounds: CountableRange<Int>) -> EncryptedData {
        return EncryptedData(data: _data[bounds])
    }
    
    subscript(index: Int) -> UInt8 {
        return _data[index]
    }

    // MARK: Accessing Underlying Memory
    
    public func withUnsafeBytes<ResultType>(_ body: (UnsafeRawBufferPointer) throws -> ResultType) rethrows -> ResultType {
        return try _data.withUnsafeBytes(body)
    }
    
    public var raw: Data {
        return self._data
    }

    // MARK: Hashable
    
    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(self._data)
        return hasher.finalize()
    }

    // MARK: Equatable
    
    public static func == (lhs: EncryptedData, rhs: EncryptedData) -> Bool {
        return [UInt8](lhs._data) == [UInt8](rhs._data)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        if let o = object as? EncryptedData {
            return self == o
        } else {
            return false
        }
    }

    
    // MARK: Sequence
    
    public func makeIterator() -> EncryptedData.Iterator {
        return EncryptedData.Iterator(self)
    }
    
    public struct Iterator: IteratorProtocol {
        
        private var dataIterator: Data.Iterator
        
        fileprivate init(_ bytes: EncryptedData) {
            dataIterator = bytes._data.makeIterator()
        }
        
        public mutating func next() -> UInt8? {
            return dataIterator.next()
        }
        
    }
    
    // MARK: Other functions
    
    public static func concatenate(_ arrayOfEncryptedDatas: [EncryptedData]) -> EncryptedData {
        let arrayOfData = arrayOfEncryptedDatas.map() { $0._data }
        let data = arrayOfData.reduce(Data()) { $0 + $1 }
        return EncryptedData(data: data)
    }
    
}

// MARK: EncryptedData implements Decodable (for Json parsing)
extension EncryptedData {
    public convenience init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let encryptedDataAsString = try container.decode(String.self)
        if let encryptedDataAsData = encryptedDataAsString.dataFromHexString() {
            self.init(data: encryptedDataAsData)
        } else {
            throw Self.makeError(message: "Failed to get hex string from encryptedDataAsString")
        }
    }
}

// MARK: Implementing ObvCodable
extension EncryptedData {
    
    public convenience init?(_ encoded: ObvEncoded) {
        guard let raw = Data(encoded) else { return nil }
        self.init(data: raw)
    }
    
    public func encode() -> ObvEncoded {
        return self.raw.encode()
    }

}

extension Data: Xorable, Authenticable {
    
    init(encryptedData: EncryptedData) {
        self = encryptedData._data
    }
    
}


extension Array where Element == UInt8 {
    
    public init(encryptedData: EncryptedData) {
        self = [UInt8](encryptedData._data)
    }
    
}

extension String {
    
    public func bytes(using encoding: String.Encoding) -> EncryptedData? {
        var bytes: EncryptedData? = nil
        if let data = self.data(using: encoding) {
            bytes = EncryptedData(data: data)
        }
        return bytes
    }
    
}

// Creating a subclass of ValueTransformer for EncryptedData, making it easy to use EncryptedData within Core Data

public class EncryptedDataTransformer: ValueTransformer {
    
    override public class func transformedValueClass() -> AnyClass {
        return EncryptedData.self
    }
    
    override public class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    override public func transformedValue(_ value: Any?) -> Any? {
        guard let encryptedData = value as? EncryptedData else { return nil }
        return encryptedData._data
    }
    
    override public func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let data = value as? Data else { return nil }
        return EncryptedData(data: data)
    }
    
}

public extension NSValueTransformerName {
    static let encryptedDataTransformerName = NSValueTransformerName(rawValue: "EncryptedDataTransformer")
}
