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
import ObvOperation
import ObvMetaManager
import OlvidUtils



// MARK: - Protocol States

extension DeviceDiscoveryForRemoteIdentityProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initialState = 0
        case waitingForDeviceUids = 1
        case deviceUidsReceived = 2 // Final
        case cancelled = 3 // Final
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState         : return ConcreteProtocolInitialState.self
            case .waitingForDeviceUids : return WaitingForDeviceUidsState.self
            case .deviceUidsReceived   : return DeviceUidsReceivedState.self
            case .cancelled            : return CancelledState.self
            }
        }
    }
    
    
    struct WaitingForDeviceUidsState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitingForDeviceUids
        
        let remoteIdentity: ObvCryptoIdentity
        
        init(_ encoded: ObvEncoded) throws {
            (remoteIdentity) = try encoded.obvDecode()
        }
        
        init(remoteIdentity: ObvCryptoIdentity) {
            self.remoteIdentity = remoteIdentity
        }
        
        func obvEncode() -> ObvEncoded {
            return remoteIdentity.obvEncode()
        }
        
    }
    
    
    struct DeviceUidsReceivedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.deviceUidsReceived
        
        let remoteIdentity: ObvCryptoIdentity
        let result: ContactDeviceDiscoveryResult
        
        init(_ obvEncoded: ObvEncoded) throws {
            guard let listOfEncoded = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            remoteIdentity = try listOfEncoded[0].obvDecode()
            result = try listOfEncoded[1].obvDecode()
        }
        
        init(remoteIdentity: ObvCryptoIdentity, result: ContactDeviceDiscoveryResult) {
            self.remoteIdentity = remoteIdentity
            self.result = result
        }
        
        func obvEncode() -> ObvEncoded {
            return [remoteIdentity, result].obvEncode()
        }
    }

    // MARK: - CancelledState
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.cancelled
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
    }

}
