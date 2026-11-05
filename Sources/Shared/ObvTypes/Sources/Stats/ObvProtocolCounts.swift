/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


/// One of the engine's cryptographic protocols, as far as anything outside the engine needs to know.
///
/// A mirror of the protocol manager's internal `CryptoProtocolId`, as ``ObvInboxAttachmentStatus`` mirrors `InboxAttachment.Status`. The mapping is an
/// exhaustive switch there, so a protocol added will not compile until it has a case here.
///
/// **Raw values are the names the engine's logs use**, so a support mail and a log line say the same word — `String` rather than `Int` because the ids on the
/// other side have gaps, and a bare number crossing the boundary would be unreadable.
public enum ObvCryptoProtocolKind: String, Sendable, Codable, CaseIterable {

    case contactDeviceDiscovery = "ContactDeviceDiscoveryProtocol"
    case channelCreationWithContactDevice = "ChannelCreationWithContactDevice"
    case deviceDiscoveryForRemoteIdentity = "DeviceDiscoveryForRemoteIdentity"
    case contactMutualIntroduction = "ContactMutualIntroduction"
    case identityDetailsPublication = "IdentityDetailsPublication"
    case downloadIdentityPhoto = "DownloadIdentityPhoto"
    case groupInvitation = "GroupInvitation"
    case groupManagement = "GroupManagement"
    case contactManagement = "ContactManagement"
    case trustEstablishmentWithSAS = "TrustEstablishmentWithSAS"
    case trustEstablishmentWithMutualScan = "TrustEstablishmentWithMutualScan"
    case fullRatchet = "FullRatchet"
    case downloadGroupPhoto = "DownloadGroupPhoto"
    case keycloakContactAddition = "KeycloakContactAddition"
    case contactCapabilitiesDiscovery = "ContactCapabilitiesDiscovery"
    case oneToOneContactInvitation = "OneToOneContactInvitation"
    case groupV2 = "GroupV2"
    case downloadGroupV2Photo = "DownloadGroupV2Photo"
    case ownedIdentityDeletion = "OwnedIdentityDeletionProtocol"
    case ownedDeviceDiscovery = "OwnedDeviceDiscoveryProtocol"
    case channelCreationWithOwnedDevice = "ChannelCreationWithOwnedDeviceProtocol"
    case keycloakBindingAndUnbinding = "KeycloakBindingAndUnbindingProtocol"
    case ownedDeviceManagement = "OwnedDeviceManagementProtocol"
    case synchronization = "SynchronizationProtocol"
    case ownedIdentityTransfer = "OwnedIdentityTransferProtocol"

}


/// What the protocol manager holds, counted by protocol.
///
/// Two tables answering different questions. A **protocol instance** is a conversation this device is in the middle of: a healthy device has a handful, coming
/// and going. A **received protocol message** is one that has arrived and not yet been stepped through; that table is meant to empty itself, so anything
/// standing in it is a device not getting through its work.
///
/// Both count every profile, active or not: these describe the *store*, and a deactivated profile's rows are still in it.
public struct ObvProtocolCounts: Sendable, Equatable {

    /// How many protocol instances exist, per protocol. A protocol with no instance is absent rather than present with a zero.
    public let protocolInstancesPerKind: [ObvCryptoProtocolKind: Int]

    /// Instances whose stored protocol id matches no protocol we know of — two protocols were retired and their rows may outlive them.
    ///
    /// **Reported rather than dropped**, so that the per-protocol figures still add up to the total, which is the one sum a reader can check.
    public let protocolInstancesWithAnUnrecognisedKind: Int

    /// How many received protocol messages are waiting to be processed, per protocol.
    public let receivedProtocolMessagesPerKind: [ObvCryptoProtocolKind: Int]

    /// Received messages whose stored protocol id matches no protocol we know of. Here for the same reason as its sibling above.
    public let receivedProtocolMessagesWithAnUnrecognisedKind: Int

    public init(protocolInstancesPerKind: [ObvCryptoProtocolKind: Int], protocolInstancesWithAnUnrecognisedKind: Int, receivedProtocolMessagesPerKind: [ObvCryptoProtocolKind: Int], receivedProtocolMessagesWithAnUnrecognisedKind: Int) {
        self.protocolInstancesPerKind = protocolInstancesPerKind
        self.protocolInstancesWithAnUnrecognisedKind = protocolInstancesWithAnUnrecognisedKind
        self.receivedProtocolMessagesPerKind = receivedProtocolMessagesPerKind
        self.receivedProtocolMessagesWithAnUnrecognisedKind = receivedProtocolMessagesWithAnUnrecognisedKind
    }

    /// Every protocol instance, whatever protocol it belongs to and including those we could not name.
    public var totalNumberOfProtocolInstances: Int {
        protocolInstancesPerKind.values.reduce(0, +) + protocolInstancesWithAnUnrecognisedKind
    }

    /// Every received protocol message awaiting processing, on the same terms.
    public var totalNumberOfReceivedProtocolMessages: Int {
        receivedProtocolMessagesPerKind.values.reduce(0, +) + receivedProtocolMessagesWithAnUnrecognisedKind
    }

}
