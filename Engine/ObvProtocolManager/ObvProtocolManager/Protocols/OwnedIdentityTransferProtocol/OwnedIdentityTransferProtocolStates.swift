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
        // No need for a targetWaitingForSessionNumber state (defined under Android)
        case targetWaitingForTransferredIdentity = 4
        case sourceWaitingForTargetSeed = 5
        case targetWaitingForDecommitment = 6
        case sourceWaitingForSASInput = 7
        case targetWaitingForSnapshot = 8
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
        
        init(sourceConnectionId: String) {
            self.sourceConnectionId = sourceConnectionId
        }
        
        func obvEncode() -> ObvEncoded { return [sourceConnectionId].obvEncode() }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 1 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.sourceConnectionId = try encodedValues[0].obvDecode()
        }

    }

    
    // MARK: - TargetWaitingForTransferredIdentityState
    
    struct TargetWaitingForTransferredIdentityState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.targetWaitingForTransferredIdentity

        let currentDeviceName: String
        let encryptionPrivateKey: PrivateKeyForPublicKeyEncryption
        let macKey: MACKey

        init(currentDeviceName: String, encryptionPrivateKey: PrivateKeyForPublicKeyEncryption, macKey: MACKey) {
            self.currentDeviceName = currentDeviceName
            self.encryptionPrivateKey = encryptionPrivateKey
            self.macKey = macKey
        }
        
        func obvEncode() -> ObvEncoded {
            [currentDeviceName,
             encryptionPrivateKey,
             macKey,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 3 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.currentDeviceName = try encodedValues[0].obvDecode()
            self.encryptionPrivateKey = try PrivateKeyForPublicKeyEncryptionDecoder.obvDecodeOrThrow(encodedValues[1])
            self.macKey = try MACKeyDecoder.obvDecodeOrThrow(encodedValues[2])
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

        init(currentDeviceName: String, encryptionPrivateKey: PrivateKeyForPublicKeyEncryption, otherConnectionIdentifier: String, transferredIdentity: ObvCryptoIdentity, commitment: Data, seedTargetForSas: Seed) {
            self.currentDeviceName = currentDeviceName
            self.encryptionPrivateKey = encryptionPrivateKey
            self.otherConnectionIdentifier = otherConnectionIdentifier
            self.transferredIdentity = transferredIdentity
            self.commitment = commitment
            self.seedTargetForSas = seedTargetForSas
        }
        
        func obvEncode() -> ObvEncoded {
            [currentDeviceName,
             encryptionPrivateKey,
             otherConnectionIdentifier,
             transferredIdentity,
             commitment,
             seedTargetForSas,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 6 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.currentDeviceName = try encodedValues[0].obvDecode()
            self.encryptionPrivateKey = try PrivateKeyForPublicKeyEncryptionDecoder.obvDecodeOrThrow(encodedValues[1])
            self.otherConnectionIdentifier = try encodedValues[2].obvDecode()
            self.transferredIdentity = try encodedValues[3].obvDecode()
            self.commitment = try encodedValues[4].obvDecode()
            self.seedTargetForSas = try encodedValues[5].obvDecode()
        }

    }

    
    
    // MARK: - TargetWaitingForSnapshotState
    
    struct TargetWaitingForSnapshotState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.targetWaitingForSnapshot

        let currentDeviceName: String // ok
        let encryptionPrivateKey: PrivateKeyForPublicKeyEncryption // ok
        let transferredIdentity: ObvCryptoIdentity // ok

        init(currentDeviceName: String, encryptionPrivateKey: PrivateKeyForPublicKeyEncryption, transferredIdentity: ObvCryptoIdentity) {
            self.currentDeviceName = currentDeviceName
            self.encryptionPrivateKey = encryptionPrivateKey
            self.transferredIdentity = transferredIdentity
        }
        
        func obvEncode() -> ObvEncoded {
            [currentDeviceName,
             encryptionPrivateKey,
             transferredIdentity,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 3 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.currentDeviceName = try encodedValues[0].obvDecode()
            self.encryptionPrivateKey = try PrivateKeyForPublicKeyEncryptionDecoder.obvDecodeOrThrow(encodedValues[1])
            self.transferredIdentity = try encodedValues[2].obvDecode()
        }

    }

    
    // MARK: - SourceWaitingForTargetSeedState
    
    struct SourceWaitingForTargetSeedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.sourceWaitingForTargetSeed

        let targetConnectionId: String
        let targetEphemeralIdentity: ObvCryptoIdentity
        let seedSourceForSas: Seed
        let decommitment: Data
        
        init(targetConnectionId: String, targetEphemeralIdentity: ObvCryptoIdentity, seedSourceForSas: Seed, decommitment: Data) {
            self.targetConnectionId = targetConnectionId
            self.targetEphemeralIdentity = targetEphemeralIdentity
            self.seedSourceForSas = seedSourceForSas
            self.decommitment = decommitment
        }
        
        func obvEncode() -> ObvEncoded {
            [
                targetConnectionId,
                targetEphemeralIdentity,
                seedSourceForSas,
                decommitment,
            ].obvEncode()
        }

        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded) else { assertionFailure(); throw ObvStateError.couldNotDecodeState}
            guard encodedValues.count == 4 else { assertionFailure(); throw ObvStateError.unexpectedNumberOfEncodedValues }
            self.targetConnectionId = try encodedValues[0].obvDecode()
            self.targetEphemeralIdentity = try encodedValues[1].obvDecode()
            self.seedSourceForSas = try encodedValues[2].obvDecode()
            self.decommitment = try encodedValues[3].obvDecode()
        }

    }

    
    // MARK: - SourceWaitingForSASInputState
    
    struct SourceWaitingForSASInputState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.sourceWaitingForSASInput

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
