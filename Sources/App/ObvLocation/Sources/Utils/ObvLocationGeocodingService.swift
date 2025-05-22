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

@available(iOS 17.0, *)
actor ObvLocationGeocodingService {
    
    private var previousLocationAndAddress: LocationAndAddress?
    
    static let shared = ObvLocationGeocodingService()
    
    private init() {}
        
    func reverseGeocoding(from location: CLLocation) async throws -> String? {
        
        if let previousLocationAndAddress, previousLocationAndAddress.location == location {
            return previousLocationAndAddress.address
        }
        
        let geocoder = CLGeocoder()
        
        let placemark = try await geocoder.reverseGeocodeLocation(location).first
        let address = placemark?.address

        self.previousLocationAndAddress = .init(location: location, address: address)

        return address
        
    }
}


private struct LocationAndAddress: Equatable {
    let location: CLLocation
    let address: String?
}
