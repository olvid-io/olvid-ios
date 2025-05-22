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


struct LearnMoreURLs {
    struct iCloudKeychain {
        static var url: URL? {
            if #available(iOS 16, *) {
                let languageCode = Locale.current.language.languageCode
                if languageCode == .french {
                    return URL(string: "https://support.apple.com/fr-fr/109016")
                } else {
                    return URL(string: "https://support.apple.com/en-us/109016")
                }
            } else {
                return URL(string: "https://support.apple.com/en-us/109016")
            }
        }
    }
}
