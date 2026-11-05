/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

public protocol ObvContextCreator: Sendable {
    func newBackgroundContext(flowId: FlowIdentifier, file: StaticString, line: Int, function: StaticString) -> ObvContext
    func performBackgroundTask(file: StaticString, line: Int, function: StaticString, _ block: @escaping (NSManagedObjectContext) -> Void)
    var viewContext: NSManagedObjectContext { get }
}


public extension ObvContextCreator {
    
    func newBackgroundContext(flowId: FlowIdentifier, file: StaticString = #file, line: Int = #line, function: StaticString = #function) -> ObvContext {
        newBackgroundContext(flowId: flowId, file: file, line: line, function: function)
    }
    
    func performBackgroundTask(file: StaticString = #file, line: Int = #line, function: StaticString = #function, _ block: @escaping (NSManagedObjectContext) -> Void) {
        performBackgroundTask(file: file, line: line, function: function, block)
    }

}
