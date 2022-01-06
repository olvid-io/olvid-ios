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
import Compression


struct ObvCompressor {
    
    
    static var errorDomain: String { String(describing: Self.self) }
    static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: Self.errorDomain, code: 0, userInfo: userInfo)
    }

    
    static func compress(_ sourceData: Data) throws -> Data {
    
        // See https://developer.apple.com/documentation/accelerate/compressing_and_decompressing_data_with_buffer_compression
        // We use a method working under iOS 11+. Under iOS 13+, we could use simpler APIs.
        
        var sourceBuffer = [UInt8](sourceData)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: sourceData.count)
        let algorithm = COMPRESSION_ZLIB
        let compressedSize = compression_encode_buffer(destinationBuffer, sourceData.count, &sourceBuffer, sourceData.count, nil, algorithm)
        guard compressedSize > 0 else {
            throw Self.makeError(message: "Compression failed")
        }
        let compressedFullBackupData = Data(bytes: destinationBuffer, count: compressedSize)
        return compressedFullBackupData
        
    }
    
    
    static func decompress(_ compressedData: Data) throws -> Data {
        
        var decodedCapacity = compressedData.count * 8
        let algorithm = COMPRESSION_ZLIB
        // Allow a capacity of about 100MB
        while decodedCapacity < 100_000_000 {

            var success = false

            let fullBackupContent = compressedData.withUnsafeBytes { (encodedSourceBuffer: UnsafeRawBufferPointer) -> Data in
                guard let encodedSourcePtr = encodedSourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    fatalError("Cannot point to data.")
                }
                let decodedDestinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decodedCapacity)
                defer { decodedDestinationBuffer.deallocate() }
                let decodedCharCount = compression_decode_buffer(decodedDestinationBuffer,
                                                                 decodedCapacity,
                                                                 encodedSourcePtr,
                                                                 compressedData.count,
                                                                 nil,
                                                                 algorithm)
                if decodedCharCount == 0 || decodedCharCount == decodedCapacity {
                    success = false
                    return Data()
                } else {
                    success = true
                    return Data(bytes: decodedDestinationBuffer, count: decodedCharCount)
                }
            }
            
            if success {
                return fullBackupContent
            } else {
                decodedCapacity *= 2
            }
        }

        // If we reach this point, something went wrong
        throw Self.makeError(message: "Could not decompress buffer")
        
    }

    
}
