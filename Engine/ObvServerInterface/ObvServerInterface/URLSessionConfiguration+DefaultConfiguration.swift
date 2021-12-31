/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

public extension URLSessionConfiguration {

    func useOlvidSettings(sharedContainerIdentifier: String?) {
        self.waitsForConnectivity = true
        self.isDiscretionary = false
        self.allowsCellularAccess = true
        self.sessionSendsLaunchEvents = true
        self.sharedContainerIdentifier = sharedContainerIdentifier
        self.shouldUseExtendedBackgroundIdleMode = true
        if #available(iOS 13.0, *) {
            self.allowsConstrainedNetworkAccess = true
            self.allowsExpensiveNetworkAccess = true
        }
    }

}
