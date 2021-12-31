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
import ObvTypes
import OlvidUtils


final class GateKeeper {
    
    private let readOnly: Bool
    
    init(readOnly: Bool) {
        self.readOnly = readOnly
    }
    
    private let contextOperationQueue: ContextOperationQueue = {
        let queue = ContextOperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.isSuspended = false
        return queue
    }()

    func waitUntilSlotIsAvailableForObvContext(_ obvContext: ObvContext) throws {
        if self.readOnly {
            // If the context is read-only (which is the case when the engine is initialized by the notification extension), we make sure that the context is never saved
            try obvContext.addContextWillSaveCompletionHandler {
                assertionFailure("The channel manager expects this context to be read only")
                return
            }
        } else {
            // If the context is not read-only, we ensure that two contexts cannot access the channel manager at the same time.
            if try contextOperationQueue.getContextOfExecutingOperation() != obvContext {
                let contextOperation = ContextOperation(obvContext: obvContext)
                contextOperationQueue.addOperation(contextOperation)
                contextOperation.operationStarted.wait()
            }
        }
    }
    
}



fileprivate final class ContextOperation: Operation {

    let operationStarted = DispatchSemaphore(value: 0)
    private let contextFreed = DispatchSemaphore(value: 0)
    let obvContext: ObvContext
    
    init(obvContext: ObvContext) {
        self.obvContext = obvContext
        super.init()
        self.obvContext.addEndOfScopeCompletionHandler { [weak self] in
            debugPrint("🧠 End of scope of the context \(obvContext.name)")
            self?.contextFreed.signal()
        }
    }
    
    override func main() {
        operationStarted.signal()
        debugPrint("🧠 About to wait for the end of scope of the context \(obvContext.name)")
        contextFreed.wait()
    }
    
}


fileprivate final class ContextOperationQueue: OperationQueue {
    
    private static var errorDomain: String { "GateKeeper" }
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }
    
    
    func getContextOfExecutingOperation() throws -> ObvContext? {
        let executingOperations = operations.filter { $0.isExecuting }
        guard executingOperations.count < 2 else {
            throw ContextOperationQueue.makeError(message: "Expecting at most 1 executing operation, found \(executingOperations.count)")
        }
        return (executingOperations.first as? ContextOperation)?.obvContext
    }
    
}
