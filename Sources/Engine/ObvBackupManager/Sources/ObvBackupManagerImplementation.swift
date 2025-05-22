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
import ObvMetaManager
import ObvTypes
import ObvCrypto
import CoreData
import Compression
import OlvidUtils


/// This is the **LEGACY** implementation of backups. See `ObvBackupManagerNew` for the new implementation.
public final class ObvBackupManagerImplementation {
    
    public var logSubsystem: String { return delegateManager.logSubsystem }

    public func prependLogSubsystem(with prefix: String) {
        delegateManager.prependLogSubsystem(with: prefix)
    }
    
    lazy var log = OSLog(subsystem: logSubsystem, category: "ObvBackupManagerImplementation")
    private let prng: PRNGService
    
    /// Strong reference to the delegate manager, which keeps strong references to all external and internal delegate requirements.
    let delegateManager: ObvBackupDelegateManager

    private static let errorDomain = "ObvBackupManagerImplementation"
    
    private var notificationTokens = [NSObjectProtocol]()
    private let internalNotificationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .background
        return queue
    }()
    
    public private(set) var isBackupRequired = false
    
    fileprivate static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ObvBackupManagerImplementation.makeError(message: message) }

    private let internalSyncQueue = DispatchQueue(label: "ObvBackupManagerImplementation internal sync queue", attributes: .concurrent)

    private var _backupsBeingCurrentltyRestored = [FlowIdentifier: FullBackup]()

    private func addBackupBeingCurrentltyRestored(flowId: FlowIdentifier, fullbackup: FullBackup) {
        internalSyncQueue.async(flags: .barrier) { [weak self] in
            assert(self?._backupsBeingCurrentltyRestored[flowId] == nil)
            self?._backupsBeingCurrentltyRestored[flowId] = fullbackup
        }
    }
    private func getBackupBeingCurrentltyRestored(flowId: FlowIdentifier) -> FullBackup? {
        var fullbackup: FullBackup?
        internalSyncQueue.sync {
            fullbackup = _backupsBeingCurrentltyRestored[flowId]
        }
        return fullbackup
    }
    
    
    // MARK: Initialiser
    
    var backupableManagers = [Weak<AnyObject>]() // Array of weak references to the ObvBackupable's (one for the app, and potentially several for the engine's managers)

    /// We know the app backupable object is the only one that conforms to `ObvBackupable` but not to `ObvBackupableManager`.
    private var appBackupableObjectIsRegistered: Bool {
        !backupableManagers.filter({
            guard let backupObject = $0.value else { return false }
            return backupObject is ObvBackupable && !(backupObject is ObvBackupableManager)
        }).isEmpty
    }

    public init(prng: PRNGService) {
        self.delegateManager = ObvBackupDelegateManager()
        self.prng = prng
        
    }
    
}

// MARK: - ObvBackupDelegate

extension ObvBackupManagerImplementation: ObvLegacyBackupDelegate {
    
    public func registerAllBackupableManagers(_ allBackupableManagers: [ObvBackupableManager]) {
        let log = self.log
        os_log("Registering %{public}d backupable managers", log: log, type: .info, allBackupableManagers.count)
        assert(backupableManagers.isEmpty)
        backupableManagers = allBackupableManagers.map { Weak($0) }
    }
    
    
    public func registerAppBackupableObject(_ appBackupableObject: ObvBackupable) {
        os_log("Registering the app backupable object", log: log, type: .info)
        backupableManagers.append(Weak(appBackupableObject))
    }
    
    
    /// Creates a new `Backup` item in database, containing all the internal data to backup of the registered backupable objects.
    public func initiateBackup(forExport: Bool, backupRequestIdentifier: FlowIdentifier) async throws -> (backupKeyUid: UID, version: Int, encryptedContent: Data) {
        
        let log = self.log
        
        guard appBackupableObjectIsRegistered else {
            os_log("Cannot backup yet. The app backupable object is not registered yet.", log: log, type: .fault)
            throw Self.makeError(message: "Cannot backup yet. The app backupable object is not registered yet.")
        }
        
        guard let backupableObjects = self.backupableManagers.map({ $0.value }) as? [ObvBackupable] else {
            os_log("Critical error. Could not recover the managers to backup", log: log, type: .default)
            throw Self.makeError(message: "Critical error. Could not recover the managers to backup")
        }

        os_log("Initiating a backup for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)
        
        let allInternalDataForBackup = try await provideAllInternalDataForBackupFromBackupableObjects(backupableObjects, backupRequestIdentifier: backupRequestIdentifier)
        
        // If we reach this step, all the backupable objects provided their internal data to backup.
        
        guard allInternalDataForBackup.count == backupableObjects.count else {
            assertionFailure()
            throw Self.makeError(message: "Unexpected number of internal data for backup")
        }
                
        let fullBackup = try FullBackup(allInternalJsonAndIdentifier: allInternalDataForBackup)
                
        // Create the full backup
        
        let fullBackupData = try fullBackup.computeData(flowId: backupRequestIdentifier, log: log)
        
        os_log("The full backup is made of %d bytes within flow %{public}@", log: log, type: .info, fullBackupData.count, backupRequestIdentifier.description)
        
        return try await createPersistedBackup(forExport: forExport, backupRequestIdentifier: backupRequestIdentifier, fullBackupData: fullBackupData)
        
    }
    
    public func getBackupKeyInformation(flowId: FlowIdentifier) async throws -> BackupKeyInformation? {
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            throw ObvBackupManagerImplementation.makeError(message: "The context creator is not set")
        }

        var backupKeyInformation: BackupKeyInformation? = nil
        
        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            
            guard let backupKey = try getCurrentBackupKey(within: obvContext) else {
                return
            }
            
            backupKeyInformation = try backupKey.backupKeyInformation

        }
        
        return backupKeyInformation
        
    }

    
    public func markLegacyBackupAsExported(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) async throws {
        
        let log = self.log
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            throw ObvBackupManagerImplementation.makeError(message: "The context creator is not set")
        }

        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in

            guard let backupKey = try getCurrentBackupKey(within: obvContext) else {
                throw ObvBackupManagerImplementation.makeError(message: "Could not get current backup key")
            }
            
            guard backupKey.uid == backupKeyUid else {
                throw ObvBackupManagerImplementation.makeError(message: "Could not mark backup as exported")
            }
            guard let backup = try backupKey.getBackupWithVersion(backupVersion) else {
                throw ObvBackupManagerImplementation.makeError(message: "Unexpected number of backup candidates")
            }
            guard backup.forExport else {
                throw ObvBackupManagerImplementation.makeError(message: "Unexpected error: the forExport is expected to be true at this point")
            }
            try backup.setExported()
            try obvContext.save(logOnFailure: log)

        }
        
    }

    
    public func deleteAllAsUserMigratesToNewBackups(flowId: FlowIdentifier) async throws {
        
        let log = self.log
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            throw ObvBackupManagerImplementation.makeError(message: "The context creator is not set")
        }

        var iteration = 0
        let maxIterations = 10

        while iteration < maxIterations {
            
            iteration += 1
            
            do {
                
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                        do {
                            try BackupKey.deleteAll(within: obvContext) // Should cascade delete all Backups as well
                            try obvContext.save(logOnFailure: log)
                            return continuation.resume()
                        } catch {
                            assertionFailure()
                            return continuation.resume(throwing: error)
                        }
                    }
                }

                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    contextCreator.performBackgroundTask(flowId: flowId) { obvContext in
                        do {
                            try Backup.deleteAllBackups(within: obvContext.context)
                            try obvContext.save(logOnFailure: log)
                            return continuation.resume()
                        } catch {
                            assertionFailure()
                            return continuation.resume(throwing: error)
                        }
                    }
                }

                // If we reach this point, the deletion was successful
                
                return

            } catch {
                
                if iteration == maxIterations {
                    throw error
                } else {
                    try await Task.sleep(seconds: Double.random(in: 0..<1))
                }
                
            }
                        
        }
        
    }
    
    public func markLegacyBackupAsUploaded(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) async throws {
        
        let log = self.log
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            throw ObvBackupManagerImplementation.makeError(message: "The context creator is not set")
        }

        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in

            guard let backupKey = try getCurrentBackupKey(within: obvContext) else {
                throw ObvBackupManagerImplementation.makeError(message: "No current backup key")
            }
            guard backupKey.uid == backupKeyUid else {
                throw ObvBackupManagerImplementation.makeError(message: "Could not mark backup as uploaded")
            }
            guard let backup = try backupKey.getBackupWithVersion(backupVersion) else {
                throw ObvBackupManagerImplementation.makeError(message: "Unexpected number of backup candidates")
            }
            guard !backup.forExport else {
                throw ObvBackupManagerImplementation.makeError(message: "Unexpected error: the forExport is expected to be false at this point")
            }
            try backup.setUploaded()
            try obvContext.save(logOnFailure: log)

            self.isBackupRequired = false

        }
        
    }

    
    public func markLegacyBackupAsFailed(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) async throws {
        
        let log = self.log
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            throw ObvBackupManagerImplementation.makeError(message: "The context creator is not set")
        }

        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in

            guard let backupKey = try getCurrentBackupKey(within: obvContext) else {
                throw ObvBackupManagerImplementation.makeError(message: "No current backup key")
            }
            guard backupKey.uid == backupKeyUid else {
                throw ObvBackupManagerImplementation.makeError(message: "Could not mark backup as failed")
            }
            guard let backup = try backupKey.getBackupWithVersion(backupVersion) else {
                throw ObvBackupManagerImplementation.makeError(message: "Unexpected number of backup candidates")
            }
            try backup.setFailed()
            try obvContext.save(logOnFailure: log)

        }

    }
    
    /// This method allows to recover the backuped data. It does not restore the data though.
    /// If this method throws, the Error is a BackupRestoreError.
    public func recoverBackupData(_ backupData: Data, withBackupKey backupKey: String, backupRequestIdentifier: FlowIdentifier) async throws -> (backupRequestIdentifier: UUID, backupDate: Date) {

        // Compute the derived keys from the backup key
        
        os_log("Computing the derived keys from the backup key for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)

        guard let backupSeed = BackupSeed(backupKey) else {
            os_log("Could not compute backup seed for backup request identified by %{public}@", log: log, type: .fault)
            throw BackupRestoreError.internalError(code: 0)
        }

        let derivedKeysForBackup = backupSeed.deriveKeysForLegacyBackup()

        // We check the mac of encryptedBackupData

        os_log("Checking the mac of encrypted backup for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)

        let (computedMac, receivedMac, encryptedBackup) = try await computeMAC(derivedKeysForBackup: derivedKeysForBackup, backupData: backupData)

        guard computedMac == receivedMac else {
            os_log("The mac comparison failed during the recover of the backup for backup request identified by %{public}@", log: log, type: .error)
            throw BackupRestoreError.macComparisonFailed
        }

        os_log("The mac of the backup data is correct for backup request identified by %{public}@. Decrypting the data", log: log, type: .info, backupRequestIdentifier.description)

        // We decrypt the data
        
        guard let privateKey = derivedKeysForBackup.privateKeyForEncryption else {
            os_log("The private key for decryption is nil, which is unexpected", log: log, type: .fault)
            throw BackupRestoreError.internalError(code: 2)
        }
        // The full backup data obtained after decryption is either compressed (if it was created with an old version of Olvid) or not (better).
        guard let possiblyCompressedFullBackupData = PublicKeyEncryption.decrypt(EncryptedData(data: encryptedBackup), using: privateKey) else {
            os_log("We failed to decrypt the encrypted backup", log: log, type: .error)
            throw BackupRestoreError.backupDataDecryptionFailed
        }
        
        os_log("The backup data was successfully decrypted for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)

        let fullBackup: FullBackup
        do {
            fullBackup = try await FullBackup(possiblyCompressedFullBackupData: possiblyCompressedFullBackupData)
        } catch {
            throw BackupRestoreError.internalError(code: 3)
        }
        
        addBackupBeingCurrentltyRestored(flowId: backupRequestIdentifier, fullbackup: fullBackup)

        return (backupRequestIdentifier, fullBackup.backupDate)
        
    }
    
    
    private func computeMAC(derivedKeysForBackup: DerivedKeysForLegacyBackup, backupData: Data) async throws -> (computedMac: Data, receivedMac: Data, encryptedBackup: Data) {
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(computedMac: Data, receivedMac: Data, encryptedBackup: Data), Error>) in
            
            let macAlgoByteId = derivedKeysForBackup.macKey.algorithmImplementationByteId
            let macLength = MAC.outputLength(for: macAlgoByteId)
            guard backupData.count >= macLength else {
                os_log("The backup data is too small for backup request", log: log, type: .error)
                continuation.resume(throwing: BackupRestoreError.macComputationFailed)
                return
            }
            let receivedMac = backupData[backupData.endIndex-macLength..<backupData.endIndex]
            let encryptedBackup = backupData[backupData.startIndex..<backupData.endIndex-macLength]
            let computedMac: Data
            do {
                computedMac = try MAC.compute(forData: encryptedBackup, withKey: derivedKeysForBackup.macKey)
            } catch {
                continuation.resume(throwing: BackupRestoreError.macComputationFailed)
                return
            }
            continuation.resume(returning: (computedMac, receivedMac, encryptedBackup))
            
        }
        
    }

    
    public func restoreFullBackup(backupRequestIdentifier: FlowIdentifier) async throws {

        guard let fullBackup = getBackupBeingCurrentltyRestored(flowId: backupRequestIdentifier) else {
            assertionFailure()
            throw Self.makeError(message: "Full backup was not found and thus cannot be restored")
        }
        
        guard appBackupableObjectIsRegistered else {
            assertionFailure()
            throw Self.makeError(message: "Cannot restore backup yet. The app backupable object is not registered yet.")
        }

        guard let backupableObjects = self.backupableManagers.map({ $0.value }) as? [ObvBackupable] else {
            assertionFailure()
            throw Self.makeError(message: "Critical error. Could not recover the managers to backup")
        }
        
        // Get the engine managers and the (single) app object to restore
        
        let backupableManagerObjects = backupableObjects.filter({ $0 is ObvBackupableManager })
        let backupableAppObjects = backupableObjects.filter({ !($0 is ObvBackupableManager) })
        guard backupableAppObjects.count == 1 else {
            throw Self.makeError(message: "Expecting exactly one backupable app object, got \(backupableAppObjects.count)")
        }
        let backupableAppObject = backupableAppObjects.first!
        
        // Restore the engine managers first

        try await restoreBackupableManagerObjects(backupableManagerObjects: backupableManagerObjects, fullBackup: fullBackup, backupRequestIdentifier: backupRequestIdentifier)
        
        // Restore the app object (the internalJson may be nil for very old backups, made at a time when the app did not provide backup data).
        
        let internalJson = fullBackup.allInternalJsonAndIdentifier[backupableAppObject.backupSource]?[backupableAppObject.backupIdentifier]
        try await backupableAppObject.restoreLegacyBackup(backupRequestIdentifier: backupRequestIdentifier, internalJson: internalJson)
        
        // If we reach this point, the full backup was restored

        await fullBackupRestored(backupRequestIdentifier: backupRequestIdentifier)
        
    }
    
    
    private func fullBackupRestored(backupRequestIdentifier: FlowIdentifier) async {

        // 2025-02-21: We used to store in database the key used to restore the backup. We don't do this anymore as we want to migrate to new backups
        
    }
    
    
    public func userJustActivatedAutomaticBackup() {
        isBackupRequired = true
    }
    
}


// MARK: - Helpers

extension ObvBackupManagerImplementation {
    
    
    private func createPersistedBackup(forExport: Bool, backupRequestIdentifier: FlowIdentifier, fullBackupData: Data) async throws -> (backupKeyUid: UID, version: Int, encryptedContent: Data) {
        
        assert(!Thread.isMainThread)
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(backupKeyUid: UID, version: Int, encryptedContent: Data), Error>) in
            
            do {
                try delegateManager.contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: backupRequestIdentifier) { (obvContext) in

                    guard let currentBackupKey = try getCurrentBackupKey(within: obvContext) else {
                        throw ObvBackupManagerImplementation.makeError(message: "No backup key available")
                    }

                    os_log("An appropriate backup key was found for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)

                    let backup = try Backup.createOngoingBackup(forExport: forExport, backupKey: currentBackupKey)
                    
                    os_log("The new ongoing backup for backup request identified by %{public}@ has version %d", log: log, type: .info, backupRequestIdentifier.description, backup.version)
                    
                    // Get the backup item from database in order to recover the current crypto keys
                    
                    guard let derivedKeysForBackup = backup.backupKey?.derivedKeysForBackup else {
                        os_log("Could not find any backup key for ongoing backup", log: log, type: .fault)
                        throw Self.makeError(message: "Could not find any backup key for ongoing backup")
                    }
                    
                    // At this point we have a backup and the appropriate keys. We can encrypt the backup.

                    os_log("Encrypting the full backup for backupRequestIdentifier %{public}@", log: log, type: .info, backupRequestIdentifier.description)
                    
                    guard let encryptedBackup = PublicKeyEncryption.encrypt(fullBackupData, using: derivedKeysForBackup.publicKeyForEncryption, and: prng) else {
                        assertionFailure()
                        throw Self.makeError(message: "Failed to encrypt full backup data")
                    }
                    let macOfEncryptedBackup = try MAC.compute(forData: encryptedBackup, withKey: derivedKeysForBackup.macKey)
                    let authenticatedEncryptedBackup = EncryptedData(data: encryptedBackup.raw + macOfEncryptedBackup)
                    
                    os_log("The encrypted backup was computed (size is %d bytes) for backupRequestIdentifier %{public}@", log: log, type: .info, authenticatedEncryptedBackup.count, backupRequestIdentifier.description)

                    try backup.setReady(withEncryptedContent: authenticatedEncryptedBackup)
                    try obvContext.save(logOnFailure: log)
                   
                    os_log("The encrypted backup was saved to DB for backupRequestIdentifier %{public}@", log: log, type: .info, backupRequestIdentifier.description)

                    guard let successfulBackupInfos = backup.successfulBackupInfos else {
                        assertionFailure()
                        throw Self.makeError(message: "Unexpected error: No successfulBackupInfos although the backup was saved to DB")
                    }

                    continuation.resume(returning: (successfulBackupInfos.backupKeyUid, successfulBackupInfos.version, successfulBackupInfos.encryptedContentRaw))
                    
                }
            } catch {
                continuation.resume(throwing: error)
            }
            
        }

    }
    
    
    /// This internal method restores the engine managers
    private func restoreBackupableManagerObjects(backupableManagerObjects: [ObvBackupable], fullBackup: FullBackup, backupRequestIdentifier: FlowIdentifier) async throws {

        try await withThrowingTaskGroup(of: Void.self) { group in
            for backupableManagerObject in backupableManagerObjects {
                group.addTask {
                    guard let internalJson = fullBackup.allInternalJsonAndIdentifier[backupableManagerObject.backupSource]?[backupableManagerObject.backupIdentifier] else {
                        throw Self.makeError(message: "Could not recover the internal backup of one of the managers (identified by key \(backupableManagerObject.backupIdentifier)")
                    }
                    try await backupableManagerObject.restoreLegacyBackup(backupRequestIdentifier: backupRequestIdentifier, internalJson: internalJson)
                }
                guard !group.isCancelled else {
                    throw Self.makeError(message: "Failed to restore a backup")
                }
                try await group.waitForAll()
            }
        }
        
    }
    
    
    private func provideAllInternalDataForBackupFromBackupableObjects(_ backupableObjects: [ObvBackupable], backupRequestIdentifier: FlowIdentifier) async throws -> [ObvBackupableObjectSource: [String: String]] {
        
        var internalJsonsAndIdentifiers = [ObvBackupableObjectSource: [String: String]]()
        
        try await withThrowingTaskGroup(of: (internalJson: String, internalJsonIdentifier: String, source: ObvBackupableObjectSource).self) { group in
            for backupableManager in backupableObjects {
                group.addTask {
                    return try await backupableManager.provideInternalDataForLegacyBackup(backupRequestIdentifier: backupRequestIdentifier)
                }
            }
            for try await internalDataForBackup in group {
                internalJsonsAndIdentifiers[internalDataForBackup.source] = [internalDataForBackup.internalJsonIdentifier: internalDataForBackup.internalJson]
            }
        }
        
        return internalJsonsAndIdentifiers
    }
    
    
    private func getCurrentBackupKey(within obvContext: ObvContext) throws -> BackupKey? {
        let flowId = obvContext.flowId
        let backupKeys: Set<BackupKey>
        do {
            backupKeys = try BackupKey.getAll(within: obvContext)
        } catch let error {
            os_log("Could not get existing backup keys with flow %{public}@: %{public}@", log: log, type: .fault, flowId.debugDescription, error.localizedDescription)
            throw error
        }
        
        if backupKeys.isEmpty {
            return nil
        }
        
        guard backupKeys.count == 1 else {
            os_log("Expecting exactly 1 existing backup key, found %d", log: log, type: .error, backupKeys.count)
            throw ObvBackupManagerImplementation.makeError(message: "Unexpected number of backup keys")
        }
        return backupKeys.first!
    }
    
}


// MARK: - ObvManager

extension ObvBackupManagerImplementation {
    
    public func fulfill(requiredDelegate delegate: AnyObject, forDelegateType delegateType: ObvEngineDelegateType) throws {
        switch delegateType {
        case .ObvCreateContextDelegate:
            guard let delegate = delegate as? ObvCreateContextDelegate else { throw Self.makeError(message: "The ObvCreateContextDelegate is nil") }
            delegateManager.contextCreator = delegate
        case .ObvNotificationDelegate:
            guard let delegate = delegate as? ObvNotificationDelegate else { throw Self.makeError(message: "The ObvNotificationDelegate is nil") }
            delegateManager.notificationDelegate = delegate
        default:
            throw Self.makeError(message: "Unexpected delegate type")
        }
    }
    
    public var requiredDelegates: [ObvEngineDelegateType] {
        return [ObvEngineDelegateType.ObvCreateContextDelegate,
                ObvEngineDelegateType.ObvNotificationDelegate]
    }


    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {

        // Observe `observeBackupableManagerDatabaseContentChanged` notifications for automatic backups
        notificationTokens.append(contentsOf: [
            ObvBackupNotification.observeBackupableManagerDatabaseContentChanged(within: delegateManager.notificationDelegate, queue: internalNotificationQueue) { [weak self] (flowId) in
                self?.isBackupRequired = true
            }
        ])
        
    }
    
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {
        if forTheFirstTime {
            evaluateIfBackupIsRequired(flowId: flowId)
            deleteObsoleteBackups(flowId: flowId)
        }
    }

    
    private func evaluateIfBackupIsRequired(flowId: FlowIdentifier) {
        
        let log = self.log
        let delegateManager = self.delegateManager
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }
        
        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            // If the time elapsed since the last successfull backup is too big, backup is required
            
            let currentBackupKey: BackupKey
            do {
                guard let _currentBackupKey = try BackupKey.getCurrent(within: obvContext) else { return }
                currentBackupKey = _currentBackupKey
            } catch let error {
                os_log("Could not get current backup key: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            let lastExportedOrUploadedBackupDate: Date
            do {
                lastExportedOrUploadedBackupDate = try currentBackupKey.backupKeyInformation.lastBackupUploadTimestamp ?? Date.distantPast
            } catch {
                os_log("Could not get the last exported or uploaded backup date: %{public}@", log: log, type: .fault, error.localizedDescription)
                return
            }
            // If reach this point, we know some backup has been uploaded or exported in the past. We check whether this was not too long ago.
            guard -lastExportedOrUploadedBackupDate.timeIntervalSinceNow < ObvConstants.maxTimeUntilBackupIsRequired else {
                os_log("Last uploaded or exported backup was performed too long ago. We set isBackupRequired to true.", log: log, type: .info)
                self.isBackupRequired = true
                return
            }
            
            // If the latest backup has failed (or no automatic backup was performed with the current key), backup is required
            
            guard let lastBackup = try? currentBackupKey.lastBackup else {
                os_log("The current key was never used to upload a backup. Setting isBackupRequired to true.", log: log, type: .info)
                self.isBackupRequired = true
                return
            }
            
            guard lastBackup.status != .failed else {
                os_log("Last automatic backup failed. Setting isBackupRequired to true.", log: log, type: .info)
                self.isBackupRequired = true
                return
            }
            
            os_log("No need to set isBackupRequired to true.", log: log, type: .info)

        }
    }

    private func deleteObsoleteBackups(flowId: FlowIdentifier) {
        let log = self.log
        let delegateManager = self.delegateManager

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            do {
                let backupKeys = try BackupKey.getAll(within: obvContext)
                for backupKey in backupKeys {
                    try backupKey.deleteObsoleteBackups(log: log)
                }
            } catch let error {
                assertionFailure()
                os_log("Could not clean previous backups: %{public}@", log: log, type: .fault, error.localizedDescription)
                return

            }
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save context after cleaning previous backups within flow %{public}@: %{public}@", log: log, type: .fault, obvContext.flowId.debugDescription, error.localizedDescription)
                return
            }
        }
    }
    
}


// MARK: - FullBackup

fileprivate struct FullBackup: Codable {
    
    private let appBackup: String?
    private let engineManagerBackups: [String: String]
    let backupTimestamp: Int /// In milliseconds
    let jsonVersion: Int
    
    var backupDate: Date {
        return Date(timeIntervalSince1970: Double(backupTimestamp / 1000))
    }
    
    enum CodingKeys: String, CodingKey {
        case appBackup = "app"
        case engineManagerBackups = "engine"
        case backupTimestamp = "backup_timestamp"
        case jsonVersion = "backup_json_version"
    }
    
    func debugPrintEngineManagerBackups() {
        for (key, value) in engineManagerBackups {
            debugPrint("📀 \(key) back data:")
            if let jsonObject = try? JSONSerialization.jsonObject(with: value.data(using: .utf8)!),
               let prettyPrintedData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]),
               let prettyPrintedString =  NSString(data: prettyPrintedData, encoding: String.Encoding.utf8.rawValue) {
                print(prettyPrintedString)
            } else {
                debugPrint("📀 Could not log data")
            }
        }
    }
    
    init(allInternalJsonAndIdentifier: [ObvBackupableObjectSource: [String: String]]) throws {
        self.backupTimestamp = Int(Date().timeIntervalSince1970 * 1000)
        var appBackup: String?
        var engineManagerBackups = [String: String]()
        for source in ObvBackupableObjectSource.allCases {
            switch source {
            case .app:
                assert(appBackup == nil)
                if let internalJsonAndIdentifier = allInternalJsonAndIdentifier[source] {
                    // We expect exactly one key/value item for the app
                    guard internalJsonAndIdentifier.keys.count == 1 else {
                        assertionFailure()
                        throw ObvBackupManagerImplementation.makeError(message: "Expecting at most one json for the app")
                    }
                    appBackup = internalJsonAndIdentifier.values.first!
                } else {
                    appBackup = nil
                }
            case .engine:
                guard let engineInternalJsonAndIdentifiers = allInternalJsonAndIdentifier[source] else {
                    assertionFailure()
                    throw ObvBackupManagerImplementation.makeError(message: "Did not receive backup data from engine")
                }
                engineManagerBackups = engineInternalJsonAndIdentifiers
            }
        }
        self.appBackup = appBackup
        self.engineManagerBackups = engineManagerBackups
        self.jsonVersion = 0
    }
    
    
    init(possiblyCompressedFullBackupData: Data) async throws {
        let jsonEncoder = JSONDecoder()
        do {
            // We first assume that the data is not compressed
            self = try jsonEncoder.decode(FullBackup.self, from: possiblyCompressedFullBackupData)
        } catch {
            // We could not parse the data, it may have been created with an old version of Olvid that used to compress backups
            let fullBackupData = try await Self.decompressCompressedBackupContent(possiblyCompressedFullBackupData)
            self = try jsonEncoder.decode(FullBackup.self, from: fullBackupData)
        }
    }


    var allInternalJsonAndIdentifier: [ObvBackupableObjectSource: [String: String]] {
        var result = [ObvBackupableObjectSource: [String: String]]()
        if let appBackup = appBackup {
            result[.app] = [ "app": appBackup ] // Yes, this is ugly. But the "app" key is ignored
        }
        result[.engine] = engineManagerBackups
        return result
    }
 
    func computeData(flowId: FlowIdentifier, log: OSLog) throws -> Data {
        
        // Create the full backup content
        
        os_log("Creating full backup content within flow %{public}@", log: log, type: .info, flowId.description)
        
        let jsonEncoder = JSONEncoder()
        let fullBackupData = try jsonEncoder.encode(self)

        return fullBackupData
        
    }
    
    
    private static func decompressCompressedBackupContent(_ compressedFullBackupData: Data) async throws -> Data {
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            var decodedCapacity = compressedFullBackupData.count * 8
            let algorithm = COMPRESSION_ZLIB
            // Allow a capacity of about 100MB
            while decodedCapacity < 100_000_000 {

                var success = false

                let fullBackupContent = compressedFullBackupData.withUnsafeBytes { (encodedSourceBuffer: UnsafeRawBufferPointer) -> Data in
                    guard let encodedSourcePtr = encodedSourceBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                        fatalError("Cannot point to data.")
                    }
                    let decodedDestinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: decodedCapacity)
                    defer { decodedDestinationBuffer.deallocate() }
                    let decodedCharCount = compression_decode_buffer(decodedDestinationBuffer,
                                                                     decodedCapacity,
                                                                     encodedSourcePtr,
                                                                     compressedFullBackupData.count,
                                                                     nil,
                                                                     algorithm)
                    if decodedCharCount == 0 || decodedCharCount == decodedCapacity {
                        success = false
                        return Data()
                    } else {
                        success = true
                        return Data(bytes: decodedDestinationBuffer, count: decodedCharCount)
                    }
                }
                
                if success {
                    continuation.resume(returning: fullBackupContent)
                    return
                } else {
                    decodedCapacity *= 2
                }
            }

            // If we reach this point, something went wrong
            continuation.resume(throwing: ObvBackupManagerImplementation.makeError(message: "Could not decompress buffer"))
        }
                
    }

}
