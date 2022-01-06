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

open class ObvOperationWrapper<WrappedObvOperationType: ObvOperation>: ObvOperation {
    
    override open var className: String {
        return "ObvOperationWrapper<\(wrappedOperation.className)>"
    }

    let log = OSLog(subsystem: ObvOperation.defaultLogSubsystem, category: "ObvOperationWrapper")
    
    private var wrappedOperationStateObservation: NSKeyValueObservation? = nil
    
    private let internalDispatchQueue = DispatchQueue(label: "io.olvid.ObvOperationWrapper")
    private var wrappedOperationDidStartTriggered = false
    private var wrappedOperationDidFinishTriggered = false
    

    public let wrappedOperation: WrappedObvOperationType
    
    public init(wrappedOperation: WrappedObvOperationType) {
        self.wrappedOperation = wrappedOperation
        super.init(uid: wrappedOperation.uid)
        if let wrappedOperationName = wrappedOperation.name {
            name = "ObvOperationWrapper<\(wrappedOperationName)>"
        }
    }
    
    final override public func execute() {
        wrappedOperationStateObservation = wrappedOperation.observe(\.state) { [weak self] (op, change) in
            
            var doTriggerMethod = false
            
            switch op.state {
                
            case .Executing:
                self?.internalDispatchQueue.sync {
                    if self?.wrappedOperationDidStartTriggered == false {
                        self?.wrappedOperationDidStartTriggered = true
                        doTriggerMethod = true
                    }
                }
                if doTriggerMethod {
                    self?.wrappedOperationDidStart(operation: op)
                }

            case .Finished:
                self?.internalDispatchQueue.sync {
                    if self?.wrappedOperationDidFinishTriggered == false {
                        self?.wrappedOperationDidFinishTriggered = true
                        doTriggerMethod = true
                    }
                }
                if doTriggerMethod {
                    if op.isCancelled {
                        self?.wrapperOperationWillFinishAndWrappedOperationDidCancel(operation: op)
                    } else {
                        self?.wrapperOperationWillFinishAndWrappedOperationDidFinishWithoutCancelling(operation: op)
                    }
                }
                self?.finish()
                if doTriggerMethod {
                    if op.isCancelled {
                        self?.wrapperOperationDidFinishAndWrappedOperationDidCancel(operation: op)
                    } else {
                        self?.wrapperOperationDidFinishAndWrappedOperationDidFinishWithoutCancelling(operation: op)
                    }
                }

            default:
                break
            }
            
        }
        
        let internalQueue = ObvOperationQueue()
        internalQueue.addOperation(wrappedOperation)
        
    }

    open func wrappedOperationDidStart(operation: WrappedObvOperationType) {
        // Default implementation does nothing
    }
    
    open func wrapperOperationWillFinishAndWrappedOperationDidFinishWithoutCancelling(operation: WrappedObvOperationType) {
        // Default implementation does nothing
    }
    
    open func wrapperOperationWillFinishAndWrappedOperationDidCancel(operation: WrappedObvOperationType) {
        // Default implementation does nothing
    }
    
    open func wrapperOperationDidFinishAndWrappedOperationDidFinishWithoutCancelling(operation: WrappedObvOperationType) {
        // Default implementation does nothing
    }
    
    open func wrapperOperationDidFinishAndWrappedOperationDidCancel(operation: WrappedObvOperationType) {
        // Default implementation does nothing
    }
    
    deinit {
        os_log("This wrapper operation will deinit: %@", log: log, type: .debug, className)
    }
}
