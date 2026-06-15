/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvTypes


public final class ProgressImportHostingView: UIHostingController<LocalNetworkImportView> {

    public init(sourceDeviceName: String?,
                sourceDeviceIdentifier: ObvOwnedDeviceIdentifier,
                transferIdFromSource: String,
                actions: any LocalNetworkImportViewActions) {
        let rootView = LocalNetworkImportView(
            localNetworkType: .webRTC(sourceDeviceIdentifier: sourceDeviceIdentifier,
                                      sourceDeviceName: sourceDeviceName,
                                      transferIdFromSource: transferIdFromSource),
            actions: actions)
        super.init(rootView: rootView)
    }

    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}
