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
import ObvTypes
import ObvSettings


/// This is the top level `ObvSyncSnapshotNode` at the app level (its identity manager counterpart at the engine level is called `ObvIdentityManagerSyncSnapshotNode`).
public struct AppSyncSnapshotNode: ObvSyncSnapshotNode, Codable {
    
    private let domain: Set<CodingKeys>
    private let ownedCryptoId: ObvCryptoId
    private let ownedIdentityNode: PersistedObvOwnedIdentitySyncSnapshotNode?
    private let globalSettingsNode: GlobalSettingsSyncSnapshotNode?
    
    public let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case ownedCryptoId = "owned_identity"
        case ownedIdentityNode = "owned_identity_node"
        case globalSettingsNode = "settings"
        case domain = "domain"
    }

    private static let defaultDomain: Set<CodingKeys> = Set(CodingKeys.allCases.filter({ $0 != .domain }))

    
    public init(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws {
        self.ownedCryptoId = ownedCryptoId
        guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
            throw ObvUICoreDataError.couldNotFindOwnedIdentity
        }
        self.ownedIdentityNode = try ownedIdentity.syncSnapshotNode
        self.globalSettingsNode = ObvMessengerSettings.syncSnapshotNode
        self.domain = Self.defaultDomain
    }

    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        try container.encode(ownedCryptoId.getIdentity(), forKey: .ownedCryptoId)
        try container.encodeIfPresent(ownedIdentityNode, forKey: .ownedIdentityNode)
        try container.encodeIfPresent(globalSettingsNode, forKey: .globalSettingsNode)
    }
    
    
    public init(from decoder: Decoder) throws {
        do {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            let identity = try values.decode(Data.self, forKey: .ownedCryptoId)
            let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
            self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
            self.ownedCryptoId = try ObvCryptoId(identity: identity)
            self.ownedIdentityNode = try values.decodeIfPresent(PersistedObvOwnedIdentitySyncSnapshotNode.self, forKey: .ownedIdentityNode)
            self.globalSettingsNode = try values.decodeIfPresent(GlobalSettingsSyncSnapshotNode.self, forKey: .globalSettingsNode)
        } catch {
            assertionFailure()
            throw error
        }
    }
    
    
    public func useToUpdateAppDatabase(within context: NSManagedObjectContext) throws {
        if domain.contains(.ownedIdentityNode) {
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                assertionFailure()
                throw ObvUICoreDataError.couldNotFindOwnedIdentity
            }
            ownedIdentityNode?.useToUpdate(ownedIdentity)
        }
        globalSettingsNode?.useToUpdateGlobalSettings()
    }
    

}
