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
import ObvMetaManager
import ObvTypes
import ObvCrypto
import OlvidUtils

// MARK: - Protocol Steps

extension ContactMutualIntroductionProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        // Mediator's side
        case introduceContacts = 0
        
        // Contact's sides
        case checkTrustLevelsAndShowDialog = 1
        case propagateInviteResponse = 2
        case processPropagatedInviteResponse = 3
        case propagateNotificationAddTrustAndSendAck = 4
        case processPropagatedNotificationAndAddTrust = 5
        case notifyMutualTrustEstablished = 6
        case recheckTrustLevelsAfterTrustLevelIncrease = 7
        case processPropagatedInitialMessage = 8
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            
            switch self {
                
            // Mediator's side
            case .introduceContacts:
                let step = IntroduceContactsStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processPropagatedInitialMessage:
                let step = ProcessPropagatedInitialMessageStep(from: concreteProtocol, and: receivedMessage)
                return step

            // Contact's sides
            case .checkTrustLevelsAndShowDialog:
                let step = CheckTrustLevelsAndShowDialogStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .propagateInviteResponse:
                let step = PropagateInviteResponseStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processPropagatedInviteResponse:
                let step = ProcessPropagatedInviteResponseStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .propagateNotificationAddTrustAndSendAck:
                let step = PropagateNotificationAddTrustAndSendAckStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .processPropagatedNotificationAndAddTrust:
                let step = ProcessPropagatedNotificationAndAddTrustStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .notifyMutualTrustEstablished:
                let step = NotifyMutualTrustEstablishedStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .recheckTrustLevelsAfterTrustLevelIncrease:
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)

            let contactIdentityA = receivedMessage.contactIdentityA
            let contactIdentityB = receivedMessage.contactIdentityB

            // Make sure both contacts are trusted (i.e., are part of the ContactIdentity database of the owned identity), active and OneToOne.
            
            for contactIdentity in [contactIdentityA, contactIdentityB] {
                guard (try identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                    os_log("One of the contact identities is not yet trusted", log: log, type: .debug)
                    return CancelledState()
                }
                guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) else {
                    os_log("One of the contact identities is not active", log: log, type: .debug)
                    return CancelledState()
                }
                guard try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) == .oneToOne else {
                    os_log("One of the contact identities is not a OneToOne contact", log: log, type: .debug)
                    return CancelledState()
                }
            }
            
            // Recover the current published core details of contact A
            
            let contactIdentityCoreDetailsA: ObvIdentityCoreDetails
            do {
                let publishedDetails = try identityDelegate.getPublishedIdentityDetailsOfContactIdentity(contactIdentityA, ofOwnedIdentity: ownedIdentity, within: obvContext)
                let trustedDetails = try identityDelegate.getTrustedIdentityDetailsOfContactIdentity(contactIdentityA, ofOwnedIdentity: ownedIdentity, within: obvContext)
                contactIdentityCoreDetailsA = publishedDetails?.contactIdentityDetailsElements.coreDetails ?? trustedDetails.contactIdentityDetailsElements.coreDetails
            }

            // Recover the current published core details of contact b
            
            let contactIdentityCoreDetailsB: ObvIdentityCoreDetails
            do {
                let publishedDetails = try identityDelegate.getPublishedIdentityDetailsOfContactIdentity(contactIdentityB, ofOwnedIdentity: ownedIdentity, within: obvContext)
                let trustedDetails = try identityDelegate.getTrustedIdentityDetailsOfContactIdentity(contactIdentityB, ofOwnedIdentity: ownedIdentity, within: obvContext)
                contactIdentityCoreDetailsB = publishedDetails?.contactIdentityDetailsElements.coreDetails ?? trustedDetails.contactIdentityDetailsElements.coreDetails
            }

            // Post an invitation message to contact A

            do {
                let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: Set([contactIdentityA]), fromOwnedIdentity: ownedIdentity, withUserContent: true))
                let concreteProtocolMessage = MediatorInvitationMessage(coreProtocolMessage: coreMessage,
                                                                        contactIdentity: contactIdentityB,
                                                                        contactIdentityCoreDetails: contactIdentityCoreDetailsB)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Post an invitation message to contact B
            
            do {
                let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithContacts(contactIdentities: Set([contactIdentityB]), fromOwnedIdentity: ownedIdentity, withUserContent: true))
                let concreteProtocolMessage = MediatorInvitationMessage(coreProtocolMessage: coreMessage,
                                                                        contactIdentity: contactIdentityA,
                                                                        contactIdentityCoreDetails: contactIdentityCoreDetailsA)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // If we have other devices, propagate the invite so the invitation sent messages can be inserted in the relevant discussion
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count

            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagatedInitialMessage(
                        coreProtocolMessage: coreMessage,
                        contactIdentityA: contactIdentityA,
                        contactIdentityB: contactIdentityB)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    assertionFailure()
                    os_log("Could not propagate accept/reject invitation to other devices.", log: log, type: .fault)
                }
            }
            
            // Send a notification to insert invitation sent messages in relevant discussions

            do {
                let notificationDelegate = self.notificationDelegate
                let ownedCryptoId = self.ownedIdentity
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return}
                    ObvProtocolNotification.contactIntroductionInvitationSent(
                        ownedIdentity: ownedCryptoId,
                        contactIdentityA: contactIdentityA,
                        contactIdentityB: contactIdentityB)
                    .postOnBackgroundQueue(within: notificationDelegate)
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }

            // Return the new state
            
            return ContactsIntroducedState()

        }
    }
    
    
    // MARK: - ProcessPropagatedInitialMessageStep
    
    final class ProcessPropagatedInitialMessageStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PropagatedInitialMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: PropagatedInitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let contactIdentityA = receivedMessage.contactIdentityA
            let contactIdentityB = receivedMessage.contactIdentityB

            // Send a notification to insert invitation sent messages in relevant discussions

            do {
                let notificationDelegate = self.notificationDelegate
                let ownedCryptoId = self.ownedIdentity
                try obvContext.addContextDidSaveCompletionHandler { error in
                    guard error == nil else { return}
                    ObvProtocolNotification.contactIntroductionInvitationSent(
                        ownedIdentity: ownedCryptoId,
                        contactIdentityA: contactIdentityA,
                        contactIdentityB: contactIdentityB)
                    .postOnBackgroundQueue(within: notificationDelegate)
                }
            } catch {
                assertionFailure(error.localizedDescription)
            }

            // Return the new state
            
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
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)
            
            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityCoreDetails = receivedMessage.contactIdentityCoreDetails
            let dialogUuid = UUID()

            guard let mediatorIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determiner the mediator identity", log: log, type: .error)
                return CancelledState()
            }
            
            // Check that the mediator is a OneToOne contact. If not, we discard the invite.
            
            guard try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: mediatorIdentity, within: obvContext) == .oneToOne else {
                os_log("We received mutual introduction invite from a mediator that is not a OneToOne contact. We discard the message.", log: log, type: .error)
                return CancelledState()
            }
            
            // Check whether the introduced contact is already a One2One contact.
            
            let contactStatus = try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext)
            
            if contactStatus == .oneToOne {
                
                // If the introduced contact is already part of our OneToOne contacts (thust trusted), we show no dialog to the user.
                // We automatically accept the invitation and notify our contact using a NotifyContactOfAcceptedInvitation message.

                do {
                    let notifyContactOfAcceptedInvitationMessageInitializer = { (coreProtocolMessage: CoreProtocolMessage, contactDeviceUids: [UID], signature: Data) -> ContactMutualIntroductionProtocol.NotifyContactOfAcceptedInvitationMessage in
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

            } else {
                
                // If we reach this point, the introduced contact is not trusted yet (i.e., not OneToOne or not a contact at all).
                // Display a dialog allowing to accept/reject the mediator's invite.

                do {
                    let dialogType = ObvChannelDialogToSendType.acceptMediatorInvite(contact: CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails),
                                                                                     mediatorIdentity: mediatorIdentity)
                    let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                    let concreteProtocolMessage = AcceptMediatorInviteDialogMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // If, in the future, the introduced contact becomes a OneToOne contact, we want end this protocol.
                // For this reason, we create a ProtocolInstanceWaitingForContactUpgradeToOneToOne entry now.
                
                do {
                    
                    guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                        os_log("Could not retrive this protocol instance", log: log, type: .fault)
                        assertionFailure()
                        return CancelledState()
                    }

                    _ = ProtocolInstanceWaitingForContactUpgradeToOneToOne(
                        ownedCryptoIdentity: ownedIdentity,
                        contactCryptoIdentity: contactIdentity,
                        messageToSendRawId: MessageId.trustLevelIncreased.rawValue,
                        protocolInstance: thisProtocolInstance,
                        delegateManager: delegateManager)

                }
                
                // Return the new state
                
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let mediatorIdentity = startState.mediatorIdentity

            let invitationAccepted = receivedMessage.invitationAccepted

            // Check the dialog UUID

            let dialogUuid: UUID
            do {
                let dialogUuidFromState = startState.dialogUuid
                let dialogUuidFromMessage = receivedMessage.dialogUuid
                guard dialogUuidFromState == dialogUuidFromMessage else { throw Self.makeError(message: "Unexpected dialog UUID") }
                dialogUuid = dialogUuidFromState
            }
                        
            // Propagate the accept/reject to other owned devices
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count

            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagateConfirmationMessage(coreProtocolMessage: coreMessage,
                                                                               invitationAccepted: invitationAccepted,
                                                                               contactIdentity: contactIdentity,
                                                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                                                               mediatorIdentity: mediatorIdentity)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not propagate accept/reject invitation to other devices.", log: log, type: .fault)
                }
            } else {
                os_log("This device is the only device of the owned identity, so we don't need to propagate the accept/reject invitation", log: log, type: .debug)
            }

            // If we rejected the invitation we delete the dialog and terminate this protocol
            
            guard invitationAccepted else {
                
                let dialogType = ObvChannelDialogToSendType.delete
                let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)

                return InvitationRejectedState()
            }
            
            // If we reach this point, the invitation was accepted. We show an appropriate dialog to the user and notify the contact with an appropriate signature
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.mediatorInviteAccepted(contact: contact,
                                                                                   mediatorIdentity: mediatorIdentity)
                let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
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
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
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
                let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                
                return InvitationRejectedState()
            }

            // If we reach this point, the invitation was accepted. We show an appropriate dialog to the user.
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.mediatorInviteAccepted(contact: contact,
                                                                                   mediatorIdentity: mediatorIdentity)
                let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
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
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let mediatorIdentity = startState.mediatorIdentity
            let dialogUuid = startState.dialogUuid
            let acceptType = startState.acceptType

            let contactDeviceUids = receivedMessage.contactDeviceUids
            let signature = receivedMessage.signature
            
            // We check the signature

            do {
                let challengeType = ChallengeType.mutualIntroduction(mediatorIdentity: mediatorIdentity, firstIdentity: ownedIdentity, secondIdentity: contactIdentity)
                guard ObvSolveChallengeStruct.checkResponse(signature, to: challengeType, from: contactIdentity) else {
                    os_log("The signature verification failed", log: log, type: .error)
                    return CancelledState()
                }
            }
            
            // We create the contact in the (trusted) contact database (or only add a new TrustOrigin if the contact already exists) and add all the device uids we just received
            
            do {
                
                let trustOrigin = TrustOrigin.introduction(timestamp: Date(), mediator: mediatorIdentity)
                
                if (try identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                    try identityDelegate.addTrustOriginIfTrustWouldBeIncreasedAndSetContactAsOneToOne(trustOrigin, toContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                } else {
                    try identityDelegate.addContactIdentity(contactIdentity, with: contactIdentityCoreDetails, andTrustOrigin: trustOrigin, forOwnedIdentity: ownedIdentity, isKnownToBeOneToOne: true, within: obvContext)
                }
                
                try contactDeviceUids.forEach { (contactDeviceUid) in
                    if try !identityDelegate.isDevice(withUid: contactDeviceUid, aDeviceOfContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext) {
                        try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, createdDuringChannelCreation: false, within: obvContext)
                    }
                }
            } catch {
                os_log("Could not add the contact identity to the contact identities database, or could not add a device uid to this contact", log: log, type: .fault)
                return CancelledState()
            }
            
            // We propagate the notification to our other owned devices
            
            let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagateContactNotificationOfAcceptedInvitationMessage(coreProtocolMessage: coreMessage,
                                                                                  contactDeviceUids: contactDeviceUids)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not propagate notification to other devices.", log: log, type: .fault)
                }
            } else {
                os_log("This device is the only device of the owned identity, so we don't need to propagate the notification", log: log, type: .debug)
            }

            // Send Ack to contact
            
            do {
                let coreMessage = getCoreMessage(for: .asymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = AckMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
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
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let mediatorIdentity = startState.mediatorIdentity
            let dialogUuid = startState.dialogUuid
            let acceptType = startState.acceptType
            
            let contactDeviceUids = receivedMessage.contactDeviceUids

            // We create the contact in the (trusted) contact database (only if it does not already exists) and add all the device uids we just received
            
            do {
                
                let trustOrigin = TrustOrigin.introduction(timestamp: Date(), mediator: mediatorIdentity)
                
                if (try identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                    try identityDelegate.addTrustOriginIfTrustWouldBeIncreasedAndSetContactAsOneToOne(trustOrigin, toContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                } else {
                    try identityDelegate.addContactIdentity(contactIdentity, with: contactIdentityCoreDetails, andTrustOrigin: trustOrigin, forOwnedIdentity: ownedIdentity, isKnownToBeOneToOne: true, within: obvContext)
                }
                
                try contactDeviceUids.forEach { (contactDeviceUid) in
                    if try !identityDelegate.isDevice(withUid: contactDeviceUid, aDeviceOfContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext) {
                        try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, createdDuringChannelCreation: false, within: obvContext)
                    }
                }
            } catch {
                os_log("Could not add the contact identity to the contact identities database, or could not add a device uid to this contact", log: log, type: .fault)
                return CancelledState()
            }

            // Return the new state
            
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
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let dialogUuid = startState.dialogUuid
            let acceptType = startState.acceptType
            // let mediatorIdentity = startState.mediatorIdentity

            // Display a mutual trust established dialog
            
            switch acceptType {
            case AcceptType.alreadyTrusted:
                // We do not notify the user in this case
                break
                
            case AcceptType.manual:
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.mutualTrustConfirmed(contact: contact)
                let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                
            default:
                // Cannot happen
                break
            }
            
            // Return the new state
            
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ContactMutualIntroductionProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let mediatorIdentity = startState.mediatorIdentity
            let dialogUuid = startState.dialogUuid

            let identityWithIncreasedTrustLevel = receivedMessage.contactIdentity
            
            // Check that the identity having an increased trust level is the contact
            
            guard contactIdentity == identityWithIncreasedTrustLevel else {
                os_log("The identity with an increased trust level is not the remote identity", log: log, type: .error)
                return startState
            }
            
            // Check whether the introduced contact is already a One2One contact.
            
            let contactStatus = try identityDelegate.getOneToOneStatusOfContactIdentity(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext)

            if contactStatus == .oneToOne {
                
                // If the introduced contact is now part of our OneToOne contacts, we remove any previous dialog showed to the user.
                // We automatically accept the invitation and notify our contact using a NotifyContactOfAcceptedInvitation message.

                do {
                    let dialogType = ObvChannelDialogToSendType.delete
                    let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                do {
                    let notifyContactOfAcceptedInvitationMessageInitializer = { (coreProtocolMessage: CoreProtocolMessage, contactDeviceUids: [UID], signature: Data) -> ContactMutualIntroductionProtocol.NotifyContactOfAcceptedInvitationMessage in
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

                
            } else {
                
                // If we reach this point, the introduced contact is not trusted yet (i.e., not OneToOne or not a contact at all).

                guard let thisProtocolInstance = ProtocolInstance.get(cryptoProtocolId: cryptoProtocolId, uid: protocolInstanceUid, ownedIdentity: ownedIdentity, delegateManager: delegateManager, within: obvContext) else {
                    os_log("Could not retrive this protocol instance", log: log, type: .fault)
                    return CancelledState()
                }

                // Remove any previous ProtocolInstanceWaitingForContactUpgradeToOneToOne entry concerning the mediator for this protocol instance
                
                do {
                    try ProtocolInstanceWaitingForContactUpgradeToOneToOne.deleteRelatedToProtocolInstance(
                        thisProtocolInstance,
                        contactCryptoIdentity: mediatorIdentity,
                        delegateManager: delegateManager)
                } catch {
                    os_log("Could not delete previous ProtocolInstanceWaitingForContactUpgradeToOneToOne entries", log: log, type: .fault)
                    return CancelledState()
                }
                
                // Insert an entry in the ProtocolInstanceWaitingForContactUpgradeToOneToOne database, so as to be notified if the Trust Level we have in the contact (remote identity) increases
                
                guard let _ = ProtocolInstanceWaitingForContactUpgradeToOneToOne(ownedCryptoIdentity: ownedIdentity,
                                                                                 contactCryptoIdentity: contactIdentity,
                                                                                 messageToSendRawId: MessageId.trustLevelIncreased.rawValue,
                                                                                 protocolInstance: thisProtocolInstance,
                                                                                 delegateManager: delegateManager)
                    else {
                        os_log("Could not create an entry in the ProtocolInstanceWaitingForContactUpgradeToOneToOne database", log: log, type: .fault)
                        return CancelledState()
                }
                
                
                // Display a dialog allowing to accept/reject the mediator's invite
                
                do {
                    let dialogType = ObvChannelDialogToSendType.acceptMediatorInvite(contact: CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails),
                                                                                     mediatorIdentity: mediatorIdentity)
                    let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity,dialogType: dialogType))
                    let concreteProtocolMessage = AcceptMediatorInviteDialogMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
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
            throw Self.makeError(message: "The solve challenge delegate is not set")
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The identity delegate is not set")
        }
        
        guard let channelDelegate = delegateManager.channelDelegate else {
            os_log("The channelDelegate is not set", log: log, type: .fault)
            throw Self.makeError(message: "The channel delegate is not set")
        }

        let signature: Data
        do {
            let challengeType = ChallengeType.mutualIntroduction(mediatorIdentity: mediatorIdentity, firstIdentity: contactIdentity, secondIdentity: ownedIdentity)
            guard let sig = try? solveChallengeDelegate.solveChallenge(challengeType, for: ownedIdentity, using: prng, within: obvContext) else {
                os_log("Could not compute signature", log: log, type: .fault)
                throw Self.makeError(message: "Could not compute signature")
            }
            signature = sig
        }
        
        do {
            let ownedDeviceUids = try identityDelegate.getDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
            let coreMessage = getCoreMessage(for: .asymmetricChannelBroadcast(to: contactIdentity, fromOwnedIdentity: ownedIdentity))
            let concreteProtocolMessage = notifyContactOfAcceptedInvitationMessageInitializer(coreMessage, Array(ownedDeviceUids), signature)
            guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
            }
            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
        }
        
        
    }
    
}
