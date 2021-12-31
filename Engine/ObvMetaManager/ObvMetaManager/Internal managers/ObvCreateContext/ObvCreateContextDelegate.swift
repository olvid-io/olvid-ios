/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import os.log
import ObvTypes
import OlvidUtils

public protocol ObvCreateContextDelegate: ObvManager {
    
    var persistentStoreCoordinator: NSPersistentStoreCoordinator { get }
    
    func performBackgroundTask(file: StaticString, line: Int, function: StaticString, _ block: @escaping (NSManagedObjectContext) -> Void)
    func performBackgroundTaskAndWait(file: StaticString, line: Int, function: StaticString, _ block: (NSManagedObjectContext) -> Void)

    func performBackgroundTask(flowId: FlowIdentifier, file: StaticString, line: Int, function: StaticString, _ block: @escaping (ObvContext) -> Void)
    func performBackgroundTaskAndWait(flowId: FlowIdentifier, file: StaticString, line: Int, function: StaticString, _ block: (ObvContext) -> Void)

    func performBackgroundTaskAndWaitOrThrow(file: StaticString, line: Int, function: StaticString, _ block: (NSManagedObjectContext) throws -> Void) throws
    func performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier, file: StaticString, line: Int, function: StaticString, _ block: (ObvContext) throws -> Void) throws

    func debugPrintCurrentBackgroundContexts()

}

extension ObvCreateContextDelegate {
    
    public func performBackgroundTask(file: StaticString = #fileID, line: Int = #line, function: StaticString = #function, _ block: @escaping (NSManagedObjectContext) -> Void) {
        self.performBackgroundTask(file: file, line: line, function: function, block)
    }

    public func performBackgroundTaskAndWait(file: StaticString = #fileID, line: Int = #line, function: StaticString = #function, _ block: @escaping (NSManagedObjectContext) -> Void) {
        self.performBackgroundTaskAndWait(file: file, line: line, function: function, block)
    }

    func performBackgroundTaskAndWaitOrThrow(file: StaticString = #fileID, line: Int = #line, function: StaticString = #function, _ block: (NSManagedObjectContext) throws -> Void) throws {
        try self.performBackgroundTaskAndWaitOrThrow(file: file, line: line, function: function, block)
    }

    public func performBackgroundTask(flowId: FlowIdentifier, file: StaticString = #fileID, line: Int = #line, function: StaticString = #function, _ block: @escaping (ObvContext) -> Void) {
        self.performBackgroundTask(flowId: flowId, file: file, line: line, function: function, block)
    }
    
    public func performBackgroundTaskAndWait(flowId: FlowIdentifier, file: StaticString = #fileID, line: Int = #line, function: StaticString = #function, _ block: (ObvContext) -> Void) {
        self.performBackgroundTaskAndWait(flowId: flowId, file: file, line: line, function: function, block)
    }

    public func performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier, file: StaticString = #fileID, line: Int = #line, function: StaticString = #function, _ block: (ObvContext) throws -> Void) throws {
        try self.performBackgroundTaskAndWaitOrThrow(flowId: flowId, file: file, line: line, function: function, block)
    }


}
