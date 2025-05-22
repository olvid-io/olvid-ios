/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvTypes
import ObvSettings


/// This is the top level `ObvSyncSnapshotNode` at the app level when creating a snapshot in the context of a device backup.
public struct AppDeviceSnapshotNode: ObvSyncSnapshotNode, Codable {
    
    private let domain: Set<CodingKeys>
    private let ownedIdentities: [ObvCryptoId: PersistedObvOwnedIdentityDeviceSnapshotNode]
    
    public let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case ownedIdentities = "owned_identities"
        case domain = "domain"
    }

    private static let defaultDomain: Set<CodingKeys> = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    
    public init(within context: NSManagedObjectContext) throws {
        // Note that we include hidden identities
        let ownedIdentitiesObjects = try PersistedObvOwnedIdentity.getAllActive(within: context)
        var ownedIdentities = [ObvCryptoId: PersistedObvOwnedIdentityDeviceSnapshotNode]()
        for ownedIdentity in ownedIdentitiesObjects {
            let cryptoId = ownedIdentity.cryptoId
            let deviceSnapshotNode = ownedIdentity.deviceSnapshotNode
            ownedIdentities[cryptoId] = deviceSnapshotNode
        }
        self.ownedIdentities = ownedIdentities
        self.domain = Self.defaultDomain
    }

    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        let dict: [String: PersistedObvOwnedIdentityDeviceSnapshotNode] = .init(ownedIdentities, keyMapping: { $0.getIdentity().base64EncodedString() }, valueMapping: { $0 })
        try container.encode(dict, forKey: .ownedIdentities)
    }
    
    
    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
            self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
            do {
                let dict = try values.decode([String: PersistedObvOwnedIdentityDeviceSnapshotNode].self, forKey: .ownedIdentities)
                self.ownedIdentities = Dictionary(dict, keyMapping: { $0.base64EncodedToData?.identityToObvCryptoId }, valueMapping: { $0 })
            }
        } catch {
            assertionFailure()
            throw error
        }
    }

}


// MARK: - Obtaining the custom display name of an owned identity

extension AppDeviceSnapshotNode {
    
    public func getCustomDisplayNameForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> String? {
        return ownedIdentities[ownedCryptoId]?.customDisplayName
    }
    
}



// MARK: - Private Helpers

private extension String {
    
    var base64EncodedToData: Data? {
        guard let data = Data(base64Encoded: self) else { assertionFailure(); return nil }
        return data
    }
    
}


private extension Data {
    
    var identityToObvCryptoId: ObvCryptoId? {
        guard let cryptoIdentity = try? ObvCryptoId(identity: self) else { assertionFailure(); return nil }
        return cryptoIdentity
    }
    
}
