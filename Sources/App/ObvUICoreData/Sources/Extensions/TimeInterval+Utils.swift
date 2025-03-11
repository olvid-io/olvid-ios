/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


extension TimeInterval {
    
    static func optionalMin(_ val1: TimeInterval?, _ val2: TimeInterval?) -> TimeInterval? {
        switch (val1, val2) {
        case (.none, .none):
            return nil
        case (.some(let val), .none):
            return val
        case (.none, .some(let val)):
            return val
        case (.some(let v1), .some(let v2)):
            return min(v1, v2)
        }
    }
}
