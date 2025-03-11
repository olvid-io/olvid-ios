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


protocol AnyObvUITabBarController: UITabBarController, OlvidMenuProvider {
    
}


// MARK: - Returning the ObvFlowControllers of each tab

extension AnyObvUITabBarController {

    var obvFlowControllers: [any ObvFlowController] {
        let flowControllers: [ObvFlowController]
        if #available(iOS 18, *) {
            flowControllers = self.tabs.compactMap { tab in
                tab.viewController as? ObvFlowController
            }
        } else {
            guard let viewControllers = self.viewControllers else { assertionFailure(); return [] }
            flowControllers = viewControllers.compactMap({ $0 as? ObvFlowController })
        }
        assert(flowControllers.count == ObvTab.allCases.count, "We expect each tab to return a view controller that is an ObvFlowController")
        return flowControllers
    }
    
}


extension AnyObvUITabBarController {
    
    var selectedObvTab: ObvTab? {
        get {
            ObvTab.allCases.first(where: { Self.indexOfObvTab($0) == self.selectedIndex })
        }
        set {
            guard let newValue else { assertionFailure(); return }
            self.selectedIndex = Self.indexOfObvTab(newValue)
        }
    }
    
    
    static func indexOfObvTab(_ obvTab: ObvTab) -> Int {
        switch self {
        case is ObvSubTabBarController.Type:
            switch obvTab {
            case .latestDiscussions: return 0
            case .contacts: return 1
            case .groups: return 3
            case .invitations: return 4
            }
        case is ObvSubTabBarControllerNew.Type:
            switch obvTab {
            case .latestDiscussions: return 0
            case .contacts: return 1
            case .groups: return 2
            case .invitations: return 3
            }
        default:
            assertionFailure()
            return 0
        }
    }
    
}


// MARK: - Implementing OlvidMenuProvider

extension AnyObvUITabBarController {
    
    func provideMenu() -> UIMenu {
        let menuElements: [UIMenuElement] = [
            UIAction(title: NSLocalizedString("SHOW_BACKUP_SCREEN", comment: ""),
                     image: UIImage(systemIcon: .arrowCounterclockwiseCircleFill)) { _ in
                ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .backupSettings)
                    .postOnDispatchQueue()
            },
            UIAction(title: NSLocalizedString("SHOW_SETTINGS_SCREEN", comment: ""),
                     image: UIImage(systemIcon: .gearshapeFill)) { _ in
                ObvMessengerInternalNotification.userWantsToNavigateToDeepLink(deepLink: .settings)
                    .postOnDispatchQueue()
            },
        ]
        let menu = UIMenu(title: "", children: menuElements)
        return menu
    }

}
