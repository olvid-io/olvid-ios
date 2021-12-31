/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

extension GroupInvitationProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case SendInvitation = 0
        case ProcessInvitation = 1
        case ProcessInvitationDialogResponse = 2
        case ReCheckTrustLevel = 3
        case ProcessPropagatedInvitationResponse = 4
        case ProcessResponse = 5
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            
            switch self {
                
            case .SendInvitation:
                let step = SendInvitationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessInvitation:
                let step = ProcessInvitationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessInvitationDialogResponse:
                let step = ProcessInvitationDialogResponseStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ReCheckTrustLevel:
                let step = ReCheckTrustLevelStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessPropagatedInvitationResponse:
                let step = ProcessPropagatedInvitationResponseStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessResponse:
                let step = ProcessResponseStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
    }

    
    // MARK: - SendInvitationStep
    
    final class SendInvitationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupInvitationProtocol.InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupInvitationProtocol.logCategory)
            os_log("GroupInvitationProtocol: starting SendInvitationStep", log: log, type: .debug)
            defer { os_log("GroupInvitationProtocol: ending SendInvitationStep", log: log, type: .debug) }

            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let contactIdentity = receivedMessage.contactIdentity
            let groupInformation = receivedMessage.groupInformation
            let membersAndPendingGroupMembers = receivedMessage.membersAndPendingGroupMembers

            // Check that the (pending) group members does not contain the owned identity
            
            guard !membersAndPendingGroupMembers.map({ $0.cryptoIdentity }).contains(ownedIdentity) else {
                os_log("The group members contain the owned identity", log: log, type: .error)
                assertionFailure()
                return CancelledState()
            }
            
            // Check that the group owner corresponds the owned identity of this protocol instance
            
            guard groupInformation.groupOwnerIdentity == ownedIdentity else {
                os_log("The group owner does not correspond to the owned identity", log: log, type: .error)
                return CancelledState()
            }
            
            // Check that the contact identity is part of the (pending) group members
            
            guard membersAndPendingGroupMembers.map({ $0.cryptoIdentity }).contains(contactIdentity) else {
                os_log("The (pending) group members list does not contain the contact identity, so we do not invite her.", log: log, type: .error)
                return CancelledState()
            }
            
            // Post an invitation to contactIdentity
            
            let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contactIdentity]), fromOwnedIdentity: ownedIdentity))
            // Note that the GroupInvitationMessage denotes the members and pending members as 'pending' only. This is because, from the point of view of the recipient, all members are 'pending' at this point
            let concreteProtocolMessage = GroupInvitationMessage(coreProtocolMessage: coreMessage,
                                                                 groupInformation: groupInformation,
                                                                 pendingGroupMembers: membersAndPendingGroupMembers)
            guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                throw NSError()
            }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

            // Return the new state
            
            return InvitationSentState()
            
        }
        
    }
    
    
    // MARK: - ProcessInvitationStep
    
    final class ProcessInvitationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: GroupInvitationMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupInvitationProtocol.GroupInvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupInvitationProtocol.logCategory)
            os_log("GroupInvitationProtocol: starting ProcessInvitationStep", log: log, type: .debug)
            defer { os_log("GroupInvitationProtocol: ending ProcessInvitationStep", log: log, type: .debug) }
            
            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let groupInformation = receivedMessage.groupInformation
            let pendingGroupMembers = receivedMessage.pendingGroupMembers
            
            // Check that we are part of the pending group members
            
            guard pendingGroupMembers.map({ $0.cryptoIdentity }).contains(ownedIdentity) else {
                os_log("The owned identity is not part of the group members", log: log, type: .error)
                return CancelledState()
            }

            // Determine the origin of the message
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessInvitationStep)", log: log, type: .error)
                return CancelledState()
            }
            
            // Check that the remote identity is the group owner
            
            guard groupInformation.groupOwnerIdentity == remoteIdentity else {
                os_log("The message was not sent by the group owner", log: log, type: .error)
                return CancelledState()
            }
            
            /* Check that we are not already aware that we are member of this group. If we are, we do the following :
             * - We send an automatic accept message to the group owner. To do so, we
             *   simply set a Boolean to true and use almost all the code of the block
             *   executed when the trust level is high, except the part where we create the group in DB.
             * - If the received details are distinct from the published group details we knew about,
             *   we reset the trusted details version to 0 and replace the local (published) details by
             *   the ones we just received. Doing so, we know for sure that the version number of the published
             *   details is larger than our version for the trusted details.
             * - We set the members version to 0 so that subsequent updates to these group members will be taken into
             *   account. Note that the group owner will the list of group members when she receives our "accept" message.
             */
            
            let alreadyPartOfThisGroup: Bool
            do {
                if try identityDelegate.getGroupJoinedStructure(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, groupOwner: groupInformation.groupOwnerIdentity, within: obvContext) != nil {
                    alreadyPartOfThisGroup = true
                } else {
                    alreadyPartOfThisGroup = false
                }
            } catch {
                os_log("While receiving an invite to be part of a group, we could not check whether we are already part of the group. We continue, assuming that this is not the case.", log: log, type: .error)
                assertionFailure()
                alreadyPartOfThisGroup = false
            }
            
            // If we were already part of the group, we perform the steps discussed above concerning the group details and the members
            
            if alreadyPartOfThisGroup {
                
                do {
                    try identityDelegate.forceUpdateOfContactGroupJoined(ownedIdentity: ownedIdentity, authoritativeGroupInformation: groupInformation, within: obvContext)
                    try identityDelegate.resetGroupMembersVersionOfContactGroupJoined(ownedIdentity: ownedIdentity, groupUid: groupInformation.groupUid, groupOwner: groupInformation.groupOwnerIdentity, within: obvContext)
                } catch let error {
                    os_log("Could not force update of contact group joined using the receive authoritative information about this group: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // We continue anyway
                }
                
            }
            
            // Get the trust level we have in the group owner

            let groupOwnerTrustLevel: TrustLevel
            do {
                groupOwnerTrustLevel = try identityDelegate.getTrustLevel(forContactIdentity: groupInformation.groupOwnerIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not get the group owner's trust level", log: log, type: .error)
                return CancelledState()
            }
            
            // Continue the step, depending on the trust level
            
            if groupOwnerTrustLevel >= ObvConstants.autoAcceptTrustLevelTreshold || alreadyPartOfThisGroup {
                
                // Auto accept
                
                // Notifiy the group owner that we accepted the invitation
                
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([groupInformation.groupOwnerIdentity]), fromOwnedIdentity: ownedIdentity))
                    let concreteProtocolMessage = InvitationResponseMessage(coreProtocolMessage: coreMessage, groupUid: groupInformation.groupUid, invitationAccepted: true)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw NSError()
                    }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }

                // Propagate the accept to other owned devices
                
                guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                    os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                    return CancelledState()
                }
                
                if numberOfOtherDevicesOfOwnedIdentity > 0 {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagateInvitationResponseMessage(coreProtocolMessage: coreMessage, invitationAccepted: true)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw NSError()
                    }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Create the group (only if we are not already part of it)
                
                if !alreadyPartOfThisGroup {
                    do {
                        let pendingGroupMemberIdentities = pendingGroupMembers.filter { $0.cryptoIdentity != ownedIdentity }
                        try identityDelegate.createContactGroupJoined(ownedIdentity: ownedIdentity,
                                                                      groupInformation: groupInformation,
                                                                      groupOwner: groupInformation.groupOwnerIdentity,
                                                                      pendingGroupMembers: pendingGroupMemberIdentities,
                                                                      within: obvContext)
                    } catch {
                        os_log("Could not create contact group (1)", log: log, type: .error)
                        return CancelledState()
                    }
                }
                                
                // Return the new state

                return ResponseSentState()
                
            } else if groupOwnerTrustLevel >= ObvConstants.userConfirmationTrustLevelTreshold {
                
                // Prompt the user to accept
                
                let dialogUuid = UUID()
                do {
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: ObvChannelDialogToSendType.acceptGroupInvite(groupInformation: groupInformation, pendingGroupMembers: pendingGroupMembers, receivedMessageTimestamp: receivedMessage.timestamp)))
                    let concreteProtocolMessage = DialogAcceptGroupInvitationMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }

                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the group owner increases
                
                guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not retrive this protocol instance", log: log, type: .fault)
                    return CancelledState()
                }
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: groupInformation.groupOwnerIdentity,
                                                                           targetTrustLevel: ObvConstants.autoAcceptTrustLevelTreshold,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }

                // Return the new state
                
                return InvitationReceivedState(groupInformation: groupInformation, dialogUuid: dialogUuid, pendingGroupMembers: pendingGroupMembers)

            } else {
                
                // Prompt the user to increase trust levels

                let dialogUuid = UUID()
                do {
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: ObvChannelDialogToSendType.increaseGroupOwnerTrustLevel(groupInformation: groupInformation, pendingGroupMembers: pendingGroupMembers, receivedMessageTimestamp: receivedMessage.timestamp)))
                    let concreteProtocolMessage = DialogAcceptGroupInvitationMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }

                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the group owner increases
                
                guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not retrive this protocol instance", log: log, type: .fault)
                    return CancelledState()
                }
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: groupInformation.groupOwnerIdentity,
                                                                           targetTrustLevel: ObvConstants.userConfirmationTrustLevelTreshold,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }

                return InvitationReceivedState(groupInformation: groupInformation, dialogUuid: dialogUuid, pendingGroupMembers: pendingGroupMembers)
                
            }
            
        }
        
    }
    
    
    // MARK: - ProcessInvitationDialogResponse
    
    final class ProcessInvitationDialogResponseStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: DialogAcceptGroupInvitationMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: GroupInvitationProtocol.DialogAcceptGroupInvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupInvitationProtocol.logCategory)
            os_log("GroupInvitationProtocol: starting ProcessInvitationDialogResponse", log: log, type: .debug)
            defer { os_log("GroupInvitationProtocol: ending ProcessInvitationDialogResponse", log: log, type: .debug) }
            
            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let groupInformation = startState.groupInformation
            let dialogUuid = startState.dialogUuid
            let pendingGroupMembers = startState.pendingGroupMembers
            
            guard dialogUuid == receivedMessage.dialogUuid else {
                os_log("Dialog uuid mismatch", log: log, type: .error)
                return CancelledState()
            }
            let invitationAccepted = receivedMessage.invitationAccepted
            
            // Remove the dialog
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Check that the group owner is an active contact
            
            guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: groupInformation.groupOwnerIdentity, within: obvContext) else {
                os_log("The group owner is not an active contact, we abort the protocol", log: log, type: .error)
                return CancelledState()
            }
            
            // Notifiy the group owner that we accepted the invitation (or not)
            
            do {
                let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([groupInformation.groupOwnerIdentity]), fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = InvitationResponseMessage(coreProtocolMessage: coreMessage, groupUid: groupInformation.groupUid, invitationAccepted: invitationAccepted)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    os_log("Could not generate protocol message to send, we abort the protocol", log: log, type: .error)
                    return CancelledState()
                }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // If the invitation was not accepted, we are done.
            
            guard invitationAccepted else {
                return ResponseSentState()
            }
            
            // If we reach this point, the response was accepted.
            
            // Create the group
            
            do {
                let pendingGroupMemberIdentities = pendingGroupMembers.filter { $0.cryptoIdentity != ownedIdentity }
                try identityDelegate.createContactGroupJoined(ownedIdentity: ownedIdentity,
                                                              groupInformation: groupInformation,
                                                              groupOwner: groupInformation.groupOwnerIdentity,
                                                              pendingGroupMembers: pendingGroupMemberIdentities,
                                                              within: obvContext)
            } catch {
                os_log("Could not create contact group (2)", log: log, type: .error)
                return CancelledState()
            }

            // Show the group joined dialog
            
            do {
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: ObvChannelDialogToSendType.groupJoined(groupInformation: groupInformation)))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            return ResponseSentState()

        }
        
    }

    
    // MARK: - ReCheckTrustLevelStep
    
    final class ReCheckTrustLevelStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: TrustLevelIncreasedMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: GroupInvitationProtocol.TrustLevelIncreasedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupInvitationProtocol.logCategory)
            os_log("GroupInvitationProtocol: starting ReCheckTrustLevelStep", log: log, type: .debug)
            defer { os_log("GroupInvitationProtocol: ending ReCheckTrustLevelStep", log: log, type: .debug) }
            
            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let groupInformation = startState.groupInformation
            let dialogUuid = startState.dialogUuid
            let pendingGroupMembers = startState.pendingGroupMembers
            let identityWithTrustLevelIncreased = receivedMessage.identityWithTrustLevelIncreased
            
            // Check that the the identity with increases trust level is the group owner
            
            guard identityWithTrustLevelIncreased == groupInformation.groupOwnerIdentity else {
                os_log("The identity with increased trust level is not the group owner", log: log, type: .error)
                return startState
            }
            
            // Get the trust level we have in the group owner
            
            let groupOwnerTrustLevel: TrustLevel
            do {
                groupOwnerTrustLevel = try identityDelegate.getTrustLevel(forContactIdentity: groupInformation.groupOwnerIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not get the group owner's trust level", log: log, type: .error)
                return CancelledState()
            }
            
            // Continue the step, depending on the trust level
            
            if groupOwnerTrustLevel >= ObvConstants.autoAcceptTrustLevelTreshold {
                
                // Auto accept
                
                // Notifiy the group owner that we accepted the invitation
                
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([groupInformation.groupOwnerIdentity]), fromOwnedIdentity: ownedIdentity))
                    let concreteProtocolMessage = InvitationResponseMessage(coreProtocolMessage: coreMessage, groupUid: groupInformation.groupUid, invitationAccepted: true)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw NSError()
                    }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Propagate the accept to other owned devices
                
                guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                    os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                    return CancelledState()
                }
                
                if numberOfOtherDevicesOfOwnedIdentity > 0 {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagateInvitationResponseMessage(coreProtocolMessage: coreMessage, invitationAccepted: true)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw NSError()
                    }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Create the group
                
                do {
                    let pendingGroupMemberIdentities = pendingGroupMembers.filter { $0.cryptoIdentity != ownedIdentity }
                    try identityDelegate.createContactGroupJoined(ownedIdentity: ownedIdentity,
                                                                  groupInformation: groupInformation,
                                                                  groupOwner: groupInformation.groupOwnerIdentity,
                                                                  pendingGroupMembers: pendingGroupMemberIdentities,
                                                                  within: obvContext)
                } catch {
                    os_log("Could not create contact group (3)", log: log, type: .error)
                    return CancelledState()
                }
                
                // Show the group joined dialog
                
                do {
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: ObvChannelDialogToSendType.groupJoined(groupInformation: groupInformation)))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return ResponseSentState()
                
            } else if groupOwnerTrustLevel >= ObvConstants.userConfirmationTrustLevelTreshold {
                
                // Prompt the user to accept
                
                do {
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: ObvChannelDialogToSendType.acceptGroupInvite(groupInformation: groupInformation, pendingGroupMembers: pendingGroupMembers, receivedMessageTimestamp: receivedMessage.timestamp)))
                    let concreteProtocolMessage = DialogAcceptGroupInvitationMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Delete any previous entry in the ProtocolInstanceWaitingForTrustLevelIncrease database
                
                guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not retrive this protocol instance", log: log, type: .fault)
                    return CancelledState()
                }

                do {
                    try ProtocolInstanceWaitingForTrustLevelIncrease.deleteRelatedToProtocolInstance(thisProtocolInstance, contactCryptoIdentity: groupInformation.groupOwnerIdentity, delegateManager: delegateManager)
                } catch {
                    os_log("Could not delete previous ProtocolInstanceWaitingForTrustLevelIncrease entries", log: log, type: .fault)
                    return CancelledState()
                }
                
                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the group owner increases
                
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: groupInformation.groupOwnerIdentity,
                                                                           targetTrustLevel: ObvConstants.autoAcceptTrustLevelTreshold,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }
                
                // Return the new state
                
                return InvitationReceivedState(groupInformation: groupInformation, dialogUuid: dialogUuid, pendingGroupMembers: pendingGroupMembers)
                
            } else {
                
                // Prompt the user to increase trust levels
                
                do {
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: ObvChannelDialogToSendType.increaseGroupOwnerTrustLevel(groupInformation: groupInformation, pendingGroupMembers: pendingGroupMembers, receivedMessageTimestamp: receivedMessage.timestamp)))
                    let concreteProtocolMessage = DialogAcceptGroupInvitationMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Delete any previous entry in the ProtocolInstanceWaitingForTrustLevelIncrease database
                
                guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not retrive this protocol instance", log: log, type: .fault)
                    return CancelledState()
                }
                
                do {
                    try ProtocolInstanceWaitingForTrustLevelIncrease.deleteRelatedToProtocolInstance(thisProtocolInstance, contactCryptoIdentity: groupInformation.groupOwnerIdentity, delegateManager: delegateManager)
                } catch {
                    os_log("Could not delete previous ProtocolInstanceWaitingForTrustLevelIncrease entries", log: log, type: .fault)
                    return CancelledState()
                }
                
                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the group owner increases
                
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: groupInformation.groupOwnerIdentity,
                                                                           targetTrustLevel: ObvConstants.userConfirmationTrustLevelTreshold,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }
                
                return InvitationReceivedState(groupInformation: groupInformation, dialogUuid: dialogUuid, pendingGroupMembers: pendingGroupMembers)
                
            }

        }
        
    }
    
    
    // MARK: - ProcessPropagatedInvitationResponseStep
    
    final class ProcessPropagatedInvitationResponseStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: PropagateInvitationResponseMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: GroupInvitationProtocol.PropagateInvitationResponseMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupInvitationProtocol.logCategory)
            os_log("GroupInvitationProtocol: starting ProcessPropagatedInvitationResponseStep", log: log, type: .debug)
            defer { os_log("GroupInvitationProtocol: ending ProcessPropagatedInvitationResponseStep", log: log, type: .debug) }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let groupInformation = startState.groupInformation
            let dialogUuid = startState.dialogUuid
            let pendingGroupMembers = startState.pendingGroupMembers
            let invitationAccepted = receivedMessage.invitationAccepted

            // Remove the dialog
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Make sure the group owner is an active contact
            
            guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: groupInformation.groupOwnerIdentity, within: obvContext) else {
                os_log("The group owner is not an active contact, we abort the protocol", log: log, type: .error)
                return CancelledState()
            }

            // If the invitation was not accepted, we are done.
            
            guard invitationAccepted else {
                return ResponseSentState()
            }
            
            // If we reach this point, the response was accepted.

            // Create the group
            
            do {
                let pendingGroupMemberIdentities = pendingGroupMembers.filter { $0.cryptoIdentity != ownedIdentity }
                try identityDelegate.createContactGroupJoined(ownedIdentity: ownedIdentity,
                                                              groupInformation: groupInformation,
                                                              groupOwner: groupInformation.groupOwnerIdentity,
                                                              pendingGroupMembers: pendingGroupMemberIdentities,
                                                              within: obvContext)
            } catch {
                os_log("Could not create contact group (4)", log: log, type: .error)
                return CancelledState()
            }
            
            // Return the new state
            
            return ResponseSentState()

        }
        
    }
    
    
    // MARK: - ProcessResponseStep
    
    final class ProcessResponseStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InvitationResponseMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: GroupInvitationProtocol.InvitationResponseMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: GroupInvitationProtocol.logCategory)
            os_log("GroupInvitationProtocol: starting ProcessResponseStep", log: log, type: .debug)
            defer { os_log("GroupInvitationProtocol: ending ProcessResponseStep", log: log, type: .debug) }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let groupUid = receivedMessage.groupUid
            let invitationAccepted = receivedMessage.invitationAccepted
            
            // Get the contact that sent the protocol message
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessResponseStep)", log: log, type: .error)
                return CancelledState()
            }

            // Get the group structure from database
            
            let groupStructure: GroupStructure
            do {
                guard let _groupStructure = try identityDelegate.getGroupOwnedStructure(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {

                    // The group was not found in database, probably because it was deleted between now and the time we sent the invitation to the contact.
                    // We send a message to the contact to kick her out of the group. Since we do not have any proper group information for this group, we create "dummy" group informations.

                    let dummyGroupInformation = try GroupInformation.createDummyGroupInformation(groupOwnerIdentity: ownedIdentity, groupUid: groupUid)
                    
                    let protocolInstanceUidForGroupManagement = dummyGroupInformation.associatedProtocolUid
                    let coreMessage = CoreProtocolMessage(channelType: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([remoteIdentity]), fromOwnedIdentity: ownedIdentity),
                                                          cryptoProtocolId: .GroupManagement,
                                                          protocolInstanceUid: protocolInstanceUidForGroupManagement)
                    let concreteProtocolMessage = GroupManagementProtocol.KickFromGroupMessage(coreProtocolMessage: coreMessage, groupInformation: dummyGroupInformation)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        os_log("Could not generate ObvChannelProtocolMessageToSend for a KickFromGroupMessage from within the GroupInvitationProtocol", log: log, type: .error)
                        return CancelledState()
                    }
                    
                    do {
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Could not notify member that she has been kicked out from group that could not be found", log: log, type: .error)
                        // Continue
                    }
                    
                    return ResponseReceivedState()
                }
                groupStructure = _groupStructure
            } catch {
                os_log("Could not access the group in database", log: log, type: .error)
                return CancelledState()
            }
                        
            // Check that the contact (remote identity) is part of the pending members (or actual members) of the group
            // If this is not the case, and the contact accepted to enter the group, send an KickFromGroupMessage
            // (from the GroupManagementProtocol). Note that this message was already sent to this contact but she obviously never received it.
            
            guard groupStructure.pendingGroupMembers.map({ $0.cryptoIdentity }).contains(remoteIdentity) || groupStructure.groupMembers.contains(remoteIdentity) else {
                os_log("The remote identity is not part of the pending members of the group", log: log, type: .error)

                guard let groupInformationWithPhoto = try? identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                    os_log("Could not access the group information in database", log: log, type: .error)
                    return CancelledState()
                }
                
                let protocolInstanceUidForGroupManagement = groupInformationWithPhoto.associatedProtocolUid
                let coreMessage = CoreProtocolMessage(channelType: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([remoteIdentity]), fromOwnedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .GroupManagement,
                                                      protocolInstanceUid: protocolInstanceUidForGroupManagement)
                let concreteProtocolMessage = GroupManagementProtocol.KickFromGroupMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformationWithPhoto.groupInformation)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    os_log("Could not generate ObvChannelProtocolMessageToSend for a KickFromGroupMessage from within the GroupInvitationProtocol", log: log, type: .error)
                    return CancelledState()
                }
                
                do {
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not notify member that she has been kicked out from group owned", log: log, type: .error)
                    // Continue
                }

                return CancelledState()
            }
            
            // If the contact is already part of the group members, we consider two case, whether she accepted or not.
            
            guard !groupStructure.groupMembers.contains(remoteIdentity) else {
                
                guard let groupInformationWithPhoto = try? identityDelegate.getGroupOwnedInformationAndPublishedPhoto(ownedIdentity: ownedIdentity, groupUid: groupUid, within: obvContext) else {
                    os_log("Could not access the group information in database", log: log, type: .error)
                    return CancelledState()
                }
                
                if invitationAccepted {
                    
                    os_log("We received an *accept* invite response from a contact who is already member of the group. We now send her the latest version of the group members list.", log: log, type: .info)
                    
                    // In that case, we know that the member reset the group member list number back to zero. We now send her the latest version of this list.
                    
                    let protocolInstanceUidForGroupManagement = groupInformationWithPhoto.associatedProtocolUid
                    let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                                          cryptoProtocolId: .GroupManagement,
                                                          protocolInstanceUid: protocolInstanceUidForGroupManagement)
                    let concreteProtocolMessage = GroupManagementProtocol.TriggerUpdateMembersMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformationWithPhoto.groupInformation, memberIdentity: remoteIdentity)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        os_log("Could not generate ObvChannelProtocolMessageToSend for a TriggerUpdateMembersMessage from within the GroupInvitationProtocol", log: log, type: .error)
                        return CancelledState()
                    }
                    
                    do {
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Could not send the latest version of the group members to a member if a group owned", log: log, type: .error)
                        assertionFailure()
                        // Continue
                    }
                    
                } else {
                    os_log("We received an *reject* invite response from a contact who is already member of the group. We pass this member to the pending members", log: log, type: .info)
                    
                    // The following callback is called after the members of the group have changed. It allows to send a (local) protocol message to the group management protocol, notifying this protocol instance that the group members changed.
                    
                    let groupMembersChangedCallback = GroupInvitationProtocol.makeGroupMembersChangedCallback(groupUid: groupUid,
                                                                                                              ownedIdentity: ownedIdentity,
                                                                                                              identityDelegate: identityDelegate,
                                                                                                              channelDelegate: channelDelegate,
                                                                                                              log: log,
                                                                                                              prng: prng,
                                                                                                              within: obvContext)
                    
                    // Move the member from the list of actual members to the list of pending members and mark her as declined
                    
                    do {
                        try identityDelegate.transferGroupMemberToPendingMembersOfContactGroupOwnedAndMarkPendingMemberAsDeclined(ownedIdentity: ownedIdentity,
                                                                                                                                  groupUid: groupUid,
                                                                                                                                  groupMember: remoteIdentity,
                                                                                                                                  within: obvContext,
                                                                                                                                  groupMembersChangedCallback: groupMembersChangedCallback)
                    } catch {
                        os_log("Could not transfer the member from the group members to the list of pending members", log: log, type: .error)
                        return CancelledState()
                    }
                    
                    // Send a kick message to this demoted member. This is message is only usefull in the case where we received the responses from this member in the wrong order (i.e., she sent 'reject' then 'accept' and we received 'accept' then 'reject'.).

                    let protocolInstanceUidForGroupManagement = groupInformationWithPhoto.associatedProtocolUid
                    let coreMessage = CoreProtocolMessage(channelType: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([remoteIdentity]), fromOwnedIdentity: ownedIdentity),
                                                          cryptoProtocolId: .GroupManagement,
                                                          protocolInstanceUid: protocolInstanceUidForGroupManagement)
                    let concreteProtocolMessage = GroupManagementProtocol.KickFromGroupMessage(coreProtocolMessage: coreMessage, groupInformation: groupInformationWithPhoto.groupInformation)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        os_log("Could not generate ObvChannelProtocolMessageToSend for a KickFromGroupMessage from within the GroupInvitationProtocol", log: log, type: .error)
                        return CancelledState()
                    }
                    
                    do {
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Could not notify member that she has been kicked out from group owned", log: log, type: .error)
                        // Continue
                    }
                    
                }
                
                return ResponseReceivedState()

            }
            
            // At this point, we know that the contact is part of the pending members, and not of the actual members.
            // Continue the step, depending on whether the remote identity accepted the invitation or not
            
            if invitationAccepted {
                
                let ownedIdentity = self.ownedIdentity
                
                // The following callback is called after the members of the group have changed. It allows to send a (local) protocol message to the group management protocol, notifying this protocol instance that the group members changed.
                
                let groupMembersChangedCallback = GroupInvitationProtocol.makeGroupMembersChangedCallback(groupUid: groupUid,
                                                                                                          ownedIdentity: ownedIdentity,
                                                                                                          identityDelegate: identityDelegate,
                                                                                                          channelDelegate: channelDelegate,
                                                                                                          log: log,
                                                                                                          prng: prng,
                                                                                                          within: obvContext)

                do {
                    try identityDelegate.transferPendingMemberToGroupMembersOfContactGroupOwned(ownedIdentity: ownedIdentity,
                                                                                                groupUid: groupUid,
                                                                                                pendingMember: remoteIdentity,
                                                                                                within: obvContext,
                                                                                                groupMembersChangedCallback: groupMembersChangedCallback)
                } catch {
                    os_log("Could not transfer the remote identity from the pending members to the group members", log: log, type: .error)
                    return CancelledState()
                }
                    
                
            } else {
                
                // Discard the remote identity from the list of pending members

                do {
                    try identityDelegate.markPendingMemberAsDeclined(ownedIdentity: ownedIdentity,
                                                                     groupUid: groupUid,
                                                                     pendingMember: remoteIdentity,
                                                                     within: obvContext)
                } catch {
                    os_log("Could not mark the pending member as declined", log: log, type: .error)
                    return CancelledState()
                }
                
            }
            
            // Return the new state
            
            return ResponseReceivedState()
            
        }
        
    }
            
    
    // MARK: - Helpers
    
    private static func makeGroupMembersChangedCallback(groupUid: UID, ownedIdentity: ObvCryptoIdentity, identityDelegate: ObvIdentityDelegate, channelDelegate: ObvChannelDelegate, log: OSLog, prng: PRNGService, within obvContext: ObvContext) -> (() throws -> Void) {
        
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
            let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                                  cryptoProtocolId: .GroupManagement,
                                                  protocolInstanceUid: childProtocolInstanceUid)
            let childProtocolInitialMessage = GroupManagementProtocol.GroupMembersChangedTriggerMessage(coreProtocolMessage: coreMessage,
                                                                                                        groupInformation: groupInformationWithPhoto.groupInformation)
            guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

        }

        return groupMembersChangedCallback
        
    }
        
}
