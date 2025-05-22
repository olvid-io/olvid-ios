/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import MobileCoreServices
import ObvTypes
import UniformTypeIdentifiers

@objc(SentFyleMessageJoinWithStatus)
public final class SentFyleMessageJoinWithStatus: FyleMessageJoinWithStatus {
    
    public static let entityName = "SentFyleMessageJoinWithStatus"

    // MARK: Properties

    @NSManaged private var rawReceptionStatus: Int

    // MARK: Relationships
    
    @NSManaged public var sentMessage: PersistedMessageSent

    // MARK: Other variables
    
    private var changedKeys = Set<String>()

    public private(set) var status: FyleStatus {
        get {
            return FyleStatus(rawValue: self.rawStatus)!
        }
        set {
            guard newValue.rawValue != self.rawStatus else { return }
            self.rawStatus = newValue.rawValue
        }
    }

    public private(set) var receptionStatus: FyleReceptionStatus {
        get {
            return FyleReceptionStatus(rawValue: rawReceptionStatus) ?? FyleReceptionStatus.none
        }
        set {
            guard receptionStatus < newValue else { return }
            self.rawReceptionStatus = newValue.rawValue
        }
    }

    public override var message: PersistedMessage? { sentMessage }


    public override var fullFileIsAvailable: Bool {
        switch status {
        case .uploadable, .uploading, .complete:
            guard !isWiped else { return false }
            guard let fyle, FileManager.default.fileExists(atPath: fyle.url.path) else { return false }
            return true
        case .downloadable, .downloading, .cancelledByServer:
            return false
        }
    }

    public enum FyleStatus: Int {
        case uploadable = 0
        case uploading = 1
        case complete = 2 // For both locally sent attachments and attachments sent from other device when fully downloaded
        case downloadable = 3 // When sent from other owned device
        case downloading = 4 // When sent from other owned device
        case cancelledByServer = 5 // When sent from other owned device
    }

    /// The reception status of a file sent from the current device
    public enum FyleReceptionStatus: Int, Comparable {
        case fullyDeliveredAndFullyRead = 2 // Was "read"
        case fullyDeliveredAndPartiallyRead = 3
        case fullyDeliveredAndNotRead = 1 // Was "delivered"
        case partiallyDeliveredAndPartiallyRead = 4
        case partiallyDeliveredNotRead = 5
        case none = 0
        
        private var order: Int {
            switch self {
            case .fullyDeliveredAndFullyRead: return 5
            case .fullyDeliveredAndPartiallyRead: return 4
            case .fullyDeliveredAndNotRead: return 3
            case .partiallyDeliveredAndPartiallyRead: return 2
            case .partiallyDeliveredNotRead: return 1
            case .none: return 0
            }
        }
        
        public static func < (lhs: Self, rhs: Self) -> Bool {
            return lhs.order < rhs.order
        }

        
    }

    // MARK: - Getting FyleMetadata
    
    public func getFyleMetadata() -> FyleMetadata? {

        guard let fyle = self.fyle else { return nil }
        
        let contentType = isPreviewType ? .olvidLinkPreview : (UTType(filenameExtension: (self.fileName as NSString).pathExtension) ?? .data)

        return FyleMetadata(fileName: self.fileName,
                            sha256: fyle.sha256,
                            contentType: contentType)
        
    }
    
    public func markAsComplete() {
        tryToSetStatusTo(.complete)
    }
    
    // Non-nil iff the message was sent from another owned device
    public var messageIdentifierFromEngine: Data? {
        return sentMessage.messageIdentifierFromEngine
    }

    // MARK: - Initializer
    
    convenience init(fyleJoin: FyleJoin, persistedMessageSentObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, within context: NSManagedObjectContext) throws {
        
        guard let fyle = fyleJoin.fyle else {
            assertionFailure()
            throw ObvUICoreDataError.fyleIsNil
        }

        // Pre-compute a few things

        guard let persistedMessageSent = try PersistedMessageSent.getPersistedMessageSent(objectID: persistedMessageSentObjectID, within: context) else {
            assertionFailure()
            throw ObvUICoreDataError.couldNotFindPersistedMessageSent
        }

        // Call the superclass initializer

        try self.init(sha256: fyle.sha256,
                      totalByteCount: fyle.getFileSize() ?? 0,
                      fileName: fyleJoin.fileName,
                      uti: fyleJoin.uti,
                      rawStatus: FyleStatus.uploadable.rawValue,
                      messageSortIndex: persistedMessageSent.sortIndex,
                      index: fyleJoin.index,
                      forEntityName: SentFyleMessageJoinWithStatus.entityName,
                      within: context)
        
        // Set the remaining properties and relationships

        self.sentMessage = persistedMessageSent
        
    }
    
    
    /// Called when receiving an attachment sent from another owned device
    private convenience init(obvOwnedAttachment: ObvOwnedAttachment, messageSent: PersistedMessageSent) throws {
        
        let metadata = try FyleMetadata.jsonDecode(obvOwnedAttachment.metadata)

        guard !messageSent.isWiped else {
            throw ObvUICoreDataError.cannotCreateSentFyleMessageJoinWithStatusForWipedMessage
        }
        
        guard let context = messageSent.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        
        try self.init(sha256: metadata.sha256,
                      totalByteCount: 0, // Reset bellow
                      fileName: metadata.fileName,
                      uti: metadata.contentType.identifier,
                      rawStatus: FyleStatus.downloadable.rawValue,
                      messageSortIndex: messageSent.sortIndex,
                      index: obvOwnedAttachment.number,
                      forEntityName: SentFyleMessageJoinWithStatus.entityName,
                      within: context)
        
        guard let fyle else {
            assertionFailure()
            throw ObvUICoreDataError.fyleIsNil
        }

        if let fileSize = fyle.getFileSize() {
            self.rawStatus = FyleStatus.complete.rawValue
            self.setTotalByteCount(to: fileSize)
        } else {
            self.rawStatus = obvOwnedAttachment.downloadPaused ? FyleStatus.downloadable.rawValue : FyleStatus.downloading.rawValue
            self.setTotalByteCount(to: obvOwnedAttachment.totalUnitCount)
        }

        // Set the remaining properties and relationships
        
        self.sentMessage = messageSent

    }
    
    
    static func createOrUpdateSentFyleMessageJoinWithStatusFromOtherOwnedDevice(with obvOwnedAttachment: ObvOwnedAttachment, messageSent: PersistedMessageSent) throws {
        
        let join: SentFyleMessageJoinWithStatus
        if obvOwnedAttachment.number < messageSent.fyleMessageJoinWithStatuses.count {
            let previousJoin = messageSent.fyleMessageJoinWithStatuses[obvOwnedAttachment.number]
            join = previousJoin
            if join.fyle == nil {
                assertionFailure("This is unexpected as the join should have been cascade deleted when the fyle was deleted")
                let metadata = try FyleMetadata.jsonDecode(obvOwnedAttachment.metadata)
                try join.getOrCreateFyle(sha256: metadata.sha256)
            }
        } else {
            join = try Self.init(obvOwnedAttachment: obvOwnedAttachment,
                             messageSent: messageSent)
            assert(join.fyle != nil, "The fyle should have been created by the init of the superclass")
        }

        try join.updateSentFyleMessageJoinWithStatusFromOtherOwnedDevice(with: obvOwnedAttachment)
            
    }
    
    
    private func updateSentFyleMessageJoinWithStatusFromOtherOwnedDevice(with obvOwnedAttachment: ObvOwnedAttachment) throws {
        
        // Update the status of the ReceivedFyleMessageJoinWithStatus depending on the status of the ObvAttachment

        switch obvOwnedAttachment.status {
        case .paused:
            tryToSetStatusTo(.downloadable)
        case .resumed:
            tryToSetStatusTo(.downloading)
        case .downloaded:
            tryToSetStatusTo(.complete)
        case .cancelledByServer:
            tryToSetStatusTo(.cancelledByServer)
        case .markedForDeletion:
            break
        }

        guard let fyle else {
            assertionFailure("Could not find fyle although this join should have been cascade deleted when the fyle was deleted")
            throw ObvUICoreDataError.fyleIsNil
        }

        try fyle.updateFyle(with: obvOwnedAttachment)

        // If the status is downloaded and the fyle is available, we can delete any existing downsized preview

        let attachmentFullyReceived = (status == .complete) && (fyle.getFileSize() == totalByteCount)

        if attachmentFullyReceived {
            deleteDownsizedThumbnail()
        }
        
    }
    

    public func fyleElementOfSentJoin() -> FyleElement? {
        try? FyleElementForFyleMessageJoinWithStatus.init(self)
    }


    public override func wipe() throws {
        try super.wipe()
        tryToSetStatusTo(.complete)
    }
    
    
    func tryToSetStatusTo(_ newStatus: FyleStatus) {
        guard self.status != .complete else { return }
        self.rawStatus = newStatus.rawValue
        if self.status == .complete {
            let joinObjectID = (self as FyleMessageJoinWithStatus).typedObjectID
            Task {
                await FyleMessageJoinWithStatus.removeProgressForJoinWithObjectID(joinObjectID)
            }
        }
    }
    
    
    func tryToSetReceptionStatusTo(_ newReceptionStatus: FyleReceptionStatus) {
        guard newReceptionStatus > receptionStatus else { return }
        self.receptionStatus = newReceptionStatus
    }
    
    
    /// Set the downsized thumbnail if required. Returns `true` if this was the case, or `false` otherwise.
    ///
    /// Exclusively called from ``PersistedMessageReceived.saveExtendedPayload(foundIn:)``.
    override func setDownsizedThumbnailIfRequired(data: Data) -> Bool {
        assert(self.downsizedThumbnail == nil)
        guard !isWiped else { assertionFailure(); return false }
        guard requiresDownsizedThumbnail() else { return false }
        return super.setDownsizedThumbnailIfRequired(data: data)
    }

    
    // `true` if this join is not complete, or if the fyle is not completely available on disk
    private func requiresDownsizedThumbnail() -> Bool {
        guard let fyle = self.fyle else { return true }
        return self.status != .complete || fyle.getFileSize() != self.totalByteCount
    }

}


// MARK: - Determining actions availability

extension SentFyleMessageJoinWithStatus {
    
    var copyActionCanBeMadeAvailableForSentJoin: Bool {
        return shareActionCanBeMadeAvailableForSentJoin
    }
    
    var shareActionCanBeMadeAvailableForSentJoin: Bool {
        guard !isPreviewType else { return false }
        return sentMessage.shareActionCanBeMadeAvailableForSentMessage
    }
    
    var forwardActionCanBeMadeAvailableForSentJoin: Bool {
        return shareActionCanBeMadeAvailableForSentJoin
    }

}


// MARK: - Convenience DB getters

extension SentFyleMessageJoinWithStatus {
    
    struct Predicate {
        enum Key: String {
            case rawReceptionStatus = "rawReceptionStatus"
            case sentMessage = "sentMessage"
        }
        static var isIncomplete: NSPredicate {
            NSPredicate(FyleMessageJoinWithStatus.Predicate.Key.rawStatus, DistinctFromInt: FyleStatus.complete.rawValue)
        }
        static var withoutSentMessage: NSPredicate {
            NSPredicate(withNilValueForKey: Key.sentMessage)
        }
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<SentFyleMessageJoinWithStatus> {
        return NSFetchRequest<SentFyleMessageJoinWithStatus>(entityName: SentFyleMessageJoinWithStatus.entityName)
    }

    public static func getSentFyleMessageJoinWithStatus(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> SentFyleMessageJoinWithStatus? {
        return try context.existingObject(with: objectID) as? SentFyleMessageJoinWithStatus
    }
    
    
    static func getSentFyleMessageJoinWithStatus(objectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>, within context: NSManagedObjectContext) throws -> SentFyleMessageJoinWithStatus? {
        let request: NSFetchRequest<SentFyleMessageJoinWithStatus> = SentFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = SentFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = Predicate.withoutSentMessage
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
}


// MARK: - Downcasting

public extension TypeSafeManagedObjectID where T == SentFyleMessageJoinWithStatus {
    var downcast: TypeSafeManagedObjectID<FyleMessageJoinWithStatus> {
        TypeSafeManagedObjectID<FyleMessageJoinWithStatus>(objectID: objectID)
    }
}


// MARK: - Notifying on changes

extension SentFyleMessageJoinWithStatus {
    
    public override func willSave() {
        super.willSave()
        if !isInserted, !isDeleted, isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }
    }
    
    
    public override func didSave() {
        super.didSave()
        
        defer {
            self.changedKeys.removeAll()
        }

        if !isDeleted, changedKeys.contains(PersistedMessage.Predicate.Key.rawStatus.rawValue), let discussion = self.sentMessage.discussion {
            let messageID = self.sentMessage.typedObjectID
            let discussionID = discussion.typedObjectID
            ObvMessengerCoreDataNotification.statusOfSentFyleMessageJoinDidChange(
                sentJoinID: self.typedObjectID,
                messageID: messageID,
                discussionID: discussionID)
                .postOnDispatchQueue()
        }
        
    }
    
}
