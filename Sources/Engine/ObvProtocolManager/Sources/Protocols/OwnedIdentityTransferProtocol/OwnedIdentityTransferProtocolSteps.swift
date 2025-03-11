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
        case sourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequest = 4

        // Steps executed on the target device
        
        case initiateTransferOnTargetDevice = 10
        case targetSendsSeed = 11
        case targetShowsSas = 12
        case targetProcessesSnapshot = 13
        case targetSendsAuthenticationProof = 14
        
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
            case .sourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequest:
                if let step = SourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequestStepFromLocalInput(from: concreteProtocol, and: receivedMessage) {
                    return step
                } else if let step = SourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequestStepFromAuthenticationProofFromTargetDevice (from: concreteProtocol, and: receivedMessage) {
                    return step
                } else {
                    return nil
                }

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
            case .targetSendsAuthenticationProof:
                let step = TargetSendsAuthenticationProofStep(from: concreteProtocol, and: receivedMessage)
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            do {
                
                // Connect to the transfer server and get a session number
                
                do {
                    let type = ObvChannelServerQueryMessageToSend.QueryType.sourceGetSessionNumber(protocolInstanceUID: protocolInstanceUid)
                    let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                    let concrete = SourceGetSessionNumberMessage(coreProtocolMessage: core)
                    guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                        throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            do {
                
                let result = receivedMessage.result
                
                switch result {
                    
                case .requestFailed:
                    
                    throw OwnedIdentityTransferError.serverRequestFailed
                    
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
                        let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                        let concrete = SourceWaitForTargetConnectionMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }
                    
                    // Return the new state
                    
                    return SourceWaitingForTargetConnectionState(sourceConnectionId: sourceConnectionId, sessionNumber: sessionNumber)
                    
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            do {
                
                let sourceConnectionId = startState.sourceConnectionId
                let sessionNumber = startState.sessionNumber
                
                switch receivedMessage.result {
                    
                case .requestFailed:
                    
                    throw OwnedIdentityTransferError.serverRequestFailed
                    
                case .requestSucceeded(targetConnectionId: let targetConnectionId, payload: let payload):
                    
                    // Decode the payload to get the target ephemeral identity
                    
                    let targetEphemeralIdentity: ObvCryptoIdentity
                    do {
                        guard let obvEncoded = ObvEncoded(withRawData: payload),
                              let identity = ObvCryptoIdentity(obvEncoded) else {
                            throw OwnedIdentityTransferError.decodingFailed
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
                        guard let _payload = PublicKeyEncryption.encrypt(cleartextPayload, for: targetEphemeralIdentity, randomizedWith: prng) else {
                            assertionFailure()
                            throw OwnedIdentityTransferError.couldNotEncryptPayload
                        }
                        payload = _payload
                    }
                    
                    // Send the encrypted payload
                    
                    do {
                        let type = ObvChannelServerQueryMessageToSend.QueryType.transferRelay(protocolInstanceUID: protocolInstanceUid, connectionIdentifier: targetConnectionId, payload: payload.raw, thenCloseWebSocket: false)
                        let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                        let concrete = SourceSendCommitmentMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }
                    
                    return SourceWaitingForTargetSeedState(targetConnectionId: targetConnectionId,
                                                           targetEphemeralIdentity: targetEphemeralIdentity,
                                                           seedSourceForSas: seedSourceForSas,
                                                           decommitment: decommitment,
                                                           sessionNumber: sessionNumber)
                    
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            do {
                
                let targetConnectionId = startState.targetConnectionId
                let targetEphemeralIdentity = startState.targetEphemeralIdentity
                let seedSourceForSas = startState.seedSourceForSas
                let decommitment = startState.decommitment
                let sessionNumber = startState.sessionNumber
                
                switch receivedMessage.result {
                    
                case .requestFailed:
                    
                    throw OwnedIdentityTransferError.serverRequestFailed
                    
                case .requestSucceeded(let payload):
                    
                    // Decrypt the payload
                    
                    let cleartextPayload: Data
                    do {
                        let encryptedPayload = EncryptedData(data: payload)
                        guard let _cleartextPayload = try? identityDelegate.decryptProtocolCiphertext(encryptedPayload, forOwnedCryptoId: ownedIdentity, within: obvContext) else {
                            throw OwnedIdentityTransferError.decryptionFailed
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
                            throw OwnedIdentityTransferError.decodingFailed
                        }
                        targetDeviceName = try dict[0].obvDecode()
                        seedTargetForSas = try dict[1].obvDecode()
                    }
                    
                    // Send the decommitment to the target device
                    
                    do {
                        guard let payload = PublicKeyEncryption.encrypt(decommitment, for: targetEphemeralIdentity, randomizedWith: prng) else {
                            assertionFailure()
                            throw OwnedIdentityTransferError.couldNotEncryptDecommitment
                        }
                        let type = ObvChannelServerQueryMessageToSend.QueryType.transferRelay(protocolInstanceUID: protocolInstanceUid, connectionIdentifier: targetConnectionId, payload: payload.raw, thenCloseWebSocket: false)
                        let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                        let concrete = SourceDecommitmentMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
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
                    
                    return SourceWaitingForSASInputState(targetConnectionId: targetConnectionId, targetEphemeralIdentity: targetEphemeralIdentity, fullSas: fullSas, sessionNumber: sessionNumber)
                    
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

    
    // MARK: - SourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequestStep
    
    class SourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequestStep: ProtocolStep {
        
        enum StartStateAndMessage {
            
            case localSASInput(startState: SourceWaitingForSASInputState, receivedMessage: SourceSASInputMessage)
            case authenticationProofFromTargetDevice(startState: SourceWaitForKeycloakAuthenticationProofState, receivedMessage: SourceWaitForKeycloakAuthenticationProofMessage)
            
            var receivedMessage: ConcreteProtocolMessage {
                switch self {
                case .localSASInput(_, let receivedMessage):
                    return receivedMessage
                case .authenticationProofFromTargetDevice(_, let receivedMessage):
                    return receivedMessage
                }
            }
            
            var startState: TypeConcreteProtocolState {
                switch self {
                case .localSASInput(let startState, _):
                    return startState
                case .authenticationProofFromTargetDevice(let startState, _):
                    return startState
                }
            }

        }

        private let input: StartStateAndMessage

        init?(input: StartStateAndMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.input = input

            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: input.receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            do {
                
                let targetConnectionId: String
                let targetEphemeralIdentity: ObvCryptoIdentity
                
                let deviceUIDToKeepActive: UID?
                
                /// If the keycloak enforces restricted profile transfers, we must keep the `ObvKeycloakTransferProofElements` to check against when the target device will send us back the proof (i.e., the signature)
                enum ShouldRequestKeycloakAuthenticationProof {
                    case no
                    case yes(keycloakTransferProofElements: ObvKeycloakTransferProofElements)
                }
                
                let shouldRequestKeycloakAuthenticationProof: ShouldRequestKeycloakAuthenticationProof
                
                switch input {
                case .localSASInput(let startState, let receivedMessage):
                    
                    targetConnectionId = startState.targetConnectionId
                    targetEphemeralIdentity = startState.targetEphemeralIdentity
                    let fullSas = startState.fullSas
                    let sessionNumber = startState.sessionNumber
                    
                    let enteredSAS = receivedMessage.enteredSAS
                    deviceUIDToKeepActive = receivedMessage.deviceUIDToKeepActive
                    
                    // Make sure the SAS entered by the user is correct (it should work as this was tested in the UI already)
                    
                    guard enteredSAS == fullSas else {
                        throw OwnedIdentityTransferError.incorrectSAS
                    }
                    
                    // The SAS is correct, we can send the snapshot or request a successful keycloak authentication in case the transfer is protected

                    if receivedMessage.isTransferRestricted {
                        let keycloakTransferProofElements = ObvKeycloakTransferProofElements(sessionNumber: sessionNumber, sas: fullSas)
                        shouldRequestKeycloakAuthenticationProof = .yes(keycloakTransferProofElements: keycloakTransferProofElements)
                    } else {
                        shouldRequestKeycloakAuthenticationProof = .no
                    }
                    
                case .authenticationProofFromTargetDevice(let startState, let receivedMessage):

                    targetConnectionId = startState.targetConnectionId
                    targetEphemeralIdentity = startState.targetEphemeralIdentity
                    deviceUIDToKeepActive = startState.deviceUIDToKeepActive
                    let keycloakTransferProofElements = startState.keycloakTransferProofElements

                    switch receivedMessage.result {
                        
                    case .requestFailed:
                        
                        throw OwnedIdentityTransferError.serverRequestFailed
                        
                    case .requestSucceeded(let payload):
                        
                        // Decrypt the payload
                        
                        let cleartextPayload: Data
                        do {
                            let encryptedPayload = EncryptedData(data: payload)
                            guard let _cleartextPayload = try? identityDelegate.decryptProtocolCiphertext(encryptedPayload, forOwnedCryptoId: ownedIdentity, within: obvContext) else {
                                assertionFailure()
                                throw OwnedIdentityTransferError.decryptionFailed
                            }
                            cleartextPayload = _cleartextPayload
                        }

                        // Decode the payload
                        
                        guard let cleartextPayloadAsString = String.init(data: cleartextPayload, encoding: .utf8) else {
                            assertionFailure()
                            throw OwnedIdentityTransferError.decodingFailed
                        }
                        
                        let keycloakTransferProofFromTargetDevice = ObvKeycloakTransferProof(signature: cleartextPayloadAsString)
                        
                        // Verify the proof (if the signature is invalid, the following call throws)
                        
                        try identityDelegate.verifyKeycloakSignature(ownedCryptoId: ownedIdentity,
                                                                     keycloakTransferProof: keycloakTransferProofFromTargetDevice,
                                                                     keycloakTransferProofElements: keycloakTransferProofElements,
                                                                     within: obvContext)
                                                
                        shouldRequestKeycloakAuthenticationProof = .no
                    }

                }
                
                switch shouldRequestKeycloakAuthenticationProof {

                case .yes(let keycloakTransferProofElements):
                    
                    // Since the transfer is restricted, we request a successfull authentication of the target device before sending the snapshot.
                    // For now, we send what the target device needs to authenticate
                    
                    guard let keycloakConfiguration = try identityDelegate.getOwnedIdentityKeycloakState(ownedIdentity: ownedIdentity, within: obvContext).obvKeycloakState?.keycloakConfiguration else {
                        assertionFailure()
                        throw OwnedIdentityTransferError.couldNotObtainKeycloakConfiguration
                    }
                    
                    let cleartext = try keycloakConfiguration.jsonEncode()
                    
                    // Encrypt the payload using the target device ephemeral identity

                    guard let ciphertext = PublicKeyEncryption.encrypt(cleartext, for: targetEphemeralIdentity, randomizedWith: prng) else {
                        assertionFailure()
                        throw OwnedIdentityTransferError.couldNotEncryptPayload
                    }
                    
                    // Post the message
                    
                    do {
                        let type = ObvChannelServerQueryMessageToSend.QueryType.transferRelay(protocolInstanceUID: protocolInstanceUid, connectionIdentifier: targetConnectionId, payload: ciphertext.raw, thenCloseWebSocket: false)
                        let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                        let concrete = SourceWaitForKeycloakAuthenticationProofMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }

                    return SourceWaitForKeycloakAuthenticationProofState(
                        targetConnectionId: targetConnectionId,
                        targetEphemeralIdentity: targetEphemeralIdentity,
                        deviceUIDToKeepActive: deviceUIDToKeepActive,
                        keycloakTransferProofElements: keycloakTransferProofElements)

                case .no:
                    
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
                    
                    guard let ciphertext = PublicKeyEncryption.encrypt(cleartext, for: targetEphemeralIdentity, randomizedWith: prng) else {
                        assertionFailure()
                        throw OwnedIdentityTransferError.couldNotEncryptPayload
                    }
                    
                    // Post the message
                    
                    do {
                        let type = ObvChannelServerQueryMessageToSend.QueryType.transferRelay(protocolInstanceUID: protocolInstanceUid, connectionIdentifier: targetConnectionId, payload: ciphertext.raw, thenCloseWebSocket: true)
                        let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                        let concrete = SourceSnapshotMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }
                    
                    notificationDelegate.postOwnedIdentityTransferProtocolNotification(.protocolFinishedSuccessfullyOnSourceDeviceAsSnapshotSentWasSent(payload: .init(
                        protocolInstanceUID: protocolInstanceUid)))
                    
                    return FinalState()

                }
                                
            } catch {
                
                assertionFailure()
                postOwnedIdentityTransferProtocolNotification(withError: error)
                return input.startState
                
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
    
    
    // MARK: SourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequestStep from local input
    
    /// Verifies the validity of a user-inputted SAS on the source device, determining whether to send the snapshot immediately or request an authentication proof from the target device.
    /// In most cases, the snapshot can be sent right away. However, when transferring a Keycloak-managed profile with transfer protection enabled (isTransferRestricted = true), this step will instead trigger a request for authentication proof to ensure secure transfer.
    final class SourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequestStepFromLocalInput: SourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequestStep, TypedConcreteProtocolStep {
        
        let startState: SourceWaitingForSASInputState
        let receivedMessage: SourceSASInputMessage

        init?(startState: SourceWaitingForSASInputState, receivedMessage: SourceSASInputMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(input: .localSASInput(startState: startState,
                                             receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }
    
    
    final class SourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequestStepFromAuthenticationProofFromTargetDevice: SourceCheckSasInputAndSendSnapshotOrKeycloakAuthenticationProofRequestStep, TypedConcreteProtocolStep {
        
        let startState: SourceWaitForKeycloakAuthenticationProofState
        let receivedMessage: SourceWaitForKeycloakAuthenticationProofMessage

        init?(startState: SourceWaitForKeycloakAuthenticationProofState, receivedMessage: SourceWaitForKeycloakAuthenticationProofMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            self.startState = startState
            self.receivedMessage = receivedMessage
            super.init(input: .authenticationProofFromTargetDevice(startState: startState,
                                             receivedMessage: receivedMessage),
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        // The step execution is defined in the superclass

    }

    
    // MARK: - InitiateTransferOnTargetDeviceStep
 
    final class InitiateTransferOnTargetDeviceStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: ConcreteProtocolInitialState
        let receivedMessage: InitiateTransferOnTargetDeviceMessage

        init?(startState: ConcreteProtocolInitialState, receivedMessage: OwnedIdentityTransferProtocol.InitiateTransferOnTargetDeviceMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
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
                    let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                    let concrete = TargetSendEphemeralIdentityMessage(coreProtocolMessage: core)
                    guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                        throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                }
                
                // Return the new state
                
                return TargetWaitingForTransferredIdentityState(currentDeviceName: currentDeviceName, encryptionPrivateKey: encryptionPrivateKey, macKey: macKey, transferSessionNumber: transferSessionNumber)
                
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {

            do {
                
                let currentDeviceName = startState.currentDeviceName
                let encryptionPrivateKey = startState.encryptionPrivateKey
                let macKey = startState.macKey
                let transferSessionNumber = startState.transferSessionNumber
                let result = receivedMessage.result
                
                switch result {
                    
                case .requestDidFail:

                    throw OwnedIdentityTransferError.serverRequestFailed
                    
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
                            throw OwnedIdentityTransferError.decryptionFailed
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
                            throw OwnedIdentityTransferError.decodingFailed
                        }
                        decryptedOtherConnectionIdentifier = _decryptedOtherConnectionIdentifier
                        transferredIdentity = _transferredIdentity
                        commitment = _commitment
                    }
                    
                    // Make sure the connection identifier match
                    
                    guard otherConnectionId == decryptedOtherConnectionIdentifier else {
                        throw OwnedIdentityTransferError.connectionIdsDoNotMatch
                    }
                    
                    // Makre sure that the owned identity we are about to transfer from the source device to this target device is not one that we have already
                    
                    guard try !identityDelegate.isOwned(transferredIdentity, within: obvContext) else {
                        throw OwnedIdentityTransferError.tryingToTransferAnOwnedIdentityThatAlreadyExistsOnTargetDevice
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
                        guard let encryptedPayload = PublicKeyEncryption.encrypt(dataToSend.rawData, using: transferredIdentity.publicKeyForPublicKeyEncryption, and: prng) else {
                            assertionFailure()
                            throw OwnedIdentityTransferError.couldNotEncryptPayload
                        }
                        payload = encryptedPayload.raw
                    }
                    
                    // Send the seedTargetForSas to the source device
                    
                    do {
                        let type = ObvChannelServerQueryMessageToSend.QueryType.transferRelay(protocolInstanceUID: protocolInstanceUid, connectionIdentifier: otherConnectionId, payload: payload, thenCloseWebSocket: false)
                        let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                        let concrete = TargetSeedMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
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
                        seedTargetForSas: seedTargetForSas,
                        transferSessionNumber: transferSessionNumber)
                    
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
                       expectedReceptionChannelInfo: .local,
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
                let transferSessionNumber = startState.transferSessionNumber
                
                let result = receivedMessage.result
                
                switch result {
                    
                case .requestFailed:
                    
                    throw OwnedIdentityTransferError.serverRequestFailed
                    
                case .requestSucceeded(payload: let payload):
                    
                    // Decrypt the payload to get the decommitment
                    
                    let decommitment: Data
                    do {
                        let encryptedPayload = EncryptedData(data: payload)
                        guard let _cleartextPayload = PublicKeyEncryption.decrypt(encryptedPayload, using: encryptionPrivateKey) else {
                            throw OwnedIdentityTransferError.decryptionFailed
                        }
                        decommitment = _cleartextPayload
                    }
                    
                    // Open the commitment to recover the full SAS
                    
                    let fullSas: ObvOwnedIdentityTransferSas
                    do {
                        let commitmentScheme = ObvCryptoSuite.sharedInstance.commitmentScheme()
                        guard let rawContactSeedForSAS = commitmentScheme.open(commitment: commitment, onTag: transferredIdentity.getIdentity(), usingDecommitToken: decommitment) else {
                            throw OwnedIdentityTransferError.couldNotOpenCommitment
                        }
                        guard let seedSourceForSas = Seed(with: rawContactSeedForSAS) else {
                            throw OwnedIdentityTransferError.couldNotComputeSeed
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
                        let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                        let concrete = TargetWaitForSnapshotMessage(coreProtocolMessage: core)
                        guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                            throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
                        }
                        _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                    }
                    
                    return TargetWaitingForSnapshotState(
                        currentDeviceName: currentDeviceName,
                        encryptionPrivateKey: encryptionPrivateKey,
                        transferredIdentity: transferredIdentity,
                        otherConnectionIdentifier: otherConnectionIdentifier,
                        fullSas: fullSas,
                        transferSessionNumber: transferSessionNumber,
                        rawAuthState: nil)
                    
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            do {
                
                let currentDeviceName = startState.currentDeviceName
                let encryptionPrivateKey = startState.encryptionPrivateKey
                let transferredIdentity = startState.transferredIdentity
                let otherConnectionIdentifier = startState.otherConnectionIdentifier
                let fullSas = startState.fullSas
                let transferSessionNumber = startState.transferSessionNumber
                let rawAuthState = startState.rawAuthState
                
                let result = receivedMessage.result
                
                switch result {
                    
                case .requestFailed:
                    
                    throw OwnedIdentityTransferError.serverRequestFailed
                    
                case .requestSucceeded(let payload):
                    
                    // Decrypt the payload
                    
                    let encryptedPayload = EncryptedData(data: payload)
                    guard let cleartextPayload = PublicKeyEncryption.decrypt(encryptedPayload, using: encryptionPrivateKey) else {
                        throw OwnedIdentityTransferError.decryptionFailed
                    }
                    
                    // The cleartext is either:
                    // - The snapshot (encoded)
                    // - A keycloak configuration, in case the source requires this target device to prove it can authenticate to the keycloak server
                    
                    if let encoded = ObvEncoded(withRawData: cleartextPayload),
                       let listOfEncoded = [ObvEncoded](encoded),
                       listOfEncoded.count >= 1,
                       let obvDictionary = ObvDictionary(listOfEncoded[0]) {
                        
                        // This is the "simple" case, where we don't need to authenticate to the keycloak server
                        // This happens if the profile is not keycloak managed, or when it is keycloak managed but isTransferRestricted is false
                        
                        // Get the sync snapshot
                        
                        let syncSnapshot = try syncSnapshotDelegate.decodeSyncSnapshot(from: obvDictionary)
                        
                        // Notify that the sync snapshot was is received and is about to be processed
                        
                        notificationDelegate.postOwnedIdentityTransferProtocolNotification(.processingReceivedSnapshotOntargetDevice(payload: .init(protocolInstanceUID: protocolInstanceUid)))
                        
                        // Restore the identity part of the snapshot with the identity manager
                        
                        try identityDelegate.restoreObvSyncSnapshotNode(syncSnapshot.identityNode, customDeviceName: currentDeviceName, within: obvContext)
                        
                        // If there is a rawAuthState, save it.
                        // This happens when performing a keycloak restricted profile transfer: in that case, we had to authenticate on this target device.
                        // We kept the authentication state to prevent another authentication request right after the transfer.
                        
                        if let rawAuthState {
                            do {
                                try identityDelegate.saveKeycloakAuthState(ownedIdentity: transferredIdentity, rawAuthState: rawAuthState, within: obvContext)
                            } catch {
                                assertionFailure() // In production, continue anyway
                            }
                        }

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
                            let activeOwnedCryptoIdsAndCurrentDeviceUIDs = try identityDelegate.getActiveOwnedIdentitiesAndCurrentDeviceUids(within: obvContext)
                            let flowId = obvContext.flowId
                            let networkFetchDelegate = self.networkFetchDelegate
                            try obvContext.addContextDidSaveCompletionHandler { error in
                                guard error == nil else { return }
                                Task {
                                    do {
                                        try await networkFetchDelegate.updatedListOfOwnedIdentites(activeOwnedCryptoIdsAndCurrentDeviceUIDs: activeOwnedCryptoIdsAndCurrentDeviceUIDs, flowId: flowId)
                                    } catch {
                                        assertionFailure(error.localizedDescription)
                                    }
                                }
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
                            Task.detached(priority: .high) {
                                
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
                            let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                            let concrete = CloseWebsocketConnectionMessage(coreProtocolMessage: core)
                            guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                                throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
                            }
                            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                        }
                        
                        // Return the final state
                        
                        return FinalState()

                        
                    } else if let keycloakConfiguration = try? ObvKeycloakConfiguration.jsonDecode(cleartextPayload) {
                        
                        // This is the "complex" case, where we (as a target) need to authenticate to the keycloak server
                        // This happens if the profile is keycloak managed and isTransferRestricted is false.
                        // In that case, we must prove to the source that we are able to authenticate. If we do, we will receive the snapshot.
                        
                        // Send the authentication request to the UI so that it can perform a keycloak authentication and send us back the result
                        
                        do {
                            let ownedCryptoIdentity = self.ownedIdentity
                            let notificationDelegate = self.notificationDelegate
                            let protocolInstanceUid = self.protocolInstanceUid
                            let keycloakTransferProofElements = ObvKeycloakTransferProofElements(sessionNumber: transferSessionNumber, sas: fullSas)
                            try obvContext.addContextDidSaveCompletionHandler { error in
                                guard error == nil else { return }
                                notificationDelegate.postOwnedIdentityTransferProtocolNotification(
                                    .keycloakAuthenticationRequiredAsProfileIsTransferRestricted(payload: .init(
                                        protocolInstanceUID: protocolInstanceUid,
                                        keycloakConfiguration: keycloakConfiguration,
                                        keycloakTransferProofElements: keycloakTransferProofElements,
                                        ownedCryptoIdentity: ownedCryptoIdentity))
                                )
                            }
                        }

                        return TargetWaitingForKeycloakAuthenticationProofMessageToSendState(
                            currentDeviceName: currentDeviceName,
                            encryptionPrivateKey: encryptionPrivateKey,
                            transferredIdentity: transferredIdentity,
                            otherConnectionIdentifier: otherConnectionIdentifier,
                            fullSas: fullSas,
                            transferSessionNumber: transferSessionNumber)
                                                
                    } else {
                        
                        // If we reach this point, we were not able to decode the cleartext: it is neither a snapshot nor a keycloak configuration.
                        
                        throw OwnedIdentityTransferError.couldNotDecodeSyncSnapshot
                        
                    }
                    
                    
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
                groupIdentifier: groupIdentifier)
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
    
    
    // MARK: - TargetSendsAuthenticationProofStep
 
    final class TargetSendsAuthenticationProofStep: ProtocolStep, TypedConcreteProtocolStep {
        
        let startState: TargetWaitingForKeycloakAuthenticationProofMessageToSendState
        let receivedMessage: KeycloakAuthenticationProofMessage

        init?(startState: TargetWaitingForKeycloakAuthenticationProofMessageToSendState, receivedMessage: OwnedIdentityTransferProtocol.KeycloakAuthenticationProofMessage, concreteCryptoProtocol: ConcreteCryptoProtocol) {
            
            self.startState = startState
            self.receivedMessage = receivedMessage
            
            super.init(expectedToIdentity: concreteCryptoProtocol.ownedIdentity,
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }

        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            do {
                
                let currentDeviceName = startState.currentDeviceName
                let encryptionPrivateKey = startState.encryptionPrivateKey
                let transferredIdentity = startState.transferredIdentity
                let otherConnectionIdentifier = startState.otherConnectionIdentifier
                let fullSas = startState.fullSas
                let transferSessionNumber = startState.transferSessionNumber
                
                let proofAndAuthState: ObvKeycloakTransferProofAndAuthState = receivedMessage.proof
                
                // Encrypt the proof
                
                guard let proof = proofAndAuthState.proof.signature.data(using: .utf8) else {
                    assertionFailure()
                    throw OwnedIdentityTransferError.couldNotEncryptPayload
                }
                
                guard let encryptedPayload = PublicKeyEncryption.encrypt(proof, using: transferredIdentity.publicKeyForPublicKeyEncryption, and: prng) else {
                    assertionFailure()
                    throw OwnedIdentityTransferError.couldNotEncryptPayload
                }
                let payload = encryptedPayload.raw

                // Send a server query allowing to wait for the ObvSyncSnapshot to restore
                
                do {
                    let type = ObvChannelServerQueryMessageToSend.QueryType.transferRelay(
                        protocolInstanceUID: protocolInstanceUid,
                        connectionIdentifier: otherConnectionIdentifier,
                        payload: payload,
                        thenCloseWebSocket: false)
                    let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                    let concrete = TargetWaitForSnapshotMessage(coreProtocolMessage: core)
                    guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                        throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
                    }
                    _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
                }

                // We sent the proof, go back in the state where we wait for the snapshot
                
                return TargetWaitingForSnapshotState(
                    currentDeviceName: currentDeviceName,
                    encryptionPrivateKey: encryptionPrivateKey,
                    transferredIdentity: transferredIdentity,
                    otherConnectionIdentifier: otherConnectionIdentifier,
                    fullSas: fullSas,
                    transferSessionNumber: transferSessionNumber,
                    rawAuthState: proofAndAuthState.rawAuthState)
                
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
                       expectedReceptionChannelInfo: .local,
                       receivedMessage: receivedMessage,
                       concreteCryptoProtocol: concreteCryptoProtocol)
        }
        
        override func executeStep(within obvContext: ObvContext) throws -> ConcreteProtocolState? {
            
            // Close the websocket connection
            
            do {
                let type = ObvChannelServerQueryMessageToSend.QueryType.closeWebsocketConnection(protocolInstanceUID: protocolInstanceUid)
                let core = getCoreMessage(for: .serverQuery(ownedIdentity: ownedIdentity))
                let concrete = CloseWebsocketConnectionMessage(coreProtocolMessage: core)
                guard let message = concrete.generateObvChannelServerQueryMessageToSend(serverQueryType: type) else {
                    assertionFailure()
                    throw OwnedIdentityTransferError.couldNotGenerateObvChannelServerQueryMessageToSend
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
    
}
