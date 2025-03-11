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
import OlvidUtils



// MARK: - Protocol States

extension ContactDeviceDiscoveryProtocol {
    
    
    enum StateId: Int, ConcreteProtocolStateId {

        case initialState = 0
        case waitingForChildProtocol = 1
        case childProtocolStateProcessed = 2
        case cancelled = 3

        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState                 : return ConcreteProtocolInitialState.self
            case .waitingForChildProtocol      : return WaitingForChildProtocolState.self
            case .childProtocolStateProcessed  : return ChildProtocolStateProcessedState.self
            case .cancelled                    : return CancelledState.self
            }
        }
    }
    
    struct WaitingForChildProtocolState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.waitingForChildProtocol
        
        let contactIdentity: ObvCryptoIdentity
        
        init(_ obvEncoded: ObvEncoded) throws {
            do {
                contactIdentity = try obvEncoded.obvDecode()
            } catch let error {
                throw error
            }
        }
        
        init(contactIdentity: ObvCryptoIdentity) {
            self.contactIdentity = contactIdentity
        }
        
        func obvEncode() -> ObvEncoded {
            return contactIdentity.obvEncode()
        }
    }

    struct ChildProtocolStateProcessedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.childProtocolStateProcessed
        
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
