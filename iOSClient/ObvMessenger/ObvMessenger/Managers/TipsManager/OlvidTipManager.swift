/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import TipKit


final class OlvidTipManager {
    
    init() {
        if #available(iOS 17, *) {
            do {
                try Tips.configure()
            } catch {
                assertionFailure()
            }
        }
    }
    
}


@available(iOS 17.0, *)
struct OlvidTip {
    
    /// This tip is intended to be shown in the single discussion view and allows the user to discover the search within a single discussion.
    struct SearchWithinDiscussion: Tip {
        
        var title: Text {
            Text("Search in this discussion")
        }
        
        var message: Text? {
            Text("The search is performed in all messages of this discussion.")
        }
        
        var image: Image? {
            Image(systemIcon: .magnifyingglass)
        }
        
        var options: [TipOption] {[
            // Do not show the tip more than twice
            Tips.MaxDisplayCount(2),
        ]}
    }
    
}
