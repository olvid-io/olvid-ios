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
import ObvMetaManager
import ObvTypes
import ObvCrypto
import OlvidUtils

// MARK: - Protocol Steps

extension ContactMutualIntroductionProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId {
        
        // Mediator's side
        case IntroduceContacts = 0
        
        // Contact's sides
        case CheckTrustLevelsAndShowDialog = 1
        case PropagateInviteResponse = 2
        case ProcessPropagatedInviteResponse = 3
        case PropagateNotificationAddTrustAndSendAck = 4
        case ProcessPropagatedNotificationAndAddTrust = 5
        case NotifyMutualTrustEstablished = 6
        case RecheckTrustLevelsAfterTrustLevelIncrease = 7
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            
            switch self {
                
            // Mediator's side
            case .IntroduceContacts:
                let step = IntroduceContactsStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            // Contact's sides
            case .CheckTrustLevelsAndShowDialog:
                let step = CheckTrustLevelsAndShowDialogStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .PropagateInviteResponse:
                let step = PropagateInviteResponseStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessPropagatedInviteResponse:
                let step = ProcessPropagatedInviteResponseStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .PropagateNotificationAddTrustAndSendAck:
                let step = PropagateNotificationAddTrustAndSendAckStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ProcessPropagatedNotificationAndAddTrust:
                let step = ProcessPropagatedNotificationAndAddTrustStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .NotifyMutualTrustEstablished:
                let step = NotifyMutualTrustEstablishedStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .RecheckTrustLevelsAfterTrustLevelIncrease:
                let step = RecheckTrustLevelsAfterTrustLevelIncreaseStep(from: concreteProtocol, and: receivedMessage)
                return step

            }
        }
    }
    
    
    // MARK: - IntroduceContactsStep
    
    final class IntroduceContactsStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ContactMutualIntroductionProtocol.InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)
            os_log("ContactMutualIntroductionProtocol: starting IntroduceContactsStep", log: log, type: .debug)

            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let contactIdentityA = receivedMessage.contactIdentityA
            let contactIdentityCoreDetailsA = receivedMessage.contactIdentityCoreDetailsA
            let contactIdentityB = receivedMessage.contactIdentityB
            let contactIdentityCoreDetailsB = receivedMessage.contactIdentityCoreDetailsB

            // Make sure both contacts are trusted (i.e., are part of the ContactIdentity database of the owned identity)
            
            for contactIdentity in [contactIdentityA, contactIdentityB] {
                guard (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                    os_log("One of the contact identities is not yet trusted", log: log, type: .debug)
                    return CancelledState()
                }
                guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) else {
                    os_log("One of the contact identities is not active", log: log, type: .debug)
                    return CancelledState()
                }
            }

            // Post an invitation message to contact A

            do {
                let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contactIdentityA]), fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = MediatorInvitationMessage(coreProtocolMessage: coreMessage,
                                                                        contactIdentity: contactIdentityB,
                                                                        contactIdentityCoreDetails: contactIdentityCoreDetailsB)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Post an invitation message to contact B
            
            do {
                let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithContactIdentities(contactIdentities: Set([contactIdentityB]), fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = MediatorInvitationMessage(coreProtocolMessage: coreMessage,
                                                                        contactIdentity: contactIdentityA,
                                                                        contactIdentityCoreDetails: contactIdentityCoreDetailsA)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
            os_log("ContactMutualIntroductionProtocol: ending IntroduceContactsStep", log: log, type: .debug)
            return ContactsIntroducedState()

        }
    }
    
    
    // MARK: - ShowInvitationDialogStep
    
    final class CheckTrustLevelsAndShowDialogStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: MediatorInvitationMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ContactMutualIntroductionProtocol.MediatorInvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)
            os_log("ContactMutualIntroductionProtocol: starting ShowInvitationDialogStep", log: log, type: .debug)
            
            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityCoreDetails = receivedMessage.contactIdentityCoreDetails
            let dialogUuid = UUID()

            guard let mediatorIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determiner the mediator identity", log: log, type: .error)
                return CancelledState()
            }
            
            // If the introduced contact is already part of our contacts, we show no dialog to the user. We automatically accept the invitation and notify our contact using a NotifyContactOfAcceptedInvitation message.
            
            guard (try? !identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                
                do {
                    let notifyContactOfAcceptedInvitationMessageInitializer = {                        (coreProtocolMessage: CoreProtocolMessage, contactDeviceUids: [UID], signature: Data) -> ContactMutualIntroductionProtocol.NotifyContactOfAcceptedInvitationMessage in
                        return NotifyContactOfAcceptedInvitationMessage(coreProtocolMessage: coreProtocolMessage, contactDeviceUids: contactDeviceUids, signature: signature)
                    }
                    try signAndSendNotificationOfAcceptedInvitationMessage(ownedIdentity: ownedIdentity,
                                                                           contactIdentity: contactIdentity,
                                                                           mediatorIdentity: mediatorIdentity,
                                                                           prng: prng,
                                                                           notifyContactOfAcceptedInvitationMessageInitializer: notifyContactOfAcceptedInvitationMessageInitializer,
                                                                           log: log,
                                                                           delegateManager: delegateManager)
                } catch {
                    os_log("Could not sign and send notification of accepted invitation", log: log, type: .fault)
                    return CancelledState()
                }
                
                return InvitationAcceptedState(contactIdentity: contactIdentity,
                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                               mediatorIdentity: mediatorIdentity,
                                               dialogUuid: dialogUuid,
                                               acceptType: AcceptType.alreadyTrusted)
            }
            
            // If we reach this point, the introduced contact is not in our contacts already. We evaluate the TrustLevel we have for the mediator. If it is high enough, we automatically accept the invitation and notify our contact using a NotifyContactOfAcceptedInvitation message. Otherwise, we show a "simple" accept dialog to present to the user if the Trust Level we have in the mediator is high enough. Otherwise, we show a dialog inviting the user to increase the Trust Level she has in the mediator or in the introduced contact.
            
            let mediatorTrustLevel: TrustLevel
            do {
                mediatorTrustLevel = try identityDelegate.getTrustLevel(forContactIdentity: mediatorIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not get the mediator's Trust Level", log: log, type: .fault)
                return CancelledState()
            }
            
            if mediatorTrustLevel >= ObvConstants.autoAcceptTrustLevelTreshold {
                
                do {
                    let notifyContactOfAcceptedInvitationMessageInitializer = {                        (coreProtocolMessage: CoreProtocolMessage, contactDeviceUids: [UID], signature: Data) -> ContactMutualIntroductionProtocol.NotifyContactOfAcceptedInvitationMessage in
                        return NotifyContactOfAcceptedInvitationMessage(coreProtocolMessage: coreProtocolMessage, contactDeviceUids: contactDeviceUids, signature: signature)
                    }
                    try signAndSendNotificationOfAcceptedInvitationMessage(ownedIdentity: ownedIdentity,
                                                                           contactIdentity: contactIdentity,
                                                                           mediatorIdentity: mediatorIdentity,
                                                                           prng: prng,
                                                                           notifyContactOfAcceptedInvitationMessageInitializer: notifyContactOfAcceptedInvitationMessageInitializer,
                                                                           log: log,
                                                                           delegateManager: delegateManager)
                } catch {
                    os_log("Could not sign and send notification of accepted invitation", log: log, type: .fault)
                    return CancelledState()
                }
                
                return InvitationAcceptedState(contactIdentity: contactIdentity,
                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                               mediatorIdentity: mediatorIdentity,
                                               dialogUuid: dialogUuid,
                                               acceptType: AcceptType.automatic)
                
            } else if mediatorTrustLevel >= ObvConstants.userConfirmationTrustLevelTreshold {
                
                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the mediator increases
                
                guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not retrive this protocol instance", log: log, type: .fault)
                    return CancelledState()
                }
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: mediatorIdentity,
                                                                           targetTrustLevel: ObvConstants.autoAcceptTrustLevelTreshold,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                    os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }
                
                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the contact (remote identity) increases
                
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: contactIdentity,
                                                                           targetTrustLevel: TrustLevel.zero,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }

                // Display a dialog allowing to accept/re1ject the mediator's invite
                
                do {
                    let dialogType = ObvChannelDialogToSendType.acceptMediatorInvite(contact: CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails),
                                                                                     mediatorIdentity: mediatorIdentity)
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                    let concreteProtocolMessage = AcceptMediatorInviteDialogMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                os_log("ContactMutualIntroductionProtocol: ending ShowInvitationDialogStep", log: log, type: .debug)
                return InvitationReceivedState(contactIdentity: contactIdentity,
                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                               mediatorIdentity: mediatorIdentity,
                                               dialogUuid: dialogUuid)
                
            } else {
                
                guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not retrive this protocol instance", log: log, type: .fault)
                    return CancelledState()
                }
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: mediatorIdentity,
                                                                           targetTrustLevel: ObvConstants.userConfirmationTrustLevelTreshold,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }
                
                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the contact (remote identity) increases
                
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: contactIdentity,
                                                                           targetTrustLevel: TrustLevel.zero,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }

                // Display a dialog notifying the user that she must increase the Trust Level she has in the mediator (or in the contact)
                
                let dialogUuid = UUID()
                
                do {
                    let dialogType = ObvChannelDialogToSendType.increaseMediatorTrustLevelRequired(contact: CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails),
                                                                                                   mediatorIdentity: mediatorIdentity)
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }

                // Return the new state
                
                os_log("ContactMutualIntroductionProtocol: ending ShowInvitationDialogStep", log: log, type: .debug)
                return InvitationReceivedState(contactIdentity: contactIdentity,
                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                               mediatorIdentity: mediatorIdentity,
                                               dialogUuid: dialogUuid)
                
            }
            
        }
    }
    
    
    // MARK: - PropagateInviteResponseStep
    
    final class PropagateInviteResponseStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: AcceptMediatorInviteDialogMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: ContactMutualIntroductionProtocol.AcceptMediatorInviteDialogMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)
            os_log("ContactMutualIntroductionProtocol: starting PropagateInviteResponseStep", log: log, type: .debug)
            
            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let mediatorIdentity = startState.mediatorIdentity

            let invitationAccepted = receivedMessage.invitationAccepted

            // Check the dialog UUID

            let dialogUuid: UUID
            do {
                let dialogUuidFromState = startState.dialogUuid
                let dialogUuidFromMessage = receivedMessage.dialogUuid
                guard dialogUuidFromState == dialogUuidFromMessage else { throw NSError() }
                dialogUuid = dialogUuidFromState
            }
                        
            // Propagate the accept/reject to other owned devices
            
            guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                return CancelledState()
            }

            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagateConfirmationMessage(coreProtocolMessage: coreMessage,
                                                                               invitationAccepted: invitationAccepted,
                                                                               contactIdentity: contactIdentity,
                                                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                                                               mediatorIdentity: mediatorIdentity)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not propagate accept/reject invitation to other devices.", log: log, type: .fault)
                }
            } else {
                os_log("This device is the only device of the owned identity, so we don't need to propagate the accept/reject invitation", log: log, type: .debug)
            }

            // If we rejected the invitation we delete the dialog and terminate this protocol
            
            guard invitationAccepted else {
                
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)

                return InvitationRejectedState()
            }
            
            // If we reach this point, the invitation was accepted. We show an appropriate dialog to the user and notify the contact with an appropriate signature
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.mediatorInviteAccepted(contact: contact,
                                                                                   mediatorIdentity: mediatorIdentity)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            do {
                let notifyContactOfAcceptedInvitationMessageInitializer = {                    (coreProtocolMessage: CoreProtocolMessage, contactDeviceUids: [UID], signature: Data) -> ContactMutualIntroductionProtocol.NotifyContactOfAcceptedInvitationMessage in
                    return NotifyContactOfAcceptedInvitationMessage(coreProtocolMessage: coreProtocolMessage, contactDeviceUids: contactDeviceUids, signature: signature)
                }
                try signAndSendNotificationOfAcceptedInvitationMessage(ownedIdentity: ownedIdentity,
                                                                       contactIdentity: contactIdentity,
                                                                       mediatorIdentity: mediatorIdentity,
                                                                       prng: prng,
                                                                       notifyContactOfAcceptedInvitationMessageInitializer: notifyContactOfAcceptedInvitationMessageInitializer,
                                                                       log: log,
                                                                       delegateManager: delegateManager)
            } catch {
                os_log("Could not sign and send notification of accepted invitation", log: log, type: .fault)
                return CancelledState()
            }
            
            // Return the new state
            
            os_log("ContactMutualIntroductionProtocol: ending PropagateInviteResponseStep", log: log, type: .debug)
            return InvitationAcceptedState(contactIdentity: contactIdentity,
                                           contactIdentityCoreDetails: contactIdentityCoreDetails,
                                           mediatorIdentity: mediatorIdentity,
                                           dialogUuid: dialogUuid,
                                           acceptType: AcceptType.manual)
            
        }
    }
    
    
    // MARK: - ProcessPropagatedInviteResponseStep
    
    final class ProcessPropagatedInviteResponseStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: PropagateConfirmationMessage
        
        init?(startState: InvitationReceivedState, receivedMessage: ContactMutualIntroductionProtocol.PropagateConfirmationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)
            os_log("ContactMutualIntroductionProtocol: starting ProcessPropagatedInviteResponseStep", log: log, type: .debug)
            
            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            // We do not use startState.contactIdentity
            // We do not use startState.contactIdentityCoreDetails
            // We do not use startState.mediatorIdentity
            let dialogUuid = startState.dialogUuid

            let invitationAccepted = receivedMessage.invitationAccepted
            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityCoreDetails = receivedMessage.contactIdentityCoreDetails
            let mediatorIdentity = receivedMessage.mediatorIdentity

            // If we rejected the invitation we delete the dialog and terminate this protocol
            
            guard invitationAccepted else {
                
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                
                return InvitationRejectedState()
            }

            // If we reach this point, the invitation was accepted. We show an appropriate dialog to the user.
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.mediatorInviteAccepted(contact: contact,
                                                                                   mediatorIdentity: mediatorIdentity)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
            os_log("ContactMutualIntroductionProtocol: ending ProcessPropagatedInviteResponseStep", log: log, type: .debug)
            return InvitationAcceptedState(contactIdentity: contactIdentity,
                                           contactIdentityCoreDetails: contactIdentityCoreDetails,
                                           mediatorIdentity: mediatorIdentity,
                                           dialogUuid: dialogUuid,
                                           acceptType: AcceptType.manual)

        }
    }
    
    
    // MARK: - PropagateNotificationAddTrustAndSendAckStep
    
    final class PropagateNotificationAddTrustAndSendAckStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationAcceptedState
        let receivedMessage: NotifyContactOfAcceptedInvitationMessage
        
        init?(startState: InvitationAcceptedState, receivedMessage: ContactMutualIntroductionProtocol.NotifyContactOfAcceptedInvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)
            os_log("ContactMutualIntroductionProtocol: starting PropagateNotificationAddTrustAndSendAckStep", log: log, type: .debug)
            
            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }
            
            guard let solveChallengeDelegate = delegateManager.solveChallengeDelegate else {
                os_log("The solve challenge delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let mediatorIdentity = startState.mediatorIdentity
            let dialogUuid = startState.dialogUuid
            let acceptType = startState.acceptType

            let contactDeviceUids = receivedMessage.contactDeviceUids
            let signature = receivedMessage.signature
            
            // We check the signature

            do {
                let identities = [mediatorIdentity, ownedIdentity, contactIdentity]
                let challenge = identities.reduce(Data()) { $0 + $1.getIdentity() }
                let prefix = ContactMutualIntroductionProtocol.signatureChallengePrefix
                guard solveChallengeDelegate.checkResponse(signature, toChallenge: challenge, prefixedWith: prefix, from: contactIdentity) else {
                    os_log("The signature verification failed", log: log, type: .error)
                    return CancelledState()
                }
            }
            
            // We create the contact in the (trusted) contact database (or only add a new TrustOrigin if the contact already exists) and add all the device uids we just received
            
            do {
                
                let trustOrigin = TrustOrigin.introduction(timestamp: Date(), mediator: mediatorIdentity)
                
                if (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                    try identityDelegate.addTrustOrigin(trustOrigin, toContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                } else {
                    try identityDelegate.addContactIdentity(contactIdentity, with: contactIdentityCoreDetails, andTrustOrigin: trustOrigin, forOwnedIdentity: ownedIdentity, within: obvContext)
                }
                
                try contactDeviceUids.forEach { (contactDeviceUid) in
                    if try !identityDelegate.isDevice(withUid: contactDeviceUid, aDeviceOfContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext) {
                        try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
                    }
                }
            } catch {
                os_log("Could not add the contact identity to the contact identities database, or could not add a device uid to this contact", log: log, type: .fault)
                return CancelledState()
            }
            
            // We propagate the notification to our other owned devices
            
            guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                return CancelledState()
            }
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagateContactNotificationOfAcceptedInvitationMessage(coreProtocolMessage: coreMessage,
                                                                                  contactDeviceUids: contactDeviceUids)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not propagate notification to other devices.", log: log, type: .fault)
                }
            } else {
                os_log("This device is the only device of the owned identity, so we don't need to propagate the notification", log: log, type: .debug)
            }

            // Send Ack to contact
            
            do {
                let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = AckMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            os_log("ContactMutualIntroductionProtocol: ending PropagateNotificationAddTrustAndSendAckStep", log: log, type: .debug)
            return WaitingForAckState(contactIdentity: contactIdentity,
                                      contactIdentityCoreDetails: contactIdentityCoreDetails,
                                      mediatorIdentity: mediatorIdentity,
                                      dialogUuid: dialogUuid,
                                      acceptType: acceptType)
            
        }
    }
    
    
    // MARK: - ProcessPropagatedNotificationAndAddTrustStep
    
    final class ProcessPropagatedNotificationAndAddTrustStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationAcceptedState
        let receivedMessage: PropagateContactNotificationOfAcceptedInvitationMessage
        
        init?(startState: InvitationAcceptedState, receivedMessage: ContactMutualIntroductionProtocol.PropagateContactNotificationOfAcceptedInvitationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)
            os_log("ContactMutualIntroductionProtocol: starting ProcessPropagatedNotificationAndAddTrustStep", log: log, type: .debug)
            
            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let mediatorIdentity = startState.mediatorIdentity
            let dialogUuid = startState.dialogUuid
            let acceptType = startState.acceptType
            
            let contactDeviceUids = receivedMessage.contactDeviceUids

            // We create the contact in the (trusted) contact database (only if it does not already exists) and add all the device uids we just received
            
            do {
                
                let trustOrigin = TrustOrigin.introduction(timestamp: Date(), mediator: mediatorIdentity)
                
                if (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                    try identityDelegate.addTrustOrigin(trustOrigin, toContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                } else {
                    try identityDelegate.addContactIdentity(contactIdentity, with: contactIdentityCoreDetails, andTrustOrigin: trustOrigin, forOwnedIdentity: ownedIdentity, within: obvContext)
                }
                
                try contactDeviceUids.forEach { (contactDeviceUid) in
                    if try !identityDelegate.isDevice(withUid: contactDeviceUid, aDeviceOfContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext) {
                        try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
                    }
                }
            } catch {
                os_log("Could not add the contact identity to the contact identities database, or could not add a device uid to this contact", log: log, type: .fault)
                return CancelledState()
            }

            // Return the new state
            
            os_log("ContactMutualIntroductionProtocol: ending ProcessPropagatedNotificationAndAddTrustStep", log: log, type: .debug)
            return WaitingForAckState(contactIdentity: contactIdentity,
                                      contactIdentityCoreDetails: contactIdentityCoreDetails,
                                      mediatorIdentity: mediatorIdentity,
                                      dialogUuid: dialogUuid,
                                      acceptType: acceptType)

        }
    }
    
    
    // MARK: - NotifyMutualTrustEstablishedStep
    
    final class NotifyMutualTrustEstablishedStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForAckState
        let receivedMessage: AckMessage
        
        init?(startState: WaitingForAckState, receivedMessage: ContactMutualIntroductionProtocol.AckMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)
            os_log("ContactMutualIntroductionProtocol: starting NotifyMutualTrustEstablishedStep", log: log, type: .debug)
            
            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channel delegate is not set", log: log, type: .fault)
                return CancelledState()
            }

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let dialogUuid = startState.dialogUuid
            let acceptType = startState.acceptType
            let mediatorIdentity = startState.mediatorIdentity

            // Display a mutual trust established dialog
            
            switch acceptType {
            case AcceptType.alreadyTrusted:
                // We do not notify the user in this case
                break
                
            case AcceptType.automatic:
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.autoconfirmedContactIntroduction(contact: contact, mediatorIdentity: mediatorIdentity)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                
            case AcceptType.manual:
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.mutualTrustConfirmed(contact: contact)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                
            default:
                // Cannot happen
                break
            }
            
            // Return the new state
            
            os_log("ContactMutualIntroductionProtocol: ending NotifyMutualTrustEstablishedStep", log: log, type: .debug)
            return MutualTrustEstablishedState()
            
        }
    }
    
    
    // MARK: - RecheckTrustLevelsAfterTrustLevelIncreaseStep
    
    final class RecheckTrustLevelsAfterTrustLevelIncreaseStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: InvitationReceivedState
        let receivedMessage: TrustLevelIncreasedMessage

        init?(startState: InvitationReceivedState, receivedMessage: ContactMutualIntroductionProtocol.TrustLevelIncreasedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)
            os_log("ContactMutualIntroductionProtocol: starting RecheckTrustLevelsAfterTrustLevelIncreaseStep", log: log, type: .debug)
            defer { os_log("ContactMutualIntroductionProtocol: ending RecheckTrustLevelsAfterTrustLevelIncreaseStep", log: log, type: .debug) }

            guard let identityDelegate = delegateManager.identityDelegate else {
                os_log("The identity delegate is not set", log: log, type: .fault)
                throw NSError()
            }
            
            guard let channelDelegate = delegateManager.channelDelegate else {
                os_log("The channelDelegate is not set", log: log, type: .fault)
                throw NSError()
            }

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let mediatorIdentity = startState.mediatorIdentity
            let dialogUuid = startState.dialogUuid

            let identityWithIncreasedTrustLevel = receivedMessage.contactIdentity
            
            // Check that the identity having an increased trust level is either the mediator or the contact
            
            guard [mediatorIdentity, contactIdentity].contains(identityWithIncreasedTrustLevel) else {
                os_log("The identity with an increased trust level is neither the mediator nor the remote identity", log: log, type: .error)
                return startState
            }
            
            // If the introduced contact is now part of our contacts, we remove any previous dialog showed to the user. We automatically accept the invitation and notify our contact using a NotifyContactOfAcceptedInvitation message.
            
            guard (try? !identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                
                do {
                    let dialogType = ObvChannelDialogToSendType.delete
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                do {
                    let notifyContactOfAcceptedInvitationMessageInitializer = {                        (coreProtocolMessage: CoreProtocolMessage, contactDeviceUids: [UID], signature: Data) -> ContactMutualIntroductionProtocol.NotifyContactOfAcceptedInvitationMessage in
                        return NotifyContactOfAcceptedInvitationMessage(coreProtocolMessage: coreProtocolMessage, contactDeviceUids: contactDeviceUids, signature: signature)
                    }
                    try signAndSendNotificationOfAcceptedInvitationMessage(ownedIdentity: ownedIdentity,
                                                                           contactIdentity: contactIdentity,
                                                                           mediatorIdentity: mediatorIdentity,
                                                                           prng: prng,
                                                                           notifyContactOfAcceptedInvitationMessageInitializer: notifyContactOfAcceptedInvitationMessageInitializer,
                                                                           log: log,
                                                                           delegateManager: delegateManager)
                } catch {
                    os_log("Could not sign and send notification of accepted invitation", log: log, type: .fault)
                    return CancelledState()
                }
                
                return InvitationAcceptedState(contactIdentity: contactIdentity,
                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                               mediatorIdentity: mediatorIdentity,
                                               dialogUuid: dialogUuid,
                                               acceptType: AcceptType.alreadyTrusted)
            }
            
            // If we reach this point, the introduced contact is not in our contacts already. We evaluate the (new) TrustLevel we have for the mediator. If it is high enough, we remove any previous dialog, we automatically accept the invitation, and notify our contact using a NotifyContactOfAcceptedInvitation message. Otherwise, we show a "simple" accept dialog to present to the user if the Trust Level we have in the mediator is high enough. Otherwise, we show a dialog inviting the user to increase the Trust Level she has in the mediator or in the introduced contact.
            
            let mediatorTrustLevel: TrustLevel
            do {
                mediatorTrustLevel = try identityDelegate.getTrustLevel(forContactIdentity: mediatorIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not get the mediator's Trust Level", log: log, type: .fault)
                return CancelledState()
            }
            
            if mediatorTrustLevel >= ObvConstants.autoAcceptTrustLevelTreshold {

                do {
                    let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                    let dialogType = ObvChannelDialogToSendType.mediatorInviteAccepted(contact: contact,
                                                                                       mediatorIdentity: mediatorIdentity)
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }

                do {
                    let notifyContactOfAcceptedInvitationMessageInitializer = {                        (coreProtocolMessage: CoreProtocolMessage, contactDeviceUids: [UID], signature: Data) -> ContactMutualIntroductionProtocol.NotifyContactOfAcceptedInvitationMessage in
                        return NotifyContactOfAcceptedInvitationMessage(coreProtocolMessage: coreProtocolMessage, contactDeviceUids: contactDeviceUids, signature: signature)
                    }
                    try signAndSendNotificationOfAcceptedInvitationMessage(ownedIdentity: ownedIdentity,
                                                                           contactIdentity: contactIdentity,
                                                                           mediatorIdentity: mediatorIdentity,
                                                                           prng: prng,
                                                                           notifyContactOfAcceptedInvitationMessageInitializer: notifyContactOfAcceptedInvitationMessageInitializer,
                                                                           log: log,
                                                                           delegateManager: delegateManager)
                } catch {
                    os_log("Could not sign and send notification of accepted invitation", log: log, type: .fault)
                    return CancelledState()
                }
                
                return InvitationAcceptedState(contactIdentity: contactIdentity,
                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                               mediatorIdentity: mediatorIdentity,
                                               dialogUuid: dialogUuid,
                                               acceptType: AcceptType.automatic)
                
            } else if mediatorTrustLevel >= ObvConstants.userConfirmationTrustLevelTreshold {
                
                guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not retrive this protocol instance", log: log, type: .fault)
                    return CancelledState()
                }

                // Remove any previous ProtocolInstanceWaitingForTrustLevelIncrease entry concerning the mediator for this protocol instance
                
                do {
                    try ProtocolInstanceWaitingForTrustLevelIncrease.deleteRelatedToProtocolInstance(thisProtocolInstance, contactCryptoIdentity: mediatorIdentity, delegateManager: delegateManager)
                } catch {
                    os_log("Could not delete previous ProtocolInstanceWaitingForTrustLevelIncrease entries", log: log, type: .fault)
                    return CancelledState()
                }
                
                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the mediator increases
                
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: mediatorIdentity,
                                                                           targetTrustLevel: ObvConstants.autoAcceptTrustLevelTreshold,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }
                
                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the contact (remote identity) increases
                
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: contactIdentity,
                                                                           targetTrustLevel: TrustLevel.zero,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }
                
                
                // Display a dialog allowing to accept/re1ject the mediator's invite
                
                do {
                    let dialogType = ObvChannelDialogToSendType.acceptMediatorInvite(contact: CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails),
                                                                                     mediatorIdentity: mediatorIdentity)
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                    let concreteProtocolMessage = AcceptMediatorInviteDialogMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                return startState
                
            } else {
                
                // Display a dialog notifying the user that she must increase the Trust Level she has in the mediator (or in the contact)
                // Should never occur here
                
                guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not retrive this protocol instance", log: log, type: .fault)
                    return CancelledState()
                }

                // Remove any previous ProtocolInstanceWaitingForTrustLevelIncrease entry for this protocol instance
                
                do {
                    try ProtocolInstanceWaitingForTrustLevelIncrease.deleteRelatedToProtocolInstance(thisProtocolInstance, contactCryptoIdentity: mediatorIdentity, delegateManager: delegateManager)
                } catch {
                    os_log("Could not delete previous ProtocolInstanceWaitingForTrustLevelIncrease entries", log: log, type: .fault)
                    return CancelledState()
                }

                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the mediator increases

                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: mediatorIdentity,
                                                                           targetTrustLevel: ObvConstants.userConfirmationTrustLevelTreshold,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }
                
                // Insert an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database, so as to be notified if the Trust Level we have in the contact (remote identity) increases
                
                guard let _ = ProtocolInstanceWaitingForTrustLevelIncrease(ownedCryptoIdentity: ownedIdentity,
                                                                           contactCryptoIdentity: contactIdentity,
                                                                           targetTrustLevel: TrustLevel.zero,
                                                                           messageToSendRawId: MessageId.TrustLevelIncreased.rawValue,
                                                                           protocolInstance: thisProtocolInstance,
                                                                           delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForTrustLevelIncrease database", log: log, type: .fault)
                        return CancelledState()
                }
                
                // Display a dialog notifying the user that she must increase the Trust Level she has in the mediator (or in the contact)
                
                do {
                    let dialogType = ObvChannelDialogToSendType.increaseMediatorTrustLevelRequired(contact: CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails),
                                                                                                   mediatorIdentity: mediatorIdentity)
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                return startState

            }

        }
        
    }
}


// MARK: - Helpers for the steps

extension ProtocolStep {
    
    fileprivate func signAndSendNotificationOfAcceptedInvitationMessage(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, mediatorIdentity: ObvCryptoIdentity, prng: PRNGService, notifyContactOfAcceptedInvitationMessageInitializer: (CoreProtocolMessage, [UID], Data) -> ContactMutualIntroductionProtocol.NotifyContactOfAcceptedInvitationMessage, log: OSLog, delegateManager: ObvProtocolDelegateManager) throws {
        
        guard let solveChallengeDelegate = delegateManager.solveChallengeDelegate else {
            os_log("The solveChallengeDelegate is not set", log: log, type: .fault)
            throw NSError()
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw NSError()
        }
        
        guard let channelDelegate = delegateManager.channelDelegate else {
            os_log("The channelDelegate is not set", log: log, type: .fault)
            throw NSError()
        }

        let signature: Data
        do {
            let identities = [mediatorIdentity, contactIdentity, ownedIdentity]
            let challenge = identities.reduce(Data()) { $0 + $1.getIdentity() }
            let prefix = ContactMutualIntroductionProtocol.signatureChallengePrefix
            guard let sig = try? solveChallengeDelegate.solveChallenge(challenge, prefixedWith: prefix, for: ownedIdentity, using: prng, within: obvContext) else {
                os_log("Could not compute signature", log: log, type: .fault)
                throw NSError()
            }
            signature = sig
        }
        
        do {
            let ownedDeviceUids = try identityDelegate.getDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
            let coreMessage = getCoreMessage(for: .AsymmetricChannelBroadcast(to: contactIdentity, fromOwnedIdentity: ownedIdentity))
            let concreteProtocolMessage = notifyContactOfAcceptedInvitationMessageInitializer(coreMessage, Array(ownedDeviceUids), signature)
            guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
            _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
        }
        
        
    }
    
}
