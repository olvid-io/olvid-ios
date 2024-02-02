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

import ObvMetaManager

extension ObvChannelSendChannelType {
    
    var obvChannelType: ObvChannel.Type {
        switch self {
        case .AllConfirmedObliviousChannelsWithContactIdentities,
             .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity,
             .AllConfirmedObliviousChannelsWithContactIdentitiesAndWithOtherDevicesOfOwnedIdentity,
             .ObliviousChannel:
            return ObvObliviousChannel.self
        case .AsymmetricChannel,
             .AsymmetricChannelBroadcast:
            return ObvAsymmetricChannel.self
        case .Local:
            return ObvLocalChannel.self
        case .UserInterface:
            return ObvUserInterfaceChannel.self
        case .ServerQuery:
            return ObvServerChannel.self
        }
    }
    
}
