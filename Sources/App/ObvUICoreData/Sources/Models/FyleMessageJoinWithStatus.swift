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
import CoreData
import os.log
import UIKit
import OlvidUtils
import UniformTypeIdentifiers
import ObvSettings


@objc(FyleMessageJoinWithStatus)
public class FyleMessageJoinWithStatus: NSManagedObject, FyleJoin {
    
    private static let entityName = "FyleMessageJoinWithStatus"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: FyleMessageJoinWithStatus.self))

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
        static func forStatus(_ rawStatus: Int) -> NSPredicate {
            NSPredicate(Key.rawStatus, EqualToInt: rawStatus)
        }
        static func withUTI(_ uti: String) -> NSPredicate {
            NSPredicate(Key.uti, EqualToString: uti)
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
        static func withPermanentID(_ permanentID: ObvManagedObjectPermanentID<FyleMessageJoinWithStatus>) -> NSPredicate {
            NSPredicate(Key.permanentUUID, EqualToUuid: permanentID.uuid)
        }
        static func whereUTIBeginsWith(_ text: String) -> NSPredicate {
            NSPredicate(beginsWithText: text, forKey: Key.uti)
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
