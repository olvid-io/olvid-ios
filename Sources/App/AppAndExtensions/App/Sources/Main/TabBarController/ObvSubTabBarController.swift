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

import UIKit
import ObvAppTypes


final class ObvSubTabBarController: UITabBarController {
    
}


// MARK: - Returning the ObvFlowControllers of each tab

extension ObvSubTabBarController {

    var obvFlowControllers: [ObvFlowController] {
        let flowControllers: [ObvFlowController]
        if #available(iOS 18, *) {
            flowControllers = self.tabs.compactMap { $0.viewController as? ObvFlowController }
        } else {
            guard let viewControllers = self.viewControllers else { assertionFailure(); return [] }
            flowControllers = viewControllers.compactMap { $0 as? ObvFlowController }
        }
        assert(flowControllers.count == ObvFlow.allCases.count, "We expect each tab to return a view controller that is an ObvFlowController")
        return flowControllers
    }
    
}


extension ObvSubTabBarController {
    
    var selectedObvTab: ObvAppTypes.ObvFlow? {
        get {
            ObvFlow.allCases.first(where: { Self.indexOfObvTab($0) == self.selectedIndex })
        }
        set {
            guard let newValue else { assertionFailure(); return }
            self.selectedIndex = Self.indexOfObvTab(newValue)
        }
    }
    
    
    static func indexOfObvTab(_ obvTab: ObvAppTypes.ObvFlow) -> Int {
        switch obvTab {
        case .latestDiscussions: return 0
        case .contacts: return 1
        case .groups: return 2
        case .invitations: return 3
        }
    }
    
}
