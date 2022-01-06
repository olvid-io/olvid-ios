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

    private var backupsBeingCurrentltyRestored = [FlowIdentifier: FullBackup]()
    
    /// The stored derived keys only include public keys. This array allows to store the derived keys when a backup is successfully recovered,
    /// so as to use these keys again for future backups.
    private var derivedKeysForBackupBeingCurrentltyRestored = [FlowIdentifier: DerivedKeysForBackup]()
    
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
    
    private let internalQueueForBackupKeyVerification = DispatchQueue(label: "Queue for backup verification")
    
    private let internalJsonToBackupQueue = DispatchQueue(label: "Queue for retrieving internal data to backup")
    private var _internalJsonToBackup: [FlowIdentifier: [ObvBackupableObjectSource: [String: String]]] = [:]

    private func addInternalJsonToBackup(_ internalJsonAndIdentifier: (internalJson: String, internalJsonIdentifier: String, source: ObvBackupableObjectSource), backupRequestIdentifier: FlowIdentifier) {
        internalJsonToBackupQueue.sync {
            var values = _internalJsonToBackup[backupRequestIdentifier] ?? [:]
            if var subValues = values[internalJsonAndIdentifier.source] {
                subValues[internalJsonAndIdentifier.internalJsonIdentifier] = internalJsonAndIdentifier.internalJson
                values[internalJsonAndIdentifier.source] = subValues
            } else {
                let subValues = [internalJsonAndIdentifier.internalJsonIdentifier: internalJsonAndIdentifier.internalJson]
                values[internalJsonAndIdentifier.source] = subValues
            }
            _internalJsonToBackup[backupRequestIdentifier] = values
        }
    }

    private func getNumberOfBackupedManagers(backupRequestIdentifier: FlowIdentifier) -> Int {
        var res = 0
        internalJsonToBackupQueue.sync {
            res = _internalJsonToBackup[backupRequestIdentifier]?.count ?? 0
        }
        return res
    }
    
    private func removeInternalDataToBackup(flowId: FlowIdentifier) -> [ObvBackupableObjectSource: [String: String]] {
        var res = [ObvBackupableObjectSource: [String: String]]()
        internalJsonToBackupQueue.sync {
            res = _internalJsonToBackup.removeValue(forKey: flowId) ?? [:]
        }
        return res
    }
    
    /* During a restore, we keep track of the backups parts that were successuflly restored (we expect two at this time: the
     * identity manager and the app). When the list (indexed by the backup flow identifier) contains all the expected elements
     * the backup is considered to be successfull and a notification is sent.
     */
    private var _restoredObvBackupables = [FlowIdentifier: [(source: ObvBackupableObjectSource, backupIdentifier: String)]]()
    private func addToRestoredObvBackupables(backupRequestIdentifier: FlowIdentifier, value: (source: ObvBackupableObjectSource, backupIdentifier: String)) {
        internalJsonToBackupQueue.sync {
            var values = _restoredObvBackupables[backupRequestIdentifier] ?? []
            guard values.contains(where: { $0.source == value.source && $0.backupIdentifier == value.backupIdentifier }) == false else { assertionFailure(); return }
            values.append(contentsOf: [value])
            _restoredObvBackupables[backupRequestIdentifier] = values
        }
    }
    private func numberOfRestoredObvBackupablesDuringBackup(backupRequestIdentifier: FlowIdentifier) -> Int {
        var res = 0
        internalJsonToBackupQueue.sync {
            res = _restoredObvBackupables[backupRequestIdentifier]?.count ?? 0
        }
        return res
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
                let notification = ObvBackupNotification.backupSeedGenerationFailed(flowId: flowId)
                notification.postOnDispatchQueue(withLabel: "Queue for posting backupSeedGenerationFailed notification", within: notificationDelegate)
                return
            }
            
            let backupKey = BackupKey(derivedKeysForBackup: derivedKeysForBackup, delegateManager: delegateManager, within: obvContext)
            let backupKeyInformation = backupKey.backupKeyInformation
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not delete previous backup keys nor create new backup key within flow %{public}@: %{public}@", log: log, type: .fault, obvContext.flowId.debugDescription, error.localizedDescription)
                let notification = ObvBackupNotification.backupSeedGenerationFailed(flowId: flowId)
                notification.postOnDispatchQueue(withLabel: "Queue for posting backupSeedGenerationFailed notification", within: notificationDelegate)
                return
            }
            
            self?.evaluateIfBackupIsRequired(flowId: flowId)
            
            os_log("New backup key was generated within flow %{public}@", log: log, type: .info, obvContext.flowId.debugDescription)
            let notification = ObvBackupNotification.newBackupSeedGenerated(backupSeedString: newBackupSeed.description, backupKeyInformation: backupKeyInformation, flowId: flowId)
            notification.postOnDispatchQueue(withLabel: "Queue for posting newBackupSeedGenerated notification", within: notificationDelegate)
            
        }
        
    }
    
    
    public func verifyBackupKey(backupSeedString: String, flowId: FlowIdentifier, completion: @escaping (Result<Void,Error>) -> Void) {

        let log = self.log

        internalQueueForBackupKeyVerification.async { [weak self] in
            
            guard let _self = self else { return }
            
            _self.delegateManager.contextCreator.performBackgroundTask(flowId: flowId) { (obvContext) in
                
                var validationSuccess = false
                defer {
                    if validationSuccess {
                        completion(.success(()))
                    } else {
                        completion(.failure(_self.makeError(message: "backup key verification failed")))
                    }
                }
                
                let currentBackupKey: BackupKey
                do {
                    guard let _currentBackupKey = try _self.getCurrentBackupKey(within: obvContext) else {
                        throw ObvBackupManagerImplementation.makeError(message: "No current backup key")
                    }
                    currentBackupKey = _currentBackupKey
                } catch let error {
                    os_log("Could not get current backup key with flow %{public}@: %{public}@", log: log, type: .fault, flowId.debugDescription, error.localizedDescription)
                    return
                }
                
                guard let backupSeed = BackupSeed(backupSeedString) else {
                    os_log("The backup seed string is not appropriate", log: log, type: .error)
                    return
                }
                
                guard backupSeed.deriveKeysForBackup() == currentBackupKey.derivedKeysForBackup else { return }
                
                // If we reach this point, the entered seed matches the current backup key
                
                currentBackupKey.addSuccessfulVerification()
                do {
                    try obvContext.save(logOnFailure: log)
                } catch let error {
                    os_log("Could not increment the number of successful verifications of the current backup key: %{public}@", log: log, type: .error, error.localizedDescription)
                    return
                }
                
                validationSuccess = true
                
            }
            
        }
        
    }
    
    public func initiateBackup(forExport: Bool, backupRequestIdentifier: FlowIdentifier) throws {
        
        let log = self.log
        let delegateManager = self.delegateManager
        
        guard let notificationDelegate = delegateManager.notificationDelegate else {
            os_log("The notification delegate is not set", log: log, type: .fault)
            assertionFailure()
            return
        }

        var ongoingBackupSavedToDatabase = false
        defer {
            if !ongoingBackupSavedToDatabase {
                let notification = ObvBackupNotification.backupFailed(flowId: backupRequestIdentifier)
                notification.postOnDispatchQueue(withLabel: "Queue for posting backupFailed notification", within: notificationDelegate)
            }
        }
        
        guard appBackupableObjectIsRegistered else {
            os_log("Cannot backup yet. The app backupable object is not registered yet.", log: log, type: .fault)
            throw ObvBackupManagerImplementation.makeError(message: "Cannot backup yet. The app backupable object is not registered yet.")
        }
        
        guard let backupableObjects = self.backupableManagers.map({ $0.value }) as? [ObvBackupable] else {
            os_log("Critical error. Could not recover the managers to backup", log: log, type: .default)
            throw ObvBackupManagerImplementation.makeError(message: "Critical error. Could not recover the managers to backup")
        }

        os_log("Initiating a backup for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)
        
        delegateManager.contextCreator.performBackgroundTaskAndWait(flowId: backupRequestIdentifier) { [weak self] (obvContext) in
            
            guard let _self = self else { return }
            
            let currentBackupKey: BackupKey
            do {
                guard let _currentBackupKey = try _self.getCurrentBackupKey(within: obvContext) else {
                    throw ObvBackupManagerImplementation.makeError(message: "No backup key available")
                }
                currentBackupKey = _currentBackupKey
            } catch let error {
                os_log("Could not get current backup key for backup request identified by %{public}@: %{public}@", log: log, type: .fault, backupRequestIdentifier.debugDescription, error.localizedDescription)
                return
            }
            
            os_log("An appropriate backup key was found for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)

            let backupObjectID: NSManagedObjectID
            do {
                let backup = try Backup.createOngoingBackup(forExport: forExport, backupKey: currentBackupKey, delegateManager: delegateManager)
                try obvContext.save(logOnFailure: log)
                backupObjectID = backup.objectID
                os_log("The new ongoing backup for backup request identified by %{public}@ has version %d", log: log, type: .info, backupRequestIdentifier.description, backup.version)
            } catch let error {
                os_log("Could not create ongoing backup for backup request identified by %{public}@: %{public}@", log: log, type: .fault, backupRequestIdentifier.debugDescription, error.localizedDescription)
                return
            }
            
            ongoingBackupSavedToDatabase = true
            
            for backupableManager in backupableObjects {
                backupableManager.provideInternalDataForBackup(backupRequestIdentifier: backupRequestIdentifier) { result in
                    switch result {
                    case .failure(let error):
                        
                        os_log("Could not get internal data for backup from one of the backupable managers: %{public}@", log: log, type: .fault, error.localizedDescription)
                        delegateManager.contextCreator.performBackgroundTask(flowId: backupRequestIdentifier) { (obvContext) in
                            let backup: Backup
                            do {
                                guard let _backup = try Backup.get(objectID: backupObjectID, delegateManager: delegateManager, within: obvContext) else {
                                    throw ObvBackupManagerImplementation.makeError(message: "Could not find Backup in database")
                                }
                                backup = _backup
                            } catch let error {
                                os_log("Could not find any appropriate ongoing backup: %{public}@", log: log, type: .fault, error.localizedDescription)
                                return
                            }
                            do {
                                try backup.setFailed()
                                try obvContext.save(logOnFailure: log)
                            } catch let error {
                                os_log("Could not mark the backup as failed: %{public}@", log: log, type: .fault, error.localizedDescription)
                                return
                            }
                        }
                        return
                        
                    case .success(let internalJsonAndIdentifier):
                        
                        // If we reach this point, the backupable manager did send an appropriate json of its internal data to backup
                        
                        self?.addInternalJsonToBackup(internalJsonAndIdentifier, backupRequestIdentifier: backupRequestIdentifier)
                        guard self?.getNumberOfBackupedManagers(backupRequestIdentifier: backupRequestIdentifier) == backupableObjects.count else {
                            debugPrint("Still waiting for some managers to provide their internal data for backup")
                            return
                        }
                        
                        // If we reach this point, we have the internal data of all the managers
                        
                        os_log("All backupable managers provided their data for the backup for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)
                        self?.allManagersProvidedTheirInternalJsonAndIdentifier(flowId: backupRequestIdentifier, backupObjectID: backupObjectID)
                        
                    }
                }
            }

        }
                
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
    public func recoverBackupData(_ backupData: Data, withBackupKey backupKey: String, backupRequestIdentifier: FlowIdentifier, completion: @escaping (Result<(backupRequestIdentifier: UUID, backupDate: Date), BackupRestoreError>) -> Void) {

        assert(Thread.current != Thread.main)
        
        var fullBackup: FullBackup?
        var usedDerivedKeys: DerivedKeysForBackup?
        var backupRestoreError: BackupRestoreError?
        defer {
            if let fullBackup = fullBackup {
                backupsBeingCurrentltyRestored[backupRequestIdentifier] = fullBackup
                // If the backup was fully recovered, we can store the used derived keys (if we have them)/
                // This will allow to store these keys in DB at the time the backup is actually restored.
                if let usedDerivedKeys = usedDerivedKeys {
                    derivedKeysForBackupBeingCurrentltyRestored[backupRequestIdentifier] = usedDerivedKeys
                } else {
                    assertionFailure()
                }
                completion(.success((backupRequestIdentifier, fullBackup.backupDate)))
            } else {
                let error = backupRestoreError ?? .internalError(code: -1)
                completion(.failure(error))
            }
        }
        
        // Compute the derive keys from the backup key
        
        os_log("Computing the derived keys from the backup key for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)

        guard let backupSeed = BackupSeed(backupKey) else {
            os_log("Could not compute backup seed for backup request identified by %{public}@", log: log, type: .fault)
            backupRestoreError = .internalError(code: 0)
            return
        }
        
        let derivedKeysForBackup = backupSeed.deriveKeysForBackup()
        usedDerivedKeys = derivedKeysForBackup.copyWithoutPrivateKeyForEncryption()
        
        // We check the mac of encryptedBackupData

        os_log("Checking the mac of encrypted backup for backup request identified by %{public}@", log: log, type: .info, backupRequestIdentifier.description)

        let macAlgoByteId = derivedKeysForBackup.macKey.algorithmImplementationByteId
        let macLength = MAC.outputLength(for: macAlgoByteId)
        guard backupData.count >= macLength else {
            os_log("The backup data is too small for backup request identified by %{public}@", log: log, type: .error, backupRequestIdentifier.description)
            backupRestoreError = .internalError(code: 1)
            return
        }
        let receivedMac = backupData[backupData.endIndex-macLength..<backupData.endIndex]
        let encryptedBackup = backupData[backupData.startIndex..<backupData.endIndex-macLength]
        let computedMac: Data
        do {
            computedMac = try MAC.compute(forData: encryptedBackup, withKey: derivedKeysForBackup.macKey)
        } catch {
            os_log("The MAC computation failed %{public}@ for backup request identified by %{public}@", log: log, type: .error, error.localizedDescription, backupRequestIdentifier.description)
            backupRestoreError = .macComputationFailed
            return
        }

        guard computedMac == receivedMac else {
            os_log("The mac comparison failed during the recover of the backup for backup request identified by %{public}@", log: log, type: .error)
            backupRestoreError = .macComparisonFailed
            return
        }
        
        os_log("The mac of the backup data is correct for backup request identified by %{public}@. Decrypting the data", log: log, type: .info, backupRequestIdentifier.description)

        // We decrypt the data
        
        guard let privateKey = derivedKeysForBackup.privateKeyForEncryption else {
            os_log("The private key for decryption is nil, which is unexpected", log: log, type: .fault)
            backupRestoreError = .internalError(code: 2)
            return
        }
        guard let compressedFullBackupData = PublicKeyEncryption.decrypt(EncryptedData(data: encryptedBackup), using: privateKey) else {
            os_log("We failed to decrypt the encrypted backup", log: log, type: .error)
            backupRestoreError = .backupDataDecryptionFailed
            return
        }
        
        os_log("The backup data was successfully decrypted for backup request identified by %{public}@. We can decompress this data.", log: log, type: .info, backupRequestIdentifier.description)

        let fullBackupData: Data
        do {
            fullBackupData = try decompressCompressedBackupContent(compressedFullBackupData)
        } catch {
            os_log("Could not decompress the backup data for backup request identified by %{public}@", log: log, type: .error)
            backupRestoreError = .internalError(code: 3)
            return
        }
        
        os_log("The backup data was successfully decompressed for backup request identified by %{public}@.", log: log, type: .info, backupRequestIdentifier.description)

        do {
            let jsonEncoder = JSONDecoder()
            fullBackup = try jsonEncoder.decode(FullBackup.self, from: fullBackupData)
        } catch let error {
            debugPrint(error.localizedDescription)
            backupRestoreError = .internalError(code: 4)
            return
        }

    }


    
    public func restoreFullBackup(backupRequestIdentifier: FlowIdentifier, completionHandler: @escaping ((Result<Void, Error>) -> Void)) {

        assert(Thread.current != Thread.main)

        guard let fullBackup = backupsBeingCurrentltyRestored[backupRequestIdentifier] else {
            completionHandler(.failure(ObvBackupManagerImplementation.makeError(message: "Full backup was not found and thus cannot be restored")))
            return
        }
        
        guard appBackupableObjectIsRegistered else {
            completionHandler(.failure(ObvBackupManagerImplementation.makeError(message: "Cannot restore backup yet. The app backupable object is not registered yet.")))
            return
        }

        guard let backupableObjects = self.backupableManagers.map({ $0.value }) as? [ObvBackupable] else {
            completionHandler(.failure(ObvBackupManagerImplementation.makeError(message: "Critical error. Could not recover the managers to backup")))
            return
        }
        
        // Restore the engine managers first
        
        let backupableManagerObjects = backupableObjects.filter({ $0 is ObvBackupableManager })
        let backupableAppObjects = backupableObjects.filter({ !($0 is ObvBackupableManager) })
        guard backupableAppObjects.count == 1 else {
            completionHandler(.failure(ObvBackupManagerImplementation.makeError(message: "Expecting exactly one backupable app object, got \(backupableAppObjects.count)")))
            return
        }
        let backupableAppObject = backupableAppObjects.first!
        
        for backupableManagerObject in backupableManagerObjects {
            guard let internalJson = fullBackup.allInternalJsonAndIdentifier[backupableManagerObject.backupSource]?[backupableManagerObject.backupIdentifier] else {
                completionHandler(.failure(ObvBackupManagerImplementation.makeError(message: "Could not recover the internal backup of one of the managers (identified by key \(backupableManagerObject.backupIdentifier)")))
                return
            }
            backupableManagerObject.restoreBackup(backupRequestIdentifier: backupRequestIdentifier, internalJson: internalJson) { [weak self] (error) in
                guard error == nil else {
                    self?.backupsBeingCurrentltyRestored.removeValue(forKey: backupRequestIdentifier)
                    completionHandler(.failure(ObvBackupManagerImplementation.makeError(message: "Could not restore backup for \(backupableManagerObject.backupIdentifier) : \(error!.localizedDescription)")))
                    return
                }
                self?.addToRestoredObvBackupables(backupRequestIdentifier: backupRequestIdentifier, value: (backupableManagerObject.backupSource, backupableManagerObject.backupIdentifier))
                if self?.numberOfRestoredObvBackupablesDuringBackup(backupRequestIdentifier: backupRequestIdentifier) == backupableManagerObjects.count {
                    self?.allManagersWereRestored(backupRequestIdentifier: backupRequestIdentifier, backupableAppObject: backupableAppObject, completionHandler: completionHandler)
                }
            }
        }

        // The rest of the procedure is performed in `allManagersWereRestored(...)`
        
    }
    
    
    /// Called during a backup restore, when all managers (well, the identity manager) have been successfully restored in DB. We can now call the restoreBackup(...) method of the app.
    private func allManagersWereRestored(backupRequestIdentifier: FlowIdentifier, backupableAppObject: ObvBackupable, completionHandler: @escaping ((Result<Void, Error>) -> Void)) {

        guard let fullBackup = backupsBeingCurrentltyRestored[backupRequestIdentifier] else {
            completionHandler(.failure(ObvBackupManagerImplementation.makeError(message: "Full backup was not found and thus cannot be restored")))
            return
        }

        guard let internalJson = fullBackup.allInternalJsonAndIdentifier[backupableAppObject.backupSource]?[backupableAppObject.backupIdentifier] else {
            os_log("Could not recover the internal backup of the app (identified by key %{public}@)", log: log, type: .default, backupableAppObject.backupIdentifier)
            return
        }

        backupableAppObject.restoreBackup(backupRequestIdentifier: backupRequestIdentifier, internalJson: internalJson) { [weak self] (error) in
            guard error == nil else {
                self?.backupsBeingCurrentltyRestored.removeValue(forKey: backupRequestIdentifier)
                completionHandler(.failure(ObvBackupManagerImplementation.makeError(message: "Could not restore backup for \(backupableAppObject.backupIdentifier) : \(error!.localizedDescription)")))
                return
            }

            self?.fullBackupRestored(backupRequestIdentifier: backupRequestIdentifier, completionHandler: completionHandler)
            
        }
        
    }
    
    
    private func fullBackupRestored(backupRequestIdentifier: FlowIdentifier, completionHandler: @escaping ((Result<Void, Error>) -> Void)) {
        // We stored the (public part) of the derived keys used to decrypt the backup during the execution of recoverBackupData(...). Since we now that these keys worked and allowed to access a backup that was restored, we save these keys in DB now so that they can be used for subsequent backups.
        guard let usedDerivedKeys = self.derivedKeysForBackupBeingCurrentltyRestored[backupRequestIdentifier] else {
            assertionFailure()
            completionHandler(.success(())) // It is ok to tell the app the backup was restored
            return
        }
     
        let delegateManager = self.delegateManager
        let log = self.log
        
        self.delegateManager.contextCreator.performBackgroundTaskAndWait(flowId: backupRequestIdentifier) { obvContext in
            
            do {
                try BackupKey.deleteAll(delegateManager: delegateManager, within: obvContext)
            } catch let error {
                os_log("Could not delete all previous backup keys within flow %{public}@: %{public}@", log: log, type: .fault, backupRequestIdentifier.debugDescription, error.localizedDescription)
                assertionFailure()
                completionHandler(.success(())) // It is ok to tell the app the backup was restored
                return
            }
            
            _ = BackupKey(derivedKeysForBackup: usedDerivedKeys, delegateManager: delegateManager, within: obvContext)
            
            do {
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not delete previous backup keys nor create new backup key within flow %{public}@: %{public}@", log: log, type: .fault, backupRequestIdentifier.debugDescription, error.localizedDescription)
                completionHandler(.success(())) // It is ok to tell the app the backup was restored
                return
            }

        }
                
        _ = backupsBeingCurrentltyRestored.removeValue(forKey: backupRequestIdentifier)
        
        completionHandler(.success(())) // It is ok to tell the app the backup was restored
        
    }
    
    
    public func userJustActivatedAutomaticBackup() {
        isBackupRequired = true
    }
    
}


// MARK: - Helpers

extension ObvBackupManagerImplementation {
    
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

    
    private func allManagersProvidedTheirInternalJsonAndIdentifier(flowId: FlowIdentifier, backupObjectID: NSManagedObjectID) {
        
        let log = self.log
        let prng = self.prng

        guard let contextCreator = delegateManager.contextCreator else {
            os_log("The context creator is not set", log: log, type: .fault)
            return
        }

        contextCreator.performBackgroundTaskAndWait(flowId: flowId) { (obvContext) in
            
            let backup: Backup
            do {
                guard let _backup = try Backup.get(objectID: backupObjectID, delegateManager: delegateManager, within: obvContext) else { throw ObvBackupManagerImplementation.makeError(message: "Could not find Backup in database") }
                backup = _backup
            } catch let error {
                os_log("Could not find any appropriate ongoing backup: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }

            let allInternalJsonAndIdentifier = removeInternalDataToBackup(flowId: flowId)
            guard allInternalJsonAndIdentifier.count == backupableManagers.count else {
                os_log("Backup failed. Unexpected number of data to backup given the number of managers.", log: log, type: .fault)
                do {
                    try backup.setFailed()
                    try obvContext.save(logOnFailure: log)
                } catch let error {
                    os_log("%{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                assertionFailure()
                return
            }
            
            let fullBackup: FullBackup
            do {
                fullBackup = try FullBackup(allInternalJsonAndIdentifier: allInternalJsonAndIdentifier)
            } catch {
                os_log("Backup failed: %{public}@", log: log, type: .fault, error.localizedDescription)
                do {
                    try backup.setFailed()
                    try obvContext.save(logOnFailure: log)
                } catch let error {
                    os_log("%{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                assertionFailure()
                return
            }
            
            // Create the full backup content
            
            os_log("Creating full backup content within flow %{public}@", log: log, type: .info, flowId.description)
            
            let fullBackupData: Data
            do {
                let jsonEncoder = JSONEncoder()
                fullBackupData = try jsonEncoder.encode(fullBackup)
            } catch let error {
                os_log("Backup failed. Could not encode the internal json: %{public}@", log: log, type: .fault, error.localizedDescription)
                do {
                    try backup.setFailed()
                    try obvContext.save(logOnFailure: log)
                } catch let error {
                    os_log("%{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                assertionFailure()
                return
            }

            // Compress the full backup content

            os_log("Compressing the %d bytes full backup content within flow %{public}@", log: log, type: .info, fullBackupData.count, flowId.description)

            let compressedFullBackupData: Data
            do {
                compressedFullBackupData = try compressFullBackupContent(fullBackupData)
            } catch let error {
                os_log("Could not compress backup data: %{public}@", log: log, type: .fault, error.localizedDescription)
                do {
                    try backup.setFailed()
                    try obvContext.save(logOnFailure: log)
                } catch let error {
                    os_log("%{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                assertionFailure()
                return
            }

            os_log("The compressed full backup is made of %d bytes within flow %{public}@", log: log, type: .info, compressedFullBackupData.count, flowId.description)

            // Get the backup item from database in order to recover the current crypto keys
            
            guard let derivedKeysForBackup = backup.backupKey?.derivedKeysForBackup else {
                os_log("Could not find any backup key for ongoing backup", log: log, type: .fault)
                do {
                    try backup.setFailed()
                    try obvContext.save(logOnFailure: log)
                } catch let error {
                    os_log("%{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                assertionFailure()
                return
            }
            
            // At this point we have a compressed backup and the appropriate keys. We can encrypt the backup.

            os_log("Encrypting the compressed full backup within flow %{public}@", log: log, type: .info, flowId.description)
            
            let authenticatedEncryptedBackup: EncryptedData
            do {
                let encryptedBackup = PublicKeyEncryption.encrypt(compressedFullBackupData, using: derivedKeysForBackup.publicKeyForEncryption, and: prng)
                let macOfEncryptedBackup = try MAC.compute(forData: encryptedBackup, withKey: derivedKeysForBackup.macKey)
                authenticatedEncryptedBackup = EncryptedData(data: encryptedBackup.raw + macOfEncryptedBackup)
            } catch {
                os_log("Could not encrypt full backup content", log: log, type: .fault)
                do {
                    try backup.setFailed()
                    try obvContext.save(logOnFailure: log)
                } catch let error {
                    os_log("%{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
                assertionFailure()
                return
            }
            
            os_log("The encrypted backup was computed (size is %d bytes) within flow %{public}@", log: log, type: .info, authenticatedEncryptedBackup.count, flowId.description)

            do {
                try backup.setReady(withEncryptedContent: authenticatedEncryptedBackup)
                try obvContext.save(logOnFailure: log)
            } catch let error {
                os_log("Could not save the encrypted backup to DB with flow %{public}@: %{public}@", log: log, type: .fault, flowId.description, error.localizedDescription)
                assertionFailure()
                return
            }
            
            os_log("The encrypted backup was saved to DB within flow %{public}@", log: log, type: .info, flowId.description)

            assert(backup.successfulBackupInfos != nil)

        }
        
        
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
    
    
    private func decompressCompressedBackupContent(_ compressedFullBackupData: Data) throws -> Data {
        
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
                return fullBackupContent
            } else {
                decodedCapacity *= 2
            }
        }

        // If we reach this point, something went wrong
        throw ObvBackupManagerImplementation.makeError(message: "Could not decompress buffer")
        
    }

}


// MARK: - ObvManager

extension ObvBackupManagerImplementation {
    
    public func fulfill(requiredDelegate delegate: AnyObject, forDelegateType delegateType: ObvEngineDelegateType) throws {
        switch delegateType {
        case .ObvCreateContextDelegate:
            guard let delegate = delegate as? ObvCreateContextDelegate else { throw NSError() }
            delegateManager.contextCreator = delegate
        case .ObvNotificationDelegate:
            guard let delegate = delegate as? ObvNotificationDelegate else { throw NSError() }
            delegateManager.notificationDelegate = delegate
        default:
            throw NSError()
        }
    }
    
    public var requiredDelegates: [ObvEngineDelegateType] {
        return [ObvEngineDelegateType.ObvCreateContextDelegate,
                ObvEngineDelegateType.ObvNotificationDelegate]
    }

    public func finalizeInitialization(flowId: FlowIdentifier, runningLog: RunningLogError) throws {

        // Observe `observeBackupableManagerDatabaseContentChanged` notifications for automatic backups
        notificationTokens.append(ObvBackupNotification.observeBackupableManagerDatabaseContentChanged(within: delegateManager.notificationDelegate, queue: internalNotificationQueue) { [weak self] (flowId) in
            self?.isBackupRequired = true
        })
        
        evaluateIfBackupIsRequired(flowId: flowId)

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
    
    public func applicationDidStartRunning(flowId: FlowIdentifier) {}
    public func applicationDidEnterBackground() {}

}


// MARK: - FullBackup

fileprivate struct FullBackup: Codable {
    
    private let appBackup: String?
    private let engineManagerBackups: [String: String]
    let backupTimestamp: Int /// In milliseconds
    let jsonVersion: Int = 0
    
    var backupDate: Date {
        return Date(timeIntervalSince1970: Double(backupTimestamp / 1000))
    }
    
    enum CodingKeys: String, CodingKey {
        case appBackup = "app"
        case engineManagerBackups = "engine"
        case backupTimestamp = "backup_timestamp"
        case jsonVersion = "backup_json_version"
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
    }
    
    
    var allInternalJsonAndIdentifier: [ObvBackupableObjectSource: [String: String]] {
        var result = [ObvBackupableObjectSource: [String: String]]()
        if let appBackup = appBackup {
            result[.app] = [ "app": appBackup ] // Yes, this is ugly. But the "app" key is ignored
        }
        result[.engine] = engineManagerBackups
        return result
    }
 
}
