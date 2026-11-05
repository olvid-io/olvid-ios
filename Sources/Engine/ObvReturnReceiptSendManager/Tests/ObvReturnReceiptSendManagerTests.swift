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


/// The module must be usable in every process, even when its store is not. Building it never fails.
final class ObvReturnReceiptSendManagerTests: XCTestCase {

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

    private func makeManager(appType: AppType, containerURL: URL? = nil) -> ObvReturnReceiptSendManager {
        ObvReturnReceiptSendManager(appType: appType, containerURL: containerURL ?? self.containerURL, runningLog: RunningLogError())
    }

    func testAManagerWithAStoreCanPersistReceipts() async {
        let manager = makeManager(appType: .mainApp)
        let canPersist = await manager.receiptsCanBePersisted
        XCTAssertTrue(canPersist)
    }

    /// A directory that does not exist, and that Core Data will not create. Without the early open of the store, this
    /// case reaches `CoreDataStack`, which calls `fatalError`: the process dies. The manager must degrade instead.
    ///
    /// The app is not tested here. For the app, this same case ends with the `assertionFailure` that says the store
    /// could not be opened even after being deleted, and an `assertionFailure` stops a debug build. In a release
    /// build, the app degrades like the extensions below. This was seen: with the app in this loop, the test process
    /// died at that assertion instead of failing a check.
    func testAManagerWhoseStoreCannotBeCreatedStillBuildsAndSaysSo() async {
        let missingDirectory = containerURL.appendingPathComponent("no", isDirectory: true).appendingPathComponent("such", isDirectory: true)
        for appType in [AppType.shareExtension, .notificationExtension, .intentExtension] {
            let manager = makeManager(appType: appType, containerURL: missingDirectory)
            let canPersist = await manager.receiptsCanBePersisted
            XCTAssertFalse(canPersist, "\(appType.transactionAuthor) should have reported a missing store")
        }
    }

    /// An extension that finds a store it may not repair runs degraded. The app repairs it and does not.
    func testOnlyTheAppRecoversFromAStoreItCannotOpen() async throws {
        try writeAStoreThisModuleCannotOpen()

        let extensionManager = makeManager(appType: .notificationExtension)
        let extensionCanPersist = await extensionManager.receiptsCanBePersisted
        XCTAssertFalse(extensionCanPersist)

        let appManager = makeManager(appType: .mainApp)
        let appCanPersist = await appManager.receiptsCanBePersisted
        XCTAssertTrue(appCanPersist)
    }

    /// Writes a store at our own store URL, built on a model that is not ours. Core Data then asks for a migration.
    /// This is the state an extension finds after a bump of the model, before the app has run. The real model has one
    /// version only, so this is the only way to reach that case today.
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
        let storeURL = containerURL.appendingPathComponent("\(ObvReturnReceiptSendManagerConstant.coreDataModelName).sqlite")
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        try coordinator.remove(store)
    }

}
