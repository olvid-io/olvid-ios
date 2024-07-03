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
import OlvidUtils
import ObvMetaManager


// MARK: - Protocol Steps

extension FullRatchetProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        case aliceSendEphemeralKey = 0 // Normal path
        case aliceResendEphemeralKeyFromAliceWaitingForK1State = 1
        case aliceResendEphemeralKeyFromAliceWaitingForAckState = 2
        case bobSendEphemeralKeyAndK1FromInitialState = 3 // Normal path
        case bobSendEphemeralKeyAndK1BobWaitingForK2State = 4
        case aliceRecoverK1AndSendK2 = 5 // Normal path
        case bobRecoverK2ToUpdateReceiveSeedAndSendAck = 6
        case aliceUpdateSendSeed = 7
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
            case .aliceSendEphemeralKey: return AliceSendEphemeralKeyStep(from: concreteProtocol, and: receivedMessage)
            case .aliceResendEphemeralKeyFromAliceWaitingForK1State: return AliceResendEphemeralKeyFromAliceWaitingForK1StateStep(from: concreteProtocol, and: receivedMessage)
            case .aliceResendEphemeralKeyFromAliceWaitingForAckState: return AliceResendEphemeralKeyFromAliceWaitingForAckStateStep(from: concreteProtocol, and: receivedMessage)
            case .bobSendEphemeralKeyAndK1FromInitialState: return BobSendEphemeralKeyAndK1FromInitialStateStep(from: concreteProtocol, and: receivedMessage)
            case .bobSendEphemeralKeyAndK1BobWaitingForK2State: return BobSendEphemeralKeyAndK1BobWaitingForK2StateStep(from: concreteProtocol, and: receivedMessage)
            case .aliceRecoverK1AndSendK2: return AliceRecoverK1AndSendK2Step(from: concreteProtocol, and: receivedMessage)
            case .bobRecoverK2ToUpdateReceiveSeedAndSendAck: return BobRecoverK2ToUpdateReceiveSeedAndSendAckStep(from: concreteProtocol, and: receivedMessage)
            case .aliceUpdateSendSeed: return AliceUpdateSendSeedStep(from: concreteProtocol, and: receivedMessage)
            }
        }
        
    }
    
    final class AliceSendEphemeralKeyStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitialMessage

        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: FullRatchetProtocol.logCategory)

            let contactIdentity = receivedMessage.contactIdentity
            let contactDeviceUid = receivedMessage.contactDeviceUid

            let nonce = FullRatchetProtocol.intFromData(prng.genBytes(count: 5)) // 40 bits
            let restartCounter = nonce << 23 // The msb is 0. This counter is 0 || nonce || 0...0
            
            // Generate an ephemeral pair of encryption keys
            
            let ephemeralPublicKey: PublicKeyForPublicKeyEncryption
            let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
            do {
                let PublicKeyEncryptionImplementation = ObvCryptoSuite.sharedInstance.getDefaultPublicKeyEncryptionImplementationByteId().algorithmImplementation
                (ephemeralPublicKey, ephemeralPrivateKey) = PublicKeyEncryptionImplementation.generateKeyPair(with: prng)
            }

            // Send the public key to Bob, together with our current device uid
            
            do {
                let channelType = ObvChannelSendChannelType.obliviousChannel(to: contactIdentity, 
                                                                             remoteDeviceUids: [contactDeviceUid],
                                                                             fromOwnedIdentity: ownedIdentity,
                                                                             necessarilyConfirmed: true,
                                                                             usePreKeyIfRequired: false)
                let coreMessage = getCoreMessage(for: channelType, partOfFullRatchetProtocolOfTheSendSeed: true)
                let concreteProtocolMessage = AliceEphemeralKeyMessage(coreProtocolMessage: coreMessage,
                                                                       contactEphemeralPublicKey: ephemeralPublicKey,
                                                                       restartCounter: restartCounter)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post AliceEphemeralKey message", log: log, type: .fault)
                return CancelledState()
            }

            // Return the new state
            
            return AliceWaitingForK1State(contactIdentity: contactIdentity,
                                          contactDeviceUid: contactDeviceUid,
                                          ephemeralPrivateKey: ephemeralPrivateKey,
                                          restartCounter: restartCounter)
        }
        
    }
    

    /// This Step is identical to the `AliceResendEphemeralKeyFromAliceWaitingForAckStateStep`, except from the start state
    final class AliceResendEphemeralKeyFromAliceWaitingForK1StateStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: AliceWaitingForK1State
        let receivedMessage: InitialMessage

        init?(startState: AliceWaitingForK1State, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: FullRatchetProtocol.logCategory)

            // We discard the ephemeral private key of that start state
            let contactIdentity = startState.contactIdentity
            let contactDeviceUid = startState.contactDeviceUid
            let previousRestartCounter = startState.restartCounter

            os_log("FullRatchetProtocol - AliceResendEphemeralKeyStep - Previous restart counter: %d", log: log, type: .info, previousRestartCounter)

            // Check consistency between the start state and the received message
            
            guard receivedMessage.contactIdentity == contactIdentity && receivedMessage.contactDeviceUid == contactDeviceUid else {
                os_log("The received message is inconsistent with the protocol state", log: log, type: .fault)
                return CancelledState()
            }
            
            let restartCounter = previousRestartCounter + 1
            
            // Generate an ephemeral pair of encryption keys
            
            let ephemeralPublicKey: PublicKeyForPublicKeyEncryption
            let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
            do {
                let PublicKeyEncryptionImplementation = ObvCryptoSuite.sharedInstance.getDefaultPublicKeyEncryptionImplementationByteId().algorithmImplementation
                (ephemeralPublicKey, ephemeralPrivateKey) = PublicKeyEncryptionImplementation.generateKeyPair(with: prng)
            }

            // Send the public key to Bob, together with our current device uid
            
            do {
                let channelType = ObvChannelSendChannelType.obliviousChannel(to: contactIdentity, 
                                                                             remoteDeviceUids: [contactDeviceUid],
                                                                             fromOwnedIdentity: ownedIdentity,
                                                                             necessarilyConfirmed: true,
                                                                             usePreKeyIfRequired: false)
                let coreMessage = getCoreMessage(for: channelType, partOfFullRatchetProtocolOfTheSendSeed: true)
                let concreteProtocolMessage = AliceEphemeralKeyMessage(coreProtocolMessage: coreMessage,
                                                                       contactEphemeralPublicKey: ephemeralPublicKey,
                                                                       restartCounter: restartCounter)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post AliceEphemeralKey message", log: log, type: .fault)
                return CancelledState()
            }
            
            // Return the new state
            
            return AliceWaitingForK1State(contactIdentity: contactIdentity,
                                          contactDeviceUid: contactDeviceUid,
                                          ephemeralPrivateKey: ephemeralPrivateKey,
                                          restartCounter: restartCounter)
        }
        
    }

    
    /// This Step is identical to the `AliceResendEphemeralKeyFromAliceWaitingForK1StateStep`, except from the start state
    final class AliceResendEphemeralKeyFromAliceWaitingForAckStateStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: AliceWaitingForAckState
        let receivedMessage: InitialMessage

        init?(startState: AliceWaitingForAckState, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: FullRatchetProtocol.logCategory)

            // We discard the ephemeral private key of that start state
            let contactIdentity = startState.contactIdentity
            let contactDeviceUid = startState.contactDeviceUid
            let previousRestartCounter = startState.restartCounter

            os_log("FullRatchetProtocol - AliceResendEphemeralKeyStep - Previous restart counter: %d", log: log, type: .info, previousRestartCounter)

            // Check consistency between the start state and the received message
            
            guard receivedMessage.contactIdentity == contactIdentity && receivedMessage.contactDeviceUid == contactDeviceUid else {
                os_log("The received message is inconsistent with the protocol state", log: log, type: .fault)
                return CancelledState()
            }
            
            let restartCounter = previousRestartCounter + 1
            
            // Generate an ephemeral pair of encryption keys
            
            let ephemeralPublicKey: PublicKeyForPublicKeyEncryption
            let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
            do {
                let PublicKeyEncryptionImplementation = ObvCryptoSuite.sharedInstance.getDefaultPublicKeyEncryptionImplementationByteId().algorithmImplementation
                (ephemeralPublicKey, ephemeralPrivateKey) = PublicKeyEncryptionImplementation.generateKeyPair(with: prng)
            }

            // Send the public key to Bob, together with our current device uid
            
            do {
                let channelType = ObvChannelSendChannelType.obliviousChannel(to: contactIdentity, 
                                                                             remoteDeviceUids: [contactDeviceUid],
                                                                             fromOwnedIdentity: ownedIdentity,
                                                                             necessarilyConfirmed: true,
                                                                             usePreKeyIfRequired: false)
                let coreMessage = getCoreMessage(for: channelType, partOfFullRatchetProtocolOfTheSendSeed: true)
                let concreteProtocolMessage = AliceEphemeralKeyMessage(coreProtocolMessage: coreMessage,
                                                                       contactEphemeralPublicKey: ephemeralPublicKey,
                                                                       restartCounter: restartCounter)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post AliceEphemeralKey message", log: log, type: .fault)
                return CancelledState()
            }
            
            // Return the new state
            
            return AliceWaitingForK1State(contactIdentity: contactIdentity,
                                          contactDeviceUid: contactDeviceUid,
                                          ephemeralPrivateKey: ephemeralPrivateKey,
                                          restartCounter: restartCounter)
        }
        
    }


    final class BobSendEphemeralKeyAndK1FromInitialStateStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: ConcreteProtocolInitialState
        let receivedMessage: AliceEphemeralKeyMessage

        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .anyObliviousChannel(ownedIdentity: concreteCryptoProtocol.ownedIdentity),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            let log = OSLog(subsystem: delegateManager.logSubsystem, category: FullRatchetProtocol.logCategory)
            
            // Since the BobSendEphemeralKeyAndK1FromInitialStateStep and the BobSendEphemeralKeyAndK1BobWaitingForK2StateStep are almost identical, we factorized most of the code into a helper function
            guard let helperValues = FullRatchetProtocol.bobSendEphemeralKeyAndK1StepHelper(receivedMessage: receivedMessage,
                                                                                            ownedIdentity: ownedIdentity,
                                                                                            delegateManager: delegateManager,
                                                                                            protocolInstanceUid: protocolInstanceUid,
                                                                                            prng: self.prng,
                                                                                            log: log,
                                                                                            within: obvContext)
                else {
                    return CancelledState()
            }
            
            let (remoteIdentity, contactDeviceUid, ephemeralPublicKey, ephemeralPrivateKey, c1, k1, restartCounter) = helperValues
            
            os_log("FullRatchetProtocol - BobSendEphemeralKeyAndK1FromInitialStateStep - restartCounter: %d", log: log, type: .info, restartCounter)
            
            // Send c1 to Alice
            
            do {
                let channelType = ObvChannelSendChannelType.obliviousChannel(to: remoteIdentity,
                                                                             remoteDeviceUids: [contactDeviceUid],
                                                                             fromOwnedIdentity: ownedIdentity,
                                                                             necessarilyConfirmed: true,
                                                                             usePreKeyIfRequired: false)
                let coreMessage = getCoreMessage(for: channelType, partOfFullRatchetProtocolOfTheSendSeed: false)
                let concreteProtocolMessage = BobEphemeralKeyAndK1Message(coreProtocolMessage: coreMessage,
                                                                          contactEphemeralPublicKey: ephemeralPublicKey,
                                                                          c1: c1,
                                                                          restartCounter: restartCounter)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post BobEphemeralKeyAndK1Message message", log: log, type: .fault)
                return CancelledState()
            }

            // Return the new state
            
            return BobWaitingForK2State(contactIdentity: remoteIdentity, contactDeviceUid: contactDeviceUid, ephemeralPrivateKey: ephemeralPrivateKey, restartCounter: restartCounter, k1: k1)
        }
        
    }

    
    /// This step is almost identical to BobSendEphemeralKeyAndK1FromInitialStateStep
    final class BobSendEphemeralKeyAndK1BobWaitingForK2StateStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: BobWaitingForK2State
        let receivedMessage: AliceEphemeralKeyMessage

        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .obliviousChannel(remoteCryptoIdentity: startState.contactIdentity, remoteDeviceUid: startState.contactDeviceUid),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: FullRatchetProtocol.logCategory)

            os_log("FullRatchetProtocol - BobSendEphemeralKeyAndK1BobWaitingForK2StateStep - Received restart counter: %d / Start state restart counter: %d", log: log, type: .info, receivedMessage.restartCounter, startState.restartCounter)

            let receivedNonce = receivedMessage.restartCounter >> 23
            let localNonce = startState.restartCounter >> 23
            guard receivedNonce != localNonce || receivedMessage.restartCounter > startState.restartCounter else {
                os_log("Receiving an AliceEphemeralKeyMessage with an old counter. We keep this protocol in the same state.", log: log, type: .info)
                return startState
            }
    
            // We do nothing with the remaining values of the start state since we are re-starting the protocol.
            
            // Since the BobSendEphemeralKeyAndK1FromInitialStateStep and the BobSendEphemeralKeyAndK1BobWaitingForK2StateStep are almost identical, we factorized most of the code into a helper function
            guard let helperValues = FullRatchetProtocol.bobSendEphemeralKeyAndK1StepHelper(receivedMessage: receivedMessage,
                                                                                            ownedIdentity: ownedIdentity,
                                                                                            delegateManager: delegateManager,
                                                                                            protocolInstanceUid: protocolInstanceUid,
                                                                                            prng: self.prng,
                                                                                            log: log,
                                                                                            within: obvContext)
                else {
                    return CancelledState()
            }
            
            let (remoteIdentity, contactDeviceUid, ephemeralPublicKey, ephemeralPrivateKey, c1, k1, restartCounter) = helperValues
            
            // Send c1 to Alice
            
            do {
                let channelType = ObvChannelSendChannelType.obliviousChannel(to: remoteIdentity,
                                                                             remoteDeviceUids: [contactDeviceUid],
                                                                             fromOwnedIdentity: ownedIdentity,
                                                                             necessarilyConfirmed: true,
                                                                             usePreKeyIfRequired: false)
                let coreMessage = getCoreMessage(for: channelType, partOfFullRatchetProtocolOfTheSendSeed: false)
                let concreteProtocolMessage = BobEphemeralKeyAndK1Message(coreProtocolMessage: coreMessage,
                                                                          contactEphemeralPublicKey: ephemeralPublicKey,
                                                                          c1: c1,
                                                                          restartCounter: restartCounter)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post BobEphemeralKeyAndK1Message message", log: log, type: .fault)
                return CancelledState()
            }

            // Return the new state
            
            return BobWaitingForK2State(contactIdentity: remoteIdentity, contactDeviceUid: contactDeviceUid, ephemeralPrivateKey: ephemeralPrivateKey, restartCounter: restartCounter, k1: k1)

        }

    }


    
    
    final class AliceRecoverK1AndSendK2Step: ProtocolStep, TypedConcreteProtocolStep {

        let startState: AliceWaitingForK1State
        let receivedMessage: BobEphemeralKeyAndK1Message

        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .obliviousChannel(remoteCryptoIdentity: startState.contactIdentity, remoteDeviceUid: startState.contactDeviceUid),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: FullRatchetProtocol.logCategory)

            let contactEphemeralPublicKey = receivedMessage.contactEphemeralPublicKey
            let c1 = receivedMessage.c1
            let receivedRestartCounter = receivedMessage.restartCounter
            /* startState.contactIdentity already used to test the channel */
            /* startState.contactDeviceUid already used to test the channel */
            let ephemeralPrivateKey = startState.ephemeralPrivateKey
            let localRestartCounter = startState.restartCounter

            os_log("FullRatchetProtocol - AliceRecoverK1AndSendK2Step - Received restart counter: %d / Start state restart counter: %d", log: log, type: .info, receivedRestartCounter, localRestartCounter)

            // Verifiy that the counter matches. Ignore the message if they don't

            guard localRestartCounter == receivedRestartCounter else {
                os_log("The counters do not match, we stay in the current state.", log: log, type: .info)
                return startState
            }
            
            // Determine the origin of the message
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity", log: log, type: .fault)
                return nil
            }
            
            guard let remoteDeviceUid = receivedMessage.receptionChannelInfo?.getRemoteDeviceUid() else {
                os_log("Could not determine the remote device uid", log: log, type: .fault)
                return nil
            }
            
            // Recover k1
            
            guard let k1 = PublicKeyEncryption.kemDecrypt(c1, using: ephemeralPrivateKey) else {
                    os_log("Could not recover k1", log: log, type: .error)
                    return CancelledState()
            }

            // Generate k2
            
            guard let (c2, k2) = PublicKeyEncryption.kemEncrypt(using: contactEphemeralPublicKey, with: prng) else {
                assertionFailure()
                os_log("Could not perform encryption using contact ephemeral public key", log: log, type: .error)
                return CancelledState()
            }

            // Compute a seed from k1 and k2
            
            guard let seed = Seed(withKeys: [k1, k2]) else {
                os_log("Could not initialize seed for Oblivious Channel", log: log, type: .fault)
                return CancelledState()
            }

            // Send a message back to Bob
            
            do {
                let channelType = ObvChannelSendChannelType.obliviousChannel(to: remoteIdentity, 
                                                                             remoteDeviceUids: [remoteDeviceUid],
                                                                             fromOwnedIdentity: ownedIdentity,
                                                                             necessarilyConfirmed: true,
                                                                             usePreKeyIfRequired: false)
                let coreMessage = getCoreMessage(for: channelType, partOfFullRatchetProtocolOfTheSendSeed: true)
                let concreteProtocolMessage = AliceK2Message(coreProtocolMessage: coreMessage, c2: c2, restartCounter: localRestartCounter)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post BobEphemeralKeyAndK1Message message", log: log, type: .fault)
                return CancelledState()
            }

            // Return the new state
            
            return AliceWaitingForAckState(contactIdentity: remoteIdentity, contactDeviceUid: remoteDeviceUid, seed: seed, restartCounter: localRestartCounter)

        }
        
    }

    
    final class BobRecoverK2ToUpdateReceiveSeedAndSendAckStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: BobWaitingForK2State
        let receivedMessage: AliceK2Message

        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .obliviousChannel(remoteCryptoIdentity: startState.contactIdentity, remoteDeviceUid: startState.contactDeviceUid),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: FullRatchetProtocol.logCategory)

            let c2 = receivedMessage.c2
            let receivedRestartCounter = receivedMessage.restartCounter
            /* startState.contactIdentity already used to test the channel */
            /* startState.contactDeviceUid already used to test the channel */
            let ephemeralPrivateKey = startState.ephemeralPrivateKey
            let localRestartCounter = startState.restartCounter
            let k1 = startState.k1

            os_log("FullRatchetProtocol - BobRecoverK2ToUpdateReceiveSeedAndSendAckStep - Received restart counter: %d / Start state restart counter: %d", log: log, type: .info, receivedRestartCounter, localRestartCounter)

            // Verifiy that the counter matches. Ignore the message if they don't

            guard localRestartCounter == receivedRestartCounter else {
                os_log("The counters do not match, we stay in the current state.", log: log, type: .info)
                return startState
            }
            
            // Determine the origin of the message
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity", log: log, type: .fault)
                return nil
            }
            
            guard let remoteDeviceUid = receivedMessage.receptionChannelInfo?.getRemoteDeviceUid() else {
                os_log("Could not determine the remote device uid", log: log, type: .fault)
                return nil
            }
            
            // Recover k2
            
            guard let k2 = PublicKeyEncryption.kemDecrypt(c2, using: ephemeralPrivateKey) else {
                os_log("Could not recover k2", log: log, type: .error)
                return CancelledState()
            }
            
            // Compute a seed from k1 and k2
            
            guard let seed = Seed(withKeys: [k1, k2]) else {
                os_log("Could not initialize seed for Oblivious Channel", log: log, type: .fault)
                return CancelledState()
            }
            
            // Update the Oblivious channel
            
            do {
                try channelDelegate.updateReceiveSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: concreteCryptoProtocol.ownedIdentity,
                                                                                                 andRemoteIdentity: remoteIdentity,
                                                                                                 withRemoteDeviceUid: remoteDeviceUid,
                                                                                                 with: seed,
                                                                                                 within: obvContext)
            } catch {
                os_log("Could not update received seed of Oblivious channel", log: log, type: .fault)
                return CancelledState()
            }
            
            // Send ack to Alice
            
            do {
                let channelType = ObvChannelSendChannelType.obliviousChannel(to: remoteIdentity, 
                                                                             remoteDeviceUids: [remoteDeviceUid],
                                                                             fromOwnedIdentity: ownedIdentity,
                                                                             necessarilyConfirmed: true,
                                                                             usePreKeyIfRequired: false)
                let coreMessage = getCoreMessage(for: channelType, partOfFullRatchetProtocolOfTheSendSeed: false)
                let concreteProtocolMessage = BobAckMessage(coreProtocolMessage: coreMessage, restartCounter: localRestartCounter)
                guard let messageToSend = concreteProtocolMessage.generateObvChannelProtocolMessageToSend(with: prng) else { return nil }
                _ = try channelDelegate.postChannelMessage(messageToSend, randomizedWith: prng, within: obvContext)
            } catch {
                os_log("Could not post BobAckMessage message", log: log, type: .fault)
                return CancelledState()
            }

            // Return the final state
            
            return FullRatchetDoneState()
            
        }
        
    }

    
    final class AliceUpdateSendSeedStep: ProtocolStep, TypedConcreteProtocolStep {

        let startState: AliceWaitingForAckState
        let receivedMessage: BobAckMessage

        init?(startState: StartConcreteProtocolStateType, receivedMessage: ConcreteProtocolMessageType, concreteCryptoProtocol: ConcreteCryptoProtocol) {

            self.startState = startState
            self.receivedMessage = receivedMessage

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .obliviousChannel(remoteCryptoIdentity: startState.contactIdentity, remoteDeviceUid: startState.contactDeviceUid),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)

        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            let log = OSLog(subsystem: delegateManager.logSubsystem, category: FullRatchetProtocol.logCategory)

            let receivedRestartCounter = receivedMessage.restartCounter
            /* startState.contactIdentity already used to test the channel */
            /* startState.contactDeviceUid already used to test the channel */
            let seed = startState.seed
            let localRestartCounter = startState.restartCounter

            os_log("FullRatchetProtocol - AliceUpdateSendSeedStep - Received restart counter: %d / Start state restart counter: %d", log: log, type: .info, receivedRestartCounter, localRestartCounter)

            // Verifiy that the counter matches. Ignore the message if they don't

            guard localRestartCounter == receivedRestartCounter else {
                os_log("The counters do not match, we stay in the current state.", log: log, type: .info)
                return startState
            }
            
            // Determine the origin of the message
            
            guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
                os_log("Could not determine the remote identity", log: log, type: .fault)
                return nil
            }
            
            guard let remoteDeviceUid = receivedMessage.receptionChannelInfo?.getRemoteDeviceUid() else {
                os_log("Could not determine the remote device uid", log: log, type: .fault)
                return nil
            }
            
            // Update the Oblivious channel
            
            do {
                try channelDelegate.updateSendSeedOfObliviousChannelBetweenTheCurrentDeviceOf(ownedIdentity: concreteCryptoProtocol.ownedIdentity,
                                                                                              andRemoteIdentity: remoteIdentity,
                                                                                              withRemoteDeviceUid: remoteDeviceUid,
                                                                                              with: seed,
                                                                                              within: obvContext)
            } catch {
                os_log("Could not update send seed of Oblivious channel", log: log, type: .fault)
                return CancelledState()
            }

            // Finish the protocol
            
            return FullRatchetDoneState()
            
        }
        
    }

}


// MARK: - Helpers

extension FullRatchetProtocol {
    
    fileprivate static func intFromData(_ data: Data) -> Int {
        var res = 0
        for i in data.startIndex..<data.endIndex {
            res = (res << 8) | Int(data[i])
        }
        return res
    }

    
    fileprivate static func bobSendEphemeralKeyAndK1StepHelper(receivedMessage: AliceEphemeralKeyMessage, ownedIdentity: ObvCryptoIdentity, delegateManager: ObvProtocolDelegateManager, protocolInstanceUid: UID, prng: PRNGService, log: OSLog, within obvContext: ObvContext) -> (remoteIdentity: ObvCryptoIdentity, contactDeviceUid: UID, ephemeralPublicKey: PublicKeyForPublicKeyEncryption, ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption, c1: EncryptedData, k1: AuthenticatedEncryptionKey, restartCounter: Int)? {
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The identity delegate is not set", log: log, type: .fault)
            return nil
        }

        let contactEphemeralPublicKey = receivedMessage.contactEphemeralPublicKey
        let restartCounter = receivedMessage.restartCounter

        // Get the current device uid
        
        let currentDeviceUid: UID
        do {
            currentDeviceUid = try identityDelegate.getCurrentDeviceUidOfOwnedIdentity(ownedIdentity, within: obvContext)
        } catch {
            os_log("Could not get the current device uid", log: log, type: .fault)
            return nil
        }

        // Determine the origin of the message
        
        guard let remoteIdentity = receivedMessage.receptionChannelInfo?.getRemoteIdentity() else {
            os_log("Could not determine the remote identity", log: log, type: .fault)
            return nil
        }
        
        guard let remoteDeviceUid = receivedMessage.receptionChannelInfo?.getRemoteDeviceUid() else {
            os_log("Could not determine the remote device uid", log: log, type: .fault)
            return nil
        }
        
        // Check that the protocol uid is appropriate
        
        let computedProtocolUid: UID
        do {
            computedProtocolUid = try FullRatchetProtocol.computeProtocolUid(aliceIdentity: remoteIdentity,
                                                                             bobIdentity: ownedIdentity,
                                                                             aliceDeviceUid: remoteDeviceUid,
                                                                             bobDeviceUid: currentDeviceUid)
        } catch {
            os_log("Could not compute protocol instance uid", log: log, type: .fault)
            return nil
        }
        
        guard protocolInstanceUid == computedProtocolUid else {
            os_log("The computed protocol instance uid does not match the uid of this protocol.", log: log, type: .fault)
            return nil
        }
        
        // Generate an ephemeral pair of encryption keys
        
        let ephemeralPublicKey: PublicKeyForPublicKeyEncryption
        let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
        do {
            let PublicKeyEncryptionImplementation = ObvCryptoSuite.sharedInstance.getDefaultPublicKeyEncryptionImplementationByteId().algorithmImplementation
            (ephemeralPublicKey, ephemeralPrivateKey) = PublicKeyEncryptionImplementation.generateKeyPair(with: prng)
        }

        // Generate k1
        
        guard let (c1, k1) = PublicKeyEncryption.kemEncrypt(using: contactEphemeralPublicKey, with: prng) else {
            assertionFailure()
            os_log("Could not perform encryption using contact ephemeral public key", log: log, type: .error)
            return nil
        }

        // Return values
        
        return (remoteIdentity, remoteDeviceUid, ephemeralPublicKey, ephemeralPrivateKey, c1, k1, restartCounter)
        
    }
    
}
