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

import Foundation
import CoreData
import OSLog
import ObvCoreDataStack
import ObvMetaManager
import OlvidUtils


/// Owns the store of this module: the return receipts we still owe.
///
/// The store is in a file of its own, used by this module only. This is why the merge policy set below is safe: it
/// cannot reach the saves of the app, nor those of the engine.
final class ReturnReceiptSendDatabaseCoordinator {

    private static let logger = Logger(subsystem: "io.olvid.returnReceiptSend", category: "ReturnReceiptSendDatabaseCoordinator")

    private let coreDataStack: CoreDataStack<ObvReturnReceiptSendManagerPersistentContainer>

    /// - Parameters:
    ///   - appType: gives both the transaction author and the right to migrate. One value, so the two always agree.
    ///   - containerURL: the directory holding the store file. The engine gives a box of its own, the tests give a
    ///     temporary directory.
    init(appType: AppType, containerURL: URL, runningLog: RunningLogError) throws {

        ObvReturnReceiptSendManagerPersistentContainer.containerURL = containerURL

        // Only the app migrates. So, after a bump of this model, an extension that runs before the app finds a store
        // it cannot open. This cannot happen with v1: there is nothing to migrate from yet.
        let enableMigrations = (appType == .mainApp)

        let migrationManager = DataMigrationManagerForObvReturnReceiptSendManager(
            modelName: ObvReturnReceiptSendManagerConstant.coreDataModelName,
            storeName: ObvReturnReceiptSendManagerConstant.coreDataModelName,
            transactionAuthor: appType.transactionAuthor,
            enableMigrations: enableMigrations,
            migrationRunningLog: runningLog)

        do {
            self.coreDataStack = try Self.openStore(migrationManager: migrationManager, containerURL: containerURL)
        } catch {

            // The store cannot be opened. Either a migration failed, or the file cannot be read.
            //
            // An extension must not delete it. After a bump of this model, the rows are a backlog that the app will
            // migrate at its next launch. Deleting them here would lose receipts we owe. The extension gives up, and
            // the caller sends the receipts right away instead.
            guard appType == .mainApp else {
                Self.logger.error("This store cannot be opened by the \(appType.transactionAuthor, privacy: .public), and only the app may repair it: \(error)")
                throw ObvError.storeIsUnavailableInThisProcess(error: error)
            }

            // The app deletes it and starts again. A receipt is the data we can most afford to lose: at worst, a few
            // senders miss a delivery mark for messages that did arrive. Failing to launch would be much worse.
            Self.logger.fault("This store cannot be opened. Deleting it and starting again: \(error)")
            do {
                try migrationManager.deleteStore()
                self.coreDataStack = try Self.openStore(migrationManager: migrationManager, containerURL: containerURL)
            } catch {
                Self.logger.fault("This store cannot be opened, even after being deleted: \(error)")
                assertionFailure()
                throw ObvError.storeIsUnavailableInThisProcess(error: error)
            }

        }

    }


    /// Migrates the store if needed, then checks that it really opens.
    ///
    /// The second step matters: `CoreDataStack` opens the store late, on the first context, and calls `fatalError`
    /// when it fails. So we open it here first, with a coordinator of our own. A missing directory or a full disk
    /// then gives an error we can handle, instead of a crash we cannot.
    private static func openStore(migrationManager: DataMigrationManagerForObvReturnReceiptSendManager, containerURL: URL) throws -> CoreDataStack<ObvReturnReceiptSendManagerPersistentContainer> {

        try migrationManager.initializeCoreDataStack()

        guard let modelURL = Bundle.module.url(forResource: ObvReturnReceiptSendManagerConstant.coreDataModelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw ObvError.theModelOfThisModuleCannotBeLoaded
        }
        let storeURL = containerURL.appendingPathComponent("\(ObvReturnReceiptSendManagerConstant.coreDataModelName).sqlite")
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let store = try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        try coordinator.remove(store)

        return migrationManager.coreDataStack

    }


    /// A context on this store. Each one carries `mergeByPropertyObjectTrump`. Thanks to it, a duplicate insert leaves
    /// one row instead of failing the save. This is what makes the dedup between processes work without a check.
    func newBackgroundContext(file: StaticString = #fileID, line: Int = #line, function: StaticString = #function) -> NSManagedObjectContext {
        let context = coreDataStack.newBackgroundContext(file: file, line: line, function: function)
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        return context
    }


    /// Closes the store. The engine never calls this, since a store stays open for the life of the process. But a test
    /// that opens several stores in one process must release the previous one. The coordinator is then dead: the
    /// contexts it gives still have a store coordinator, but with nothing behind it.
    func close() throws {
        let coordinator = coreDataStack.persistentStoreCoordinator
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }

}


// MARK: - Errors

extension ReturnReceiptSendDatabaseCoordinator {

    enum ObvError: Error {
        /// This process has no store. The app already tried to delete it and to start again. An extension did not
        /// try, on purpose. See ``ObvReturnReceiptSendManager/init(appType:containerURL:runningLog:)`` for what the
        /// module does then.
        case storeIsUnavailableInThisProcess(error: Error)
        case theModelOfThisModuleCannotBeLoaded
    }

}
