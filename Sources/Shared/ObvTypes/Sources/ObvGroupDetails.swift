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


public struct ObvGroupDetails: Equatable {

    public let coreDetails: ObvGroupCoreDetails
    public let photoURL: URL?

    public init(coreDetails: ObvGroupCoreDetails, photoURL: URL?) {
        self.coreDetails = coreDetails
        self.photoURL = photoURL
    }

    public static func == (lhs: ObvGroupDetails, rhs: ObvGroupDetails) -> Bool {
        guard lhs.coreDetails == rhs.coreDetails else { return false }
        switch (lhs.photoURL?.path, rhs.photoURL?.path) {
        case (.none, .none): break
        case (.none, .some): return false
        case (.some, .none): return false
        case (.some(let path1), .some(let path2)):
            guard FileManager.default.contentsEqual(atPath: path1, andPath: path2) else {
                return false
            }
        }
        return true
    }

}
