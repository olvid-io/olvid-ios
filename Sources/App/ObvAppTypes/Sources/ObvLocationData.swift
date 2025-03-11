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


public struct ObvLocationData: Equatable, Sendable {
    public let timestamp: Date? // location timestamp
    public let latitude: Double
    public let longitude: Double
    public let altitude: Double? // meters (default value null)
    public let precision: Double? // meters (default value null)
    public let address: String? // (default value empty string or null)
    
    public init(timestamp: Date?, latitude: Double, longitude: Double, altitude: Double?, precision: Double?, address: String?) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.precision = precision
        self.address = address
    }
    
    
    public init(clLocation: CLLocation) {
        self.init(timestamp: clLocation.timestamp,
                  latitude: clLocation.coordinate.latitude,
                  longitude: clLocation.coordinate.longitude,
                  altitude: clLocation.altitude,
                  precision: (clLocation.horizontalAccuracy + clLocation.verticalAccuracy) / 2.0,
                  address: nil)
    }
    
    
    public func withAddress(_ address: String?) -> Self {
        ObvLocationData.init(timestamp: timestamp,
                             latitude: latitude,
                             longitude: longitude,
                             altitude: altitude,
                             precision: precision,
                             address: address)
    }
    
}
