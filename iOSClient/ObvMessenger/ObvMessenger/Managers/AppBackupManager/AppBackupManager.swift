/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvEngine
import ObvTypes
import CloudKit
import OlvidUtils
import ObvCrypto
import ObvUICoreData
import CoreData
import ObvSettings



final actor AppBackupManager: AppBackupDelegate, ObvErrorMaker {

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: AppBackupManager.self))

    static let errorDomain = "AppBackupManager"
    static let recordType = "EngineBackupRecord"
    static let creationDate = "creationDate" // Not a custom key since it belongs to CKRecord

    private let obvEngine: ObvEngine

    private var notificationTokens = [NSObjectProtocol]()
    
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier?

    /// Type of the current incremental cleaning
    enum CurrentIncrementalCleanType {
        case none
        case starting
        case ongoing(progress: ObvProgress)
    }

    /// This variable indicate the status of the current incremental cleaning of iCloud backups.
    /// This variable is
    /// - `none` when no incremental cleaning is in progress
    /// - `starting` if an incremental cleaning is starting
    /// - `ongoing` when there is an incremental cleaning in progress. In that case, an `ObvProgress` allows to monitor the progress of the cleaning.
    private var currentIncrementalClean = CurrentIncrementalCleanType.none
    
    var cleaningProgress: ObvProgress? {
        get async {
            switch currentIncrementalClean {
            case .none, .starting: return nil
            case .ongoing(progress: let progress): return progress
            }
        }
    }
    
    enum Key: String {
        case deviceIdentifierForVendor = "deviceIdentifierForVendor"
        case deviceName = "deviceName"
        case encryptedBackupFile = "encryptedBackupFile"
    }

    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        Task {
            await observeNotifications()
        }
        do {
            try obvEngine.registerAppBackupableObject(self)
        } catch {
            os_log("Could not register the app within the engine for performing App data backup", log: Self.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
        
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func observeNotifications() {
        
        // Internal notifications
        
        notificationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeUserWantsToStartIncrementalCleanBackup { [weak self] cleanAllDevices in
                Task(priority: .userInitiated) { [weak self] in
                    await self?.startIncrementalCleanCloudBackups(cleanAllDevices: cleanAllDevices)
                }
            },
        ])

        // Engine notifications
        
        notificationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeNewBackupKeyGenerated(within: NotificationCenter.default) { [weak self] (backupKeyString, backupKeyInformation) in
                // When a new backup key is created, we immediately perform a fresh automatic backup if required
                Task(priority: .background) { [weak self] in
                    try? await self?.performBackupToICloud(manuallyRequestByUser: false)
                }
            },
        ])

    }
    
    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        guard forTheFirstTime else { return }
        Task(priority: .background) { [weak self] in
            try? await self?.performBackupToICloud(manuallyRequestByUser: false)
        }
    }
    
}


// MARK: - Requesting backup for export

extension AppBackupManager {

    func exportBackup(sourceView: UIView, sourceViewController: UIViewController) async throws -> Bool {
        let (backupKeyUid, backupVersion, encryptedContent) = try await obvEngine.initiateBackup(forExport: true, requestUUID: UUID())

        let success = try await newEncryptedBackupAvailableForExport(backupKeyUid: backupKeyUid,
                                                                     backupVersion: backupVersion,
                                                                     encryptedContent: encryptedContent,
                                                                     sourceView: sourceView,
                                                                     sourceViewController: sourceViewController)

        if success {
            ObvMessengerInternalNotification.backupForExportWasExported.postOnDispatchQueue()
        }
        return success
    }
    
}


// MARK: - Uploading a backup with CloudKit

extension AppBackupManager {

    func uploadBackupToICloud() async throws {
        try await performBackupToICloud(manuallyRequestByUser: true)
    }

    
    private func performBackupToICloud(manuallyRequestByUser: Bool) async throws {
    
        os_log("Call to performBackupToICloud with manuallyRequestByUser: %{public}@. The current background task identifier is %{public}@", log: Self.log, type: .info, manuallyRequestByUser.description, backgroundTaskIdentifier.debugDescription)
        
        guard backgroundTaskIdentifier == nil else { return }
        
        // Check that automatic backups are requested or that the user explicitely requested the backup
        guard (ObvMessengerSettings.Backup.isAutomaticBackupEnabled && obvEngine.isBackupRequired) || manuallyRequestByUser else {
            os_log("A backup key is available, but since automatic backup are not requested or backup was not required, and since we are not considering a manual backup, we do not perform an backup to the cloud", log: Self.log, type: .info)
            return
        }

        // Begin background task
        self.backgroundTaskIdentifier = await UIApplication.shared.beginBackgroundTask(withName: "Olvid Automatic Backup") {
            os_log("Could not perform automatic backup to CloudKit, could not begin background task", log: Self.log, type: .fault)
            return
        }
        guard let backgroundTaskIdentifier = self.backgroundTaskIdentifier else { assertionFailure(); return }
        defer {
            Task {
                // End background task
                self.backgroundTaskIdentifier = nil
                os_log("Ending flow created for uploadind backup for background task identifier: %{public}d", log: Self.log, type: .info, backgroundTaskIdentifier.rawValue)
                await UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            }
        }
        guard backgroundTaskIdentifier != .invalid else {
            ObvMessengerInternalNotification.backupForUploadFailedToUpload.postOnDispatchQueue()
            throw Self.makeError(message: "Could not perform automatic backup to CloudKit, running in the background isn't possible.")
        }
        os_log("Starting background task for automatic backup with background task idenfier: %{public}d", log: Self.log, type: .info, backgroundTaskIdentifier.rawValue)

        // If we reach this point, we should try to perform a backup
        let backupRequestUuid = UUID()
        let (backupKeyUid, version, encryptedContent) = try await obvEngine.initiateBackup(forExport: false, requestUUID: backupRequestUuid)
        do {
            try await newEncryptedBackupAvailableForUploadToCloudKit(backupKeyUid: backupKeyUid,
                                                                     backupVersion: version,
                                                                     encryptedContent: encryptedContent,
                                                                     backupRequestUuid: backupRequestUuid,
                                                                     manuallyRequestByUser: manuallyRequestByUser)
            ObvMessengerInternalNotification.backupForUploadWasUploaded.postOnDispatchQueue()
        } catch {
            ObvMessengerInternalNotification.backupForUploadFailedToUpload.postOnDispatchQueue()
            throw error
        }
    }
    
    
    private func newEncryptedBackupAvailableForUploadToCloudKit(backupKeyUid: UID, backupVersion: Int, encryptedContent: Data, backupRequestUuid: UUID, manuallyRequestByUser: Bool) async throws {
        os_log("New encrypted backup available for upload to CloudKit", log: Self.log, type: .info)
        let backupFile = try BackupFile(encryptedContent: encryptedContent, backupKeyUid: backupKeyUid, backupVersion: backupVersion, log: Self.log)
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else {
            os_log("The iCloud account isn't available. We cannot perform automatic backup.", log: Self.log, type: .fault)
            try? backupFile.deleteData()
            await self.markBackupAsFailed(backupFile: backupFile)
            return
        }
        try await self.uploadBackupFileToCloudKit(backupFile: backupFile, container: container, backupRequestUuid: backupRequestUuid, manuallyRequestByUser: manuallyRequestByUser)

        if ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled {
            Task {
                await self.startIncrementalCleanCloudBackups(cleanAllDevices: false)
            }
        }
    }

    private func markBackupAsFailed(backupFile: BackupFile) async {
        do {
            try await obvEngine.markBackupAsFailed(backupKeyUid: backupFile.backupKeyUid, backupVersion: backupFile.backupVersion)
        } catch let error {
            os_log("Could mark the backup as uploaded: %{public}@", log: Self.log, type: .error, error.localizedDescription)
        }
    }

    private func markBackupAsUploaded(backupFile: BackupFile) async {
        do {
            try await self.obvEngine.markBackupAsUploaded(backupKeyUid: backupFile.backupKeyUid, backupVersion: backupFile.backupVersion)
        } catch let error {
            os_log("Could mark the backup as uploaded although it was uploaded successfully: %{public}@", log: Self.log, type: .error, error.localizedDescription)
        }
    }


    private func uploadBackupFileToCloudKit(backupFile: BackupFile, container: CKContainer, backupRequestUuid: UUID, manuallyRequestByUser: Bool) async throws {

        defer {
            try? backupFile.deleteData()
        }
        
        os_log("Will upload backup to CloudKit", log: Self.log, type: .info)

        guard let identifierForVendor = await UIDevice.current.identifierForVendor else {
            await self.markBackupAsFailed(backupFile: backupFile)
            throw Self.makeError(message: "We could not determine the device's identifier for vendor. We cannot perform automatic backup.")
        }

        // Create the CloudKit record
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[.deviceName] = await UIDevice.current.name as NSString
        record[.deviceIdentifierForVendor] = identifierForVendor.uuidString as NSString
        record[.encryptedBackupFile] = backupFile.ckAsset
        
        // Get the private CloudKit database
        let privateDatabase = container.privateCloudDatabase

        // Last chance to check whether automatic backup are enabled or if the backup was manually requested (i.e., forced).
        guard ObvMessengerSettings.Backup.isAutomaticBackupEnabled || manuallyRequestByUser else {
            os_log("We cancel the backup upload to iCloud since automatic backups are disabled and since this backup was not manually requested.", log: Self.log, type: .error)
            assertionFailure()
            return
        }

        // Upload the record
        do {
            _ = try await privateDatabase.save(record)
            os_log("Encrypted backup was uploaded to CloudKit", log: Self.log, type: .info)
            await self.markBackupAsUploaded(backupFile: backupFile)
        } catch(let error) {
            await self.markBackupAsFailed(backupFile: backupFile)
            throw error
        }
    }

}

// MARK: - Backups utils

extension AppBackupManager {

    func getAccountStatus() async throws -> CKAccountStatus {
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        return try await container.accountStatus()
    }

    func checkAccount() async throws {
        let accountStatus = try await getAccountStatus()
        guard accountStatus == .available else {
            throw CloudKitError.accountNotAvailable(accountStatus)
        }
    }

    func deleteCloudBackup(record: CKRecord) async throws {
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        try await checkAccount()
        let privateDatabase = container.privateCloudDatabase
        do {
            _ = try await privateDatabase.deleteRecord(withID: record.recordID)
        } catch(let error) {
            throw CloudKitError.operationError(error)
        }
    }

    /// Returns the latest backup for the current device
    func getLatestCloudBackup(desiredKeys: [AppBackupManager.Key]?) async throws -> CKRecord? {
        guard let identifierForVendor = await UIDevice.current.identifierForVendor else {
            throw CloudKitError.operationError(Self.makeError(message: "Cannot get identifierForVendor"))
        }
        let iterator = CloudKitBackupRecordIterator(identifierForVendor: identifierForVendor,
                                                    resultsLimit: 1,
                                                    desiredKeys: desiredKeys)
        return try await iterator.next()?.first
    }

    func getBackupsAndDevicesCount(identifierForVendor: UUID?) async throws -> (backupCount: Int, deviceCount: Int) {
        let iterator = CloudKitBackupRecordIterator(identifierForVendor: identifierForVendor,
                                                    resultsLimit: nil,
                                                    desiredKeys: [.deviceIdentifierForVendor])
        var backupCount = 0
        var devices = Set<UUID>()
        for try await records in iterator {
            backupCount += records.count
            devices.formUnion(records.compactMap({ $0.deviceIdentifierForVendor }))
        }
        return (backupCount, devices.count)
    }

}

// MARK: - Backups settings

extension AppBackupManager {

    static func CKAccountStatusMessage(_ accountStatus: CKAccountStatus) -> (title: String, message: String)? {
        switch accountStatus {
        case .noAccount:
            return (Strings.titleSignIn, Strings.messageSignIn)
        case .couldNotDetermine:
            return (Strings.titleCloudKitStatusUnclear, Strings.messageSignIn)
        case .restricted:
            return (Strings.titleCloudRestricted, Strings.messageRestricted)
        case .available:
            return nil
        case .temporarilyUnavailable:
            return (Strings.temporarilyUnavailable, Strings.tryAgainLater)
        @unknown default:
            assertionFailure()
            return nil
        }
    }

    private struct Strings {
        static let titleSignIn = NSLocalizedString("Sign in to iCloud", comment: "Alert title")
        static let messageSignIn = NSLocalizedString("Please sign in to your iCloud account to enable automatic backups. On the Home screen, launch Settings, tap iCloud, and enter your Apple ID. Turn iCloud Drive on. If you don't have an iCloud account, tap Create a new Apple ID.", comment: "Alert message")
        static let titleCloudKitStatusUnclear = NSLocalizedString("iCloud status is unclear", comment: "Alert title")
        static let titleCloudRestricted = NSLocalizedString("iCloud access is restricted", comment: "Alert title")
        static let temporarilyUnavailable = NSLocalizedString("ICLOUD_ACCOUNT_TEMPORARILY_UNAVAILABLE", comment: "Alert title")
        static let tryAgainLater = NSLocalizedString("ICLOUD_ACCOUNT_TRY_AGAIN_LATER", comment: "Alert body")
        static let messageRestricted = NSLocalizedString("Your iCloud account is not available. Access was denied due to Parental Controls or Mobile Device Management restrictions", comment: "Alert body")
    }

}


// MARK: - Deleting obsolete (old) backups

extension AppBackupManager {

    private func startIncrementalCleanCloudBackups(cleanAllDevices: Bool) async {
        guard case .none = currentIncrementalClean else {
            // An incremental clean is starting or ongoing. We do not want two cleaning in parallel.
            return
        }
        currentIncrementalClean = .starting
        defer {
            currentIncrementalClean = .none
        }
        os_log("🧽 Start incremental backup clean", log: Self.log, type: .info)

        do {
            let identifierForVendor: UUID?
            if cleanAllDevices {
                identifierForVendor = nil
            } else {
                guard let _identifierForVendor = await UIDevice.current.identifierForVendor else {
                    throw CloudKitError.operationError(Self.makeError(message: "Cannot get identifierForVendor"))
                }
                identifierForVendor = _identifierForVendor
            }

            let (backupCount, deviceCount) = try await getBackupsAndDevicesCount(identifierForVendor: identifierForVendor)
            let totalUnitCount = backupCount - deviceCount // We substract deviceCount as this corresponds to the number of latest backups that we will keep
            let progress = ObvProgress(totalUnitCount: Int64(totalUnitCount))
            currentIncrementalClean = .ongoing(progress: progress)
            ObvMessengerInternalNotification.incrementalCleanBackupStarts.postOnDispatchQueue()
            try await queueIncrementalCleanCloudBackups(identifierForVendor: identifierForVendor)
        } catch(let error) {
            let error = error as? CloudKitError ?? .unknownError(error)
            switch error {
            case .accountError(let error):
                os_log("🧽 Clean previous backups error: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            case .accountNotAvailable:
                os_log("🧽 Clean previous backups error: account is not available", log: Self.log, type: .fault)
            case .operationError(let error):
                os_log("🧽 Clean previous backups error: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            case .unknownError(let error):
                os_log("🧽 Clean previous backups error: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
            case .internalError:
                assertionFailure()
                os_log("🧽 Clean previous backups internal error", log: Self.log, type: .fault)
            }
        }
    }

    
    private func queueIncrementalCleanCloudBackups(identifierForVendor: UUID?) async throws {

        let iterator = CloudKitBackupRecordIterator(identifierForVendor: identifierForVendor, resultsLimit: 50, desiredKeys: [.deviceIdentifierForVendor])

        guard let records = try await iterator.next() else {
            os_log("🧽 Clean previous backups is terminated (No record found (A))", log: Self.log, type: .info)
            ObvMessengerInternalNotification.incrementalCleanBackupTerminates.postOnDispatchQueue()
            return
        }
        guard !records.isEmpty else {
            os_log("🧽 Clean previous backups is terminated (No record found (B))", log: Self.log, type: .info)
            ObvMessengerInternalNotification.incrementalCleanBackupTerminates.postOnDispatchQueue()
            return
        }

        // Multimap of Device to ordered records (most recent first)
        var deviceToRecords: [UUID: [CKRecord]] = [:]
        for record in records {
            guard let deviceIdentifierForVendor = record.deviceIdentifierForVendor else { assertionFailure(); continue }
            if let recordsForDevice = deviceToRecords[deviceIdentifierForVendor] {
                deviceToRecords[deviceIdentifierForVendor] = recordsForDevice + [record]
            } else {
                deviceToRecords[deviceIdentifierForVendor] = [record]
            }
        }

        // Records to save to latest for each device
        var recordsToSave = [CKRecord]()
        
        // Record to delete: all record except the latest
        var recordsToDelete = [CKRecord]()
        
        for records in deviceToRecords.values {
            guard let recordToSave = records.first else { assertionFailure(); continue }
            guard let recordToSaveCreationDate = recordToSave.creationDate else {
                assertionFailure(); continue
            }
            recordsToSave += [recordToSave]
            for record in records {
                guard record.recordID != recordToSave.recordID else { continue }
                guard let creationDate = record.creationDate else { assertionFailure(); continue }
                guard creationDate < recordToSaveCreationDate else { assertionFailure(); continue }
                recordsToDelete += [record]
            }
        }

        let recordIDsToDelete = recordsToDelete.map { $0.recordID }
        guard !recordIDsToDelete.isEmpty else {
            os_log("🧽 Clean previous backup is terminated (No records to delete)", log: Self.log, type: .info)
            ObvMessengerInternalNotification.incrementalCleanBackupTerminates.postOnDispatchQueue()
            return
        }

        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        try await checkAccount()
        let database = container.privateCloudDatabase

        try await database.modifyRecords(recordsToSave: recordsToSave,
                                         recordIDsToDelete: recordIDsToDelete)
        // Update current cleaning count
        Task { [weak self] in
            await self?.cleaningProgress?.completedUnitCount += Int64(recordIDsToDelete.count)
        }
        // Launch another cleaning batch
        try await self.queueIncrementalCleanCloudBackups(identifierForVendor: identifierForVendor)
    }
}

private extension CKDatabase {

    func modifyRecords(recordsToSave: [CKRecord]? = nil,
                       recordIDsToDelete: [CKRecord.ID]? = nil) async throws {
        return try await withCheckedThrowingContinuation({ cont in
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave,
                                                     recordIDsToDelete: recordIDsToDelete)
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .failure(let error):
                    cont.resume(throwing: CloudKitError.operationError(error))
                case .success:
                    cont.resume()
                }
            }
            self.add(operation)
        })
    }

}


// MARK: - Exporting a backup

extension AppBackupManager {

    @MainActor
    private func newEncryptedBackupAvailableForExport(backupKeyUid: UID, backupVersion: Int, encryptedContent: Data, sourceView: UIView, sourceViewController: UIViewController) async throws -> Bool {

        assert(Thread.isMainThread)

        let backupFile = try BackupFile(encryptedContent: encryptedContent, backupKeyUid: backupKeyUid, backupVersion: backupVersion, log: Self.log)

        let ativityController = UIActivityViewController(activityItems: [backupFile], applicationActivities: nil)
        ativityController.popoverPresentationController?.sourceView = sourceView
        return try await withCheckedThrowingContinuation { cont in
            ativityController.completionWithItemsHandler = { [weak self] (activityType, completed, returnedItems, error) in
                guard completed else {
                    try? backupFile.deleteData()
                    cont.resume(returning: false)
                    return
                }
                Task {
                    if activityType != nil {
                        // We assume that the backup file was indeed exported
                        do {
                            try await self?.obvEngine.markBackupAsExported(backupKeyUid: backupFile.backupKeyUid, backupVersion: backupFile.backupVersion)
                        } catch let error {
                            cont.resume(throwing: error)
                        }
                    }
                    do {
                        try backupFile.deleteData()
                    } catch let error {
                        os_log("Could not delete the encrypted backup: %{public}@", log: Self.log, type: .error, error.localizedDescription)
                    }
                    cont.resume(returning: true)
                }
            }
            DispatchQueue.main.async {
                sourceViewController.present(ativityController, animated: true)
            }
        }
    }
    
    
}


// MARK: - BackupFile type used for both exported and uploaded backups

fileprivate final class BackupFile: UIActivityItemProvider {
    
    private let tempLocation: URL
    private let fileName: String
    private let url: URL
    let backupKeyUid: UID
    let backupVersion: Int
    
    private static let errorDomain = "BackupFile"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    private let dateFormaterForBackupFileName: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd HH-mm-ss"
        return df
    }()

    init(encryptedContent: Data, backupKeyUid: UID, backupVersion: Int, log: OSLog) throws {
        
        self.backupKeyUid = backupKeyUid
        self.backupVersion = backupVersion
        let nowAsString = dateFormaterForBackupFileName.string(from: Date())
        self.fileName = "Olvid backup \(nowAsString).olvidbackup"
        let randomDirectoryName = UUID().uuidString
        self.tempLocation = ObvUICoreDataConstants.ContainerURL.forTempFiles.appendingPathComponent("BackupFiles", isDirectory: true).appendingPathComponent(randomDirectoryName, isDirectory: true)
        self.url = tempLocation.appendingPathComponent(fileName)

        super.init(placeholderItem: url)

        // Write the encrypted content to a temporary file
        
        try FileManager.default.createDirectory(at: tempLocation, withIntermediateDirectories: true, attributes: nil)
        do {
            try encryptedContent.write(to: url)
        } catch let error {
            os_log("Could not save backup encrypted data to temporary URL %{public}@: %{public}@", log: log, type: .error, url.absoluteString, error.localizedDescription)
            throw BackupFile.makeError(message: "Could not save backup encrypted data to temporary URL: \(error.localizedDescription)")
        }
        os_log("Backup encrypted data saved to %{public}@", log: log, type: .info, url.absoluteString)

    }
    
    override var item: Any {
        return url
    }
    
    func deleteData() throws {
        try FileManager.default.removeItem(at: tempLocation)
    }
    
    var ckAsset: CKAsset {
        return CKAsset(fileURL: url)
    }
    
}

extension CKRecord {

    subscript(key: AppBackupManager.Key) -> CKRecordValue? {
        get {
            self[key.rawValue]
        }
        set {
            self[key.rawValue] = newValue
        }
    }

    var deviceIdentifierForVendor: UUID? {
        guard let deviceIdentifierForVendorAsString = self[.deviceIdentifierForVendor] as? String,
              let deviceIdentifierForVendor = UUID(deviceIdentifierForVendorAsString) else {
                  assertionFailure(); return nil }
        return deviceIdentifierForVendor
    }
}

// MARK: - Responding to engine request for app backup items

extension AppBackupManager: ObvBackupable {
    static var backupIdentifier: String {
        return "app" // This value is ignored by the engine
    }

    nonisolated var backupIdentifier: String {
        return AppBackupManager.backupIdentifier
    }

    nonisolated var backupSource: ObvBackupableObjectSource {
        .app
    }

    func provideInternalDataForBackup(backupRequestIdentifier: FlowIdentifier) async throws -> (internalJson: String, internalJsonIdentifier: String, source: ObvBackupableObjectSource) {
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(internalJson: String, internalJsonIdentifier: String, source: ObvBackupableObjectSource), Error>) in
            do {
                try ObvStack.shared.performBackgroundTaskAndWaitOrThrow { context in
                    let ownedIdentities = try PersistedObvOwnedIdentity.getAll(within: context)
                    let appBackupItem = AppBackupItem(ownedIdentities: ownedIdentities)
                    let jsonEncoder = JSONEncoder()
                    let data = try jsonEncoder.encode(appBackupItem)
                    guard let internalData = String(data: data, encoding: .utf8) else {
                        throw Self.makeError(message: "Could not convert json to UTF8 string during app backup")
                    }
                    continuation.resume(returning: (internalData, AppBackupManager.backupIdentifier, .app))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        
    }
 
    
    func restoreBackup(backupRequestIdentifier: FlowIdentifier, internalJson: String?) async throws {
        
        // This is called when all the engine data have been restored. We can thus start the restore of app backuped data.
        
        // We first sync of all the engine database to make sure the app database is in sync
        
        let queues = try await syncAppDatabasesWithEngine()
        
        // If internalJson is nil, we are restoring a very old backup, that does not contain backuped data for the app.
        // In general, we expect it to be non-nil.

        if let internalJson {
            
            // The app database is in sync with the engine database.
            // We can use the backuped data so as to "update" certain app database objects.
                        
            do {
                try await processAppInternalJson(internalJson, queues: queues)
            } catch {
                // Although we did not succeed to restore the app backup, for now, we consider the restore is complete
                assertionFailure()
                return
            }
                        
        }
        
        // Perform additional step after backup restoration

        await performAdditionalStepsAfterBackupRestoration(queues: queues)
        
    }
    
    
    /// Helper method for ``restoreBackup(backupRequestIdentifier:internalJson:)``.
    /// Simple wrapper around the ``ObvMessengerInternalNotification.requestSyncAppDatabasesWithEngine`` notification.
    /// The returned queue is the coordinator queue (on which we can exectue Core Data operations).
    private func syncAppDatabasesWithEngine() async throws -> (coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue) {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue), Error>) in
            ObvMessengerInternalNotification.requestSyncAppDatabasesWithEngine(queuePriority: .veryHigh, isRestoringSyncSnapshotOrBackup: true) { result in
                switch result {
                case .failure(let error):
                    return continuation.resume(throwing: error)
                case .success(let coordinatorsQueue):
                    return continuation.resume(returning: coordinatorsQueue)
                }
            }.postOnDispatchQueue(DispatchQueue(label: "Queue for posting a requestSyncAppDatabasesWithEngine notification"))
        }
    }
    
    
    /// Helper method for ``restoreBackup(backupRequestIdentifier:internalJson:)``.
    private func processAppInternalJson(_ internalJson: String, queues: (coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue)) async throws {
        
        let internalJsonData = internalJson.data(using: .utf8)!
        let jsonDecoder = JSONDecoder()
        let appBackupItem: AppBackupItem
        do {
            appBackupItem = try jsonDecoder.decode(AppBackupItem.self, from: internalJsonData)
        } catch {
            // Although we did not succeed to restore the app backup, for now, we consider the restore is complete
            assertionFailure()
            return
        }
        
        // Step 1: update all owned identities, contacts, and groups
        
        if let ownedIdentityBackupItems = appBackupItem.ownedIdentities {
            
            let op1 = RestoreOwnedIdentityBackupItemsOperation(ownedIdentityBackupItems: ownedIdentityBackupItems, log: Self.log)
            let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, queueForComposedOperations: queues.queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
            composedOp.queuePriority = .veryHigh
            await queues.coordinatorsQueue.addAndAwaitOperation(composedOp)
            
            guard composedOp.isFinished && !composedOp.isCancelled else {
                assertionFailure()
                throw Self.makeError(message: "Could not restore app internal JSON")
            }
            
        }
        
        // Step 2: Update the app global configuration
        
        appBackupItem.globalSettings.updateExistingObvMessengerSettings()

        
    }
    
    
    /// Helper method for ``restoreBackup(backupRequestIdentifier:internalJson:)``.
    private func performAdditionalStepsAfterBackupRestoration(queues: (coordinatorsQueue: OperationQueue, queueForComposedOperations: OperationQueue)) async {
        
        let op1 = PerformAdditionalStepsAfterBackupRestorationOperation(log: Self.log)
        let composedOp = CompositionOfOneContextualOperation(op1: op1, contextCreator: ObvStack.shared, queueForComposedOperations: queues.queueForComposedOperations, log: Self.log, flowId: FlowIdentifier())
        composedOp.queuePriority = .veryHigh
        await queues.coordinatorsQueue.addAndAwaitOperation(composedOp)

        assert(composedOp.isFinished && !composedOp.isCancelled)
        
    }
    
}
