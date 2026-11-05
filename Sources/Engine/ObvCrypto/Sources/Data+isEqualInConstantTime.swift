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


extension Data {
    
    /// Compares two byte strings in a time that depends on their length only, not on where they first differ. Use it
    /// when one of them is secret or derived from a secret, such as a MAC. The lengths are not secret.
    func isEqualInConstantTime(to other: Data) -> Bool {
        guard count == other.count else { return false }
        guard !isEmpty else { return true }
        return withUnsafeBytes { lhs in
            other.withUnsafeBytes { rhs in
                timingsafe_bcmp(lhs.baseAddress, rhs.baseAddress, count) == 0
            }
        }
    }
    
}
