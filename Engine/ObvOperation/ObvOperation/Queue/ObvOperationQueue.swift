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

public class ObvOperationQueue: OperationQueue {
    
    override public func addOperation(_ op: Operation) {
        if let operation = op as? ObvOperation {
            operation.willEnqueue()
        }
        super.addOperation(op)
    }
    
    public override func addOperations(_ ops: [Operation], waitUntilFinished wait: Bool) {
        for op in ops {
            if let operation = op as? ObvOperation {
                operation.willEnqueue()
            }
        }
        super.addOperations(ops, waitUntilFinished: wait)
    }

    public func numberOfExecutingOperations() -> Int {
        let executingOps = self.operations.filter { $0.isExecuting }
        return executingOps.count
    }
    
}
