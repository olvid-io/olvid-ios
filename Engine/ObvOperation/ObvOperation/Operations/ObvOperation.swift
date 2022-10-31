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
import CoreData
import os.log
import ObvCrypto

@objcMembers open class ObvOperation: Operation {
    
    static let defaultLogSubsystem = "io.olivd.operation"
    private let log = OSLog(subsystem: ObvOperation.defaultLogSubsystem, category: "ObvOperation")
    
    open var className: String { return "ObvOperation" }
    
    private static let internalDispatchQueue = DispatchQueue.init(label: "io.olvid.obvoperation.internal")
    
    // MARK: State Management
    
    @objc enum State: Int, Comparable, CustomDebugStringConvertible {
        
        /// The initial state of an `Operation`.
        case Initialized = 0
        /// The `Operation` is evaluating conditions.
        case EvaluatingConditions = 1
        /// The `Operation`'s conditions have all been satisfied, and it is ready to execute.
        case Ready = 2
        /// The `Operation` is executing.
        case Executing = 3
        /// Execution of the `Operation` has finished, but it has not yet notified the queue of this.
        case Finishing = 4
        /// The `Operation` has finished executing.
        case Finished = 5
        
        func canTransitionTo(_ target: State, log: OSLog) -> Bool {
            switch (self, target) {
            case (.Initialized, .EvaluatingConditions),
                 (.EvaluatingConditions, .Ready),
                 (.Ready, .Executing),
                 (.Ready, .Finishing), // This happens if the operation is cancelled at the time the start() method is called
                 (.Executing, .Finishing),
                 (.Finishing, .Finished):
                return true
            default:
                os_log("Cannot transition from state %@ to state %@", log: log, type: .fault, self.debugDescription, target.debugDescription)
                return false
            }
        }
        
        var debugDescription: String {
            switch self {
            case .Initialized:
                return "Initialized"
            case .EvaluatingConditions:
                return "EvaluatingConditions"
            case .Ready:
                return "Ready"
            case .Executing:
                return "Executing"
            case .Finishing:
                return "Finishing"
            case .Finished:
                return "Finished"
            }
        }
    }
    
    /// Private storage for the `state` property that will be KVO observed.
    /// This var must only be accessed by means of the `state` property.
    private var _state = State.Initialized
    
    /// A dispatch queue used to guard reads and writes to the `_state` property
    private let stateQueue = DispatchQueue(label: "io.olvid.obvoperation.internal.state", target: ObvOperation.internalDispatchQueue)
    
    @objc dynamic var state: State {
        get {
            return stateQueue.sync { _state }
        }
        set(newState) {
            /*
             * It's important to note that the KVO notifications are NOT called from inside
             * the lock. If they were, the app would deadlock, because in the middle of
             * calling the `didChangeValueForKey()` method, the observers try to access
             * properties like "isReady" or "isFinished". Since those methods also
             * acquire the lock, then we'd be stuck waiting on our own lock. It's the
             * classic definition of deadlock.
             */
            willChangeValue(for: \ObvOperation.state)
            stateQueue.sync {
                if _state != .Finished, _state != newState {
                    guard _state.canTransitionTo(newState, log: log) else {
                        os_log("%@ is trying to perform an invalid state transtition from %@ to %@", log: log, type: .fault, self.debugDescription, _state.debugDescription, newState.debugDescription)
                        return
                    }
                    _state = newState
                }
            }
            didChangeValue(for: \ObvOperation.state)
        }
    }
    
    /**
     Indicates that the Operation can now begin to evaluate readiness conditions,
     if appropriate.
     */
    func willEnqueue() {
        state = .EvaluatingConditions
    }
        
    public init(uid: UID? = nil) {
        self.uid = uid
        super.init()
    }
    
    // MARK: Managing mutuall exclusivity of `ObvOperation`s
    
    let uid: UID? // This is essentially to prevent the execution of two `ObvOperation`s with the same uid
    lazy public var operationIdentifier: ObvOperationIdentifier? = {
        guard let uid = uid else { return nil }
        return ObvOperationIdentifier.init(className: className, uid: uid)
    }()
    
    private static var identifiersOfOperationsCurrentlyExecuting = Set<ObvOperationIdentifier>()
    private let tempLog = OSLog(subsystem: ObvOperation.defaultLogSubsystem, category: "ObvOperationIdentifier")
    private static let uidQueue = DispatchQueue(label: "io.olvid.obvoperation.internal.uidsOfOperationsCurrentlyExecuting", target: ObvOperation.internalDispatchQueue) // A dispatch queue used to guard reads and writes to the `uidsOfOperationsCurrentlyExecuting` property
    
    // Here is where we extend our definition of "readiness". This var is access each time the (internal) state is changed, allowing to perform computations that allow to update the (internal) state, and so on.

    override open var isReady: Bool {
        updateInternalState()
        return state == .Ready
    }
    
    /// This method gets called each time `isReady` is accessed, which is the case each time the (internal) state changes. This method changes this (internal) state, triggering a new access of the `isReady` var, and so on.
    private func updateInternalState() {
        
        switch state {
            
        case .Initialized:
            break // Going from Initialized to EvaluatingConditions requires a call to the `willEnqueue()` method
            
        case .EvaluatingConditions:
            
            // If super is not ready (e.g., when we have unfinished dependencies), then we are not ready either.
            guard super.isReady else { return }
            
            // At this point, we know for sure that all our dependencies are in the Finish state.
            if let operationIdentifier = self.operationIdentifier {
                
                // For a given identifier (i.e., name and uid), there can be only *zero or one* operation currently executing.
                var localIsReady = false
                ObvOperation.uidQueue.sync {
                    if !ObvOperation.identifiersOfOperationsCurrentlyExecuting.contains(operationIdentifier) {
                        os_log("Will insert %@ in the set of executing operations (which currently contains %d operations)", log: tempLog, type: .debug, operationIdentifier.debugDescription, ObvOperation.identifiersOfOperationsCurrentlyExecuting.count)
                        _ = ObvOperation.identifiersOfOperationsCurrentlyExecuting.update(with: operationIdentifier)
                        localIsReady = true
                    } else {
                        os_log("There already is an executing operation with this identifier %@", log: tempLog, type: .debug, operationIdentifier.debugDescription)
                    }
                }
                if localIsReady {
                    state = .Ready
                }
                
            } else {
                
                state = .Ready
                
            }
            
        case .Ready:
            break // Going from Ready to Executing is performed within the `main()` function
            
        case .Executing:
            break // Going from Executing to Finishing is done within the `finish()` method. In practice, this method is called within the override of the `execute()` method a concrete subclasses of `ObvOperation`.
            
        case .Finishing:
            break // Going from Finishing to Finished is done within the `finish()` method.
            
        case .Finished:
            break
        }
    }
    
    override open var isExecuting: Bool {
        return state == .Executing
    }
    
    override open var isFinished: Bool {
        return state == .Finished
    }
    
    // MARK: For ensuring KVO compliance, we must register dependent keys to indicate that changes to "state" affect other properties as well
    
    class func keyPathsForValuesAffectingIsReady() -> Set<String> {
        return [#keyPath(ObvOperation.state)]
    }

    class func keyPathsForValuesAffectingIsExecuting() -> Set<String> {
        return [#keyPath(ObvOperation.state)]
    }

    class func keyPathsForValuesAffectingIsFinished() -> Set<String> {
        return [#keyPath(ObvOperation.state)]
    }

    // MARK: Delegate and dependencies
    
    weak var delegate: OperationDelegate?
    
    override open func addDependency(_ op: Operation) {
        guard state == .Initialized else {
            os_log("Dependencies can only be set when the operation is in the Initialized state", log: log, type: .error)
            return
        }
        super.addDependency(op)
    }
    
    // MARK: Execution and Cancellation
    
    
    /// This method is called by the operation queue
    override public final func start() {
        
        os_log("This ObvOperation did start: %@", log: log, type: .debug, self.operationIdentifier?.debugDescription ?? self.className)
        
        guard state == .Ready else {
            os_log("An ObvOperation must be queued on an operation queue", log: log, type: .fault)
            return
        }

        // An ObvOperation cancels itself it any of its dependencies is cancelled.
        
        let cancelledDependencies = dependencies.filter() { $0.isCancelled }
        if cancelledDependencies.count > 0 {
            os_log("This operation will cancel because it has a cancelled dependency", log: log, type: .error)
            cancel()
        }
        
        // If we reach this point, the operation is ready to execute and is not cancelled. We call execute() and call our delegates.
        
        delegate?.operationWillExecute(operation: self)
        state = .Executing
        execute()
    }
    
    /**
     `execute()` is the entry point of execution for all `ObvOperation` subclasses.
     If you subclass `ObvOperation` and wish to customize its execution, you would
     do so by overriding the `execute()` method.
     
     At some point, your `ObvOperation` subclass must call one of the "finish"
     methods defined below; this is how you indicate that your operation has
     finished its execution, and that operations dependent on yours can re-evaluate
     their readiness state.
     */
    open func execute() {
        finish()
    }
    
    // MARK: Finishing
    
    private var hasFinishedAlready = false // Allows to ensure we only notify the observers once that the operation has finished.
    
    public final func finish() {
        if !hasFinishedAlready {
            hasFinishedAlready = true
            state = .Finishing
            
            if let operationIdentifier = self.operationIdentifier {
                ObvOperation.uidQueue.sync {
                    os_log("Will remove %@ from the set of executing operations", log: tempLog, type: .debug, operationIdentifier.debugDescription)
                    _ = ObvOperation.identifiersOfOperationsCurrentlyExecuting.remove(operationIdentifier)
                }
            }
            
            state = .Finished
            
            delegate?.operationDidFinish(operation: self)

            os_log("ObvOperation did finish: %@", log: log, type: .debug, self.operationIdentifier?.debugDescription ?? self.className)
        }
    }
}

// MARK: Implementing Comparable
extension ObvOperation.State {

    // Simple operator functions to simplify the assertions used above.
    static func < (lhs: ObvOperation.State, rhs: ObvOperation.State) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
    
    static func == (lhs: ObvOperation.State, rhs: ObvOperation.State) -> Bool {
        return lhs.rawValue == rhs.rawValue
    }

}


extension ObvOperation {
    
    public class func tryToSave(_ context: NSManagedObjectContext, logTo log: OSLog) {
        context.performAndWait {
            if context.hasChanges {
                do {
                    try context.save()
                } catch let error {
                    if let contextName = context.name {
                        os_log("We could not save the context %@: %@", log: log, type: .fault, contextName, error.localizedDescription)

                    } else {
                        os_log("We could not save the context: %@", log: log, type: .fault, error.localizedDescription)

                    }
                    return
                }
            }
        }
    }
    
}
