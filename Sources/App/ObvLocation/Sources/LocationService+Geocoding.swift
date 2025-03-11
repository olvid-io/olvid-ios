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

extension ObvLocationService {
    
    private static let lastReverseGeocoded = LastReverseGeocoded()
    
    static func reverseGeocoding(from location: CLLocation) async throws -> String? {
        
        let (lastReverseGeocodedLocation, lastReverseGeocodedAddress) = await lastReverseGeocoded.locationAndAddress

        if lastReverseGeocodedLocation == location {
            return lastReverseGeocodedAddress
        }
        let geocoder = CLGeocoder()
        
        let placemark = try await geocoder.reverseGeocodeLocation(location).first
    
        await lastReverseGeocoded.set(location: location, address: placemark?.address)
        
        return lastReverseGeocodedAddress
    }
}


fileprivate actor LastReverseGeocoded {

    private var location: CLLocation?
    private var address: String?

    var locationAndAddress: (CLLocation?, String?) {
        (location, address)
    }
    
    func set(location: CLLocation, address: String?) {
        self.location = location
        self.address = address
    }
    
}
