/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

public struct TurnCredentials {
    public let expiringUsername1: String
    public let password1: String
    public let expiringUsername2: String
    public let password2: String
    public init(expiringUsername1: String, password1: String, expiringUsername2: String, password2: String) {
        self.expiringUsername1 = expiringUsername1
        self.password1 = password1
        self.expiringUsername2 = expiringUsername2
        self.password2 = password2
    }
}
