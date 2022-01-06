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

open class DataMigrationManager<PersistentContainerType: NSPersistentContainer> {
    
    private let enableMigrations: Bool
    public let migrationRunningLog: RunningLogError
    public let modelName: String
    private let storeName: String
    private let transactionAuthor: String
    private let log = OSLog(subsystem: "io.olvid.messenger", category: "CoreDataStack")
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
    }
    
    
    // MARK: - Persistent store
    
    private var storeURL: URL {
        let directory = PersistentContainerType.defaultDirectoryURL()
        let storeFileName = [storeName, "sqlite"].joined(separator: ".")
        let url = URL(fileURLWithPath: storeFileName, relativeTo: directory)
        debugPrint("Store URL is: \(url)")
        return url
    }
    
    private func storeExists() -> Bool {
        let res = FileManager.default.fileExists(atPath: storeURL.path)
        os_log("Core Data Store exists at %{public}@: %{public}@", log: log, type: .info, storeURL.path, res.description)
        return res
    }
    
    private func getSourceStoreMetadata() throws -> [String: Any] {
        let dict = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType,
                                                                               at: storeURL,
                                                                               options: nil)
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
        // Hack required for the 18th version of the database
        let filteredURLs: [URL]
        if #available(iOS 13, *) {
            filteredURLs = urls
        } else {
            filteredURLs = urls.filter({$0.lastPathComponent != "ObvMessenger 18.mom"})
        }
        // End Hack
        let models = filteredURLs.compactMap { NSManagedObjectModel(contentsOf: $0) }
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
    
    
    private func getStoreManagedObjectModel() throws -> NSManagedObjectModel {
        let storeMetadata = try getSourceStoreMetadata()
        let allModels = try getAllManagedObjectModels()
        for model in allModels {
            if model.isConfiguration(withName: nil, compatibleWithStoreMetadata: storeMetadata) {
                return model
            }
        }
        migrationRunningLog.addEvent(message: "Could not determine the store managed object model on disk")
        throw DataMigrationManager.makeError(message: "Could not determine the store managed object model on disk")
    }
    
    
    // MARK: - Is migration needed
    
    private func isMigrationNeeded() throws -> Bool {

        let destinationManagedObjectModel = try getDestinationManagedObjectModel()
        migrationRunningLog.addEvent(message: "Destination Managed Object Model: \(destinationManagedObjectModel.versionIdentifier)")
        os_log("Destination Managed Object Model: %{public}@", log: log, type: .info, destinationManagedObjectModel.versionIdentifier)

        let sourceStoreMetadata = try getSourceStoreMetadata()
        if let sourceVersionIdentifier = (sourceStoreMetadata[NSStoreModelVersionIdentifiersKey] as? [Any])?.first as? String {
            migrationRunningLog.addEvent(message: "Source Store Model Version Identifier: \(sourceVersionIdentifier)")
            os_log("Source Store Model Version Identifier: %{public}@", log: log, type: .info, sourceVersionIdentifier)
        }

        return !destinationManagedObjectModel.isConfiguration(withName: nil,
                                                              compatibleWithStoreMetadata: sourceStoreMetadata)
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
        
        var currentStoreModel = try getStoreManagedObjectModel()
        
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
            currentStoreModel = try getStoreManagedObjectModel()
            
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
