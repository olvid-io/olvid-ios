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
import OlvidUtils

/// All the manager managed by the ObvMetaManager must implement this protocol.
public protocol ObvManager: AnyObject {
    
    var logSubsystem: String { get }
    func prependLogSubsystem(with: String)
    
    func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws
    var requiredDelegates: [ObvEngineDelegateType] { get }
    
    func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws
    func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async
    
}
