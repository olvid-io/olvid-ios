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

import UIKit
import SwiftUI



public final class ObvSideBarViewController: UIHostingController<ObvSideBarView> {
    
    public init(actions: ObvSideBarViewActions, dataSource: ObvSideBarViewDataSource) {
        let rootView = ObvSideBarView(actions: actions, dataSource: dataSource)
        super.init(rootView: rootView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        if #available(iOS 26, *) {
            // Nothing to tweak
        } else {
            // Workaround for macOS 15.6.1: Prevents a visual artifact (a small, miscolored rectangle)
            // from appearing at the bottom of the sidebar.
            // Note: A complementary fix is also required in `ObvSideBarView` to address a similar issue
            // on iPadOS 18 and earlier versions.
            self.view.backgroundColor = .systemBackground
        }
        
    }
    
}
