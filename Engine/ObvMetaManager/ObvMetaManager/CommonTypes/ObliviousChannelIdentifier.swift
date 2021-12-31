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
import ObvCrypto
import ObvTypes


/// This is a convenience strucutre used, in particular, during the engine bootstraping process to sync the devices stored within the identity manager and the oblivious channels stored within the channel manager.
///
/// This structure allows to store together :
/// - a current device uid,
/// - a remote (contact or owned) crypto identity,
/// - and a remote device uid (belonging to the remote identity).
///
/// This is used, in particular, during the engine bootstraping process to sync the devices stored within the identity manager and the oblivious channels stored within the channel manager.
/// Note that this structure corresponds to the primary key of an Oblivious channel.
public struct ObliviousChannelIdentifier: Hashable {
    
    public let currentDeviceUid: UID
    public let remoteCryptoIdentity: ObvCryptoIdentity
    public let remoteDeviceUid: UID
    
    public init(currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) {
        self.currentDeviceUid = currentDeviceUid
        self.remoteCryptoIdentity = remoteCryptoIdentity
        self.remoteDeviceUid = remoteDeviceUid
    }
    
}


public struct ObliviousChannelIdentifierAlt: Hashable {
    
    public let ownedCryptoIdentity: ObvCryptoIdentity
    public let remoteCryptoIdentity: ObvCryptoIdentity
    public let remoteDeviceUid: UID
    
    public init(ownedCryptoIdentity: ObvCryptoIdentity, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID) {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.remoteCryptoIdentity = remoteCryptoIdentity
        self.remoteDeviceUid = remoteDeviceUid
    }

}
