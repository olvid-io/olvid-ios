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
import OlvidUtils
import os.log
import ObvTypes
import ObvMetaManager
import ObvCrypto


extension OneToOneContactInvitationProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case aliceInvitesBob = 0
        case bobProcessesAlicesInvitation = 1
        case bobRespondsToAlicesInvitation = 2
        case aliceReceivesBobsResponse = 3
        case aliceAbortsHerInvitationToBob = 4
        case bobProcessesAbort = 5
        case processContactUpgradedToOneToOneWhileInInvitationSentState = 6
        case processContactUpgradedToOneToOneWhileInInvitationReceivedState = 7
        case processPropagatedOneToOneInvitationMessage = 8
        case processPropagatedOneToOneResponseMessage = 9
        case processPropagatedAbortMessage = 10
        case aliceProcessesUnexpectedBobResponse = 11
        case aliceSendsOneToOneStatusSyncRequestMessages = 12
        case bobProcessesSyncRequest = 13

        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
            case .aliceInvitesBob:
                return AliceInvitesBobStep(from: concreteProtocol, and: receivedMessage)
            case .bobProcessesAlicesInvitation:
                return BobProcessesAlicesInvitationStep(from: concreteProtocol, and: receivedMessage)
            case .bobRespondsToAlicesInvitation:
                return BobRespondsToAlicesInvitationStep(from: concreteProtocol, and: receivedMessage)
            case .aliceReceivesBobsResponse:
                return AliceReceivesBobsResponseStep(from: concreteProtocol, and: receivedMessage)
            case .aliceAbortsHerInvitationToBob:
                return AliceAbortsHerInvitationToBobStep(from: concreteProtocol, and: receivedMessage)
            case .bobProcessesAbort:
                return BobProcessesAbortStep(from: concreteProtocol, and: receivedMessage)
            case .processContactUpgradedToOneToOneWhileInInvitationSentState:
                return ProcessContactUpgradedToOneToOneWhileInInvitationSentStateStep(from: concreteProtocol, and: receivedMessage)
            case .processContactUpgradedToOneToOneWhileInInvitationReceivedState:
                return ProcessContactUpgradedToOneToOneWhileInInvitationReceivedStateStep(from: concreteProtocol, and: receivedMessage)
            case .processPropagatedOneToOneInvitationMessage:
                return ProcessPropagatedOneToOneInvitationMessageStep(from: concreteProtocol, and: receivedMessage)
            case .processPropagatedOneToOneResponseMessage:
                return ProcessPropagatedOneToOneResponseMessageStep(from: concreteProtocol, and: receivedMessage)
            case .processPropagatedAbortMessage:
                return ProcessPropagatedAbortMessageStep(from: concreteProtocol, and: receivedMessage)
            case .aliceProcessesUnexpectedBobResponse:
                return AliceProcessesUnexpectedBobResponseStep(from: concreteProtocol, and: receivedMessage)
            case .aliceSendsOneToOneStatusSyncRequestMessages:
                return AliceSendsOneToOneStatusSyncRequestMessagesStep(from: concreteProtocol, and: receivedMessage)
            case .bobProcessesSyncRequest:
                return BobProcessesSyncRequestStep(from: concreteProtocol, and: receivedMessage)
            }
        }

    }

    
    
    // MARK: - AliceInvitesBobStep
    
    final class AliceInvitesBobStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OneToOneContactInvitationProtocol.logCategory)
            
            let contactIdentity = receivedMessage.contactIdentity

            // If Bob is already a OneToOne contact, there is nothing to do in theory. Yet, we decide to send the protocol message anyway.
            
            // Create an ObvDialog informing Alice that her request has been taken into account. This dialog also allows Alice to abort this
            // Protocol. We only do this if Bob is not already oneToOne (as aborting the protocol using the dialog always reset the contact to
            // non-oneToOne).

            let dialogUuid = UUID()
            let contactStatus = try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext)
            switch contactStatus {
            case .oneToOne:
                // Do not show a dialog
                break
            case .notOneToOne, .toBeDefined:
                let dialogType = ObvChannelDialogToSendType.oneToOneInvitationSent(contact: contactIdentity, ownedIdentity: ownedIdentity)
                let channelType = ObvChannelSendChannelType.UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType)
                let coreMessage = getCoreMessage(for: channelType)
                let concreteProtocolMessage = DialogInvitationSentMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Send a OneToOne invitation to Bob
            
            do {
                let channelType = ObvChannelSendChannelType.AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contactIdentity]), fromOwnedIdentity: ownedIdentity)
                let coreMessage = getCoreMessage(for: channelType)
                let concreteProtocolMessage = OneToOneInvitationMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    throw Self.makeError(message: "Could not generate ProtocolMessageToSend for OneToOneInvitationMessage")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Create an entry in the ProtocolInstanceWaitingForContactUpgradeToOneToOne. This makes it possible to accept immediately in case
            // We receive an invitation from Bob (which typically happens when Bob sends an invitation at the exact same moment as we do or without seeing Alice's invitation).
            
            guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not retrive this protocol instance", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }

            guard let _ = ProtocolInstanceWaitingForContactUpgradeToOneToOne(ownedCryptoIdentity: ownedIdentity,
                                                                             contactCryptoIdentity: contactIdentity,
                                                                             messageToSendRawId: MessageId.contactUpgradedToOneToOne.rawValue,
                                                                             protocolInstance: thisProtocolInstance,
                                                                             delegateManager: delegateManager)
                else {
                    os_log("Could not create an entry in the ProtocolInstanceWaitingForContactUpgradeToOneToOne database", log: log, type: .fault)
                    return CancelledState()
            }
            
            // Propagate the invitation to the other owned devices of Alice
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count

            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagateOneToOneInvitationMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not propagate OneToOne invitation to other devices.", log: log, type: .fault)
                    assertionFailure()
                }
            }

            // Finish this step, we wait from Bob answer.
            
            return InvitationSentState(contactIdentity: contactIdentity, dialogUuid: dialogUuid)
            
        }
    }

    
    // MARK: - BobProcessesAlicesInvitationStep
    
    final class BobProcessesAlicesInvitationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: OneToOneInvitationMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: OneToOneInvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OneToOneContactInvitationProtocol.logCategory)
            
            // Determine the origin of the message
            
            guard let contactIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessNewMembersStep)", log: log, type: .error)
                return CancelledState()
            }
            
            // If the remote identity is already a OneToOne contact, we can immediately accept the invitation and
            // Finish the protocol
            
            let contactStatus = try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext)
            
            switch contactStatus {
            case .oneToOne:
                
                do {
                    let channelType = ObvChannelSendChannelType.AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contactIdentity]), fromOwnedIdentity: ownedIdentity)
                    let coreMessage = getCoreMessage(for: channelType)
                    let concreteProtocolMessage = OneToOneResponseMessage(coreProtocolMessage: coreMessage, invitationAccepted: true)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw Self.makeError(message: "Could not generate ProtocolMessageToSend for OneToOneInvitationMessage")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                return FinishedState()
                
            case .notOneToOne, .toBeDefined:
                
                break

            }
            
            // It might be the case that Bob already invited Alice. This can be detected by looking for an appropriate entry in the
            // ProtocolInstanceWaitingForContactUpgradeToOneToOne database. If an entry is found, no need to ask Bob whether he accepts the invitation:
            // We automatically accept it and do the work to make sure the other protocol instance (the one started when Bob sent his invitation) does finish.
            
            do {
                let waitingInstances = try ProtocolInstanceWaitingForContactUpgradeToOneToOne.getAll(ownedCryptoIdentity: ownedIdentity, contactCryptoIdentity: contactIdentity, delegateManager: delegateManager, within: obvContext)
                let appropriateWaitingInstances = waitingInstances
                    .compactMap({ $0.protocolInstance })
                    .filter({ $0.cryptoProtocolId == self.cryptoProtocolId })
                    .filter({ $0.currentStateRawId == StateId.invitationSent.rawValue })
                guard appropriateWaitingInstances.isEmpty else {
                 
                    // If we reach this point, we can indeed auto-accept the invitation
                    
                    // Upgrade Alice's OneToOne status. When the context is saved, a notification will be send that the trust level was increased.
                    // This will be catched by the protocol manager which will replay the message in the ProtocolInstanceWaitingForContactUpgradeToOneToOne db.
                    // This message will execute the ProcessContactUpgradedToOneToOneStep of the other protocol instance, allowing it to finish properly
                    
                    let reasonToLog = "OneToOneContactInvitationProtocol.BobProcessesAlicesInvitationStep"
                    try identityDelegate.setOneToOneContactStatus(ownedIdentity: ownedIdentity,
                                                                  contactIdentity: contactIdentity,
                                                                  newIsOneToOneStatus: true,
                                                                  reasonToLog: reasonToLog,
                                                                  within: obvContext)

                    // Accept the invitation
                    
                    do {
                        let channelType = ObvChannelSendChannelType.AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contactIdentity]), fromOwnedIdentity: ownedIdentity)
                        let coreMessage = getCoreMessage(for: channelType)
                        let concreteProtocolMessage = OneToOneResponseMessage(coreProtocolMessage: coreMessage, invitationAccepted: true)
                        guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                            throw Self.makeError(message: "Could not generate ProtocolMessageToSend for OneToOneInvitationMessage")
                        }
                        _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                    }

                    // We can finish this protocol instance
                    
                    return FinishedState()

                }
            }
            
            // If we reach this point, we received a OneToOne invitations from a non-OneToOne contact. We show a dialog to Bob
            // Allowing him to accept or decline this invitation
            
            let dialogUuid = UUID()
            do {
                let dialogType = ObvChannelDialogToSendType.oneToOneInvitationReceived(contact: contactIdentity, ownedIdentity: ownedIdentity)
                let channelType = ObvChannelSendChannelType.UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType)
                let coreMessage = getCoreMessage(for: channelType)
                let concreteProtocolMessage = DialogAcceptOneToOneInvitationMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // If Bob decides to send an invitation to Alice (e.g., because he did not see Alice's invitation), we want to properly finish
            // This protocol. To do so, we create the appropriate instance in the ProtocolInstanceWaitingForContactUpgradeToOneToOne database.
            
            guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not retrive this protocol instance", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }

            guard let _ = ProtocolInstanceWaitingForContactUpgradeToOneToOne(ownedCryptoIdentity: ownedIdentity,
                                                                             contactCryptoIdentity: contactIdentity,
                                                                             messageToSendRawId: MessageId.contactUpgradedToOneToOne.rawValue,
                                                                             protocolInstance: thisProtocolInstance,
                                                                             delegateManager: delegateManager)
                else {
                    os_log("Could not create an entry in the ProtocolInstanceWaitingForContactUpgradeToOneToOne database", log: log, type: .fault)
                    return CancelledState()
            }

            // Finish this step
            
            return InvitationReceivedState(contactIdentity: contactIdentity, dialogUuid: dialogUuid)

        }
    }

    
    // MARK: - BobRespondsToAlicesInvitationStep
    
    final class BobRespondsToAlicesInvitationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: DialogAcceptOneToOneInvitationMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: DialogAcceptOneToOneInvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OneToOneContactInvitationProtocol.logCategory)
            
            let contactIdentity = startState.contactIdentity
            let invitationAccepted = receivedMessage.invitationAccepted
            let dialogUuid = receivedMessage.dialogUuid
            
            // If Alice is not a contact anymore (because she was deleted in the meantime), we simply removes Bob's dialog and end this protocol instance.
            
            guard try identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) else {
                
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                
                return FinishedState()
            }
            
            // Send Bob response to Alice
            
            do {
                let channelType = ObvChannelSendChannelType.AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contactIdentity]), fromOwnedIdentity: ownedIdentity)
                let coreMessage = getCoreMessage(for: channelType)
                let concreteProtocolMessage = OneToOneResponseMessage(coreProtocolMessage: coreMessage, invitationAccepted: invitationAccepted)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    throw Self.makeError(message: "Could not generate ProtocolMessageToSend for OneToOneInvitationMessage")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Upgrade/downgrade Alice's OneToOne status
            
            let reasonToLog = "OneToOneContactInvitationProtocol.BobRespondsToAlicesInvitationStep"
            try identityDelegate.setOneToOneContactStatus(ownedIdentity: ownedIdentity,
                                                          contactIdentity: contactIdentity,
                                                          newIsOneToOneStatus: invitationAccepted,
                                                          reasonToLog: reasonToLog,
                                                          within: obvContext)
            
            // Remove Bob's dialog
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Propagate the answer to the other owned devices of Bob
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count

            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagateOneToOneResponseMessage(coreProtocolMessage: coreMessage, invitationAccepted: invitationAccepted)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not propagate accept/reject invitation to other devices.", log: log, type: .fault)
                    assertionFailure()
                }
            }

            // Finish this protocol. Note that the ProtocolInstanceWaitingForContactUpgradeToOneToOne instance created in the
            // BobProcessesAlicesInvitationStep step will be cascade deleted.

            return FinishedState()
        }
    }

    
    // MARK: - AliceReceivesBobsResponseStep
    
    final class AliceReceivesBobsResponseStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationSentState
        let receivedMessage: OneToOneResponseMessage
        
        init?(startState: InvitationSentState, receivedMessage: OneToOneResponseMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OneToOneContactInvitationProtocol.logCategory)
            
            let contactIdentity = startState.contactIdentity
            let dialogUuid = startState.dialogUuid
            let invitationAccepted = receivedMessage.invitationAccepted
            
            // Determine the origin of the message
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessNewMembersStep)", log: log, type: .error)
                return CancelledState()
            }

            // Check that the origin of the message is coherent with the contact we kept in the state
            
            guard contactIdentity == remoteIdentity else {
                os_log("The origin of the message is coherent with the contact we kept in the state", log: log, type: .error)
                return startState
            }
            
            // Upgrade/downgrade Bob's OneToOne status
            
            let reasonToLog = "OneToOneContactInvitationProtocol.AliceReceivesBobsResponseStep"
            try identityDelegate.setOneToOneContactStatus(ownedIdentity: ownedIdentity,
                                                          contactIdentity: contactIdentity,
                                                          newIsOneToOneStatus: invitationAccepted,
                                                          reasonToLog: reasonToLog,
                                                          within: obvContext)
            
            // Remove the dialog showed to Alice (telling her that an invitation was sent to Bob, and allowing to abort this protocol)
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Finish the protocol. Note that the ProtocolInstanceWaitingForContactUpgradeToOneToOne instance created in the
            // AliceInvitesBob step will be cascade deleted.
            
            return FinishedState()
        }
    }

    
    // MARK: - AliceAbortsHerInvitationToBobStep
    
    final class AliceAbortsHerInvitationToBobStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationSentState
        let receivedMessage: DialogInvitationSentMessage // This dialog, when received, allows to abort the protocol started for inviting the contact
        
        init?(startState: InvitationSentState, receivedMessage: DialogInvitationSentMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity, // We cannot access ownedIdentity directly at this point,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OneToOneContactInvitationProtocol.logCategory)
            
            let contactIdentity = startState.contactIdentity
            let dialogUuid = startState.dialogUuid
            let cancelInvitation = receivedMessage.cancelInvitation
            
            // If Bob is not a contact anymore (because he was deleted in the meantime), we simply removes Alice's dialog and end this protocol instance.
            
            guard try identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) else {
                
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                
                return FinishedState()
            }

            // Check that cancelInvitation is what we expect (it should always be true)
            
            guard cancelInvitation else {
                assertionFailure()
                return startState
            }

            // Send an abort message to Bob
            
            do {
                let channelType = ObvChannelSendChannelType.AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contactIdentity]), fromOwnedIdentity: ownedIdentity)
                let coreMessage = getCoreMessage(for: channelType)
                let concreteProtocolMessage = AbortMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    throw Self.makeError(message: "Could not generate ProtocolMessageToSend for AbortMessage")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Remove the dialog showed to Alice (telling her that an invitation was sent to Bob, and allowing to abort this protocol, which is exactly what we are doing here)
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Propagate the abort to the other owned devices of Alice
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count

            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagateAbortMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not propagate abort OneToOne invitation to other devices.", log: log, type: .fault)
                    assertionFailure()
                }
            }

            // Finish the protocol. Note that the ProtocolInstanceWaitingForContactUpgradeToOneToOne instance created in the
            // AliceInvitesBob step will be cascade deleted.
            
            return FinishedState()
        }
    }

    
    // MARK: - BobProcessesAbortStep
    
    final class BobProcessesAbortStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: AbortMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: AbortMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
                     
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OneToOneContactInvitationProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let dialogUuid = startState.dialogUuid
            
            // Check the message origin
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessNewMembersStep)", log: log, type: .error)
                return CancelledState()
            }

            guard contactIdentity == remoteIdentity else {
                os_log("Unexpected message origin. Ending the protocol step now.", log: log, type: .error)
                return startState
            }
            
            // Remove the dialog showed to Bob (that allowed Bob to accept Alice's invitation, but hey, it's too late now)
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Finish the protocol
            
            return FinishedState()
        }
    }

    
    // MARK: - ProcessContactUpgradedToOneToOneWhileInInvitationSentStateStep
    
    final class ProcessContactUpgradedToOneToOneWhileInInvitationSentStateStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationSentState
        let receivedMessage: ContactUpgradedToOneToOneMessage
        
        init?(startState: InvitationSentState, receivedMessage: ContactUpgradedToOneToOneMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let contactIdentity = startState.contactIdentity
            let dialogUuid = startState.dialogUuid
            
            // Make sure the contact is indeed a OneToOne contact now. Note that, during startup, all the messages targeted by the
            // ProtocolInstanceWaitingForContactUpgradeToOneToOne entries are replayed.
            // So it is frequent to execute this step although the contact is *not* OneToOne yet. In that case, we simply do not change the protocol state.
            
            let contactStatus = try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext)
            switch contactStatus {
            case .notOneToOne, .toBeDefined:
                return startState
            case .oneToOne:
                break
            }
            
            // If we reach this point, the contact that we invited to be a OneToOne contact has been upgraded to be OneToOne.
            // This typically happens if Bob invited us at the very same time we invited him. In that case, when receiving his invitation,
            // We automatically accept it and do the required actions to re-launch this protocol.
            
            // Remove the dialog showed to Alice
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Finish the protocol
            
            return FinishedState()
        }
    }

    
    // MARK: - ProcessContactUpgradedToOneToOneWhileInInvitationReceivedStateStep
    
    final class ProcessContactUpgradedToOneToOneWhileInInvitationReceivedStateStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: ContactUpgradedToOneToOneMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: ContactUpgradedToOneToOneMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let contactIdentity = startState.contactIdentity
            let dialogUuid = startState.dialogUuid
            
            // Make sure the contact is indeed a OneToOne contact now. Note that, during startup, all the messages targeted by the
            // ProtocolInstanceWaitingForContactUpgradeToOneToOne entries are replayed.
            // So it is frequent to execute this step although the contact is *not* OneToOne yet. In that case, we simply do not change the protocol state.
            
            let contactStatus = try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext)
            
            switch contactStatus {
            case .notOneToOne, .toBeDefined:
                return startState
            case .oneToOne:
                break
            }
            
            // If we reach this point, the contact that we invited to be a OneToOne contact has been upgraded to be OneToOne.
            // This typically happens if Bob invited us at the very same time we invited him. In that case, when receiving his invitation,
            // We automatically accept it and do the required actions to re-launch this protocol.
            
            // Remove the dialog showed to Alice
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Finish the protocol
            
            return FinishedState()
        }
    }

    
    // MARK: - ProcessPropagatedOneToOneInvitationMessageStep
    
    final class ProcessPropagatedOneToOneInvitationMessageStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagateOneToOneInvitationMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: PropagateOneToOneInvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OneToOneContactInvitationProtocol.logCategory)
            
            let contactIdentity = receivedMessage.contactIdentity
            
            // Make sure the contact identity received is indeed part of our contacts (normally, it should be, but hey...)
            
            guard try identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext) else {
                os_log("Since the contact identity received is not a local contact, we do not display a dialog since it could not be aborted.", log: log, type: .error)
                return FinishedState()
            }
            
            // Create an ObvDialog informing Alice that her request has been taken into account. This dialog also allows Alice to abort this
            // Protocol.
            
            let dialogUuid = UUID()
            do {
                let dialogType = ObvChannelDialogToSendType.oneToOneInvitationSent(contact: contactIdentity, ownedIdentity: ownedIdentity)
                let channelType = ObvChannelSendChannelType.UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType)
                let coreMessage = getCoreMessage(for: channelType)
                let concreteProtocolMessage = DialogInvitationSentMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Create an entry in the ProtocolInstanceWaitingForContactUpgradeToOneToOne. This makes it possible to accept immediately in case
            // We receive an invitation from Bob (which typically happens when Bob sends an invitation at the exact same moment as we do or without seeing Alice's invitation).
            
            guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                os_log("Could not retrive this protocol instance", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }

            guard let _ = ProtocolInstanceWaitingForContactUpgradeToOneToOne(ownedCryptoIdentity: ownedIdentity,
                                                                             contactCryptoIdentity: contactIdentity,
                                                                             messageToSendRawId: MessageId.contactUpgradedToOneToOne.rawValue,
                                                                             protocolInstance: thisProtocolInstance,
                                                                             delegateManager: delegateManager)
                else {
                    os_log("Could not create an entry in the ProtocolInstanceWaitingForContactUpgradeToOneToOne database", log: log, type: .fault)
                    return CancelledState()
            }
            
            // Finish this step, we wait from Bob answer.
            
            return InvitationSentState(contactIdentity: contactIdentity, dialogUuid: dialogUuid)
        }
    }

    
    // MARK: - ProcessPropagatedOneToOneResponseMessageStep
    
    final class ProcessPropagatedOneToOneResponseMessageStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: PropagateOneToOneResponseMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: PropagateOneToOneResponseMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let contactIdentity = startState.contactIdentity
            let dialogUuid = startState.dialogUuid
            let invitationAccepted = receivedMessage.invitationAccepted

            // Upgrade/downgrade Alice's OneToOne status
            
            let reasonToLog = "OneToOneContactInvitationProtocol.ProcessPropagatedOneToOneResponseMessageStep"
            try identityDelegate.setOneToOneContactStatus(ownedIdentity: ownedIdentity,
                                                          contactIdentity: contactIdentity,
                                                          newIsOneToOneStatus: invitationAccepted,
                                                          reasonToLog: reasonToLog,
                                                          within: obvContext)
            
            // Remove Bob's dialog
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Finish this protocol. Note that the ProtocolInstanceWaitingForContactUpgradeToOneToOne instance created in the
            // BobProcessesAlicesInvitationStep step will be cascade deleted.

            return FinishedState()

        }
    }

    
    // MARK: - ProcessPropagatedAbortMessageStep
    
    final class ProcessPropagatedAbortMessageStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: PropagateAbortMessage

        init?(startState: InvitationReceivedState, receivedMessage: PropagateAbortMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            _ = startState.contactIdentity
            let dialogUuid = startState.dialogUuid

            // Remove the dialog showed to Alice (telling her that an invitation was sent to Bob, and allowing to abort this protocol, which is exactly what we are doing here)
            
            do {
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Finish the protocol. Note that the ProtocolInstanceWaitingForContactUpgradeToOneToOne instance created in the
            // AliceInvitesBob step will be cascade deleted.
            
            return FinishedState()

        }
    }

    
    // MARK: - AliceProcessesUnexpectedBobResponseStep
    
    final class AliceProcessesUnexpectedBobResponseStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: OneToOneResponseMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: OneToOneResponseMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OneToOneContactInvitationProtocol.logCategory)

            let contactConsidersUsAsOneToOne = receivedMessage.invitationAccepted
            
            // Determine the origin of the message
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessNewMembersStep)", log: log, type: .error)
                return CancelledState()
            }
            
            // If our contact consider us as OneToOne, do nothing. Three cases:
            // - we already consider the contact as OneToOne, everything is fine
            // - we consider the contact as not OneToOne, there is a desync situation
            // - we consider the contact as toBeDefined, there is a desync situation
            // The desync situations are preferable to the situation where a user "looses" a contact for not good reason.
            // If our contact considers us as not OneToOne, we downgrade her
            
            guard !contactConsidersUsAsOneToOne else {
                return FinishedState()
            }
            
            // At this point, our contact considers us as not one2one, we downgrade
            
            let reasonToLog = "OneToOneContactInvitationProtocol.AliceProcessesUnexpectedBobResponseStep"
            try identityDelegate.setOneToOneContactStatus(ownedIdentity: ownedIdentity,
                                                          contactIdentity: remoteIdentity,
                                                          newIsOneToOneStatus: false,
                                                          reasonToLog: reasonToLog,
                                                          within: obvContext)

            let initialMessageToSend = try delegateManager.protocolStarterDelegate.getInitialMessageForDowngradingOneToOneContact(ownedIdentity: ownedIdentity, contactIdentity: remoteIdentity)
            _ = try channelDelegate.postChannelMessage(initialMessageToSend, randomizedWith: prng, within: obvContext)

            return FinishedState()

        }
    }

    
    // MARK: - AliceSendsOneToOneStatusSyncRequestMessagesStep
    
    final class AliceSendsOneToOneStatusSyncRequestMessagesStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialOneToOneStatusSyncRequestMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: InitialOneToOneStatusSyncRequestMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OneToOneContactInvitationProtocol.logCategory)

            let contactsToSync = receivedMessage.contactsToSync
            
            // If there is no contact to sync, we are done.
            
            guard !contactsToSync.isEmpty else {
                return FinishedState()
            }
            
            // For each contact to sync, send a sync request containing Alice's view of the contact OneToOne status
            
            contactsToSync.forEach { contact in
                do {
                    let contactStatus = try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contact, within: obvContext)
                    let contactIsOneToOne: Bool
                    switch contactStatus {
                    case .oneToOne:
                        contactIsOneToOne = true
                    case .notOneToOne:
                        contactIsOneToOne = false
                    case .toBeDefined:
                        // Don't request a sync if we do not have a strong opinion on the one2one status of the contact
                        return
                    }
                    let channelType = ObvChannelSendChannelType.AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contact]), fromOwnedIdentity: ownedIdentity)
                    let coreMessage = getCoreMessage(for: channelType)
                    let concreteProtocolMessage = OneToOneStatusSyncRequestMessage(coreProtocolMessage: coreMessage, aliceConsidersBobAsOneToOne: contactIsOneToOne)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw Self.makeError(message: "Could not generate ProtocolMessageToSend for OneToOneStatusSyncRequestMessage")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not sync OneToOne status with one of the contacts: %{public}@", log: log, type: .error, error.localizedDescription)
                    assertionFailure()
                    // Continue anyway
                }
            }

            return FinishedState()

        }
    }

    
    // MARK: - BobProcessesSyncRequestStep
    
    final class BobProcessesSyncRequestStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: OneToOneStatusSyncRequestMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: OneToOneStatusSyncRequestMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: OneToOneContactInvitationProtocol.logCategory)

            let aliceConsidersBobAsOneToOne = receivedMessage.aliceConsidersBobAsOneToOne
            
            // Determine the origin of the message
            
            guard let contactIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity (ProcessNewMembersStep)", log: log, type: .error)
                return CancelledState()
            }

            // Check if the current OneToOne status of the contact agrees with the status shes has for us.
            // We consider to be Bob here.
            
            let aliceStatusForBob = try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext)
            
            switch (aliceConsidersBobAsOneToOne, aliceStatusForBob) {

            case (true, .oneToOne), (false, .notOneToOne), (true, .toBeDefined), (false, .toBeDefined):
                return FinishedState()
                
            case (false, .oneToOne):
                
                // We downgrade Alice so as to agree with her
                
                let reasonToLog = "OneToOneContactInvitationProtocol.BobProcessesSyncRequestStep"
                try identityDelegate.setOneToOneContactStatus(ownedIdentity: ownedIdentity,
                                                              contactIdentity: contactIdentity,
                                                              newIsOneToOneStatus: false,
                                                              reasonToLog: reasonToLog,
                                                              within: obvContext)
                
                return FinishedState()

            case (true, .notOneToOne):
                
                // Alice considers us as OneToOne, but we do not. We do not upgrade her, unless we did invite her to be OneToOne.
                // This can be detected by looking for an appropriate entry in the
                // ProtocolInstanceWaitingForContactUpgradeToOneToOne database. If an entry is found, we upgrade the contact.
                // This will eventually trigger the message allowing the other protocol to properly finish.
                
                do {
                    let waitingInstances = try ProtocolInstanceWaitingForContactUpgradeToOneToOne.getAll(ownedCryptoIdentity: ownedIdentity, contactCryptoIdentity: contactIdentity, delegateManager: delegateManager, within: obvContext)
                    let appropriateWaitingInstances = waitingInstances
                        .compactMap({ $0.protocolInstance })
                        .filter({ $0.cryptoProtocolId == self.cryptoProtocolId })
                        .filter({ $0.currentStateRawId == StateId.invitationSent.rawValue })
                    guard appropriateWaitingInstances.isEmpty else {
                     
                        // Upgrade Alice's OneToOne status. When the context is saved, a notification will be send that the trust level was increased.
                        // This will be catched by the protocol manager which will replay the message in the ProtocolInstanceWaitingForContactUpgradeToOneToOne db.
                        // This message will execute the ProcessContactUpgradedToOneToOneStep of the other protocol instance, allowing it to finish properly
                        
                        let reasonToLog = "OneToOneContactInvitationProtocol.BobProcessesSyncRequestStep"
                        try identityDelegate.setOneToOneContactStatus(ownedIdentity: ownedIdentity,
                                                                      contactIdentity: contactIdentity,
                                                                      newIsOneToOneStatus: true,
                                                                      reasonToLog: reasonToLog,
                                                                      within: obvContext)

                        // We can finish this protocol instance
                        
                        return FinishedState()

                    }
                }

                // If we reach this point, there is not much we can do and we tell Alice that we consider her as non-OneToOne.
                // We re-create a protocol (since, one Alice's side, the protocol with the current UID is finished).
                // If we did not, things could go wrong on Alice's side in the case she receives multiple message with the same protocol UID:
                // She could process one, and delete all the others. This is why we create a subprotocol here.
                
                let newProtocolInstanceUid = UID.gen(with: prng)
                let coreMessage = CoreProtocolMessage(channelType: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contactIdentity]), fromOwnedIdentity: ownedIdentity),
                                                      cryptoProtocolId: .oneToOneContactInvitation,
                                                      protocolInstanceUid: newProtocolInstanceUid)
                let concreteProtocolMessage = OneToOneStatusSyncRequestMessage(coreProtocolMessage: coreMessage, aliceConsidersBobAsOneToOne: false)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    throw Self.makeError(message: "Could not generate ProtocolMessageToSend for OneToOneStatusSyncRequestMessage")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)

                // Finish the protocol
                
                return FinishedState()
                
            } // End of switch

        }

    }
    
}
