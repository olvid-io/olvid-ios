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
import ObvEngine
import LinkPresentation
import OlvidUtils


final class BootstrapCoordinator {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BootstrapCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    private let internalQueue: OperationQueue

    private static let errorDomain = "BootstrapCoordinator"
    private func makeError(message: String) -> Error { NSError(domain: BootstrapCoordinator.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    init(obvEngine: ObvEngine, operationQueue: OperationQueue) {
        self.obvEngine = obvEngine
        self.internalQueue = operationQueue
        listenToNotifications()
        
        // Bootstrap now
        
        syncPersistedContactDevicesWithEngineObliviousChannelsOnOwnedIdentityChangedNotifications()
        AppStateManager.shared.addCompletionHandlerToExecuteWhenInitializedAndActive { [weak self] in
            DispatchQueue(label: "Queue for syncing engine database to app").async {
                self?.processRequestSyncAppDatabasesWithEngine(completion: { _ in })
            }
        }
    }

    
    private func listenToNotifications() {
        
        // Internal Notifications

        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeAppStateChanged() { [weak self] (previousState, currentState) in
                self?.processAppStateChanged(previousState: previousState, currentState: currentState)
            },
            ObvMessengerInternalNotification.observePersistedContactWasInserted() { [weak self] (objectID, contactCryptoId) in
                self?.processPersistedContactWasInsertedNotification(objectID: objectID, contactCryptoId: contactCryptoId)
            },
            ObvMessengerInternalNotification.observeRequestSyncAppDatabasesWithEngine() { [weak self] completion in
                self?.processRequestSyncAppDatabasesWithEngine(completion: completion)
            },
        ])
        
    }
    
}



extension BootstrapCoordinator {
    
    
    private func processAppStateChanged(previousState: AppState, currentState: AppState) {
        if !previousState.isInitializedAndActive && currentState.isInitializedAndActive {
            if #available(iOS 13, *) {
                removeOldCachedURLMetadata()
            }
            resendPreviousObvEngineNewUserDialogToPresentNotifications()
            sendUnsentDrafts()
            if ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled {
                AppBackupCoordinator.cleanPreviousICloudBackupsThenLogResult(currentCount: 0, cleanAllDevices: false)
            }
        }
    }
    
    
    
    @available(iOS 13.0, *)
    private func removeOldCachedURLMetadata() {
        let dateLimit = Date().addingTimeInterval(TimeInterval(integerLiteral: -ObvMessengerConstants.TTL.cachedURLMetadata))
        LPMetadataProvider.removeCachedURLMetadata(olderThan: dateLimit)
    }
    

    private func resendPreviousObvEngineNewUserDialogToPresentNotifications() {
        do {
            try obvEngine.resendDialogs()
        } catch {
            os_log("Could not resend dialog notifications", log: log, type: .fault)
        }
    }

    
    private func sendUnsentDrafts() {
        ObvStack.shared.performBackgroundTask { [weak self] context in

            guard let _self = self else { return }
            
            let unsentDrafts: [PersistedDraft]
            do {
                let _unsentDrafts = try PersistedDraft.getAllUnsent(within: context)
                unsentDrafts = _unsentDrafts
            } catch {
                os_log("Failed to query the Draft DB", log: _self.log, type: .fault)
                return
            }
            
            if !unsentDrafts.isEmpty {
                os_log("There is/are %d unsent drafts to send", log: _self.log, type: .debug, unsentDrafts.count)
                unsentDrafts.forEach { $0.forceResend() }
            }
        }
    }

    

    
    private func syncPersistedContactDevicesWithEngineObliviousChannelsOnOwnedIdentityChangedNotifications() {
        let log = self.log
        let token = ObvMessengerInternalNotification.observeCurrentOwnedCryptoIdChanged(queue: internalQueue) { [weak self] (newOwnedCryptoId, apiKey) in
            ObvStack.shared.performBackgroundTaskAndWait { [weak self] (context) in
                context.name = "Context created in MetaFlowController within syncContactDevices"
                guard let _self = self else { return }
                guard let contactIdentities = try? PersistedObvContactIdentity.getAllContactOfOwnedIdentity(with: newOwnedCryptoId, within: context) else { return }
                for contact in contactIdentities {
                    guard let ownedIdentity = contact.ownedIdentity else {
                        os_log("Could not find owned identity. This is ok if it was just deleted.", log: log, type: .error)
                        continue
                    }
                    guard let obvContactDevices = try? _self.obvEngine.getAllObliviousChannelsEstablishedWithContactIdentity(with: contact.cryptoId, ofOwnedIdentyWith: ownedIdentity.cryptoId) else { continue }
                    do {
                        try contact.set(obvContactDevices)
                        try context.save(logOnFailure: _self.log)
                    } catch {
                        os_log("Could not sync contact devices with engine's oblivious channels", log: _self.log, type: .fault)
                        continue
                    }
                }
                
            }
        }
        observationTokens.append(token)
        
    }
    
    
    private func processRequestSyncAppDatabasesWithEngine(completion: (Result<Void,Error>) -> Void) {
        assert(!Thread.isMainThread)
        let op1 = SyncPersistedObvOwnedIdentitiesWithEngineOperation(obvEngine: obvEngine)
        let op2 = SyncPersistedObvContactIdentitiesWithEngineOperation(obvEngine: obvEngine)
        let op3 = SyncPersistedContactGroupsWithEngineOperation(obvEngine: obvEngine)
        let composedOp = CompositionOfThreeContextualOperations(op1: op1, op2: op2, op3: op3, contextCreator: ObvStack.shared, flowId: FlowIdentifier(), log: log)
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
        if composedOp.isCancelled {
            let reasonForCancel = composedOp.reasonForCancel ?? makeError(message: "Request sync of app database with engine did fail without specifying a proper reason. This is a bug")
            assertionFailure()
            completion(.failure(reasonForCancel))
        } else {
            completion(.success(()))
        }
    }

    
    private func processPersistedContactWasInsertedNotification(objectID: NSManagedObjectID, contactCryptoId: ObvCryptoId) {
        /* When receiving a PersistedContactWasInsertedNotification, we re-sync the groups from the engine. This is required when the following situation occurs :
         * Bob creates a group with Alice and Charlie, who do not know each other. Alice receives a new list of group members including Charlie *before* she includes
         * Charlie in her contacts. In that case, Charlie stays in the list of pending members. Here, we re-sync the groups members, making sure Charlie appears in
         * the list of group members.
         */
        let op1 = SyncPersistedContactGroupsWithEngineOperation(obvEngine: obvEngine)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

}
