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
import ObvTypes
import ObvCrypto
import OlvidUtils


struct ObvIdentityManagerDeviceSnapshotNode: ObvSyncSnapshotNode, Codable {
    
    private let domain: Set<CodingKeys>
    private let ownedIdentities: [ObvCryptoId: OwnedIdentityDeviceSnapshotNode]
    
    let id = Self.generateIdentifier()

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case ownedIdentities = "owned_identities"
        case domain = "domain"
    }

    private static let defaultDomain: Set<CodingKeys> = Set(CodingKeys.allCases.filter({ $0 != .domain }))
    
    
    init(delegateManager: ObvIdentityDelegateManager, within obvContext: ObvContext) throws {
        let ownedIdentitiesObjects = try OwnedIdentity.getAll(restrictToActive: true, delegateManager: delegateManager, within: obvContext)
        guard !ownedIdentitiesObjects.isEmpty else {
            throw ObvError.noActiveIdentity
        }
        var ownedIdentities = [ObvCryptoId: OwnedIdentityDeviceSnapshotNode]()
        for ownedIdentity in ownedIdentitiesObjects {
            let ownedCryptoId = ObvCryptoId(cryptoIdentity: ownedIdentity.cryptoIdentity)
            let deviceSnapshotNode = try ownedIdentity.deviceSnapshotNode
            ownedIdentities[ownedCryptoId] = deviceSnapshotNode
        }
        self.ownedIdentities = ownedIdentities
        self.domain = Self.defaultDomain
    }
    
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(domain, forKey: .domain)
        let dict: [String: OwnedIdentityDeviceSnapshotNode] = .init(ownedIdentities, keyMapping: { $0.getIdentity().base64EncodedString() }, valueMapping: { $0 })
        try container.encode(dict, forKey: .ownedIdentities)
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rawKeys = try values.decode(Set<String>.self, forKey: .domain)
        self.domain = Set(rawKeys.compactMap({ CodingKeys(rawValue: $0) }))
        do {
            let dict = try values.decode([String: OwnedIdentityDeviceSnapshotNode].self, forKey: .ownedIdentities)
            self.ownedIdentities = Dictionary(dict, keyMapping: { $0.base64EncodedToData?.identityToObvCryptoId }, valueMapping: { $0 })
        }
    }
    
    
    enum ObvError: Error {
        case noActiveIdentity
    }
    
}


// MARK: - Creating a ObvTypes.ObvDeviceBackupFromServer

extension ObvIdentityManagerDeviceSnapshotNode {
    
    /// Called when parsing a device backup downloaded from the server
    func toObvDeviceBackupFromServer(version: Int) throws -> ObvTypes.ObvDeviceBackupFromServer {
        
        var profiles = [ObvTypes.ObvDeviceBackupFromServer.Profile]()
        
        for (ownedCryptoId, ownedIdentityDeviceSnapshotNode) in ownedIdentities {
            
            let profile = try ownedIdentityDeviceSnapshotNode.toObvDeviceBackupFromServerProfile(ownedCryptoId: ownedCryptoId)
            
            profiles.append(profile)
                        
        }
        
        return ObvTypes.ObvDeviceBackupFromServer(version: version, profiles: profiles)
        
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
