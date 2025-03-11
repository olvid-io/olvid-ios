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
    
    actor ContinuousUpdatedLocation: AnyObvLocationTask {
        
        typealias Stream = AsyncStream<StreamEvent>
        
        /// The event produced by the stream.
        enum StreamEvent: CustomStringConvertible, Equatable {
            
            /// A new array of locations has been received.
            case didUpdateLocations(_ locations: [CLLocation])
            
            /// Something went wrong while reading new locations.
            case didFail(_ error: Error)
            
            /// Location updates did resume.
            case didResume
            
            /// Location updates did pause.
            case didPause
            
            /// Return the location received by the event if it's a location event.
            /// In case of multiple events it will return the most recent one.
            var location: CLLocation? {
                locations?.max(by: { $0.timestamp < $1.timestamp })
            }
            
            /// Return the list of locations received if the event is a location update.
            var locations: [CLLocation]? {
                guard case .didUpdateLocations(let locations) = self else {
                    return nil
                }
                return locations
            }
            
            /// Error received if any.
            var error: Error? {
                guard case .didFail(let error) = self else {
                    return nil
                }
                return error
            }
            
            var description: String {
                switch self {
                case .didPause:
                    return "paused"
                case .didResume:
                    return "resume"
                case let .didFail(error):
                    return "error \(error.localizedDescription)"
                case let .didUpdateLocations(locations):
                    return "\(locations.count) locations"
                }
            }
            
            static func == (lhs: ObvLocationTaskKind.ContinuousUpdatedLocation.StreamEvent, rhs: ObvLocationTaskKind.ContinuousUpdatedLocation.StreamEvent) -> Bool {
                switch (lhs, rhs) {
                case (.didFail(let lhError), .didFail(let rhError)):
                    return lhError.localizedDescription == rhError.localizedDescription
                #if os(iOS)
                case (.didPause, .didPause):
                    return true
                case (.didResume, .didResume):
                    return true
                #endif
                case (.didUpdateLocations(let lhLocation), .didUpdateLocations(let rhLocation)):
                    return lhLocation == rhLocation
                default:
                    return false
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
            case .locationUpdatesPaused:
                stream?.yield(.didPause)
                
            case .locationUpdatesResumed:
                stream?.yield(.didResume)
                
            case let .didFailWithError(error):
                stream?.yield(.didFail(error))
                
            case let .receiveNewLocations(locations):
                stream?.yield(.didUpdateLocations(locations))
                
            default:
                break
            }
        }
        
        func didCancel() {
            guard let stream = stream else {
                return
            }
            
            stream.finish()
            self.stream = nil
        }
        
    }
    
    
}
