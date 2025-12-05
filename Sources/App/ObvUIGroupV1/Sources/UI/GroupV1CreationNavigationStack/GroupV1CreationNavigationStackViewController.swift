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


final class GroupV1CreationNavigationStackViewController: UIHostingController<GroupV1CreationNavigationStack> {
    
    init(ownedCryptoId: ObvCryptoId,
         dataSources: GroupV1CreationNavigationStack.DataSources,
         actions: any GroupV1CreationNavigationStackActions,
         navigation: any GroupV1CreationNavigationStackNavigation) {
        let rootView = GroupV1CreationNavigationStack(
            ownedCryptoId: ownedCryptoId,
            dataSources: dataSources,
            actions: actions,
            navigation: navigation)
        super.init(rootView: rootView)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
