/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvMetaManager

final class ObvFlowDelegateManager {
 
    static let defaultLogSubsystem = "io.olvid.flow"
    private(set) var logSubsystem = ObvFlowDelegateManager.defaultLogSubsystem
    
    func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }
    
    // MARK: Internal delegates
    
    let simpleBackgroundTaskDelegate: SimpleBackgroundTaskDelegate
    let backgroundTaskDelegate: BackgroundTaskDelegate? // Nil when used within an extension
    // let remoteNotificationDelegate: RemoteNotificationDelegate
    
    // MARK: Instance variables (external delegates). Thanks to a mecanism within the DelegateManager, we know for sure that these delegates will be instantiated by the time the Manager is fully initialized. So we can safely force unwrapping.
    
    weak var notificationDelegate: ObvNotificationDelegate! {
        didSet {
            backgroundTaskDelegate?.observeEngineNotifications()
        }
    }
    
    init(simpleBackgroundTaskDelegate: SimpleBackgroundTaskDelegate, backgroundTaskDelegate: BackgroundTaskDelegate?) { //, remoteNotificationDelegate: RemoteNotificationDelegate) {
        self.simpleBackgroundTaskDelegate = simpleBackgroundTaskDelegate
        self.backgroundTaskDelegate = backgroundTaskDelegate
    }
    
}
