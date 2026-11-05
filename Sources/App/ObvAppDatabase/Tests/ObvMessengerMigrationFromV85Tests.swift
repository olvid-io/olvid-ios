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


/// Migrates a store written on v85 through the step the app's migration manager announces for it, and checks that a contact
/// that existed before reads as never set aside and never shown.
///
/// The step is performed here rather than by ``DataMigrationManager/initializeCoreDataStack()``, whose store lives in the
/// app group container: the test makes the same `migrateStore` call the manager makes, with the mapping the manager would
/// infer, from a store in a temporary directory.
final class ObvMessengerMigrationFromV85Tests: XCTestCase {

    private let bundle = Bundle(for: DataMigrationManagerForObvMessenger.self)
    private var containerURL: URL!

    /// The app opens its store with history tracking, so the migration finds it on in every store on a device.
    private let storeOptions: [String: Any] = [NSPersistentHistoryTrackingKey: true as NSNumber]

    private let contactIdentity = Data(repeating: 0xC0, count: 32)
    private let contactFullDisplayName = "Alice Martin"

    override func setUpWithError() throws {
        containerURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ObvMessengerMigrationFromV85Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: containerURL)
        containerURL = nil
    }

    private var sourceStoreURL: URL {
        containerURL.appendingPathComponent("ObvMessenger.sqlite")
    }

    private var destinationStoreURL: URL {
        containerURL.appendingPathComponent("ObvMessenger-migrated.sqlite")
    }

    private func compiledModel(_ name: String) throws -> NSManagedObjectModel {
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "mom", subdirectory: "ObvMessenger.momd"))
        return try XCTUnwrap(NSManagedObjectModel(contentsOf: url))
    }

    /// A copy of the compiled model with every entity backed by `NSManagedObject`, so that writing, migrating and reading
    /// rows runs none of the app's code, whose classes live in a module this target does not load. A class name is not
    /// part of an entity's version hash, so the store keeps its version. The copy is needed because a compiled model is
    /// immutable once loaded.
    private func plainModel(_ model: NSManagedObjectModel) throws -> NSManagedObjectModel {
        let copy = try XCTUnwrap(model.copy() as? NSManagedObjectModel)
        for entity in copy.entities {
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        return copy
    }

    /// A contact as v85 stores it, with every attribute the model requires and no relationship, none of them being required.
    private func writeAStoreOnV85(model: NSManagedObjectModel) throws {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: sourceStoreURL, options: storeOptions)
        let context = NSManagedObjectContext(.privateQueue)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let contact = NSEntityDescription.insertNewObject(forEntityName: "PersistedObvContactIdentity", into: context)
            contact.setValue(contactFullDisplayName, forKey: "fullDisplayName")
            contact.setValue(contactIdentity, forKey: "identity")
            contact.setValue(false, forKey: "isCertifiedByOwnKeycloak")
            contact.setValue(UUID(), forKey: "permanentUUID")
            contact.setValue(Data(repeating: 0x0A, count: 32), forKey: "rawOwnedIdentityIdentity")
            contact.setValue(0, forKey: "rawStatus")
            contact.setValue(Data(), forKey: "serializedIdentityCoreDetails")
            contact.setValue(contactFullDisplayName, forKey: "sortDisplayName")
            contact.setValue("A", forKey: "sortInitial")
            try context.save()
        }
        try coordinator.remove(store)
    }

    func testAContactIsNeitherSetAsideNorSeen() throws {

        let manager = DataMigrationManagerForObvMessenger(modelName: "ObvMessenger",
                                                          storeName: "ObvMessenger",
                                                          transactionAuthor: "ObvMessengerMigrationFromV85Tests",
                                                          enableMigrations: true,
                                                          migrationRunningLog: RunningLogError())

        let v85 = try compiledModel("ObvMessenger 85")
        let (destinationModel, migrationType) = try manager.getNextManagedObjectModelVersion(from: v85)
        XCTAssertEqual(migrationType, .lightweight)
        XCTAssertEqual(destinationModel.versionIdentifiers.first as? String, "ObvMessengerModel-v86")

        let source = try plainModel(v85)
        let destination = try plainModel(destinationModel)

        try writeAStoreOnV85(model: source)
        XCTAssertTrue(v85.isConfiguration(withName: nil, compatibleWithStoreMetadata: try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: sourceStoreURL)),
                      "The store written for the test is not a v85 store")

        let mapping = try NSMappingModel.inferredMappingModel(forSourceModel: source, destinationModel: destination)
        try NSMigrationManager(sourceModel: source, destinationModel: destination)
            .migrateStore(from: sourceStoreURL, type: .sqlite, options: storeOptions,
                          mapping: mapping,
                          to: destinationStoreURL, type: .sqlite, options: storeOptions)

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: destinationStoreURL)
        XCTAssertTrue(destinationModel.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata), "The migrated store is not a v86 store")

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: destination)
        let store = try coordinator.addPersistentStore(type: .sqlite, at: destinationStoreURL, options: storeOptions)
        defer { try? coordinator.remove(store) }
        let context = NSManagedObjectContext(.privateQueue)
        context.persistentStoreCoordinator = coordinator
        try context.performAndWait {
            let contacts = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "PersistedObvContactIdentity"))
            XCTAssertEqual(contacts.count, 1)
            let contact = try XCTUnwrap(contacts.first)
            XCTAssertEqual(contact.value(forKey: "identity") as? Data, contactIdentity)
            XCTAssertEqual(contact.value(forKey: "fullDisplayName") as? String, contactFullDisplayName)
            XCTAssertEqual(contact.value(forKey: "stopSuggesting") as? Bool, false)
            XCTAssertEqual(contact.value(forKey: "suggestionSeen") as? Bool, false)
        }

    }

}
