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
@testable import ObvAppDatabase


/// Checks the chain of app model versions against the compiled models, without a store: every step the migration
/// manager announces must be one Core Data can perform, and every version must lead to the latest.
final class ObvMessengerModelVersionsTests: XCTestCase {

    private typealias Version = DataMigrationManagerForObvMessenger.ObvMessengerModelVersion
    private typealias MigrationType = DataMigrationManagerForObvMessenger.MigrationType

    private struct Step {
        let source: Version
        let sourceModel: NSManagedObjectModel
        let destination: Version
        let destinationModel: NSManagedObjectModel
        let migrationType: MigrationType
    }

    private let bundle = Bundle(for: DataMigrationManagerForObvMessenger.self)
    private var manager: DataMigrationManagerForObvMessenger!
    private var models: [NSManagedObjectModel]!

    override func setUpWithError() throws {
        manager = DataMigrationManagerForObvMessenger(modelName: "ObvMessenger",
                                                      storeName: "ObvMessenger",
                                                      transactionAuthor: "ObvMessengerModelVersionsTests",
                                                      enableMigrations: true,
                                                      migrationRunningLog: RunningLogError())
        models = try manager.getAllManagedObjectModels()
    }

    override func tearDown() {
        manager = nil
        models = nil
    }

    /// Reads a model's version without ``DataMigrationManagerForObvMessenger/ObvMessengerModelVersion/init(model:)``,
    /// so that a bad model fails the test with a message rather than with the manager's error.
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
        XCTAssertFalse(versions.contains(nil), "A compiled model has an identifier ObvMessengerModelVersion does not know")
        let identifiers = versions.compactMap { $0?.rawValue }
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "Two compiled models share a version identifier")
    }

    /// Two compiled models with the same entity hashes would both match a store, and the migration manager takes the
    /// first it finds. A change the hashes do not cover, such as a fetch index or a delete rule, needs a
    /// `versionHashModifier` to make a version of its own.
    ///
    /// v21 and v22 are the one pair allowed: they differ only by a delete rule, and both migrate straight to v23, so
    /// either may be taken for the other.
    func testNoTwoModelsAreCompatibleWithTheSameStore() {
        let pairsWithTheSameHashes: Set<Set<Version>> = [[.version21, .version22]]
        for i in models.indices {
            for j in models.indices where j > i && models[i].entityVersionHashesByName == models[j].entityVersionHashesByName {
                let pair: Set<Version?> = [version(of: models[i]), version(of: models[j])]
                guard !pairsWithTheSameHashes.contains(where: { Set($0.map(Optional.some)) == pair }) else { continue }
                XCTFail("\(version(of: models[i])?.rawValue ?? "?") and \(version(of: models[j])?.rawValue ?? "?") have the same entity hashes")
            }
        }
    }

    func testTheLatestVersionIsTheHighestAndTheCurrentModel() throws {
        XCTAssertEqual(Version.latest.intValue, models.compactMap { version(of: $0)?.intValue }.max())
        let momdURL = try XCTUnwrap(bundle.url(forResource: "ObvMessenger", withExtension: "momd"))
        let currentModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: momdURL))
        XCTAssertEqual(version(of: currentModel), .latest, "The current version of ObvMessenger.xcdatamodeld is not ObvMessengerModelVersion.latest")
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
