/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


enum TransferTransportLayerState: Equatable {
    case initial
    case initializing // transport layer is starting
    case connecting // transport layer is establishing a connection to the peer
    case ready // transport layer is functional, messages can be sent
    case closed(exportWasCancelledByUser: Bool) // transport layer closed
    
    var isClosed: Bool {
        switch self {
        case .closed(exportWasCancelledByUser: _):
            return true
        default:
            return false
        }
    }
    
}


extension TransferTransportLayerState: CustomStringConvertible {
    
    var description: String {
        switch self {
        case .initial: return "initial"
        case .initializing: return "initializing"
        case .connecting: return "connecting"
        case .ready: return "ready"
        case .closed(exportWasCancelledByUser: let exportWasCancelledByUser): return "closed(exportWasCancelledByUser: \(exportWasCancelledByUser))"
        }
    }
        
}
