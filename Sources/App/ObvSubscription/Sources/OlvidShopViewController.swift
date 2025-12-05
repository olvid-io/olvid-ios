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
import UIKit


@MainActor
public protocol OlvidShopViewControllerNavigation: AnyObject {
    func olvidShopViewControllerDidDisappear(_ vc: OlvidShopViewController)
}


public final class OlvidShopViewController: UIHostingController<OlvidShopView> {
    
    weak private var viewControllerNavigation: (any OlvidShopViewControllerNavigation)?
    
    public init(dataSources: OlvidShopView.DataSources,
         navigation: any OlvidShopViewNavigation,
         actions: any OlvidShopViewActions,
         viewControllerNavigation: any OlvidShopViewControllerNavigation) {
        self.viewControllerNavigation = viewControllerNavigation
        let rootView = OlvidShopView(
            dataSources: dataSources,
            navigation: navigation,
            actions: actions)
        super.init(rootView: rootView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
 
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewControllerNavigation?.olvidShopViewControllerDidDisappear(self)
    }
    
}
