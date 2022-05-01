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
import CoreData
import CoreDataStack
import ObvMetaManager
import ObvTypes
import OlvidUtils


public final class ObvDatabaseManager: ObvCreateContextDelegate {
    
    public class var containerURL: URL? {
        get {
            return ObvEnginePersistentContainer.containerURL
        }
        set {
            ObvEnginePersistentContainer.containerURL = newValue
        }
    }

    private let stackName: String
    private let transactionAuthor: String
    private let enableMigrations: Bool
    
    // This is set in the `func finalizeInitialization(flowId: FlowIdentifier) throws` method
    private var coreDataStack: CoreDataStack<ObvEnginePersistentContainer>!
    
    public private(set) var logSubsystem = "io.olvid.database.manager"
    
    public func prependLogSubsystem(with prefix: String) {
        logSubsystem = "\(prefix).\(logSubsystem)"
    }

    lazy private var log = OSLog(subsystem: logSubsystem, category: "ObvDatabaseManager")

    public func applicationDidStartRunning(flowId: FlowIdentifier) {}
    public func applicationDidEnterBackground() {}

    // MARK: - Initializer
    
    public init(name: String, transactionAuthor: String, enableMigrations: Bool) {
        self.stackName = name
        self.transactionAuthor = transactionAuthor
        self.enableMigrations = enableMigrations
    }

}


// MARK: - ObvCreateContextDelegate

extension ObvDatabaseManager {
    
    public var persistentStoreCoordinator: NSPersistentStoreCoordinator {
        self.coreDataStack.persistentStoreCoordinator
    }
    
    public func performBackgroundTask(file: StaticString, line: Int, function: StaticString, _ block: @escaping (NSManagedObjectContext) -> Void) {
        coreDataStack.performBackgroundTask { (context) in
            context.name = "\(file) - \(function) - Line \(line)"
            assert(context.transactionAuthor != nil)
            block(context)
        }
    }

    
    public func performBackgroundTask(flowId: FlowIdentifier, file: StaticString, line: Int, function: StaticString, _ block: @escaping (ObvContext) -> Void) {
        coreDataStack.performBackgroundTask { (context) in
            context.name = "\(file) - \(function) - Line \(line)"
            assert(context.transactionAuthor != nil)
            let obvContext = ObvContext(context: context, flowId: flowId, file: file, line: line, function: function)
            block(obvContext)
            obvContext.performAllEndOfScopeCompletionHAndlers()
        }
    }

    
    public func performBackgroundTaskAndWait(file: StaticString, line: Int, function: StaticString, _ block: (NSManagedObjectContext) -> Void) {
        coreDataStack.performBackgroundTaskAndWait { (context) in
            context.name = "\(file) - \(function) - Line \(line)"
            assert(context.transactionAuthor != nil)
            block(context)
        }
    }

    
    public func performBackgroundTaskAndWait(flowId: FlowIdentifier, file: StaticString, line: Int, function: StaticString, _ block: (ObvContext) -> Void) {
        coreDataStack.performBackgroundTaskAndWait(file: file, line: line, function: function) { (context) in
            context.name = "\(file) - \(function) - Line \(line)"
            assert(context.transactionAuthor != nil)
            let obvContext = ObvContext(context: context, flowId: flowId, file: file, line: line, function: function)
            block(obvContext)
            obvContext.performAllEndOfScopeCompletionHAndlers()
        }
    }

    
    public func performBackgroundTaskAndWaitOrThrow(file: StaticString, line: Int, function: StaticString, _ block: (NSManagedObjectContext) throws -> Void) throws {
        try coreDataStack.performBackgroundTaskAndWaitOrThrow { (context) in
            context.name = "\(file) - \(function) - Line \(line)"
            assert(context.transactionAuthor != nil)
            try block(context)
        }
    }

    
    public func performBackgroundTaskAndWaitOrThrow(flowId: FlowIdentifier, file: StaticString, line: Int, function: StaticString, _ block: (ObvContext) throws -> Void) throws {
        try coreDataStack.performBackgroundTaskAndWaitOrThrow { (context) in
            context.name = "\(file) - \(function) - Line \(line)"
            assert(context.transactionAuthor != nil)
            let obvContext = ObvContext(context: context, flowId: flowId, file: file, line: line, function: function)
            do {
                try block(obvContext)
            } catch {
                obvContext.performAllEndOfScopeCompletionHAndlers()
                throw error
            }
            obvContext.performAllEndOfScopeCompletionHAndlers()
        }
    }

    
    public func debugPrintCurrentBackgroundContexts() {
    }
}


// MARK: - Implementing ObvContextCreator

extension ObvDatabaseManager {

    public func newBackgroundContext(flowId: FlowIdentifier, file: StaticString = #fileID, line: Int = #line, function: StaticString = #function) -> ObvContext {
        return coreDataStack.newBackgroundContext(flowId: flowId, file: file, line: line, function: function)
    }
    
    public var viewContext: NSManagedObjectContext {
        return coreDataStack.viewContext
    }
    
}


// MARK: - Implementing ObvManager

extension ObvDatabaseManager {
    public var requiredDelegates: [ObvEngineDelegateType] {
        return [ObvEngineDelegateType]()
    }
    
    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {
        let manager = DataMigrationManagerForObvEngine(modelName: "ObvEngine", storeName: "ObvEngine", transactionAuthor: transactionAuthor, enableMigrations: enableMigrations, migrationRunningLog: runningLog)
        try manager.initializeCoreDataStack()
        self.coreDataStack = manager.coreDataStack
    }
    
    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    
    public static var bundleIdentifier: String { return "io.olvid.ObvDatabaseManager" }
    
    public static var dataModelNames: [String] { return [] }
    
}


extension CoreDataStack: ObvContextCreator {
    
    public func newBackgroundContext(flowId: FlowIdentifier, file: StaticString = #fileID, line: Int = #line, function: StaticString = #function) -> ObvContext {
        let context = newBackgroundContext()
        let obvContext = ObvContext(context: context, flowId: flowId, file: file, line: line, function: function)
        return obvContext
    }
    
}
