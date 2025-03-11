/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
    
    case local(ownedIdentity: ObvCryptoIdentity) // Send from/to this owned identity
    case allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: Set<ObvCryptoIdentity>, fromOwnedIdentity: ObvCryptoIdentity, withUserContent: Bool = false, contactDeviceIdentifiersToExclude: Set<ObvContactDeviceIdentifier> = Set([]))
    case allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ObvCryptoIdentity)
    case allConfirmedObliviousChannelsOrPreKeyChannelsWithContactsAndWithOtherOwnedDevices(contactIdentities: Set<ObvCryptoIdentity>, fromOwnedIdentity: ObvCryptoIdentity, withUserContent: Bool = false, contactDeviceIdentifiersToExclude: Set<ObvContactDeviceIdentifier> = Set([]))
    case obliviousChannel(to: ObvCryptoIdentity, remoteDeviceUids: [UID], fromOwnedIdentity: ObvCryptoIdentity, necessarilyConfirmed: Bool, usePreKeyIfRequired: Bool)
    case asymmetricChannel(to: ObvCryptoIdentity, remoteDeviceUids: [UID], fromOwnedIdentity: ObvCryptoIdentity)
    case asymmetricChannelBroadcast(to: ObvCryptoIdentity, fromOwnedIdentity: ObvCryptoIdentity)
    case userInterface(uuid: UUID, ownedIdentity: ObvCryptoIdentity, dialogType: ObvChannelDialogToSendType)
    case serverQuery(ownedIdentity: ObvCryptoIdentity) // The identity is one of our own, used to receive the server response
    case confirmedObliviousChannelOrPreKeyChannelWithContactDevice(contactDevice: ObvContactDeviceIdentifier)

    
    /// Only owned identities can "send" on a channel. Note that when sending a message to self, the `fromOwnedIdentity` is identical to the `toIdentity`
    public var fromOwnedIdentity: ObvCryptoIdentity {
        switch self {
        case .local(ownedIdentity: let fromOwnedIdentity),
             .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: let fromOwnedIdentity),
             .obliviousChannel(to: _, remoteDeviceUids: _, fromOwnedIdentity: let fromOwnedIdentity, necessarilyConfirmed: _, usePreKeyIfRequired: _),
             .asymmetricChannel(to: _, remoteDeviceUids: _, fromOwnedIdentity: let fromOwnedIdentity),
             .asymmetricChannelBroadcast(to: _, fromOwnedIdentity: let fromOwnedIdentity),
             .userInterface(uuid: _, ownedIdentity: let fromOwnedIdentity, dialogType: _),
             .serverQuery(ownedIdentity: let fromOwnedIdentity),
             .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: _, fromOwnedIdentity: let fromOwnedIdentity, withUserContent: _, contactDeviceIdentifiersToExclude: _),
             .allConfirmedObliviousChannelsOrPreKeyChannelsWithContactsAndWithOtherOwnedDevices(contactIdentities: _, fromOwnedIdentity: let fromOwnedIdentity, withUserContent: _, contactDeviceIdentifiersToExclude: _):
            return fromOwnedIdentity
        case .confirmedObliviousChannelOrPreKeyChannelWithContactDevice(contactDevice: let contactDevice):
            return contactDevice.ownedCryptoId.cryptoIdentity
        }
    }
    
    
    /// The toIdentity can be a contact identity, or an owned identity, depending on the case.
    public var toIdentity: ObvCryptoIdentity? {
        switch self {
        case .local(ownedIdentity: let toIdentity),
             .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: let toIdentity),
             .obliviousChannel(to: let toIdentity, remoteDeviceUids: _, fromOwnedIdentity: _, necessarilyConfirmed: _, usePreKeyIfRequired: _),
             .asymmetricChannel(to: let toIdentity, remoteDeviceUids: _, fromOwnedIdentity: _),
             .asymmetricChannelBroadcast(to: let toIdentity, fromOwnedIdentity: _),
             .userInterface(uuid: _, ownedIdentity: let toIdentity, dialogType: _),
             .serverQuery(ownedIdentity: let toIdentity):
            return toIdentity
        case .confirmedObliviousChannelOrPreKeyChannelWithContactDevice(contactDevice: let contactDevice):
            return contactDevice.contactCryptoId.cryptoIdentity
        case .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts,
                .allConfirmedObliviousChannelsOrPreKeyChannelsWithContactsAndWithOtherOwnedDevices:
            return nil
        }
    }
    
    
    public var toIdentities: Set<ObvCryptoIdentity>? {
        switch self {
        case .local,
             .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices,
             .obliviousChannel,
             .asymmetricChannel,
             .asymmetricChannelBroadcast,
             .userInterface,
             .serverQuery:
            return nil
        case .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: let toIdentities, fromOwnedIdentity: _, withUserContent: _, contactDeviceIdentifiersToExclude: _),
                .allConfirmedObliviousChannelsOrPreKeyChannelsWithContactsAndWithOtherOwnedDevices(contactIdentities: let toIdentities, fromOwnedIdentity: _, withUserContent: _, contactDeviceIdentifiersToExclude: _):
            return toIdentities
        case .confirmedObliviousChannelOrPreKeyChannelWithContactDevice(contactDevice: let contactDevice):
            return Set([contactDevice.contactCryptoId.cryptoIdentity])
        }
    }
    
    
    public var withUserContent: Bool {
        switch self {
        case .local,
                .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices,
                .obliviousChannel,
                .asymmetricChannel,
                .asymmetricChannelBroadcast,
                .userInterface,
                .serverQuery:
            return false
        case .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: _, fromOwnedIdentity: _, withUserContent: let withUserContent, contactDeviceIdentifiersToExclude: _),
                .allConfirmedObliviousChannelsOrPreKeyChannelsWithContactsAndWithOtherOwnedDevices(contactIdentities: _, fromOwnedIdentity: _, withUserContent: let withUserContent, contactDeviceIdentifiersToExclude: _):
            return withUserContent
        case .confirmedObliviousChannelOrPreKeyChannelWithContactDevice(contactDevice: _):
            return false
        }
    }
    
}
