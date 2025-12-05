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
import ObvTypes
import ObvAppTypes
import ObvDesignSystem
import ObvUIGroupSharedBetweenV1AndV2

public final class SingleGroupV2MainViewController: UIHostingController<SingleGroupV2MainView> {
    
    public let groupIdentifier: ObvGroupV2Identifier
    
    public init(groupIdentifier: ObvGroupV2Identifier,
                dataSource: any SingleGroupV2MainViewDataSource,
                subDataSources: SingleGroupV2MainView.SubDataSources,
                actions: any SingleGroupV2MainViewActionsProtocol,
                navigation: any SingleGroupV2MainViewNavigation,
                uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        self.groupIdentifier = groupIdentifier
        let rootView = SingleGroupV2MainView(
            groupIdentifier: groupIdentifier,
            dataSource: dataSource,
            subDataSources: subDataSources,
            actions: actions,
            navigation: navigation,
            uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
        super.init(rootView: rootView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}
