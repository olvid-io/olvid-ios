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
import OlvidUtils

final class DataMigrationManagerForObvMessenger: DataMigrationManager<ObvMessengerPersistentContainer>, ObvErrorMaker {

    private let log = OSLog(subsystem: "io.olvid.messenger", category: "CoreDataStack")
    static let errorDomain = "DataMigrationManagerForObvMessenger"

    enum ObvMessengerModelVersion: String {

        case version1 = "ObvMessengerModel-v1"
        case version2 = "ObvMessengerModel-v2"
        case version3 = "ObvMessengerModel-v3"
        case version4 = "ObvMessengerModel-v4"
        case version5 = "ObvMessengerModel-v5"
        case version6 = "ObvMessengerModel-v6"
        case version7 = "ObvMessengerModel-v7"
        case version8 = "ObvMessengerModel-v8"
        case version9 = "ObvMessengerModel-v9"
        case version10 = "ObvMessengerModel-v10"
        case version11 = "ObvMessengerModel-v11"
        case version12 = "ObvMessengerModel-v12"
        case version13 = "ObvMessengerModel-v13"
        case version14 = "ObvMessengerModel-v14"
        case version15 = "ObvMessengerModel-v15"
        case version16 = "ObvMessengerModel-v16"
        case version17 = "ObvMessengerModel-v17"
        case version18 = "ObvMessengerModel-v18"
        case version19 = "ObvMessengerModel-v19"
        case version20 = "ObvMessengerModel-v20"
        case version21 = "ObvMessengerModel-v21"
        case version22 = "ObvMessengerModel-v22"
        case version23 = "ObvMessengerModel-v23"
        case version24 = "ObvMessengerModel-v24"
        case version25 = "ObvMessengerModel-v25"
        case version26 = "ObvMessengerModel-v26"
        case version27 = "ObvMessengerModel-v27"
        case version28 = "ObvMessengerModel-v28"
        case version29 = "ObvMessengerModel-v29"
        case version30 = "ObvMessengerModel-v30"
        case version31 = "ObvMessengerModel-v31"
        case version32 = "ObvMessengerModel-v32"
        case version33 = "ObvMessengerModel-v33"
        case version34 = "ObvMessengerModel-v34"
        case version35 = "ObvMessengerModel-v35"
        case version36 = "ObvMessengerModel-v36"
        case version37 = "ObvMessengerModel-v37"
        case version38 = "ObvMessengerModel-v38"
        case version39 = "ObvMessengerModel-v39"
        case version40 = "ObvMessengerModel-v40"
        case version41 = "ObvMessengerModel-v41"
        case version42 = "ObvMessengerModel-v42"
        case version43 = "ObvMessengerModel-v43"
        case version44 = "ObvMessengerModel-v44"
        case version45 = "ObvMessengerModel-v45"
        case version46 = "ObvMessengerModel-v46"
        case version47 = "ObvMessengerModel-v47"
        case version48 = "ObvMessengerModel-v48"
        case version49 = "ObvMessengerModel-v49"
        case version50 = "ObvMessengerModel-v50"
        case version51 = "ObvMessengerModel-v51"
        case version52 = "ObvMessengerModel-v52"
        case version53 = "ObvMessengerModel-v53"
        case version54 = "ObvMessengerModel-v54"
        case version55 = "ObvMessengerModel-v55"
        case version56 = "ObvMessengerModel-v56"
        case version57 = "ObvMessengerModel-v57"
        case version58 = "ObvMessengerModel-v58"
        case version59 = "ObvMessengerModel-v59"
        case version60 = "ObvMessengerModel-v60"
        case version61 = "ObvMessengerModel-v61"

        static var latest: ObvMessengerModelVersion {
            return .version61
        }

        var identifier: String {
            return self.rawValue
        }
        
        var intValue: Int? {
            let digits = self.rawValue.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
            let intValue = Int(digits)
            assert(intValue != nil)
            return intValue
        }

        init(model: NSManagedObjectModel) throws {
            guard model.versionIdentifiers.count == 1 else {
                throw DataMigrationManagerForObvMessenger.makeError(message: "Unexpected number of version identifiers found. Got \(model.versionIdentifiers.count) although 1 is expected")
            }
            guard let versionIdentifier = model.versionIdentifiers.first! as? String else {
                throw DataMigrationManagerForObvMessenger.makeError(message: "Could not recover the version identifier of the model")
            }
            guard let version = ObvMessengerModelVersion.init(rawValue: versionIdentifier) else {
                throw DataMigrationManagerForObvMessenger.makeError(message: "Could not cast the version identifier of the model")
            }
            self = version
        }

    }


    private func getManagedObjectModel(version: ObvMessengerModelVersion) throws -> NSManagedObjectModel {
        let allModels = try getAllManagedObjectModels()
        let model = try allModels.filter {
            guard $0.versionIdentifiers.count == 1 else {
                throw Self.makeError(message: "Unexpected count of version identifiers. Expecting 1, got \($0.versionIdentifiers.count)")
            }
            guard let versionIdentifier = $0.versionIdentifiers.first! as? String else {
                throw Self.makeError(message: "Could not cast the version identifier")
            }
            return versionIdentifier == version.identifier
        }
        guard model.count == 1 else {
            throw Self.makeError(message: "After filtering all available models, \(model.count) appropriate models were found instead of 1")
        }
        return model.first!
    }
    
    
    override func modelVersion(_ rawModelVersion: String, isMoreRecentThan otherRawModelVersion: String?) throws -> Bool {
        guard let otherRawModelVersion else { return true }
        guard let otherModelVersion = ObvMessengerModelVersion(rawValue: otherRawModelVersion) else {
            assertionFailure()
            throw Self.makeError(message: "Could not parse other raw model version")
        }
        guard let modelVersion = ObvMessengerModelVersion(rawValue: rawModelVersion) else {
            assertionFailure()
            throw Self.makeError(message: "Could not parse raw model version")
        }
        guard let otherModelVersionAsInt = otherModelVersion.intValue else {
            assertionFailure()
            throw Self.makeError(message: "Could not determine int value from other model version")
        }
        guard let modelVersionAsInt = modelVersion.intValue else {
            assertionFailure()
            throw Self.makeError(message: "Could not determine int value from model version")
        }
        return modelVersionAsInt > otherModelVersionAsInt
    }


    override func getNextManagedObjectModelVersion(from sourceModel: NSManagedObjectModel) throws -> (destinationModel: NSManagedObjectModel, migrationType: DataMigrationManager<ObvMessengerPersistentContainer>.MigrationType) {

        let sourceVersion = try ObvMessengerModelVersion(model: sourceModel)

        os_log("Current version of the App's Core Data Stack: %{public}@", log: log, type: .info, sourceVersion.identifier)

        let destinationVersion: ObvMessengerModelVersion
        let migrationType: MigrationType
        switch sourceVersion {
        case .version1: migrationType = .lightweight; destinationVersion = .version2
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
        case .version17: migrationType = .heavyweight; destinationVersion = .version19 // Don't change this
        case .version18: migrationType = .heavyweight; destinationVersion = .version19
        case .version19: migrationType = .heavyweight; destinationVersion = .version20
        case .version20: migrationType = .lightweight; destinationVersion = .version21
        case .version21: migrationType = .heavyweight; destinationVersion = .version23 // Don't change this
        case .version22: migrationType = .heavyweight; destinationVersion = .version23
        case .version23: migrationType = .heavyweight; destinationVersion = .version24
        case .version24: migrationType = .heavyweight; destinationVersion = .version25
        case .version25: migrationType = .heavyweight; destinationVersion = .version26
        case .version26: migrationType = .heavyweight; destinationVersion = .version27
        case .version27: migrationType = .heavyweight; destinationVersion = .version28
        case .version28: migrationType = .heavyweight; destinationVersion = .version29
        case .version29: migrationType = .heavyweight; destinationVersion = .version30
        case .version30: migrationType = .heavyweight; destinationVersion = .version31
        case .version31: migrationType = .lightweight; destinationVersion = .version32
        case .version32: migrationType = .lightweight; destinationVersion = .version33
        case .version33: migrationType = .lightweight; destinationVersion = .version34
        case .version34: migrationType = .lightweight; destinationVersion = .version35
        case .version35: migrationType = .lightweight; destinationVersion = .version36
        case .version36: migrationType = .lightweight; destinationVersion = .version37
        case .version37: migrationType = .lightweight; destinationVersion = .version38
        case .version38: migrationType = .heavyweight; destinationVersion = .version39
        case .version39: migrationType = .lightweight; destinationVersion = .version40
        case .version40: migrationType = .lightweight; destinationVersion = .version41
        case .version41: migrationType = .lightweight; destinationVersion = .version42
        case .version42: migrationType = .heavyweight; destinationVersion = .version43
        case .version43: migrationType = .heavyweight; destinationVersion = .version44
        case .version44: migrationType = .heavyweight; destinationVersion = .version45
        case .version45: migrationType = .lightweight; destinationVersion = .version46
        case .version46: migrationType = .lightweight; destinationVersion = .version47
        case .version47: migrationType = .lightweight; destinationVersion = .version48
        case .version48: migrationType = .heavyweight; destinationVersion = .version49
        case .version49: migrationType = .heavyweight; destinationVersion = .version50
        case .version50: migrationType = .lightweight; destinationVersion = .version51
        case .version51: migrationType = .lightweight; destinationVersion = .version52
        case .version52: migrationType = .lightweight; destinationVersion = .version53
        case .version53: migrationType = .lightweight; destinationVersion = .version54
        case .version54: migrationType = .heavyweight; destinationVersion = .version55
        case .version55: migrationType = .heavyweight; destinationVersion = .version56
        case .version56: migrationType = .lightweight; destinationVersion = .version57
        case .version57: migrationType = .lightweight; destinationVersion = .version58
        case .version58: migrationType = .heavyweight; destinationVersion = .version59
        case .version59: migrationType = .lightweight; destinationVersion = .version60
        case .version60: migrationType = .lightweight; destinationVersion = .version61
        case .version61: migrationType = .heavyweight; destinationVersion = .version61
        }
        
        let destinationModel = try getManagedObjectModel(version: destinationVersion)

        os_log("Performing a %{public}@ migration of the ObvMessengerModel from version %{public}@ to %{public}@", log: log, type: .info, migrationType.debugDescription, sourceVersion.identifier, destinationVersion.identifier)

        return (destinationModel, migrationType)

    }


    override func managedObjectModelIsLatestVersion(_ model: NSManagedObjectModel) throws -> Bool {
        let modelVersion = try ObvMessengerModelVersion(model: model)
        return modelVersion == .latest
    }


    override func performPreMigrationWork(forSourceModel sourceModel: NSManagedObjectModel, destinationModel: NSManagedObjectModel) throws {
        try performPreMigrationWorkOnV28(forSourceModel: sourceModel)
        try performPreMigrationWorkOnV29(forSourceModel: sourceModel)
    }

}


// MARK: - Specific pre migration work

extension DataMigrationManagerForObvMessenger {

    private func performPreMigrationWorkOnV29(forSourceModel sourceModel: NSManagedObjectModel) throws {

        let currentModelVersion = try ObvMessengerModelVersion(model: sourceModel)
        guard currentModelVersion == .version29 else { return }

        migrationRunningLog.addEvent(message: "Performing pre-migration work on v29")
        defer {
            migrationRunningLog.addEvent(message: "The pre-migration work on v29")
        }

        let currentContainer = ObvMessengerPersistentContainer(name: modelName, managedObjectModel: sourceModel)
        currentContainer.loadPersistentStores { [weak self] description, error in
            guard let _self = self else { return }
            guard error == nil else {
                _self.migrationRunningLog.addEvent(message: "Could not perform pre-migration work on v29. Could not load persistent stores: \(error!.localizedDescription)")
                return
            }
        }

        deleteOrphanedPersistedExpirationForReceivedMessageWithLimitedVisibility(currentContainer: currentContainer)

    }


    private func performPreMigrationWorkOnV28(forSourceModel sourceModel: NSManagedObjectModel) throws {

        let currentModelVersion = try ObvMessengerModelVersion(model: sourceModel)
        guard currentModelVersion == .version28 else { return }

        migrationRunningLog.addEvent(message: "Performing pre-migration work on v28")
        defer {
            migrationRunningLog.addEvent(message: "The pre-migration work on v28")
        }

        let currentContainer = ObvMessengerPersistentContainer(name: modelName, managedObjectModel: sourceModel)
        currentContainer.loadPersistentStores { [weak self] description, error in
            guard let _self = self else { return }
            guard error == nil else {
                _self.migrationRunningLog.addEvent(message: "Could not perform pre-migration work on v28. Could not load persistent stores: \(error!.localizedDescription)")
                return
            }
        }

        deleteOrphanedPersistedExpirationForReceivedMessageWithLimitedVisibility(currentContainer: currentContainer)

    }


    private func deleteOrphanedPersistedExpirationForReceivedMessageWithLimitedVisibility(currentContainer: ObvMessengerPersistentContainer) {

        let context = currentContainer.newBackgroundContext()
        context.performAndWait {
            let request: NSFetchRequest<NSManagedObject> = NSFetchRequest(entityName: "PersistedExpirationForReceivedMessageWithLimitedVisibility")
            request.predicate = NSPredicate(format: "messageReceivedWithLimitedVisibility == NIL")
            do {
                let results = try context.fetch(request)
                guard !results.isEmpty else {
                    migrationRunningLog.addEvent(message: "We found no PersistedExpirationForReceivedMessageWithLimitedVisibility instance requiring deletion")
                    return
                }
                migrationRunningLog.addEvent(message: "We found \(results.count) PersistedExpirationForReceivedMessageWithLimitedVisibility instances requiring deletion. We delete them now")
                for result in results {
                    context.delete(result)
                }
                try context.save()
            } catch {
                migrationRunningLog.addEvent(message: "The deletion of the PersistedExpirationForReceivedMessageWithLimitedVisibility instances failed: \(error.localizedDescription)")
            }
        }

    }


}
