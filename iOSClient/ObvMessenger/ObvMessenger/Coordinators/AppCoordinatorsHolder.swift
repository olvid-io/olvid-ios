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
import ObvEngine

final class AppCoordinatorsHolder {
    
    private let persistedDiscussionsUpdatesCoordinator: PersistedDiscussionsUpdatesCoordinator
    private let bootstrapCoordinator: BootstrapCoordinator
    private let obvOwnedIdentityCoordinator: ObvOwnedIdentityCoordinator
    private let contactIdentityCoordinator: ContactIdentityCoordinator
    private let contactGroupCoordinator: ContactGroupCoordinator

    
    init(obvEngine: ObvEngine) {

        ObvDisplayableLogs.shared.log("🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨🧨 Creeating the coordonators serial queue")
        
        let queueSharedAmongCoordinators = LoggedOperationQueue.createSerialQueue(name: "Queue shared among coordinators", qualityOfService: .userInteractive)
        let queueForComposedOperations = {
            let queue = OperationQueue()
            queue.name = "Queue for composed operations"
            queue.qualityOfService = .userInteractive
            return queue
        }()
        
        self.persistedDiscussionsUpdatesCoordinator = PersistedDiscussionsUpdatesCoordinator(obvEngine: obvEngine, coordinatorsQueue: queueSharedAmongCoordinators, queueForComposedOperations: queueForComposedOperations)
        self.bootstrapCoordinator = BootstrapCoordinator(obvEngine: obvEngine, coordinatorsQueue: queueSharedAmongCoordinators, queueForComposedOperations: queueForComposedOperations)
        self.obvOwnedIdentityCoordinator = ObvOwnedIdentityCoordinator(obvEngine: obvEngine, coordinatorsQueue: queueSharedAmongCoordinators, queueForComposedOperations: queueForComposedOperations)
        self.contactIdentityCoordinator = ContactIdentityCoordinator(obvEngine: obvEngine, coordinatorsQueue: queueSharedAmongCoordinators, queueForComposedOperations: queueForComposedOperations)
        self.contactGroupCoordinator = ContactGroupCoordinator(obvEngine: obvEngine, coordinatorsQueue: queueSharedAmongCoordinators, queueForComposedOperations: queueForComposedOperations)
        
    }
    

    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        await self.persistedDiscussionsUpdatesCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.bootstrapCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.obvOwnedIdentityCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.contactIdentityCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
        await self.contactGroupCoordinator.applicationAppearedOnScreen(forTheFirstTime: forTheFirstTime)
    }

}



final class LoggedOperationQueue: OperationQueue {
    
    override func addOperations(_ ops: [Operation], waitUntilFinished wait: Bool) {
        ops.forEach { op in
            op.printObvDisplayableLogsWhenFinished()
        }
        _ = logOperations(ops: ops)
        super.addOperations(ops, waitUntilFinished: wait)
    }
    
    
    override func addOperation(_ op: Operation) {
        op.printObvDisplayableLogsWhenFinished()
        _ = logOperations(ops: [op])
        super.addOperation(op)
    }
    
    
    func logOperations(ops: [Operation]) -> String {
        let queuedOperations = ops.map({ $0.debugDescription })
        let currentOperations = self.operations
        if !currentOperations.isEmpty {
            let currentNotExecutingOperations = currentOperations.filter({ !$0.isExecuting })
            let currentExecutingOperations = currentOperations.filter({ $0.isExecuting })
            let currentNotExecutingOperationsAsString = currentNotExecutingOperations.map({ $0.debugDescription }).joined(separator: ", ")
            let currentExecutingOperationsAsString = currentExecutingOperations.map({ $0.debugDescription }).joined(separator: ", ")
            let stringToLog = "🍒⚠️ Queuing operation \(queuedOperations) but the queue (isSuspended=\(self.isSuspended)) is already executing the following \(currentExecutingOperations.count) operations: \(currentExecutingOperationsAsString). The following \(currentNotExecutingOperations.count) operations still need to be executed: \(currentNotExecutingOperationsAsString)"
            ObvDisplayableLogs.shared.log(stringToLog)
            return stringToLog
        } else {
            let stringToLog = "🍒✅ Queuing operation \(queuedOperations)"
            ObvDisplayableLogs.shared.log(stringToLog)
            return stringToLog
        }
    }
        
}


private extension Operation {
    
    func printObvDisplayableLogsWhenFinished() {
        if let completion = self.completionBlock {
            self.completionBlock = {
                completion()
                ObvDisplayableLogs.shared.log("🐷 \(self.debugDescription) is finished")
            }
        } else {
            self.completionBlock = {
                ObvDisplayableLogs.shared.log("🐷 \(self.debugDescription) is finished")
            }
        }
    }
    
}
