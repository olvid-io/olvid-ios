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

public final class ObvOperationPriorityQueue: ObvOperationQueue, @unchecked Sendable {
    
    private let internalOperationQueue = ObvOperationQueue() // On which we queue the "real" operations
    
    private let priorityHeapDispatch = DispatchQueue(label: "io.olvid.ObvOperationPriorityQueue")
    
    private static let defaultInitialAllocationLength = 15 // 2^n - 1
    private var priorityHeap: [ObvOperationWithPriority] = {
        var h = [ObvOperationWithPriority]()
        return h
    }()
    
    public init(maxConcurrentOperationCount: Int) {
        super.init()
        self.maxConcurrentOperationCount = maxConcurrentOperationCount
    }
    
    public func addOperation(_ op: ObvOperationWithPriority) {

        self.insert(op)
        super.addOperation { [weak self] in
            if let opToExecute = self?.getOperationWithHighestPriority() {
                self?.internalOperationQueue.addOperations([opToExecute], waitUntilFinished: true)
            }
        }

    }
        
    public override var operations: [Operation] {
        return internalOperationQueue.operations
    }
    
    public var operationsWithPriorities: [ObvOperationWithPriority] {
        return operations as! [ObvOperationWithPriority]
    }
    
    private func insert(_ operationWithPriority: ObvOperationWithPriority) {
        priorityHeapDispatch.sync {
            priorityHeap.append(operationWithPriority)
            swim(from: priorityHeap.count-1)
        }
    }
    
    private func printHeap() {
        var i = 0
        for _ in self.priorityHeap {
            i += 1
        }
    }
    
    private func getOperationWithHighestPriority() -> ObvOperationWithPriority? {
        var opWithHighestPriority: ObvOperationWithPriority?
        self.priorityHeapDispatch.sync {
            switch self.priorityHeap.count {
            case 0:
                break
            case 1:
                opWithHighestPriority = self.priorityHeap.removeFirst()
            default:
                opWithHighestPriority = self.priorityHeap.first!
                self.priorityHeap[0] = self.priorityHeap.removeLast()
                self.sink(from: 0)
            }
        }
        return opWithHighestPriority
    }
    
    // See https://algs4.cs.princeton.edu/home/
    private func swim(from: Int) {
        var k = from
        while k > 0 && priorityHeap[k/2].priorityNumber < priorityHeap[k].priorityNumber {
            priorityHeap.swapAt(k/2, k)
            k /= 2
        }
    }
    
    // See https://algs4.cs.princeton.edu/home/
    private func sink(from: Int) {
        guard priorityHeap.count > 1 else { return }
        var k = from
        while 2*k < priorityHeap.count {
            var j = 2*k
            if j < priorityHeap.count-1 && priorityHeap[j].priorityNumber < priorityHeap[j+1].priorityNumber {
                j += 1
            }
            if priorityHeap[j].priorityNumber <= priorityHeap[k].priorityNumber {
                break
            } else {
                priorityHeap.swapAt(j, k)
                k = j
            }
        }
    }
    
}
