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
import ObvCoreDataStack
import ObvMetaManager
import ObvTypes
import OlvidUtils


/// **`@unchecked Sendable`, and what is being promised is an order rather than a lock.**
///
/// The conformance is not asked for here: `ObvCreateContextDelegate` inherits `ObvContextCreator`, which is `Sendable`, so this class is required to be one
/// from two protocols away. Two of its stored properties are written after `init` — ``coreDataStack``, in `finalizeInitialization(flowId:runningLog:)`, and
/// ``logSubsystem``, in `prependLogSubsystem(with:)` — which is what the compiler objects to, and it is right to: it cannot see when either happens.
///
/// **What makes it safe is the engine's startup sequence, and it is explicit rather than incidental.** `ObvMetaManager` finds the context delegate among the
/// registered managers and finalises *it* before all the others, precisely because the others need the stack it makes. Both writes therefore happen while the
/// engine is being built, on one thread, before anything holds this object to use it; everything afterwards only reads.
///
/// So this is the house pattern for an engine manager rather than a shortcut — and it is the promise that would have to be revisited if a write ever moved
/// out of startup. A stack handed in at `init` would need no promise at all, but `finalizeInitialization` is mandated by `ObvManager` and has to run the
/// migration first, so that is a change to how the engine starts rather than to this line.
public final class ObvDatabaseManager: ObvCreateContextDelegate, @unchecked Sendable {
    
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

    public func applicationWasInitializedButWasNeverOnScreen(flowId: FlowIdentifier) async {}
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {}

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

    
    public func performBackgroundTaskAndWaitOrThrow<T>(file: StaticString, line: Int, function: StaticString, _ block: (NSManagedObjectContext) throws -> T) throws -> T {
        try coreDataStack.performBackgroundTaskAndWaitOrThrow { (context) in
            context.name = "\(file) - \(function) - Line \(line)"
            assert(context.transactionAuthor != nil)
            return try block(context)
        }
    }
    
    
    public func performBackgroundTaskAndWaitOrThrow<T>(flowId: FlowIdentifier, file: StaticString, line: Int, function: StaticString, _ block: (ObvContext) throws -> T) throws -> T {
        return try coreDataStack.performBackgroundTaskAndWaitOrThrow { context in
            context.name = "\(file) - \(function) - Line \(line)"
            assert(context.transactionAuthor != nil)
            let obvContext = ObvContext(context: context, flowId: flowId, file: file, line: line, function: function)
            let returnedValue: T
            do {
                returnedValue = try block(obvContext)
            } catch {
                obvContext.performAllEndOfScopeCompletionHAndlers()
                throw error
            }
            obvContext.performAllEndOfScopeCompletionHAndlers()
            return returnedValue
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
        let manager = DataMigrationManagerForObvEngine(modelName: "ObvEngine",
                                                       storeName: "ObvEngine",
                                                       transactionAuthor: transactionAuthor,
                                                       enableMigrations: enableMigrations,
                                                       migrationRunningLog: runningLog)
        try manager.initializeCoreDataStack()
        self.coreDataStack = manager.coreDataStack
    }
    
    public func fulfill(requiredDelegate: AnyObject, forDelegateType: ObvEngineDelegateType) throws {}
    
    public static var bundleIdentifier: String { return "io.olvid.ObvDatabaseManager" }
    
    public static var dataModelNames: [String] { return [] }
    
}
