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
import ObvCrypto
import ObvTypes

public struct UserData: Hashable {
    public let ownedIdentity: ObvCryptoIdentity
    public let label: UID
    public let nextRefreshTimestamp: Date
    public let kind: UserDataKind

    public init(ownedIdentity: ObvCryptoIdentity, label: UID, nextRefreshTimestamp: Date, kind: UserDataKind) {
        self.ownedIdentity = ownedIdentity
        self.label = label
        self.nextRefreshTimestamp = nextRefreshTimestamp
        self.kind = kind
    }

}

public enum UserDataKind: Hashable {
    case identity
    case group(groupUid: UID)
    case groupV2(groupIdentifier: GroupV2.Identifier)
}
