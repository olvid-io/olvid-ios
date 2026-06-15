/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

func NSLocalizedString(_ key: String, comment: String) -> String {
    return NSLocalizedString(key, tableName: "Localizable", bundle: ObvCompositionResources.bundle, comment: comment)
}


func NSLocalizedString(_ key: String) -> String {
    return NSLocalizedString(key, tableName: "Localizable", bundle: ObvCompositionResources.bundle, comment: "Within ObvComposition")
}


extension Text {
  
    init(_ key: LocalizedStringKey, comment: StaticString? = nil) {
        self.init(key, tableName: "Localizable", bundle: ObvCompositionResources.bundle, comment: comment ?? "Within ObvComposition")
    }

}

extension String {
    
    var localizedInThisBundle: String {
        ObvCompositionResources.bundle.localizedString(forKey: self, value: nil, table: "Localizable")
    }
    
    init(localizedInThisBundle: LocalizationValue) {
        self.init(localized: localizedInThisBundle, table: "Localizable", bundle: ObvCompositionResources.bundle)
    }
    
}
