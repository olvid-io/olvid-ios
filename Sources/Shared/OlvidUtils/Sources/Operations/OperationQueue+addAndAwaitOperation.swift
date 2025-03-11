/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


extension OperationQueue {
    
    /// Adds the specified operation to the queue and wait until the operation is finished.
    public func addAndAwaitOperation(_ op: Operation) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let currentCompletion = op.completionBlock
            op.completionBlock = {
                continuation.resume()
                currentCompletion?()
            }
            self.addOperation(op)
        }
    }
    
    /// Adds the specified operations to the queue and wait until the operations are finished.
    public func addAndAwaitOperations(_ ops: [Operation]) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.addOperations(ops, waitUntilFinished: true)
            continuation.resume()
        }
    }
    
}
