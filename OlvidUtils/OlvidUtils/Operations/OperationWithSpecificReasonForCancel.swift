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
import CoreData


open class OperationWithSpecificReasonForCancel<ReasonForCancelType: LocalizedErrorWithLogType>: Operation {
    
    public var reasonForCancel: ReasonForCancelType?

    public func logReasonIfCancelled(log: OSLog) {
        assert(isFinished)
        guard isCancelled else { return }
        guard let reason = self.reasonForCancel else {
            os_log("%{public}@ cancelled without providing a reason. This is a bug", log: log, type: .fault, String(describing: self))
            assertionFailure()
            return
        }
        os_log("%{public}@ cancelled: %{public}@", log: log, type: reason.logType, String(describing: self), reason.localizedDescription)
        if reason.logType == .fault {
            assertionFailure()
        }
    }

    
    open func cancel(withReason reason: ReasonForCancelType) {
        assert(self.reasonForCancel == nil)
        self.reasonForCancel = reason
        self.cancel()
    }

}



public protocol OperationThatCanLogReasonForCancel: Operation {
    func logReasonIfCancelled(log: OSLog)
}
extension OperationWithSpecificReasonForCancel: OperationThatCanLogReasonForCancel {}



public protocol LocalizedErrorWithLogType: LocalizedError {
    var logType: OSLogType { get }
}



/// This is an example of a simple enum implementing `LocalizedErrorWithLogType` that can we used within operations that can only fail when a Core Data error occurs.
public enum CoreDataOperationReasonForCancel: LocalizedErrorWithLogType {
    
    case coreDataError(error: Error)
    case contextIsNil

    public var logType: OSLogType {
        switch self {
        case .coreDataError, .contextIsNil:
            return .fault
        }
    }

    public var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        }
    }

}
