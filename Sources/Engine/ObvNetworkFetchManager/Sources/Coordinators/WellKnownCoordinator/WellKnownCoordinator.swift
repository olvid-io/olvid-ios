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
import os.log
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils


protocol WellKnownCacheDelegate: AnyObject {

    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) async throws
    func initializateCache(flowId: FlowIdentifier) async throws
    func downloadAndUpdateCache(flowId: FlowIdentifier) async throws
    func getTurnURLs(for server: URL, flowId: FlowIdentifier) async throws -> Result<[String], WellKnownCacheError>
    func getWebSocketURL(for server: URL, flowId: FlowIdentifier) async throws -> URL
    func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) async throws

}


actor WellKnownCoordinator {
    
    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "WellKnownCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)

    private static let wellKnownPath = "/.well-known"
    private static let serverConfigName = "server-config.json"

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    private var wellKnownDownloadTasks = [URL: WellKnownDownloadTask]()
    private enum WellKnownDownloadTask {
        case inProgress(task: Task<(wellKnown: WellKnownJSON, isUpdated: Bool), Error>)
    }
        
    private var wellKnownCache = [URL: WellKnownJSON]()
    private var isCacheInitialized = false

    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    init(logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
    }

    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

}


// MARK: - WellKnownCacheDelegate

extension WellKnownCoordinator: WellKnownCacheDelegate {
    
    
    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            throw ObvError.theDelegateManagerIsNotSet
        }

        let op1 = DeleteObsoleteCachedWellKnownOperation(ownedIdentities: ownedIdentities)
        do {
            try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
        } catch {
            os_log("The DeleteObsoleteCachedWellKnownOperation failed", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.failedToDeleteObsoleteCachedWellKnown
        }
        
        let servers = Set(ownedIdentities.map({ $0.serverURL }))

        await withTaskGroup(of: Void.self) { group in
            for server in servers {
                group.addTask { [weak self] in
                    guard let self else { return }
                    let (wellKnown, isUpdated) = await downloadAndCacheWellKnownFromServer(serverURL: server, delegateManager: delegateManager, flowId: flowId)
                    Task { [weak self] in
                        guard let self else { return }
                        await notifyDelegateAboutCachedWellKnown(server: server, wellKnown: wellKnown, isUpdated: isUpdated, delegateManager: delegateManager, flowId: flowId)
                    }
                }
            }
        }
        
//        for server in servers {
//            let (wellKnown, isUpdated) = await downloadAndCacheWellKnownFromServer(serverURL: server, delegateManager: delegateManager, flowId: flowId)
//            Task {
//                notifyDelegateAboutCachedWellKnown(server: server, wellKnown: wellKnown, isUpdated: isUpdated, delegateManager: delegateManager, flowId: flowId)
//            }
//        }
        
    }
    
    
    func initializateCache(flowId: FlowIdentifier) async throws {
        
        guard !isCacheInitialized else { return }
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            throw ObvError.theDelegateManagerIsNotSet
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: Self.log, type: .fault)
            throw ObvError.theContextCreatorIsNotSet
        }

        // Fill the cache with what we already have in database

        let valuesFromDB = try await getWellKnownFromDatabase(contextCreator: contextCreator, flowId: flowId)
        for (serverURL, wellKnown) in valuesFromDB {
            wellKnownCache[serverURL] = wellKnown
        }
        
        isCacheInitialized = true

    }
    
    
    func downloadAndUpdateCache(flowId: FlowIdentifier) async throws {
        let ownedIdentities = try await getOwnedCryptoIds(flowId: flowId)
        try await updatedListOfOwnedIdentites(ownedIdentities: ownedIdentities, flowId: flowId)
    }

    
    func getTurnURLs(for server: URL, flowId: FlowIdentifier) async throws -> Result<[String], WellKnownCacheError> {
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        try await initializateCache(flowId: flowId)
        
        if let wellKnown = wellKnownCache[server] {
            return .success(wellKnown.serverConfig.turnServerURLs)
        } else {
            let (wellKnown, isUpdated) = await downloadAndCacheWellKnownFromServer(serverURL: server, delegateManager: delegateManager, flowId: flowId)
            Task {
                notifyDelegateAboutCachedWellKnown(server: server, wellKnown: wellKnown, isUpdated: isUpdated, delegateManager: delegateManager, flowId: flowId)
            }
            return .success(wellKnown.serverConfig.turnServerURLs)
        }

    }
    
    
    func getWebSocketURL(for server: URL, flowId: FlowIdentifier) async throws -> URL {
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        try await initializateCache(flowId: flowId)

        if let wellKnown = wellKnownCache[server] {
            return wellKnown.serverConfig.webSocketURL
        } else {
            let (wellKnown, isUpdated) = await downloadAndCacheWellKnownFromServer(serverURL: server, delegateManager: delegateManager, flowId: flowId)
            Task {
                notifyDelegateAboutCachedWellKnown(server: server, wellKnown: wellKnown, isUpdated: isUpdated, delegateManager: delegateManager, flowId: flowId)
            }
            return wellKnown.serverConfig.webSocketURL
        }
        
    }


    func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) async throws {
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        let (wellKnown, isUpdated) = await downloadAndCacheWellKnownFromServer(serverURL: serverURL, delegateManager: delegateManager, flowId: flowId)
        Task {
            notifyDelegateAboutCachedWellKnown(server: serverURL, wellKnown: wellKnown, isUpdated: isUpdated, delegateManager: delegateManager, flowId: flowId)
        }
        
    }
    
}


// MARK: - Helpers

extension WellKnownCoordinator {
    
    private func getWellKnownFromDatabase(contextCreator: ObvCreateContextDelegate, flowId: FlowIdentifier) async throws -> [URL: WellKnownJSON] {
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[URL: WellKnownJSON], Error>) in
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
                var returnedValues = [URL: WellKnownJSON]()
                do {
                    let cachedWellKnowns = try CachedWellKnown.getAllCachedWellKnown(within: obvContext)
                    for cachedWellKnown in cachedWellKnowns {
                        guard let wellKnown = cachedWellKnown.wellKnownJSON else { assertionFailure(); continue }
                        returnedValues[cachedWellKnown.serverURL] = wellKnown
                    }
                    return continuation.resume(returning: returnedValues)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
            
        }
    }

    
    private func notifyDelegateAboutCachedWellKnown(server: URL, wellKnown: WellKnownJSON, isUpdated: Bool, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) {
        delegateManager.networkFetchFlowDelegate.newWellKnownWasCached(
            server: server,
            newWellKnownJSON: wellKnown,
            flowId: flowId)
        if isUpdated {
            delegateManager.networkFetchFlowDelegate.cachedWellKnownWasUpdated(
                server: server,
                newWellKnownJSON: wellKnown,
                flowId: flowId)
        } else {
            delegateManager.networkFetchFlowDelegate.currentCachedWellKnownCorrespondToThatOnServer(
                server: server,
                wellKnownJSON: wellKnown,
                flowId: flowId)
        }
    }

    
    private func createTaskToDownloadAndCacheWellKnown(serverURL: URL, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) -> Task<(wellKnown: WellKnownJSON, isUpdated: Bool), Error> {
        return Task {
            
            let url = serverURL
                .appendingPathComponent(Self.wellKnownPath)
                .appendingPathComponent(Self.serverConfigName)

            var urlRequest = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 60)
            urlRequest.allowsCellularAccess = true
            urlRequest.allowsConstrainedNetworkAccess = true
            urlRequest.allowsExpensiveNetworkAccess = true

            let (data, response) = try await URLSession.shared.data(for: urlRequest)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
//                assertionFailure()
                throw ObvError.wellKnownWasDownloadFailed
            }
            
            guard (try? WellKnownJSON.decode(data)) != nil else {
                assertionFailure()
                throw ObvError.wellKnownWasDownloadFailed
            }

            let op1 = UpdateCachedWellKnownOperation(server: serverURL, newWellKnownData: data, flowId: flowId)
            do {
                try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
            } catch {
                assertionFailure()
                throw ObvError.failedToUpdateCachedWellKnown
            }
            
            guard let (wellKnownJSON, isUpdated) = op1.cachedWellKnownJSON else {
                assertionFailure()
                throw ObvError.failedToUpdateCachedWellKnown
            }
            
            wellKnownCache[serverURL] = wellKnownJSON
            
            return (wellKnownJSON, isUpdated)
            
        }
    }

    
    private func downloadAndCacheWellKnownFromServer(serverURL: URL, delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async -> (wellKnown: WellKnownJSON, isUpdated: Bool) {
        
        do {
            
            if let cached = wellKnownDownloadTasks[serverURL] {
                switch cached {
                case .inProgress(task: let task):
                    return try await task.value
                }
            }
            
            // No cached task, we create one and cache it
            
            let downloadTask = createTaskToDownloadAndCacheWellKnown(serverURL: serverURL, delegateManager: delegateManager, flowId: flowId)
            
            let wellKnown: WellKnownJSON
            let isUpdated: Bool
            
            do {
                wellKnownDownloadTasks[serverURL] = .inProgress(task: downloadTask)
                (wellKnown, isUpdated) = try await downloadTask.value
                wellKnownDownloadTasks.removeValue(forKey: serverURL)
            } catch {
                wellKnownDownloadTasks.removeValue(forKey: serverURL)
                throw error
            }
            
            failedAttemptsCounterManager.reset(counter: .queryServerWellKnown(serverURL: serverURL))

            return (wellKnown, isUpdated)
            
        } catch {
            
            let delay = failedAttemptsCounterManager.incrementAndGetDelay(.queryServerWellKnown(serverURL: serverURL))
            os_log("Will retry the call to downloadAndCacheWellKnownFromServer in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
            await retryManager.waitForDelay(milliseconds: delay)
            return await downloadAndCacheWellKnownFromServer(serverURL: serverURL, delegateManager: delegateManager, flowId: flowId)
            
        }
        
    }

    
    private func getOwnedCryptoIds(flowId: FlowIdentifier) async throws -> Set<ObvCryptoIdentity> {
        
        guard let delegateManager = delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theDelegateManagerIsNotSet
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The Identity Delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theIdentityDelegateIsNotSet
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.theContextCreatorIsNotSet
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Set<ObvCryptoIdentity>, Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let ownedIdentities = try identityDelegate.getOwnedIdentities(restrictToActive: true, within: obvContext)
                    return continuation.resume(returning: ownedIdentities)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
        
    }

}


enum WellKnownCacheError: Error {
    case cacheNotInitialized
    case missingValue
}


// MARK: - Errors

extension WellKnownCoordinator {
    
    enum ObvError: Error {
        case theDelegateManagerIsNotSet
        case theContextCreatorIsNotSet
        case failedToDeleteObsoleteCachedWellKnown
        case wellKnownWasDownloadFailed
        case failedToUpdateCachedWellKnown
        case theIdentityDelegateIsNotSet
    }
    
}
