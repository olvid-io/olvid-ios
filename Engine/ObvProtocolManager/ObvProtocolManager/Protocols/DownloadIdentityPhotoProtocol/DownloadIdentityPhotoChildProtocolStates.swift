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

extension DownloadIdentityPhotoChildProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case InitialState = 0
        case DownloadingPhoto = 1
        case PhotoDownloaded = 2
        case Cancelled = 3
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .InitialState     : return ConcreteProtocolInitialState.self
            case .DownloadingPhoto : return DownloadingPhotoState.self
            case .PhotoDownloaded  : return PhotoDownloadedState.self
            case .Cancelled        : return CancelledState.self
            }
        }
    }
    
    // MARK: - DownloadingPhotoState
    
    struct DownloadingPhotoState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.DownloadingPhoto
        
        let contactIdentity: ObvCryptoIdentity
        let contactIdentityDetailsElements: IdentityDetailsElements
        
        func encode() -> ObvEncoded {
            let encodedContactIdentityDetailsElements = try! contactIdentityDetailsElements.encode()
            return [contactIdentity, encodedContactIdentityDetailsElements].encode()
        }
        
        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 2) else { throw NSError() }
            self.contactIdentity = try encodedElements[0].decode()
            let encodedContactIdentityDetailsElements: Data = try encodedElements[1].decode()
            self.contactIdentityDetailsElements = try IdentityDetailsElements(encodedContactIdentityDetailsElements)
        }
        
        init(contactIdentity: ObvCryptoIdentity, contactIdentityDetailsElements: IdentityDetailsElements) {
            self.contactIdentity = contactIdentity
            self.contactIdentityDetailsElements = contactIdentityDetailsElements
        }

    }
    
    
    // MARK: - PhotoDownloadedState
    
    struct PhotoDownloadedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.PhotoDownloaded
        
        func encode() -> ObvEncoded { return 0.encode() }
        
        init(_ encoded: ObvEncoded) throws {}
        
        init() {}
        
    }
    
    
    // MARK: - CancelledState
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Cancelled
        
        init(_: ObvEncoded) throws {}
        
        init() {}
        
        func encode() -> ObvEncoded { return 0.encode() }
        
    }

}
