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


public extension Data {

    /// A total order on `Data`: the shorter comes first, and data of the same length compare byte by byte.
    ///
    /// This is the order of `ObvCryptoId`'s `<` on the bytes of the identities, so stored identity bytes sort the same
    /// way whether or not they can be parsed. It is a named function rather than a `Comparable` conformance, so that it
    /// cannot clash with a conformance of `Data` declared elsewhere.
    static func isLessThan(lhs: Data, rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return lhs.count < rhs.count }
        let bytesPair = zip(lhs, rhs)
        for bytes in bytesPair {
            guard bytes.0 != bytes.1 else { continue }
            return bytes.0 < bytes.1
        }
        return false
    }
    
    func isLessThan(_ other: Data) -> Bool {
        Self.isLessThan(lhs: self, rhs: other)
    }

}
