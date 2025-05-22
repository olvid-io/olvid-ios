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


/// This struct is a trivial wrapper around a `CLLocationCoordinate2D`, allowing to conform to `Equatable`, `Hashable`, and `Sendable`
/// on an internal type instead on an Apple's type.
public struct ObvLocationCoordinate2D: Equatable, Hashable, Sendable {
    
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    
    public init(latitude: CLLocationDegrees, longitude: CLLocationDegrees) {
        self.latitude = latitude
        self.longitude = longitude
    }
    
    init(location: CLLocationCoordinate2D) {
        self.latitude = location.latitude
        self.longitude = location.longitude
    }
    
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
}
