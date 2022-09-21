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
import ObvTypes
import ObvMetaManager
import OlvidUtils

public final class ObvNotificationCenter: ObvNotificationDelegate {
    
    static let defaultLogSubsystem = "io.olvid.notification.center"
    public private(set) var logSubsystem = ObvNotificationCenter.defaultLogSubsystem
    
    private let internalNotificationCenter = NotificationCenter()

    private var blockedNotifications = Set<NSNotification.Name>()
    
    private let internalQueue = DispatchQueue(label: "ObvNotificationCenterQueue", qos: DispatchQoS.default)
    
    public init() {}
}

// MARK: Implementing ObvNotificationDelegate
extension ObvNotificationCenter {

    public func addObserver(forName name: NSNotification.Name, using block: @escaping (Notification) -> Void) -> NSObjectProtocol {
        return internalNotificationCenter.addObserver(forName: name, object: nil, queue: nil, using: block)
    }

    public func addObserver(forName name: NSNotification.Name, queue: OperationQueue?, using block: @escaping (Notification) -> Void) -> NSObjectProtocol {
        return internalNotificationCenter.addObserver(forName: name, object: nil, queue: queue, using: block)
    }

    public func removeObserver(_ observer: Any) {
        internalNotificationCenter.removeObserver(observer)
    }
    
    public func post(name: NSNotification.Name, userInfo: [AnyHashable: Any]? = nil) {
        var isBlocked = false
        internalQueue.sync {
            isBlocked = blockedNotifications.contains(name)
        }
        if !isBlocked {
            internalNotificationCenter.post(name: name, object: nil, userInfo: userInfo)
        }
    }
    
    public func blockNotification(name: NSNotification.Name) {
        internalQueue.sync {
            _ = blockedNotifications.insert(name)
        }
    }
    
    public func unblockNotification(name: NSNotification.Name) {
        internalQueue.sync {
            _ = blockedNotifications.remove(name)
        }
    }
}

// MARK: Implementing ObvManager
extension ObvNotificationCenter {

    public var requiredDelegates: [ObvEngineDelegateType] { return [] }

    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}

    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }

    static public var bundleIdentifier: String { return "io.olvid.ObvNotificationCenter" }
    static public var dataModelNames: [String] { return [] }
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {}

}
