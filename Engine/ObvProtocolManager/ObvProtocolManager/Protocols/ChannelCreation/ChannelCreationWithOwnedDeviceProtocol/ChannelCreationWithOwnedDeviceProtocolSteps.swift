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

extension ChannelCreationWithOwnedDeviceProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case sendPing = 0
        case sendPingOrEphemeralKey = 1
        case recoverK1AndSendK2AndCreateChannel = 2
        case confirmChannelAndSendAck = 3
        case sendEphemeralKeyAndK1 = 4
        case recoverK2CreateChannelAndSendAck = 5
        case confirmChannel = 6
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            case .sendPing:
                let step = SendPingStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .sendPingOrEphemeralKey:
                let step = SendPingOrEphemeralKeyStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .recoverK1AndSendK2AndCreateChannel:
                let step = RecoverK1AndSendK2AndCreateChannelStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .confirmChannelAndSendAck:
                let step = ConfirmChannelAndSendAckStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .sendEphemeralKeyAndK1:
                let step = SendEphemeralKeyAndK1Step(from: concreteProtocol, and: receivedMessage)
                return step
            case .recoverK2CreateChannelAndSendAck:
                let step = RecoverK2CreateChannelAndSendAckStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .confirmChannel:
                let step = ConfirmChannelStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
        
    }
    

    // MARK: - SendPingStep
    
    final class SendPingStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ChannelCreationWithOwnedDeviceProtocol.InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithOwnedDeviceProtocol.logCategory)

            let remoteDeviceUid = receivedMessage.remoteDeviceUid
            
            // Check that the remote device Uid is not the current device Uid
            
            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
            
            guard remoteDeviceUid != currentDeviceUid else {
                os_log("Trying to run a ChannelCreationWithOwnedDeviceProtocol with our currentDeviceUid", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }
            
            // Clean any ongoing instance of this protocol
            
            os_log("Cleaning any ongoing instances of the ChannelCreationWithOwnedDeviceProtocol", log: log, type: .debug)
            do {
                if try ChannelCreationWithOwnedDeviceProtocolInstance.exists(ownedCryptoIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid, within: obvContext) {
                    os_log("There exists a ChannelCreationWithOwnedDeviceProtocolInstance to clean", log: log, type: .debug)
                    let protocolInstanceUids = try ChannelCreationWithOwnedDeviceProtocolInstance.deleteAll(ownedCryptoIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid, within: obvContext)
                    for protocolInstanceUid in protocolInstanceUids {
                        os_log("The ChannelCreationWithOwnedDeviceProtocolInstance to clean has uid %{public}@", log: log, type: .debug, protocolInstanceUid.debugDescription)
                        let abortProtocolBlock = delegateManager.receivedMessageDelegate.createBlockForAbortingProtocol(withProtocolInstanceUid: protocolInstanceUid, forOwnedIdentity: ownedIdentity, within: obvContext)
                        os_log("Executing the block allowing to abort the protocol with instance uid %{public}@", log: log, type: .debug, protocolInstanceUid.debugDescription)
                        abortProtocolBlock()
                        os_log("The block allowing to clest the protocol with instance uid %{public}@ was executed", log: log, type: .debug, protocolInstanceUid.debugDescription)
                    }
                }
            } catch {
                os_log("Could not check whether a previous instance of this protocol exists, or could not delete it", log: log, type: .error)
                return CancelledState()
            }
            
            // Clear any already created ObliviousChannel
            
            do {
                try channelDelegate.deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: currentDeviceUid,
                                                                                     andTheRemoteDeviceWithUid: remoteDeviceUid,
                                                                                     ofRemoteIdentity: ownedIdentity,
                                                                                     within: obvContext)
            } catch {
                os_log("Could not delete previous oblivious channel", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }
            
            // Send a signed ping proving you trust the contact and have no channel with him
            
            let signature: Data
            do {
                let challengeType = ChallengeType.channelCreation(firstDeviceUid: remoteDeviceUid, secondDeviceUid: currentDeviceUid, firstIdentity: ownedIdentity, secondIdentity: ownedIdentity)
                guard let res = try? solveChallengeDelegate.solveChallenge(challengeType, for: ownedIdentity, using: prng, within: obvContext) else {
                    os_log("Could not solve challenge", log: log, type: .fault)
                    return CancelledState()
                }
                signature = res
            }
            
            // Send the ping message containing the signature
            
            do {
                let coreMessage = getCoreMessage(for: .asymmetricChannel(to: ownedIdentity, remoteDeviceUids: [remoteDeviceUid], fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = PingMessage(coreProtocolMessage: coreMessage, remoteDeviceUid: currentDeviceUid, signature: signature)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    return CancelledState()
                }
                
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post message", log: log, type: .fault)
                return CancelledState()
            }
            
            // Inform the identity manager about the ping sent to the remote owned device
            
            do {
                let deviceIdentifier = ObvOwnedDeviceIdentifier(ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedIdentity), deviceUID: remoteDeviceUid)
                try identityDelegate.setLatestChannelCreationPingTimestampOfRemoteOwnedDevice(withIdentifier: deviceIdentifier, to: Date.now, within: obvContext)
            } catch {
                os_log("🛟 [%{public}@] [ChannelCreationWithOwnedDeviceProtocol,SendPingStep] Failed to set the latest channel creation ping timestamp of remote owned device: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // In production continue anyway
            }

            // Return the new state
            
            return PingSentState()
            
        }
        
    }
    
    
    // MARK: - SendPingOrEphemeralKeyStep
    
    final class SendPingOrEphemeralKeyStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PingMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ChannelCreationWithOwnedDeviceProtocol.PingMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithOwnedDeviceProtocol.logCategory)

            let remoteDeviceUid = receivedMessage.remoteDeviceUid
            let signature = receivedMessage.signature
            
            // Check that the remote device Uid is not the current device Uid
            
            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
            
            guard remoteDeviceUid != currentDeviceUid else {
                os_log("Trying to run a ChannelCreationWithOwnedDeviceProtocol with our currentDeviceUid", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }

            // Verify the signature
            
            let challengeType = ChallengeType.channelCreation(firstDeviceUid: currentDeviceUid, secondDeviceUid: remoteDeviceUid, firstIdentity: ownedIdentity, secondIdentity: ownedIdentity)
            guard ObvSolveChallengeStruct.checkResponse(signature, to: challengeType, from: ownedIdentity) else {
                os_log("The signature is invalid", log: log, type: .error)
                return CancelledState()
            }

            // If we reach this point, we have a valid signature => the remote device of our owned identity does not have an Oblivious channel with our current device
            
            // We make sure we are not facing a replay attack
            
            do {
                guard !(try ChannelCreationPingSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity,
                                                                        signature: signature,
                                                                        within: obvContext)) else {
                    os_log("The signature received was already received in a previous protocol message. This should not happen but with a negligible probability. We cancel.", log: log, type: .fault)
                    return CancelledState()
                }
            } catch {
                os_log("We could not perform check whether the signature was already received: %{public}@", log: log, type: .fault, error.localizedDescription)
                return CancelledState()
            }
            
            guard ChannelCreationPingSignatureReceived(ownedCryptoIdentity: ownedIdentity,
                                                       signature: signature,
                                                       within: obvContext) != nil else {
                os_log("We could not insert a new ChannelCreationPingSignatureReceived entry", log: log, type: .fault)
                return CancelledState()
            }
            
            // Clean any ongoing instance of this protocol
            
            do {
                if try ChannelCreationWithOwnedDeviceProtocolInstance.exists(ownedCryptoIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid, within: obvContext) {
                    let protocolInstanceUids = try ChannelCreationWithOwnedDeviceProtocolInstance.deleteAll(ownedCryptoIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid, within: obvContext)
                        for protocolInstanceUid in protocolInstanceUids {
                        let abortProtocolBlock = delegateManager.receivedMessageDelegate.createBlockForAbortingProtocol(withProtocolInstanceUid: protocolInstanceUid, forOwnedIdentity: ownedIdentity, within: obvContext)
                        abortProtocolBlock()
                    }
                }
            } catch {
                os_log("Could not check whether a previous instance of this protocol exists, or could not delete it", log: log, type: .error)
                return CancelledState()
            }

            
            // Clear any already created ObliviousChannel
            
            do {
                try channelDelegate.deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: currentDeviceUid,
                                                                                     andTheRemoteDeviceWithUid: remoteDeviceUid,
                                                                                     ofRemoteIdentity: ownedIdentity,
                                                                                     within: obvContext)
            } catch {
                os_log("Could not delete previous oblivious channel", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }

            // Compute a signature to prove we trust the contact and don't have any channel/ongoing protocol with him

            let ownSignature: Data
            do {
                let challengeType = ChallengeType.channelCreation(firstDeviceUid: remoteDeviceUid, secondDeviceUid: currentDeviceUid, firstIdentity: ownedIdentity, secondIdentity: ownedIdentity)
                guard let res = try? solveChallengeDelegate.solveChallenge(challengeType, for: ownedIdentity, using: prng, within: obvContext) else {
                    os_log("Could not solve challenge (1)", log: log, type: .fault)
                    return CancelledState()
                }
                ownSignature = res
            }
            
            // If we are "in charge" (small device uid), send an ephemeral key.
            // Otherwise, simply send a ping back
            
            if currentDeviceUid >= remoteDeviceUid {
                
                os_log("We are *not* in charge of establishing the channel", log: log, type: .debug)
        
                // Send the ping message containing the signature
                
                do {
                    let coreMessage = getCoreMessage(for: .asymmetricChannel(to: ownedIdentity, remoteDeviceUids: [remoteDeviceUid], fromOwnedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PingMessage(coreProtocolMessage: coreMessage, remoteDeviceUid: currentDeviceUid, signature: ownSignature)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not post message", log: log, type: .fault)
                    return CancelledState()
                }
                
                // Inform the identity manager about the ping sent to the remote owned device
                
                do {
                    let deviceIdentifier = ObvOwnedDeviceIdentifier(ownedCryptoId: ObvCryptoId(cryptoIdentity: ownedIdentity), deviceUID: remoteDeviceUid)
                    try identityDelegate.setLatestChannelCreationPingTimestampOfRemoteOwnedDevice(withIdentifier: deviceIdentifier, to: Date.now, within: obvContext)
                } catch {
                    os_log("🛟 [%{public}@] [ChannelCreationWithOwnedDeviceProtocol,SendPingStep] Failed to set the latest channel creation ping timestamp of remote owned device: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // In production continue anyway
                }

                // Return the new state
                
                os_log("ChannelCreationWithOwnedDeviceProtocol: ending SendPingOrEphemeralKeyStep", log: log, type: .debug)
                return PingSentState()
                
            } else {
                
                os_log("We are in charge of establishing the channel", log: log, type: .debug)
                
                // We are in charge of establishing the channel.
                
                // Create a new ChannelCreationWithOwnedDeviceProtocolInstance entry in database
                
                _ = ChannelCreationWithOwnedDeviceProtocolInstance(protocolInstanceUid: protocolInstanceUid,
                                                                   ownedIdentity: ownedIdentity,
                                                                   remoteDeviceUid: remoteDeviceUid,
                                                                   delegateManager: delegateManager,
                                                                   within: obvContext)
                
                // Generate an ephemeral pair of encryption keys
                
                let ephemeralPublicKey: PublicKeyForPublicKeyEncryption
                let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
                do {
                    let PublicKeyEncryptionImplementation = ObvCryptoSuite.sharedInstance.getDefaultPublicKeyEncryptionImplementationByteId().algorithmImplementation
                    (ephemeralPublicKey, ephemeralPrivateKey) = PublicKeyEncryptionImplementation.generateKeyPair(with: prng)
                }
                
                // Send the public key to Bob, together with our own identity and current device uid
                
                do {
                    let coreMessage = getCoreMessage(for: .asymmetricChannel(to: ownedIdentity, remoteDeviceUids: [remoteDeviceUid], fromOwnedIdentity: ownedIdentity))
                    let concreteProtocolMessage = AliceIdentityAndEphemeralKeyMessage(coreProtocolMessage: coreMessage,
                                                                                      remoteDeviceUid: currentDeviceUid,
                                                                                      signature: ownSignature,
                                                                                      remoteEphemeralPublicKey: ephemeralPublicKey)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return WaitingForK1State(remoteDeviceUid: remoteDeviceUid, ephemeralPrivateKey: ephemeralPrivateKey)
                
            }
        }
    }
    
    
    // MARK: - SendEphemeralKeyAndK1Step
    
    final class SendEphemeralKeyAndK1Step: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: AliceIdentityAndEphemeralKeyMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ChannelCreationWithOwnedDeviceProtocol.AliceIdentityAndEphemeralKeyMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithOwnedDeviceProtocol.logCategory)

            let remoteDeviceUid = receivedMessage.remoteDeviceUid
            let remoteEphemeralPublicKey = receivedMessage.remoteEphemeralPublicKey
            let signature = receivedMessage.signature
            
            // Check that the remote device Uid is not the current device Uid
            
            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
            
            guard remoteDeviceUid != currentDeviceUid else {
                os_log("Trying to run a ChannelCreationWithOwnedDeviceProtocol with our currentDeviceUid", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }

            // Verify the signature
            
            do {
                let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
                let challengeType = ChallengeType.channelCreation(firstDeviceUid: currentDeviceUid, secondDeviceUid: remoteDeviceUid, firstIdentity: ownedIdentity, secondIdentity: ownedIdentity)
                guard ObvSolveChallengeStruct.checkResponse(signature, to: challengeType, from: ownedIdentity) else {
                    os_log("The signature is invalid", log: log, type: .error)
                    return CancelledState()
                }
            } catch {
                os_log("Could not check the signature", log: log, type: .fault)
                return CancelledState()
            }

            // If we reach this point, we have a valid signature => we have no Oblivious channel with our owned remote device

            // We make sure we are not facing a replay attack
            
            do {
                guard !(try ChannelCreationPingSignatureReceived.exists(ownedCryptoIdentity: ownedIdentity,
                                                                        signature: signature,
                                                                        within: obvContext)) else {
                    os_log("The signature received was already received in a previous protocol message. This should not happen but with a negligible probability. We cancel.", log: log, type: .fault)
                    assertionFailure()
                    return CancelledState()
                }
            } catch {
                os_log("We could not perform check whether the signature was already received: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return CancelledState()
            }

            // Check whether there already is an instance of this protocol running. If this is the case, abort it, terminate this protocol, and restart it with a fresh ping.
            
            do {
                if try ChannelCreationWithOwnedDeviceProtocolInstance.exists(ownedCryptoIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid, within: obvContext) {
                    os_log("A previous ChannelCreationWithOwnedDeviceProtocolInstance exists. We abort it", log: log, type: .info)
                    let protocolInstanceUids = try ChannelCreationWithOwnedDeviceProtocolInstance.deleteAll(ownedCryptoIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid, within: obvContext)
                    for protocolInstanceUid in protocolInstanceUids {
                        let abortProtocolBlock = delegateManager.receivedMessageDelegate.createBlockForAbortingProtocol(withProtocolInstanceUid: protocolInstanceUid, forOwnedIdentity: ownedIdentity, within: obvContext)
                        abortProtocolBlock()
                    }
                    
                    let initialMessageToSend = try protocolStarterDelegate.getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid)
                    _ = try channelDelegate.postChannelMessage(initialMessageToSend, randomizedWith: prng, within: obvContext)
                    
                    return CancelledState()
                }
            } catch {
                os_log("Could not check whether a previous instance of this protocol exists, could not delete it, or could not initiate new ChannelCreationWithOwnedDeviceProtocol", log: log, type: .error)
                return CancelledState()
            }

            // If we reach this point, there was no previous instance of this protocol. We create it now
            
            _ = ChannelCreationWithOwnedDeviceProtocolInstance(protocolInstanceUid: protocolInstanceUid,
                                                               ownedIdentity: ownedIdentity,
                                                               remoteDeviceUid: remoteDeviceUid,
                                                               delegateManager: delegateManager,
                                                               within: obvContext)
            
            // Generate an ephemeral pair of encryption keys
            
            let ephemeralPublicKey: PublicKeyForPublicKeyEncryption
            let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
            do {
                let PublicKeyEncryptionImplementation = ObvCryptoSuite.sharedInstance.getDefaultPublicKeyEncryptionImplementationByteId().algorithmImplementation
                (ephemeralPublicKey, ephemeralPrivateKey) = PublicKeyEncryptionImplementation.generateKeyPair(with: prng)
            }

            // Generate k1
            
            guard let (c1, k1) = PublicKeyEncryption.kemEncrypt(using: remoteEphemeralPublicKey, with: prng) else {
                assertionFailure()
                os_log("Could not perform encryption using remote ephemeral public key", log: log, type: .error)
                return CancelledState()
            }
            
            // Send the ephemeral public key and k1 to Alice
            
            do {
                let coreMessage = getCoreMessage(for: .asymmetricChannel(to: ownedIdentity, remoteDeviceUids: [remoteDeviceUid], fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = BobEphemeralKeyAndK1Message(coreProtocolMessage: coreMessage,
                                                                          remoteEphemeralPublicKey: ephemeralPublicKey,
                                                                          c1: c1)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
            return WaitingForK2State(remoteDeviceUid: remoteDeviceUid, ephemeralPrivateKey: ephemeralPrivateKey, k1: k1)

        }
    }
    
    
    // MARK: - RecoverK1AndSendK2AndCreateChannelStep
    
    final class RecoverK1AndSendK2AndCreateChannelStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForK1State
        let receivedMessage: BobEphemeralKeyAndK1Message
        
        init?(startState: WaitingForK1State, receivedMessage: ChannelCreationWithOwnedDeviceProtocol.BobEphemeralKeyAndK1Message, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithOwnedDeviceProtocol.logCategory)

            let remoteDeviceUid = startState.remoteDeviceUid
            let ephemeralPrivateKey = startState.ephemeralPrivateKey

            let remoteEphemeralPublicKey = receivedMessage.remoteEphemeralPublicKey
            let c1 = receivedMessage.c1
            
            // Check that the remote device Uid is not the current device Uid
            
            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
            
            guard remoteDeviceUid != currentDeviceUid else {
                os_log("Trying to run a ChannelCreationWithOwnedDeviceProtocol with our currentDeviceUid", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }

            // Recover k1
            
            guard let k1 = PublicKeyEncryption.kemDecrypt(c1, using: ephemeralPrivateKey) else {
                    os_log("Could not recover k1", log: log, type: .error)
                    return CancelledState()
            }

            // Generate k2
            
            guard let (c2, k2) = PublicKeyEncryption.kemEncrypt(using: remoteEphemeralPublicKey, with: prng) else {
                assertionFailure()
                os_log("Could not perform encryption using remote ephemeral public key", log: log, type: .error)
                return CancelledState()
            }

            // Add the remoteDeviceUid for this owned identity (if it was not already there)
            
            do {
                try identityDelegate.addOtherDeviceForOwnedIdentity(ownedIdentity, withUid: remoteDeviceUid, createdDuringChannelCreation: true, within: obvContext)
            } catch {
                os_log("Could not add the device uid to the list of device uids of the contact identity", log: log, type: .fault)
                assertionFailure()
                // Continue anyway
            }
            
            // At this point, if a channel exist (rare case), we cannot create a new one. If this occurs:
            // - We destroy it (as we are in a situation where we know we should create a new one)
            // - Since we want to restart this protocol, we clean the ChannelCreationWithOwnedDeviceProtocolInstance entry
            // - We send a ping to restart the whole process of creating a channel
            // - We finish this protocol instance

            guard try !channelDelegate.anObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: ownedIdentity, withRemoteDeviceUid: remoteDeviceUid, within: obvContext) else {
                try channelDelegate.deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: currentDeviceUid,
                                                                                     andTheRemoteDeviceWithUid: remoteDeviceUid,
                                                                                     ofRemoteIdentity: ownedIdentity,
                                                                                     within: obvContext)
                _ = try ChannelCreationWithOwnedDeviceProtocolInstance.deleteAll(ownedCryptoIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid, within: obvContext)
                let initialMessageToSend = try delegateManager.protocolStarterDelegate.getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid)
                _ = try channelDelegate.postChannelMessage(initialMessageToSend, randomizedWith: prng, within: obvContext)
                return CancelledState()
            }

            // Create the Oblivious Channel using the seed derived from k1 and k2
            
            do {
                guard let seed = Seed(withKeys: [k1, k2]) else {
                    os_log("Could not initialize seed for Oblivious Channel", log: log, type: .error)
                    return CancelledState()
                }
                let cryptoSuiteVersion = 0
                try channelDelegate.createObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                    andRemoteIdentity: ownedIdentity,
                                                                                    withRemoteDeviceUid: remoteDeviceUid,
                                                                                    with: seed,
                                                                                    cryptoSuiteVersion: cryptoSuiteVersion,
                                                                                    within: obvContext)
            }

            // Send the k2 to Bob
            
            do {
                let coreMessage = getCoreMessage(for: .asymmetricChannel(to: ownedIdentity, remoteDeviceUids: [remoteDeviceUid], fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = K2Message(coreProtocolMessage: coreMessage, c2: c2)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
            return WaitForFirstAckState(remoteDeviceUid: remoteDeviceUid)

        }
    }
    
    
    // MARK: - RecoverK2CreateChannelAndSendAckStep
    
    final class RecoverK2CreateChannelAndSendAckStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForK2State
        let receivedMessage: K2Message
        
        init?(startState: WaitingForK2State, receivedMessage: ChannelCreationWithOwnedDeviceProtocol.K2Message, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .asymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithOwnedDeviceProtocol.logCategory)

            let remoteDeviceUid = startState.remoteDeviceUid
            let ephemeralPrivateKey = startState.ephemeralPrivateKey
            let k1 = startState.k1
            
            let c2 = receivedMessage.c2
            
            // Check that the remote device Uid is not the current device Uid
            
            let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
            
            guard remoteDeviceUid != currentDeviceUid else {
                os_log("Trying to run a ChannelCreationWithOwnedDeviceProtocol with our currentDeviceUid", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }

            // Recover k2
            
            guard let k2 = PublicKeyEncryption.kemDecrypt(c2, using: ephemeralPrivateKey) else {
                os_log("Could not recover k2", log: log, type: .error)
                return CancelledState()
            }
            
            // Add the remoteDeviceUid for this owned identity (if it was not already there)
            
            do {
                try identityDelegate.addOtherDeviceForOwnedIdentity(ownedIdentity, withUid: remoteDeviceUid, createdDuringChannelCreation: true, within: obvContext)
            } catch {
                os_log("Could not add the device uid to the list of device uids of the contact identity", log: log, type: .fault)
                assertionFailure()
                // Continue anyway
            }

            // Create the seed that will allow to create the Oblivious Channel
            
            guard let seed = Seed(withKeys: [k1, k2]) else {
                os_log("Could not initialize seed for Oblivious Channel", log: log, type: .error)
                return CancelledState()
            }
            
            // At this point, if a channel exist (rare case), we cannot create a new one. If this occurs:
            // - We destroy it (as we are in a situation where we know we should create a new one)
            // - Since we want to restart this protocol, we clean the ChannelCreationWithOwnedDeviceProtocolInstance entry
            // - We send a ping to restart the whole process of creating a channel
            // - We finish this protocol instance

            guard try !channelDelegate.anObliviousChannelExistsBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity, andRemoteIdentity: ownedIdentity, withRemoteDeviceUid: remoteDeviceUid, within: obvContext) else {
                try channelDelegate.deleteObliviousChannelBetweenCurentDeviceWithUid(currentDeviceUid: currentDeviceUid,
                                                                                     andTheRemoteDeviceWithUid: remoteDeviceUid,
                                                                                     ofRemoteIdentity: ownedIdentity,
                                                                                     within: obvContext)
                _ = try ChannelCreationWithOwnedDeviceProtocolInstance.deleteAll(ownedCryptoIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid, within: obvContext)
                let initialMessageToSend = try delegateManager.protocolStarterDelegate.getInitialMessageForChannelCreationWithOwnedDeviceProtocol(ownedIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid)
                _ = try channelDelegate.postChannelMessage(initialMessageToSend, randomizedWith: prng, within: obvContext)
                return CancelledState()
            }

            // If reach this point, there is no existing channel between our current device and the contact device.
            // We create the Oblivious Channel using the seed.
                        
            do {
                let cryptoSuiteVersion = 0
                try channelDelegate.createObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                    andRemoteIdentity: ownedIdentity,
                                                                                    withRemoteDeviceUid: remoteDeviceUid,
                                                                                    with: seed,
                                                                                    cryptoSuiteVersion: cryptoSuiteVersion,
                                                                                    within: obvContext)
            }
            
            // Send the message trigerring the next step, where we check that the contact identity is trusted and create the oblivious channel if this is the case
                        
            do {
                let channelType = ObvChannelSendChannelType.obliviousChannel(to: ownedIdentity, 
                                                                             remoteDeviceUids: [remoteDeviceUid],
                                                                             fromOwnedIdentity: ownedIdentity,
                                                                             necessarilyConfirmed: false,
                                                                             usePreKeyIfRequired: false)
                let coreMessage = getCoreMessage(for: channelType)
                let (ownedIdentityDetailsElements, _) = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext)
                let concreteProtocolMessage = FirstAckMessage(coreProtocolMessage: coreMessage, remoteIdentityDetailsElements: ownedIdentityDetailsElements)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post ack message", log: log, type: .fault)
                return CancelledState()
            }
            
            // Return the new state
            
            return WaitForSecondAckState(remoteDeviceUid: remoteDeviceUid)
            
        }
    }
    
    
    // MARK: - ConfirmChannelAndSendAckStep
    
    final class ConfirmChannelAndSendAckStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitForFirstAckState
        let receivedMessage: FirstAckMessage
        
        init?(startState: WaitForFirstAckState, receivedMessage: ChannelCreationWithOwnedDeviceProtocol.FirstAckMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .obliviousChannel(remoteCryptoIdentity: concreteCryptoProtocol.ownedIdentity,
                                                                       remoteDeviceUid: startState.remoteDeviceUid),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithOwnedDeviceProtocol.logCategory)

            let remoteDeviceUid = startState.remoteDeviceUid
            let remoteIdentityDetailsElements = receivedMessage.remoteIdentityDetailsElements
            
            // Confirm the Oblivious Channel
            
            do {
                try channelDelegate.confirmObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                     andRemoteIdentity: ownedIdentity,
                                                                                     withRemoteDeviceUid: remoteDeviceUid,
                                                                                     within: obvContext)
            } catch {
                os_log("Could not confirm Oblivious channel", log: log, type: .error)
                return CancelledState()
            }
            
            // Update the published details with the remote details if they are newer. In that case, we might need to re-download the photo
                      
            let photoDownloadNeeded: Bool
            do {
                photoDownloadNeeded = try identityDelegate.updateOwnedPublishedDetailsWithOtherDetailsIfNewer(ownedIdentity, with: remoteIdentityDetailsElements, within: obvContext)
            } catch {
                os_log("Failed to update owned published details with other details: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                photoDownloadNeeded = false
                // In production, continue
            }

            do {
                if photoDownloadNeeded {
                    let childProtocolInstanceUid = UID.gen(with: prng)
                    let coreMessage = getCoreMessageForOtherLocalProtocol(
                        otherCryptoProtocolId: .downloadIdentityPhoto,
                        otherProtocolInstanceUid: childProtocolInstanceUid)
                    let childProtocolInitialMessage = DownloadIdentityPhotoChildProtocol.InitialMessage(
                        coreProtocolMessage: coreMessage,
                        contactIdentity: ownedIdentity,
                        contactIdentityDetailsElements: remoteIdentityDetailsElements)
                    guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
            } catch {
                os_log("Failed to request the download of the new owned profile picture: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // In production, continue
            }
            
            // Delete the ChannelCreationProtocolInstance
            
            do {
                _ = try ChannelCreationWithOwnedDeviceProtocolInstance.deleteAll(ownedCryptoIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid, within: obvContext)
            } catch {
                os_log("Could not delete the ChannelCreationWithOwnedDeviceProtocolInstance", log: log, type: .fault)
                return CancelledState()
            }
            
            // Send ack to Bob
            
            do {
                let channelType = ObvChannelSendChannelType.obliviousChannel(to: ownedIdentity,
                                                                             remoteDeviceUids: [remoteDeviceUid],
                                                                             fromOwnedIdentity: ownedIdentity,
                                                                             necessarilyConfirmed: true,
                                                                             usePreKeyIfRequired: false)
                let coreMessage = getCoreMessage(for: channelType)
                let (ownedIdentityDetailsElements, _) = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext)
                let concreteProtocolMessage = SecondAckMessage(coreProtocolMessage: coreMessage, remoteIdentityDetailsElements: ownedIdentityDetailsElements)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post ack message", log: log, type: .fault)
                return CancelledState()
            }
            
            // Make sure this device capabilities are sent to Bob's device
            
            do {
                let channel = ObvChannelSendChannelType.local(ownedIdentity: ownedIdentity)
                let newProtocolInstanceUid = UID.gen(with: prng)
                let coreMessage = CoreProtocolMessage(channelType: channel,
                                                      cryptoProtocolId: .contactCapabilitiesDiscovery,
                                                      protocolInstanceUid: newProtocolInstanceUid)
                let message = DeviceCapabilitiesDiscoveryProtocol.InitialSingleOwnedDeviceMessage(
                    coreProtocolMessage: coreMessage,
                    otherOwnedDeviceUid: remoteDeviceUid,
                    isResponse: false)
                guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw Self.makeError(message: "Implementation error")
                }
                do {
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Failed to inform our contact of the current device capabilities", log: log, type: .fault)
                    assertionFailure()
                    // Continue anyway
                }
            }
            
            // Initiate a device synchronization protocol (that will be in an ongoing state for the lifetime of the new other device)
            
//            do {
//                let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
//                let protocolInstanceUid = try SynchronizationProtocol.computeOngoingProtocolInstanceUid(ownedCryptoId: ownedIdentity, currentDeviceUid: currentDeviceUid, otherOwnedDeviceUid: remoteDeviceUid)
//                let coreMessage = CoreProtocolMessage(
//                    channelType: .Local(ownedIdentity: ownedIdentity),
//                    cryptoProtocolId: .synchronization,
//                    protocolInstanceUid: protocolInstanceUid)
//                let concreteProtocolMessage = SynchronizationProtocol.InitiateSyncSnapshotMessage(coreProtocolMessage: coreMessage, otherOwnedDeviceUID: remoteDeviceUid)
//                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure();  return nil }
//                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
//            }

            // Return the new state
            
            return ChannelConfirmedState()
            
        }
    }

    
    // MARK: - ConfirmChannelStep
    
    final class ConfirmChannelStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitForSecondAckState
        let receivedMessage: SecondAckMessage
        
        init?(startState: WaitForSecondAckState, receivedMessage: ChannelCreationWithOwnedDeviceProtocol.SecondAckMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .obliviousChannel(remoteCryptoIdentity: concreteCryptoProtocol.ownedIdentity,
                                                                       remoteDeviceUid: startState.remoteDeviceUid),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithOwnedDeviceProtocol.logCategory)

            let remoteDeviceUid = startState.remoteDeviceUid
            let remoteIdentityDetailsElements = receivedMessage.remoteIdentityDetailsElements
            
            // Confirm the Oblivious Channel
            
            do {
                try channelDelegate.confirmObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                     andRemoteIdentity: ownedIdentity,
                                                                                     withRemoteDeviceUid: remoteDeviceUid,
                                                                                     within: obvContext)
            } catch {
                os_log("Could not confirm Oblivious channel", log: log, type: .fault)
                return CancelledState()
            }
            
            // Update the published details with the remote details if they are newer. In that case, we might need to re-download the photo
                      
            let photoDownloadNeeded: Bool
            do {
                photoDownloadNeeded = try identityDelegate.updateOwnedPublishedDetailsWithOtherDetailsIfNewer(ownedIdentity, with: remoteIdentityDetailsElements, within: obvContext)
            } catch {
                os_log("Failed to update owned published details with other details: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                photoDownloadNeeded = false
                // In production, continue
            }

            do {
                if photoDownloadNeeded {
                    let childProtocolInstanceUid = UID.gen(with: prng)
                    let coreMessage = getCoreMessageForOtherLocalProtocol(
                        otherCryptoProtocolId: .downloadIdentityPhoto,
                        otherProtocolInstanceUid: childProtocolInstanceUid)
                    let childProtocolInitialMessage = DownloadIdentityPhotoChildProtocol.InitialMessage(
                        coreProtocolMessage: coreMessage,
                        contactIdentity: ownedIdentity,
                        contactIdentityDetailsElements: remoteIdentityDetailsElements)
                    guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                        assertionFailure()
                        throw Self.makeError(message: "Could not generate ObvChannelProtocolMessageToSend")
                    }
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                }
            } catch {
                os_log("Failed to request the download of the new owned profile picture: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                // In production, continue
            }

            // Delete the ChannelCreationProtocolInstance
            
            do {
                _ = try ChannelCreationWithOwnedDeviceProtocolInstance.deleteAll(ownedCryptoIdentity: ownedIdentity, remoteDeviceUid: remoteDeviceUid, within: obvContext)
            } catch {
                os_log("Could not delete the ChannelCreationWithOwnedDeviceProtocolInstance", log: log, type: .fault)
                return CancelledState()
            }

            // Make sure this device capabilities are sent to Alice's device
            
            do {
                let channel = ObvChannelSendChannelType.local(ownedIdentity: ownedIdentity)
                let newProtocolInstanceUid = UID.gen(with: prng)
                let coreMessage = CoreProtocolMessage(channelType: channel,
                                                      cryptoProtocolId: .contactCapabilitiesDiscovery,
                                                      protocolInstanceUid: newProtocolInstanceUid)
                let message = DeviceCapabilitiesDiscoveryProtocol.InitialSingleOwnedDeviceMessage(
                    coreProtocolMessage: coreMessage,
                    otherOwnedDeviceUid: remoteDeviceUid,
                    isResponse: false)
                guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw Self.makeError(message: "Implementation error")
                }
                do {
                    _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Failed to inform our contact of the current device capabilities", log: log, type: .fault)
                    assertionFailure()
                    // Continue anyway
                }
            }

            // Initiate a device synchronization protocol (that will be in an ongoing state for the lifetime of the new other device)
            
//            do {
//                let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
//                let protocolInstanceUid = try SynchronizationProtocol.computeOngoingProtocolInstanceUid(ownedCryptoId: ownedIdentity, currentDeviceUid: currentDeviceUid, otherOwnedDeviceUid: remoteDeviceUid)
//                let coreMessage = CoreProtocolMessage(
//                    channelType: .Local(ownedIdentity: ownedIdentity),
//                    cryptoProtocolId: .synchronization,
//                    protocolInstanceUid: protocolInstanceUid)
//                let concreteProtocolMessage = SynchronizationProtocol.InitiateSyncSnapshotMessage(coreProtocolMessage: coreMessage, otherOwnedDeviceUID: remoteDeviceUid)
//                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { assertionFailure();  return nil }
//                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
//            }
            
            // Return the new state
            
            return ChannelConfirmedState()
            
        }
    }

}
