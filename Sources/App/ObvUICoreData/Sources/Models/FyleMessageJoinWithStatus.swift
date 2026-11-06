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
import UIKit
import OlvidUtils
import UniformTypeIdentifiers
import ObvSettings
import ObvTypes
import ObvCrypto

@objc(FyleMessageJoinWithStatus)
public class FyleMessageJoinWithStatus: NSManagedObject, FyleJoin {
    
    private static let entityName = "FyleMessageJoinWithStatus"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: FyleMessageJoinWithStatus.self))
    private static let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: FyleMessageJoinWithStatus.self))

    // MARK: - Properties

    @NSManaged public private(set) var downsizedThumbnail: Data?
    @NSManaged private(set) public var fileName: String
    @NSManaged private(set) public var index: Int // Corresponds to the index of this attachment in the message. Used together with messageSortIndex to sort all joins received in a discussion
    @NSManaged public private(set) var isWiped: Bool
    @NSManaged private(set) var messageSortIndex: Double // Equal to the message sortIndex, used to sort FyleMessageJoinWithStatus instances in the gallery
    @NSManaged private var permanentUUID: UUID
    @NSManaged public internal(set) var rawStatus: Int
    @NSManaged public private(set) var totalByteCount: Int64 // Was totalUnitCount
    @NSManaged private(set) public var uti: String
    
    // MARK: - Transient properties (allowing to feed SwiftUI progress views)
    
    @NSManaged public var fractionCompleted: Double
    @NSManaged public var estimatedTimeRemaining: TimeInterval
    @NSManaged public var throughput: Int

    // MARK: - Relationships

    @NSManaged private(set) public var fyle: Fyle? // If nil, this entity is eventually cascade-deleted
    
    // MARK: - Other variables
    
    public var contentType: UTType {
        assert(UTType(uti) != nil)
        return UTType(uti) ?? .data
    }
    
    public var isPreviewType: Bool {
        return contentType.conforms(to: .olvidLinkPreview)
    }

    /// Whether this attachment is shown as a picture — in a bubble, in the grid of a message carrying several — rather than as an attachment card.
    ///
    /// Asked of the type system rather than of a list of five identifiers, which is what this used to be and which left TIFF, BMP and camera RAW looking like
    /// documents. Every one of them is something ImageIO decodes and the reader thinks of as a photograph.
    ///
    /// Vector images are the exception, and are excluded on purpose: they conform to `public.image` but ImageIO does not rasterise them, so treating one as a
    /// picture would reserve a bubble for an image that never arrives. A card, which says its name and its size, is the honest thing to show.
    public var isImageType: Bool {
        guard contentType.conforms(to: .image) else { return false }
        guard !contentType.conforms(to: .svg) else { return false }
        return true
    }

    /// Whether this attachment is shown as a video preview — a picture of a frame with a play glyph on it — rather than as an attachment card. Step 63.
    ///
    /// `public.movie` and nothing wider. `public.audiovisual-content` would have been the tempting choice and is **wrong**: `public.audio` conforms to it too, so
    /// every voice message would have become a video. `public.video` — a stream with no sound — conforms to `public.movie`, so it is already covered.
    public var isVideoType: Bool {
        contentType.conforms(to: .movie)
    }

    /// Whether this attachment is a paginated document, of the sort worth showing the first page of.
    ///
    /// `public.compositeContent` is exactly the set wanted, verified rather than assumed: PDF, `.docx`, `.doc`, Pages, `.xlsx`, `.pptx`, Keynote and EPUB conform
    /// to it, while RTF, HTML, plain text and zip archives do not. No list of identifiers to maintain, and none to fall behind the next format Apple adds.
    ///
    /// **Wider than the legacy screen**, which gives its large preview to PDFs alone — `fyleMessageJoinWithStatusesOfPDFOrOtherDocumentLikeType` promises more
    /// than it delivers, being `conforms(to: .pdf)` and nothing else. Nothing new is needed to render the others: the thumbnail path goes through QuickLook, which
    /// does not care what a file is. Narrow this to `.pdf` to return to the legacy behaviour.
    public var isDocumentType: Bool {
        contentType.conforms(to: .compositeContent)
    }
    
    public var message: PersistedMessage? {
        assertionFailure("Must be overriden by subclasses")
        return nil
    }

    public var readOnce: Bool {
        message?.readOnce ?? false
    }
    
    public var fullFileIsAvailable: Bool {
        assertionFailure("Must be overriden by subclasses")
        return false
    }
    
    public var fyleMessageJoinPermanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus> {
        ObvManagedObjectPermanentID(entityName: FyleMessageJoinWithStatus.entityName, uuid: self.permanentUUID)
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
    
    private var skipAllNotificationsOnDidSave = false
    
    func setSkipAllNotificationsOnDidSave(to newValue: Bool) {
        self.skipAllNotificationsOnDidSave = newValue
    }
    
    // MARK: - Initializer

    convenience init(sha256: Data, totalByteCount: Int64, fileName: String, uti: String, rawStatus: Int, messageSortIndex: Double, index: Int, forEntityName entityName: String, within context: NSManagedObjectContext) throws {

        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.downsizedThumbnail = nil // Will be received later
        self.index = index
        self.fileName = fileName
        self.uti = uti
        self.rawStatus = rawStatus
        self.messageSortIndex = messageSortIndex
        self.permanentUUID = UUID()
        self.isWiped = false
        self.totalByteCount = totalByteCount

        self.fyle = try Fyle.getOrCreate(sha256: sha256, within: context)
    }

    
    /// This method is only used during the migration to v1.4, when updating the UTI of the joins that corresponds to ObvLinkPreviews.
    public func migrateDynUtiToOlvidPreviewUti() {
        guard self.uti.starts(with: "dyn") else { assertionFailure(); return }
        if self.uti != UTType.olvidPreviewUti {
            self.uti = UTType.olvidPreviewUti
        }
    }
    
    
    func getOrCreateFyle(sha256: Data) throws {
        guard let context = self.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        self.fyle = try Fyle.getOrCreate(sha256: sha256, within: context)
    }
    
    
    /// Shall only be called by one of the subclasses
    func setTotalByteCount(to newTotalByteCount: Int64) {
        guard self.totalByteCount != newTotalByteCount else { return }
        self.totalByteCount = newTotalByteCount
    }

    public func wipe() throws {
        self.isWiped = true
        self.fyle = nil
        self.fileName = ""
        self.totalByteCount = 0
        self.uti = ""
        deleteDownsizedThumbnail()
    }


    // MARK: - Managing a progress object in the view context
    
    public static let formatterForEstimatedTimeRemaining: DateComponentsFormatter = {
        let dcf = DateComponentsFormatter()
        dcf.unitsStyle = .short
        dcf.includesApproximationPhrase = true
        dcf.includesTimeRemainingPhrase = true
        dcf.allowedUnits = [.day, .hour, .minute, .second]
        return dcf
    }()

    
    // MARK: - Managing the downsized thumbnail
    
    func deleteDownsizedThumbnail() {
        guard self.downsizedThumbnail != nil else { return }
        self.downsizedThumbnail = nil
    }

    
    /// Exclusively called from ``SentFyleMessageJoinWithStatus.setDownsizedThumbnailIfRequired(data:)`` and from ``ReceivedFyleMessageJoinWithStatus.setDownsizedThumbnailIfRequired(data:)``.
    func setDownsizedThumbnailIfRequired(data: Data) -> Bool {
        guard self.downsizedThumbnail != data else { return false }
        self.downsizedThumbnail = data
        return true
    }
    
}


// MARK: - Convenience DB getters

extension FyleMessageJoinWithStatus {
    
    struct Predicate {
        enum Key: String {
            case fileName = "fileName"
            case index = "index"
            case fyle = "fyle"
            case rawStatus = "rawStatus"
            case uti = "uti"
            case messageSortIndex = "messageSortIndex"
            case permanentUUID = "permanentUUID"
            case isWiped = "isWiped"
            case totalByteCount = "totalByteCount"
            
            static let receivedMessage = ReceivedFyleMessageJoinWithStatus.Predicate.Key.receivedMessage.rawValue
            static let sentMessage = SentFyleMessageJoinWithStatus.Predicate.Key.sentMessage.rawValue
            static let ownedIdentityIdentity = [PersistedDiscussion.Predicate.Key.ownedIdentity.rawValue,
                                                PersistedObvOwnedIdentity.Predicate.Key.identity.rawValue].joined(separator: ".")
            static let receivedOwnedIdentity = [receivedMessage,
                                                PersistedMessage.Predicate.Key.discussion.rawValue,
                                                ownedIdentityIdentity].joined(separator: ".")
            static let sentOwnedIdentity = [sentMessage,
                                            PersistedMessage.Predicate.Key.discussion.rawValue,
                                            ownedIdentityIdentity].joined(separator: ".")
            
            // Other
            static let fyleSha256 = [fyle.rawValue, Fyle.Predicate.Key.sha256.rawValue].joined(separator: ".")
        }
        static func withObjectIDs(_ objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>) -> NSPredicate {
            NSPredicate(format: "SELF IN %@", objectIDs.map({ $0.objectID }))
        }
        static func isSentFyleMessageJoinWithStatusInDiscussion(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
            let discussionKey = [SentFyleMessageJoinWithStatus.Predicate.Key.sentMessage.rawValue, PersistedMessage.Predicate.Key.discussion.rawValue].joined(separator: ".")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withEntity: SentFyleMessageJoinWithStatus.entity()),
                NSPredicate(format: "%K == %@", discussionKey, discussionObjectID.objectID),
            ])
        }
        static var isSentFyleMessageJoinWithStatus: NSPredicate {
            return NSPredicate(withEntity: SentFyleMessageJoinWithStatus.entity())
        }
        static var isReceivedFyleMessageJoinWithStatus: NSPredicate {
            return NSPredicate(withEntity: ReceivedFyleMessageJoinWithStatus.entity())
        }
        static func forReceivedOwnedCryptoId(_ ownCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.receivedOwnedIdentity, EqualToData: ownCryptoId.getIdentity())
        }
        static func forSentOwnedCryptoId(_ ownCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.sentOwnedIdentity, EqualToData: ownCryptoId.getIdentity())
        }
        static func forStatus(_ rawStatus: Int) -> NSPredicate {
            NSPredicate(Key.rawStatus, EqualToInt: rawStatus)
        }
        static func withUTI(_ uti: String) -> NSPredicate {
            NSPredicate(Key.uti, EqualToString: uti)
        }
        static func withOwnCryptoId(_ ownCryptoId: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.ownedIdentityIdentity, EqualToData: ownCryptoId.getIdentity())
        }
        static func isWiped(is value: Bool) -> NSPredicate {
            NSPredicate(Key.isWiped, is: value)
        }
        static var fyleIsNonNil: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.fyle)
        }
        static func withSha256(_ sha256: Data) -> NSPredicate {
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                fyleIsNonNil,
                NSPredicate(Key.fyleSha256, EqualToData: sha256),
            ])
        }
        static func withTotalByteCountIsGreaterThanOrEqualTo(_ count: Int64) -> NSPredicate {
            NSPredicate(Key.totalByteCount, largerThanOrEqualToInt: count)
        }
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>) -> NSPredicate {
            NSPredicate(Key.permanentUUID, EqualToUuid: permanentID.uuid)
        }
        static func whereUTIBeginsWith(_ text: String) -> NSPredicate {
            NSPredicate(beginsWithText: text, forKey: Key.uti)
        }
        static func fyleSha256IsIn(sha256s: [Data]) -> NSPredicate {
            assert(sha256s.count < 200)
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                fyleIsNonNil,
                NSPredicate(Key.fyleSha256, in: sha256s),
            ])
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<FyleMessageJoinWithStatus> {
        return NSFetchRequest<FyleMessageJoinWithStatus>(entityName: FyleMessageJoinWithStatus.entityName)
    }

    
    static func getManagedObject(withPermanentID permanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>, within context: NSManagedObjectContext) throws -> FyleMessageJoinWithStatus? {
        let request: NSFetchRequest<FyleMessageJoinWithStatus> = FyleMessageJoinWithStatus.fetchRequest()
        request.predicate = Predicate.withPermanentID(permanentID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    public static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> FyleMessageJoinWithStatus? {
        return try context.existingObject(with: objectID) as? FyleMessageJoinWithStatus
    }


    /// Observes one join, so that a screen showing that attachment of that message can be told when its file arrives.
    public static func getFetchedResultsController(objectID: NSManagedObjectID, within context: NSManagedObjectContext) -> NSFetchedResultsController<FyleMessageJoinWithStatus> {
        let request: NSFetchRequest<FyleMessageJoinWithStatus> = FyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSPredicate(format: "self == %@", objectID)
        request.fetchLimit = 1
        request.sortDescriptors = []
        return .init(fetchRequest: request,
                     managedObjectContext: context,
                     sectionNameKeyPath: nil,
                     cacheName: nil)
    }


    /// Returns the subset of `sha256s` corresponding to fyles that at least one (non-wiped, received or sent) join still awaits: the join references the fyle, but the file is not available on disk.
    ///
    /// This is used during a message history transfer, on the destination device, to decide what to do with the attachments that were declared as expected during negotiation but that no
    /// transferred message ended up requiring. Those still awaited by an existing message (e.g., a message known before the transfer whose attachment was never downloaded) must be
    /// requested to the source; the others must be declined (`DstDoNotRequestSha256`). Requesting an attachment no message awaits (e.g., the user deleted the photo from the discussion's
    /// gallery, which wipes the join but keeps the message) would recreate an orphaned fyle that no message references.
    ///
    /// The "file not on disk" rule deliberately mirrors the request/decline decision made in ``PersistedMessage.createDuringHistoryTransfer(_:within:)`` when storing transferred messages.
    public static func filterSha256sOfFylesStillAwaitedByAJoin(sha256s: Set<Data>, within context: NSManagedObjectContext) throws -> Set<Data> {
        Self.logger.info("📰 Determining which of the \(sha256s.count) sha256s correspond to a fyle still awaited by a join")
        let sliceSize = 100
        var stillAwaited = Set<Data>()
        var sha256sReferencedByAFetchedJoin = Set<Data>()
        let slices = [Data](sha256s).toSlices(ofMaxSize: sliceSize)
        for slice in slices {
            let request: NSFetchRequest<FyleMessageJoinWithStatus> = FyleMessageJoinWithStatus.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.isWiped(is: false),
                Predicate.fyleSha256IsIn(sha256s: slice),
            ])
            let results = try context.fetch(request)
            Self.logger.info("📰 Fetched \(results.count) non-wiped joins for a slice of \(slice.count) sha256s")
            for join in results {
                guard let fyle = join.fyle else {
                    // The predicate requires a non-nil fyle, so this means the fyle was deleted between the fetch and now
                    Self.logger.info("📰 Discarding a \(String(describing: type(of: join)), privacy: .public) (rawStatus: \(join.rawStatus)): its fyle is nil")
                    continue
                }
                let sha256Prefix = fyle.sha256.hexString().prefix(8)
                sha256sReferencedByAFetchedJoin.insert(fyle.sha256)
                guard !fyle.fileExistsOnDisk else {
                    Self.logger.info("📰 [\(sha256Prefix, privacy: .public)] Discarding for the \(String(describing: type(of: join)), privacy: .public) (rawStatus: \(join.rawStatus)): the fyle's file already exists on disk")
                    continue
                }
                Self.logger.info("📰 [\(sha256Prefix, privacy: .public)] Still awaited by a \(String(describing: type(of: join)), privacy: .public) (rawStatus: \(join.rawStatus), totalByteCount: \(join.totalByteCount)): the fyle's file is not on disk")
                stillAwaited.insert(fyle.sha256)
            }
        }
        for sha256 in sha256s.subtracting(sha256sReferencedByAFetchedJoin) {
            Self.logger.info("📰 [\(sha256.hexString().prefix(8), privacy: .public)] Discarding: no non-wiped join references a fyle with this sha256")
        }
        Self.logger.info("📰 Done determining the still awaited fyles: \(stillAwaited.count) still awaited out of \(sha256s.count) sha256s")
        return stillAwaited
    }

    
    static func getAllWithObjectIDs(_ objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>, within context: NSManagedObjectContext) throws -> Set<FyleMessageJoinWithStatus> {
        let request: NSFetchRequest<FyleMessageJoinWithStatus> = FyleMessageJoinWithStatus.fetchRequest()
        request.predicate = Predicate.withObjectIDs(objectIDs)
        return Set(try context.fetch(request))
    }
    
    /**
     * Get all `FyleMessageJoinWithStatus` persisted on the local database not downloaded yet and of type `Preview`, regardless of the owned identity
     *  - Returns [FyleMessageJoinWithStatus]
     */
    /// Returns all `FyleMessageJoinWithStatus` not downloaded yet, regardless of the owned identity.
    public static func getAllPreviewsWithStatusNotDownloaded(within context: NSManagedObjectContext) throws -> [FyleMessageJoinWithStatus] {
        
        // Previews Received
        let receivedRequest: NSFetchRequest<ReceivedFyleMessageJoinWithStatus> = ReceivedFyleMessageJoinWithStatus.fetchRequest()
        receivedRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forStatus(ReceivedFyleMessageJoinWithStatus.FyleStatus.downloadable.rawValue),
            Predicate.withUTI(UTType.olvidPreviewUti),
        ])
        let receivedPreviewsNotDownloaded = try context.fetch(receivedRequest)
        
        // Previews sent
        let sentRequest: NSFetchRequest<SentFyleMessageJoinWithStatus> = SentFyleMessageJoinWithStatus.fetchRequest()
        sentRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.forStatus(SentFyleMessageJoinWithStatus.FyleStatus.downloadable.rawValue),
            Predicate.withUTI(UTType.olvidPreviewUti),
        ])
        let sentPreviewsNotDownloaded = try context.fetch(sentRequest)

        return receivedPreviewsNotDownloaded + sentPreviewsNotDownloaded
    }
    
    /**
     * Get all `FyleMessageJoinWithStatus` persisted on the local database already downloaded.
     *  - Returns [FyleMessageJoinWithStatus]
     */
    /// Returns all `FyleMessageJoinWithStatus` already downloaded
    public static func getFetchRequestForAllFyleMessageJoinWithStatusDownloaded(for ownCryptoId: ObvCryptoId, withMinimumThresholdOfTotalByteCount totalByteCount: Int64? = nil, within discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>? = nil) -> NSFetchRequest<FyleMessageJoinWithStatus> {
        
        let request: NSFetchRequest<FyleMessageJoinWithStatus> = FyleMessageJoinWithStatus.fetchRequest()
        
        request.sortDescriptors = sortDescriptorsForAllFyleMessageJoinWithStatusDownloaded()
        request.predicate = predicateForAllFyleMessageJoinWithStatusDownloaded(for: ownCryptoId,
                                                                               withMinimumThresholdOfTotalByteCount: totalByteCount,
                                                                               within: discussionObjectID)
        
        return request
    }
    
    private static func sortDescriptorsForAllFyleMessageJoinWithStatusDownloaded() -> [NSSortDescriptor] {
        [NSSortDescriptor(key: FyleMessageJoinWithStatus.Predicate.Key.index.rawValue, ascending: true)]
    }
    
    public static func predicateForAllFyleMessageJoinWithStatusDownloaded(for ownCryptoId: ObvCryptoId, withMinimumThresholdOfTotalByteCount totalByteCount: Int64? = nil, within discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>? = nil) -> NSPredicate {
        
        let receivedPredicate = predicateForReceivedFyleMessageJoinWithStatusDownloaded(for: ownCryptoId,
                                                                                        withMinimumThresholdOfTotalByteCount: totalByteCount,
                                                                                        within: discussionObjectID)
        
        let sentPredicate = predicateForSentFyleMessageJoinWithStatusDownloaded(for: ownCryptoId,
                                                                                withMinimumThresholdOfTotalByteCount: totalByteCount,
                                                                                within: discussionObjectID)
        
        return NSCompoundPredicate(orPredicateWithSubpredicates: [receivedPredicate, sentPredicate])
    }
    
    public static func predicateForReceivedFyleMessageJoinWithStatusDownloaded(for ownCryptoId: ObvCryptoId, withMinimumThresholdOfTotalByteCount totalByteCount: Int64? = nil, within discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>? = nil) -> NSPredicate {
        
        var subPredicates = [
            Predicate.isReceivedFyleMessageJoinWithStatus,
            Predicate.forStatus(ReceivedFyleMessageJoinWithStatus.FyleStatus.complete.rawValue),
            Predicate.forReceivedOwnedCryptoId(ownCryptoId),
            Predicate.isWiped(is: false)
        ]
        
        if let totalByteCount {
            subPredicates.append(Predicate.withTotalByteCountIsGreaterThanOrEqualTo(totalByteCount))
        }
        
        if let discussionObjectID {
            subPredicates.append(Predicate.isFyleMessageJoinWithStatusInDiscussion(discussionObjectID))
        }
        
        return NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
    }
    
    public static func predicateForSentFyleMessageJoinWithStatusDownloaded(for ownCryptoId: ObvCryptoId, withMinimumThresholdOfTotalByteCount totalByteCount: Int64? = nil, within discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>? = nil) -> NSPredicate {
        
        var subPredicates = [
            Predicate.isSentFyleMessageJoinWithStatus,
            Predicate.forStatus(SentFyleMessageJoinWithStatus.FyleStatus.complete.rawValue),
            Predicate.forSentOwnedCryptoId(ownCryptoId),
            Predicate.isWiped(is: false)
        ]
        
        if let totalByteCount {
            subPredicates.append(Predicate.withTotalByteCountIsGreaterThanOrEqualTo(totalByteCount))
        }
        
        if let discussionObjectID {
            subPredicates.append(Predicate.isFyleMessageJoinWithStatusInDiscussion(discussionObjectID))
        }
        
        return NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
    }
    
    /**
     * Get all `FyleMessageJoinWithStatus` persisted on the local database already downloaded regardless of the owned identity
     *  - Returns [FyleMessageJoinWithStatus]
     */
    /// Returns all `FyleMessageJoinWithStatus` already downloaded, regardless of the owned identity.
    public static func getFetchRequestForSentFyleMessageJoinWithStatusDownloaded(for ownCryptoId: ObvCryptoId) -> NSFetchRequest<FyleMessageJoinWithStatus> {
        
        let request: NSFetchRequest<FyleMessageJoinWithStatus> = FyleMessageJoinWithStatus.fetchRequest()
        
        request.sortDescriptors = sortDescriptorsForAllFyleMessageJoinWithStatusDownloaded()
        request.predicate = predicateForSentFyleMessageJoinWithStatusDownloaded(for: ownCryptoId)
        
        return request
    }
    
    /// Returns the ``objectID`` of all ``FyleMessageJoinWithStatus`` objects whose UTI starts with the string "dyn."
    public static func getIdentifiersOfFyleMessageJoinWithStatusWithDynamicUTI(within context: NSManagedObjectContext) throws -> [TypeSafeManagedObjectID<FyleMessageJoinWithStatus>] {
        let request = Self.fetchRequest()
        request.predicate = Predicate.whereUTIBeginsWith("dyn.")
        request.fetchBatchSize = 500
        request.propertiesToFetch = []
        let joins = try context.fetch(request)
        return joins.map(\.typedObjectID)
    }
    
    
    @MainActor
    public static var progressForJoinWithObjectID = [TypeSafeManagedObjectID<FyleMessageJoinWithStatus>: ObvProgress]()
    
    @MainActor
    static func removeProgressForJoinWithObjectID(_ joinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) {
        assert(Thread.isMainThread)
        _ = progressForJoinWithObjectID.removeValue(forKey: joinObjectID)
    }
}


// MARK: - On save

extension FyleMessageJoinWithStatus {
    
    public override func didSave() {
        super.didSave()

        // We don't set skipAllNotificationsOnDidSave back to false, this
        // is done by one of the two concrete subclasses (SentFyleMessageJoinWithStatus or
        // ReceivedFyleMessageJoinWithStatus)
        
        guard !self.skipAllNotificationsOnDidSave else { return }

        if isInserted {
            ObvMessengerCoreDataNotification.fyleMessageJoinWithStatusWasInserted(fyleMessageJoinObjectID: typedObjectID)
                .postOnDispatchQueue()
        }
        
        if isUpdated {
            ObvMessengerCoreDataNotification.fyleMessageJoinWithStatusWasUpdated(fyleMessageJoinObjectID: typedObjectID)
                .postOnDispatchQueue()
        }
        
    }
    
}

extension FyleMessageJoinWithStatus: Identifiable {}

// MARK: - NSFetchedResultsController safeObject

public extension NSFetchedResultsController<FyleMessageJoinWithStatus> {
    
    /// Provides a safe way to access a `PersistedMessage` at an `indexPath`.
    func safeObject(at indexPath: IndexPath) -> FyleMessageJoinWithStatus? {
        guard let selfSections = self.sections, indexPath.section < selfSections.count else { return nil }
        let sectionInfos = selfSections[indexPath.section]
        guard indexPath.item < sectionInfos.numberOfObjects else { return nil }
        return self.object(at: indexPath)
    }
    
}
