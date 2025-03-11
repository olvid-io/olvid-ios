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

extension IdentityDetailsPublicationProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case InitialState = 0
        case UploadingPhoto = 1
        case DetailsSent = 2
        case DetailsReceived = 3
        case Cancelled = 4
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState    : return ConcreteProtocolInitialState.self
            case .UploadingPhoto  : return UploadingPhotoState.self
            case .DetailsSent     : return DetailsSentState.self
            case .DetailsReceived : return DetailsReceivedState.self
            case .Cancelled       : return CancelledState.self
            }
        }
    }

    
    // MARK: - UploadingPhotoState
    
    struct UploadingPhotoState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.UploadingPhoto
        
        let ownedIdentityDetailsElements: IdentityDetailsElements
        
        func obvEncode() -> ObvEncoded {
            let encodedOwnedIdentityDetailsElements = try! ownedIdentityDetailsElements.jsonEncode()
            return [encodedOwnedIdentityDetailsElements].obvEncode()
        }
        
        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 1) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            let encodedOwnedIdentityDetailsElements: Data = try encodedElements[0].obvDecode()
            self.ownedIdentityDetailsElements = try IdentityDetailsElements(encodedOwnedIdentityDetailsElements)
        }
        
        init(ownedIdentityDetailsElements: IdentityDetailsElements) {
            self.ownedIdentityDetailsElements = ownedIdentityDetailsElements
        }
        
    }
    
    
    // MARK: - DetailsSentState
    
    struct DetailsSentState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.DetailsSent

        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
        init(_ encoded: ObvEncoded) throws {}
        
        init() {}

    }
    
    
    // MARK: - DetailsReceivedState
    
    struct DetailsReceivedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.DetailsReceived
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
        init(_ encoded: ObvEncoded) throws {}
        
        init() {}

    }
    
    
    // MARK: - CancelledState
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Cancelled
        
        init(_: ObvEncoded) throws {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }

}
