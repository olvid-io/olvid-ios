/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import UI_ObvCircledInitials
import ObvUICoreData


extension OlvidCall: OlvidCallViewModelProtocol {
    
    typealias InitialCircleViewNewModel = PersistedObvOwnedIdentity

    var ownedInitialCircle: ObvUICoreData.PersistedObvOwnedIdentity {
        self.persistedObvOwnedIdentity
    }
    
    var localUserStillNeedsToAcceptOrRejectIncomingCall: Bool {
        switch self.direction {
        case .outgoing:
            return false
        case .incoming:
            switch self.state {
            case .initial:
                return true
            case .userAnsweredIncomingCall,
                    .gettingTurnCredentials,
                    .initializingCall,
                    .callInProgress,
                    .hangedUp,
                    .ringing,
                    .kicked,
                    .callRejected,
                    .unanswered,
                    .outgoingCallIsConnecting,
                    .reconnecting,
                    .answeredOnAnotherDevice:
                return false
            }
        }
    }

    
    /// We mirror the self video view when using the front camera, not the back.
    var doMirrorViewSelfVideoView: Bool {
        guard let currentCameraPosition = self.currentCameraPosition else { return false }
        switch currentCameraPosition {
        case .unspecified:
            return true
        case .back:
            return false
        case .front:
            return true
        @unknown default:
            return true
        }
    }

}
