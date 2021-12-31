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
import CoreData
import ObvCrypto
import ObvTypes
import OlvidUtils

/// This is a list of all registered protocols
enum CryptoProtocolId: Int, CustomDebugStringConvertible {
    
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
    case ObliviousChannelManagement = 10
    case TrustEstablishmentWithSAS = 11
    case TrustEstablishmentWithMutualScan = 12
    case FullRatchet = 13
    case DownloadGroupPhoto = 14
    case KeycloakContactAddition = 15

    func getConcreteCryptoProtocol(from instance: ProtocolInstance, prng: PRNGService) -> ConcreteCryptoProtocol? {
        var concreteCryptoProtocol: ConcreteCryptoProtocol?
        switch instance.cryptoProtocolId {
        case .DeviceDiscoveryForContactIdentity:
            concreteCryptoProtocol = DeviceDiscoveryForContactIdentityProtocol(protocolInstance: instance, prng: prng)
        case .TrustEstablishment:
            concreteCryptoProtocol = TrustEstablishmentProtocol(protocolInstance: instance, prng: prng)
        case .ChannelCreationWithContactDevice:
            concreteCryptoProtocol = ChannelCreationWithContactDeviceProtocol(protocolInstance: instance, prng: prng)
        case .DeviceDiscoveryForRemoteIdentity:
            concreteCryptoProtocol = DeviceDiscoveryForRemoteIdentityProtocol(protocolInstance: instance, prng: prng)
        case .ContactMutualIntroduction:
            concreteCryptoProtocol = ContactMutualIntroductionProtocol(protocolInstance: instance, prng: prng)
        case .IdentityDetailsPublication:
            concreteCryptoProtocol = IdentityDetailsPublicationProtocol(protocolInstance: instance, prng: prng)
        case .DownloadIdentityPhoto:
            concreteCryptoProtocol = DownloadIdentityPhotoChildProtocol(protocolInstance: instance, prng: prng)
        case .GroupInvitation:
            concreteCryptoProtocol = GroupInvitationProtocol(protocolInstance: instance, prng: prng)
        case .GroupManagement:
            concreteCryptoProtocol = GroupManagementProtocol(protocolInstance: instance, prng: prng)
        case .ObliviousChannelManagement:
            concreteCryptoProtocol = ObliviousChannelManagementProtocol(protocolInstance: instance, prng: prng)
        case .TrustEstablishmentWithSAS:
            concreteCryptoProtocol = TrustEstablishmentWithSASProtocol(protocolInstance: instance, prng: prng)
        case .FullRatchet:
            concreteCryptoProtocol = FullRatchetProtocol(protocolInstance: instance, prng: prng)
        case .DownloadGroupPhoto:
            concreteCryptoProtocol = DownloadGroupPhotoChildProtocol(protocolInstance: instance, prng: prng)
        case .KeycloakContactAddition:
            concreteCryptoProtocol = KeycloakContactAdditionProtocol(protocolInstance: instance, prng: prng)
        case .TrustEstablishmentWithMutualScan:
            concreteCryptoProtocol = TrustEstablishmentWithMutualScanProtocol(protocolInstance: instance, prng: prng)
        }
        return concreteCryptoProtocol
    }
    
    func getConcreteCryptoProtocolInInitialState(instanceUid: UID, ownedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, prng: PRNGService, within obvContext: ObvContext) -> ConcreteCryptoProtocol {
        switch self {
        case .DeviceDiscoveryForContactIdentity:
            return DeviceDiscoveryForContactIdentityProtocol(instanceUid: instanceUid,
                                                             currentState: ConcreteProtocolInitialState(),
                                                             ownedCryptoIdentity: ownedCryptoIdentity,
                                                             delegateManager: delegateManager,
                                                             prng: prng,
                                                             within: obvContext)
        case .TrustEstablishment:
            return TrustEstablishmentProtocol(instanceUid: instanceUid,
                                              currentState: ConcreteProtocolInitialState(),
                                              ownedCryptoIdentity: ownedCryptoIdentity,
                                              delegateManager: delegateManager,
                                              prng: prng,
                                              within: obvContext)
        case .ChannelCreationWithContactDevice:
            return ChannelCreationWithContactDeviceProtocol(instanceUid: instanceUid,
                                                            currentState: ConcreteProtocolInitialState(),
                                                            ownedCryptoIdentity: ownedCryptoIdentity,
                                                            delegateManager: delegateManager,
                                                            prng: prng,
                                                            within: obvContext)
        case .DeviceDiscoveryForRemoteIdentity:
            return DeviceDiscoveryForRemoteIdentityProtocol(instanceUid: instanceUid,
                                                            currentState: ConcreteProtocolInitialState(),
                                                            ownedCryptoIdentity: ownedCryptoIdentity,
                                                            delegateManager: delegateManager,
                                                            prng: prng,
                                                            within: obvContext)
        case .ContactMutualIntroduction:
            return ContactMutualIntroductionProtocol(instanceUid: instanceUid,
                                                     currentState: ConcreteProtocolInitialState(),
                                                     ownedCryptoIdentity: ownedCryptoIdentity,
                                                     delegateManager: delegateManager,
                                                     prng: prng,
                                                     within: obvContext)
        case .IdentityDetailsPublication:
            return IdentityDetailsPublicationProtocol(instanceUid: instanceUid,
                                                      currentState: ConcreteProtocolInitialState(),
                                                      ownedCryptoIdentity: ownedCryptoIdentity,
                                                      delegateManager: delegateManager,
                                                      prng: prng,
                                                      within: obvContext)
        case .DownloadIdentityPhoto:
            return DownloadIdentityPhotoChildProtocol(instanceUid: instanceUid,
                                                      currentState: ConcreteProtocolInitialState(),
                                                      ownedCryptoIdentity: ownedCryptoIdentity,
                                                      delegateManager: delegateManager,
                                                      prng: prng,
                                                      within: obvContext)
        case .GroupInvitation:
            return GroupInvitationProtocol(instanceUid: instanceUid,
                                           currentState: ConcreteProtocolInitialState(),
                                           ownedCryptoIdentity: ownedCryptoIdentity,
                                           delegateManager: delegateManager,
                                           prng: prng,
                                           within: obvContext)
        case .GroupManagement:
            return GroupManagementProtocol(instanceUid: instanceUid,
                                           currentState: ConcreteProtocolInitialState(),
                                           ownedCryptoIdentity: ownedCryptoIdentity,
                                           delegateManager: delegateManager,
                                           prng: prng,
                                           within: obvContext)
        case .ObliviousChannelManagement:
            return ObliviousChannelManagementProtocol(instanceUid: instanceUid,
                                                      currentState: ConcreteProtocolInitialState(),
                                                      ownedCryptoIdentity: ownedCryptoIdentity,
                                                      delegateManager: delegateManager,
                                                      prng: prng,
                                                      within: obvContext)
        case .TrustEstablishmentWithSAS:
            return TrustEstablishmentWithSASProtocol(instanceUid: instanceUid,
                                                     currentState: ConcreteProtocolInitialState(),
                                                     ownedCryptoIdentity: ownedCryptoIdentity,
                                                     delegateManager: delegateManager,
                                                     prng: prng,
                                                     within: obvContext)
        case .FullRatchet:
            return FullRatchetProtocol(instanceUid: instanceUid,
                                       currentState: ConcreteProtocolInitialState(),
                                       ownedCryptoIdentity: ownedCryptoIdentity,
                                       delegateManager: delegateManager,
                                       prng: prng,
                                       within: obvContext)
        case .DownloadGroupPhoto:
            return DownloadGroupPhotoChildProtocol(instanceUid: instanceUid,
                                                   currentState: ConcreteProtocolInitialState(),
                                                   ownedCryptoIdentity: ownedCryptoIdentity,
                                                   delegateManager: delegateManager,
                                                   prng: prng,
                                                   within: obvContext)
        case .KeycloakContactAddition:
            return KeycloakContactAdditionProtocol(instanceUid: instanceUid,
                                                   currentState: ConcreteProtocolInitialState(),
                                                   ownedCryptoIdentity: ownedCryptoIdentity,
                                                   delegateManager: delegateManager,
                                                   prng: prng,
                                                   within: obvContext)
        case .TrustEstablishmentWithMutualScan:
            return TrustEstablishmentWithMutualScanProtocol(instanceUid: instanceUid,
                                                            currentState: ConcreteProtocolInitialState(),
                                                            ownedCryptoIdentity: ownedCryptoIdentity,
                                                            delegateManager: delegateManager,
                                                            prng: prng,
                                                            within: obvContext)
        }
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
        case .ObliviousChannelManagement: return "ObliviousChannelManagement"
        case .TrustEstablishmentWithSAS: return "TrustEstablishmentWithSAS"
        case .FullRatchet: return "FullRatchet"
        case .DownloadGroupPhoto: return "DownloadGroupPhoto"
        case .KeycloakContactAddition: return "KeycloakContactAddition"
        case .TrustEstablishmentWithMutualScan: return "TrustEstablishmentWithMutualScan"
        }
    }

}
