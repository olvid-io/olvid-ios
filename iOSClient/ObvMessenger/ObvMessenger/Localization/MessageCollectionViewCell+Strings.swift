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

extension MessageCollectionViewCell {

    struct Strings {
        
        static let seeAttachments = { (count: Int) in
            return String.localizedStringWithFormat(NSLocalizedString("see count attachments", comment: "Number of attachments"), count)
        }

        static let replyToMessageWasDeleted = NSLocalizedString("Deleted message", comment: "Body displayed when a reply-to message was deleted.")
        
        static let replyToMessageUnavailable = NSLocalizedString("UNAVAILABLE_MESSAGE", comment: "Body displayed when a reply-to message cannot be found.")

    }
    
}
