/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
    
    case contactDeviceDiscovery = 0
    // 2023-01-28 We remove the legacy TrustEstablishment protocol
    case channelCreationWithContactDevice = 2
    case deviceDiscoveryForRemoteIdentity = 3
    case ContactMutualIntroduction = 4
    /* case GroupCreation = 5 */
    case identityDetailsPublication = 6
    case downloadIdentityPhoto = 7
    case groupInvitation = 8
    case groupManagement = 9
    case contactManagement = 10
    case trustEstablishmentWithSAS = 11
    case trustEstablishmentWithMutualScan = 12
    case fullRatchet = 13
    case downloadGroupPhoto = 14
    case keycloakContactAddition = 15
    case contactCapabilitiesDiscovery = 16
    case oneToOneContactInvitation = 17
    case groupV2 = 18
    case downloadGroupV2Photo = 19
    case ownedIdentityDeletionProtocol = 20
    case ownedDeviceDiscovery = 21
    case channelCreationWithOwnedDevice = 22
    case keycloakBindingAndUnbinding = 23
    case ownedDeviceManagement = 24
    case synchronization = 25
    case ownedIdentityTransfer = 26

    func getConcreteCryptoProtocol(from instance: ProtocolInstance, prng: PRNGService) -> ConcreteCryptoProtocol? {
        return self.concreteCryptoProtocol.init(protocolInstance: instance, prng: prng)
    }
    
    private var concreteCryptoProtocol: ConcreteCryptoProtocol.Type {
        switch self {
        case .contactDeviceDiscovery:
            return ContactDeviceDiscoveryProtocol.self
        case .channelCreationWithContactDevice:
            return ChannelCreationWithContactDeviceProtocol.self
        case .deviceDiscoveryForRemoteIdentity:
            return DeviceDiscoveryForRemoteIdentityProtocol.self
        case .ContactMutualIntroduction:
            return ContactMutualIntroductionProtocol.self
        case .identityDetailsPublication:
            return IdentityDetailsPublicationProtocol.self
        case .downloadIdentityPhoto:
            return DownloadIdentityPhotoChildProtocol.self
        case .groupInvitation:
            return GroupInvitationProtocol.self
        case .groupManagement:
            return GroupManagementProtocol.self
        case .contactManagement:
            return ContactManagementProtocol.self
        case .trustEstablishmentWithSAS:
            return TrustEstablishmentWithSASProtocol.self
        case .trustEstablishmentWithMutualScan:
            return TrustEstablishmentWithMutualScanProtocol.self
        case .fullRatchet:
            return FullRatchetProtocol.self
        case .downloadGroupPhoto:
            return DownloadGroupPhotoChildProtocol.self
        case .keycloakContactAddition:
            return KeycloakContactAdditionProtocol.self
        case .contactCapabilitiesDiscovery:
            return DeviceCapabilitiesDiscoveryProtocol.self
        case .oneToOneContactInvitation:
            return OneToOneContactInvitationProtocol.self
        case .groupV2:
            return GroupV2Protocol.self
        case .downloadGroupV2Photo:
            return DownloadGroupV2PhotoProtocol.self
        case .ownedIdentityDeletionProtocol:
            return OwnedIdentityDeletionProtocol.self
        case .ownedDeviceDiscovery:
            return OwnedDeviceDiscoveryProtocol.self
        case .channelCreationWithOwnedDevice:
            return ChannelCreationWithOwnedDeviceProtocol.self
        case .keycloakBindingAndUnbinding:
            return KeycloakBindingAndUnbindingProtocol.self
        case .ownedDeviceManagement:
            return OwnedDeviceManagementProtocol.self
        case .synchronization:
            return SynchronizationProtocol.self
        case .ownedIdentityTransfer:
            return OwnedIdentityTransferProtocol.self
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
        case .contactDeviceDiscovery: return "ContactDeviceDiscoveryProtocol"
        case .channelCreationWithContactDevice: return "ChannelCreationWithContactDevice"
        case .deviceDiscoveryForRemoteIdentity: return "DeviceDiscoveryForRemoteIdentity"
        case .ContactMutualIntroduction: return "ContactMutualIntroduction"
        case .identityDetailsPublication: return "IdentityDetailsPublication"
        case .downloadIdentityPhoto: return "DownloadIdentityPhoto"
        case .groupInvitation: return "GroupInvitation"
        case .groupManagement: return "GroupManagement"
        case .contactManagement: return "ContactManagement"
        case .trustEstablishmentWithSAS: return "TrustEstablishmentWithSAS"
        case .fullRatchet: return "FullRatchet"
        case .downloadGroupPhoto: return "DownloadGroupPhoto"
        case .keycloakContactAddition: return "KeycloakContactAddition"
        case .trustEstablishmentWithMutualScan: return "TrustEstablishmentWithMutualScan"
        case .contactCapabilitiesDiscovery: return "ContactCapabilitiesDiscovery"
        case .oneToOneContactInvitation: return "OneToOneContactInvitation"
        case .groupV2: return "GroupV2"
        case .downloadGroupV2Photo: return "DownloadGroupV2Photo"
        case .ownedIdentityDeletionProtocol: return "OwnedIdentityDeletionProtocol"
        case .ownedDeviceDiscovery: return "OwnedDeviceDiscoveryProtocol"
        case .channelCreationWithOwnedDevice: return "ChannelCreationWithOwnedDeviceProtocol"
        case .keycloakBindingAndUnbinding: return "KeycloakBindingAndUnbindingProtocol"
        case .ownedDeviceManagement: return "OwnedDeviceManagementProtocol"
        case .synchronization: return "SynchronizationProtocol"
        case .ownedIdentityTransfer: return "OwnedIdentityTransferProtocol"
        }
    }

}
