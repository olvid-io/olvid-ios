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

extension Range: ObvCodable where Element == Int {
    
    
    public func obvEncode() -> ObvEncoded {
        return [self.lowerBound, self.upperBound].obvEncode()
    }

    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded, expectedCount: 2) else { return nil }
        guard let lowerBound = Int(listOfEncoded.first!) else { return nil }
        guard let upperBound = Int(listOfEncoded.last!) else { return nil }
        self = lowerBound..<upperBound
    }
    
    
}
