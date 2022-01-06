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
import ObvTypes
import ObvCrypto
import ObvMetaManager
import OlvidUtils

enum WellKnownCacheError: Error {
    case cacheNotInitialized
    case missingValue
}

protocol WellKnownCacheDelegate: AnyObject {

    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier)
    func initializateCache(flowId: FlowIdentifier)
    func getTurnURLs(for server: URL, flowId: FlowIdentifier) -> Result<[String], WellKnownCacheError>
    func getWebSocketURL(for server: URL, flowId: FlowIdentifier) -> Result<URL, WellKnownCacheError>
    func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier)

}


final class WellKnownCoordinator {

    // MARK: - Instance variables

    fileprivate let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    fileprivate let logCategory = "WellKnownCoordinator"

    private static let errorDomain = "WellKnownCoordinator"
    private func makeError(message: String) -> Error { NSError(domain: WellKnownCoordinator.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private let queueForNotifications = OperationQueue()
    
    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "WellKnownCoordinator internal Queue"
        return queue
    }()

    weak var delegateManager: ObvNetworkFetchDelegateManager?

    private var _cacheInitialized = false
    private var _wellKnownCache: [URL: WellKnownJSON] = [:]
    private let wellKnownCacheQueue = DispatchQueue(label: "WellKnownCoordinatorQueueForWellKnownCacheQueue")
    
    private func setWellKnownJSON(_ wellKnown: WellKnownJSON, for serverURL: URL) {
        wellKnownCacheQueue.sync {
            _wellKnownCache[serverURL] = wellKnown
        }
    }
    
    private var cacheInitialized: Bool {
        get {
            var value = false
            wellKnownCacheQueue.sync {
                value = _cacheInitialized
            }
            return value
        }
        set {
            wellKnownCacheQueue.sync {
                _cacheInitialized = newValue
            }
        }
    }
    
    private func getWellKnownJSON(for serverURL: URL) -> WellKnownJSON? {
        var wellKnown: WellKnownJSON?
        wellKnownCacheQueue.sync {
            wellKnown = _wellKnownCache[serverURL]
        }
        return wellKnown
    }

}


// MARK: - WellKnownCacheDelegate

extension WellKnownCoordinator: WellKnownCacheDelegate {

    func updatedListOfOwnedIdentites(ownedIdentities: Set<ObvCryptoIdentity>, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            return
        }

        let op1 = DeleteObsoleteCachedWellKnownOperation(ownedIdentities: ownedIdentities, log: log, flowId: flowId, contextCreator: contextCreator)
        let op2 = WellKnownDownloadOperation(ownedIdentities: ownedIdentities, flowId: flowId, delegate: self)
        
        internalQueue.addOperations([op1, op2], waitUntilFinished: false)
        
    }
    
    
    func initializateCache(flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The Identity Delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        // Fill the cache with what we already have in database

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
            do {
                let cachedWellKnowns = try CachedWellKnown.getAllCachedWellKnown(within: obvContext)
                for cachedWellKnown in cachedWellKnowns {
                    if let wellKnown = try? WellKnownJSON.decode(cachedWellKnown.wellKnownData) {
                        setWellKnownJSON(wellKnown, for: cachedWellKnown.serverURL)
                    }
                }
            } catch {
                os_log("Could not get all cached well known: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
            }
        }

        cacheInitialized = true

        // Download updated versions of the well known
        
        var ownedIdentities = Set<ObvCryptoIdentity>()
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            guard let _ownedIdentities = try? identityDelegate.getOwnedIdentities(within: obvContext) else { assertionFailure(); return }
            ownedIdentities = _ownedIdentities
        }
        
        self.updatedListOfOwnedIdentites(ownedIdentities: ownedIdentities, flowId: flowId)

    }

    
    func getWebSocketURL(for server: URL, flowId: FlowIdentifier) -> Result<URL, WellKnownCacheError> {
        guard cacheInitialized else {
            return .failure(.cacheNotInitialized)
        }
        guard let wellKnown = getWellKnownJSON(for: server) else {
            let op = WellKnownDownloadOperation(servers: Set([server]), flowId: flowId, delegate: self)
            internalQueue.addOperations([op], waitUntilFinished: false)
            return .failure(.missingValue)
        }
        return .success(wellKnown.serverConfig.webSocketURL)
    }

    func getTurnURLs(for server: URL, flowId: FlowIdentifier) -> Result<[String], WellKnownCacheError> {
        guard cacheInitialized else {
            return .failure(.cacheNotInitialized)
        }
        guard let wellKnown = getWellKnownJSON(for: server) else {
            let op = WellKnownDownloadOperation(servers: Set([server]), flowId: flowId, delegate: self)
            internalQueue.addOperations([op], waitUntilFinished: false)
            return .failure(.missingValue)
        }
        return .success(wellKnown.serverConfig.turnServerURLs)
    }

    func queryServerWellKnown(serverURL: URL, flowId: FlowIdentifier) {
        let op = WellKnownDownloadOperation(servers: Set([serverURL]), flowId: flowId, delegate: self)
        internalQueue.addOperations([op], waitUntilFinished: false)
    }

}


// MARK: - WellKnownDownloadOperationDelegate

extension WellKnownCoordinator: WellKnownDownloadOperationDelegate {
    
    func wellKnownWasDownloaded(server: URL, flowId: FlowIdentifier, wellKnownData: Data) {

        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let log = OSLog(subsystem: delegateManager.logSubsystem, category: logCategory)

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        let op = UpdateCachedWellKnownOperation(newWellKnownData: wellKnownData, server: server, log: log, flowId: flowId, contextCreator: contextCreator, delegate: self)
        internalQueue.addOperations([op], waitUntilFinished: false)

    }

    
    func wellKnownWasDownloadFailed(server: URL, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        delegateManager.networkFetchFlowDelegate.failedToQueryServerWellKnown(serverURL: server, flowId: flowId)
        
    }

}


// MARK: - UpdateCachedWellKnownOperationDelegate

extension WellKnownCoordinator: UpdateCachedWellKnownOperationDelegate {
    
    
    func newWellKnownWasCached(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }
        
        setWellKnownJSON(newWellKnownJSON, for: server)

        delegateManager.networkFetchFlowDelegate.newWellKnownWasCached(server: server, newWellKnownJSON: newWellKnownJSON, flowId: flowId)
        
    }
    
    func cachedWellKnownWasUpdated(server: URL, newWellKnownJSON: WellKnownJSON, flowId: FlowIdentifier) {
        
        guard let delegateManager = delegateManager else {
            let log = OSLog(subsystem: ObvNetworkFetchDelegateManager.defaultLogSubsystem, category: logCategory)
            os_log("The Delegate Manager is not set", log: log, type: .fault)
            return
        }

        setWellKnownJSON(newWellKnownJSON, for: server)

        delegateManager.networkFetchFlowDelegate.cachedWellKnownWasUpdated(server: server, newWellKnownJSON: newWellKnownJSON, flowId: flowId)
        
    }

}
