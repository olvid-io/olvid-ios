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
import CoreData
import os.log

public final class ObvContext: Hashable {
    
    public let context: NSManagedObjectContext
    public let flowId: FlowIdentifier
    private var token: NSObjectProtocol?
    public let uuid = UUID()
    private var saveWasCalledWithOnSaveCompletionHandlers = false
    private var saveWasCalled = false
    private let file: StaticString
    private let line: Int
    private let function: StaticString

    // We distinguish two types of completion handlers:
    // - contextWillSaveCompletionHandlers are called when saving the context, just before the save() method is called
    // - contextDidSaveCompletionHandlers are called on save and any save error is passed to them
    // - endOfScopeCompletionHandlers are called when exiting the context block (the actual call is implemented at the stack level)
    private var contextWillSaveCompletionHandlers = [() -> Void]()
    private var contextDidSaveCompletionHandlers = [(Error?) -> Void]()
    private var endOfScopeCompletionHandlers = [() -> Void]()

    
    public init(context: NSManagedObjectContext, flowId: FlowIdentifier, file: StaticString, line: Int, function: StaticString) {
        self.file = file
        self.line = line
        self.function = function
        self.context = context
        self.flowId = flowId
        self.token = NotificationCenter.default.addObserver(forName: Notification.Name.NSManagedObjectContextDidSave, object: context, queue: nil) { [weak self] (notification) in
            guard let _self = self else { return }
            guard let notificationContext = notification.object as? NSManagedObjectContext else { return }
            assert(notificationContext == _self.context)
            if !_self.saveWasCalled {
                assertionFailure("The NSManagedObjectContext of an ObvContext seems to have been saved without calling save() on the ObvContext, which is an error.")
            }
        }
    }

    public func canAddContextDidSaveCompletionHandler() -> Bool {
        return !saveWasCalledWithOnSaveCompletionHandlers
    }

    public func canAddContextWillSaveCompletionHandler() -> Bool {
        return !saveWasCalledWithOnSaveCompletionHandlers
    }

    public func addContextDidSaveCompletionHandler(_ completionHandler: @escaping (Error?) -> Void) throws {
        guard !saveWasCalledWithOnSaveCompletionHandlers else {
            let message = "Cannot add a completion handler to an ObvContext that has already been saved"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: "ObvContext", code: 0, userInfo: userInfo)
        }
        contextDidSaveCompletionHandlers.insert(completionHandler, at: 0)
    }

    public func addContextWillSaveCompletionHandler(_ completionHandler: @escaping () -> Void) throws {
        guard !saveWasCalledWithOnSaveCompletionHandlers else {
            let message = "Cannot add a completion handler to an ObvContext that has already been saved"
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: "ObvContext", code: 0, userInfo: userInfo)
        }
        contextWillSaveCompletionHandlers.insert(completionHandler, at: 0)
    }

    
    public func addEndOfScopeCompletionHandler(_ handler: @escaping () -> Void) {
        endOfScopeCompletionHandlers.insert(handler, at: 0)
    }
    
    
    /// Saving an ObvContext *must* be done by means of this method. One should *never* save the underlying
    /// `NSManagedObjectContext` directly.
    public func save(logOnFailure log: OSLog) throws {
        self.saveWasCalled = true
        if saveWasCalledWithOnSaveCompletionHandlers {
            assertionFailure("An ObvContext cannot be saved twice if it has completion handlers")
        }
        // If we save this obvContext and if it has completion handlers, we don't accept a second save in the future
        if !contextDidSaveCompletionHandlers.isEmpty {
            self.saveWasCalledWithOnSaveCompletionHandlers = true
        }
        performAllContextWillSaveCompletionHandlers()
        do {
            try self.context.save(logOnFailure: log)
        } catch let error {
            performAllContextDidSaveCompletionHandlers(error: error)
            throw error
        }
        performAllContextDidSaveCompletionHandlers(error: nil)
    }
 
    
    deinit {
        if let token {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    private func performAllContextWillSaveCompletionHandlers() {
        while let completionHandler = self.contextWillSaveCompletionHandlers.popLast() {
            completionHandler()
        }
    }
    
    private func performAllContextDidSaveCompletionHandlers(error: Error?) {
        while let completionHandler = self.contextDidSaveCompletionHandlers.popLast() {
            completionHandler(error)
        }
    }

    
    public func performAllEndOfScopeCompletionHAndlers() {
        while let handler = self.endOfScopeCompletionHandlers.popLast() {
            handler()
        }
    }
    
    public static func == (lhs: ObvContext, rhs: ObvContext) -> Bool {
        return lhs.uuid == rhs.uuid
    }

    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.uuid)
    }
    
    public func createChildObvContext() -> ObvContext {
        let childContext = NSManagedObjectContext(concurrencyType: self.context.concurrencyType)
        childContext.parent = self.context
        return ObvContext(context: childContext, flowId: flowId, file: file, line: line, function: function)
    }
    
}

// MARK: - Replicating NSManagedObjectContext methods

extension ObvContext {
    
    public func mergeChanges(fromContextDidSave notification: Notification) {
        self.context.mergeChanges(fromContextDidSave: notification)
    }

    public func refreshAllObjects() {
        self.context.refreshAllObjects()
    }
    
    public func fetch<T: ObvManagedObject>(_ request: NSFetchRequest<T>) throws -> [T] {
        let items = try self.context.fetch(request)
        return items.map { $0.obvContext = self; return $0 }
    }

    
    public func delete(_ object: ObvManagedObject) {
        object.obvContext = self
        self.context.delete(object)
    }
    
    
    public func count<T>(for request: NSFetchRequest<T>) throws -> Int {
        return try self.context.count(for: request)
    }

    
    public func execute(_ request: NSPersistentStoreRequest) throws -> NSPersistentStoreResult {
        return try self.context.execute(request)
    }
    
    
    public func refresh(_ object: NSManagedObject, mergeChanges flag: Bool) {
        return self.context.refresh(object, mergeChanges: flag)
    }
    
    
    public func existingObject(with objectID: NSManagedObjectID) throws -> NSManagedObject {
        let item = try self.context.existingObject(with: objectID)
        (item as? ObvManagedObject)?.obvContext = self
        return item
    }
    
    
    public var persistentStoreCoordinator: NSPersistentStoreCoordinator? {
        get {
            return self.context.persistentStoreCoordinator
        }
        set {
            self.context.persistentStoreCoordinator = newValue
        }
    }
    
    
    public var mergePolicy: Any {
        get {
            return self.context.mergePolicy
        }
        set {
            self.context.mergePolicy = newValue
        }
    }
    
    
    public var name: String {
        "\(file) - \(function) - Line \(line) - UUID \(self.uuid.uuidString)"
    }
    
    
    public func performAndWait(_ block: () -> Void) {
        self.context.performAndWait(block)
    }

    
    public func performAndWaitOrThrow(_ block: () throws -> Void) throws {
        var error: Error? = nil
        self.context.performAndWait {
            do {
                try block()
            } catch let err {
                error = err
            }
        }
        guard error == nil else {
            throw error!
        }
    }

    
    public func perform(_ block: @escaping () -> Void) {
        self.context.perform(block)
    }
    
    public var registeredObjects: Set<NSManagedObject> {
        return self.context.registeredObjects
    }
    
}


// MARK: - Extending NSEntityDescription for ObvContext

public extension NSEntityDescription {
    
    class func entity(forEntityName entityName: String, in obvContext: ObvContext) -> NSEntityDescription? {
        return NSEntityDescription.entity(forEntityName: entityName, in: obvContext.context)
    }
    
}


// MARK: - Extending NSManagedObject for ObvContext

public extension NSManagedObject {
    
    convenience init(entity: NSEntityDescription, insertInto obvContext: ObvContext?) {
        self.init(entity: entity, insertInto: obvContext?.context)
        if let _self = self as? ObvManagedObject {
            _self.obvContext = obvContext
        }
    }

}

// MARK: - ObvManagedObject

public protocol ObvManagedObject: NSManagedObject {
    var obvContext: ObvContext? { get set }
}
