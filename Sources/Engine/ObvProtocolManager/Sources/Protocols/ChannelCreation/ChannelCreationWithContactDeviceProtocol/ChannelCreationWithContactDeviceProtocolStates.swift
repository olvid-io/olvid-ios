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
import CoreData
import os.log
import ObvCrypto
import ObvEncoder
import ObvTypes
import ObvOperation


// MARK: - Protocol States

extension ChannelCreationWithContactDeviceProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initialState = 0
        // Alice's side
        case waitingForK1 = 1
        case waitForFirstAck = 2
        // Bob's side
        case waitingForK2 = 3
        case waitForSecondAck = 5
        // On Alice's and Bob's sides
        case pingSent = 6
        case channelConfirmed = 7
        case cancelled = 8
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState     : return ConcreteProtocolInitialState.self
            case .waitingForK1     : return WaitingForK1State.self
            case .waitForFirstAck  : return WaitForFirstAckState.self
            case .waitingForK2     : return WaitingForK2State.self
            case .waitForSecondAck : return WaitForSecondAckState.self
            case .pingSent         : return PingSentState.self
            case .channelConfirmed : return ChannelConfirmedState.self
            case .cancelled        : return CancelledState.self
            }
        }
    }
    
    
    // MARK: - WaitingForK1State
    
    struct WaitingForK1State: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitingForK1
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
        
        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 3) else {
                throw ChannelCreationWithContactDeviceProtocol.makeError(message: "Unexpected number of encoded elements in WaitingForK1State")
            }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.contactDeviceUid = try encodedElements[1].obvDecode()
            guard let ephemeralPrivateKey = PrivateKeyForPublicKeyEncryptionDecoder.obvDecode(encodedElements[2]) else {
                throw ChannelCreationWithContactDeviceProtocol.makeError(message: "Could not decode private key in WaitingForK1State")
            }
            self.ephemeralPrivateKey = ephemeralPrivateKey
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.ephemeralPrivateKey = ephemeralPrivateKey
        }
        
        func obvEncode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, ephemeralPrivateKey].obvEncode()
        }
    }

    
    // MARK: - WaitingForFirstAckState
    
    struct WaitForFirstAckState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitForFirstAck
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let currentDeviceUid: UID
        
        init(_ encoded: ObvEncoded) throws {
            (contactIdentity, contactDeviceUid, currentDeviceUid) = try encoded.obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, currentDeviceUid: UID) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.currentDeviceUid = currentDeviceUid
        }
        
        func obvEncode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, currentDeviceUid].obvEncode()
        }
    }

    
    // MARK: - WaitingForK2State
    
    struct WaitingForK2State: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitingForK2
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
        let k1: AuthenticatedEncryptionKey
        
        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 4) else {
                throw ChannelCreationWithContactDeviceProtocol.makeError(message: "Unexpected number of encoded elements in WaitingForK2State")
            }
            self.contactIdentity = try encodedElements[0].obvDecode()
            self.contactDeviceUid = try encodedElements[1].obvDecode()
            guard let ephemeralPrivateKey = PrivateKeyForPublicKeyEncryptionDecoder.obvDecode(encodedElements[2]) else {
                throw ChannelCreationWithContactDeviceProtocol.makeError(message: "Could not decode private key in WaitingForK2State")
            }
            self.ephemeralPrivateKey = ephemeralPrivateKey
            k1 = try AuthenticatedEncryptionKeyDecoder.decode(encodedElements[3])
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption, k1: AuthenticatedEncryptionKey) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.ephemeralPrivateKey = ephemeralPrivateKey
            self.k1 = k1
        }
        
        func obvEncode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, ephemeralPrivateKey, k1].obvEncode()
        }
    }

    
    // MARK: - WaitForSecondAckState
    
    struct WaitForSecondAckState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitForSecondAck
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let currentDeviceUid: UID
        
        init(_ encoded: ObvEncoded) throws {
            (contactIdentity, contactDeviceUid, currentDeviceUid) = try encoded.obvDecode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, currentDeviceUid: UID) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.currentDeviceUid = currentDeviceUid
        }
        
        func obvEncode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, currentDeviceUid].obvEncode()
        }

    }

    
    // MARK: - PingSentState
    
    struct PingSentState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.pingSent
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }

    }
    
    // MARK: - ChannelConfirmedState
    
    struct ChannelConfirmedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.channelConfirmed
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }

    
    // MARK: - CancelledState
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.cancelled
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
    }

}
