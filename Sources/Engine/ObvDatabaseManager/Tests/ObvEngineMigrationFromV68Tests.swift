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
import SQLite3
import XCTest
@testable import ObvDatabaseManager


/// Migrates a store written on v68 with the engine's migration manager, and checks what the v68 to v69 step made of it.
///
/// The manager migrates to the latest version, so the migrated store is read with the latest model and the
/// assertions bear on what v69 changed, which no later version touches.
final class ObvEngineMigrationFromV68Tests: XCTestCase {

    private struct CouldNotReadTheStore: Error {
        let reason: String
    }

    private let bundle = Bundle(for: DataMigrationManagerForObvEngine.self)
    private var containerURL: URL!
    private var previousContainerURL: URL?

    /// The engine opens its store with history tracking, so the migration finds it on in every store on a device.
    private let storeOptions: [String: Any] = [NSPersistentHistoryTrackingKey: true as NSNumber]

    private let parentUid = Data(repeating: 0xA1, count: 32)
    private let childUid = Data(repeating: 0xC3, count: 32)
    private let messageToSendRawId = 1

    override func setUpWithError() throws {
        containerURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ObvEngineMigrationFromV68Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
        previousContainerURL = ObvEnginePersistentContainer.containerURL
        ObvEnginePersistentContainer.containerURL = containerURL
    }

    override func tearDownWithError() throws {
        ObvEnginePersistentContainer.containerURL = previousContainerURL
        try? FileManager.default.removeItem(at: containerURL)
        containerURL = nil
    }

    private var storeURL: URL {
        containerURL.appendingPathComponent("ObvEngine.sqlite")
    }

    private func compiledModel(_ name: String) throws -> NSManagedObjectModel {
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "mom", subdirectory: "ObvEngine.momd"))
        return try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
    }

    /// The current version of the model, which is what the migration manager migrates to. Loading the `momd`
    /// directory rather than one `mom` file inside it is what makes this follow every later version.
    private func latestCompiledModel() throws -> NSManagedObjectModel {
        let url = try XCTUnwrap(bundle.url(forResource: "ObvEngine", withExtension: "momd"))
        return try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
    }

    /// A copy of the compiled model with every entity backed by `NSManagedObject`, so that writing and reading rows
    /// runs none of the engine's code. A class name is not part of an entity's version hash, so the store keeps its
    /// version. The copy is needed because the model loaded from the `momd` directory is immutable.
    private func plainModel(_ model: NSManagedObjectModel) throws -> NSManagedObjectModel {
        let copy = try XCTUnwrap(model.copy() as? NSManagedObjectModel)
        for entity in copy.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        return copy
    }

    private func storeMetadata() throws -> [String: Any] {
        try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: storeURL)
    }

    private func columns(of table: String) throws -> Set<String> {
        var database: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw CouldNotReadTheStore(reason: "Could not open the store")
        }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK else {
            throw CouldNotReadTheStore(reason: "Could not prepare the PRAGMA")
        }
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            if let name = sqlite3_column_text(statement, 1) {
                names.insert(String(cString: name))
            }
        }
        return names
    }

    private func writeAStoreOnV68() throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try plainModel(compiledModel("ObvEngine-v68")))
        let store = try coordinator.addPersistentStore(type: .sqlite, at: storeURL, options: storeOptions)
        let context = NSManagedObjectContext(.privateQueue)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let parent = NSEntityDescription.insertNewObject(forEntityName: "ProtocolInstance", into: context)
            parent.setValue(0, forKey: "cryptoProtocolRawId")
            parent.setValue(1, forKey: "currentStateRawId")
            parent.setValue(Data([0x00]), forKey: "rawEncodedCurrentState")
            parent.setValue(Data([0x01]), forKey: "rawOwnedCryptoIdentity")
            parent.setValue(parentUid, forKey: "rawUID")
            let link = NSEntityDescription.insertNewObject(forEntityName: "LinkBetweenProtocolInstances", into: context)
            link.setValue(2, forKey: "expectedChildStateRawId")
            link.setValue(messageToSendRawId, forKey: "messageToSendRawId")
            link.setValue(childUid, forKey: "rawChildProtocolInstanceUid")
            link.setValue(parent, forKey: "parentProtocolInstance")
            try context.save()
        }
        try coordinator.remove(store)
    }

    func testALinkLosesTheExpectedChildStateAndKeepsTheRest() throws {

        let v68 = try compiledModel("ObvEngine-v68")
        let latest = try latestCompiledModel()

        try writeAStoreOnV68()
        XCTAssertTrue(v68.isConfiguration(withName: nil, compatibleWithStoreMetadata: try storeMetadata()), "The store written for the test is not a v68 store")
        XCTAssertTrue(try columns(of: "ZLINKBETWEENPROTOCOLINSTANCES").contains("ZEXPECTEDCHILDSTATERAWID"))

        let manager = DataMigrationManagerForObvEngine(modelName: "ObvEngine",
                                                       storeName: "ObvEngine",
                                                       transactionAuthor: "ObvEngineMigrationFromV68Tests",
                                                       enableMigrations: true,
                                                       migrationRunningLog: RunningLogError())
        try manager.initializeCoreDataStack()

        let metadata = try storeMetadata()
        XCTAssertTrue(latest.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata), "The migrated store is not on the latest version")
        XCTAssertFalse(v68.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata))

        let columns = try columns(of: "ZLINKBETWEENPROTOCOLINSTANCES")
        XCTAssertFalse(columns.contains("ZEXPECTEDCHILDSTATERAWID"))
        XCTAssertTrue(columns.contains("ZMESSAGETOSENDRAWID"))

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try plainModel(latestCompiledModel()))
        let store = try coordinator.addPersistentStore(type: .sqlite, at: storeURL, options: storeOptions)
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(.privateQueue)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let links = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "LinkBetweenProtocolInstances"))
            XCTAssertEqual(links.count, 1)
            let link = try XCTUnwrap(links.first)
            XCTAssertEqual(link.value(forKey: "messageToSendRawId") as? Int, messageToSendRawId)
            XCTAssertEqual(link.value(forKey: "rawChildProtocolInstanceUid") as? Data, childUid)
            let parent = try XCTUnwrap(link.value(forKey: "parentProtocolInstance") as? NSManagedObject)
            XCTAssertEqual(parent.value(forKey: "rawUID") as? Data, parentUid)
        }

    }

}
