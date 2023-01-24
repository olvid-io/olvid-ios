/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

extension DownloadsSettingsTableViewController {
    
    struct Strings {
        
        static let downloadSizeTitle = NSLocalizedString("Maximum size for automatic downloads", comment: "Table view group header")

        static let downloadSizeExplanation = { (size: String) in
            return String.localizedStringWithFormat(NSLocalizedString("Attachments smaller than %@ will be automatically downloaded. Larger attachments will require manual download.", comment: ""), size)
        }

        static let downloadSizeExplanationWhenUnlimited = NSLocalizedString("ALL_ATTACHMENTS_WILL_BE_AUTOMATICALLY_DOWNLOADED", comment: "")
        
    }
    
}
