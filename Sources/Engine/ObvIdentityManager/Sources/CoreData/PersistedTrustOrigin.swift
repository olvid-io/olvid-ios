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
import os.log
import CoreData
import ObvCrypto
import ObvMetaManager
import ObvTypes
import OlvidUtils
import ObvEncoder


@objc(PersistedTrustOrigin)
final class PersistedTrustOrigin: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "PersistedTrustOrigin"
    private static let contactKey = "contact"
    
    // MARK: Attributes

    @NSManaged private var identityServer: URL?
    @NSManaged private var mediatorOrGroupOwnerCryptoIdentity: ObvCryptoIdentity?
    @NSManaged private var mediatorOrGroupOwnerTrustLevelMajor: NSNumber?
    @NSManaged private var rawObvGroupV2Identifier: Data?
    @NSManaged private(set) var timestamp: Date
    @NSManaged private var trustTypeRaw: Int
    
    // MARK: Relationships
    
    private(set) var contact: ContactIdentity {
        get {
            let item = kvoSafePrimitiveValue(forKey: PersistedTrustOrigin.contactKey) as! ContactIdentity
            item.obvContext = self.obvContext
            return item
        }
        set {
            kvoSafeSetPrimitiveValue(newValue, forKey: PersistedTrustOrigin.contactKey)
        }
    }
    
    // MARK: Other variables
    
    private var delegateManager: ObvIdentityDelegateManager?
    weak var obvContext: ObvContext?
    
    // MARK: - Initializer
    
    // Must be called from ContactIdentity and from nowhere else
    convenience init?(trustOrigin: TrustOrigin, contact: ContactIdentity, delegateManager: ObvIdentityDelegateManager) {
        
        guard let obvContext = contact.obvContext else { return nil }
        
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedTrustOrigin.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        
        guard let ownedIdentity = contact.ownedIdentity else {
            assertionFailure("Could not find owned identity associated to the contact")
            return nil
        }
        
        self.trustTypeRaw = trustOrigin.trustTypeRaw
        self.timestamp = trustOrigin.timestamp
        switch trustOrigin {
        case .direct:
            self.mediatorOrGroupOwnerCryptoIdentity = nil
            self.mediatorOrGroupOwnerTrustLevelMajor = nil
            self.identityServer = nil
            self.rawObvGroupV2Identifier = nil
        case .group(timestamp: _, groupOwner: let cryptoIdentity),
             .introduction(timestamp: _, mediator: let cryptoIdentity):
            guard let mediatorOrGroupOwner = try? ContactIdentity.get(contactIdentity: cryptoIdentity,
                                                                      ownedIdentity: ownedIdentity.cryptoIdentity,
                                                                      delegateManager: delegateManager,
                                                                      within: obvContext) else { return nil }
            self.mediatorOrGroupOwnerCryptoIdentity = cryptoIdentity
            self.mediatorOrGroupOwnerTrustLevelMajor = NSNumber(value: mediatorOrGroupOwner.trustLevel.major)
            self.identityServer = nil
            self.rawObvGroupV2Identifier = nil
        case .keycloak(timestamp: _, keycloakServer: let keycloakServer):
            self.identityServer = keycloakServer
            self.rawObvGroupV2Identifier = nil
        case .serverGroupV2(timestamp: _, groupIdentifier: let groupIdentifier):
            self.rawObvGroupV2Identifier = groupIdentifier.obvEncode().rawData
        }
        
        self.contact = contact
        
        self.delegateManager = delegateManager
        
        // Sanity checks
        guard self.trustOrigin != nil else { assertionFailure(); return nil }
        guard self.trustLevel != nil else { assertionFailure(); return nil }
        
    }
    
    /// Used *exclusively* during a backup restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(backupItem: PersistedTrustOriginBackupItem, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedTrustOrigin.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.identityServer = backupItem.identityServer
        self.mediatorOrGroupOwnerCryptoIdentity = backupItem.mediatorOrGroupOwnerCryptoIdentity
        self.mediatorOrGroupOwnerTrustLevelMajor = backupItem.mediatorOrGroupOwnerTrustLevelMajor
        self.timestamp = backupItem.timestamp
        self.trustTypeRaw = backupItem.trustTypeRaw
        self.rawObvGroupV2Identifier = backupItem.rawObvGroupV2Identifier
    }
    
    
    /// Used *exclusively* during a snapshot restore for creating an instance, relatioships are recreater in a second step
    fileprivate convenience init(snapshotItem: PersistedTrustOriginSyncSnapshotItem, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedTrustOrigin.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.identityServer = snapshotItem.identityServer
        self.mediatorOrGroupOwnerCryptoIdentity = snapshotItem.mediatorOrGroupOwnerCryptoIdentity
        self.mediatorOrGroupOwnerTrustLevelMajor = snapshotItem.mediatorOrGroupOwnerTrustLevelMajor
        self.timestamp = snapshotItem.timestamp
        self.trustTypeRaw = snapshotItem.trustTypeRaw
        self.rawObvGroupV2Identifier = snapshotItem.rawObvGroupV2Identifier
    }

}


// MARK: - Returning a TrustOrigin and TrustLevel

extension PersistedTrustOrigin {
    
    var trustOrigin: TrustOrigin? {
        
        switch self.trustTypeRaw {
        case 0:
            return .direct(timestamp: self.timestamp)
        case 1:
            guard let groupOwner = self.mediatorOrGroupOwnerCryptoIdentity else { return nil }
            return .group(timestamp: self.timestamp, groupOwner: groupOwner)
        case 2:
            guard let mediatorIdentity = self.mediatorOrGroupOwnerCryptoIdentity else { return nil }
            return .introduction(timestamp: self.timestamp, mediator: mediatorIdentity)
        case 3:
            guard let keycloakServer = self.identityServer else { return nil }
            return .keycloak(timestamp: self.timestamp, keycloakServer: keycloakServer)
        case 4:
            guard let rawObvGroupV2Identifier = self.rawObvGroupV2Identifier,
                  let encoded = ObvEncoded(withRawData: rawObvGroupV2Identifier),
                  let obvGroupV2Identifier = ObvGroupV2.Identifier(encoded) else { assertionFailure(); return nil }
            return .serverGroupV2(timestamp: self.timestamp, groupIdentifier: obvGroupV2Identifier)
        default:
            assertionFailure()
            return nil
        }
        
    }
    
    var trustLevel: TrustLevel? {
        
        switch self.trustTypeRaw {
        case 0:
            /* .direct */
            return TrustLevel.forDirect()
        case 1, 2:
            /* .group or .introduction */
            // The minor level of the TrustLevel of this TrustOrigin the major of the TrustLevel of the groupOwner/mediator
            guard let minor = self.mediatorOrGroupOwnerTrustLevelMajor?.intValue else { return nil }
            return TrustLevel.forGroupOrIntroduction(withMinor: minor)
        case 3:
            return TrustLevel.forServer()
        case 4:
            return TrustLevel.forGroupV2()
        default:
            return nil
        }

    }
    
}


// MARK: - Private TrustOrigin extension

private extension TrustOrigin {
    
    var trustTypeRaw: Int {
        switch self {
        case .direct: return 0
        case .group: return 1
        case .introduction: return 2
        case .keycloak: return 3
        case .serverGroupV2: return 4
        }
    }
    
    var timestamp: Date {
        switch self {
        case .direct(timestamp: let timestamp): return timestamp
        case .group(timestamp: let timestamp, groupOwner: _): return timestamp
        case .introduction(timestamp: let timestamp, mediator: _): return timestamp
        case .keycloak(timestamp: let timestamp, keycloakServer: _): return timestamp
        case .serverGroupV2(timestamp: let timestamp, groupIdentifier: _): return timestamp
        }
    }
    
}


// MARK: - For Backup purposes

extension PersistedTrustOrigin {
    
    var backupItem: PersistedTrustOriginBackupItem {
        return PersistedTrustOriginBackupItem(identityServer: identityServer,
                                              mediatorOrGroupOwnerCryptoIdentity: mediatorOrGroupOwnerCryptoIdentity,
                                              mediatorOrGroupOwnerTrustLevelMajor: mediatorOrGroupOwnerTrustLevelMajor,
                                              timestamp: timestamp,
                                              trustTypeRaw: trustTypeRaw,
                                              rawObvGroupV2Identifier: rawObvGroupV2Identifier)
    }
    

}


struct PersistedTrustOriginBackupItem: Codable, Hashable {

    fileprivate let identityServer: URL?
    fileprivate let mediatorOrGroupOwnerCryptoIdentity: ObvCryptoIdentity?
    fileprivate let mediatorOrGroupOwnerTrustLevelMajor: NSNumber?
    fileprivate let timestamp: Date
    fileprivate let trustTypeRaw: Int
    fileprivate let rawObvGroupV2Identifier: Data?

    // Allows to prevent association failures in two items have identical variables
    private let transientUuid = UUID()

    private static let errorDomain = String(describing: PersistedTrustOriginBackupItem.self)

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    fileprivate init(identityServer: URL?, mediatorOrGroupOwnerCryptoIdentity: ObvCryptoIdentity?, mediatorOrGroupOwnerTrustLevelMajor: NSNumber?, timestamp: Date, trustTypeRaw: Int, rawObvGroupV2Identifier: Data?) {
        self.identityServer = identityServer
        self.mediatorOrGroupOwnerCryptoIdentity = mediatorOrGroupOwnerCryptoIdentity
        self.mediatorOrGroupOwnerTrustLevelMajor = mediatorOrGroupOwnerTrustLevelMajor
        self.timestamp = timestamp
        self.trustTypeRaw = trustTypeRaw
        self.rawObvGroupV2Identifier = rawObvGroupV2Identifier
    }

    enum CodingKeys: String, CodingKey {
        case identityServer = "identity_server"
        case mediatorOrGroupOwnerCryptoIdentity = "mediator_or_group_owner_identity"
        case mediatorOrGroupOwnerTrustLevelMajor = "mediator_or_group_owner_trust_level_major"
        case timestamp = "timestamp"
        case trustTypeRaw = "trust_type"
        case rawObvGroupV2Identifier = "raw_obv_group_v2_identifier"
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(identityServer, forKey: .identityServer)
        try container.encodeIfPresent(mediatorOrGroupOwnerCryptoIdentity?.getIdentity(), forKey: .mediatorOrGroupOwnerCryptoIdentity)
        try container.encodeIfPresent(mediatorOrGroupOwnerTrustLevelMajor?.intValue, forKey: .mediatorOrGroupOwnerTrustLevelMajor)
        try container.encodeIfPresent(Int(timestamp.timeIntervalSince1970 * 1000), forKey: .timestamp)
        try container.encodeIfPresent(trustTypeRaw, forKey: .trustTypeRaw)
        try container.encodeIfPresent(rawObvGroupV2Identifier, forKey: .rawObvGroupV2Identifier)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.identityServer = try values.decodeIfPresent(URL.self, forKey: .identityServer)
        if let identity = try values.decodeIfPresent(Data.self, forKey: .mediatorOrGroupOwnerCryptoIdentity) {
            guard let cryptoIdentity = ObvCryptoIdentity(from: identity) else {
                throw PersistedTrustOriginBackupItem.makeError(message: "Could not parse identity")
            }
            self.mediatorOrGroupOwnerCryptoIdentity = cryptoIdentity
            if let trustLevel = try values.decodeIfPresent(Int.self, forKey: .mediatorOrGroupOwnerTrustLevelMajor) {
                self.mediatorOrGroupOwnerTrustLevelMajor = NSNumber(value: trustLevel)
            } else {
                self.mediatorOrGroupOwnerTrustLevelMajor = nil
            }
        } else {
            self.mediatorOrGroupOwnerCryptoIdentity = nil
            self.mediatorOrGroupOwnerTrustLevelMajor = nil
        }
        let timestamp = try values.decode(Int.self, forKey: .timestamp)
        self.timestamp = Date(timeIntervalSince1970: Double(timestamp)/1000.0)
        self.trustTypeRaw = try values.decode(Int.self, forKey: .trustTypeRaw)
        self.rawObvGroupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .rawObvGroupV2Identifier)
    }
 
    func restoreInstance(within obvContext: ObvContext, associations: inout BackupItemObjectAssociations) throws {
        let persistedTrustOrigin = PersistedTrustOrigin(backupItem: self, within: obvContext)
        try associations.associate(persistedTrustOrigin, to: self)
    }
    
    func restoreRelationships(associations: BackupItemObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing do to here
    }
}


// MARK: - For Snapshot purposes

extension PersistedTrustOrigin {
    
    var snapshotItem: PersistedTrustOriginSyncSnapshotItem {
        return PersistedTrustOriginSyncSnapshotItem(
            identityServer: identityServer,
            mediatorOrGroupOwnerCryptoIdentity: mediatorOrGroupOwnerCryptoIdentity,
            mediatorOrGroupOwnerTrustLevelMajor: mediatorOrGroupOwnerTrustLevelMajor,
            timestamp: timestamp,
            trustTypeRaw: trustTypeRaw,
            rawObvGroupV2Identifier: rawObvGroupV2Identifier)
    }

}


struct PersistedTrustOriginSyncSnapshotItem: Codable, Hashable, Identifiable {

    fileprivate let identityServer: URL?
    fileprivate let mediatorOrGroupOwnerCryptoIdentity: ObvCryptoIdentity?
    fileprivate let mediatorOrGroupOwnerTrustLevelMajor: NSNumber?
    fileprivate let timestamp: Date
    fileprivate let trustTypeRaw: Int
    fileprivate let rawObvGroupV2Identifier: Data?

    let id = ObvSyncSnapshotNodeUtils.generateIdentifier()

    enum CodingKeys: String, CodingKey {
        case identityServer = "identity_server"
        case mediatorOrGroupOwnerCryptoIdentity = "mediator_or_group_owner_identity"
        case mediatorOrGroupOwnerTrustLevelMajor = "mediator_or_group_owner_trust_level_major"
        case timestamp = "timestamp"
        case trustTypeRaw = "trust_type"
        case rawObvGroupV2Identifier = "raw_obv_group_v2_identifier"
        case domain = "domain"
    }

    
    fileprivate init(identityServer: URL?, mediatorOrGroupOwnerCryptoIdentity: ObvCryptoIdentity?, mediatorOrGroupOwnerTrustLevelMajor: NSNumber?, timestamp: Date, trustTypeRaw: Int, rawObvGroupV2Identifier: Data?) {
        self.identityServer = identityServer
        self.mediatorOrGroupOwnerCryptoIdentity = mediatorOrGroupOwnerCryptoIdentity
        self.mediatorOrGroupOwnerTrustLevelMajor = mediatorOrGroupOwnerTrustLevelMajor
        self.timestamp = timestamp
        self.trustTypeRaw = trustTypeRaw
        self.rawObvGroupV2Identifier = rawObvGroupV2Identifier
    }

    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(identityServer, forKey: .identityServer)
        try container.encodeIfPresent(mediatorOrGroupOwnerCryptoIdentity?.getIdentity(), forKey: .mediatorOrGroupOwnerCryptoIdentity)
        try container.encodeIfPresent(mediatorOrGroupOwnerTrustLevelMajor?.intValue, forKey: .mediatorOrGroupOwnerTrustLevelMajor)
        try container.encodeIfPresent(Int(timestamp.timeIntervalSince1970 * 1000), forKey: .timestamp)
        try container.encodeIfPresent(trustTypeRaw, forKey: .trustTypeRaw)
        try container.encodeIfPresent(rawObvGroupV2Identifier, forKey: .rawObvGroupV2Identifier)
    }
    

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.identityServer = try values.decodeIfPresent(URL.self, forKey: .identityServer)
        if let identity = try values.decodeIfPresent(Data.self, forKey: .mediatorOrGroupOwnerCryptoIdentity) {
            guard let cryptoIdentity = ObvCryptoIdentity(from: identity) else {
                throw ObvError.couldNotParseIdentity
            }
            self.mediatorOrGroupOwnerCryptoIdentity = cryptoIdentity
            if let trustLevel = try values.decodeIfPresent(Int.self, forKey: .mediatorOrGroupOwnerTrustLevelMajor) {
                self.mediatorOrGroupOwnerTrustLevelMajor = NSNumber(value: trustLevel)
            } else {
                self.mediatorOrGroupOwnerTrustLevelMajor = nil
            }
        } else {
            self.mediatorOrGroupOwnerCryptoIdentity = nil
            self.mediatorOrGroupOwnerTrustLevelMajor = nil
        }
        let timestamp = try values.decode(Int.self, forKey: .timestamp)
        self.timestamp = Date(timeIntervalSince1970: Double(timestamp)/1000.0)
        self.trustTypeRaw = try values.decode(Int.self, forKey: .trustTypeRaw)
        self.rawObvGroupV2Identifier = try values.decodeIfPresent(Data.self, forKey: .rawObvGroupV2Identifier)
    }
 
    
    func restoreInstance(within obvContext: ObvContext, associations: inout SnapshotNodeManagedObjectAssociations) throws {
        let persistedTrustOrigin = PersistedTrustOrigin(snapshotItem: self, within: obvContext)
        try associations.associate(persistedTrustOrigin, to: self)
    }
    
    
    func restoreRelationships(associations: SnapshotNodeManagedObjectAssociations, within obvContext: ObvContext) throws {
        // Nothing do to here
    }
    
    
    enum ObvError: Error {
        case couldNotParseIdentity
    }
    
}
