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
import SwiftUI
import ObvSystemIcon


extension Text {
    
    init(_ key: LocalizedStringKey, comment: StaticString? = nil) {
        self.init(key, tableName: "Localizable", bundle: Bundle(for: ObvOnboardingResources.self), comment: comment ?? "Within ObvOnboarding")
    }
    
}


extension Color {
    
    static let blue01: Color = Color("Blue01", bundle: Bundle(for: ObvOnboardingResources.self))
    static let textFieldBackgroundColor: Color = Color("TextFieldBackgroundColor", bundle: Bundle(for: ObvOnboardingResources.self))
    
}


extension Label where Title == Text, Icon == Image {

    init(_ titleKey: LocalizedStringKey, systemIcon icon: SystemIcon) {
        self.init {
            Text(titleKey)
        } icon: {
            Image(systemName: icon.name)
        }
    }

}

extension String {
    
    var localizedInThisBundle: String {
        Bundle(for: ObvOnboardingResources.self).localizedString(forKey: self, value: nil, table: "Localizable")
    }
    
    init(localizedInThisBundle: LocalizationValue) {
        self.init(localized: localizedInThisBundle, table: "Localizable", bundle: Bundle(for: ObvOnboardingResources.self))
    }
    
}
