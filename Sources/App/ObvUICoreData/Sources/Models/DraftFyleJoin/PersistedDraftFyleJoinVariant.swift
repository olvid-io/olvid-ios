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
import OlvidUtils
import UniformTypeIdentifiers
import ObvAppTypes


/// One photo or video of a draft, at one of the four sizes it may be sent at: which `Fyle` holds that size, what it weighs, and its size
/// in pixels. The size menu reads these, and the join's own `fyle`, `fileName` and `uti` are rewritten from the chosen one.
///
/// Several rows often share one `Fyle`: a photo already within a size's cap is not enlarged, so that size points at the original.
///
/// A photo gets all four rows when attached. A video, whose export takes tens of seconds, gets ``ObvMediaFormat/max`` and the size chosen.
/// Any other attachment has none.
@objc(PersistedDraftFyleJoinVariant)
public final class PersistedDraftFyleJoinVariant: NSManagedObject {

    public static let entityName = "PersistedDraftFyleJoinVariant"

    // MARK: Attributes

    /// What the file weighs, in bytes. Kept here rather than read from disk, because the menu asks for all four at once, on the main
    /// thread, every time the reader opens it.
    @NSManaged private(set) public var byteCount: Int64
    @NSManaged private(set) public var fileName: String?
    @NSManaged private(set) public var pixelHeight: Int64
    @NSManaged private(set) public var pixelWidth: Int64
    @NSManaged private var rawFormat: String?
    @NSManaged private(set) public var uti: String?

    // MARK: Relationships

    @NSManaged private(set) public var draftFyleJoin: PersistedDraftFyleJoin? // If nil, this entity is eventually cascade-deleted
    @NSManaged private(set) public var fyle: Fyle? // If nil, this entity is eventually cascade-deleted

    // MARK: Computed properties

    /// The size this variant holds, or nil if the stored raw value is not one this build knows.
    ///
    /// Answering nil rather than trapping matters: the store is shared with three extensions and with whatever build of Olvid ran last,
    /// so a row written by a later version naming a format this one has never heard of is a state to survive rather than a bug.
    public var format: ObvMediaFormat? {
        guard let rawFormat else { return nil }
        return ObvMediaFormat(rawValue: rawFormat)
    }

    /// Nil when the row has no type identifier, which is what a row deleted underneath this object reads. An identifier this system does
    /// not know gives `.data`.
    public var contentType: UTType? {
        guard let uti else { return nil }
        return UTType(uti) ?? .data
    }

}


// MARK: - Initializer

extension PersistedDraftFyleJoinVariant {

    /// Creates the row recording that `fyle` holds `draftFyleJoin`'s attachment at `format`.
    ///
    /// It neither makes nor checks the file: the caller has already moved it into the `Fyle` store, the encoding happening away from any
    /// context's queue.
    ///
    /// Throws when the join already has a row for this format, which keeps the existing one. Callers ask what is missing first.
    public convenience init(draftFyleJoin: PersistedDraftFyleJoin, format: ObvMediaFormat, fyle: Fyle, fileName: String, contentType: UTType, byteCount: Int64, pixelWidth: Int, pixelHeight: Int) throws {

        guard let context = draftFyleJoin.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }

        guard draftFyleJoin.variant(for: format) == nil else {
            throw ObvUICoreDataError.aVariantAlreadyExistsForThisMediaFormat
        }

        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedDraftFyleJoinVariant.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.byteCount = byteCount
        self.fileName = fileName
        self.pixelHeight = Int64(pixelHeight)
        self.pixelWidth = Int64(pixelWidth)
        self.rawFormat = format.rawValue
        self.uti = contentType.identifier

        self.draftFyleJoin = draftFyleJoin
        self.fyle = fyle

    }


    /// Records that `format` needs no file of its own, being the attachment exactly as attached: always for ``ObvMediaFormat/max``, and
    /// for a smaller size when the photo is already within its cap, since enlarging it would make it heavier than the original.
    ///
    /// The original is read from the ``ObvMediaFormat/max`` variant when there is one, the join's own `fyle` naming the chosen size.
    public static func createVariantPointingAtTheOriginal(of draftFyleJoin: PersistedDraftFyleJoin, format: ObvMediaFormat, byteCount: Int64, pixelWidth: Int, pixelHeight: Int) throws {

        let original = draftFyleJoin.variant(for: .max)

        guard let fyle = original?.fyle ?? draftFyleJoin.fyle else {
            throw ObvUICoreDataError.couldNotFindFyle
        }

        _ = try PersistedDraftFyleJoinVariant(draftFyleJoin: draftFyleJoin,
                                              format: format,
                                              fyle: fyle,
                                              fileName: original?.fileName ?? draftFyleJoin.fileName,
                                              contentType: original?.contentType ?? draftFyleJoin.contentType,
                                              byteCount: byteCount,
                                              pixelWidth: pixelWidth,
                                              pixelHeight: pixelHeight)

    }


    /// Records that `format` uses the same file as `variant`, a larger size of the same attachment.
    ///
    /// Used when encoding `format` produced a file no lighter than `variant`'s, so that a smaller size never weighs more than a larger one.
    public static func createVariantPointingAtTheFileOf(_ variant: PersistedDraftFyleJoinVariant, format: ObvMediaFormat) throws {

        guard let draftFyleJoin = variant.draftFyleJoin, let fyle = variant.fyle, let fileName = variant.fileName, let contentType = variant.contentType else {
            throw ObvUICoreDataError.couldNotFindFyle
        }

        _ = try PersistedDraftFyleJoinVariant(draftFyleJoin: draftFyleJoin,
                                              format: format,
                                              fyle: fyle,
                                              fileName: fileName,
                                              contentType: contentType,
                                              byteCount: variant.byteCount,
                                              pixelWidth: Int(variant.pixelWidth),
                                              pixelHeight: Int(variant.pixelHeight))

    }

}


// MARK: - Convenience DB getters

extension PersistedDraftFyleJoinVariant {

    public struct Predicate {
        public enum Key: String {
            // Attributes
            case byteCount = "byteCount"
            case fileName = "fileName"
            case pixelHeight = "pixelHeight"
            case pixelWidth = "pixelWidth"
            case rawFormat = "rawFormat"
            case uti = "uti"
            // Relationships
            case draftFyleJoin = "draftFyleJoin"
            case fyle = "fyle"
            // Others
            static let draftOfDraftFyleJoin = [draftFyleJoin.rawValue, PersistedDraftFyleJoin.Predicate.Key.draft.rawValue].joined(separator: ".")
        }
        static func withFormat(_ format: ObvMediaFormat) -> NSPredicate {
            NSPredicate(Key.rawFormat, EqualToString: format.rawValue)
        }
        static func withFyleWithObjectID(_ fyleObjectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(Key.fyle, equalToObjectWithObjectID: fyleObjectID)
        }
        static func withDraft(_ draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) -> NSPredicate {
            NSPredicate(Key.draftOfDraftFyleJoin, equalToObjectWithObjectID: draftObjectID.objectID)
        }
    }


    @nonobjc public static func fetchRequest() -> NSFetchRequest<PersistedDraftFyleJoinVariant> {
        return NSFetchRequest<PersistedDraftFyleJoinVariant>(entityName: PersistedDraftFyleJoinVariant.entityName)
    }


    /// Returns the variant recording that `fyleObjectID` is the **original** of one of `draftObjectID`'s photos, if there is one.
    ///
    /// This is how attaching the same photo twice is still recognised as the same photo. The join's own `fyle` used to answer that
    /// question and no longer can: it names whichever size is currently chosen, so it moves when the reader changes the size, and a
    /// second copy of an already-attached photo would no longer match it. The ``ObvMediaFormat/max`` variant does not move.
    static func getVariantHoldingTheOriginal(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, fyleObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoinVariant? {
        let request: NSFetchRequest<PersistedDraftFyleJoinVariant> = PersistedDraftFyleJoinVariant.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withDraft(draftObjectID),
            Predicate.withFormat(.max),
            Predicate.withFyleWithObjectID(fyleObjectID),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    /// Watches every variant of every attachment of one draft. The composition bar needs it: a new variant updates a join, not the draft,
    /// so the controller watching the draft would never tell the size menu that a weight is now known.
    ///
    /// `sortDescriptors` is empty: nothing reads the order, and a descriptor on a value without `compare:` crashes on a merged insert.
    /// - Parameter draftObjectID: nil when the discussion has no draft, in which case the controller matches nothing.
    public static func getFetchedResultsControllerForAllVariantsOfDraft(withObjectID draftObjectID: TypeSafeManagedObjectID<PersistedDraft>?, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDraftFyleJoinVariant> {
        let request: NSFetchRequest<PersistedDraftFyleJoinVariant> = PersistedDraftFyleJoinVariant.fetchRequest()
        if let draftObjectID {
            request.predicate = Predicate.withDraft(draftObjectID)
        } else {
            request.predicate = NSPredicate(value: false)
        }
        request.sortDescriptors = []
        request.fetchBatchSize = 50
        return NSFetchedResultsController(fetchRequest: request,
                                          managedObjectContext: context,
                                          sectionNameKeyPath: nil,
                                          cacheName: nil)
    }

}
