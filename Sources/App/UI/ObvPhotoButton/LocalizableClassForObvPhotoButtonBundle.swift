/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


/// This is a dummy class, allowing to specify the appropriate module when declaring a localized string, so that the localized string key is looked up in the correct `Localizable.xcstrings` file.
final class LocalizableClassForObvPhotoButtonBundle {}


func NSLocalizedString(_ key: String, comment: String) -> String {
    return NSLocalizedString(key, tableName: "Localizable", bundle: Bundle(for: LocalizableClassForObvPhotoButtonBundle.self), comment: comment)
}


func NSLocalizedString(_ key: String) -> String {
    return NSLocalizedString(key, tableName: "Localizable", bundle: Bundle(for: LocalizableClassForObvPhotoButtonBundle.self), comment: "Within ObvPhotoButton")
}


extension Text {
  
    init(_ key: LocalizedStringKey, comment: StaticString? = nil) {
        self.init(key, tableName: "Localizable", bundle: Bundle(for: LocalizableClassForObvPhotoButtonBundle.self), comment: comment ?? "Within ObvPhotoButton")
    }

}


extension Label where Title == Text, Icon == Image {
    
    init(_ titleKey: LocalizedStringKey, systemIcon icon: SystemIcon) {
        self.init(title: {
            Text(titleKey)
        }, icon: {
            Image(systemIcon: icon)
        })
    }

}
