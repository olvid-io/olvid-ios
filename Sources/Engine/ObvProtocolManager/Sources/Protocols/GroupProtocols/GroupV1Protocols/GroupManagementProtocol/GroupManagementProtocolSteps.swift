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
import os.log
import ObvTypes
import ObvMetaManager
import ObvCrypto
import OlvidUtils

// MARK: - Protocol Steps

extension GroupManagementProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case initiateGroupCreation = 0
        case notifyMembersChanged = 1
        case processNewMembers = 2
        case addGroupMembers = 3
        case removeGroupMembers = 4
        case getKicked = 5
        case leaveGroupJoined = 6
        case processGroupLeft = 7
        case queryGroupMembers = 8
        case sendGroupMember = 9
        case reinvite = 10
        case updateMembers = 11
        case disbandGroup = 12
        case processPropagateDisbandGroupMessage = 13
        case processPropagateGroupCreationMessage = 14
        case processPropagateLeaveGroupMessage = 15
        // For now, the ReinvitePendingMemberStep is not implemented
        case processPropagateReinvitePendingMember = 17

        case notifyMembersChangedAfterPhotoUploading = 100 // Copy of NotifyMembersChanged

        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            
            switch self {
                
            case .initiateGroupCreation:
                let step = InitiateGroupCreationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .notifyMembersChanged:
                let step = NotifyMembersChangedStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processNewMembers:
                let step = ProcessNewMembersStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .addGroupMembers:
                let step = AddGroupMembersStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .removeGroupMembers:
                let step = RemoveGroupMembersStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .getKicked:
                let step = GetKickedStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .leaveGroupJoined:
                let step = LeaveGroupJoinedStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processGroupLeft:
                let step = ProcessGroupLeftStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .queryGroupMembers:
                let step = QueryGroupMembersStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .sendGroupMember:
                let step = SendGroupMemberStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .reinvite:
                let step = ReinviteStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .updateMembers:
                let step = UpdateMembersStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .notifyMembersChangedAfterPhotoUploading:
                let step = NotifyMembersChangedAfterPhotoUploadingStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .disbandGroup:
                let step = DisbandGroupStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processPropagateDisbandGroupMessage:
                let step = ProcessPropagateDisbandGroupMessageStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processPropagateGroupCreationMessage:
                let step = ProcessPropagateGroupCreationMessageStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processPropagateLeaveGroupMessage:
                let step = ProcessPropagateLeaveGroupMessageStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processPropagateReinvitePendingMember:
                let step = ProcessPropagateReinvitePendingMemberStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
    }
    
    
    // MARK: - InitiateGroupCreationStep
    
    final class InitiateGroupCreationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateGroupCreationMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.InitiateGroupCreationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)
            
            eraseReceivedMessagesAfterReachingAFinalState = false
            
            let initialGroupInformationWithPhoto = receivedMessage.groupInformationWithPhoto
            let pendingGroupMembers = receivedMessage.pendingGroupMembers
            
            // Check that the pending group members does not contain the owned identity
            
            guard !pendingGroupMembers.map({ $0.cryptoIdentity }).contains(ownedIdentity) else {
                os_log("The group members contain the owned identity", log: log, type: .error)
                assertionFailure()
                return CancelledState()
            }

            // Check that the group owner corresponds the owned identity of this protocol instance
            
            guard initialGroupInformationWithPhoto.groupOwnerIdentity == ownedIdentity else {
                os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
                return CancelledState()
            }
            
            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == initialGroupInformationWithPhoto.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }
            
            
            // Create the ContactGroup in database

            var updatedGroupInformationWithPhoto: GroupInformationWithPhoto
            do {
                // The createContactGroupOwned(...) returns an updated version of the GroupInformationWithPhoto instance
                assert(initialGroupInformationWithPhoto.groupDetailsElementsWithPhoto.photoServerKeyAndLabel == nil)
                updatedGroupInformationWithPhoto = try identityDelegate.createContactGroupOwned(ownedIdentity: ownedIdentity,
                                                                                                groupInformationWithPhoto: initialGroupInformationWithPhoto,
                                                                                                pendingGroupMembers: pendingGroupMembers,
                                                                                                within: obvContext)
            } catch {
                os_log("Could not create contact group", log: log, type: .error)
                return CancelledState()
            }

            if updatedGroupInformationWithPhoto.photoURL != nil {
                assert(updatedGroupInformationWithPhoto.groupDetailsElementsWithPhoto.photoServerKeyAndLabel != nil)
                do {
                                        
                    guard let updatedPhotoURL = updatedGroupInformationWithPhoto.groupDetailsElementsWithPhoto.photoURL else { assertionFailure(); return nil }
                    guard let photoServerLabel = updatedGroupInformationWithPhoto.groupDetailsElementsWithPhoto.photoServerKeyAndLabel?.label else { assertionFailure(); return nil }
                    guard let photoServerKey = updatedGroupInformationWithPhoto.groupDetailsElementsWithPhoto.photoServerKeyAndLabel?.key else { assertionFailure(); return nil }

                    let coreMessage = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                    let concreteMessage = GroupManagementProtocol.UploadGroupPhotoMessage.init(coreProtocolMessage: coreMessage, groupInformation: updatedGroupInformationWithPhoto.groupInformation)
                    let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.putUserData(label: photoServerLabel, dataURL: updatedPhotoURL, dataKey: photoServerKey)
                    guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Error: %{public}@", log: log, type: .error, error.localizedDescription)
                    assertionFailure()
                    // An error occured with the photo, this should not prevent group creation, so we do nothing
                }
            }

            // Propagate the group creation to other owned devices
            
            guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                return CancelledState()
            }
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                let concreteProtocolMessage = PropagateGroupCreationMessage(
                    coreProtocolMessage: coreMessage,
                    groupInformation: updatedGroupInformationWithPhoto.groupInformation,
                    pendingGroupMembers: pendingGroupMembers)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Post an invitation to each group member by starting a child GroupInvitationProtocol
            
            for contactIdentity in pendingGroupMembers.map({ $0.cryptoIdentity }) {
                let childProtocolInstanceUid = UID.gen(with: prng)
                let coreMessage = getCoreMessageForOtherLocalProtocol(otherCryptoProtocolId: .groupInvitation,
                                                                      otherProtocolInstanceUid: childProtocolInstanceUid)
                // We only pass *pending* group members to the initial message of the GroupInvitationProtocol since, at this point, there are no proper members yet
                let childProtocolInitialMessage = GroupInvitationProtocol.InitialMessage(coreProtocolMessage: coreMessage,
                                                                                         contactIdentity: contactIdentity,
                                                                                         groupInformation: updatedGroupInformationWithPhoto.groupInformation,
                                                                                         membersAndPendingGroupMembers: pendingGroupMembers)
                guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            return FinalState()
            
        }
        
    }
    
    
    // MARK: - NotifyMembersChangedStep
    
    final class NotifyMembersChangedStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: GroupMembersChangedTriggerMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.GroupMembersChangedTriggerMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            return try notifyMembersChangedStepImpl(concreteProtocolStep: self, groupInformation: receivedMessage.groupInformation, within: obvContext)
        }
    }
    

    // MARK: - NotifyMembersChangedAfterPhotoUploadingStep

    final class NotifyMembersChangedAfterPhotoUploadingStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: ConcreteProtocolInitialState
        let receivedMessage: UploadGroupPhotoMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.UploadGroupPhotoMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            return try notifyMembersChangedStepImpl(concreteProtocolStep: self, groupInformation: receivedMessage.groupInformation, within: obvContext)
        }
    }

    
    // MARK: - ProcessNewMembersStep
    
    final class ProcessNewMembersStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: NewMembersMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.NewMembersMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let newGroupInformation = receivedMessage.groupInformation
            let groupMembers = receivedMessage.groupMembers
            let pendingMembers = receivedMessage.pendingMembers
            let groupMembersVersion = receivedMessage.groupMembersVersion
            
            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == newGroupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }

            // Determine the origin of the message
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessNewMembersStep)", log: log, type: .error)
                return CancelledState()
            }
            
            // Check that the remote identity is the group owner
            
            guard newGroupInformation.groupOwnerIdentity == remoteIdentity else {
                os_log("The message was not sent by the group owner", log: log, type: .error)
                return CancelledState()
            }

            // Get the group structure from database
            
            let groupStructureOrNil: GroupStructure?
            
            if remoteIdentity == ownedIdentity {
                do {
                    groupStructureOrNil = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: newGroupInformation.groupUid, within: obvContext)
                } catch {
                    os_log("Could not access the group in database", log: log, type: .error)
                    return CancelledState()
                }
            } else {
                do {
                    groupStructureOrNil = try identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedIdentity, groupUid: newGroupInformation.groupUid, groupOwner: newGroupInformation.groupOwnerIdentity, within: obvContext)
                } catch {
                    os_log("Could not access the group in database", log: log, type: .error)
                    return CancelledState()
                }
            }
            

            // If the group structure is nil, it means that we have not joined the group yet, which is not expected at this point.
            
            guard let groupStructure = groupStructureOrNil else {
                os_log("The group structure is nil, which is unexpected", log: log, type: .error)
                return CancelledState()
            }
            
            // If we reach this point, we can update the group
            
            
            if remoteIdentity == ownedIdentity {
                // Check that the group is one we joined, not one we own
                guard groupStructure.groupType == .owned else {
                    os_log("The group is not one we own", log: log, type: .error)
                    return CancelledState()
                }
            } else {
                // Check that the group is one we joined, not one we own
                guard groupStructure.groupType == .joined else {
                    os_log("The group is not one we joined", log: log, type: .error)
                    return CancelledState()
                }
            }
            
            // Check that the received member version is more recent than the one we already know about

            guard groupMembersVersion >= groupStructure.groupMembersVersion else {
                os_log("The received group member version is not more recent than the one we already know about", log: log, type: .info)
                return FinalState()
            }
            
            let newGroupDetails = newGroupInformation.groupDetailsElements
            
            // Check if a group photo needs to be downloaded

            if newGroupDetails.photoServerKeyAndLabel != nil {
                
                let publishedDetailsWithPhoto: GroupInformationWithPhoto
                if remoteIdentity == ownedIdentity {
                    
                    do {
                        publishedDetailsWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity, groupUid: newGroupInformation.groupUid, within: obvContext)
                    } catch {
                        os_log("Could not get details of published group", log: log, type: .error)
                        return CancelledState()
                    }
                    
                } else {
                    
                    do {
                        publishedDetailsWithPhoto = try identityDelegate.getGroupJoinedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity, groupUid: newGroupInformation.groupUid, groupOwner: newGroupInformation.groupOwnerIdentity, within: obvContext)
                    } catch {
                        os_log("Could not get details of published group", log: log, type: .error)
                        return CancelledState()
                    }

                }
                
                let currentGroupDetailsElementsWithPhoto = publishedDetailsWithPhoto.groupDetailsElementsWithPhoto
                let currentPhotoURL = publishedDetailsWithPhoto.groupDetailsElementsWithPhoto.photoURL
                let photoServerKeyAndLabelAreDistinct = currentGroupDetailsElementsWithPhoto.photoServerKeyAndLabel != newGroupDetails.photoServerKeyAndLabel
                
                if currentPhotoURL == nil || photoServerKeyAndLabelAreDistinct {
                    
                    // Launch a child protocol instance for downloading the photo. To do so, we post an appropriate message on the loopback channel. In this particular case, we do not need to "link" this protocol to the current protocol.
                    
                    let childProtocolInstanceUid = UID.gen(with: prng)
                    let coreMessage = getCoreMessageForOtherLocalProtocol(
                        otherCryptoProtocolId: .downloadGroupPhoto,
                        otherProtocolInstanceUid: childProtocolInstanceUid)
                    let childProtocolInitialMessage = DownloadGroupPhotoChildProtocol.InitialMessage(
                        coreProtocolMessage: coreMessage,
                        groupInformation: newGroupInformation)
                    guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                    
                }
                
                
            }

            // Update the details of the group with the new details
            
            if remoteIdentity == ownedIdentity {
                
                do {
                    let groupDetailsElementsWithPhoto = GroupDetailsElementsWithPhoto(groupDetailsElements: newGroupInformation.groupDetailsElements, photoURL: nil)
                    try identityDelegate.updateLatestDetailsOfContactGroupOwned(
                        ownedIdentity: ownedIdentity,
                        groupUid: newGroupInformation.groupUid,
                        with: groupDetailsElementsWithPhoto,
                        within: obvContext)
                    try identityDelegate.publishLatestDetailsOfContactGroupOwned(ownedIdentity: ownedIdentity, groupUid: newGroupInformation.groupUid, within: obvContext)
                } catch {
                    os_log("Could not update latest details of the contact group owned", log: log, type: .error)
                    // We do not return
                }

                do {
                    try identityDelegate.updatePendingMembersAndGroupMembersOfContactGroupOwned(ownedIdentity: ownedIdentity,
                                                                                                groupUid: newGroupInformation.groupUid,
                                                                                                groupMembers: groupMembers,
                                                                                                pendingGroupMembers: pendingMembers,
                                                                                                groupMembersVersion: groupMembersVersion,
                                                                                                within: obvContext)
                } catch {
                    os_log("Could not update pending members nor group members of the joined contact group", log: log, type: .error)
                    // We do not return
                }

            } else {
                do {
                    try identityDelegate.updatePublishedDetailsOfContactGroupJoined(ownedIdentity: ownedIdentity,
                                                                                    groupInformation: newGroupInformation,
                                                                                    within: obvContext)
                } catch {
                    os_log("Could not update published details of the contact group joined", log: log, type: .error)
                    // We do not return
                }

                // Update the pending members and the group members of the joined contact group
                
                do {
                    try identityDelegate.updatePendingMembersAndGroupMembersOfContactGroupJoined(ownedIdentity: ownedIdentity,
                                                                                                 groupUid: newGroupInformation.groupUid,
                                                                                                 groupOwner: newGroupInformation.groupOwnerIdentity,
                                                                                                 groupMembers: groupMembers,
                                                                                                 pendingGroupMembers: pendingMembers,
                                                                                                 groupMembersVersion: groupMembersVersion,
                                                                                                 within: obvContext)
                } catch {
                    os_log("Could not update pending members nor group members of the joined contact group", log: log, type: .error)
                    // We do not return
                }

            }


            // Return the new state
            
            return FinalState()

        }
    }
    
    
    // MARK: - AddGroupMembersStep
    
    final class AddGroupMembersStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: AddGroupMembersMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.AddGroupMembersMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)

            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInformation = receivedMessage.groupInformation
            let newGroupMembers = receivedMessage.newGroupMembers

            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }
            
            // Check that the owned identity is the group owner
            
            guard groupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The message was not sent by the group owner", log: log, type: .error)
                return CancelledState()
            }

            // Add pending members to the group and notify existing members (in the callback)
            
            let ownedIdentity = self.ownedIdentity
            let groupUid = groupInformation.groupUid
            let localPrng = prng
            
            // We need the following delegates in the callback
            
            let identityDelegate = self.identityDelegate
            let channelDelegate = self.channelDelegate
            
            let groupMembersChangedCallback = {
                
                let groupInformationWithPhoto: GroupInformationWithPhoto
                do {
                    groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity,
                                                                                                               groupUid: groupUid,
                                                                                                               within: obvContext)
                } catch {
                    os_log("Could not get group information", log: log, type: .fault)
                    return
                }
                
                let childProtocolInstanceUid = groupInformationWithPhoto.associatedProtocolUid
                let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .groupManagement,
                                                      protocolInstanceUid: childProtocolInstanceUid)
                let childProtocolInitialMessage = GroupManagementProtocol.GroupMembersChangedTriggerMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformationWithPhoto.groupInformation)
                guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: localPrng) else {
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: localPrng, within: obvContext)
                
            }
            
            do {
                try identityDelegate.addPendingMembersToContactGroupOwned(ownedIdentity: ownedIdentity,
                                                                          groupUid: groupUid,
                                                                          newPendingMembers: newGroupMembers,
                                                                          within: obvContext,
                                                                          groupMembersChangedCallback: groupMembersChangedCallback)
            } catch {
                os_log("Could not add pending members to owned contact group", log: log, type: .error)
                return CancelledState()
            }
            
            // Get the group structure from database
            
            let groupStructure: GroupStructure
            do {
                guard let _groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, within: obvContext) else {
                    throw Self.makeError(message: "Could not get group owned structure")
                }
                groupStructure = _groupStructure
            } catch {
                os_log("Could not access the group in database", log: log, type: .error)
                return CancelledState()
            }

            // Post invitations to the new pending members
            
            let pendingGroupMembers = groupStructure.pendingGroupMembers
            let groupMembers: Set<CryptoIdentityWithCoreDetails> = Set(try groupStructure.groupMembers.map { (cryptoIdentity) in
                let allContactDetails = try identityDelegate.getIdentityDetailsOfContactIdentity(cryptoIdentity,
                                                                                                 ofOwnedIdentity: ownedIdentity,
                                                                                                 within: obvContext)
                let details = allContactDetails.publishedIdentityDetails ?? allContactDetails.trustedIdentityDetails
                return CryptoIdentityWithCoreDetails(cryptoIdentity: cryptoIdentity, coreDetails: details.coreDetails)
                })
            let membersAndPendingGroupMembers = pendingGroupMembers.union(groupMembers)
            
            assert(!membersAndPendingGroupMembers.map({ $0.cryptoIdentity }).contains(ownedIdentity))
            
            for contactIdentity in newGroupMembers {
                let childProtocolInstanceUid = UID.gen(with: prng)
                let coreMessage = getCoreMessageForOtherLocalProtocol(otherCryptoProtocolId: .groupInvitation,
                                                                      otherProtocolInstanceUid: childProtocolInstanceUid)
                // Note that the initial message of the GroupInvitationProtocol expects the list of (pending) members to *not* include the group owned, i.e., *not* include the owned identity.
                let childProtocolInitialMessage = GroupInvitationProtocol.InitialMessage(coreProtocolMessage: coreMessage,
                                                                                         contactIdentity: contactIdentity,
                                                                                         groupInformation: groupInformation,
                                                                                         membersAndPendingGroupMembers: membersAndPendingGroupMembers)
                guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            return FinalState()
        }
            
    }

    
    // MARK: - RemoveGroupMembersStep
    
    final class RemoveGroupMembersStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: RemoveGroupMembersMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.RemoveGroupMembersMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInformation = receivedMessage.groupInformation
            let removedGroupMembers = receivedMessage.removedGroupMembers
            
            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }
            
            // Check that the remote identity is the group owner
            
            guard groupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The message was not sent by the group owner", log: log, type: .error)
                return CancelledState()
            }

            // Remove members from the group and notify remaining members (in the callback)
            
            let ownedIdentity = self.ownedIdentity
            let groupUid = groupInformation.groupUid
            let localPrng = prng
            
            // We need the following delegates in the callback
            
            let identityDelegate = self.identityDelegate
            let channelDelegate = self.channelDelegate

            let groupMembersChangedCallback = {
                
                let groupInformationWithPhoto: GroupInformationWithPhoto
                do {
                    groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity,
                                                                                                               groupUid: groupUid,
                                                                                                               within: obvContext)
                } catch {
                    os_log("Could not get group information", log: log, type: .fault)
                    return
                }
                
                let childProtocolInstanceUid = groupInformationWithPhoto.associatedProtocolUid
                let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .groupManagement,
                                                      protocolInstanceUid: childProtocolInstanceUid)
                let childProtocolInitialMessage = GroupManagementProtocol.GroupMembersChangedTriggerMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformationWithPhoto.groupInformation)
                guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: localPrng) else {
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: localPrng, within: obvContext)
                
            }

            do {
                try identityDelegate.removePendingAndMembersToContactGroupOwned(ownedIdentity: ownedIdentity,
                                                                                groupUid: groupUid,
                                                                                pendingOrMembersToRemove: removedGroupMembers,
                                                                                within: obvContext,
                                                                                groupMembersChangedCallback: groupMembersChangedCallback)
            } catch {
                os_log("Could not remove pending or group members from owned contact group", log: log, type: .error)
                return CancelledState()
            }
            
            // Notify members that have been kicked
            
            for removedGroupMember in removedGroupMembers {
                let coreMessage = CoreProtocolMessage(channelType: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: Set([removedGroupMember]), fromOwnedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .groupManagement,
                                                      protocolInstanceUid: protocolInstanceUid)
                let concreteProtocolMessage = KickFromGroupMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformation)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    return CancelledState()
                }
                
                do {
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not notify member that she has been kicked out from group owned", log: log, type: .error)
                    // Continue
                }

            }
            
            return FinalState()
        }
        
    }

    
    // MARK: - GetKickedStep
    
    final class GetKickedStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: KickFromGroupMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.KickFromGroupMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)
            
            eraseReceivedMessagesAfterReachingAFinalState = true

            let groupInformation = receivedMessage.groupInformation
            
            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }

            // Determine the origin of the message
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessNewMembersStep)", log: log, type: .error)
                return CancelledState()
            }

            // Check that the remote identity is the group owner
            
            guard groupInformation.groupOwnerIdentity == remoteIdentity else {
                os_log("The message was not sent by the group owner", log: log, type: .error)
                return CancelledState()
            }

            // Delete the group
            
            do {
                try identityDelegate.deleteContactGroupJoined(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, groupOwner: groupInformation.groupOwnerIdentity, within: obvContext)
            } catch let error {
                os_log("Could not leave group joined: %{public}@", log: log, type: .error, error.localizedDescription)
                return CancelledState()
            }
            
            return FinalState()
        }
        
    }
    
    
    // MARK: - LeaveGroupJoinedStep
    
    final class LeaveGroupJoinedStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: LeaveGroupJoinedMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.LeaveGroupJoinedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)
            
            eraseReceivedMessagesAfterReachingAFinalState = true
            
            let groupInformation = receivedMessage.groupInformation
            
            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                assertionFailure()
                return CancelledState()
            }

            // Check that we are not the group owner
            
            guard groupInformation.groupOwnerIdentity != ownedIdentity else {
                os_log("Trying to leave a group for which we are the group owned", log: log, type: .error)
                return CancelledState()
            }

            do {
                
                let protocolInstanceUidForGroupManagement = groupInformation.associatedProtocolUid
                let coreMessage = CoreProtocolMessage(channelType: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: Set([groupInformation.groupOwnerIdentity]), fromOwnedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .groupManagement,
                                                      protocolInstanceUid: protocolInstanceUidForGroupManagement)
                let concreteProtocolMessage = GroupManagementProtocol.NotifyGroupLeftMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformation)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    os_log("Could not generate ObvChannelProtocolMessageToSend for a NotifyGroupLeftMessage from within the GroupInvitationProtocol.", log: log, type: .info)
                    return CancelledState()
                }
                
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)

            } catch {
                // This can happen if we have no oblivious channel and no pre-key with the contact. We could not notify the group owner, but we continue anyway
                os_log("Could not notify the group owner that we wish to leave the group: %{public}@. We continue anyway.", log: log, type: .error, error.localizedDescription)
                assertionFailure()
            }
            
            // Propagate to our other owned devices
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                let concreteProtocolMessage = PropagateLeaveGroupMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformation)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Delete the group within the identity manager
            
            do {
                try identityDelegate.deleteContactGroupJoined(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, groupOwner: groupInformation.groupOwnerIdentity, within: obvContext)
            } catch {
                os_log("The call to leaveContactGroupJoined of the identity manager failed", log: log, type: .error)
                return CancelledState()
            }
            
            return FinalState()
        }
        
    }

    
    // MARK: - ProcessGroupLeftStep
    
    final class ProcessGroupLeftStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: NotifyGroupLeftMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.NotifyGroupLeftMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)
            
            eraseReceivedMessagesAfterReachingAFinalState = false
            
            let groupInformation = receivedMessage.groupInformation

            // Check that the group owner corresponds the owned identity of this protocol instance
            
            guard groupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
                return CancelledState()
            }
            
            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }

            // Determine the origin of the message (i.e., the member who wishes to leave the group)
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessNewMembersStep)", log: log, type: .error)
                return CancelledState()
            }

            // Remove members from the group and notify remaining members (in the callback)
            
            let ownedIdentity = self.ownedIdentity
            let groupUid = groupInformation.groupUid
            let localPrng = prng
            
            // We need the following delegates in the callback
            
            let identityDelegate = self.identityDelegate
            let channelDelegate = self.channelDelegate

            let groupMembersChangedCallback = {
                
                let groupInformationWithPhoto: GroupInformationWithPhoto
                do {
                    groupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity,
                                                                                                               groupUid: groupUid,
                                                                                                               within: obvContext)
                } catch {
                    os_log("Could not get group information", log: log, type: .fault)
                    return
                }
                
                let childProtocolInstanceUid = groupInformationWithPhoto.associatedProtocolUid
                let coreMessage = CoreProtocolMessage(channelType: .local(ownedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .groupManagement,
                                                      protocolInstanceUid: childProtocolInstanceUid)
                let childProtocolInitialMessage = GroupManagementProtocol.GroupMembersChangedTriggerMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformationWithPhoto.groupInformation)
                guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: localPrng) else {
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: localPrng, within: obvContext)
                
            }
            
            do {
                try identityDelegate.removePendingAndMembersToContactGroupOwned(ownedIdentity: ownedIdentity,
                                                                                groupUid: groupUid,
                                                                                pendingOrMembersToRemove: Set([remoteIdentity]),
                                                                                within: obvContext,
                                                                                groupMembersChangedCallback: groupMembersChangedCallback)
            } catch {
                os_log("Could not remove pending or group members from owned contact group", log: log, type: .error)
                return CancelledState()
            }
            
            return FinalState()
        }
        
    }
    
    
    // MARK: - QueryGroupMemberStep
    
    /// This step is executed by a member of a group joined, so as to query the group owner about the latest informations about the group.
    final class QueryGroupMembersStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateGroupMembersQueryMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.InitiateGroupMembersQueryMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInformation = receivedMessage.groupInformation

            // Check that we are not the group owner
            
            guard groupInformation.groupOwnerIdentity != ownedIdentity else {
                os_log("Trying to leave a group for which we are the group owned", log: log, type: .error)
                return CancelledState()
            }
            
            // Send a query message to the group owner
            
            let protocolInstanceUidForGroupManagement = groupInformation.associatedProtocolUid
            let coreMessage = CoreProtocolMessage(channelType: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: Set([groupInformation.groupOwnerIdentity]), fromOwnedIdentity: ownedIdentity),
                                                  cryptoProtocolId: .groupManagement,
                                                  protocolInstanceUid: protocolInstanceUidForGroupManagement)
            let concreteProtocolMessage = GroupManagementProtocol.QueryGroupMembersMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformation)
            guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                os_log("Could not generate ObvChannelProtocolMessageToSend for a QueryGroupMembersMessage from within the GroupInvitationProtocol.", log: log, type: .info)
                return CancelledState()
            }
            
            do {
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not ask the group owner about the latest version of the group members", log: log, type: .error)
                return CancelledState()
            }

            return FinalState()
            
        }
        
    }
    
    
    // MARK: - SendGroupMemberStep
    
    final class SendGroupMemberStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: QueryGroupMembersMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.QueryGroupMembersMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)
            
            eraseReceivedMessagesAfterReachingAFinalState = false
            
            let receivedGroupInformation = receivedMessage.groupInformation

            // Check that the group owner corresponds the owned identity of this protocol instance
            
            guard receivedGroupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
                return CancelledState()
            }

            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == receivedGroupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }

            // Determine the origin of the message
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessNewMembersStep)", log: log, type: .error)
                return CancelledState()
            }

            // Get the group structure from database
            
            let groupStructure: GroupStructure
            do {
                guard let _groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: receivedGroupInformation.groupUid, within: obvContext) else {
                    // The group does not exist, kick the remote identy out
                    
                    os_log("The remote identity asks for informations about a group that does not exists (it was deleted?). We kick this contact out.", log: log, type: .info)
                    
                    let coreMessage = CoreProtocolMessage(channelType: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: Set([remoteIdentity]), fromOwnedIdentity: ownedIdentity),
                                                          cryptoProtocolId: .groupManagement,
                                                          protocolInstanceUid: protocolInstanceUid)
                    let concreteProtocolMessage = KickFromGroupMessage(coreProtocolMessage: coreMessage, groupInformation: receivedGroupInformation)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        return CancelledState()
                    }
                    
                    do {
                        _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Could not notify a remote identity that she was kicked from a group owned (that we cannot find, maybe because it was deleted in the past).", log: log, type: .error)
                        // Continue
                    }
                    
                    return FinalState()

                }
                groupStructure = _groupStructure
            } catch {
                os_log("Could not access the group in database", log: log, type: .error)
                return CancelledState()
            }
            
            // Create a list of group members with serialized details
            
            var groupMembersWithCoreDetails: Set<CryptoIdentityWithCoreDetails>
            do {
                groupMembersWithCoreDetails = Set(try groupStructure.groupMembers.map { (contactIdentity) in
                    let allDetails = try identityDelegate.getIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                    let details = allDetails.publishedIdentityDetails ?? allDetails.trustedIdentityDetails
                    return CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: details.coreDetails)
                    })
            } catch {
                os_log("Could not get all the details of the group members", log: log, type: .fault)
                return CancelledState()
            }

            // Also add the yourself (group owner) to the group
            
            do {
                let ownedDetails = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext)
                groupMembersWithCoreDetails.insert(CryptoIdentityWithCoreDetails.init(cryptoIdentity: ownedIdentity, coreDetails: ownedDetails.ownedIdentityDetailsElements.coreDetails))
            } catch {
                os_log("Could not get owned published details", log: log, type: .fault)
                return CancelledState()
            }
                                    
            // Check that the remote identity is part of the group members or of the pending members. If this is not the case, send her a kick
            
            guard groupMembersWithCoreDetails.map({ $0.cryptoIdentity }).contains(remoteIdentity) || groupStructure.pendingGroupMembers.map({ $0.cryptoIdentity }).contains(remoteIdentity) else {

                os_log("The remote identity is not part of the group members nor of the pending members. We kick this contact out.", log: log, type: .info)
                
                let coreMessage = CoreProtocolMessage(channelType: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: Set([remoteIdentity]), fromOwnedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .groupManagement,
                                                      protocolInstanceUid: protocolInstanceUid)
                let concreteProtocolMessage = KickFromGroupMessage(coreProtocolMessage: coreMessage, groupInformation: receivedGroupInformation)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    return CancelledState()
                }
                
                do {
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not notify a remote identity that she was kicked from a group owned she doesn't belong to anyway", log: log, type: .error)
                    // Continue
                }
                
                return FinalState()
                
            }
            
            // If we reach this line, the remote identity is indeed a member or a pending member of the group.
            // Send a message to the contact informing her of the latest informations about the group
            
            let latestGroupInformationWithPhoto: GroupInformationWithPhoto
            do {
                latestGroupInformationWithPhoto = try identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity, groupUid: receivedGroupInformation.groupUid, within: obvContext)
            } catch {
                os_log("Could not get the latest group informations of an owned group", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }
            
            let protocolInstanceUidForGroupManagement = receivedGroupInformation.associatedProtocolUid
            let coreMessage = CoreProtocolMessage(channelType: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: Set([remoteIdentity]), fromOwnedIdentity: ownedIdentity),
                                                  cryptoProtocolId: .groupManagement,
                                                  protocolInstanceUid: protocolInstanceUidForGroupManagement)
            let concreteProtocolMessage = NewMembersMessage(coreProtocolMessage: coreMessage, groupInformation: latestGroupInformationWithPhoto.groupInformation, groupMembers: groupMembersWithCoreDetails, pendingMembers: groupStructure.pendingGroupMembers, groupMembersVersion: groupStructure.groupMembersVersion)
            guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                os_log("Could not generate ObvChannelProtocolMessageToSend for a NewMembersMessage from within the GroupInvitationProtocol.", log: log, type: .info)
                return CancelledState()
            }
            
            do {
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not send the latest version of the group members to a group member", log: log, type: .error)
                return CancelledState()
            }

            return FinalState()
            
        }
        
    }

    
    // MARK: - ReinviteStep
    
    final class ReinviteStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: TriggerReinviteMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.TriggerReinviteMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInformation = receivedMessage.groupInformation
            let memberIdentity = receivedMessage.memberIdentity
            
            // Check that the group owner corresponds the owned identity of this protocol instance
            
            guard groupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
                return CancelledState()
            }

            // Check that we are not trying te re-invite our owned identity to the group
            
            guard memberIdentity != ownedIdentity else {
                os_log("Tryining to reinvite our own identity to a group she owns.", log: log, type: .fault)
                return CancelledState()
            }
            
            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }

            // Get the group structure from database
            
            let groupStructure: GroupStructure
            do {
                guard let _groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, within: obvContext) else {
                    os_log("The group does not exist. This is unexpected since this step should never have been started in that case.", log: log, type: .error)
                    return CancelledState()
                }
                groupStructure = _groupStructure
            } catch {
                os_log("Could not access the group in database", log: log, type: .error)
                return CancelledState()
            }
            
            // Create a list of group members with serialized details
            
            let groupMembersWithCoreDetails: Set<CryptoIdentityWithCoreDetails>
            do {
                groupMembersWithCoreDetails = Set(try groupStructure.groupMembers.map { (contactIdentity) in
                    let allDetails = try identityDelegate.getIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                    let details = allDetails.publishedIdentityDetails ?? allDetails.trustedIdentityDetails
                    return CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: details.coreDetails)
                    })
            } catch {
                os_log("Could not get all the details of the group members", log: log, type: .fault)
                return CancelledState()
            }
            
            // Create a list of group members union pending members (without the owned identity)
            
            let pendingGroupMembers = groupStructure.pendingGroupMembers
            let membersAndPendingGroupMembers = pendingGroupMembers.union(groupMembersWithCoreDetails)
            
            // Check that the remote identity is part of the group members or of the pending group members.
            
            guard membersAndPendingGroupMembers.map({ $0.cryptoIdentity }).contains(memberIdentity) else {
                os_log("The remote identity is not part of the group members nor of the pending group members. This is unexpected since this step should not be triggered in this case.", log: log, type: .error)
                return CancelledState()
            }

            // In addtion to the previous message, we send an invite. If the member is aware that she is part of the group, this invite will be silently discarded. If she is not, the previous message will certain be useless, since we need to invite her first. This is what we do here.

            let childProtocolInstanceUid = UID.gen(with: prng)
            let coreMessage = getCoreMessageForOtherLocalProtocol(otherCryptoProtocolId: .groupInvitation,
                                                                  otherProtocolInstanceUid: childProtocolInstanceUid)
            // Note that the InitialMessage below expects that the membersAndPendingGroupMembers does *not* contain the owned identity, i.e., does *not* contain the group owner
            let childProtocolInitialMessage = GroupInvitationProtocol.InitialMessage(coreProtocolMessage: coreMessage,
                                                                                     contactIdentity: memberIdentity,
                                                                                     groupInformation: groupInformation,
                                                                                     membersAndPendingGroupMembers: membersAndPendingGroupMembers)
            guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                assertionFailure()
                throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
            }
            do {
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post a (local) initial message for the GroupInvitationProtocol", log: log, type: .fault)
                return CancelledState()
            }

            return FinalState()
        }
    }
    
    
    // MARK: - UpdateMembersStep
    
    final class UpdateMembersStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: TriggerUpdateMembersMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupManagementProtocol.TriggerUpdateMembersMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)
            
            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInformation = receivedMessage.groupInformation
            let memberIdentity = receivedMessage.memberIdentity
            
            // Check that the group owner corresponds the owned identity of this protocol instance
            
            guard groupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
                return CancelledState()
            }

            // Check that we are not trying te re-invite our owned identity to the group
            
            guard memberIdentity != ownedIdentity else {
                os_log("Tryining to reinvite our own identity to a group she owns.", log: log, type: .fault)
                return CancelledState()
            }
            
            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }

            // Get the group structure from database
            
            let groupStructure: GroupStructure
            do {
                guard let _groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, within: obvContext) else {
                    os_log("The group does not exist. This is unexpected since this step should never have been started in that case.", log: log, type: .error)
                    return CancelledState()
                }
                groupStructure = _groupStructure
            } catch {
                os_log("Could not access the group in database", log: log, type: .error)
                return CancelledState()
            }
            
            // Create a list of group members with serialized details
            
            let groupMembersWithCoreDetails: Set<CryptoIdentityWithCoreDetails>
            do {
                groupMembersWithCoreDetails = Set(try groupStructure.groupMembers.map { (contactIdentity) in
                    let allDetails = try identityDelegate.getIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                    let details = allDetails.publishedIdentityDetails ?? allDetails.trustedIdentityDetails
                    return CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: details.coreDetails)
                    })
            } catch {
                os_log("Could not get all the details of the group members", log: log, type: .fault)
                return CancelledState()
            }
            
            // Create a list of group members union pending members (without the owned identity)
            
            let pendingGroupMembers = groupStructure.pendingGroupMembers
            let membersAndPendingGroupMembers = pendingGroupMembers.union(groupMembersWithCoreDetails)

            // Create a new list of group members, containing the owned identity
            
            let ownedIdentityAndGroupMembersWithCoreDetails: Set<CryptoIdentityWithCoreDetails>
            do {
                let ownedDetails = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext)
                ownedIdentityAndGroupMembersWithCoreDetails = groupMembersWithCoreDetails.union([CryptoIdentityWithCoreDetails.init(cryptoIdentity: ownedIdentity, coreDetails: ownedDetails.ownedIdentityDetailsElements.coreDetails)])
            } catch {
                os_log("Could not get owned published details", log: log, type: .fault)
                return CancelledState()
            }
            
            // Check that the remote identity is part of the group members or of the pending group members.
            
            guard membersAndPendingGroupMembers.map({ $0.cryptoIdentity }).contains(memberIdentity) else {
                os_log("The remote identity is not part of the group members nor of the pending group members. This is unexpected since this step should not be triggered in this case.", log: log, type: .error)
                return CancelledState()
            }

            // Send a NewMembers message to the group member. In case this member is aware to be a member of this group, this will force this member to have the same list of members and pending members as the one we have as a group owner.

            if groupMembersWithCoreDetails.map({ $0.cryptoIdentity }).contains(memberIdentity) {
                do {
                    let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: [memberIdentity], fromOwnedIdentity: ownedIdentity))
                    /* Note that the NewMembersMessage expects the list of group members to include the owned identity, i.e., the group owner */
                    let concreteProtocolMessage = NewMembersMessage(coreProtocolMessage: coreMessage,
                                                                    groupInformation: groupInformation,
                                                                    groupMembers: ownedIdentityAndGroupMembersWithCoreDetails,
                                                                    pendingMembers: pendingGroupMembers,
                                                                    groupMembersVersion: groupStructure.groupMembersVersion)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not post NewMembersMessage", log: log, type: .fault)
                    return CancelledState()
                }
            }
            
            return FinalState()
        }
    }

    
    // MARK: - DisbandGroupStep
    
    final class DisbandGroupStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: DisbandGroupMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: DisbandGroupMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)

            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInformation = receivedMessage.groupInformation
            
            // Check that the group owner corresponds the owned identity of this protocol instance
            
            guard groupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
                return CancelledState()
            }

            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }

            // Get the group structure from database
            
            let groupStructure: GroupStructure
            do {
                guard let _groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, within: obvContext) else {
                    os_log("The group does not exist. This is unexpected since this step should never have been started in that case.", log: log, type: .error)
                    return CancelledState()
                }
                groupStructure = _groupStructure
            } catch {
                os_log("Could not access the group in database", log: log, type: .error)
                return CancelledState()
            }

            // Send a KickFromGroupMessage to all members and pending members of the group

            do {
                let coreMessage = CoreProtocolMessage(channelType: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: groupStructure.groupMembers, fromOwnedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .groupManagement,
                                                      protocolInstanceUid: protocolInstanceUid)
                let concreteProtocolMessage = KickFromGroupMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformation)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    return CancelledState()
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            do {
                let coreMessage = CoreProtocolMessage(channelType: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: groupStructure.pendingGroupMembersIdentities, fromOwnedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .groupManagement,
                                                      protocolInstanceUid: protocolInstanceUid)
                let concreteProtocolMessage = KickFromGroupMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformation)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    return CancelledState()
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Propagate the disband to our other owned devices
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                let concreteProtocolMessage = PropagateDisbandGroupMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformation)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Delete the group
            
            try identityDelegate.deleteContactGroupOwned(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, deleteEvenIfGroupMembersStillExist: true, within: obvContext)
            
            // Return the final state
            
            return FinalState()

        }
    }

    
    // MARK: - ProcessPropagateDisbandGroupMessageStep
    
    final class ProcessPropagateDisbandGroupMessageStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateDisbandGroupMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: PropagateDisbandGroupMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)

            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInformation = receivedMessage.groupInformation
            
            // Check that the group owner corresponds the owned identity of this protocol instance
            
            guard groupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
                return CancelledState()
            }

            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }

            // Delete the group
            
            try identityDelegate.deleteContactGroupOwned(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, deleteEvenIfGroupMembersStillExist: true, within: obvContext)
            
            // Return the final state

            return FinalState()

        }
    }

    
    // MARK: - ProcessPropagateLeaveGroupMessageStep
    
    final class ProcessPropagateLeaveGroupMessageStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateLeaveGroupMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: PropagateLeaveGroupMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)

            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInformation = receivedMessage.groupInformation
            
            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                assertionFailure()
                return CancelledState()
            }

            // Check that we are not the group owner
            
            guard groupInformation.groupOwnerIdentity != ownedIdentity else {
                os_log("Trying to leave a group for which we are the group owned", log: log, type: .error)
                return CancelledState()
            }

            // Delete the group
            
            try identityDelegate.deleteContactGroupJoined(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, groupOwner: groupInformation.groupOwnerIdentity, within: obvContext)
            
            // Return the final state

            return FinalState()

        }
    }
    
    
    // MARK: - ProcessPropagateReinvitePendingMemberStep
    
    // Note: This step has been implemented on 2023-10-08 to maintain compatibility with the Android version of Olvid.
    // The step sending the PropagateReinvitePendingMemberMessage has not been implemented yet under iOS.
    
    final class ProcessPropagateReinvitePendingMemberStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateReinvitePendingMemberMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: PropagateReinvitePendingMemberMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)

            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInformation = receivedMessage.groupInformation
            let pendingMemberIdentity = receivedMessage.pendingMemberIdentity

            // Check that the group owner corresponds the owned identity of this protocol instance
            
            guard groupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
                return CancelledState()
            }

            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }

            // Mark the pending member as "not declined"
            
            try identityDelegate.unmarkDeclinedPendingMemberAsDeclined(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, pendingMember: pendingMemberIdentity, within: obvContext)

            return FinalState()

        }
    }

    
    // MARK: - ProcessPropagateGroupCreationMessageStep
    
    final class ProcessPropagateGroupCreationMessageStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateGroupCreationMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: PropagateGroupCreationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)

            eraseReceivedMessagesAfterReachingAFinalState = false

            let groupInformation = receivedMessage.groupInformation
            let pendingGroupMembers = receivedMessage.pendingGroupMembers
            
            // Check that the pending group members does not contain the owned identity
            
            guard !pendingGroupMembers.map({ $0.cryptoIdentity }).contains(ownedIdentity) else {
                os_log("The group members contain the owned identity", log: log, type: .error)
                assertionFailure()
                return CancelledState()
            }

            // Check that the group owner corresponds the owned identity of this protocol instance
            
            guard groupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
                return CancelledState()
            }

            // Check that the protocol uid of this protocol corresponds to the group information
            
            guard protocolInstanceUid == groupInformation.associatedProtocolUid else {
                os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
                return CancelledState()
            }
            
            // Create the ContactGroup in database

            do {
                // The createContactGroupOwned(...) returns an updated version of the GroupInformationWithPhoto instance
                let groupInformationWithPhoto = GroupInformationWithPhoto(groupInformation: groupInformation, photoURL: nil)
                _ = try identityDelegate.createContactGroupOwned(ownedIdentity: ownedIdentity,
                                                                 groupInformationWithPhoto: groupInformationWithPhoto,
                                                                 pendingGroupMembers: pendingGroupMembers,
                                                                 within: obvContext)
            } catch {
                os_log("Could not create contact group", log: log, type: .error)
                return CancelledState()
            }

            // If there is a group photo, download it now
            
            if groupInformation.groupDetailsElements.photoServerKeyAndLabel != nil {
                do {
                    let childProtocolInstanceUid = UID.gen(with: prng)
                    let coreMessage = getCoreMessageForOtherLocalProtocol(
                        otherCryptoProtocolId: .downloadGroupPhoto,
                        otherProtocolInstanceUid: childProtocolInstanceUid)
                    let childProtocolInitialMessage = DownloadGroupPhotoChildProtocol.InitialMessage(
                        coreProtocolMessage: coreMessage,
                        groupInformation: groupInformation)
                    guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Error: %{public}@", log: log, type: .error, error.localizedDescription)
                    assertionFailure()
                    // An error occured with the photo, this should not prevent group creation, so we do nothing
                }
            }

            // Return the final state

            return FinalState()

        }
    }

}

extension ProtocolStep {

    fileprivate func notifyMembersChangedStepImpl(concreteProtocolStep step: ConcreteProtocolStep, groupInformation: GroupInformation, within obvContext: ObvContext) throws -> ConcreteProtocolState? {

        let log = OSLog(subsystem: step.delegateManager.logSubsystem, category: GroupManagementProtocol.logCategory)

        guard let identityDelegate = step.delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return GroupManagementProtocol.CancelledState()
        }

        guard let channelDelegate = step.delegateManager.channelDelegate else {
            os_log("The channel delegate is not set", log: log, type: .fault)
            return GroupManagementProtocol.CancelledState()
        }

        // Check that the group owner corresponds the owned identity of this protocol instance

        guard groupInformation.groupOwnerIdentity == step.ownedIdentity else {
            os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
            return GroupManagementProtocol.CancelledState()
        }

        // Check that the protocol uid of this protocol corresponds to the group information

        guard step.protocolInstanceUid == groupInformation.associatedProtocolUid else {
            os_log("The protocol instance uid does not correspond to the one associated with the group", log: log, type: .error)
            return GroupManagementProtocol.CancelledState()
        }

        // Get the group structure from database

        let groupStructure: GroupStructure
        do {
            guard let _groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: step.ownedIdentity, groupUid: groupInformation.groupUid, within: obvContext) else {
                throw Self.makeError(message: "Could not get group owned structure")
            }
            groupStructure = _groupStructure
        } catch {
            os_log("Could not access the group in database", log: log, type: .error)
            return GroupManagementProtocol.CancelledState()
        }

        // Create a list of group members with serialized details

        var groupMembersWithCoreDetails: Set<CryptoIdentityWithCoreDetails>
        do {
            groupMembersWithCoreDetails = Set(try groupStructure.groupMembers.map { (contactIdentity) in
                let allDetails = try identityDelegate.getIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: step.ownedIdentity, within: obvContext)
                let details = allDetails.publishedIdentityDetails ?? allDetails.trustedIdentityDetails
                return CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: details.coreDetails)
            })
        } catch {
            os_log("Could not get all the details of the group members", log: log, type: .fault)
            return GroupManagementProtocol.CancelledState()
        }

        // Also add the yourself (group owner) to the group
        do {
            let (ownedDetails, _) = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(step.ownedIdentity, within: obvContext)
            groupMembersWithCoreDetails.insert(CryptoIdentityWithCoreDetails.init(cryptoIdentity: step.ownedIdentity, coreDetails: ownedDetails.coreDetails))
        } catch {
            os_log("Could not get owned published details", log: log, type: .fault)
            return GroupManagementProtocol.CancelledState()
        }

        // If there is a photo to upload, upload it now. In that case, we do not notify the group members yet and wait until this method is called again.
        
        if let photoURL = groupStructure.publishedGroupDetailsWithPhoto.photoURL, groupStructure.publishedGroupDetailsWithPhoto.photoServerKeyAndLabel == nil {
            
            do {

                let photoServerKeyAndLabel = try identityDelegate.setPhotoServerKeyAndLabelForContactGroupOwned(ownedIdentity: step.ownedIdentity, groupUid: groupInformation.groupUid, within: obvContext)
                let updatedGroupInformation = try groupInformation.withPhotoServerKeyAndLabel(photoServerKeyAndLabel)

                let coreMessage = getCoreMessage(for: .serverQuery(ownedIdentity: step.ownedIdentity))
                let concreteMessage = GroupManagementProtocol.UploadGroupPhotoMessage(coreProtocolMessage: coreMessage, groupInformation: updatedGroupInformation)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.putUserData(label: photoServerKeyAndLabel.label, dataURL: photoURL, dataKey: photoServerKeyAndLabel.key)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: step.prng, within: obvContext)

            } catch {
                os_log("Error: %{public}@", log: log, type: .error, error.localizedDescription)
                assertionFailure()
                // An error occured with the photo, this should not prevent group creation, so we do nothing
            }
            
        } else {
            
            // Notify all group members (not the pending group members) with a single message
            
            if groupStructure.groupMembers.count > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: groupStructure.groupMembers, fromOwnedIdentity: step.ownedIdentity))
                    let concreteProtocolMessage = GroupManagementProtocol.NewMembersMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformation, groupMembers: groupMembersWithCoreDetails, pendingMembers: groupStructure.pendingGroupMembers, groupMembersVersion: groupStructure.groupMembersVersion)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: step.prng) else {
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: step.prng, within: obvContext)
                } catch {
                    os_log("Could not post NewMembersMessage", log: log, type: .fault)
                    return GroupManagementProtocol.CancelledState()
                }
            }
            
            // Also notify our other owned devices
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                let concreteProtocolMessage = GroupManagementProtocol.NewMembersMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformation, groupMembers: groupMembersWithCoreDetails, pendingMembers: groupStructure.pendingGroupMembers, groupMembersVersion: groupStructure.groupMembersVersion)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

        }
        
        // Return the new state

        return GroupManagementProtocol.FinalState()
    }

}
