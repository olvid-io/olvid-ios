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

enum ObvCryptoError: Error {
    case inputSizesDoNotMatch
    
    var localizedDescription: String {
        switch self {
        case .inputSizesDoNotMatch:
            return NSLocalizedString("Input sizes do not match", comment: "Error message")
        }
    }
}

protocol Xorable: Sequence {
    
    var count: Int { get }
    
    subscript(index: Int) -> UInt8 { get }
    
    var startIndex: Data.Index { get }
    
}



extension Data {
    static func xor<T1: Xorable, T2: Xorable>(_ data1: T1, _ data2: T2) throws -> Data {
        guard data1.count == data2.count else { throw ObvCryptoError.inputSizesDoNotMatch }
        var res = Data()
        for i in 0..<data1.count {
            res.append(data1[data1.startIndex + i] ^ data2[data2.startIndex + i])
        }
        return res
    }
}
