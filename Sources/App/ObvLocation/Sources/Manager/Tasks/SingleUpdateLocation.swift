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
    
    actor SingleUpdateLocation: AnyObvLocationTask {
        
         typealias Continuation = CheckedContinuation<ContinuousUpdatedLocation.StreamEvent, Error>
        
        // MARK: - Properties

        let uuid = UUID()
        var cancellable: ObvLocationCancellableTask?
        private var continuation: Continuation?
        private var runCalled = false
        
        // MARK: - Private Properties
        private var timeout: TimeInterval?
        private weak var locationManager: ObvLocationManager?
        
        // MARK: - Initialization

        init(locationManager: ObvLocationManager, timeout: TimeInterval?) {
            self.locationManager = locationManager
            self.timeout = timeout
        }
        
        // MARK: - Functions

        func run() async throws -> ContinuousUpdatedLocation.StreamEvent {
            guard !runCalled else { assertionFailure("This method cannot be called twice as this could lead to a leaked continuation"); throw ObvError.cannotCallRunTwice }
            runCalled = true
            guard let locationManager else { assertionFailure(); throw ObvLocationError.locationManagerIsNil }
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                Task { await locationManager.requestLocation(for: self) }
            }
        }
        
        func receivedLocationManagerEvent(_ event: ObvLocationManagerEvent) {
            switch event {
            case let .receiveNewLocations(locations):
                continuation?.resume(returning: .didUpdateLocations(locations))
                continuation = nil
                Task {
                    await cancellable?.cancel(task: self)
                }
            case let .didFailWithError(error):
                continuation?.resume(returning: .didFail(error))
                continuation = nil
                Task {
                    await cancellable?.cancel(task: self)
                }
            default:
                break
            }
        }
        
        func didCancel() {
            continuation = nil
        }
        
        func willStart() {
            guard let timeout else {
                return
            }
            
            Task {
                try await Task.sleep(seconds: timeout)
                self.continuation?.resume(throwing: ObvLocationError.timeout)
                self.continuation = nil
                await self.cancellable?.cancel(task: self)
            }
        }
        
        enum ObvError: Error {
            case cannotCallRunTwice
        }
        
    }
    
}
