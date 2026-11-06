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
import ObvEncoder
import ObvAppTypes

@objc(PersistedDraftFyleJoin)
public final class PersistedDraftFyleJoin: NSManagedObject, FyleJoin, ObvIdentifiableManagedObject {
    
    public static let entityName = "PersistedDraftFyleJoin"
    
    // MARK: Attributes

    /// **This is the name of the file that will be *sent***, not the name of the file that was attached, and the two differ whenever the
    /// reader has chosen a photo size that had to be re-encoded — a `.HEIC` attached and sent at Med leaves as a `.jpeg`. See the note on
    /// ``fyle``.
    @NSManaged private(set) public var fileName: String
    @NSManaged private(set) public var index: Int
    @NSManaged private var permanentUUID: UUID
    /// The content type of the file that will be *sent*. See the note on ``fyle``.
    @NSManaged private(set) public var uti: String

    // MARK: Relationships

    @NSManaged public private(set) var draft: PersistedDraft? // If nil, this entity is eventually cascade-deleted

    /// The file that will be sent, which for a photo or a video is the file of the chosen size.
    ///
    /// It moves: ``setSelectedFormat(_:)`` rewrites it, with ``fileName`` and ``uti``, when the size changes. That is what lets the send
    /// path stay unchanged, and it means this is not a stable identity for the attachment. Two things rely on the original instead:
    /// - recognising a file already attached asks for the ``ObvMediaFormat/max`` variant, which never moves;
    /// - the thumbnail is built from ``originalFyle``, its hardlink being cached against this join and never invalidated.
    ///
    /// For any other attachment there are no variants, and this never moves.
    @NSManaged private(set) public var fyle: Fyle? // If nil, this entity is eventually cascade-deleted

    /// This photo or video at each of the sizes that have been produced for it — the dictionary the composition bar's size menu reads.
    /// Empty for anything that is neither. See ``PersistedDraftFyleJoinVariant``.
    ///
    /// **A photo has all four rows and a video usually has two**, and that difference is the whole of what separates the two features. A
    /// photo's three downscales are written the moment it is attached, because each costs a few hundred milliseconds; a video's export
    /// costs tens of seconds, so only ``ObvMediaFormat/max`` — which is free, being the file itself — and the size currently chosen are
    /// ever made. A size a video has never been asked for simply has no row, and gains one if the reader picks it.
    @NSManaged private(set) public var variants: Set<PersistedDraftFyleJoinVariant>

    // MARK: Computed properties
    
    /// Expected to be non-nil, unless this `NSManagedObject` is deleted.
    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin> {
        get throws {
            guard self.managedObjectContext != nil else { assertionFailure(); throw ObvUICoreDataError.noContext }
            return ObvManagedObjectPermanentID<PersistedDraftFyleJoin>(uuid: self.permanentUUID)
        }
    }
    
    public var contentType: UTType {
        assert(UTType(uti) != nil)
        return UTType(uti) ?? .data
    }
    
    // MARK: - Other variables
    public var isPreviewType: Bool {
        return contentType.conforms(to: .olvidLinkPreview)
    }
    
    // MARK: - Other variables
    public var isAudioType: Bool {
        return contentType.conforms(to: .audio)
    }

    /// The type of the file as it was attached.
    ///
    /// ``contentType`` names the size currently chosen, which is a JPEG or an MP4 once a smaller size is picked. The ``ObvMediaFormat/max``
    /// variant keeps the original's; a join without one has never moved.
    private var originalContentType: UTType {
        variant(for: .max)?.contentType ?? contentType
    }

    /// Whether this attachment is a photograph the reader may choose a size for: one of ``ObvMediaFormat/photoTypesASizeMayBeChosenFor``.
    ///
    /// Asked of the original's type, since the join's becomes `public.jpeg` once a smaller size is chosen. A listed photo with several
    /// frames or an alpha channel is still eligible here, the check needing a file read; the maker then points every size at the original.
    public var isPhotoEligibleForAFormatChoice: Bool {
        guard !isPreviewType else { return false }
        return ObvMediaFormat.mayBeChosen(forPhotoOfType: originalContentType)
    }

    /// Whether this attachment is a video the reader may choose a size for: one of ``ObvMediaFormat/videoTypesASizeMayBeChosenFor``.
    ///
    /// Asked by conformance (a `switch` over a `UTType` tests equality), and of the original's type, the join's becoming `public.mpeg-4`
    /// once a smaller size is chosen. A voice message does not conform, as `testOnlyAVideoIsOfferedASizeAndAVoiceMessageIsNot` checks.
    public var isVideoEligibleForAFormatChoice: Bool {
        guard !isPreviewType else { return false }
        return ObvMediaFormat.mayBeChosen(forVideoOfType: originalContentType)
    }

    /// Whether the reader may choose the size this attachment is sent at, whatever kind of thing it is.
    public var isEligibleForAFormatChoice: Bool {
        isPhotoEligibleForAFormatChoice || isVideoEligibleForAFormatChoice
    }

}


// MARK: - The sizes this photo may be sent at

extension PersistedDraftFyleJoin {

    /// This photo's file at each size that has been produced so far — the dictionary the size menu reads.
    ///
    /// Incomplete while the sizes are still being made, and empty for anything that is not a photo.
    public var fyleForFormat: [ObvMediaFormat: Fyle] {
        var result = [ObvMediaFormat: Fyle]()
        for variant in variants {
            guard let format = variant.format, let fyle = variant.fyle else { continue }
            result[format] = fyle
        }
        return result
    }


    public func variant(for format: ObvMediaFormat) -> PersistedDraftFyleJoinVariant? {
        variants.first(where: { $0.format == format })
    }


    /// The weight of each size that has a file: what a ceiling is chosen among.
    ///
    /// One definition for the sizes sent, the video maker and the size menu, so that the menu shows what the maker would do.
    public var byteCountForFormat: [ObvMediaFormat: Int64] {
        var result = [ObvMediaFormat: Int64]()
        for variant in variants where variant.fyle != nil {
            guard let format = variant.format else { continue }
            result[format] = variant.byteCount
        }
        return result
    }


    /// The file exactly as it was attached.
    ///
    /// Falls back to ``fyle`` for a join that has no variants — anything that is not a photo, and any photo attached by a build of Olvid
    /// from before sizes existed and not yet caught up with. In both of those cases ``fyle`` has never moved, so it *is* the original.
    public var originalFyle: Fyle? {
        variant(for: .max)?.fyle ?? fyle
    }


    /// The sizes that have no file yet, largest first.
    ///
    /// Largest first because that is the order they are worth making in: ``ObvMediaFormat/max`` exists from the moment the photo is
    /// attached, and of the three left, the large ones take the longest, so starting with them means the menu's rows settle from the top
    /// down rather than the bottom up.
    ///
    /// Empty for anything that is not a photo, so that asking is the same as asking whether there is anything to do.
    public var photoFormatsWithoutAFile: [ObvMediaFormat] {
        guard isPhotoEligibleForAFormatChoice else { return [] }
        let formatsWithAFile = Set(fyleForFormat.keys)
        return ObvMediaFormat.orderShownInMenu.filter { !formatsWithAFile.contains($0) }
    }


    /// The sizes this video has no file for **and is going to be given one for**, which is at most two.
    ///
    /// ``ObvMediaFormat/max``, then `selectedFormat`: an export takes tens of seconds, so sizes not chosen are not made.
    ///
    /// ``ObvMediaFormat/max`` costs nothing, pointing at the file already there, and is required: once ``fyle`` has moved to an exported
    /// copy, it is the only link to the original, which `getJoinHolding(fyleObjectID:atAnySize:within:)` needs to refuse the same clip twice.
    ///
    /// Empty for anything that is not a video.
    public func videoFormatsWithoutAFile(whenSelectedFormatIs selectedFormat: ObvMediaFormat) -> [ObvMediaFormat] {
        guard isVideoEligibleForAFormatChoice else { return [] }
        let formatsWithAFile = Set(fyleForFormat.keys)
        var formatsWanted: [ObvMediaFormat] = [.max]
        if selectedFormat != .max { formatsWanted.append(selectedFormat) }
        return formatsWanted.filter { !formatsWithAFile.contains($0) }
    }


    /// The size sent when `format` is chosen: its own file, or else the lightest larger size that has one — in practice the nearest
    /// larger, `max` when no other has a file. Nil for a join with no variants, which is sent as it is.
    ///
    /// Depends only on which files exist, not on what was chosen before. The same question as the weight ceilings.
    public func variantSent(whenSelectedFormatIs format: ObvMediaFormat) -> PersistedDraftFyleJoinVariant? {
        if let ownVariant = variant(for: format), ownVariant.fyle != nil {
            return ownVariant
        }
        guard let larger = ObvMediaFormat.lightestSize(largerThan: format, among: byteCountForFormat) else { return nil }
        return variant(for: larger.format)
    }


    /// Points this join's ``fyle``, ``fileName`` and ``uti`` at the file sent for `format`: see ``variantSent(whenSelectedFormatIs:)``.
    ///
    /// The file for that size may not exist yet. The join then points at the nearest larger size, and this is called again when the file
    /// lands. Sending waits for it.
    ///
    /// Each property is written only if it changes, so that fetched results controllers watching the draft do not rebuild for nothing.
    func setSelectedFormat(_ format: ObvMediaFormat) {
        guard let variant = variantSent(whenSelectedFormatIs: format),
              let fyleOfVariant = variant.fyle,
              let utiOfVariant = variant.uti,
              let fileNameOfVariant = variant.fileName else { return }
        if self.fyle != fyleOfVariant { self.fyle = fyleOfVariant }
        if self.uti != utiOfVariant { self.uti = utiOfVariant }
        if self.fileName != fileNameOfVariant { self.fileName = fileNameOfVariant }
    }

}


// MARK: - Initializer

extension PersistedDraftFyleJoin {
    
    private convenience init(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, fyleObjectID: NSManagedObjectID, fileName: String, uti: String, within context: NSManagedObjectContext) throws {

        guard let draft = try PersistedDraft.get(objectID: draftObjectID, within: context) else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindDraft
        }
        guard let fyle = try Fyle.get(objectID: fyleObjectID, within: context) else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindFyle
        }

        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedDraftFyleJoin.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.fileName = fileName
        self.uti = uti
        let currentIndexes = draft.unsortedDraftFyleJoins.map { return $0.index }
        self.index = 1 + (currentIndexes.max() ?? -1)
        self.permanentUUID = UUID()
        
        self.draft = draft
        self.fyle = fyle
        
    }
    
    // MARK: detect attachment type
    
    fileprivate static let imageUTTypes: [UTType] = [.jpeg, .gif, .png, .image, .tiff, .rawImage, .svg, .heic, .heif]
    fileprivate static let imageUTIs: [String] = imageUTTypes.map(\.description)
    
    fileprivate static let videoUTTypes: [UTType] = [.movie, .quickTimeMovie, .mpeg4Movie, .mpeg, .avi]
    fileprivate static let videoUTIs: [String] = videoUTTypes.map(\.description)

    fileprivate static let audioUTTypes: [UTType] = [.m4a]
    fileprivate static let audioUTIs: [String] = audioUTTypes.map(\.description)

    fileprivate static let mediaUTIs: [String] = videoUTIs + audioUTIs
    
    public var attachmentType: FyleMessageJoinType {
        if Self.videoUTIs.contains(uti) {
            return .video
        }
        
        if Self.audioUTIs.contains(uti) {
            return .audio
        }
        
        if !(Self.mediaUTIs + Self.imageUTIs).contains(uti) {
            return .other
        }
        
        return .photo
    }
    
    public enum FyleMessageJoinType {
        case photo
        case video
        case audio
        case other
    }
    
    
    /// Method to call to add an attachment to a draft
    public static func createPersistedDraftFyleJoinIfRequired(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, fileName: String, fileType: UTType, fyle: Fyle, within context: NSManagedObjectContext) throws {
        if try PersistedDraftFyleJoin.getJoinHolding(fyleObjectID: fyle.objectID, atAnySize: draftObjectID, within: context) == nil {
            _ = try PersistedDraftFyleJoin(draftObjectID: draftObjectID, fyleObjectID: fyle.objectID, fileName: fileName, uti: fileType.identifier, within: context)
        }
    }


    /// Whether this file is already attached to this draft — which is what stops the same photo being attached twice.
    ///
    /// Two lookups, because ``fyle`` moves: the join's own `fyle` while it is still the original, then the ``ObvMediaFormat/max`` variant,
    /// the only one holding the original once sizes exist. Only `max` is asked, not every variant, so that a different file identical to
    /// some other attachment's smaller copy is not refused.
    static func getJoinHolding(fyleObjectID: NSManagedObjectID, atAnySize draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        if let join = try PersistedDraftFyleJoin.get(draftObjectID: draftObjectID, fyleObjectID: fyleObjectID, within: context) {
            return join
        }
        return try PersistedDraftFyleJoinVariant.getVariantHoldingTheOriginal(draftObjectID: draftObjectID, fyleObjectID: fyleObjectID, within: context)?.draftFyleJoin
    }


}


// MARK: - Convenience DB getters

extension PersistedDraftFyleJoin {
    
    public struct Predicate {
        public enum Key: String {
            // Attributes
            case fileName = "fileName"
            case index = "index"
            case permanentUUID = "permanentUUID"
            case uti = "uti"
            // Relationships
            case draft = "draft"
            case fyle = "fyle"
            case variants = "variants"
            // Others
            static let draftPermanentUUID = [draft.rawValue, PersistedDraft.Predicate.Key.permanentUUID.rawValue].joined(separator: ".")
        }
        static func persistedDraftFyleJoin(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
        public static func withPersistedDraft(_ persistedDraft: PersistedDraft) -> NSPredicate {
            NSPredicate(Key.draft, equalTo: persistedDraft)
        }
        static func withPersistedDraft(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraft>) -> NSPredicate {
            NSPredicate(Key.draft, equalToObjectWithObjectID: objectID.objectID)
        }
        
        static func withPersistedDraftWithoutPreviews(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraft>) -> NSPredicate {
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.draft, equalToObjectWithObjectID: objectID.objectID),
                NSPredicate(Key.uti, NotEqualToString: UTType.olvidPreviewUti)
            ])
        }
        
        static func withPersistedDraftOnlyPreviews(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraft>) -> NSPredicate {
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(Key.draft, equalToObjectWithObjectID: objectID.objectID),
                NSPredicate(Key.uti, EqualToString: UTType.olvidPreviewUti)
            ])
        }
        
        static func withFyle(_ fyle: Fyle) -> NSPredicate {
            NSPredicate(Key.fyle, equalTo: fyle)
        }
        static func withFyleWithObjectID(_ fyleObjectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(Key.fyle, equalToObjectWithObjectID: fyleObjectID)
        }
        static var withoutDraft: NSPredicate {
            NSPredicate(withNilValueForKey: Key.draft)
        }
        static func withDraft(withPermanentID draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>) -> NSPredicate {
            NSPredicate(Key.draftPermanentUUID, EqualToUuid: draftPermanentID.uuid)
        }
        static func withDraft(_ objectID: TypeSafeManagedObjectID<PersistedDraft>) -> NSPredicate {
            NSPredicate(Key.draft, equalToObjectWithObjectID: objectID.objectID)
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>) -> NSPredicate {
            NSPredicate(Key.permanentUUID, EqualToUuid: permanentID.uuid)
        }
    }
    
    
    @nonobjc public static func fetchRequest() -> NSFetchRequest<PersistedDraftFyleJoin> {
        return NSFetchRequest<PersistedDraftFyleJoin>(entityName: PersistedDraftFyleJoin.entityName)
    }
    

    static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<PersistedDraftFyleJoin>, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(draftPermanentID: ObvManagedObjectPermanentID<PersistedDraft>, fyleObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withDraft(withPermanentID: draftPermanentID),
            Predicate.withFyleWithObjectID(fyleObjectID),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, fyleObjectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withDraft(draftObjectID),
            Predicate.withFyleWithObjectID(fyleObjectID),
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(objectID typeSafeObjectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, within context: NSManagedObjectContext) -> PersistedDraftFyleJoin? {
        let join: PersistedDraftFyleJoin
        do {
            guard let res = try context.existingObject(with: typeSafeObjectID.objectID) as? PersistedDraftFyleJoin else { throw ObvUICoreDataError.couldNotFindPersistedDraftFyleJoin }
            join = res
        } catch {
            return nil
        }
        return join
    }
    
    
    /// Returns the `ObvLinkMetadata` of a draft. This assumes there is a maximum of one `ObvLinkMetadata` per draft.
    public static func getLinkMetadaAsObvLinkMetadata(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, within context: NSManagedObjectContext) throws -> ObvLinkMetadata? {
        guard let join = try Self.getLinkMetadaAsPersistedDraftFyleJoin(draftObjectID: draftObjectID, within: context) else { return nil }
        guard let fallbackURL = URL(string: join.fileName),
              let fyleURL = join.fyle?.url,
              FileManager.default.fileExists(atPath: fyleURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fyleURL)
        guard let obvEncoded = ObvEncoded(withRawData: data) else { return nil }
        return ObvLinkMetadata.decode(obvEncoded, fallbackURL: fallbackURL)
    }
    
    
    public static func getLinkMetadaAsPersistedDraftFyleJoin(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withDraft(draftObjectID),
            NSPredicate(Predicate.Key.uti, EqualToString: UTType.olvidPreviewUti),
        ])
        request.fetchLimit = 1
        let join = try context.fetch(request).first
        return join
    }
    
    
    
    public static func get(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, within context: NSManagedObjectContext) throws -> PersistedDraftFyleJoin? {
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = Predicate.persistedDraftFyleJoin(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }


    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = Predicate.withoutDraft
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        deleteRequest.resultType = .resultTypeObjectIDs
        let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
    public static func getFetchedResultsController(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraftFyleJoin>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDraftFyleJoin> {
        let request: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        request.predicate = Predicate.persistedDraftFyleJoin(withObjectID: objectID)
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.index.rawValue, ascending: false)]
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: request,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }

    
//    public static func getFetchRequestForPreviewAttachments(withObjectID draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) -> NSFetchRequest<PersistedDraftFyleJoin> {
//        let fetchRequest: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
//        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.index.rawValue, ascending: false)]
//        fetchRequest.fetchBatchSize = 50
//        fetchRequest.predicate = Predicate.withPersistedDraftOnlyPreviews(withObjectID: draftObjectID)
//        return fetchRequest
//    }
    
    public static func getFetchedResultsControllerForAllDraftFyleJoinsOfDraft(withObjectID draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, within context: NSManagedObjectContext) -> NSFetchedResultsController<PersistedDraftFyleJoin> {
        let fetchRequest: NSFetchRequest<PersistedDraftFyleJoin> = PersistedDraftFyleJoin.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.index.rawValue, ascending: false)]
        fetchRequest.fetchBatchSize = 50
        fetchRequest.predicate = Predicate.withPersistedDraftWithoutPreviews(withObjectID: draftObjectID)
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
}


// MARK: - NSFetchedResultsController safeObject

public extension NSFetchedResultsController<PersistedDraftFyleJoin> {
    
    /// Provides a safe way to access a `PersistedMessage` at an `indexPath`.
    func safeObject(at indexPath: IndexPath) -> PersistedDraftFyleJoin? {
        guard let selfSections = self.sections, indexPath.section < selfSections.count else { return nil }
        let sectionInfos = selfSections[indexPath.section]
        guard indexPath.item < sectionInfos.numberOfObjects else { return nil }
        return self.object(at: indexPath)
    }
    
}
