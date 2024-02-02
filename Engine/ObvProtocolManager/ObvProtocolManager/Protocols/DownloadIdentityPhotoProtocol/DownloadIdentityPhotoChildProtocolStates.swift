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

extension DownloadIdentityPhotoChildProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initialState = 0
        case downloadingPhoto = 1
        case photoDownloaded = 2
        case cancelled = 3
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState     : return ConcreteProtocolInitialState.self
            case .downloadingPhoto : return DownloadingPhotoState.self
            case .photoDownloaded  : return PhotoDownloadedState.self
            case .cancelled        : return CancelledState.self
            }
        }
    }
    
    // MARK: - DownloadingPhotoState
    
    struct DownloadingPhotoState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.downloadingPhoto
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityDetailsElements: IdentityDetailsElements
        
        func obvEncode() -> ObvEncoded {
            let encodedContactIdentityDetailsElements = try! contactIdentityDetailsElements.jsonEncode()
            return [contactIdentity, encodedContactIdentityDetailsElements].obvEncode()
        }
        
        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 2) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            self.contactIdentity = try encodedElements[0].obvDecode()
            let encodedContactIdentityDetailsElements: Data = try encodedElements[1].obvDecode()
            self.contactIdentityDetailsElements = try IdentityDetailsElements(encodedContactIdentityDetailsElements)
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) {
            self.contactIdentity = contactIdentity
            self.contactIdentityDetailsElements = contactIdentityDetailsElements
        }

    }
    
    
    // MARK: - PhotoDownloadedState
    
    struct PhotoDownloadedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.photoDownloaded
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
        init(_ encoded: ObvEncoded) throws {}
        
        init() {}
        
    }
    
    
    // MARK: - CancelledState
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.cancelled
        
        init(_: ObvEncoded) throws {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }

}
