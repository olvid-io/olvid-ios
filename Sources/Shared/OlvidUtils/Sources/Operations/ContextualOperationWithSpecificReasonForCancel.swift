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
import CoreData

protocol ContextualOperation: Operation {

    var obvContext: ObvContext? { get set }
    var viewContext: NSManagedObjectContext? { get }
    
}


open class ContextualOperationWithSpecificReasonForCancel<ReasonForCancelType: LocalizedErrorWithLogType>: OperationWithSpecificReasonForCancel<ReasonForCancelType>, @unchecked Sendable, ContextualOperation, ObvErrorMaker {

    public static var errorDomain: String { String(describing: self) }

    public var obvContext: ObvContext?
    public var viewContext: NSManagedObjectContext?

    open override var debugDescription: String {
        let memoryAddress = Unmanaged.passUnretained(self).toOpaque().debugDescription
        return "\(String(describing: type(of: self)))<\(memoryAddress)>"
    }
    
    final public override func main() {
        // If we are cancelled, we return immediately. This is important so as to make sure that the mechanism implemented in, e.g., CompositionOfTwoContextualOperations.cancel(withReason:)
        // works properly.
        guard !isCancelled else {
            return
        }
        guard let obvContext else {
            assertionFailure()
            self.cancel()
            return
        }
        guard let viewContext else {
            assertionFailure()
            self.cancel()
            return
        }
        obvContext.performAndWait {
            main(obvContext: obvContext, viewContext: viewContext)
        }
    }
    
    /// This method is the one to override in subclasses, instead of the ``main()`` method. It is executed on a thread that is appropriate for the `ObvContext`.
    open func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        // Expected to be overridden in subclasses
    }
    
}
