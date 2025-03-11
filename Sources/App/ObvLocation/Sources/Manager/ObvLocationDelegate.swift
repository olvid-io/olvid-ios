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

/// This is the class which received events from the `LocationManagerProtocol` implementation
/// and dispatches to the bridged tasks.
final class ObvLocationDelegate: NSObject, CLLocationManagerDelegate {
    
    private weak var locationTask: ObvLocationTask?
        
    init(locationTask: ObvLocationTask) {
        self.locationTask = locationTask
        super.init()
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard let locationTask else { return }
        let authorizationStatus = manager.authorizationStatus
        let accuracyAuthorization = manager.accuracyAuthorization
        Task {
            await locationTask.dispatchEvent(.didChangeAuthorization(authorizationStatus))
            await locationTask.dispatchEvent(.didChangeAccuracyAuthorization(accuracyAuthorization))
        }
    }
    
    // MARK: - Location Updates
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let locationTask else { return }
        Task {
            await locationTask.dispatchEvent(.receiveNewLocations(locations: locations))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let locationTask else { return }
        Task {
            await locationTask.dispatchEvent(.didFailWithError(error))
        }
    }
    
    
    // MARK: - Pause/Resume
    func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {
        guard let locationTask else { return }
        Task {
            await locationTask.dispatchEvent(.locationUpdatesPaused)
        }
    }
    
    func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {
        guard let locationTask else { return }
        Task {
            await locationTask.dispatchEvent(.locationUpdatesResumed)
        }
    }
    
}

extension CLLocationManager {
    func locationServicesEnabled() -> Bool {
        CLLocationManager.locationServicesEnabled()
    }
}
