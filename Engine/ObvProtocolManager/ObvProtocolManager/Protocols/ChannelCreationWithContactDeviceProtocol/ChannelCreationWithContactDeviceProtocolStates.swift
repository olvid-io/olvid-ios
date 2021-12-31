/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
        
        case InitialState = 0
        // Alice's side
        case WaitingForK1 = 1
        case WaitForFirstAck = 2
        // Bob's side
        case WaitingForK2 = 3
        case WaitForSecondAck = 5
        // On Alice's and Bob's sides
        case PingSent = 6
        case ChannelConfirmed = 7
        case Cancelled = 8
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState     : return ConcreteProtocolInitialState.self
            case .WaitingForK1     : return WaitingForK1State.self
            case .WaitForFirstAck  : return WaitForFirstAckState.self
            case .WaitingForK2     : return WaitingForK2State.self
            case .WaitForSecondAck : return WaitForSecondAckState.self
            case .PingSent         : return PingSentState.self
            case .ChannelConfirmed : return ChannelConfirmedState.self
            case .Cancelled        : return CancelledState.self
            }
        }
    }
    
    
    // MARK: - WaitingForK1State
    
    struct WaitingForK1State: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitingForK1
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
        
        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded].init(encoded, expectedCount: 3) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].decode()
            self.contactDeviceUid = try encodedElements[1].decode()
            guard let ephemeralPrivateKey = PrivateKeyForPublicKeyEncryptionDecoder.decode(encodedElements[2]) else { throw NSError() }
            self.ephemeralPrivateKey = ephemeralPrivateKey
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.ephemeralPrivateKey = ephemeralPrivateKey
        }
        
        func encode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, ephemeralPrivateKey].encode()
        }
    }

    
    // MARK: - WaitingForFirstAckState
    
    struct WaitForFirstAckState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitForFirstAck
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let currentDeviceUid: UID
        
        init(_ encoded: ObvEncoded) throws {
            (contactIdentity, contactDeviceUid, currentDeviceUid) = try encoded.decode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, currentDeviceUid: UID) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.currentDeviceUid = currentDeviceUid
        }
        
        func encode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, currentDeviceUid].encode()
        }
    }

    
    // MARK: - WaitingForK2State
    
    struct WaitingForK2State: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitingForK2
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption
        let k1: AuthenticatedEncryptionKey
        
        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded].init(encoded, expectedCount: 4) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].decode()
            self.contactDeviceUid = try encodedElements[1].decode()
            guard let ephemeralPrivateKey = PrivateKeyForPublicKeyEncryptionDecoder.decode(encodedElements[2]) else { throw NSError() }
            self.ephemeralPrivateKey = ephemeralPrivateKey
            k1 = try AuthenticatedEncryptionKeyDecoder.decode(encodedElements[3])
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, ephemeralPrivateKey: PrivateKeyForPublicKeyEncryption, k1: AuthenticatedEncryptionKey) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.ephemeralPrivateKey = ephemeralPrivateKey
            self.k1 = k1
        }
        
        func encode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, ephemeralPrivateKey, k1].encode()
        }
    }

    
    // MARK: - WaitForSecondAckState
    
    struct WaitForSecondAckState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.WaitForSecondAck
        
        let contactIdentity: ObvCryptoIdentity
        let contactDeviceUid: UID
        let currentDeviceUid: UID
        
        init(_ encoded: ObvEncoded) throws {
            (contactIdentity, contactDeviceUid, currentDeviceUid) = try encoded.decode()
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactDeviceUid: UID, currentDeviceUid: UID) {
            self.contactIdentity = contactIdentity
            self.contactDeviceUid = contactDeviceUid
            self.currentDeviceUid = currentDeviceUid
        }
        
        func encode() -> ObvEncoded {
            return [contactIdentity, contactDeviceUid, currentDeviceUid].encode()
        }

    }

    
    // MARK: - PingSentState
    
    struct PingSentState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.PingSent
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }

    }
    
    // MARK: - ChannelConfirmedState
    
    struct ChannelConfirmedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.ChannelConfirmed
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }
        
    }

    
    // MARK: - CancelledState
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Cancelled
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }
    }

}
