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
import ObvEncoder
import ObvTypes
import ObvCrypto
import ObvMetaManager


// MARK: - Protocol States

extension OwnedDeviceDiscoveryProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initial = 0
        case waitingForServerQueryResult = 1
        case serverQueryProcessed = 2 // Final
        case waitingForUploadOfCurrentDevicePreKey = 3
        case cancelled = 100 // Final
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initial                              : return ConcreteProtocolInitialState.self
            case .waitingForServerQueryResult          : return WaitingForServerQueryResultState.self
            case .serverQueryProcessed                 : return ServerQueryProcessedState.self
            case .waitingForUploadOfCurrentDevicePreKey: return WaitingForUploadOfCurrentDevicePreKeyState.self
            case .cancelled                            : return CancelledState.self
            }
        }
    }
    
    
    // MARK: - WaitingForServerQueryResultState
    
    struct WaitingForServerQueryResultState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitingForServerQueryResult
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }

    
    // MARK: - ServerQueryProcessedState
    
    struct ServerQueryProcessedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.serverQueryProcessed
        
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

    
    // MARK: - WaitingForUploadOfCurrentDevicePreKeyState
    
    struct WaitingForUploadOfCurrentDevicePreKeyState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.cancelled
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }

}
