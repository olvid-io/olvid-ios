/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

import SwiftUI

public extension Color {
    
    init(nameInThisBundle name: String) {
        self.init(name, bundle: ObvPollFeatureResources.bundle)
    }
    
    static let pollColors: [Color] = [
        Color(nameInThisBundle: "poll_color_2"),
        Color(nameInThisBundle: "poll_color_3"),
        Color(nameInThisBundle: "poll_color_4"),
        Color(nameInThisBundle: "poll_color_5"),
        Color(nameInThisBundle: "poll_color_6"),
        Color(nameInThisBundle: "poll_color_7"),
        Color(nameInThisBundle: "poll_color_1"),
//        Color(nameInThisBundle: "poll_color_8"),
//        Color(nameInThisBundle: "poll_color_9"),
//        Color(nameInThisBundle: "poll_color_10"),
//        Color(nameInThisBundle: "poll_color_11"),
//        Color(nameInThisBundle: "poll_color_12"),
    ]
}
