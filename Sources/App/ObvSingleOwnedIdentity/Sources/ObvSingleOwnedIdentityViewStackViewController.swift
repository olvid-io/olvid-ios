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


public final class ObvSingleOwnedIdentityViewStackViewController: UIHostingController<ObvSingleOwnedIdentityViewStack> {
    
    public init(ownedCryptoId: ObvCryptoId,
                dataSources: ObvSingleOwnedIdentityViewStack.DataSources,
                actions: any ObvSingleOwnedIdentityViewStackActions,
                navigation: any ObvSingleOwnedIdentityViewStackNavigation,
                uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet) {
        let rootView = ObvSingleOwnedIdentityViewStack(
            ownedCryptoId: ownedCryptoId,
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
