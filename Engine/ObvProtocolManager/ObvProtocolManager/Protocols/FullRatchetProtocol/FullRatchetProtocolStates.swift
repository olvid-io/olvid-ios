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
import ObvEncoder
import ObvCrypto
import ObvTypes

// MARK: - Protocol States

extension FullRatchetProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case InitialState = 0
        case AliceWaitingForK1 = 1
        case BobWaitingForK2 = 2
        case AliceWaitingForAck = 3
        case FullRatchetDone = 4
        case Cancelled = 5
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState       : return ConcreteProtocolInitialState.self
            case .AliceWaitingForK1  : return AliceWaitingForK1State.self
            case .BobWaitingForK2    : return BobWaitingForK2State.self
            case .AliceWaitingForAck : return AliceWaitingForAckState.self
            case .FullRatchetDone    : return FullRatchetDoneState.self
            case .Cancelled          : return CancelledState.self
            }
        }
        
    }
    
    
    struct AliceWaitingForK1State: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.AliceWaitingForK1
                
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
        let restartCounter: Int

        func encode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, ephemeralPrivateKey, restartCounter].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded].init(encoded, expectedCount: 4) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].decode()
            self.contactDeviceUid = try encodedElements[1].decode()
            guard let ephemeralPrivateKey = PrivateKeyForPublicKeyEncryptionDecoder.decode(encodedElements[2]) else { throw NSError() }
            self.ephemeralPrivateKey = ephemeralPrivateKey
            self.restartCounter = try encodedElements[3].decode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption, restartCounter: Int) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.ephemeralPrivateKey = ephemeralPrivateKey
            self.restartCounter = restartCounter
        }
        
    }


    struct BobWaitingForK2State: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.BobWaitingForK2
                
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
        let restartCounter: Int
        let k1: AuthenticatedEncryptionKey

        func encode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, ephemeralPrivateKey, restartCounter, k1].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded].init(encoded, expectedCount: 5) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].decode()
            self.contactDeviceUid = try encodedElements[1].decode()
            guard let ephemeralPrivateKey = PrivateKeyForPublicKeyEncryptionDecoder.decode(encodedElements[2]) else { throw NSError() }
            self.ephemeralPrivateKey = ephemeralPrivateKey
            self.restartCounter = try encodedElements[3].decode()
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
        
        let id: ConcreteProtocolStateId = StateId.AliceWaitingForAck
                
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let seed: Seed
        let restartCounter: Int

        func encode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, seed, restartCounter].encode()
        }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded].init(encoded, expectedCount: 4) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].decode()
            self.contactDeviceUid = try encodedElements[1].decode()
            self.seed = try encodedElements[2].decode()
            self.restartCounter = try encodedElements[3].decode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, seed: Seed, restartCounter: Int) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.seed = seed
            self.restartCounter = restartCounter
        }
        
    }


    struct FullRatchetDoneState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.FullRatchetDone
                
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }

    }


    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Cancelled
                
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }

    }

}
