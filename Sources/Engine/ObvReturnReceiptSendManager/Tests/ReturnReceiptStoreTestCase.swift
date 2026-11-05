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


/// A real SQLite store in a temporary directory, and as many database coordinators over it as a test asks for.
///
/// Several coordinators over one file is how the conflicts between two processes are reproduced here. Core Data has
/// no special path for another process: two store coordinators over one file use the same optimistic locking, whether
/// they live in one process or in two.
///
/// The store must be a real one. `NSInMemoryStoreType` sorts and checks in memory, and once gave two false
/// reproductions of a crash in this repository. A SQLite store at `/dev/null` is real, but is private to one store
/// coordinator, so two of them never meet.
class ReturnReceiptStoreTestCase: XCTestCase {

    private(set) var containerURL: URL!
    private var coordinators = [ReturnReceiptSendDatabaseCoordinator]()

    override func setUpWithError() throws {
        try super.setUpWithError()
        containerURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("\(Self.self)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        coordinators.forEach { try? $0.close() }
        coordinators.removeAll()
        try? FileManager.default.removeItem(at: containerURL)
        containerURL = nil
        try super.tearDownWithError()
    }

    /// Another coordinator over the same store file. Closed at the end of the test.
    func makeCoordinator(appType: AppType = .mainApp) throws -> ReturnReceiptSendDatabaseCoordinator {
        let coordinator = try ReturnReceiptSendDatabaseCoordinator(appType: appType, containerURL: containerURL, runningLog: RunningLogError())
        coordinators.append(coordinator)
        return coordinator
    }

    /// Runs the block on a context of this coordinator, then saves. A conflict only exists at save time, so a test
    /// that never saves tests nothing here.
    @discardableResult
    func write<T>(on coordinator: ReturnReceiptSendDatabaseCoordinator, _ block: (NSManagedObjectContext) throws -> T) throws -> T {
        let context = coordinator.newBackgroundContext()
        var result: Result<T, Error>!
        context.performAndWait {
            do {
                let value = try block(context)
                try context.save()
                result = .success(value)
            } catch {
                result = .failure(error)
            }
        }
        return try result.get()
    }

    /// Runs the block on a fresh context of this coordinator, without saving. Fresh, so that what it reads comes from
    /// the store and not from something another test step left in a context.
    func read<T>(on coordinator: ReturnReceiptSendDatabaseCoordinator, _ block: (NSManagedObjectContext) throws -> T) throws -> T {
        let context = coordinator.newBackgroundContext()
        var result: Result<T, Error>!
        context.performAndWait {
            do {
                result = .success(try block(context))
            } catch {
                result = .failure(error)
            }
        }
        return try result.get()
    }

    func countOfRows(on coordinator: ReturnReceiptSendDatabaseCoordinator) throws -> Int {
        try read(on: coordinator) { context in
            try context.count(for: PersistedReturnReceiptToSend.fetchRequest())
        }
    }

}
