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
import ObvCrypto

private class ObvOperationWrapperForNoDuplicateQueue<WrappedObvOperationType: ObvOperation>: ObvOperationWrapper<WrappedObvOperationType>, @unchecked Sendable {
    
    override var debugClassName: String {
        return "ObvOperationWrapperForNoDuplicateQueue<\(String(describing: wrappedOperation.debugClassName))>"
    }

    weak var queue: ObvOperationNoDuplicateQueue?
    
    init(wrappedOperation: WrappedObvOperationType, from queue: ObvOperationNoDuplicateQueue) {
        self.queue = queue
        super.init(wrappedOperation: wrappedOperation)
    }
    
    override func wrappedOperationDidStart(operation: WrappedObvOperationType) {
        guard let uid = operation.uid else { return }
        queue?.internalDispatchQueue.sync {
            let queueContainsTheUid = queue?.uidsOfNotYetExecutingQueuedOperations.contains(uid) ?? false
            if queueContainsTheUid {
                queue?.uidsOfNotYetExecutingQueuedOperations.remove(uid)
            }
        }
    }
    
}

public class ObvOperationNoDuplicateQueue: ObvOperationQueue, @unchecked Sendable {
    
    fileprivate let internalDispatchQueue = DispatchQueue(label: "io.olvid.ObvOperationNoDuplicateQueue")
    fileprivate var uidsOfNotYetExecutingQueuedOperations = Set<UID>()
    
    public func addOperation(_ op: ObvOperation) {
        var opToQueue: Operation? = nil
        internalDispatchQueue.sync {
            if let uid = op.uid {
                if !uidsOfNotYetExecutingQueuedOperations.contains(uid) {
                    uidsOfNotYetExecutingQueuedOperations.insert(uid)
                    opToQueue = ObvOperationWrapperForNoDuplicateQueue(wrappedOperation: op, from: self)
                }
            } else {
                opToQueue = op
            }
        }
        if let op = opToQueue {
            super.addOperation(op)
        }
    }

    public override func addOperations(_ ops: [Operation], waitUntilFinished wait: Bool) {
        // We create a new ops array with operations that have unique uids
        let inputOps = filterOperationsWithIdenticalUids(in: ops)
        var opsToQueue = [Operation]()
        internalDispatchQueue.sync {
            // This is the list of ops that will eventually get to execute
            let opsToExecute = inputOps.filter() { (op) -> Bool in
                guard let op = op as? ObvOperation, let uid = op.uid else { return true }
                return !uidsOfNotYetExecutingQueuedOperations.contains(uid)
            }
            // The ops to execute that are ObvOperation and that have an UID must be wrapped
            opsToQueue = opsToExecute.map({ (op) -> Operation in
                if let op = op as? ObvOperation, let uid = op.uid {
                    uidsOfNotYetExecutingQueuedOperations.insert(uid)
                    return ObvOperationWrapperForNoDuplicateQueue(wrappedOperation: op, from: self)
                } else {
                    return op
                }
            })
        }
        super.addOperations(opsToQueue, waitUntilFinished: wait)
    }
    
    private func filterOperationsWithIdenticalUids(in ops: [Operation]) -> [Operation] {
        var uidsOfInputOps = [UID]()
        let inputOps = ops.filter { (op) -> Bool in
            guard let op = op as? ObvOperation, let uid = op.uid else { return true }
            if uidsOfInputOps.contains(uid) {
                return false
            } else {
                uidsOfInputOps.append(uid)
                return true
            }
        }
        return inputOps
    }

}
