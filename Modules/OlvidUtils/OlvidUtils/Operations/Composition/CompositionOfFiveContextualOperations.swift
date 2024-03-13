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


public final class CompositionOfFiveContextualOperations<ReasonForCancelType1: LocalizedErrorWithLogType,
                                                         ReasonForCancelType2: LocalizedErrorWithLogType,
                                                         ReasonForCancelType3: LocalizedErrorWithLogType,
                                                         ReasonForCancelType4: LocalizedErrorWithLogType,
                                                         ReasonForCancelType5: LocalizedErrorWithLogType>: OperationWithSpecificReasonForCancel<CompositionOfFiveContextualOperationsReasonForCancel<ReasonForCancelType1,
                                                                                              ReasonForCancelType2,
                                                                                              ReasonForCancelType3,
                                                                                              ReasonForCancelType4,
                                                                                              ReasonForCancelType5>> {
    
    let contextCreator: ObvContextCreator
    let flowId: FlowIdentifier
    let log: OSLog
    let queueForComposedOperations: OperationQueue
    let op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>
    let op2: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType2>
    let op3: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType3>
    let op4: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType4>
    let op5: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType5>
    public private(set) var executionStartDate: Date?

    public init(op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>,
                op2: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType2>,
                op3: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType3>,
                op4: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType4>,
                op5: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType5>,
                contextCreator: ObvContextCreator,
                queueForComposedOperations: OperationQueue,
                log: OSLog,
                flowId: FlowIdentifier) {
        self.contextCreator = contextCreator
        self.queueForComposedOperations = queueForComposedOperations
        self.flowId = flowId
        self.log = log
        self.op1 = op1
        self.op2 = op2
        self.op3 = op3
        self.op4 = op4
        self.op5 = op5
        super.init()
    }
    
    public override var debugDescription: String {
        let concatanatedOpsNames = [op1, op2, op3, op4, op5].map({ $0.debugDescription }).joined(separator: "->")
        let thisOperationName = "CompositionOfFiveContextualOperations"
        return "\(thisOperationName)[\(concatanatedOpsNames)]"
    }
    
    
    /// See ``CompositionOfTwoContextualOperations.cancel(withReason:)``.
    public override func cancel(withReason reason: CompositionOfFiveContextualOperationsReasonForCancel<ReasonForCancelType1, ReasonForCancelType2, ReasonForCancelType3, ReasonForCancelType4, ReasonForCancelType5>) {
        for op in [op1, op2, op3, op4, op5] {
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
            logExecutionDurationToDisplayableLog()
            obvContext.performAllEndOfScopeCompletionHAndlers()
        }

        assert(queueForComposedOperations.operationCount < 5)

        // See ``CompositionOfOneContextualOperation``
        guard op1.dependencies.allSatisfy({ $0.isFinished }) else {
            assertionFailure()
            return cancel(withReason: .op1HasUnfinishedDependency(op1: op1))
        }

        op1.obvContext = obvContext
        op1.viewContext = contextCreator.viewContext
        queueForComposedOperations.addOperations([op1], waitUntilFinished: true)
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
        queueForComposedOperations.addOperations([op2], waitUntilFinished: true)
        guard !op2.isCancelled else {
            guard let reason = op2.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op2Cancelled(reason: reason))
        }
        
        // See ``CompositionOfOneContextualOperation``
        guard op3.dependencies.allSatisfy({ $0.isFinished }) else {
            assertionFailure()
            return cancel(withReason: .op3HasUnfinishedDependency(op3: op3))
        }

        op3.obvContext = obvContext
        op3.viewContext = contextCreator.viewContext
        queueForComposedOperations.addOperations([op3], waitUntilFinished: true)
        guard !op3.isCancelled else {
            guard let reason = op3.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op3Cancelled(reason: reason))
        }

        // See ``CompositionOfOneContextualOperation``
        guard op4.dependencies.allSatisfy({ $0.isFinished }) else {
            assertionFailure()
            return cancel(withReason: .op4HasUnfinishedDependency(op4: op4))
        }

        op4.obvContext = obvContext
        op4.viewContext = contextCreator.viewContext
        queueForComposedOperations.addOperations([op4], waitUntilFinished: true)
        guard !op4.isCancelled else {
            guard let reason = op4.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op4Cancelled(reason: reason))
        }

        // See ``CompositionOfOneContextualOperation``
        guard op5.dependencies.allSatisfy({ $0.isFinished }) else {
            assertionFailure()
            return cancel(withReason: .op5HasUnfinishedDependency(op5: op5))
        }

        op5.obvContext = obvContext
        op5.viewContext = contextCreator.viewContext
        queueForComposedOperations.addOperations([op5], waitUntilFinished: true)
        guard !op5.isCancelled else {
            guard let reason = op5.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op5Cancelled(reason: reason))
        }

        obvContext.performAndWait {
            do {
                guard obvContext.context.hasChanges else {
                    debugPrint("🙃 No need to save completion handler for op1: \(op1.debugDescription), op2: \(op2.debugDescription), op3: \(op3.debugDescription), op4: \(op4.debugDescription), op5: \(op5.debugDescription)")
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
        ObvDisplayableLogs.shared.log("[⏱️] [\(duration) seconds] [CompositionOfFiveContextualOperations<\(op1.description)->\(op2.description)->\(op3.description)->\(op4.description)->\(op5.description)>]")
    }

}


public enum CompositionOfFiveContextualOperationsReasonForCancel<ReasonForCancelType1: LocalizedErrorWithLogType,
                                                                 ReasonForCancelType2: LocalizedErrorWithLogType,
                                                                 ReasonForCancelType3: LocalizedErrorWithLogType,
                                                                 ReasonForCancelType4: LocalizedErrorWithLogType,
                                                                 ReasonForCancelType5: LocalizedErrorWithLogType>: LocalizedErrorWithLogType {
    
    case unknownReason
    case coreDataError(error: Error)
    case op1Cancelled(reason: ReasonForCancelType1)
    case op2Cancelled(reason: ReasonForCancelType2)
    case op3Cancelled(reason: ReasonForCancelType3)
    case op4Cancelled(reason: ReasonForCancelType4)
    case op5Cancelled(reason: ReasonForCancelType5)
    case op1HasUnfinishedDependency(op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>)
    case op2HasUnfinishedDependency(op2: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType2>)
    case op3HasUnfinishedDependency(op3: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType3>)
    case op4HasUnfinishedDependency(op4: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType4>)
    case op5HasUnfinishedDependency(op5: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType5>)

    public var logType: OSLogType {
        switch self {
        case .unknownReason, .coreDataError, .op1HasUnfinishedDependency, .op2HasUnfinishedDependency, .op3HasUnfinishedDependency, .op4HasUnfinishedDependency, .op5HasUnfinishedDependency:
            return .fault
        case .op1Cancelled(reason: let reason):
            return reason.logType
        case .op2Cancelled(reason: let reason):
            return reason.logType
        case .op3Cancelled(reason: let reason):
            return reason.logType
        case .op4Cancelled(reason: let reason):
            return reason.logType
        case .op5Cancelled(reason: let reason):
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
        case .op3Cancelled(reason: let reason):
            return reason.errorDescription
        case .op4Cancelled(reason: let reason):
            return reason.errorDescription
        case .op5Cancelled(reason: let reason):
            return reason.errorDescription
        case .op1HasUnfinishedDependency(op1: let op1):
            return "\(op1.debugDescription) has an unfinished dependency"
        case .op2HasUnfinishedDependency(op2: let op2):
            return "\(op2.debugDescription) has an unfinished dependency"
        case .op3HasUnfinishedDependency(op3: let op3):
            return "\(op3.debugDescription) has an unfinished dependency"
        case .op4HasUnfinishedDependency(op4: let op4):
            return "\(op4.debugDescription) has an unfinished dependency"
        case .op5HasUnfinishedDependency(op5: let op5):
            return "\(op5.debugDescription) has an unfinished dependency"
        }
    }
    
}
