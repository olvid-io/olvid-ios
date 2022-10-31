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
    private func removeBackupBeingCurrentltyRestored(flowId: FlowIdentifier) {
        internalSyncQueue.async(flags: .barrier) { [weak self] in
            assert(self?._backupsBeingCurrentltyRestored[flowId] != nil)
            self?._backupsBeingCurrentltyRestored.removeValue(forKey: flowId)
        }
    }
    
    
    /// The stored derived keys only include public keys. This array allows to store the derived keys when a backup is successfully recovered,
    /// so as to use these keys again for future backups.
    private var _derivedKeysForBackupBeingCurrentlyRestored = [FlowIdentifier: DerivedKeysForBackup]()
    private func addDerivedKeysForBackupBeingCurrentlyRestored(flowId: FlowIdentifier, derivedKeys: DerivedKeysForBackup) {
        internalSyncQueue.async(flags: .barrier) { [weak self] in
            assert(self?._derivedKeysForBackupBeingCurrentlyRestored[flowId] == nil)
            self?._derivedKeysForBackupBeingCurrentlyRestored[flowId] = derivedKeys
        }
    }
    private func getDerivedKeysForBackupBeingCurrentlyRestored(flowId: FlowIdentifier) -> DerivedKeysForBackup? {
        var derivedKeys: DerivedKeysForBackup?
        internalSyncQueue.sync {
            derivedKeys = _derivedKeysForBackupBeingCurrentlyRestored[flowId]
        }
        return derivedKeys
    }
    private func removeDerivedKeysForBackupBeingCurrentlyRestored(flowId: FlowIdentifier) {
        internalSyncQueue.async(flags: .barrier) { [weak self] in
            assert(self?._derivedKeysForBackupBeingCurrentlyRestored[flowId] != nil)
            self?._derivedKeysForBackupBeingCurrentlyRestored.removeValue(forKey: flowId)
        }
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

extension ObvBackupManagerImplementation: ObvBackupDelegate {
    
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
    
    
    public func generateNewBackupKey(flowId: FlowIdentifier) {
        
        let log = self.log
        let newBackupSeed = prng.genBackupSeed()
        let derivedKeysForBackup = newBackupSeed.deriveKeysForBackup()

        let delegateManager = self.delegateManager
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            return
        }
        
        delegateManager.contextCreator.performBackgroundTask(flowId: flowId) { [weak self] (obvContext) in
            
            do {
                try BackupKey.deleteAll(delegateManager: delegateManager, within: obvContext)
            } catch let error {
                os_log("Could not delete all previous backup keys within flow %{public}@: %{public}@", log: log, type: .fault, obvContext.flowId.debugDescription, error.localizedDescription)
                ObvBackupNotification.backupSeedGenerationFailed(flowId: flowId)
                    .postOnBackgroundQueue(within: notificationDelegate)
                return
            }
            
            let backupKey = BackupKey(derivedKeysForBackup: derivedKeysForBackup, delegateManager: delegateManager, within: obvContext)
            let backupKeyInformation = backupKey.backupKeyInformation
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not delete previous backup keys nor create new backup key within flow %{public}@: %{public}@", log: log, type: .fault, obvContext.flowId.debugDescription, error.localizedDescription)
                ObvBackupNotification.backupSeedGenerationFailed(flowId: flowId)
                    .postOnBackgroundQueue(within: notificationDelegate)
                return
            }
            
            self?.evaluateIfBackupIsRequired(flowId: flowId)
            
            os_log("New backup key was generated within flow %{public}@", log: log, type: .info, obvContext.flowId.debugDescription)
            ObvBackupNotification.newBackupSeedGenerated(backupSeedString: newBackupSeed.description, backupKeyInformation: backupKeyInformation, flowId: flowId)
                .postOnBackgroundQueue(within: notificationDelegate)
            
        }
        
    }
    
    
    public func verifyBackupKey(backupSeedString: String, flowId: FlowIdentifier) async throws -> Bool {

        let log = self.log

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                
            do {
                try delegateManager.contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
                    
                    guard let currentBackupKey = try getCurrentBackupKey(within: obvContext) else {
                        throw Self.makeError(message: "No current backup key")
                    }
                    
                    guard let backupSeed = BackupSeed(backupSeedString) else {
                        os_log("The backup seed string is not appropriate", log: log, type: .error)
                        throw Self.makeError(message: "The backup seed string is not appropriate")
                    }
                    
                    guard backupSeed.deriveKeysForBackup() == currentBackupKey.derivedKeysForBackup else {
                        continuation.resume(returning: false)
                        return
                    }
                    
                    // If we reach this point, the entered seed matches the current backup key
                    
                    currentBackupKey.addSuccessfulVerification()
                    do {
                        try obvContext.save(logOnFailure: log)
                    } catch {
                        assertionFailure()
                        // Continue anyway since the backup key is correct
                    }
                    
                    continuation.resume(returning: true)
                }
            } catch {
                continuation.resume(throwing: error)
            }
            
        }
        
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
                
        // Create and compress the full backup
        
        let compressedFullBackupData = try fullBackup.computeCompressedData(flowId: backupRequestIdentifier, log: log)
        
        os_log("The compressed full backup is made of %d bytes within flow %{public}@", log: log, type: .info, compressedFullBackupData.count, backupRequestIdentifier.description)

        return try await createPersistedBackup(forExport: forExport, backupRequestIdentifier: backupRequestIdentifier, compressedFullBackupData: compressedFullBackupData)
        
    }
    
    
    public func getBackupKeyInformation(flowId: FlowIdentifier) throws -> BackupKeyInformation? {
        
        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            throw ObvBackupManagerImplementation.makeError(message: "The context creator is not set")
        }

        var backupKeyInformation: BackupKeyInformation? = nil
        
        try contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: flowId) { (obvContext) in
            
            guard let backupKey = try getCurrentBackupKey(within: obvContext) else {
                return
            }
            
            backupKeyInformation = backupKey.backupKeyInformation

        }
        
        return backupKeyInformation
        
    }

    
    public func markBackupAsExported(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws {
        
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
            let candidates = backupKey.backups.filter({ $0.forExport && $0.version == backupVersion })
            guard candidates.count == 1 else {
                throw ObvBackupManagerImplementation.makeError(message: "Unexpected number of backup candidates")
            }
            let backup = candidates.first!
            try backup.setExported()
            try obvContext.save(logOnFailure: log)

        }
        
    }

    
    public func markBackupAsUploaded(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws {
        
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
            let candidates = backupKey.backups.filter({ !$0.forExport && $0.version == backupVersion })
            guard candidates.count == 1 else {
                throw ObvBackupManagerImplementation.makeError(message: "Unexpected number of backup candidates. Expecting 1, got \(candidates.count)")
            }
            let backup = candidates.first!
            try backup.setUploaded()
            try obvContext.save(logOnFailure: log)

            self.isBackupRequired = false

        }
        
    }

    
    public func markBackupAsFailed(backupKeyUid: UID, backupVersion: Int, flowId: FlowIdentifier) throws {
        
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
            let candidates = backupKey.backups.filter({ $0.version == backupVersion })
            guard candidates.count == 1 else {
                throw ObvBackupManagerImplementation.makeError(message: "Unexpected number of backup candidates. Expecting 1, got \(candidates.count)")
            }
            let backup = candidates.first!
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

        let derivedKeysForBackup = backupSeed.deriveKeysForBackup()
        let usedDerivedKeys = derivedKeysForBackup.copyWithoutPrivateKeyForEncryption()

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
        guard let compressedFullBackupData = PublicKeyEncryption.decrypt(EncryptedData(data: encryptedBackup), using: privateKey) else {
            os_log("We failed to decrypt the encrypted backup", log: log, type: .error)
            throw BackupRestoreError.backupDataDecryptionFailed
        }
        
        os_log("The backup data was successfully decrypted for backup request identified by %{public}@. We can decompress this data.", log: log, type: .info, backupRequestIdentifier.description)

        let fullBackup: FullBackup
        do {
            fullBackup = try await FullBackup(compressedFullBackupData: compressedFullBackupData)
        } catch {
            throw BackupRestoreError.internalError(code: 3)
        }
        
        addBackupBeingCurrentltyRestored(flowId: backupRequestIdentifier, fullbackup: fullBackup)
        addDerivedKeysForBackupBeingCurrentlyRestored(flowId: backupRequestIdentifier, derivedKeys: usedDerivedKeys)

        return (backupRequestIdentifier, fullBackup.backupDate)
        
    }
    
    
    private func computeMAC(derivedKeysForBackup: DerivedKeysForBackup, backupData: Data) async throws -> (computedMac: Data, receivedMac: Data, encryptedBackup: Data) {
        
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
        
        // Restore the app object
        
        guard let internalJson = fullBackup.allInternalJsonAndIdentifier[backupableAppObject.backupSource]?[backupableAppObject.backupIdentifier] else {
            os_log("Could not recover the internal backup of the app (identified by key %{public}@)", log: log, type: .default, backupableAppObject.backupIdentifier)
            throw Self.makeError(message: "Could not recover the internal backup of the app")
        }

        try await backupableAppObject.restoreBackup(backupRequestIdentifier: backupRequestIdentifier, internalJson: internalJson)
        
        // If we reach this point, the full backup was restored

        await fullBackupRestored(backupRequestIdentifier: backupRequestIdentifier)
        
    }
    
    
    private func fullBackupRestored(backupRequestIdentifier: FlowIdentifier) async {

        // We stored the (public part) of the derived keys used to decrypt the backup during the execution of recoverBackupData(...). Since we now that these keys worked and allowed to access a backup that was restored, we save these keys in DB now so that they can be used for subsequent backups.
        guard let usedDerivedKeys = getDerivedKeysForBackupBeingCurrentlyRestored(flowId: backupRequestIdentifier) else {
            assertionFailure()
            return
        }
     
        let delegateManager = self.delegateManager
        let log = self.log
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            
            delegateManager.contextCreator.performBackgroundTaskAndWait(flowId: backupRequestIdentifier) { obvContext in
                
                do {
                    try BackupKey.deleteAll(delegateManager: delegateManager, within: obvContext)
                } catch let error {
                    os_log("Could not delete all previous backup keys within flow %{public}@: %{public}@", log: log, type: .fault, backupRequestIdentifier.debugDescription, error.localizedDescription)
                    assertionFailure()
                    continuation.resume() // It is ok to tell the app the backup was restored
                    return
                }
                
                _ = BackupKey(derivedKeysForBackup: usedDerivedKeys, delegateManager: delegateManager, within: obvContext)
                
                do {
                    try obvContext.save(logOnFailure: log)
                } catch let error {
                    os_log("Could not delete previous backup keys nor create new backup key within flow %{public}@: %{public}@", log: log, type: .fault, backupRequestIdentifier.debugDescription, error.localizedDescription)
                    continuation.resume() // It is ok to tell the app the backup was restored
                    return
                }

            }
                    
            removeBackupBeingCurrentltyRestored(flowId: backupRequestIdentifier)
            
            continuation.resume()

        }
        
    }
    
    
    public func userJustActivatedAutomaticBackup() {
        isBackupRequired = true
    }
    
}


// MARK: - Helpers

extension ObvBackupManagerImplementation {
    
    
    private func createPersistedBackup(forExport: Bool, backupRequestIdentifier: FlowIdentifier, compressedFullBackupData: Data) async throws -> (backupKeyUid: UID, version: Int, encryptedContent: Data) {
        
        assert(!Thread.isMainThread)
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(backupKeyUid: UID, version: Int, encryptedContent: Data), Error>) in
            
            do {
                try delegateManager.contextCreator.performBackgroundTaskAndWaitOrThrow(flowId: backupRequestIdentifier) { (obvContext) in

                    guard let currentBackupKey = try getCurrentBackupKey(within: obvContext) else {
                        throw ObvBackupManagerImplementation.makeError(message: "No backup key available")
                    }

                    os_log("An appropriate backup key was found for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)

                    let backup = try Backup.createOngoingBackup(forExport: forExport, backupKey: currentBackupKey, delegateManager: delegateManager)
                    
                    os_log("The new ongoing backup for backup request identified by %{public}@ has version %d", log: log, type: .info, backupRequestIdentifier.description, backup.version)
                    
                    // Get the backup item from database in order to recover the current crypto keys
                    
                    guard let derivedKeysForBackup = backup.backupKey?.derivedKeysForBackup else {
                        os_log("Could not find any backup key for ongoing backup", log: log, type: .fault)
                        throw Self.makeError(message: "Could not find any backup key for ongoing backup")
                    }
                    
                    // At this point we have a compressed backup and the appropriate keys. We can encrypt the backup.

                    os_log("Encrypting the compressed full backup for backupRequestIdentifier %{public}@", log: log, type: .info, backupRequestIdentifier.description)
                    
                    let encryptedBackup = PublicKeyEncryption.encrypt(compressedFullBackupData, using: derivedKeysForBackup.publicKeyForEncryption, and: prng)
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
                    try await backupableManagerObject.restoreBackup(backupRequestIdentifier: backupRequestIdentifier, internalJson: internalJson)
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
                    return try await backupableManager.provideInternalDataForBackup(backupRequestIdentifier: backupRequestIdentifier)
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
            backupKeys = try BackupKey.getAll(delegateManager: delegateManager, within: obvContext)
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
                guard let _currentBackupKey = try BackupKey.getCurrent(delegateManager: delegateManager, within: obvContext) else { return }
                currentBackupKey = _currentBackupKey
            } catch let error {
                os_log("Could not get current backup key: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            let lastExportedOrUploadedBackupDate = currentBackupKey.backupKeyInformation.lastBackupUploadTimestamp ?? Date.distantPast
            // If reach this point, we know some backup has been uploaded or exported in the past. We check whether this was not too long ago.
            guard -lastExportedOrUploadedBackupDate.timeIntervalSinceNow < ObvConstants.maxTimeUntilBackupIsRequired else {
                os_log("Last uploaded or exported backup was performed too long ago. We set isBackupRequired to true.", log: log, type: .info)
                self.isBackupRequired = true
                return
            }
            
            // If the latest backup has failed (or no automatic backup was performed with the current key), backup is required
            
            guard let lastBackup = currentBackupKey.lastBackup else {
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
    
    
    init(compressedFullBackupData: Data) async throws {
        let fullBackupData = try await Self.decompressCompressedBackupContent(compressedFullBackupData)
        let jsonEncoder = JSONDecoder()
        self = try jsonEncoder.decode(FullBackup.self, from: fullBackupData)
    }
    
    
    var allInternalJsonAndIdentifier: [ObvBackupableObjectSource: [String: String]] {
        var result = [ObvBackupableObjectSource: [String: String]]()
        if let appBackup = appBackup {
            result[.app] = [ "app": appBackup ] // Yes, this is ugly. But the "app" key is ignored
        }
        result[.engine] = engineManagerBackups
        return result
    }
 
    func computeCompressedData(flowId: FlowIdentifier, log: OSLog) throws -> Data {
        
        // Create the full backup content
        
        os_log("Creating full backup content within flow %{public}@", log: log, type: .info, flowId.description)
        
        let jsonEncoder = JSONEncoder()
        let fullBackupData = try jsonEncoder.encode(self)

        // Compress the full backup content

        os_log("Compressing the %d bytes full backup content within flow %{public}@", log: log, type: .info, fullBackupData.count, flowId.description)

        let compressedFullBackupData = try compressFullBackupContent(fullBackupData)
        
        return compressedFullBackupData

    }
    
    
    private func compressFullBackupContent(_ fullBackupContent: Data) throws -> Data {
    
        // See https://developer.apple.com/documentation/accelerate/compressing_and_decompressing_data_with_buffer_compression
        // We use a method working under iOS 11+. Under iOS 13+, we could use simpler APIs.
        
        var sourceBuffer = [UInt8](fullBackupContent)
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: fullBackupContent.count)
        let algorithm = COMPRESSION_ZLIB
        let compressedSize = compression_encode_buffer(destinationBuffer, fullBackupContent.count, &sourceBuffer, fullBackupContent.count, nil, algorithm)
        guard compressedSize > 0 else {
            throw ObvBackupManagerImplementation.makeError(message: "Compression failed")
        }
        let compressedFullBackupData = Data(bytes: destinationBuffer, count: compressedSize)
        return compressedFullBackupData
        
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
