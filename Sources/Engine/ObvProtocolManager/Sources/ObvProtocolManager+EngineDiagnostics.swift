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
import CoreData
import OlvidUtils
import ObvTypes


// MARK: - Describing what the protocol manager holds

extension ObvProtocolManager {

    /// What the protocol manager holds, counted by protocol.
    ///
    /// For the diagnostics panel, which until now said everything about the inbox and nothing about this — so a device caught in a storm of protocol
    /// instances, or holding a `ReceivedMessage` table that never empties, looked exactly like a healthy one.
    ///
    /// Two grouped queries over one context, materialising nothing. **One context for both**, so the two tables describe the same instant: a reader comparing
    /// them is asking whether the messages are being turned into instances, and two numbers read at two moments would not answer that.
    ///
    /// **Not run on the queue that executes protocol steps.** This is a read, and a count taken a moment before or after a step is equally true — where
    /// waiting behind a step would make a diagnostic screen hang on exactly the device that has most protocol work outstanding.
    public func getProtocolCounts(flowId: FlowIdentifier) async throws -> ObvProtocolCounts {

        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); throw ObvError.contextCreatorIsNil }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ObvProtocolCounts, any Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let instances = try ProtocolInstance.countPerCryptoProtocolId(within: obvContext.context)
                    let messages = try ReceivedMessage.countPerCryptoProtocolId(within: obvContext.context)
                    return continuation.resume(returning: ObvProtocolCounts(
                        protocolInstancesPerKind: instances.perProtocol.mapKeysToDiagnostics(),
                        protocolInstancesWithAnUnrecognisedKind: instances.unrecognised,
                        receivedProtocolMessagesPerKind: messages.perProtocol.mapKeysToDiagnostics(),
                        receivedProtocolMessagesWithAnUnrecognisedKind: messages.unrecognised))
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }

    }

}


// MARK: - Helpers

fileprivate extension Dictionary where Key == CryptoProtocolId, Value == Int {

    func mapKeysToDiagnostics() -> [ObvCryptoProtocolKind: Int] {
        reduce(into: [ObvCryptoProtocolKind: Int]()) { result, element in
            result[element.key.forDiagnostics, default: 0] += element.value
        }
    }

}


fileprivate extension CryptoProtocolId {

    /// This protocol as anything outside the engine sees it.
    ///
    /// **An exhaustive switch, and that is the point of it.** `CryptoProtocolId` is internal to this module and its raw values have gaps, so it cannot itself
    /// cross the boundary; this is where the two vocabularies are tied together, and a protocol added to the enum above will not compile until it has been
    /// given a line here. The names match ``debugDescription`` so that a figure in a support mail and a line in a log say the same word.
    var forDiagnostics: ObvCryptoProtocolKind {
        switch self {
        case .contactDeviceDiscovery: return .contactDeviceDiscovery
        case .channelCreationWithContactDevice: return .channelCreationWithContactDevice
        case .deviceDiscoveryForRemoteIdentity: return .deviceDiscoveryForRemoteIdentity
        case .ContactMutualIntroduction: return .contactMutualIntroduction
        case .identityDetailsPublication: return .identityDetailsPublication
        case .downloadIdentityPhoto: return .downloadIdentityPhoto
        case .groupInvitation: return .groupInvitation
        case .groupManagement: return .groupManagement
        case .contactManagement: return .contactManagement
        case .trustEstablishmentWithSAS: return .trustEstablishmentWithSAS
        case .trustEstablishmentWithMutualScan: return .trustEstablishmentWithMutualScan
        case .fullRatchet: return .fullRatchet
        case .downloadGroupPhoto: return .downloadGroupPhoto
        case .keycloakContactAddition: return .keycloakContactAddition
        case .contactCapabilitiesDiscovery: return .contactCapabilitiesDiscovery
        case .oneToOneContactInvitation: return .oneToOneContactInvitation
        case .groupV2: return .groupV2
        case .downloadGroupV2Photo: return .downloadGroupV2Photo
        case .ownedIdentityDeletionProtocol: return .ownedIdentityDeletion
        case .ownedDeviceDiscovery: return .ownedDeviceDiscovery
        case .channelCreationWithOwnedDevice: return .channelCreationWithOwnedDevice
        case .keycloakBindingAndUnbinding: return .keycloakBindingAndUnbinding
        case .ownedDeviceManagement: return .ownedDeviceManagement
        case .synchronization: return .synchronization
        case .ownedIdentityTransfer: return .ownedIdentityTransfer
        }
    }

}
