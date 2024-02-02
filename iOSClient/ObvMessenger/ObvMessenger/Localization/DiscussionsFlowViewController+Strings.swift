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

extension DiscussionsFlowViewController {

    struct Strings {
        
        struct AlertConfirmAllDiscussionMessagesDeletion {
            static let title = NSLocalizedString("Delete all messages?", comment: "Alert title")
            static let message = NSLocalizedString("Do you wish to delete all the messages within this discussion? This action is irreversible.", comment: "Alert message")
            static let actionDeleteAll = NSLocalizedString("Delete all messages", comment: "Alert action title")
            static let actionDeleteAllGlobally = NSLocalizedString("Delete all messages for all users", comment: "Alert action title")
        }
        
        struct AlertConfirmAllDiscussionMessagesDeletionGlobally {
            static let title = NSLocalizedString("Delete all messages for all users?", comment: "Alert title")
            static let message = NSLocalizedString("DELETE_ALL_MSGS_ON_ALL_DEVICES__ACTION_IRREVERSIBLE", comment: "Alert message")
            static let actionDeleteAllGlobally = NSLocalizedString("Delete all messages for all users", comment: "Alert action title")
        }
    }

    
}
