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

extension DownloadGroupPhotoChildProtocol {

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

        let groupInformation: GroupInformation

        func obvEncode() -> ObvEncoded { [ groupInformation.obvEncode() ].obvEncode() }

        init(_ encoded: ObvEncoded) throws {
            guard let encodedElements = [ObvEncoded](encoded, expectedCount: 1) else { assertionFailure(); throw Self.makeError(message: "Could not obtain list of encoded elements") }
            self.groupInformation = try encodedElements[0].obvDecode()
        }

        init(groupInformation: GroupInformation) {
            self.groupInformation = groupInformation
        }

    }


    // MARK: - PhotoDownloadedState

    struct PhotoDownloadedState: TypeConcreteProtocolState {

        let id: ConcreteProtocolStateId = StateId.PhotoDownloaded

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
