/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import OSLog
import Combine


open class ObvDataSourceStreamManager<ViewModel: Sendable & Equatable>: NSObject, NSFetchedResultsControllerDelegate, @unchecked Sendable {
    
    public let streamUUID = UUID()
    public var stream: AsyncStream<ViewModel>?
    public var continuation: AsyncStream<ViewModel>.Continuation?
    var latestYieldedModel: ViewModel?
    private var dateOfLastYield = Date.distantPast
    
    public var debounceTimeInterval: TimeInterval = 0.3
    private var debouncedViewModel: (viewModel: ViewModel, requestId: UUID)?
    //private var debouncedViewModelAlt: ViewModel?
    private var currentDebounceTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "io.olvid.messenger", category: "ObvDataSourceStreamManager")
    
    func startStream() async throws -> (streamUUID: UUID, stream: AsyncStream<ViewModel>) {
        assertionFailure("Must be implemented by subclass")
        throw ObvDataSourceError.mustBeImplementedBySubclass
    }
                
    open func finishStream() {
        continuation?.finish()
        continuation = nil
    }
    
    
//    public func yieldModelIfNeededAlt(model: ViewModel, within context: NSManagedObjectContext) {
//        guard let continuation else { return }
//        
//        let timeToWait: TimeInterval = debounceTimeInterval - Date.now.timeIntervalSince(dateOfLastYield)
//        
//        if timeToWait <= 0 {
//            debouncedViewModelAlt = nil
//            guard latestYieldedModel != model else {
//                debugPrint("🐶 [\(self.debugDescription)] Previously yielded model is identical to the one to yield. skipping.")
//                return
//            }
//            latestYieldedModel = model
//            dateOfLastYield = .now
//            continuation.yield(model)
//            debugPrint("🐶 [\(self.debugDescription)] Did yield model")
//        } else {
//            if debouncedViewModel == nil {
//                Task {
//                    try await Task.sleep(seconds: timeToWait)
//                    await context.perform { [weak self] in
//                        guard let self else { return }
//                        guard let debouncedViewModelAlt else { return }
//                        self.debouncedViewModelAlt = nil
//                        guard latestYieldedModel != debouncedViewModelAlt else {
//                            debugPrint("🐶 [\(self.debugDescription)] Previously yielded model is identical to the one to yield. skipping.")
//                            return
//                        }
//                        latestYieldedModel = debouncedViewModelAlt
//                        dateOfLastYield = .now
//                        continuation.yield(debouncedViewModelAlt)
//                        debugPrint("🐶 [\(self.debugDescription)] Did yield model")
//                    }
//                }
//            }
//            debouncedViewModelAlt = model
//        }
//    }
    
    
    public func yieldModelIfNeeded(model: ViewModel, within context: NSManagedObjectContext) {
        guard let continuation else { return }
        currentDebounceTask?.cancel()
        currentDebounceTask = nil
        
        let timeToWait: TimeInterval = debounceTimeInterval - Date.now.timeIntervalSince(dateOfLastYield)
        debugPrint("🐶 [\(self.debugDescription)] timeToWait: \(timeToWait)")
        if timeToWait <= 0 {
            debouncedViewModel = nil
            guard latestYieldedModel != model else {
                debugPrint("🐶 [\(self.debugDescription)] Previously yielded model is identical to the one to yield. skipping.")
                return
            }
            latestYieldedModel = model
            dateOfLastYield = .now
            continuation.yield(model)
            debugPrint("🐶 [\(self.debugDescription)] Did yield model")
        } else {
            let debouncedRequestId = UUID()
            debouncedViewModel = nil
            guard latestYieldedModel != model else {
                debugPrint("🐶 [\(self.debugDescription)] Previously yielded model is identical to the one to yield. skipping.")
                return
            }
            debouncedViewModel = (viewModel: model, requestId: debouncedRequestId)
            currentDebounceTask = Task {
                do {
                    try await Task.sleep(seconds: timeToWait)
                    await context.perform { [weak self] in
                        guard let self else { return }
                        guard let debouncedViewModel else { return }
                        guard debouncedViewModel.requestId == debouncedRequestId else { return }
                        self.debouncedViewModel = nil
                        let model = debouncedViewModel.viewModel
                        guard latestYieldedModel != model else {
                            debugPrint("🐶 [\(self.debugDescription)] Previously yielded model is identical to the one to yield. skipping.")
                            return
                        }
                        latestYieldedModel = model
                        dateOfLastYield = .now
                        continuation.yield(model)
                        debugPrint("🐶 [\(self.debugDescription)] Did yield model")
                    }
                } catch {
                    debugPrint("🐶 [\(self.debugDescription)] Task cancelled as a new model arrived in the meantime.")
                }
            }
        }
    }

    open func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
        let logger = self.logger
        Task { [weak self] in
            do {
                try await self?.getFetchedObjectsAndYieldModelIfNeeded()
            } catch {
                logger.error("Failed to get fetched objects and yield new model version (this can happen, e.g., if the user requested the deletion of certain objects in database): \(error.localizedDescription)")
            }
        }
    }

    public func getFetchedObjectsAndYieldModelIfNeeded() async throws {
        assertionFailure("Must be implemented by subclass")
    }
    
    enum ObvDataSourceError: Error {
        case mustBeImplementedBySubclass
        case couldNotFetchObjects
        case inconsistentContexts
    }
    
}


// MARK: - ObvDataSourceStreamManagerWithOneFetchedResultsController

open class ObvDataSourceStreamManagerWithOneFetchedResultsController<ViewModel: Sendable & Equatable, ManagedObject: NSManagedObject>: ObvDataSourceStreamManager<ViewModel>, @unchecked Sendable {
    
    private let logger = Logger(subsystem: "io.olvid.messenger", category: "ObvDataSourceStreamManagerWithOneFetchedResultsController")

    public let frc: NSFetchedResultsController<ManagedObject>
    
    public init(frc: NSFetchedResultsController<ManagedObject>) {
        self.frc = frc
    }

    open override func startStream() async throws -> (streamUUID: UUID, stream: AsyncStream<ViewModel>) {
        if let stream { return (streamUUID, stream) }
        frc.delegate = self
        try await frc.managedObjectContext.perform { [weak self] in
            guard let self else { return }
            try frc.performFetch()
        }
        let logger = self.logger
        let stream = AsyncStream(ViewModel.self) { [weak self] (continuation: AsyncStream<ViewModel>.Continuation) in
            guard let self else { return }
            self.continuation = continuation
            Task { [weak self] in
                do {
                    try await self?.getFetchedObjectsAndYieldModelIfNeeded()
                } catch {
                    logger.error("Failed to fetch objects and yield model: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        self.stream = stream
        return (streamUUID, stream)
    }
    
    public override func getFetchedObjectsAndYieldModelIfNeeded() async throws {
        try await frc.managedObjectContext.perform { [weak self] in
            guard let self else { return }
            guard let fetchedObjects = frc.fetchedObjects else {
                assertionFailure()
                throw ObvDataSourceError.couldNotFetchObjects
            }
            let model = try createModel(fetchedObjects: fetchedObjects)
            yieldModelIfNeeded(model: model, within: frc.managedObjectContext)
        }
    }
    
    open func createModel(fetchedObjects: [ManagedObject]) throws -> ViewModel {
        assertionFailure("Must be implemented by subclass")
        throw ObvDataSourceError.mustBeImplementedBySubclass
    }
    
}


// MARK: - ObvDataSourceStreamManagerWithTwoFetchedResultsController

open class ObvDataSourceStreamManagerWithTwoFetchedResultsController<ViewModel: Sendable & Equatable, ManagedObject1: NSManagedObject, ManagedObject2: NSManagedObject>: ObvDataSourceStreamManager<ViewModel>, @unchecked Sendable {
    
    private let logger = Logger(subsystem: "io.olvid.messenger", category: "ObvDataSourceStreamManagerWithTwoFetchedResultsController")
    
    public let frc1: NSFetchedResultsController<ManagedObject1>
    public let frc2: NSFetchedResultsController<ManagedObject2>
    
    public init(frc1: NSFetchedResultsController<ManagedObject1>, frc2: NSFetchedResultsController<ManagedObject2>) {
        self.frc1 = frc1
        self.frc2 = frc2
    }

    open override func startStream() async throws -> (streamUUID: UUID, stream: AsyncStream<ViewModel>) {
        if let stream { return (streamUUID, stream) }
        try checkContextsForInconsistency()
        frc1.delegate = self
        frc2.delegate = self
        try await frc1.managedObjectContext.perform { [weak self] in
            guard let self else { return }
            try frc1.performFetch()
            try frc2.performFetch()
        }
        let logger = self.logger
        let stream = AsyncStream(ViewModel.self) { [weak self] (continuation: AsyncStream<ViewModel>.Continuation) in
            guard let self else { return }
            self.continuation = continuation
            Task { [weak self] in
                do {
                    try await self?.getFetchedObjectsAndYieldModelIfNeeded()
                } catch {
                    logger.error("Failed to fetch objects and yield model: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        self.stream = stream
        return (streamUUID, stream)
    }
    
    
    private func checkContextsForInconsistency() throws {
        guard frc1.managedObjectContext == frc2.managedObjectContext else {
            assertionFailure()
            throw ObvDataSourceError.inconsistentContexts
        }
    }
    

    public override func getFetchedObjectsAndYieldModelIfNeeded() async throws {
        try checkContextsForInconsistency()
        try await frc1.managedObjectContext.perform { [weak self] in
            guard let self else { return }
            guard let fetchedObjects1 = frc1.fetchedObjects, let fetchedObjects2 = frc2.fetchedObjects else {
                assertionFailure()
                throw ObvDataSourceError.couldNotFetchObjects
            }
            let model = try createModel(fetchedObjects1: fetchedObjects1, fetchedObjects2: fetchedObjects2)
            yieldModelIfNeeded(model: model, within: frc1.managedObjectContext)
        }
    }

    open func createModel(fetchedObjects1: [ManagedObject1], fetchedObjects2: [ManagedObject2]) throws -> ViewModel {
        assertionFailure("Must be implemented by subclass")
        throw ObvDataSourceError.mustBeImplementedBySubclass
    }

}


// MARK: - ObvDataSourceStreamManagerWithThreeFetchedResultsController

open class ObvDataSourceStreamManagerWithThreeFetchedResultsController<ViewModel: Sendable & Equatable, ManagedObject1: NSManagedObject, ManagedObject2: NSManagedObject, ManagedObject3: NSManagedObject>: ObvDataSourceStreamManager<ViewModel>, @unchecked Sendable {
    
    public let frc1: NSFetchedResultsController<ManagedObject1>
    public let frc2: NSFetchedResultsController<ManagedObject2>
    public let frc3: NSFetchedResultsController<ManagedObject3>
    
    public init(frc1: NSFetchedResultsController<ManagedObject1>, frc2: NSFetchedResultsController<ManagedObject2>, frc3: NSFetchedResultsController<ManagedObject3>) {
        self.frc1 = frc1
        self.frc2 = frc2
        self.frc3 = frc3
    }

    public override func startStream() async throws -> (streamUUID: UUID, stream: AsyncStream<ViewModel>) {
        if let stream { return (streamUUID, stream) }
        try checkContextsForInconsistency()
        frc1.delegate = self
        frc2.delegate = self
        frc3.delegate = self
        try await frc1.managedObjectContext.perform { [weak self] in
            guard let self else { return }
            try frc1.performFetch()
            try frc2.performFetch()
            try frc3.performFetch()
        }
        let stream = AsyncStream(ViewModel.self) { [weak self] (continuation: AsyncStream<ViewModel>.Continuation) in
            guard let self else { return }
            self.continuation = continuation
            Task { [weak self] in
                do {
                    try await self?.getFetchedObjectsAndYieldModelIfNeeded()
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }
        }
        self.stream = stream
        return (streamUUID, stream)
    }

    private func checkContextsForInconsistency() throws {
        guard frc1.managedObjectContext == frc2.managedObjectContext else {
            assertionFailure()
            throw ObvDataSourceError.inconsistentContexts
        }
        guard frc2.managedObjectContext == frc3.managedObjectContext else {
            assertionFailure()
            throw ObvDataSourceError.inconsistentContexts
        }
    }

    public override func getFetchedObjectsAndYieldModelIfNeeded() async throws {
        try checkContextsForInconsistency()
        try await frc1.managedObjectContext.perform { [weak self] in
            guard let self else { return }
            guard let fetchedObjects1 = frc1.fetchedObjects,
                  let fetchedObjects2 = frc2.fetchedObjects,
                  let fetchedObjects3 = frc3.fetchedObjects
            else {
                assertionFailure()
                throw ObvDataSourceError.couldNotFetchObjects
            }
            let model = try createModel(fetchedObjects1: fetchedObjects1, fetchedObjects2: fetchedObjects2, fetchedObjects3: fetchedObjects3)
            yieldModelIfNeeded(model: model, within: frc1.managedObjectContext)
        }
    }

    open func createModel(fetchedObjects1: [ManagedObject1], fetchedObjects2: [ManagedObject2], fetchedObjects3: [ManagedObject3]) throws -> ViewModel {
        assertionFailure("Must be implemented by subclass")
        throw ObvDataSourceError.mustBeImplementedBySubclass
    }

}


// MARK: - ObvDataSourceStreamManagerWithFourFetchedResultsController

open class ObvDataSourceStreamManagerWithFourFetchedResultsController<ViewModel: Sendable & Equatable, ManagedObject1: NSManagedObject, ManagedObject2: NSManagedObject, ManagedObject3: NSManagedObject, ManagedObject4: NSManagedObject>: ObvDataSourceStreamManager<ViewModel>, @unchecked Sendable {
    
    public let frc1: NSFetchedResultsController<ManagedObject1>
    public let frc2: NSFetchedResultsController<ManagedObject2>
    public let frc3: NSFetchedResultsController<ManagedObject3>
    public let frc4: NSFetchedResultsController<ManagedObject4>
    
    public init(frc1: NSFetchedResultsController<ManagedObject1>, frc2: NSFetchedResultsController<ManagedObject2>, frc3: NSFetchedResultsController<ManagedObject3>, frc4: NSFetchedResultsController<ManagedObject4>) {
        self.frc1 = frc1
        self.frc2 = frc2
        self.frc3 = frc3
        self.frc4 = frc4
    }

    public override func startStream() async throws -> (streamUUID: UUID, stream: AsyncStream<ViewModel>) {
        if let stream { return (streamUUID, stream) }
        try checkContextsForInconsistency()
        frc1.delegate = self
        frc2.delegate = self
        frc3.delegate = self
        frc4.delegate = self
        try await frc1.managedObjectContext.perform { [weak self] in
            guard let self else { return }
            try frc1.performFetch()
            try frc2.performFetch()
            try frc3.performFetch()
            try frc4.performFetch()
        }
        let stream = AsyncStream(ViewModel.self) { [weak self] (continuation: AsyncStream<ViewModel>.Continuation) in
            guard let self else { return }
            self.continuation = continuation
            Task { [weak self] in
                do {
                    try await self?.getFetchedObjectsAndYieldModelIfNeeded()
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }
        }
        self.stream = stream
        return (streamUUID, stream)
    }

    private func checkContextsForInconsistency() throws {
        guard frc1.managedObjectContext == frc2.managedObjectContext else {
            assertionFailure()
            throw ObvDataSourceError.inconsistentContexts
        }
        guard frc2.managedObjectContext == frc3.managedObjectContext else {
            assertionFailure()
            throw ObvDataSourceError.inconsistentContexts
        }
        guard frc3.managedObjectContext == frc4.managedObjectContext else {
            assertionFailure()
            throw ObvDataSourceError.inconsistentContexts
        }
    }
    
    public override func getFetchedObjectsAndYieldModelIfNeeded() async throws {
        try checkContextsForInconsistency()
        try await frc1.managedObjectContext.perform { [weak self] in
            guard let self else { return }
            guard let fetchedObjects1 = frc1.fetchedObjects,
                  let fetchedObjects2 = frc2.fetchedObjects,
                  let fetchedObjects3 = frc3.fetchedObjects,
                  let fetchedObjects4 = frc4.fetchedObjects
            else {
                assertionFailure()
                throw ObvDataSourceError.couldNotFetchObjects
            }
            let model = try createModel(fetchedObjects1: fetchedObjects1, fetchedObjects2: fetchedObjects2, fetchedObjects3: fetchedObjects3, fetchedObjects4: fetchedObjects4)
            yieldModelIfNeeded(model: model, within: frc1.managedObjectContext)
        }
    }

    open func createModel(fetchedObjects1: [ManagedObject1], fetchedObjects2: [ManagedObject2], fetchedObjects3: [ManagedObject3], fetchedObjects4: [ManagedObject4]) throws -> ViewModel {
        assertionFailure("Must be implemented by subclass")
        throw ObvDataSourceError.mustBeImplementedBySubclass
    }

}
