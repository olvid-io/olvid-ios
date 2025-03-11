/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import CloudKit
import ObvAppCoreConstants


enum CloudKitError: Error {
    case accountError(_: Error)
    case accountNotAvailable(_: CKAccountStatus)
    case operationError(_: Error)
    case unknownError(_: Error)
    case internalError
}


/// This iterator allows to iterate on the backups saved to iCloud. The records returned are sorted according to their creation date, the most recent record first.
final class CloudKitBackupRecordIterator: AsyncIteratorProtocol {

    private let container: CKContainer
    private let database: CKDatabase
    private let query: CKQuery
    private let desiredKeys: [String]?
    private let resultsLimit: Int

    private var cursor: CKQueryOperation.Cursor? = nil

    /// Indicates whether more results are available.
    ///
    /// Returns:
    /// - ``nil`` if `next()` was never called, we don't know yet if there is result or not
    /// - ``true`` if there is more results to load, call ``next()`` to get a batch of ``resultsLimit`` records
    /// - ``false`` if there is no more result, or if iCloud does not send more result for the moment. It may have more results later.
    private(set) var hasNext: Bool? = nil

    /// - Parameter identifierForVendor: if set, the iterator will restrict to records with the given identifierForVendor.
    /// - Parameter resultsLimit: The size of batch returned when calling ``next()``.
    /// - Parameter desiredKeys: The fields of the records to fetch. If ``nil``, all fields are fetched.
    init(identifierForVendor: UUID? = nil,
         resultsLimit: Int?,
         desiredKeys: [ObvAppCoreConstants.BackupConstants.Key]?) {

        self.container = CKContainer(identifier: ObvAppCoreConstants.iCloudContainerIdentifierForEngineBackup)
        self.database = container.privateCloudDatabase
        let predicate: NSPredicate
        if let identifierForVendor = identifierForVendor {
            predicate = NSPredicate(ObvAppCoreConstants.BackupConstants.Key.deviceIdentifierForVendor, EqualToString: identifierForVendor.uuidString)
        } else {
            predicate = NSPredicate(value: true)
        }
        self.query = CKQuery(recordType: ObvAppCoreConstants.BackupConstants.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: ObvAppCoreConstants.BackupConstants.creationDate, ascending: false)]

        self.desiredKeys = desiredKeys?.map({ $0.rawValue })
        self.resultsLimit = resultsLimit ?? CKQueryOperation.maximumResults
    }

    /// Returns the next batch of records, with a size limited by ``resultsLimit``. Returns ``nil`` if there is no more records to fetch in this iterator.
    /// This method is not thread safe: do not call it on different queues.
    func next() async throws -> [CKRecord]? {
        if let hasNext = hasNext {
            guard hasNext else { return nil }
        }

        let accountStatus = try await self.container.accountStatus()

        guard accountStatus == .available else {
            throw CloudKitError.accountNotAvailable(accountStatus)
        }

        let op: CKQueryOperation
        if let cursor = cursor {
            // Continue the previous operation
            op = CKQueryOperation(cursor: cursor)
        } else {
            // No previous operation, build one with query.
            op = CKQueryOperation(query: self.query)
        }
        if let desiredKeys = self.desiredKeys {
            op.desiredKeys = desiredKeys
        }
        op.resultsLimit = resultsLimit

        return try await withCheckedThrowingContinuation { cont in
            @Atomic var records: [CKRecord] = []
            op.recordMatchedBlock = { (_, result) in
                switch result {
                case .success(let record):
                    records += [record]
                case .failure(let error):
                    assertionFailure(error.localizedDescription)
                }
            }
            op.queryResultBlock = { result in
                switch result {
                case .failure(let error):
                    cont.resume(throwing: error)
                    return
                case .success(let cursor):
                    self.cursor = cursor
                    self.hasNext = self.cursor != nil
                    cont.resume(returning: records)
                }
            }
            self.database.add(op)
        }
    }

}


extension CloudKitBackupRecordIterator: AsyncSequence {

    typealias AsyncIterator = CloudKitBackupRecordIterator
    typealias Element = [CKRecord]

    func makeAsyncIterator() -> CloudKitBackupRecordIterator {
        self
    }

}
