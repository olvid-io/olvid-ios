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
import CoreData
import OSLog
import ObvCoreDataStack


final class DataMigrationManagerForObvBackupManagerNew: DataMigrationManager<ObvBackupManagerNewPersistentContainer> {
    
    
    private static let logger = Logger(subsystem: "io.olvid.backup", category: "DataMigrationManagerForObvBackupManagerNew")

    
    enum ObvBackupManagerModelVersion: String {
        
        case version1 = "ObvBackupManagerModel-v1"

        static var latest: ObvBackupManagerModelVersion {
            return .version1
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
                let logger = DataMigrationManagerForObvBackupManagerNew.logger
                logger.fault("Unexpected number of version identifiers found. Got \(model.versionIdentifiers.count) although 1 is expected")
                throw ObvError.unexpectedNumberOfVersionIdentifiers
            }
            guard let versionIdentifier = model.versionIdentifiers.first! as? String else {
                throw ObvError.couldNotRecoverVersionIdentifierOfTheModel
            }
            guard let version = Self.init(rawValue: versionIdentifier) else {
                throw ObvError.couldNotCastTheVersionIdentifierOfTheModel
            }
            self = version
        }

    }

    
    private func getManagedObjectModel(version: ObvBackupManagerModelVersion) throws -> NSManagedObjectModel {
        let allModels = try getAllManagedObjectModels()
        let model = try allModels.filter {
            guard $0.versionIdentifiers.count == 1 else {
                Self.logger.fault("Unexpected number of version identifiers found. Got \($0.versionIdentifiers.count) although 1 is expected")
                throw ObvError.unexpectedNumberOfVersionIdentifiers
            }
            guard let versionIdentifier = $0.versionIdentifiers.first! as? String else {
                throw ObvError.couldNotCastTheVersionIdentifierOfTheModel
            }
            return versionIdentifier == version.identifier
        }
        guard model.count == 1 else {
            Self.logger.fault("After filtering all available models, \(model.count) appropriate models were found instead of 1")
            throw ObvError.unexpectedNumberOfAppropriateModels
        }
        return model.first!
    }

    
    override func modelVersion(_ rawModelVersion: String, isMoreRecentThan otherRawModelVersion: String?) throws -> Bool {
        guard let otherRawModelVersion else { return true }
        guard let otherModelVersion = ObvBackupManagerModelVersion(rawValue: otherRawModelVersion) else {
            assertionFailure()
            Self.logger.fault("Could not parse other raw model version")
            throw ObvError.couldNotParseRawModelVersion
        }
        guard let modelVersion = ObvBackupManagerModelVersion(rawValue: rawModelVersion) else {
            assertionFailure()
            Self.logger.fault("Could not parse raw model version")
            throw ObvError.couldNotParseRawModelVersion
        }
        guard let otherModelVersionAsInt = otherModelVersion.intValue else {
            assertionFailure()
            Self.logger.fault("Could not determine int value from other model version")
            throw ObvError.couldNotDetermineIntValueFromModelVersion
        }
        guard let modelVersionAsInt = modelVersion.intValue else {
            assertionFailure()
            Self.logger.fault("Could not determine int value from model version")
            throw ObvError.couldNotDetermineIntValueFromModelVersion
        }
        return modelVersionAsInt > otherModelVersionAsInt
    }


    public override func getNextManagedObjectModelVersion(from sourceModel: NSManagedObjectModel) throws -> (destinationModel: NSManagedObjectModel, migrationType: DataMigrationManager<ObvBackupManagerNewPersistentContainer>.MigrationType) {

        let sourceVersion = try ObvBackupManagerModelVersion(model: sourceModel)

        Self.logger.info("Current version of the ObvBackupManager' Core Data stack: \(sourceVersion.identifier)")

        let destinationVersion: ObvBackupManagerModelVersion
        let migrationType: MigrationType
        switch sourceVersion {
        case .version1: migrationType = .heavyweight; destinationVersion = .version1
        }
        
        let destinationModel = try getManagedObjectModel(version: destinationVersion)

        Self.logger.info("Performing a \(migrationType.debugDescription) migration of the ObvBackupManagerModel from version \(sourceVersion.identifier) to \(destinationVersion.identifier)")
        
        return (destinationModel, migrationType)

    }

    
    public override func managedObjectModelIsLatestVersion(_ model: NSManagedObjectModel) throws -> Bool {
        let modelVersion = try ObvBackupManagerModelVersion(model: model)
        return modelVersion == .latest
    }

    
    public override func performPreMigrationWork(forSourceModel sourceModel: NSManagedObjectModel, destinationModel: NSManagedObjectModel) throws {
        // Nothing for now
    }

}


// Errors

extension DataMigrationManagerForObvBackupManagerNew {
    
    enum ObvError: Error {
        case unexpectedNumberOfVersionIdentifiers
        case couldNotRecoverVersionIdentifierOfTheModel
        case couldNotCastTheVersionIdentifierOfTheModel
        case unexpectedNumberOfAppropriateModels
        case couldNotParseRawModelVersion
        case couldNotDetermineIntValueFromModelVersion
    }
    
}

