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
import ObvTypes
import ObvCrypto
import ObvMetaManager

// MARK: - Protocol States

extension GroupManagementProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case InitialState = 0
        case Final = 1
        case Cancelled = 9
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState      : return ConcreteProtocolInitialState.self
            case .Final             : return FinalState.self
            case .Cancelled         : return CancelledState.self
            }
        }
    }
    
    
    // MARK: - FinalState
    
    struct FinalState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Final
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }
        
    }

    
    // MARK: - CancelledState
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Cancelled
        
        init(_: ObvEncoded) throws {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }
        
    }

}
