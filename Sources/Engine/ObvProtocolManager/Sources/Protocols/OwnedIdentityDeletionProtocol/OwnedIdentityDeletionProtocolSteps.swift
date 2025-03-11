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
        case finalizeDeletion = 1
        case processContactOwnedIdentityWasDeletedMessage = 2

        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            case .startDeletion:
                if let step = StartDeletionFromInitiateOwnedIdentityDeletionMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = StartDeletionFromPropagateOwnedIdentityDeletionMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = StartDeletionFromReplayStartDeletionStepMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }
                
            case .finalizeDeletion:
                if let step = FinalizeDeletionStepFromDeactivateOwnedDeviceServerQueryMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = FinalizeDeletionStepFromFinalizeOwnedIdentityDeletionMessageStep(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }
                
            case .processContactOwnedIdentityWasDeletedMessage:
                switch receivedMessage.receptionChannelInfo {
                case .asymmetricChannel:
                    let step = ProcessContactOwnedIdentityWasDeletedMessageReceivedFromContactStep(from: concreteProtocol, and: receivedMessage)
                    return step
                case .anyObliviousChannelOrPreKeyWithOwnedDevice:
                    let step = ProcessProcessContactOwnedIdentityWasDeletedMessagePropagatedStep(from: concreteProtocol, and: receivedMessage)
                    return step
                default:
                    return nil
                }

            }
            
        }
    }
    

    // MARK: - StartDeletionStep
    
    class StartDeletionStep: ProtocolStep {
        
        private let startState: StartStateType
        private let receivedMessage: ReceivedMessageType

        enum StartStateType {
            case initial(startState: ConcreteProtocolInitialState)
            case firstDeletionStepPerformedState(startState: FirstDeletionStepPerformedState)
        }
        
        enum ReceivedMessageType {
            case initiateOwnedIdentityDeletionMessage(receivedMessage: InitiateOwnedIdentityDeletionMessage)
            case propagateGlobalOwnedIdentityDeletionMessage(receivedMessage: PropagateGlobalOwnedIdentityDeletionMessage)
            case replayStartDeletionStepMessage(receivedMessage: ReplayStartDeletionStepMessage)
        }

        init?(startState: StartStateType, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            switch (startState, receivedMessage) {
            case (.initial, .initiateOwnedIdentityDeletionMessage(receivedMessage: let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.initial, .propagateGlobalOwnedIdentityDeletionMessage(receivedMessage: let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case (.firstDeletionStepPerformedState, .replayStartDeletionStepMessage(receivedMessage: let receivedMessage)):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            default:
                // Any other state/message combination is unexpected
                assertionFailure()
                return nil
            }
            
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
                        
            let globalOwnedIdentityDeletion: Bool
            let propagationNeeded: Bool
            switch receivedMessage {
            case .initiateOwnedIdentityDeletionMessage(receivedMessage: let receivedMessage):
                globalOwnedIdentityDeletion = receivedMessage.globalOwnedIdentityDeletion
                propagationNeeded = true
            case .propagateGlobalOwnedIdentityDeletionMessage:
                globalOwnedIdentityDeletion = true
                propagationNeeded = false
            case .replayStartDeletionStepMessage:
                switch startState {
                case .initial:
                    assertionFailure()
                    throw Self.makeError(message: "Unexpected state")
                case .firstDeletionStepPerformedState(let startState):
                    globalOwnedIdentityDeletion = startState.globalOwnedIdentityDeletion
                    propagationNeeded = startState.propagationNeeded
                }
            }
            
            // If the user request a global deletion, we make sure the identity is active
            
            let ownedIdentityIsActive = try identityDelegate.isOwnedIdentityActive(ownedIdentity: ownedIdentity, flowId: obvContext.flowId)
            if globalOwnedIdentityDeletion {
                guard ownedIdentityIsActive || !propagationNeeded else {
                    assertionFailure()
                    throw Self.makeError(message: "Owned identity must be active when requeting a global deletion")
                }
            }
            
            // Perform pre-deletion tasks (note that ObvDialogs are deleted asynchronously by the engine coordinator, when receiving the notification from the identity manager that the owned identity has been deleted).
            
            try prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ownedIdentity, within: obvContext)
            try networkPostDelegate.prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ownedIdentity, within: obvContext)
            Task { try await networkFetchDelegate.prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ownedIdentity, flowId: obvContext.flowId) }
            
            // In case we are performing a *global* deletion, we want our other devices to execute this protocol too
            // Note that in the case we perform a *local* deletion, we want our other owned devices to perform a simple owned device discovery.
            // We wait until the end of the server query (that deactivates this device) before sending them a InitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage.

            if propagationNeeded && ownedIdentityIsActive && globalOwnedIdentityDeletion {
                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !otherDeviceUIDs.isEmpty {
                    let channelType = ObvChannelSendChannelType.obliviousChannel(to: ownedIdentity, 
                                                                                 remoteDeviceUids: Array(otherDeviceUIDs),
                                                                                 fromOwnedIdentity: ownedIdentity,
                                                                                 necessarilyConfirmed: true,
                                                                                 usePreKeyIfRequired: true)
                    let coreMessage = getCoreMessage(for: channelType)
                    let concreteMessage = PropagateGlobalOwnedIdentityDeletionMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }
            
            // Mark the owned identity for deletion
            
            try identityDelegate.markOwnedIdentityForDeletion(ownedIdentity, within: obvContext)

            // If our owned identity is active on the current device, we want to deactivate it on the server.
            // Otherwise, we simply want to immediately continue this deletion protocol.
            
            if ownedIdentityIsActive {
                                
                let currentDeviceUID = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
                let coreMessage = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                let concreteMessage = DeactivateOwnedDeviceServerQueryMessage(coreProtocolMessage: coreMessage)
                let serverQueryType = ObvChannelServerQueryMessageToSend.QueryType.deactivateOwnedDevice(
                    ownedDeviceUID: currentDeviceUID,
                    isCurrentDevice: true)
                guard let messageToSend = concreteMessage.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)
                
            } else {
                
                let coreMessage = getCoreMessage(for: .local(ownedIdentity: ownedIdentity))
                let concreteMessage = FinalizeOwnedIdentityDeletionMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Could not generate ContinueOwnedIdentityDeletionMessage") }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: concreteCryptoProtocol.prng, within: obvContext)

            }
            
            return FirstDeletionStepPerformedState(globalOwnedIdentityDeletion: globalOwnedIdentityDeletion, propagationNeeded: propagationNeeded)
                        
        }
        
        
        private func prepareForOwnedIdentityDeletion(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
            
            // Delete all received messages
            
            try ReceivedMessage.batchDeleteAllReceivedMessagesForOwnedCryptoIdentity(ownedCryptoIdentity, within: obvContext)
            
            // Delete signatures, commitments,... received relating to this owned identity
            
            try ChannelCreationPingSignatureReceived.batchDeleteAllChannelCreationPingSignatureReceivedForOwnedCryptoIdentity(ownedCryptoIdentity, within: obvContext)
            try TrustEstablishmentCommitmentReceived.batchDeleteAllTrustEstablishmentCommitmentReceivedForOwnedCryptoIdentity(ownedCryptoIdentity, within: obvContext)
            try MutualScanSignatureReceived.batchDeleteAllMutualScanSignatureReceivedForOwnedCryptoIdentity(ownedCryptoIdentity, within: obvContext)
            try GroupV2SignatureReceived.deleteAllAssociatedWithOwnedIdentity(ownedCryptoIdentity, within: obvContext)
            try ContactOwnedIdentityDeletionSignatureReceived.deleteAllAssociatedWithOwnedIdentity(ownedCryptoIdentity, within: obvContext)
            try ProtocolInstance.deleteAllProtocolInstancesOfOwnedIdentity(ownedIdentity, withProtocolInstanceUidDistinctFrom: self.protocolInstanceUid, within: obvContext)
            try ReceivedMessage.deleteAllAssociatedWithOwnedIdentity(ownedCryptoIdentity, within: obvContext)
            
        }

    }
    
    
    // MARK: StartDeletionFromInitiateOwnedIdentityDeletionMessageStep
    
    final class StartDeletionFromInitiateOwnedIdentityDeletionMessageStep: StartDeletionStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateOwnedIdentityDeletionMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitiateOwnedIdentityDeletionMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState),
                       receivedMessage: .initiateOwnedIdentityDeletionMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass
        
    }

    
    // MARK: StartDeletionFromPropagateOwnedIdentityDeletionMessageStep
    
    final class StartDeletionFromPropagateOwnedIdentityDeletionMessageStep: StartDeletionStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateGlobalOwnedIdentityDeletionMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: PropagateGlobalOwnedIdentityDeletionMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .initial(startState: startState),
                       receivedMessage: .propagateGlobalOwnedIdentityDeletionMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass
        
    }
    
    
    // MARK: StartDeletionFromReplayStartDeletionStepMessageStep
    
    final class StartDeletionFromReplayStartDeletionStepMessageStep: StartDeletionStep, TypedConcreteProtocolStep {
        
        let startState: FirstDeletionStepPerformedState
        let receivedMessage: ReplayStartDeletionStepMessage

        init?(startState: FirstDeletionStepPerformedState, receivedMessage: ReplayStartDeletionStepMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .firstDeletionStepPerformedState(startState: startState),
                       receivedMessage: .replayStartDeletionStepMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass
        
    }

    
    // MARK: FinalizeDeletionStep
    
    class FinalizeDeletionStep: ProtocolStep {
        
        private let startState: FirstDeletionStepPerformedState
        private let receivedMessage: ReceivedMessageType

        enum ReceivedMessageType {
            case deactivateOwnedDeviceServerQueryMessage(receivedMessage: DeactivateOwnedDeviceServerQueryMessage)
            case finalizeOwnedIdentityDeletionMessage(receivedMessage: FinalizeOwnedIdentityDeletionMessage)
        }

        init?(startState: FirstDeletionStepPerformedState, receivedMessage: ReceivedMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            switch receivedMessage {
            case .deactivateOwnedDeviceServerQueryMessage(receivedMessage: let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .finalizeOwnedIdentityDeletionMessage(receivedMessage: let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .local,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            }

        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let globalOwnedIdentityDeletion = startState.globalOwnedIdentityDeletion
            let propagationNeeded = startState.propagationNeeded
            
            let ownedIdentityIsActive = try identityDelegate.isOwnedIdentityActive(ownedIdentity: ownedIdentity, flowId: obvContext.flowId)
            
            // In case we are performing a *local* deletion, we want our other owned devices to perform a simple owned device discovery

            if propagationNeeded && ownedIdentityIsActive && !globalOwnedIdentityDeletion {
                let otherDeviceUIDs = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                if !otherDeviceUIDs.isEmpty {
                    let channelType = ObvChannelSendChannelType.obliviousChannel(to: ownedIdentity, 
                                                                                 remoteDeviceUids: Array(otherDeviceUIDs),
                                                                                 fromOwnedIdentity: ownedIdentity,
                                                                                 necessarilyConfirmed: true, 
                                                                                 usePreKeyIfRequired: true)
                    let coreMessage = getCoreMessageForOtherProtocol(for: channelType, otherCryptoProtocolId: .ownedDeviceDiscovery, otherProtocolInstanceUid: UID.gen(with: prng))
                    let concreteMessage = OwnedDeviceDiscoveryProtocol.InitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }
            
            // Process groups v1 and v2

            try processGroupsV1(globalOwnedIdentityDeletion: globalOwnedIdentityDeletion, propagationNeeded: propagationNeeded, ownedIdentityIsActive: ownedIdentityIsActive)
            try processGroupsV2(globalOwnedIdentityDeletion: globalOwnedIdentityDeletion, propagationNeeded: propagationNeeded, ownedIdentityIsActive: ownedIdentityIsActive)
            
            // Process contacts
            
            try processContacts(globalOwnedIdentityDeletion: globalOwnedIdentityDeletion, propagationNeeded: propagationNeeded, ownedIdentityIsActive: ownedIdentityIsActive)
            
            // Process channels
            
            try processChannels(globalOwnedIdentityDeletion: globalOwnedIdentityDeletion, propagationNeeded: propagationNeeded, ownedIdentityIsActive: ownedIdentityIsActive)
            
            // When everything has been processed, we request the deletion of the owned identity
            
            do {
                try identityDelegate.deleteOwnedIdentity(ownedIdentity, within: obvContext)
            } catch {
                assertionFailure(error.localizedDescription)
            }

            // Delete all server session (note that the InitiateOwnedDeviceDiscoveryRequestedByAnotherOwnedDeviceMessage posted above does not need one)

            let flowId = obvContext.flowId
            let networkFetchDelegate = self.networkFetchDelegate
            let ownedIdentity = self.ownedIdentity
            try obvContext.addContextDidSaveCompletionHandler { error in
                guard error == nil else { assertionFailure(); return }
                Task {
                    do {
                        try await networkFetchDelegate.finalizeOwnedIdentityDeletion(ownedCryptoIdentity: ownedIdentity, flowId: flowId)
                    } catch {
                        assertionFailure("Could not delete server session of the deleted owned identity: \(error.localizedDescription)")
                    }
                }

            }

            // We are done
            
            return FinalState()

        }
        
        
        /// Helper method for this step.
        /// By the end of this method, all groups V1 (both owned and joined) are deleted. If `globalOwnedIdentityDeletion`, `propagationNeeded`, and `ownedIdentityIsActive` are `true`, other group members are kicked or notified.
        private func processGroupsV1(globalOwnedIdentityDeletion: Bool, propagationNeeded: Bool, ownedIdentityIsActive: Bool) throws {
            
            let allGroupStructures = try identityDelegate.getAllGroupStructures(ownedIdentity: ownedIdentity, within: obvContext)

            if globalOwnedIdentityDeletion && propagationNeeded && ownedIdentityIsActive {
                                
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
                    guard groupManagementProtocolState?.rawId == GroupManagementProtocol.StateId.final.rawValue else {
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
                    guard groupManagementProtocolState?.rawId == GroupManagementProtocol.StateId.final.rawValue else {
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
            
        }

        
        /// Helper method for this step
        private func processGroupsV2(globalOwnedIdentityDeletion: Bool, propagationNeeded: Bool, ownedIdentityIsActive: Bool) throws {
            
            let allGroups = try identityDelegate.getAllObvGroupV2(of: ownedIdentity, within: obvContext)
            
            if globalOwnedIdentityDeletion && propagationNeeded && ownedIdentityIsActive {
                
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
                            simulateReceivedMessage: true)
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
                        simulateReceivedMessage: true)
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
            
        }

        
        /// Helper method for this step
        private func processContacts(globalOwnedIdentityDeletion: Bool, propagationNeeded: Bool, ownedIdentityIsActive: Bool) throws {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OwnedIdentityDeletionProtocol.logCategory)

            let allContacts = try identityDelegate.getContactsOfOwnedIdentity(ownedIdentity, within: obvContext)
            
            if propagationNeeded && ownedIdentityIsActive {
                if globalOwnedIdentityDeletion {
                    
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
                            
                            let coreMessage = getCoreMessage(for: .asymmetricChannelBroadcast(to: contact, fromOwnedIdentity: ownedIdentity))
                            let concreteMessage = ContactOwnedIdentityWasDeletedMessage(coreProtocolMessage: coreMessage, deletedContactOwnedIdentity: ownedIdentity, signature: signature)
                            guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                        }
                        
                    }
                    
                } else {
                    
                    if !allContacts.isEmpty {
                        let channel = ObvChannelSendChannelType.allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: allContacts, fromOwnedIdentity: ownedIdentity)
                        let coreMessage = getCoreMessageForOtherProtocol(for: channel, otherCryptoProtocolId: .contactManagement, otherProtocolInstanceUid: UID.gen(with: prng))
                        let concreteMessage = ContactManagementProtocol.PerformContactDeviceDiscoveryMessage(coreProtocolMessage: coreMessage)
                        guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                        _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
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
            
        }

        
        /// Helper method for this step
        private func processChannels(globalOwnedIdentityDeletion: Bool, propagationNeeded: Bool, ownedIdentityIsActive: Bool) throws {
            
            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
            
            try channelDelegate.deleteAllObliviousChannelsWithTheCurrentDeviceUid(currentDeviceUid, within: obvContext)
            
        }

    }
    
    
    // MARK: FinalizeDeletionStepFromDeactivateOwnedDeviceServerQueryMessageStep
    
    final class FinalizeDeletionStepFromDeactivateOwnedDeviceServerQueryMessageStep: FinalizeDeletionStep, TypedConcreteProtocolStep {
        
        let startState: FirstDeletionStepPerformedState
        let receivedMessage: DeactivateOwnedDeviceServerQueryMessage

        init?(startState: FirstDeletionStepPerformedState, receivedMessage: DeactivateOwnedDeviceServerQueryMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState,
                       receivedMessage: .deactivateOwnedDeviceServerQueryMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass
        
    }
    
    
    // MARK: FinalizeDeletionStepFromFinalizeOwnedIdentityDeletionMessageStep
    
    final class FinalizeDeletionStepFromFinalizeOwnedIdentityDeletionMessageStep: FinalizeDeletionStep, TypedConcreteProtocolStep {
        
        let startState: FirstDeletionStepPerformedState
        let receivedMessage: FinalizeOwnedIdentityDeletionMessage

        init?(startState: FirstDeletionStepPerformedState, receivedMessage: FinalizeOwnedIdentityDeletionMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: startState,
                       receivedMessage: .finalizeOwnedIdentityDeletionMessage(receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass
        
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
                           expectedReceptionChannelInfo: .asymmetricChannel,
                           receivedMessage: receivedMessage,
                           concreteCryptoProtocol: concreteCryptoProtocol)
            case .propagatedMessage(receivedMessage: let receivedMessage):
                super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                           expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
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
                    let channelType = ObvChannelSendChannelType.obliviousChannel(to: ownedIdentity, 
                                                                                 remoteDeviceUids: Array(otherDeviceUIDs),
                                                                                 fromOwnedIdentity: ownedIdentity,
                                                                                 necessarilyConfirmed: true,
                                                                                 usePreKeyIfRequired: true)
                    let coreMessage = getCoreMessage(for: channelType)
                    let concreteMessage = ContactOwnedIdentityWasDeletedMessage(coreProtocolMessage: coreMessage, deletedContactOwnedIdentity: deletedContactOwnedIdentity, signature: signature)
                    guard let messageToSend = concreteMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure(); throw Self.makeError(message: "Implementation error") }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
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
                        guard groupManagementProtocolState?.rawId == GroupManagementProtocol.StateId.final.rawValue else {
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
                            changeset: changeset)
                        
                        _ = try channelDelegate.postChannelMessage(initiateGroupUpdateMessage, randomizedWith: prng, within: obvContext)
                        
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
