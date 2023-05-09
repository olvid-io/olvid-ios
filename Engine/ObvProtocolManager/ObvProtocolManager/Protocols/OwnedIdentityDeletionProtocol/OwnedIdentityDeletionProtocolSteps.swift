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

extension OwnedIdentityDeletionProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case startDeletion = 0
        case determineNextStepToExecute = 1
        case processOtherProtocolInstances = 2
        case processGroupsV1 = 3
        case processGroupsV2 = 4
        case processContacts = 5
        case processChannels = 6
        case processContactOwnedIdentityWasDeletedMessage = 7

        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            case .startDeletion:
                let step = StartDeletionStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .determineNextStepToExecute:
                let step = DetermineNextStepToExecuteStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .processOtherProtocolInstances:
                let step = ProcessOtherProtocolInstancesStep(from: concreteProtocol, and: receivedMessage)
                return step

            case .processGroupsV1:
                let step = ProcessGroupsV1Step(from: concreteProtocol, and: receivedMessage)
                return step

            case .processGroupsV2:
                let step = ProcessGroupsV2Step(from: concreteProtocol, and: receivedMessage)
                return step
                
            case .processContacts:
                let step = ProcessContactsStep(from: concreteProtocol, and: receivedMessage)
                return step

            case .processChannels:
                let step = ProcessChannelsStep(from: concreteProtocol, and: receivedMessage)
                return step

            case .processContactOwnedIdentityWasDeletedMessage:
                switch receivedMessage.receptionChannelInfo {
                case .AsymmetricChannel:
                    let step = ProcessContactOwnedIdentityWasDeletedMessageReceivedFromContactStep(from: concreteProtocol, and: receivedMessage)
                    return step
                case .AnyObliviousChannelWithOwnedDevice:
                    let step = ProcessProcessContactOwnedIdentityWasDeletedMessagePropagatedStep(from: concreteProtocol, and: receivedMessage)
                    return step
                default:
                    return nil
                }

            }
            
        }
    }
    
        
    // MARK: - StartDeletionStep
    
    final class StartDeletionStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateOwnedIdentityDeletionMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitiateOwnedIdentityDeletionMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
                        
            let ownedCryptoIdentityToDelete = receivedMessage.ownedCryptoIdentityToDelete
            let notifyContacts = receivedMessage.notifyContacts
            
            // Make sure that the current owned identity is the one we are deleting
            
            guard ownedIdentity == ownedCryptoIdentityToDelete else {
                assertionFailure()
                return FinalState()
            }

            // Mark the owned identity for deletion
            
            try identityDelegate.markOwnedIdentityForDeletion(ownedCryptoIdentityToDelete, within: obvContext)
            
            // Post a local message for this protocol so at the launch the `DetermineNextStepToExecuteStep`

            let coreMessage = getCoreMessage(for: .Local(ownedIdentity: ownedIdentity))
            let concreteMessage = ContinueOwnedIdentityDeletionMessage(coreProtocolMessage: coreMessage)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate ContinueOwnedIdentityDeletionMessage") }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // Return the new state

            return DeletionCurrentStatusState(notifyContacts: notifyContacts)

        }
        
    }
    
    
    // MARK: - DetermineNextStepToExecuteStep
    
    final class DetermineNextStepToExecuteStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: DeletionCurrentStatusState
        let receivedMessage: ContinueOwnedIdentityDeletionMessage
        
        init?(startState: DeletionCurrentStatusState, receivedMessage: ContinueOwnedIdentityDeletionMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let coreMessage = getCoreMessage(for: .Local(ownedIdentity: ownedIdentity))
            let concreteMessage: GenericProtocolMessageToSendGenerator

            if !startState.otherProtocolInstancesHaveBeenProcessed {
                concreteMessage = ProcessOtherProtocolInstancesMessage(coreProtocolMessage: coreMessage)
            } else if !startState.groupsV1HaveBeenProcessed {
                concreteMessage = ProcessGroupsV1Message(coreProtocolMessage: coreMessage)
            } else if !startState.groupsV2HaveBeenProcessed {
                concreteMessage = ProcessGroupsV2Message(coreProtocolMessage: coreMessage)
            } else if !startState.contactsHaveBeenProcessed {
                concreteMessage = ProcessContactsMessage(coreProtocolMessage: coreMessage)
            } else if !startState.channelsHaveBeenProcessed {
                concreteMessage = ProcessChannelsMessage(coreProtocolMessage: coreMessage)
            } else {
                
                // When everything has been processed, we request the deletion of the owned identity
                
                do {
                    try identityDelegate.deleteOwnedIdentity(ownedIdentity, within: obvContext)
                } catch {
                    assertionFailure(error.localizedDescription)                    
                }
                
                return FinalState()
            }

            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate ContinueOwnedIdentityDeletionMessage") }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            return startState
            
        }
        
    }
    
    
    // MARK: - ProcessOtherProtocolInstancesStep
    
    /// By the end of this step, all (send and receive) network messages are deleted as well as other protocol instances.
    final class ProcessOtherProtocolInstancesStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: DeletionCurrentStatusState
        let receivedMessage: ProcessOtherProtocolInstancesMessage
        
        init?(startState: DeletionCurrentStatusState, receivedMessage: ProcessOtherProtocolInstancesMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            // Delete all other protocol instances
            
            try ProtocolInstance.deleteAllProtocolInstancesOfOwnedIdentity(ownedIdentity, withProtocolInstanceUidDistinctFrom: self.protocolInstanceUid, within: obvContext)
                     
            // Post a local message for this protocol so at the launch the `DetermineNextStepToExecuteStep`
            
            let coreMessage = getCoreMessage(for: .Local(ownedIdentity: ownedIdentity))
            let concreteMessage = ContinueOwnedIdentityDeletionMessage(coreProtocolMessage: coreMessage)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate ContinueOwnedIdentityDeletionMessage") }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // Return the new state

            let newState = startState.getStateWhenOtherProtocolInstancesHaveBeenProcessed()
            return newState

        }
        
    }
    

    
    // MARK: - ProcessGroupsV1Step
    
    /// By the end of this step, all groups V1 (both owned and joined) are deleted. If the state's `notifyContacts` Boolean is `true`, other group members are kicked or notified.
    final class ProcessGroupsV1Step: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: DeletionCurrentStatusState
        let receivedMessage: ProcessGroupsV1Message
        
        init?(startState: DeletionCurrentStatusState, receivedMessage: ProcessGroupsV1Message, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let allGroupStructures = try identityDelegate.getAllGroupStructures(ownedIdentity: ownedIdentity, within: obvContext)

            if startState.notifyContacts {
                                
                // Leave all joined groups by executing now the LeaveGroupJoinedStep of the GroupManagementProtocol
                
                let joinedGroups = allGroupStructures.filter({ $0.groupType == .joined })
                
                for joinedGroup in joinedGroups {
                
                    let leaveGroupJoinedMessage = try protocolStarterDelegate.getLeaveGroupJoinedMessageForStartingGroupManagementProtocol(
                        ownedIdentity: ownedIdentity,
                        groupUid: joinedGroup.groupUid,
                        groupOwner: joinedGroup.groupOwner,
                        simulateReceivedMessage: true,
                        within: obvContext)
                    let groupManagementProtocol = GroupManagementProtocol(
                        instanceUid: leaveGroupJoinedMessage.coreProtocolMessage.protocolInstanceUid,
                        currentState: ConcreteProtocolInitialState(),
                        ownedCryptoIdentity: ownedIdentity,
                        delegateManager: delegateManager,
                        prng: prng,
                        within: obvContext)
                    guard let leaveGroupJoinedStep = GroupManagementProtocol.LeaveGroupJoinedStep(
                        startState: ConcreteProtocolInitialState(),
                        receivedMessage: leaveGroupJoinedMessage,
                        concreteCryptoProtocol: groupManagementProtocol)
                    else {
                        assertionFailure()
                        continue
                    }
                    let groupManagementProtocolState = try leaveGroupJoinedStep.executeStep(within: obvContext)
                    guard groupManagementProtocolState?.rawId == GroupManagementProtocol.StateId.Final.rawValue else {
                        assertionFailure()
                        continue
                    }
                    
                }
                
                // Kick all the members of all owned groups
                
                let ownedGroups = allGroupStructures.filter({ $0.groupType == .owned })

                for ownedGroup in ownedGroups {
                    
                    let removeGroupMembersMessage = try protocolStarterDelegate.getRemoveGroupMembersMessageForStartingGroupManagementProtocol(
                        groupUid: ownedGroup.groupUid,
                        ownedIdentity: ownedIdentity,
                        removedGroupMembers: ownedGroup.groupMembers,
                        simulateReceivedMessage: true,
                        within: obvContext)
                    let groupManagementProtocol = GroupManagementProtocol(
                        instanceUid: removeGroupMembersMessage.coreProtocolMessage.protocolInstanceUid,
                        currentState: ConcreteProtocolInitialState(),
                        ownedCryptoIdentity: ownedIdentity,
                        delegateManager: delegateManager,
                        prng: prng,
                        within: obvContext)
                    guard let removeGroupMembersStep = GroupManagementProtocol.RemoveGroupMembersStep(
                        startState: ConcreteProtocolInitialState(),
                        receivedMessage: removeGroupMembersMessage,
                        concreteCryptoProtocol: groupManagementProtocol)
                    else {
                        assertionFailure()
                        continue
                    }
                    let groupManagementProtocolState = try removeGroupMembersStep.executeStep(within: obvContext)
                    guard groupManagementProtocolState?.rawId == GroupManagementProtocol.StateId.Final.rawValue else {
                        assertionFailure()
                        continue
                    }
                                        
                }
                                
            }
            
            // Locally delete all groups
            
            for groupStructure in allGroupStructures {
                switch groupStructure.groupType {
                case .joined:
                    do {
                        try identityDelegate.deleteContactGroupJoined(ownedIdentity: ownedIdentity, groupUid: groupStructure.groupUid, groupOwner: groupStructure.groupOwner, within: obvContext)
                    } catch {
                        assertionFailure(error.localizedDescription)
                        // In production, continue anyway
                    }
                case .owned:
                    do {
                        try identityDelegate.deleteContactGroupOwned(ownedIdentity: ownedIdentity, groupUid: groupStructure.groupUid, deleteEvenIfGroupMembersStillExist: true, within: obvContext)
                    } catch {
                        assertionFailure(error.localizedDescription)
                        // In production, continue anyway
                    }
                }
            }
            
            // Post a local message for this protocol so at the launch the `DetermineNextStepToExecuteStep`
            
            let coreMessage = getCoreMessage(for: .Local(ownedIdentity: ownedIdentity))
            let concreteMessage = ContinueOwnedIdentityDeletionMessage(coreProtocolMessage: coreMessage)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate ContinueOwnedIdentityDeletionMessage") }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // Return the new state

            let newState = startState.getStateWhenGroupsV1HaveBeenProcessed()
            return newState
            
        }
        
    }

    
    // MARK: - ProcessGroupsV2Step
    
    final class ProcessGroupsV2Step: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: DeletionCurrentStatusState
        let receivedMessage: ProcessGroupsV2Message
        
        init?(startState: DeletionCurrentStatusState, receivedMessage: ProcessGroupsV2Message, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let allGroups = try identityDelegate.getAllObvGroupV2(of: ownedIdentity, within: obvContext)
            
            if startState.notifyContacts {
                
                // Leave all groups that we joined or where we are *not* the only administrator.
                // Groups for which we are the sole administrator are disbanded.
                
                var groupsToDisband = [GroupV2.Identifier]()
                
                for group in allGroups {
                    
                    guard let encodedGroupIdentifier = ObvEncoded(withRawData: group.appGroupIdentifier),
                          let obvGroupV2Identifier = ObvGroupV2.Identifier(encodedGroupIdentifier)
                    else {
                        assertionFailure()
                        // In production, continue anyway
                        continue
                    }
                    let groupIdentifier = GroupV2.Identifier(obvGroupV2Identifier: obvGroupV2Identifier)
                    
                    // If we are the sole administrator of the group, we add it to the set of groups to disband
                    
                    let allNonPendingAdministratorsIdentities = try identityDelegate.getAllNonPendingAdministratorsIdentitiesOfGroupV2(withGroupWithIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                    let weAreTheSoleAdministratorOfTheGroup = allNonPendingAdministratorsIdentities.contains(ownedIdentity) && allNonPendingAdministratorsIdentities.count == 1
                    
                    if weAreTheSoleAdministratorOfTheGroup {

                        groupsToDisband += [groupIdentifier]

                    } else {
                        
                        let initiateGroupLeaveMessage = try protocolStarterDelegate.getInitiateGroupLeaveMessageForStartingGroupV2Protocol(
                            ownedIdentity: ownedIdentity,
                            groupIdentifier: groupIdentifier,
                            simulateReceivedMessage: true,
                            flowId: obvContext.flowId)
                        let groupV2Protocol = GroupV2Protocol(
                            instanceUid: initiateGroupLeaveMessage.coreProtocolMessage.protocolInstanceUid,
                            currentState: ConcreteProtocolInitialState(),
                            ownedCryptoIdentity: ownedIdentity,
                            delegateManager: delegateManager,
                            prng: prng,
                            within: obvContext)
                        guard let processInitiateGroupLeaveMessage = GroupV2Protocol.ProcessInitiateGroupLeaveMessageFromConcreteProtocolInitialStateStep(
                            startState: ConcreteProtocolInitialState(),
                            receivedMessage: initiateGroupLeaveMessage,
                            concreteCryptoProtocol: groupV2Protocol)
                        else {
                            assertionFailure()
                            continue
                        }
                        let groupV2ProtocolState = try processInitiateGroupLeaveMessage.executeStep(within: obvContext)
                        
                        // At this point, the blob is updated on the server, but the group members were not notified (i.e., they need to manually refresh the group).
                        // This issue is fixed later, when sending the `ContactOwnedIdentityWasDeletedMessage` message.
                        
                        // Make sure we are in one of the possible retured states of the ProcessInitiateGroupLeaveMessageFromConcreteProtocolInitialStateStep
                        
                        guard groupV2ProtocolState?.rawId == GroupV2Protocol.StateId.final.rawValue || groupV2ProtocolState?.rawId == GroupV2Protocol.StateId.rejectingInvitationOrLeavingGroup.rawValue  else {
                            assertionFailure()
                            continue
                        }
                        
                    } // End of else for 'if weAreTheSoleAdministratorOfTheGroup'
                        
                } // End of 'for group in allGroups'
                
                for groupIdentifier in groupsToDisband {
                    
                    // Execute the DisbandGroupStep of the group v2 protocol
                    
                    let initiateGroupDisbandMessage = try protocolStarterDelegate.getInitiateInitiateGroupDisbandMessageForStartingGroupV2Protocol(
                        ownedIdentity: ownedIdentity,
                        groupIdentifier: groupIdentifier,
                        simulateReceivedMessage: true,
                        flowId: obvContext.flowId)
                    let instanceUid = initiateGroupDisbandMessage.coreProtocolMessage.protocolInstanceUid
                    let groupV2Protocol = GroupV2Protocol(
                        instanceUid: instanceUid,
                        currentState: ConcreteProtocolInitialState(),
                        ownedCryptoIdentity: ownedIdentity,
                        delegateManager: delegateManager,
                        prng: prng,
                        within: obvContext)
                    guard let disbandGroupStep = GroupV2Protocol.ProcessInitiateGroupDisbandMessageFromConcreteProtocolInitialStateStep(
                        startState: ConcreteProtocolInitialState(),
                        receivedMessage: initiateGroupDisbandMessage,
                        concreteCryptoProtocol: groupV2Protocol)
                    else {
                        assertionFailure()
                        continue
                    }
                    let groupV2ProtocolState = try disbandGroupStep.executeStep(within: obvContext)

                    guard groupV2ProtocolState?.rawId == GroupV2Protocol.StateId.final.rawValue || groupV2ProtocolState?.rawId == GroupV2Protocol.StateId.disbandingGroup.rawValue  else {
                        assertionFailure()
                        continue
                    }

                    // Execute the FinalizeGroupDisbandStep of the group v2 protocol (immediately, simulating the success of the server query sent in the previous executed step).
                    // This allows to send kick messages to all participants.
                    
                    if let disbandingGroupState = groupV2ProtocolState as? GroupV2Protocol.DisbandingGroupState {
                        
                        let deleteGroupBlobFromServerMessage = GroupV2Protocol.DeleteGroupBlobFromServerMessage(
                            forSimulatingReceivedMessageForOwnedIdentity: ownedIdentity,
                            protocolInstanceUid: instanceUid)
                        let groupV2Protocol = GroupV2Protocol(
                            instanceUid: deleteGroupBlobFromServerMessage.coreProtocolMessage.protocolInstanceUid,
                            currentState: disbandingGroupState,
                            ownedCryptoIdentity: ownedIdentity,
                            delegateManager: delegateManager,
                            prng: prng,
                            within: obvContext)
                        guard let finalizeGroupDisbandStep = GroupV2Protocol.FinalizeGroupDisbandStep(
                            startState: disbandingGroupState,
                            receivedMessage: deleteGroupBlobFromServerMessage,
                            concreteCryptoProtocol: groupV2Protocol)
                        else {
                            assertionFailure()
                            continue
                        }
                        _ = try finalizeGroupDisbandStep.executeStep(within: obvContext)
                                                
                    }

                }
                
            } // End of if startState.notifyContacts
            
            // Locally delete all groups

            for group in allGroups {
                
                guard let encodedGroupIdentifier = ObvEncoded(withRawData: group.appGroupIdentifier),
                      let obvGroupV2Identifier = ObvGroupV2.Identifier(encodedGroupIdentifier)
                else {
                    assertionFailure()
                    // In production, continue anyway
                    continue
                }
                let groupIdentifier = GroupV2.Identifier(obvGroupV2Identifier: obvGroupV2Identifier)

                do {
                    try identityDelegate.deleteGroupV2(withGroupIdentifier: groupIdentifier, of: ownedIdentity, within: obvContext)
                } catch {
                    assertionFailure(error.localizedDescription)
                    continue
                }
                
            }
            
            // Post a local message for this protocol so at the launch the `DetermineNextStepToExecuteStep`
            
            let coreMessage = getCoreMessage(for: .Local(ownedIdentity: ownedIdentity))
            let concreteMessage = ContinueOwnedIdentityDeletionMessage(coreProtocolMessage: coreMessage)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate ContinueOwnedIdentityDeletionMessage") }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // Return the new state

            let newState = startState.getStateWhenGroupsV2HaveBeenProcessed()
            return newState
            
        }
        
    }

    
    // MARK: - ProcessContactsStep
    
    final class ProcessContactsStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: DeletionCurrentStatusState
        let receivedMessage: ProcessContactsMessage
        
        init?(startState: DeletionCurrentStatusState, receivedMessage: ProcessContactsMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OwnedIdentityDeletionProtocol.logCategory)

            let allContacts = try identityDelegate.getContactsOfOwnedIdentity(ownedIdentity, within: obvContext)
            
            if startState.notifyContacts {
            
                // Notify all contacts that our own identity is about to be deleted.
                
                for contact in allContacts {
                
                    // We first send a broadcast message allowing to be radical in the way our contacts will delete our own identity (and to delete it also with contacts without channels).
                    // This only works with contacts who understand this protocol.

                    do {
                        
                        let signature: Data
                        do {
                            let challengeType = ChallengeType.ownedIdentityDeletion(notifiedContactIdentity: contact)
                            guard let sig = try? solveChallengeDelegate.solveChallenge(challengeType, for: ownedIdentity, using: prng, within: obvContext) else {
                                os_log("Could not compute signature", log: log, type: .fault)
                                assertionFailure()
                                // Continue with the next contact
                                continue
                            }
                            signature = sig
                        }

                        let coreMessage = getCoreMessage(for: .AsymmetricChannelBroadcast(to: contact, fromOwnedIdentity: ownedIdentity))
                        let concreteMessage = ContactOwnedIdentityWasDeletedMessage(coreProtocolMessage: coreMessage, deletedContactOwnedIdentity: ownedIdentity, signature: signature)
                        guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    }
                                        
                }
                
            }
            
            // Locally delete all contacts and their associated channels
            
            for contact in allContacts {
                do {
                    try channelDelegate.deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andTheDevicesOfContactIdentity: contact, within: obvContext)
                } catch {
                    assertionFailure(error.localizedDescription)
                    // In production, continue anyway
                }
                do {
                    try identityDelegate.deleteContactIdentity(contact, forOwnedIdentity: ownedIdentity, failIfContactIsPartOfACommonGroup: false, within: obvContext)
                } catch {
                    assertionFailure(error.localizedDescription)
                    // In production, continue anyway
                }
            }
            
            // Post a local message for this protocol so at the launch the `DetermineNextStepToExecuteStep`
            
            let coreMessage = getCoreMessage(for: .Local(ownedIdentity: ownedIdentity))
            let concreteMessage = ContinueOwnedIdentityDeletionMessage(coreProtocolMessage: coreMessage)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate ContinueOwnedIdentityDeletionMessage") }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // Return the new state

            let newState = startState.getStateWhenContactsHaveBeenProcessed()
            return newState

        }
        
    }

    
    // MARK: - ProcessChannelsStep
    
    final class ProcessChannelsStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: DeletionCurrentStatusState
        let receivedMessage: ProcessChannelsMessage
        
        init?(startState: DeletionCurrentStatusState, receivedMessage: ProcessChannelsMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
            
            try channelDelegate.deleteAllObliviousChannelsWithTheCurrentDeviceUid(currentDeviceUid, within: obvContext)
            
            // Post a local message for this protocol so at the launch the `DetermineNextStepToExecuteStep`
            
            let coreMessage = getCoreMessage(for: .Local(ownedIdentity: ownedIdentity))
            let concreteMessage = ContinueOwnedIdentityDeletionMessage(coreProtocolMessage: coreMessage)
            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate ContinueOwnedIdentityDeletionMessage") }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // Return the new state

            let newState = startState.getStateWhenChannelsHaveBeenProcessed()
            return newState

        }
        
    }

    
    // MARK: - ProcessContactOwnedIdentityWasDeletedMessageStep
    
    class ProcessContactOwnedIdentityWasDeletedMessageStep: ProtocolStep {
        
        private let startState: ConcreteProtocolInitialState
        private let receivedMessage: ReceivedMessageType
        
        enum ReceivedMessageType {
            case fromContactMessage(receivedMessage: ContactOwnedIdentityWasDeletedMessage)
            case propagatedMessage(receivedMessage: ContactOwnedIdentityWasDeletedMessage)
        }
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            switch receivedMessage {
            case .fromContactMessage(receivedMessage: let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AsymmetricChannel,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .propagatedMessage(receivedMessage: let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }
            
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let deletedContactOwnedIdentity: ObvCryptoIdentity
            let signature: Data
            let propagated: Bool
            switch receivedMessage {
            case .fromContactMessage(receivedMessage: let receivedMessage):
                deletedContactOwnedIdentity = receivedMessage.deletedContactOwnedIdentity
                signature = receivedMessage.signature
                propagated = false
            case .propagatedMessage(receivedMessage: let receivedMessage):
                deletedContactOwnedIdentity = receivedMessage.deletedContactOwnedIdentity
                signature = receivedMessage.signature
                propagated = true
            }
                        
            // Check that the signature was not replayed by searching the DB
            
            guard try !ContactOwnedIdentityDeletionSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity, signature: signature, within: obvContext) else {
                return FinalState()
            }

            // We check the signature

            do {
                let challengeType = ChallengeType.ownedIdentityDeletion(notifiedContactIdentity: ownedIdentity)
                guard ObvSolveChallengeStruct.checkResponse(signature, to: challengeType, from: deletedContactOwnedIdentity) else {
                    assertionFailure()
                    return FinalState()
                }
            }

            // Store the signature to prevent replay attacks
            
            _ = ContactOwnedIdentityDeletionSignatureReceived(ownedCryptoIdentity: ownedIdentity, signature: signature, within: obvContext)

            // Propagate the signature to our other owned devices (we use the same concrete message type than the one sent by our contact)
            
            if !propagated {
                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !otherDeviceUIDs.isEmpty {
                    let coreMessage = getCoreMessage(for: ObvChannelSendChannelType.ObliviousChannel(to: ownedIdentity, remoteDeviceUids: Array(otherDeviceUIDs), fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: true))
                    let concreteMessage = ContactOwnedIdentityWasDeletedMessage(coreProtocolMessage: coreMessage, deletedContactOwnedIdentity: deletedContactOwnedIdentity, signature: signature)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }
            
            // Deal with groups v1
            
            do {
                
                let allGroupStructures = try identityDelegate.getAllGroupStructures(ownedIdentity: ownedIdentity, within: obvContext)
                
                // For all joined groups:
                //  - If the contact who deleted her owned identity is the group v1 admin, we "locally" leave the group (we do not execute any protocol step, we simply delete the group from the identity manager).
                //  - Otherwise, we remove the contact from the joined group without waiting for the administrator to confirm that this contact has been removed from the group.

                let joinedGroups = allGroupStructures.filter({ $0.groupType == .joined })
                
                for joinedGroup in joinedGroups {
                                        
                    do {
                        if joinedGroup.groupOwner == deletedContactOwnedIdentity {
                            try identityDelegate.deleteContactGroupJoined(ownedIdentity: ownedIdentity,
                                                                          groupUid: joinedGroup.groupUid,
                                                                          groupOwner: deletedContactOwnedIdentity,
                                                                          within: obvContext)
                        } else {
                            try identityDelegate.removeContactFromPendingAndGroupMembersOfContactGroupJoined(
                                ownedIdentity: ownedIdentity,
                                groupOwner: joinedGroup.groupOwner,
                                groupUid: joinedGroup.groupUid,
                                contactIdentity: deletedContactOwnedIdentity,
                                within: obvContext)
                        }
                    } catch {
                        assertionFailure(error.localizedDescription)
                        // In production, continue anyway
                    }
                    
                }
                
                // Kick the contact that deleted her owned identity from all owned groups
                // Only do so in the case we are not dealing with a propagated message (no need to perform the same work twice), in which case we only remove the contact "locally" (since we will be deleting her identity in this step)

                let ownedGroups = allGroupStructures.filter({ $0.groupType == .owned })

                for ownedGroup in ownedGroups {
                    
                    if propagated {
                        
                        try identityDelegate.removePendingAndMembersToContactGroupOwned(
                            ownedIdentity: ownedIdentity,
                            groupUid: ownedGroup.groupUid,
                            pendingOrMembersToRemove: Set([deletedContactOwnedIdentity]),
                            within: obvContext,
                            groupMembersChangedCallback: {})
                        
                    } else {
                        
                        let removeGroupMembersMessage = try protocolStarterDelegate.getRemoveGroupMembersMessageForStartingGroupManagementProtocol(
                            groupUid: ownedGroup.groupUid,
                            ownedIdentity: ownedIdentity,
                            removedGroupMembers: [deletedContactOwnedIdentity],
                            simulateReceivedMessage: true,
                            within: obvContext)
                        let groupManagementProtocol = GroupManagementProtocol(
                            instanceUid: removeGroupMembersMessage.coreProtocolMessage.protocolInstanceUid,
                            currentState: ConcreteProtocolInitialState(),
                            ownedCryptoIdentity: ownedIdentity,
                            delegateManager: delegateManager,
                            prng: prng,
                            within: obvContext)
                        guard let removeGroupMembersStep = GroupManagementProtocol.RemoveGroupMembersStep(
                            startState: ConcreteProtocolInitialState(),
                            receivedMessage: removeGroupMembersMessage,
                            concreteCryptoProtocol: groupManagementProtocol)
                        else {
                            assertionFailure()
                            continue
                        }
                        let groupManagementProtocolState = try removeGroupMembersStep.executeStep(within: obvContext)
                        guard groupManagementProtocolState?.rawId == GroupManagementProtocol.StateId.Final.rawValue else {
                            assertionFailure()
                            continue
                        }
                        
                    }
                    
                }
                
            } // End of part dealing with groups v1
            
            // Deal with groups v2

            do {
                
                let allGroups = try identityDelegate.getAllObvGroupV2(of: ownedIdentity, within: obvContext)
                                
                for group in allGroups {

                    guard let encodedGroupIdentifier = ObvEncoded(withRawData: group.appGroupIdentifier),
                          let obvGroupV2Identifier = ObvGroupV2.Identifier(encodedGroupIdentifier)
                    else {
                        assertionFailure()
                        // In production, continue anyway
                        continue
                    }
                    let groupIdentifier = GroupV2.Identifier(obvGroupV2Identifier: obvGroupV2Identifier)

                    // If we are an administrator, kick the contact who deleted her owned identity.
                    // We start a protocol for that.
                    // We do so only if we are not dealing with a propagated message (no need to publish a new group blob several times).

                    if group.ownPermissions.contains(.groupAdmin) && !propagated {
                                            
                        let changeset = try ObvGroupV2.Changeset(changes: Set([.memberRemoved(contactCryptoId: ObvCryptoId(cryptoIdentity: deletedContactOwnedIdentity))]))

                        // Note that this protocol will work even if the contact does not exist anymore, which will be the case as we will delete it before this protocol is executed.
                        let initiateGroupUpdateMessage = try protocolStarterDelegate.getInitiateGroupUpdateMessageForGroupV2Protocol(
                            ownedIdentity: ownedIdentity,
                            groupIdentifier: groupIdentifier,
                            changeset: changeset,
                            flowId: obvContext.flowId)
                        
                        _ = try channelDelegate.post(initiateGroupUpdateMessage, randomizedWith: prng, within: obvContext)
                        
                    }
                        
                    // We do not check whether the contact (who deleted her owned identity) is the sole admin or not.
                    // In both case, we simply remove her from the group. If she was the sole admin, she disbanded the group and kicked us from it. We shall soon receive that message.
                    // If she is not the sole admin, we should not delete the group, only remove her from the members and pending members.
                    
                    try identityDelegate.removeOtherMembersOrPendingMembersFromGroupV2(
                        withGroupIdentifier: groupIdentifier,
                        of: ownedIdentity,
                        identitiesToRemove: Set([deletedContactOwnedIdentity]),
                        within: obvContext)
                    
                }
                
            } // End of part dealing with groups v2
            
            // Delete the contact who deleted her owned identity
            
            do {
                try channelDelegate.deleteAllObliviousChannelsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andTheDevicesOfContactIdentity: deletedContactOwnedIdentity, within: obvContext)
            } catch {
                assertionFailure(error.localizedDescription)
                // In production, continue anyway
            }
            do {
                try identityDelegate.deleteContactIdentity(deletedContactOwnedIdentity, forOwnedIdentity: ownedIdentity, failIfContactIsPartOfACommonGroup: false, within: obvContext)
            } catch {
                assertionFailure(error.localizedDescription)
                // In production, continue anyway
            }
            
            // We are done, return the final state
            
            return FinalState()
            
        }
        
    }
    
    
    // MARK: ProcessProcessContactOwnedIdentityWasDeletedMessageReceivedFromContactStep
    
    final class ProcessContactOwnedIdentityWasDeletedMessageReceivedFromContactStep: ProcessContactOwnedIdentityWasDeletedMessageStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: ContactOwnedIdentityWasDeletedMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: ContactOwnedIdentityWasDeletedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState, receivedMessage: .fromContactMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
    }

    
    // MARK: ProcessProcessContactOwnedIdentityWasDeletedMessagePropagatedStep
    
    final class ProcessProcessContactOwnedIdentityWasDeletedMessagePropagatedStep: ProcessContactOwnedIdentityWasDeletedMessageStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: ContactOwnedIdentityWasDeletedMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: ContactOwnedIdentityWasDeletedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState, receivedMessage: .propagatedMessage(receivedMessage: receivedMessage), concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
    }
    
}
