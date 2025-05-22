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

/// This is the class which received events from the `LocationManagerProtocol` implementation
/// and dispatches to the bridged tasks.
final class ObvLocationPermissionDelegate: NSObject, CLLocationManagerDelegate {
    
    private weak var locationTask: ObvLocationPermissionTask?
        
    init(locationTask: ObvLocationPermissionTask) {
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
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let locationTask else { return }
        Task {
            await locationTask.dispatchEvent(.didFailWithError(error))
        }
    }

}

extension CLLocationManager {
    func locationServicesEnabled() -> Bool {
        CLLocationManager.locationServicesEnabled()
    }
}
