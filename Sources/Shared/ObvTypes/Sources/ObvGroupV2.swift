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
import OlvidUtils
import ObvEncoder
import ObvCrypto
import CryptoKit


public struct ObvGroupV2: ObvErrorMaker, ObvFailableCodable, Equatable, Hashable {
    
    let groupIdentifier: Identifier
    public let ownIdentity: ObvCryptoId
    public let ownPermissions: Set<Permission>
    public let otherMembers: Set<IdentityAndPermissionsAndDetails>
    public let trustedDetailsAndPhoto: DetailsAndPhoto
    public let publishedDetailsAndPhoto: DetailsAndPhoto?
    public let updateInProgress: Bool
    public let serializedSharedSettings: String? // non-nil only for keycloak groups
    public let lastModificationTimestamp: Date? // non-nil only for keycloak groups
    public let serializedGroupType: Data?

    public static let errorDomain = "ObvGroupV2"

    private enum ObvCodingKeys: String, CaseIterable, CodingKey {
        case groupIdentifier = "gi"
        case ownIdentity = "oi"
        case ownPermissions = "op"
        case otherMembers = "om"
        case trustedDetailsAndPhoto = "tdp"
        case publishedDetailsAndPhoto = "pdp"
        case updateInProgress = "uip"
        case serializedSharedSettings = "sss"
        case lastModificationTimestamp = "lmt"
        case serializedGroupType = "sgt"
        var key: Data { rawValue.data(using: .utf8)! }
    }

    public init(groupIdentifier: Identifier, ownIdentity: ObvCryptoId, ownPermissions: Set<Permission>, otherMembers: Set<IdentityAndPermissionsAndDetails>, trustedDetailsAndPhoto: DetailsAndPhoto, publishedDetailsAndPhoto: DetailsAndPhoto?, updateInProgress: Bool, serializedSharedSettings: String?, lastModificationTimestamp: Date?, serializedGroupType: Data?) {
        self.groupIdentifier = groupIdentifier
        self.ownIdentity = ownIdentity
        self.ownPermissions = ownPermissions
        self.otherMembers = otherMembers
        self.trustedDetailsAndPhoto = trustedDetailsAndPhoto
        self.publishedDetailsAndPhoto = publishedDetailsAndPhoto
        self.updateInProgress = updateInProgress
        self.serializedSharedSettings = serializedSharedSettings
        self.lastModificationTimestamp = lastModificationTimestamp
        self.serializedGroupType = serializedGroupType
    }
    
    public var appGroupIdentifier: GroupV2Identifier {
        groupIdentifier.appGroupIdentifier
    }
    
    public var obvGroupIdentifier: ObvGroupV2Identifier {
        ObvGroupV2Identifier(ownedCryptoId: ownIdentity, identifier: groupIdentifier)
    }
    
    public var keycloakManaged: Bool {
        switch groupIdentifier.category {
        case .server:
            return false
        case .keycloak:
            return true
        }
    }
    
    // ObvCodable
    
    public func obvEncode() throws -> ObvEncoded {
        var obvDict = [Data: ObvEncoded]()
        for codingKey in ObvCodingKeys.allCases {
            switch codingKey {
            case .groupIdentifier:
                try obvDict.obvEncode(groupIdentifier, forKey: codingKey)
            case .ownIdentity:
                try obvDict.obvEncode(ownIdentity, forKey: codingKey)
            case .ownPermissions:
                try obvDict.obvEncode(ownPermissions, forKey: codingKey)
            case .otherMembers:
                try obvDict.obvEncode(otherMembers, forKey: codingKey)
            case .trustedDetailsAndPhoto:
                try obvDict.obvEncode(trustedDetailsAndPhoto, forKey: codingKey)
            case .publishedDetailsAndPhoto:
                try obvDict.obvEncodeIfPresent(publishedDetailsAndPhoto, forKey: codingKey)
            case .updateInProgress:
                try obvDict.obvEncode(updateInProgress, forKey: codingKey)
            case .serializedSharedSettings:
                try obvDict.obvEncodeIfPresent(serializedSharedSettings, forKey: codingKey)
            case .lastModificationTimestamp:
                try obvDict.obvEncodeIfPresent(lastModificationTimestamp, forKey: codingKey)
            case .serializedGroupType:
                try obvDict.obvEncodeIfPresent(serializedGroupType, forKey: codingKey)
            }
        }
        return obvDict.obvEncode()
    }

    
    public init?(_ obvEncoded: ObvEncoded) {
        guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
        do {
            let groupIdentifier = try obvDict.obvDecode(Identifier.self, forKey: ObvCodingKeys.groupIdentifier)
            let ownIdentity = try obvDict.obvDecode(ObvCryptoId.self, forKey: ObvCodingKeys.ownIdentity)
            let ownPermissions = try obvDict.obvDecode(Set<Permission>.self, forKey: ObvCodingKeys.ownPermissions)
            let otherMembers = try obvDict.obvDecode(Set<IdentityAndPermissionsAndDetails>.self, forKey: ObvCodingKeys.otherMembers)
            let trustedDetailsAndPhoto = try obvDict.obvDecode(DetailsAndPhoto.self, forKey: ObvCodingKeys.trustedDetailsAndPhoto)
            let publishedDetailsAndPhoto = try obvDict.obvDecodeIfPresent(DetailsAndPhoto.self, forKey: ObvCodingKeys.publishedDetailsAndPhoto)
            let updateInProgress = try obvDict.obvDecode(Bool.self, forKey: ObvCodingKeys.updateInProgress)
            let serializedSharedSettings = try obvDict.obvDecodeIfPresent(String.self, forKey: ObvCodingKeys.serializedSharedSettings)
            let lastModificationTimestamp = try obvDict.obvDecodeIfPresent(Date.self, forKey: ObvCodingKeys.lastModificationTimestamp)
            let serializedGroupType = try obvDict.obvDecodeIfPresent(Data.self, forKey: ObvCodingKeys.serializedGroupType)
            self.init(groupIdentifier: groupIdentifier,
                      ownIdentity: ownIdentity,
                      ownPermissions: ownPermissions,
                      otherMembers: otherMembers,
                      trustedDetailsAndPhoto: trustedDetailsAndPhoto,
                      publishedDetailsAndPhoto: publishedDetailsAndPhoto,
                      updateInProgress: updateInProgress,
                      serializedSharedSettings: serializedSharedSettings,
                      lastModificationTimestamp: lastModificationTimestamp,
                      serializedGroupType: serializedGroupType)
        } catch {
            assertionFailure(error.localizedDescription)
            return nil
        }
    }

    
    // Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(groupIdentifier)
    }
    

    // MARK: - Identifier

    /// The `Codable` conformance should **not** be used within long term storage since we may change it regularly.
    public struct Identifier: ObvErrorMaker, ObvCodable, Equatable, Hashable, Codable, Sendable {
        
        public static let errorDomain = "ObvGroupV2.Identifier"

        /// The `Codable` conformance should **not** be used within long term storage since we may change it regularly.
        public enum Category: Int, Codable, Sendable {
            case server = 0
            case keycloak = 1
        }
        
        public let groupUID: UID
        public let serverURL: URL
        public let category: Category

        
        public init(groupUID: UID, serverURL: URL, category: Category) {
            self.groupUID = groupUID
            self.serverURL = serverURL
            self.category = category
        }
        
        
        public init?(appGroupIdentifier: Data) {
            guard let obvEncoded = ObvEncoded(withRawData: appGroupIdentifier) else { assertionFailure(); return nil }
            self.init(obvEncoded)
        }
        
        // ObvCodable
        
        public func obvEncode() -> ObvEncoded {
            return [groupUID.obvEncode(), serverURL.obvEncode(), category.rawValue.obvEncode()].obvEncode()
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 3) else { assertionFailure(); return nil }
            guard let groupUID: UID = try? encodedValues[0].obvDecode(),
                  let serverURL: URL = try? encodedValues[1].obvDecode(),
                  let rawCategory: Int = try? encodedValues[2].obvDecode(),
                  let category = Category(rawValue: rawCategory)
            else {
                assertionFailure()
                return nil
            }
            self.init(groupUID: groupUID, serverURL: serverURL, category: category)
        }

        public var appGroupIdentifier: Data {
            self.obvEncode().rawData
        }

        // Equatable
        
        public static func == (lhs: Identifier, rhs: Identifier) -> Bool {
            lhs.groupUID == rhs.groupUID && lhs.serverURL == rhs.serverURL && lhs.category == rhs.category
        }
        
        // Hashable (required to make ObvTrustOrigin hashable)
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(groupUID)
            hasher.combine(serverURL)
            hasher.combine(category)
        }

    }

    // MARK: - Permission
    
    public enum Permission: String, CaseIterable, ObvCodable, ObvErrorMaker, Sendable {
        case groupAdmin = "ga"
        case remoteDeleteAnything = "rd" // Allows to remote delete any message or discussion
        case editOrRemoteDeleteOwnMessages = "eo" // Allows to edit and remote delete own messages
        case changeSettings = "cs"
        case sendMessage = "sm"
        
        public static let errorDomain = "ObvGroupV2.Permission"

        public func obvEncode() -> ObvEncoded {
            return self.rawValue.obvEncode()
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            do {
                let rawValue: String = try obvEncoded.obvDecode()
                guard let value = Permission(rawValue: rawValue) else { throw Self.makeError(message: "Could not parse decoded raw value") }
                self = value
            } catch {
                assertionFailure()
                return nil
            }
        }
        
    }
    
    // MARK: - IdentityAndPermissions

    public struct IdentityAndPermissions: Hashable, ObvCodable {
            
        public let identity: ObvCryptoId
        public let permissions: Set<Permission>
        
        public init(identity: ObvCryptoId, permissions: Set<Permission>) {
            self.identity = identity
            self.permissions = permissions
        }
        
        public var hasGroupAdminPermission: Bool {
            permissions.contains(.groupAdmin)
        }
        
        // ObvCodable
        
        public func obvEncode() -> ObvEncoded {
            let encodedIdentity = identity.obvEncode()
            let encodedPermissions = permissions.map({ $0.rawValue.obvEncode() }).obvEncode()
            return [encodedIdentity, encodedPermissions].obvEncode()
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); return nil }
            let encodedIdentity = encodedValues[0]
            let encodedPermissions = encodedValues[1]
            guard let identity = ObvCryptoIdentity(encodedIdentity) else { assertionFailure(); return nil }
            guard let listOfEncodedPermissions = [ObvEncoded](encodedPermissions) else { assertionFailure(); return nil }
            let permissions: Set<Permission> = Set(listOfEncodedPermissions.compactMap({ Permission($0) }))
            assert(permissions.count == listOfEncodedPermissions.count)
            self.init(identity: ObvCryptoId(cryptoIdentity: identity), permissions: permissions)
        }

    }

    
    // MARK: - IdentityAndPermissionsAndDetails

    public struct IdentityAndPermissionsAndDetails: Hashable, ObvCodable {
            
        private let identityAndPermissions: IdentityAndPermissions
        public let serializedIdentityCoreDetails: Data
        public let isPending: Bool
        
        public init(identity: ObvCryptoId, permissions: Set<Permission>, serializedIdentityCoreDetails: Data, isPending: Bool) {
            self.identityAndPermissions = IdentityAndPermissions(identity: identity, permissions: permissions)
            self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
            self.isPending = isPending
        }

        private init(identityAndPermissions: IdentityAndPermissions, serializedIdentityCoreDetails: Data, isPending: Bool) {
            self.identityAndPermissions = identityAndPermissions
            self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
            self.isPending = isPending
        }

        public var hasGroupAdminPermission: Bool {
            identityAndPermissions.hasGroupAdminPermission
        }
        
        public var identity: ObvCryptoId {
            identityAndPermissions.identity
        }
        
        public var permissions: Set<Permission> {
            identityAndPermissions.permissions
        }
        
        // ObvCodable
        
        public func obvEncode() -> ObvEncoded {
            let encodedIdentityAndPermissions = identityAndPermissions.obvEncode()
            let encodedSerializedCoreDetails = serializedIdentityCoreDetails.obvEncode()
            let encodedIsPending = isPending.obvEncode()
            return [encodedIdentityAndPermissions, encodedSerializedCoreDetails, encodedIsPending].obvEncode()
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 3) else { assertionFailure(); return nil }
            let encodedIdentityAndPermissions = encodedValues[0]
            let encodedSerializedCoreDetails = encodedValues[1]
            let encodedIsPending = encodedValues[2]
            guard let identityAndPermissions = IdentityAndPermissions(encodedIdentityAndPermissions) else { assertionFailure(); return nil }
            guard let serializedIdentityCoreDetails: Data = try? encodedSerializedCoreDetails.obvDecode() else { return nil }
            guard let isPending = Bool(encodedIsPending) else { return nil }
            self.init(identityAndPermissions: identityAndPermissions, serializedIdentityCoreDetails: serializedIdentityCoreDetails, isPending: isPending)
        }

        // Hashable

        // Although we only match the Identity in the (internal) GroupV2 structure, we don't do that here since we need to test a full equality at the ObvDialog level.
        // We thus keep the synthetized implementation.

    }
    
    
    // MARK: - KeycloakGroupMemberAndPermissions

    public struct KeycloakGroupMemberAndPermissions: Hashable, ObvCodable {
            
        private let identityAndPermissions: IdentityAndPermissions
        private let signedUserDetails: String

        public init(identity: ObvCryptoId, permissions: Set<Permission>, signedUserDetails: String) {
            self.identityAndPermissions = IdentityAndPermissions(identity: identity, permissions: permissions)
            self.signedUserDetails = signedUserDetails
        }

        private init(identityAndPermissions: IdentityAndPermissions, signedUserDetails: String) {
            self.identityAndPermissions = identityAndPermissions
            self.signedUserDetails = signedUserDetails
        }

        public var identity: ObvCryptoId {
            identityAndPermissions.identity
        }
        
        public var permissions: Set<Permission> {
            identityAndPermissions.permissions
        }
        
        // ObvCodable
        
        public func obvEncode() -> ObvEncoded {
            let encodedIdentityAndPermissions = identityAndPermissions.obvEncode()
            let encodedSignedUserDetails = signedUserDetails.obvEncode()
            return [encodedIdentityAndPermissions, encodedSignedUserDetails].obvEncode()
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); return nil }
            let encodedIdentityAndPermissions = encodedValues[0]
            let encodedSignedUserDetails = encodedValues[1]
            guard let identityAndPermissions = IdentityAndPermissions(encodedIdentityAndPermissions) else { assertionFailure(); return nil }
            guard let signedUserDetails = String(encodedSignedUserDetails) else { assertionFailure(); return nil }
            self.init(identityAndPermissions: identityAndPermissions, signedUserDetails: signedUserDetails)
        }

        // Hashable

        // Although we only match the Identity in the (internal) GroupV2 structure, we don't do that here since we need to test a full equality at the ObvDialog level.
        // We thus keep the synthetized implementation.

    }

    
    // MARK: - DetailsAndPhoto
    
    public struct DetailsAndPhoto: ObvFailableCodable, Equatable {
        
        public let serializedGroupCoreDetails: Data
        public let photoURLFromEngine: PhotoURLFromEngineType
        
        public enum PhotoURLFromEngineType: ObvCodable, Equatable {
            case none
            case downloaded(url: URL)
            case downloading
            
            private var rawValue: Int {
                switch self {
                case .none: return 0
                case .downloaded: return 1
                case .downloading: return 2
                }
            }
            
            public func obvEncode() -> ObvEncoded {
                switch self {
                case .none, .downloading:
                    return [self.rawValue.obvEncode()].obvEncode()
                case .downloaded(let url):
                    return [self.rawValue.obvEncode(), url.obvEncode()].obvEncode()
                }
            }
            
            public init?(_ obvEncoded: ObvEncoded) {
                guard let listOfEncoded = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
                guard let encodedRawValue = listOfEncoded.first else { return nil }
                guard let rawValue = Int(encodedRawValue) else { return nil }
                switch rawValue {
                case 0:
                    assert(listOfEncoded.count == 1)
                    self = .none
                case 1:
                    guard listOfEncoded.count == 2 else { assertionFailure(); return nil }
                    guard let url = URL(listOfEncoded[1]) else { return nil }
                    self = .downloaded(url: url)
                case 2:
                    assert(listOfEncoded.count == 1)
                    self = .downloading
                default:
                    assertionFailure()
                    return nil
                }
            }
            
            public var url: URL? {
                switch self {
                case .none, .downloading:
                    return nil
                case .downloaded(let url):
                    return url
                }
            }

        }
        
        public init(serializedGroupCoreDetails: Data, photoURLFromEngine: PhotoURLFromEngineType) {
            self.serializedGroupCoreDetails = serializedGroupCoreDetails
            self.photoURLFromEngine = photoURLFromEngine
        }
        
        
        private enum ObvCodingKeys: String, CaseIterable, CodingKey {
            case serializedGroupCoreDetails = "sgcd"
            case photoURLFromEngine = "pufe"
            var key: Data { rawValue.data(using: .utf8)! }
        }

        
        public func obvEncode() throws -> ObvEncoded {
            var obvDict = [Data: ObvEncoded]()
            for codingKey in ObvCodingKeys.allCases {
                switch codingKey {
                case .serializedGroupCoreDetails:
                    try obvDict.obvEncode(serializedGroupCoreDetails, forKey: codingKey)
                case .photoURLFromEngine:
                    try obvDict.obvEncodeIfPresent(photoURLFromEngine, forKey: codingKey)
                }
            }
            return obvDict.obvEncode()
        }
        
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
            do {
                let serializedGroupCoreDetails = try obvDict.obvDecode(Data.self, forKey: ObvCodingKeys.serializedGroupCoreDetails)
                let photoURLFromEngine = try obvDict.obvDecodeIfPresent(PhotoURLFromEngineType.self, forKey: ObvCodingKeys.photoURLFromEngine) ?? .none
                self.init(serializedGroupCoreDetails: serializedGroupCoreDetails, photoURLFromEngine: photoURLFromEngine)
            } catch {
                assertionFailure(error.localizedDescription)
                return nil
            }
        }

    }
    
    
    // MARK: - Change type for changeset
    
    public enum ChangeValue: Int, CaseIterable {
        case memberRemoved = 0
        case memberAdded = 1
        case memberChanged = 2
        case ownPermissionsChanged = 3
        case groupDetails = 4
        case groupPhoto = 5
        case groupType = 6
    }
    
    public enum Change: Hashable, ObvFailableCodable, Sendable {
        case memberRemoved(contactCryptoId: ObvCryptoId)
        case memberAdded(contactCryptoId: ObvCryptoId, permissions: Set<Permission>)
        case memberChanged(contactCryptoId: ObvCryptoId, permissions: Set<Permission>)
        case ownPermissionsChanged(permissions: Set<Permission>) // If we are an admin, we can change our own permissions
        case groupDetails(serializedGroupCoreDetails: Data)
        case groupPhoto(photoURL: URL?)
        case groupType(serializedGroupType: Data)

        var value: ChangeValue {
            switch self {
            case .memberRemoved: return .memberRemoved
            case .memberAdded: return .memberAdded
            case .memberChanged: return .memberChanged
            case .ownPermissionsChanged: return .ownPermissionsChanged
            case .groupDetails: return .groupDetails
            case .groupPhoto: return .groupPhoto
            case .groupType: return .groupType
            }
        }
        
        private var rawValue: Int {
            value.rawValue
        }
        
        public var isGroupPhotoChange: Bool {
            switch self {
            case .groupPhoto:
                return true
            default:
                return false
            }
        }
        
        public var serializedGroupTypeInChange: Data? {
            switch self {
            case .groupType(let serializedGroupType):
                return serializedGroupType
            default:
                return nil
            }
        }
        
        fileprivate var orderCriteria: Int {
            switch self {
            case .memberRemoved: return 0
            case .memberChanged: return 1
            case .memberAdded: return 2
            case .ownPermissionsChanged: return 3
            case .groupDetails: return 4
            case .groupPhoto: return 5
            case .groupType: return 6
            }
        }
        
        fileprivate var contactCryptoId: ObvCryptoId? {
            switch self {
            case .memberRemoved(let contactCryptoId),
                    .memberAdded(let contactCryptoId, _),
                    .memberChanged(let contactCryptoId, _):
                return contactCryptoId
            case .groupDetails, .groupPhoto, .ownPermissionsChanged, .groupType:
                return nil
            }
        }
        
        private var permissions: Set<Permission>? {
            switch self {
            case .memberAdded(_, let permissions), .memberChanged(_, let permissions), .ownPermissionsChanged(let permissions):
                return permissions
            case .memberRemoved, .groupDetails, .groupPhoto, .groupType:
                return nil
            }
        }
        
        
        private var serializedGroupCoreDetails: Data? {
            switch self {
            case .groupDetails(let serializedGroupCoreDetails):
                return serializedGroupCoreDetails
            case .memberRemoved, .memberAdded, .memberChanged, .groupPhoto, .ownPermissionsChanged, .groupType:
                return nil
            }
        }
        
        private var serializedGroupType: Data? {
            switch self {
            case .groupType(let serializedGroupType):
                return serializedGroupType
            case .memberRemoved, .memberAdded, .memberChanged, .groupPhoto, .ownPermissionsChanged, .groupDetails:
                return nil
            }
        }
        
        private var photoURL: URL? {
            switch self {
            case .groupPhoto(let photoURL):
                return photoURL
            case .memberRemoved, .memberAdded, .memberChanged, .groupDetails, .ownPermissionsChanged, .groupType:
                return nil
            }
        }

        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(rawValue)
            hasher.combine(contactCryptoId)
        }
        
                
        private enum ObvCodingKeys: String, CaseIterable, CodingKey {
            case rawValue = "rv"
            case contactCryptoId = "cci"
            case permissions = "p"
            case serializedGroupCoreDetails = "sgcd"
            case photoURL = "pu"
            case serializedGroupType = "gt"
            var key: Data { rawValue.data(using: .utf8)! }
        }
        
        public func obvEncode() throws -> ObvEncoded {
            var obvDict = [Data: ObvEncoded]()
            for codingKey in ObvCodingKeys.allCases {
                switch codingKey {
                case .rawValue:
                    try obvDict.obvEncode(rawValue, forKey: codingKey)
                case .contactCryptoId:
                    try obvDict.obvEncodeIfPresent(contactCryptoId, forKey: codingKey)
                case .permissions:
                    try obvDict.obvEncodeIfPresent(permissions, forKey: codingKey)
                case .serializedGroupCoreDetails:
                    try obvDict.obvEncodeIfPresent(serializedGroupCoreDetails, forKey: codingKey)
                case .photoURL:
                    try obvDict.obvEncodeIfPresent(photoURL, forKey: codingKey)
                case .serializedGroupType:
                    try obvDict.obvEncodeIfPresent(serializedGroupType, forKey: codingKey)
                }
            }
            return obvDict.obvEncode()
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
            do {
                let rawValue = try obvDict.obvDecode(Int.self, forKey: ObvCodingKeys.rawValue)
                let contactCryptoId = try obvDict.obvDecodeIfPresent(ObvCryptoId.self, forKey: ObvCodingKeys.contactCryptoId)
                let permissions = try obvDict.obvDecodeIfPresent(Set<ObvGroupV2.Permission>.self, forKey: ObvCodingKeys.permissions)
                let serializedGroupCoreDetails = try obvDict.obvDecodeIfPresent(Data.self, forKey: ObvCodingKeys.serializedGroupCoreDetails)
                let photoURL = try obvDict.obvDecodeIfPresent(URL.self, forKey: ObvCodingKeys.photoURL)
                let serializedGroupType = try obvDict.obvDecodeIfPresent(Data.self, forKey: ObvCodingKeys.serializedGroupType)
                switch rawValue {
                case 0:
                    guard let contactCryptoId = contactCryptoId else { assertionFailure(); return nil }
                    assert(permissions == nil)
                    assert(serializedGroupCoreDetails == nil)
                    assert(photoURL == nil)
                    self = .memberRemoved(contactCryptoId: contactCryptoId)
                case 1:
                    guard let contactCryptoId = contactCryptoId else { assertionFailure(); return nil }
                    guard let permissions = permissions else { assertionFailure(); return nil }
                    assert(serializedGroupCoreDetails == nil)
                    assert(photoURL == nil)
                    self = .memberAdded(contactCryptoId: contactCryptoId, permissions: permissions)
                case 2:
                    guard let contactCryptoId = contactCryptoId else { assertionFailure(); return nil }
                    guard let permissions = permissions else { assertionFailure(); return nil }
                    assert(serializedGroupCoreDetails == nil)
                    assert(photoURL == nil)
                    self = .memberChanged(contactCryptoId: contactCryptoId, permissions: permissions)
                case 3:
                    guard let permissions = permissions else { assertionFailure(); return nil }
                    assert(contactCryptoId == nil)
                    assert(serializedGroupCoreDetails == nil)
                    assert(photoURL == nil)
                    self = .ownPermissionsChanged(permissions: permissions)
                case 4:
                    assert(contactCryptoId == nil)
                    assert(permissions == nil)
                    guard let serializedGroupCoreDetails = serializedGroupCoreDetails else { assertionFailure(); return nil }
                    assert(photoURL == nil)
                    self = .groupDetails(serializedGroupCoreDetails: serializedGroupCoreDetails)
                case 5:
                    assert(contactCryptoId == nil)
                    assert(permissions == nil)
                    assert(serializedGroupCoreDetails == nil)
                    self = .groupPhoto(photoURL: photoURL)
                case 6:
                    assert(contactCryptoId == nil)
                    assert(permissions == nil)
                    guard let serializedGroupType = serializedGroupType else { assertionFailure(); return nil }
                    assert(photoURL == nil)
                    assert(serializedGroupCoreDetails == nil)
                    self = .groupType(serializedGroupType: serializedGroupType)
                default:
                    assertionFailure()
                    return nil
                }
            } catch {
                assertionFailure(error.localizedDescription)
                return nil
            }
        }
        
    }
    
    
    // MARK: - Changeset
    
    public struct Changeset: ObvFailableCodable, ObvErrorMaker, Sendable {
        
        public let changes: Set<Change>
        
        public static let errorDomain = "ObvGroupV2.Changeset"

        public init(changes: Set<Change>) throws {
            guard Changeset.allMemberChangesConcernDistinctMembers(changes: changes) else {
                throw Self.makeError(message: "Invalid changeset: it contains two distinct changes that concern the same member")
            }
            guard Changeset.changesetContainsAtMostOneGroupDetailsChange(changes: changes) else {
                throw Self.makeError(message: "Invalid changeset: it contains more than one groupDetails changes")
            }
            guard Changeset.changesetContainsAtMostOneGroupTypeChange(changes: changes) else {
                throw Self.makeError(message: "Invalid changeset: it contains more than one groupType changes")
            }
            guard Changeset.changesetContainsAtMostOneGroupPhotoChange(changes: changes) else {
                throw Self.makeError(message: "Invalid changeset: it contains more than one groupPhoto changes")
            }
            self.changes = changes
        }
        
        
        /// When creating a `Changeset`, we do not want to have, e.g., a `memberAdded` and a `memberRemoved` for the same contact.
        /// This method returns `true` iff no such "colliding" changes exist.
        private static func allMemberChangesConcernDistinctMembers(changes: Set<Change>) -> Bool {
            let changesAboutMembers = changes.filter { $0.contactCryptoId != nil }
            let concernedMembers = Set(changesAboutMembers.compactMap({ $0.contactCryptoId }))
            return changesAboutMembers.count == concernedMembers.count
        }
        
        
        public var removedMembersCryptoIds: Set<ObvCryptoId> {
            var cryptoIds = Set<ObvCryptoId>()
            for change in changes {
                switch change {
                case .memberRemoved(contactCryptoId: let cryptoId):
                    cryptoIds.insert(cryptoId)
                default:
                    break
                }
            }
            return cryptoIds
        }

        
        public var addedMembersCryptoIds: Set<ObvCryptoId> {
            var cryptoIds = Set<ObvCryptoId>()
            for change in changes {
                switch change {
                case .memberAdded(contactCryptoId: let cryptoId, permissions: _):
                    cryptoIds.insert(cryptoId)
                default:
                    break
                }
            }
            return cryptoIds
        }
        
        
        public func specifiedPermissionsOfOtherMember(cryptoId: ObvCryptoId) -> Set<Permission>? {
            for change in orderedChanges.reversed() {
                switch change {
                case .memberAdded(contactCryptoId: let contactCryptoId, permissions: let permissions):
                    guard contactCryptoId == cryptoId else { continue }
                    return permissions
                case .memberChanged(contactCryptoId: let contactCryptoId, permissions: let permissions):
                    guard contactCryptoId == cryptoId else { continue }
                    return permissions
                case .ownPermissionsChanged, .groupDetails, .groupPhoto, .groupType, .memberRemoved:
                    continue
                }
            }
            return nil
        }

        
        /// When creating a `Changeset`, we do not want to have two distinct `groupDetails` changes.
        /// This method returns `true` iff there 0 or 1 `groupDetails` change in the `changes`.
        private static func changesetContainsAtMostOneGroupDetailsChange(changes: Set<Change>) -> Bool {
            let groupDetailsChanges = changes.filter({ change in
                switch change {
                case .groupDetails: return true
                default: return false
                }
            })
            return groupDetailsChanges.count < 2
        }
        
        /// When creating a `Changeset`, we do not want to have two distinct `groupType` changes.
        /// This method returns `true` iff there 0 or 1 `groupType` change in the `changes`.
        private static func changesetContainsAtMostOneGroupTypeChange(changes: Set<Change>) -> Bool {
            let groupTypeChanges = changes.filter({ change in
                switch change {
                case .groupType: return true
                default: return false
                }
            })
            return groupTypeChanges.count < 2
        }

        
        /// When creating a `Changeset`, we do not want to have two distinct `groupDetails` changes.
        /// This method returns `true` iff there 0 or 1 `groupPhoto` change in the `changes`.
        private static func changesetContainsAtMostOneGroupPhotoChange(changes: Set<Change>) -> Bool {
            let groupPhotoChanges = changes.filter({ change in
                switch change {
                case .groupPhoto: return true
                default: return false
                }
            })
            return groupPhotoChanges.count < 2
        }


        public var isEmpty: Bool {
            self.changes.isEmpty
        }
        
        public func obvEncode() throws -> ObvEncoded {
            try self.changes.map({ try $0.obvEncode() }).obvEncode()
        }
        
        /// If the changeset contains a `.groupPhoto` change (note that it can contain either 0 or 1, not more),
        /// this variable returns the `URL` of the new photo.
        public var photoURL: URL? {
            for change in changes {
                switch change {
                case .groupPhoto(photoURL: let photoURL):
                    return photoURL
                default:
                    continue
                }
            }
            return nil
        }
        
        public var containsDeletePhotoChange: Bool {
            for change in changes {
                switch change {
                case .groupPhoto(photoURL: let photoURL):
                    return photoURL == nil
                default:
                    continue
                }
            }
            return false
        }
        
        public var groupType: Data? {
            for change in changes {
                switch change {
                case .groupType(serializedGroupType: let serializedGroupType):
                    return serializedGroupType
                default: continue
                }
            }
            return nil
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let encodedElements = [ObvEncoded](obvEncoded) else { assertionFailure(); return nil }
            let changes = encodedElements.compactMap({ Change($0) })
            guard encodedElements.count == changes.count else { assertionFailure(); return nil }
            do {
                try self.init(changes: Set(changes))
            } catch {
                assertionFailure(error.localizedDescription)
                return nil
            }
        }
        
        public var orderedChanges: [Change] {
            self.changes.sorted { $0.orderCriteria < $1.orderCriteria }
        }
        
        
        /// Set of all `ObvCryptoId` concerned by at least one change within this changeset.
        public var concernedMembers: Set<ObvCryptoId> {
            Set(changes.compactMap({ $0.contactCryptoId }))
        }
        
        /// Return a new changeset with the original changes plus the new changes
        public func adding(newChanges: Set<Change>) throws -> Changeset {
            var returnedChanges = self.changes
            returnedChanges.formUnion(newChanges)
            return try Changeset(changes: returnedChanges)
        }
        
    }
    
    
    /// When a group v2 is created/updated within the identity manager, a notification is sent. It contains an indication of who was at the origin of the creation/update.
    public enum CreationOrUpdateInitiator {
        case createdOrUpdatedBySomeoneElse
        case createdByMe
        case updatedByMe
    }
    
}
