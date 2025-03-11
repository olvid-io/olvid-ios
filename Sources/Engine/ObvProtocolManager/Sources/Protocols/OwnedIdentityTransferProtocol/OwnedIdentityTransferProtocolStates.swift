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
import ObvEncoder
import ObvCrypto
import ObvTypes


// MARK: - Protocol States

extension OwnedIdentityTransferProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initialState = 0
        case sourceWaitingForSessionNumber = 1
        case sourceWaitingForTargetConnection = 2
        case sourceWaitForKeycloakAuthenticationProof = 11
        // No need for a targetWaitingForSessionNumber state (defined under Android)
        case targetWaitingForTransferredIdentity = 4
        case sourceWaitingForTargetSeed = 5
        case targetWaitingForDecommitment = 6
        case sourceWaitingForSASInput = 7
        case targetWaitingForSnapshot = 8
        case sourceWaitingForTargetAuthenticationProof = 9
        case targetWaitingForKeycloakAuthenticationProofMessageToSend = 10
        case final = 99

        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState: return ConcreteProtocolInitialState.self
            case .sourceWaitingForSessionNumber: return SourceWaitingForSessionNumberState.self
            case .sourceWaitingForTargetConnection: return SourceWaitingForTargetConnectionState.self
            case .targetWaitingForTransferredIdentity: return TargetWaitingForTransferredIdentityState.self
            case .targetWaitingForDecommitment: return TargetWaitingForDecommitmentState.self
            case .targetWaitingForSnapshot: return TargetWaitingForSnapshotState.self
            case .final: return FinalState.self
            case .sourceWaitingForTargetSeed: return SourceWaitingForTargetSeedState.self
            case .sourceWaitingForSASInput: return SourceWaitingForSASInputState.self
            case .sourceWaitingForTargetAuthenticationProof: return SourceWaitingForTargetAuthenticationProofState.self
            case .targetWaitingForKeycloakAuthenticationProofMessageToSend: return TargetWaitingForKeycloakAuthenticationProofMessageToSendState.self
            case .sourceWaitForKeycloakAuthenticationProof: return SourceWaitForKeycloakAuthenticationProofState.self
            }
        }

    }
 
    
    
    // MARK: - SourceWaitingForSessionNumberState
    
    struct SourceWaitingForSessionNumberState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.sourceWaitingForSessionNumber
                
        init() {}

        func obvEncode() -> ObvEncoded { return 0.obvEncode() }

        init(_ obvEncoded: ObvEncoded) throws {}
        
    }

    
    // MARK: - SourceWaitingForTargetConnectionState
    
    struct SourceWaitingForTargetConnectionState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.sourceWaitingForTargetConnection

        let sourceConnectionId: String
        let sessionNumber: ObvOwnedIdentityTransferSessionNumber
        
        init(sourceConnectionId: String, sessionNumber: ObvOwnedIdentityTransferSessionNumber) {
            self.sourceConnectionId = sourceConnectionId
            self.sessionNumber = sessionNumber
        }
        
        func obvEncode() -> ObvEncoded {
            [
                sourceConnectionId,
                sessionNumber,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 2 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.sourceConnectionId = try encodedValues[0].obvDecode()
            self.sessionNumber = try encodedValues[1].obvDecode()
        }

    }

    
    // MARK: - TargetWaitingForTransferredIdentityState
    
    struct TargetWaitingForTransferredIdentityState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.targetWaitingForTransferredIdentity

        let currentDeviceName: String
        let encryptionPrivateKey: PrivateKeyForPublicKeyEncryption
        let macKey: MACKey
        let transferSessionNumber: ObvOwnedIdentityTransferSessionNumber

        init(currentDeviceName: String, encryptionPrivateKey: PrivateKeyForPublicKeyEncryption, macKey: MACKey, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber) {
            self.currentDeviceName = currentDeviceName
            self.encryptionPrivateKey = encryptionPrivateKey
            self.macKey = macKey
            self.transferSessionNumber = transferSessionNumber
        }
        
        func obvEncode() -> ObvEncoded {
            [currentDeviceName,
             encryptionPrivateKey,
             macKey,
             transferSessionNumber,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 4 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.currentDeviceName = try encodedValues[0].obvDecode()
            self.encryptionPrivateKey = try PrivateKeyForPublicKeyEncryptionDecoder.obvDecodeOrThrow(encodedValues[1])
            self.macKey = try MACKeyDecoder.obvDecodeOrThrow(encodedValues[2])
            self.transferSessionNumber = try encodedValues[3].obvDecode()
        }

    }

    
    // MARK: - TargetWaitingForDecommitmentState
    
    struct TargetWaitingForDecommitmentState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.targetWaitingForDecommitment

        let currentDeviceName: String
        let encryptionPrivateKey: PrivateKeyForPublicKeyEncryption
        let otherConnectionIdentifier: String
        let transferredIdentity: ObvCryptoIdentity
        let commitment: Data
        let seedTargetForSas: Seed
        let transferSessionNumber: ObvOwnedIdentityTransferSessionNumber

        init(currentDeviceName: String, encryptionPrivateKey: PrivateKeyForPublicKeyEncryption, otherConnectionIdentifier: String, transferredIdentity: ObvCryptoIdentity, commitment: Data, seedTargetForSas: Seed, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber) {
            self.currentDeviceName = currentDeviceName
            self.encryptionPrivateKey = encryptionPrivateKey
            self.otherConnectionIdentifier = otherConnectionIdentifier
            self.transferredIdentity = transferredIdentity
            self.commitment = commitment
            self.seedTargetForSas = seedTargetForSas
            self.transferSessionNumber = transferSessionNumber
        }
        
        func obvEncode() -> ObvEncoded {
            [currentDeviceName,
             encryptionPrivateKey,
             otherConnectionIdentifier,
             transferredIdentity,
             commitment,
             seedTargetForSas,
             transferSessionNumber,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 7 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.currentDeviceName = try encodedValues[0].obvDecode()
            self.encryptionPrivateKey = try PrivateKeyForPublicKeyEncryptionDecoder.obvDecodeOrThrow(encodedValues[1])
            self.otherConnectionIdentifier = try encodedValues[2].obvDecode()
            self.transferredIdentity = try encodedValues[3].obvDecode()
            self.commitment = try encodedValues[4].obvDecode()
            self.seedTargetForSas = try encodedValues[5].obvDecode()
            self.transferSessionNumber = try encodedValues[6].obvDecode()
        }

    }

    
    
    // MARK: - TargetWaitingForSnapshotState
    
    struct TargetWaitingForSnapshotState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.targetWaitingForSnapshot

        let currentDeviceName: String // ok
        let encryptionPrivateKey: PrivateKeyForPublicKeyEncryption // ok
        let transferredIdentity: ObvCryptoIdentity // ok
        let otherConnectionIdentifier: String
        let fullSas: ObvOwnedIdentityTransferSas
        let transferSessionNumber: ObvOwnedIdentityTransferSessionNumber
        let rawAuthState: Data?
        
        private enum ObvCodingKeys: String, CaseIterable, CodingKey {
            case currentDeviceName = "cdn"
            case encryptionPrivateKey = "epk"
            case transferredIdentity = "ti"
            case otherConnectionIdentifier = "oci"
            case fullSas = "sas"
            case transferSessionNumber = "tsn"
            case rawAuthState = "ras"
            var key: Data { rawValue.data(using: .utf8)! }
        }

        init(currentDeviceName: String, encryptionPrivateKey: PrivateKeyForPublicKeyEncryption, transferredIdentity: ObvCryptoIdentity, otherConnectionIdentifier: String, fullSas: ObvOwnedIdentityTransferSas, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, rawAuthState: Data?) {
            self.currentDeviceName = currentDeviceName
            self.encryptionPrivateKey = encryptionPrivateKey
            self.transferredIdentity = transferredIdentity
            self.otherConnectionIdentifier = otherConnectionIdentifier
            self.fullSas = fullSas
            self.transferSessionNumber = transferSessionNumber
            self.rawAuthState = rawAuthState
        }
        
        func obvEncode() throws -> ObvEncoded {
            var obvDict = [Data: ObvEncoded]()
            for codingKey in ObvCodingKeys.allCases {
                switch codingKey {
                case .currentDeviceName:
                    try obvDict.obvEncode(currentDeviceName, forKey: codingKey)
                case .encryptionPrivateKey:
                    try obvDict.obvEncode(encryptionPrivateKey, forKey: codingKey)
                case .transferredIdentity:
                    try obvDict.obvEncode(transferredIdentity, forKey: codingKey)
                case .otherConnectionIdentifier:
                    try obvDict.obvEncode(otherConnectionIdentifier, forKey: codingKey)
                case .fullSas:
                    try obvDict.obvEncode(fullSas, forKey: codingKey)
                case .transferSessionNumber:
                    try obvDict.obvEncode(transferSessionNumber, forKey: codingKey)
                case .rawAuthState:
                    try obvDict.obvEncodeIfPresent(rawAuthState, forKey: codingKey)
                }
            }
            return obvDict.obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let obvDict = ObvDictionary(obvEncoded) else { assertionFailure(); throw Self.makeError(message: "Could not decode dict in TargetWaitingForSnapshotState") }
            self.currentDeviceName = try obvDict.obvDecode(String.self, forKey: ObvCodingKeys.currentDeviceName)
            let encodedPrivKey = try obvDict.getValue(forKey: ObvCodingKeys.encryptionPrivateKey)
            guard let encryptionPrivateKey = PrivateKeyForPublicKeyEncryptionDecoder.obvDecode(encodedPrivKey) else {
                assertionFailure()
                throw Self.makeError(message: "Failed to decode private key in TargetWaitingForSnapshotState")
            }
            self.encryptionPrivateKey = encryptionPrivateKey
            self.transferredIdentity = try obvDict.obvDecode(ObvCryptoIdentity.self, forKey: ObvCodingKeys.transferredIdentity)
            self.otherConnectionIdentifier = try obvDict.obvDecode(String.self, forKey: ObvCodingKeys.otherConnectionIdentifier)
            self.fullSas = try obvDict.obvDecode(ObvOwnedIdentityTransferSas.self, forKey: ObvCodingKeys.fullSas)
            self.transferSessionNumber = try obvDict.obvDecode(ObvOwnedIdentityTransferSessionNumber.self, forKey: ObvCodingKeys.transferSessionNumber)
            self.rawAuthState = try obvDict.obvDecodeIfPresent(Data.self, forKey: ObvCodingKeys.rawAuthState)
        }

    }
    
    
    // MARK: - TargetWaitingForKeycloakAuthenticationProofMessageToSendState
    
    struct TargetWaitingForKeycloakAuthenticationProofMessageToSendState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.targetWaitingForKeycloakAuthenticationProofMessageToSend

        let currentDeviceName: String // ok
        let encryptionPrivateKey: PrivateKeyForPublicKeyEncryption // ok
        let transferredIdentity: ObvCryptoIdentity // ok
        let otherConnectionIdentifier: String
        let fullSas: ObvOwnedIdentityTransferSas
        let transferSessionNumber: ObvOwnedIdentityTransferSessionNumber

        init(currentDeviceName: String, encryptionPrivateKey: PrivateKeyForPublicKeyEncryption, transferredIdentity: ObvCryptoIdentity, otherConnectionIdentifier: String, fullSas: ObvOwnedIdentityTransferSas, transferSessionNumber: ObvOwnedIdentityTransferSessionNumber) {
            self.currentDeviceName = currentDeviceName
            self.encryptionPrivateKey = encryptionPrivateKey
            self.transferredIdentity = transferredIdentity
            self.otherConnectionIdentifier = otherConnectionIdentifier
            self.fullSas = fullSas
            self.transferSessionNumber = transferSessionNumber
        }
        
        func obvEncode() -> ObvEncoded {
            [currentDeviceName,
             encryptionPrivateKey,
             transferredIdentity,
             otherConnectionIdentifier,
             fullSas,
             transferSessionNumber,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 6 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.currentDeviceName = try encodedValues[0].obvDecode()
            self.encryptionPrivateKey = try PrivateKeyForPublicKeyEncryptionDecoder.obvDecodeOrThrow(encodedValues[1])
            self.transferredIdentity = try encodedValues[2].obvDecode()
            self.otherConnectionIdentifier = try encodedValues[3].obvDecode()
            self.fullSas = try encodedValues[4].obvDecode()
            self.transferSessionNumber = try encodedValues[5].obvDecode()
        }

    }

    
    // MARK: - SourceWaitingForTargetSeedState
    
    struct SourceWaitingForTargetSeedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.sourceWaitingForTargetSeed

        let targetConnectionId: String
        let targetEphemeralIdentity: ObvCryptoIdentity
        let seedSourceForSas: Seed
        let decommitment: Data
        let sessionNumber: ObvOwnedIdentityTransferSessionNumber

        init(targetConnectionId: String, targetEphemeralIdentity: ObvCryptoIdentity, seedSourceForSas: Seed, decommitment: Data, sessionNumber: ObvOwnedIdentityTransferSessionNumber) {
            self.targetConnectionId = targetConnectionId
            self.targetEphemeralIdentity = targetEphemeralIdentity
            self.seedSourceForSas = seedSourceForSas
            self.decommitment = decommitment
            self.sessionNumber = sessionNumber
        }
        
        func obvEncode() -> ObvEncoded {
            [
                targetConnectionId,
                targetEphemeralIdentity,
                seedSourceForSas,
                decommitment,
                sessionNumber,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 5 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.targetConnectionId = try encodedValues[0].obvDecode()
            self.targetEphemeralIdentity = try encodedValues[1].obvDecode()
            self.seedSourceForSas = try encodedValues[2].obvDecode()
            self.decommitment = try encodedValues[3].obvDecode()
            self.sessionNumber = try encodedValues[4].obvDecode()
        }

    }

    
    // MARK: - SourceWaitingForSASInputState
    
    struct SourceWaitingForSASInputState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.sourceWaitingForSASInput

        let targetConnectionId: String
        let targetEphemeralIdentity: ObvCryptoIdentity
        let fullSas: ObvOwnedIdentityTransferSas
        let sessionNumber: ObvOwnedIdentityTransferSessionNumber

        
        init(targetConnectionId: String, targetEphemeralIdentity: ObvCryptoIdentity, fullSas: ObvOwnedIdentityTransferSas, sessionNumber: ObvOwnedIdentityTransferSessionNumber) {
            self.targetConnectionId = targetConnectionId
            self.targetEphemeralIdentity = targetEphemeralIdentity
            self.fullSas = fullSas
            self.sessionNumber = sessionNumber
        }
        
        func obvEncode() -> ObvEncoded {
            [
                targetConnectionId,
                targetEphemeralIdentity,
                fullSas,
                sessionNumber,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 4 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.targetConnectionId = try encodedValues[0].obvDecode()
            self.targetEphemeralIdentity = try encodedValues[1].obvDecode()
            self.fullSas = try encodedValues[2].obvDecode()
            self.sessionNumber = try encodedValues[3].obvDecode()
        }

    }
    
    
    // MARK: - SourceWaitForKeycloakAuthenticationProofState
    
    /// One of the possible states for the source device, used when transferring a Keycloak-managed profile with transfer protection enabled (`isTransferRestricted` = `true`).
    /// In this scenario, before sending the snapshot, the source device requests a proof of authentication from the target device, which involves verifying credentials on the Keycloak server.
    /// The source device remains in this state while waiting for the target device to provide the requested authentication proof.
    struct SourceWaitForKeycloakAuthenticationProofState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.sourceWaitForKeycloakAuthenticationProof

        let targetConnectionId: String
        let targetEphemeralIdentity: ObvCryptoIdentity
        let deviceUIDToKeepActive: UID?
        let keycloakTransferProofElements: ObvKeycloakTransferProofElements // Will have to check the received signature against these elements

        init(targetConnectionId: String, targetEphemeralIdentity: ObvCryptoIdentity, deviceUIDToKeepActive: UID?, keycloakTransferProofElements: ObvKeycloakTransferProofElements) {
            self.targetConnectionId = targetConnectionId
            self.targetEphemeralIdentity = targetEphemeralIdentity
            self.deviceUIDToKeepActive = deviceUIDToKeepActive
            self.keycloakTransferProofElements = keycloakTransferProofElements
        }
        
        func obvEncode() -> ObvEncoded {
            var encoded = [
                targetConnectionId.obvEncode(),
                targetEphemeralIdentity.obvEncode(),
                keycloakTransferProofElements.obvEncode(),
            ]
            if let deviceUIDToKeepActive {
                encoded.append(deviceUIDToKeepActive.obvEncode())
            }
            return encoded.obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 3 || encodedValues.count == 4 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.targetConnectionId = try encodedValues[0].obvDecode()
            self.targetEphemeralIdentity = try encodedValues[1].obvDecode()
            self.keycloakTransferProofElements = try encodedValues[2].obvDecode()
            if encodedValues.count == 4 {
                self.deviceUIDToKeepActive = try encodedValues[3].obvDecode()
            } else {
                self.deviceUIDToKeepActive = nil
            }
        }

    }
    
    
    // MARK: - SourceWaitingForTargetAuthenticationProofState

    struct SourceWaitingForTargetAuthenticationProofState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.sourceWaitingForTargetAuthenticationProof

        let targetConnectionId: String
        let targetEphemeralIdentity: ObvCryptoIdentity
        let fullSas: ObvOwnedIdentityTransferSas
        
        
        init(targetConnectionId: String, targetEphemeralIdentity: ObvCryptoIdentity, fullSas: ObvOwnedIdentityTransferSas) {
            self.targetConnectionId = targetConnectionId
            self.targetEphemeralIdentity = targetEphemeralIdentity
            self.fullSas = fullSas
        }
        
        func obvEncode() -> ObvEncoded {
            [
                targetConnectionId,
                targetEphemeralIdentity,
                fullSas,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 3 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.targetConnectionId = try encodedValues[0].obvDecode()
            self.targetEphemeralIdentity = try encodedValues[1].obvDecode()
            self.fullSas = try encodedValues[2].obvDecode()
        }

    }
    

    
    // MARK: - FinalState
    
    struct FinalState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.final
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }

    
    // Errors
    
    enum ObvStateError: Error {
        case couldNotDecodeState
        case unexpectedNumberOfEncodedValues
    }
    
}
