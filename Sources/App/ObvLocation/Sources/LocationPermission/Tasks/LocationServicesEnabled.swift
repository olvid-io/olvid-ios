/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import CoreLocation

extension ObvLocationTaskKind {
    
    actor LocationServicesEnabled: AnyObvLocationPermissionTask {
        
        typealias Stream = AsyncStream<StreamEvent>
        
        /// The event produced by the stream.
        enum StreamEvent: CustomStringConvertible, Equatable {
            
            /// A new change in the location services status has been detected.
            case didChangeLocationEnabled(_ enabled: Bool)
            
            /// Return `true` if location service is enabled.
            var isLocationEnabled: Bool {
                switch self {
                case let .didChangeLocationEnabled(enabled):
                    return enabled
                }
            }
            
            var description: String {
                switch self {
                case .didChangeLocationEnabled:
                    return "didChangeLocationEnabled"
                    
                }
            }
            
        }
        
        // MARK: - Properties
        
        let uuid = UUID()
        var stream: Stream.Continuation?
        var cancellable: ObvLocationCancellableTask?
        
        // MARK: - Functions
        
        func receivedLocationManagerEvent(_ event: ObvLocationPermissionManagerEvent) {
            switch event {
            case .didChangeLocationEnabled(let enabled):
                stream?.yield(.didChangeLocationEnabled(enabled))
            default:
                break
            }
        }
        
    }
    
}
