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
import OlvidUtils

/// This is a list of all registered protocols
enum CryptoProtocolId: Int, CustomDebugStringConvertible, CaseIterable {
    
    case DeviceDiscoveryForContactIdentity = 0
    case TrustEstablishment = 1 // 2019-10-24 Legacy protocol that shall be removed in the following weeks. (2020-03-02 will indeed be removed in the following weeks)
    case ChannelCreationWithContactDevice = 2
    case DeviceDiscoveryForRemoteIdentity = 3
    case ContactMutualIntroduction = 4
    /* case GroupCreation = 5 */
    case IdentityDetailsPublication = 6
    case DownloadIdentityPhoto = 7
    case GroupInvitation = 8
    case GroupManagement = 9
    case ContactManagement = 10
    case TrustEstablishmentWithSAS = 11
    case TrustEstablishmentWithMutualScan = 12
    case FullRatchet = 13
    case DownloadGroupPhoto = 14
    case KeycloakContactAddition = 15
    case ContactCapabilitiesDiscovery = 16
    case OneToOneContactInvitation = 17
    case GroupV2 = 18
    case DownloadGroupV2Photo = 19

    func getConcreteCryptoProtocol(from instance: ProtocolInstance, prng: PRNGService) -> ConcreteCryptoProtocol? {
        return self.concreteCryptoProtocol.init(protocolInstance: instance, prng: prng)
    }
    
    private var concreteCryptoProtocol: ConcreteCryptoProtocol.Type {
        switch self {
        case .DeviceDiscoveryForContactIdentity:
            return DeviceDiscoveryForContactIdentityProtocol.self
        case .TrustEstablishment:
            return TrustEstablishmentProtocol.self
        case .ChannelCreationWithContactDevice:
            return ChannelCreationWithContactDeviceProtocol.self
        case .DeviceDiscoveryForRemoteIdentity:
            return DeviceDiscoveryForRemoteIdentityProtocol.self
        case .ContactMutualIntroduction:
            return ContactMutualIntroductionProtocol.self
        case .IdentityDetailsPublication:
            return IdentityDetailsPublicationProtocol.self
        case .DownloadIdentityPhoto:
            return DownloadIdentityPhotoChildProtocol.self
        case .GroupInvitation:
            return GroupInvitationProtocol.self
        case .GroupManagement:
            return GroupManagementProtocol.self
        case .ContactManagement:
            return ContactManagementProtocol.self
        case .TrustEstablishmentWithSAS:
            return TrustEstablishmentWithSASProtocol.self
        case .TrustEstablishmentWithMutualScan:
            return TrustEstablishmentWithMutualScanProtocol.self
        case .FullRatchet:
            return FullRatchetProtocol.self
        case .DownloadGroupPhoto:
            return DownloadGroupPhotoChildProtocol.self
        case .KeycloakContactAddition:
            return KeycloakContactAdditionProtocol.self
        case .ContactCapabilitiesDiscovery:
            return DeviceCapabilitiesDiscoveryProtocol.self
        case .OneToOneContactInvitation:
            return OneToOneContactInvitationProtocol.self
        case .GroupV2:
            return GroupV2Protocol.self
        case .DownloadGroupV2Photo:
            return DownloadGroupV2PhotoProtocol.self
        }
    }
    
    
    var finalStateRawIds: [Int] {
        return self.concreteCryptoProtocol.finalStateRawIds
    }
    
    
    func getConcreteCryptoProtocolInInitialState(instanceUid: UID, ownedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, prng: PRNGService, within obvContext: ObvContext) -> ConcreteCryptoProtocol {
        return self.concreteCryptoProtocol.init(instanceUid: instanceUid,
                                                currentState: ConcreteProtocolInitialState(),
                                                ownedCryptoIdentity: ownedCryptoIdentity,
                                                delegateManager: delegateManager,
                                                prng: prng,
                                                within: obvContext)
    }
}

extension CryptoProtocolId {
    
    var debugDescription: String {
        switch self {
        case .DeviceDiscoveryForContactIdentity: return "DeviceDiscoveryForContactIdentity"
        case .TrustEstablishment: return "TrustEstablishment"
        case .ChannelCreationWithContactDevice: return "ChannelCreationWithContactDevice"
        case .DeviceDiscoveryForRemoteIdentity: return "DeviceDiscoveryForRemoteIdentity"
        case .ContactMutualIntroduction: return "ContactMutualIntroduction"
        case .IdentityDetailsPublication: return "IdentityDetailsPublication"
        case .DownloadIdentityPhoto: return "DownloadIdentityPhoto"
        case .GroupInvitation: return "GroupInvitation"
        case .GroupManagement: return "GroupManagement"
        case .ContactManagement: return "ContactManagement"
        case .TrustEstablishmentWithSAS: return "TrustEstablishmentWithSAS"
        case .FullRatchet: return "FullRatchet"
        case .DownloadGroupPhoto: return "DownloadGroupPhoto"
        case .KeycloakContactAddition: return "KeycloakContactAddition"
        case .TrustEstablishmentWithMutualScan: return "TrustEstablishmentWithMutualScan"
        case .ContactCapabilitiesDiscovery: return "ContactCapabilitiesDiscovery"
        case .OneToOneContactInvitation: return "OneToOneContactInvitation"
        case .GroupV2: return "GroupV2"
        case .DownloadGroupV2Photo: return "DownloadGroupV2Photo"
        }
    }

}
