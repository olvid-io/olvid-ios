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
import CoreData
import ObvTypes
import ObvCrypto
import OlvidUtils

public struct ObvChannelNotification {
    
    public struct NewUserDialogToPresent {
        public static let name = NSNotification.Name("ObvChannelNotification.NewUserDialogToPresent")
        public struct Key {
            public static let obvChannelDialogMessageToSend = "obvChannelDialogMessageToSend" // ObvChannelDialogMessageToSend
            public static let obvContext = "obvContext"
        }
        public static func parse(_ notification: Notification) -> (obvChannelDialogMessageToSend: ObvChannelDialogMessageToSend, context: ObvContext)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let obvChannelDialogMessageToSend = userInfo[Key.obvChannelDialogMessageToSend] as? ObvChannelDialogMessageToSend else { return nil }
            guard let obvContext = userInfo[Key.obvContext] as? ObvContext else { return nil }
            return (obvChannelDialogMessageToSend, obvContext)
        }
    }

    
    public struct NewConfirmedObliviousChannel {
        public static let name = NSNotification.Name("ObvChannelNotification.NewConfirmedObliviousChannel")
        public struct Key {
            public static let currentDeviceUid = "currentDeviceUid"
            public static let remoteCryptoIdentity = "remoteCryptoIdentity"
            public static let remoteDeviceUid = "remoteDeviceUid"
        }
        public static func parse(_ notification: Notification) -> (currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let currentDeviceUid = userInfo[Key.currentDeviceUid] as? UID else { return nil }
            guard let remoteCryptoIdentity = userInfo[Key.remoteCryptoIdentity] as? ObvCryptoIdentity else { return nil }
            guard let remoteDeviceUid = userInfo[Key.remoteDeviceUid] as? UID else { return nil }
            return (currentDeviceUid, remoteCryptoIdentity, remoteDeviceUid)
        }
    }
    
    
    public struct DeletedConfirmedObliviousChannel {
        public static let name = NSNotification.Name("ObvChannelNotification.DeletedConfirmedObliviousChannel")
        public struct Key {
            public static let currentDeviceUid = "currentDeviceUid"
            public static let remoteCryptoIdentity = "remoteCryptoIdentity"
            public static let remoteDeviceUid = "remoteDeviceUid"
        }
        public static func parse(_ notification: Notification) -> (currentDeviceUid: UID, remoteCryptoIdentity: ObvCryptoIdentity, remoteDeviceUid: UID)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let currentDeviceUid = userInfo[Key.currentDeviceUid] as? UID else { return nil }
            guard let remoteCryptoIdentity = userInfo[Key.remoteCryptoIdentity] as? ObvCryptoIdentity else { return nil }
            guard let remoteDeviceUid = userInfo[Key.remoteDeviceUid] as? UID else { return nil }
            return (currentDeviceUid, remoteCryptoIdentity, remoteDeviceUid)
        }
    }

    
    public struct NetworkReceivedMessageWasProcessed {
        public static let name = NSNotification.Name("ObvChannelNotification.NetworkReceivedMessageWasProcessed")
        public struct Key {
            public static let messageId = "messageId"
            public static let flowId = "flowId"
        }
        public static func parse(_ notification: Notification) -> (messageId: MessageIdentifier, flowId: FlowIdentifier)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let messageId = userInfo[Key.messageId] as? MessageIdentifier else { return nil }
            guard let flowId = userInfo[Key.flowId] as? FlowIdentifier else { return nil }
            return (messageId, flowId)
        }
    }
}
