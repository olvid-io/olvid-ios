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
import ObvTypes
import ObvCrypto
import ObvMetaManager


// MARK: - Protocol States

extension GroupV2Protocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initialState = 0
        case uploadingCreatedGroupData = 1
        case downloadingGroupBlob = 2
        case iNeedMoreSeeds = 3
        case invitationReceived = 4
        case rejectingInvitationOrLeavingGroup = 5
        case waitingForLock = 6
        case uploadingUpdatedGroupBlob = 7
        case uploadingUpdatedGroupPhoto = 8
        case disbandingGroup = 9
        case final = 100
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState                       : return ConcreteProtocolInitialState.self
            case .uploadingCreatedGroupData          : return UploadingCreatedGroupDataState.self
            case .downloadingGroupBlob               : return DownloadingGroupBlobState.self
            case .iNeedMoreSeeds                     : return INeedMoreSeedsState.self
            case .invitationReceived                 : return InvitationReceivedState.self
            case .rejectingInvitationOrLeavingGroup  : return RejectingInvitationOrLeavingGroupState.self
            case .waitingForLock                     : return WaitingForLockState.self
            case .uploadingUpdatedGroupBlob          : return UploadingUpdatedGroupBlobState.self
            case .uploadingUpdatedGroupPhoto         : return UploadingUpdatedGroupPhotoState.self
            case .disbandingGroup                    : return DisbandingGroupState.self
            case .final                              : return FinalState.self
            }
        }
    }
    
    
    // MARK: - UploadingGroupDataState
    
    struct UploadingCreatedGroupDataState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.uploadingCreatedGroupData
        
        let groupIdentifier: GroupV2.Identifier
        let groupVersion: Int
        let waitingForBlobUpload: Bool
        let waitingForPhotoUpload: Bool

        init(groupIdentifier: GroupV2.Identifier, groupVersion: Int, waitingForBlobUpload: Bool, waitingForPhotoUpload: Bool) {
            self.groupIdentifier = groupIdentifier
            self.groupVersion = groupVersion
            self.waitingForBlobUpload = waitingForBlobUpload
            self.waitingForPhotoUpload = waitingForPhotoUpload
        }

        func obvEncode() -> ObvEncoded {
            [groupIdentifier, groupVersion, waitingForBlobUpload, waitingForPhotoUpload].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 4) else { assertionFailure(); throw Self.makeError(message: "Unexpected number of elements in encoded UploadingGroupDataState") }
            self.groupIdentifier = try encodedValues[0].obvDecode()
            self.groupVersion = try encodedValues[1].obvDecode()
            self.waitingForBlobUpload = try encodedValues[2].obvDecode()
            self.waitingForPhotoUpload = try encodedValues[3].obvDecode()
        }
                        
    }
    
    
    // MARK: - DownloadingGroupBlobState
    
    struct DownloadingGroupBlobState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.downloadingGroupBlob
        
        let groupIdentifier: GroupV2.Identifier
        let dialogUuid: UUID
        let invitationCollectedData: GroupV2.InvitationCollectedData
        let expectedInternalServerQueryIdentifier: Int
        let lastKnownOwnInvitationNonceAndOtherMembers: (nonce: Data, otherGroupMembers: Set<ObvCryptoIdentity>)?

        init(groupIdentifier: GroupV2.Identifier, dialogUuid: UUID, invitationCollectedData: GroupV2.InvitationCollectedData, expectedInternalServerQueryIdentifier: Int, lastKnownOwnInvitationNonceAndOtherMembers: (nonce: Data, otherGroupMembers: Set<ObvCryptoIdentity>)?) {
            self.groupIdentifier = groupIdentifier
            self.dialogUuid = dialogUuid
            self.invitationCollectedData = invitationCollectedData
            self.lastKnownOwnInvitationNonceAndOtherMembers = lastKnownOwnInvitationNonceAndOtherMembers
            self.expectedInternalServerQueryIdentifier = expectedInternalServerQueryIdentifier
        }

        func obvEncode() throws -> ObvEncoded {
            let encodedCollectedData = try invitationCollectedData.obvEncode()
            var encodedValues = [groupIdentifier.obvEncode(), dialogUuid.obvEncode(), encodedCollectedData, expectedInternalServerQueryIdentifier.obvEncode()]
            if let lastKnownOwnInvitationNonceAndOtherMembers = lastKnownOwnInvitationNonceAndOtherMembers {
                encodedValues.append(lastKnownOwnInvitationNonceAndOtherMembers.nonce.obvEncode())
                encodedValues.append(Array(lastKnownOwnInvitationNonceAndOtherMembers.otherGroupMembers).map({ $0.obvEncode() }).obvEncode())
            }
            return encodedValues.obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw Self.makeError(message: "Could not decode DownloadingGroupDataState") }            
            guard [4, 6].contains(encodedValues.count) else { assertionFailure(); throw Self.makeError(message: "Unexpected number of elements in encoded DownloadingGroupDataState") }
            self.groupIdentifier = try encodedValues[0].obvDecode()
            self.dialogUuid = try encodedValues[1].obvDecode()
            self.invitationCollectedData = try encodedValues[2].obvDecode()
            self.expectedInternalServerQueryIdentifier = try encodedValues[3].obvDecode()
            if encodedValues.count == 6 {
                let nonce: Data = try encodedValues[4].obvDecode()
                guard let encodedGroupMemberIdentities = [ObvEncoded](encodedValues[5]) else { assertionFailure(); throw Self.makeError(message: "Could not decode group member identities in DownloadingGroupDataState") }
                let groupMemberIdentities = Set(encodedGroupMemberIdentities.compactMap({ ObvCryptoIdentity($0) }))
                self.lastKnownOwnInvitationNonceAndOtherMembers = (nonce, groupMemberIdentities)
            } else {
                self.lastKnownOwnInvitationNonceAndOtherMembers = nil
            }
        }
                        
    }

    
    // MARK: - INeedMoreSeedsState
    
    struct INeedMoreSeedsState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.iNeedMoreSeeds
        
        let groupIdentifier: GroupV2.Identifier
        let dialogUuid: UUID
        let invitationCollectedData: GroupV2.InvitationCollectedData
        let lastKnownOwnInvitationNonceAndOtherMembers: (nonce: Data, otherGroupMembers: Set<ObvCryptoIdentity>)?

        init(groupIdentifier: GroupV2.Identifier, dialogUuid: UUID, invitationCollectedData: GroupV2.InvitationCollectedData, lastKnownOwnInvitationNonceAndOtherMembers: (nonce: Data, otherGroupMembers: Set<ObvCryptoIdentity>)?) {
            self.groupIdentifier = groupIdentifier
            self.dialogUuid = dialogUuid
            self.invitationCollectedData = invitationCollectedData
            self.lastKnownOwnInvitationNonceAndOtherMembers = lastKnownOwnInvitationNonceAndOtherMembers
        }

        func obvEncode() throws -> ObvEncoded {
            let encodedCollectedData = try invitationCollectedData.obvEncode()
            var encodedValues = [groupIdentifier.obvEncode(), dialogUuid.obvEncode(), encodedCollectedData]
            if let lastKnownOwnInvitationNonceAndOtherMembers = lastKnownOwnInvitationNonceAndOtherMembers {
                encodedValues.append(lastKnownOwnInvitationNonceAndOtherMembers.nonce.obvEncode())
                encodedValues.append(Array(lastKnownOwnInvitationNonceAndOtherMembers.otherGroupMembers).map({ $0.obvEncode() }).obvEncode())
            }
            return encodedValues.obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw Self.makeError(message: "Could not decode INeedMoreSeedsState") }
            guard [3, 5].contains(encodedValues.count) else { assertionFailure(); throw Self.makeError(message: "Unexpected number of elements in encoded INeedMoreSeedsState") }
            self.groupIdentifier = try encodedValues[0].obvDecode()
            self.dialogUuid = try encodedValues[1].obvDecode()
            self.invitationCollectedData = try encodedValues[2].obvDecode()
            if encodedValues.count == 5 {
                let nonce: Data = try encodedValues[3].obvDecode()
                guard let encodedOtherGroupMembers = [ObvEncoded](encodedValues[4]) else { assertionFailure(); throw Self.makeError(message: "Could not decode group member identities in INeedMoreSeedsState") }
                let otherGroupMembers = Set(encodedOtherGroupMembers.compactMap({ ObvCryptoIdentity($0) }))
                self.lastKnownOwnInvitationNonceAndOtherMembers = (nonce, otherGroupMembers)
            } else {
                self.lastKnownOwnInvitationNonceAndOtherMembers = nil
            }
        }
                        
    }

    
    // MARK: - FinalState
    
    struct FinalState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.final
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }

    
    // MARK: - InvitationReceivedState
    
    struct InvitationReceivedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.invitationReceived
        
        let groupIdentifier: GroupV2.Identifier
        let dialogUuid: UUID
        let inviterIdentity: ObvCryptoIdentity
        let serverBlob: GroupV2.ServerBlob
        let blobKeys: GroupV2.BlobKeys // With non-nil main seed

        init(groupIdentifier: GroupV2.Identifier, dialogUuid: UUID, inviterIdentity: ObvCryptoIdentity, serverBlob: GroupV2.ServerBlob, blobKeys: GroupV2.BlobKeys) {
            self.groupIdentifier = groupIdentifier
            self.dialogUuid = dialogUuid
            self.inviterIdentity = inviterIdentity
            self.serverBlob = serverBlob
            self.blobKeys = blobKeys
        }

        
        func obvEncode() throws -> ObvEncoded {
            return try [groupIdentifier.obvEncode(),
                        dialogUuid.obvEncode(),
                        inviterIdentity.obvEncode(),
                        serverBlob.obvEncode(),
                        blobKeys.obvEncode()].obvEncode()
        }

        
        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 5) else { assertionFailure(); throw Self.makeError(message: "Unexpected number of elements in encoded InvitationReceivedState") }
            self.groupIdentifier = try encodedValues[0].obvDecode()
            self.dialogUuid = try encodedValues[1].obvDecode()
            self.inviterIdentity = try encodedValues[2].obvDecode()
            self.serverBlob = try encodedValues[3].obvDecode()
            self.blobKeys = try encodedValues[4].obvDecode()
        }
            
        
    }

    
    // MARK: - InvitationReceivedState
    
    struct RejectingInvitationOrLeavingGroupState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.rejectingInvitationOrLeavingGroup
        
        let groupIdentifier: GroupV2.Identifier
        let groupMembersToNotify: Set<ObvCryptoIdentity>

        init(groupIdentifier: GroupV2.Identifier, groupMembersToNotify: Set<ObvCryptoIdentity>) {
            self.groupIdentifier = groupIdentifier
            self.groupMembersToNotify = groupMembersToNotify
        }

        
        func obvEncode() -> ObvEncoded {
            return  [groupIdentifier.obvEncode(), groupMembersToNotify.map({ $0.obvEncode() }).obvEncode()].obvEncode()
        }

        
        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); throw Self.makeError(message: "Unexpected number of elements in encoded RejectingInvitationState") }
            self.groupIdentifier = try encodedValues[0].obvDecode()
            guard let encodedGroupMembersToNotify = [ObvEncoded](encodedValues[1]) else { assertionFailure(); throw Self.makeError(message: "Could not decode group members to notify") }
            let groupMembersToNotify: [ObvCryptoIdentity] = try encodedGroupMembersToNotify.map({ try $0.obvDecode() })
            self.groupMembersToNotify = Set(groupMembersToNotify)
        }
        
    }
    
    
    // MARK: - WaitingForLockState
    
    struct WaitingForLockState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitingForLock
        
        let groupIdentifier: GroupV2.Identifier
        let changeset: ObvGroupV2.Changeset
        let lockNonce: Data
        let failedUploadCounter: Int
        
        init(groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset, lockNonce: Data, failedUploadCounter: Int) {
            self.groupIdentifier = groupIdentifier
            self.changeset = changeset
            self.lockNonce = lockNonce
            self.failedUploadCounter = failedUploadCounter
        }

        
        func obvEncode() throws -> ObvEncoded {
            return try [groupIdentifier.obvEncode(), changeset.obvEncode(), lockNonce.obvEncode(), failedUploadCounter.obvEncode()].obvEncode()
        }

        
        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 4) else {
                assertionFailure()
                throw Self.makeError(message: "Unexpected number of elements in encoded WaitingForLockState")
            }
            (groupIdentifier, changeset, lockNonce, failedUploadCounter) = try encodedValues.obvDecode()
        }

    }

    
    // MARK: - UploadingUpdatedGroupBlobState
    
    struct UploadingUpdatedGroupBlobState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.uploadingUpdatedGroupBlob
        
        let groupIdentifier: GroupV2.Identifier
        let changeset: ObvGroupV2.Changeset
        let previousServerBlob: GroupV2.ServerBlob
        let uploadedServerBlob: GroupV2.ServerBlob
        let updatedServerAuthenticationPrivateKey: PrivateKeyForAuthentication?
        let updatedBlobVersionSeed: Seed
        let failedUploadCounter: Int

        private enum ObvCodingKeys: String, CaseIterable, CodingKey {
            case groupIdentifier = "gi"
            case changeset = "cs"
            case previousServerBlob = "psb"
            case uploadedServerBlob = "usb"
            case updatedServerAuthenticationPrivateKey = "usapk"
            case updatedBlobVersionSeed = "ubvs"
            case failedUploadCounter = "fuc"
            var key: Data { rawValue.data(using: .utf8)! }
        }

        /// When creating the state, the blob is actually not uploaded yet.
        init(groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset, previousServerBlob: GroupV2.ServerBlob, uploadedServerBlob: GroupV2.ServerBlob, updatedServerAuthenticationPrivateKey: PrivateKeyForAuthentication?, updatedBlobVersionSeed: Seed, failedUploadCounter: Int) {
            self.groupIdentifier = groupIdentifier
            self.changeset = changeset
            self.previousServerBlob = previousServerBlob
            self.uploadedServerBlob = uploadedServerBlob
            self.updatedServerAuthenticationPrivateKey = updatedServerAuthenticationPrivateKey
            self.updatedBlobVersionSeed = updatedBlobVersionSeed
            self.failedUploadCounter = failedUploadCounter
        }
        
        
        public func obvEncode() throws -> ObvEncoded {
            var obvDict = [Data: ObvEncoded]()
            for codingKey in ObvCodingKeys.allCases {
                switch codingKey {
                case .groupIdentifier:
                    try obvDict.obvEncode(groupIdentifier, forKey: codingKey)
                case .changeset:
                    try obvDict.obvEncode(changeset, forKey: codingKey)
                case .previousServerBlob:
                    try obvDict.obvEncode(previousServerBlob, forKey: codingKey)
                case .uploadedServerBlob:
                    try obvDict.obvEncode(uploadedServerBlob, forKey: codingKey)
                case .updatedServerAuthenticationPrivateKey:
                    guard let privateKey = updatedServerAuthenticationPrivateKey else { continue }
                    try obvDict.updateValue(privateKey.obvEncode(), forKey: codingKey)
                case .updatedBlobVersionSeed:
                    try obvDict.obvEncode(updatedBlobVersionSeed, forKey: codingKey)
                case .failedUploadCounter:
                    try obvDict.obvEncode(failedUploadCounter, forKey: codingKey)
                }
            }
            return obvDict.obvEncode()
        }

        
        init(_ obvEncoded: ObvEncoded) throws {
            guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); throw Self.makeError(message: "Could not decode dict in UploadingUpdatedGroupBlobState") }
            self.groupIdentifier = try obvDict.obvDecode(GroupV2.Identifier.self, forKey: ObvCodingKeys.groupIdentifier)
            self.changeset = try obvDict.obvDecode(ObvGroupV2.Changeset.self, forKey: ObvCodingKeys.changeset)
            self.previousServerBlob = try obvDict.obvDecode(GroupV2.ServerBlob.self, forKey: ObvCodingKeys.previousServerBlob)
            self.uploadedServerBlob = try obvDict.obvDecode(GroupV2.ServerBlob.self, forKey: ObvCodingKeys.uploadedServerBlob)
            if let encodedPrivKey = try obvDict.getValueIfPresent(forKey: ObvCodingKeys.updatedServerAuthenticationPrivateKey) {
                guard let privKey = PrivateKeyForAuthenticationDecoder.obvDecode(encodedPrivKey) else {
                    assertionFailure()
                    throw Self.makeError(message: "Failed to decode private key in UploadingUpdatedGroupBlobState")
                }
                self.updatedServerAuthenticationPrivateKey = privKey
            } else {
                self.updatedServerAuthenticationPrivateKey = nil
            }
            self.updatedBlobVersionSeed = try obvDict.obvDecode(Seed.self, forKey: ObvCodingKeys.updatedBlobVersionSeed)
            self.failedUploadCounter = try obvDict.obvDecode(Int.self, forKey: ObvCodingKeys.failedUploadCounter)
        }

    }


    // MARK: - UploadingUpdatedGroupPhotoState
    
    struct UploadingUpdatedGroupPhotoState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.uploadingUpdatedGroupPhoto
        
        let groupIdentifier: GroupV2.Identifier
        let changeset: ObvGroupV2.Changeset
        let previousServerBlob: GroupV2.ServerBlob
        let uploadedServerBlob: GroupV2.ServerBlob
        let updatedServerAuthenticationPrivateKey: PrivateKeyForAuthentication?
        let updatedBlobVersionSeed: Seed
        let serverPhotoInfoOfNewUploadedPhoto: GroupV2.ServerPhotoInfo?

        private enum ObvCodingKeys: String, CaseIterable, CodingKey {
            case groupIdentifier = "gi"
            case changeset = "cs"
            case previousServerBlob = "psb"
            case uploadedServerBlob = "usb"
            case updatedServerAuthenticationPrivateKey = "usapk"
            case updatedBlobVersionSeed = "ubvs"
            case serverPhotoInfoOfNewUploadedPhoto = "spi"
            var key: Data { rawValue.data(using: .utf8)! }
        }

        /// When creating the state, the blob is actually not uploaded yet.
        init(groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset, previousServerBlob: GroupV2.ServerBlob, uploadedServerBlob: GroupV2.ServerBlob, updatedServerAuthenticationPrivateKey: PrivateKeyForAuthentication?, updatedBlobVersionSeed: Seed, serverPhotoInfoOfNewUploadedPhoto: GroupV2.ServerPhotoInfo?) {
            self.groupIdentifier = groupIdentifier
            self.changeset = changeset
            self.previousServerBlob = previousServerBlob
            self.uploadedServerBlob = uploadedServerBlob
            self.updatedServerAuthenticationPrivateKey = updatedServerAuthenticationPrivateKey
            self.updatedBlobVersionSeed = updatedBlobVersionSeed
            self.serverPhotoInfoOfNewUploadedPhoto = serverPhotoInfoOfNewUploadedPhoto
        }
        
        
        public func obvEncode() throws -> ObvEncoded {
            var obvDict = [Data: ObvEncoded]()
            for codingKey in ObvCodingKeys.allCases {
                switch codingKey {
                case .groupIdentifier:
                    try obvDict.obvEncode(groupIdentifier, forKey: codingKey)
                case .changeset:
                    try obvDict.obvEncode(changeset, forKey: codingKey)
                case .previousServerBlob:
                    try obvDict.obvEncode(previousServerBlob, forKey: codingKey)
                case .uploadedServerBlob:
                    try obvDict.obvEncode(uploadedServerBlob, forKey: codingKey)
                case .updatedServerAuthenticationPrivateKey:
                    guard let privateKey = updatedServerAuthenticationPrivateKey else { continue }
                    try obvDict.updateValue(privateKey.obvEncode(), forKey: codingKey)
                case .updatedBlobVersionSeed:
                    try obvDict.obvEncode(updatedBlobVersionSeed, forKey: codingKey)
                case .serverPhotoInfoOfNewUploadedPhoto:
                    try obvDict.obvEncodeIfPresent(serverPhotoInfoOfNewUploadedPhoto, forKey: codingKey)
                }
            }
            return obvDict.obvEncode()
        }


        init(_ obvEncoded: ObvEncoded) throws {
            guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); throw Self.makeError(message: "Could not decode dict in UploadingUpdatedGroupPhotoState") }
            self.groupIdentifier = try obvDict.obvDecode(GroupV2.Identifier.self, forKey: ObvCodingKeys.groupIdentifier)
            self.changeset = try obvDict.obvDecode(ObvGroupV2.Changeset.self, forKey: ObvCodingKeys.changeset)
            self.previousServerBlob = try obvDict.obvDecode(GroupV2.ServerBlob.self, forKey: ObvCodingKeys.previousServerBlob)
            self.uploadedServerBlob = try obvDict.obvDecode(GroupV2.ServerBlob.self, forKey: ObvCodingKeys.uploadedServerBlob)
            if let encodedPrivKey = try obvDict.getValueIfPresent(forKey: ObvCodingKeys.updatedServerAuthenticationPrivateKey) {
                guard let privKey = PrivateKeyForAuthenticationDecoder.obvDecode(encodedPrivKey) else {
                    assertionFailure()
                    throw Self.makeError(message: "Failed to decode private key in UploadingUpdatedGroupPhotoState")
                }
                self.updatedServerAuthenticationPrivateKey = privKey
            } else {
                self.updatedServerAuthenticationPrivateKey = nil
            }
            self.updatedBlobVersionSeed = try obvDict.obvDecode(Seed.self, forKey: ObvCodingKeys.updatedBlobVersionSeed)
            self.serverPhotoInfoOfNewUploadedPhoto = try obvDict.obvDecodeIfPresent(GroupV2.ServerPhotoInfo.self, forKey: ObvCodingKeys.serverPhotoInfoOfNewUploadedPhoto)
        }

    }

    
    // MARK: - DisbandingGroupState
    
    struct DisbandingGroupState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.disbandingGroup
        
        let groupIdentifier: GroupV2.Identifier
        let blobMainSeed: Seed

        init(groupIdentifier: GroupV2.Identifier, blobMainSeed: Seed) {
            self.groupIdentifier = groupIdentifier
            self.blobMainSeed = blobMainSeed
        }

        func obvEncode() throws -> ObvEncoded {
            return [groupIdentifier.obvEncode(), blobMainSeed.obvEncode()].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); throw Self.makeError(message: "Unexpected number of elements in encoded DisbandingGroupState") }
            self.groupIdentifier = try encodedValues[0].obvDecode()
            self.blobMainSeed = try encodedValues[1].obvDecode()
        }
                        
    }

}
