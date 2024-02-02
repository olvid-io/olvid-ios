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
import ObvTypes
import ObvCrypto
import ObvMetaManager


// MARK: - Protocol States

extension OwnedIdentityDeletionProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {

        case initialState = 0
        case firstDeletionStepPerformed = 1
        case final = 100

        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState              : return ConcreteProtocolInitialState.self
            case .firstDeletionStepPerformed: return FirstDeletionStepPerformedState.self
            case .final                     : return FinalState.self
            }
        }
    }
    
    
    // MARK: - FirstDeletionStepPerformedState
    
    struct FirstDeletionStepPerformedState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.firstDeletionStepPerformed
        let globalOwnedIdentityDeletion: Bool
        let propagationNeeded: Bool

        init(globalOwnedIdentityDeletion: Bool, propagationNeeded: Bool) {
            self.globalOwnedIdentityDeletion = globalOwnedIdentityDeletion
            self.propagationNeeded = propagationNeeded
        }
        
        func obvEncode() -> ObvEncoded {
            return  [
                globalOwnedIdentityDeletion,
                propagationNeeded,
            ].obvEncode()
        }
        
        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); throw Self.makeError(message: "Unexpected number of elements in encoded DeletionCurrentStatusState") }
            (globalOwnedIdentityDeletion, propagationNeeded) = try encodedValues.obvDecode()
        }

    }

    
    // MARK: - FinalState
    
    struct FinalState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.final
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }
    
}
