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

extension FullRatchetProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initialState = 0
        case aliceWaitingForK1 = 1
        case bobWaitingForK2 = 2
        case aliceWaitingForAck = 3
        case fullRatchetDone = 4
        case cancelled = 5
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState       : return ConcreteProtocolInitialState.self
            case .aliceWaitingForK1  : return AliceWaitingForK1State.self
            case .bobWaitingForK2    : return BobWaitingForK2State.self
            case .aliceWaitingForAck : return AliceWaitingForAckState.self
            case .fullRatchetDone    : return FullRatchetDoneState.self
            case .cancelled          : return CancelledState.self
            }
        }
        
    }
    
    
    struct AliceWaitingForK1State: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.aliceWaitingForK1
                
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
        let restartCounter: Int

        func obvEncode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, ephemeralPrivateKey, restartCounter].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 4) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.contactDeviceUid = try encodedElements[1].obvDecode()
            guard let ephemeralPrivateKey = PrivateKeyForPublicKeyEncryptionDecoder.obvDecode(encodedElements[2]) else { assertionFailure(); throw Self.makeError(message: "Could not decode private key") }
            self.ephemeralPrivateKey = ephemeralPrivateKey
            self.restartCounter = try encodedElements[3].obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption, restartCounter: Int) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.ephemeralPrivateKey = ephemeralPrivateKey
            self.restartCounter = restartCounter
        }
        
    }


    struct BobWaitingForK2State: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.bobWaitingForK2
                
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
        let restartCounter: Int
        let k1: AuthenticatedEncryptionKey

        func obvEncode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, ephemeralPrivateKey, restartCounter, k1].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 5) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.contactDeviceUid = try encodedElements[1].obvDecode()
            guard let ephemeralPrivateKey = PrivateKeyForPublicKeyEncryptionDecoder.obvDecode(encodedElements[2]) else { assertionFailure(); throw Self.makeError(message: "Could not decode private key") }
            self.ephemeralPrivateKey = ephemeralPrivateKey
            self.restartCounter = try encodedElements[3].obvDecode()
            self.k1 = try AuthenticatedEncryptionKeyDecoder.decode(encodedElements[4])
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption, restartCounter: Int, k1: AuthenticatedEncryptionKey) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.ephemeralPrivateKey = ephemeralPrivateKey
            self.restartCounter = restartCounter
            self.k1 = k1
        }

    }


    struct AliceWaitingForAckState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.aliceWaitingForAck
                
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let seed: Seed
        let restartCounter: Int

        func obvEncode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, seed, restartCounter].obvEncode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 4) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.contactDeviceUid = try encodedElements[1].obvDecode()
            self.seed = try encodedElements[2].obvDecode()
            self.restartCounter = try encodedElements[3].obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, seed: Seed, restartCounter: Int) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.seed = seed
            self.restartCounter = restartCounter
        }
        
    }


    struct FullRatchetDoneState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.fullRatchetDone
                
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }

    }


    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.cancelled
                
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }

    }

}
