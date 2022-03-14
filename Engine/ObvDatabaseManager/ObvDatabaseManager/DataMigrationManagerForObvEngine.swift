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
import CoreDataStack
import os.log
import SQLite3

final class DataMigrationManagerForObvEngine: DataMigrationManager<ObvEnginePersistentContainer> {
    
    private let log = OSLog(subsystem: "io.olvid.messenger", category: "CoreDataStack")

    private static let errorDomain = "DataMigrationManagerForObvEngine"
    
    private func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: DataMigrationManagerForObvEngine.errorDomain, code: 0, userInfo: userInfo)
    }

    enum ObvEngineModelVersion: String {
        
        case version1 = "ObvEngineModel-v1"
        case version2 = "ObvEngineModel-v2"
        case version3 = "ObvEngineModel-v3"
        case version4 = "ObvEngineModel-v4"
        case version5 = "ObvEngineModel-v5"
        case version6 = "ObvEngineModel-v6"
        case version7 = "ObvEngineModel-v7"
        case version8 = "ObvEngineModel-v8"
        case version9 = "ObvEngineModel-v9"
        case version10 = "ObvEngineModel-v10"
        case version11 = "ObvEngineModel-v11"
        case version12 = "ObvEngineModel-v12"
        case version13 = "ObvEngineModel-v13"
        case version14 = "ObvEngineModel-v14"
        case version15 = "ObvEngineModel-v15"
        case version16 = "ObvEngineModel-v16"
        case version17 = "ObvEngineModel-v17"
        case version18 = "ObvEngineModel-v18"
        case version19 = "ObvEngineModel-v19"
        case version20 = "ObvEngineModel-v20"
        case version21 = "ObvEngineModel-v21"
        case version22 = "ObvEngineModel-v22"
        case version23 = "ObvEngineModel-v23"
        case version24 = "ObvEngineModel-v24"
        case version25 = "ObvEngineModel-v25"
        case version26 = "ObvEngineModel-v26"
        case version27 = "ObvEngineModel-v27"
        case version28 = "ObvEngineModel-v28"
        case version29 = "ObvEngineModel-v29"
        case version30 = "ObvEngineModel-v30"
        case version31 = "ObvEngineModel-v31"
        case version32 = "ObvEngineModel-v32"
        case version33 = "ObvEngineModel-v33"
        case version34 = "ObvEngineModel-v34"
        case version35 = "ObvEngineModel-v35"
        case version36 = "ObvEngineModel-v36"

        static var latest: ObvEngineModelVersion {
            return .version36
        }
        
        var identifier: String {
            return self.rawValue
        }
        
        init(model: NSManagedObjectModel) throws {
            guard model.versionIdentifiers.count == 1 else { throw NSError() }
            guard let versionIdentifier = model.versionIdentifiers.first! as? String else { throw NSError() }
            guard let version = ObvEngineModelVersion(rawValue: versionIdentifier) else { throw NSError() }
            self = version
        }
        
    }

    
    private func getManagedObjectModel(version: ObvEngineModelVersion) throws -> NSManagedObjectModel {
        let allModels = try getAllManagedObjectModels()
        let model = try allModels.filter {
            guard $0.versionIdentifiers.count == 1 else { throw NSError() }
            guard let versionIdentifier = $0.versionIdentifiers.first! as? String else { throw NSError() }
            return versionIdentifier == version.identifier
        }
        guard model.count == 1 else { throw NSError() }
        return model.first!
    }

    
    override func getNextManagedObjectModelVersion(from sourceModel: NSManagedObjectModel) throws -> (destinationModel: NSManagedObjectModel, migrationType: MigrationType) {
        
        let sourceVersion = try ObvEngineModelVersion(model: sourceModel)
        
        os_log("Current version of the Engine's Core Data Stack: %{public}@", log: log, type: .info, sourceVersion.identifier)
        
        let destinationVersion: ObvEngineModelVersion
        let migrationType: MigrationType
        switch sourceVersion {
        case .version1: migrationType = .heavyweight; destinationVersion = .version2
        case .version2: migrationType = .heavyweight; destinationVersion = .version3
        case .version3: migrationType = .heavyweight; destinationVersion = .version4
        case .version4: migrationType = .heavyweight; destinationVersion = .version5
        case .version5: migrationType = .heavyweight; destinationVersion = .version6
        case .version6: migrationType = .heavyweight; destinationVersion = .version7
        case .version7: migrationType = .heavyweight; destinationVersion = .version8
        case .version8: migrationType = .heavyweight; destinationVersion = .version9
        case .version9: migrationType = .heavyweight; destinationVersion = .version10
        case .version10: migrationType = .heavyweight; destinationVersion = .version11
        case .version11: migrationType = .heavyweight; destinationVersion = .version12
        case .version12: migrationType = .heavyweight; destinationVersion = .version13
        case .version13: migrationType = .heavyweight; destinationVersion = .version14
        case .version14: migrationType = .heavyweight; destinationVersion = .version15
        case .version15: migrationType = .heavyweight; destinationVersion = .version16
        case .version16: migrationType = .heavyweight; destinationVersion = .version17
        case .version17: migrationType = .heavyweight; destinationVersion = .version18
        case .version18: migrationType = .lightweight; destinationVersion = .version19
        case .version19: migrationType = .heavyweight; destinationVersion = .version20
        case .version20: migrationType = .heavyweight; destinationVersion = .version21
        case .version21: migrationType = .heavyweight; destinationVersion = .version23 // Correct
        case .version22: migrationType = .lightweight; destinationVersion = .version21 // Correct
        case .version23: migrationType = .lightweight; destinationVersion = .version24
        case .version24: migrationType = .heavyweight; destinationVersion = .version25
        case .version25: migrationType = .lightweight; destinationVersion = .version26
        case .version26: migrationType = .heavyweight; destinationVersion = .version27
        case .version27: migrationType = .heavyweight; destinationVersion = .version28
        case .version28: migrationType = .heavyweight; destinationVersion = .version29
        case .version29: migrationType = .heavyweight; destinationVersion = .version30
        case .version30: migrationType = .heavyweight; destinationVersion = .version31
        case .version31: migrationType = .lightweight; destinationVersion = .version32
        case .version32: migrationType = .lightweight; destinationVersion = .version33
        case .version33: migrationType = .lightweight; destinationVersion = .version34
        case .version34: migrationType = .heavyweight; destinationVersion = .version35
        case .version35: migrationType = .lightweight; destinationVersion = .version36
        case .version36: migrationType = .heavyweight; destinationVersion = .version36
        }
        
        let destinationModel = try getManagedObjectModel(version: destinationVersion)
        
        os_log("Performing a %{public}@ migration of the ObvEngineModel from version %{public}@ to %{public}@", log: log, type: .info, migrationType.debugDescription, sourceVersion.identifier, destinationVersion.identifier)
        
        return (destinationModel, migrationType)
        
    }

    
    override func managedObjectModelIsLatestVersion(_ model: NSManagedObjectModel) throws -> Bool {
        let modelVersion = try ObvEngineModelVersion(model: model)
        return modelVersion == .latest
    }

    
    override func performPreMigrationWork(forSourceModel sourceModel: NSManagedObjectModel, destinationModel: NSManagedObjectModel) throws {

        let sourceModelVersion = try ObvEngineModelVersion(model: sourceModel)
        let destinationModelVersion = try ObvEngineModelVersion(model: destinationModel)
        
        switch (sourceModelVersion, destinationModelVersion) {
        case (.version21, .version23):
            try deleteOldExpiredKeyMaterialsUsingSQLite()
        default:
            break
        }

    }
    
    
}


// MARK: - Utils for pre-migration work

extension DataMigrationManagerForObvEngine {
    
    private func deleteOldExpiredKeyMaterialWithinModelV21(temporaryContainer: NSPersistentContainer) throws {
        let context = temporaryContainer.newBackgroundContext()
        var error: Error?
        context.performAndWait {
            do {
                try deleteOldExpiredKeyMaterialsUsingSQLite()
            } catch let _error {
                error = _error
            }
        }
        guard error == nil else { throw error! }
    }

    
    private func deleteOldExpiredKeyMaterialsUsingSQLite() throws {
        
        os_log("Starting the deletion of old expired key materials", log: log, type: .info)
        
        guard let containerURL = ObvDatabaseManager.containerURL else {
            throw makeError(message: "ObvDatabaseManager.containerURL not set in deleteOldExpiredKeyMaterialsUsingSQLite")
        }
        
        let storeURL = containerURL.appendingPathComponent("\(modelName).sqlite")
                
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            throw makeError(message: "Cannot find \(modelName).sqlite in container within deleteOldExpiredKeyMaterialsUsingSQLite")
        }
        
        // Open the database
        
        var db: OpaquePointer?
        guard sqlite3_open(storeURL.path, &db) == SQLITE_OK else {
            throw makeError(message: "Could not open database with SQLite for deleting old expired key materials")
        }
                
        defer {
            sqlite3_close(db!)
        }
        
        let startTimestamp = Date()
        
        let deleteStatementString = "DELETE FROM ZKEYMATERIAL WHERE ZEXPIRATIONTIMESTAMP IS NOT NULL AND ZEXPIRATIONTIMESTAMP < \(NSDate().timeIntervalSinceReferenceDate)"
        var deleteStatement: OpaquePointer?
        if sqlite3_prepare_v2(db, deleteStatementString, -1, &deleteStatement, nil) == SQLITE_OK {
          if sqlite3_step(deleteStatement) == SQLITE_DONE {
            os_log("Successfully deleted old key materials", log: log, type: .info)
          } else {
            os_log("Could not delete old key materials", log: log, type: .fault)
          }
        } else {
            os_log("Could not delete old key materials (DELETE statement could not be prepared)", log: log, type: .fault)
            throw makeError(message: "Could not delete old key materials (DELETE statement could not be prepared)")
        }

        sqlite3_finalize(deleteStatement)

        let stopTimestamp = Date()
        let timeRequired = stopTimestamp.timeIntervalSince(startTimestamp)

        os_log("Number of seconds that were required to delete the old key materials: %{public}f", log: log, type: .info, timeRequired)
        
    }
    
}
