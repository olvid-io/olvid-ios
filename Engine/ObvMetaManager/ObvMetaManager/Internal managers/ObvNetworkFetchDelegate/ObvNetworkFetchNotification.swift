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
import ObvCrypto
import ObvTypes
import OlvidUtils


public struct ObvNetworkFetchNotification {
    
    
    public struct InboxMessageDeletedFromServerAndInboxes {
        public static let name = Notification.Name("ObvNetworkFetchNotification.InboxMessageDeletedFromServerAndInboxes")
        public struct Key {
            public static let messageId = "messageId"
            public static let flowId = "flowId"
        }
        public static func parse(_ notification: Notification) -> (messageId: ObvMessageIdentifier, flowId: FlowIdentifier)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let messageId = userInfo[Key.messageId] as? ObvMessageIdentifier else { return nil }
            guard let flowId = userInfo[Key.flowId] as? FlowIdentifier else { return nil }
            return (messageId, flowId)
        }
    }
    
    public struct NewReturnReceiptToProcess {
        public static let name = Notification.Name("ObvNetworkFetchNotification.NewReturnReceiptToProcess")
        public struct Key {
            public static let returnReceipt = "returnReceipt"
        }
        public static func parse(_ notification: Notification) -> ReturnReceipt? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let returnReceipt = userInfo[Key.returnReceipt] as? ReturnReceipt else { assert(false); return nil }
            return returnReceipt
        }
    }
}
