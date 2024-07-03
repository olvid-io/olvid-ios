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
import ObvTypes
import ObvEncoder
import ObvCrypto
import CoreData
import OlvidUtils

// The AnyObliviousChannelWithOwnedDevice is never actually set on a message. It is only used within protocol steps so as to allow a message to come from any other device of the current owned identity.
// Similarly, the AnyObliviousChannel is never actually set on a message. It is only used within protocol steps so as to allow a message to come from any Oblivious Channel with the current device (including oblivious channels with our other owned devices)

public enum ObvProtocolReceptionChannelInfo: ObvCodable, Equatable {

    case local // Used to initiate a protocol
    case obliviousChannel(remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID)
    case preKeyChannel(remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID)
    case asymmetricChannel
    case anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: ObvCryptoIdentity) // Dummy type, see above
    case anyObliviousChannelOrPreKeyChannel(ownedIdentity: ObvCryptoIdentity) // Dummy type, see above
    case anyObliviousChannel(ownedIdentity: ObvCryptoIdentity) // Dummy type, see above
    
    public var debugDescription: String {
        switch self {
        case .local: return "Local"
        case .obliviousChannel: return "ObliviousChannel"
        case .preKeyChannel: return "PreKeyChannel"
        case .asymmetricChannel: return "AsymmetricChannel"
        case .anyObliviousChannelOrPreKeyWithOwnedDevice: return "AnyObliviousChannelWithOwnedDevice"
        case .anyObliviousChannelOrPreKeyChannel: return "AnyObliviousChannel"
        case .anyObliviousChannel: return "anyObliviousChannel"
        }
    }
    
    public func getRemoteIdentity() -> ObvCryptoIdentity? {
        switch self {
        case .local,
             .asymmetricChannel,
             .anyObliviousChannelOrPreKeyWithOwnedDevice,
             .anyObliviousChannelOrPreKeyChannel,
             .anyObliviousChannel:
            return nil
        case .obliviousChannel(remoteCryptoIdentity: let remoteIdentity, remoteDeviceUid: _), .preKeyChannel(remoteCryptoIdentity: let remoteIdentity, remoteDeviceUid: _):
            return remoteIdentity
        }
    }
    
    public func getRemoteDeviceUid() -> UID? {
        switch self {
        case .local,
             .asymmetricChannel,
             .anyObliviousChannelOrPreKeyWithOwnedDevice,
             .anyObliviousChannelOrPreKeyChannel,
             .anyObliviousChannel:
            return nil
        case .obliviousChannel(remoteCryptoIdentity: _, remoteDeviceUid: let remoteDeviceUid), .preKeyChannel(remoteCryptoIdentity: _, remoteDeviceUid: let remoteDeviceUid):
            return remoteDeviceUid
        }
    }
    
    // MARK: Implementing ObvCodable

    private enum ObvProtocolReceptionChannelInfoRaw: Int {
        case local = 0
        case obliviousChannel = 1
        case asymmetricChannel = 2
        case anyObliviousChannelOrPreKeyWithOwnedDevice = 3
        case anyObliviousChannelOrPreKeyChannel = 4
        case preKeyChannel = 5
        case anyObliviousChannel = 6
    }
    
    private var intId: Int {
        let raw: ObvProtocolReceptionChannelInfoRaw
        switch self {
        case .local:
            raw = .local
        case .obliviousChannel:
            raw = .obliviousChannel
        case .asymmetricChannel:
            raw = .asymmetricChannel
        case .anyObliviousChannelOrPreKeyWithOwnedDevice:
            raw = .anyObliviousChannelOrPreKeyWithOwnedDevice
        case .anyObliviousChannelOrPreKeyChannel:
            raw = .anyObliviousChannelOrPreKeyChannel
        case .preKeyChannel:
            raw = .preKeyChannel
        case .anyObliviousChannel:
            raw = .anyObliviousChannel
        }
        return raw.rawValue
    }

    public func obvEncode() -> ObvEncoded {
        switch self {
        case .obliviousChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: let remoteDeviceUid),
                .preKeyChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: let remoteDeviceUid):
            return [self.intId, remoteCryptoIdentity, remoteDeviceUid].obvEncode()
        case .asymmetricChannel,
             .local:
            return [self.intId].obvEncode()
        case .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: let ownedIdentity),
             .anyObliviousChannelOrPreKeyChannel(ownedIdentity: let ownedIdentity),
             .anyObliviousChannel(ownedIdentity: let ownedIdentity):
            return [self.intId, ownedIdentity].obvEncode()
        }
    }

    public init?(_ obvEncoded: ObvEncoded) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
        guard !listOfEncoded.isEmpty else { return nil }
        guard let intId = Int(listOfEncoded[0]) else { return nil }
        guard let raw = ObvProtocolReceptionChannelInfoRaw(rawValue: intId) else { assertionFailure(); return nil }
        switch raw {
        case .local:
            guard listOfEncoded.count == 1 else { return nil }
            self = ObvProtocolReceptionChannelInfo.local
        case .obliviousChannel:
            // For legacy reasons, we accept lists of 5 items
            guard listOfEncoded.count == 5 || listOfEncoded.count == 3 else { return nil }
            guard let remoteCryptoIdentity = ObvCryptoIdentity(listOfEncoded[1]),
                let remoteDeviceUid = UID(listOfEncoded[2]) else {
                    return nil
            }
            self = ObvProtocolReceptionChannelInfo.obliviousChannel(remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: remoteDeviceUid)
        case .asymmetricChannel:
            guard listOfEncoded.count == 1 else { assertionFailure(); return nil }
            self = ObvProtocolReceptionChannelInfo.asymmetricChannel
        case .anyObliviousChannelOrPreKeyWithOwnedDevice:
            guard listOfEncoded.count == 2 else { return nil }
            guard let ownedIdentity = ObvCryptoIdentity(listOfEncoded[1]) else { assertionFailure(); return nil }
            self = ObvProtocolReceptionChannelInfo.anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: ownedIdentity)
        case .anyObliviousChannelOrPreKeyChannel:
            guard listOfEncoded.count == 2 else { return nil }
            guard let ownedIdentity = ObvCryptoIdentity(listOfEncoded[1]) else { assertionFailure(); return nil }
            self = ObvProtocolReceptionChannelInfo.anyObliviousChannelOrPreKeyChannel(ownedIdentity: ownedIdentity)
        case .preKeyChannel:
            guard listOfEncoded.count == 3 else { return nil }
            guard let remoteCryptoIdentity = ObvCryptoIdentity(listOfEncoded[1]),
                let remoteDeviceUid = UID(listOfEncoded[2]) else {
                    return nil
            }
            self = ObvProtocolReceptionChannelInfo.preKeyChannel(remoteCryptoIdentity: remoteCryptoIdentity, remoteDeviceUid: remoteDeviceUid)
        case .anyObliviousChannel:
            guard listOfEncoded.count == 2 else { return nil }
            guard let ownedIdentity = ObvCryptoIdentity(listOfEncoded[1]) else { assertionFailure(); return nil }
            self = .anyObliviousChannel(ownedIdentity: ownedIdentity)
        }
    }
}

// Implementing Equatable
extension ObvProtocolReceptionChannelInfo {
    public static func == (lhs: ObvProtocolReceptionChannelInfo, rhs: ObvProtocolReceptionChannelInfo) -> Bool {
        switch lhs {
        case .obliviousChannel(remoteCryptoIdentity: let lhs0, remoteDeviceUid: let lhs1):
            switch rhs {
            case .obliviousChannel(remoteCryptoIdentity: let rhs0, remoteDeviceUid: let rhs1):
                return lhs0 == rhs0 && lhs1 == rhs1
            default:
                return false
            }
        case .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: let lhs0):
            switch rhs {
            case .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: let rhs0):
                return lhs0 == rhs0
            default:
                return false
            }
        case .anyObliviousChannel(ownedIdentity: let lhs0):
            switch rhs {
            case .anyObliviousChannel(ownedIdentity: let rhs0):
                return lhs0 == rhs0
            default:
                return false
            }
        case .anyObliviousChannelOrPreKeyChannel(ownedIdentity: let lhs0):
            switch rhs {
            case .anyObliviousChannelOrPreKeyChannel(ownedIdentity: let rhs0):
                return lhs0 == rhs0
            default:
                return false
            }
        case .preKeyChannel(remoteCryptoIdentity: let lhs0, remoteDeviceUid: let lhs1):
            switch rhs {
            case .preKeyChannel(remoteCryptoIdentity: let rhs0, remoteDeviceUid: let rhs1):
                return lhs0 == rhs0 && lhs1 == rhs1
            default:
                return false
            }
        default:
            return lhs.intId == rhs.intId
        }
    }

}



extension ObvProtocolReceptionChannelInfo {

    public func accepts(_ other: ObvProtocolReceptionChannelInfo, identityDelegate: ObvIdentityDelegate, within obvContext: ObvContext) throws -> Bool {
        if self == other {
            return true
        } else {
            switch self {
            case .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: let ownedIdentity):
                switch other {
                case .obliviousChannel(remoteCryptoIdentity: let remoteIdentity, remoteDeviceUid: _),
                        .preKeyChannel(remoteCryptoIdentity: let remoteIdentity, remoteDeviceUid: _):
                    return ownedIdentity == remoteIdentity
                default:
                    assertionFailure()
                    return false
                }
            case .anyObliviousChannelOrPreKeyChannel(ownedIdentity: let ownedIdentity):
                switch other {
                case .obliviousChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: _),
                        .preKeyChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: _):
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
            case .anyObliviousChannel(ownedIdentity: let ownedIdentity):
                switch other {
                case .obliviousChannel(remoteCryptoIdentity: let remoteCryptoIdentity, remoteDeviceUid: _):
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
