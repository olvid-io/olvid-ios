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
import ObvTypes
import LinkPresentation
import OlvidUtils
import ObvEngine


final class BootstrapCoordinator {
    
    private let obvEngine: ObvEngine
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BootstrapCoordinator.self))
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BootstrapCoordinator.self))
    private var observationTokens = [NSObjectProtocol]()
    private let internalQueue: OperationQueue

    private static let errorDomain = "BootstrapCoordinator"
    private func makeError(message: String) -> Error { NSError(domain: BootstrapCoordinator.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    private var bootstrapOnIsInitializedAndActiveWasPerformed = false
    private let userDefaults = UserDefaults(suiteName: ObvMessengerConstants.appGroupIdentifier)

    init(obvEngine: ObvEngine, operationQueue: OperationQueue) {
        self.obvEngine = obvEngine
        self.internalQueue = operationQueue
        listenToNotifications()
    }

    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        // Bootstrap now
        syncPersistedContactDevicesWithEngineObliviousChannelsOnOwnedIdentityChangedNotifications()
        if let userDefaults = self.userDefaults {
            userDefaults.resetObjectsModifiedByShareExtension()
        }
        pruneObsoletePersistedInvitations()
        removeOldCachedURLMetadata()
        resyncPersistedInvitationsWithEngine()
        sendUnsentDrafts()
        if ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled {
            AppBackupManager.cleanPreviousICloudBackupsThenLogResult(currentCount: 0, cleanAllDevices: false)
        }
        deleteOldPendingRepliedTo()
        resetOwnObvCapabilities()
        autoAcceptPendingGroupInvitesIfPossible()
        if forTheFirstTime {
            processRequestSyncAppDatabasesWithEngine(completion: { _ in })
            deleteOrphanedPersistedAttachmentSentRecipientInfosOperation()
        }
    }

    
    private func listenToNotifications() {
        
        // Internal Notifications

        observationTokens.append(contentsOf: [
            ObvMessengerCoreDataNotification.observePersistedContactWasInserted() { [weak self] (objectID, contactCryptoId) in
                self?.processPersistedContactWasInsertedNotification(objectID: objectID, contactCryptoId: contactCryptoId)
            },
            ObvMessengerInternalNotification.observeRequestSyncAppDatabasesWithEngine() { [weak self] completion in
                self?.processRequestSyncAppDatabasesWithEngine(completion: completion)
            },
        ])
        
    }
    
}



extension BootstrapCoordinator {
    
    private func deleteOrphanedPersistedAttachmentSentRecipientInfosOperation() {
        assert(!Thread.isMainThread)
        let op1 = DeleteOrphanedPersistedAttachmentSentRecipientInfosOperation()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        composedOp.queuePriority = .veryLow
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }
    
    
    private func pruneObsoletePersistedInvitations() {
        assert(!Thread.isMainThread)
        let op1 = DeletePersistedInvitationTheCannotBeParsedAnymoreOperation()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }
    
    
    /// If there exist some group invitations that are pending, but that should be automatically accepted based on the current app settings, we accept them during bootstraping.
    private func autoAcceptPendingGroupInvitesIfPossible() {
        assert(!Thread.isMainThread)
        let op1 = AutoAcceptPendingGroupInvitesIfPossibleOperation(obvEngine: obvEngine)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }
    
    
    private func deleteOldPendingRepliedTo() {
        assert(!Thread.isMainThread)
        let op1 = DeleteOldPendingRepliedToOperation()
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
        internalQueue.addOperations([composedOp], waitUntilFinished: true)
        composedOp.logReasonIfCancelled(log: log)
    }

    private func removeOldCachedURLMetadata() {
        let dateLimit = Date().addingTimeInterval(TimeInterval(integerLiteral: -ObvMessengerConstants.TTL.cachedURLMetadata))
        LPMetadataProvider.removeCachedURLMetadata(olderThan: dateLimit)
    }
    

    private func resyncPersistedInvitationsWithEngine() {
        assert(OperationQueue.current != internalQueue)
        Task(priority: .utility) {
            do {
                let obvDialogsFromEngine = try await obvEngine.getAllDialogsWithinEngine()
                let op1 = SyncPersistedInvitationsWithEngineOperation(obvDialogsFromEngine: obvDialogsFromEngine, obvEngine: obvEngine)
                let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
                composedOp.completionBlock = { composedOp.logReasonIfCancelled(log: Self.log) }
                internalQueue.addOperation(composedOp)
            } catch {
                os_log("Could not get all the dialog from engine: %{public}@", log: log, type: .fault, error.localizedDescription)
            }
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
                guard let contactIdentities = try? PersistedObvContactIdentity.getAllContactOfOwnedIdentity(with: newOwnedCryptoId, whereOneToOneStatusIs: .any, within: context) else { return }
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
        let op4 = SyncPersistedContactGroupsV2WithEngineOperation(obvEngine: obvEngine)
        let composedOp = CompositionOfFourContextualOperations(op1: op1, op2: op2, op3: op3, op4: op4, contextCreator: ObvStack.shared, log: log, flowId: FlowIdentifier())
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
    
    
    private func resetOwnObvCapabilities() {
        do {
            try obvEngine.setCapabilitiesOfCurrentDeviceForAllOwnedIdentities(ObvMessengerConstants.supportedObvCapabilities)
        } catch {
            assertionFailure("Could not set capabilities")
        }
    }

}
