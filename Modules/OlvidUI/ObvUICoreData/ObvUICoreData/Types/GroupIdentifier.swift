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

public enum GroupIdentifierBasedOnObjectID {
    case groupV1(TypeSafeManagedObjectID<PersistedContactGroup>)
    case groupV2(TypeSafeManagedObjectID<PersistedGroupV2>)
}

public enum GroupIdentifier {
    case groupV1(groupV1Identifier: GroupV1Identifier)
    case groupV2(groupV2Identifier: GroupV2Identifier)
}
