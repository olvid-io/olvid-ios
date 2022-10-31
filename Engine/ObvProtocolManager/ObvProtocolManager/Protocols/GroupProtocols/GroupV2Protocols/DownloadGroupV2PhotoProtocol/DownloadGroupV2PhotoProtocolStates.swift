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
import ObvMetaManager


// MARK: - Protocol States

extension DownloadGroupV2PhotoProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case InitialState = 0
        case DownloadingPhoto = 1
        case PhotoDownloaded = 2
        case Cancelled = 99
        
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
        
        let groupIdentifier: GroupV2.Identifier
        let serverPhotoInfo: GroupV2.ServerPhotoInfo

        init(groupIdentifier: GroupV2.Identifier, serverPhotoInfo: GroupV2.ServerPhotoInfo) {
            self.groupIdentifier = groupIdentifier
            self.serverPhotoInfo = serverPhotoInfo
        }
        
        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 2) else { assertionFailure(); throw Self.makeError(message: "Unexpected number of elements in encoded DownloadingPhotoState") }
            self.groupIdentifier = try encodedValues[0].obvDecode()
            self.serverPhotoInfo = try encodedValues[1].obvDecode()
        }
        
        func obvEncode() -> ObvEncoded {
            [groupIdentifier.obvEncode(), serverPhotoInfo.obvEncode()].obvEncode()
        }

    }

    
    // MARK: - PhotoDownloadedState
    
    struct PhotoDownloadedState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.PhotoDownloaded
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }

    }

    
    // MARK: - CancelledState
    
    struct CancelledState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.Cancelled
        
        init(_: ObvEncoded) throws {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }

}
