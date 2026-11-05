/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

import CoreData
import OlvidUtils
import XCTest
@testable import ObvDatabaseManager


/// Checks the chain of engine model versions against the compiled models, without a store: every step the migration
/// manager announces must be one Core Data can perform, and every version must lead to the latest.
final class ObvEngineModelVersionsTests: XCTestCase {

    private typealias Version = DataMigrationManagerForObvEngine.ObvEngineModelVersion
    private typealias MigrationType = DataMigrationManagerForObvEngine.MigrationType

    private struct Step {
        let source: Version
        let sourceModel: NSManagedObjectModel
        let destination: Version
        let destinationModel: NSManagedObjectModel
        let migrationType: MigrationType
    }

    private let bundle = Bundle(for: DataMigrationManagerForObvEngine.self)
    private var manager: DataMigrationManagerForObvEngine!
    private var models: [NSManagedObjectModel]!

    override func setUpWithError() throws {
        manager = DataMigrationManagerForObvEngine(modelName: "ObvEngine",
                                                   storeName: "ObvEngine",
                                                   transactionAuthor: "ObvEngineModelVersionsTests",
                                                   enableMigrations: true,
                                                   migrationRunningLog: RunningLogError())
        models = try manager.getAllManagedObjectModels()
    }

    override func tearDown() {
        manager = nil
        models = nil
    }

    /// Reads a model's version without ``DataMigrationManagerForObvEngine/ObvEngineModelVersion/init(model:)``, which
    /// asserts, so that a bad model fails the test instead of stopping it.
    private func version(of model: NSManagedObjectModel) -> Version? {
        guard model.versionIdentifiers.count == 1, let identifier = model.versionIdentifiers.first as? String else { return nil }
        return Version(rawValue: identifier)
    }

    /// One step per version but the latest, as the migration manager announces it.
    private func steps() throws -> [Step] {
        try models.compactMap { sourceModel in
            guard let source = version(of: sourceModel), source != .latest else { return nil }
            let (destinationModel, migrationType) = try manager.getNextManagedObjectModelVersion(from: sourceModel)
            let destination = try XCTUnwrap(version(of: destinationModel))
            return Step(source: source, sourceModel: sourceModel, destination: destination, destinationModel: destinationModel, migrationType: migrationType)
        }
    }

    /// A new version is made by copying the previous one, identifier included. Left unchanged, two models claim one
    /// version and the migration manager cannot tell them apart.
    func testEveryModelHasAVersionOfItsOwn() {
        XCTAssertFalse(models.isEmpty)
        let versions = models.map { version(of: $0) }
        XCTAssertFalse(versions.contains(nil), "A compiled model has an identifier ObvEngineModelVersion does not know")
        let identifiers = versions.compactMap { $0?.rawValue }
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "Two compiled models share a version identifier")
    }

    func testTheLatestVersionIsTheHighestAndTheCurrentModel() throws {
        XCTAssertEqual(Version.latest.intValue, models.compactMap { version(of: $0)?.intValue }.max())
        let momdURL = try XCTUnwrap(bundle.url(forResource: "ObvEngine", withExtension: "momd"))
        let currentModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: momdURL))
        XCTAssertEqual(version(of: currentModel), .latest, "The current version of ObvEngine.xcdatamodeld is not ObvEngineModelVersion.latest")
    }

    /// A lightweight step needs a mapping Core Data can infer, a heavyweight one a mapping model in the bundle: the two
    /// lookups the migration makes. One test, because announcing the steps loads every model once per version.
    func testEveryStepCanBePerformedAndLeadsToTheLatest() throws {

        let steps = try steps()
        XCTAssertEqual(steps.count, models.count - 1)

        for step in steps {
            let name = "\(step.source.rawValue) → \(step.destination.rawValue)"
            switch step.migrationType {
            case .lightweight:
                XCTAssertNoThrow(try NSMappingModel.inferredMappingModel(forSourceModel: step.sourceModel, destinationModel: step.destinationModel),
                                 "No mapping can be inferred for the lightweight step \(name)")
            case .heavyweight:
                XCTAssertNotNil(NSMappingModel(from: [bundle], forSourceModel: step.sourceModel, destinationModel: step.destinationModel),
                                "No mapping model in the bundle for the heavyweight step \(name)")
            }
        }

        let next = Dictionary(steps.map { ($0.source, $0.destination) }, uniquingKeysWith: { first, _ in first })
        for start in next.keys {
            var current = start
            var numberOfSteps = 0
            while current != .latest {
                guard let following = next[current], numberOfSteps < models.count else {
                    XCTFail("\(start.rawValue) does not lead to \(Version.latest.rawValue)")
                    break
                }
                current = following
                numberOfSteps += 1
            }
        }
    }

}
