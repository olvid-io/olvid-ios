/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


open class AsyncOperationWithSpecificReasonForCancel<ReasonForCancelType: LocalizedErrorWithLogType>: OperationWithSpecificReasonForCancel<ReasonForCancelType>, @unchecked Sendable {
    
    
    private var _isFinished = false {
        willSet { willChangeValue(for: \.isFinished) }
        didSet { didChangeValue(for: \.isFinished) }
    }
    
    
    final public override var isFinished: Bool { _isFinished }

    
    final public override func cancel(withReason reason: ReasonForCancelType) {
        super.cancel(withReason: reason)
        _isFinished = true
    }
    

    final public func finish() {
        _isFinished = true
    }

    
    final public override func main() {
        Task {
            await main()
            // Prevent a deadlock if the call forgot to call ``finish()``.
            if !isFinished {
                assertionFailure("Your operationimplementation did not call finish() as it should")
                return finish()
            }
        }
    }
    
    /// This method is the one to override in subclasses, instead of the ``main()`` method.
    /// The override *must* call either ``finish()`` or ``cancel(withReason:)`` in order to finish this operation (and preventing a potential deadlock if the queue is a serial queue).
    open func main() async {
        // Expected to be overridden in subclasses
        assertionFailure("Expected to be overridden in subclasses")
        return finish()
    }

}
