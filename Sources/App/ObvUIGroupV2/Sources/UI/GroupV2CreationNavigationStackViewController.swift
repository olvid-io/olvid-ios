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
import ObvUIGroupSharedBetweenV1AndV2
import ObvTypes
import ObvDesignSystem


final class GroupV2CreationNavigationStackViewController: UIHostingController<GroupV2CreationNavigationStack> {
    
    init(ownedCryptoId: ObvCryptoId,
         creationMode: ObvGroupV2CreationRouter.CreationMode,
         dataSources: GroupV2CreationNavigationStack.DataSources,
         actions: any GroupV2CreationNavigationStackActions,
         navigation: any GroupCreationNavigationStackNavigation,
         uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        let rootView = GroupV2CreationNavigationStack(
            ownedCryptoId: ownedCryptoId,
            creationMode: creationMode,
            dataSources: dataSources,
            actions: actions,
            navigation: navigation,
            uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
        super.init(rootView: rootView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
