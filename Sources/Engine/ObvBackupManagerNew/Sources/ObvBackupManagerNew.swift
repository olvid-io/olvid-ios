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
import OSLog
import ObvCrypto
import OlvidUtils
import ObvCoreDataStack
import ObvMetaManager
import ObvServerInterface
import ObvEncoder
import ObvTypes


public protocol ObvBackupManagerNewDelegate: AnyObject {
    func hasActiveOwnedIdentities(_ backupManager: ObvBackupManagerNew) async throws -> Bool
    func solveChallengeForBackupUpload(_ backupManager: ObvBackupManagerNew, backupKeyUID: UID, deviceOrProfileBackupThreadUID: UID, backupVersion: Int, encryptedBackup: EncryptedData, authenticationKeyPair: (publicKey: any PublicKeyForAuthentication, privateKey: any PrivateKeyForAuthentication)) async throws -> Data
    func solveChallengeForBackupDelete(_ backupManager: ObvBackupManagerNew, backupKeyUID: UID, deviceOrProfileBackupThreadUID: UID, backupVersion: Int, authenticationKeyPair: (publicKey: any PublicKeyForAuthentication, privateKey: any PrivateKeyForAuthentication)) async throws -> Data
    func getDeviceSnapshotNodeAsObvDictionary(_ backupManager: ObvBackupManagerNew) async throws -> ObvEncoder.ObvDictionary
    func getProfileSnapshotNodeAsObvDictionary(_ backupManager: ObvBackupManagerNew, ownedCryptoId: ObvCryptoId) async throws -> ObvEncoder.ObvDictionary
    func getBackupSeedOfOwnedIdentity(_ backupManager: ObvBackupManagerNew, ownedCryptoId: ObvCryptoId, restrictToActive: Bool, flowId: FlowIdentifier) async throws -> BackupSeed?
    func getAdditionalInfosForProfileBackup(_ backupManager: ObvBackupManagerNew, ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws -> AdditionalInfosForProfileBackup
    func getAllActiveOwnedIdentities(_ backupManager: ObvBackupManagerNew, flowId: FlowIdentifier) async throws -> Set<ObvCryptoId>
    func parseDeviceBackup(_ backupManager: ObvBackupManagerNew, deviceBackupToParse: DeviceBackupToParse, flowId: FlowIdentifier) async throws -> ObvDeviceBackupFromServer
    func parseProfileBackup(_ backupManager: ObvBackupManagerNew, profileCryptoId: ObvCryptoId, profileBackupToParse: ProfileBackupToParse, flowId: FlowIdentifier) async throws -> ObvProfileBackupFromServer
}


public actor ObvBackupManagerNew {
    
    private static let logger = Logger(subsystem: "io.olvid.ObvBackupManagerNew", category: "ObvBackupManagerNew")
    private static let log = OSLog(subsystem: "io.olvid.ObvBackupManagerNew", category: "ObvBackupManagerNew")

    private weak var delegate: ObvBackupManagerNewDelegate?

    private let keychainManager: KeychainManager
    private var databaseCoordinator: BackupManagerDatabaseCoordinator

    private let prng: any PRNGService
    
    private typealias DeviceBackupCreationAndUploadTask = Task<Void,Error>
    private var deviceBackupCreationAndUploadTaskInProgress: DeviceBackupCreationAndUploadTask?
    
    private typealias ProfileBackupCreationAndUploadTask = Task<Void,Error>
    private var profileBackupCreationAndUploadTaskInProgress = [ObvCryptoId: ProfileBackupCreationAndUploadTask]()
    
    private enum ScheduledBackupKind: Hashable, CustomDebugStringConvertible {
        case profile(ownedCryptoId: ObvCryptoId)
        case device
        var debugDescription: String {
            switch self {
            case .profile(let ownedCryptoId):
                return "profile(\(ownedCryptoId.debugDescription))"
            case .device:
                return "device"
            }
        }
    }
    
    private var scheduledBackupTask = [ScheduledBackupKind: Task<Void,Never>]()

    public init(prng: PRNGService, transactionAuthor: String, enableMigrations: Bool, containerURL: URL, appGroupIdentifier: String, physicalDeviceName: String, runningLog: RunningLogError) throws {
        ObvBackupManagerNewPersistentContainer.containerURL = containerURL
        self.prng = prng
        self.keychainManager = KeychainManager(appGroupIdentifier: appGroupIdentifier)
        self.databaseCoordinator = try BackupManagerDatabaseCoordinator(physicalDeviceName: physicalDeviceName,
                                                                        prng: prng,
                                                                        transactionAuthor: transactionAuthor,
                                                                        enableMigrations: enableMigrations,
                                                                        runningLog: runningLog)
    }

    
    public func finalizeInitialization(delegate: ObvBackupManagerNewDelegate) async throws {
        self.delegate = delegate
    }
    
}

// MARK: - Public API for boostrap

extension ObvBackupManagerNew {
    
    public func applicationAppearedOnScreen(forTheFirstTime: Bool, flowId: FlowIdentifier) async {
        if forTheFirstTime {
            Task {
                do {
                    try await deleteFromServerDeviceBackupOfInactiveDeviceBackupSeedsAndCleanupAllProfileBackupsIfAppropriate(flowId: flowId)
                } catch {
                    Self.logger.fault("Failed to delete from server device backup of inactive device backup seeds and cleanup all profile backups if appropriate: \(error)")
                    assertionFailure()
                }
            }
            Task {
                await rescheduleBackupsIfRequired()
            }
        }
    }
    
    
    public func deleteProfileBackupThreadsAssociatedToNonExistingOwnedIdentity(existingOwnedCryptoIds: Set<ObvCryptoId>, flowId: FlowIdentifier) async throws {
        
        let allProfileBackupThreadIds = try await databaseCoordinator.getAllProfileBackupThreadIds(flowId: flowId)
        let ownedCryptoIdsInBackupThreads = Set(allProfileBackupThreadIds.compactMap(\.ownedCryptoId))
        let toDelete = ownedCryptoIdsInBackupThreads.subtracting(existingOwnedCryptoIds)
        
        for ownedCryptoId in toDelete {
            do {
                try await databaseCoordinator.deletePersistedProfileBackupThreadId(ownedCryptoId: ownedCryptoId, flowId: flowId)
            } catch {
                assertionFailure() // Continue with the next
            }
        }

    }
    
    
}


// MARK: - Public API used to be notified that automatic backup is required

extension ObvBackupManagerNew {
        
    public func previousBackedUpDeviceSnapShotIsObsolete(flowId: FlowIdentifier) async {
        
        // Make sure backups are active
        
        do {
            guard try await getDeviceActiveBackupSeedAndServerURL(flowId: flowId) != nil else {
                Self.logger.info("Backups are not active, we will not schedule a device backup")
                return
            }
        } catch {
            Self.logger.fault("Could not check if backups are active, we will not schedule a device backup: \(error.localizedDescription)")
            assertionFailure()
            return
        }
        
        let backupToSchedule = ScheduledBackupKind.device
        
        if let previousTask = scheduledBackupTask.removeValue(forKey: backupToSchedule) {
            previousTask.cancel()
        }

        do {
            try await databaseCoordinator.setNextDeviceBackupUUID(flowId: flowId)
        } catch {
            Self.logger.fault("Could not set UUID of scheduled backup: \(error.localizedDescription)")
            assertionFailure()
        }

        scheduledBackupTask[backupToSchedule] = scheduleNewBackupTask(kind: backupToSchedule, flowId: flowId)
                
    }
    
    public func previousBackupOfOwnedIdentityIsObsolete(ownedCryptoId: ObvTypes.ObvCryptoId, flowId: FlowIdentifier) async {
        
        // Make sure backups are active
        
        do {
            guard try await getDeviceActiveBackupSeedAndServerURL(flowId: flowId) != nil else {
                Self.logger.info("Backups are not active, we will not schedule a device backup")
                return
            }
        } catch {
            Self.logger.fault("Could not check if backups are active, we will not schedule a device backup: \(error.localizedDescription)")
            assertionFailure()
            return
        }
        
        let backupToSchedule = ScheduledBackupKind.profile(ownedCryptoId: ownedCryptoId)

        if let previousTask = scheduledBackupTask.removeValue(forKey: backupToSchedule) {
            previousTask.cancel()
        }

        do {
            try await databaseCoordinator.setNextProfileBackupUUID(ownedCryptoId: ownedCryptoId, flowId: flowId)
        } catch {
            if let error = error as? SetNextProfileBackupUUIDOperation.ReasonForCancel {
                switch error {
                case .coreDataError(error: let error):
                    Self.logger.info("Could not set UUID of scheduled backup (this may happen right after a profile creation): \(error.localizedDescription)")
                    assertionFailure()
                }
            } else {
                Self.logger.info("Could not set UUID of scheduled backup (this may happen right after a profile creation): \(error.localizedDescription)")
                assertionFailure()
            }
        }

        scheduledBackupTask[backupToSchedule] = scheduleNewBackupTask(kind: backupToSchedule, flowId: flowId)

    }

}


// MARK: - Public API for performing backups

extension ObvBackupManagerNew {
    
    public func createDeviceBackupSeed(serverURLForStoringDeviceBackup: URL, physicalDeviceName: String, saveToKeychain: Bool, flowId: FlowIdentifier) async throws(ObvBackupManagerError.CreateDeviceBackupSeed) -> ObvCrypto.BackupSeed {

        Self.logger.info("Call to getOrCreateDeviceBackupSeed")
        
        let createdDeviceBackupSeed = try await databaseCoordinator.createDeviceBackupSeed(serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup, flowId: flowId)
        
        if saveToKeychain {
            
            do {
                try keychainManager.saveOrUpdateCurrentDeviceBackupSeedToKeychain(secAttrAccount: createdDeviceBackupSeed.secAttrAccount,
                                                                                  backupSeedAndStorageServerURL: createdDeviceBackupSeed.backupSeedAndStorageServerURL,
                                                                                  physicalDeviceName: physicalDeviceName)
            } catch {
                try? await databaseCoordinator.deletePersistedDeviceBackupSeed(backupSeed: createdDeviceBackupSeed.backupSeed, flowId: flowId)
                throw .keychain(error: error)
            }
        }
        
        // We created a device backup seed, we asynchronously launch a device and profiles backup before returning the device backup seed
        
        Task {
            do {
                try await createAndUploadDeviceAndProfilesBackupNow(flowId: flowId)
            } catch {
                Self.logger.fault("Failed to create and upload device and profile backups after creating the device backup seed: \(error.localizedDescription)")
                assertionFailure()
            }
        }
        
        return createdDeviceBackupSeed.backupSeed

    }
    
    
    /// Returns the current (active) physical device backup seed, if there is one.
    public func getDeviceActiveBackupSeedAndServerURL(flowId: FlowIdentifier) async throws(ObvBackupManagerError.GetDeviceActiveBackupSeedAndServerURL) -> ObvBackupSeedAndStorageServerURL? {
        return try await databaseCoordinator.getActiveDeviceBackupSeedStruct(flowId: flowId)?.backupSeedAndStorageServerURL
    }
    
    
    public func usersWantsToGetBackupParameterIsSynchronizedWithICloud(flowId: FlowIdentifier) async throws(ObvBackupManagerError.GetBackupParameterIsSynchronizedWithICloud) -> Bool {
        
        let secAttrAccount: String?
        do {
            secAttrAccount = try await databaseCoordinator.getActiveDeviceBackupSeedStruct(flowId: flowId)?.secAttrAccount
        } catch {
            assertionFailure()
            throw .getKeychainSecAttrAccount(error: error)
        }
        
        guard let secAttrAccount else {
            assertionFailure()
            throw .secAttrAccountIsNil
        }
        
        do {
            return try keychainManager.getBackupParameterIsSynchronizedWithICloud(secAttrAccount: secAttrAccount)
        } catch {
            throw .keychain(error: error)
        }
        
    }
    
    
    public func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(newIsSynchronizedWithICloud: Bool, physicalDeviceName: String, flowId: FlowIdentifier) async throws(ObvBackupManagerError.SetBackupParameterIsSynchronizedWithICloud) {
        
        do {
            guard try await usersWantsToGetBackupParameterIsSynchronizedWithICloud(flowId: flowId) != newIsSynchronizedWithICloud else { return }
        } catch {
            throw .get(error)
        }
        
        let secAttrAccount: String?
        do {
            secAttrAccount = try await databaseCoordinator.getActiveDeviceBackupSeedStruct(flowId: flowId)?.secAttrAccount
        } catch {
            assertionFailure()
            throw .getKeychainSecAttrAccount(error: error)
        }
        
        guard let secAttrAccount else {
            assertionFailure()
            throw .secAttrAccountIsNil
        }
        
        if newIsSynchronizedWithICloud {
            
            let backupSeedAndStorageServerURL: ObvBackupSeedAndStorageServerURL?
            do {
                backupSeedAndStorageServerURL = try await getDeviceActiveBackupSeedAndServerURL(flowId: flowId)
            } catch {
                throw .getDeviceActiveBackupSeedAndServerURL(error: error)
            }
            
            guard let backupSeedAndStorageServerURL else {
                throw .deviceBackupSeedIsNil
            }
            
            do {
                try keychainManager.saveOrUpdateCurrentDeviceBackupSeedToKeychain(secAttrAccount: secAttrAccount, backupSeedAndStorageServerURL: backupSeedAndStorageServerURL, physicalDeviceName: physicalDeviceName)
            } catch {
                throw .keychain(error: error)
            }
            
        } else {
            
            do {
                try keychainManager.deleteDeviceBackupSeedFromKeychain(secAttrAccount: secAttrAccount)
            } catch {
                throw .keychain(error: error)
            }
            
        }
        
    }

    
    /// This function is employed in scenarios where the user suspects or confirms their device backup seed has been compromised. In such an instance, they have the ability to request erasure of the existing device backup seed alongside
    /// its corresponding cloud-stored backup, succeeded by generation of a fresh device backup seed.
    public func userWantsToEraseAndGenerateNewDeviceBackupSeed(serverURLForStoringDeviceBackup: URL, physicalDeviceName: String, flowId: FlowIdentifier) async throws -> ObvCrypto.BackupSeed {
        
        let currentIsSynchronizedWithICloud = (try? await usersWantsToGetBackupParameterIsSynchronizedWithICloud(flowId: flowId)) ?? false

        // Deactivate the current device backup seed
        
        try await databaseCoordinator.deactivateAllPersistedDeviceBackupSeeds(flowId: flowId)

        // Create a new active device backup seed
        
        let newDeviceBackupSeed = try await createDeviceBackupSeed(serverURLForStoringDeviceBackup: serverURLForStoringDeviceBackup,
                                                                   physicalDeviceName: physicalDeviceName,
                                                                   saveToKeychain: currentIsSynchronizedWithICloud,
                                                                   flowId: flowId)

        // For all device backup seeds left in DB (probably 0 or 1), delete all backups from the cloud and remove the seed from the keychain if it exists.
        // This will not delete any profile backup, since there is an active device backup seed left (we just created it)
        
        try await deleteFromServerDeviceBackupOfInactiveDeviceBackupSeedsAndCleanupAllProfileBackupsIfAppropriate(flowId: flowId)
        
        // Return the fresh device backup seed
        
        return newDeviceBackupSeed
        
    }
    
    
    /// This method is called when the user wants to delete the current device backup seed alongside its corresponding cloud-stored backup.
    /// Since no new device keep is generated, this method also deletes all the profile cloud-stored backups.
    public func userWantsToResetThisDeviceSeedAndBackups(flowId: FlowIdentifier) async throws {

        // Deactivate the current device backup seed
        
        try await databaseCoordinator.deactivateAllPersistedDeviceBackupSeeds(flowId: flowId)
        
        // For all device backup seeds left in DB (probably 0 or 1), delete all backups from the cloud and remove the seed from the keychain if it exists.
        // This will certainly also delete all profile backups, since there is no active device backup seed left
        
        try await deleteFromServerDeviceBackupOfInactiveDeviceBackupSeedsAndCleanupAllProfileBackupsIfAppropriate(flowId: flowId)
        
    }
    
    
    public func createAndUploadDeviceAndProfilesBackupDuringBackgroundProcessing(flowId: FlowIdentifier) async throws {
                
        try await createAndUploadDeviceAndProfilesBackupNow(flowId: flowId)

    }
    
    
    public func userWantsToDeleteProfileBackup(infoForDeletion: ObvProfileBackupFromServer.InfoForDeletion, flowId: FlowIdentifier) async throws {
        
        Self.logger.info("[\(flowId.shortDebugDescription)] User requested the deletion of a profile backup")
        
        let deriveKeys = infoForDeletion.backupSeed.deriveKeysForNewBackup()
        
        try await deleteBackupFromServer(serverURL: infoForDeletion.serverURL,
                                         backupKeyUID: deriveKeys.backupKeyUID,
                                         threadUID: infoForDeletion.threadUID,
                                         backupVersion: infoForDeletion.backupVersion,
                                         authenticationKeyPair: deriveKeys.authenticationKeyPair,
                                         flowId: flowId)
        
        Self.logger.info("[\(flowId.shortDebugDescription)] Profile backup was deleted as requested by user")

    }

}


// MARK: - Public API for fetching backups from server

extension ObvBackupManagerNew {
    
    public func userWantsToFetchAllProfileBackupsFromServer(profileCryptoId: ObvCryptoId, backupSeedAndStorageServerURL: ObvBackupSeedAndStorageServerURL, flowId: FlowIdentifier) async throws -> [ObvProfileBackupFromServer] {
        let profileBackupsFromServer = try await fetchProfileBackupsFromServer(profileCryptoId: profileCryptoId, backupSeedAndStorageServerURL: backupSeedAndStorageServerURL, flowId: flowId)
        return profileBackupsFromServer
    }
    
    
    private enum BackupKind {
        case device
        case profiles
    }
    
    
    public func userWantsToUseDeviceBackupSeed(backupSeedAndStorageServerURL: ObvBackupSeedAndStorageServerURL, flowId: FlowIdentifier) async throws -> ObvTypes.ObvDeviceBackupFromServer? {
        let deviceBackupFromServer = try await fetchDeviceBackupFromServer(backupSeedAndStorageServerURL: backupSeedAndStorageServerURL, flowId: flowId)
        return deviceBackupFromServer
    }
    
    
    /// This method is invoked when the user requests a listing of restorable profiles. At this point, we retrieve all obtainable device backup seeds - those from the current device (stored in the database)
    /// as well as any found within the iCloud keychain. We utilize these seeds to download and decrypt device backups from the server. Each of these device backups encompasses a list of restorable profiles,
    /// accompanied by pertinent information needed for actual profile restoration - namely, the ownedCryptoId, profile backup seed, and serverURL.
    ///
    /// This is typically called before calling ``userWantsToFetchAllProfileBackupsFromServer(ownedCryptoId:backupSeedAndStorageServerURL:flowId:)``.
    public func userWantsToFetchDeviceBakupFromServer(flowId: FlowIdentifier) -> AsyncStream<ObvTypes.ObvDeviceBackupFromServerKind> {
        return AsyncStream(ObvDeviceBackupFromServerKind.self) { (continuation: AsyncStream<ObvDeviceBackupFromServerKind>.Continuation) in
            Task {
                await fetchDeviceBackupFromServerForBackupSeedOfCurrentDevice(flowId: flowId, continuation: continuation)
                await fetchDeviceBackupFromServerForBackupSeedsFoundInKeychain(flowId: flowId, continuation: continuation)
                continuation.finish()
            }
        }
    }
    
    
    /// Helper method for ``userWantsToFetchDeviceBakupFromServer(flowId:)``
    private func fetchDeviceBackupFromServerForBackupSeedOfCurrentDevice(flowId: FlowIdentifier, continuation: AsyncStream<ObvDeviceBackupFromServerKind>.Continuation) async {
        
        do {
            
            guard let backupSeedAndStorageServerURL = try await getDeviceActiveBackupSeedAndServerURL(flowId: flowId) else {
                // This typically happens when listing backups during the onboarding
                continuation.yield(.thisPhysicalDeviceHasNoBackupSeed)
                return
            }

            let deviceBackupFromServer = try await fetchDeviceBackupFromServer(backupSeedAndStorageServerURL: backupSeedAndStorageServerURL, flowId: flowId)

            continuation.yield(.thisPhysicalDevice(deviceBackupFromServer))
            return
            
        } catch {
            continuation.yield(.errorOccuredForFetchingBackupOfThisPhysicalDevice(error: error))
            return
        }
        
    }
    
    
    /// Helper method for ``userWantsToFetchDeviceBakupFromServer(flowId:)``
    private func fetchDeviceBackupFromServerForBackupSeedsFoundInKeychain(flowId: FlowIdentifier, continuation: AsyncStream<ObvDeviceBackupFromServerKind>.Continuation) async {
        
        do {
            
            let allBackupSeedAndStorageServerURLs = try await keychainManager.getAllBackupSeedAndStorageServerURLFoundInKeychain()
            
            guard !allBackupSeedAndStorageServerURLs.isEmpty else {
                return
            }

            let thisDeviceBackupSeedAndStorageServerURL = (try? await getDeviceActiveBackupSeedAndServerURL(flowId: flowId))
            
            let backupSeedAndStorageServerURLsToUse = allBackupSeedAndStorageServerURLs.filter({ $0 != thisDeviceBackupSeedAndStorageServerURL })

            for backupSeedAndStorageServerURL in backupSeedAndStorageServerURLsToUse {
                
                do {
                    let deviceBackupFromServer = try await fetchDeviceBackupFromServer(backupSeedAndStorageServerURL: backupSeedAndStorageServerURL, flowId: flowId)
                    continuation.yield(.keychain(deviceBackupFromServer))
                } catch {
                    continuation.yield(.errorOccuredForFetchingBackupsFromKeychain(error: error))
                }
                
            }
            
        } catch {
            continuation.yield(.errorOccuredForFetchingBackupsFromKeychain(error: error))
            return
        }
        
    }
    
    
    private func fetchProfileBackupsFromServer(profileCryptoId: ObvCryptoId, backupSeedAndStorageServerURL: ObvBackupSeedAndStorageServerURL, flowId: FlowIdentifier) async throws -> [ObvProfileBackupFromServer] {
        
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }

        let backupsToParse: [BackupToParse] = try await fetchAndDecryptAllBackupsFromServer(backupSeedAndStorageServerURL: backupSeedAndStorageServerURL, flowId: flowId, kind: .profiles)

        assert(!backupsToParse.isEmpty)
        
        var profileBackupsToParse = [ProfileBackupToParse]()
        
        for backupToParse in backupsToParse {
            guard let profileBackupSnapshot = ObvProfileBackupSnapshot(backupToParse.encodedSnapshotNode) else { assertionFailure(); continue }
            let backupMadeByThisDevice: Bool = (try? await databaseCoordinator.determineIfFetchedBackupWasMadeByThisDevice(ownedCryptoId: profileCryptoId, threadUID: backupToParse.threadUID, flowId: flowId)) ?? false
            let profileBackupToParse = ProfileBackupToParse(profileBackupSnapshot: profileBackupSnapshot,
                                                            backupSeed: backupToParse.backupSeed,
                                                            threadUID: backupToParse.threadUID,
                                                            version: backupToParse.version,
                                                            backupMadeByThisDevice: backupMadeByThisDevice)
            profileBackupsToParse.append(profileBackupToParse)
        }
        
        assert(profileBackupsToParse.count == backupsToParse.count)
        
        var profileBackupsFromServer = [ObvProfileBackupFromServer]()
        
        for profileBackupToParse in profileBackupsToParse {
            let profileBackupFromServer: ObvProfileBackupFromServer = try await delegate.parseProfileBackup(self, profileCryptoId: profileCryptoId, profileBackupToParse: profileBackupToParse, flowId: flowId)
            profileBackupsFromServer.append(profileBackupFromServer)
        }
        
        profileBackupsFromServer.sort(by: { $0.creationDate > $1.creationDate })
        
        return profileBackupsFromServer
        
    }
        
    
    private func fetchDeviceBackupFromServer(backupSeedAndStorageServerURL: ObvBackupSeedAndStorageServerURL, flowId: FlowIdentifier) async throws -> ObvDeviceBackupFromServer {
        
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }

        let backupsToParse: [BackupToParse] = try await fetchAndDecryptAllBackupsFromServer(backupSeedAndStorageServerURL: backupSeedAndStorageServerURL, flowId: flowId, kind: .device)

        assert(backupsToParse.count == 1 || backupsToParse.count == 0)
        
        guard let backupToParse = backupsToParse.first else {
            throw ObvError.deviceBackupFromServerNotFound
        }
        
        guard let deviceBackupSnapshot = ObvDictionary(backupToParse.encodedSnapshotNode) else {
            assertionFailure()
            throw ObvError.couldNotParseDecryptedDeviceBackup
        }
        
        let deviceBackupToParse = DeviceBackupToParse(deviceBackupSnapshot: deviceBackupSnapshot, version: backupToParse.version)

        let deviceBackupFromServer = try await delegate.parseDeviceBackup(self, deviceBackupToParse: deviceBackupToParse, flowId: flowId)
        
        return deviceBackupFromServer

    }
    
    
    /// Helper method for both
    /// ``fetchDeviceBackupFromServer(backupSeedAndStorageServerURL:flowId:)``
    /// and
    /// ``fetchProfileBackupsFromServer(backupSeedAndStorageServerURL:flowId:)``
    ///
    /// When `kind` is `.device`, this method returns a list with at most on device backup. If `kind` is `.profile`, the list can have multiple profile backups.
    private func fetchAndDecryptAllBackupsFromServer(backupSeedAndStorageServerURL: ObvBackupSeedAndStorageServerURL, flowId: FlowIdentifier, kind: BackupKind) async throws -> [BackupToParse] {
        
        let backupSeed = backupSeedAndStorageServerURL.backupSeed
        let serverURLForStoringDeviceBackup = backupSeedAndStorageServerURL.serverURLForStoringDeviceBackup

        let derivedKeys = backupSeed.deriveKeysForNewBackup()

        let listBackupsOnServerResult = try await listBackupsOnServer(server: serverURLForStoringDeviceBackup, backupKeyUID: derivedKeys.backupKeyUID, flowId: flowId)
        
        let allBackupsToDownloadAndDecrypt: [BackupToDownloadAndDecrypt]
        
        switch listBackupsOnServerResult {
            
        case .backupKeyUIDDoesNotExistOnServer:
            throw ObvError.deviceBackupFromServerNotFound
            
        case .backupKeyUIDExistsOnServer(backupsToDownloadAndDecrypt: let backupsToDownloadAndDecrypt):
            switch kind {
            case .device:
                guard let deviceBackupToDownloadAndDecrypt = backupsToDownloadAndDecrypt.first(where: { $0.threadUID == ObvBackupManagerConstant.deviceBackupThreadUID }) else {
                    return []
                }
                allBackupsToDownloadAndDecrypt = [deviceBackupToDownloadAndDecrypt]
            case .profiles:
                assert(backupsToDownloadAndDecrypt.map({ $0.threadUID }).allSatisfy({ $0 != ObvBackupManagerConstant.deviceBackupThreadUID }), "We don't expect to find the device backup thread UID when looking for profile backups")
                allBackupsToDownloadAndDecrypt = backupsToDownloadAndDecrypt.filter({ $0.threadUID != ObvBackupManagerConstant.deviceBackupThreadUID })
            }
        }

        // For each BackupToDownloadAndDecrypt, we download and decrypt a snapshot node of the device or profile backup
        
        var backupsToParse = [BackupToParse]()
        var oneOfTheErrors: Error?

        for backupToDownloadAndDecrypt in allBackupsToDownloadAndDecrypt {
            
            do {
                
                // Download the encrypted backup from the server
                
                let downloadURL = backupToDownloadAndDecrypt.downloadURL
                let (responseData, response) = try await URLSession.shared.data(from: downloadURL)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    assertionFailure()
                    throw ObvError.badHTTPURLResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
                }
                
                let encryptedDeviceBackup = EncryptedData(data: responseData)
                
                // Check and decrypt the encrypted backup
                
                let decryptedBackup = try AuthenticatedEncryption.decrypt(encryptedDeviceBackup,
                                                                          with: derivedKeys.encryptionKey)
                
                guard let encodedSnapshotNode = ObvEncoded(withPaddedRawData: decryptedBackup) else {
                    assertionFailure()
                    throw ObvError.couldNotParseDecryptedDeviceBackup
                }
                
                backupsToParse.append(BackupToParse(item: backupToDownloadAndDecrypt, encodedSnapshotNode: encodedSnapshotNode, backupSeed: backupSeed))
                
            } catch {
                Self.logger.fault("Failed to fetch and/or decrypt backup: \(error)")
                assertionFailure()
                oneOfTheErrors = error
                // We continue with the next backup
            }
            
        }
        
        // If we have no backup to return, and at least one backup failed to be fetched or parsed, we throw an error
        
        if backupsToParse.isEmpty, let oneOfTheErrors {
            throw oneOfTheErrors
        }

        return backupsToParse

    }

    
}


// MARK: - Private methods for scheduling backups

extension ObvBackupManagerNew {
    
    private func rescheduleBackupsIfRequired() async {
        
        let flowId = FlowIdentifier()
        
        do {
            if let previousFlowId = try await databaseCoordinator.getNextDeviceBackupUUID(flowId: flowId) {
                await previousBackedUpDeviceSnapShotIsObsolete(flowId: previousFlowId)
            }
        } catch {
            Self.logger.fault("Failed to re-schedule previous scheduled backup: \(error)")
            // Continue anyway
        }
        
        do {
            let previous = try await databaseCoordinator.getNextProfileBackupUUIDs(flowId: flowId)
            await withTaskGroup(of: Void.self) { taskGroup in
                for (ownedCryptoId, uuid) in previous {
                    taskGroup.addTask {
                        await self.previousBackupOfOwnedIdentityIsObsolete(ownedCryptoId: ownedCryptoId, flowId: uuid)
                    }
                }
            }
        } catch {
            Self.logger.fault("Failed to re-schedule previous scheduled backup: \(error)")
            // Continue anyway
        }

    }

    
    private func scheduleNewBackupTask(kind: ScheduledBackupKind, flowId: FlowIdentifier) -> Task<Void,Never> {
        
        return Task {
            
            // Wait for some time. This prevents performing several backups in a row.
            
            do {
                try await Task.sleep(seconds: 15) // This throws if the task is cancelled
            } catch {
                Self.logger.info("An obsolete scheduled backup task was cancelled (\(kind.debugDescription))")
                do {
                    switch kind {
                    case .profile(ownedCryptoId: let ownedCryptoId):
                        try await databaseCoordinator.removeNextProfileBackupUUID(ownedCryptoId: ownedCryptoId, flowIdToRemove: flowId)
                    case .device:
                        try await databaseCoordinator.removeNextDeviceBackupUUID(flowIdToRemove: flowId)
                    }
                } catch {
                    Self.logger.fault("Could not set UUID of scheduled backup: \(error.localizedDescription)")
                    assertionFailure()
                }
                return
            }
            
            do {
                switch kind {
                case .profile(let ownedCryptoId):
                    try await createAndUploadProfileBackupNow(ownedCryptoId: ownedCryptoId, flowId: flowId)
                case .device:
                    try await createAndUploadDeviceBackupNow(flowId: flowId)
                }
            } catch {
                Self.logger.fault("Could not finish schedule backup task (\(kind.debugDescription)): \(error.localizedDescription)")
                do {
                    switch kind {
                    case .profile(ownedCryptoId: let ownedCryptoId):
                        try await databaseCoordinator.removeNextProfileBackupUUID(ownedCryptoId: ownedCryptoId, flowIdToRemove: flowId)
                    case .device:
                        try await databaseCoordinator.removeNextDeviceBackupUUID(flowIdToRemove: flowId)
                    }
                } catch {
                    Self.logger.fault("Could not set UUID of scheduled backup: \(error.localizedDescription)")
                    assertionFailure()
                }
                assertionFailure()
            }
            
            do {
                switch kind {
                case .profile(ownedCryptoId: let ownedCryptoId):
                    try await databaseCoordinator.removeNextProfileBackupUUID(ownedCryptoId: ownedCryptoId, flowIdToRemove: flowId)
                case .device:
                    try await databaseCoordinator.removeNextDeviceBackupUUID(flowIdToRemove: flowId)
                }
            } catch {
                Self.logger.fault("Could not set UUID of scheduled backup: \(error.localizedDescription)")
                assertionFailure()
            }

            Self.logger.info("Scheduled backup task (\(kind.debugDescription)) is done")
            
        }

    }

}


// MARK: - Private methods for creating and uploading a device and all profiles backups

extension ObvBackupManagerNew {
    
    private func createAndUploadDeviceAndProfilesBackupNow(flowId: FlowIdentifier) async throws {
        
        // Backup the device
        
        do {
            try await createAndUploadDeviceBackupNow(flowId: flowId)
        } catch {
            Self.logger.fault("Failed to create and upload device backup: \(error)")
            assertionFailure()
        }
        
        // Backup the profiles
        
        let ownedCryptoIds: Set<ObvCryptoId>
        do {
            guard let delegate else { assertionFailure(); return }
            ownedCryptoIds = try await delegate.getAllActiveOwnedIdentities(self, flowId: flowId)
        } catch {
            Self.logger.fault("Failed to get active owned identities: \(error)")
            assertionFailure()
            return
        }
        
        for ownedCryptoId in ownedCryptoIds {
            do {
                try await createAndUploadProfileBackupNow(ownedCryptoId: ownedCryptoId, flowId: flowId)
            } catch {
                Self.logger.fault("Failed to backup profile: \(error)")
                assertionFailure() // Continue with the next profile
            }
        }
        
    }
    
}


// MARK: - Private methods for creating and uploading a profile backup

extension ObvBackupManagerNew {
    
    private func createAndUploadProfileBackupNow(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws {
        
        if let priorTask = profileBackupCreationAndUploadTaskInProgress[ownedCryptoId] {
            
            // A backup task is already in progress. Since it was created before our own call, we wait until it is done
            // before performing our own work
            
            try? await priorTask.value

            // Since this task was suspended while we were waiting for the end of the task launched prior our call, there might
            // be a new task in progress, created *after* our call.
            
            if let newTask = profileBackupCreationAndUploadTaskInProgress[ownedCryptoId], newTask != priorTask {
                
                // A backup task already exists. It was created *after* our call to this method so we can
                // simply await until it is done.
                
                try await newTask.value
                
            } else {
                
                // No backup task was created. So we create one, save it in order to make it accessible to other calls to this method.
                
                let newTask = createTaskToCreateAndUploadProfileBackupTask(ownedCryptoId: ownedCryptoId, flowId: flowId)
                self.profileBackupCreationAndUploadTaskInProgress[ownedCryptoId] = newTask

                try await newTask.value
                
                if self.profileBackupCreationAndUploadTaskInProgress[ownedCryptoId] == newTask {
                    self.profileBackupCreationAndUploadTaskInProgress[ownedCryptoId] = nil
                }

            }

        } else {
            
            // No backup task in progress. So we create one, save it in order to make it accessible to other calls to this method.
            
            let newTask = createTaskToCreateAndUploadProfileBackupTask(ownedCryptoId: ownedCryptoId, flowId: flowId)
            self.profileBackupCreationAndUploadTaskInProgress[ownedCryptoId] = newTask

            try await newTask.value
            
            if self.profileBackupCreationAndUploadTaskInProgress[ownedCryptoId] == newTask {
                self.profileBackupCreationAndUploadTaskInProgress[ownedCryptoId] = nil
            }

        }

    }

    
    private func createTaskToCreateAndUploadProfileBackupTask(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) -> DeviceBackupCreationAndUploadTask {
        return Task {
            try await createAndUploadProfileBackupTask(ownedCryptoId: ownedCryptoId, flowId: flowId)
        }
    }

    
    /// Shall only be called from ``createTaskToCreateAndUploadProfileBackupTask(ownedCryptoId:flowId:)``
    private func createAndUploadProfileBackupTask(ownedCryptoId: ObvCryptoId, flowId: FlowIdentifier) async throws(ObvBackupManagerError.CreateAndUploadProfileBackupTask) {
        
        guard let delegate else {
            assertionFailure()
            throw .delegateIsNil
        }
        
        let profileBackupThreadUID: UID
        do {
            profileBackupThreadUID = try await databaseCoordinator.getOrCreateProfileBackupThreadUIDForOwnedCryptoId(ownedCryptoId: ownedCryptoId, flowId: flowId)
        } catch {
            assertionFailure()
            throw .getOrCreateProfileBackupThreadUIDForOwnedCryptoId(error: error)
        }
        
        let server = ownedCryptoId.cryptoIdentity.serverURL
        
        let profileBackupSeed: BackupSeed?
        do {
            profileBackupSeed = try await delegate.getBackupSeedOfOwnedIdentity(self, ownedCryptoId: ownedCryptoId, restrictToActive: true, flowId: flowId)
        } catch {
            throw .otherError(error: error)
        }
        
        guard let profileBackupSeed else {
            assertionFailure("This happens if the owned identity does not exist in database")
            throw .profileBackupSeedIsNil
        }
        
        let derivedKeys = profileBackupSeed.deriveKeysForNewBackup()
        
        //
        // List existing backups
        //
                
        let listBackupsOnServerResult: ListBackupsOnServerResult
        do {
            listBackupsOnServerResult = try await listBackupsOnServer(server: server, backupKeyUID: derivedKeys.backupKeyUID, flowId: flowId)
        } catch {
            throw .listBackupsOnServerError(error: error)
        }

        //
        // If the backupKeyUID does not exist on the server, create it. Otherwise, use the backup found (if any) to determine the future backup version
        //
        
        let nextVersion: Int
        
        switch listBackupsOnServerResult {
            
        case .backupKeyUIDDoesNotExistOnServer:
            
            do {
                try await createBackupKeyUIDOnServer(server: server, backupKeyUID: derivedKeys.backupKeyUID, publicKey: derivedKeys.authenticationKeyPair.publicKey, flowId: flowId)
            } catch {
                throw .createBackupKeyUIDOnServerError(error: error)
            }

            nextVersion = Date.now.timeIntervalSince1970.toMilliseconds
            
        case .backupKeyUIDExistsOnServer(backupsToDownloadAndDecrypt: let backupsToDownloadAndDecrypt):

            // Restrict the profile's backup
            let previousProfileBackups = backupsToDownloadAndDecrypt.filter({ $0.threadUID == profileBackupThreadUID })

            nextVersion = ((previousProfileBackups.map(\.version).max()) ?? 1) + 1
            
        }
        
        //
        // Create a new profile snapshot
        //
        
        let profileSnapshotNode: ObvDictionary
        do {
            profileSnapshotNode = try await delegate.getProfileSnapshotNodeAsObvDictionary(self, ownedCryptoId: ownedCryptoId)
        } catch {
            throw .failedToCreateProfileSnapshotNode(error: error)
        }

        //
        // Get the additional infos
        //
        
        let additionalInfosForProfileBackup: AdditionalInfosForProfileBackup
        do {
            additionalInfosForProfileBackup = try await delegate.getAdditionalInfosForProfileBackup(self, ownedCryptoId: ownedCryptoId, flowId: flowId)
        } catch {
            throw .failedToGetAdditionalInfosForProfileBackup(error: error)
        }
        
        //
        // Create the `ObvProfileBackupSnapshot`
        //
        
        let profileBackupSnapshot = ObvProfileBackupSnapshot(profileSnapshotNode: profileSnapshotNode, additionalInfosForProfileBackup: additionalInfosForProfileBackup)
        
        //
        // Encode, pad to a multiple of 512 bytes, encrypt, and sign
        //
        
        let plaintextContent: Data
        do {
            plaintextContent = try profileBackupSnapshot.obvEncode().rawData
        } catch {
            throw .encodingError(error: error)
        }
        guard plaintextContent.count > 0 else {
            throw .deviceBackupSnapshotSizeError
        }
        let paddedPlaintextContentCount: Int = ((plaintextContent.count-1) | 511) + 1
        let paddedPlaintextContent: Data = plaintextContent + Data(repeating: 0x00, count: max(0, paddedPlaintextContentCount - plaintextContent.count))
        assert(paddedPlaintextContent.count % 512 == 0)
        
        let encryptedBackup = AuthenticatedEncryption.encrypt(paddedPlaintextContent,
                                                              with: derivedKeys.encryptionKey,
                                                              and: prng)

        let signaturePayload: Data
        do {
            signaturePayload = try await delegate.solveChallengeForBackupUpload(self,
                                                                                backupKeyUID: derivedKeys.backupKeyUID,
                                                                                deviceOrProfileBackupThreadUID: profileBackupThreadUID,
                                                                                backupVersion: nextVersion,
                                                                                encryptedBackup: encryptedBackup,
                                                                                authenticationKeyPair: derivedKeys.authenticationKeyPair)
        } catch {
            assertionFailure()
            throw .signatureGenerationFailed(error: error)
        }

        
        //
        // Upload the encrypted snapshot to the server
        //

        do {
            try await uploadBackupToServer(serverURL: server,
                                           backupKeyUID: derivedKeys.backupKeyUID,
                                           threadUID: profileBackupThreadUID,
                                           backupVersion: nextVersion,
                                           encryptedBackup: encryptedBackup,
                                           signature: signaturePayload,
                                           flowId: flowId)
        } catch {
            assertionFailure()
            throw .uploadBackupToServerError(error: error)
        }
        
        debugPrint("Done")

    }
    
    
    
}


// MARK: - Private methods for creating and uploading a device backup

extension ObvBackupManagerNew {
    
    private func createAndUploadDeviceBackupNow(flowId: FlowIdentifier) async throws {
        
        if let priorTask = deviceBackupCreationAndUploadTaskInProgress {
            
            // A backup task is alreafy in progress. Since it was created before our own call, we wait until it is done
            // before performing our own work
            
            try? await priorTask.value

            // Since this task was suspended while we were waiting for the end of the task launched prior our call, there might
            // be a new task in progress, created *after* our call.
            
            if let newTask = deviceBackupCreationAndUploadTaskInProgress, newTask != priorTask {
                
                // A backup task already exists. It was created *after* our call to this method so we can
                // simply await until it is done.
                
                try await newTask.value
                
            } else {
                
                // No backup task was created. So we create one, save it in order to make it accessible to other calls to this method.
                
                let newTask = createTaskToCreateAndUploadDeviceBackup(flowId: flowId)
                self.deviceBackupCreationAndUploadTaskInProgress = newTask

                try await newTask.value
                
                if self.deviceBackupCreationAndUploadTaskInProgress == newTask {
                    self.deviceBackupCreationAndUploadTaskInProgress = nil
                }

            }

        } else {
            
            // No backup task in progress. So we create one, save it in order to make it accessible to other calls to this method.
            
            let newTask = createTaskToCreateAndUploadDeviceBackup(flowId: flowId)
            self.deviceBackupCreationAndUploadTaskInProgress = newTask

            try await newTask.value
            
            if self.deviceBackupCreationAndUploadTaskInProgress == newTask {
                self.deviceBackupCreationAndUploadTaskInProgress = nil
            }

        }

    }
    
    
    /// Should only be called from ``createAndUploadDeviceBackupNow(flowId:)``
    private func createTaskToCreateAndUploadDeviceBackup(flowId: FlowIdentifier) -> DeviceBackupCreationAndUploadTask {
        return Task {
            try await createAndUploadDeviceBackupTask(flowId: flowId)
        }
    }
    
    
    /// Should only be called from ``createTaskToCreateAndUploadDeviceBackup(flowId:)``
    private func createAndUploadDeviceBackupTask(flowId: FlowIdentifier) async throws(ObvBackupManagerError.CreateAndUploadDeviceBackupTask) {
        
        guard let delegate else {
            assertionFailure()
            throw .delegateIsNil
        }
        
        let deviceBackupSeedAndStorageServerURL: ObvBackupSeedAndStorageServerURL?
        do {
            deviceBackupSeedAndStorageServerURL = try await getDeviceActiveBackupSeedAndServerURL(flowId: flowId)
        } catch {
            assertionFailure()
            throw .getDeviceActiveBackupSeedAndServerURL(error: error)
        }
        
        guard let deviceBackupSeedAndStorageServerURL else {
            assertionFailure()
            throw .deviceBackupSeedIsNil
        }
        
        let deviceBackupSeed = deviceBackupSeedAndStorageServerURL.backupSeed
        let serverURLForStoringDeviceBackup = deviceBackupSeedAndStorageServerURL.serverURLForStoringDeviceBackup
        
        let derivedKeys = deviceBackupSeed.deriveKeysForNewBackup()

        //
        // Check that there is at least one active owned identity
        //
        
        do {
            guard try await delegate.hasActiveOwnedIdentities(self) else {
                throw ObvError.noActiveOwnedIdentityToBackup
            }
        } catch {
            throw .delegateError(error: error)
        }
        
        //
        // List existing backups
        //
                
        let listBackupsOnServerResult: ListBackupsOnServerResult
        do {
            listBackupsOnServerResult = try await listBackupsOnServer(server: serverURLForStoringDeviceBackup, backupKeyUID: derivedKeys.backupKeyUID, flowId: flowId)
        } catch {
            throw .listBackupsOnServerError(error: error)
        }
        
        //
        // If the backupKeyUID does not exist on the server, create it. Otherwise, use the backup found (if any) to determine the future backup version
        //
        
        let nextVersion: Int
        
        switch listBackupsOnServerResult {
            
        case .backupKeyUIDDoesNotExistOnServer:
            
            do {
                try await createBackupKeyUIDOnServer(server: serverURLForStoringDeviceBackup, backupKeyUID: derivedKeys.backupKeyUID, publicKey: derivedKeys.authenticationKeyPair.publicKey, flowId: flowId)
            } catch {
                throw .createBackupKeyUIDOnServerError(error: error)
            }

            nextVersion = Date.now.timeIntervalSince1970.toMilliseconds
            
        case .backupKeyUIDExistsOnServer(backupsToDownloadAndDecrypt: let backupsToDownloadAndDecrypt):
            // If there is one, we extract the only device backup from the list of backup items
            let previousBackup = backupsToDownloadAndDecrypt.first(where: { $0.threadUID == ObvBackupManagerConstant.deviceBackupThreadUID })
            if let previousVersion = previousBackup?.version {
                nextVersion = previousVersion + 1
            } else {
                nextVersion = Date.now.timeIntervalSince1970.toMilliseconds
            }
            
        }
        
        //
        // Create a new snapshot
        //
        
        let deviceSnapshotNode: ObvDictionary
        do {
            deviceSnapshotNode = try await delegate.getDeviceSnapshotNodeAsObvDictionary(self)
        } catch {
            throw .failedToCreateDeviceSnapshotNode(error: error)
        }
                
        //
        // Encode, pad to a multiple of 512 bytes, encrypt, and sign
        //
        
        let plaintextContent: Data = deviceSnapshotNode.obvEncode().rawData
        guard plaintextContent.count > 0 else {
            throw .deviceBackupSnapshotSizeError
        }
        let paddedPlaintextContentCount: Int = ((plaintextContent.count-1) | 511) + 1
        let paddedPlaintextContent: Data = plaintextContent + Data(repeating: 0x00, count: max(0, paddedPlaintextContentCount - plaintextContent.count))
        assert(paddedPlaintextContent.count % 512 == 0)
        
        let encryptedBackup = AuthenticatedEncryption.encrypt(paddedPlaintextContent,
                                                              with: derivedKeys.encryptionKey,
                                                              and: prng)

        let signaturePayload: Data
        do {
            signaturePayload = try await delegate.solveChallengeForBackupUpload(
                self,
                backupKeyUID: derivedKeys.backupKeyUID,
                deviceOrProfileBackupThreadUID: ObvBackupManagerConstant.deviceBackupThreadUID,
                backupVersion: nextVersion,
                encryptedBackup: encryptedBackup,
                authenticationKeyPair: derivedKeys.authenticationKeyPair)
        } catch {
            assertionFailure()
            throw .signatureGenerationFailed(error: error)
        }
                                                
        //
        // Upload the encrypted snapshot to the server
        //

        do {
            try await uploadBackupToServer(serverURL: serverURLForStoringDeviceBackup,
                                           backupKeyUID: derivedKeys.backupKeyUID,
                                           threadUID: ObvBackupManagerConstant.deviceBackupThreadUID,
                                           backupVersion: nextVersion,
                                           encryptedBackup: encryptedBackup,
                                           signature: signaturePayload,
                                           flowId: flowId)
        } catch {
            assertionFailure()
            throw .uploadBackupToServerError(error: error)
        }
        
        debugPrint("Done")
        
    }
    
    
    private func uploadBackupToServer(serverURL: URL, backupKeyUID: UID, threadUID: UID, backupVersion: Int, encryptedBackup: EncryptedData, signature: Data, flowId: FlowIdentifier) async throws(UploadBackupToServerError) {
        
        let method = ObvServerBackupUploadMethod(serverURL: serverURL,
                                                 backupKeyUID: backupKeyUID,
                                                 threadUID: threadUID,
                                                 backupVersion: backupVersion,
                                                 encryptedBackup: encryptedBackup,
                                                 signature: signature,
                                                 flowId: flowId)
        
        // Since the request of a upload task should not contain a body or a body stream, we use URLSession.upload(for:from:), passing the data to send via the `from` attribute.
        let dataToSend = method.dataToSendNonNil
        method.dataToSend = nil
        let urlRequest: URLRequest
        do {
            urlRequest = try method.getURLRequest()
        } catch {
            throw .urlRequestError(error: error)
        }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.upload(for: urlRequest, from: dataToSend)
        } catch {
            throw .uploadError(error: error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            assertionFailure()
            throw .badHTTPURLResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        
        let status: ObvServerBackupUploadMethod.PossibleReturnStatus
        do {
            status = try ObvServerBackupUploadMethod.parseObvServerResponse(responseData: responseData, using: Self.log)
        } catch {
            throw .serverResponseParseError(error: error)
        }

        switch status {
        case .invalidSignature:
            assertionFailure()
            throw .invalidSignature
        case .backupVersionTooSmall:
            assertionFailure()
            throw .backupVersionTooSmall
        case .unknownBackupKeyUID:
            assertionFailure()
            throw .backupKeyUIDDoesNotExistOnServer
        case .parsingError:
            Self.logger.error("Failed to create first backup: the server returned a parsing error")
            assertionFailure()
            throw .serverQueryFailed
        case .generalError:
            Self.logger.error("Failed to create first backup: the server returned a parsing error")
            assertionFailure()
            throw .serverQueryFailed
        case .ok:
            Self.logger.info("Backup was successfully uploaded to the server")
        }
                
    }
    
    
    private func createBackupKeyUIDOnServer(server: URL, backupKeyUID: UID, publicKey: any PublicKeyForAuthentication, flowId: FlowIdentifier) async throws(CreateBackupKeyUIDOnServerError) {
        
        let method = ObvServerCreateBackupMethod(serverURL: server,
                                                 backupKeyUID: backupKeyUID,
                                                 authenticationPublicKey: publicKey,
                                                 flowId: flowId)
        
        // Since the request of a upload task should not contain a body or a body stream, we use URLSession.upload(for:from:), passing the data to send via the `from` attribute.
        let dataToSend = method.dataToSendNonNil
        method.dataToSend = nil
        let urlRequest: URLRequest
        do {
            urlRequest = try method.getURLRequest()
        } catch {
            throw .urlRequestError(error: error)
        }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.upload(for: urlRequest, from: dataToSend)
        } catch {
            throw .uploadError(error: error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            assertionFailure()
            throw .badHTTPURLResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        
        let status: ObvServerCreateBackupMethod.PossibleReturnStatus
        do {
            status = try ObvServerCreateBackupMethod.parseObvServerResponse(responseData: responseData, using: Self.log)
        } catch {
            throw .serverResponseParseError(error: error)
        }

        switch status {
        case .backupUIDAlreadyUsed:
            throw .backupUIDAlreadyUsed
        case .parsingError:
            Self.logger.error("Failed to create first backup: the server returned a parsing error")
            assertionFailure()
            throw .serverQueryFailed
        case .generalError:
            Self.logger.error("Failed to create first backup: the server returned a general error")
            assertionFailure()
            throw .serverQueryFailed
        case .ok:
            Self.logger.info("Device backup UID created on server")
        }
        
    }
    
    enum ListBackupsOnServerResult {
        case backupKeyUIDDoesNotExistOnServer
        case backupKeyUIDExistsOnServer(backupsToDownloadAndDecrypt: [BackupToDownloadAndDecrypt])
    }
    
    private func listBackupsOnServer(server: URL, backupKeyUID: UID, flowId: FlowIdentifier) async throws(ListBackupsOnServerError) -> ListBackupsOnServerResult {
        
        let method = ObvServerBackupListMethod(serverURL: server, backupKeyUID: backupKeyUID, flowId: flowId)
        
        // Since the request of a upload task should not contain a body or a body stream, we use URLSession.upload(for:from:), passing the data to send via the `from` attribute.
        let dataToSend = method.dataToSendNonNil
        method.dataToSend = nil
        let urlRequest: URLRequest
        do {
            urlRequest = try method.getURLRequest()
        } catch {
            throw .urlRequestError(error: error)
        }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.upload(for: urlRequest, from: dataToSend)
        } catch {
            throw .uploadError(error: error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            assertionFailure()
            throw .badHTTPURLResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        
        let status: ObvServerBackupListMethod.PossibleReturnStatus
        do {
            status = try ObvServerBackupListMethod.parseObvServerResponse(responseData: responseData, using: Self.log)
        } catch {
            throw .serverResponseParseError(error: error)
        }

        let result: ListBackupsOnServerResult
        
        switch status {
        case .generalError:
            Self.logger.error("Failed to list backups: the server returned a general error")
            assertionFailure()
            throw .serverQueryFailed
        case .unknownBackupKeyUID:
            Self.logger.info("Server returned that the backup key UID is unknown (normal for the first backup)")
            result = .backupKeyUIDDoesNotExistOnServer
        case .parsingError:
            Self.logger.error("Failed to list backups: the server returned a parsing error")
            assertionFailure()
            throw .serverQueryFailed
        case .ok(backupsToDownloadAndDecrypt: let backupsToDownloadAndDecrypt):
            Self.logger.info("ObvServerBackupListServerMethod success")
            result = .backupKeyUIDExistsOnServer(backupsToDownloadAndDecrypt: backupsToDownloadAndDecrypt)
        }
        
        return result

    }
    
}


// MARK: - Private methods for deleting backups

extension ObvBackupManagerNew {
    
    /// Fetches all inactive device backup seeds and, for each one found, deletes the corresponding device backup from the cloud. At the end, the inactive backup seeds are deleted.
    /// If there is no more active backup seed at the end, this method also delete all profile backups from the server.
    private func deleteFromServerDeviceBackupOfInactiveDeviceBackupSeedsAndCleanupAllProfileBackupsIfAppropriate(flowId: FlowIdentifier) async throws {
        
        let allInactiveDeviceBackupSeeds = try await databaseCoordinator.getAllInactiveDeviceBackupSeeds(flowId: flowId)
        
        for inactiveDeviceBackupSeed in allInactiveDeviceBackupSeeds {
            try await deleteFromServerDeviceBackup(backupSeed: inactiveDeviceBackupSeed.backupSeed, flowId: flowId)
            try keychainManager.deleteDeviceBackupSeedFromKeychain(secAttrAccount: inactiveDeviceBackupSeed.secAttrAccount)
        }
        
        // Remove the inactive device backup seed from database

        try await databaseCoordinator.deleteAllInactiveDeviceBackupSeeds(flowId: flowId)

        // If there is no active backup key, delete all profile backups
        
        if try await databaseCoordinator.getActiveDeviceBackupSeedStruct(flowId: flowId) == nil {
            try await deleteFromServerAllProfileBackupsMadeByThisDevice(flowId: flowId)
        }

    }
    
    
    
    private func deleteFromServerDeviceBackup(backupSeed: BackupSeed, flowId: FlowIdentifier) async throws {

        var iteration = 0
        let maxIterations = 10
        
        while iteration < maxIterations {
            
            iteration += 1
            
            do {
                
                guard let backupSeedAndStorageServerURL = try await databaseCoordinator.getDeviceBackupSeedAndServerURL(backupSeed: backupSeed, flowId: flowId) else {
                    // The seed was deleted, there is nothing left to do
                    return
                }
                
                let serverURLForStoringDeviceBackup = backupSeedAndStorageServerURL.serverURLForStoringDeviceBackup
                let deviceDerivedKeys = backupSeed.deriveKeysForNewBackup()
                let deviceBackupKeyUID = deviceDerivedKeys.backupKeyUID
                let deviceAuthenticationKeyPair = deviceDerivedKeys.authenticationKeyPair
                
                // List the backups and delete the device backup found (if any)
                
                let listOfBackups = try await listBackupsOnServer(server: backupSeedAndStorageServerURL.serverURLForStoringDeviceBackup, backupKeyUID: deviceBackupKeyUID, flowId: flowId)
                
                switch listOfBackups {
                    
                case .backupKeyUIDDoesNotExistOnServer:
                    // There is no device backup to delete, we can proceed.
                    break
                    
                case .backupKeyUIDExistsOnServer(backupsToDownloadAndDecrypt: let backupsToDownloadAndDecrypt):
                    // Look for a device backup in the list (we expect at most 1)
                    let deviceBackups: [BackupToDownloadAndDecrypt] = backupsToDownloadAndDecrypt.filter( { $0.threadUID == ObvBackupManagerConstant.deviceBackupThreadUID } )
                    assert(deviceBackups.count == 0 || deviceBackups.count == 1)
                    for deviceBackup in deviceBackups {
                        try await deleteBackupFromServer(deviceBackup, serverURL: serverURLForStoringDeviceBackup, backupKeyUID: deviceBackupKeyUID, authenticationKeyPair: deviceAuthenticationKeyPair, flowId: flowId)
                    }
                    
                }
                
                // If we reach this point, the cleanup was successful
                
                return
                
            } catch {
                
                assertionFailure()
                if iteration == maxIterations {
                    throw error
                } else {
                    try await Task.sleep(seconds: Double.random(in: 0..<1))
                }
                
            }
            
        }
        
        
    }
    
    
    private func deleteFromServerAllProfileBackupsMadeByThisDevice(flowId: FlowIdentifier) async throws {
        
        guard let delegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }

        var iteration = 0
        let maxIterations = 10

        while iteration < maxIterations {
            
            iteration += 1
            
            do {
                
                let allProfileBackupThreadIds = try await databaseCoordinator.getAllProfileBackupThreadIds(flowId: flowId)
                
                for (ownedCryptoId, profileBackupThreadUID) in allProfileBackupThreadIds {
                    
                    guard let profileBackupSeed = try await delegate.getBackupSeedOfOwnedIdentity(self, ownedCryptoId: ownedCryptoId, restrictToActive: false, flowId: flowId) else {
                        // This profile has no backup seed, there is nothing to delete. Continue with the next one
                        continue
                    }
                    
                    let serverURL = ownedCryptoId.cryptoIdentity.serverURL
                    let profileDerivedKeys = profileBackupSeed.deriveKeysForNewBackup()
                    let profileBackupKeyUID = profileDerivedKeys.backupKeyUID
                    let profileAuthenticationKeyPair = profileDerivedKeys.authenticationKeyPair
                    
                    // List the profile backups
                    
                    let listOfBackups = try await listBackupsOnServer(server: serverURL, backupKeyUID: profileBackupKeyUID, flowId: flowId)
                    
                    switch listOfBackups {
                        
                    case .backupKeyUIDDoesNotExistOnServer:
                        // There is no profile backup to delete, we can proceed.
                        break
                        
                    case .backupKeyUIDExistsOnServer(backupsToDownloadAndDecrypt: let backupsToDownloadAndDecrypt):
                        // Look for a profile backup in the list (we expect at most 1)
                        let profileBackups = backupsToDownloadAndDecrypt.filter( { $0.threadUID == profileBackupThreadUID } )
                        assert(profileBackups.count == 0 || profileBackups.count == 1)
                        for profileBackup in profileBackups {
                            try await deleteBackupFromServer(profileBackup, serverURL: serverURL, backupKeyUID: profileBackupKeyUID, authenticationKeyPair: profileAuthenticationKeyPair, flowId: flowId)
                        }
                        
                    }
                    
                }
                
                // If we reach this point, the cleanup was successful
                
                return
                
            } catch {
                
                assertionFailure()
                try await Task.sleep(seconds: 1)

            }
            
        }
    }
    
    
    /// Helper method of ``deleteDeviceBackupFromServer(backupSeed:flowId:)``.
    private func deleteBackupFromServer(_ deviceBackup: BackupToDownloadAndDecrypt, serverURL: URL, backupKeyUID: UID, authenticationKeyPair: (publicKey: any PublicKeyForAuthentication, privateKey: any PrivateKeyForAuthentication), flowId: FlowIdentifier) async throws {
        
        try await deleteBackupFromServer(serverURL: serverURL, backupKeyUID: backupKeyUID, threadUID: deviceBackup.threadUID, backupVersion: deviceBackup.version, authenticationKeyPair: authenticationKeyPair, flowId: flowId)
        
    }
    
    
    /// Helper method for ``deleteBackupFromServer(_:serverURL:backupKeyUID:authenticationKeyPair:flowId:)`` and when the user requests the deletion of a specific profile backup.
    private func deleteBackupFromServer(serverURL: URL, backupKeyUID: UID, threadUID: UID, backupVersion: Int, authenticationKeyPair: (publicKey: any PublicKeyForAuthentication, privateKey: any PrivateKeyForAuthentication), flowId: FlowIdentifier) async throws(DeleteBackupFromServerError) {
        
        
        guard let delegate else {
            assertionFailure()
            throw .delegateIsNil
        }
        
        let signaturePayload: Data
        do {
            signaturePayload = try await delegate.solveChallengeForBackupDelete(self,
                                                                                backupKeyUID: backupKeyUID,
                                                                                deviceOrProfileBackupThreadUID: threadUID,
                                                                                backupVersion: backupVersion,
                                                                                authenticationKeyPair: authenticationKeyPair)
        } catch {
            assertionFailure()
            throw .signatureGenerationFailed(error: error)
        }

        
        try await deleteBackupFromServer(serverURL: serverURL, backupKeyUID: backupKeyUID, threadUID: threadUID, backupVersion: backupVersion, signature: signaturePayload, flowId: flowId)
        
    }
    
    
    /// Helper method for ``deleteBackupFromServer(serverURL:backupKeyUID:threadUID:backupVersion:authenticationKeyPair:flowId:)``.
    private func deleteBackupFromServer(serverURL: URL, backupKeyUID: UID, threadUID: UID, backupVersion: Int, signature: Data, flowId: FlowIdentifier) async throws(DeleteBackupFromServerError) {
        
        let method = ObvServerBackupDeleteMethod(serverURL: serverURL, backupKeyUID: backupKeyUID, threadUID: threadUID, backupVersion: backupVersion, signature: signature, flowId: flowId)
     
        // S ince the request of a upload task should not contain a body or a body stream, we use URLSession.upload(for:from:), passing the data to send via the `from` attribute.
        let dataToSend = method.dataToSendNonNil
        method.dataToSend = nil
        let urlRequest: URLRequest
        do {
            urlRequest = try method.getURLRequest()
        } catch {
            throw .urlRequestError(error: error)
        }

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await URLSession.shared.upload(for: urlRequest, from: dataToSend)
        } catch {
            throw .uploadError(error: error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            assertionFailure()
            throw .badHTTPURLResponse(statusCode: (response as? HTTPURLResponse)?.statusCode)
        }
        
        let status: ObvServerBackupDeleteMethod.PossibleReturnStatus
        do {
            status = try ObvServerBackupDeleteMethod.parseObvServerResponse(responseData: responseData, using: Self.log)
        } catch {
            throw .serverResponseParseError(error: error)
        }

        switch status {
        case .ok:
            return
        case .invalidSignature:
            assertionFailure()
            throw .invalidSignature
        case .unknownBackupKeyUID:
            assertionFailure()
            return
        case .unknownThreadUID:
            assertionFailure()
            return
        case .unknownBackupVersion:
            assertionFailure()
            return
        case .parsingError:
            assertionFailure()
            throw .serverQueryFailed
        case .generalError:
            assertionFailure()
            throw .serverQueryFailed
        }

    }
    
}


// MARK: - Errors

enum GetOrCreateThreadUIDForOwnedCryptoIdError: Error {
    case unknownError
    case otherError(error: Error)
}

public enum UploadBackupToServerError: Error {
    case urlRequestError(error: Error)
    case uploadError(error: Error)
    case badHTTPURLResponse(statusCode: Int?)
    case serverResponseParseError(error: Error)
    case invalidSignature
    case backupVersionTooSmall
    case backupKeyUIDDoesNotExistOnServer
    case serverQueryFailed
}

public enum CreateBackupKeyUIDOnServerError: Error {
    case urlRequestError(error: Error)
    case uploadError(error: Error)
    case badHTTPURLResponse(statusCode: Int?)
    case serverResponseParseError(error: Error)
    case backupUIDAlreadyUsed
    case serverQueryFailed
}

public enum ListBackupsOnServerError: Error {
    case urlRequestError(error: Error)
    case uploadError(error: Error)
    case badHTTPURLResponse(statusCode: Int?)
    case serverResponseParseError(error: Error)
    case serverQueryFailed
}

enum DeleteBackupFromServerError: Error {
    case urlRequestError(error: Error)
    case uploadError(error: Error)
    case badHTTPURLResponse(statusCode: Int?)
    case serverResponseParseError(error: Error)
    case invalidSignature
    case serverQueryFailed
    case delegateIsNil
    case signatureGenerationFailed(error: Error)
}

enum CreateAndUploadDeviceBackupError: Error {
    case noActiveDeviceBackupSeed
}



public enum ObvError: Error {
    case coreDataStackIsNil
    case couldNotParseBackupSeed
    case couldNotParseServerURL
    case coreDataError(error: Error)
    case otherError(error: Error)
    case anActivePersistedDeviceBackupSeedAlreadyExists
    case deviceBackupSeedIsNil
    case unknownError
    case delegateIsNil
    case delegateError(error: Error)
    case noActiveOwnedIdentityToBackup
    case listBackupsOnServerError(error: ListBackupsOnServerError)
    case createBackupKeyUIDOnServerError(error: CreateBackupKeyUIDOnServerError)
    case deviceBackupSnapshotSizeError
    case signatureGenerationFailed(error: Error)
    case uploadBackupToServerError(error: UploadBackupToServerError)
    case failedToCreateDeviceSnapshotNode(error: Error)
    case failedToGetAdditionalInfosForProfileBackup(error: Error)
    case cannotBackupInactiveOwnedIdentity
    case ownedIdentityHasNoBackupSeed
    case encodingError(error: Error)
    case badHTTPURLResponse(statusCode: Int?)
    case couldNotParseDecryptedDeviceBackup
    case failedToCreateProfileSnapshotNode(error: Error)
    case deviceBackupFromServerNotFound
    case couldNotDeactivateBackupSeed
    case couldNotEncodeBackupSeedForKeychain
}
