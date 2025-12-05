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

import Foundation
import ObvTypes


@MainActor
public final class ObvGroupV1CreationRouter {
    
    private let dataSources: ObvUIGroupV1RouterDataSources
    private let actions: any GroupV1CreationNavigationStackActions
    
    public init(dataSources: ObvUIGroupV1RouterDataSources, actions: any GroupV1CreationNavigationStackActions) {
        self.dataSources = dataSources
        self.actions = actions
    }
    
}

// MARK: - Public API to present the flow on a navigation stack managed internally (in SwiftUI)

extension ObvGroupV1CreationRouter {
    
    public func presentInitialViewControllerForGroupV1Creation(
        ownedCryptoId: ObvCryptoId,
        presentingViewController: UIViewController,
        navigation: any GroupV1CreationNavigationStackNavigation) {

            let vc = GroupV1CreationNavigationStackViewController(
                ownedCryptoId: ownedCryptoId,
                dataSources: self.dataSources.groupV1CreationNavigationStackDataSources,
                actions: actions,
                navigation: navigation)
            var finalPresentingViewController = presentingViewController
            while let presentedViewController = finalPresentingViewController.presentedViewController {
                finalPresentingViewController = presentedViewController
            }
            finalPresentingViewController.present(vc, animated: true)

        }
    
}
