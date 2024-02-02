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
import ObvMetaManager
import OlvidUtils



// MARK: - Protocol States

extension DeviceDiscoveryForRemoteIdentityProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initialState = 0
        case waitingForDeviceUids = 1
        case deviceUidsReceived = 2 // Final
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState         : return ConcreteProtocolInitialState.self
            case .waitingForDeviceUids : return WaitingForDeviceUidsState.self
            case .deviceUidsReceived   : return DeviceUidsReceivedState.self
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
        let deviceUids: [UID]
        
        init(_ obvEncoded: ObvEncoded) throws {
            guard let listOfEncoded = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            remoteIdentity = try listOfEncoded[0].obvDecode()
            guard let listOfEncodedDeviceUids = [ObvEncoded](listOfEncoded[1]) else { assertionFailure(); throw Self.makeError(message: "Failed to obtain encoded device uids") }
            deviceUids = try listOfEncodedDeviceUids.map { return try $0.obvDecode() }
        }
        
        init(remoteIdentity: ObvCryptoIdentity, deviceUids: [UID]) {
            self.remoteIdentity = remoteIdentity
            self.deviceUids = deviceUids
        }
        
        func obvEncode() -> ObvEncoded {
            let listOfEncodedDeviceUids = deviceUids.map { $0.obvEncode() }
            let encodedDeviceUids = listOfEncodedDeviceUids.obvEncode()
            let encodedRemoteIdentity = remoteIdentity.obvEncode()
            return [encodedRemoteIdentity, encodedDeviceUids].obvEncode()
        }
    }

}
