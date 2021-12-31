/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


enum ObvNewFeatures: CaseIterable {
    
    static private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)!
    
    /// This structure represent the Privacy tab in the settings. Using this preference allows
    /// to display a badge on the setting tab and on the Privacy row in the settings VC, allowing
    /// the user to notice this new feature.
    case PrivacySetting
    
    /// The key used for storing values in the user defaults
    private var userDefaultsKey: String {
        switch self {
        case .PrivacySetting: return "obvNewFeatures.privacySetting.wasSeenByUser"
        }
    }
    
    
    var seenByUser: Bool {
        ObvNewFeatures.userDefaults.boolOrNil(forKey: self.userDefaultsKey) ?? false
    }
    
    func markSeenByUser(to value: Bool) {
        ObvNewFeatures.userDefaults.setValue(value, forKey: self.userDefaultsKey)
    }
    
    
    /// This is typically called when Olvid is installed. This prevents showing all features as "new" to a new user.
    static func markAllAsSeenByUser() {
        for feature in ObvNewFeatures.allCases {
            feature.markSeenByUser(to: true)
        }
    }
    
    
    /// This is a convenience method that returns `true` whenever there is a new feature (not seen by the user)
    /// within the App settings
    static var settingsHaveNewFeature: Bool {
        for feature in ObvNewFeatures.allCases {
            switch feature {
            case .PrivacySetting:
                if !feature.seenByUser { return true }
            }
        }
        return false
    }
}
