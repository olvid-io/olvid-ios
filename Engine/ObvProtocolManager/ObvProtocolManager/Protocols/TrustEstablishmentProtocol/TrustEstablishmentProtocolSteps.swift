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
import CoreData
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import ObvMetaManager
import OlvidUtils

// MARK: - Protocol Steps

extension TrustEstablishmentProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId {
        
        // Alice's side
        case SendCommitment = 0
        case StoreDecommitment = 1
        case ShowSasDialogAndSendDecommitment = 2
        
        // Bob's side
        case StoreAndPropagateCommitmentAndAskForConfirmation = 3
        case StoreCommitmentAndAskForConfirmation = 4
        case SendSeedAndPropagateConfirmation = 5
        case ReceiveConfirmationFromOtherDevice = 6
        case ShowSasDialog = 7
        
        // Both sides
        case CheckSasAndAddTrust = 8
        case CheckPropagatedSasAndAddTrust = 9
        case NotifiedMutualTrustEstablished = 10
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            // Alice's side
            case .SendCommitment:
                let step = SendCommitmentStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .StoreDecommitment:
                let step = StoreDecommitmentStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ShowSasDialogAndSendDecommitment:
                let step = ShowSasDialogAndSendDecommitmentStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            // Bob's side
            case .StoreAndPropagateCommitmentAndAskForConfirmation:
                let step = StoreAndPropagateCommitmentAndAskForConfirmationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .StoreCommitmentAndAskForConfirmation:
                let step = StoreCommitmentAndAskForConfirmationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .SendSeedAndPropagateConfirmation:
                let step = SendSeedAndPropagateConfirmationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ReceiveConfirmationFromOtherDevice:
                let step = ReceiveConfirmationFromOtherDeviceStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ShowSasDialog:
                let step = ShowSasDialogStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            // Both Sides
            case .CheckSasAndAddTrust:
                let step = CheckSasAndAddTrustStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .CheckPropagatedSasAndAddTrust:
                let step = CheckPropagatedSasAndAddTrustStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .NotifiedMutualTrustEstablished:
                let step = NotifiedMutualTrustEstablishedStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
    }
    
    
    final class SendCommitmentStep: ProtocolStep, TypedConcreteProtocolStep {
        
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
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityFullDisplayName = receivedMessage.contactIdentityFullDisplayName
            let ownIdentityCoreDetails = receivedMessage.ownIdentityCoreDetails
            let dialogUuid = UUID()
            
            // Generate a seed for the SAS and commit on it
            
            let seedForSas = prng.genSeed()
            let commitmentScheme = ObvCryptoSuite.sharedInstance.commitmentScheme()
            let (commitment, decommitment) = commitmentScheme.commit(onTag: ownedIdentity.getIdentity(),
                                                                     andValue: seedForSas.raw,
                                                                     with: prng)

            // Propagate the invitation, the seed, and the decommitment to our other owned devices
            
            guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                return CancelledState()
            }
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = AlicePropagatesHerInviteToOtherDevicesMessage(coreProtocolMessage: coreMessage,
                                                                                                contactIdentity: contactIdentity,
                                                                                                contactIdentityFullDisplayName: contactIdentityFullDisplayName,
                                                                                                decommitment: decommitment,
                                                                                                seedForSas: seedForSas,
                                                                                                dialogUuid: dialogUuid)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not propagate invite to other devices.", log: log, type: .fault)
                }
            } else {
                os_log("This device is the only device of the owned identity, so we don't need to propagate the invitation", log: log, type: .debug)
            }
            
            // Send the commitment on our own seed for SAS, as well as our identity and display name.
            
            guard let ownedDeviceUids = try? identityDelegate.getDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext) else {
                os_log("Could not determine owned device uids", log: log, type: .fault)
                return CancelledState()
            }
            
            do {
                let coreMessage = getCoreMessage(for: .AsymmetricChannelBroadcast(to: contactIdentity, fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = AliceSendsCommitmentMessage(coreProtocolMessage: coreMessage,
                                                                          contactIdentityCoreDetails: ownIdentityCoreDetails,
                                                                          contactIdentity: ownedIdentity,
                                                                          contactDeviceUids: [UID](ownedDeviceUids),
                                                                          commitment: commitment)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Send a dialog to Alice to notify her that the invitation was sent
            
            do {
                let contact = CryptoIdentityWithFullDisplayName(cryptoIdentity: contactIdentity, fullDisplayName: contactIdentityFullDisplayName)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: .inviteSent(contact: contact)))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
            return WaitingForSeedState(contactIdentity: contactIdentity,
                                       decommitment: decommitment,
                                       seedForSas: seedForSas,
                                       dialogUuid: dialogUuid)
        }
    }
    
    
    final class StoreDecommitmentStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: AlicePropagatesHerInviteToOtherDevicesMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: AlicePropagatesHerInviteToOtherDevicesMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityFullDisplayName = receivedMessage.contactIdentityFullDisplayName
            let decommitment = receivedMessage.decommitment
            let seedForSas = receivedMessage.seedForSas
            let dialogUuid = UUID()
            
            // Send a dialog to Alice to notify her that the invitation was sent
            
            do {
                let contact = CryptoIdentityWithFullDisplayName(cryptoIdentity: contactIdentity, fullDisplayName: contactIdentityFullDisplayName)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: .inviteSent(contact: contact)))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            return WaitingForSeedState(contactIdentity: contactIdentity,
                                       decommitment: decommitment,
                                       seedForSas: seedForSas,
                                       dialogUuid: dialogUuid)
        }
    }

    
    final class ShowSasDialogAndSendDecommitmentStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForSeedState
        let receivedMessage: BobSendsSeedMessage
        
        init?(startState: WaitingForSeedState, receivedMessage: BobSendsSeedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentProtocol.logCategory)
            
            let contactIdentity = startState.contactIdentity
            let decommitment = startState.decommitment
            let seedForSas = startState.seedForSas
            let dialogUuid = startState.dialogUuid
            
            let contactSeedForSas = receivedMessage.contactSeedForSas
            let contactDeviceUids = receivedMessage.contactDeviceUids
            let contactIdentityCoreDetails = receivedMessage.contactIdentityCoreDetails
            
            // Send the decommitment to Bob
            
            do {
                let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = AliceSendsDecommitmentMessage(coreProtocolMessage: coreMessage, decommitment: decommitment)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Bob accepted the invitation. We have all the information we need to compute and show a SAS dialog to Alice
            
            guard let sasToDisplay = SAS.compute(seed1: seedForSas, seed2: contactSeedForSas, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS) else {
                os_log("Could not compute SAS", log: log, type: .fault)
                return CancelledState()
            }

            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.sasExchange(contact: contact, sasToDisplay: sasToDisplay, numberOfBadEnteredSas: 0)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogSasExchangeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            return WaitingForUserSASState(contactIdentity: contactIdentity,
                                          contactIdentityCoreDetails: contactIdentityCoreDetails,
                                          contactDeviceUids: contactDeviceUids,
                                          seedForSas: seedForSas,
                                          contactSeedForSas: contactSeedForSas,
                                          dialogUuid: dialogUuid,
                                          numberOfBadEnteredSas: 0)
        }
    }

    
    final class StoreAndPropagateCommitmentAndAskForConfirmationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: AliceSendsCommitmentMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: AliceSendsCommitmentMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentProtocol.logCategory)
            
            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityCoreDetails = receivedMessage.contactIdentityCoreDetails
            let contactDeviceUids = receivedMessage.contactDeviceUids
            let commitment = receivedMessage.commitment
            let dialogUuid = UUID()

            // Show a dialog allowing Bob to accept or reject Alice's invitation
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: .acceptInvite(contact: contact)))
                let concreteProtocolMessage = BobDialogInvitationConfirmationMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Propagate Alice's invitation (with the commitment) to the other owned devices of Bob
            
            guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                return CancelledState()
            }
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = BobPropagatesCommitmentToOtherDevicesMessage(coreProtocolMessage: coreMessage,
                                                                                               contactIdentity: contactIdentity,
                                                                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                                                                               contactDeviceUids: contactDeviceUids,
                                                                                               commitment: commitment)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
            }
            
            // Return the new state
            
            return WaitingForConfirmationState(contactIdentity: contactIdentity,
                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                               contactDeviceUids: contactDeviceUids,
                                               commitment: commitment,
                                               dialogUuid: dialogUuid)
        }
    }


    final class StoreCommitmentAndAskForConfirmationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: BobPropagatesCommitmentToOtherDevicesMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: BobPropagatesCommitmentToOtherDevicesMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityCoreDetails = receivedMessage.contactIdentityCoreDetails
            let contactDeviceUids = receivedMessage.contactDeviceUids
            let commitment = receivedMessage.commitment
            let dialogUuid = UUID()
            
            // Show a dialog allowing Bob to accept or reject Alice's invitation
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: .acceptInvite(contact: contact)))
                let concreteProtocolMessage = BobDialogInvitationConfirmationMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            return WaitingForConfirmationState(contactIdentity: contactIdentity,
                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                               contactDeviceUids: contactDeviceUids,
                                               commitment: commitment,
                                               dialogUuid: dialogUuid)
        }
    }

    
    final class SendSeedAndPropagateConfirmationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForConfirmationState
        let receivedMessage: BobDialogInvitationConfirmationMessage
        
        init?(startState: WaitingForConfirmationState, receivedMessage: BobDialogInvitationConfirmationMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentProtocol.logCategory)
            
            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let commitment = startState.commitment
            let dialogUuid = startState.dialogUuid
            
            let invitationAccepted = receivedMessage.invitationAccepted
            
            // Get owned identity core details
            
            let ownedIdentityCoreDetails: ObvIdentityCoreDetails
            do {
                ownedIdentityCoreDetails = try identityDelegate.getIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext).publishedIdentityDetails.coreDetails
            } catch {
                os_log("Could not get owned identity core details", log: log, type: .fault)
                return CancelledState()
            }
            
            // Propagate Bob's choice to all his other devices
            
            guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                return CancelledState()
            }
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = BobPropagatesConfirmationToOtherDevicesMessage(coreProtocolMessage: coreMessage, invitationAccepted: invitationAccepted)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not propagate accept/reject invitation to other devices.", log: log, type: .fault)
                }
            } else {
                os_log("This device is the only device of the owned identity, so we don't need to propagate the accept/reject invitation", log: log, type: .debug)
            }

            // If the invitation was rejected, we terminate the protocol
            
            guard invitationAccepted else {
                os_log("The user rejected the invitation", log: log, type: .debug)
                
                do {
                    let dialogType = ObvChannelDialogToSendType.delete
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }

                return CancelledState()
            }
            
            // If we reach this point, Bob accepted Alice's invitation
            
            // Show a dialog informing Bob that he accepted Alice's invitation
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.invitationAccepted(contact: contact)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Send a seed for the SAS to Alice
            
            let seedForSas: Seed
            do {
                guard !commitment.isEmpty else { throw NSError() }
                seedForSas = try identityDelegate.getDeterministicSeedForOwnedIdentity(ownedIdentity, diversifiedUsing: commitment, within: obvContext)
            } catch {
                os_log("Could not compute (deterministic but diversified) seed for sas", log: log, type: .error)
                return CancelledState()
            }
            
            guard let ownedDeviceUids = try? identityDelegate.getDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext) else {
                os_log("Could not determine owned device uids", log: log, type: .fault)
                return CancelledState()
            }

            do {
                let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = BobSendsSeedMessage(coreProtocolMessage: coreMessage,
                                                                  contactSeedForSas: seedForSas,
                                                                  contactIdentityCoreDetails: ownedIdentityCoreDetails,
                                                                  contactDeviceUids: [UID](ownedDeviceUids))
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            return WaitingForDecommitmentState(contactIdentity: contactIdentity,
                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                               contactDeviceUids: contactDeviceUids,
                                               commitment: commitment,
                                               seedForSas: seedForSas,
                                               dialogUuid: dialogUuid)
        }
    }

    
    final class ReceiveConfirmationFromOtherDeviceStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForConfirmationState
        let receivedMessage: BobPropagatesConfirmationToOtherDevicesMessage
        
        init?(startState: WaitingForConfirmationState, receivedMessage: BobPropagatesConfirmationToOtherDevicesMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentProtocol.logCategory)
            
            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let commitment = startState.commitment
            let dialogUuid = startState.dialogUuid
            
            let invitationAccepted = receivedMessage.invitationAccepted
            
            // If the invitation was rejected, we terminate the protocol
            
            guard invitationAccepted else {
                os_log("The user rejected the invitation", log: log, type: .debug)
                
                do {
                    let dialogType = ObvChannelDialogToSendType.delete
                    let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                return CancelledState()
            }
            
            // If we reach this point, Bob accepted Alice's invitation
            
            // Show a dialog informing Bob that he accepted Alice's invitation
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.invitationAccepted(contact: contact)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Compute the seed for the SAS (that was sent to Alice by the other device)
            
            let seedForSas: Seed
            do {
                guard !commitment.isEmpty else { throw NSError() }
                seedForSas = try identityDelegate.getDeterministicSeedForOwnedIdentity(ownedIdentity, diversifiedUsing: commitment, within: obvContext)
            } catch {
                os_log("Could not compute (deterministic but diversified) seed for sas", log: log, type: .error)
                return CancelledState()
            }

            // Return the new state
            
            return WaitingForDecommitmentState(contactIdentity: contactIdentity,
                                               contactIdentityCoreDetails: contactIdentityCoreDetails,
                                               contactDeviceUids: contactDeviceUids,
                                               commitment: commitment,
                                               seedForSas: seedForSas,
                                               dialogUuid: dialogUuid)
        }
    }

    
    final class ShowSasDialogStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForDecommitmentState
        let receivedMessage: AliceSendsDecommitmentMessage
        
        init?(startState: WaitingForDecommitmentState, receivedMessage: AliceSendsDecommitmentMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentProtocol.logCategory)
            
            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let commitment =  startState.commitment
            let seedForSas = startState.seedForSas
            let dialogUuid = startState.dialogUuid
            
            let decommitment = receivedMessage.decommitment
            
            // Open the commitment to recover the contact seed for the SAS
            
            let contactSeedForSas: Seed
            do {
                let commitmentScheme = ObvCryptoSuite.sharedInstance.commitmentScheme()
                guard let rawContactSeedForSAS = commitmentScheme.open(commitment: commitment, onTag: contactIdentity.getIdentity(), usingDecommitToken: decommitment) else {
                    os_log("Could not open the commitment", log: log, type: .error)
                    return CancelledState()
                }
                guard let seed = Seed(with: rawContactSeedForSAS) else {
                    os_log("Could not recover contact seed", log: log, type: .error)
                    return CancelledState()
                }
                contactSeedForSas = seed
            }
            
            // We have all the information we need to compute and show a SAS dialog to Bob
            
            guard let sasToDisplay = SAS.compute(seed1: seedForSas, seed2: contactSeedForSas, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS) else {
                os_log("Could not compute SAS", log: log, type: .fault)
                return CancelledState()
            }
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.sasExchange(contact: contact, sasToDisplay: sasToDisplay, numberOfBadEnteredSas: 0)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogSasExchangeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
            return WaitingForUserSASState(contactIdentity: contactIdentity,
                                          contactIdentityCoreDetails: contactIdentityCoreDetails,
                                          contactDeviceUids: contactDeviceUids,
                                          seedForSas: seedForSas,
                                          contactSeedForSas: contactSeedForSas,
                                          dialogUuid: dialogUuid,
                                          numberOfBadEnteredSas: 0)
        }
    }

    
    final class CheckSasAndAddTrustStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForUserSASState
        let receivedMessage: DialogSasExchangeMessage
        
        init?(startState: WaitingForUserSASState, receivedMessage: DialogSasExchangeMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentProtocol.logCategory)
            
            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let seedForSas = startState.seedForSas
            let contactSeedForSas = startState.contactSeedForSas
            let dialogUuid = startState.dialogUuid
            let numberOfBadEnteredSas = startState.numberOfBadEnteredSas
            
            guard let sasEnteredByUser = receivedMessage.sasEnteredByUser else {
                os_log("Could not retrieve SAS entered by user", log: log, type: .fault)
                return CancelledState()
            }

            // Re-compute the SAS and compare it to the SAS entered by the user
            
            let sasToDisplay: Data
            let sasEntered: Data
            do {
                guard let sas = SAS.compute(seed1: seedForSas, seed2: contactSeedForSas, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS) else {
                    os_log("Could not compute SAS to display", log: log, type: .fault)
                    return nil
                }
                sasToDisplay = sas
                guard let computedSAS = SAS.compute(seed1: contactSeedForSas, seed2: seedForSas, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS) else {
                    os_log("Could not compute SAS to compare to entered SAS", log: log, type: .fault)
                    return nil
                }
                guard computedSAS == sasEnteredByUser else {
                    os_log("The SAS entered by the user does not match the expected SAS.", log: log, type: .error)
                    
                    // We re-post the same dialog
                    let newNumberOfBadEnteredSas = numberOfBadEnteredSas + 1
                    do {
                        let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                        let dialogType = ObvChannelDialogToSendType.sasExchange(contact: contact, sasToDisplay: sasToDisplay, numberOfBadEnteredSas: newNumberOfBadEnteredSas)
                        let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                        let concreteProtocolMessage = DialogSasExchangeMessage(coreProtocolMessage: coreMessage)
                        guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    }

                    // We go back to the WaitingForUserSAS state (only the number of bad entered sas changes)
                    return WaitingForUserSASState(contactIdentity: contactIdentity,
                                                  contactIdentityCoreDetails: contactIdentityCoreDetails,
                                                  contactDeviceUids: contactDeviceUids,
                                                  seedForSas: seedForSas,
                                                  contactSeedForSas: contactSeedForSas,
                                                  dialogUuid: dialogUuid,
                                                  numberOfBadEnteredSas: newNumberOfBadEnteredSas)
                }
                sasEntered = computedSAS
            }
            
            // Propagate the sas entered by the user to all the other devices of this user
            
            guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                return CancelledState()
            }
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .AllConfirmedObliviousChannelsWithOtherDevicesOfOwnedIdentity(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PropagateEnteredSasToOtherDevicesMessage.init(coreProtocolMessage: coreMessage, sasEnteredByUser: sasEntered)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not propagate sas to other devices.", log: log, type: .fault)
                }
            } else {
                os_log("This device is the only device of the owned identity, so we don't need to propagate the entered sas", log: log, type: .debug)
            }

            // Send a dialog message similar to the one asking to enter the SAS, but with the entered SAS "built-in"
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.sasConfirmed(contact: contact, sasToDisplay: sasToDisplay, sasEntered: sasEntered)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Add the contact identity to the contact database (or simply add a new trust origin if the contact already exists) and add all the contact device uids
            
            do {
                let trustOrigin = TrustOrigin.direct(timestamp: Date())
                
                if (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                    try identityDelegate.addTrustOrigin(trustOrigin, toContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, setIsOneToOneTo: true, within: obvContext)
                } else {
                    try identityDelegate.addContactIdentity(contactIdentity, with: contactIdentityCoreDetails, andTrustOrigin: trustOrigin, forOwnedIdentity: ownedIdentity, setIsOneToOneTo: true, within: obvContext)
                }
                
                try contactDeviceUids.forEach { (contactDeviceUid) in
                    try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
                }
            } catch {
                os_log("Could not add the contact identity to the contact identities database, or could not add a device uid to this contact", log: log, type: .fault)
                return CancelledState()
            }
            
            // Send a confirmation message
            
            do {
                let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = MutualTrustConfirmationMessageMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            return ContactIdentityTrustedState(contactIdentity: contactIdentity, contactIdentityCoreDetails: contactIdentityCoreDetails, dialogUuid: dialogUuid)
        }
    }

    
    final class CheckPropagatedSasAndAddTrustStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForUserSASState
        let receivedMessage: PropagateEnteredSasToOtherDevicesMessage
        
        init?(startState: WaitingForUserSASState, receivedMessage: PropagateEnteredSasToOtherDevicesMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AnyObliviousChannelWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentProtocol.logCategory)
            
            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let seedForSas = startState.seedForSas
            let contactSeedForSas = startState.contactSeedForSas
            let dialogUuid = startState.dialogUuid

            let sasEnteredByUser = receivedMessage.sasEnteredByUser
            
            // Re-compute the SAS and compare it to the SAS entered by the user
            
            let sasToDisplay: Data
            let sasEntered: Data
            do {
                guard let sas = SAS.compute(seed1: seedForSas, seed2: contactSeedForSas, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS) else {
                    os_log("Could not compute SAS to display", log: log, type: .fault)
                    return nil
                }
                sasToDisplay = sas
                guard let computedSAS = SAS.compute(seed1: contactSeedForSas, seed2: seedForSas, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS) else {
                    os_log("Could not compute SAS to compare to entered SAS", log: log, type: .fault)
                    return nil
                }
                guard computedSAS == sasEnteredByUser else {
                    os_log("The SAS entered by the user does not match the expected SAS.", log: log, type: .error)
                    // Remove the any dialog related to this protocol
                    do {
                        let dialogType = ObvChannelDialogToSendType.delete
                        let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                        let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                        guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { throw NSError() }
                        _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    }
                    return CancelledState()
                }
                sasEntered = computedSAS
            }
            
            // Send a dialog message similar to the one asking to enter the SAS, but with the entered SAS "built-in"
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.sasConfirmed(contact: contact, sasToDisplay: sasToDisplay, sasEntered: sasEntered)
                let coreMessage = getCoreMessage(for: .UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Add the contact identity to the (trusted) contact database and add all the contact device uids
            
            do {
                let trustOrigin = TrustOrigin.direct(timestamp: Date())
                
                if (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                    try identityDelegate.addTrustOrigin(trustOrigin, toContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, setIsOneToOneTo: true, within: obvContext)
                } else {
                    try identityDelegate.addContactIdentity(contactIdentity, with: contactIdentityCoreDetails, andTrustOrigin: trustOrigin, forOwnedIdentity: ownedIdentity, setIsOneToOneTo: true, within: obvContext)
                }
                
                try contactDeviceUids.forEach { (contactDeviceUid) in
                    try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
                }
            } catch {
                os_log("Could not add the contact identity to the contact identities database, or could not add a device uid to this contact", log: log, type: .fault)
                return CancelledState()
            }
            
            // Send a confirmation message
            
            do {
                let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = MutualTrustConfirmationMessageMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            return ContactIdentityTrustedState(contactIdentity: contactIdentity, contactIdentityCoreDetails: contactIdentityCoreDetails, dialogUuid: dialogUuid)
        }
    }

    
    final class NotifiedMutualTrustEstablishedStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ContactIdentityTrustedState
        let receivedMessage: MutualTrustConfirmationMessageMessage
        
        init?(startState: ContactIdentityTrustedState, receivedMessage: MutualTrustConfirmationMessageMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let dialogUuid = startState.dialogUuid
            
            // Send a dialog message notifying the user that the mutual trust is confirmed
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let dialogType = ObvChannelDialogToSendType.mutualTrustConfirmed(contact: contact)
                let channelType = ObvChannelSendChannelType.UserInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType)
                let coreMessage = getCoreMessage(for: channelType)
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            return MutualTrustConfirmedState()
            
        }
    }

}
