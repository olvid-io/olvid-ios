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
import ObvCrypto
import ObvTypes
import OlvidUtils

public enum ObvProtocolNotificationNew {
    
    case mutualScanContactAdded(ownedIdentity: ObvCryptoIdentity, contactIdentity: ObvCryptoIdentity, signature: Data)
    
    private enum Name {
        case mutualScanContactAdded
        
        private var namePrefix: String { String(describing: ObvProtocolNotificationNew.self) }

        private var nameSuffix: String { String(describing: self) }

        var name: NSNotification.Name {
            let name = [namePrefix, nameSuffix].joined(separator: ".")
            return NSNotification.Name(name)
        }

        static func forInternalNotification(_ notification: ObvProtocolNotificationNew) -> NSNotification.Name {
            switch notification {
            case .mutualScanContactAdded: return Name.mutualScanContactAdded.name
            }
        }
    }
    
    private var userInfo: [AnyHashable: Any]? {
        let info: [AnyHashable: Any]?
        switch self {
        case .mutualScanContactAdded(ownedIdentity: let ownedIdentity, contactIdentity: let contactIdentity, signature: let signature):
            info = [
                "ownedIdentity": ownedIdentity,
                "contactIdentity": contactIdentity,
                "signature": signature,
            ]
        }
        return info
    }
    
    
    public static func observeMutualScanContactAdded(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (ObvCryptoIdentity, ObvCryptoIdentity, Data) -> Void) -> NSObjectProtocol {
        let name = Name.mutualScanContactAdded.name
        return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
            let ownedIdentity = notification.userInfo!["ownedIdentity"] as! ObvCryptoIdentity
            let contactIdentity = notification.userInfo!["contactIdentity"] as! ObvCryptoIdentity
            let signature = notification.userInfo!["signature"] as! Data
            block(ownedIdentity, contactIdentity, signature)
        }
    }

    
    public func postOnBackgroundQueue(object anObject: Any? = nil) {
        let name = Name.forInternalNotification(self)
        postOnBackgroundQueue(withLabel: "Queue for posting \(name.rawValue) notification", object: anObject)
    }

    func postOnBackgroundQueue(_ queue: DispatchQueue) {
        let name = Name.forInternalNotification(self)
        queue.async {
            NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
        }
    }

    private func postOnBackgroundQueue(withLabel label: String, object anObject: Any? = nil) {
        let name = Name.forInternalNotification(self)
        let userInfo = self.userInfo
        DispatchQueue(label: label).async {
            NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
        }
    }

}

public struct ObvProtocolNotification {
    
    public struct ProtocolMessageToProcess {
        public static let name = Notification.Name("ObvProtocolNotification.ProtocolMessageToProcess")
        public struct Key {
            public static let protocolMessageId = "protocolMessageId"
            public static let flowId = "flowId"
        }
        public static func parse(_ notification: Notification) -> (protocolMessageId: MessageIdentifier, flowId: FlowIdentifier)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let protocolMessageId = userInfo[Key.protocolMessageId] as? MessageIdentifier else { return nil }
            guard let flowId = userInfo[Key.flowId] as? FlowIdentifier else { return nil }
            return (protocolMessageId, flowId)
        }
    }
        
    public struct ProtocolMessageProcessed {
        public static let name = Notification.Name("ObvProtocolNotification.ProtocolMessageProcessed")
        public struct Key {
            public static let protocolMessageId = "protocolMessageId"
            public static let flowId = "flowId"
        }
        public static func parse(_ notification: Notification) -> (protocolMessageId: MessageIdentifier, flowId: FlowIdentifier)? {
            guard notification.name == name else { return nil }
            guard let userInfo = notification.userInfo else { return nil }
            guard let protocolMessageId = userInfo[Key.protocolMessageId] as? MessageIdentifier else { return nil }
            guard let flowId = userInfo[Key.flowId] as? FlowIdentifier else { return nil }
            return (protocolMessageId, flowId)
        }
    }

}
