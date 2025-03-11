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

/// List of all the delegate protocols that serve as an interface within the Oblivious Engine.
public enum ObvEngineDelegateType: Int, Hashable, CaseIterable {
    case ObvBackupDelegate
    case ObvCreateContextDelegate
    case ObvNetworkPostDelegate
    case ObvNetworkFetchDelegate
    case ObvSolveChallengeDelegate
    case ObvProcessDownloadedMessageDelegate
    case ObvChannelDelegate
    case ObvKeyWrapperForIdentityDelegate
    case ObvProtocolDelegate
    case ObvFullRatchetProtocolStarterDelegate
    case ObvIdentityDelegate
    case ObvNotificationDelegate
    case ObvFlowDelegate
    case ObvSimpleFlowDelegate
    case ObvSyncSnapshotDelegate
}
