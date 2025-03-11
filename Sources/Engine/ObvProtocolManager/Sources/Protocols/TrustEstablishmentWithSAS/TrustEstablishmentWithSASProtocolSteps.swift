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
import CoreData
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation
import ObvMetaManager
import OlvidUtils

// MARK: - Protocol Steps

extension TrustEstablishmentWithSASProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        // Alice's side
        case sendCommitment = 0
        case storeDecommitment = 1
        case showSasDialogAndSendDecommitment = 2
        
        // Bob's side
        case storeAndPropagateCommitmentAndAskForConfirmation = 3
        case storeCommitmentAndAskForConfirmation = 4
        case sendSeedAndPropagateConfirmation = 5
        case receiveConfirmationFromOtherDevice = 6
        case showSasDialog = 7
        
        // Both sides
        case checkSas = 8 // 2020-03-02 Used to be CheckSasAndAddTrust
        case checkPropagatedSas = 9 // 2020-03-02 Used to be CheckPropagatedSasAndAddTrust
        case notifiedMutualTrustEstablishedLegacy = 10 // 2020-03-02 Used to be NotifiedMutualTrustEstablished
        case addTrust = 11 // 2020-03-02 New step
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            // Alice's side
            case .sendCommitment:
                let step = SendCommitmentStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .storeDecommitment:
                let step = StoreDecommitmentStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .showSasDialogAndSendDecommitment:
                let step = ShowSasDialogAndSendDecommitmentStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            // Bob's side
            case .storeAndPropagateCommitmentAndAskForConfirmation:
                let step = StoreAndPropagateCommitmentAndAskForConfirmationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .storeCommitmentAndAskForConfirmation:
                let step = StoreCommitmentAndAskForConfirmationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .sendSeedAndPropagateConfirmation:
                let step = SendSeedAndPropagateConfirmationStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .receiveConfirmationFromOtherDevice:
                let step = ReceiveConfirmationFromOtherDeviceStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .showSasDialog:
                let step = ShowSasDialogStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            // Both Sides
            case .checkSas:
                let step = CheckSasStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .checkPropagatedSas:
                let step = CheckPropagatedSasStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .notifiedMutualTrustEstablishedLegacy:
                let step = NotifiedMutualTrustEstablishedLegacyStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .addTrust:
                let step = AddTrustStep(from: concreteProtocol, and: receivedMessage)
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityFullDisplayName = receivedMessage.contactIdentityFullDisplayName
            let ownIdentityCoreDetails = receivedMessage.ownIdentityCoreDetails
            let dialogUuid = UUID()
            
            // Generate a seed for the SAS and commit on it
            
            let seedAliceForSas = prng.genSeed()
            let commitmentScheme = ObvCryptoSuite.sharedInstance.commitmentScheme()
            let (commitment, decommitment) = commitmentScheme.commit(
                onTag: ownedIdentity.getIdentity(),
                andValue: seedAliceForSas.raw,
                with: prng)

            // Propagate the invitation, the seed, and the decommitment to our other owned devices
            
            guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                return CancelledState()
            }
            
            if numberOfOtherDevicesOfOwnedIdentity > 0 {
                do {
                    let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                    let concreteProtocolMessage = AlicePropagatesHerInviteToOtherDevicesMessage(coreProtocolMessage: coreMessage,
                                                                                                contactIdentity: contactIdentity,
                                                                                                contactIdentityFullDisplayName: contactIdentityFullDisplayName,
                                                                                                decommitment: decommitment,
                                                                                                seedAliceForSas: seedAliceForSas)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
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
                let coreMessage = getCoreMessage(for: .asymmetricChannelBroadcast(to: contactIdentity, fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = AliceSendsCommitmentMessage(coreProtocolMessage: coreMessage,
                                                                          contactIdentityCoreDetails: ownIdentityCoreDetails,
                                                                          contactIdentity: ownedIdentity,
                                                                          contactDeviceUids: [UID](ownedDeviceUids),
                                                                          commitment: commitment)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Send a dialog to Alice to notify her that the invitation was sent
            
            do {
                let contact = CryptoIdentityWithFullDisplayName(cryptoIdentity: contactIdentity, fullDisplayName: contactIdentityFullDisplayName)
                let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: .inviteSent(contact: contact)))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
            return WaitingForSeedState(contactIdentity: contactIdentity,
                                       decommitment: decommitment,
                                       seedAliceForSas: seedAliceForSas,
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
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityFullDisplayName = receivedMessage.contactIdentityFullDisplayName
            let decommitment = receivedMessage.decommitment
            let seedAliceForSas = receivedMessage.seedAliceForSas
            let dialogUuid = UUID()
            
            // Send a dialog to Alice to notify her that the invitation was sent
            
            do {
                let contact = CryptoIdentityWithFullDisplayName(cryptoIdentity: contactIdentity, fullDisplayName: contactIdentityFullDisplayName)
                let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: .inviteSent(contact: contact)))
                let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }
            
            // Return the new state
            
            return WaitingForSeedState(contactIdentity: contactIdentity,
                                       decommitment: decommitment,
                                       seedAliceForSas: seedAliceForSas,
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
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let decommitment = startState.decommitment
            let seedAliceForSas = startState.seedAliceForSas
            let dialogUuid = startState.dialogUuid
            
            let seedBobForSas = receivedMessage.seedBobForSas
            let contactDeviceUids = receivedMessage.contactDeviceUids
            let contactIdentityCoreDetails = receivedMessage.contactIdentityCoreDetails
            
            do {
                
                // Send the decommitment to Bob
                
                do {
                    let coreMessage = getCoreMessage(for: .asymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: ownedIdentity))
                    let concreteProtocolMessage = AliceSendsDecommitmentMessage(coreProtocolMessage: coreMessage, decommitment: decommitment)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Bob accepted the invitation. We have all the information we need to compute and show a SAS dialog to Alice.
                
                let sasToDisplay: Data
                do {
                    let fullSAS = try SAS.compute(seedAlice: seedAliceForSas, seedBob: seedBobForSas, identityBob: contactIdentity, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS * 2)
                    sasToDisplay = fullSAS.leftHalf
                } catch let error {
                    os_log("Could not compute SAS: %{public}@", log: log, type: .fault, error.localizedDescription)
                    removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                    return CancelledState()
                }
                
                do {
                    let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                    let dialogType = ObvChannelDialogToSendType.sasExchange(contact: contact, sasToDisplay: sasToDisplay, numberOfBadEnteredSas: 0)
                    let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogSasExchangeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return WaitingForUserSASState(contactIdentity: contactIdentity,
                                              contactIdentityCoreDetails: contactIdentityCoreDetails,
                                              contactDeviceUids: contactDeviceUids,
                                              seedForSas: seedAliceForSas,
                                              contactSeedForSas: seedBobForSas,
                                              dialogUuid: dialogUuid,
                                              isAlice: true,
                                              numberOfBadEnteredSas: 0)
            } catch {
                
                assertionFailure()
                removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                return CancelledState()

            }
                
        }
    }

    
    final class StoreAndPropagateCommitmentAndAskForConfirmationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: AliceSendsCommitmentMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: AliceSendsCommitmentMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityCoreDetails = receivedMessage.contactIdentityCoreDetails
            let contactDeviceUids = receivedMessage.contactDeviceUids
            let commitment = receivedMessage.commitment
            let dialogUuid = UUID()

            do {
                
                // Check whether this commitment was already received in the past. In case it was, cancel.
                
                do {
                    guard !(try TrustEstablishmentCommitmentReceived.exists(ownedCryptoIdentity: ownedIdentity,
                                                                            commitment: commitment,
                                                                            within: obvContext)) else {
                        os_log("The commitment received was already received in a previous protocol message. This should not happen but with a negligible probability. We cancel.", log: log, type: .fault)
                        throw ObvError.commitmentReplay
                    }
                } catch {
                    os_log("We could not perform check whether the commitment was already received: %{public}@", log: log, type: .fault, error.localizedDescription)
                    throw error
                }
                
                guard TrustEstablishmentCommitmentReceived(ownedCryptoIdentity: ownedIdentity,
                                                           commitment: commitment,
                                                           within: obvContext) != nil else {
                    os_log("We could not insert a new TrustEstablishmentCommitmentReceived entry", log: log, type: .fault)
                    assertionFailure()
                    throw ObvError.couldNotInsertNewTrustEstablishmentCommitmentReceivedEntry
                }
                
                // Show a dialog allowing Bob to accept or reject Alice's invitation
                
                do {
                    let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                    let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: .acceptInvite(contact: contact)))
                    let concreteProtocolMessage = BobDialogInvitationConfirmationMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw ObvError.couldNotGenerateObvChannelDialogMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Propagate Alice's invitation (with the commitment) to the other owned devices of Bob
                
                let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
                
                if numberOfOtherDevicesOfOwnedIdentity > 0 {
                    do {
                        let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                        let concreteProtocolMessage = BobPropagatesCommitmentToOtherDevicesMessage(coreProtocolMessage: coreMessage,
                                                                                                   contactIdentity: contactIdentity,
                                                                                                   contactIdentityCoreDetails: contactIdentityCoreDetails,
                                                                                                   contactDeviceUids: contactDeviceUids,
                                                                                                   commitment: commitment)
                        guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                            throw ObvError.generateObvChannelProtocolMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                    }
                }
                
                // Return the new state
                
                return WaitingForConfirmationState(contactIdentity: contactIdentity,
                                                   contactIdentityCoreDetails: contactIdentityCoreDetails,
                                                   contactDeviceUids: contactDeviceUids,
                                                   commitment: commitment,
                                                   dialogUuid: dialogUuid)
                
            } catch {
                
                assertionFailure()
                removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                return CancelledState()

            }
                
        }
        
        
        enum ObvError: Error {
            case commitmentReplay
            case couldNotInsertNewTrustEstablishmentCommitmentReceivedEntry
            case couldNotGenerateObvChannelDialogMessageToSend
            case generateObvChannelProtocolMessageToSend
        }
        
    }


    final class StoreCommitmentAndAskForConfirmationStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: BobPropagatesCommitmentToOtherDevicesMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: BobPropagatesCommitmentToOtherDevicesMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            let contactIdentityCoreDetails = receivedMessage.contactIdentityCoreDetails
            let contactDeviceUids = receivedMessage.contactDeviceUids
            let commitment = receivedMessage.commitment
            let dialogUuid = UUID()
            
            // Check whether this (propagated) commitment was already received in the past. In case it was, cancel.
            
            do {
                guard !(try TrustEstablishmentCommitmentReceived.exists(ownedCryptoIdentity: ownedIdentity,
                                                                        commitment: commitment,
                                                                        within: obvContext)) else {
                    os_log("The commitment received (propagation) was already received in a previous protocol message. This should not happen but with a negligible probability. We cancel.", log: log, type: .fault)
                    throw ObvError.commitmentReplay
                }
            } catch {
                os_log("We could not perform check whether the commitment was already received: %{public}@", log: log, type: .fault, error.localizedDescription)
                throw error
            }
            
            guard TrustEstablishmentCommitmentReceived(ownedCryptoIdentity: ownedIdentity,
                                                       commitment: commitment,
                                                       within: obvContext) != nil else {
                os_log("We could not insert a new TrustEstablishmentCommitmentReceived entry", log: log, type: .fault)
                assertionFailure()
                throw ObvError.couldNotInsertNewTrustEstablishmentCommitmentReceivedEntry
            }

            // Show a dialog allowing Bob to accept or reject Alice's invitation
            
            do {
                let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: .acceptInvite(contact: contact)))
                let concreteProtocolMessage = BobDialogInvitationConfirmationMessage(coreProtocolMessage: coreMessage)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                    assertionFailure()
                    throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let commitment = startState.commitment
            let dialogUuid = startState.dialogUuid
            
            let invitationAccepted = receivedMessage.invitationAccepted
            
            do {
                
                // Get owned identity core details
                
                let ownedIdentityCoreDetails: ObvIdentityCoreDetails
                do {
                    ownedIdentityCoreDetails = try identityDelegate.getIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext).publishedIdentityDetails.coreDetails
                } catch {
                    os_log("Could not get owned identity core details", log: log, type: .fault)
                    throw ObvError.couldNotGetOwnedIdentityCoreDetails
                }
                
                // Propagate Bob's choice to all his other devices
                
                guard let numberOfOtherDevicesOfOwnedIdentity = try? identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count else {
                    os_log("Could not determine whether the owned identity has other (remote) devices", log: log, type: .fault)
                    throw ObvError.couldNotDetermineWhetherOwnedIdentityHasOtherRemoteDevices
                }
                
                if numberOfOtherDevicesOfOwnedIdentity > 0 {
                    do {
                        let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                        let concreteProtocolMessage = BobPropagatesConfirmationToOtherDevicesMessage(coreProtocolMessage: coreMessage, invitationAccepted: invitationAccepted)
                        guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                            assertionFailure()
                            throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                        }
                        _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Could not propagate accept/reject invitation to other devices.", log: log, type: .fault)
                    }
                } else {
                    os_log("This device is the only device of the owned identity, so we don't need to propagate the accept/reject invitation", log: log, type: .debug)
                }
                
                // If the invitation was rejected, we terminate the protocol
                
                guard invitationAccepted else {
                    os_log("The user rejected the invitation", log: log, type: .debug)
                    removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                    return CancelledState()
                }
                
                // If we reach this point, Bob accepted Alice's invitation
                
                // Show a dialog informing Bob that he accepted Alice's invitation
                
                do {
                    let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                    let dialogType = ObvChannelDialogToSendType.invitationAccepted(contact: contact)
                    let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Send a seed for the SAS to Alice
                
                let seedBobForSas: Seed
                do {
                    guard !commitment.isEmpty else { throw Self.makeError(message: "The commitment is empty") }
                    seedBobForSas = try identityDelegate.getDeterministicSeedForOwnedIdentity(ownedIdentity, diversifiedUsing: commitment, within: obvContext)
                } catch {
                    os_log("Could not compute (deterministic but diversified) seed for sas", log: log, type: .error)
                    throw ObvError.couldNotComputeDeterministicButDiversifiedSeedForSas
                }
                
                let ownedDeviceUids = try identityDelegate.getDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext)
                
                do {
                    let coreMessage = getCoreMessage(for: .asymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: ownedIdentity))
                    let concreteProtocolMessage = BobSendsSeedMessage(
                        coreProtocolMessage: coreMessage,
                        seedBobForSas: seedBobForSas,
                        contactIdentityCoreDetails: ownedIdentityCoreDetails,
                        contactDeviceUids: [UID](ownedDeviceUids))
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw ObvError.couldNotGenerateObvChannelDialogMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return WaitingForDecommitmentState(contactIdentity: contactIdentity,
                                                   contactIdentityCoreDetails: contactIdentityCoreDetails,
                                                   contactDeviceUids: contactDeviceUids,
                                                   commitment: commitment,
                                                   seedBobForSas: seedBobForSas,
                                                   dialogUuid: dialogUuid)
                
            } catch {
                
                assertionFailure()
                removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                return CancelledState()

            }
                
        }
        
        enum ObvError: Error {
            case couldNotGetOwnedIdentityCoreDetails
            case couldNotDetermineWhetherOwnedIdentityHasOtherRemoteDevices
            case couldNotComputeDeterministicButDiversifiedSeedForSas
            case couldNotGenerateObvChannelDialogMessageToSend
        }
        
    }

    
    final class ReceiveConfirmationFromOtherDeviceStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForConfirmationState
        let receivedMessage: BobPropagatesConfirmationToOtherDevicesMessage
        
        init?(startState: WaitingForConfirmationState, receivedMessage: BobPropagatesConfirmationToOtherDevicesMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let commitment = startState.commitment
            let dialogUuid = startState.dialogUuid
            
            let invitationAccepted = receivedMessage.invitationAccepted
            
            do {
                
                // If the invitation was rejected, we terminate the protocol
                
                guard invitationAccepted else {
                    os_log("The user rejected the invitation", log: log, type: .debug)
                    removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                    return CancelledState()
                }
                
                // If we reach this point, Bob accepted Alice's invitation
                
                // Show a dialog informing Bob that he accepted Alice's invitation
                
                do {
                    let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                    let dialogType = ObvChannelDialogToSendType.invitationAccepted(contact: contact)
                    let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        assertionFailure()
                        throw ObvError.couldNotGenerateObvChannelDialogMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Compute the seed for the SAS (that was sent to Alice by the other device)
                
                let seedBobForSas: Seed
                do {
                    guard !commitment.isEmpty else { throw ObvError.emptyCommitment }
                    seedBobForSas = try identityDelegate.getDeterministicSeedForOwnedIdentity(ownedIdentity, diversifiedUsing: commitment, within: obvContext)
                } catch {
                    os_log("Could not compute (deterministic but diversified) seed for sas", log: log, type: .error)
                    throw ObvError.couldNotComputeDeterministicButDiversifiedSeedForSas
                }
                
                // Return the new state
                
                return WaitingForDecommitmentState(contactIdentity: contactIdentity,
                                                   contactIdentityCoreDetails: contactIdentityCoreDetails,
                                                   contactDeviceUids: contactDeviceUids,
                                                   commitment: commitment,
                                                   seedBobForSas: seedBobForSas,
                                                   dialogUuid: dialogUuid)
                
            } catch {
                
                assertionFailure()
                removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                return CancelledState()

            }
                
        }
        
        
        enum ObvError: Error {
            case couldNotGenerateObvChannelDialogMessageToSend
            case emptyCommitment
            case couldNotComputeDeterministicButDiversifiedSeedForSas
        }

    }

    
    final class ShowSasDialogStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForDecommitmentState
        let receivedMessage: AliceSendsDecommitmentMessage
        
        init?(startState: WaitingForDecommitmentState, receivedMessage: AliceSendsDecommitmentMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let commitment =  startState.commitment
            let seedBobForSas = startState.seedBobForSas
            let dialogUuid = startState.dialogUuid
            
            let decommitment = receivedMessage.decommitment
            
            do {
                
                // Open the commitment to recover the contact seed for the SAS
                
                let seedAliceForSas: Seed
                do {
                    let commitmentScheme = ObvCryptoSuite.sharedInstance.commitmentScheme()
                    guard let rawContactSeedForSAS = commitmentScheme.open(commitment: commitment, onTag: contactIdentity.getIdentity(), usingDecommitToken: decommitment) else {
                        os_log("Could not open the commitment", log: log, type: .error)
                        throw ObvError.couldNotOpenDecommitment
                    }
                    guard let seed = Seed(with: rawContactSeedForSAS) else {
                        os_log("Could not recover contact seed", log: log, type: .error)
                        throw ObvError.couldNotRecoverContactSeed
                    }
                    seedAliceForSas = seed
                }
                
                // We have all the information we need to compute and show a SAS dialog to Bob
                
                let sasToDisplay: Data
                do {
                    let fullSAS = try SAS.compute(seedAlice: seedAliceForSas, seedBob: seedBobForSas, identityBob: ownedIdentity, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS * 2)
                    sasToDisplay = fullSAS.rightHalf
                } catch let error {
                    os_log("Could not compute SAS: %{public}@", log: log, type: .fault, error.localizedDescription)
                    throw ObvError.couldNotComputeSAS
                }
                
                do {
                    let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                    let dialogType = ObvChannelDialogToSendType.sasExchange(contact: contact, sasToDisplay: sasToDisplay, numberOfBadEnteredSas: 0)
                    let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogSasExchangeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw ObvError.couldNotGenerateObvChannelDialogMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return WaitingForUserSASState(contactIdentity: contactIdentity,
                                              contactIdentityCoreDetails: contactIdentityCoreDetails,
                                              contactDeviceUids: contactDeviceUids,
                                              seedForSas: seedBobForSas,
                                              contactSeedForSas: seedAliceForSas,
                                              dialogUuid: dialogUuid,
                                              isAlice: false,
                                              numberOfBadEnteredSas: 0)
                
            } catch {
                
                assertionFailure()
                removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                return CancelledState()

            }
                
        }
        
        
        enum ObvError: Error {
            case couldNotOpenDecommitment
            case couldNotRecoverContactSeed
            case couldNotComputeSAS
            case couldNotGenerateObvChannelDialogMessageToSend
        }
        
        
    }

    
    final class CheckSasStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForUserSASState
        let receivedMessage: DialogSasExchangeMessage
        
        init?(startState: WaitingForUserSASState, receivedMessage: DialogSasExchangeMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let seedForSas = startState.seedForSas
            let contactSeedForSas = startState.contactSeedForSas
            let dialogUuid = startState.dialogUuid
            let isAlice = startState.isAlice
            let numberOfBadEnteredSas = startState.numberOfBadEnteredSas
            
            do {
                
                guard let sasEnteredByUser = receivedMessage.sasEnteredByUser else {
                    os_log("Could not retrieve SAS entered by user", log: log, type: .fault)
                    removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                    return CancelledState()
                }
                
                // Re-compute the SAS and compare it to the SAS entered by the user
                
                let sasToDisplay: Data
                do {
                    let seedAlice = isAlice ? seedForSas : contactSeedForSas
                    let seedBob = isAlice ? contactSeedForSas : seedForSas
                    let identityBob = isAlice ? contactIdentity : ownedIdentity
                    let fullSAS = try SAS.compute(seedAlice: seedAlice, seedBob: seedBob, identityBob: identityBob, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS * 2)
                    
                    sasToDisplay = isAlice ? fullSAS.leftHalf : fullSAS.rightHalf
                    let sasToCompare = isAlice ? fullSAS.rightHalf : fullSAS.leftHalf
                    
                    guard sasToCompare == sasEnteredByUser else {
                        os_log("The SAS entered by the user does not match the expected SAS.", log: log, type: .error)
                        
                        // We re-post the same dialog
                        let newNumberOfBadEnteredSas = numberOfBadEnteredSas + 1
                        do {
                            let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                            let dialogType = ObvChannelDialogToSendType.sasExchange(contact: contact, sasToDisplay: sasToDisplay, numberOfBadEnteredSas: newNumberOfBadEnteredSas)
                            let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                            let concreteProtocolMessage = DialogSasExchangeMessage(coreProtocolMessage: coreMessage)
                            guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                                assertionFailure()
                                throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
                            }
                            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                        }
                        
                        // We go back to the WaitingForUserSAS state (only the number of bad entered sas changes)
                        return WaitingForUserSASState(contactIdentity: contactIdentity,
                                                      contactIdentityCoreDetails: contactIdentityCoreDetails,
                                                      contactDeviceUids: contactDeviceUids,
                                                      seedForSas: seedForSas,
                                                      contactSeedForSas: contactSeedForSas,
                                                      dialogUuid: dialogUuid,
                                                      isAlice: isAlice,
                                                      numberOfBadEnteredSas: newNumberOfBadEnteredSas)
                    }
                } catch {
                    os_log("Could not re-compute the SAS and compare it to the SAS entered by the user", log: log, type: .fault)
                    removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                    return CancelledState()
                }
                
                // Propagate the sas entered by the user to all the other devices of this user
                
                let numberOfOtherDevicesOfOwnedIdentity = try identityDelegate.getOtherDeviceUidsOfOwnedIdentity(ownedIdentity, within: obvContext).count
                
                if numberOfOtherDevicesOfOwnedIdentity > 0 {
                    do {
                        let coreMessage = getCoreMessage(for: .allConfirmedObliviousChannelsOrPreKeyChannelsWithOtherOwnedDevices(ownedIdentity: ownedIdentity))
                        let concreteProtocolMessage = PropagateEnteredSasToOtherDevicesMessage(coreProtocolMessage: coreMessage, contactSas: sasEnteredByUser)
                        guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                            assertionFailure()
                            throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                        }
                        _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                    } catch {
                        os_log("Could not propagate sas to other devices.", log: log, type: .fault)
                    }
                } else {
                    os_log("This device is the only device of the owned identity, so we don't need to propagate the entered sas", log: log, type: .debug)
                }
                
                // Send a dialog message similar to the one asking to enter the SAS, but with the entered SAS "built-in"
                
                do {
                    let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                    let dialogType = ObvChannelDialogToSendType.sasConfirmed(contact: contact, sasToDisplay: sasToDisplay, sasEntered: sasEnteredByUser)
                    let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw ObvError.couldNotGenerateObvChannelDialogMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // 2020-03-02 : We used to add the contact identity to the contact database (or simply add a new trust origin if the contact already exists) and add all the contact device uids
                // We do not do this now. Instead, this is performed within the AddAndPropagateTrustStep since, at this point, we know for sure that both users checked their respective SAS.
                
                // Send a confirmation message
                
                do {
                    let coreMessage = getCoreMessage(for: .asymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: ownedIdentity))
                    let concreteProtocolMessage = MutualTrustConfirmationMessageMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw ObvError.couldNotGenerateObvChannelDialogMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return ContactSASCheckedState(contactIdentity: contactIdentity, contactIdentityCoreDetails: contactIdentityCoreDetails, contactDeviceUids: contactDeviceUids, dialogUuid: dialogUuid)
                
            } catch {
                
                assertionFailure()
                removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                return CancelledState()

            }
        }
        
        
        enum ObvError: Error {
            case couldNotGenerateObvChannelDialogMessageToSend
        }

        
    }

    
    final class CheckPropagatedSasStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForUserSASState
        let receivedMessage: PropagateEnteredSasToOtherDevicesMessage
        
        init?(startState: WaitingForUserSASState, receivedMessage: PropagateEnteredSasToOtherDevicesMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannelOrPreKeyWithOwnedDevice(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let seedForSas = startState.seedForSas
            let contactSeedForSas = startState.contactSeedForSas
            let dialogUuid = startState.dialogUuid
            let isAlice = startState.isAlice

            let sasEnteredByUser = receivedMessage.contactSas
            
            do {
                
                // Re-compute the SAS and compare it to the SAS entered by the user
                
                let sasToDisplay: Data
                do {
                    let seedAlice = isAlice ? seedForSas : contactSeedForSas
                    let seedBob = isAlice ? contactSeedForSas : seedForSas
                    let identityBob = isAlice ? contactIdentity : ownedIdentity
                    let fullSAS = try SAS.compute(seedAlice: seedAlice, seedBob: seedBob, identityBob: identityBob, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS * 2)
                    
                    sasToDisplay = isAlice ? fullSAS.leftHalf : fullSAS.rightHalf
                    let sasToCompare = isAlice ? fullSAS.rightHalf : fullSAS.leftHalf
                    
                    guard sasToCompare == sasEnteredByUser else {
                        os_log("The SAS entered by the user does not match the expected SAS.", log: log, type: .error)
                        // Remove any dialog related to this protocol
                        removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                        return CancelledState()
                    }
                } catch {
                    os_log("Could not re-compute the SAS and compare it to the SAS entered by the user", log: log, type: .fault)
                    throw error
                }
                
                // Send a dialog message similar to the one asking to enter the SAS, but with the entered SAS "built-in"
                
                do {
                    let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                    let dialogType = ObvChannelDialogToSendType.sasConfirmed(contact: contact, sasToDisplay: sasToDisplay, sasEntered: sasEnteredByUser)
                    let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw ObvError.couldNotGenerateObvChannelDialogMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // 2020-03-02 : We used to add the contact identity to the contact database (or simply add a new trust origin if the contact already exists) and add all the contact device uids
                // We do not do this now. Instead, this is performed within the AddAndPropagateTrustStep since, at this point, we know for sure that both users checked their respective SAS.
                
                // Send a confirmation message
                
                do {
                    let coreMessage = getCoreMessage(for: .asymmetricChannel(to: contactIdentity, remoteDeviceUids: contactDeviceUids, fromOwnedIdentity: ownedIdentity))
                    let concreteProtocolMessage = MutualTrustConfirmationMessageMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        throw ObvError.couldNotGenerateObvChannelDialogMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return ContactSASCheckedState(contactIdentity: contactIdentity, contactIdentityCoreDetails: contactIdentityCoreDetails, contactDeviceUids: contactDeviceUids, dialogUuid: dialogUuid)
                
            } catch {
                
                assertionFailure()
                removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                return CancelledState()
                
            }
            
        }
        
        
        enum ObvError: Error {
            case couldNotGenerateObvChannelDialogMessageToSend
        }
        
        
    }

    
    final class NotifiedMutualTrustEstablishedLegacyStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ContactIdentityTrustedLegacyState
        let receivedMessage: MutualTrustConfirmationMessageMessage
        
        init?(startState: ContactIdentityTrustedLegacyState, receivedMessage: MutualTrustConfirmationMessageMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let dialogUuid = startState.dialogUuid
            
            do {
                
                // Send a dialog message notifying the user that the mutual trust is confirmed
                
                do {
                    let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                    let dialogType = ObvChannelDialogToSendType.mutualTrustConfirmed(contact: contact)
                    let channelType = ObvChannelSendChannelType.userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType)
                    let coreMessage = getCoreMessage(for: channelType)
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw ObvError.couldNotGenerateObvChannelDialogMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return MutualTrustConfirmedState()
                
            } catch {
                
                assertionFailure()
                removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                return CancelledState()

            }
            
        }
        
        enum ObvError: Error {
            case couldNotGenerateObvChannelDialogMessageToSend
        }

    }

    
    final class AddTrustStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ContactSASCheckedState
        let receivedMessage: MutualTrustConfirmationMessageMessage
        
        init?(startState: ContactSASCheckedState, receivedMessage: MutualTrustConfirmationMessageMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: TrustEstablishmentWithSASProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactIdentityCoreDetails = startState.contactIdentityCoreDetails
            let contactDeviceUids = startState.contactDeviceUids
            let dialogUuid = startState.dialogUuid
            
            do {
                
                // Add the contact identity to the contact database (or simply add a new trust origin if the contact already exists) and add all the contact device uids
                do {
                    let trustOrigin = TrustOrigin.direct(timestamp: Date())
                    
                    if (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true {
                        try identityDelegate.addTrustOriginIfTrustWouldBeIncreasedAndSetContactAsOneToOne(trustOrigin, toContactIdentity: contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext)
                    } else {
                        try identityDelegate.addContactIdentity(contactIdentity, with: contactIdentityCoreDetails, andTrustOrigin: trustOrigin, forOwnedIdentity: ownedIdentity, isKnownToBeOneToOne: true, within: obvContext)
                    }
                    
                    try contactDeviceUids.forEach { (contactDeviceUid) in
                        try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, createdDuringChannelCreation: false, within: obvContext)
                    }
                } catch {
                    os_log("Could not add the contact identity to the contact identities database, or could not add a device uid to this contact", log: log, type: .fault)
                    removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                    return CancelledState()
                }
                
                // Send a dialog message notifying the user that the mutual trust is confirmed
                
                do {
                    let contact = CryptoIdentityWithCoreDetails(cryptoIdentity: contactIdentity, coreDetails: contactIdentityCoreDetails)
                    let dialogType = ObvChannelDialogToSendType.mutualTrustConfirmed(contact: contact)
                    let channelType = ObvChannelSendChannelType.userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType)
                    let coreMessage = getCoreMessage(for: channelType)
                    let concreteProtocolMessage = DialogInformativeMessage(coreProtocolMessage: coreMessage)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                        throw ObvError.couldNotGenerateObvChannelDialogMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return MutualTrustConfirmedState()
                
            } catch {
                
                assertionFailure()
                removeAnyUserDialogRelatingToThisProtocol(dialogUuid: dialogUuid, log: log)
                return CancelledState()

            }
            
        }
    }
    

    enum ObvError: Error {
        case couldNotGenerateObvChannelDialogMessageToSend
        case commitmentReplay
        case couldNotInsertNewTrustEstablishmentCommitmentReceivedEntry
    }

}


fileprivate extension Data {
    
    var leftHalf: Data {
        return self[self.startIndex..<self.startIndex+self.count/2]
    }

    var rightHalf: Data {
        return self[self.startIndex+self.count/2..<self.startIndex+self.count]
    }

}


fileprivate extension ProtocolStep {

    /// Helper method allowing to remove any dialog relating to this protocol. This is typically used when the protocol fails, in order to make sure that no dialog remains visible to the user
    /// although the protocol is finished.
    func removeAnyUserDialogRelatingToThisProtocol(dialogUuid: UUID, log: OSLog) {
        do {
            let dialogType = ObvChannelDialogToSendType.delete
            let coreMessage = getCoreMessage(for: .userInterface(uuid: dialogUuid, ownedIdentity: ownedIdentity, dialogType: dialogType))
            let concreteProtocolMessage = TrustEstablishmentWithSASProtocol.DialogInformativeMessage(coreProtocolMessage: coreMessage)
            guard let messageToSend = concreteProtocolMessage.generateObvChannelDialogMessageToSend() else {
                assertionFailure()
                throw Self.makeError(message: "Could not generate ObvChannelDialogMessageToSend")
            }
            _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
        } catch {
            // We don't want to prevent the protocol to cancel because of a dialog, so we only log the error here
            os_log("Failed to delete all dialog relating to this protocol: %{public}@", log: log, type: .fault, error.localizedDescription)
        }
    }
    
}
