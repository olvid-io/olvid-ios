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


/// This very simple `ByteCountFormatter` overrides the ``string(fromByteCount byteCount: Int64)`` method to return the word "Unlimited" if the `byCount` is negative.
/// It is typically used to show automatic download sizes for attachments.
final class ObvPositiveByteCountFormatter: ByteCountFormatter {
    
    override func string(fromByteCount byteCount: Int64) -> String {
        if byteCount >= 0 {
            return super.string(fromByteCount: byteCount)
        } else {
            return CommonString.Word.Unlimited
        }
    }
    
}
