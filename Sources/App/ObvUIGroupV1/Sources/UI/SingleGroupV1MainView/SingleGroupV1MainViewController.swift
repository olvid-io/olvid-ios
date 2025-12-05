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
import ObvDesignSystem


public final class SingleGroupV1MainViewController: UIHostingController<SingleGroupV1MainView> {
    
    public let groupIdentifier: ObvGroupV1Identifier
    
    public init(groupIdentifier: ObvGroupV1Identifier,
                dataSources: SingleGroupV1MainView.DataSources,
                actions: any SingleGroupV1MainViewActionsProtocol,
                navigation: any SingleGroupV1MainViewNavigation,
                uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        let rootView = SingleGroupV1MainView(
            groupIdentifier: groupIdentifier,
            dataSources: dataSources,
            actions: actions,
            navigation: navigation,
            uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
        self.groupIdentifier = groupIdentifier
        super.init(rootView: rootView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
