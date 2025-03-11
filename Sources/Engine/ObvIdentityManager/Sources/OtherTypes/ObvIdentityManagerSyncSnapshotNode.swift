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
import ObvTypes
import ObvCrypto
import OlvidUtils
import ObvMetaManager


/// This is the top level `ObvSyncSnapshotNode` at the identity manager level. Its App counterpart is called `AppSyncSnapshotNode`.
struct ObvIdentityManagerSyncSnapshotNode: ObvSyncSnapshotNode, Codable {
    
    private let domain: Set<CodingKeys>
    private let ownedCryptoIdentity: ObvCryptoIdentity
    private let ownedIdentityNode: OwnedIdentitySyncSnapshotNode
    
    let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case ownedCryptoIdentity = "owned_identity"
        case ownedIdentityNode = "owned_identity_node"
        case domain = "domain"
    }

    private static let defaultDomain: Set<CodingKeys> = Set(CodingKeys.allCases.filter({ $0 != .domain }))
    
    
    init(ownedCryptoIdentity: ObvCryptoIdentity, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        self.ownedCryptoIdentity = ownedCryptoIdentity
        guard let ownedIdentity = try OwnedIdentity.get(ownedCryptoIdentity, delegateManager: delegateManager, within: obvContext) else {
            throw ObvError.couldNotFindOwnedIdentity
        }
        self.ownedIdentityNode = ownedIdentity.syncSnapshotNode
        self.domain = Self.defaultDomain
    }
    
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        try container.encode(ownedCryptoIdentity.getIdentity(), forKey: .ownedCryptoIdentity)
        try container.encode(ownedIdentityNode, forKey: .ownedIdentityNode)
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
        let ownedIdentityIdentity = try values.decode(Data.self, forKey: .ownedCryptoIdentity)
        guard let ownedCryptoIdentity = ObvCryptoIdentity(from: ownedIdentityIdentity) else {
            throw ObvError.couldNotParseOwnedIdentityIdentity
        }
        self.ownedCryptoIdentity = ownedCryptoIdentity
        self.ownedIdentityNode = try values.decode(OwnedIdentitySyncSnapshotNode.self, forKey: .ownedIdentityNode)
    }
    
    
    func restore(prng: PRNGService, customDeviceName: String, delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        var associations = SnapshotNodeManagedObjectAssociations()
        try ownedIdentityNode.restoreInstance(cryptoIdentity: ownedCryptoIdentity, within: obvContext, associations: &associations)
        try ownedIdentityNode.restoreRelationships(associations: associations, prng: prng, customDeviceName: customDeviceName, delegateManager: delegateManager, within: obvContext)
    }
    
    
    enum ObvError: Error {
        case couldNotFindOwnedIdentity
        case couldNotParseOwnedIdentityIdentity
        case mismatchBetweenDomainAndValues
    }
    
}
