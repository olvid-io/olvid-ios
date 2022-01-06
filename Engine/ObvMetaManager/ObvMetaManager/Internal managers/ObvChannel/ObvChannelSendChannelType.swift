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
import CoreData

import ObvCrypto
import ObvTypes


public enum ObvChannelSendChannelType {
    
    case Local(ownedIdentity: ObvCryptoIdentity) // Send from/to this owned identity
    case AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set<ObvCryptoIdentity>, fromOwnedIdentity: ObvCryptoIdentity)
    case AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ObvCryptoIdentity)
    case ObliviousChannel(to: ObvCryptoIdentity, remoteDeviceUids: [UID], fromOwnedIdentity: ObvCryptoIdentity, necessarilyConfirmed: Bool)
    case AsymmetricChannel(to: ObvCryptoIdentity, remoteDeviceUids: [UID], fromOwnedIdentity: ObvCryptoIdentity)
    case AsymmetricChannelBroadcast(to: ObvCryptoIdentity, fromOwnedIdentity: ObvCryptoIdentity)
    case UserInterface(uuid: UUID, ownedIdentity: ObvCryptoIdentity, dialogType: ObvChannelDialogToSendType)
    case ServerQuery(ownedIdentity: ObvCryptoIdentity) // The identity is one of our own, used to receive the server response
    
    /// Only owned identities can "send" on a channel. Note that when sending a message to self, the `fromOwnedIdentity` is identical to the `toIdentity`
    public var fromOwnedIdentity: ObvCryptoIdentity? {
        switch self {
        case .Local(ownedIdentity: let fromOwnedIdentity),
             .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: let fromOwnedIdentity),
             .ObliviousChannel(to: _, remoteDeviceUids: _, fromOwnedIdentity: let fromOwnedIdentity, necessarilyConfirmed: _),
             .AsymmetricChannel(to: _, remoteDeviceUids: _, fromOwnedIdentity: let fromOwnedIdentity),
             .AsymmetricChannelBroadcast(to: _, fromOwnedIdentity: let fromOwnedIdentity),
             .UserInterface(uuid: _, ownedIdentity: let fromOwnedIdentity, dialogType: _),
             .ServerQuery(ownedIdentity: let fromOwnedIdentity):
            return fromOwnedIdentity
        case .AllConfirmedObliviousChannelsWithContactIdentities:
            return nil
        }
    }
    
    /// The toIdentity can be a contact identity, or an owned identity, depending on the case.
    public var toIdentity: ObvCryptoIdentity? {
        switch self {
        case .Local(ownedIdentity: let toIdentity),
             .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: let toIdentity),
             .ObliviousChannel(to: let toIdentity, remoteDeviceUids: _, fromOwnedIdentity: _, necessarilyConfirmed: _),
             .AsymmetricChannel(to: let toIdentity, remoteDeviceUids: _, fromOwnedIdentity: _),
             .AsymmetricChannelBroadcast(to: let toIdentity, fromOwnedIdentity: _),
             .UserInterface(uuid: _, ownedIdentity: let toIdentity, dialogType: _),
             .ServerQuery(ownedIdentity: let toIdentity):
            return toIdentity
        case .AllConfirmedObliviousChannelsWithContactIdentities:
            return nil
        }
    }
    
    public var toIdentities: Set<ObvCryptoIdentity>? {
        switch self {
        case .Local,
             .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity,
             .ObliviousChannel,
             .AsymmetricChannel,
             .AsymmetricChannelBroadcast,
             .UserInterface,
             .ServerQuery:
            return nil
        case .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: let toIdentities, fromOwnedIdentity: _):
            return toIdentities
        }

    }
}
