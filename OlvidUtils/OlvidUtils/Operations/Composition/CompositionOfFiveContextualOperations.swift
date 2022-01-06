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
    let queue = OperationQueue()
    let op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>
    let op2: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType2>
    let op3: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType3>
    let op4: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType4>
    let op5: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType5>

    public init(op1: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType1>,
                op2: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType2>,
                op3: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType3>,
                op4: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType4>,
                op5: ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType5>,
                contextCreator: ObvContextCreator,
                flowId: FlowIdentifier,
                log: OSLog) {
        self.contextCreator = contextCreator
        self.flowId = flowId
        self.log = log
        self.op1 = op1
        self.op2 = op2
        self.op3 = op3
        self.op4 = op4
        self.op5 = op5
        super.init()
    }
    
    public override func main() {
        
        let obvContext = contextCreator.newBackgroundContext(flowId: flowId)

        op1.obvContext = obvContext
        op1.viewContext = contextCreator.viewContext
        queue.addOperations([op1], waitUntilFinished: true)
        guard !op1.isCancelled else {
            guard let reason = op1.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op1Cancelled(reason: reason))
        }

        op2.obvContext = obvContext
        op2.viewContext = contextCreator.viewContext
        queue.addOperations([op2], waitUntilFinished: true)
        guard !op2.isCancelled else {
            guard let reason = op2.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op2Cancelled(reason: reason))
        }
        
        op3.obvContext = obvContext
        op3.viewContext = contextCreator.viewContext
        queue.addOperations([op3], waitUntilFinished: true)
        guard !op3.isCancelled else {
            guard let reason = op3.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op3Cancelled(reason: reason))
        }

        op4.obvContext = obvContext
        op4.viewContext = contextCreator.viewContext
        queue.addOperations([op4], waitUntilFinished: true)
        guard !op4.isCancelled else {
            guard let reason = op4.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op4Cancelled(reason: reason))
        }

        op5.obvContext = obvContext
        op5.viewContext = contextCreator.viewContext
        queue.addOperations([op5], waitUntilFinished: true)
        guard !op5.isCancelled else {
            guard let reason = op5.reasonForCancel else { return cancel(withReason: .unknownReason) }
            return cancel(withReason: .op5Cancelled(reason: reason))
        }

        obvContext.performAndWait {
            do {
                try obvContext.save(logOnFailure: log)
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
        
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

    public var logType: OSLogType {
        switch self {
        case .unknownReason, .coreDataError:
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
        }
    }
    
}
