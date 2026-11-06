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
import ObvCrypto
import ObvTypes
import OlvidUtils


/// One return receipt that we owe to a contact, kept until an upload carrying it has succeeded.
@objc(PersistedReturnReceiptToSend)
final class PersistedReturnReceiptToSend: NSManagedObject {

    private static let entityName = "PersistedReturnReceiptToSend"

    // MARK: Properties

    @NSManaged private var contactIdentity: Data? // Non-nil in the model
    @NSManaged private var createdAt: Date? // Non-nil in the model
    @NSManaged private var key: Data? // Non-nil in the model
    @NSManaged private var nonce: Data? // Non-nil in the model
    @NSManaged private var ownedIdentity: Data? // Non-nil in the model
    @NSManaged private var rawAttachmentNumber: Int32
    @NSManaged private var rawStatus: Int16
    @NSManaged private var serverURL: URL? // Non-nil in the model

    // MARK: The attachment number, and the value that stands for "no attachment"

    /// Value of `rawAttachmentNumber` for a receipt about a message, and not about one of its attachments.
    ///
    /// The column cannot be optional, because it belongs to the uniqueness constraint: SQLite sees two NULLs as
    /// different values, so a nil would switch the dedup off for message receipts, which are most rows. A real
    /// attachment number is an index, so it is never negative.
    private static let rawAttachmentNumberForAMessage: Int32 = -1

    /// The only place where an attachment number becomes a column value.
    ///
    /// The insert and the predicates must use this one function. If two places did the conversion and disagreed, the
    /// delete would match no row — and matching no row is normal here, since another process may have deleted it
    /// first. So nothing would fail, and the receipt would be sent again on every drain, for ever.
    private static func rawAttachmentNumber(from attachmentNumber: Int?) throws(ObvError) -> Int32 {
        guard let attachmentNumber else { return rawAttachmentNumberForAMessage }
        guard attachmentNumber >= 0, let raw = Int32(exactly: attachmentNumber) else {
            // A negative value would look exactly like "no attachment". No `assertionFailure` here, on purpose: the
            // throw already stops the insert, and a trap would make this guard impossible to test. It is the one
            // guard standing between a bad number and a row that reads as a message receipt.
            throw .attachmentNumberIsOutOfRange
        }
        return raw
    }

    private static func attachmentNumber(from rawAttachmentNumber: Int32) -> Int? {
        guard rawAttachmentNumber != rawAttachmentNumberForAMessage else { return nil }
        return Int(rawAttachmentNumber)
    }

    // MARK: - Initializer

    /// - Parameter createdAt: given by the caller, and not read from the clock here, because the age cap is tested
    ///   against it.
    convenience init(returnReceiptToSend: ObvReturnReceiptToSend, createdAt: Date, within context: NSManagedObjectContext) throws(ObvError) {
        try self.init(returnReceiptToUpload: .init(returnReceiptToSend: returnReceiptToSend, createdAt: createdAt), within: context)
    }


    /// The row of a value, which is what makes ``ReturnReceiptToUpload`` the only place a receipt is turned into these
    /// columns. A second derivation of `serverURL` could disagree with this one, and a receipt would then be uploaded
    /// to one server and its row read back for another.
    convenience init(returnReceiptToUpload: ReturnReceiptToUpload, within context: NSManagedObjectContext) throws(ObvError) {

        // Computed before the object is inserted. A convenience initializer that throws after `self.init` would leave
        // a half-built object in the context, and the next save would fail.
        let rawAttachmentNumber = try Self.rawAttachmentNumber(from: returnReceiptToUpload.identifier.attachmentNumber)

        guard let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context) else {
            assertionFailure()
            throw .theEntityCannotBeFound
        }
        self.init(entity: entityDescription, insertInto: context)

        self.contactIdentity = returnReceiptToUpload.identifier.contactIdentifier.contactCryptoId.getIdentity()
        self.createdAt = returnReceiptToUpload.createdAt
        self.key = returnReceiptToUpload.key
        self.nonce = returnReceiptToUpload.identifier.nonce
        self.ownedIdentity = returnReceiptToUpload.identifier.contactIdentifier.ownedCryptoId.getIdentity()
        self.rawAttachmentNumber = rawAttachmentNumber
        self.rawStatus = Int16(returnReceiptToUpload.identifier.status.rawValue)
        self.serverURL = returnReceiptToUpload.serverURL

    }

    // MARK: - Accessors

    /// The value that leaves the context. Built inside a `perform` block, used outside it.
    var returnReceiptToUpload: ReturnReceiptToUpload {
        get throws(ObvError) {
            guard let contactIdentity, let createdAt, let key, let nonce, let ownedIdentity, let serverURL else {
                assertionFailure()
                throw .aColumnIsUnexpectedlyNil
            }
            guard let status = ObvReturnReceiptStatus(rawValue: Int(rawStatus)) else {
                assertionFailure()
                throw .theStatusCannotBeParsed
            }
            let contactCryptoId: ObvCryptoId
            let ownedCryptoId: ObvCryptoId
            do {
                contactCryptoId = try ObvCryptoId(identity: contactIdentity)
                ownedCryptoId = try ObvCryptoId(identity: ownedIdentity)
            } catch {
                assertionFailure()
                throw .anIdentityCannotBeParsed
            }
            let identifier = ReturnReceiptIdentifier(
                contactIdentifier: .init(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId),
                nonce: nonce,
                status: status,
                attachmentNumber: Self.attachmentNumber(from: rawAttachmentNumber))
            return .init(identifier: identifier, key: key, serverURL: serverURL, createdAt: createdAt)
        }
    }

}


// MARK: - Errors

extension PersistedReturnReceiptToSend {

    enum ObvError: Error {
        case theEntityCannotBeFound
        case attachmentNumberIsOutOfRange
        case aColumnIsUnexpectedlyNil
        case theStatusCannotBeParsed
        case anIdentityCannotBeParsed
        case coreDataError(Error)
    }

}


// MARK: - Predicates and fetches

extension PersistedReturnReceiptToSend {

    private struct Predicate {

        enum Key: String {
            // Properties
            case contactIdentity = "contactIdentity"
            case createdAt = "createdAt"
            case key = "key"
            case nonce = "nonce"
            case ownedIdentity = "ownedIdentity"
            case rawAttachmentNumber = "rawAttachmentNumber"
            case rawStatus = "rawStatus"
            case serverURL = "serverURL"
        }

        static func forServer(_ serverURL: URL) -> NSPredicate {
            NSPredicate(Key.serverURL, EqualToUrl: serverURL)
        }

        /// The only place where the identity of a row is written. `withIdentifiers(_:)` is built from it, so the two
        /// cannot disagree.
        static func withIdentifier(_ identifier: ReturnReceiptIdentifier) throws(ObvError) -> NSPredicate {
            let rawAttachmentNumber = try PersistedReturnReceiptToSend.rawAttachmentNumber(from: identifier.attachmentNumber)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.ownedIdentity, EqualToData: identifier.contactIdentifier.ownedCryptoId.getIdentity()),
                NSPredicate(Key.contactIdentity, EqualToData: identifier.contactIdentifier.contactCryptoId.getIdentity()),
                NSPredicate(Key.nonce, EqualToData: identifier.nonce),
                NSPredicate(Key.rawStatus, EqualToInt: identifier.status.rawValue),
                NSPredicate(Key.rawAttachmentNumber, EqualToInt: Int(rawAttachmentNumber)),
            ])
        }

        static func withIdentifiers(_ identifiers: [ReturnReceiptIdentifier]) throws(ObvError) -> NSPredicate {
            // An OR over an empty array is false, which is what we want here. We write it, rather than rely on it:
            // an AND over an empty array is true, and that mistake would mean every row of the table.
            guard !identifiers.isEmpty else { return NSPredicate(value: false) }
            var subpredicates = [NSPredicate]()
            for identifier in identifiers {
                subpredicates.append(try withIdentifier(identifier))
            }
            return NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)
        }

    }


    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedReturnReceiptToSend> {
        NSFetchRequest<PersistedReturnReceiptToSend>(entityName: Self.entityName)
    }


    /// One page of the receipts owed to one server, oldest first, as values.
    ///
    /// The oldest first, because the age cap of a drain applies to the rows at the front of the batch.
    ///
    /// - Parameter skipping: how many rows to step over before the page starts. A sweep deletes what it settles, so
    ///   it normally advances by deleting and asks for no offset at all; this is for the rows it *cannot* settle,
    ///   which would otherwise be the whole of every page it ever read. One caveat, and it is why this is a count
    ///   rather than a cursor: a `post` gives a whole batch one `createdAt`, and rows sharing one have no order
    ///   between two fetches, so an offset landing inside such a group may step over a row the sweep has not seen.
    ///   That row is not lost — the next sweep starts at nought again.
    static func getReturnReceiptsToUpload(forServer serverURL: URL, skipping numberOfRowsToSkip: Int = 0, fetchLimit: Int, within context: NSManagedObjectContext) throws(ObvError) -> [ReturnReceiptToUpload] {
        let request = Self.fetchRequest()
        request.predicate = Predicate.forServer(serverURL)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.createdAt.rawValue, ascending: true)]
        request.fetchOffset = numberOfRowsToSkip
        request.fetchLimit = fetchLimit
        let items: [PersistedReturnReceiptToSend]
        do {
            items = try context.fetch(request)
        } catch {
            throw .coreDataError(error)
        }
        var values = [ReturnReceiptToUpload]()
        for item in items {
            values.append(try item.returnReceiptToUpload)
        }
        return values
    }


    /// The servers that owe something, each one once.
    ///
    /// A dictionary fetch: it reads one column and builds no managed object, so the size of the table costs nothing.
    /// It carries **no sort descriptor**. `serverURL` is stored as a URI, and `NSURL` has no `compare:`, so sorting on
    /// it in memory would kill the process.
    static func getDistinctServerURLs(within context: NSManagedObjectContext) throws(ObvError) -> Set<URL> {
        let request = NSFetchRequest<NSDictionary>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [Predicate.Key.serverURL.rawValue]
        request.returnsDistinctResults = true
        request.sortDescriptors = []
        let results: [NSDictionary]
        do {
            results = try context.fetch(request)
        } catch {
            throw .coreDataError(error)
        }
        return Set(results.compactMap { $0[Predicate.Key.serverURL.rawValue] as? URL })
    }


    /// How many identifiers one fetch may name.
    ///
    /// Each identifier adds five terms to the predicate, and above a certain size SQLite refuses the expression.
    /// Measured on 2026-09-17: 100 identifiers take 7ms, 250 take 14ms, 500 take 90ms, and **1000 fail**, with
    /// `NSSQLiteErrorDomain=1` that Core Data reports as "the file couldn't be opened" — which reads like a broken
    /// store and is not one. A drain page holds fifty rows, so a caller never comes close; the value is here so that
    /// one that does gets several fetches instead of an error.
    private static let maximumNumberOfIdentifiersPerFetch = 50


    /// Deletes the rows named by these identifiers. Rows that are not there are not an error: another process may have
    /// sent the same receipt and deleted them first.
    static func deleteReturnReceipts(withIdentifiers identifiers: [ReturnReceiptIdentifier], within context: NSManagedObjectContext) throws(ObvError) {
        for slice in identifiers.toSlices(ofMaxSize: maximumNumberOfIdentifiersPerFetch) {
            try deleteReturnReceipts(namedByAtMostOneFetch: slice, within: context)
        }
    }


    private static func deleteReturnReceipts(namedByAtMostOneFetch identifiers: [ReturnReceiptIdentifier], within context: NSManagedObjectContext) throws(ObvError) {
        guard !identifiers.isEmpty else { return }
        let request = Self.fetchRequest()
        request.predicate = try Predicate.withIdentifiers(identifiers)
        request.fetchLimit = identifiers.count
        let items: [PersistedReturnReceiptToSend]
        do {
            items = try context.fetch(request)
        } catch {
            throw .coreDataError(error)
        }
        items.forEach { context.delete($0) }
    }

}
