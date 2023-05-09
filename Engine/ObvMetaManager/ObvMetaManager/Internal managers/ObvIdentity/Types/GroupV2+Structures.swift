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
import ObvEncoder
import ObvCrypto
import CryptoKit
import OlvidUtils
import ObvTypes

public struct GroupV2 {
    
    // MARK: - AdministratorsChain
    
    public struct AdministratorsChain: ObvCodable, ObvErrorMaker {

        public static var errorDomain = "GroupV2.AdministratorsChain"

        public struct Block {
                        
            public struct InnerData: ObvCodable {
                
                let previousBlockHash: Data
                let encodedAdministrators: [ObvEncoded]
                
                private init(previousBlockHash: Data, encodedAdministrators: [ObvEncoded]) {
                    self.previousBlockHash = previousBlockHash
                    self.encodedAdministrators = encodedAdministrators
                }
                
                public init?(_ encodedInnerData: ObvEncoded) {
                    guard let elements = [ObvEncoded](encodedInnerData, expectedCount: 2) else { assertionFailure(); return nil }
                    let encodedHash = elements[0]
                    let encodedListOfAdministrators = elements[1]
                    guard let previousBlockHash = Data(encodedHash),
                          let encodedAdministrators = [ObvEncoded](encodedListOfAdministrators),
                          !encodedAdministrators.isEmpty
                    else {
                        assertionFailure()
                        return nil
                    }
                    self.init(previousBlockHash: previousBlockHash, encodedAdministrators: encodedAdministrators)
                }
                
                public func obvEncode() -> ObvEncoded {
                    [previousBlockHash.obvEncode(), encodedAdministrators.obvEncode()].obvEncode()
                }
                
                /// Creates an InnerData instance appropriate for the first `Block` of a `GroupAdministratorsChain`.
                fileprivate init(ownedIdentity: ObvCryptoIdentity, otherAdministrators: [ObvCryptoIdentity], prng: PRNG) {
                    self.previousBlockHash = prng.genBytes(count: ObvCryptoSuite.sharedInstance.hashFunctionSha256().outputLength)
                    let allAdministrators = [ownedIdentity] + otherAdministrators
                    self.encodedAdministrators = allAdministrators.map({ $0.obvEncode() })
                }
                
                /// Creates an InnerData instance appropriate for subsequent `Block` of an `GroupAdministratorsChain`.
                fileprivate init(ownedIdentity: ObvCryptoIdentity, otherAdministrators: [ObvCryptoIdentity], previousBlock: Block) {
                    self.previousBlockHash = previousBlock.computeSha256()
                    let allAdministrators = [ownedIdentity] + otherAdministrators
                    self.encodedAdministrators = allAdministrators.map({ $0.obvEncode() })
                }

            }
            
            let encodedInnerData: ObvEncoded
            let innerData: InnerData
            let signatureOnInnerData: Data

            var allAdministratorIdentities: Set<ObvCryptoIdentity> {
                let encodedAdministrators = innerData.encodedAdministrators
                let administrators = encodedAdministrators.compactMap({ ObvCryptoIdentity($0) })
                return Set(administrators)
            }
            
            public init?(_ encodedBlock: ObvEncoded) {
                guard let elements = [ObvEncoded](encodedBlock, expectedCount: 2) else { assertionFailure(); return nil }
                let encodedInnerData = elements[0]
                let encodedSignature = elements[1]
                guard let innerData = InnerData(encodedInnerData),
                      let signatureOnInnerData = Data(encodedSignature)
                 else {
                    assertionFailure()
                    return nil
                }
                self.encodedInnerData = encodedInnerData
                self.innerData = innerData
                self.signatureOnInnerData = signatureOnInnerData
            }

            public func obvEncode() -> ObvEncoded {
                [encodedInnerData, signatureOnInnerData.obvEncode()].obvEncode()
            }
            
            
            /// Creates a block instance appropriate as the first block of a `GroupAdministratorsChain`.
            fileprivate init(ownedIdentity: ObvCryptoIdentity, otherAdministrators: [ObvCryptoIdentity], using prng: PRNGService, solveChallengeDelegate: ObvSolveChallengeDelegate, within obvContext: ObvContext) throws {
                let innerData = InnerData(ownedIdentity: ownedIdentity, otherAdministrators: otherAdministrators, prng: prng)
                let encodedInnerData = innerData.obvEncode()
                let signature = try solveChallengeDelegate.solveChallenge(.groupV2AdministratorsChain(rawInnerData: encodedInnerData.rawData), for: ownedIdentity, using: prng, within: obvContext)
                self.encodedInnerData = encodedInnerData
                self.innerData = innerData
                self.signatureOnInnerData = signature
            }

            
            /// Creates a block instance appropriate for the subsequent block of a `GroupAdministratorsChain`.
            fileprivate init(ownedIdentity: ObvCryptoIdentity, otherAdministrators: [ObvCryptoIdentity], previousBlock: Block, using prng: PRNGService, solveChallengeDelegate: ObvSolveChallengeDelegate, within obvContext: ObvContext) throws {
                let innerData = InnerData(ownedIdentity: ownedIdentity, otherAdministrators: otherAdministrators, previousBlock: previousBlock)
                let encodedInnerData = innerData.obvEncode()
                let signature = try solveChallengeDelegate.solveChallenge(.groupV2AdministratorsChain(rawInnerData: encodedInnerData.rawData), for: ownedIdentity, using: prng, within: obvContext)
                self.encodedInnerData = encodedInnerData
                self.innerData = innerData
                self.signatureOnInnerData = signature
            }

            
            func computeSha256() -> Data {
                let dataToHash = self.obvEncode().rawData
                let sha256 = ObvCryptoSuite.sharedInstance.hashFunctionSha256()
                return sha256.hash(dataToHash)
            }
            
            
            func signatureOnInnerDataIsValid(administratorsOfPreviousBlock administrators: [ObvCryptoIdentity]) -> Bool {
                for administrator in administrators {
                    if signatureOnInnerDataWasComputedBy(administrator) {
                        return true
                    }
                }
                return false
            }
            
            
            func signatureOnInnerDataWasComputedBy(_ cryptoIdentity: ObvCryptoIdentity) -> Bool {
                return ObvSolveChallengeStruct.checkResponse(signatureOnInnerData, to: .groupV2AdministratorsChain(rawInnerData: encodedInnerData.rawData), from: cryptoIdentity)
            }
            
        }

        public let groupUID: UID
        let blocks: [Block]
        public let integrityChecked: Bool

        // Initializers
        
        private init(groupUID: UID, blocks: [Block], integrityChecked: Bool) {
            self.groupUID = groupUID
            self.blocks = blocks
            self.integrityChecked = integrityChecked
        }
        
        
        public init?(_ encodedAdministratorsChain: ObvEncoded) {
            guard let encodedBlocks = [ObvEncoded](encodedAdministratorsChain) else { assertionFailure(); return nil }
            guard !encodedBlocks.isEmpty else { assertionFailure(); return nil }
            let blocks = encodedBlocks.compactMap({ Block($0) })
            guard blocks.count == encodedBlocks.count else { assertionFailure(); return nil }
            guard let sha256OfFirstBlock = blocks.first?.computeSha256(),
                  let groupUID = UID(uid: sha256OfFirstBlock)
            else {
                return nil
            }
            self.init(groupUID: groupUID, blocks: blocks, integrityChecked: false)
        }
        
        /// Decrypts and checks the integrity of the encrypted administrator chain.
        ///
        /// This method first decrypts the encrypted administrator chain using the blob main seed.
        /// It then checks the integrity.
        /// Only in case of success does this method return an administrator chain.
        public static func decryptAndCheckIntegrity(encryptedAdministratorChain: EncryptedData, blobMainSeed: Seed, expectedGroupUID: UID) throws -> AdministratorsChain {
            
            let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption()
            let decryptionKey = authEnc.generateKey(with: blobMainSeed)
            let rawEncodedAdministratorChain = try authEnc.decrypt(encryptedAdministratorChain, with: decryptionKey)
            guard let encodedAdministratorChain = ObvEncoded(withRawData: rawEncodedAdministratorChain) else { throw Self.makeError(message: "Could not parse encoded administrator chain") }
            guard let administratorChain = GroupV2.AdministratorsChain(encodedAdministratorChain) else { throw Self.makeError(message: "Could not decode administrator chain") }

            let administratorChainWithCheckedIntegrity = try administratorChain.withCheckedIntegrity(expectedGroupUID: expectedGroupUID)
            
            return administratorChainWithCheckedIntegrity
            
        }
        
        
        public func encrypt(blobMainSeed: Seed, prng: PRNGService) throws -> EncryptedData {
            let plaintext = self.obvEncode().rawData
            let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption()
            let encryptionKey = authEnc.generateKey(with: blobMainSeed)
            let encryptedAdministratorChain = try authEnc.encrypt(plaintext, with: encryptionKey, and: prng)
            return encryptedAdministratorChain
        }
        
        
        public static func startNewChain(ownedIdentity: ObvCryptoIdentity, otherAdministrators: [ObvCryptoIdentity], using prng: PRNGService, solveChallengeDelegate: ObvSolveChallengeDelegate, within obvContext: ObvContext) throws -> AdministratorsChain {
            let firstBlock = try Block(ownedIdentity: ownedIdentity, otherAdministrators: otherAdministrators, using: prng, solveChallengeDelegate: solveChallengeDelegate, within: obvContext)
            let sha256OfFirstBlock = firstBlock.computeSha256()
            guard let groupUID = UID(uid: sha256OfFirstBlock) else { throw Self.makeError(message: "Could not compute Group UID from Sha256 of first block") }
            return try AdministratorsChain(groupUID: groupUID, blocks: [firstBlock], integrityChecked: false).withCheckedIntegrity(expectedGroupUID: groupUID)
        }
        
        
        func addBlock(ownedIdentity: ObvCryptoIdentity, otherAdministrators: [ObvCryptoIdentity], using prng: PRNGService, solveChallengeDelegate: ObvSolveChallengeDelegate, within obvContext: ObvContext) throws -> AdministratorsChain {
            guard let currentLastBlock = self.blocks.last else {
                assertionFailure()
                throw Self.makeError(message: "The administrator chain is empty")
            }
            // Check that currently are an administrator
            guard currentLastBlock.allAdministratorIdentities.contains(ownedIdentity) else {
                assertionFailure()
                throw Self.makeError(message: "The owned identity cannot update the administrator chain since she is not an administrator")
            }
            let newBlock = try Block(ownedIdentity: ownedIdentity, otherAdministrators: otherAdministrators, previousBlock: currentLastBlock, using: prng, solveChallengeDelegate: solveChallengeDelegate, within: obvContext)
            
            return Self.init(groupUID: self.groupUID,
                             blocks: self.blocks + [newBlock],
                             integrityChecked: self.integrityChecked)
        }
        
        
        public func obvEncode() -> ObvEncoded {
            blocks.map({ $0.obvEncode() }).obvEncode()
        }
        
        
        public var allCurrentAdministratorIdentities: Set<ObvCryptoIdentity> {
            blocks.last?.allAdministratorIdentities ?? Set<ObvCryptoIdentity>()
        }
        
        public var numberOfBlocks: Int {
            blocks.count
        }
        
        public var anAdministratorWasDemotedInTheLastUpdate: Bool {
            let lastBlocks = blocks.suffix(2) as [Block]
            guard lastBlocks.count == 2 else { return false }
            return !lastBlocks[0].allAdministratorIdentities.subtracting(lastBlocks[1].allAdministratorIdentities).isEmpty
        }

        // Checking the chain integrity
        
        /// Checks the integrity of this `GroupAdministratorsChain` and returns an identical `GroupAdministratorsChain` such that `integrityChecked` is `true`.
        /// This method checks that the `administrator` is part of the administrors advertized in the last block.
        /// The `expectedGroupUID` is typically the UID part of the group identifier of the group we downloaded from the server.
        /// We check that this UID is equal to the groupUID included in this chain to prevent a simple replacement of this chain by another valid one that would correspond to another group.
        fileprivate func withCheckedIntegrity(expectedGroupUID: UID) throws -> AdministratorsChain {
            
            guard !self.integrityChecked else { return self }
            
            // Check the group UID
            
            guard let sha256OfFirstBlock = blocks.first?.computeSha256(), let computedGroupUID = UID(uid: sha256OfFirstBlock) else {
                throw Self.makeError(message: "Failed to compute the Group UID")
            }
            guard self.groupUID == computedGroupUID else {
                throw Self.makeError(message: "The GroupUID verification failed")
            }
            guard self.groupUID == expectedGroupUID else {
                throw Self.makeError(message: "The GroupUID of the chain is not the one we expect")
            }

            // Check the chain of digests
            
            var computedDigests = blocks.map({ $0.computeSha256() })
            var receivedDigests = blocks.map({ $0.innerData.previousBlockHash })
            computedDigests.removeLast()
            receivedDigests.removeFirst()
            guard computedDigests == receivedDigests else {
                throw Self.makeError(message: "Chain integrity failed")
            }
            
            // Check signatures (the first block is self signed)
            
            guard let encodedAdministratorsOfFirstBlock = blocks.first?.innerData.encodedAdministrators else { throw Self.makeError(message: "Could not recover administrators of the first block") }
            var administratorsOfPreviousBlock = encodedAdministratorsOfFirstBlock.compactMap({ ObvCryptoIdentity($0) })
            for block in blocks {
                guard block.signatureOnInnerDataIsValid(administratorsOfPreviousBlock: administratorsOfPreviousBlock) else {
                    throw Self.makeError(message: "Invalid block signature")
                }
                administratorsOfPreviousBlock = block.innerData.encodedAdministrators.compactMap({ ObvCryptoIdentity($0) })
            }
            
            // If we reach this point, the integrity of the chain has been checked
            
            return AdministratorsChain(groupUID: self.groupUID, blocks: self.blocks, integrityChecked: true)
            
        }
        
        
        fileprivate func withForcedCheckedIntegrity() -> AdministratorsChain {
            return AdministratorsChain(groupUID: self.groupUID, blocks: self.blocks, integrityChecked: true)
        }
            
        
        public func isPrefixOfOtherAdministratorsChain(_ other: AdministratorsChain) -> Bool {
            guard self.groupUID == other.groupUID else { return false }
            guard self.blocks.count <= other.blocks.count else { return false }
            for pairOfBlocks in zip(self.blocks, other.blocks[0..<self.blocks.count]) {
                guard pairOfBlocks.0.encodedInnerData == pairOfBlocks.1.encodedInnerData else { return false }
            }
            return true
        }
        
    }

    
    // MARK: - Identifier

    public struct Identifier: ObvCodable, ObvErrorMaker, Equatable {
        
        public static let errorDomain = "GroupV2.Identifier"

        public enum Category: Int {
            case server = 0
            case keycloak = 1
            
            var toObvGroupV2IdentifierCategory: ObvGroupV2.Identifier.Category {
                switch self {
                case .server: return .server
                case .keycloak: return .keycloak
                }
            }
            
        }
        
        public let groupUID: UID
        public let serverURL: URL
        public let category: Category

        
        public init(groupUID: UID, serverURL: URL, category: Category) {
            self.groupUID = groupUID
            self.serverURL = serverURL
            self.category = category
        }
        
        public init(obvGroupV2Identifier: ObvGroupV2.Identifier) {
            self.groupUID = obvGroupV2Identifier.groupUID
            self.serverURL = obvGroupV2Identifier.serverURL
            switch obvGroupV2Identifier.category {
            case .server:
                self.category = .server
            case .keycloak:
                self.category = .keycloak
            }
        }
        
        public var toObvGroupV2Identifier: ObvGroupV2.Identifier {
            return ObvGroupV2.Identifier(groupUID: groupUID,
                                         serverURL: serverURL,
                                         category: category.toObvGroupV2IdentifierCategory)
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
        
        // Returning a protocol instance UID
        
        public func computeProtocolInstanceUid() throws -> UID {
            let encodedSelf = self.obvEncode()
            guard let seed = Seed(with: encodedSelf.rawData) else { throw Self.makeError(message: "Could not compute seed from encoded self") }
            let prngClass = ObvCryptoSuite.sharedInstance.concretePRNG()
            let prng = prngClass.init(with: seed)
            return UID.gen(with: prng)
        }
        
        // Equatable
        
        public static func == (lhs: Identifier, rhs: Identifier) -> Bool {
            lhs.groupUID == rhs.groupUID && lhs.serverURL == rhs.serverURL && lhs.category == rhs.category
        }

    }

    
    // MARK: - Permission
    
    public enum Permission: String, CaseIterable {
        case groupAdmin = "ga"
        case remoteDeleteAnything = "rd" // Allows to remote delete any message or discussion
        case editOrRemoteDeleteOwnMessages = "eo" // Allows to edit and remote delete own messages
        case changeSettings = "cs"
        case sendMessage = "sm"
        
        public var toGroupV2Permission: ObvGroupV2.Permission {
            switch self {
            case .groupAdmin: return .groupAdmin
            case .remoteDeleteAnything: return .remoteDeleteAnything
            case .editOrRemoteDeleteOwnMessages: return .editOrRemoteDeleteOwnMessages
            case .changeSettings: return .changeSettings
            case .sendMessage: return .sendMessage
            }
        }
        
        public init(obvGroupV2Permission: ObvGroupV2.Permission) {
            switch obvGroupV2Permission {
            case .groupAdmin:
                self = .groupAdmin
            case .remoteDeleteAnything:
                self = .remoteDeleteAnything
            case .editOrRemoteDeleteOwnMessages:
                self = .editOrRemoteDeleteOwnMessages
            case .changeSettings:
                self = .changeSettings
            case .sendMessage:
                self = .sendMessage
            }
        }
        
    }

    
    public struct ServerPhotoInfo: Equatable, ObvCodable {
        
        public let key: AuthenticatedEncryptionKey
        public let label: UID
        public let identity: ObvCryptoIdentity // The identity of the admin who uploaded the photo
        
        public init(key: AuthenticatedEncryptionKey, label: UID, identity: ObvCryptoIdentity) {
            self.key = key
            self.label = label
            self.identity = identity
        }
        
        public static func == (lhs: ServerPhotoInfo, rhs: ServerPhotoInfo) -> Bool {
            guard lhs.label == rhs.label, lhs.identity == rhs.identity else { return false }
            do {
                guard try AuthenticatedEncryptionKeyComparator.areEqual(lhs.key, rhs.key) else { return false }
            } catch {
                assertionFailure()
                return false
            }
            return true
        }
        

        public static func generate(for identity: ObvCryptoIdentity, with prng: PRNGService) -> ServerPhotoInfo {
            let label = UID.gen(with: prng)
            let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption()
            let key = authEnc.generateKey(with: prng)
            return ServerPhotoInfo(key: key, label: label, identity: identity)
        }
        
        
        public func obvEncode() -> ObvEncoded {
            [identity.obvEncode(), label.obvEncode(), key.obvEncode()].obvEncode()
        }
        
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let encodedElements = [ObvEncoded](obvEncoded, expectedCount: 3) else { assertionFailure(); return nil }
            do {
                self.identity = try encodedElements[0].obvDecode()
                self.label = try encodedElements[1].obvDecode()
                self.key = try AuthenticatedEncryptionKeyDecoder.decode(encodedElements[2])
            } catch {
                assertionFailure()
                return nil
            }
        }
        
    }
    
    
    // MARK: - IdentityAndPermissionsAndDetails

    public struct IdentityAndPermissionsAndDetails: ObvCodable, Hashable {
            
        public let identity: ObvCryptoIdentity
        public let rawPermissions: Set<String>
        public let serializedIdentityCoreDetails: Data
        public let groupInvitationNonce: Data
        
        public init(identity: ObvCryptoIdentity, rawPermissions: Set<String>, serializedIdentityCoreDetails: Data, groupInvitationNonce: Data) {
            self.identity = identity
            self.rawPermissions = rawPermissions
            self.serializedIdentityCoreDetails = serializedIdentityCoreDetails
            self.groupInvitationNonce = groupInvitationNonce
        }
        
        public var hasGroupAdminPermission: Bool {
            rawPermissions.contains(Permission.groupAdmin.rawValue)
        }
        
        // ObvCodable
        
        public func obvEncode() -> ObvEncoded {
            let encodedIdentity = identity.obvEncode()
            let encodedPermissions = rawPermissions.map({ $0.obvEncode() }).obvEncode()
            let encodedSerializedCoreDetails = serializedIdentityCoreDetails.obvEncode()
            let encodedGroupInvitationNonce = groupInvitationNonce.obvEncode()
            return [encodedIdentity, encodedPermissions, encodedSerializedCoreDetails, encodedGroupInvitationNonce].obvEncode()
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 4) else { assertionFailure(); return nil }
            let encodedIdentity = encodedValues[0]
            let encodedPermissions = encodedValues[1]
            let encodedSerializedCoreDetails = encodedValues[2]
            let encodedGroupInvitationNonce = encodedValues[3]
            guard let identity = ObvCryptoIdentity(encodedIdentity) else { assertionFailure(); return nil }
            guard let listOfEncodedPermissions = [ObvEncoded](encodedPermissions) else { assertionFailure(); return nil }
            let rawPermissions: Set<String> = Set(listOfEncodedPermissions.compactMap({ String($0) }))
            assert(rawPermissions.count == listOfEncodedPermissions.count)
            guard let serializedIdentityCoreDetails: Data = try? encodedSerializedCoreDetails.obvDecode(),
                  let groupInvitationNonce: Data = try? encodedGroupInvitationNonce.obvDecode()
            else {
                return nil
            }
            self.init(identity: identity, rawPermissions: rawPermissions, serializedIdentityCoreDetails: serializedIdentityCoreDetails, groupInvitationNonce: groupInvitationNonce)
        }

        public func toObvGroupV2IdentityAndPermissionsAndDetails(isPending: Bool) -> ObvGroupV2.IdentityAndPermissionsAndDetails {
            let permissions = rawPermissions.compactMap({ Permission(rawValue: $0)?.toGroupV2Permission })
            return ObvGroupV2.IdentityAndPermissionsAndDetails(identity: ObvCryptoId(cryptoIdentity: identity),
                                                               permissions: Set(permissions),
                                                               serializedIdentityCoreDetails: serializedIdentityCoreDetails,
                                                               isPending: isPending)
        }

        // Hashable
            
        /// We only match the Identity to avoid duplicate group members when building sets of IdentityAndGroupPermissions
        public static func == (lhs: IdentityAndPermissionsAndDetails, rhs: IdentityAndPermissionsAndDetails) -> Bool {
            return lhs.identity == rhs.identity
        }
        
        // We only consider the Identity to avoid duplicate group members when building sets of IdentityAndGroupPermissions
        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.identity)
        }

    }

    
    // MARK: - IdentityAndPermissions

    /// Used when creating a GroupV2 for the local protocol message allowing to launch the group creation protocol.
    public struct IdentityAndPermissions: ObvCodable, Hashable {
            
        public let identity: ObvCryptoIdentity
        public let rawPermissions: Set<String>
        
        public init(identity: ObvCryptoIdentity, rawPermissions: Set<String>) {
            self.identity = identity
            self.rawPermissions = rawPermissions
        }
        
        public init(from obvGroupV2IdentityAndPermissions: ObvGroupV2.IdentityAndPermissions) {
            let identity = obvGroupV2IdentityAndPermissions.identity.cryptoIdentity
            var permissions = Set<GroupV2.Permission>()
            for permission in obvGroupV2IdentityAndPermissions.permissions {
                switch permission {
                case .groupAdmin:
                    permissions.insert(.groupAdmin)
                case .remoteDeleteAnything:
                    permissions.insert(.remoteDeleteAnything)
                case .editOrRemoteDeleteOwnMessages:
                    permissions.insert(.editOrRemoteDeleteOwnMessages)
                case .changeSettings:
                    permissions.insert(.changeSettings)
                case .sendMessage:
                    permissions.insert(.sendMessage)
                }
            }
            self.init(identity: identity, rawPermissions: Set(permissions.map({ $0.rawValue })))
        }
        
        public var hasGroupAdminPermission: Bool {
            rawPermissions.contains(Permission.groupAdmin.rawValue)
        }
        
        // ObvCodable
        
        public func obvEncode() -> ObvEncoded {
            let encodedIdentity = identity.obvEncode()
            let encodedPermissions = rawPermissions.map({ $0.obvEncode() }).obvEncode()
            return [encodedIdentity, encodedPermissions].obvEncode()
        }
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); return nil }
            let encodedIdentity = encodedValues[0]
            let encodedPermissions = encodedValues[1]
            guard let identity = ObvCryptoIdentity(encodedIdentity) else { assertionFailure(); return nil }
            guard let listOfEncodedPermissions = [ObvEncoded](encodedPermissions) else { assertionFailure(); return nil }
            let rawPermissions: Set<String> = Set(listOfEncodedPermissions.compactMap({ String($0) }))
            assert(rawPermissions.count == listOfEncodedPermissions.count)
            self.init(identity: identity, rawPermissions: rawPermissions)
        }


        // Hashable
            
        /// We only match the Identity to avoid duplicate group members when building sets of IdentityAndGroupPermissions
        public static func == (lhs: IdentityAndPermissions, rhs: IdentityAndPermissions) -> Bool {
            return lhs.identity == rhs.identity
        }
        
        // We only consider the Identity to avoid duplicate group members when building sets of IdentityAndGroupPermissions
        public func hash(into hasher: inout Hasher) {
            hasher.combine(self.identity)
        }

    }

    
    // MARK: - ServerBlob
        
    public struct ServerBlob: ObvFailableCodable, ObvErrorMaker {
        
        public let administratorsChain: AdministratorsChain
        public let groupMembers: Set<IdentityAndPermissionsAndDetails>
        public let groupVersion: Int
        public let serializedGroupCoreDetails: Data
        public let serverPhotoInfo: ServerPhotoInfo? // Nil if the group has no photo
        
        public static let errorDomain = "GroupV2.ServerBlob"
        
        public init(administratorsChain: AdministratorsChain, groupMembers: Set<IdentityAndPermissionsAndDetails>, groupVersion: Int, serializedGroupCoreDetails: Data, serverPhotoInfo: ServerPhotoInfo?) {
            self.administratorsChain = administratorsChain
            self.groupMembers = groupMembers
            self.groupVersion = groupVersion
            self.serializedGroupCoreDetails = serializedGroupCoreDetails
            self.serverPhotoInfo = serverPhotoInfo
        }
        
        
        private enum ObvCodingKeys: String, CaseIterable, CodingKey {
            
            case administratorsChain = "ac"
            case groupMembers = "mem"
            case groupVersion = "v"
            case serializedGroupCoreDetails = "det"
            case serverPhotoInfo = "ph"
            
            var key: Data { rawValue.data(using: .utf8)! }
            
        }
        
        
        public func obvEncode() throws -> ObvEncoded {
            var obvDict = [Data: ObvEncoded]()
            for codingKey in ObvCodingKeys.allCases {
                switch codingKey {
                case .administratorsChain:
                    try obvDict.obvEncode(administratorsChain, forKey: codingKey)
                case .groupMembers:
                    try obvDict.obvEncode(groupMembers, forKey: codingKey)
                case .groupVersion:
                    try obvDict.obvEncode(groupVersion, forKey: codingKey)
                case .serializedGroupCoreDetails:
                    try obvDict.obvEncode(serializedGroupCoreDetails, forKey: codingKey)
                case .serverPhotoInfo:
                    try obvDict.obvEncodeIfPresent(serverPhotoInfo, forKey: codingKey)
                }
            }
            return obvDict.obvEncode()
        }
        
        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
            do {
                let administratorsChain = try obvDict.obvDecode(AdministratorsChain.self, forKey: ObvCodingKeys.administratorsChain)
                let groupMembers = try obvDict.obvDecode(Set<IdentityAndPermissionsAndDetails>.self, forKey: ObvCodingKeys.groupMembers)
                let groupVersion = try obvDict.obvDecode(Int.self, forKey: ObvCodingKeys.groupVersion)
                let serializedGroupCoreDetails = try obvDict.obvDecode(Data.self, forKey: ObvCodingKeys.serializedGroupCoreDetails)
                let serverPhotoInfo = try obvDict.obvDecodeIfPresent(ServerPhotoInfo.self, forKey: ObvCodingKeys.serverPhotoInfo)
                self.init(administratorsChain: administratorsChain,
                          groupMembers: groupMembers,
                          groupVersion: groupVersion,
                          serializedGroupCoreDetails: serializedGroupCoreDetails,
                          serverPhotoInfo: serverPhotoInfo)
            } catch {
                assertionFailure(error.localizedDescription)
                return nil
            }
        }
        
        
        public func signThenEncrypt(ownedIdentity: ObvCryptoIdentity, blobMainSeed: Seed, blobVersionSeed: Seed, solveChallengeDelegate: ObvSolveChallengeDelegate, with prng: PRNGService, within obvContext: ObvContext) throws -> EncryptedData {
            
            let encodedBlob = try self.obvEncode()
            
            let signature = try solveChallengeDelegate.solveChallenge(.groupBlob(rawEncodedBlob: encodedBlob.rawData),
                                                                      for: ownedIdentity,
                                                                      using: prng,
                                                                      within: obvContext)
            
            let encodedSignedBlob = [encodedBlob, ownedIdentity.obvEncode(), signature.obvEncode()].obvEncode()
            
            // Pad the signed blob so as to obtain as plaintext which size is a multiple of 4096
            
            let unpaddedLength = encodedSignedBlob.rawData.count
            let paddedLength: Int = (1 + ((unpaddedLength-1)>>12)) << 12 // We pad to the smallest multiple of 4096 larger than the actual length
            let paddedBlobPlaintext = encodedSignedBlob.rawData + Data(count: paddedLength-unpaddedLength)
            
            // Encrypt the padded blob plaintext
            
            guard let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption(forSuiteVersion: 0) else { assertionFailure(); throw Self.makeError(message: "Internal error") }
            let sharedBlobSecretKey = authEnc.generateKey(with: Seed(seeds: [blobMainSeed, blobVersionSeed]))

            let encryptedServerBlob = AuthenticatedEncryption.encrypt(paddedBlobPlaintext, with: sharedBlobSecretKey, and: prng)
            
            return encryptedServerBlob
            
        }
        
        public init(encryptedServerBlob: EncryptedData, blobMainSeed: Seed, blobVersionSeed: Seed, expectedGroupIdentifier: Identifier, solveChallengeDelegate: ObvSolveChallengeDelegate) throws {
            
            guard let authEnc = ObvCryptoSuite.sharedInstance.authenticatedEncryption(forSuiteVersion: 0) else { assertionFailure(); throw Self.makeError(message: "Internal error") }
            let sharedBlobSecretKey = authEnc.generateKey(with: Seed(seeds: [blobMainSeed, blobVersionSeed]))

            let paddedBlobPlaintext = try AuthenticatedEncryption.decrypt(encryptedServerBlob, with: sharedBlobSecretKey)

            guard let encodedSignedBlob = ObvEncoded(withPaddedRawData: paddedBlobPlaintext) else {
                // We could not get an unpadded blob although we could decrypt it. Unlikely...
                assertionFailure()
                throw Self.makeError(message: "Could not parse decrypted blob (1)")
            }
            
            guard let encodedBlobElements = [ObvEncoded](encodedSignedBlob, expectedCount: 3) else {
                assertionFailure()
                throw Self.makeError(message: "Could not parse decrypted blob (2)")
            }

            let encodedBlob = encodedBlobElements[0]
            let encodedSignerIdentity = encodedBlobElements[1]
            let encodedSignature = encodedBlobElements[2]
            
            guard let signer = ObvCryptoIdentity(encodedSignerIdentity) else {
                throw Self.makeError(message: "Could not get signer")
            }

            // Check the signature on the encoded blob
            
            guard let signature = Data(encodedSignature) else {
                assertionFailure()
                throw Self.makeError(message: "Could not parse blob signature")
            }
            
            guard ObvSolveChallengeStruct.checkResponse(signature, to: .groupBlob(rawEncodedBlob: encodedBlob.rawData), from: signer) else {
                assertionFailure()
                throw Self.makeError(message: "The blob signature is invalid")
            }
            
            guard let blob = ServerBlob(encodedBlob) else {
                assertionFailure()
                throw Self.makeError(message: "Could not parse decrypted blob (3)")
            }
            
            let checkedAdministratorsChain = try blob.administratorsChain.withCheckedIntegrity(expectedGroupUID: expectedGroupIdentifier.groupUID)
            
            guard blob.administratorsChain.allCurrentAdministratorIdentities.contains(signer) else {
                throw Self.makeError(message: "The signer is not part of the current administators")
            }

            // Check that the administrators included in the last block of the (integrity checked) chain correspond of the administrators among the groupMembers
            
            do {
                guard let allAdministratorIdentities = checkedAdministratorsChain.blocks.last?.allAdministratorIdentities else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not determine the administrators identities")
                }
                guard !allAdministratorIdentities.isEmpty else {
                    assertionFailure()
                    throw Self.makeError(message: "The administrator identities is empty, this is unexpected")
                }
                let administratorsAmongMembers = blob.groupMembers.filter({ $0.hasGroupAdminPermission })
                for admin in administratorsAmongMembers {
                    guard allAdministratorIdentities.contains(admin.identity) else {
                        assertionFailure()
                        throw Self.makeError(message: "One of the admin group members is not part of the integrity checked administrator chain")
                    }
                }
            }
            
            // Return the blob
            
            self.init(administratorsChain: checkedAdministratorsChain,
                      groupMembers: blob.groupMembers,
                      groupVersion: blob.groupVersion,
                      serializedGroupCoreDetails: blob.serializedGroupCoreDetails,
                      serverPhotoInfo: blob.serverPhotoInfo)
            
        }
        
        
        /// This method consolidates the blob by removing all the leavers (i.e., members who left the group by signing and uploading their `groupInvitationNonce`).
        public func consolidateWithLogEntries(groupIdentifier: Identifier, _ logEntries: Set<Data>) -> ServerBlob {
            
            var leavers = Set<ObvCryptoIdentity>()
            for logEntry in logEntries {
                for groupMember in self.groupMembers {
                    if ObvSolveChallengeStruct.checkResponse(logEntry, to: .groupLeaveNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: groupMember.groupInvitationNonce), from: groupMember.identity) {
                        leavers.insert(groupMember.identity)
                    }
                }
            }
            
            let groupMembersWithoutLeavers = self.groupMembers.filter({ !leavers.contains($0.identity) })

            let blobWithoutLeavers = ServerBlob(administratorsChain: self.administratorsChain,
                                                groupMembers: groupMembersWithoutLeavers,
                                                groupVersion: self.groupVersion,
                                                serializedGroupCoreDetails: self.serializedGroupCoreDetails,
                                                serverPhotoInfo: self.serverPhotoInfo)

            return blobWithoutLeavers
            
        }
        
        
        /// Returns an updated `ServerBlob` given the changeset.
        public func consolidateWithChangeset(_ changeset: ObvGroupV2.Changeset, ownedIdentity: ObvCryptoIdentity, identityDelegate: ObvIdentityDelegate, prng: PRNGService, solveChallengeDelegate: ObvSolveChallengeDelegate, within obvContext: ObvContext) throws -> ServerBlob {
            
            var updatedSerializedGroupCoreDetails = self.serializedGroupCoreDetails
            var updatedServerPhotoInfo = self.serverPhotoInfo
            
            // We update the core details of all group members, even those that are not concerned by the changeset.
            
            var updatedGroupMembers = Set<GroupV2.IdentityAndPermissionsAndDetails>()
            for member in self.groupMembers {
                do {
                    if try identityDelegate.isIdentity(member.identity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) {
                        let (publishedIdentityDetails, trustedIdentityDetails) = try identityDelegate.getIdentityDetailsOfContactIdentity(member.identity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                        let updatedSerializedIdentityCoreDetails = try (publishedIdentityDetails ?? trustedIdentityDetails).coreDetails.jsonEncode()
                        let memberWithUpdatedCoreDetails = GroupV2.IdentityAndPermissionsAndDetails(identity: member.identity,
                                                                                                    rawPermissions: member.rawPermissions,
                                                                                                    serializedIdentityCoreDetails: updatedSerializedIdentityCoreDetails,
                                                                                                    groupInvitationNonce: member.groupInvitationNonce)
                        updatedGroupMembers.insert(memberWithUpdatedCoreDetails)
                    } else {
                        updatedGroupMembers.insert(member)
                    }
                } catch {
                    assertionFailure() // In production, continue anyway
                    updatedGroupMembers.insert(member)
                }
            }
            
            for change in changeset.orderedChanges {
                switch change {
                    
                case .memberRemoved(let contactCryptoId):
                    updatedGroupMembers = updatedGroupMembers.filter({ $0.identity != contactCryptoId.cryptoIdentity })

                case .memberAdded(let contactCryptoId, let permissions):
                    // If the member is already part of the group members, ignore this change
                    guard !updatedGroupMembers.map({ $0.identity }).contains(contactCryptoId.cryptoIdentity) else {
                        continue
                    }
                    guard try identityDelegate.isIdentity(contactCryptoId.cryptoIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) else {
                        assertionFailure()
                        throw Self.makeError(message: "One of the added members is not a contact of the owned identity")
                    }
                    let details = try identityDelegate.getIdentityDetailsOfContactIdentity(contactCryptoId.cryptoIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                    let detailsToUse = details.publishedIdentityDetails ?? details.trustedIdentityDetails
                    let serializedIdentityCoreDetails = try detailsToUse.coreDetails.jsonEncode()
                    // If the member was already part of the group, we do not change her invitation nonce. Otherwise, we create one.
                    let groupInvitationNonce: Data
                    if let member = updatedGroupMembers.first(where: { $0.identity == contactCryptoId.cryptoIdentity }) {
                        groupInvitationNonce = member.groupInvitationNonce
                    } else {
                        groupInvitationNonce = prng.genBytes(count: ObvConstants.groupInvitationNonceLength)
                    }
                    let rawPermissions = Set(permissions.map({ Permission(obvGroupV2Permission: $0) }).map({ $0.rawValue }))
                    let identityAndPermissionsAndDetails = IdentityAndPermissionsAndDetails(identity: contactCryptoId.cryptoIdentity,
                                                                                            rawPermissions: rawPermissions,
                                                                                            serializedIdentityCoreDetails: serializedIdentityCoreDetails,
                                                                                            groupInvitationNonce: groupInvitationNonce)
                    updatedGroupMembers.remove(identityAndPermissionsAndDetails)
                    updatedGroupMembers.insert(identityAndPermissionsAndDetails)
                    
                case .memberChanged(let contactCryptoId, let permissions):
                    guard let member = updatedGroupMembers.first(where: { $0.identity == contactCryptoId.cryptoIdentity }) else { continue }
                    let updatedRawPermissions = Set(permissions.map({ Permission(obvGroupV2Permission: $0) }).map({ $0.rawValue }))
                    let updatedMember = IdentityAndPermissionsAndDetails(identity: member.identity,
                                                                         rawPermissions: updatedRawPermissions,
                                                                         serializedIdentityCoreDetails: member.serializedIdentityCoreDetails,
                                                                         groupInvitationNonce: member.groupInvitationNonce)
                    updatedGroupMembers.remove(updatedMember)
                    updatedGroupMembers.insert(updatedMember)
                    
                case .ownPermissionsChanged(permissions: let permissions):
                    guard let member = updatedGroupMembers.first(where: { $0.identity == ownedIdentity }) else { assertionFailure(); continue }
                    let updatedRawPermissions = Set(permissions.map({ Permission(obvGroupV2Permission: $0) }).map({ $0.rawValue }))
                    let updatedMember = IdentityAndPermissionsAndDetails(identity: member.identity,
                                                                         rawPermissions: updatedRawPermissions,
                                                                         serializedIdentityCoreDetails: member.serializedIdentityCoreDetails,
                                                                         groupInvitationNonce: member.groupInvitationNonce)
                    updatedGroupMembers.remove(updatedMember)
                    updatedGroupMembers.insert(updatedMember)

                case .groupDetails(serializedGroupCoreDetails: let serializedGroupCoreDetails):
                    updatedSerializedGroupCoreDetails = serializedGroupCoreDetails
                    
                case .groupPhoto(photoURL: let photoURL):
                    if photoURL == nil {
                        updatedServerPhotoInfo = nil
                    } else {
                        updatedServerPhotoInfo = GroupV2.ServerPhotoInfo.generate(for: ownedIdentity, with: prng)
                    }
                    
                }
            }
            
            // Check whether the administrator chains needs to be updated.
            // Compare the set of administrators advertized in the last block with the administors in updated group members for the blob
            
            let updatedAdministratorsChain: AdministratorsChain
            do {
                let chainAdmins = self.administratorsChain.allCurrentAdministratorIdentities
                let blobAdmins = Set(updatedGroupMembers.filter({ $0.hasGroupAdminPermission }).map({ $0.identity }))
                if chainAdmins != blobAdmins {
                    let otherAdministrators = Array(blobAdmins.filter({ $0 != ownedIdentity }))
                    updatedAdministratorsChain = try self.administratorsChain.addBlock(ownedIdentity: ownedIdentity,
                                                                                       otherAdministrators: otherAdministrators,
                                                                                       using: prng,
                                                                                       solveChallengeDelegate: solveChallengeDelegate,
                                                                                       within: obvContext)
                } else {
                    updatedAdministratorsChain = self.administratorsChain
                }
            }
            
            // Create and return the updated blob
            
            let updatedBlob = ServerBlob(administratorsChain: updatedAdministratorsChain,
                                         groupMembers: updatedGroupMembers,
                                         groupVersion: self.groupVersion + 1,
                                         serializedGroupCoreDetails: updatedSerializedGroupCoreDetails,
                                         serverPhotoInfo: updatedServerPhotoInfo)

            return updatedBlob
            
        }
        
        
        public func withCheckedAdministratorsChainIntegrity(expectedGroupIdentifier: Identifier) throws -> ServerBlob {
            
            let checkedAdministratorsChain = try self.administratorsChain.withCheckedIntegrity(expectedGroupUID: expectedGroupIdentifier.groupUID)
            
            return ServerBlob(administratorsChain: checkedAdministratorsChain,
                              groupMembers: self.groupMembers,
                              groupVersion: self.groupVersion,
                              serializedGroupCoreDetails: self.serializedGroupCoreDetails,
                              serverPhotoInfo: self.serverPhotoInfo)

        }
        
        
        public func withForcedCheckedAdministratorsChainIntegrity() -> ServerBlob {
            
            guard !self.administratorsChain.integrityChecked else { return self }
            
            let checkedAdministratorsChain = self.administratorsChain.withForcedCheckedIntegrity()

            return ServerBlob(administratorsChain: checkedAdministratorsChain,
                              groupMembers: self.groupMembers,
                              groupVersion: self.groupVersion,
                              serializedGroupCoreDetails: self.serializedGroupCoreDetails,
                              serverPhotoInfo: self.serverPhotoInfo)

        }
        
        
        /// Extracts the owned identity's permission and group invitation nonce
        ///
        /// If the owned identity is not part of the group members, this method returns `nil`.
        public func getOwnPermissionsAndGroupInvitationNonce(ownedIdentity: ObvCryptoIdentity) -> (rawOwnPermissions: Set<String>, ownGroupInvitationNonce: Data)? {
            guard let groupMember = self.groupMembers.first(where: { $0.identity == ownedIdentity }) else { return nil }
            return (groupMember.rawPermissions, groupMember.groupInvitationNonce)
        }

        
        /// Extracts  the identities and permissions of the other group members.
        public func getOtherGroupMembers(ownedIdentity: ObvCryptoIdentity) -> Set<GroupV2.IdentityAndPermissionsAndDetails> {
            return self.groupMembers.filter({ $0.identity != ownedIdentity })
        }
        
    }
    
    
    // MARK: - BlobKeys
    
    public struct BlobKeys: ObvFailableCodable, ObvErrorMaker {
        
        public let blobMainSeed: Seed? // May be nil when sent through an asymmetric channel
        public let blobVersionSeed: Seed
        public let groupAdminServerAuthenticationPrivateKey: PrivateKeyForAuthentication? // May be nil when you are not admin/they are not the admin
        
        public static let errorDomain = "GroupV2.BlobKeys"

        public init(blobMainSeed: Seed?, blobVersionSeed: Seed, groupAdminServerAuthenticationPrivateKey: PrivateKeyForAuthentication?) {
            self.blobMainSeed = blobMainSeed
            self.blobVersionSeed = blobVersionSeed
            self.groupAdminServerAuthenticationPrivateKey = groupAdminServerAuthenticationPrivateKey
        }
        
        private enum ObvCodingKeys: String, CaseIterable, CodingKey {
            case blobMainSeed = "ms"
            case blobVersionSeed = "vs"
            case groupAdminServerAuthenticationPrivateKey = "ga"
            var key: Data { rawValue.data(using: .utf8)! }
        }

        public func obvEncode() throws -> ObvEncoded {
            var obvDict = [Data: ObvEncoded]()
            for codingKey in ObvCodingKeys.allCases {
                switch codingKey {
                case .blobMainSeed:
                    try obvDict.obvEncodeIfPresent(blobMainSeed, forKey: codingKey)
                case .blobVersionSeed:
                    try obvDict.obvEncode(blobVersionSeed, forKey: codingKey)
                case .groupAdminServerAuthenticationPrivateKey:
                    if let key = groupAdminServerAuthenticationPrivateKey {
                        obvDict[ObvCodingKeys.groupAdminServerAuthenticationPrivateKey.key] = key.obvEncode()
                    }
                }
            }
            return obvDict.obvEncode()
        }

        public init?(_ obvEncoded: ObvEncoded) {
            guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
            do {
                let blobMainSeed = try obvDict.obvDecodeIfPresent(Seed.self, forKey: ObvCodingKeys.blobMainSeed)
                let blobVersionSeed = try obvDict.obvDecode(Seed.self, forKey: ObvCodingKeys.blobVersionSeed)
                let groupAdminServerAuthenticationPrivateKey: PrivateKeyForAuthentication?
                if let encodedKey = obvDict[ObvCodingKeys.groupAdminServerAuthenticationPrivateKey.key] {
                    guard let key = PrivateKeyForAuthenticationDecoder.obvDecode(encodedKey) else {
                        assertionFailure(); throw Self.makeError(message: "Could not decode groupAdminServerAuthenticationPrivateKey")
                    }
                    groupAdminServerAuthenticationPrivateKey = key
                } else {
                    groupAdminServerAuthenticationPrivateKey = nil
                }
                self.init(blobMainSeed: blobMainSeed,
                          blobVersionSeed: blobVersionSeed,
                          groupAdminServerAuthenticationPrivateKey: groupAdminServerAuthenticationPrivateKey)
            } catch {
                assertionFailure(error.localizedDescription)
                return nil
            }
        }
    }
    
    
    // MARK: - InvitationCollectedData
    
    public struct InvitationCollectedData: ObvFailableCodable, ObvErrorMaker {
        
        public let inviterIdentityAndBlobMainSeedCandidates: [ObvCryptoIdentity: Seed]
        public let blobVersionSeedCandidates: Set<Seed>
        public let groupAdminServerAuthenticationPrivateKeyCandidates: [PrivateKeyForAuthentication]
        
        public static let errorDomain = "GroupV2.InvitationCollectedData"

        private enum ObvCodingKeys: String, CaseIterable, CodingKey {
            case inviterIdentityAndBlobMainSeedCandidates = "ms"
            case blobVersionSeedCandidates = "vs"
            case groupAdminServerAuthenticationPrivateKeyCandidates = "ga"
            var key: Data { rawValue.data(using: .utf8)! }
        }

        private init(inviterIdentityAndBlobMainSeedCandidates: [ObvCryptoIdentity: Seed], blobVersionSeedCandidates: Set<Seed>, groupAdminServerAuthenticationPrivateKeyCandidates: [PrivateKeyForAuthentication]) {
            self.inviterIdentityAndBlobMainSeedCandidates = inviterIdentityAndBlobMainSeedCandidates
            self.blobVersionSeedCandidates = blobVersionSeedCandidates
            self.groupAdminServerAuthenticationPrivateKeyCandidates = groupAdminServerAuthenticationPrivateKeyCandidates
        }

        public init() {
            self.inviterIdentityAndBlobMainSeedCandidates = [ObvCryptoIdentity: Seed]()
            self.blobVersionSeedCandidates = Set<Seed>()
            self.groupAdminServerAuthenticationPrivateKeyCandidates = [PrivateKeyForAuthentication]()
        }
                
        public func obvEncode() throws -> ObvEncoded {
            var obvDict = [Data: ObvEncoded]()
            for codingKey in ObvCodingKeys.allCases {
                switch codingKey {
                case .inviterIdentityAndBlobMainSeedCandidates:
                    let listOfEncoded = inviterIdentityAndBlobMainSeedCandidates.map { (inviter, seed) in
                        [inviter.obvEncode(), seed.obvEncode()].obvEncode()
                    }
                    obvDict[codingKey.key] = listOfEncoded.obvEncode()
                case .blobVersionSeedCandidates:
                    try obvDict.obvEncode(blobVersionSeedCandidates, forKey: codingKey)
                case .groupAdminServerAuthenticationPrivateKeyCandidates:
                    try obvDict.obvEncode(groupAdminServerAuthenticationPrivateKeyCandidates, forKey: codingKey)
                }
            }
            return obvDict.obvEncode()
        }

        
        public init?(_ obvEncoded: ObvEncoded) {
            guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); return nil }
            do {
                guard let encodedList = obvDict[ObvCodingKeys.inviterIdentityAndBlobMainSeedCandidates.key],
                      let listOfEncoded = [ObvEncoded](encodedList) else { return nil }
                let inviterIdentityAndBlobMainSeedCandidates: [ObvCryptoIdentity: Seed] = try Dictionary(uniqueKeysWithValues: listOfEncoded.map { encodedPair in
                    guard let pairOfEncoded = [ObvEncoded](encodedPair, expectedCount: 2),
                          let cryptoIdentity = ObvCryptoIdentity(pairOfEncoded[0]),
                          let seed = Seed(pairOfEncoded[1]) else { throw Self.makeError(message: "Decoding error") }
                    return (cryptoIdentity, seed)
                })
                let blobVersionSeedCandidates = try obvDict.obvDecode(Set<Seed>.self, forKey: ObvCodingKeys.blobVersionSeedCandidates)
                guard let encodedKeys = obvDict[ObvCodingKeys.groupAdminServerAuthenticationPrivateKeyCandidates.key],
                      let listOfEncodedKeys = [ObvEncoded](encodedKeys) else { return nil }
                let groupAdminServerAuthenticationPrivateKeyCandidates: [PrivateKeyForAuthentication] = try listOfEncodedKeys.map {
                    guard let key = PrivateKeyForAuthenticationDecoder.obvDecode($0) else { throw Self.makeError(message: "Decoding key error") }
                    return key
                }
                self.init(inviterIdentityAndBlobMainSeedCandidates: inviterIdentityAndBlobMainSeedCandidates,
                          blobVersionSeedCandidates: blobVersionSeedCandidates,
                          groupAdminServerAuthenticationPrivateKeyCandidates: groupAdminServerAuthenticationPrivateKeyCandidates)
            } catch {
                assertionFailure(error.localizedDescription)
                return nil
            }
        }
        
        
        public func insertingBlobKeysCandidates(_ blobKeysCandidates: BlobKeys, fromInviter inviter: ObvCryptoIdentity?) -> Self {
            
            var inviterIdentityAndBlobMainSeedCandidates = self.inviterIdentityAndBlobMainSeedCandidates
            if let blobMainSeed = blobKeysCandidates.blobMainSeed, let inviter = inviter {
                inviterIdentityAndBlobMainSeedCandidates[inviter] = blobMainSeed
            }
            
            var blobVersionSeedCandidates = self.blobVersionSeedCandidates
            blobVersionSeedCandidates.insert(blobKeysCandidates.blobVersionSeed)
            
            var groupAdminServerAuthenticationPrivateKeyCandidates = self.groupAdminServerAuthenticationPrivateKeyCandidates
            if let key = blobKeysCandidates.groupAdminServerAuthenticationPrivateKey {
                groupAdminServerAuthenticationPrivateKeyCandidates.append(key)
            }

            return Self.init(inviterIdentityAndBlobMainSeedCandidates: inviterIdentityAndBlobMainSeedCandidates,
                             blobVersionSeedCandidates: blobVersionSeedCandidates,
                             groupAdminServerAuthenticationPrivateKeyCandidates: groupAdminServerAuthenticationPrivateKeyCandidates)

        }
        
    }
    
    
    // MARK: - IdentifierVersionAndKeys
    
    public struct IdentifierVersionAndKeys: ObvFailableCodable, ObvErrorMaker {
        
        public let groupIdentifier: Identifier
        public let groupVersion: Int
        public let blobKeys: BlobKeys
        
        public static var errorDomain = "GroupV2.IdentifierVersionAndKeys"

        public init(groupIdentifier: Identifier, groupVersion: Int, blobKeys: BlobKeys) {
            self.groupIdentifier = groupIdentifier
            self.groupVersion = groupVersion
            self.blobKeys = blobKeys
        }
        
        public func obvEncode() throws -> ObvEncoded {
            [groupIdentifier.obvEncode(), groupVersion.obvEncode(), try blobKeys.obvEncode()].obvEncode()
        }

        public init?(_ obvEncoded: ObvEncoded) {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 3) else { assertionFailure(); return nil }
            do { (groupIdentifier, groupVersion, blobKeys) = try encodedValues.obvDecode() } catch { assertionFailure(); return nil }
        }
        
    }
    
}
