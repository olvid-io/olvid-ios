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
import CoreLocation

extension ObvLocationTaskKind {
    
    actor Authorization: AnyObvLocationTask {
        
        typealias Stream = AsyncStream<StreamEvent>
        
        /// The event produced by the stream.
        enum StreamEvent {
            
            /// Authorization did change with a new value
            case didChangeAuthorization(_ status: CLAuthorizationStatus)
            
            /// The current status of the authorization.
            var authorizationStatus: CLAuthorizationStatus {
                switch self {
                case let .didChangeAuthorization(status):
                    return status
                }
            }
            
        }
        
        // MARK: - Properties
        
        let uuid = UUID()
        private(set) var stream: Stream.Continuation?
        var cancellable: ObvLocationCancellableTask?
        
        func setStream(to stream: Stream.Continuation) {            
            self.stream = stream
        }
        
        // MARK: - Functions
        
        func receivedLocationManagerEvent(_ event: ObvLocationManagerEvent) {
            switch event {
            case .didChangeAuthorization(let status):
                stream?.yield(.didChangeAuthorization(status))
            default:
                break
            }
        }
    }
    
}
