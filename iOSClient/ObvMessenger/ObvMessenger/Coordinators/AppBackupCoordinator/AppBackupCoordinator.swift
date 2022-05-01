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
import ObvEngine
import ObvTypes
import CloudKit
import OlvidUtils
import SwiftUI


final class AppBackupCoordinator: ObvBackupable {
    
    private let obvEngine: ObvEngine
    private var notificationTokens = [NSObjectProtocol]()
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier?

    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: AppBackupCoordinator.self))

    private static let errorDomain = "AppBackupCoordinator"
    static let recordType = "EngineBackupRecord"
    static let deviceIdentifierForVendorKey = "deviceIdentifierForVendor"
    static let deviceNameKey = "deviceName"
    static let creationDate = "creationDate"

    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    weak var vcDelegate: UIViewController?
    
    /// This makes it possible to upload a backup to iCloud even when automatic backups are disabled. This is
    /// used when the user explicitely ask for an iCloud backup.
    private var uuidOfForcedBackupRequests = Set<UUID>()

    private let interalQueue = OperationQueue.createSerialQueue(name: "AppBackupCoordinator internal queue", qualityOfService: .default)
    
    public static var backupIdentifier: String {
        return "app" // This value is ignored by the engine
    }
    
    public var backupIdentifier: String {
        return AppBackupCoordinator.backupIdentifier
    }
    
    public var backupSource: ObvBackupableObjectSource { .app }

    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        observeNotifications()
        do {
            try obvEngine.registerAppBackupableObject(self)
        } catch {
            os_log("Could not register the app within the engine for performing App data backup", log: AppBackupCoordinator.log, type: .fault, error.localizedDescription)
            assertionFailure()
        }
    }
        
    private func observeNotifications() {
        
        // Internal notifications
        
        notificationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeAppStateChanged(queue: interalQueue) { [weak self] (previousState, currentState) in
                if currentState.isInitializedAndActive {
                    self?.performBackupToCloudKit(manuallyRequestByUser: false)
                } else if currentState.isInitialized && previousState.iOSAppState == .active {
                    self?.performBackupToCloudKit(manuallyRequestByUser: false)
                }
            },
            ObvMessengerInternalNotification.observeUserWantsToPerfomBackupForExportNow(queue: interalQueue) { [weak self] (sourceView) in
                self?.processUserWantsToPerfomBackupForExportNow(sourceView: sourceView)
            },
            ObvMessengerInternalNotification.observeUserWantsToPerfomCloudKitBackupNow(queue: interalQueue) { [weak self] in
                self?.performBackupToCloudKit(manuallyRequestByUser: true)
            },
            ObvMessengerInternalNotification.observeIncrementalCleanBackupInProgress(queue: OperationQueue.main) { currentCount, cleanAllDevices in
                Self.cleanPreviousICloudBackupsThenLogResult(currentCount: currentCount, cleanAllDevices: cleanAllDevices)
            },
        ])

        // Engine notifications
        
        notificationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeNewBackupKeyGenerated(within: NotificationCenter.default, queue: interalQueue) { [weak self] (backupKeyString, backupKeyInformation) in
                // When a new backup key is created, we immediately perform a fresh automatic backup if required
                self?.performBackupToCloudKit(manuallyRequestByUser: false)
            },
        ])

    }
    
}


// MARK: - Requesting backup for export

extension AppBackupCoordinator {
    
    
    private func processUserWantsToPerfomBackupForExportNow(sourceView: UIView) {
        Task {
            do {
                let (backupKeyUid, backupVersion, encryptedContent) = try await obvEngine.initiateBackup(forExport: true, requestUUID: UUID())
                DispatchQueue.main.async { [weak self] in
                    self?.newEncryptedBackupAvailableForExport(backupKeyUid: backupKeyUid, backupVersion: backupVersion, encryptedContent: encryptedContent, sourceView: sourceView)
                }
            } catch {
                /// If the backup fails we do nothing. We probably should since, in practice, the user will see a never ending spinner.
                os_log("The backup failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                return
            }
        }
    }
    
    
}


// MARK: - Uploading a backup with CloudKit

extension AppBackupCoordinator {
    
    private func endBackgroundTaskNow() {
        interalQueue.addOperation { [weak self] in
            guard let _self = self else { return }
            guard let backgroundTaskIdentifier = _self.backgroundTaskIdentifier else { assertionFailure(); return }
            _self.backgroundTaskIdentifier = nil
            os_log("Ending flow created for uploadind backup for background task identifier: %{public}d", log: Self.log, type: .info, backgroundTaskIdentifier.rawValue)
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        }
    }
    
    
    private func performBackupToCloudKit(manuallyRequestByUser: Bool) {
        assert(OperationQueue.current == interalQueue)
        os_log("Call to performBackupToICloud with manuallyRequestByUser: %{public}@. The current background task identifier is %{public}@", log: Self.log, type: .info, manuallyRequestByUser.description, backgroundTaskIdentifier.debugDescription)
        guard backgroundTaskIdentifier == nil else { return }
        // Check whether automatic backups are requested
        guard ObvMessengerSettings.Backup.isAutomaticBackupEnabled || manuallyRequestByUser else {
            os_log("A backup key is available, but since automatic backup are not requested, and since we are not considering a manual backup, we do not perform an backup to the cloud", log: Self.log, type: .info)
            return
        }
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: "Olvid Automatic Backup") {
            os_log("Could not perform automatic backup to CloudKit, could not begin background task", log: Self.log, type: .fault)
            return
        }
        os_log("Starting background task for automatic backup with background task idenfier: %{public}d", log: Self.log, type: .info, backgroundTaskIdentifier!.rawValue)
        guard (obvEngine.isBackupRequired || manuallyRequestByUser) else {
            endBackgroundTaskNow()
            return
        }
        // If we reach this point, we should try to perform a backup
        
        Task(priority: manuallyRequestByUser ? .userInitiated : .background) {
            do {
                let backupRequestUuid = UUID()
                let (backupKeyUid, version, encryptedContent) = try await obvEngine.initiateBackup(forExport: false, requestUUID: backupRequestUuid)
                interalQueue.addOperation { [weak self] in
                    do {
                        try self?.newEncryptedBackupAvailableForUploadToCloudKit(backupKeyUid: backupKeyUid,
                                                                                 backupVersion: version,
                                                                                 encryptedContent: encryptedContent,
                                                                                 backupRequestUuid: backupRequestUuid,
                                                                                 manuallyRequestByUser: manuallyRequestByUser)
                    } catch {
                        os_log("Failed to perform automatic backup: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                        self?.endBackgroundTaskNow()
                        assertionFailure()
                        return
                    }
                }
            } catch {
                os_log("Failed to perform automatic backup: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                endBackgroundTaskNow()
                assertionFailure()
                return
            }
        }
    }
    
    
    private func newEncryptedBackupAvailableForUploadToCloudKit(backupKeyUid: UID, backupVersion: Int, encryptedContent: Data, backupRequestUuid: UUID, manuallyRequestByUser: Bool) throws {
        assert(OperationQueue.current == interalQueue)
        let log = Self.log
        os_log("New encrypted available for upload to CloudKit", log: log, type: .info)
        let backupFile = try BackupFile(encryptedContent: encryptedContent, backupKeyUid: backupKeyUid, backupVersion: backupVersion, log: log)
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        container.accountStatus { [weak self] (accountStatus, error) in
            guard accountStatus == .available else {
                os_log("The iCloud account isn't available. We cannot perform automatic backup.", log: log, type: .fault)
                try? backupFile.deleteData()
                do {
                    try self?.obvEngine.markBackupAsFailed(backupKeyUid: backupFile.backupKeyUid, backupVersion: backupFile.backupVersion)
                } catch let error {
                    os_log("Could mark the backup as uploaded although it was uploaded successfully: %{public}@", log: log, type: .error, error.localizedDescription)
                }
                self?.endBackgroundTaskNow()
                return
            }
            self?.uploadBackupFileToCloudKit(backupFile: backupFile, container: container, backupRequestUuid: backupRequestUuid, manuallyRequestByUser: manuallyRequestByUser)

            if ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled {
                Self.cleanPreviousICloudBackupsThenLogResult(currentCount: 0, cleanAllDevices: false)
            }
        }
    }

    
    private func uploadBackupFileToCloudKit(backupFile: BackupFile, container: CKContainer, backupRequestUuid: UUID, manuallyRequestByUser: Bool) {
        
        let log = Self.log
        os_log("Will upload backup to CloudKit", log: log, type: .info)

        guard let identifierForVendor = UIDevice.current.identifierForVendor else {
            os_log("We could not determine the device's identifier for vendor. We cannot perform automatic backup.", log: log, type: .fault)
            try? backupFile.deleteData()
            do {
                try obvEngine.markBackupAsFailed(backupKeyUid: backupFile.backupKeyUid, backupVersion: backupFile.backupVersion)
            } catch let error {
                os_log("Could mark the backup as uploaded although it was uploaded successfully: %{public}@", log: log, type: .error, error.localizedDescription)
            }
            endBackgroundTaskNow()
            return
        }

        // Create the CloudKit record
        let recordID = CKRecord.ID(recordName: UUID().uuidString)
        let record = CKRecord(recordType: Self.recordType, recordID: recordID)
        record[Self.deviceNameKey] = UIDevice.current.name as NSString
        record[Self.deviceIdentifierForVendorKey] = identifierForVendor.uuidString as NSString
        record["encryptedBackupFile"] = backupFile.ckAsset
        
        // Get the private CloudKit database
        let privateDatabase = container.privateCloudDatabase
        
        // Last chance to check whether automatic backup are enabled or if the backup was manually requested (i.e., forced).
        guard ObvMessengerSettings.Backup.isAutomaticBackupEnabled || manuallyRequestByUser else {
            os_log("We cancel the backup upload to iCloud since automatic backups are disabled and since this backup was not manually requested.", log: log, type: .error)
            assertionFailure()
            return
        }
        
        // Upload the record
        privateDatabase.save(record) { [weak self] (record, error) in
            defer {
                try? backupFile.deleteData()
                self?.endBackgroundTaskNow()
            }
            guard error == nil else {
                os_log("Could not upload encrypted backup to CloudKit: %{public}@", log: log, type: .fault, error!.localizedDescription)
                do {
                    try self?.obvEngine.markBackupAsFailed(backupKeyUid: backupFile.backupKeyUid, backupVersion: backupFile.backupVersion)
                } catch let error {
                    os_log("Could mark the backup as uploaded although it was uploaded successfully: %{public}@", log: log, type: .error, error.localizedDescription)
                }
                return
            }
            os_log("Encrypted backup was uploaded to CloudKit", log: log, type: .info)
            do {
                try self?.obvEngine.markBackupAsUploaded(backupKeyUid: backupFile.backupKeyUid, backupVersion: backupFile.backupVersion)
            } catch let error {
                os_log("Could mark the backup as uploaded although it was uploaded successfully: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }

    }

    enum AppBackupError: Error {
        case accountError(_: Error)
        case accountNotAvailable(_: CKAccountStatus)
        case operationError(_: Error)
    }

    final class CKRecordIterator: ObservableObject {

        let container: CKContainer
        let database: CKDatabase
        let query: CKQuery

        private let resultsLimit: Int = 50

        private var cursor: CKQueryOperation.Cursor? = nil

        enum Operation {
            case initialization
            case loadMoreRecords
        }

        @Published var records: [CKRecord] = []
        @Published var currentOperation: Operation? = nil
        @Published var error: AppBackupError?

        var hasMoreRecords: Bool { cursor != nil }

        init(container: CKContainer,
             database: KeyPath<CKContainer, CKDatabase>,
             query: CKQuery) {
            self.container = container
            self.database = container[keyPath: database]
            self.query = query
            initialize()
        }

        func initialize() {
            DispatchQueue.main.async {
                withAnimation {
                    self.currentOperation = .initialization
                }
            }
            self.records.removeAll()
            self.error = nil
            self.container.accountStatus {  (accountStatus, error) in
                if let error = error {
                    self.error = .accountError(error)
                    return
                }
                guard accountStatus == .available else {
                    self.error = .accountNotAvailable(accountStatus)
                    return
                }

                let queryOp = CKQueryOperation(query: self.query)
                queryOp.recordFetchedBlock = self.recordFetchedBlock
                queryOp.queryCompletionBlock = self.queryCompletionBlock
                queryOp.resultsLimit = self.resultsLimit

                self.database.add(queryOp)
            }
        }

        func loadMoreRecords() {
            guard let cursor = cursor else { return  }
            self.cursor = nil
            DispatchQueue.main.async {
                withAnimation {
                    self.currentOperation = .loadMoreRecords
                }
            }
            let nextQueryOp = CKQueryOperation(cursor: cursor)
            nextQueryOp.recordFetchedBlock = recordFetchedBlock
            nextQueryOp.queryCompletionBlock = queryCompletionBlock
            nextQueryOp.resultsLimit = resultsLimit
            self.database.add(nextQueryOp)
        }

        private func recordFetchedBlock(record: CKRecord) {
            DispatchQueue.main.async {
                withAnimation {
                    self.records += [record]
                }
            }
        }

        private func queryCompletionBlock(cursor: CKQueryOperation.Cursor?, error: Error?) {
            defer {
                DispatchQueue.main.async {
                    withAnimation {
                        self.currentOperation = nil
                    }
                }
            }
            if let error = error {
                DispatchQueue.main.async {
                    self.error = .operationError(error)
                }
                return
            }
            self.cursor = cursor
        }


    }

    static func buildAllCloudBackupsIterator(identifierForVendor: UUID? = nil) -> CKRecordIterator {
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)

        let predicate: NSPredicate
        if let identifierForVendor = identifierForVendor {
            predicate = NSPredicate(format: "%K == %@", Self.deviceIdentifierForVendorKey, identifierForVendor.uuidString)
        } else {
            predicate = NSPredicate(value: true)
        }
        let query = CKQuery(recordType: Self.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: Self.creationDate, ascending: false)]

        return CKRecordIterator(container: container, database: \.privateCloudDatabase, query: query)
    }

    /// identifierForVendor == nil -> Fetch records for all device
    /// identifierForVendor != nil -> Fetch records for the device for the given identifierForVendor
    static func fetchAllCloudBackups(identifierForVendor: UUID? = nil, resultsLimit: Int? = nil, completionHandler: @escaping (Result<([UUID: [CKRecord]], CKDatabase), AppBackupError>) -> Void) {
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        container.accountStatus { (accountStatus, error) in
            if let error = error {
                completionHandler(.failure(.accountError(error)))
                return
            }
            guard accountStatus == .available else {
                completionHandler(.failure(.accountNotAvailable(accountStatus)))
                return
            }
            let privateDatabase = container.privateCloudDatabase
            let predicate: NSPredicate
            if let identifierForVendor = identifierForVendor {
                predicate = NSPredicate(format: "%K == %@", Self.deviceIdentifierForVendorKey, identifierForVendor.uuidString)
            } else {
                predicate = NSPredicate(value: true)
            }
            let query = CKQuery(recordType: Self.recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: Self.creationDate, ascending: false)]
            let queryOp = CKQueryOperation(query: query)
            if let resultsLimit = resultsLimit {
                queryOp.resultsLimit = resultsLimit
            }

            var records = [UUID: [CKRecord]]()

            func recordFetchedBlock(record: CKRecord) {
                guard let deviceIdentifierForVendor = record.deviceIdentifierForVendor else { return }
                if let recordsForDevice = records[deviceIdentifierForVendor] {
                    records[deviceIdentifierForVendor] = recordsForDevice + [record]
                } else {
                    records[deviceIdentifierForVendor] = [record]
                }
            }
            queryOp.recordFetchedBlock = recordFetchedBlock

            func queryCompletionBlock(cursor: CKQueryOperation.Cursor?, error: Error?) {
                if let error = error {
                    completionHandler(.failure(.operationError(error)))
                    return
                }
                if cursor == nil {
                    completionHandler(.success((records, privateDatabase)))
                    return
                }
                if let resultsLimit = resultsLimit, resultsLimit <= records.count {
                    completionHandler(.success((records, privateDatabase)))
                    return
                }
                let nextQueryOp = CKQueryOperation(cursor: cursor!)
                nextQueryOp.recordFetchedBlock = recordFetchedBlock
                nextQueryOp.queryCompletionBlock = queryCompletionBlock
                nextQueryOp.resultsLimit = queryOp.resultsLimit
                privateDatabase.add(nextQueryOp)
            }

            queryOp.queryCompletionBlock = queryCompletionBlock
            privateDatabase.add(queryOp)
        }
    }

    /// identifierForVendor == nil -> Fetch records for all device
    /// identifierForVendor != nil -> Fetch records for the device for the given identifierForVendor
    static func fetchNFirstCloudBackups(identifierForVendor: UUID? = nil, resultsLimit: Int? = nil, completionHandler: @escaping (Result<([UUID: [CKRecord]], CKDatabase), AppBackupError>) -> Void) {
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        container.accountStatus { (accountStatus, error) in
            if let error = error {
                completionHandler(.failure(.accountError(error)))
                return
            }
            guard accountStatus == .available else {
                completionHandler(.failure(.accountNotAvailable(accountStatus)))
                return
            }
            let privateDatabase = container.privateCloudDatabase
            let predicate: NSPredicate
            if let identifierForVendor = identifierForVendor {
                predicate = NSPredicate(format: "%K == %@", Self.deviceIdentifierForVendorKey, identifierForVendor.uuidString)
            } else {
                predicate = NSPredicate(value: true)
            }
            let query = CKQuery(recordType: Self.recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: Self.creationDate, ascending: true)]
            let queryOp = CKQueryOperation(query: query)
            if let resultsLimit = resultsLimit {
                queryOp.resultsLimit = resultsLimit
            }

            var records = [UUID: [CKRecord]]()

            func recordFetchedBlock(record: CKRecord) {
                guard let deviceIdentifierForVendor = record.deviceIdentifierForVendor else { return }
                if let recordsForDevice = records[deviceIdentifierForVendor] {
                    records[deviceIdentifierForVendor] = [record] + recordsForDevice
                } else {
                    records[deviceIdentifierForVendor] = [record]
                }
            }
            queryOp.recordFetchedBlock = recordFetchedBlock

            func queryCompletionBlock(cursor: CKQueryOperation.Cursor?, error: Error?) {
                if let error = error {
                    completionHandler(.failure(.operationError(error)))
                    return
                }
                completionHandler(.success((records, privateDatabase)))
            }

            queryOp.queryCompletionBlock = queryCompletionBlock
            privateDatabase.add(queryOp)
        }
    }


    static func deleteCloudBackup(record: CKRecord, completionHandler: @escaping (Result<Void, AppBackupError>) -> Void) {
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        container.accountStatus { (accountStatus, error) in
            if let error = error {
               completionHandler(.failure(.accountError(error)))
                return
            }
            guard accountStatus == .available else {
                completionHandler(.failure(.accountNotAvailable(accountStatus)))
                return
            }
            let privateDatabase = container.privateCloudDatabase

            privateDatabase.delete(withRecordID: record.recordID) { id, error in
                if let error = error {
                    completionHandler(.failure(.operationError(error)))
                }
                completionHandler(.success(()))
            }
        }
    }

    static func getLatestCloudBackup(completionHandler: @escaping (Result<CKRecord?, AppBackupError>) -> Void) {
        guard let identifierForVendor = UIDevice.current.identifierForVendor else {
            completionHandler(.failure(.operationError(Self.makeError(message: "Cannot get identifierForVendor"))))
            return
        }
        fetchAllCloudBackups(identifierForVendor: identifierForVendor, resultsLimit: 1) { result in
            switch result {
            case .success(let (records, _)):
                assert(records.count <= 1)
                completionHandler(.success(records.first?.value.first))
            case .failure(let error):
                completionHandler(.failure(error))
            }
        }
    }

    static func incrementalCleanCloudBackups(cleanAllDevices: Bool, completionHandler: @escaping (Result<Int, AppBackupError>) -> Void) {
        Self.incrementalCleanCloudBackups(currentCount: 0,
                                          cleanAllDevices: cleanAllDevices,
                                          completionHandler: completionHandler)
    }

    private static func incrementalCleanCloudBackups(currentCount: Int, cleanAllDevices: Bool, completionHandler: @escaping (Result<Int, AppBackupError>) -> Void) {
        guard let identifierForVendor = UIDevice.current.identifierForVendor else {
            completionHandler(.failure(.operationError(Self.makeError(message: "Cannot get identifierForVendor"))))
            return
        }
        os_log("🧽 Start incremental backup clean", log: self.log, type: .info)
        ObvMessengerInternalNotification.incrementalCleanBackupStarts(initialCount: currentCount).postOnDispatchQueue()
        let successHandler: (Int, Bool) -> Void = { count, inProgress in
            if inProgress {
                os_log("🧽 Clean previous backup has removed %{public}@ backups", log: Self.log, type: .info, String(count))
                ObvMessengerInternalNotification.incrementalCleanBackupInProgress(currentCount: count, cleanAllDevices: cleanAllDevices).postOnDispatchQueue()
            } else {
                os_log("🧽 Clean previous backup is terminated", log: Self.log, type: .info)
                ObvMessengerInternalNotification.incrementalCleanBackupTerminates(totalCount: count).postOnDispatchQueue()
            }
            completionHandler(.success(count))
        }

        fetchNFirstCloudBackups(identifierForVendor: cleanAllDevices ? nil : identifierForVendor, resultsLimit: 50) { result in
            switch result {
            case .success(let (records, database)):
                guard !records.isEmpty else {
                    successHandler(currentCount, false)
                    return
                }

                // Latest record for each device.
                var recordsToSave = [CKRecord]()
                var recordsToDelete = [CKRecord]()

                for device in records.keys {
                    guard let recordsForDevice = records[device] else { assertionFailure(); continue }
                    guard let recordToSave = recordsForDevice.first else { assertionFailure(); continue }
                    guard let recordToSaveCreationDate = recordToSave.creationDate else {
                        assertionFailure(); continue
                    }
                    recordsToSave += [recordToSave]
                    for recordForDevice in recordsForDevice {
                        guard recordForDevice.recordID != recordToSave.recordID else { continue }
                        guard let creationDate = recordForDevice.creationDate else { assertionFailure(); continue }
                        guard creationDate < recordToSaveCreationDate else { assertionFailure(); continue }
                        recordsToDelete += [recordForDevice]
                    }
                }

                let recordIDsToDelete = recordsToDelete.map { $0.recordID }
                guard !recordIDsToDelete.isEmpty else {
                    successHandler(currentCount, false)
                    return
                }

                let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave,
                                                         recordIDsToDelete: recordIDsToDelete)

                if #available(iOS 15.0, *) {
                    operation.modifyRecordsResultBlock = { result in
                        switch result {
                        case .success:
                            print("clean \(currentCount + recordIDsToDelete.count) records")
                            successHandler(currentCount + recordIDsToDelete.count, true)
                        case .failure(let error):
                            completionHandler(.failure(.operationError(error)))
                        }
                    }
                } else {
                    operation.modifyRecordsCompletionBlock = { (savedRecords, deletedRecordIDs, error) in
                        if let error = error {
                            completionHandler(.failure(.operationError(error)))
                            return
                        }
                        successHandler(currentCount + recordIDsToDelete.count, true)
                    }
                }

                database.add(operation)
            case .failure(let error):
                completionHandler(.failure(error))
                return
            }
        }
    }

    static func cleanPreviousICloudBackupsThenLogResult(currentCount: Int, cleanAllDevices: Bool) {
        AppBackupCoordinator.incrementalCleanCloudBackups(currentCount: currentCount,
                                                          cleanAllDevices: cleanAllDevices) { result in
            switch result {
            case .success(let deletedRecords):
                os_log("🧽 Clean previous iCloud backups done: %{public}@ deleted record", log: self.log, type: .info, String(deletedRecords))
            case .failure(let error):
                switch error {
                case .accountError(let error):
                    os_log("🧽 Clean previous backups error: %{public}@", log: self.log, type: .fault, error.localizedDescription)
                case .accountNotAvailable:
                    os_log("🧽 Clean previous backups error: account is not available", log: self.log, type: .fault)
                case .operationError(let error):
                    os_log("🧽 Clean previous backups error: %{public}@", log: self.log, type: .fault, error.localizedDescription)
                }
            }
        }
    }
    
}


// MARK: - Exporting a backup

extension AppBackupCoordinator {
    
    private func newEncryptedBackupAvailableForExport(backupKeyUid: UID, backupVersion: Int, encryptedContent: Data, sourceView: UIView) {
        assert(Thread.isMainThread)
        
        guard let vcDelegate = self.vcDelegate else { assertionFailure(); return }
                
        let log = Self.log
        
        let backupFile: BackupFile
        do {
            backupFile = try BackupFile(encryptedContent: encryptedContent, backupKeyUid: backupKeyUid, backupVersion: backupVersion, log: log)
        } catch let error {
            os_log("Could not save encrypted backup: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
        
        let ativityController = UIActivityViewController(activityItems: [backupFile], applicationActivities: nil)
        ativityController.popoverPresentationController?.sourceView = sourceView
        ativityController.completionWithItemsHandler = { [weak self] (activityType, completed, returnedItems, error) in
            guard completed || activityType == nil else {
                return
            }
            if activityType != nil {
                // We assume that the backup file was indeed exported
                do {
                    try self?.obvEngine.markBackupAsExported(backupKeyUid: backupFile.backupKeyUid, backupVersion: backupFile.backupVersion)
                } catch let error {
                    os_log("Could not mark the backup as exported within the engine: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    // Continue anyway
                }
            }
            do {
                try backupFile.deleteData()
            } catch let error {
                os_log("Could not delete the encrypted backup: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }
        vcDelegate.dismiss(animated: true) {
            vcDelegate.present(ativityController, animated: true)
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
        self.tempLocation = ObvMessengerConstants.containerURL.forTempFiles.appendingPathComponent("BackupFiles", isDirectory: true).appendingPathComponent(randomDirectoryName, isDirectory: true)
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
    var deviceIdentifierForVendor: UUID? {
        guard let deviceIdentifierForVendorAsString = self[AppBackupCoordinator.deviceIdentifierForVendorKey] as? String,
              let deviceIdentifierForVendor = UUID(deviceIdentifierForVendorAsString) else {
                  assertionFailure(); return nil }
        return deviceIdentifierForVendor
    }
}

// MARK: - Responding to engine request for app backup items

extension AppBackupCoordinator {
    
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
                    continuation.resume(returning: (internalData, AppBackupCoordinator.backupIdentifier, .app))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
        
    }
 
    
    func restoreBackup(backupRequestIdentifier: FlowIdentifier, internalJson: String) async throws {
        
        // This is called when all the engine data have been restored. We can thus start the restore of app backuped data.
        
        // We first request a sync of all the engine database to make sure the app database is in sync
        
        let log = AppBackupCoordinator.log
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
         
            ObvMessengerInternalNotification.requestSyncAppDatabasesWithEngine { result in

                switch result {

                case .failure(let error):
                    continuation.resume(throwing: error)
                    return
                    
                case .success:

                    // The app database is in sync with the engine database.
                    // We can use the backuped data so as to "update" certain app database objects.
                    // We first need to parse the internal json
                    
                    let internalJsonData = internalJson.data(using: .utf8)!
                    let jsonDecoder = JSONDecoder()
                    let appBackupItem: AppBackupItem
                    do {
                        appBackupItem = try jsonDecoder.decode(AppBackupItem.self, from: internalJsonData)
                    } catch {
                        // Although we did not succeed to restore the app backup, for now, we consider the restore is complete
                        assertionFailure()
                        continuation.resume()
                        return
                    }

                    // Step 1: update all owned identities, contacts, and groups
                    
                    if let ownedIdentityBackupItems = appBackupItem.ownedIdentities {
                        ObvStack.shared.performBackgroundTaskAndWait { context in
                            
                            ownedIdentityBackupItems.forEach { ownedIdentityBackupItem in
                                do {
                                    try ownedIdentityBackupItem.updateExistingInstance(within: context)
                                } catch {
                                    os_log("One of the app backup item could not be fully restored: %{public}@", log: log, type: .fault, error.localizedDescription)
                                    assertionFailure()
                                    // Continue anyway
                                }
                            }
                            
                            do {
                                try context.save(logOnFailure: AppBackupCoordinator.log)
                            } catch {
                                // Although we did not succeed to restore the app backup, we consider its ok (for now)
                                assertionFailure(error.localizedDescription)
                                return
                            }

                        }
                    }
                    
                    // Step 2: Update the app global configuration
                    
                    appBackupItem.globalSettings.updateExistingObvMessengerSettings()
                    
                    // We restored the app data, we can call the completion handler
                    
                    continuation.resume()
                    
                }
                
            }.postOnDispatchQueue(DispatchQueue(label: "Queue for posting a requestSyncAppDatabasesWithEngine notification"))

        }
        
    }

}
