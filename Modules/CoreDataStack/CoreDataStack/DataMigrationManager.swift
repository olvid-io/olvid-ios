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
import CoreData
import OlvidUtils
import os.log
import SQLite3

open class DataMigrationManager<PersistentContainerType: NSPersistentContainer> {
    
    private let enableMigrations: Bool
    public let migrationRunningLog: RunningLogError
    public let modelName: String
    private let storeName: String
    private let transactionAuthor: String
    private let log: OSLog
    private var kvObservations = [NSKeyValueObservation]()

    private static func makeError(code: Int = 0, message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: "DataMigrationManager", code: code, userInfo: userInfo)
    }
    
    public enum MigrationType: CustomDebugStringConvertible {
        
        case lightweight
        case heavyweight

        public var debugDescription: String {
            switch self {
            case .lightweight: return "lightweight"
            case .heavyweight: return "heavyweight"
            }
        }

    }
    
    
    private func cleanOldTemporaryMigrationFiles() {
        os_log("Deleting old temporary migration files...", log: log, type: .info)
        let uuidPattern = "[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}"
        let uuidLength = 36
        let uuidRegex: NSRegularExpression
        do {
            uuidRegex = try NSRegularExpression(pattern: uuidPattern, options: .caseInsensitive)
        } catch {
            os_log("Could not construct expression for detecting UUID: %{public}@", log: log, type: .fault, error.localizedDescription)
            return
        }
        let directory = PersistentContainerType.defaultDirectoryURL()
        do {
            let directoryContents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            let oldTemporaryFiles = directoryContents.filter({ uuidRegex.firstMatch(in: $0.lastPathComponent, options: .anchored, range: NSRange(location: 0, length: min($0.lastPathComponent.count, uuidLength))) != nil })
            var numberOfDeletedFiles = 0
            for oldTemporaryFile in oldTemporaryFiles {
                do {
                    try FileManager.default.removeItem(at: oldTemporaryFile)
                } catch {
                    os_log("Could not clean old temporary database file: %{public}@", log: log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    continue
                }
                numberOfDeletedFiles += 1
            }
            os_log("Number of deleted old temporary migration files: %{public}d", log: log, type: .info, numberOfDeletedFiles)
        } catch {
            os_log("Could not clean old temporary migration files: %{public}@", log: log, type: .fault, error.localizedDescription)
            assertionFailure()
            return
        }
    }

    
    public func initializeCoreDataStack() throws {

        os_log("Initializing Core Data Stack %{public}@", log: log, type: .info, storeName)

        migrationRunningLog.addEvent(message: "Checking if a store already exists...")
        
        guard storeExists() else {
            migrationRunningLog.addEvent(message: "No preexisting store, we create one now")
            self._coreDataStack = CoreDataStack(modelName: modelName, transactionAuthor: transactionAuthor)
            return
        }

        migrationRunningLog.addEvent(message: "A previous store exists")

        do {
            migrationRunningLog.addEvent(message: "Checking if a migration is needed...")
            if try isMigrationNeeded() {
                migrationRunningLog.addEvent(message: "Migration needed")
                guard enableMigrations else {
                    migrationRunningLog.addEvent(message: "Migrations are not enabled. We exit now.")
                    throw DataMigrationManager.makeError(code: CoreDataStackErrorCodes.migrationRequiredButNotEnabled.rawValue, message: CoreDataStackErrorCodes.migrationRequiredButNotEnabled.localizedDescription)
                }
                migrationRunningLog.addEvent(message: "Migrations are enabled.")
                try performMigration()
            } else {
                migrationRunningLog.addEvent(message: "No migration needed")
            }
        } catch {
            migrationRunningLog.addEvent(message: "The migration failed: \(error.localizedDescription). Domain: \((error as NSError).domain)")
            throw migrationRunningLog
        }
                        
        migrationRunningLog.addEvent(message: "Creating the core data stack")

        self._coreDataStack = CoreDataStack(modelName: modelName, transactionAuthor: transactionAuthor)
        cleanOldTemporaryMigrationFiles()
    }
    
    private var _coreDataStack: CoreDataStack<PersistentContainerType>!
    public var coreDataStack: CoreDataStack<PersistentContainerType> {
        guard _coreDataStack != nil else {
            fatalError("The core data stack was not initialized. The initializeCoreDataStack() method must be called before trying to access the stack.")
        }
        return _coreDataStack!
    }
    
    public init(modelName: String, storeName: String, transactionAuthor: String, enableMigrations: Bool, migrationRunningLog: RunningLogError) {
        self.modelName = modelName
        self.storeName = storeName
        self.transactionAuthor = transactionAuthor
        self.enableMigrations = enableMigrations
        self.migrationRunningLog = migrationRunningLog
        let logCategory = "CoreDataStack-\(storeName)"
        self.log = OSLog(subsystem: "io.olvid.messenger", category: logCategory)
    }
    
    
    // MARK: - Persistent store
    
    lazy private var storeURL: URL = {
        let directory = PersistentContainerType.defaultDirectoryURL()
        let storeFileName = [storeName, "sqlite"].joined(separator: ".")
        let url = URL(fileURLWithPath: storeFileName, relativeTo: directory)
        os_log("Store URL is %{public}@", log: log, type: .info, url.path)
        return url
    }()
    
    private func storeExists() -> Bool {
        let res = FileManager.default.fileExists(atPath: storeURL.path)
        os_log("Core Data Store exists at %{public}@: %{public}@", log: log, type: .info, storeURL.path, res.description)
        return res
    }
    
    private func getSourceStoreMetadata(storeURL: URL) throws -> [String: Any] {
        let dict: [String: Any]
        dict = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL)
        return dict
    }
    
    
    // MARK: - Managed Object Models URLs
    
    // Returns one URL per model version. It does so by scanning all bundles. In each bundle, it looks for an appropriate `momd` folder and for all `mom` files within this folder. We expect exactly one bundle to contain appropriate `mom` files. If this is not the case, this method throws.
    private func getURLsOfAllManagedObjectModelVersions() throws -> [URL] {
        // We look for an array of URLs in the current bundle
        let bundle = Bundle(for: type(of: self))
        let momdSubdirectory = [self.modelName, "momd"].joined(separator: ".")
        guard let urls = bundle.urls(forResourcesWithExtension: "mom", subdirectory: momdSubdirectory) else {
            throw DataMigrationManager.makeError(message: "The call to urls(forResourcesWithExtension ext: String?, subdirectory subpath: String?) failed")
        }
        guard !urls.isEmpty else {
            throw DataMigrationManager.makeError(message: "The array of URLs returned by urls(forResourcesWithExtension ext: String?, subdirectory subpath: String?) is empty")
        }
        return urls
    }
    
    
    // MARK: - Managed Object Models
    
    public func getAllManagedObjectModels() throws -> [NSManagedObjectModel] {
        let urls = try getURLsOfAllManagedObjectModelVersions()
        let models = urls.compactMap { NSManagedObjectModel(contentsOf: $0) }
        return models
    }
    
    
    private func getDestinationManagedObjectModel() throws -> NSManagedObjectModel {
        let bundle = Bundle(for: type(of: self))
        guard let momdURL = bundle.url(forResource: modelName, withExtension: "momd") else {
            throw DataMigrationManager.makeError(message: "The call to url(forResource name: String?, withExtension ext: String?) -> URL? failed in getDestinationManagedObjectModel() throws")
        }
        guard let model = NSManagedObjectModel(contentsOf: momdURL) else {
            throw DataMigrationManager.makeError(message: "The call to the constructor of NSManagedObjectModel failed in getDestinationManagedObjectModel() throws")
        }
        return model
    }
    
    
    private func getStoreManagedObjectModel(storeURL: URL) throws -> NSManagedObjectModel {
        let storeMetadata = try getSourceStoreMetadata(storeURL: storeURL)
        
        let allModels = try getAllManagedObjectModels()
        for model in allModels {
            if model.isConfiguration(withName: nil, compatibleWithStoreMetadata: storeMetadata) {
                return model
            }
        }
        
        // If we reach this point, we could not find a model compatible with the store metadata
        // We log a few things to debug this situation
        migrationRunningLog.addEvent(message: "Could not determine the store managed object model on disk")
        do {
            logStoreMetadataTo(migrationRunningLog: migrationRunningLog, storeMetadata: storeMetadata)
            if let storeModelVersionIdentifiers = (storeMetadata[NSStoreModelVersionIdentifiersKey] as? NSArray)?.firstObject as? String {
                migrationRunningLog.addEvent(message: "The store model version identifier from the store metadadata found on disk is \(storeModelVersionIdentifiers)")
                if let model = allModels.first(where: { $0.versionIdentifier == storeModelVersionIdentifiers }) {
                    migrationRunningLog.addEvent(message: "We found a model having the version identifier \(storeModelVersionIdentifiers). Logging its details now.")
                    logNSManagedObjectModelTo(migrationRunningLog: migrationRunningLog, model: model)
                } else {
                    migrationRunningLog.addEvent(message: "Among all the models, we could not find a model having an identifier equal to \(storeModelVersionIdentifiers)")
                }
            } else {
                migrationRunningLog.addEvent(message: "Could not determine the store model version identifier from the store metadadata found on disk")
            }
        }
        
        throw DataMigrationManager.makeError(message: "Could not determine the store managed object model on disk")
    }
    
    
    private func logStoreMetadataTo(migrationRunningLog: RunningLogError, storeMetadata: [String: Any]) {
        migrationRunningLog.addEvent(message: "Content of Store Metadata on disk:")
        for (key, value) in storeMetadata {
            if key == "NSStoreModelVersionHashes", let modelVersionHashes = value as? [String: Data] {
                migrationRunningLog.addEvent(message: "  \(key) :")
                let sortedModelVersionHashes = modelVersionHashes.sorted { $0.key < $1.key }
                for (key, value) in sortedModelVersionHashes {
                    migrationRunningLog.addEvent(message: "    \(key) : \(value.hexString())")
                }
            } else {
                migrationRunningLog.addEvent(message: "  \(key) : \(String(describing: value))")
            }
        }
    }
    
    
    private func logNSManagedObjectModelTo(migrationRunningLog: RunningLogError, model: NSManagedObjectModel) {
        let entities = model.entities.sorted { ($0.name ?? "") < ($1.name ?? "") }
        for entity in entities {
            if let entityName = entity.name {
                migrationRunningLog.addEvent(message: "  \(entityName) : \(entity.versionHash.hexString())")
            } else {
                migrationRunningLog.addEvent(message: "  Entity without name : \(entity.versionHash.hexString())")
            }
        }
    }
    
    
    // MARK: - Is migration needed
    
    private func isMigrationNeeded() throws -> Bool {

        let destinationManagedObjectModel = try getDestinationManagedObjectModel()
        migrationRunningLog.addEvent(message: "Destination Managed Object Model: \(destinationManagedObjectModel.versionIdentifier)")
        let versionChecksum: String
        if #available(iOS 17, *) {
            versionChecksum = destinationManagedObjectModel.versionChecksum
        } else {
            versionChecksum = "Only available in iOS17+"
        }
        os_log("Destination Managed Object Model: %{public}@ with version checksum: %{public}@", log: log, type: .info, destinationManagedObjectModel.versionIdentifier, versionChecksum)

        let sourceStoreMetadata: [String: Any]
        do {
            sourceStoreMetadata = try getSourceStoreMetadata(storeURL: self.storeURL)
        } catch {
            migrationRunningLog.addEvent(message: "Failed to get source store metadata: \(error.localizedDescription)")
            os_log("Failed to get source store metadata: %{public}@", log: log, type: .fault, error.localizedDescription)
            logDebugInformation()
            assert(SQLITE_CORRUPT == 11)
            let nsError = error as NSError
            if (nsError.domain == NSSQLiteErrorDomain && nsError.code == SQLITE_CORRUPT) ||
                (nsError.domain == NSCocoaErrorDomain && nsError.code == NSPersistentStoreInvalidTypeError) {
                // If the database is corrupted, we know we won't be able to do anything with the file.
                // Before giving up, we look for another (not corrupted) .sqlite file in the same directory.
                // If non is found, we have no choice but to throw an error.
                // If one or more are found, we keep the one with the latest version, use it to replace the corrupted .sqlite file, and try again.
                migrationRunningLog.addEvent(message: "[RECOVERY] Since the database is corrupted, we try to recover")
                if let urlOfLatestUsableSQLiteFile = getURLOfLatestUsableSQLiteFile(distinctFrom: storeURL) {
                    
                    migrationRunningLog.addEvent(message: "[RECOVERY] We found a candidate for the database replacement: \(urlOfLatestUsableSQLiteFile.lastPathComponent)")
                    
                    // Step 1: remove all files relating to the corrupted database (in that order shm file -> wal file -> sqlite file)
                    let shmFile = self.storeURL.deletingPathExtension().appendingPathExtension("sqlite-shm")
                    let walFile = self.storeURL.deletingPathExtension().appendingPathExtension("sqlite-wal")
                    do {
                        if FileManager.default.fileExists(atPath: shmFile.path) {
                            migrationRunningLog.addEvent(message: "[RECOVERY] Deleting \(shmFile.lastPathComponent)")
                            try FileManager.default.removeItem(at: shmFile)
                        } else {
                            migrationRunningLog.addEvent(message: "[RECOVERY] No \(shmFile.lastPathComponent) to delete")
                        }
                        if FileManager.default.fileExists(atPath: walFile.path) {
                            migrationRunningLog.addEvent(message: "[RECOVERY] Deleting \(walFile.lastPathComponent)")
                            try FileManager.default.removeItem(at: walFile)
                        } else {
                            migrationRunningLog.addEvent(message: "[RECOVERY] No \(walFile.lastPathComponent) to delete")
                        }
                        if FileManager.default.fileExists(atPath: storeURL.path) {
                            migrationRunningLog.addEvent(message: "[RECOVERY] Deleting \(storeURL.lastPathComponent)")
                            try FileManager.default.removeItem(at: storeURL)
                        } else {
                            migrationRunningLog.addEvent(message: "[RECOVERY] No \(storeURL.lastPathComponent) to delete")
                        }
                    }
                    
                    // Step 2: move the latest usable SQLite file (and its associated files, in that order: sqlite file -> wal file -> shm file)
                    let shmFileSource = urlOfLatestUsableSQLiteFile.deletingPathExtension().appendingPathExtension("sqlite-shm")
                    let walFileSource = urlOfLatestUsableSQLiteFile.deletingPathExtension().appendingPathExtension("sqlite-wal")
                    try FileManager.default.moveItem(at: urlOfLatestUsableSQLiteFile, to: storeURL)
                    migrationRunningLog.addEvent(message: "[RECOVERY] Did move \(urlOfLatestUsableSQLiteFile.lastPathComponent) to \(storeURL.lastPathComponent)")
                    if FileManager.default.fileExists(atPath: walFileSource.path) {
                        try FileManager.default.moveItem(at: walFileSource, to: walFile)
                        migrationRunningLog.addEvent(message: "[RECOVERY] Did move \(walFileSource.lastPathComponent) to \(walFile.lastPathComponent)")
                    }
                    if FileManager.default.fileExists(atPath: shmFileSource.path) {
                        try FileManager.default.moveItem(at: shmFileSource, to: shmFile)
                        migrationRunningLog.addEvent(message: "[RECOVERY] Did move \(shmFileSource.lastPathComponent) to \(shmFile.lastPathComponent)")
                    }

                    // We have replaced the corrupted database found by the best possible candidate. Now we try again.
                    
                    migrationRunningLog.addEvent(message: "[RECOVERY] Done with recovery operations. We test again whether a migration is needed.")
                    return try isMigrationNeeded()
                }
                migrationRunningLog.addEvent(message: "[RECOVERY] We could not recover as no temporary SQLite file could be found")
            }
            throw error
        }
        
        migrationRunningLog.addEvent(message: "Just got the source store metada")
        os_log("Just got the source store metada", log: log, type: .info)

        if let sourceVersionIdentifier = (sourceStoreMetadata[NSStoreModelVersionIdentifiersKey] as? [Any])?.first as? String {
            migrationRunningLog.addEvent(message: "Source Store Model Version Identifier: \(sourceVersionIdentifier)")
            os_log("Source Store Model Version Identifier: %{public}@", log: log, type: .info, sourceVersionIdentifier)
        }

        return !destinationManagedObjectModel.isConfiguration(withName: nil,
                                                              compatibleWithStoreMetadata: sourceStoreMetadata)
    }
    
    
    // MARK: - Logging debug informations
    
    
    private let byteCountFormatter: ByteCountFormatter = {
        var bcf = ByteCountFormatter()
        return bcf
    }()
    
    
    private let dateFormatter: DateFormatter = {
        var df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }()
    
    
    private func getURLOfLatestUsableSQLiteFile(distinctFrom urlToSkip: URL) -> URL? {
        migrationRunningLog.addEvent(message: "[RECOVERY] Looking for the latest temporary SQLite file")
        var urlOfLatestSQLiteFile: URL?
        var modelVersionOfLatestSQLiteFile: String?
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: storeURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            let storeDirectory = storeURL.deletingLastPathComponent()
            migrationRunningLog.addEvent(message: "[RECOVERY] Looking for the latest temporary SQLite file in \(storeDirectory.path)")
            if let directoryContents = try? FileManager.default.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil) {
                for file in directoryContents {
                    guard file.pathExtension == "sqlite" && file != urlToSkip else { continue }
                    migrationRunningLog.addEvent(message: "[RECOVERY] Found an sqlite file: \(file.lastPathComponent)")
                    guard let sourceStoreMetadata = try? getSourceStoreMetadata(storeURL: file) else {
                        migrationRunningLog.addEvent(message: "[RECOVERY] Could not get metadata of file: \(file.lastPathComponent)")
                        continue
                    }
                    guard let sourceVersionIdentifier = (sourceStoreMetadata[NSStoreModelVersionIdentifiersKey] as? [Any])?.first as? String else {
                        assertionFailure()
                        migrationRunningLog.addEvent(message: "[RECOVERY] Could not get version identifier from source store metadata of file: \(file.lastPathComponent)")
                        continue
                    }
                    migrationRunningLog.addEvent(message: "[RECOVERY] The source version identifier of file \(file.lastPathComponent) is \(sourceVersionIdentifier)")
                    guard (try? modelVersion(sourceVersionIdentifier, isMoreRecentThan: modelVersionOfLatestSQLiteFile)) == true else {
                        migrationRunningLog.addEvent(message: "[RECOVERY] The file \(file.lastPathComponent) is not the latest")
                        continue
                    }
                    // We found a new latest candidate
                    migrationRunningLog.addEvent(message: "[RECOVERY] We found a new candidate for the latest temporary SQLite file: \(file.lastPathComponent)")
                    urlOfLatestSQLiteFile = file
                    modelVersionOfLatestSQLiteFile = sourceVersionIdentifier
                }
            }
        }
        if let urlOfLatestSQLiteFile {
            migrationRunningLog.addEvent(message: "[RECOVERY] Returning \(urlOfLatestSQLiteFile.lastPathComponent) as the latest temporary sqlite file")
        } else {
            migrationRunningLog.addEvent(message: "[RECOVERY] We could not find any temporary sqlite file")
        }
        return urlOfLatestSQLiteFile
    }

    
    /// As for now, this method is called when we fail to obtain (metada) information about the current version of the database and thus, fail to migrate to a new version.
    private func logDebugInformation() {
        
        migrationRunningLog.addEvent(message: "[DEBUG] Source Store URL: \(storeURL.debugDescription)")
        migrationRunningLog.addEvent(message: "[DEBUG] Model name: \(modelName)")

        // List the files in the source store URL (and remember sqlite files)
        var sqliteFiles = [URL]()
        do {
            var isDirectory: ObjCBool = false
            let resourceKeys = [URLResourceKey.fileSizeKey, .creationDateKey, .contentModificationDateKey, .attributeModificationDateKey]
            if FileManager.default.fileExists(atPath: storeURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    migrationRunningLog.addEvent(message: "[DEBUG] The storeURL is a directory, which is not expected")
                } else if let directoryContents = try? FileManager.default.contentsOfDirectory(at: storeURL.deletingLastPathComponent(), includingPropertiesForKeys: resourceKeys) {
                    migrationRunningLog.addEvent(message: "[DEBUG] Listing the files in \(storeURL.deletingLastPathComponent().path)")
                    for value in directoryContents.enumerated() {
                        var resourceString = [String]()
                        if let resourceValues = try? value.element.resourceValues(forKeys: Set(resourceKeys)) {
                            if let fileSize = resourceValues.fileSize {
                                resourceString.append("File size: \(byteCountFormatter.string(fromByteCount: Int64(fileSize)))")
                            }
                            if let creationDate = resourceValues.creationDate {
                                resourceString.append("Creation date: \(dateFormatter.string(from: creationDate))")
                            }
                            if let contentModificationDate = resourceValues.contentModificationDate {
                                resourceString.append("Content modification date: \(dateFormatter.string(from: contentModificationDate))")
                            }
                            if let attributeModificationDate = resourceValues.attributeModificationDate {
                                resourceString.append("Attribute modification date: \(dateFormatter.string(from: attributeModificationDate))")
                            }
                        }
                        let allResources = resourceString.joined(separator: ", ")
                        migrationRunningLog.addEvent(message: "[DEBUG] File \(value.offset): \(value.element.lastPathComponent) (\(allResources))")
                        if value.element.pathExtension == "sqlite" {
                            sqliteFiles.append(value.element)
                        }
                    }
                }
            }
        }
        
        // List all sqlite files
        
        migrationRunningLog.addEvent(message: "[DEBUG] Found \(sqliteFiles.count) sqlite files")
        
        for (offset, url) in sqliteFiles.enumerated() {
            migrationRunningLog.addEvent(message: "[DEBUG][\(offset)] \(url.path)")
            do {
                try logMetadaQueryOn(sqliteFile: url)
                if let model = try? getStoreManagedObjectModel(storeURL: url) {
                    migrationRunningLog.addEvent(message: "[DEBUG][\(offset)] The model version identifier is \(model.versionIdentifier)")
                } else {
                    migrationRunningLog.addEvent(message: "[DEBUG][\(offset)] Failed to determine the model version identifier")
                }
            } catch {
                // If we reach this point, we could not log metada informations about the sqlite file at `url`
                migrationRunningLog.addEvent(message: "[DEBUG][\(offset)] Failed to log metada on \(url.debugDescription): \(error.localizedDescription)")
            }
            
        }
        
    }

    
    private func createBackupOf(sqliteFile: URL) throws -> URL {
        
        // Open the database
        
        var db: OpaquePointer?
        do {
            let res = sqlite3_open(sqliteFile.path, &db)
            guard res == SQLITE_OK else {
                migrationRunningLog.addEvent(message: "[DEBUG] Could not open sqlite file \(sqliteFile.path). Error is \(res.description)")
                throw Self.makeError(message: res.description)
            }
        }
        
        guard let db else {
            migrationRunningLog.addEvent(message: "[DEBUG] Could not open sqlite file \(sqliteFile.path). The db point is nil")
            throw Self.makeError(message: "Unexpected error")
        }

        defer { sqlite3_close(db) }

        // Create the database to which we will backup records
        
        let backupSqliteFile = sqliteFile.deletingLastPathComponent().appendingPathComponent("backup-\(UUID().uuidString).sqlite")
        
        var backupDb: OpaquePointer?
        do {
            let res = sqlite3_open(backupSqliteFile.path, &backupDb)
            guard res == SQLITE_OK else {
                migrationRunningLog.addEvent(message: "[DEBUG] Could not open backup sqlite file \(sqliteFile.path). Error is \(res.description)")
                throw Self.makeError(message: res.description)
            }
        }

        guard let backupDb else {
            migrationRunningLog.addEvent(message: "[DEBUG] Could not open backup sqlite file \(backupSqliteFile.path). The backupDb point is nil")
            throw Self.makeError(message: "Unexpected error")
        }

        defer { sqlite3_close(backupDb) }

        // Initiate the backup
        
        let sql3Backup = sqlite3_backup_init(backupDb, "main" , db, "main")
        
        guard let sql3Backup else {
            migrationRunningLog.addEvent(message: "[DEBUG] Could not initiate backup of file \(sqliteFile.path)")
            throw Self.makeError(message: "[DEBUG] Could not initiate backup of file \(sqliteFile.path)")
        }

        // Perform the backup
        
        do {
            let res = sqlite3_backup_step(sql3Backup, -1)
            guard res == SQLITE_DONE else {
                migrationRunningLog.addEvent(message: "[DEBUG] Could not perform backup of sqlite file \(sqliteFile.path). Error is \(res.description)")
                throw Self.makeError(message: res.description)
            }
        }

        // Finish the backup
        
        do {
            let res = sqlite3_backup_finish(sql3Backup)
            guard res == SQLITE_OK else {
                migrationRunningLog.addEvent(message: "[DEBUG] Could not finish backup of sqlite file \(sqliteFile.path). Error is \(res.description)")
                throw Self.makeError(message: res.description)
            }
        }

        return backupSqliteFile
    }
    
    
    private func logMetadaQueryOn(sqliteFile: URL) throws {
        
        migrationRunningLog.addEvent(message: "[DEBUG] Performing a raw SQL query on \(sqliteFile.path)")
        
        // Open the database
        
        var db: OpaquePointer?
        do {
            let res = sqlite3_open(sqliteFile.path, &db)
            guard res == SQLITE_OK else {
                migrationRunningLog.addEvent(message: "[DEBUG] Could not open sqlite file \(sqliteFile.path). Error is \(res.description)")
                throw Self.makeError(message: res.description)
            }
        }
        
        guard let db else {
            migrationRunningLog.addEvent(message: "[DEBUG] Could not open sqlite file \(sqliteFile.path). The db point is nil")
            return
        }
                
        defer { sqlite3_close(db) }
        
        let statementString = "SELECT * FROM Z_METADATA;"
        var statement: OpaquePointer?
        do {
            let res = sqlite3_prepare_v2(db, statementString, -1, &statement, nil)
            guard res == SQLITE_OK else {
                migrationRunningLog.addEvent(message: "[DEBUG] Could not prepare statement for sqlite file \(sqliteFile.path). Error is \(res.description)")
                throw Self.makeError(message: res.description)
            }
        }
        
        while sqlite3_step(statement) == SQLITE_ROW {
            migrationRunningLog.addEvent(message: "[DEBUG] Found a metadata row")
            let version = sqlite3_column_int(statement, 0)
            migrationRunningLog.addEvent(message: "[DEBUG] Version is \(version)")
            if let rawBlob = sqlite3_column_blob(statement, 2) {
                let count = sqlite3_column_bytes(statement, 2)
                let blob = Data(bytes: rawBlob, count: Int(count))
                migrationRunningLog.addEvent(message: "[DEBUG] Blob length is \(blob.debugDescription) (typical is 3726 bytes)")
            }
        }

        sqlite3_finalize(statement)
        
    }


    // MARK: - Migrating
    
    
    private func generateDestinationStoreURLFromSourceStoreURL() -> URL {
        let sourceStoreDirectory = storeURL.deletingLastPathComponent()
        let sourceStoreFilename = storeURL.lastPathComponent
        let destinationFilename = [UUID().uuidString, sourceStoreFilename].joined(separator: ".")
        let destinationURL = URL.init(fileURLWithPath: destinationFilename, relativeTo: sourceStoreDirectory)
        return destinationURL
    }
    
    
    
    private final func performMigration() throws {
        
        migrationRunningLog.addEvent(message: "Starting migration of the Core Data Stack \(storeName)")
        
        os_log("Performing a migration for the Core Data Stack %{public}@", log: log, type: .info, storeName)

        migrationRunningLog.addEvent(message: "Trying to determine the model of the store on disk...")
        
        var currentStoreModel = try getStoreManagedObjectModel(storeURL: self.storeURL)
        
        migrationRunningLog.addEvent(message: "The current model of the store on disk is \(currentStoreModel.versionIdentifier)")

        while try !managedObjectModelIsLatestVersion(currentStoreModel) {
            
            migrationRunningLog.addEvent(message: "--- Starting migration step")
            
            migrationRunningLog.addEvent(message: "Trying to determine the next destination model...")

            let (destinationModel, migrationType) = try getNextManagedObjectModelVersion(from: currentStoreModel)
            
            migrationRunningLog.addEvent(message: "We will try to migrate from model \(currentStoreModel.versionIdentifier) to model \(destinationModel.versionIdentifier) using a \(migrationType) migration")

            let bundle = Bundle(for: type(of: self))
                        
            let mappingModel: NSMappingModel
            switch migrationType {
            case .heavyweight:
                migrationRunningLog.addEvent(message: "Trying to obtain an explicit mapping from model \(currentStoreModel.versionIdentifier) to model \(destinationModel.versionIdentifier)...")
                guard let explicitMapping = NSMappingModel(from: [bundle], forSourceModel: currentStoreModel, destinationModel: destinationModel) else {
                    migrationRunningLog.addEvent(message: "We could not find an explicit mapping for migrating from \(currentStoreModel.versionIdentifier) to model \(destinationModel.versionIdentifier)")
                    throw DataMigrationManager.makeError(message: "Could not find mapping model for migrating from store model (\(currentStoreModel.versionIdentifier)) to destination model (\(destinationModel.versionIdentifier))")
                }
                /* Prefix each migration policy class name with the executable name. This avoid specifying this information as a prefix each time we define a custom policy in our
                 * xcmappingmodel files. This also allows to be more resilient to Xcode changes, like the one we experienced from Xcode 12.4 to Xcode 12.5, which changes the executable
                 * name, causing migration errors.
                 */
                do {
                    if let namespace = bundle.infoDictionary?["CFBundleName"] as? String {
                        explicitMapping.entityMappings.forEach { entityMapping in
                            if let entityMigrationPolicyClassName = entityMapping.entityMigrationPolicyClassName {
                                entityMapping.entityMigrationPolicyClassName = [namespace, entityMigrationPolicyClassName].joined(separator: ".")
                            }
                        }
                    } else {
                        assertionFailure()
                    }
                }
                mappingModel = explicitMapping
            case .lightweight:
                do {
                    migrationRunningLog.addEvent(message: "Trying to infer a mapping from model \(currentStoreModel.versionIdentifier) to model \(destinationModel.versionIdentifier)...")
                    mappingModel = try NSMappingModel.inferredMappingModel(forSourceModel: currentStoreModel, destinationModel: destinationModel)
                } catch {
                    migrationRunningLog.addEvent(message: "Could not infer mapping for migrating from \(currentStoreModel.versionIdentifier) to model \(destinationModel.versionIdentifier)")
                    throw error
                }
            }
            
            let migrationManager = NSMigrationManager(sourceModel: currentStoreModel, destinationModel: destinationModel)
            
            let destinationStoreURL = generateDestinationStoreURLFromSourceStoreURL()

            // Extract the source store options
            let sourceOptions: [String: NSObject]
            do {
                let currentContainer = PersistentContainerType(name: modelName)
                let descriptions = currentContainer.persistentStoreDescriptions
                // We only support migration for one persistent store
                guard descriptions.count == 1 else {
                    throw DataMigrationManager.makeError(message: "Unexpected number of persistent store descriptions. Expecting 1, got \(descriptions.count).")
                }
                sourceOptions = descriptions.first!.options
            }
            let destinationOptions = sourceOptions // The new store should have the same options as the source

            migrationRunningLog.addEvent(message: "Performing pre-migration work...")
            os_log("Performing pre-migration work", log: log, type: .info)
            
            try performPreMigrationWork(forSourceModel: currentStoreModel, destinationModel: destinationModel)

            migrationRunningLog.addEvent(message: "Migrating the store from \(currentStoreModel.versionIdentifier) to \(destinationModel.versionIdentifier)")
            os_log("Starting the store migration", log: log, type: .info)

            let migrationProgress = Progress(totalUnitCount: 1000)
            kvObservations.append(migrationManager.observe(\.migrationProgress) { _, _ in
                migrationProgress.completedUnitCount = Int64(1000*migrationManager.migrationProgress)
            })
            DataMigrationManagerNotification.migrationManagerWillMigrateStore(observableProgress: migrationProgress, storeName: storeName)
                .postOnDispatchQueue()
            do {
                try migrationManager.migrateStore(from: storeURL,
                                                  sourceType: NSSQLiteStoreType,
                                                  options: sourceOptions,
                                                  with: mappingModel,
                                                  toDestinationURL: destinationStoreURL,
                                                  destinationType: NSSQLiteStoreType,
                                                  destinationOptions: destinationOptions)
            } catch {
                if FileManager.default.isDeletableFile(atPath: destinationStoreURL.path) {
                    try? FileManager.default.removeItem(at: destinationStoreURL)
                }
                migrationRunningLog.addEvent(message: "The call to migrateStore failed: \(error.localizedDescription))")
                throw error
            }

            migrationRunningLog.addEvent(message: "The store was migrated from \(currentStoreModel.versionIdentifier) to \(destinationModel.versionIdentifier)")
            os_log("The store was migrated", log: log, type: .info)

            let psc = NSPersistentStoreCoordinator(managedObjectModel: destinationModel)

            migrationRunningLog.addEvent(message: "Replacing the persistent store...")
            os_log("Replacing persistent store", log: log, type: .info)

            try psc.replacePersistentStore(at: storeURL,
                                           destinationOptions: nil,
                                           withPersistentStoreFrom: destinationStoreURL,
                                           sourceOptions: nil,
                                           ofType: NSSQLiteStoreType)

            migrationRunningLog.addEvent(message: "The persistent store was replaced")
            os_log("The persistent store was replaced", log: log, type: .info)

            migrationRunningLog.addEvent(message: "Destroying the previous store...")
            os_log("Destroying the previous store", log: log, type: .info)

            try psc.destroyPersistentStore(at: destinationStoreURL,
                                           ofType: NSSQLiteStoreType,
                                           options: nil)

            migrationRunningLog.addEvent(message: "The previous store was destroyed")
            os_log("Previous store was destroyed", log: log, type: .info)

            if FileManager.default.isDeletableFile(atPath: destinationStoreURL.path) {
                try? FileManager.default.removeItem(at: destinationStoreURL)
            }
            
            
            migrationRunningLog.addEvent(message: "Determining the new store model...")
            currentStoreModel = try getStoreManagedObjectModel(storeURL: self.storeURL)
            
            migrationRunningLog.addEvent(message: "The (new) store model on disk is \(currentStoreModel.versionIdentifier)")

            migrationRunningLog.addEvent(message: "--- Ending migration step")

        }
        
        migrationRunningLog.addEvent(message: "We reached the latest version of the model: \(currentStoreModel.versionIdentifier)")

    }
    
    
    open func managedObjectModelIsLatestVersion(_: NSManagedObjectModel) throws -> Bool {
        fatalError("Must be overwritten by subclass")
    }
    
    
    open func getNextManagedObjectModelVersion(from sourceModel: NSManagedObjectModel) throws -> (destinationModel: NSManagedObjectModel, migrationType: MigrationType) {
        fatalError("Must be overwritten by subclass")
    }
    
    
    open func performPreMigrationWork(forSourceModel sourceModel: NSManagedObjectModel, destinationModel: NSManagedObjectModel) throws {
        fatalError("Must be overwritten by subclass")
    }

    
    open func modelVersion(_ rawModelVersion: String, isMoreRecentThan otherRawModelVersion: String?) throws -> Bool {
        fatalError("Must be overwritten by subclass")
    }
    
}


fileprivate extension Data {
    
    func hexString() -> String {
        return self.map { String(format: "%02hhx", $0) }.joined()
    }
    
}


fileprivate extension NSManagedObjectModel {
    
    var versionIdentifier: String {
        guard !versionIdentifiers.isEmpty else { return "ERROR_NONE" }
        guard versionIdentifiers.count == 1 else { return "ERROR_MULTIPLE_VALUES" }
        guard let identifier = versionIdentifiers.first as? String else { return "ERROR_NOT_A_STRING" }
        return identifier
    }
    
}
