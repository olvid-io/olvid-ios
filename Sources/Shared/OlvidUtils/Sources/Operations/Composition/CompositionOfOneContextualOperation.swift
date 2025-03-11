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
@preconcurrency import os.log

// Note: we mark os.log as @preconcurrency to silent a warning in logExecutionDuration(log:). Quick and dirty.


public final class CompositionOfOneContextualOperation<ReasonForCancelType1: LocalizedErrorWithLogType>: OperationWithSpecificReasonForCancel<CompositionOfOneContextualOperationReasonForCancel<ReasonForCancelType1>>, @unchecked Sendable {

    let contextCreator: ObvContextCreator
    let log: OSLog
    let flowId: FlowIdentifier
    let op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>
    let queueForComposedOperations: OperationQueue
    public private(set) var executionStartDate: Date?

    public init(op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>, contextCreator: ObvContextCreator, queueForComposedOperations: OperationQueue, log: OSLog, flowId: FlowIdentifier) {
        self.contextCreator = contextCreator
        self.queueForComposedOperations = queueForComposedOperations
        self.flowId = flowId
        self.log = log
        self.op1 = op1
        super.init()
    }
    
    public override var debugDescription: String {
        let concatanatedOpsNames = [op1].map({ $0.debugDescription }).joined(separator: "->")
        let thisOperationName = "CompositionOfOneContextualOperation"
        return "\(thisOperationName)[\(concatanatedOpsNames)]"
    }
    

    public override func main() {

        assert(executionStartDate == nil)
        executionStartDate = Date.now
        
        let obvContext = contextCreator.newBackgroundContext(flowId: flowId)
        defer {
            obvContext.performAllEndOfScopeCompletionHAndlers()
            logExecutionDurationToDisplayableLog()
        }
        
        assert(queueForComposedOperations.operationCount < 20)

        // Make sure op1 does not depend on an unfinished operation.
        // If this is the case, we might be in a deadlock situation. For example, assume:
        // - Some composed with 2 operations fails because the first operation fails
        // - Assume that op1 (the one we have here) depends on the second operation, that never got a chance to execute
        // then, in that case, we have a potential deadlock on the serial queue that executes this CompositionOfOneContextualOperation
        
        guard op1.dependencies.allSatisfy({ $0.isFinished }) else {
            assertionFailure()
            return cancel(withReason: .op1HasUnfinishedDependency(op1: op1))
        }
        
        op1.obvContext = obvContext
        op1.viewContext = contextCreator.viewContext
        assert(op1.isReady)
        queueForComposedOperations.addOperations([op1], waitUntilFinished: true)
        assert(op1.isFinished)
        guard !op1.isCancelled else {
            guard let reason = op1.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op1Cancelled(reason: reason))
        }

        obvContext.performAndWait {
            do {
                guard obvContext.context.hasChanges else {
                    debugPrint("🙃 No need to save completion handler for op1: \(op1.debugDescription)")
                    return
                }
                debugPrint("🙂 Saving the context for op1: \(op1.debugDescription)")
                try obvContext.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
    
    private func logExecutionDurationToDisplayableLog() {
        guard let executionStartDate else { assertionFailure(); return }
        let duration = Date.now.timeIntervalSince(executionStartDate)
        ObvDisplayableLogs.shared.log("[⏱️][\(duration)] [CompositionOfOneContextualOperation<\(op1.description)>]")
    }
    
    
//    public func logExecutionDuration(log: OSLog) {
//        let op1Description = op1.description
//        self.appendCompletionBlock { [weak self] in
//            guard let executionStartDate = self?.executionStartDate else { assertionFailure(); return }
//            let duration = Date.now.timeIntervalSince(executionStartDate)
//            os_log("⏱️ CompositionOfOneContextualOperation<%{public}@> took %f seconds", log: log, type: .info, op1Description, duration)
//        }
//    }

}


public enum CompositionOfOneContextualOperationReasonForCancel<ReasonForCancelType1: LocalizedErrorWithLogType>: LocalizedErrorWithLogType {
    
    case unknownReason
    case coreDataError(error: Error)
    case op1Cancelled(reason: ReasonForCancelType1)
    case op1HasUnfinishedDependency(op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>)

    public var logType: OSLogType {
        switch self {
        case .unknownReason, .coreDataError, .op1HasUnfinishedDependency:
            return .fault
        case .op1Cancelled(reason: let reason):
            return reason.logType
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unknownReason:
            return "One of the operations cancelled without speciying a reason. This is a bug."
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .op1Cancelled(reason: let reason):
            return reason.errorDescription
        case .op1HasUnfinishedDependency(op1: let op1):
            return "\(op1.debugDescription) has an unfinished dependency"
        }
    }
    
}
