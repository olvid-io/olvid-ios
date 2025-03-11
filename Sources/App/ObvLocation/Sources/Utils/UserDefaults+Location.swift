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

extension UserDefaults {
        
    func set(location:CLLocation?, forKey key: String) {
        guard let location else {
            removeObject(forKey: key)
            return
        }
        
        let locationData = try? NSKeyedArchiver.archivedData(withRootObject: location, requiringSecureCoding: false)
        set(locationData, forKey: key)
    }
    
    func location(forKey key: String) -> CLLocation? {
        guard let locationData = data(forKey: key) else {
            return nil
        }

        do {
            return try NSKeyedUnarchiver.unarchivedObject(ofClass: CLLocation.self, from: locationData)
        } catch {
            return nil
        }
    }
    
}
