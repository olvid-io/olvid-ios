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

extension ChannelCreationWithContactDeviceProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId {
        
        case SendPing = 0
        case SendPingOrEphemeralKey = 1
        case RecoverK1AndSendK2AndCreateChannel = 2
        case ConfirmChannelAndSendAck = 3
        case SendEphemeralKeyAndK1 = 4
        case RecoverK2CreateChannelAndSendAck = 5
        case ConfirmChannel = 6
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            case .SendPing:
                let step = SendPingStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .SendPingOrEphemeralKey:
                let step = SendPingOrEphemeralKeyStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .RecoverK1AndSendK2AndCreateChannel:
                let step = RecoverK1AndSendK2AndCreateChannelStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ConfirmChannelAndSendAck:
                let step = ConfirmChannelAndSendAckStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .SendEphemeralKeyAndK1:
                let step = SendEphemeralKeyAndK1Step(from: concreteProtocol, and: receivedMessage)
                return step
            case .RecoverK2CreateChannelAndSendAck:
                let step = RecoverK2CreateChannelAndSendAckStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .ConfirmChannel:
                let step = ConfirmChannelStep(from: concreteProtocol, and: receivedMessage)
                return step
            }
        }
        
    }
    

    // MARK: - SendPingStep
    
    final class SendPingStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ChannelCreationWithContactDeviceProtocol.InitialMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithContactDeviceProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            let contactDeviceUid = receivedMessage.contactDeviceUid
            
            // Check that the contact identity is trusted by the owned identity running this protocol, i.e., check that the contact identity is part of the owned identity's contacts
            
            guard (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                os_log("The contact identity is not yet trusted", log: log, type: .error)
                return CancelledState()
            }
            
            guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) else {
                os_log("The contact identity is not active", log: log, type: .error)
                return CancelledState()
            }
            
            // Clean any ongoing instance of this protocol
            
            os_log("Cleaning any ongoing instances of the ChannelCreationWithContactDeviceProtocol", log: log, type: .debug)
            do {
                if try ChannelCreationWithContactDeviceProtocolInstance.exists(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, andOwnedIdentity: ownedIdentity, within: obvContext) {
                    os_log("There exists a ChannelCreationWithContactDeviceProtocolInstance to clean", log: log, type: .debug)
                    let protocolInstanceUid = try ChannelCreationWithContactDeviceProtocolInstance.delete(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, andOwnedIdentity: ownedIdentity, within: obvContext)
                    os_log("The ChannelCreationWithContactDeviceProtocolInstance to clean has uid %{public}@", log: log, type: .debug, protocolInstanceUid.debugDescription)
                    let abortProtocolBlock = delegateManager.receivedMessageDelegate.createBlockForAbortingProtocol(withProtocolInstanceUid: protocolInstanceUid, forOwnedIdentity: ownedIdentity, within: obvContext)
                    os_log("Executing the block allowing to abort the protocol with instance uid %{public}@", log: log, type: .debug, protocolInstanceUid.debugDescription)
                    abortProtocolBlock()
                    os_log("The block allowing to clest the protocol with instance uid %{public}@ was executed", log: log, type: .debug, protocolInstanceUid.debugDescription)
                }
            } catch {
                os_log("Could not check whether a previous instance of this protocol exists, or could not delete it", log: log, type: .error)
                return CancelledState()
            }
            
            // Clear any already created ObliviousChannel
            
            do {
                try channelDelegate.deleteObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                    andTheRemoteDeviceWithUid: contactDeviceUid,
                                                                                    ofRemoteIdentity: contactIdentity,
                                                                                    within: obvContext)
            } catch {
                os_log("Could not delete previous oblivious channel", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }
            
            // Get the current device uid
            
            let currentDeviceUid: UID
            do {
                currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not get the current device uid", log: log, type: .error)
                return CancelledState()
            }
            
            // Send a signed ping proving you trust the contact and have no channel with him
            
            let signature: Data
            do {
                let challengeType = ChallengeType.channelCreation(firstDeviceUid: contactDeviceUid, secondDeviceUid: currentDeviceUid, firstIdentity: contactIdentity, secondIdentity: ownedIdentity)
                guard let res = try? solveChallengeDelegate.solveChallenge(challengeType, for: ownedIdentity, using: prng, within: obvContext) else {
                    os_log("Could not solve challenge", log: log, type: .fault)
                    return CancelledState()
                }
                signature = res
            }
            
            // Send the ping message containing the signature
            
            do {
                let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: [contactDeviceUid], fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = PingMessage(coreProtocolMessage: coreMessage, contactIdentity: ownedIdentity, contactDeviceUid: currentDeviceUid, signature: signature)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                    return CancelledState()
                }
                
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post message", log: log, type: .fault)
                return CancelledState()
            }
            
            // Return the new state
            
            return PingSentState()
            
        }
        
    }
    
    
    // MARK: - SendPingOrEphemeralKeyStep
    
    final class SendPingOrEphemeralKeyStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: PingMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ChannelCreationWithContactDeviceProtocol.PingMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithContactDeviceProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            let contactDeviceUid = receivedMessage.contactDeviceUid
            let signature = receivedMessage.signature
            
            // Make sure the contact identity is trusted (i.e., is part of the ContactIdentity database of the owned identity)
            
            guard (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                os_log("The contact identity is not yet trusted", log: log, type: .debug)
                return CancelledState()
            }
            
            guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) else {
                os_log("The contact identity is not active", log: log, type: .error)
                return CancelledState()
            }

            // Verify the signature
            
            do {
                let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
                let challengeType = ChallengeType.channelCreation(firstDeviceUid: currentDeviceUid, secondDeviceUid: contactDeviceUid, firstIdentity: ownedIdentity, secondIdentity: contactIdentity)
                guard ObvSolveChallengeStruct.checkResponse(signature, to: challengeType, from: contactIdentity) else {
                    os_log("The signature is invalid", log: log, type: .error)
                    return CancelledState()
                }
            } catch {
                os_log("Could not check the signature", log: log, type: .fault)
                return CancelledState()
            }

            // If we reach this point, we have a valid signature => the contact trusts our identity, and she does not have an Oblivious channel with us
            
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
                if try ChannelCreationWithContactDeviceProtocolInstance.exists(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, andOwnedIdentity: ownedIdentity, within: obvContext) {
                    let protocolInstanceUid = try ChannelCreationWithContactDeviceProtocolInstance.delete(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, andOwnedIdentity: ownedIdentity, within: obvContext)
                    let abortProtocolBlock = delegateManager.receivedMessageDelegate.createBlockForAbortingProtocol(withProtocolInstanceUid: protocolInstanceUid, forOwnedIdentity: ownedIdentity, within: obvContext)
                    abortProtocolBlock()
                }
            } catch {
                os_log("Could not check whether a previous instance of this protocol exists, or could not delete it", log: log, type: .error)
                return CancelledState()
            }

            
            // Clear any already created ObliviousChannel
            
            do {
                try channelDelegate.deleteObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                    andTheRemoteDeviceWithUid: contactDeviceUid,
                                                                                    ofRemoteIdentity: contactIdentity,
                                                                                    within: obvContext)
            } catch {
                os_log("Could not delete previous oblivious channel", log: log, type: .fault)
                assertionFailure()
                return CancelledState()
            }

            // Get our own current device UID in order to compare it to the contact device UID
            
            guard let currentDeviceUid = try? identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext) else {
                os_log("Could not find current device uid", log: log, type: .fault)
                return CancelledState()
            }

            // Compute a signature to prove we trust the contact and don't have any channel/ongoing protocol with him

            let ownSignature: Data
            do {
                let challengeType = ChallengeType.channelCreation(firstDeviceUid: contactDeviceUid, secondDeviceUid: currentDeviceUid, firstIdentity: contactIdentity, secondIdentity: ownedIdentity)
                guard let res = try? solveChallengeDelegate.solveChallenge(challengeType, for: ownedIdentity, using: prng, within: obvContext) else {
                    os_log("Could not solve challenge (1)", log: log, type: .fault)
                    return CancelledState()
                }
                ownSignature = res
            }
            
            // If we are "in charge" (small device uid), send an ephemeral key.
            // Otherwise, simply send a ping back
            
            if currentDeviceUid >= contactDeviceUid || (currentDeviceUid == contactDeviceUid && ownedIdentity.getIdentity() >= contactIdentity.getIdentity()) {
                
                os_log("We are *not* in charge of establishing the channel", log: log, type: .debug)
        
                // Send the ping message containing the signature
                
                do {
                    let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: [contactDeviceUid], fromOwnedIdentity: ownedIdentity))
                    let concreteProtocolMessage = PingMessage(coreProtocolMessage: coreMessage, contactIdentity: ownedIdentity, contactDeviceUid: currentDeviceUid, signature: ownSignature)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Could not post message", log: log, type: .fault)
                    return CancelledState()
                }
                
                // Return the new state
                
                os_log("ChannelCreationWithContactDeviceProtocol: ending SendPingOrEphemeralKeyStep", log: log, type: .debug)
                return PingSentState()
                
            } else {
                
                os_log("We are in charge of establishing the channel", log: log, type: .debug)
                
                // We are in charge of establishing the channel.
                
                // Create a new ChannelCreationWithContactDeviceProtocolInstance entry in database
                
                _ = ChannelCreationWithContactDeviceProtocolInstance(protocolInstanceUid: protocolInstanceUid, ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, delegateManager: delegateManager, within: obvContext)
                
                // Generate an ephemeral pair of encryption keys
                
                let ephemeralPublicKey: PublicKeyForPublicKeyEncryption
                let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
                do {
                    let PublicKeyEncryptionImplementation = ObvCryptoSuite.sharedInstance.getDefaultPublicKeyEncryptionImplementationByteId().algorithmImplementation
                    (ephemeralPublicKey, ephemeralPrivateKey) = PublicKeyEncryptionImplementation.generateKeyPair(with: prng)
                }
                
                // Send the public key to Bob, together with our own identity and current device uid
                
                do {
                    let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: [contactDeviceUid], fromOwnedIdentity: ownedIdentity))
                    let concreteProtocolMessage = AliceIdentityAndEphemeralKeyMessage(coreProtocolMessage: coreMessage,
                                                                                      contactIdentity: ownedIdentity,
                                                                                      contactDeviceUid: currentDeviceUid,
                                                                                      signature: ownSignature,
                                                                                      contactEphemeralPublicKey: ephemeralPublicKey)
                    guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return WaitingForK1State(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, ephemeralPrivateKey: ephemeralPrivateKey)
                
            }
        }
    }
    
    
    // MARK: - SendEphemeralKeyAndK1Step
    
    final class SendEphemeralKeyAndK1Step: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: AliceIdentityAndEphemeralKeyMessage
        
        init?(startState: ConcreteProtocolInitialState, receivedMessage: ChannelCreationWithContactDeviceProtocol.AliceIdentityAndEphemeralKeyMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithContactDeviceProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            let contactDeviceUid = receivedMessage.contactDeviceUid
            let contactEphemeralPublicKey = receivedMessage.contactEphemeralPublicKey
            let signature = receivedMessage.signature
            
            // Make sure the contact identity is trusted (i.e., is part of the ContactIdentity database of the owned identity)
            
            guard (try? identityDelegate.isIdentity(contactIdentity, aContactIdentityOfTheOwnedIdentity: ownedIdentity, within: obvContext)) == true else {
                os_log("The contact identity is not yet trusted", log: log, type: .debug)
                return CancelledState()
            }
            
            guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) else {
                os_log("The contact identity is not active", log: log, type: .error)
                return CancelledState()
            }

            // Verify the signature
            
            do {
                let currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
                let challengeType = ChallengeType.channelCreation(firstDeviceUid: currentDeviceUid, secondDeviceUid: contactDeviceUid, firstIdentity: ownedIdentity, secondIdentity: contactIdentity)
                guard ObvSolveChallengeStruct.checkResponse(signature, to: challengeType, from: contactIdentity) else {
                    os_log("The signature is invalid", log: log, type: .error)
                    return CancelledState()
                }
            } catch {
                os_log("Could not check the signature", log: log, type: .fault)
                return CancelledState()
            }

            // If we reach this point, we have a valid signature => the contact trusts our identity, and she does not have an Oblivious channel with us

            // Check whether there already is an instance of this protocol running. If this is the case, abort it, terminate this protocol, and restart it with a fresh ping.
            
            do {
                if try ChannelCreationWithContactDeviceProtocolInstance.exists(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, andOwnedIdentity: ownedIdentity, within: obvContext) {
                    os_log("A previous ChannelCreationWithContactDeviceProtocolInstance exists. We abort it", log: log, type: .info)
                    let protocolInstanceUid = try ChannelCreationWithContactDeviceProtocolInstance.delete(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, andOwnedIdentity: ownedIdentity, within: obvContext)
                    let abortProtocolBlock = delegateManager.receivedMessageDelegate.createBlockForAbortingProtocol(withProtocolInstanceUid: protocolInstanceUid, forOwnedIdentity: ownedIdentity, within: obvContext)
                    abortProtocolBlock()
                    
                    let initialMessageToSend = try delegateManager.protocolStarterDelegate.getInitialMessageForChannelCreationWithContactDeviceProtocol(betweenTheCurrentDeviceOfOwnedIdentity: ownedIdentity, andTheDeviceUid: contactDeviceUid, ofTheContactIdentity: contactIdentity)
                    _ = try channelDelegate.post(initialMessageToSend, randomizedWith: prng, within: obvContext)
                    
                    return CancelledState()
                }
            } catch {
                os_log("Could not check whether a previous instance of this protocol exists, could not delete it, or could not initiate new ChannelCreationWithContactDeviceProtocol", log: log, type: .error)
                return CancelledState()
            }

            // If we reach this point, there was no previous instance of this protocol. We create it now
            
            _ = ChannelCreationWithContactDeviceProtocolInstance(protocolInstanceUid: protocolInstanceUid,
                                                                 ownedIdentity: ownedIdentity,
                                                                 contactIdentity: contactIdentity,
                                                                 contactDeviceUid: contactDeviceUid,
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
            
            let (c1, k1) = PublicKeyEncryption.kemEncrypt(using: contactEphemeralPublicKey, with: prng)
            
            // Send the ephemeral public key and k1 to Alice
            
            do {
                let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: [contactDeviceUid], fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = BobEphemeralKeyAndK1Message(coreProtocolMessage: coreMessage,
                                                                          contactEphemeralPublicKey: ephemeralPublicKey,
                                                                          c1: c1)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Return the new state
            
            return WaitingForK2State(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, ephemeralPrivateKey: ephemeralPrivateKey, k1: k1)
        }
    }
    
    
    // MARK: - RecoverK1AndSendK2AndCreateChannelStep
    
    final class RecoverK1AndSendK2AndCreateChannelStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForK1State
        let receivedMessage: BobEphemeralKeyAndK1Message
        
        init?(startState: WaitingForK1State, receivedMessage: ChannelCreationWithContactDeviceProtocol.BobEphemeralKeyAndK1Message, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithContactDeviceProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactDeviceUid = startState.contactDeviceUid
            let ephemeralPrivateKey = startState.ephemeralPrivateKey

            let contactEphemeralPublicKey = receivedMessage.contactEphemeralPublicKey
            let c1 = receivedMessage.c1
            
            // Recover k1
            
            guard let k1 = PublicKeyEncryption.kemDecrypt(c1, using: ephemeralPrivateKey) else {
                    os_log("Could not recover k1", log: log, type: .error)
                    return CancelledState()
            }

            // Generate k2
            
            let (c2, k2) = PublicKeyEncryption.kemEncrypt(using: contactEphemeralPublicKey, with: prng)

            // Check the contact is not revoked
            
            guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) else {
                os_log("The contact identity is not active", log: log, type: .error)
                return CancelledState()
            }
            
            // Add the deviceUid for this contact (if it was not already there), and also trigger a device discovery
            
            do {
                try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not add the device uid to the list of device uids of the contact identity", log: log, type: .fault)
                assertionFailure()
                // Continue anyway
            }
            
            let protocolInstanceUidForChildDeviceDiscoveryProtocol = UID.gen(with: prng)
            let coreMessage = CoreProtocolMessage(channelType: .Local(ownedIdentity: ownedIdentity),
                                                  cryptoProtocolId: .DeviceDiscoveryForContactIdentity,
                                                  protocolInstanceUid: protocolInstanceUidForChildDeviceDiscoveryProtocol)
            let concreteProtocolMessage = DeviceDiscoveryForContactIdentityProtocol.InitialMessage(coreProtocolMessage: coreMessage, contactIdentity: contactIdentity)
            guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else {
                os_log("Could not generate ObvChannelProtocolMessageToSend for an InitialMessage of a child DeviceDiscoveryForContactIdentityProtocol from within the ChannelCreationWithContactDeviceProtocol", log: log, type: .fault)
                return CancelledState()
            }
            
            do {
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post an initial message in order to trigger a (child) ChannelCreationWithContactDeviceProtocol", log: log, type: .error)
                // Continue anyway
            }

            // Create the Oblivious Channel using the seed derived from k1 and k2
            
            do {
                guard let seed = Seed(withKeys: [k1, k2]) else {
                    os_log("Could not initialize seed for Oblivious Channel", log: log, type: .error)
                    return CancelledState()
                }
                let cryptoSuiteVersion = 0
                try channelDelegate.createObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                    andRemoteIdentity: contactIdentity,
                                                                                    withRemoteDeviceUid: contactDeviceUid,
                                                                                    with: seed,
                                                                                    cryptoSuiteVersion: cryptoSuiteVersion,
                                                                                    within: obvContext)
            }

            // Send the k2 to Bob
            
            do {
                let coreMessage = getCoreMessage(for: .AsymmetricChannel(to: contactIdentity, remoteDeviceUids: [contactDeviceUid], fromOwnedIdentity: ownedIdentity))
                let concreteProtocolMessage = K2Message(coreProtocolMessage: coreMessage, c2: c2)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            }

            // Get our own current device UID
            
            guard let currentDeviceUid = try? identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext) else {
                os_log("Could not find current device uid", log: log, type: .fault)
                return CancelledState()
            }

            // Return the new state
            
            return WaitForFirstAckState(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, currentDeviceUid: currentDeviceUid)

        }
    }
    
    
    // MARK: - RecoverK2CreateChannelAndSendAckStep
    
    final class RecoverK2CreateChannelAndSendAckStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitingForK2State
        let receivedMessage: K2Message
        
        init?(startState: WaitingForK2State, receivedMessage: ChannelCreationWithContactDeviceProtocol.K2Message, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .AsymmetricChannel,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithContactDeviceProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactDeviceUid = startState.contactDeviceUid
            let ephemeralPrivateKey = startState.ephemeralPrivateKey
            let k1 = startState.k1
            
            let c2 = receivedMessage.c2
            
            // Recover k2
            
            guard let k2 = PublicKeyEncryption.kemDecrypt(c2, using: ephemeralPrivateKey) else {
                os_log("Could not recover k2", log: log, type: .error)
                return CancelledState()
            }
            
            // Check the contact is not revoked
            
            guard try identityDelegate.isContactIdentityActive(ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, within: obvContext) else {
                os_log("The contact identity is not active", log: log, type: .error)
                return CancelledState()
            }

            // Add the contact device uid to the contact identity (if needed)
            
            do {
                try identityDelegate.addDeviceForContactIdentity(contactIdentity, withUid: contactDeviceUid, ofOwnedIdentity: ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not add device uid to contact identity", log: log, type: .fault)
                return CancelledState()
            }
            
            // Create the seed that will allow to create the Oblivious Channel
            
            guard let seed = Seed(withKeys: [k1, k2]) else {
                os_log("Could not initialize seed for Oblivious Channel", log: log, type: .error)
                return CancelledState()
            }
            
            // Create the Oblivious Channel using the seed
            
            do {
                let cryptoSuiteVersion = 0
                try channelDelegate.createObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                    andRemoteIdentity: contactIdentity,
                                                                                    withRemoteDeviceUid: contactDeviceUid,
                                                                                    with: seed,
                                                                                    cryptoSuiteVersion: cryptoSuiteVersion,
                                                                                    within: obvContext)
            }
            
            // Send the message trigerring the next step, where we check that the contact identity is trusted and create the oblivious channel if this is the case
                        
            do {
                let coreMessage = getCoreMessage(for: .ObliviousChannel(to: contactIdentity, remoteDeviceUids: [contactDeviceUid], fromOwnedIdentity: ownedIdentity, necessarilyConfirmed: false))
                let (ownedIdentityDetailsElements, _) = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext)
                let concreteProtocolMessage = FirstAckMessage(coreProtocolMessage: coreMessage, contactIdentityDetailsElements: ownedIdentityDetailsElements)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post ack message", log: log, type: .fault)
                return CancelledState()
            }
            
            // Get our own current device UID
            
            guard let currentDeviceUid = try? identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext) else {
                os_log("Could not find current device uid", log: log, type: .fault)
                return CancelledState()
            }
            
            // Return the new state
            
            return WaitForSecondAckState(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, currentDeviceUid: currentDeviceUid)
            
        }
    }
    
    
    // MARK: - ConfirmChannelAndSendAckStep
    
    final class ConfirmChannelAndSendAckStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitForFirstAckState
        let receivedMessage: FirstAckMessage
        
        init?(startState: WaitForFirstAckState, receivedMessage: ChannelCreationWithContactDeviceProtocol.FirstAckMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .ObliviousChannel(remoteCryptoIdentity: startState.contactIdentity,
                                                                       remoteDeviceUid: startState.contactDeviceUid),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithContactDeviceProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactDeviceUid = startState.contactDeviceUid
            let contactIdentityDetailsElements = receivedMessage.contactIdentityDetailsElements
            
            // Confirm the Oblivious Channel
            
            do {
                try channelDelegate.confirmObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                     andRemoteIdentity: contactIdentity,
                                                                                     withRemoteDeviceUid: contactDeviceUid,
                                                                                     within: obvContext)
            } catch {
                os_log("Could not confirm Oblivious channel", log: log, type: .error)
                return CancelledState()
            }
            
            // Update the published details of the contact.
            
            do {
                try identityDelegate.updatePublishedIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, with: contactIdentityDetailsElements, allowVersionDowngrade: true, within: obvContext)
            } catch {
                os_log("Could not update the published identity details (1)", log: log, type: .fault)
                return CancelledState()
            }

            do {
                let appropriateDetails = try (identityDelegate.getPublishedIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext) ?? identityDelegate.getTrustedIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext))
                if appropriateDetails.photoURL == nil &&
                    appropriateDetails.contactIdentityDetailsElements.photoServerKeyAndLabel != nil {
                    let childProtocolInstanceUid = UID.gen(with: prng)
                    let coreMessage = getCoreMessageForOtherLocalProtocol(
                        otherCryptoProtocolId: .DownloadIdentityPhoto,
                        otherProtocolInstanceUid: childProtocolInstanceUid)
                    let childProtocolInitialMessage = DownloadIdentityPhotoChildProtocol.InitialMessage(
                        coreProtocolMessage: coreMessage,
                        contactIdentity: contactIdentity,
                        contactIdentityDetailsElements: contactIdentityDetailsElements)
                    guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    
                }
            } catch {
                os_log("Could get published/trusted identity details to check if a photo needs to be downloaded", log: log, type: .fault)
            }
            
            // Delete the ChannelCreationProtocolInstance
            
            do {
                _ = try ChannelCreationWithContactDeviceProtocolInstance.delete(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, andOwnedIdentity: ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not delete the ChannelCreationWithContactDeviceProtocolInstance", log: log, type: .fault)
                return CancelledState()
            }
            
            // Send ack to Bob
            
            do {
                let channelType = ObvChannelSendChannelType.ObliviousChannel(to: contactIdentity,
                                                                             remoteDeviceUids: [contactDeviceUid],
                                                                             fromOwnedIdentity: ownedIdentity,
                                                                             necessarilyConfirmed: true)
                let coreMessage = getCoreMessage(for: channelType)
                let (ownedIdentityDetailsElements, _) = try identityDelegate.getPublishedIdentityDetailsOfOwnedIdentity(ownedIdentity, within: obvContext)
                let concreteProtocolMessage = SecondAckMessage(coreProtocolMessage: coreMessage, contactIdentityDetailsElements: ownedIdentityDetailsElements)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post ack message", log: log, type: .fault)
                return CancelledState()
            }
            
            // Make sure this device capabilities are sent to Bob's device
            
            do {
                
                let channel = ObvChannelSendChannelType.Local(ownedIdentity: ownedIdentity)
                let newProtocolInstanceUid = UID.gen(with: prng)
                let coreMessage = CoreProtocolMessage(channelType: channel,
                                                      cryptoProtocolId: .ContactCapabilitiesDiscovery,
                                                      protocolInstanceUid: newProtocolInstanceUid)
                let message = DeviceCapabilitiesDiscoveryProtocol.InitialSingleContactDeviceMessage(coreProtocolMessage: coreMessage,
                                                                                                     contactIdentity: contactIdentity,
                                                                                                     contactDeviceUid: contactDeviceUid,
                                                                                                     isResponse: false)
                guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw Self.makeError(message: "Implementation error")
                }
                do {
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Failed to inform our contact of the current device capabilities", log: log, type: .fault)
                    assertionFailure()
                    // Continue anyway
                }

            }
            
            // Also make sure we agree on the OneToOne status. Note that we do not perform this check in the SendAckStep since performing it here is sufficient as
            // Our contact will reply if this is pertinent.

            do {
                
                let channel = ObvChannelSendChannelType.Local(ownedIdentity: ownedIdentity)
                let newProtocolInstanceUid = UID.gen(with: prng)
                let coreMessage = CoreProtocolMessage(channelType: channel,
                                                      cryptoProtocolId: .OneToOneContactInvitation,
                                                      protocolInstanceUid: newProtocolInstanceUid)
                let message = OneToOneContactInvitationProtocol.InitialOneToOneStatusSyncRequestMessage(coreProtocolMessage: coreMessage, contactsToSync: Set([contactIdentity]))
                guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw Self.makeError(message: "Implementation error")
                }
                do {
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Failed to request our own OneToOne status to our contact", log: log, type: .fault)
                    assertionFailure()
                    // Continue anyway
                }
                
            }

            // Return the new state
            
            return ChannelConfirmedState()
            
        }
    }

    
    // MARK: - ConfirmChannelStep
    
    final class ConfirmChannelStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: WaitForSecondAckState
        let receivedMessage: SecondAckMessage
        
        init?(startState: WaitForSecondAckState, receivedMessage: ChannelCreationWithContactDeviceProtocol.SecondAckMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .ObliviousChannel(remoteCryptoIdentity: startState.contactIdentity,
                                                                       remoteDeviceUid: startState.contactDeviceUid),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: ChannelCreationWithContactDeviceProtocol.logCategory)

            let contactIdentity = startState.contactIdentity
            let contactDeviceUid = startState.contactDeviceUid
            let contactIdentityDetailsElements = receivedMessage.contactIdentityDetailsElements
            
            // Confirm the Oblivious Channel
            
            do {
                try channelDelegate.confirmObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: ownedIdentity,
                                                                                     andRemoteIdentity: contactIdentity,
                                                                                     withRemoteDeviceUid: contactDeviceUid,
                                                                                     within: obvContext)
            } catch {
                os_log("Could not confirm Oblivious channel", log: log, type: .fault)
                return CancelledState()
            }
            
            // Update the published details of the contact. Automatically accept these details if they are identical to the trusted details
            
            do {
                try identityDelegate.updatePublishedIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, with: contactIdentityDetailsElements, allowVersionDowngrade: true, within: obvContext)
            } catch {
                os_log("Could not update the published identity details (2)", log: log, type: .fault)
                return CancelledState()
            }

            do {
                let appropriateDetails = try (identityDelegate.getPublishedIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext) ?? identityDelegate.getTrustedIdentityDetailsOfContactIdentity(contactIdentity, ofOwnedIdentity: ownedIdentity, within: obvContext))
                if appropriateDetails.photoURL == nil &&
                    appropriateDetails.contactIdentityDetailsElements.photoServerKeyAndLabel != nil {
                    let childProtocolInstanceUid = UID.gen(with: prng)
                    let coreMessage = getCoreMessageForOtherLocalProtocol(
                        otherCryptoProtocolId: .DownloadIdentityPhoto,
                        otherProtocolInstanceUid: childProtocolInstanceUid)
                    let childProtocolInitialMessage = DownloadIdentityPhotoChildProtocol.InitialMessage(
                        coreProtocolMessage: coreMessage,
                        contactIdentity: contactIdentity,
                        contactIdentityDetailsElements: contactIdentityDetailsElements)
                    guard let messageToSend = childProtocolInitialMessage.generateObvChannelProtocolMessageToSend(with: prng) else { throw NSError() }
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                    
                }
            } catch {
                os_log("Could get published/trusted identity details to check if a photo needs to be downloaded", log: log, type: .fault)
            }

            // Delete the ChannelCreationProtocolInstance
            
            do {
                _ = try ChannelCreationWithContactDeviceProtocolInstance.delete(contactIdentity: contactIdentity, contactDeviceUid: contactDeviceUid, andOwnedIdentity: ownedIdentity, within: obvContext)
            } catch {
                os_log("Could not delete the ChannelCreationWithContactDeviceProtocolInstance", log: log, type: .fault)
                return CancelledState()
            }

            // Make sure this device capabilities are sent to Alice's device
            
            do {
                
                let channel = ObvChannelSendChannelType.Local(ownedIdentity: ownedIdentity)
                let newProtocolInstanceUid = UID.gen(with: prng)
                let coreMessage = CoreProtocolMessage(channelType: channel,
                                                      cryptoProtocolId: .ContactCapabilitiesDiscovery,
                                                      protocolInstanceUid: newProtocolInstanceUid)
                let message = DeviceCapabilitiesDiscoveryProtocol.InitialSingleContactDeviceMessage(coreProtocolMessage: coreMessage,
                                                                                                     contactIdentity: contactIdentity,
                                                                                                     contactDeviceUid: contactDeviceUid,
                                                                                                     isResponse: false)
                guard let messageToSend = message.generateObvChannelProtocolMessageToSend(with: prng) else {
                    assertionFailure()
                    throw DeviceCapabilitiesDiscoveryProtocol.makeError(message: "Implementation error")
                }
                do {
                    _ = try channelDelegate.post(messageToSend, randomizedWith: prng, within: obvContext)
                } catch {
                    os_log("Failed to inform our contact of the current device capabilities", log: log, type: .fault)
                    assertionFailure()
                    // Continue anyway
                }

            }

            // Return the new state
            
            return ChannelConfirmedState()
            
        }
    }

}
