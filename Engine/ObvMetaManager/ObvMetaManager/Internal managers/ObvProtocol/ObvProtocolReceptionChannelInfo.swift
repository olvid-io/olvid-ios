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
import ObvTypes
import ObvEncoder
import ObvCrypto
import CoreData
import OlvidUtils

// The AnyObliviousChannelWithOwnedDevice is never actually set on a message. It is only used within protocol steps so as to allow a message to come from any other device of the current owned identity.
// Similarly, the AnyObliviousChannel is never actually set on a message. It is only used within protocol steps so as to allow a message to come from any Oblivious Channel with the current device (including oblivious channels with our other owned devices)


public enum ObvProtocolReceptionChannelInfo: ObvCodable, Equatable {

    case Local // Used to initiate a protocol
    case ObliviousChannel(remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID)
    case AsymmetricChannel
    case AnyObliviousChannelWithOwnedDevice(ownedIdentity: ObvCryptoIdentity) // Dummy type, see above
    case AnyObliviousChannel(ownedIdentity: ObvCryptoIdentity) // Dummy type, see above
    
    public var debugDescription: String {
        switch self {
        case .Local: return "Local"
        case .ObliviousChannel: return "ObliviousChannel"
        case .AsymmetricChannel: return "AsymmetricChannel"
        case .AnyObliviousChannelWithOwnedDevice: return "AnyObliviousChannelWithOwnedDevice"
        case .AnyObliviousChannel: return "AnyObliviousChannel"
        }
    }
    
    public func getRemoteIdentity() -> ObvCryptoIdentity? {
        switch self {
        case .Local,
             .AsymmetricChannel,
             .AnyObliviousChannelWithOwnedDevice,
             .AnyObliviousChannel:
            return nil
        case .ObliviousChannel(remoteCryptoIdentity: let remoteIdentity, remoteDeviceUid: _):
            return remoteIdentity
        }
    }
    
    public func getRemoteDeviceUid() -> UID? {
        switch self {
        case .Local,
             .AsymmetricChannel,
             .AnyObliviousChannelWithOwnedDevice,
             .AnyObliviousChannel:
            return nil
        case .ObliviousChannel(remoteCryptoIdentity: _, remoteDeviceUid: let remoteDeviceUid):
            return remoteDeviceUid
        }
    }
    
    // MARK: Implementing ObvCodable

    private var intId: Int {
        switch self {
        case .Local:
            return 0
        case .ObliviousChannel:
            return 1
        case .AsymmetricChannel:
            return 2
        case .AnyObliviousChannelWithOwnedDevice:
            return 3
        case .AnyObliviousChannel:
            return 4
        }
    }

    public func obvEncode() -> ObvEncoded {
        switch self {
        case .ObliviousChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: let remoteDeviceUid):
            return [self.intId, remoteCryptoIdentity, remoteDeviceUid].obvEncode()
        case .AsymmetricChannel,
             .Local:
            return [self.intId].obvEncode()
        case .AnyObliviousChannelWithOwnedDevice(ownedIdentity: let ownedIdentity),
             .AnyObliviousChannel(ownedIdentity: let ownedIdentity):
            return [self.intId, ownedIdentity].obvEncode()
        }
    }

    public init?(_ obvEncoded: ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
        guard !listOfEncoded.isEmpty else { return nil }
        guard let intId = Int(listOfEncoded[0]) else { return nil }
        switch intId {
        case 0:
            guard listOfEncoded.count == 1 else { return nil }
            self = ObvProtocolReceptionChannelInfo.Local
        case 1:
            // For legacy reasons, we accept lists of 5 items
            guard listOfEncoded.count == 5 || listOfEncoded.count == 3 else { return nil }
            guard let remoteCryptoIdentity = ObvCryptoIdentity(listOfEncoded[1]),
                let remoteDeviceUid = UID(listOfEncoded[2]) else {
                    return nil
            }
            self = ObvProtocolReceptionChannelInfo.ObliviousChannel(remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: remoteDeviceUid)
        case 2:
            guard listOfEncoded.count == 1 else { assertionFailure(); return nil }
            self = ObvProtocolReceptionChannelInfo.AsymmetricChannel
        case 3:
            guard listOfEncoded.count == 2 else { return nil }
            guard let ownedIdentity = ObvCryptoIdentity(listOfEncoded[1]) else { assertionFailure(); return nil }
            self = ObvProtocolReceptionChannelInfo.AnyObliviousChannelWithOwnedDevice(ownedIdentity: ownedIdentity)
        case 4:
            guard listOfEncoded.count == 2 else { return nil }
            guard let ownedIdentity = ObvCryptoIdentity(listOfEncoded[1]) else { assertionFailure(); return nil }
            self = ObvProtocolReceptionChannelInfo.AnyObliviousChannel(ownedIdentity: ownedIdentity)
        default:
            return nil
        }
    }
}

// Implementing Equatable
extension ObvProtocolReceptionChannelInfo {
    public static func == (lhs: ObvProtocolReceptionChannelInfo, rhs: ObvProtocolReceptionChannelInfo) -> Bool {
        switch lhs {
        case .ObliviousChannel(remoteCryptoIdentity: let lhs0, remoteDeviceUid: let lhs1):
            switch rhs {
            case .ObliviousChannel(remoteCryptoIdentity: let rhs0, remoteDeviceUid: let rhs1):
                return lhs0 == rhs0 && lhs1 == rhs1
            default:
                return false
            }
        case .AnyObliviousChannelWithOwnedDevice(ownedIdentity: let lhs0):
            switch rhs {
            case .AnyObliviousChannelWithOwnedDevice(ownedIdentity: let rhs0):
                return lhs0 == rhs0
            default:
                return false
            }
        case .AnyObliviousChannel(ownedIdentity: let lhs0):
            switch rhs {
            case .AnyObliviousChannel(ownedIdentity: let rhs0):
                return lhs0 == rhs0
            default:
                return false
            }
        default:
            return lhs.intId == rhs.intId
        }
    }

}

//
extension ObvProtocolReceptionChannelInfo {
    
    public func accepts(_ other: ObvProtocolReceptionChannelInfo, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) throws -> Bool {
        if self == other {
            return true
        } else {
            switch self {
            case .AnyObliviousChannelWithOwnedDevice(ownedIdentity: let ownedIdentity):
                switch other {
                case .ObliviousChannel(remoteCryptoIdentity: let remoteIdentity, remoteDeviceUid: _):
                    return ownedIdentity == remoteIdentity
                default:
                    assertionFailure()
                    return false
                }
            case .AnyObliviousChannel(ownedIdentity: let ownedIdentity):
                switch other {
                case .ObliviousChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: _):
                    if try identityDelegate.isIdentity(remoteCryptoIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext),
                       try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: remoteCryptoIdentity, within: obvContext) {
                        return true
                    } else if remoteCryptoIdentity == ownedIdentity {
                        return true
                    } else {
                        return false
                    }
                default:
                    return false
                }
            default:
                return false
            }
        }
    }
    
}
