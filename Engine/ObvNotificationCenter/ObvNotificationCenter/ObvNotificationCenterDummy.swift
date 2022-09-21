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
import os.log
import ObvTypes
import ObvMetaManager
import OlvidUtils


public final class ObvNotificationCenterDummy: ObvNotificationDelegate {
    
    static let defaultLogSubsystem = "io.olvid.notification.center"
    lazy public var logSubsystem: String = {
        return ObvNotificationCenterDummy.defaultLogSubsystem
    }()
    
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
        self.log = OSLog(subsystem: logSubsystem, category: "ObvNotificationCenterDummy")
    }

    // MARK: Instance variables
    
    private var log: OSLog
    private var discardableNotificationLogDisplayedAtLeastOnce = false
    
    // MARK: Initialiser
    
    public init() {
        self.log = OSLog(subsystem: ObvNotificationCenterDummy.defaultLogSubsystem, category: "ObvNotificationCenterDummy")
    }

    public func addObserver(forName name: NSNotification.Name, using: @escaping (Notification) -> Void) -> NSObjectProtocol {
        if acceptableDiscardedNotifications.contains(name) {
            if !discardableNotificationLogDisplayedAtLeastOnce {
                os_log("addObserver(forName: NSNotification.Name, using: @escaping (Notification) -> Void) does nothing in this dummy implementation", log: log, type: .debug)
                discardableNotificationLogDisplayedAtLeastOnce = true
            }
        } else {
            os_log("addObserver(forName: NSNotification.Name, using: @escaping (Notification) -> Void) does nothing in this dummy implementation. Discarding observer for notification %{public}@", log: log, type: .error, name.rawValue)
        }
        return NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "None"), object: self, queue: nil, using: { (_) in })
    }
    
    public func addObserver(forName name: NSNotification.Name, queue: OperationQueue?, using: @escaping (Notification) -> Void) -> NSObjectProtocol {
        os_log("addObserver(forName: NSNotification.Name, queue: OperationQueue?, using: @escaping (Notification) -> Void) does nothing in this dummy implementation. Discarding observer for notification %{public}@", log: log, type: .error, name.rawValue)
        return NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: "None"), object: self, queue: nil, using: { (_) in })
    }

    
    public func removeObserver(_: Any) {
        os_log("removeObserver(_: Any) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func post(name: NSNotification.Name, userInfo: [AnyHashable: Any]?) {
        os_log("post(name: NSNotification.Name, userInfo: [AnyHashable : Any]?) does nothing in this dummy implementation. Notification %{public}@ discarded.", log: log, type: .debug, name.rawValue)
    }
    
    public func blockNotification(name: NSNotification.Name) {
        os_log("blockNotification(name: NSNotification.Name) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    public func unblockNotification(name: NSNotification.Name) {
        os_log("unblockNotification(name: NSNotification.Name) does nothing in this dummy implementation", log: log, type: .error)
    }
    
    // MARK: - Implementing ObvManager
    
    public let requiredDelegates = [ObvEngineDelegateType]()
    
    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {}
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {}

    // MARK: - Notification names for which we should not generate a log within this dummy implementation
    private let acceptableDiscardedNotifications = Set<Notification.Name>([
        ObvNetworkFetchNotification.InboxMessageDeletedFromServerAndInboxes.name,
        ObvIdentityNotification.NewContactGroupJoined.name,
        ObvIdentityNotification.NewContactGroupOwned.name,
        ObvIdentityNotification.ContactGroupOwnedHasUpdatedPublishedDetails.name,
        ObvIdentityNotification.ContactGroupJoinedHasUpdatedPublishedDetails.name
        ])
}
