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
import CommonCrypto


public protocol HashFunction {
    static var outputLength: Int { get }
    static func hash(_ data: Data) -> Data
    static func hash(fileAtUrl url: URL) throws -> Data
}


protocol HashFunctionBasedOnCommonCrypto {
    static var ccOutputLength: Int32 { get }
    static var ccBlockLength: Int32 { get }
    static func ccHash(_ data: UnsafeRawPointer!, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>!) -> UnsafeMutablePointer<UInt8>!
    init()
    func ccHashUpdate(_ data: UnsafeRawPointer!, _ len: CC_LONG)
    func ccHashFinal(_ md: UnsafeMutablePointer<UInt8>!)
}


extension HashFunction where Self: HashFunctionBasedOnCommonCrypto {
    
    static func makeError(message: String) -> Error { NSError(domain: "HashFunction", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    static var outputLength: Int {
        return Int(ccOutputLength)
    }

    static func hash(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0x00, count: outputLength)
        let dataLength = CC_LONG(data.count)
        data.withUnsafeBytes {
            _ = ccHash($0.baseAddress!, dataLength, &hash)
        }

        return Data(hash)
    }
    
    
    static func hash(fileAtUrl url: URL) throws -> Data {

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw Self.makeError(message: "Hash computation failed as there is no file at the specified URL")
        }
        
        let hashFunction = Self()
        
        guard let fileStream = InputStream(fileAtPath: url.path) else {
            throw Self.makeError(message: "Failed to create InputStream")
        }
        fileStream.open()
        let bufferSize = 64_000
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while fileStream.hasBytesAvailable {
            let read = fileStream.read(buffer, maxLength: bufferSize)
            guard read >= 0 else { throw NSError(domain: "HashFunction", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: "Could not read file"]) }
            hashFunction.ccHashUpdate(buffer, UInt32(read))
        }
        
        var hash = [UInt8](repeating: 0x00, count: outputLength)
        hashFunction.ccHashFinal(&hash)
        
        return Data(hash)

    }

}

final class SHA256: HashFunctionBasedOnCommonCrypto, HashFunction {

    static var ccBlockLength: Int32 {
        return CC_SHA256_BLOCK_BYTES
    }
    
    static var ccOutputLength: Int32 {
        return CC_SHA256_DIGEST_LENGTH
    }

    static func ccHash(_ data: UnsafeRawPointer!, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>!) -> UnsafeMutablePointer<UInt8>! {
        return CC_SHA256(data, len, md)
    }
    
    private var context: CC_SHA256_CTX
    
    required init() {
        context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)
    }
    
    func ccHashUpdate(_ data: UnsafeRawPointer!, _ len: CC_LONG) {
        CC_SHA256_Update(&self.context, data, len)
    }
    
    func ccHashFinal(_ md: UnsafeMutablePointer<UInt8>!) {
        CC_SHA256_Final(md, &self.context)
    }
}


final class SHA512: HashFunctionBasedOnCommonCrypto, HashFunction {

    static var ccBlockLength: Int32 {
        return CC_SHA512_BLOCK_BYTES
    }
    
    static var ccOutputLength: Int32 {
        return CC_SHA512_DIGEST_LENGTH
    }

    static func ccHash(_ data: UnsafeRawPointer!, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>!) -> UnsafeMutablePointer<UInt8>! {
        return CC_SHA512(data, len, md)
    }
    
    private var context: CC_SHA512_CTX
    
    required init() {
        context = CC_SHA512_CTX()
        CC_SHA512_Init(&context)
    }
    
    func ccHashUpdate(_ data: UnsafeRawPointer!, _ len: CC_LONG) {
        CC_SHA512_Update(&self.context, data, len)
    }
    
    func ccHashFinal(_ md: UnsafeMutablePointer<UInt8>!) {
        CC_SHA512_Final(md, &self.context)
    }
}
