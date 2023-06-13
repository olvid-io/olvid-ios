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
import ObvTypes
import ObvMetaManager
import ObvCrypto
import OlvidUtils
import ObvEncoder

// MARK: - Protocol Steps

extension GroupV2Protocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case initiateGroupCreation = 0
        case checkIfGroupCreationCanBeFinalizedOnUploadGroupPhotoMessage = 1
        case checkIfGroupCreationCanBeFinalizedOnUploadGroupBlobMessage = 2
        case finalizeGroupCreation = 3
        case processInvitationOrMembersUpdateStep = 4
        case processDownloadedGroupData = 5
        case doNothingAfterDeleteBlobFromServer = 6
        case processPingOrPropagatedPing = 7
        case processInvitationDialogResponse = 8
        case notifyMembersOfRejection = 9
        case initiateBlobReDownload = 10
        case initiateGroupUpdate = 11
        case prepareBlobForGroupUpdate = 12
        case processGroupUpdateBlobUploadResponse = 13
        case processGroupUpdatePhotoUploadResponse = 14
        case finalizeGroupUpdate = 15
        case getKicked = 16
        case leaveGroup = 17
        case disbandGroup = 18
        case finalizeGroupDisband = 19
        case prepareBatchKeysMessage = 20
        case processBatchKeysMessage = 21
        case processInitiateUpdateKeycloakGroupsMessage = 300


        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            case .initiateGroupCreation:
                let step = InitiateGroupCreationStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .checkIfGroupCreationCanBeFinalizedOnUploadGroupPhotoMessage:
                let step = CheckIfGroupCreationCanBeFinalizedOnUploadGroupPhotoMessageStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .checkIfGroupCreationCanBeFinalizedOnUploadGroupBlobMessage:
                let step = CheckIfGroupCreationCanBeFinalizedOnUploadGroupBlobMessageStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .finalizeGroupCreation:
                let step = FinalizeGroupCreationStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .processInvitationOrMembersUpdateStep:
                if let step = ProcessInvitationOrMembersUpdateMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInvitationOrMembersUpdateBroadcastMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInvitationOrMembersUpdatePropagatedMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInvitationOrMembersUpdateMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInvitationOrMembersUpdateBroadcastMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInvitationOrMembersUpdatePropagatedMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInvitationOrMembersUpdateMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInvitationOrMembersUpdateBroadcastMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInvitationOrMembersUpdatePropagatedMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessBlobKeysAfterChannelCreationMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessBlobKeysAfterChannelCreationMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessBlobKeysAfterChannelCreationMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }
                
            case .processDownloadedGroupData:
                let step = ProcessDownloadedGroupDataStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .doNothingAfterDeleteBlobFromServer:
                let step = DoNothingAfterDeleteBlobFromServerStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .processPingOrPropagatedPing:
                if let step = ProcessPingStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagatedPingStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }

            case .processInvitationDialogResponse:
                if let step = ProcessDialogAcceptGroupV2InvitationMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagateInvitationDialogResponseMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessDialogAcceptGroupV2InvitationMessageFromDownloadingGroupBlobStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagateInvitationDialogResponseMessageFromDownloadingGroupBlobStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessDialogAcceptGroupV2InvitationMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagateInvitationDialogResponseMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }

            case .notifyMembersOfRejection:
                let step = NotifyMembersOfRejectionStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .initiateBlobReDownload:
                if let step = ProcessInitiateGroupReDownloadMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInvitationRejectedBroadcastMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInvitationRejectedBroadcastMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagateInvitationRejectedMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagateInvitationRejectedMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }

            case .initiateGroupUpdate:
                let step = InitiateGroupUpdateStep(from: concreteProtocol, and: receivedMessage)
                return step

            case .prepareBlobForGroupUpdate:
                let step = PrepareBlobForGroupUpdateStep(from: concreteProtocol, and: receivedMessage)
                return step

            case .processGroupUpdateBlobUploadResponse:
                let step = ProcessGroupUpdateBlobUploadResponseStep(from: concreteProtocol, and: receivedMessage)
                return step

            case .processGroupUpdatePhotoUploadResponse:
                let step = ProcessGroupUpdatePhotoUploadResponseStep(from: concreteProtocol, and: receivedMessage)
                return step

            case .finalizeGroupUpdate:
                let step = FinalizeGroupUpdateStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .getKicked:
                if let step = ProcessKickMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessKickMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessKickMessageFromDownloadingGroupBlobStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessKickMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessKickMessageFromWaitingForLockStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagatedKickMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagatedKickMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagatedKickMessageFromDownloadingGroupBlobStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagatedKickMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagatedKickMessageFromWaitingForLockStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }
                
            case .leaveGroup:
                if let step = ProcessInitiateGroupLeaveMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInitiateGroupLeaveMessageFromDownloadingGroupBlobStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInitiateGroupLeaveMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessInitiateGroupLeaveMessageFromWaitingForLockStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagatedGroupLeaveMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagatedGroupLeaveMessageFromDownloadingGroupBlobStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagatedGroupLeaveMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagatedGroupLeaveMessageFromWaitingForLockStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }

            case .disbandGroup:
                if let step = ProcessInitiateGroupDisbandMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagateGroupDisbandMessageFromConcreteProtocolInitialStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagateGroupDisbandMessageFromDownloadingGroupBlobStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagateGroupDisbandMessageFromINeedMoreSeedsStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = ProcessPropagateGroupDisbandMessageFromInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }
                
            case .finalizeGroupDisband:
                let step = FinalizeGroupDisbandStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .prepareBatchKeysMessage:
                let step = PrepareBatchKeysMessageStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .processBatchKeysMessage:
                let step = ProcessBatchKeysMessageStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .processInitiateUpdateKeycloakGroupsMessage:
                let step = ProcessInitiateUpdateKeycloakGroupsMessageStep(from: concreteProtocol, and: receivedMessage)
                return step

            }
        }
    }
    
    // MARK: - InitiateGroupCreationStep
    
    final class InitiateGroupCreationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateGroupCreationMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InitiateGroupCreationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let ownRawPermissions = receivedMessage.ownRawPermissions
            let otherGroupMembers = receivedMessage.otherGroupMembers
            let serializedGroupCoreDetails = receivedMessage.serializedGroupCoreDetails
            let photoURLManagedByTheApp = receivedMessage.photoURL // URL of the photo, typically, in app cache manager

            // Create the group in DB.
            // This call makes sure of the other group members are indeed contacts of the owned identity. It also create the first version of the administrators chain.
            // Note that created group starts in a "frozen" state.
            
            let values = try identityDelegate.createContactGroupV2AdministratedByOwnedIdentity(ownedIdentity,
                                                                                               serializedGroupCoreDetails: serializedGroupCoreDetails,
                                                                                               photoURL: photoURLManagedByTheApp,
                                                                                               ownRawPermissions: ownRawPermissions,
                                                                                               otherGroupMembers: otherGroupMembers,
                                                                                               within: obvContext)
            
            let groupIdentifier = values.groupIdentifier
            let groupAdminServerAuthenticationPublicKey = values.groupAdminServerAuthenticationPublicKey
            let serverPhotoInfo = values.serverPhotoInfo
            let encryptedServerBlob = values.encryptedServerBlob
            let photoURLManagedByTheIdentityManager = values.photoURL // URL of the photo managed by the identity manager (thus, distinct that the value in photoURL)
                        
            // If the group has a photo, upload it
            
            var uploadingPhoto = false
            if let photoURLManagedByTheIdentityManager = photoURLManagedByTheIdentityManager, let serverPhotoInfo = serverPhotoInfo {
                
                let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = UploadGroupPhotoMessage(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.putUserData(label: serverPhotoInfo.photoServerKeyAndLabel.label, dataURL: photoURLManagedByTheIdentityManager, dataKey: serverPhotoInfo.photoServerKeyAndLabel.key)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                uploadingPhoto = true
                
            }
            
            // Upload the encrypted blob
            
            do {
                let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = UploadGroupBlobMessage(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.createGroupBlob(groupIdentifier: groupIdentifier, serverAuthenticationPublicKey: groupAdminServerAuthenticationPublicKey, encryptedBlob: encryptedServerBlob)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state

            return UploadingCreatedGroupDataState(groupIdentifier: groupIdentifier, groupVersion: 0, waitingForBlobUpload: true, waitingForPhotoUpload: uploadingPhoto)
            
        }
        
    }

    
    // MARK: - CheckIfGroupCreationCanBeFinalizedStep
    
    class CheckIfGroupCreationCanBeFinalizedStep: ProtocolStep {
        
        private let startState: UploadingCreatedGroupDataState
        private let receivedMessage: ReceivedMessageType

        enum ReceivedMessageType {
            case uploadGroupPhoto(receivedMessage: UploadGroupPhotoMessage)
            case uploadGroupBlob(receivedMessage: UploadGroupBlobMessage)
        }

        init?(startState: UploadingCreatedGroupDataState, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            switch receivedMessage {
            case .uploadGroupPhoto(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .uploadGroupBlob(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
                        
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier = startState.groupIdentifier
            let groupVersion = startState.groupVersion
            var waitingForBlobUpload = startState.waitingForBlobUpload
            var waitingForPhotoUpload = startState.waitingForPhotoUpload

            switch receivedMessage {
            case .uploadGroupBlob(let receivedMessage):
                switch receivedMessage.blobUploadResult {
                case .success:
                    break
                case .permanentFailure:
                    // We were not able to upload the blob to the server --> roll back the group creation
                    try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                    return FinalState()
                case .temporaryFailure:
                    // We could try again. For now, we behave just like in the .permanentFailure case
                    try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                    return FinalState()
                }
                // If we reach this point, the blob was successfully uploaded on the server
                waitingForBlobUpload = false

            case .uploadGroupPhoto:
                waitingForPhotoUpload = false
            }
            
            // If we reach this point, we must check whether we are still waiting for the photo or blob upload.
            // If there is nothing left to upload, post a (local) message to initiate the finalization of the group creation
            
            if !waitingForBlobUpload && !waitingForPhotoUpload {
                let coreMessage = getCoreMessage(for: .Local(ownedIdentity: ownedIdentity))
                let concreteMessage = FinalizeGroupCreationMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate FinalizeGroupCreationMessage") }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state

            return UploadingCreatedGroupDataState(groupIdentifier: groupIdentifier, groupVersion: groupVersion, waitingForBlobUpload: waitingForBlobUpload, waitingForPhotoUpload: waitingForPhotoUpload)
            
        }
        
    }

    
    // MARK: CheckIfGroupCreationCanBeFinalizedOnUploadGroupPhotoMessageStep
    
    final class CheckIfGroupCreationCanBeFinalizedOnUploadGroupPhotoMessageStep: CheckIfGroupCreationCanBeFinalizedStep, TypedConcreteProtocolStep {
        
        let startState: UploadingCreatedGroupDataState
        let receivedMessage: UploadGroupPhotoMessage
        
        init?(startState: UploadingCreatedGroupDataState, receivedMessage: UploadGroupPhotoMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState, receivedMessage: .uploadGroupPhoto(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
                
        // The step execution is defined in the superclass
        
    }


    // MARK: CheckIfGroupPublicationCanBeFinalizedOnUploadGroupBlobMessageStep
    
    final class CheckIfGroupCreationCanBeFinalizedOnUploadGroupBlobMessageStep: CheckIfGroupCreationCanBeFinalizedStep, TypedConcreteProtocolStep {
        
        let startState: UploadingCreatedGroupDataState
        let receivedMessage: UploadGroupBlobMessage
        
        init?(startState: UploadingCreatedGroupDataState, receivedMessage: UploadGroupBlobMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState, receivedMessage: .uploadGroupBlob(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
                
        // The step execution is defined in the superclass

    }

    
    // MARK: - FinalizeGroupCreationStep
    
    final class FinalizeGroupCreationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: UploadingCreatedGroupDataState
        let receivedMessage: FinalizeGroupCreationMessage
        
        init?(startState: UploadingCreatedGroupDataState, receivedMessage: GroupV2Protocol.FinalizeGroupCreationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier = startState.groupIdentifier
            let groupVersion = startState.groupVersion
            let waitingForBlobUpload = startState.waitingForBlobUpload
            let waitingForPhotoUpload = startState.waitingForPhotoUpload
            
            assert(!waitingForBlobUpload && !waitingForPhotoUpload)

            // Request the blob keys to the identity manager
            
            let blobKeys: GroupV2.BlobKeys
            let groupAdminServerAuthenticationPrivateKey: PrivateKeyForAuthentication
            do {
                blobKeys = try identityDelegate.getGroupV2BlobKeysOfGroup(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                guard let key = blobKeys.groupAdminServerAuthenticationPrivateKey, blobKeys.blobMainSeed != nil else { throw Self.makeError(message: "key and main seed cannot be nil during group creation") }
                groupAdminServerAuthenticationPrivateKey = key
            } catch {
                try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                return FinalState()
            }
            
            // Fetch all group pending members and their permissions (used later).
            // For each pending member, determine the set of device UIDs with whom the current device has a confirmed Oblivious channel
            
            let pendingMembersAndPermissions: Set<GroupV2.IdentityAndPermissions>
            do {
                pendingMembersAndPermissions = try identityDelegate.getPendingMembersAndPermissionsOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            } catch {
                try deleteGroupBlobFromServer(groupIdentifier: groupIdentifier, groupAdminServerAuthenticationPrivateKey: groupAdminServerAuthenticationPrivateKey)
                try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                return FinalState()
            }
            let identitesOfPendingMembers = Set(pendingMembersAndPermissions.map({ $0.identity }))
            let deviceUidsOfRemoteIdentity = try channelDelegate.getDeviceUidsOfRemoteIdentitiesHavingConfirmedObliviousChannelWithTheCurrentDeviceOfOwnedIdentity(ownedIdentity, remoteIdentities: identitesOfPendingMembers, within: obvContext)

            // Make sure we have at least one confirmed oblivious channel with each pending member
            
            let aConfirmedChannelExistsWithEveryPendingMember = deviceUidsOfRemoteIdentity.allSatisfy({ !$0.value.isEmpty })
            guard aConfirmedChannelExistsWithEveryPendingMember else {
                // We have a problem, we invited a member with whom we do not have a channel...
                // Rollback everything and delete the group
                try deleteGroupBlobFromServer(groupIdentifier: groupIdentifier, groupAdminServerAuthenticationPrivateKey: groupAdminServerAuthenticationPrivateKey)
                try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                return FinalState()
            }
            
            // Compute the protocol instance UID for the invited members
            
            let invitationProtocolInstanceUid: UID
            do {
                invitationProtocolInstanceUid = try groupIdentifier.computeProtocolInstanceUid()
            } catch {
                try deleteGroupBlobFromServer(groupIdentifier: groupIdentifier, groupAdminServerAuthenticationPrivateKey: groupAdminServerAuthenticationPrivateKey)
                try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                return FinalState()
            }
            
            // Invite all the pending members
            
            do {
                try deviceUidsOfRemoteIdentity.forEach { (pendingMember, deviceUids) in
                    let coreMessage = CoreProtocolMessage(channelType: .ObliviousChannel(to: pendingMember, remoteDeviceUids: Array(deviceUids), fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true),
                                                          cryptoProtocolId: .GroupV2,
                                                          protocolInstanceUid: invitationProtocolInstanceUid)
                    let concreteMessage = InvitationOrMembersUpdateMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupVersion: groupVersion, blobKeys: blobKeys, notifiedDeviceUIDs: deviceUids)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
            } catch {
                try deleteGroupBlobFromServer(groupIdentifier: groupIdentifier, groupAdminServerAuthenticationPrivateKey: groupAdminServerAuthenticationPrivateKey)
                try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                return FinalState()
            }

            // Unfreeze the group
            
            try identityDelegate.unfreezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            
            // Return the new state

            return FinalState()
            
        }
        
        private func deleteGroupBlobFromServer(groupIdentifier: GroupV2.Identifier, groupAdminServerAuthenticationPrivateKey: PrivateKeyForAuthentication) throws {
            let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
            let concreteMessage = DeleteGroupBlobFromServerMessage(coreProtocolMessage: coreMessage)
            guard let signature = ObvSolveChallengeStruct.solveChallenge(.groupDelete, with: groupAdminServerAuthenticationPrivateKey, using: prng) else { assertionFailure(); throw Self.makeError(message: "Could not compute signature for deleting group") }
            let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.deleteGroupBlob(groupIdentifier: groupIdentifier, signature: signature)
            guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
        }

    }
    
    
    // MARK: - ProcessInvitationOrMembersUpdateStep
    
    class ProcessInvitationOrMembersUpdateStep: ProtocolStep {
        
        private let startState: StartStateType
        private let receivedMessage: ReceivedMessageType

        enum StartStateType {
            case initial(startState: ConcreteProtocolInitialState)
            case iNeedMoreSeed(startState: INeedMoreSeedsState)
            case invitationReceived(startState: InvitationReceivedState)
        }
        
        enum ReceivedMessageType {
            case invitationOrMembersUpdateMessage(receivedMessage: InvitationOrMembersUpdateMessage)
            case invitationOrMembersUpdateBroadcastMessage(receivedMessage: InvitationOrMembersUpdateBroadcastMessage)
            case invitationOrMembersUpdatePropagatedMessage(receivedMessage: InvitationOrMembersUpdatePropagatedMessage)
            case blobKeysAfterChannelCreationMessage(receivedMessage: BlobKeysAfterChannelCreationMessage)
        }
        
        init?(startState: StartStateType, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            switch (startState, receivedMessage) {
            case (.initial, .invitationOrMembersUpdateMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.initial, .invitationOrMembersUpdateBroadcastMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AsymmetricChannel,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.initial, .invitationOrMembersUpdatePropagatedMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.initial, .blobKeysAfterChannelCreationMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.iNeedMoreSeed, .invitationOrMembersUpdateMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.iNeedMoreSeed, .invitationOrMembersUpdateBroadcastMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AsymmetricChannel,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.iNeedMoreSeed, .invitationOrMembersUpdatePropagatedMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.iNeedMoreSeed, .blobKeysAfterChannelCreationMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.invitationReceived, .invitationOrMembersUpdateMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.invitationReceived, .invitationOrMembersUpdateBroadcastMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AsymmetricChannel,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.invitationReceived, .invitationOrMembersUpdatePropagatedMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.invitationReceived, .blobKeysAfterChannelCreationMessage(let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false
            
            // Determine an appropriate state to return if the received message should be discarded
            
            let returnedStateWhenDiscardingReceivedMessage: ConcreteProtocolState
            let dialogUuid: UUID
            let lastKnownOwnInvitationNonceAndOtherMembers: (nonce: Data, otherGroupMembers: Set<ObvCryptoIdentity>)?
            switch startState {
            case .initial:
                returnedStateWhenDiscardingReceivedMessage = FinalState()
                dialogUuid = UUID()
                lastKnownOwnInvitationNonceAndOtherMembers = nil
            case .iNeedMoreSeed(startState: let startState):
                returnedStateWhenDiscardingReceivedMessage = startState
                dialogUuid = startState.dialogUuid
                lastKnownOwnInvitationNonceAndOtherMembers = startState.lastKnownOwnInvitationNonceAndOtherMembers
            case .invitationReceived(startState: let startState):
                returnedStateWhenDiscardingReceivedMessage = startState
                dialogUuid = startState.dialogUuid
                let ownInvitationNonce: Data? = startState.serverBlob.getOwnPermissionsAndGroupInvitationNonce(ownedIdentity: ownedIdentity)?.ownGroupInvitationNonce
                let otherGroupMembers = Set(startState.serverBlob.getOtherGroupMembers(ownedIdentity: ownedIdentity).map({ $0.identity }))
                if let ownInvitationNonce = ownInvitationNonce {
                    lastKnownOwnInvitationNonceAndOtherMembers = (ownInvitationNonce, otherGroupMembers)
                } else {
                    lastKnownOwnInvitationNonceAndOtherMembers = nil
                }
            }

            let groupIdentifier: GroupV2.Identifier
            let notifiedDeviceUIDs: Set<UID>
            let propagateIfNecessary: Bool
            let groupVersion: Int
            let receivedBlobKeys: GroupV2.BlobKeys
            let inviter: ObvCryptoIdentity?
            switch receivedMessage {
            case .invitationOrMembersUpdateMessage(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                notifiedDeviceUIDs = receivedMessage.notifiedDeviceUIDs
                propagateIfNecessary = true
                groupVersion = receivedMessage.groupVersion
                receivedBlobKeys = receivedMessage.blobKeys
                guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                    assertionFailure()
                    return returnedStateWhenDiscardingReceivedMessage
                }
                inviter = remoteIdentity
            case .invitationOrMembersUpdateBroadcastMessage(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                notifiedDeviceUIDs = Set<UID>()
                propagateIfNecessary = true
                groupVersion = receivedMessage.groupVersion
                assert(receivedMessage.blobKeys.blobMainSeed == nil, "The blob main seed should never be sent on a broadcast channel")
                receivedBlobKeys = GroupV2.BlobKeys(blobMainSeed: nil, blobVersionSeed: receivedMessage.blobKeys.blobVersionSeed, groupAdminServerAuthenticationPrivateKey: receivedMessage.blobKeys.groupAdminServerAuthenticationPrivateKey)
                inviter = nil
            case .invitationOrMembersUpdatePropagatedMessage(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                notifiedDeviceUIDs = Set<UID>()
                propagateIfNecessary = false
                groupVersion = receivedMessage.groupVersion
                receivedBlobKeys = receivedMessage.blobKeys
                inviter = receivedMessage.inviter
            case .blobKeysAfterChannelCreationMessage(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                notifiedDeviceUIDs = Set<UID>()
                propagateIfNecessary = false
                groupVersion = receivedMessage.groupVersion
                receivedBlobKeys = receivedMessage.blobKeys
                inviter = receivedMessage.inviter
            }
            
            // Check that the protocol instance UID matches the group identifier

            guard protocolInstanceUid == (try? groupIdentifier.computeProtocolInstanceUid()) else {
                assertionFailure()
                return returnedStateWhenDiscardingReceivedMessage
            }
                        
            // If the sender could not send the message to all devices, propagate it to other owned devices, if any

            if propagateIfNecessary {
                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                let notNotifiedDeviceUIDs = otherDeviceUIDs.subtracting(notifiedDeviceUIDs)
                if !notNotifiedDeviceUIDs.isEmpty {
                    let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ObliviousChannel(to: ownedIdentity, remoteDeviceUids: Array(notNotifiedDeviceUIDs), fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true))
                    let concreteMessage = InvitationOrMembersUpdatePropagatedMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupVersion: groupVersion, blobKeys: receivedBlobKeys, inviter: inviter)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }
            
            // Check whether we already have a more recent group version invitation
            
            switch startState {
            case .initial, .iNeedMoreSeed:
                break
            case .invitationReceived(let startState):
                guard startState.serverBlob.groupVersion < groupVersion else {
                    return startState
                }
                
                // The information we are processing is more recent than the one we had.
                // Since the blob we have in an old version of the group blob, we freeze the invitation while we update the blob

                do {
                    
                    guard let (rawOwnPermissions, _) = startState.serverBlob.getOwnPermissionsAndGroupInvitationNonce(ownedIdentity: ownedIdentity) else {
                        // We are not part of the group, unexpected
                        assertionFailure()
                        return startState
                    }
                    
                    let ownPermissions = Set(rawOwnPermissions.compactMap { ObvGroupV2.Permission(rawValue: $0) })
                    let otherMembers = Set(startState.serverBlob.getOtherGroupMembers(ownedIdentity: ownedIdentity).map({ $0.toObvGroupV2IdentityAndPermissionsAndDetails(isPending: true) }))
                    
                    let trustedDetailsAndPhoto = ObvGroupV2.DetailsAndPhoto(serializedGroupCoreDetails: startState.serverBlob.serializedGroupCoreDetails, photoURLFromEngine: .none)
                    assert(groupIdentifier.category == .server, "If we are dealing with anything else than .server, we cannot always set serializedSharedSettings to nil bellow")
                    let group = ObvGroupV2(groupIdentifier: groupIdentifier.toObvGroupV2Identifier,
                                           ownIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity),
                                           ownPermissions: ownPermissions,
                                           otherMembers: otherMembers,
                                           trustedDetailsAndPhoto: trustedDetailsAndPhoto,
                                           publishedDetailsAndPhoto: nil,
                                           updateInProgress: false,
                                           serializedSharedSettings: nil,
                                           lastModificationTimestamp: nil)
                    let dialogType = ObvChannelDialogToSendType.freezeGroupV2Invite(inviter: ObvCryptoId(cryptoIdentity: startState.inviterIdentity), group: group)
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogFreezeGroupV2InvitationMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                    }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }

            }
            
            // Check whether the group already exists in DB
            
            let groupExistsInDB = try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)

            // Check if we already joined this group and have a larger group version
            // If this is the case, we can continue and freeze the group

            if groupExistsInDB {
                
                let groupVersionInDB = try identityDelegate.getVersionOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                
                if groupVersion < groupVersionInDB {
                    
                    // We already have a more recent version of this group, ignore the message
                    return returnedStateWhenDiscardingReceivedMessage
                    
                } else {
                    
                    // If the contact is pending on our side, we ping her so that, eventually, she becomes "not pending".
                    if let inviter {
                        let inviterIsPending = try identityDelegate.getPendingMembersAndPermissionsOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                            .map(\.identity)
                            .contains(where: { $0 == inviter })
                        if inviterIsPending {
                            let ownGroupInvitationNonce = try identityDelegate.getOwnGroupInvitationNonceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                            let challenge = ChallengeType.groupJoinNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, recipientIdentity: inviter)
                            let signature = try solveChallengeDelegate.solveChallenge(challenge, for: ownedIdentity, using: prng, within: obvContext)
                            let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: inviter, fromOwnedIdentity: ownedIdentity))
                            let concreteMessage = PingMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: signature, isReponse: false)
                            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                        }
                    }
                    
                    guard groupVersion > groupVersionInDB else {
                        return returnedStateWhenDiscardingReceivedMessage
                    }

                    try identityDelegate.freezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                    
                }
            }
            
            // Recover what was already collected, and augment it with what we received and what we already have in db
            
            var invitationCollectedData: GroupV2.InvitationCollectedData
            
            switch startState {
            case .initial:
                invitationCollectedData = GroupV2.InvitationCollectedData()
            case .iNeedMoreSeed(startState: let startState):
                invitationCollectedData = startState.invitationCollectedData
            case .invitationReceived(startState: let startState):
                invitationCollectedData = GroupV2.InvitationCollectedData()
                invitationCollectedData = invitationCollectedData.insertingBlobKeysCandidates(startState.blobKeys, fromInviter: startState.inviterIdentity)
            }
            
            if groupExistsInDB {
                let blobKeys = try identityDelegate.getGroupV2BlobKeysOfGroup(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                invitationCollectedData = invitationCollectedData.insertingBlobKeysCandidates(blobKeys, fromInviter: ownedIdentity) // We consider the main seed in DB comes from the owned identity
            }

            switch receivedMessage {
            case .invitationOrMembersUpdateMessage(let receivedMessage):
                let newBlobKeys = receivedMessage.blobKeys
                invitationCollectedData = invitationCollectedData.insertingBlobKeysCandidates(newBlobKeys, fromInviter: inviter)
            case .invitationOrMembersUpdateBroadcastMessage(let receivedMessage):
                let newBlobKeys = receivedMessage.blobKeys
                invitationCollectedData = invitationCollectedData.insertingBlobKeysCandidates(newBlobKeys, fromInviter: inviter)
            case .invitationOrMembersUpdatePropagatedMessage(let receivedMessage):
                let newBlobKeys = receivedMessage.blobKeys
                invitationCollectedData = invitationCollectedData.insertingBlobKeysCandidates(newBlobKeys, fromInviter: inviter)
            case .blobKeysAfterChannelCreationMessage(let receivedMessage):
                let newBlobKeys = receivedMessage.blobKeys
                invitationCollectedData = invitationCollectedData.insertingBlobKeysCandidates(newBlobKeys, fromInviter: inviter)
            }
            
            // Request the download a fresh version of the encrypted server blob and logs (group data) from the server
            
            let internalServerQueryIdentifier = Int.random(in: 0..<Int.max)
            do {
                let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = DownloadGroupBlobMessage(coreProtocolMessage: coreMessage, internalServerQueryIdentifier: internalServerQueryIdentifier)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.getGroupBlob(groupIdentifier: groupIdentifier)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
            return DownloadingGroupBlobState(groupIdentifier: groupIdentifier,
                                             dialogUuid: dialogUuid,
                                             invitationCollectedData: invitationCollectedData,
                                             expectedInternalServerQueryIdentifier: internalServerQueryIdentifier,
                                             lastKnownOwnInvitationNonceAndOtherMembers: lastKnownOwnInvitationNonceAndOtherMembers)
            
        }

    }

    
    // MARK: ConcreteProtocolInitialState / InvitationOrMembersUpdateMessage

    final class ProcessInvitationOrMembersUpdateMessageFromConcreteProtocolInitialStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InvitationOrMembersUpdateMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InvitationOrMembersUpdateMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState),
                       receivedMessage: .invitationOrMembersUpdateMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: ConcreteProtocolInitialState / InvitationOrMembersUpdateBroadcastMessage

    final class ProcessInvitationOrMembersUpdateBroadcastMessageFromConcreteProtocolInitialStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InvitationOrMembersUpdateBroadcastMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InvitationOrMembersUpdateBroadcastMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState),
                       receivedMessage: .invitationOrMembersUpdateBroadcastMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: ConcreteProtocolInitialState / InvitationOrMembersUpdatePropagatedMessage

    final class ProcessInvitationOrMembersUpdatePropagatedMessageFromConcreteProtocolInitialStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InvitationOrMembersUpdatePropagatedMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InvitationOrMembersUpdatePropagatedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState),
                       receivedMessage: .invitationOrMembersUpdatePropagatedMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: Process BlobKeysAfterChannelCreationMessage from ConcreteProtocolInitialState

    final class ProcessBlobKeysAfterChannelCreationMessageFromConcreteProtocolInitialStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: BlobKeysAfterChannelCreationMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.BlobKeysAfterChannelCreationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState),
                       receivedMessage: .blobKeysAfterChannelCreationMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: INeedMoreSeedsState / InvitationOrMembersUpdateMessage

    final class ProcessInvitationOrMembersUpdateMessageFromINeedMoreSeedsStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: InvitationOrMembersUpdateMessage

        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.InvitationOrMembersUpdateMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeed(startState: startState),
                       receivedMessage: .invitationOrMembersUpdateMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: INeedMoreSeedsState / InvitationOrMembersUpdateBroadcastMessage

    final class ProcessInvitationOrMembersUpdateBroadcastMessageFromINeedMoreSeedsStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: InvitationOrMembersUpdateBroadcastMessage

        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.InvitationOrMembersUpdateBroadcastMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeed(startState: startState),
                       receivedMessage: .invitationOrMembersUpdateBroadcastMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: INeedMoreSeedsState / InvitationOrMembersUpdatePropagatedMessage

    final class ProcessInvitationOrMembersUpdatePropagatedMessageFromINeedMoreSeedsStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: InvitationOrMembersUpdatePropagatedMessage

        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.InvitationOrMembersUpdatePropagatedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeed(startState: startState),
                       receivedMessage: .invitationOrMembersUpdatePropagatedMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }


    // MARK: Process BlobKeysAfterChannelCreationMessage from INeedMoreSeedsState

    final class ProcessBlobKeysAfterChannelCreationMessageFromINeedMoreSeedsStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: BlobKeysAfterChannelCreationMessage

        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.BlobKeysAfterChannelCreationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeed(startState: startState),
                       receivedMessage: .blobKeysAfterChannelCreationMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: InvitationReceivedState / InvitationOrMembersUpdateMessage

    final class ProcessInvitationOrMembersUpdateMessageFromInvitationReceivedStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: InvitationOrMembersUpdateMessage

        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.InvitationOrMembersUpdateMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceived(startState: startState),
                       receivedMessage: .invitationOrMembersUpdateMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: InvitationReceivedState / InvitationOrMembersUpdateBroadcastMessage

    final class ProcessInvitationOrMembersUpdateBroadcastMessageFromInvitationReceivedStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: InvitationOrMembersUpdateBroadcastMessage

        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.InvitationOrMembersUpdateBroadcastMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceived(startState: startState),
                       receivedMessage: .invitationOrMembersUpdateBroadcastMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: InvitationReceivedState / InvitationOrMembersUpdatePropagatedMessage

    final class ProcessInvitationOrMembersUpdatePropagatedMessageFromInvitationReceivedStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: InvitationOrMembersUpdatePropagatedMessage

        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.InvitationOrMembersUpdatePropagatedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceived(startState: startState),
                       receivedMessage: .invitationOrMembersUpdatePropagatedMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }
    
    
    // MARK: Process BlobKeysAfterChannelCreationMessage from InvitationReceivedState

    final class ProcessBlobKeysAfterChannelCreationMessageFromInvitationReceivedStateStep: ProcessInvitationOrMembersUpdateStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: BlobKeysAfterChannelCreationMessage

        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.BlobKeysAfterChannelCreationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceived(startState: startState),
                       receivedMessage: .blobKeysAfterChannelCreationMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }


    
    // MARK: - ProcessDownloadedGroupDataStep
    
    final class ProcessDownloadedGroupDataStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: DownloadingGroupBlobState
        let receivedMessage: DownloadGroupBlobMessage
        
        init?(startState: DownloadingGroupBlobState, receivedMessage: GroupV2Protocol.DownloadGroupBlobMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier = self.startState.groupIdentifier
            let dialogUuid = self.startState.dialogUuid
            let invitationCollectedData = self.startState.invitationCollectedData
            let lastKnownOwnInvitationNonceAndOtherMembers = self.startState.lastKnownOwnInvitationNonceAndOtherMembers
            let expectedInternalServerQueryIdentifier = startState.expectedInternalServerQueryIdentifier
            
            // Check that the received server query response corresponds to the one we were waiting for.
            // If not, we simply discard the message.
            
            guard expectedInternalServerQueryIdentifier == receivedMessage.internalServerQueryIdentifier else {
                return startState
            }
                        
            // Check the result of the download
            
            let encryptedServerBlob: EncryptedData
            let logEntries: Set<Data>
            let groupAdminPublicKey: PublicKeyForAuthentication
            switch receivedMessage.result {
            case .none:
                assertionFailure("This is not expected as the result is nil only when posting the server query from the protocol manager to the network fetch manager")
                return startState
            case .some(let result):
                switch result {
                case .blobWasDeletedFromServer:
                    
                    // If the group is deleted from server, we delete the group, and remove any related dialog and abort the protocol.
                    
                    try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                    
                    do {
                        let dialogType = ObvChannelDialogToSendType.delete
                        let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                        let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                        guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                            throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                        }
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    }

                    return FinalState()
                    
                case .blobCouldNotBeDownloaded:
                    
                    // This happens when the server returned a general error.
                    // We unfreeze the group and finish immediately

                    do {
                        let dialogType = ObvChannelDialogToSendType.delete
                        let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                        let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                        guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                            throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                        }
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    }

                    if try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext) {
                        try identityDelegate.unfreezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                    }
                    
                    return FinalState()
                    
                case .blobDownloaded(encryptedServerBlob: let _encryptedServerBlob, logEntries: let _logEntries, groupAdminPublicKey: let _groupAdminPublicKey):
                    
                    encryptedServerBlob = _encryptedServerBlob
                    logEntries = _logEntries
                    groupAdminPublicKey = _groupAdminPublicKey
                    
                }
            }
            
            // If we reach this point, we successfully downloaded an encrypted blob, log entries, and admin public key from the server.
            
            // We try to decrypt the encrypted blob
            
            guard let (inviterIdentity, serverBlobToConsolidate, blobKeys) = tryToDecrypt(encryptedServerBlob: encryptedServerBlob, using: invitationCollectedData, groupAdminPublicKey: groupAdminPublicKey, expectedGroupIdentifier: groupIdentifier) else {
                // We could not decrypt the blob, we need more keys
                return INeedMoreSeedsState(groupIdentifier: groupIdentifier,
                                           dialogUuid: dialogUuid,
                                           invitationCollectedData: invitationCollectedData,
                                           lastKnownOwnInvitationNonceAndOtherMembers: lastKnownOwnInvitationNonceAndOtherMembers)
            }
            
            // The log entries allows to "consolidate" the blob, i.e., to remove the leavers from the blob's group members

            let consolidatedServerBlob = serverBlobToConsolidate.consolidateWithLogEntries(groupIdentifier: groupIdentifier, logEntries)

            // Check that we are indeed part of the group and check whether we are an admin
            
            let ownedIdentityHasGroupAdminPermission: Bool
            let ownGroupInvitationNonce: Data
            let ownPermissions: Set<ObvGroupV2.Permission>
            do {
                guard let groupMember = consolidatedServerBlob.groupMembers.first(where: { $0.identity == ownedIdentity }) else {
                    // We are not part of the group
                    assertionFailure()
                    return FinalState()
                }
                ownedIdentityHasGroupAdminPermission = groupMember.hasGroupAdminPermission
                ownGroupInvitationNonce = groupMember.groupInvitationNonce
                ownPermissions = Set(groupMember.rawPermissions.compactMap({ GroupV2.Permission(rawValue: $0)?.toGroupV2Permission }))
            }
            
            // If we are an admin, make sure we have the group authentication private key
            
            if ownedIdentityHasGroupAdminPermission {
                guard blobKeys.groupAdminServerAuthenticationPrivateKey != nil else {
                    // Although we are indicated as an administrator of the group, we do not have access to the group administration private key
                    return INeedMoreSeedsState(groupIdentifier: groupIdentifier,
                                               dialogUuid: dialogUuid,
                                               invitationCollectedData: invitationCollectedData,
                                               lastKnownOwnInvitationNonceAndOtherMembers: lastKnownOwnInvitationNonceAndOtherMembers)
                }
            }
                                    
            // At this point, we have everything:
            // - the blob with a integrity checked administrators chain
            // - the inviter
            // - the keys
            // - the identities of the leavers
            // From here:
            // - Either we already have a group in DB (meaning that we already accepted to join the group) and we update it.
            // - Or we don't, and we send a user dialog to the owned identity to request whether she wants to join the group.
            
            let groupExistsInDB = try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            
            if groupExistsInDB {
                
                // Update the group in DB and get back the identities that are either new or which an update invite nonce.
                
                let identitiesToPing = try identityDelegate.updateGroupV2(withGroupWithIdentifier: groupIdentifier,
                                                                          of: ownedIdentity,
                                                                          newBlobKeys: blobKeys,
                                                                          consolidatedServerBlob: consolidatedServerBlob,
                                                                          groupUpdatedByOwnedIdentity: false,
                                                                          within: obvContext)
                
                // Send a ping to the identities returned by the identity manager. Doing so allow us to inform them that we agreed to be part of the group.

                if !identitiesToPing.isEmpty {
                    for identityToPing in identitiesToPing {
                        let challenge = ChallengeType.groupJoinNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, recipientIdentity: identityToPing)
                        let signature = try solveChallengeDelegate.solveChallenge(challenge, for: ownedIdentity, using: prng, within: obvContext)
                        let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: identityToPing, fromOwnedIdentity: ownedIdentity))
                        let concreteMessage = PingMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: signature, isReponse: false)
                        guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    }
                }

                // At this point, if we have a nil photoURL but have server photo info in the consolidated blob, we can launch a download if the photo is not available already.
                
                if let serverPhotoInfo = consolidatedServerBlob.serverPhotoInfo {
                    let photoDownloadNeeded = try identityDelegate.photoNeedsToBeDownloadedForGroupV2(withGroupWithIdentifier: groupIdentifier,
                                                                                                      of: ownedIdentity,
                                                                                                      serverPhotoInfo: serverPhotoInfo,
                                                                                                      within: obvContext)
                    if photoDownloadNeeded {
                        
                        // Launch a child protocol instance for downloading the photo. To do so, we post an appropriate message on the loopback channel. In this particular case, we do not need to "link" this protocol to the current protocol.
                        
                        let childProtocolInstanceUid = UID.gen(with: prng)
                        let coreMessage = getCoreMessageForOtherLocalProtocol(
                            otherCryptoProtocolId: .DownloadGroupV2Photo,
                            otherProtocolInstanceUid: childProtocolInstanceUid)
                        let childProtocolInitialMessage = DownloadGroupV2PhotoProtocol.InitialMessage(
                            coreProtocolMessage: coreMessage,
                            groupIdentifier: groupIdentifier,
                            serverPhotoInfo: serverPhotoInfo)
                        guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw Self.makeError(message: "Could not generate child protocol message") }
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

                    }
                }
                
                // Unfreeze the group
                
                try identityDelegate.unfreezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                
                // Return the new state

                return FinalState()
                
            }

            // If we reach this point, the group does not exist in DB, meaning we are yet to accept to be part of it.
            // Prompt the user to accept.

            do {
                let trustedDetailsAndPhoto = ObvGroupV2.DetailsAndPhoto(serializedGroupCoreDetails: consolidatedServerBlob.serializedGroupCoreDetails, photoURLFromEngine: .none)
                let otherMembers = Set(consolidatedServerBlob.getOtherGroupMembers(ownedIdentity: ownedIdentity).map({ $0.toObvGroupV2IdentityAndPermissionsAndDetails(isPending: true) }))
                assert(groupIdentifier.category == .server, "If we are dealing with anything else than .server, we cannot always set serializedSharedSettings to nil bellow")
                let group = ObvGroupV2(groupIdentifier: groupIdentifier.toObvGroupV2Identifier,
                                       ownIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity),
                                       ownPermissions: ownPermissions,
                                       otherMembers: otherMembers,
                                       trustedDetailsAndPhoto: trustedDetailsAndPhoto,
                                       publishedDetailsAndPhoto: nil,
                                       updateInProgress: false,
                                       serializedSharedSettings: nil,
                                       lastModificationTimestamp: nil)
                let dialogType = ObvChannelDialogToSendType.acceptGroupV2Invite(inviter: ObvCryptoId(cryptoIdentity: inviterIdentity), group: group)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogAcceptGroupV2InvitationMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state

            return InvitationReceivedState(groupIdentifier: groupIdentifier,
                                           dialogUuid: dialogUuid,
                                           inviterIdentity: inviterIdentity,
                                           serverBlob: consolidatedServerBlob,
                                           blobKeys: blobKeys)
            
        }

        
        /// This method uses the collected data seeds one by one until a pair allows to decrypt the encrypted blob.
        /// In case the owned identity is a group admin, it should have received at least one authentication private key. To determine the correct one, we look for a private received key matching the group admin public key.
        private func tryToDecrypt(encryptedServerBlob: EncryptedData, using invitationCollectedData: GroupV2.InvitationCollectedData, groupAdminPublicKey: PublicKeyForAuthentication, expectedGroupIdentifier: GroupV2.Identifier) -> (inviter: ObvCryptoIdentity, blob: GroupV2.ServerBlob, blobKeys: GroupV2.BlobKeys)? {
            
            for (inviter, blobMainSeed) in invitationCollectedData.inviterIdentityAndBlobMainSeedCandidates {
                for blobVersionSeed in invitationCollectedData.blobVersionSeedCandidates {

                    let blob: GroupV2.ServerBlob
                    do {
                        blob = try GroupV2.ServerBlob(encryptedServerBlob: encryptedServerBlob, blobMainSeed: blobMainSeed, blobVersionSeed: blobVersionSeed, expectedGroupIdentifier: expectedGroupIdentifier, solveChallengeDelegate: solveChallengeDelegate)
                    } catch {
                        // We could not decrypt the blob with these seeds. Wy try another pair of candidates.
                        debugPrint(error.localizedDescription)
                        continue
                    }

                    guard blob.administratorsChain.integrityChecked else {
                        assertionFailure("The ServerBlob should have checked the administrator chain integrity")
                        continue
                    }
                    
                    var groupAdminServerAuthenticationPrivateKey: PrivateKeyForAuthentication? = nil
                    for privateKey in invitationCollectedData.groupAdminServerAuthenticationPrivateKeyCandidates {
                        if Authentication.areKeysMatching(publicKey: groupAdminPublicKey, privateKey: privateKey) {
                            groupAdminServerAuthenticationPrivateKey = privateKey
                        }
                    }
                    
                    let blobKeys = GroupV2.BlobKeys(blobMainSeed: blobMainSeed, blobVersionSeed: blobVersionSeed, groupAdminServerAuthenticationPrivateKey: groupAdminServerAuthenticationPrivateKey)
                    
                    return (inviter, blob, blobKeys)
                    
                }
            }

            // If we reach this point, we could not decrypt the blob
            
            return nil
            
        }
        
    }

    
    // MARK: - DoNothingAfterDeleteBlobFromServerStep
    
    /// When requesting the deletion of a group (blob) from the server, we expect to receive a server query response indicating that the deletion was performed.
    /// There is nothing to do when receiving this response, so we define this very simple step that does nothing to gently handle the response.
    final class DoNothingAfterDeleteBlobFromServerStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InitiateGroupCreationStep
        let receivedMessage: DeleteGroupBlobFromServerMessage
        
        init?(startState: InitiateGroupCreationStep, receivedMessage: GroupV2Protocol.DeleteGroupBlobFromServerMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            return FinalState()
                            
        }

    }
    
    
    // MARK: - ProcessPingOrPropagatedPingStep
    
    class ProcessPingOrPropagatedPingStep: ProtocolStep {
        
        private let startState: ConcreteProtocolInitialState
        private let receivedMessage: ReceivedMessageType
        
        enum ReceivedMessageType {
            case pingMessage(receivedMessage: PingMessage)
            case propagatedPingMessage(receivedMessage: PropagatedPingMessage)
        }
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            switch receivedMessage {
            case .pingMessage(receivedMessage: let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AsymmetricChannel,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .propagatedPingMessage(receivedMessage: let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier: GroupV2.Identifier
            let groupInvitationNonce: Data
            let signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: Data
            let isReponse: Bool

            switch receivedMessage {
            case .pingMessage(receivedMessage: let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                groupInvitationNonce = receivedMessage.groupInvitationNonce
                signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity = receivedMessage.signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity
                isReponse = receivedMessage.isReponse
            case .propagatedPingMessage(receivedMessage: let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                groupInvitationNonce = receivedMessage.groupInvitationNonce
                signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity = receivedMessage.signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity
                isReponse = receivedMessage.isReponse
            }
            
            // Check that the received group identifier matches the protocol instance UID
            
            guard (try groupIdentifier.computeProtocolInstanceUid()) == protocolInstanceUid else {
                assertionFailure("It is highly probable that the step computing the ping did not properly compute the protocol instance uid")
                return FinalState()
            }
            
            // Check that the signature was not replayed by searching the DB
            
            guard try !GroupV2SignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity, within: obvContext) else {
                return FinalState()
            }

            // If the ping we received was not already propagated, we propagate it to our other own devices

            if case .pingMessage = receivedMessage {
                let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
                if numberOfOtherDevicesOfOwnedIdentity > 0 {
                    do {
                        let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                        let concreteProtocolMessage = PropagatedPingMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupInvitationNonce: groupInvitationNonce, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity, isReponse: isReponse)
                        guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                            throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                        }
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    } catch {
                        assertionFailure(error.localizedDescription)
                        // Continue anyway
                    }
                }
            }

            // Check that the group exists in DB (which means we accepted to join it). If it does not, return immediately.
            
            let groupExistsInDB = try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            guard groupExistsInDB else {
                return FinalState()
            }
            
            // Check that the nonce we received indeed corresponds to a member or pending member by requesting her identity to the identity manager

            let candidates = try identityDelegate.getAllOtherMembersOrPendingMembersOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, memberOrPendingMemberInvitationNonce: groupInvitationNonce, within: obvContext)
            guard !candidates.isEmpty else {
                // We could not find the member given the nonce we received. It might be the case that the group we have is not up to date. It will be shortly, and we will certainly send a fresh ping to that contact.
                // For now, we finish this protocol.
                return FinalState()
            }

            // Check the nonce signature
            
            guard let memberWhoSignedTheNonce = candidates.first(where: { candidate in
                ObvSolveChallengeStruct.checkResponse(signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity,
                                                      to: .groupJoinNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: groupInvitationNonce, recipientIdentity: ownedIdentity),
                                                      from: candidate.identity)
            }) else {
                // The signature is incorrect, nothing left to do
                return FinalState()
            }
            
            // If we reach this point, we received a valid signature on a valid nonce that allowed to identify the group member. We store it in DB to prevent replay attacks.
            
            _ = GroupV2SignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity, within: obvContext)
            
            // Move the pending member to the group members. Note that this call also creates a contact for the owned identity if required. If not, it adds the appropriate TrustOrigin for the existing contact.
            
            try identityDelegate.movePendingMemberToMembersOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, pendingMemberCryptoIdentity: memberWhoSignedTheNonce.identity, within: obvContext)
            
            // If the ping message is not a response, we respond by sending our own ping
            
            if !isReponse {
                let ownGroupInvitationNonce = try identityDelegate.getOwnGroupInvitationNonceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                let challenge = ChallengeType.groupJoinNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, recipientIdentity: memberWhoSignedTheNonce.identity)
                let signature = try solveChallengeDelegate.solveChallenge(challenge, for: ownedIdentity, using: prng, within: obvContext)
                let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: memberWhoSignedTheNonce.identity, fromOwnedIdentity: ownedIdentity))
                let concreteMessage = PingMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: signature, isReponse: true)
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state

            return FinalState()
            
        }
    }
    
    
    // MARK: ConcreteProtocolInitialState / PingMessage
    
    final class ProcessPingStep: ProcessPingOrPropagatedPingStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PingMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.PingMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState, receivedMessage: .pingMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass
        
    }

    
    // MARK: ConcreteProtocolInitialState / PropagatedPingMessage
    
    final class ProcessPropagatedPingStep: ProcessPingOrPropagatedPingStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagatedPingMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.PropagatedPingMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState, receivedMessage: .propagatedPingMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass
        
    }

    
    // MARK: - ProcessInvitationDialogResponseStep
    
    class ProcessInvitationDialogResponseStep: ProtocolStep {
        
        private let startState: StartStateType
        private let receivedMessage: ReceivedMessageType
        
        enum StartStateType {
            case invitationReceivedState(startState: InvitationReceivedState)
            case downloadingGroupBlobState(startState: DownloadingGroupBlobState)
            case iNeedMoreSeed(startState: INeedMoreSeedsState)
        }

        enum ReceivedMessageType {
            case dialogAcceptGroupV2InvitationMessage(receivedMessage: DialogAcceptGroupV2InvitationMessage)
            case propagateInvitationDialogResponseMessage(receivedMessage: PropagateInvitationDialogResponseMessage)
        }

        init?(startState: StartStateType, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            switch receivedMessage {
            case .dialogAcceptGroupV2InvitationMessage(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .propagateInvitationDialogResponseMessage(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false
            
            let groupIdentifier: GroupV2.Identifier
            let dialogUuid: UUID
            let returnedStateWhenDiscardingReceivedMessage: ConcreteProtocolState
            switch startState {
            case .invitationReceivedState(let startState):
                groupIdentifier = startState.groupIdentifier
                dialogUuid = startState.dialogUuid
                returnedStateWhenDiscardingReceivedMessage = startState
            case .downloadingGroupBlobState(let startState):
                groupIdentifier = startState.groupIdentifier
                dialogUuid = startState.dialogUuid
                returnedStateWhenDiscardingReceivedMessage = startState
            case .iNeedMoreSeed(let startState):
                groupIdentifier = startState.groupIdentifier
                dialogUuid = startState.dialogUuid
                returnedStateWhenDiscardingReceivedMessage = startState
            }

            let dialogUuidFromMessage: UUID?
            let invitationAccepted: Bool
            let propagated: Bool
            let propagatedOwnGroupInvitationNonce: Data?
            switch receivedMessage {
            case .dialogAcceptGroupV2InvitationMessage(let receivedMessage):
                dialogUuidFromMessage = receivedMessage.dialogUuid
                invitationAccepted = receivedMessage.invitationAccepted
                propagated = false
                propagatedOwnGroupInvitationNonce = nil
            case .propagateInvitationDialogResponseMessage(let receivedMessage):
                dialogUuidFromMessage = nil
                invitationAccepted = receivedMessage.invitationAccepted
                propagated = true
                propagatedOwnGroupInvitationNonce = receivedMessage.ownGroupInvitationNonce
            }

            // Check the dialog UUID (unless we are receiving a propagated response)
            
            guard dialogUuid == dialogUuidFromMessage || propagated else {
                
                assertionFailure()

                // Remove the dialog
                
                if let dialogUuidFromMessage = dialogUuidFromMessage {
                    let dialogType = ObvChannelDialogToSendType.delete
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuidFromMessage, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                    }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }

                return returnedStateWhenDiscardingReceivedMessage
            }
            
            // Make sure we are part of the group. Abort otherwise.
            // Get our own group invitation nonce from the server blob or from the last known value.
            // Do the same for the group members to notify
            
            let ownGroupInvitationNonce: Data
            let groupMembersToNotify: Set<ObvCryptoIdentity>
            do {
                switch startState {
                case .invitationReceivedState(let startState):

                    guard let nonce = startState.serverBlob.getOwnPermissionsAndGroupInvitationNonce(ownedIdentity: ownedIdentity)?.ownGroupInvitationNonce else {
                        // We are not part of the group, we abort
                        try postObvChannelDialogToSendTypeDelete(dialogUuid: dialogUuid)
                        return FinalState()
                    }

                    // We are part of the group since we can recover our own group invitation nonce

                    ownGroupInvitationNonce = nonce
                    groupMembersToNotify = Set(startState.serverBlob.getOtherGroupMembers(ownedIdentity: ownedIdentity).map({ $0.identity }))
                    
                case .downloadingGroupBlobState(let startState):

                    guard let lastKnownOwnInvitationNonceAndOtherMembers = startState.lastKnownOwnInvitationNonceAndOtherMembers else {
                        // We are not part of the group, we abort
                        try postObvChannelDialogToSendTypeDelete(dialogUuid: dialogUuid)
                        return FinalState()
                    }
                    
                    ownGroupInvitationNonce = lastKnownOwnInvitationNonceAndOtherMembers.nonce
                    groupMembersToNotify = lastKnownOwnInvitationNonceAndOtherMembers.otherGroupMembers
                    
                case .iNeedMoreSeed(let startState):
                    
                    guard let lastKnownOwnInvitationNonceAndOtherMembers = startState.lastKnownOwnInvitationNonceAndOtherMembers else {
                        // We are not part of the group, we abort
                        try postObvChannelDialogToSendTypeDelete(dialogUuid: dialogUuid)
                        return FinalState()
                    }
                    
                    ownGroupInvitationNonce = lastKnownOwnInvitationNonceAndOtherMembers.nonce
                    groupMembersToNotify = lastKnownOwnInvitationNonceAndOtherMembers.otherGroupMembers

                }
            }
            
            // Check that our group invitation nonce indicated in the server blob matches the one in the message (for propagated invitation response only)
            
            guard !propagated || propagatedOwnGroupInvitationNonce == ownGroupInvitationNonce else {
                // Propagated response for bad invitation nonce --> ignore the message
                return returnedStateWhenDiscardingReceivedMessage
            }
            
            // If we are not already dealing with a propagated invitation response, we propagate the response now to our other devices

            if !propagated {
                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !otherDeviceUIDs.isEmpty {
                    let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ObliviousChannel(to: ownedIdentity, remoteDeviceUids: Array(otherDeviceUIDs), fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true))
                    let concreteMessage = PropagateInvitationDialogResponseMessage(coreProtocolMessage: coreMessage, invitationAccepted: invitationAccepted, ownGroupInvitationNonce: ownGroupInvitationNonce)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }
            
            // If the owned identity did not accept the group invite, we put a signed log on the server, and prepare to notify other group members
            
            guard invitationAccepted else {
                
                do {
                    let leaveSignature = try solveChallengeDelegate.solveChallenge(.groupLeaveNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce), for: ownedIdentity, using: prng, within: obvContext)
                    let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                    let concreteMessage = PutGroupLogOnServerMessage(coreProtocolMessage: coreMessage)
                    let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.putGroupLog(groupIdentifier: groupIdentifier, querySignature: leaveSignature)
                    guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                do {
                    let dialogType = ObvChannelDialogToSendType.delete
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                    }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                return RejectingInvitationOrLeavingGroupState(groupIdentifier: groupIdentifier, groupMembersToNotify: groupMembersToNotify)
            }
            
            // If we reach this point, the invitation was accepted by the owned identity.
            // At this point, we cannot be in any other state than the invitationReceivedState since the only acceptable choice from the two other states is to reject the invitation.

            let blobKeys: GroupV2.BlobKeys
            let serverBlob: GroupV2.ServerBlob
            switch startState {
            case .invitationReceivedState(let startState):
                serverBlob = startState.serverBlob
                blobKeys = startState.blobKeys
            case .downloadingGroupBlobState, .iNeedMoreSeed:
                return returnedStateWhenDiscardingReceivedMessage
            }

            // The integrity of the administrators chain was already checked, so we force it now
            
            let serverBlobWithCheckedIntegrity = serverBlob.withForcedCheckedAdministratorsChainIntegrity()
                        
            // We create the group in database on the basis of the information we already have.
            
            try identityDelegate.createContactGroupV2JoinedByOwnedIdentity(ownedIdentity,
                                                                           groupIdentifier: groupIdentifier,
                                                                           serverBlob: serverBlobWithCheckedIntegrity,
                                                                           blobKeys: blobKeys,
                                                                           within: obvContext)
            
            // At this point, if we have a nil photoURL but have server photo info in the consolidated blob, we can launch a download if the photo is not available already.
            
            if let serverPhotoInfo = serverBlobWithCheckedIntegrity.serverPhotoInfo {
                let photoDownloadNeeded = try identityDelegate.photoNeedsToBeDownloadedForGroupV2(withGroupWithIdentifier: groupIdentifier,
                                                                                                  of: ownedIdentity,
                                                                                                  serverPhotoInfo: serverPhotoInfo,
                                                                                                  within: obvContext)
                if photoDownloadNeeded {
                    
                    // Launch a child protocol instance for downloading the photo. To do so, we post an appropriate message on the loopback channel. In this particular case, we do not need to "link" this protocol to the current protocol.
                    
                    let childProtocolInstanceUid = UID.gen(with: prng)
                    let coreMessage = getCoreMessageForOtherLocalProtocol(
                        otherCryptoProtocolId: .DownloadGroupV2Photo,
                        otherProtocolInstanceUid: childProtocolInstanceUid)
                    let childProtocolInitialMessage = DownloadGroupV2PhotoProtocol.InitialMessage(
                        coreProtocolMessage: coreMessage,
                        groupIdentifier: groupIdentifier,
                        serverPhotoInfo: serverPhotoInfo)
                    guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw Self.makeError(message: "Could not generate child protocol message") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

                }
            }

            // Ping all the members and pending members of this group. All those that actually already accepted will ping us back.
            // Note: we also send the ping in case we are dealing with a propagated accept, as we might have missed the ping response to the main device ping.
            
            do {
                let ownGroupInvitationNonce = try identityDelegate.getOwnGroupInvitationNonceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                let identitiesToPing = Set(serverBlobWithCheckedIntegrity.groupMembers.map({ $0.identity })).filter({ $0 != ownedIdentity })
                assert(!identitiesToPing.isEmpty)
                for identity in identitiesToPing {
                    let challenge = ChallengeType.groupJoinNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, recipientIdentity: identity)
                    let signature = try solveChallengeDelegate.solveChallenge(challenge, for: ownedIdentity, using: prng, within: obvContext)
                    let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: identity, fromOwnedIdentity: ownedIdentity))
                    let concreteMessage = PingMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: signature, isReponse: false)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }
            
            // Remove the dialog
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state

            return FinalState()
            
        }
        
        
        private func postObvChannelDialogToSendTypeDelete(dialogUuid: UUID) throws {
            let dialogType = ObvChannelDialogToSendType.delete
            let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
            let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
            guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
            }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
        }
        
        
    }

    
    // MARK: InvitationReceivedState / DialogAcceptGroupV2InvitationMessage

    final class ProcessDialogAcceptGroupV2InvitationMessageFromInvitationReceivedStateStep: ProcessInvitationDialogResponseStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: DialogAcceptGroupV2InvitationMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.DialogAcceptGroupV2InvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceivedState(startState: startState),
                       receivedMessage: .dialogAcceptGroupV2InvitationMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }
    
    
    // MARK: InvitationReceivedState / PropagateInvitationDialogResponseMessage

    final class ProcessPropagateInvitationDialogResponseMessageFromInvitationReceivedStateStep: ProcessInvitationDialogResponseStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: PropagateInvitationDialogResponseMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.PropagateInvitationDialogResponseMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceivedState(startState: startState),
                       receivedMessage: .propagateInvitationDialogResponseMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: DownloadingGroupBlobState / DialogAcceptGroupV2InvitationMessage

    final class ProcessDialogAcceptGroupV2InvitationMessageFromDownloadingGroupBlobStateStep: ProcessInvitationDialogResponseStep, TypedConcreteProtocolStep {
        
        let startState: DownloadingGroupBlobState
        let receivedMessage: DialogAcceptGroupV2InvitationMessage
        
        init?(startState: DownloadingGroupBlobState, receivedMessage: GroupV2Protocol.DialogAcceptGroupV2InvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .downloadingGroupBlobState(startState: startState),
                       receivedMessage: .dialogAcceptGroupV2InvitationMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }
    
    
    // MARK: DownloadingGroupBlobState / PropagateInvitationDialogResponseMessage

    final class ProcessPropagateInvitationDialogResponseMessageFromDownloadingGroupBlobStateStep: ProcessInvitationDialogResponseStep, TypedConcreteProtocolStep {
        
        let startState: DownloadingGroupBlobState
        let receivedMessage: PropagateInvitationDialogResponseMessage
        
        init?(startState: DownloadingGroupBlobState, receivedMessage: GroupV2Protocol.PropagateInvitationDialogResponseMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .downloadingGroupBlobState(startState: startState),
                       receivedMessage: .propagateInvitationDialogResponseMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: INeedMoreSeedsState / DialogAcceptGroupV2InvitationMessage

    final class ProcessDialogAcceptGroupV2InvitationMessageFromINeedMoreSeedsStateStep: ProcessInvitationDialogResponseStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: DialogAcceptGroupV2InvitationMessage
        
        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.DialogAcceptGroupV2InvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeed(startState: startState),
                       receivedMessage: .dialogAcceptGroupV2InvitationMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }
    
    
    // MARK: INeedMoreSeedsState / PropagateInvitationDialogResponseMessage

    final class ProcessPropagateInvitationDialogResponseMessageFromINeedMoreSeedsStateStep: ProcessInvitationDialogResponseStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: PropagateInvitationDialogResponseMessage
        
        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.PropagateInvitationDialogResponseMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeed(startState: startState),
                       receivedMessage: .propagateInvitationDialogResponseMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: - NotifyMembersOfRejectionStep
    
    final class NotifyMembersOfRejectionStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: RejectingInvitationOrLeavingGroupState
        let receivedMessage: PutGroupLogOnServerMessage
        
        init?(startState: RejectingInvitationOrLeavingGroupState, receivedMessage: GroupV2Protocol.PutGroupLogOnServerMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false
            
            let groupIdentifier = startState.groupIdentifier
            let groupMembersToNotify = startState.groupMembersToNotify
            
            for groupMember in groupMembersToNotify {
                // Send rejection update message
                let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: groupMember, fromOwnedIdentity: ownedIdentity))
                let concreteMessage = InvitationRejectedBroadcastMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier)
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            return FinalState()
                            
        }

    }
    
    
    // MARK: - InitiateBlobReDownloadStep
    
    class InitiateBlobReDownloadStep: ProtocolStep {
        
        private let startState: StartStateType
        private let receivedMessage: ReceivedMessageType
        
        enum StartStateType {
            case initial(startState: ConcreteProtocolInitialState)
            case invitationReceived(startState: InvitationReceivedState)
        }

        enum ReceivedMessageType {
            case initiateGroupReDownload(receivedMessage: InitiateGroupReDownloadMessage)
            case invitationRejectedBroadcast(receivedMessage: InvitationRejectedBroadcastMessage)
            case propagateInvitationRejected(receivedMessage: PropagateInvitationRejectedMessage)
        }

        init?(startState: StartStateType, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            switch receivedMessage {
            case .initiateGroupReDownload(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .invitationRejectedBroadcast(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AsymmetricChannel,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .propagateInvitationRejected(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let concreteStartState: ConcreteProtocolState
            let dialogUuid: UUID
            switch startState {
            case .initial(let startState):
                concreteStartState = startState
                dialogUuid = UUID()
            case .invitationReceived(let startState):
                concreteStartState = startState
                dialogUuid = startState.dialogUuid
            }
            
            let groupIdentifier: GroupV2.Identifier
            let propagationNeeded: Bool
            let pingAllOtherMembersIfInitialState: Bool
            switch receivedMessage {
            case .initiateGroupReDownload(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                propagationNeeded = true
                pingAllOtherMembersIfInitialState = true
            case .invitationRejectedBroadcast(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                propagationNeeded = true
                pingAllOtherMembersIfInitialState = false
            case .propagateInvitationRejected(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                propagationNeeded = false
                pingAllOtherMembersIfInitialState = false
            }
            
            // Check that the protocol instance UID matches the group identifier

            guard protocolInstanceUid == (try? groupIdentifier.computeProtocolInstanceUid()) else {
                assertionFailure()
                return concreteStartState
            }

            // Propagate the message if needed
            
            if propagationNeeded {
                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !otherDeviceUIDs.isEmpty {
                    let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ObliviousChannel(to: ownedIdentity, remoteDeviceUids: Array(otherDeviceUIDs), fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true))
                    let concreteMessage = PropagateInvitationRejectedMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }
            
            // Make sure we are considering a server group (otherwise, re-downloading the blob makes no sense)
            
            guard groupIdentifier.category == .server else {
                assertionFailure()
                return FinalState()
            }
            
            // If the start state is the initial state, we don't have any information at hand for re-downloading the blob.
            // In that case, we query the identity manager to get the blob keys and set the inviter to the owned identity.
            // We also freeze the group since we will download a new version.
            // If the start state is the `InvitationReceivedState`, we use the information contained in the state for the blob keys and inviter.
            // We also freeze the invitation dialog.
            
            let blobKeys: GroupV2.BlobKeys
            let inviterIdentity: ObvCryptoIdentity
            let lastKnownOwnInvitationNonceAndOtherMembers: (nonce: Data, otherGroupMembers: Set<ObvCryptoIdentity>)?

            switch startState {
                
            case .initial:
                                
                // Fetch the blob keys from DB and set the inviter to the owned identity
                
                blobKeys = try identityDelegate.getGroupV2BlobKeysOfGroup(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                inviterIdentity = ownedIdentity
                
                // Since we will be downloading a new blob, we freeze the group
                
                try identityDelegate.freezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                
                // We don't need our own nonce
                
                lastKnownOwnInvitationNonceAndOtherMembers = nil
                                
                // Ping all the members and pending members of this group if required. This allows to make sure we are not indicated as "pending" anymore on other group member devices.
                // All those that actually already accepted will ping us back.
                
                if pingAllOtherMembersIfInitialState {
                    let ownGroupInvitationNonce = try identityDelegate.getOwnGroupInvitationNonceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                    let identitiesToPing = try identityDelegate.getAllOtherMembersOrPendingMembersOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext).map(\.identity)
                    for identity in identitiesToPing {
                        let challenge = ChallengeType.groupJoinNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, recipientIdentity: identity)
                        let signature = try solveChallengeDelegate.solveChallenge(challenge, for: ownedIdentity, using: prng, within: obvContext)
                        let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: identity, fromOwnedIdentity: ownedIdentity))
                        let concreteMessage = PingMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: signature, isReponse: false)
                        guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    }
                }

            case .invitationReceived(let startState):

                // Get the blob keys from the `InvitationReceivedState` (the group does not exist in DB yet)
                
                blobKeys = startState.blobKeys
                inviterIdentity = startState.inviterIdentity
                
                // Freeze the dialog
                
                if let rawOwnPermissions = startState.serverBlob.getOwnPermissionsAndGroupInvitationNonce(ownedIdentity: ownedIdentity)?.rawOwnPermissions {
                    let ownPermissions = Set(rawOwnPermissions.compactMap({ GroupV2.Permission(rawValue: $0)?.toGroupV2Permission }))
                    assert(ownPermissions.count == ownPermissions.count)
                    let otherMembers = Set(startState.serverBlob.getOtherGroupMembers(ownedIdentity: ownedIdentity).map({ $0.toObvGroupV2IdentityAndPermissionsAndDetails(isPending: true) }))
                    let trustedDetailsAndPhoto = ObvGroupV2.DetailsAndPhoto(serializedGroupCoreDetails: startState.serverBlob.serializedGroupCoreDetails, photoURLFromEngine: .none)
                    assert(groupIdentifier.category == .server, "If we are dealing with anything else than .server, we cannot always set serializedSharedSettings to nil bellow")
                    let group = ObvGroupV2(groupIdentifier: groupIdentifier.toObvGroupV2Identifier,
                                           ownIdentity: ObvCryptoId(cryptoIdentity: ownedIdentity),
                                           ownPermissions: ownPermissions,
                                           otherMembers: otherMembers,
                                           trustedDetailsAndPhoto: trustedDetailsAndPhoto,
                                           publishedDetailsAndPhoto: nil,
                                           updateInProgress: false,
                                           serializedSharedSettings: nil,
                                           lastModificationTimestamp: nil)
                    let dialogType = ObvChannelDialogToSendType.freezeGroupV2Invite(inviter: ObvCryptoId(cryptoIdentity: startState.inviterIdentity), group: group)
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogFreezeGroupV2InvitationMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                    }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Store the own invitation nonce and other group members identities
                
                if let nonce = startState.serverBlob.getOwnPermissionsAndGroupInvitationNonce(ownedIdentity: ownedIdentity)?.ownGroupInvitationNonce {
                    let otherMembers = Set(startState.serverBlob.getOtherGroupMembers(ownedIdentity: ownedIdentity).map({ $0.identity }))
                    lastKnownOwnInvitationNonceAndOtherMembers = (nonce, otherMembers)
                } else {
                    lastKnownOwnInvitationNonceAndOtherMembers = nil
                }
                
            }

            // Request the download a fresh version of the encrypted server blob and logs (group data) from the server

            let internalServerQueryIdentifier = Int.random(in: 0..<Int.max)
            do {
                let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = DownloadGroupBlobMessage(coreProtocolMessage: coreMessage, internalServerQueryIdentifier: internalServerQueryIdentifier)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.getGroupBlob(groupIdentifier: groupIdentifier)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Create an initial version of the invitation collected data
            
            let invitationCollectedData = GroupV2.InvitationCollectedData().insertingBlobKeysCandidates(blobKeys, fromInviter: inviterIdentity)
            
            // Return the new state

            return DownloadingGroupBlobState(groupIdentifier: groupIdentifier,
                                             dialogUuid: dialogUuid,
                                             invitationCollectedData: invitationCollectedData,
                                             expectedInternalServerQueryIdentifier: internalServerQueryIdentifier,
                                             lastKnownOwnInvitationNonceAndOtherMembers: lastKnownOwnInvitationNonceAndOtherMembers)

        }
        
    }

    
    
    // MARK: Process InitiateGroupReDownloadMessage from ConcreteProtocolInitialState

    final class ProcessInitiateGroupReDownloadMessageFromConcreteProtocolInitialStateStep: InitiateBlobReDownloadStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateGroupReDownloadMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InitiateGroupReDownloadMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState), receivedMessage: .initiateGroupReDownload(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // We do not process the InitiateGroupReDownloadMessage from the InvitationReceivedState

    
    // MARK: Process InvitationRejectedBroadcastMessage from ConcreteProtocolInitialState

    final class ProcessInvitationRejectedBroadcastMessageFromConcreteProtocolInitialStateStep: InitiateBlobReDownloadStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InvitationRejectedBroadcastMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InvitationRejectedBroadcastMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState), receivedMessage: .invitationRejectedBroadcast(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: Process InvitationRejectedBroadcastMessage from InvitationReceivedState

    final class ProcessInvitationRejectedBroadcastMessageFromInvitationReceivedStateStep: InitiateBlobReDownloadStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: InvitationRejectedBroadcastMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.InvitationRejectedBroadcastMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceived(startState: startState), receivedMessage: .invitationRejectedBroadcast(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagateInvitationRejectedMessage from ConcreteProtocolInitialState

    final class ProcessPropagateInvitationRejectedMessageFromConcreteProtocolInitialStateStep: InitiateBlobReDownloadStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateInvitationRejectedMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.PropagateInvitationRejectedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState), receivedMessage: .propagateInvitationRejected(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagateInvitationRejectedMessage from InvitationReceivedState

    final class ProcessPropagateInvitationRejectedMessageFromInvitationReceivedStateStep: InitiateBlobReDownloadStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: PropagateInvitationRejectedMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.PropagateInvitationRejectedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceived(startState: startState), receivedMessage: .propagateInvitationRejected(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: - InitiateGroupUpdateStep
    
    final class InitiateGroupUpdateStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateGroupUpdateMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InitiateGroupUpdateMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier = receivedMessage.groupIdentifier
            let changeset = receivedMessage.changeset

            // Check that the protocol instance UID is appropriate for this groupIdentifier
            
            guard try groupIdentifier.computeProtocolInstanceUid() == self.protocolInstanceUid else {
                notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, flowId: obvContext.flowId)
                return FinalState()
            }
            
            // Check that the group exists in DB
            
            guard try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext) else {
                notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, flowId: obvContext.flowId)
                return FinalState()
            }
            
            // Get the blob keys and check that we do have the group admin private key
            
            let blobKeys = try identityDelegate.getGroupV2BlobKeysOfGroup(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            guard let groupAdminServerAuthenticationPrivateKey = blobKeys.groupAdminServerAuthenticationPrivateKey else {
                // We do not have the group admin server authentication private key --> we cannot sign the blob
                notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, flowId: obvContext.flowId)
                return FinalState()
            }
                        
            // Create and sign a server nonce allowing to request a lock
            
            let lockNonce = prng.genBytes(count: ObvConstants.groupLockNonceLength)
            let challenge = ChallengeType.groupLockNonce(lockNonce: lockNonce)
            guard let lockNonceSignature = ObvSolveChallengeStruct.solveChallenge(challenge, with: groupAdminServerAuthenticationPrivateKey, using: prng) else {
                // We could not solve the challenge --> We cannot update the blob
                notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, flowId: obvContext.flowId)
                return FinalState()
            }

            // Request a group lock to the server
            
            let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
            let concreteMessage = RequestServerLockMessage(coreProtocolMessage: coreMessage)
            let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.requestGroupBlobLock(groupIdentifier: groupIdentifier, lockNonce: lockNonce, signature: lockNonceSignature)
            guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // Since we will be waiting for "a long time", we freeze the group
            
            try identityDelegate.freezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            
            // Since we will be waiting for "a long time", we create a local copy of the photo contained in the changeset if there is one.
            // If there is no photo, and if the updated group already has a trusted photo, we get the photo from the identity manager and behaves just as if the user decided to update the photo.
            // This will allow to "move" the photo on the server from the "previous" administrator space to the one of the local own identity (the "new" administrator).
            
            let updatedChangeset: ObvGroupV2.Changeset
            do {
                if changeset.containsDeletePhotoChange {
                    // The user requested to delete the group photo. We keep the changeset as is.
                    updatedChangeset = changeset
                } else if let photoURLWithinApp = changeset.photoURL {
                    // The user requested a change of the group photo. We create a local copy and update the changeset with the new photo URL.
                    if let photoURLWithinProtocolManager = createLocalCopyOfFile(at: photoURLWithinApp) {
                        let groupPhotoChange = ObvGroupV2.Change.groupPhoto(photoURL: photoURLWithinProtocolManager)
                        let updatedChanges = changeset.changes.filter({ !$0.isGroupPhotoChange }).union(Set([groupPhotoChange]))
                        updatedChangeset = try ObvGroupV2.Changeset(changes: updatedChanges)
                    } else {
                        assertionFailure()
                        updatedChangeset = changeset
                    }
                } else {
                    if let existingPhotoURLAndUploaderWithinIdentityManager = try identityDelegate.getTrustedPhotoURLAndUploaderOfObvGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext), existingPhotoURLAndUploaderWithinIdentityManager.uploader != ownedIdentity {
                        // The group already has a trusted photo (that was uploaded by somebody else) and the user did not request a change.
                        // We create a local copy of the photo (local to the protocol manager)
                        if let photoURLWithinProtocolManager = createLocalCopyOfFile(at: existingPhotoURLAndUploaderWithinIdentityManager.url) {
                            // We manually insert a change to refresh the photo on the server
                            let groupPhotoChange = ObvGroupV2.Change.groupPhoto(photoURL: photoURLWithinProtocolManager)
                            let updatedChanges = changeset.changes.union(Set([groupPhotoChange]))
                            updatedChangeset = try ObvGroupV2.Changeset(changes: updatedChanges)
                        } else {
                            assertionFailure()
                            updatedChangeset = changeset
                        }
                    } else {
                        // The group has no trusted photo (or the existing photo was previously uploaded by us) and the user did not request a change. There is nothing to do.
                        updatedChangeset = changeset
                    }
                }
            }
            
            // Return the new state
            
            return WaitingForLockState(groupIdentifier: groupIdentifier, changeset: updatedChangeset, lockNonce: lockNonce, failedUploadCounter: 0)
            
        }
        
        
        private func notifyThatTheGroupUpdateFailed(groupIdentifier: GroupV2.Identifier, flowId: FlowIdentifier) {
            ObvProtocolNotification.groupV2UpdateDidFail(ownedIdentity: ownedIdentity, appGroupIdentifier: groupIdentifier.toObvGroupV2Identifier.appGroupIdentifier, flowId: flowId)
                .postOnBackgroundQueue(within: notificationDelegate)
        }
        
        
        private func createLocalCopyOfFile(at url: URL) -> URL? {
            guard FileManager.default.fileExists(atPath: url.path) else {
                assertionFailure()
                return nil
            }
            let localURL = delegateManager.uploadingUserData.appendingPathComponent(UUID().uuidString)
            guard !FileManager.default.fileExists(atPath: localURL.path) else { assertionFailure(); return nil }
            do {
                try FileManager.default.linkItem(at: url, to: localURL)
                return localURL
            } catch {
                do {
                    try FileManager.default.copyItem(at: url, to: localURL)
                    return localURL
                } catch let error {
                    assertionFailure(error.localizedDescription)
                    return nil
                }
            }
        }
        
    }

    
    // MARK: - PrepareBlobForGroupUpdateStep
    
    final class PrepareBlobForGroupUpdateStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForLockState
        let receivedMessage: RequestServerLockMessage
        
        init?(startState: WaitingForLockState, receivedMessage: GroupV2Protocol.RequestServerLockMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false
            
            let groupIdentifier = startState.groupIdentifier
            let changeset = startState.changeset
            let lockNonce = startState.lockNonce
            let failedUploadCounter = startState.failedUploadCounter
            
            // Check that the group exists in DB
            
            guard try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext) else {
                try unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, within: obvContext)
                return FinalState()
            }

            // If the received message does not contain the expected data (blob, log entries and group admin public key), it means that the blob was deleted from server or that some other error occured.
            // In that case, there is nothing we can do.
            
            let encryptedServerBlob: EncryptedData
            let logEntries: Set<Data>
            let currentGroupAdminServerAuthenticationPublicKey: PublicKeyForAuthentication
            switch receivedMessage.result {
            case .none:
                assertionFailure("This is not expected as the result is nil only when posting the server query from the protocol manager to the network fetch manager")
                try unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, within: obvContext)
                return FinalState()
            case .some(let result):
                switch result {
                case .permanentFailure:
                    try unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, within: obvContext)
                    return FinalState()
                case .lockObtained(let _encryptedServerBlob, let _logEntries, let _groupAdminPublicKey):
                    encryptedServerBlob = _encryptedServerBlob
                    logEntries = _logEntries
                    currentGroupAdminServerAuthenticationPublicKey = _groupAdminPublicKey
                }
            }
            
            // If we reach this point, we successfully downloaded an encrypted blob, log entries, and admin public key from the server.
            
            // Get the BlobKeys from the identity manager (should succeed since we are an admin)
            
            let blobKeys: GroupV2.BlobKeys
            do {
                blobKeys = try identityDelegate.getGroupV2BlobKeysOfGroup(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            } catch {
                try unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, within: obvContext)
                return FinalState()
            }
            
            guard let blobMainSeed = blobKeys.blobMainSeed else {
                try unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, within: obvContext)
                return FinalState()
            }
            
            guard let currentGroupAdminServerAuthenticationPrivateKey = blobKeys.groupAdminServerAuthenticationPrivateKey else {
                try unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, within: obvContext)
                return FinalState()
            }

            // We try to decrypt the encrypted blob
            
            guard let serverBlobToConsolidate = tryToDecrypt(encryptedServerBlob: encryptedServerBlob, blobMainSeed: blobMainSeed, blobVersionSeed: blobKeys.blobVersionSeed, expectedGroupIdentifier: groupIdentifier) else {
                // We could not decrypt the blob received from the server.
                // This typically happens if the group was updated by some other admin but we are not aware of it yet.
                // Indeed, in that case, our version seed is outdated and the decryption necessarily fails.
                // For now, we fail the step and hope we will receive the new version seed soon.
                try unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, within: obvContext)
                return FinalState()
            }
            
            // The log entries allows to "consolidate" the blob, i.e., to remove the leavers from the blob's group members.
            // We also merge the changeset requested by the user.

            let previousServerBlob = serverBlobToConsolidate.consolidateWithLogEntries(groupIdentifier: groupIdentifier, logEntries)
            let newServerBlob = try previousServerBlob.consolidateWithChangeset(changeset,
                                                                                ownedIdentity: ownedIdentity,
                                                                                identityDelegate: identityDelegate,
                                                                                prng: prng,
                                                                                solveChallengeDelegate: solveChallengeDelegate,
                                                                                within: obvContext)
            
            // Check that we have a channel with all the members that we invite.
            // Also check that we have a channel with the members to whom we will need to send a new invitation nonce
            
            do {
                let membersToInvite = newServerBlob.groupMembers.subtracting(previousServerBlob.groupMembers)
                for memberToInvite in membersToInvite {
                    guard try channelDelegate.aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: memberToInvite.identity, within: obvContext) else {
                        // We are trying to invite a member with whom we have no oblivious channel. We discard the changeset and notify the app.
                        try unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, within: obvContext)
                        return FinalState()
                    }
                }
                var membersWithNewInvitationSeed = Set<ObvCryptoIdentity>()
                for member in newServerBlob.groupMembers {
                    if previousServerBlob.groupMembers.first(where: { $0.identity == member.identity && $0.groupInvitationNonce != member.groupInvitationNonce }) != nil {
                        membersWithNewInvitationSeed.insert(member.identity)
                    }
                }
                for membersWithNewInvitationSeed in membersWithNewInvitationSeed {
                    guard try channelDelegate.aConfirmedObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: membersWithNewInvitationSeed, within: obvContext) else {
                        // We are trying to invite a member with whom we have no oblivious channel. We discard the changeset and notify the app.
                        try unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, within: obvContext)
                        return FinalState()
                    }
                }
            }
            
            // If an administrator was demoted, we want to update the group admin authentication key pair

            let updatedServerAuthenticationKeys: (publicKey: PublicKeyForAuthentication, privateKey: PrivateKeyForAuthentication)?
            if previousServerBlob.administratorsChain.numberOfBlocks != newServerBlob.administratorsChain.numberOfBlocks && newServerBlob.administratorsChain.anAdministratorWasDemotedInTheLastUpdate {
                updatedServerAuthenticationKeys = ObvCryptoSuite.sharedInstance.authentication().generateKeyPair(with: prng)
            } else {
                updatedServerAuthenticationKeys = nil
            }

            // We generate a new version seed and use it to encrypt the consolidated blob
            
            let updatedBlobVersionSeed = prng.genSeed()
            let encryptedConsolidatedServerBlob = try newServerBlob.signThenEncrypt(ownedIdentity: ownedIdentity,
                                                                                    blobMainSeed: blobMainSeed,
                                                                                    blobVersionSeed: updatedBlobVersionSeed,
                                                                                    solveChallengeDelegate: solveChallengeDelegate,
                                                                                    with: prng,
                                                                                    within: obvContext)
            
            // Solve the challenge required by the server when updating a blob
            
            let encodedServerAdminPublicKey = (updatedServerAuthenticationKeys?.publicKey ?? currentGroupAdminServerAuthenticationPublicKey).obvEncode()
            let challenge = ChallengeType.groupUpdate(lockNonce: lockNonce, encryptedBlob: encryptedConsolidatedServerBlob, encodedServerAdminPublicKey: encodedServerAdminPublicKey)
            guard let solveChallengeSignature = ObvSolveChallengeStruct.solveChallenge(challenge, with: currentGroupAdminServerAuthenticationPrivateKey, using: prng) else {
                try unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, within: obvContext)
                return FinalState()
            }

            // Upload the encrypted blob (using the same nonce we created when locking the group on the server)
            
            do {
                let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = UploadGroupBlobMessage(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.updateGroupBlob(
                    groupIdentifier: groupIdentifier,
                    encodedServerAdminPublicKey: encodedServerAdminPublicKey,
                    encryptedBlob: encryptedConsolidatedServerBlob,
                    lockNonce: lockNonce,
                    signature: solveChallengeSignature)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
            return UploadingUpdatedGroupBlobState(groupIdentifier: groupIdentifier,
                                                  changeset: changeset,
                                                  previousServerBlob: previousServerBlob,
                                                  uploadedServerBlob: newServerBlob,
                                                  updatedServerAuthenticationPrivateKey: updatedServerAuthenticationKeys?.privateKey,
                                                  updatedBlobVersionSeed: updatedBlobVersionSeed,
                                                  failedUploadCounter: failedUploadCounter)
            
        }
        
        
        private func unfreezeTheGroupAndNotifyThatTheGroupUpdateFailed(groupIdentifier: GroupV2.Identifier, within obvContext: ObvContext) throws {
            try identityDelegate.unfreezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            ObvProtocolNotification.groupV2UpdateDidFail(ownedIdentity: ownedIdentity, appGroupIdentifier: groupIdentifier.toObvGroupV2Identifier.appGroupIdentifier, flowId: obvContext.flowId)
                .postOnBackgroundQueue(within: notificationDelegate)
        }

        
        /// This method uses the collected data seeds one by one until a pair allows to decrypt the encrypted blob.
        /// In case the owned identity is a group admin, it should have received at least one authentication private key. To determine the correct one, we look for a private received key matching the group admin public key.
        private func tryToDecrypt(encryptedServerBlob: EncryptedData, blobMainSeed: Seed, blobVersionSeed: Seed, expectedGroupIdentifier: GroupV2.Identifier) -> GroupV2.ServerBlob? {
            
            let blob: GroupV2.ServerBlob
            do {
                blob = try GroupV2.ServerBlob(encryptedServerBlob: encryptedServerBlob, blobMainSeed: blobMainSeed, blobVersionSeed: blobVersionSeed, expectedGroupIdentifier: expectedGroupIdentifier, solveChallengeDelegate: solveChallengeDelegate)
            } catch {
                // We could not decrypt the blob with these seeds.
                return nil
            }
            
            guard blob.administratorsChain.integrityChecked else {
                assertionFailure("The ServerBlob should have checked the administrator chain integrity")
                return nil
            }
            
            return blob
            
        }

    }
    
    
    // MARK: - ProcessGroupUpdateBlobUploadResponseStep
    
    final class ProcessGroupUpdateBlobUploadResponseStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: UploadingUpdatedGroupBlobState
        let receivedMessage: UploadGroupBlobMessage
        
        init?(startState: UploadingUpdatedGroupBlobState, receivedMessage: GroupV2Protocol.UploadGroupBlobMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
                        
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier = startState.groupIdentifier
            let changeset = startState.changeset
            let previousServerBlob = startState.previousServerBlob
            let uploadedServerBlob = startState.uploadedServerBlob
            let updatedServerAuthenticationPrivateKey = startState.updatedServerAuthenticationPrivateKey
            let updatedBlobVersionSeed = startState.updatedBlobVersionSeed
            let failedUploadCounter = startState.failedUploadCounter

            // Depending on the blob upload result, we might abort, try again or continue
            
            switch receivedMessage.blobUploadResult {

            case .permanentFailure:
                
                try notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, doUnfreezeTheGroup: true, within: obvContext)
                return FinalState()
                
            case .temporaryFailure:
                
                guard failedUploadCounter < 10 else {
                    try notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, doUnfreezeTheGroup: true, within: obvContext)
                    return FinalState()
                }
                
                guard try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext) else {
                    try notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, doUnfreezeTheGroup: false, within: obvContext)
                    return FinalState()
                }
                
                let blobKeys: GroupV2.BlobKeys
                do {
                    blobKeys = try identityDelegate.getGroupV2BlobKeysOfGroup(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                } catch {
                    try notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, doUnfreezeTheGroup: true, within: obvContext)
                    return FinalState()
                }
                
                guard let groupAdminServerAuthenticationPrivateKey = blobKeys.groupAdminServerAuthenticationPrivateKey else {
                    try notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, doUnfreezeTheGroup: true, within: obvContext)
                    return FinalState()
                }
                
                // Create and sign a server nonce allowing to request a lock
                
                let lockNonce = prng.genBytes(count: ObvConstants.groupLockNonceLength)
                let challenge = ChallengeType.groupLockNonce(lockNonce: lockNonce)
                guard let lockNonceSignature = ObvSolveChallengeStruct.solveChallenge(challenge, with: groupAdminServerAuthenticationPrivateKey, using: prng) else {
                    // We could not solve the challenge --> We cannot update the blob
                    try notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, doUnfreezeTheGroup: true, within: obvContext)
                    return FinalState()
                }

                // Request a new group lock to the server
                
                let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = RequestServerLockMessage(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.requestGroupBlobLock(groupIdentifier: groupIdentifier, lockNonce: lockNonce, signature: lockNonceSignature)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

                // Increment fail counter and wait for the lock

                return WaitingForLockState(groupIdentifier: groupIdentifier, changeset: changeset, lockNonce: lockNonce, failedUploadCounter: failedUploadCounter+1)
                
            case .success:

                break
                
            }
            
            // If we reach this point, the blob upload was successful
            
            // If there is a new photo to upload, we post the appropriate message to upload it after generating new photo infos.
            // If not, we post a local message allowing to leave the UploadingUpdatedGroupPhotoState

            assert(changeset.photoURL == nil || uploadedServerBlob.serverPhotoInfo != nil) // If there is a photo in the changeset, we expect to find appropriate server photo infos in the updated blob
            
            let serverPhotoInfoOfNewUploadedPhoto: GroupV2.ServerPhotoInfo?
            if let groupPhotoURL = changeset.photoURL, let serverPhotoInfo = uploadedServerBlob.serverPhotoInfo, FileManager.default.fileExists(atPath: groupPhotoURL.path) {
                assert(groupPhotoURL.path.starts(with: delegateManager.uploadingUserData.path)) // At this point, we expect the URL to be managed by the protocol manager
                let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = UploadGroupPhotoMessage(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.putUserData(label: serverPhotoInfo.photoServerKeyAndLabel.label, dataURL: groupPhotoURL, dataKey: serverPhotoInfo.photoServerKeyAndLabel.key)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                serverPhotoInfoOfNewUploadedPhoto = serverPhotoInfo
            } else {
                let coreMessage = getCoreMessage(for: .Local(ownedIdentity: ownedIdentity))
                let concreteMessage = FinalizeGroupUpdateMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate FinalizeGroupUpdateMessage") }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                serverPhotoInfoOfNewUploadedPhoto = nil
            }

            // Return the new state (even if we do not have a new photo, the appropriate state is UploadingUpdatedGroupPhotoState)
            
            return UploadingUpdatedGroupPhotoState(groupIdentifier: groupIdentifier,
                                                   changeset: changeset,
                                                   previousServerBlob: previousServerBlob,
                                                   uploadedServerBlob: uploadedServerBlob,
                                                   updatedServerAuthenticationPrivateKey: updatedServerAuthenticationPrivateKey,
                                                   updatedBlobVersionSeed: updatedBlobVersionSeed,
                                                   serverPhotoInfoOfNewUploadedPhoto: serverPhotoInfoOfNewUploadedPhoto)
            
        }
        
        
        private func notifyThatTheGroupUpdateFailed(groupIdentifier: GroupV2.Identifier, doUnfreezeTheGroup: Bool, within obvContext: ObvContext) throws {
            assertionFailure()
            if doUnfreezeTheGroup {
                try identityDelegate.unfreezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            }
            ObvProtocolNotification.groupV2UpdateDidFail(ownedIdentity: ownedIdentity, appGroupIdentifier: groupIdentifier.toObvGroupV2Identifier.appGroupIdentifier, flowId: obvContext.flowId)
                .postOnBackgroundQueue(within: notificationDelegate)
        }

    }

    
    // MARK: - ProcessGroupUpdatePhotoUploadResponseStep
    
    final class ProcessGroupUpdatePhotoUploadResponseStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: UploadingUpdatedGroupPhotoState
        let receivedMessage: UploadGroupPhotoMessage
        
        init?(startState: UploadingUpdatedGroupPhotoState, receivedMessage: GroupV2Protocol.UploadGroupPhotoMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
        
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier = startState.groupIdentifier
            let changeset = startState.changeset
            let previousServerBlob = startState.previousServerBlob
            let uploadedServerBlob = startState.uploadedServerBlob
            let updatedServerAuthenticationPrivateKey = startState.updatedServerAuthenticationPrivateKey
            let updatedBlobVersionSeed = startState.updatedBlobVersionSeed
            let serverPhotoInfoOfNewUploadedPhoto = startState.serverPhotoInfoOfNewUploadedPhoto

            let coreMessage = getCoreMessage(for: .Local(ownedIdentity: ownedIdentity))
            let concreteMessage = FinalizeGroupUpdateMessage(coreProtocolMessage: coreMessage)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate FinalizeGroupUpdateMessage") }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            
            return UploadingUpdatedGroupPhotoState(groupIdentifier: groupIdentifier,
                                                   changeset: changeset,
                                                   previousServerBlob: previousServerBlob,
                                                   uploadedServerBlob: uploadedServerBlob,
                                                   updatedServerAuthenticationPrivateKey: updatedServerAuthenticationPrivateKey,
                                                   updatedBlobVersionSeed: updatedBlobVersionSeed,
                                                   serverPhotoInfoOfNewUploadedPhoto: serverPhotoInfoOfNewUploadedPhoto)

        }
                
    }

    
    // MARK: - FinalizeGroupUpdateStep
    
    final class FinalizeGroupUpdateStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: UploadingUpdatedGroupPhotoState
        let receivedMessage: FinalizeGroupUpdateMessage
        
        init?(startState: UploadingUpdatedGroupPhotoState, receivedMessage: GroupV2Protocol.FinalizeGroupUpdateMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
        
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier = startState.groupIdentifier
            let changeset = startState.changeset
            let previousServerBlob = startState.previousServerBlob
            let uploadedServerBlob = startState.uploadedServerBlob
            let updatedServerAuthenticationPrivateKey = startState.updatedServerAuthenticationPrivateKey
            let updatedBlobVersionSeed = startState.updatedBlobVersionSeed
            let serverPhotoInfoOfNewUploadedPhoto = startState.serverPhotoInfoOfNewUploadedPhoto

            // Make sure that the integrity of the updated server blob is checked
            
            let uploadedServerBlobWithCheckedIntegrity: GroupV2.ServerBlob
            do {
                uploadedServerBlobWithCheckedIntegrity = try uploadedServerBlob.withCheckedAdministratorsChainIntegrity(expectedGroupIdentifier: groupIdentifier)
            } catch {
                try notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, doUnfreezeTheGroup: true, within: obvContext)
                return FinalState()
            }
            
            // Get the current blob keys
            
            let currentBlobKeys = try identityDelegate.getGroupV2BlobKeysOfGroup(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            guard let blobMainSeed = currentBlobKeys.blobMainSeed else {
                try notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, doUnfreezeTheGroup: true, within: obvContext)
                return FinalState()
            }
            
            // Update the group within the identity manager. We obtain a list of the identities that have been inserted or with a new invitationNonce.
                        
            do {
                let newBlobKeys = GroupV2.BlobKeys(blobMainSeed: blobMainSeed,
                                                   blobVersionSeed: updatedBlobVersionSeed,
                                                   groupAdminServerAuthenticationPrivateKey: updatedServerAuthenticationPrivateKey ?? currentBlobKeys.groupAdminServerAuthenticationPrivateKey)
                _ = try identityDelegate.updateGroupV2(withGroupWithIdentifier: groupIdentifier,
                                                       of: ownedIdentity,
                                                       newBlobKeys: newBlobKeys,
                                                       consolidatedServerBlob: uploadedServerBlobWithCheckedIntegrity,
                                                       groupUpdatedByOwnedIdentity: true,
                                                       within: obvContext)
            } catch {
                try notifyThatTheGroupUpdateFailed(groupIdentifier: groupIdentifier, doUnfreezeTheGroup: true, within: obvContext)
                return FinalState()
            }
            
            // If we reach this point, the group was updated in database
            
            // Unfreeze the group
            
            try identityDelegate.unfreezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            
            // For each group member & pending member, send:
            //  - the main seed, to members with an oblivious channel
            //  - the version seed, to everyone
            //  - the groupAdmin private key, to group admins

            let otherGroupMembers = uploadedServerBlob.getOtherGroupMembers(ownedIdentity: ownedIdentity)
            
            let keysToSend = { (hasGroupAdminPermission: Bool, sentThroughObliviousChannel: Bool) -> GroupV2.BlobKeys in
                let groupAdminServerAuthenticationPrivateKey = updatedServerAuthenticationPrivateKey ?? currentBlobKeys.groupAdminServerAuthenticationPrivateKey
                switch (hasGroupAdminPermission, sentThroughObliviousChannel) {
                case (false, false):
                    return GroupV2.BlobKeys(blobMainSeed: nil,
                                            blobVersionSeed: updatedBlobVersionSeed,
                                            groupAdminServerAuthenticationPrivateKey: nil)
                case (false, true):
                    return GroupV2.BlobKeys(blobMainSeed: blobMainSeed,
                                            blobVersionSeed: updatedBlobVersionSeed,
                                            groupAdminServerAuthenticationPrivateKey: nil)
                case (true, false):
                    return GroupV2.BlobKeys(blobMainSeed: nil,
                                            blobVersionSeed: updatedBlobVersionSeed,
                                            groupAdminServerAuthenticationPrivateKey: groupAdminServerAuthenticationPrivateKey)
                case (true, true):
                    return GroupV2.BlobKeys(blobMainSeed: blobMainSeed,
                                            blobVersionSeed: updatedBlobVersionSeed,
                                            groupAdminServerAuthenticationPrivateKey: groupAdminServerAuthenticationPrivateKey)
                }
            }
            
            let otherGroupMembersIdentities = Set(otherGroupMembers.map({ $0.identity }))
            let deviceUidsOfRemoteIdentity = try channelDelegate.getDeviceUidsOfRemoteIdentitiesHavingConfirmedObliviousChannelWithTheCurrentDeviceOfOwnedIdentity(ownedIdentity, remoteIdentities: otherGroupMembersIdentities, within: obvContext)
            
            for member in otherGroupMembers {
                if let memberDeviceUids = deviceUidsOfRemoteIdentity[member.identity], !memberDeviceUids.isEmpty {
                    let keysToSend = keysToSend(member.hasGroupAdminPermission, true)
                    let channelType = ObvChannelSendChannelType.ObliviousChannel(to: member.identity, remoteDeviceUids: Array(memberDeviceUids), fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true)
                    let coreMessage = CoreProtocolMessage(channelType: channelType, cryptoProtocolId: .GroupV2, protocolInstanceUid: protocolInstanceUid)
                    let concreteMessage = InvitationOrMembersUpdateMessage(coreProtocolMessage: coreMessage,
                                                                           groupIdentifier: groupIdentifier,
                                                                           groupVersion: uploadedServerBlob.groupVersion,
                                                                           blobKeys: keysToSend,
                                                                           notifiedDeviceUIDs: memberDeviceUids)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } else {
                    let keysToSend = keysToSend(member.hasGroupAdminPermission, false)
                    let channelType = ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: member.identity, fromOwnedIdentity: ownedIdentity)
                    let coreMessage = CoreProtocolMessage(channelType: channelType, cryptoProtocolId: .GroupV2, protocolInstanceUid: protocolInstanceUid)
                    let concreteMessage = InvitationOrMembersUpdateBroadcastMessage(coreProtocolMessage: coreMessage,
                                                                                    groupIdentifier: groupIdentifier,
                                                                                    groupVersion: uploadedServerBlob.groupVersion,
                                                                                    blobKeys: keysToSend)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }

            // Kick removed members
            
            let membersToKick = previousServerBlob.groupMembers.subtracting(uploadedServerBlob.groupMembers)
            if !membersToKick.isEmpty {
                
                // Compute the encrypted administrator chain
                
                let encryptedAdministratorChain = try uploadedServerBlob.administratorsChain.encrypt(blobMainSeed: blobMainSeed, prng: prng)
                
                // Kick removed members
                
                for member in membersToKick {
                    let challenge = ChallengeType.groupKick(encryptedAdministratorChain: encryptedAdministratorChain, groupInvitationNonce: member.groupInvitationNonce)
                    let signature = try solveChallengeDelegate.solveChallenge(challenge, for: ownedIdentity, using: prng, within: obvContext)
                    let channelType = ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: member.identity, fromOwnedIdentity: ownedIdentity)
                    let coreMessage = CoreProtocolMessage(channelType: channelType, cryptoProtocolId: .GroupV2, protocolInstanceUid: protocolInstanceUid)
                    let concreteMessage = KickMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, encryptedAdministratorChain: encryptedAdministratorChain, signature: signature)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
            }
            
            // If there is an uploaded photo, we expect its URL to be managed by the protocol manager.
            // At this point, we can pass the photo to the identity manager and delete the file we have within the protocol manager
            
            assert(changeset.photoURL == nil || serverPhotoInfoOfNewUploadedPhoto != nil)
            
            if let photoURL = changeset.photoURL, let serverPhotoInfoOfNewUploadedPhoto = serverPhotoInfoOfNewUploadedPhoto, FileManager.default.fileExists(atPath: photoURL.path) {
                let photoData = try Data(contentsOf: photoURL)
                try identityDelegate.setDownloadedPhotoOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, serverPhotoInfo: serverPhotoInfoOfNewUploadedPhoto, photo: photoData, within: obvContext)
                try? obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return }
                    try? FileManager.default.removeItem(at: photoURL)
                }
            }
            
            return FinalState()
            
        }

        
        private func notifyThatTheGroupUpdateFailed(groupIdentifier: GroupV2.Identifier, doUnfreezeTheGroup: Bool, within obvContext: ObvContext) throws {
            assertionFailure()
            if doUnfreezeTheGroup {
                try identityDelegate.unfreezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            }
            ObvProtocolNotification.groupV2UpdateDidFail(ownedIdentity: ownedIdentity, appGroupIdentifier: groupIdentifier.toObvGroupV2Identifier.appGroupIdentifier, flowId: obvContext.flowId)
                .postOnBackgroundQueue(within: notificationDelegate)
        }

    }

    
    // MARK: - GetKickedStep
    
    class GetKickedStep: ProtocolStep {
        
        private let startState: StartStateType
        private let receivedMessage: ReceivedMessageType
        
        enum ReceivedMessageType {
            case kickMessage(receivedMessage: KickMessage)
            case propagatedKickMessage(receivedMessage: PropagatedKickMessage)
        }

        enum StartStateType {
            case initial(startState: ConcreteProtocolInitialState)
            case invitationReceived(startState: InvitationReceivedState)
            case downloadingGroupBlob(startState: DownloadingGroupBlobState)
            case iNeedMoreSeeds(startState: INeedMoreSeedsState)
            case waitingForLockState(startState: WaitingForLockState)
        }

        init?(startState: StartStateType, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            switch receivedMessage {
            case .kickMessage(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AsymmetricChannel,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .propagatedKickMessage(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier: GroupV2.Identifier
            let propagationNeeded: Bool
            let encryptedAdministratorChain: EncryptedData
            let signature: Data
            switch receivedMessage {
            case .kickMessage(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                encryptedAdministratorChain = receivedMessage.encryptedAdministratorChain
                signature = receivedMessage.signature
                propagationNeeded = true
            case .propagatedKickMessage(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                encryptedAdministratorChain = receivedMessage.encryptedAdministratorChain
                signature = receivedMessage.signature
                propagationNeeded = false
            }
            
            
            let dialogUuid: UUID?
            let stateToReturn: ConcreteProtocolState
            switch startState {
            case .initial:
                dialogUuid = nil
                stateToReturn = FinalState()
            case .invitationReceived(let startState):
                dialogUuid = startState.dialogUuid
                stateToReturn = startState
            case .downloadingGroupBlob(let startState):
                dialogUuid = startState.dialogUuid
                stateToReturn = startState
            case .iNeedMoreSeeds(let startState):
                dialogUuid = startState.dialogUuid
                stateToReturn = startState
            case .waitingForLockState(let startState):
                dialogUuid = nil
                stateToReturn = startState
            }

            // Check that the protocol instance UID matches the group identifier

            guard protocolInstanceUid == (try? groupIdentifier.computeProtocolInstanceUid()) else {
                assertionFailure()
                return stateToReturn
            }
            
            // Propagate the message if needed
            
            if propagationNeeded {
                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !otherDeviceUIDs.isEmpty {
                    let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ObliviousChannel(to: ownedIdentity, remoteDeviceUids: Array(otherDeviceUIDs), fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true))
                    let concreteMessage = PropagatedKickMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, encryptedAdministratorChain: encryptedAdministratorChain, signature: signature)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }

            // Depending on the start state, we either look for information about the group in the start state or within the identity manager.
            
            let ownGroupInvitationNonce: Data
            let blobMainSeed: Seed
            let knownAdministratorsChain: GroupV2.AdministratorsChain
            
            switch startState {
            case .invitationReceived(let startState):
                
                // If we are in the InvitationReceivedState, we use the information within instead of queriing the identity delegate.
                
                // We fetch our invitation nonce in the InvitationReceivedState. It is required to check the signature contained in the received message.
                
                guard let _ownGroupInvitationNonce = startState.serverBlob.getOwnPermissionsAndGroupInvitationNonce(ownedIdentity: ownedIdentity)?.ownGroupInvitationNonce else {
                    // We could not get our own invitation nonce, meaning we are not able to check the signature received in the kick message. There is nothing we can do here.
                    assertionFailure()
                    return FinalState()
                }
                
                ownGroupInvitationNonce = _ownGroupInvitationNonce
                
                // In order to decrypt the received administrator chain, we need the Blob main seed
                
                guard let _blobMainSeed = startState.blobKeys.blobMainSeed else {
                    // We could not recover the blob main seed, meaning we won't be able to decrypt the received administrator chain. There is nothing we can do here.
                    assertionFailure()
                    return FinalState()
                }
                
                blobMainSeed = _blobMainSeed
                
                knownAdministratorsChain = startState.serverBlob.administratorsChain

            case .downloadingGroupBlob, .iNeedMoreSeeds, .waitingForLockState, .initial:
                
                // In all these start states, we fetch information about the group from the identity delegate.

                let groupExistsInDB = try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                guard groupExistsInDB else {
                    // The group does not exist in DB. There is not much we can do.
                    return stateToReturn
                }
                
                // We fetch our invitation nonce since it is required to check the signature contained in the received message.

                ownGroupInvitationNonce = try identityDelegate.getOwnGroupInvitationNonceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                
                // In order to decrypt the received administrator chain, we need the Blob main seed

                guard let _blobMainSeed = try identityDelegate.getGroupV2BlobKeysOfGroup(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext).blobMainSeed else {
                    // Without the main seed, we won't be able to decrypt the received administrator chain
                    return stateToReturn
                }
                
                blobMainSeed = _blobMainSeed
                
                knownAdministratorsChain = try identityDelegate.getAdministratorChainOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                
            }
            
            // Decrypt and verify the received administrators chain using the main seed, and check its integrity
            
            let receivedAdministratorChain: GroupV2.AdministratorsChain
            do {
                receivedAdministratorChain = try GroupV2.AdministratorsChain.decryptAndCheckIntegrity(encryptedAdministratorChain: encryptedAdministratorChain,
                                                                                                      blobMainSeed: blobMainSeed,
                                                                                                      expectedGroupUID: groupIdentifier.groupUID)
            } catch {
                // Something bad happened (e.g., the decryption of the administator chain failed).
                assertionFailure()
                return stateToReturn
            }
            
            // Check that the chain we already knew about is a prefx of the chain we received
            
            guard knownAdministratorsChain.isPrefixOfOtherAdministratorsChain(receivedAdministratorChain) else {
                return stateToReturn
            }

            // Verify that the signature in the received message matches an administrator of the chain

            var signatureIsValid = false
            for administrator in receivedAdministratorChain.allCurrentAdministratorIdentities {
                if ObvSolveChallengeStruct.checkResponse(signature,
                                                         to: .groupKick(encryptedAdministratorChain: encryptedAdministratorChain, groupInvitationNonce: ownGroupInvitationNonce),
                                                         from: administrator) {
                    signatureIsValid = true
                }
            }
            guard signatureIsValid else {
                return stateToReturn
            }

            // If we reach this point, the signature is valid, we are indeed kick from the group
            
            // Remove the dialog
            
            if let dialogUuid = dialogUuid {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Delete the group
            
            try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            
            // Depending on the current state, we either return the final state, or the current state.
            // This allows to deal with the case occuring when we are part of the group, go offline, an admin kick then re-invites us.
            // In that case, if processing the messages in the correct order, we first receive the invitation, thus download the group blob.
            // During the download, we process the kick message and arrive here. As we can see, this will delete the group, but we stay in the downloading group blob state.
            // Doing so allows to recover and to display an invitation dialog.
            
            switch startState {
            case .initial, .invitationReceived, .waitingForLockState:
                return FinalState()
            case .downloadingGroupBlob(startState: let startState):
                return startState
            case .iNeedMoreSeeds(startState: let startState):
                return startState
            }
                                    
        }
    }

    
    
    // MARK: Process KickMessage from ConcreteProtocolInitialState

    final class ProcessKickMessageFromConcreteProtocolInitialStateStep: GetKickedStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: KickMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.KickMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState), receivedMessage: .kickMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: Process KickMessage from InvitationReceivedState

    final class ProcessKickMessageFromInvitationReceivedStateStep: GetKickedStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: KickMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.KickMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceived(startState: startState), receivedMessage: .kickMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process KickMessage from DownloadingGroupBlobState

    final class ProcessKickMessageFromDownloadingGroupBlobStateStep: GetKickedStep, TypedConcreteProtocolStep {
        
        let startState: DownloadingGroupBlobState
        let receivedMessage: KickMessage
        
        init?(startState: DownloadingGroupBlobState, receivedMessage: GroupV2Protocol.KickMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .downloadingGroupBlob(startState: startState), receivedMessage: .kickMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process KickMessage from INeedMoreSeedsState

    final class ProcessKickMessageFromINeedMoreSeedsStateStep: GetKickedStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: KickMessage
        
        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.KickMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeeds(startState: startState), receivedMessage: .kickMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: Process KickMessage from WaitingForLockState

    final class ProcessKickMessageFromWaitingForLockStateStep: GetKickedStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForLockState
        let receivedMessage: KickMessage
        
        init?(startState: WaitingForLockState, receivedMessage: GroupV2Protocol.KickMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .waitingForLockState(startState: startState), receivedMessage: .kickMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagatedKickMessage from ConcreteProtocolInitialState

    final class ProcessPropagatedKickMessageFromConcreteProtocolInitialStateStep: GetKickedStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagatedKickMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.PropagatedKickMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState), receivedMessage: .propagatedKickMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: Process PropagatedKickMessage from InvitationReceivedState

    final class ProcessPropagatedKickMessageFromInvitationReceivedStateStep: GetKickedStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: PropagatedKickMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.PropagatedKickMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceived(startState: startState), receivedMessage: .propagatedKickMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagatedKickMessage from DownloadingGroupBlobState

    final class ProcessPropagatedKickMessageFromDownloadingGroupBlobStateStep: GetKickedStep, TypedConcreteProtocolStep {
        
        let startState: DownloadingGroupBlobState
        let receivedMessage: PropagatedKickMessage
        
        init?(startState: DownloadingGroupBlobState, receivedMessage: GroupV2Protocol.PropagatedKickMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .downloadingGroupBlob(startState: startState), receivedMessage: .propagatedKickMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagatedKickMessage from INeedMoreSeedsState

    final class ProcessPropagatedKickMessageFromINeedMoreSeedsStateStep: GetKickedStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: PropagatedKickMessage
        
        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.PropagatedKickMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeeds(startState: startState), receivedMessage: .propagatedKickMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: Process PropagatedKickMessage from WaitingForLockState

    final class ProcessPropagatedKickMessageFromWaitingForLockStateStep: GetKickedStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForLockState
        let receivedMessage: PropagatedKickMessage
        
        init?(startState: WaitingForLockState, receivedMessage: GroupV2Protocol.PropagatedKickMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .waitingForLockState(startState: startState), receivedMessage: .propagatedKickMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    
    // MARK: - LeaveGroupStep
    
    class LeaveGroupStep: ProtocolStep {
        
        private let startState: StartStateType
        private let receivedMessage: ReceivedMessageType

        enum ReceivedMessageType {
            case initiateGroupLeaveMessage(receivedMessage: InitiateGroupLeaveMessage)
            case propagatedGroupLeaveMessage(receivedMessage: PropagatedGroupLeaveMessage)
        }

        enum StartStateType {
            case initial(startState: ConcreteProtocolInitialState)
            case downloadingGroupBlob(startState: DownloadingGroupBlobState)
            case iNeedMoreSeeds(startState: INeedMoreSeedsState)
            case waitingForLockState(startState: WaitingForLockState)
        }

        init?(startState: StartStateType, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            switch receivedMessage {
            case .initiateGroupLeaveMessage(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .propagatedGroupLeaveMessage(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier: GroupV2.Identifier
            let propagationNeeded: Bool
            switch receivedMessage {
            case .initiateGroupLeaveMessage(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                propagationNeeded = true
            case .propagatedGroupLeaveMessage(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                propagationNeeded = false
            }
            
            let stateToReturn: ConcreteProtocolState
            switch startState {
            case .initial:
                stateToReturn = FinalState()
            case .downloadingGroupBlob(let startState):
                stateToReturn = startState
            case .iNeedMoreSeeds(let startState):
                stateToReturn = startState
            case .waitingForLockState(let startState):
                stateToReturn = startState
            }

            // Check that the protocol instance UID matches the group identifier

            guard protocolInstanceUid == (try? groupIdentifier.computeProtocolInstanceUid()) else {
                assertionFailure()
                return stateToReturn
            }
            
            // We cannot leave the group if it is a keycloak group. Make sure this is not the case
            
            switch groupIdentifier.category {
            case .keycloak:
                assertionFailure("It is not possible to leave a keycloak group, so we prevent this here. Yet, the interface should not allow this call to be made.")
                return stateToReturn
            case .server:
                break
            }
            
            // Check that we are indeed part of the group

            guard try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext) else {
                return stateToReturn
            }
            
            let ownGroupInvitationNonce = try identityDelegate.getOwnGroupInvitationNonceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)

            // Ignore propagated messages containing a bad invitation nonce
            
            switch receivedMessage {
            case .initiateGroupLeaveMessage:
                break
            case .propagatedGroupLeaveMessage(let receivedMessage):
                guard receivedMessage.groupInvitationNonce == ownGroupInvitationNonce else {
                    return stateToReturn
                }
            }
            
            // We cannot leave a group if we are the only admin. Make sure this is not the case
            
            do {
                let allNonPendingAdministratorsIdentities = try identityDelegate.getAllNonPendingAdministratorsIdentitiesOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                if allNonPendingAdministratorsIdentities.contains(ownedIdentity) && allNonPendingAdministratorsIdentities.count == 1 {
                    return stateToReturn
                }
            }
            
            // If propagation is needed, propagate now.
            // In the case we propagate the message, we also are in charge of leaving a "group left" log on the server.
            // In the case we propagate the message, we also create a list of other members to notify.
            
            var groupMembersToNotify = Set<ObvCryptoIdentity>()
            if propagationNeeded {
                
                // Propagate the group leave message to other devices

                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !otherDeviceUIDs.isEmpty {
                    let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ObliviousChannel(to: ownedIdentity, remoteDeviceUids: Array(otherDeviceUIDs), fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true))
                    let concreteMessage = PropagatedGroupLeaveMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Put a group left log on server
                
                let leaveSignature = try solveChallengeDelegate.solveChallenge(.groupLeaveNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce), for: ownedIdentity, using: prng, within: obvContext)
                let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = PutGroupLogOnServerMessage(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.putGroupLog(groupIdentifier: groupIdentifier, querySignature: leaveSignature)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

                // Get the list of members to notify (before deleting the group)

                let otherMembers = try identityDelegate.getAllOtherMembersOrPendingMembersOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                groupMembersToNotify = Set(otherMembers.map({ $0.identity }))
                
            }
            
            // Delete the group from DB
            
            try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            
            // In the case we propagate the message, we move to the RejectingInvitationOrLeavingGroupState, otherwise, we are done.
            
            if propagationNeeded {
                return RejectingInvitationOrLeavingGroupState(groupIdentifier: groupIdentifier, groupMembersToNotify: groupMembersToNotify)
            } else {
                return FinalState()
            }
            
        }
    }

    
    
    // MARK: Process InitiateGroupLeaveMessage from ConcreteProtocolInitialState

    final class ProcessInitiateGroupLeaveMessageFromConcreteProtocolInitialStateStep: LeaveGroupStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateGroupLeaveMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InitiateGroupLeaveMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState), receivedMessage: .initiateGroupLeaveMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: Process InitiateGroupLeaveMessage from InvitationReceivedState

    final class ProcessInitiateGroupLeaveMessageFromDownloadingGroupBlobStateStep: LeaveGroupStep, TypedConcreteProtocolStep {
        
        let startState: DownloadingGroupBlobState
        let receivedMessage: InitiateGroupLeaveMessage
        
        init?(startState: DownloadingGroupBlobState, receivedMessage: GroupV2Protocol.InitiateGroupLeaveMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .downloadingGroupBlob(startState: startState), receivedMessage: .initiateGroupLeaveMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process InitiateGroupLeaveMessage from DownloadingGroupBlobState

    final class ProcessInitiateGroupLeaveMessageFromINeedMoreSeedsStateStep: LeaveGroupStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: InitiateGroupLeaveMessage
        
        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.InitiateGroupLeaveMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeeds(startState: startState), receivedMessage: .initiateGroupLeaveMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process InitiateGroupLeaveMessage from WaitingForLockState

    final class ProcessInitiateGroupLeaveMessageFromWaitingForLockStateStep: LeaveGroupStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForLockState
        let receivedMessage: InitiateGroupLeaveMessage
        
        init?(startState: WaitingForLockState, receivedMessage: GroupV2Protocol.InitiateGroupLeaveMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .waitingForLockState(startState: startState), receivedMessage: .initiateGroupLeaveMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagatedGroupLeaveMessage from WaitingForLockState

    final class ProcessPropagatedGroupLeaveMessageFromConcreteProtocolInitialStateStep: LeaveGroupStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagatedGroupLeaveMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.PropagatedGroupLeaveMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState), receivedMessage: .propagatedGroupLeaveMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagatedGroupLeaveMessage from ConcreteProtocolInitialState

    final class ProcessPropagatedGroupLeaveMessageFromDownloadingGroupBlobStateStep: LeaveGroupStep, TypedConcreteProtocolStep {
        
        let startState: DownloadingGroupBlobState
        let receivedMessage: PropagatedGroupLeaveMessage
        
        init?(startState: DownloadingGroupBlobState, receivedMessage: GroupV2Protocol.PropagatedGroupLeaveMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .downloadingGroupBlob(startState: startState), receivedMessage: .propagatedGroupLeaveMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: Process PropagatedGroupLeaveMessage from ConcreteProtocolInitialState

    final class ProcessPropagatedGroupLeaveMessageFromINeedMoreSeedsStateStep: LeaveGroupStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: PropagatedGroupLeaveMessage
        
        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.PropagatedGroupLeaveMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeeds(startState: startState), receivedMessage: .propagatedGroupLeaveMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagatedGroupLeaveMessage from ConcreteProtocolInitialState

    final class ProcessPropagatedGroupLeaveMessageFromWaitingForLockStateStep: LeaveGroupStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForLockState
        let receivedMessage: PropagatedGroupLeaveMessage
        
        init?(startState: WaitingForLockState, receivedMessage: GroupV2Protocol.PropagatedGroupLeaveMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .waitingForLockState(startState: startState), receivedMessage: .propagatedGroupLeaveMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: - DisbandGroupStep
    
    class DisbandGroupStep: ProtocolStep {
        
        private let startState: StartStateType
        private let receivedMessage: ReceivedMessageType

        enum ReceivedMessageType {
            case initiateGroupDisband(receivedMessage: InitiateGroupDisbandMessage)
            case propagateGroupDisband(receivedMessage: PropagateGroupDisbandMessage)
        }

        enum StartStateType {
            case initial(startState: ConcreteProtocolInitialState)
            case downloadingGroupBlob(startState: DownloadingGroupBlobState)
            case iNeedMoreSeeds(startState: INeedMoreSeedsState)
            case invitationReceived(startState: InvitationReceivedState)
        }

        init?(startState: StartStateType, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            switch receivedMessage {
            case .initiateGroupDisband(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .Local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .propagateGroupDisband(let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupIdentifier: GroupV2.Identifier
            let propagationNeeded: Bool
            switch receivedMessage {
            case .initiateGroupDisband(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                propagationNeeded = true
            case .propagateGroupDisband(let receivedMessage):
                groupIdentifier = receivedMessage.groupIdentifier
                propagationNeeded = false
            }
            
            let stateToReturn: ConcreteProtocolState
            switch startState {
            case .initial:
                stateToReturn = FinalState()
            case .downloadingGroupBlob(let startState):
                stateToReturn = startState
            case .iNeedMoreSeeds(let startState):
                stateToReturn = startState
            case .invitationReceived(let startState):
                stateToReturn = startState
            }

            // Check that the protocol instance UID matches the group identifier

            guard protocolInstanceUid == (try? groupIdentifier.computeProtocolInstanceUid()) else {
                assertionFailure()
                return stateToReturn
            }
            
            // Check that the group exists in DB
            
            guard try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext) else {
                return stateToReturn
            }

            // Check that we are indeed part of the group and check whether we are an admin
            
            let groupAdminServerAuthenticationPrivateKey: PrivateKeyForAuthentication
            let blobMainSeed: Seed
            do {
                let administratorChain = try identityDelegate.getAdministratorChainOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                guard administratorChain.allCurrentAdministratorIdentities.contains(ownedIdentity) else {
                    // We are not administrator of the group, we cannot disband this group
                    return stateToReturn
                }
                let blobKeys = try identityDelegate.getGroupV2BlobKeysOfGroup(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                guard let adminKey = blobKeys.groupAdminServerAuthenticationPrivateKey else {
                    // We do not have the admin key, we cannot disband the group
                    return stateToReturn
                }
                groupAdminServerAuthenticationPrivateKey = adminKey
                guard let _blobMainSeed = blobKeys.blobMainSeed else {
                    // We do not have the blob main seed, meaning that we won't be able to kick other members
                    return stateToReturn
                }
                blobMainSeed = _blobMainSeed
            }

            if propagationNeeded {
                
                // The propagation will be performed in the FinalizeGroupDisbandStep.
                
                // Delete the group from the server
                
                let coreMessage = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = DeleteGroupBlobFromServerMessage(coreProtocolMessage: coreMessage)
                guard let signature = ObvSolveChallengeStruct.solveChallenge(.groupDelete, with: groupAdminServerAuthenticationPrivateKey, using: prng) else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not compute signature for deleting group")
                }
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.deleteGroupBlob(groupIdentifier: groupIdentifier, signature: signature)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                
                // Freeze the group
                
                try identityDelegate.freezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)

                return DisbandingGroupState(groupIdentifier: groupIdentifier, blobMainSeed: blobMainSeed)
                
            } else {
                
                // Since no propagation is needed, we only have to delete the group locally
                
                try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                
                return FinalState()
                
            }
            
        }
    }

    
    // MARK: Process InitiateGroupDisbandMessage from ConcreteProtocolInitialState

    final class ProcessInitiateGroupDisbandMessageFromConcreteProtocolInitialStateStep: DisbandGroupStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateGroupDisbandMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InitiateGroupDisbandMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState), receivedMessage: .initiateGroupDisband(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: Process PropagateGroupDisbandMessage from ConcreteProtocolInitialState

    final class ProcessPropagateGroupDisbandMessageFromConcreteProtocolInitialStateStep: DisbandGroupStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateGroupDisbandMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.PropagateGroupDisbandMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState), receivedMessage: .propagateGroupDisband(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagateGroupDisbandMessage from DownloadingGroupBlobState

    final class ProcessPropagateGroupDisbandMessageFromDownloadingGroupBlobStateStep: DisbandGroupStep, TypedConcreteProtocolStep {
        
        let startState: DownloadingGroupBlobState
        let receivedMessage: PropagateGroupDisbandMessage
        
        init?(startState: DownloadingGroupBlobState, receivedMessage: GroupV2Protocol.PropagateGroupDisbandMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .downloadingGroupBlob(startState: startState), receivedMessage: .propagateGroupDisband(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagateGroupDisbandMessage from INeedMoreSeedsState

    final class ProcessPropagateGroupDisbandMessageFromINeedMoreSeedsStateStep: DisbandGroupStep, TypedConcreteProtocolStep {
        
        let startState: INeedMoreSeedsState
        let receivedMessage: PropagateGroupDisbandMessage
        
        init?(startState: INeedMoreSeedsState, receivedMessage: GroupV2Protocol.PropagateGroupDisbandMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .iNeedMoreSeeds(startState: startState), receivedMessage: .propagateGroupDisband(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }


    // MARK: Process PropagateGroupDisbandMessage from InvitationReceivedState

    final class ProcessPropagateGroupDisbandMessageFromInvitationReceivedStateStep: DisbandGroupStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: PropagateGroupDisbandMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: GroupV2Protocol.PropagateGroupDisbandMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .invitationReceived(startState: startState), receivedMessage: .propagateGroupDisband(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        // The step execution is defined in the superclass

    }

    
    // MARK: - FinalizeGroupDisbandStep
    
    final class FinalizeGroupDisbandStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: DisbandingGroupState
        let receivedMessage: DeleteGroupBlobFromServerMessage
        
        init?(startState: DisbandingGroupState, receivedMessage: GroupV2Protocol.DeleteGroupBlobFromServerMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
        
            eraseReceivedMessagesAfterReachingAFinalState = false // Set back to true if the disband succeeds

            let groupDeletionWasSuccessful = receivedMessage.groupDeletionWasSuccessful
            let groupIdentifier = startState.groupIdentifier
            let blobMainSeed = startState.blobMainSeed

            // Check that the group still exists in DB
            
            guard try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext) else {
                // The group does not exist anymore, there is nothing left to do
                return FinalState()
            }
            
            // If we could not disband the group on the server, we unfreeze the group and go the final state
            
            guard groupDeletionWasSuccessful else {
                try identityDelegate.unfreezeGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                return FinalState()
            }
            
            // If we reach this point, we know the group still exists in DB but was deleted from the server.
            
            // We propagate the disband request to our other devices
            
            do {
                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !otherDeviceUIDs.isEmpty {
                    let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ObliviousChannel(to: ownedIdentity, remoteDeviceUids: Array(otherDeviceUIDs), fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true))
                    let concreteMessage = PropagateGroupDisbandMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }
            
            // Send a kick message to all the other group members
            
            let membersToKick = try identityDelegate.getAllOtherMembersOrPendingMembersOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            if !membersToKick.isEmpty {
                
                // Compute the encrypted administrator chain

                let administratorChain = try identityDelegate.getAdministratorChainOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                let encryptedAdministratorChain = try administratorChain.encrypt(blobMainSeed: blobMainSeed, prng: prng)
                
                // Kick all other members
                
                for member in membersToKick {
                    let challenge = ChallengeType.groupKick(encryptedAdministratorChain: encryptedAdministratorChain, groupInvitationNonce: member.groupInvitationNonce)
                    let signature = try solveChallengeDelegate.solveChallenge(challenge, for: ownedIdentity, using: prng, within: obvContext)
                    let channelType = ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: member.identity, fromOwnedIdentity: ownedIdentity)
                    let coreMessage = CoreProtocolMessage(channelType: channelType, cryptoProtocolId: .GroupV2, protocolInstanceUid: protocolInstanceUid)
                    let concreteMessage = KickMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, encryptedAdministratorChain: encryptedAdministratorChain, signature: signature)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
            }

            // Locally delete the group
            
            try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            
            // We are done
            
            eraseReceivedMessagesAfterReachingAFinalState = true

            return FinalState()
            
        }
    }

    
    // MARK: - PrepareBatchKeysMessageStep
    
    final class PrepareBatchKeysMessageStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateBatchKeysResendMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InitiateBatchKeysResendMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
        
            eraseReceivedMessagesAfterReachingAFinalState = false

            let contactIdentity = receivedMessage.contactIdentity
            let contactDeviceUID = receivedMessage.contactDeviceUID

            // Get all group identifiers, versions, and keys of groups shared with the contact
            
            let allIdentifierVersionAndKeys = try identityDelegate.getAllGroupsV2IdentifierVersionAndKeysForContact(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
            
            // Send the information to the contact

            if !allIdentifierVersionAndKeys.isEmpty {
                let channelType = ObvChannelSendChannelType.ObliviousChannel(to: contactIdentity, remoteDeviceUids: [contactDeviceUID], fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: false)
                let coreMessage = CoreProtocolMessage(channelType: channelType, cryptoProtocolId: .GroupV2, protocolInstanceUid: protocolInstanceUid)
                let concreteMessage = BlobKeysBatchAfterChannelCreationMessage(coreProtocolMessage: coreMessage, groupInfos: allIdentifierVersionAndKeys)
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // We are done
            
            return FinalState()
            
        }
    }

    
    // MARK: - ProcessBatchKeysMessageStep
    
    final class ProcessBatchKeysMessageStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: BlobKeysBatchAfterChannelCreationMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.BlobKeysBatchAfterChannelCreationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
        
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInfos = receivedMessage.groupInfos

            // For each GroupV2.IdentifierVersionAndKeys contained in the `groupInfos`, we post one local message with the correct protocol UID for each group
            
            for groupIdentifierVersionAndKeys in groupInfos {
                
                let protocolInstanceUID = try groupIdentifierVersionAndKeys.groupIdentifier.computeProtocolInstanceUid()
                
                // Determine the origin of the message
                
                guard let contactIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                    assertionFailure()
                    return FinalState()
                }
                
                let channelType = ObvChannelSendChannelType.Local(ownedIdentity: ownedIdentity)
                let coreMessage = CoreProtocolMessage(channelType: channelType, cryptoProtocolId: .GroupV2, protocolInstanceUid: protocolInstanceUID)
                let concreteMessage = BlobKeysAfterChannelCreationMessage(coreProtocolMessage: coreMessage,
                                                                          groupIdentifier: groupIdentifierVersionAndKeys.groupIdentifier,
                                                                          groupVersion: groupIdentifierVersionAndKeys.groupVersion,
                                                                          blobKeys: groupIdentifierVersionAndKeys.blobKeys,
                                                                          inviter: contactIdentity)
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            }

            // We are done
            
            return FinalState()
            
        }
    }

    
    // MARK: - ProcessInitiateUpdateKeycloakGroupsMessageStep
    
    /// This steps is an "isolated" step as it starts from the initial state and finishes in a final state. Its protocol instance UID is a random one. It is called when the keycloak manager of the app receives new informations concerning keycloak groups.
    /// This steps processes all this information and launches new protocol steps, e.g., one for each new signed group.
    final class ProcessInitiateUpdateKeycloakGroupsMessageStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateUpdateKeycloakGroupsMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InitiateUpdateKeycloakGroupsMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let signedGroupBlobs = receivedMessage.signedGroupBlobs
            let signedGroupDeletions = receivedMessage.signedGroupDeletions
            let signedGroupKicks = receivedMessage.signedGroupKicks // Contains kicks for our owned identity only
            let keycloakCurrentTimestamp = receivedMessage.keycloakCurrentTimestamp

            let keycloakGroupV2UpdateOutputs: [KeycloakGroupV2UpdateOutput]
            do {
                keycloakGroupV2UpdateOutputs = try identityDelegate.updateKeycloakGroups(
                    ownedIdentity: ownedIdentity,
                    signedGroupBlobs: signedGroupBlobs,
                    signedGroupDeletions: signedGroupDeletions,
                    signedGroupKicks: signedGroupKicks,
                    keycloakCurrentTimestamp: keycloakCurrentTimestamp,
                    within: obvContext)
            } catch {
                assertionFailure("Failed to update keycloak groups in the identity manager: \(error.localizedDescription)")
                return FinalState()
            }
            
            for output in keycloakGroupV2UpdateOutputs {
                
                let groupIdentifier = output.groupIdentifier
                let ownGroupInvitationNonce = output.ownGroupInvitationNonce
                
                if let serverPhotoInfo = output.serverPhotoInfoIfPhotoNeedsToBeDownloaded {
                    
                    // Launch a child protocol instance for downloading the photo. To do so, we post an appropriate message on the loopback channel. In this particular case, we do not need to "link" this protocol to the current protocol.
                    
                    let childProtocolInstanceUid = UID.gen(with: prng)
                    let coreMessage = getCoreMessageForOtherLocalProtocol(
                        otherCryptoProtocolId: .DownloadGroupV2Photo,
                        otherProtocolInstanceUid: childProtocolInstanceUid)
                    let childProtocolInitialMessage = DownloadGroupV2PhotoProtocol.InitialMessage(
                        coreProtocolMessage: coreMessage,
                        groupIdentifier: output.groupIdentifier,
                        serverPhotoInfo: serverPhotoInfo)
                    guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw Self.makeError(message: "Could not generate child protocol message") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    
                }
                
                // Send a ping to the identities returned by the identity manager. Doing so allow us to inform them that we agreed to be part of the group.
                // This happens when the group was just created within the identity manager.

                for identityToPing in output.insertedOrUpdatedIdentities {
                    let otherProtocolInstanceUid = try groupIdentifier.computeProtocolInstanceUid()
                    let challenge = ChallengeType.groupJoinNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: output.ownGroupInvitationNonce, recipientIdentity: identityToPing)
                    let signature = try solveChallengeDelegate.solveChallenge(challenge, for: ownedIdentity, using: prng, within: obvContext)
                    let coreMessage = getCoreMessageForSameProtocolButOtherProtocolInstanceUid(
                        for: ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: identityToPing, fromOwnedIdentity: ownedIdentity),
                        otherProtocolInstanceUid: otherProtocolInstanceUid)
                    let concreteMessage = PingMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: signature, isReponse: false)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }


            }
            
            return FinalState()
            
        }
    }

    
    // MARK: - SendKeycloakGroupTargetedPingStep
    
    /// When a contact `isCertifiedByOwnKeycloak` status changes from `fase` to `true`, we want to ping this contact for all groups where she is pending. This loop is performed at the engine level, which leverage this protocol step to send the Ping message.
    final class SendKeycloakGroupTargetedPingStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateTargetedPingMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupV2Protocol.InitiateTargetedPingMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let groupIdentifier = receivedMessage.groupIdentifier
            let pendingMemberIdentity = receivedMessage.pendingMemberIdentity

            // Check that the protocol instance UID matches the group identifier

            guard protocolInstanceUid == (try? groupIdentifier.computeProtocolInstanceUid()) else {
                assertionFailure()
                return FinalState()
            }

            // Check that the group exists in DB (which means we accepted to join it). If it does not, return immediately.
            
            let groupExistsInDB = try identityDelegate.checkExistenceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
            guard groupExistsInDB else {
                return FinalState()
            }

            // Get the group own invitation nonce

            let ownGroupInvitationNonce = try identityDelegate.getOwnGroupInvitationNonceOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)

            // Sign the group invitation nonce and send a ping message to the pending member
            
            let challenge = ChallengeType.groupJoinNonce(groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, recipientIdentity: pendingMemberIdentity)
            let signature = try solveChallengeDelegate.solveChallenge(challenge, for: ownedIdentity, using: prng, within: obvContext)
            let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.AsymmetricChannelBroadcast(to: pendingMemberIdentity, fromOwnedIdentity: ownedIdentity))
            let concreteMessage = PingMessage(coreProtocolMessage: coreMessage, groupIdentifier: groupIdentifier, groupInvitationNonce: ownGroupInvitationNonce, signatureOnGroupIdentifierAndInvitationNonceAndRecipientIdentity: signature, isReponse: false)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // We are done
            
            return FinalState()
        }
        
    }
}
