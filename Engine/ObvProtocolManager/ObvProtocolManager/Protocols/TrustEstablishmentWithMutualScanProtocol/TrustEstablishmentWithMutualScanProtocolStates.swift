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
import ObvEncoder
import ObvCrypto


extension TrustEstablishmentWithMutualScanProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case Initial = 0
        case WaitingForConfirmation = 1
        case Finished = 2
        case Cancelled = 3
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .Initial                : return ConcreteProtocolInitialState.self
            case .WaitingForConfirmation : return WaitingForConfirmationState.self
            case .Finished               : return FinishedState.self
            case .Cancelled: return CancelledState.self
            }
        }
        
    }

    
    struct WaitingForConfirmationState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.WaitingForConfirmation

        let bobIdentity: ObvCryptoIdentity

        func encode() -> ObvEncoded { [bobIdentity].encode() }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded].init(encoded, expectedCount: 1) else { throw NSError() }
            self.bobIdentity = try encodedElements[0].decode()
        }

        init(bobIdentity: ObvCryptoIdentity) {
            self.bobIdentity = bobIdentity
        }

    }

    
    struct FinishedState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.Finished

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
