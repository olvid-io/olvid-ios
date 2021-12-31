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
import os.log


open class ObvOperationWithPriorityWrapper<WrappedObvOperationType: ObvOperationWithPriority>: ObvOperationWithPriority, OperationDelegate {

    override open var className: String {
        return "ObvOperationWithPriorityWrapper<\(wrappedOperation.className)>"
    }

    let log = OSLog(subsystem: ObvOperation.defaultLogSubsystem, category: "ObvOperationWithPriorityWrapper")

    public let wrappedOperation: WrappedObvOperationType

    public init(wrappedOperation: WrappedObvOperationType) {
        self.wrappedOperation = wrappedOperation
        super.init(uid: wrappedOperation.uid, priorityNumber: wrappedOperation.priorityNumber)
    }

    override open func execute() {
        os_log("Starting the execute() function of the ObvOperationWrapper", log: log, type: .debug)
        wrappedOperation.delegate = self
        let internalQueue = ObvOperationQueue()
        internalQueue.addOperation(wrappedOperation)
    }

    final func operationWillExecute(operation: Operation) {
        wrappedOperationDidStart(operation: operation as! WrappedObvOperationType)
    }

    final func operationDidFinish(operation: Operation) {
        if operation.isCancelled {
            wrappedOperationDidCancel(operation: operation as! WrappedObvOperationType)
        } else {
            wrappedOperationDidFinishWithoutCancelling(operation: operation as! WrappedObvOperationType)
        }
        finish()
    }

    open func wrappedOperationDidStart(operation: WrappedObvOperationType) {
        // Default implementation does nothing
    }

    open func wrappedOperationDidFinishWithoutCancelling(operation: WrappedObvOperationType) {
        // Default implementation does nothing
    }

    open func wrappedOperationDidCancel(operation: WrappedObvOperationType) {
        // Default implementation does nothing
    }

}
