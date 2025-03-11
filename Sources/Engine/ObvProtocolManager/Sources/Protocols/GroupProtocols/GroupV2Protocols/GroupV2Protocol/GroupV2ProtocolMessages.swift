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

// MARK: - Protocol Messages

extension GroupV2Protocol {
    
    enum MessageId: Int, ConcreteProtocolMessageId {
        
        case initiateGroupCreation = 0
        case uploadGroupPhoto = 1
        case uploadGroupBlob = 2
        case finalizeGroupCreation = 3
        case invitationOrMembersUpdate = 4
        case invitationOrMembersUpdateBroadcast = 5
        case invitationOrMembersUpdatePropagated = 6
        case downloadGroupBlob = 7
        case finalizeGroupUpdate = 8
        case deleteGroupBlobFromServer = 9
        case dialogAcceptGroupV2Invitation = 10
        case ping = 11
        case propagatedPing = 12
        case kick = 13
        case propagateInvitationDialogResponse = 14
        case putGroupLogOnServer = 15
        case invitationRejectedBroadcast = 16
        case propagateInvitationRejected = 17
        case initiateGroupUpdate = 18
        case requestServerLock = 19
        case initiateGroupLeave = 20
        case propagatedGroupLeave = 21
        case initiateGroupDisband = 22
        case propagateGroupDisband = 23
        case propagatedKick = 24
        case initiateGroupReDownload = 25
        case initiateBatchKeysResend = 26
        case blobKeysBatchAfterChannelCreation = 27
        case blobKeysAfterChannelCreation = 28
        case initiateTargetedPing = 30
        case dialogInformative = 50
        case dialogFreezeGroupV2Invitation = 200
        case initiateUpdateKeycloakGroups = 300
        case autoAcceptInvitation = 400

        var concreteProtocolMessageType: ConcreteProtocolMessage.Type {
            switch self {
            case .initiateGroupCreation               : return InitiateGroupCreationMessage.self
            case .uploadGroupPhoto                    : return UploadGroupPhotoMessage.self
            case .uploadGroupBlob                     : return UploadGroupBlobMessage.self
            case .finalizeGroupCreation               : return FinalizeGroupCreationMessage.self
            case .invitationOrMembersUpdate           : return InvitationOrMembersUpdateMessage.self
            case .invitationOrMembersUpdateBroadcast  : return InvitationOrMembersUpdateBroadcastMessage.self
            case .invitationOrMembersUpdatePropagated : return InvitationOrMembersUpdatePropagatedMessage.self
            case .downloadGroupBlob                   : return DownloadGroupBlobMessage.self
            case .finalizeGroupUpdate                 : return FinalizeGroupUpdateMessage.self
            case .deleteGroupBlobFromServer           : return DeleteGroupBlobFromServerMessage.self
            case .dialogAcceptGroupV2Invitation       : return DialogAcceptGroupV2InvitationMessage.self
            case .ping                                : return PingMessage.self
            case .propagatedPing                      : return PropagatedPingMessage.self
            case .kick                                : return KickMessage.self
            case .propagateInvitationDialogResponse   : return PropagateInvitationDialogResponseMessage.self
            case .putGroupLogOnServer                 : return PutGroupLogOnServerMessage.self
            case .invitationRejectedBroadcast         : return InvitationRejectedBroadcastMessage.self
            case .propagateInvitationRejected         : return PropagateInvitationRejectedMessage.self
            case .dialogInformative                   : return DialogInformativeMessage.self
            case .initiateGroupUpdate                 : return InitiateGroupUpdateMessage.self
            case .requestServerLock                   : return RequestServerLockMessage.self
            case .initiateGroupLeave                  : return InitiateGroupLeaveMessage.self
            case .propagatedGroupLeave                : return PropagatedGroupLeaveMessage.self
            case .initiateGroupDisband                : return InitiateGroupDisbandMessage.self
            case .propagateGroupDisband               : return PropagateGroupDisbandMessage.self
            case .propagatedKick                      : return PropagatedKickMessage.self
            case .initiateGroupReDownload             : return InitiateGroupReDownloadMessage.self
            case .initiateBatchKeysResend             : return InitiateBatchKeysResendMessage.self
            case .blobKeysBatchAfterChannelCreation   : return BlobKeysBatchAfterChannelCreationMessage.self
            case .blobKeysAfterChannelCreation        : return BlobKeysAfterChannelCreationMessage.self
            case .initiateTargetedPing                : return InitiateTargetedPingMessage.self
            case .dialogFreezeGroupV2Invitation       : return DialogFreezeGroupV2InvitationMessage.self
            case .initiateUpdateKeycloakGroups        : return InitiateUpdateKeycloakGroupsMessage.self
            case .autoAcceptInvitation                : return AutoAcceptInvitationMessage.self
            }
        }
    }
    
    
    // MARK: - InitiateGroupCreationMessage
    
    struct InitiateGroupCreationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateGroupCreation
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let ownRawPermissions: Set<String>
        let otherGroupMembers: Set<GroupV2.IdentityAndPermissions>
        let serializedGroupCoreDetails: Data // Serialized GroupV2.CoreDetails
        let photoURL: URL?
        let serializedGroupType: Data // Serialized ObvGroupType
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, ownRawPermissions: Set<String>, otherGroupMembers: Set<GroupV2.IdentityAndPermissions>, serializedGroupCoreDetails: Data, photoURL: URL?, serializedGroupType: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.ownRawPermissions = ownRawPermissions
            self.otherGroupMembers = otherGroupMembers
            self.serializedGroupCoreDetails = serializedGroupCoreDetails
            self.photoURL = photoURL
            self.serializedGroupType = serializedGroupType
        }

        var encodedInputs: [ObvEncoded] {
            let encodedOwnRawPermissions = (ownRawPermissions.map { $0.obvEncode() }).obvEncode()
            let encodedMembers = (otherGroupMembers.map { $0.obvEncode() }).obvEncode()
            let encodedCoreDetails = serializedGroupCoreDetails.obvEncode()
            let encodedGroupType = serializedGroupType.obvEncode()
            
            var encodedValues = [encodedOwnRawPermissions, encodedMembers, encodedCoreDetails, encodedGroupType]
            if let photoURL = photoURL {
                encodedValues.append(photoURL.obvEncode())
            }
            
            return encodedValues
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 4 || message.encodedInputs.count == 5 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded inputs") }
            let encodedOwnRawPermissions = message.encodedInputs[0]
            guard let listOfEncodedOwnRawPermissions = [ObvEncoded](encodedOwnRawPermissions) else { throw Self.makeError(message: "Could not decode list of encoded own permissions") }
            self.ownRawPermissions = try Set(listOfEncodedOwnRawPermissions.map { try $0.obvDecode() })
            let encodedMembers = message.encodedInputs[1]
            guard let listOfEncodedMembers = [ObvEncoded](encodedMembers) else { throw Self.makeError(message: "Could not decode list members") }
            self.otherGroupMembers = try Set(listOfEncodedMembers.map { try $0.obvDecode() })
            let encodedCoreDetails = message.encodedInputs[2]
            self.serializedGroupCoreDetails = try encodedCoreDetails.obvDecode()
            let encodedGroupType = message.encodedInputs[3]
            self.serializedGroupType = try encodedGroupType.obvDecode()
            if message.encodedInputs.count > 4 {
                let encodedPhotoURL = message.encodedInputs[4]
                self.photoURL = try encodedPhotoURL.obvDecode()
            } else {
                self.photoURL = nil
            }
        }
        
    }
    
    
    // MARK: - UploadGroupPhotoMessage
    
    struct UploadGroupPhotoMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.uploadGroupPhoto
        let coreProtocolMessage: CoreProtocolMessage

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }

    }


    // MARK: - UploadGroupBlobMessage
    
    struct UploadGroupBlobMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.uploadGroupBlob
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let blobUploadResult: UploadResult
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.blobUploadResult = .temporaryFailure // Will be properly set when set using the server response
        }

        var encodedInputs: [ObvEncoded] {
            []
        }
        
        // Init when receiving this message (the query response are added after the encoded inputs)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { throw Self.makeError(message: "Unexpected number of encoded elements") }
            self.blobUploadResult = try message.encodedInputs[0].obvDecode()
        }

    }

    
    // MARK: - FinalizeGroupCreationMessage
    
    struct FinalizeGroupCreationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.finalizeGroupCreation
        let coreProtocolMessage: CoreProtocolMessage

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message (the query response are added after the encoded inputs)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 0 else { throw Self.makeError(message: "Unexpected number of encoded elements") }
        }

    }

    
    // MARK: - InvitationOrMembersUpdateMessage

    struct InvitationOrMembersUpdateMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.invitationOrMembersUpdate
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        let groupVersion: Int
        let blobKeys: GroupV2.BlobKeys
        let notifiedDeviceUIDs: Set<UID>

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, groupVersion: Int, blobKeys: GroupV2.BlobKeys, notifiedDeviceUIDs: Set<UID>) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
            self.groupVersion = groupVersion
            self.blobKeys = blobKeys
            self.notifiedDeviceUIDs = notifiedDeviceUIDs
        }

        var encodedInputs: [ObvEncoded] {
            get throws {
                let encodedBlobKeys = try blobKeys.obvEncode()
                return [groupIdentifier.obvEncode(), groupVersion.obvEncode(), encodedBlobKeys, notifiedDeviceUIDs.map({ $0.obvEncode() }).obvEncode()]
            }
        }
        
        // Init when receiving this message (the query response are added after the encoded inputs)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 4 else { throw Self.makeError(message: "Unexpected number of encoded elements") }
            let encodedGroupIdentifier = message.encodedInputs[0]
            let encodedGroupVersion = message.encodedInputs[1]
            let encodedBlobKeys = message.encodedInputs[2]
            let encodedNotifiedDeviceUIDs = message.encodedInputs[3]
            self.groupIdentifier = try encodedGroupIdentifier.obvDecode()
            self.groupVersion = try encodedGroupVersion.obvDecode()
            self.blobKeys = try encodedBlobKeys.obvDecode()
            guard let listOfEncodedNotifiedDeviceUIDs = [ObvEncoded](encodedNotifiedDeviceUIDs) else { throw Self.makeError(message: "Could not decode notified device UIDs") }
            self.notifiedDeviceUIDs = Set(try listOfEncodedNotifiedDeviceUIDs.compactMap({ try $0.obvDecode() }))
        }

    }

    
    // MARK: - InvitationOrMembersUpdateBroadcastMessage

    struct InvitationOrMembersUpdateBroadcastMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.invitationOrMembersUpdateBroadcast
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        let groupVersion: Int
        let blobKeys: GroupV2.BlobKeys

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, groupVersion: Int, blobKeys: GroupV2.BlobKeys) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
            self.groupVersion = groupVersion
            self.blobKeys = blobKeys
        }

        var encodedInputs: [ObvEncoded] {
            get throws {
                let encodedBlobKeys = try blobKeys.obvEncode()
                return [groupIdentifier.obvEncode(), groupVersion.obvEncode(), encodedBlobKeys]
            }
        }
        
        // Init when receiving this message (the query response are added after the encoded inputs)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 3 else { throw Self.makeError(message: "Unexpected number of encoded elements") }
            let encodedGroupIdentifier = message.encodedInputs[0]
            let encodedGroupVersion = message.encodedInputs[1]
            let encodedBlobKeys = message.encodedInputs[2]
            self.groupIdentifier = try encodedGroupIdentifier.obvDecode()
            self.groupVersion = try encodedGroupVersion.obvDecode()
            self.blobKeys = try encodedBlobKeys.obvDecode()
        }

    }

    
    // MARK: - InvitationOrMembersUpdatePropagatedMessage

    struct InvitationOrMembersUpdatePropagatedMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.invitationOrMembersUpdatePropagated
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        let groupVersion: Int
        let blobKeys: GroupV2.BlobKeys
        let inviter: ObvCryptoIdentity?

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, groupVersion: Int, blobKeys: GroupV2.BlobKeys, inviter: ObvCryptoIdentity?) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
            self.groupVersion = groupVersion
            self.blobKeys = blobKeys
            self.inviter = inviter
        }

        var encodedInputs: [ObvEncoded] {
            get throws {
                let encodedBlobKeys = try blobKeys.obvEncode()
                var encodedValues = [groupIdentifier.obvEncode(), groupVersion.obvEncode(), encodedBlobKeys]
                if let inviter = self.inviter {
                    encodedValues.append(inviter.obvEncode())
                }
                return encodedValues
            }
        }

        // Init when receiving this message (the query response are added after the encoded inputs)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 3 || message.encodedInputs.count == 4 else { throw Self.makeError(message: "Unexpected number of encoded elements") }
            let encodedGroupIdentifier = message.encodedInputs[0]
            let encodedGroupVersion = message.encodedInputs[1]
            let encodedBlobKeys = message.encodedInputs[2]
            self.groupIdentifier = try encodedGroupIdentifier.obvDecode()
            self.groupVersion = try encodedGroupVersion.obvDecode()
            self.blobKeys = try encodedBlobKeys.obvDecode()
            if message.encodedInputs.count == 4 {
                let encodedInviter = message.encodedInputs[3]
                self.inviter = try encodedInviter.obvDecode()
            } else {
                self.inviter = nil
            }
        }

    }

    
    // MARK: - DownloadGroupBlobMessage

    struct DownloadGroupBlobMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.downloadGroupBlob
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message.
        // In this particular messages, these values are only used in the response

        // Nil when posting this message from the protocol manager
        let result: GetGroupBlobResult?
        
        // Used to make sure sur the response received by the protocol correspond to request made.
        // Handy to discard "old" requests.
        let internalServerQueryIdentifier: Int
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, internalServerQueryIdentifier: Int) {
            self.coreProtocolMessage = coreProtocolMessage
            self.internalServerQueryIdentifier = internalServerQueryIdentifier
            self.result = nil
        }

        var encodedInputs: [ObvEncoded] {
            return [internalServerQueryIdentifier.obvEncode()]
        }

        // Init when receiving this message (the query response are added after the encoded inputs)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 2 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            self.internalServerQueryIdentifier = try message.encodedInputs[0].obvDecode()
            self.result = try message.encodedInputs[1].obvDecode()
        }

    }

    
    // MARK: - FinalizeGroupUpdateMessage

    struct FinalizeGroupUpdateMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.finalizeGroupUpdate
        let coreProtocolMessage: CoreProtocolMessage

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message (the query response are added after the encoded inputs)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 0 else { throw Self.makeError(message: "Unexpected number of encoded elements") }
        }

    }

    
    // MARK: - DeleteGroupBlobFromServerMessage

    struct DeleteGroupBlobFromServerMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.deleteGroupBlobFromServer
        let coreProtocolMessage: CoreProtocolMessage
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        // Makes sens when receiving this server query, not when posting it from a protocol step
        let groupDeletionWasSuccessful: Bool

        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { throw Self.makeError(message: "Unexpected number of encoded elements") }
            self.groupDeletionWasSuccessful = try message.encodedInputs[0].obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupDeletionWasSuccessful = false // Not important when posting this message from a protocol step
        }
        
        // Simulating a returned server query (used in the OwnedIdentityDeletionProtocol)
                
        init(forSimulatingReceivedMessageForOwnedIdentity ownedIdentity: ObvCryptoIdentity, protocolInstanceUid: UID) {
            self.coreProtocolMessage = CoreProtocolMessage.getServerQueryCoreProtocolMessageForSimulatingReceivedMessage(
                ownedIdentity: ownedIdentity,
                cryptoProtocolId: .groupV2,
                protocolInstanceUid: protocolInstanceUid)
            self.groupDeletionWasSuccessful = true
        }
        
    }

    
    // MARK: - DialogAcceptGroupV2InvitationMessage
    
    struct DialogAcceptGroupV2InvitationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.dialogAcceptGroupV2Invitation
        let coreProtocolMessage: CoreProtocolMessage
        
        let dialogUuid: UUID // Only used when this protocol receives this message
        let invitationAccepted: Bool // Only used when this protocol receives this message
        
        var encodedInputs: [ObvEncoded] {
            return [invitationAccepted.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else { assertionFailure(); throw Self.makeError(message: "Could not get encoded user dialog response") }
            invitationAccepted = try encodedUserDialogResponse.obvDecode()
            guard let userDialogUuid = message.userDialogUuid else { assertionFailure(); throw Self.makeError(message: "Could not get user dialog UUID") }
            dialogUuid = userDialogUuid
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = false // Not used
            dialogUuid = UUID() // Not used
        }
        
    }

    
    // MARK: - PingMessage
    
    struct PingMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.ping
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let groupIdentifier: GroupV2.Identifier
        let groupInvitationNonce: Data // When sending this message, this is our own invitation nonce for this group
        let signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: Data
        let isReponse: Bool

        var encodedInputs: [ObvEncoded] {
            return [groupIdentifier.obvEncode(), groupInvitationNonce.obvEncode(), signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity.obvEncode(), isReponse.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (groupIdentifier, groupInvitationNonce, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity, isReponse) = try encodedElements.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, groupInvitationNonce: Data, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: Data, isReponse: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
            self.groupInvitationNonce = groupInvitationNonce
            self.signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity = signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity
            self.isReponse = isReponse
        }
    }

    
    // MARK: - PropagatedPingMessage
    
    struct PropagatedPingMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagatedPing
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let groupIdentifier: GroupV2.Identifier
        let groupInvitationNonce: Data // Group invitation nonce of the member that initally sent the PingMessage
        let signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: Data
        let isReponse: Bool

        var encodedInputs: [ObvEncoded] {
            return [groupIdentifier.obvEncode(), groupInvitationNonce.obvEncode(), signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity.obvEncode(), isReponse.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (groupIdentifier, groupInvitationNonce, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity, isReponse) = try encodedElements.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, groupInvitationNonce: Data, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: Data, isReponse: Bool) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
            self.groupInvitationNonce = groupInvitationNonce
            self.signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity = signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity
            self.isReponse = isReponse
        }
    }

    
    // MARK: - KickMessage
    
    struct KickMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.kick
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let groupIdentifier: GroupV2.Identifier
        let encryptedAdministratorChain: EncryptedData
        let signature: Data // Computed by one of the administrators indicated in the last block of the chain, on the invitation nonce of the kicked user

        var encodedInputs: [ObvEncoded] {
            return [groupIdentifier.obvEncode(), encryptedAdministratorChain.obvEncode(), signature.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (groupIdentifier, encryptedAdministratorChain, signature) = try encodedElements.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, encryptedAdministratorChain: EncryptedData, signature: Data) {
            self.groupIdentifier = groupIdentifier
            self.coreProtocolMessage = coreProtocolMessage
            self.encryptedAdministratorChain = encryptedAdministratorChain
            self.signature = signature
        }
    }

    
    // MARK: - PropagateInvitationDialogResponseMessage
    
    struct PropagateInvitationDialogResponseMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateInvitationDialogResponse
        let coreProtocolMessage: CoreProtocolMessage
        
        let invitationAccepted: Bool
        let ownGroupInvitationNonce: Data
        
        var encodedInputs: [ObvEncoded] {
            return [invitationAccepted.obvEncode(), ownGroupInvitationNonce.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (invitationAccepted, ownGroupInvitationNonce) = try encodedElements.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, invitationAccepted: Bool, ownGroupInvitationNonce: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = invitationAccepted
            self.ownGroupInvitationNonce = ownGroupInvitationNonce
        }
        
    }

    

    
    // MARK: - PutGroupLogOnServerMessage

    struct PutGroupLogOnServerMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.putGroupLogOnServer
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message.
        // This particular server message (server query) has no values used as a response.

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] {
            return []
        }

        // Init when receiving this message (the query response are added after the encoded inputs)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }

    }

    
    // MARK: - InvitationRejectedBroadcastMessage
    
    struct InvitationRejectedBroadcastMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.invitationRejectedBroadcast
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let groupIdentifier: GroupV2.Identifier

        var encodedInputs: [ObvEncoded] {
            return [groupIdentifier].map({ $0.obvEncode() })
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (groupIdentifier) = try encodedElements.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
        }
    }

    
    // MARK: - PropagateInvitationRejectedMessage
    
    struct PropagateInvitationRejectedMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateInvitationRejected
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let groupIdentifier: GroupV2.Identifier

        var encodedInputs: [ObvEncoded] {
            return [groupIdentifier].map({ $0.obvEncode() })
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (groupIdentifier) = try encodedElements.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
        }
    }

 
    // MARK: - InitiateGroupUpdateMessage
    
    struct InitiateGroupUpdateMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateGroupUpdate
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        let changeset: ObvGroupV2.Changeset
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, changeset: ObvGroupV2.Changeset) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
            self.changeset = changeset
        }

        var encodedInputs: [ObvEncoded] {
            get throws {
                try [groupIdentifier.obvEncode(), changeset.obvEncode()]
            }
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            (groupIdentifier, changeset) = try message.encodedInputs.obvDecode()
        }
        
    }

    
    // MARK: - RequestServerLockMessage
    
    struct RequestServerLockMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.requestServerLock
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        // Nil when posting this message from the protocol manager
        let result: RequestGroupBlobLockResult?

        // Init when sending this message (local properties are only set on reception of the server answer to the server query)

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.result = nil
        }

        var encodedInputs: [ObvEncoded] { [] }

        // Init when receiving this message (the query response are added after the encoded inputs)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            self.result = try message.encodedInputs[0].obvDecode()
        }

    }


    // MARK: - InitiateGroupLeaveMessage
    
    struct InitiateGroupLeaveMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateGroupLeave
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
        }

        var encodedInputs: [ObvEncoded] {
            [groupIdentifier.obvEncode()]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            groupIdentifier = try message.encodedInputs.obvDecode()
        }
        
    }


    // MARK: - PropagatedGroupLeaveMessage
    
    struct PropagatedGroupLeaveMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagatedGroupLeave
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let groupIdentifier: GroupV2.Identifier
        let groupInvitationNonce: Data // When sending this message, this is our own invitation nonce for this group

        var encodedInputs: [ObvEncoded] {
            [groupIdentifier.obvEncode(), groupInvitationNonce.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (groupIdentifier, groupInvitationNonce) = try encodedElements.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, groupInvitationNonce: Data) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
            self.groupInvitationNonce = groupInvitationNonce
        }
    }
    
    
    // MARK: - InitiateGroupDisbandMessage
    
    struct InitiateGroupDisbandMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateGroupDisband
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
        }

        var encodedInputs: [ObvEncoded] {
            [groupIdentifier.obvEncode()]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            groupIdentifier = try message.encodedInputs.obvDecode()
        }
        
    }


    // MARK: - PropagateGroupDisbandMessage
    
    struct PropagateGroupDisbandMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagateGroupDisband
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
        }

        var encodedInputs: [ObvEncoded] {
            [groupIdentifier.obvEncode()]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            groupIdentifier = try message.encodedInputs.obvDecode()
        }
        
    }

    
    // MARK: - PropagatedKickMessage
    
    struct PropagatedKickMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.propagatedKick
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message
        
        let groupIdentifier: GroupV2.Identifier
        let encryptedAdministratorChain: EncryptedData
        let signature: Data // Computed by one of the administrators indicated in the last block of the chain, on the invitation nonce of the kicked user

        var encodedInputs: [ObvEncoded] {
            return [groupIdentifier.obvEncode(), encryptedAdministratorChain.obvEncode(), signature.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedElements = message.encodedInputs
            (groupIdentifier, encryptedAdministratorChain, signature) = try encodedElements.obvDecode()
        }
        
        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, encryptedAdministratorChain: EncryptedData, signature: Data) {
            self.groupIdentifier = groupIdentifier
            self.coreProtocolMessage = coreProtocolMessage
            self.encryptedAdministratorChain = encryptedAdministratorChain
            self.signature = signature
        }
    }

    
    // MARK: - InitiateGroupReDownloadMessage
    
    struct InitiateGroupReDownloadMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateGroupReDownload
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
        }

        var encodedInputs: [ObvEncoded] {
            [groupIdentifier.obvEncode()]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            groupIdentifier = try message.encodedInputs.obvDecode()
        }
        
    }

    
    // MARK: - InitiateBatchKeysResendMessage
    
    struct InitiateBatchKeysResendMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateBatchKeysResend
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let remoteIdentity: ObvCryptoIdentity
        let remoteDeviceUID: UID
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, remoteIdentity: ObvCryptoIdentity, remoteDeviceUID: UID) {
            self.coreProtocolMessage = coreProtocolMessage
            self.remoteIdentity = remoteIdentity
            self.remoteDeviceUID = remoteDeviceUID
        }

        var encodedInputs: [ObvEncoded] {
            [remoteIdentity.obvEncode(), remoteDeviceUID.obvEncode()]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            (remoteIdentity, remoteDeviceUID) = try message.encodedInputs.obvDecode()
        }
        
    }
    
    
    // MARK: - BlobKeysBatchAfterChannelCreationMessage
    
    struct BlobKeysBatchAfterChannelCreationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.blobKeysBatchAfterChannelCreation
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let groupInfos: [GroupV2.IdentifierVersionAndKeys]
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupInfos: [GroupV2.IdentifierVersionAndKeys]) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupInfos = groupInfos
        }

        var encodedInputs: [ObvEncoded] {
            get throws {
                let listOfEncodedGroupInfos = try groupInfos.map({ try $0.obvEncode() })
                return [listOfEncodedGroupInfos.obvEncode()]
            }
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            let encodedInputs = message.encodedInputs
            guard encodedInputs.count == 1 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements in BlobKeysBatchAfterChannelCreationMessage") }
            let encodedListOfGroupInfos = encodedInputs[0]
            guard let listOfEncodedGroupInfos = [ObvEncoded](encodedListOfGroupInfos) else { assertionFailure(); throw Self.makeError(message: "Could not decode encoded list in BlobKeysBatchAfterChannelCreationMessage")}
            let groupInfos = listOfEncodedGroupInfos.compactMap({ GroupV2.IdentifierVersionAndKeys($0) })
            guard groupInfos.count == listOfEncodedGroupInfos.count else { assertionFailure(); throw Self.makeError(message: "Could not decode all infos in BlobKeysBatchAfterChannelCreationMessage") }
            self.groupInfos = groupInfos
        }
        
    }


    // MARK: - BlobKeysAfterChannelCreationMessage
    
    struct BlobKeysAfterChannelCreationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.blobKeysAfterChannelCreation
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        let groupVersion: Int
        let blobKeys: GroupV2.BlobKeys
        let inviter: ObvCryptoIdentity

        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, groupVersion: Int, blobKeys: GroupV2.BlobKeys, inviter: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
            self.groupVersion = groupVersion
            self.blobKeys = blobKeys
            self.inviter = inviter
        }

        var encodedInputs: [ObvEncoded] {
            get throws {
                let encodedBlobKeys = try blobKeys.obvEncode()
                return [groupIdentifier.obvEncode(), groupVersion.obvEncode(), encodedBlobKeys, inviter.obvEncode()]
            }
        }
        
        // Init when receiving this message (the query response are added after the encoded inputs)

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard message.encodedInputs.count == 4 else { assertionFailure(); throw Self.makeError(message: "Unexpected number of encoded elements") }
            let encodedGroupIdentifier = message.encodedInputs[0]
            let encodedGroupVersion = message.encodedInputs[1]
            let encodedBlobKeys = message.encodedInputs[2]
            let encodedInviter = message.encodedInputs[3]
            self.groupIdentifier = try encodedGroupIdentifier.obvDecode()
            self.groupVersion = try encodedGroupVersion.obvDecode()
            self.blobKeys = try encodedBlobKeys.obvDecode()
            self.inviter = try encodedInviter.obvDecode()
        }

    }

    
    // MARK: - DialogInformativeMessage
    // This message is always sent from this protocol, never to this protocol

    struct DialogInformativeMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.dialogInformative
        let coreProtocolMessage: CoreProtocolMessage
        
        var encodedInputs: [ObvEncoded] { return [] }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            // Never used
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }
    }

    
    // MARK: - DialogFreezeGroupV2InvitationMessage
    
    struct DialogFreezeGroupV2InvitationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.dialogFreezeGroupV2Invitation
        let coreProtocolMessage: CoreProtocolMessage
        
        let dialogUuid: UUID // Only used when this protocol receives this message
        let invitationAccepted: Bool // Only used when this protocol receives this message
        
        var encodedInputs: [ObvEncoded] {
            return [invitationAccepted.obvEncode()]
        }
        
        // Initializers
        
        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
            guard let encodedUserDialogResponse = message.encodedUserDialogResponse else { assertionFailure(); throw Self.makeError(message: "Could not get encoded user dialog response") }
            invitationAccepted = try encodedUserDialogResponse.obvDecode()
            guard let userDialogUuid = message.userDialogUuid else { assertionFailure(); throw Self.makeError(message: "Could not get user dialog UUID") }
            dialogUuid = userDialogUuid
        }
        
        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
            self.invitationAccepted = false // Not used
            dialogUuid = UUID() // Not used
        }
        
    }

    
    // MARK: - InitiateUpdateKeycloakGroupsMessage
    
    struct InitiateUpdateKeycloakGroupsMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateUpdateKeycloakGroups
        let coreProtocolMessage: CoreProtocolMessage
        
        // Properties specific to this concrete protocol message

        let signedGroupBlobs: Set<String>
        let signedGroupDeletions: Set<String>
        let signedGroupKicks: Set<String>
        let keycloakCurrentTimestamp: Date
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage, signedGroupBlobs: Set<String>, signedGroupDeletions: Set<String>, signedGroupKicks: Set<String>, keycloakCurrentTimestamp: Date) {
            self.coreProtocolMessage = coreProtocolMessage
            self.signedGroupBlobs = signedGroupBlobs
            self.signedGroupDeletions = signedGroupDeletions
            self.signedGroupKicks = signedGroupKicks
            self.keycloakCurrentTimestamp = keycloakCurrentTimestamp
        }

        var encodedInputs: [ObvEncoded] {
            let encodedSignedGroupBlobs = (signedGroupBlobs.map { $0.obvEncode() }).obvEncode()
            let encodedSignedGroupDeletions = (signedGroupDeletions.map { $0.obvEncode() }).obvEncode()
            let encodedSignedGroupKicks = (signedGroupKicks.map { $0.obvEncode() }).obvEncode()
            let encodedKeycloakCurrentTimestamp = keycloakCurrentTimestamp.obvEncode()
            return [encodedSignedGroupBlobs, encodedSignedGroupDeletions, encodedSignedGroupKicks, encodedKeycloakCurrentTimestamp]
        }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            do {
                self.coreProtocolMessage = CoreProtocolMessage(with: message)
                guard message.encodedInputs.count == 4 else { throw Self.makeError(message: "Unexpected number of encoded inputs in InitiateUpdateKeycloakGroupsMessage") }
                let encodedSignedGroupBlobs = message.encodedInputs[0]
                let encodedSignedGroupDeletions = message.encodedInputs[1]
                let encodedSignedGroupKicks = message.encodedInputs[2]
                let encodedKeycloakCurrentTimestamp = message.encodedInputs[3]
                guard let listOfEncodedSignedGroupBlobs = [ObvEncoded](encodedSignedGroupBlobs) else { throw Self.makeError(message: "Could not decode list of signed blobs") }
                guard let listOfEncodedSignedGroupDeletions = [ObvEncoded](encodedSignedGroupDeletions) else { throw Self.makeError(message: "Could not decode list of signed group deletions") }
                guard let listOfEncodedSignedGroupKicks = [ObvEncoded](encodedSignedGroupKicks) else { throw Self.makeError(message: "Could not decode list of kicks") }
                self.signedGroupBlobs = try Set(listOfEncodedSignedGroupBlobs.map { try $0.obvDecode() })
                self.signedGroupDeletions = try Set(listOfEncodedSignedGroupDeletions.map { try $0.obvDecode() })
                self.signedGroupKicks = try Set(listOfEncodedSignedGroupKicks.map { try $0.obvDecode() })
                self.keycloakCurrentTimestamp = try encodedKeycloakCurrentTimestamp.obvDecode()
            } catch {
                assertionFailure()
                throw error
            }
        }
        
    }

    
    // MARK: - InitiateTargetedPingMessage
    
    struct InitiateTargetedPingMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.initiateTargetedPing
        let coreProtocolMessage: CoreProtocolMessage

        // Properties specific to this concrete protocol message

        let groupIdentifier: GroupV2.Identifier
        let pendingMemberIdentity: ObvCryptoIdentity
        
        init(coreProtocolMessage: CoreProtocolMessage, groupIdentifier: GroupV2.Identifier, pendingMemberIdentity: ObvCryptoIdentity) {
            self.coreProtocolMessage = coreProtocolMessage
            self.groupIdentifier = groupIdentifier
            self.pendingMemberIdentity = pendingMemberIdentity
        }

        var encodedInputs: [ObvEncoded] {
            return [groupIdentifier.obvEncode(), pendingMemberIdentity.obvEncode()]
        }

        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            do {
                self.coreProtocolMessage = CoreProtocolMessage(with: message)
                guard message.encodedInputs.count == 2 else { throw Self.makeError(message: "Unexpected number of encoded inputs in InitiateTargetedPingMessage") }
                let encodedGroupIdentifier = message.encodedInputs[0]
                let encodedPendingMemberIdentity = message.encodedInputs[1]
                self.groupIdentifier = try encodedGroupIdentifier.obvDecode()
                self.pendingMemberIdentity = try encodedPendingMemberIdentity.obvDecode()
            } catch {
                assertionFailure()
                throw error
            }
        }

    }
    
    
    // MARK: - AutoAcceptInvitationFromOwnedIdentityMessage
    
    struct AutoAcceptInvitationMessage: ConcreteProtocolMessage {
        
        let id: ConcreteProtocolMessageId = MessageId.autoAcceptInvitation
        let coreProtocolMessage: CoreProtocolMessage
        
        // Init when sending this message

        init(coreProtocolMessage: CoreProtocolMessage) {
            self.coreProtocolMessage = coreProtocolMessage
        }

        var encodedInputs: [ObvEncoded] { [] }
        
        // Init when receiving this message

        init(with message: ReceivedMessage) throws {
            self.coreProtocolMessage = CoreProtocolMessage(with: message)
        }

    }

}
