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

/// This is the list of events who can be received by any task.
enum ObvLocationManagerEvent {
    
    // MARK: - Authorization
    case didChangeLocationEnabled(_ enabled: Bool)
    case didChangeAuthorization(_ status: CLAuthorizationStatus)
    case didChangeAccuracyAuthorization(_ authorization: CLAccuracyAuthorization)

    // MARK: - Location Monitoring
    case locationUpdatesPaused
    case locationUpdatesResumed
    case receiveNewLocations(locations: [CLLocation])
    

    // MARK: - Failures
    case didFailWithError(_ error: Error)
}
