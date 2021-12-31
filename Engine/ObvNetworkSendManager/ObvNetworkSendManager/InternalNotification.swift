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

public enum ObvNetworkSendManagerInternalNotification {
    
    // 2020-07-14 Not used anymore. We keep this code for now
    case attachmentUploadRequestIsTakenCareOfByShareExtension
    
    enum Name {
        case attachmentUploadRequestIsTakenCareOfByShareExtension

        private var namePrefix: String { return "ObvNetworkSendManagerInternalNotification" }
        
        private var nameSuffix: String {
            switch self {
            case .attachmentUploadRequestIsTakenCareOfByShareExtension: return "attachmentUploadRequestIsTakenCareOfByShareExtension"
            }
        }

        var name: NSNotification.Name {
            return NSNotification.Name(stringName)
        }
        
        var stringName: String {
            return [namePrefix, nameSuffix].joined(separator: ".")
        }
        
        static func forInternalNotification(_ notification: ObvNetworkSendManagerInternalNotification) -> NSNotification.Name {
            switch notification {
            case .attachmentUploadRequestIsTakenCareOfByShareExtension: return Name.attachmentUploadRequestIsTakenCareOfByShareExtension.name
            }
        }
        
        static func forDarwinPostNotification(_ notification: ObvNetworkSendManagerInternalNotification) -> CFNotificationName? {
            switch notification {
            case .attachmentUploadRequestIsTakenCareOfByShareExtension: return CFNotificationName(rawValue: Name.attachmentUploadRequestIsTakenCareOfByShareExtension.stringName as CFString)
            }
        }
        
        static func forDarwinObserveNotification(_ notification: ObvNetworkSendManagerInternalNotification) -> CFString? {
            switch notification {
            case .attachmentUploadRequestIsTakenCareOfByShareExtension: return Name.attachmentUploadRequestIsTakenCareOfByShareExtension.stringName as CFString
            }
        }
    }
    
    private var userInfo: [AnyHashable: Any]? {
        let info: [AnyHashable: Any]?
        switch self {
        case .attachmentUploadRequestIsTakenCareOfByShareExtension:
            info = nil
        }
        
        return info
    }
    
    func postOnDarwinNotificationCenter() throws {
        guard let name = Name.forDarwinPostNotification(self) else { throw NSError() }
        let nc = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(nc, name, nil, nil, true)
    }
    
    func post(within appNotificationCenter: NotificationCenter) {
        assert(self != .attachmentUploadRequestIsTakenCareOfByShareExtension)
        let name = Name.forInternalNotification(self)
        appNotificationCenter.post(name: name, object: nil, userInfo: userInfo)
    }
        
    func postOnDispatchQueue(withLabel label: String, within appNotificationCenter: NotificationCenter) {
        assert(self != .attachmentUploadRequestIsTakenCareOfByShareExtension)
        let name = Name.forInternalNotification(self)
        let userInfo = self.userInfo
        DispatchQueue(label: label).async {
            appNotificationCenter.post(name: name, object: nil, userInfo: userInfo)
        }
    }

    public static func observeAttachmentUploadRequestIsTakenCareOfByShareExtensionOnDarwinNotificationCenter(queue: OperationQueue? = nil, block: @escaping () -> Void) throws -> NSObjectProtocol {
        guard let darwinName = Name.forDarwinObserveNotification(.attachmentUploadRequestIsTakenCareOfByShareExtension) else { throw NSError() }
        let nc = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(nc, nil, { (_, _, _, _, _) in
            let standardName = Notification.Name(Name.forDarwinObserveNotification(.attachmentUploadRequestIsTakenCareOfByShareExtension)! as String)
            NotificationCenter.default.post(name: standardName, object: nil)
        }, darwinName, nil, .deliverImmediately)
        let standardName = Notification.Name(Name.forDarwinObserveNotification(.attachmentUploadRequestIsTakenCareOfByShareExtension)! as String)
        return NotificationCenter.default.addObserver(forName: standardName,
                                                      object: nil,
                                                      queue: queue) { (_) in
                                                        block() }
    }
    
    
}
