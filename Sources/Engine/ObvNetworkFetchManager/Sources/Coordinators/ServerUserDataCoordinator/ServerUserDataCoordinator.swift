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
import os.log
import ObvTypes
import ObvCrypto
import ObvMetaManager
import ObvServerInterface
import ObvEncoder
import OlvidUtils

protocol ServerUserDataDelegate {
    func deleteOrRefreshServerUserData(flowId: FlowIdentifier) async throws
}

enum ServerUserDataTaskKind {
    case refresh
    case deleted
}

/// Minimal information  needed to create a ServerUserData operation
struct ServerUserDataInput: Hashable {
    let label: UID
    let ownedIdentity: ObvCryptoIdentity
    let kind: ServerUserDataTaskKind
}




actor ServerUserDataCoordinator {

    // MARK: - Instance variables

    private static let defaultLogSubsystem = ObvNetworkFetchDelegateManager.defaultLogSubsystem
    private static let logCategory = "ServerUserDataCoordinator"
    private static var log = OSLog(subsystem: defaultLogSubsystem, category: logCategory)
    private static var logger = Logger(subsystem: defaultLogSubsystem, category: logCategory)

    weak var delegateManager: ObvNetworkFetchDelegateManager?
    
    public static let errorDomain = "ServerUserDataCoordinator"

    private lazy var session: URLSession! = {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.useOlvidSettings(sharedContainerIdentifier: delegateManager?.sharedContainerIdentifier)
        return URLSession(configuration: sessionConfiguration, delegate: nil, delegateQueue: nil)
    }()
    
    private var cacheOfUserDataDeletionTasks = [ServerUserDataInput: UserDataDeletionOrRefreshTask]()
    private var cacheOfUserDataRefreshTasks = [ServerUserDataInput: UserDataDeletionOrRefreshTask]()
    private enum UserDataDeletionOrRefreshTask {
        case inProgress(task: Task<Void, any Error>)
    }
    
    private var failedAttemptsCounterManager = FailedAttemptsCounterManager()
    private var retryManager = FetchRetryManager()

    let downloadedUserData: URL
    private var notificationCenterTokens = [NSObjectProtocol]()

    init(downloadedUserData: URL, logPrefix: String) {
        let logSubsystem = "\(logPrefix).\(Self.defaultLogSubsystem)"
        Self.log = OSLog(subsystem: logSubsystem, category: Self.logCategory)
        self.downloadedUserData = downloadedUserData
    }
    
    
    func setDelegateManager(_ delegateManager: ObvNetworkFetchDelegateManager) {
        self.delegateManager = delegateManager
    }

    
    deinit {
        Task { [weak self] in
            await self?.unsubscribeFromNotifications()
        }
    }
    
    private func unsubscribeFromNotifications() {
        notificationCenterTokens.forEach { delegateManager?.notificationDelegate?.removeObserver($0) }
    }

    func finalizeInitialization(flowId: FlowIdentifier) async throws {

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.delegateManagerIsNil
        }

        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.notificationDelegateIsNil
        }
        
        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The Identity Delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.identityDelegateIsNil
        }

        notificationCenterTokens.append(ObvIdentityNotificationNew.observeServerLabelHasBeenDeleted(within: notificationDelegate) { [weak self] (ownedCryptoIdentity, label) in
            guard let self else { return }
            Task { [weak self] in
                guard let self else { return }
                let flowId = FlowIdentifier()
                let input = ServerUserDataInput(label: label, ownedIdentity: ownedCryptoIdentity, kind: .deleted)
                do {
                    // Make sure the owned identity still exists (i.e., that we are not processing a profile deletion request).
                    // If this is the case, we cannot request the deletion of the user data. It will be deleted soon from the server anyway.
                    if try await isIdentityOwned(ownedCryptoIdentity: ownedCryptoIdentity, flowId: flowId) {
                        try await deleteUserData(input, delegateManager: delegateManager, identityDelegate: identityDelegate, currentInvalidToken: nil, flowId: flowId)
                    }
                    await cleanupDownloadedUserDataDirectoryOfOrphanedFiles()
                } catch {
                    Self.logger.fault("Could not delete user data on notification that a server label was deleted within the identity manager: \(error.localizedDescription)")
                    assertionFailure()
                }
            }
        })
    }

}


// MARK: - ServerUserDataDelegate

extension ServerUserDataCoordinator: ServerUserDataDelegate {

    /// Called during bootstrap to delete obsolete user data from the server and to refresh user data if appropriate
    public func deleteOrRefreshServerUserData(flowId: FlowIdentifier) async throws {
        
        // Check all ServerUserData
        // Delete no longer useful ServerUserData, refresh those that need it

        guard let delegateManager else {
            os_log("The Delegate Manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.delegateManagerIsNil
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The Identity Delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.identityDelegateIsNil
        }

        // Check all ServerUserData
        // Delete no longer useful ServerUserData, refresh those that need it

        let userDatas = try await getAllServerDataToSynchronizeWithServer(delegateManager: delegateManager, flowId: flowId)

        for userData in userDatas.toDelete {
            do {
                let serverUserDataInput = ServerUserDataInput(label: userData.label, ownedIdentity: userData.ownedIdentity, kind: .deleted)
                try await deleteUserData(serverUserDataInput, delegateManager: delegateManager, identityDelegate: identityDelegate, currentInvalidToken: nil, flowId: flowId)
            } catch {
                os_log("Failed to delete user data", log: Self.log, type: .fault)
                assertionFailure(error.localizedDescription)
                // In production, continue anyway with the next item
            }
        }
        
        for userData in userDatas.toRefresh {
            do {
                let serverUserDataInput = ServerUserDataInput(label: userData.label, ownedIdentity: userData.ownedIdentity, kind: .refresh)
                try await refreshUserData(serverUserDataInput, delegateManager: delegateManager, identityDelegate: identityDelegate, currentInvalidToken: nil, flowId: flowId)
            } catch {
                Self.logger.fault("Failed to refresh user data: \(error.localizedDescription)")
                assertionFailure(error.localizedDescription)
                // In production, continue anyway with the next item
            }
        }


        // Cleanup downloaded user data dir of orphan files

        cleanupDownloadedUserDataDirectoryOfOrphanedFiles()

    }
    
}

// MARK: - Errors

extension ServerUserDataCoordinator {
    
    enum ObvError: Error {
        case delegateManagerIsNil
        case identityDelegateIsNil
        case contextCreatorIsNil
        case invalidServerResponse
        case couldNotParseReturnStatusFromServer
        case invalidToken(invalidToken: Data)
        case serverReturnedGeneralError
        case failedToCreatePendingServerQueryAlthoughUserDataToRefreshIsMissingOnServer
        case notificationDelegateIsNil
    }
    
}


// MARK: - Helpers

extension ServerUserDataCoordinator {
    
    private func isIdentityOwned(ownedCryptoIdentity: ObvCryptoIdentity, flowId: FlowIdentifier) async throws -> Bool {
        
        guard let delegateManager else { assertionFailure(); throw ObvError.delegateManagerIsNil }
        guard let contextCreator = delegateManager.contextCreator else { assertionFailure(); throw ObvError.contextCreatorIsNil }
        guard let identityDelegate = delegateManager.identityDelegate else { assertionFailure(); throw ObvError.identityDelegateIsNil }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, any Error>) in
            contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                do {
                    let isOwned = try identityDelegate.isOwned(ownedCryptoIdentity, within: obvContext)
                    return continuation.resume(returning: isOwned)
                } catch {
                    assertionFailure()
                    return continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    private func cleanupDownloadedUserDataDirectoryOfOrphanedFiles() {
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: self.downloadedUserData, includingPropertiesForKeys: nil, options: []) else {
            assertionFailure()
            return
        }
        
        for file in files {
            /// REMARK This file name is built in ObvServerGetUserDataMethod#parseObvServerResponse
            let components = file.lastPathComponent.components(separatedBy: ".")
            if components.count == 2 {
                if let expireTimestamp = Int(components.first!) {
                    let expirationDate = Date(timeIntervalSince1970: TimeInterval(expireTimestamp))
                    if expirationDate > Date() { continue }
                }
                /// filename is not well-formed, or the file is expired --> delete it
                try? FileManager.default.removeItem(at: file)
            }
        }
    }


    private func getAllServerDataToSynchronizeWithServer(delegateManager: ObvNetworkFetchDelegateManager, flowId: FlowIdentifier) async throws -> (toDelete: Set<UserData>, toRefresh: Set<UserData>) {
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator manager is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.contextCreatorIsNil
        }

        guard let identityDelegate = delegateManager.identityDelegate else {
            os_log("The Identity Delegate is not set", log: Self.log, type: .fault)
            assertionFailure()
            throw ObvError.identityDelegateIsNil
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(toDelete: Set<UserData>, toRefresh: Set<UserData>), Error>) in
            contextCreator.performBackgroundTaskAndWait(flowId: flowId) { obvContext in
                do {
                    let userDatas = try identityDelegate.getAllServerDataToSynchronizeWithServer(within: obvContext)
                    return continuation.resume(returning: userDatas)
                } catch {
                    return continuation.resume(throwing: error)
                }
            }
        }
        
    }
    
    
    private func createTaskForDeletingUserData(_ userData: ServerUserDataInput, serverSessionToken: Data, identityDelegate: ObvIdentityDelegate, flowId: FlowIdentifier) -> Task<Void,Error> {
        return Task {
            
            let method = ObvServerDeleteUserDataMethod(ownedIdentity: userData.ownedIdentity, token: serverSessionToken, serverLabel: userData.label, flowId: flowId)
            method.identityDelegate = identityDelegate
            
            let (data, response) = try await session.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ObvError.invalidServerResponse
            }

            guard let returnStatus = ObvServerDeleteUserDataMethod.parseObvServerResponse(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }
            
            switch returnStatus {

            case .ok:
                failedAttemptsCounterManager.reset(counter: .serverUserData(input: .init(label: userData.label, ownedIdentity: userData.ownedIdentity, kind: .deleted)))
                try await identityDelegate.deleteUserData(for: userData.ownedIdentity, with: userData.label, flowId: flowId)
                return
                
            case .invalidToken:
                failedAttemptsCounterManager.reset(counter: .serverUserData(input: .init(label: userData.label, ownedIdentity: userData.ownedIdentity, kind: .deleted)))
                throw ObvError.invalidToken(invalidToken: serverSessionToken)
                
            case .generalError:
                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.serverUserData(input: .init(label: userData.label, ownedIdentity: userData.ownedIdentity, kind: .deleted)))
                os_log("Will retry to delete user data in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
                await retryManager.waitForDelay(milliseconds: delay)
                throw ObvError.serverReturnedGeneralError
            }

        }
    }

    
    private func createTaskForRefreshingUserData(_ userData: ServerUserDataInput, serverSessionToken: Data, delegateManager: ObvNetworkFetchDelegateManager, identityDelegate: ObvIdentityDelegate, flowId: FlowIdentifier) -> Task<Void,Error> {
        return Task {
            
            let method = ObvServerRefreshUserDataMethod(ownedIdentity: userData.ownedIdentity, token: serverSessionToken, serverLabel: userData.label, flowId: flowId)
            method.identityDelegate = identityDelegate
            
            let (data, response) = try await session.data(for: method.getURLRequest())
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw ObvError.invalidServerResponse
            }

            guard let returnStatus = ObvServerRefreshUserDataMethod.parseObvServerResponse(responseData: data, using: Self.log) else {
                assertionFailure()
                throw ObvError.couldNotParseReturnStatusFromServer
            }
            
            switch returnStatus {

            case .ok:
                failedAttemptsCounterManager.reset(counter: .serverUserData(input: .init(label: userData.label, ownedIdentity: userData.ownedIdentity, kind: .refresh)))
                try await identityDelegate.updateUserDataNextRefreshTimestamp(for: userData.ownedIdentity, with: userData.label, flowId: flowId)
                return
                
            case .invalidToken:
                failedAttemptsCounterManager.reset(counter: .serverUserData(input: .init(label: userData.label, ownedIdentity: userData.ownedIdentity, kind: .refresh)))
                throw ObvError.invalidToken(invalidToken: serverSessionToken)
                
            case .generalError:
                let delay = failedAttemptsCounterManager.incrementAndGetDelay(.serverUserData(input: .init(label: userData.label, ownedIdentity: userData.ownedIdentity, kind: .refresh)))
                os_log("Will retry to refresh user data in %f seconds", log: Self.log, type: .error, Double(delay) / 1000.0)
                await retryManager.waitForDelay(milliseconds: delay)
                throw ObvError.serverReturnedGeneralError
                
            case .deletedFromServer:
                // The user data we are trying to refresh appears not to be on the server. We upload it back.
                let op1 = CreatePendingServerQueryOperation(ownedCryptoId: userData.ownedIdentity, label: userData.label, delegateManager: delegateManager, identityDelegate: identityDelegate)
                do {
                    try await delegateManager.queueAndAwaitCompositionOfOneContextualOperation(op1: op1, log: Self.log, flowId: flowId)
                } catch {
                    assertionFailure()
                    throw ObvError.failedToCreatePendingServerQueryAlthoughUserDataToRefreshIsMissingOnServer
                }
                try await delegateManager.serverQueryDelegate.processAllPendingServerQueries(for: userData.ownedIdentity, flowId: flowId)
            }

        }
    }

    
    private func deleteUserData(_ userData: ServerUserDataInput, delegateManager: ObvNetworkFetchDelegateManager, identityDelegate: ObvIdentityDelegate, currentInvalidToken: Data?, flowId: FlowIdentifier) async throws {
        
        let serverSessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: userData.ownedIdentity, currentInvalidToken: currentInvalidToken, flowId: flowId).serverSessionToken
        
        do {
            
            if let cached = cacheOfUserDataDeletionTasks[userData] {
                switch cached {
                case .inProgress(task: let task):
                    try await task.value
                }
            } else {
                let task = createTaskForDeletingUserData(userData, serverSessionToken: serverSessionToken, identityDelegate: identityDelegate, flowId: flowId)
                cacheOfUserDataDeletionTasks[userData] = .inProgress(task: task)
                do {
                    try await task.value
                    cacheOfUserDataDeletionTasks.removeValue(forKey: userData)
                } catch {
                    cacheOfUserDataDeletionTasks.removeValue(forKey: userData)
                    throw error
                }
            }
            
        } catch {
            
            if let error = error as? ObvError {
                switch error {
                case .invalidToken(let invalidToken):
                    return try await deleteUserData(userData, delegateManager: delegateManager, identityDelegate: identityDelegate, currentInvalidToken: invalidToken, flowId: flowId)
                case .serverReturnedGeneralError:
                    // We already waited for the appropriate delay within the task
                    return try await deleteUserData(userData, delegateManager: delegateManager, identityDelegate: identityDelegate, currentInvalidToken: nil, flowId: flowId)
                default:
                    assertionFailure()
                    throw error
                }
            } else {
                Self.logger.error("Failed to delete user data: \(error.localizedDescription)")
                assertionFailure()
                throw error
            }

        }
                
    }

    
    private func refreshUserData(_ userData: ServerUserDataInput, delegateManager: ObvNetworkFetchDelegateManager, identityDelegate: ObvIdentityDelegate, currentInvalidToken: Data?, flowId: FlowIdentifier) async throws {
        
        let serverSessionToken = try await delegateManager.serverSessionDelegate.getValidServerSessionToken(for: userData.ownedIdentity, currentInvalidToken: currentInvalidToken, flowId: flowId).serverSessionToken

        do {
            
            if let cached = cacheOfUserDataRefreshTasks[userData] {
                switch cached {
                case .inProgress(task: let task):
                    try await task.value
                }
            } else {
                let task = createTaskForRefreshingUserData(userData, serverSessionToken: serverSessionToken, delegateManager: delegateManager, identityDelegate: identityDelegate, flowId: flowId)
                cacheOfUserDataRefreshTasks[userData] = .inProgress(task: task)
                do {
                    try await task.value
                    cacheOfUserDataRefreshTasks.removeValue(forKey: userData)
                } catch {
                    cacheOfUserDataRefreshTasks.removeValue(forKey: userData)
                    throw error
                }
            }
            
        } catch {
            
            if let error = error as? ObvError {
                switch error {
                case .invalidToken(let invalidToken):
                    return try await refreshUserData(userData, delegateManager: delegateManager, identityDelegate: identityDelegate, currentInvalidToken: invalidToken, flowId: flowId)
                case .serverReturnedGeneralError:
                    // We already waited for the appropriate delay within the task
                    return try await refreshUserData(userData, delegateManager: delegateManager, identityDelegate: identityDelegate, currentInvalidToken: nil, flowId: flowId)
                default:
                    assertionFailure()
                    throw error
                }
            } else {
                assertionFailure()
                throw error
            }

        }

        
    }


}
