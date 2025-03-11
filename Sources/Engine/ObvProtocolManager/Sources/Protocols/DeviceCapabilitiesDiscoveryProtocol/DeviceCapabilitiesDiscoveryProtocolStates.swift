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


extension DeviceCapabilitiesDiscoveryProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initial = 0
        case finished = 1
        case cancelled = 2
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initial   : return ConcreteProtocolInitialState.self
            case .finished  : return FinishedState.self
            case .cancelled : return CancelledState.self
            }
        }
        
    }

    
    struct FinishedState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.finished

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
