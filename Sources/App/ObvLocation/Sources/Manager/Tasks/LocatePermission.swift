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
    
    actor LocatePermission: AnyObvLocationTask {
        
        typealias Continuation = CheckedContinuation<CLAuthorizationStatus, Error>
        
        // MARK: - Properties
        
        let uuid = UUID()
        var cancellable: ObvLocationCancellableTask?
        var continuation: Continuation?
        private var permissionRequested = false
        
        // MARK: - Private Properties
        
        private weak var locationManager: ObvLocationManager?
        
        // MARK: - Initialization
        
        init(locationManager: ObvLocationManager) {
            self.locationManager = locationManager
        }
        
        // MARK: - Functions
        
        func receivedLocationManagerEvent(_ event: ObvLocationManagerEvent) {
            switch event {
            case .didChangeAuthorization(let authorization):
                guard let continuation else {
                    Task {
                        await cancellable?.cancel(task: self)
                    }
                    return
                }
                guard authorization != .notDetermined else { return }
                continuation.resume(returning: authorization)
                self.continuation = nil
                Task {
                    await cancellable?.cancel(task: self)
                }
            default:
                break
            }
        }
        

        func requestWhenInUsePermissionIfNotDetermined() async throws -> CLAuthorizationStatus {
            guard !permissionRequested else { assertionFailure("This method cannot be called twice as this could lead to a leaked continuation"); throw ObvError.cannotRequestPermissionTwice }
            permissionRequested = true
            guard let locationManager = self.locationManager else { assertionFailure(); throw ObvLocationError.locationManagerIsNil }
            // Make sure the current status is "not determined". Otherwise, return the current authorization status.
            let currentAuthorizationStatus = await locationManager.authorizationStatus
            guard currentAuthorizationStatus == .notDetermined else { return currentAuthorizationStatus }
            // The current status is "not determined". Request more.
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                Task { await locationManager.requestWhenInUsePermission(for: self) }
            }
        }
        
        
        func requestAlwaysPermissionIfNotDetermined() async throws -> CLAuthorizationStatus {
            guard !permissionRequested else { assertionFailure("This method cannot be called twice as this could lead to a leaked continuation"); throw ObvError.cannotRequestPermissionTwice }
            permissionRequested = true
            guard let locationManager = self.locationManager else { assertionFailure(); throw ObvLocationError.locationManagerIsNil }
            // Make sure the current status is "not determined". Otherwise, return the current authorization status.
            let currentAuthorizationStatus = await locationManager.authorizationStatus
            guard currentAuthorizationStatus == .notDetermined else { return currentAuthorizationStatus }
            // The current status is "not determined". Request more.
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                Task { await locationManager.requestAlwaysAuthorization(for: self) }
            }
        }
        
    }
    
    // MARK: - Errors
    
    enum ObvError: Error {
        case cannotRequestPermissionTwice
    }
    
}
