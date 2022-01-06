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

extension DiscussionsSettingsTableViewController {
    
    struct Strings {
        struct SendReadRecceipts {
            static let explanationWhenYes = NSLocalizedString("Your contacts will be notified when you have read their messages. This settting can be overriden on a per discussion basis.", comment: "Explantation")
            static let explanationWhenNo = NSLocalizedString("Your contacts won't be notified when you read their messages. This settting can be overriden on a per discussion basis.", comment: "Explantation")
        }
        struct RichLinks {
            static let title = NSLocalizedString("Rich link preview", comment: "Cell title")
            static let sentMessagesOnly = NSLocalizedString("Sent messages only", comment: "")
        }
    }
    
}
