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
import ObvMetaManager
import ObvCrypto
import ObvEncoder
import ObvTypes


// MARK: - Protocol Steps

extension OwnedIdentityTransferProtocol {
    
    enum StepId: Int, ConcreteProtocolStepId, CaseIterable {
        
        // Steps executed on the source device

        case initiateTransferOnSourceDevice = 0
        case sourceDisplaysSessionNumber = 1
        case sourceSendsTransferredIdentityAndCommitment = 2
        case sourceSendsDecommitmentAndShowsSasInput = 3
        case sourceCheckSasInputAndSendSnapshot = 4

        // Steps executed on the target device
        
        case initiateTransferOnTargetDevice = 10
        case targetSendsSeed = 11
        case targetShowsSas = 12
        case targetProcessesSnapshot = 13
        
        // Abort step
        
        case abortProtocol = 100
        
        func getConcreteProtocolStep(_ concreteProtocol: ConcreteCryptoProtocol, _ receivedMessage: ConcreteProtocolMessage) -> ConcreteProtocolStep? {
            switch self {
                
            // Steps executed on the source device
                
            case .initiateTransferOnSourceDevice:
                let step = InitiateTransferOnSourceDeviceStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .sourceDisplaysSessionNumber:
                let step = SourceDisplaysSessionNumberStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .sourceSendsTransferredIdentityAndCommitment:
                let step = SourceSendsTransferredIdentityAndCommitmentStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .sourceSendsDecommitmentAndShowsSasInput:
                let step = SourceSendsDecommitmentAndShowsSasInputStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .sourceCheckSasInputAndSendSnapshot:
                let step = SourceCheckSasInputAndSendSnapshotStep(from: concreteProtocol, and: receivedMessage)
                return step

            // Steps executed on the target device
                
            case .initiateTransferOnTargetDevice:
                let step = InitiateTransferOnTargetDeviceStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .targetSendsSeed:
                let step = TargetSendsSeedStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .targetShowsSas:
                let step = TargetShowsSasStep(from: concreteProtocol, and: receivedMessage)
                return step
            case .targetProcessesSnapshot:
                let step = TargetProcessesSnapshotStep(from: concreteProtocol, and: receivedMessage)
                return step
                
            // Abort step
                
            case .abortProtocol:
                if let step = AbortProtocolStepFromSourceWaitingForSessionNumberState(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = AbortProtocolStepFromSourceWaitingForTargetConnectionState(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = AbortProtocolStepFromSourceWaitingForTargetSeedState(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = AbortProtocolStepFromTargetWaitingForTransferredIdentityState(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = AbortProtocolStepFromTargetWaitingForDecommitmentState(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = AbortProtocolStepFromSourceWaitingForSASInputState(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = AbortProtocolStepFromTargetWaitingForSnapshotState(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }
            }
        }
        
    }
    
    
    // MARK: - InitiateTransferOnSourceDeviceStep
 
    final class InitiateTransferOnSourceDeviceStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateTransferOnSourceDeviceMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: OwnedIdentityTransferProtocol.InitiateTransferOnSourceDeviceMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            do {
                
                // Connect to the transfer server and get a session number
                
                do {
                    let type = ObvChannelServerQueryMessageToSend.QueryType.sourceGetSessionNumber(protocolInstanceUID: protocolInstanceUid)
                    let core = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                    let concrete = SourceGetSessionNumberMessage(coreProtocolMessage: core)
                    guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                        throw ObvError.couldNotGenerateObvChannelServerQueryMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return SourceWaitingForSessionNumberState()
                
            } catch {
                
                assertionFailure()
                postOwnedIdentityTransferProtocolNotification(withError: error)
                return startState

            }
            
        }
        
        
        /// Called by the step when things got really wrong. This notification will be catched by the protocol starter delegate that will properly abort this protocol and notify the app.
        private func postOwnedIdentityTransferProtocolNotification(withError: Error) {
            let notificationDelegate = self.notificationDelegate
            let ownedCryptoIdentity = self.ownedIdentity
            let protocolInstanceUID = self.protocolInstanceUid
            try? obvContext.addContextDidSaveCompletionHandler { error in
                notificationDelegate.postOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed(payload: .init(
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    protocolInstanceUID: protocolInstanceUID,
                    error: withError)))
            }
        }

        
    }

    
    // MARK: - SourceDisplaysSessionNumberStep
    
    final class SourceDisplaysSessionNumberStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: SourceWaitingForSessionNumberState
        let receivedMessage: SourceGetSessionNumberMessage

        init?(startState: SourceWaitingForSessionNumberState, receivedMessage: SourceGetSessionNumberMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            do {
                
                let result = receivedMessage.result
                
                switch result {
                    
                case .requestFailed:
                    
                    throw ObvError.serverRequestFailed
                    
                case .requestSucceeded(sourceConnectionId: let sourceConnectionId, sessionNumber: let sessionNumber):
                    
                    // On save, notify that the session number is available
                    
                    do {
                        let notificationDelegate = self.notificationDelegate
                        let protocolInstanceUid = self.protocolInstanceUid
                        try obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            notificationDelegate.postOwnedIdentityTransferProtocolNotification(.sourceDisplaySessionNumber(payload: .init(protocolInstanceUID: protocolInstanceUid, sessionNumber: sessionNumber)))
                        }
                    }
                    
                    // Wait for the transfer server's target connection message
                    
                    do {
                        let type = ObvChannelServerQueryMessageToSend.QueryType.sourceWaitForTargetConnection(protocolInstanceUID: protocolInstanceUid)
                        let core = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                        let concrete = SourceWaitForTargetConnectionMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw ObvError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }
                    
                    // Return the new state
                    
                    return SourceWaitingForTargetConnectionState(sourceConnectionId: sourceConnectionId)
                    
                }
                
            } catch {
                
                assertionFailure()
                postOwnedIdentityTransferProtocolNotification(withError: error)
                return startState

            }
            
        }

        
        /// Called by the step when things got really wrong. This notification will be catched by the protocol starter delegate that will properly abort this protocol and notify the app.
        private func postOwnedIdentityTransferProtocolNotification(withError: Error) {
            let notificationDelegate = self.notificationDelegate
            let ownedCryptoIdentity = self.ownedIdentity
            let protocolInstanceUID = self.protocolInstanceUid
            try? obvContext.addContextDidSaveCompletionHandler { error in
                notificationDelegate.postOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed(payload: .init(
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    protocolInstanceUID: protocolInstanceUID,
                    error: withError)))
            }
        }
        
    }

    
    // MARK: - SourceSendsTransferredIdentityAndCommitmentStep
    
    final class SourceSendsTransferredIdentityAndCommitmentStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: SourceWaitingForTargetConnectionState
        let receivedMessage: SourceWaitForTargetConnectionMessage

        init?(startState: SourceWaitingForTargetConnectionState, receivedMessage: SourceWaitForTargetConnectionMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            do {
                
                let sourceConnectionId = startState.sourceConnectionId
                
                switch receivedMessage.result {
                    
                case .requestFailed:
                    
                    throw ObvError.serverRequestFailed
                    
                case .requestSucceeded(targetConnectionId: let targetConnectionId, payload: let payload):
                    
                    // Decode the payload to get the target ephemeral identity
                    
                    let targetEphemeralIdentity: ObvCryptoIdentity
                    do {
                        guard let obvEncoded = ObvEncoded(withRawData: payload),
                              let identity = ObvCryptoIdentity(obvEncoded) else {
                            throw ObvError.decodingFailed
                        }
                        targetEphemeralIdentity = identity
                    }
                    
                    // Generate a seed for the SAS and commit on it
                    
                    let seedSourceForSas = prng.genSeed()
                    let commitmentScheme = ObvCryptoSuite.sharedInstance.commitmentScheme()
                    let (commitment, decommitment) = commitmentScheme.commit(
                        onTag: ownedIdentity.getIdentity(),
                        andValue: seedSourceForSas.raw,
                        with: prng)
                    
                    // Compute the encrypted payload, containing our sourceConnectionIdentifier, the identity to transfer, and the commitment
                    
                    let payload: EncryptedData
                    do {
                        let cleartextPayload: Data = [
                            sourceConnectionId.obvEncode(),
                            ownedIdentity.obvEncode(),
                            commitment.obvEncode(),
                        ].obvEncode().rawData
                        payload = PublicKeyEncryption.encrypt(cleartextPayload, for: targetEphemeralIdentity, randomizedWith: prng)
                    }
                    
                    // Send the encrypted payload
                    
                    do {
                        let type = ObvChannelServerQueryMessageToSend.QueryType.transferRelay(protocolInstanceUID: protocolInstanceUid, connectionIdentifier: targetConnectionId, payload: payload.raw, thenCloseWebSocket: false)
                        let core = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                        let concrete = SourceSendCommitmentMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw ObvError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }
                    
                    return SourceWaitingForTargetSeedState(targetConnectionId: targetConnectionId, targetEphemeralIdentity: targetEphemeralIdentity, seedSourceForSas: seedSourceForSas, decommitment: decommitment)
                    
                }
                
            } catch {
                
                assertionFailure()
                postOwnedIdentityTransferProtocolNotification(withError: error)
                return startState

            }
            
        }

        
        /// Called by the step when things got really wrong. This notification will be catched by the protocol starter delegate that will properly abort this protocol and notify the app.
        private func postOwnedIdentityTransferProtocolNotification(withError: Error) {
            let notificationDelegate = self.notificationDelegate
            let ownedCryptoIdentity = self.ownedIdentity
            let protocolInstanceUID = self.protocolInstanceUid
            try? obvContext.addContextDidSaveCompletionHandler { error in
                notificationDelegate.postOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed(payload: .init(
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    protocolInstanceUID: protocolInstanceUID,
                    error: withError)))
            }
        }

        
    }
    
    
    // MARK: - SourceSendsDecommitmentAndShowsSasInputStep
    
    final class SourceSendsDecommitmentAndShowsSasInputStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: SourceWaitingForTargetSeedState
        let receivedMessage: SourceSendCommitmentMessage

        init?(startState: SourceWaitingForTargetSeedState, receivedMessage: SourceSendCommitmentMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            do {
                
                let targetConnectionId = startState.targetConnectionId
                let targetEphemeralIdentity = startState.targetEphemeralIdentity
                let seedSourceForSas = startState.seedSourceForSas
                let decommitment = startState.decommitment
                
                switch receivedMessage.result {
                    
                case .requestFailed:
                    
                    throw ObvError.serverRequestFailed
                    
                case .requestSucceeded(let payload):
                    
                    // Decrypt the payload
                    
                    let cleartextPayload: Data
                    do {
                        let encryptedPayload = EncryptedData(data: payload)
                        guard let _cleartextPayload = try? identityDelegate.decryptProtocolCiphertext(encryptedPayload, forOwnedCryptoId: ownedIdentity, within: obvContext) else {
                            throw ObvError.decryptionFailed
                        }
                        cleartextPayload = _cleartextPayload
                    }
                    
                    // Decode the cleartext payload to get the seedTargetForSas and the target device name
                    
                    let targetDeviceName: String
                    let seedTargetForSas: Seed
                    do {
                        guard let encoded = ObvEncoded(withRawData: cleartextPayload),
                              let dict = [ObvEncoded](encoded),
                              dict.count == 2 else {
                            throw ObvError.decodingFailed
                        }
                        targetDeviceName = try dict[0].obvDecode()
                        seedTargetForSas = try dict[1].obvDecode()
                    }
                    
                    // Send the decommitment to the target device
                    
                    do {
                        let payload = PublicKeyEncryption.encrypt(decommitment, for: targetEphemeralIdentity, randomizedWith: prng)
                        let type = ObvChannelServerQueryMessageToSend.QueryType.transferRelay(protocolInstanceUID: protocolInstanceUid, connectionIdentifier: targetConnectionId, payload: payload.raw, thenCloseWebSocket: false)
                        let core = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                        let concrete = SourceDecommitmentMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw ObvError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }
                    
                    // Compute the complete SAS
                    
                    let fullSas: ObvOwnedIdentityTransferSas
                    do {
                        let Sas = try SAS.compute(seedAlice: seedSourceForSas, seedBob: seedTargetForSas, identityBob: targetEphemeralIdentity, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS * 2)
                        fullSas = try .init(fullSas: Sas)
                    }
                    
                    // Send the SAS to the UI so that it can wait and check for the SAS user input
                    
                    do {
                        let notificationDelegate = self.notificationDelegate
                        let protocolInstanceUid = self.protocolInstanceUid
                        try obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            notificationDelegate.postOwnedIdentityTransferProtocolNotification(
                                .waitingForSASOnSourceDevice(payload: .init(protocolInstanceUID: protocolInstanceUid,
                                                                            sasExpectedOnInput: fullSas,
                                                                            targetDeviceName: targetDeviceName
                                                                           )))
                        }
                    }
                    
                    // Return the new state
                    
                    return SourceWaitingForSASInputState(targetConnectionId: targetConnectionId, targetEphemeralIdentity: targetEphemeralIdentity, fullSas: fullSas)
                    
                }
                
            } catch {
                
                assertionFailure()
                postOwnedIdentityTransferProtocolNotification(withError: error)
                return startState

            }
            
        }

        
        /// Called by the step when things got really wrong. This notification will be catched by the protocol starter delegate that will properly abort this protocol and notify the app.
        private func postOwnedIdentityTransferProtocolNotification(withError: Error) {
            let notificationDelegate = self.notificationDelegate
            let ownedCryptoIdentity = self.ownedIdentity
            let protocolInstanceUID = self.protocolInstanceUid
            try? obvContext.addContextDidSaveCompletionHandler { error in
                notificationDelegate.postOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed(payload: .init(
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    protocolInstanceUID: protocolInstanceUID,
                    error: withError)))
            }
        }

    }

    
    // MARK: - SourceCheckSasInputAndSendSnapshotStep
    
    final class SourceCheckSasInputAndSendSnapshotStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: SourceWaitingForSASInputState
        let receivedMessage: SourceSASInputMessage

        init?(startState: SourceWaitingForSASInputState, receivedMessage: SourceSASInputMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            do {
                
                let targetConnectionId = startState.targetConnectionId
                let targetEphemeralIdentity = startState.targetEphemeralIdentity
                let fullSas = startState.fullSas
                
                let enteredSAS = receivedMessage.enteredSAS
                let deviceUIDToKeepActive = receivedMessage.deviceUIDToKeepActive
                
                // Make sure the SAS entered by the user is correct (it should work as this was tested in the UI already)
                
                guard enteredSAS == fullSas else {
                    throw ObvError.incorrectSAS
                }
                
                // The SAS is correct, we can send the snapshot
                
                // Compute the cleartext containing the snapshot and, optionally, the UID of the device to keep active (nil means "do nothing", i.e., the target device will remain active)
                
                let syncSnapshotAsObvDict = try syncSnapshotDelegate.getSyncSnapshotNodeAsObvDictionary(for: ObvCryptoId(cryptoIdentity: ownedIdentity))
                let cleartext: Data
                if let deviceUIDToKeepActive {
                    cleartext = [
                        syncSnapshotAsObvDict.obvEncode(),
                        deviceUIDToKeepActive.obvEncode(),
                    ].obvEncode().rawData
                } else {
                    cleartext = [
                        syncSnapshotAsObvDict.obvEncode(),
                    ].obvEncode().rawData
                }

                // Encrypt using the target device ephemeral identity
                
                let ciphertext = PublicKeyEncryption.encrypt(cleartext, for: targetEphemeralIdentity, randomizedWith: prng)
                
                // Post the message
                
                do {
                    let type = ObvChannelServerQueryMessageToSend.QueryType.transferRelay(protocolInstanceUID: protocolInstanceUid, connectionIdentifier: targetConnectionId, payload: ciphertext.raw, thenCloseWebSocket: true)
                    let core = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                    let concrete = SourceSnapshotMessage(coreProtocolMessage: core)
                    guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                        throw ObvError.couldNotGenerateObvChannelServerQueryMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                }
                
                return FinalState()
                
            } catch {
                
                assertionFailure()
                postOwnedIdentityTransferProtocolNotification(withError: error)
                return startState
                
            }
            
        }

        /// Called by the step when things got really wrong. This notification will be catched by the protocol starter delegate that will properly abort this protocol and notify the app.
        private func postOwnedIdentityTransferProtocolNotification(withError: Error) {
            let notificationDelegate = self.notificationDelegate
            let ownedCryptoIdentity = self.ownedIdentity
            let protocolInstanceUID = self.protocolInstanceUid
            try? obvContext.addContextDidSaveCompletionHandler { error in
                notificationDelegate.postOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed(payload: .init(
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    protocolInstanceUID: protocolInstanceUID,
                    error: withError)))
            }
        }

        
    }

    
    // MARK: - InitiateTransferOnTargetDeviceStep
 
    final class InitiateTransferOnTargetDeviceStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateTransferOnTargetDeviceMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: OwnedIdentityTransferProtocol.InitiateTransferOnTargetDeviceMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            do {
                
                let currentDeviceName = receivedMessage.currentDeviceName
                let transferSessionNumber = receivedMessage.transferSessionNumber
                let encryptionPrivateKey = receivedMessage.encryptionPrivateKey
                let macKey = receivedMessage.macKey
                
                // Send the ephemeral owned identity to the source (note that the current owned identity is an ephemeral identity, generated to execute this protocol step)
                
                do {
                    let payload = ownedIdentity.obvEncode().rawData // This is an ephemeral identity generated for this protocol only
                    let type = ObvChannelServerQueryMessageToSend.QueryType.targetSendEphemeralIdentity(protocolInstanceUID: protocolInstanceUid, transferSessionNumber: transferSessionNumber, payload: payload)
                    let core = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                    let concrete = TargetSendEphemeralIdentityMessage(coreProtocolMessage: core)
                    guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                        throw ObvError.couldNotGenerateObvChannelServerQueryMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return TargetWaitingForTransferredIdentityState(currentDeviceName: currentDeviceName, encryptionPrivateKey: encryptionPrivateKey, macKey: macKey)
                
            } catch {
                
                assertionFailure()
                postOwnedIdentityTransferProtocolNotification(withError: error)
                return startState

            }
        }
        
        
        /// Called by the step when things got really wrong. This notification will be catched by the protocol starter delegate that will properly abort this protocol and notify the app.
        private func postOwnedIdentityTransferProtocolNotification(withError: Error) {
            let notificationDelegate = self.notificationDelegate
            let ownedCryptoIdentity = self.ownedIdentity
            let protocolInstanceUID = self.protocolInstanceUid
            try? obvContext.addContextDidSaveCompletionHandler { error in
                notificationDelegate.postOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed(payload: .init(
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    protocolInstanceUID: protocolInstanceUID,
                    error: withError)))
            }
        }

        
    }

    
    // MARK: - TargetSendsSeedStep
    
    final class TargetSendsSeedStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: TargetWaitingForTransferredIdentityState
        let receivedMessage: TargetSendEphemeralIdentityMessage

        init?(startState: TargetWaitingForTransferredIdentityState, receivedMessage: TargetSendEphemeralIdentityMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            do {
                
                let currentDeviceName = startState.currentDeviceName
                let encryptionPrivateKey = startState.encryptionPrivateKey
                let macKey = startState.macKey
                let result = receivedMessage.result
                
                switch result {
                    
                case .requestDidFail:

                    throw ObvError.serverRequestFailed
                    
                case .incorrectTransferSessionNumber:
                    
                    // On save, notify that the transfer session number entered by the user is incorrect
                    
                    do {
                        let notificationDelegate = self.notificationDelegate
                        let protocolInstanceUid = self.protocolInstanceUid
                        try obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            notificationDelegate.postOwnedIdentityTransferProtocolNotification(.userEnteredIncorrectTransferSessionNumber(payload: .init(protocolInstanceUID: protocolInstanceUid)))
                        }
                    }
                    
                    // Return the start state
                    
                    return startState
                    
                case .requestSucceeded(otherConnectionId: let otherConnectionId, payload: let payload):
                    
                    // Decrypt the payload
                    
                    let cleartextPayload: Data
                    do {
                        let encryptedPayload = EncryptedData(data: payload)
                        guard let _cleartextPayload = PublicKeyEncryption.decrypt(encryptedPayload, using: encryptionPrivateKey) else {
                            throw ObvError.decryptionFailed
                        }
                        cleartextPayload = _cleartextPayload
                    }
                    
                    // Decode the payload
                    
                    let decryptedOtherConnectionIdentifier: String
                    let transferredIdentity: ObvCryptoIdentity
                    let commitment: Data
                    do {
                        guard let encoded = ObvEncoded(withRawData: cleartextPayload),
                              let encodedPayloadValues = [ObvEncoded](encoded),
                              encodedPayloadValues.count == 3,
                              let _decryptedOtherConnectionIdentifier: String = try? encodedPayloadValues[0].obvDecode(),
                              let _transferredIdentity: ObvCryptoIdentity = try? encodedPayloadValues[1].obvDecode(),
                              let _commitment: Data = try? encodedPayloadValues[2].obvDecode() else {
                            throw ObvError.decodingFailed
                        }
                        decryptedOtherConnectionIdentifier = _decryptedOtherConnectionIdentifier
                        transferredIdentity = _transferredIdentity
                        commitment = _commitment
                    }
                    
                    // Make sure the connection identifier match
                    
                    guard otherConnectionId == decryptedOtherConnectionIdentifier else {
                        throw ObvError.connectionIdsDoNotMatch
                    }
                    
                    // Makre sure that the owned identity we are about to transfer from the source device to this target device is not one that we have already
                    
                    guard try !identityDelegate.isOwned(transferredIdentity, within: obvContext) else {
                        throw ObvError.tryingToTransferAnOwnedIdentityThatAlreadyExistsOnTargetDevice
                    }
                    
                    // Compute the target part of the SAS
                    
                    let seedTargetForSas = try identityDelegate.getDeterministicSeed(
                        diversifiedUsing: commitment,
                        secretMACKey: macKey,
                        forProtocol: .ownedIdentityTransfer)
                    
                    // Encrypt the payload to be sent to the source device
                    
                    let payload: Data
                    do {
                        let dataToSend: ObvEncoded = [
                            currentDeviceName.obvEncode(),
                            seedTargetForSas.obvEncode(),
                        ].obvEncode()
                        let encryptedPayload = PublicKeyEncryption.encrypt(dataToSend.rawData, using: transferredIdentity.publicKeyForPublicKeyEncryption, and: prng)
                        payload = encryptedPayload.raw
                    }
                    
                    // Send the seedTargetForSas to the source device
                    
                    do {
                        let type = ObvChannelServerQueryMessageToSend.QueryType.transferRelay(protocolInstanceUID: protocolInstanceUid, connectionIdentifier: otherConnectionId, payload: payload, thenCloseWebSocket: false)
                        let core = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                        let concrete = TargetSeedMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw ObvError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }
                    
                    // Return the new state
                    
                    return TargetWaitingForDecommitmentState(
                        currentDeviceName: currentDeviceName,
                        encryptionPrivateKey: encryptionPrivateKey,
                        otherConnectionIdentifier: otherConnectionId,
                        transferredIdentity: transferredIdentity,
                        commitment: commitment,
                        seedTargetForSas: seedTargetForSas)
                    
                }
                
            } catch {
                
                assertionFailure()
                postOwnedIdentityTransferProtocolNotification(withError: error)
                return startState

            }
                        
        }
        
        
        /// Called by the step when things got really wrong. This notification will be catched by the protocol starter delegate that will properly abort this protocol and notify the app.
        private func postOwnedIdentityTransferProtocolNotification(withError: Error) {
            let notificationDelegate = self.notificationDelegate
            let ownedCryptoIdentity = self.ownedIdentity
            let protocolInstanceUID = self.protocolInstanceUid
            try? obvContext.addContextDidSaveCompletionHandler { error in
                notificationDelegate.postOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed(payload: .init(
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    protocolInstanceUID: protocolInstanceUID,
                    error: withError)))
            }
        }

    }

    
    
    // MARK: - TargetShowsSasStep
    
    final class TargetShowsSasStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: TargetWaitingForDecommitmentState
        let receivedMessage: TargetSeedMessage

        init?(startState: TargetWaitingForDecommitmentState, receivedMessage: TargetSeedMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            do {
            
            let currentDeviceName = startState.currentDeviceName
            let encryptionPrivateKey = startState.encryptionPrivateKey
            let otherConnectionIdentifier = startState.otherConnectionIdentifier
            let transferredIdentity = startState.transferredIdentity
            let commitment = startState.commitment
            let seedTargetForSas = startState.seedTargetForSas

            let result = receivedMessage.result

                switch result {
                    
                case .requestFailed:
                    
                    throw ObvError.serverRequestFailed
                    
                case .requestSucceeded(payload: let payload):
                    
                    // Decrypt the payload to get the decommitment
                    
                    let decommitment: Data
                    do {
                        let encryptedPayload = EncryptedData(data: payload)
                        guard let _cleartextPayload = PublicKeyEncryption.decrypt(encryptedPayload, using: encryptionPrivateKey) else {
                            throw ObvError.decryptionFailed
                        }
                        decommitment = _cleartextPayload
                    }
                    
                    // Open the commitment to recover the full SAS
                    
                    let fullSas: ObvOwnedIdentityTransferSas
                    do {
                        let commitmentScheme = ObvCryptoSuite.sharedInstance.commitmentScheme()
                        guard let rawContactSeedForSAS = commitmentScheme.open(commitment: commitment, onTag: transferredIdentity.getIdentity(), usingDecommitToken: decommitment) else {
                            throw ObvError.couldNotOpenCommitment
                        }
                        guard let seedSourceForSas = Seed(with: rawContactSeedForSAS) else {
                            throw ObvError.couldNotComputeSeed
                        }
                        let Sas = try SAS.compute(seedAlice: seedSourceForSas, seedBob: seedTargetForSas, identityBob: ownedIdentity, numberOfDigits: ObvConstants.defaultNumberOfDigitsForSAS * 2)
                        fullSas = try .init(fullSas: Sas)
                    }
                    
                    // On save, notify that the SAS is now available on this target device
                    
                    do {
                        let notificationDelegate = self.notificationDelegate
                        let protocolInstanceUid = self.protocolInstanceUid
                        try obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            notificationDelegate.postOwnedIdentityTransferProtocolNotification(.sasIsAvailable(payload: .init(
                                protocolInstanceUID: protocolInstanceUid,
                                sas: fullSas)))
                        }
                    }
                    
                    // Send a server query allowing to wait for the ObvSyncSnapshot to restore
                    
                    do {
                        let type = ObvChannelServerQueryMessageToSend.QueryType.transferWait(protocolInstanceUID: protocolInstanceUid, connectionIdentifier: otherConnectionIdentifier)
                        let core = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                        let concrete = TargetWaitForSnapshotMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw ObvError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }
                    
                    return TargetWaitingForSnapshotState(
                        currentDeviceName: currentDeviceName,
                        encryptionPrivateKey: encryptionPrivateKey,
                        transferredIdentity: transferredIdentity)
                    
                }
                
            } catch {
                
                assertionFailure()
                postOwnedIdentityTransferProtocolNotification(withError: error)
                return startState

            }

        }

        
        /// Called by the step when things got really wrong. This notification will be catched by the protocol starter delegate that will properly abort this protocol and notify the app.
        private func postOwnedIdentityTransferProtocolNotification(withError: Error) {
            let notificationDelegate = self.notificationDelegate
            let ownedCryptoIdentity = self.ownedIdentity
            let protocolInstanceUID = self.protocolInstanceUid
            try? obvContext.addContextDidSaveCompletionHandler { error in
                notificationDelegate.postOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed(payload: .init(
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    protocolInstanceUID: protocolInstanceUID,
                    error: withError)))
            }
        }

    }

    
    // MARK: - TargetProcessesSnapshotStep
    
    final class TargetProcessesSnapshotStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: TargetWaitingForSnapshotState
        let receivedMessage: TargetWaitForSnapshotMessage

        init?(startState: TargetWaitingForSnapshotState, receivedMessage: TargetWaitForSnapshotMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            do {
                
                let currentDeviceName = startState.currentDeviceName
                let encryptionPrivateKey = startState.encryptionPrivateKey
                let transferredIdentity = startState.transferredIdentity
                
                let result = receivedMessage.result
                
                switch result {
                    
                case .requestFailed:
                    
                    throw ObvError.serverRequestFailed
                    
                case .requestSucceeded(let payload):
                    
                    // Decrypt the payload
                    
                    let encryptedPayload = EncryptedData(data: payload)
                    guard let cleartextPayload = PublicKeyEncryption.decrypt(encryptedPayload, using: encryptionPrivateKey) else {
                        throw ObvError.decryptionFailed
                    }
                    guard let encoded = ObvEncoded(withRawData: cleartextPayload),
                          let listOfEncoded = [ObvEncoded](encoded),
                          listOfEncoded.count >= 1,
                          let obvDictionary = ObvDictionary(listOfEncoded[0])
                    else {
                        throw ObvError.couldNotDecodeSyncSnapshot
                    }
                    
                    // Get the sync snapshot
                    
                    let syncSnapshot = try syncSnapshotDelegate.decodeSyncSnapshot(from: obvDictionary)
                    
                    // Notify that the sync snapshot was is received and is about to be processed
                    
                    notificationDelegate.postOwnedIdentityTransferProtocolNotification(.processingReceivedSnapshotOntargetDevice(payload: .init(protocolInstanceUID: protocolInstanceUid)))
                    
                    // Restore the identity part of the snapshot with the identity manager
                    
                    try identityDelegate.restoreObvSyncSnapshotNode(syncSnapshot.identityNode, customDeviceName: currentDeviceName, within: obvContext)
                    
                    // At this point, we don't want the protocol to fail if something goes wrong,
                    // We juste want the user to know about it.
                    // So we create a set of errors that will post back to the user if not empty
                    
                    var nonDefinitiveErrors = [Error]()
                    
                    // Download all missing user data (typically, photos)

                    do {
                        try downloadAllUserData(within: obvContext)
                    } catch {
                        assertionFailure()
                        nonDefinitiveErrors.append(error) // Continue anyway
                    }
                    
                    // Re-download all groups V2
                    
                    do {
                        try requestReDownloadOfAllNonKeycloakGroupV2(ownedCryptoIdentity: transferredIdentity, within: obvContext)
                    } catch {
                        assertionFailure()
                        nonDefinitiveErrors.append(error) // Continue anyway
                    }
                    
                    // Start an owned device discovery protocol

                    do {
                        try startOwnedDeviceDiscoveryProtocol(for: transferredIdentity, within: obvContext)
                    } catch {
                        assertionFailure()
                        nonDefinitiveErrors.append(error) // Continue anyway
                    }
                    
                    // Start contact discovery protocol for all contacts
                    
                    do {
                        try startDeviceDiscoveryForAllContactsOfOwnedIdentity(transferredIdentity, within: obvContext)
                    } catch {
                        assertionFailure()
                        nonDefinitiveErrors.append(error) // Continue anyway
                    }
                    
                    // Inform the network fetch delegate about the new owned identity.
                    // This will open a websocket for her, and update the well known cache.
                    // We need to perform this after the context is saved, as the network needs to access the
                    // identity manager's database

                    do {
                        let allOwnedIdentities = try identityDelegate.getOwnedIdentities(within: obvContext)
                        let flowId = obvContext.flowId
                        let networkFetchDelegate = self.networkFetchDelegate
                        try obvContext.addContextDidSaveCompletionHandler { error in
                            guard error == nil else { return }
                            networkFetchDelegate.updatedListOfOwnedIdentites(ownedIdentities: allOwnedIdentities, flowId: flowId)
                        }
                    } catch {
                        assertionFailure()
                        nonDefinitiveErrors.append(error) // Continue anyway
                    }

                    // Get the device to keep active
                    
                    let deviceUidToKeepActive: UID?
                    if listOfEncoded.count >= 2 {
                        deviceUidToKeepActive = try listOfEncoded[1].obvDecode()
                    } else {
                        deviceUidToKeepActive = nil
                    }
                    
                    // At this point, we restored the identity (engine) snapshot.
                    // On context save, we need to:
                    // - sync the engine database with the app database
                    // - restore the app snapshot
                    
                    let localSyncSnapshotDelegate = syncSnapshotDelegate
                    let transferredOwnedCryptoId = ObvCryptoId(cryptoIdentity: transferredIdentity)
                    let notificationDelegate = self.notificationDelegate
                    let protocolInstanceUid = self.protocolInstanceUid
                    let ownedIdentity = self.ownedIdentity
                    let nonDefinitiveErrorsFromEngine = nonDefinitiveErrors
                    try obvContext.addContextDidSaveCompletionHandler { error in
                        guard error == nil else {
                            notificationDelegate.postOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed(payload: .init(ownedCryptoIdentity: ownedIdentity, protocolInstanceUID: protocolInstanceUid, error: error!)))
                            return
                        }
                        Task {
                            
                            // We will collect errors the occur during the restore at the app level.
                            // We start with an array made of the non-definitive errors that occured at the engine level.
                            // If not empty, one of these errors will be sent back to the app.
                            // At some point, it might be a good idea to send them all back to the app.
                            var errors = nonDefinitiveErrorsFromEngine
                            
                            do {
                                try await localSyncSnapshotDelegate.syncEngineDatabaseThenUpdateAppDatabase(using: syncSnapshot.appNode)
                            } catch {
                                errors.append(error)
                            }
                            
                            do {
                                if let deviceUidToKeepActive {
                                    try await localSyncSnapshotDelegate.requestServerToKeepDeviceActive(ownedCryptoId: transferredOwnedCryptoId, deviceUidToKeepActive: deviceUidToKeepActive)
                                }
                            } catch {
                                errors.append(error)
                            }
                            
                            assert(errors.isEmpty)
                            
                            // Notify that the transfer is finished and successful on this target device
                            notificationDelegate.postOwnedIdentityTransferProtocolNotification(.successfulTransferOnTargetDevice(payload: .init(protocolInstanceUID: protocolInstanceUid, transferredOwnedCryptoId: transferredOwnedCryptoId, postTransferError: errors.first)))
                            
                        }
                    }
                    
                    
                    // Close the websocket connection
                    
                    do {
                        let type = ObvChannelServerQueryMessageToSend.QueryType.closeWebsocketConnection(protocolInstanceUID: protocolInstanceUid)
                        let core = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                        let concrete = CloseWebsocketConnectionMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw ObvError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }
                    
                    // Return the final state
                    
                    return FinalState()
                    
                }
                
            } catch {
                
                assertionFailure()
                postOwnedIdentityTransferProtocolNotification(withError: error)
                return startState

            }
            
        }

        
        /// Called by the step when things got really wrong. This notification will be catched by the protocol starter delegate that will properly abort this protocol and notify the app.
        private func postOwnedIdentityTransferProtocolNotification(withError: Error) {
            let notificationDelegate = self.notificationDelegate
            let ownedCryptoIdentity = self.ownedIdentity
            let protocolInstanceUID = self.protocolInstanceUid
            try? obvContext.addContextDidSaveCompletionHandler { error in
                notificationDelegate.postOwnedIdentityTransferProtocolNotification(.ownedIdentityTransferProtocolFailed(payload: .init(
                    ownedCryptoIdentity: ownedCryptoIdentity,
                    protocolInstanceUID: protocolInstanceUID,
                    error: withError)))
            }
        }
        
        
        // MARK: Downloading user data
        
        private func downloadAllUserData(within obvContext: ObvContext) throws {
            
            var errorToThrowInTheEnd: Error?
            
            do {
                let items = try identityDelegate.getAllOwnedIdentityWithMissingPhotoUrl(within: obvContext)
                for (ownedIdentity, details) in items {
                    do {
                        try startDownloadIdentityPhotoProtocolWithinTransaction(within: obvContext, ownedIdentity: ownedIdentity, contactIdentity: ownedIdentity, contactIdentityDetailsElements: details)
                    } catch {
                        errorToThrowInTheEnd = error
                    }
                }
            }

            do {
                let items = try identityDelegate.getAllContactsWithMissingPhotoUrl(within: obvContext)
                for (ownedIdentity, contactIdentity, details) in items {
                    do {
                        try startDownloadIdentityPhotoProtocolWithinTransaction(within: obvContext, ownedIdentity: ownedIdentity, contactIdentity: contactIdentity, contactIdentityDetailsElements: details)
                    } catch {
                        errorToThrowInTheEnd = error
                    }
                }
            }

            do {
                let items = try identityDelegate.getAllGroupsWithMissingPhotoUrl(within: obvContext)
                for (ownedIdentity, groupInformation) in items {
                    do {
                        try startDownloadGroupPhotoProtocolWithinTransaction(within: obvContext, ownedIdentity: ownedIdentity, groupInformation: groupInformation)
                    } catch {
                        errorToThrowInTheEnd = error
                    }
                }
            }
            
            if let errorToThrowInTheEnd {
                assertionFailure()
                throw errorToThrowInTheEnd
            }

        }
        
        
        private func startDownloadIdentityPhotoProtocolWithinTransaction(within obvContext: ObvContext, ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) throws {
            let message = try protocolStarterDelegate.getInitialMessageForDownloadIdentityPhotoChildProtocol(
                ownedIdentity: ownedIdentity,
                contactIdentity: contactIdentity,
                contactIdentityDetailsElements: contactIdentityDetailsElements)
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        }

        
        private func startDownloadGroupPhotoProtocolWithinTransaction(within obvContext: ObvContext, ownedIdentity: ObvCryptoIdentity, groupInformation: GroupInformation) throws {
            let message = try protocolStarterDelegate.getInitialMessageForDownloadGroupPhotoChildProtocol(
                ownedIdentity: ownedIdentity, 
                groupInformation: groupInformation)
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        }

        
        // MARK: Re-download of Groups V2
                
        /// After a successful restore within the engine, we need to re-download all groups v2
        private func requestReDownloadOfAllNonKeycloakGroupV2(ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
            
            var errorToThrowInTheEnd: Error?

            let allNonKeycloakGroups = try identityDelegate.getAllObvGroupV2(of: ownedCryptoIdentity, within: obvContext)
                .filter({ !$0.keycloakManaged })
            for group in allNonKeycloakGroups {
                do {
                    try requestReDownloadOfGroup(
                        ownedCryptoIdentity: ownedCryptoIdentity,
                        group: group,
                        within: obvContext)
                } catch {
                    errorToThrowInTheEnd = error
                }
            }
            
            if let errorToThrowInTheEnd {
                assertionFailure()
                throw errorToThrowInTheEnd
            }
            
        }
        
        
        private func requestReDownloadOfGroup(ownedCryptoIdentity: ObvCryptoIdentity, group: ObvGroupV2, within obvContext: ObvContext) throws {
            guard let groupIdentifier = GroupV2.Identifier(appGroupIdentifier: group.appGroupIdentifier) else {
                assertionFailure(); return
            }
            let message = try protocolStarterDelegate.getInitiateGroupReDownloadMessageForGroupV2Protocol(
                ownedIdentity: ownedCryptoIdentity,
                groupIdentifier: groupIdentifier,
                flowId: obvContext.flowId)
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        }
        
        
        // MARK: Start Owned device discovery protocol
        
        private func startOwnedDeviceDiscoveryProtocol(for ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
            
            let message = try protocolStarterDelegate.getInitiateOwnedDeviceDiscoveryMessage(ownedCryptoIdentity: ownedCryptoIdentity)
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            
        }
        
        
        // MARK: Start contact discovery protocol for all contacts
        
        private func startDeviceDiscoveryForAllContactsOfOwnedIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
            
            var errorToThrowInTheEnd: Error?

            let contacts = try identityDelegate.getContactsOfOwnedIdentity(ownedCryptoIdentity, within: obvContext)
            for contact in contacts {
                do {
                    let message = try protocolStarterDelegate.getInitialMessageForContactDeviceDiscoveryProtocol(
                        ownedIdentity: ownedCryptoIdentity,
                        contactIdentity: contact)
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                } catch {
                    errorToThrowInTheEnd = error
                }
            }
            
            if let errorToThrowInTheEnd {
                assertionFailure()
                throw errorToThrowInTheEnd
            }

        }
        
    }
    
    
    // MARK: - AbortProtocolStep
    
    class AbortProtocolStep: ProtocolStep {
        
        private let startState: StartStateType
        private let receivedMessage: AbortProtocolMessage

        enum StartStateType {
            case sourceWaitingForSessionNumberState(startState: SourceWaitingForSessionNumberState)
            case sourceWaitingForTargetConnectionState(startState: SourceWaitingForTargetConnectionState)
            case sourceWaitingForTargetSeedState(startState: SourceWaitingForTargetSeedState)
            case targetWaitingForTransferredIdentityState(startState: TargetWaitingForTransferredIdentityState)
            case targetWaitingForDecommitmentState(startState: TargetWaitingForDecommitmentState)
            case sourceWaitingForSASInputState(startState: SourceWaitingForSASInputState)
            case targetWaitingForSnapshotState(startState: TargetWaitingForSnapshotState)
        }

        init?(startState: StartStateType, receivedMessage: AbortProtocolMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .Local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            // Close the websocket connection
            
            do {
                let type = ObvChannelServerQueryMessageToSend.QueryType.closeWebsocketConnection(protocolInstanceUID: protocolInstanceUid)
                let core = getCoreMessage(for: .ServerQuery(ownedIdentity: ownedIdentity))
                let concrete = CloseWebsocketConnectionMessage(coreProtocolMessage: core)
                guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                    assertionFailure()
                    throw ObvError.couldNotGenerateObvChannelServerQueryMessageToSend
                }
                _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
            }

            return FinalState()
            
        }

    }
    
    
    // MARK: AbortProtocolStep from SourceWaitingForSessionNumberState
    
    final class AbortProtocolStepFromSourceWaitingForSessionNumberState: AbortProtocolStep, TypedConcreteProtocolStep {
        
        let startState: SourceWaitingForSessionNumberState
        let receivedMessage: AbortProtocolMessage

        init?(startState: SourceWaitingForSessionNumberState, receivedMessage: AbortProtocolMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .sourceWaitingForSessionNumberState(startState: startState),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }
    
    
    // MARK: AbortProtocolStep from SourceWaitingForTargetConnectionState

    final class AbortProtocolStepFromSourceWaitingForTargetConnectionState: AbortProtocolStep, TypedConcreteProtocolStep {
        
        let startState: SourceWaitingForTargetConnectionState
        let receivedMessage: AbortProtocolMessage

        init?(startState: SourceWaitingForTargetConnectionState, receivedMessage: AbortProtocolMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .sourceWaitingForTargetConnectionState(startState: startState),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: AbortProtocolStep from SourceWaitingForTargetSeedState

    final class AbortProtocolStepFromSourceWaitingForTargetSeedState: AbortProtocolStep, TypedConcreteProtocolStep {
        
        let startState: SourceWaitingForTargetSeedState
        let receivedMessage: AbortProtocolMessage

        init?(startState: SourceWaitingForTargetSeedState, receivedMessage: AbortProtocolMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .sourceWaitingForTargetSeedState(startState: startState),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: AbortProtocolStep from TargetWaitingForTransferredIdentityState

    final class AbortProtocolStepFromTargetWaitingForTransferredIdentityState: AbortProtocolStep, TypedConcreteProtocolStep {
        
        let startState: TargetWaitingForTransferredIdentityState
        let receivedMessage: AbortProtocolMessage

        init?(startState: TargetWaitingForTransferredIdentityState, receivedMessage: AbortProtocolMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .targetWaitingForTransferredIdentityState(startState: startState),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: AbortProtocolStep from TargetWaitingForDecommitmentState

    final class AbortProtocolStepFromTargetWaitingForDecommitmentState: AbortProtocolStep, TypedConcreteProtocolStep {
        
        let startState: TargetWaitingForDecommitmentState
        let receivedMessage: AbortProtocolMessage

        init?(startState: TargetWaitingForDecommitmentState, receivedMessage: AbortProtocolMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .targetWaitingForDecommitmentState(startState: startState),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: AbortProtocolStep from SourceWaitingForSASInputState

    final class AbortProtocolStepFromSourceWaitingForSASInputState: AbortProtocolStep, TypedConcreteProtocolStep {
        
        let startState: SourceWaitingForSASInputState
        let receivedMessage: AbortProtocolMessage

        init?(startState: SourceWaitingForSASInputState, receivedMessage: AbortProtocolMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .sourceWaitingForSASInputState(startState: startState),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: AbortProtocolStep from TargetWaitingForSnapshotState

    final class AbortProtocolStepFromTargetWaitingForSnapshotState: AbortProtocolStep, TypedConcreteProtocolStep {
        
        let startState: TargetWaitingForSnapshotState
        let receivedMessage: AbortProtocolMessage

        init?(startState: TargetWaitingForSnapshotState, receivedMessage: AbortProtocolMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(startState: .targetWaitingForSnapshotState(startState: startState),
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }


    // MARK: - Errors
    
    enum ObvError: Error {
        case couldNotGenerateObvChannelServerQueryMessageToSend
        case couldNotDecodeSyncSnapshot
        case decryptionFailed
        case decodingFailed
        case incorrectSAS
        case serverRequestFailed
        case connectionIdsDoNotMatch
        case tryingToTransferAnOwnedIdentityThatAlreadyExistsOnTargetDevice
        case couldNotOpenCommitment
        case couldNotComputeSeed
    }
}
