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
import os.log


public final class CompositionOfTwoContextualOperations<ReasonForCancelType1: LocalizedErrorWithLogType,
                                                        ReasonForCancelType2: LocalizedErrorWithLogType>: OperationWithSpecificReasonForCancel<CompositionOfTwoContextualOperationsReasonForCancel<ReasonForCancelType1, ReasonForCancelType2>>, @unchecked Sendable {
    
    let contextCreator: ObvContextCreator
    let flowId: FlowIdentifier
    let log: OSLog
    let op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>
    let op2: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType2>
    let queueForComposedOperations: OperationQueue
    public private(set) var executionStartDate: Date?

    public init(op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>,
                op2: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType2>, contextCreator: ObvContextCreator, queueForComposedOperations: OperationQueue, log: OSLog, flowId: FlowIdentifier) {
        self.contextCreator = contextCreator
        self.queueForComposedOperations = queueForComposedOperations
        self.flowId = flowId
        self.log = log
        self.op1 = op1
        self.op2 = op2
        super.init()
    }
    
    public override var debugDescription: String {
        let concatanatedOpsNames = [op1, op2].map({ $0.debugDescription }).joined(separator: "->")
        let thisOperationName = "CompositionOfTwoContextualOperations"
        return "\(thisOperationName)[\(concatanatedOpsNames)]"
    }
    
    
    /// This override allows to make sure that, if we cancel, then we also cancel and finish all  internal operations. This prevents a potential deadlock if the caller creates another operation and makes it depend on, e.g., op2.
    /// In that case, if op2 never gets a chance to execute (e.g., because op1 cancels), then this other (external) operation may never execute.
    /// Note that executing a *cancelled* OperationWithSpecificReasonForCancel returns immediately, see ``ContextualOperationWithSpecificReasonForCancel.main()``.
    public override func cancel(withReason reason: CompositionOfTwoContextualOperationsReasonForCancel<ReasonForCancelType1, ReasonForCancelType2>) {
        for op in [op1, op2] {
            if !op.isFinished {
                op.cancel()
                queueForComposedOperations.addOperations([op], waitUntilFinished: true)
            }
        }
        super.cancel(withReason: reason)
    }
    

    public override func main() {

        assert(executionStartDate == nil)
        executionStartDate = Date.now

        let obvContext = contextCreator.newBackgroundContext(flowId: flowId)
        defer {
            obvContext.performAllEndOfScopeCompletionHAndlers()
            logExecutionDurationToDisplayableLog()
        }

        assert(queueForComposedOperations.operationCount < 5)

        // See ``CompositionOfOneContextualOperation``
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

        // See ``CompositionOfOneContextualOperation``
        guard op2.dependencies.allSatisfy({ $0.isFinished }) else {
            assertionFailure()
            return cancel(withReason: .op2HasUnfinishedDependency(op2: op2))
        }

        op2.obvContext = obvContext
        op2.viewContext = contextCreator.viewContext
        assert(op2.isReady)
        queueForComposedOperations.addOperations([op2], waitUntilFinished: true)
        assert(op2.isFinished)
        guard !op2.isCancelled else {
            guard let reason = op2.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op2Cancelled(reason: reason))
        }
        
        obvContext.performAndWait {
            do {
                guard obvContext.context.hasChanges else {
                    debugPrint("🙃 No need to save completion handler for op1: \(op1.debugDescription), op2: \(op2.debugDescription)")
                    return
                }
                try obvContext.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
    }
    
    
    private func logExecutionDurationToDisplayableLog() {
        guard let executionStartDate else { assertionFailure(); return }
        let duration = Date.now.timeIntervalSince(executionStartDate)
        ObvDisplayableLogs.shared.log("[⏱️][\(duration)] [CompositionOfTwoContextualOperations<\(op1.description)->\(op2.description)>]")
    }

}


public enum CompositionOfTwoContextualOperationsReasonForCancel<ReasonForCancelType1: LocalizedErrorWithLogType,
                                                                ReasonForCancelType2: LocalizedErrorWithLogType>: LocalizedErrorWithLogType {
    
    case unknownReason
    case coreDataError(error: Error)
    case op1Cancelled(reason: ReasonForCancelType1)
    case op2Cancelled(reason: ReasonForCancelType2)
    case op1HasUnfinishedDependency(op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>)
    case op2HasUnfinishedDependency(op2: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType2>)

    public var logType: OSLogType {
        switch self {
        case .unknownReason, .coreDataError, .op1HasUnfinishedDependency, .op2HasUnfinishedDependency:
            return .fault
        case .op1Cancelled(reason: let reason):
            return reason.logType
        case .op2Cancelled(reason: let reason):
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
        case .op2Cancelled(reason: let reason):
            return reason.errorDescription
        case .op1HasUnfinishedDependency(op1: let op1):
            return "\(op1.debugDescription) has an unfinished dependency"
        case .op2HasUnfinishedDependency(op2: let op2):
            return "\(op2.debugDescription) has an unfinished dependency"
        }
    }
    
}
