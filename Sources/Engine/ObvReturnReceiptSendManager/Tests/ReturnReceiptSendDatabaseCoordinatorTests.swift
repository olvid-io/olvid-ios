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
import ObvMetaManager
import OlvidUtils
import XCTest
@testable import ObvReturnReceiptSendManager


/// Opens the store in a temporary directory and closes it again. `ObvBackupManagerNew`, which this store is copied
/// from, has no test target, so this is the first time the stack is built anywhere but in a running app.
final class ReturnReceiptSendDatabaseCoordinatorTests: XCTestCase {

    private var containerURL: URL!

    override func setUpWithError() throws {
        containerURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ObvReturnReceiptSendManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: containerURL)
        containerURL = nil
    }

    private func makeCoordinator(appType: AppType = .mainApp) throws -> ReturnReceiptSendDatabaseCoordinator {
        try ReturnReceiptSendDatabaseCoordinator(appType: appType, containerURL: containerURL, runningLog: RunningLogError())
    }

    private var storeURL: URL {
        containerURL.appendingPathComponent("\(ObvReturnReceiptSendManagerConstant.coreDataModelName).sqlite")
    }

    func testOpeningTheStoreWritesItsFileInTheGivenDirectory() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path), "Nothing should be there before")
        let coordinator = try makeCoordinator()
        // The store is opened lazily, on the first context.
        _ = coordinator.newBackgroundContext()
        XCTAssertTrue(FileManager.default.fileExists(atPath: storeURL.path))
        try coordinator.close()
    }

    func testAClosedStoreCanBeOpenedAgainAndIsTheSameFile() throws {
        let first = try makeCoordinator()
        _ = first.newBackgroundContext()
        let inodeOfFirst = try FileManager.default.attributesOfItem(atPath: storeURL.path)[.systemFileNumber] as? NSNumber
        try first.close()

        let second = try makeCoordinator()
        _ = second.newBackgroundContext()
        let inodeOfSecond = try FileManager.default.attributesOfItem(atPath: storeURL.path)[.systemFileNumber] as? NSNumber
        XCTAssertEqual(inodeOfFirst, inodeOfSecond, "The second open should have found the first store, not made a new one")
        try second.close()
    }

    /// Two coordinators built in one process for two directories, each opening its own file.
    ///
    /// The directory is carried to `NSPersistentContainer` through
    /// `ObvReturnReceiptSendManagerPersistentContainer.containerURL`, a **static**, because `defaultDirectoryURL()`
    /// is a class method and has no instance to ask. Every coordinator built in this process writes it, and it is
    /// read twice at two different moments: `DataMigrationManager.storeURL` reads it while the coordinator is being
    /// built, and `NSPersistentContainer(name:)` reads it again when the store is first opened, which is later. A
    /// coordinator built in between those two moments changes the answer the first one gets — so the migration is
    /// checked against one directory and the store opened in another.
    ///
    /// There is one coordinator per process in the app, so nothing meets this today. It is worth a test because it
    /// is silent: the wrong directory holds a perfectly good store, nothing throws and nothing is logged.
    ///
    /// The comparison is on the directory each store landed in, and both exist by then, which is what makes
    /// `resolvingSymlinksInPath()` the right tool here — `NSTemporaryDirectory()` is itself a symlink, so the two
    /// sides are spelled differently until it is applied.
    ///
    /// **This is an expected failure: the defect is real and is not fixed.** Measured on 2026-09-18, both
    /// coordinators opened the *second* one's file, so everything the first wrote would land in the second's store.
    /// Every fix for it either moves when the store is opened — `loadPersistentStores` calls `fatalError`, so that
    /// relocates a crash into a launch path — or gives the store URL to `CoreDataStack` explicitly and drops
    /// `defaultDirectoryURL()`, which is every store in the app, the main database included. Neither is worth doing
    /// under a bug nothing has ever met. The expectation is strict, so this reports as soon as one of them is done.
    ///
    /// `ObvEnginePersistentContainer` and `ObvBackupManagerNewPersistentContainer` carry the same static and the same
    /// defect. Neither module has a test target; this is the one place it can be shown.
    func testTwoCoordinatorsBuiltForTwoDirectoriesEachOpenTheirOwnStore() throws {

        XCTExpectFailure("The directory travels through a static that the second coordinator overwrites before the first one's store is opened")

        let otherContainerURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ObvReturnReceiptSendManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: otherContainerURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: otherContainerURL) }

        // Built first and not used: its store is opened on its first context, and not before.
        let first = try makeCoordinator()
        let second = try ReturnReceiptSendDatabaseCoordinator(appType: .mainApp, containerURL: otherContainerURL, runningLog: RunningLogError())
        defer {
            try? first.close()
            try? second.close()
        }

        let storeOfTheFirst = try XCTUnwrap(first.newBackgroundContext().persistentStoreCoordinator?.persistentStores.first?.url)
        let storeOfTheSecond = try XCTUnwrap(second.newBackgroundContext().persistentStoreCoordinator?.persistentStores.first?.url)

        XCTAssertEqual(storeOfTheFirst.deletingLastPathComponent().resolvingSymlinksInPath(),
                       containerURL.resolvingSymlinksInPath(),
                       "The first coordinator opened its store in the directory the second one was given")
        XCTAssertEqual(storeOfTheSecond.deletingLastPathComponent().resolvingSymlinksInPath(),
                       otherContainerURL.resolvingSymlinksInPath(),
                       "The second coordinator opened its store somewhere other than the directory it was given")

    }


    func testClosingRemovesEveryStoreFromTheCoordinator() throws {
        let coordinator = try makeCoordinator()
        let context = coordinator.newBackgroundContext()
        XCTAssertFalse(context.persistentStoreCoordinator!.persistentStores.isEmpty)
        try coordinator.close()
        XCTAssertTrue(context.persistentStoreCoordinator!.persistentStores.isEmpty)
    }

    /// The merge policy is what turns a uniqueness-constraint violation into one surviving row rather than a failed
    /// save. It is set here, on every context, rather than at the one call site that inserts.
    func testEveryContextCarriesTheMergePolicyTheConstraintNeeds() throws {
        let coordinator = try makeCoordinator()
        defer { try? coordinator.close() }
        for _ in 0..<3 {
            let context = coordinator.newBackgroundContext()
            let policy = try XCTUnwrap(context.mergePolicy as? NSMergePolicy)
            XCTAssertEqual(policy, NSMergePolicy.mergeByPropertyObjectTrump)
        }
    }

    /// `NSPersistentContainer(name:)` finds its model by searching bundles, so "a store opened" is not by itself
    /// "our store opened" — a test host carrying other models could have supplied one. This pins it to ours.
    func testTheStoreIsOpenedOnThisModuleSOwnModel() throws {
        let coordinator = try makeCoordinator()
        defer { try? coordinator.close() }
        let context = coordinator.newBackgroundContext()
        let model = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectModel)
        XCTAssertEqual(model.entities.map(\.name), ["PersistedReturnReceiptToSend"])
        XCTAssertEqual(model.versionIdentifiers as? Set<String>, ["ObvReturnReceiptSendDataModel-v1"])
    }


    /// An extension must never migrate this store. The two are derived from one `AppType` so that they cannot
    /// disagree; this checks the store still opens for each of the four.
    func testTheStoreOpensForEveryAppType() throws {
        for appType in [AppType.mainApp, .shareExtension, .notificationExtension, .intentExtension] {
            let coordinator = try makeCoordinator(appType: appType)
            let context = coordinator.newBackgroundContext()
            XCTAssertEqual(context.transactionAuthor, appType.transactionAuthor)
            try coordinator.close()
        }
    }


    // MARK: - A store that will not open

    /// Writes a store at our own store URL, on a model that is not ours. Core Data then reports that a migration is
    /// needed, which is the state an extension meets after the model is bumped and before the app has run. There is
    /// only one version of the real model, so this is the only way to reach that branch at v1.
    private func writeAStoreThisModuleCannotOpen() throws {
        let entity = NSEntityDescription()
        entity.name = "PersistedReturnReceiptToSend"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let attribute = NSAttributeDescription()
        attribute.name = "anAttributeOurModelHasNeverHeardOf"
        attribute.attributeType = .stringAttributeType
        attribute.isOptional = true
        entity.properties = [attribute]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        model.versionIdentifiers = ["ObvReturnReceiptSendDataModel-v0"]
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        try coordinator.remove(store)
    }

    /// Receipts are the most droppable data this app holds, so the app destroys a store it cannot open rather than
    /// refusing to launch.
    func testTheAppDestroysAStoreItCannotOpenAndCarriesOn() throws {
        try writeAStoreThisModuleCannotOpen()
        let coordinator = try makeCoordinator(appType: .mainApp)
        defer { try? coordinator.close() }
        let context = coordinator.newBackgroundContext()
        let model = try XCTUnwrap(context.persistentStoreCoordinator?.managedObjectModel)
        XCTAssertEqual(model.versionIdentifiers as? Set<String>, ["ObvReturnReceiptSendDataModel-v1"],
                       "The store should have been replaced by one on the current model")
    }

    /// An extension must never destroy it: the rows are a backlog the app will migrate on its next launch. It reports
    /// that it has no store instead, and the caller posts to the network directly.
    func testAnExtensionRefusesToOpenItAndLeavesEveryByteWhereItWas() throws {
        try writeAStoreThisModuleCannotOpen()
        let before = try Data(contentsOf: storeURL)

        for appType in [AppType.shareExtension, .notificationExtension, .intentExtension] {
            XCTAssertThrowsError(try makeCoordinator(appType: appType)) { error in
                guard case ReturnReceiptSendDatabaseCoordinator.ObvError.storeIsUnavailableInThisProcess = error else {
                    return XCTFail("Expected storeIsUnavailableInThisProcess, got \(error)")
                }
            }
            let after = try Data(contentsOf: storeURL)
            XCTAssertEqual(before, after, "\(appType.transactionAuthor) altered a store it may not repair")
        }
    }

    /// And the two compose: what an extension declined to touch, the app still repairs.
    func testTheAppStillRepairsAStoreAnExtensionDeclinedToTouch() throws {
        try writeAStoreThisModuleCannotOpen()
        XCTAssertThrowsError(try makeCoordinator(appType: .notificationExtension))
        let coordinator = try makeCoordinator(appType: .mainApp)
        defer { try? coordinator.close() }
        let model = try XCTUnwrap(coordinator.newBackgroundContext().persistentStoreCoordinator?.managedObjectModel)
        XCTAssertEqual(model.versionIdentifiers as? Set<String>, ["ObvReturnReceiptSendDataModel-v1"])
    }

}
