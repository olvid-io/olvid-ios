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
import OSLog
import CoreData
import MobileCoreServices
import ObvTypes
import ObvAppTypes
import UniformTypeIdentifiers
import ObvSettings
import ObvAppTypes


@objc(SentFyleMessageJoinWithStatus)
public final class SentFyleMessageJoinWithStatus: FyleMessageJoinWithStatus {
    
    public static let entityName = "SentFyleMessageJoinWithStatus"
    private static let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: "SentFyleMessageJoinWithStatus")

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
        case .downloadable, .downloading, .cancelledByServer, .untransferred:
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
        case untransferred = 6
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
    

    /// This method shall only be called when considering a message sent from the current device.
    public func markAsFullyUploadedByCurrentDevice() {
        guard sentMessage.isSentFromCurrentDevice else {
            Self.logger.fault("Calling markAsFullyUploadedByCurrentDevice on a message sent from another owned device. This is a bug.")
            assertionFailure("This method should only be called on attachments sent from the current device. This error should be investigated.")
            return
        }
        tryToSetStatusTo(.complete)
    }
    
    
    // Non-nil iff the message was sent from another owned device
    public var messageIdentifierFromEngine: Data? {
        return sentMessage.messageIdentifierFromEngine
    }

    
    private var skipAllNotificationsOnDidSave = false
    
    override func setSkipAllNotificationsOnDidSave(to newValue: Bool) {
        super.setSkipAllNotificationsOnDidSave(to: newValue)
        self.skipAllNotificationsOnDidSave = newValue
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
            switch obvOwnedAttachment.status {
            case .paused(let expectedTotalUnitCount):
                self.setTotalByteCount(to: expectedTotalUnitCount)
            case .resumed(let expectedTotalUnitCount):
                self.setTotalByteCount(to: expectedTotalUnitCount)
            case .downloaded(url: let url):
                if let totalUnitCount = FileManager.default.getFileSize(at: url) {
                    self.setTotalByteCount(to: Int64(totalUnitCount))
                }
            case .cancelledByServer:
                self.setTotalByteCount(to: 0)
            case .markedForDeletion:
                self.setTotalByteCount(to: 0)
            case .receivedInUserNotification:
                self.setTotalByteCount(to: 0)
            }
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
    
    func setStatusToDownloadedDuringHistoryTransfer(fileSize: Int64) {
        tryToSetStatusTo(.complete)
        self.setTotalByteCount(to: fileSize)
        self.setSkipAllNotificationsOnDidSave(to: true)
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
        case .receivedInUserNotification:
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


// MARK: - History transfer

extension SentFyleMessageJoinWithStatus {
    
    /// Creates a `SentFyleMessageJoinWithStatus` during a history transfer from a source to this destination device. A previous `SentFyleMessageJoinWithStatus` cannot exist.
    static func createSentDuringHistoryTransfer(sentMessage: PersistedMessageSent,
                                                attachment: ObvHistoryReceivedMessage.Attachment) throws {
        let join = try Self.init(sentMessage: sentMessage, attachment: attachment)
        assert(join.fyle != nil, "The fyle should have been created by the init of the superclass")
    }

    
    private convenience init(sentMessage: PersistedMessageSent,
                             attachment: ObvHistoryReceivedMessage.Attachment) throws {
        
        guard let context = sentMessage.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }

        try self.init(sha256: attachment.sha256,
                      totalByteCount: Int64(attachment.size),
                      fileName: attachment.filename.trimmingWhitespacesAndNewlines(),
                      uti: attachment.uti,
                      rawStatus: FyleStatus.untransferred.rawValue,
                      messageSortIndex: sentMessage.sortIndex,
                      index: attachment.number,
                      forEntityName: SentFyleMessageJoinWithStatus.entityName,
                      within: context)
        
        // Properties
        
        self.receptionStatus = .none
        
        // Relationships
        
        self.sentMessage = sentMessage
        
        guard let fyle else {
            assertionFailure()
            throw ObvUICoreDataError.theFyleShouldHaveBeenCreatedByTheSuperclassInitializer
        }

        if let fileSize = fyle.getFileSize() {
            self.rawStatus = FyleStatus.complete.rawValue
            self.setTotalByteCount(to: fileSize)
        } else {
            self.rawStatus = FyleStatus.untransferred.rawValue
        }

        self.setSkipAllNotificationsOnDidSave(to: true)

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
        static var isComplete: NSPredicate {
            NSPredicate(FyleMessageJoinWithStatus.Predicate.Key.rawStatus, EqualToInt: FyleStatus.complete.rawValue)
        }
        static var withoutSentMessage: NSPredicate {
            NSPredicate(withNilValueForKey: Key.sentMessage)
        }
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<SentFyleMessageJoinWithStatus>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
        static func withOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> NSPredicate {
            let key: String = [
                Key.sentMessage.rawValue,
                PersistedMessage.Predicate.Key.discussion.rawValue,
                PersistedDiscussion.Predicate.Key.ownedIdentityIdentity].joined(separator: ".")
            return NSPredicate(key, EqualToData: ownedCryptoId.getIdentity())
        }
        static func fyleSha256IsIn(sha256s: [Data]) -> NSPredicate {
            assert(sha256s.count < 200)
            let key = [
                FyleMessageJoinWithStatus.Predicate.Key.fyle.rawValue,
                Fyle.Predicate.Key.sha256.rawValue,
            ].joined(separator: ".")
            return NSPredicate(key, in: sha256s)
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<SentFyleMessageJoinWithStatus> {
        return NSFetchRequest<SentFyleMessageJoinWithStatus>(entityName: SentFyleMessageJoinWithStatus.entityName)
    }
    
    
    /// Returns a dictionary keyed by Fyle's sha256, where values are the file size on disk.
    ///
    /// This is used during a message history transfer on the source device.
    public static func getSha256AndSizeOfCompleteFyles(ownedCryptoId: ObvCryptoId, within context: NSManagedObjectContext) throws -> [Data: UInt64] {
        let request: NSFetchRequest<SentFyleMessageJoinWithStatus> = SentFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedCryptoId(ownedCryptoId),
            Predicate.isComplete,
        ])
        request.propertiesToFetch = [
            FyleMessageJoinWithStatus.Predicate.Key.fyle.rawValue,
        ]
        request.fetchBatchSize = 200
        let items = try context.fetch(request)
        var sizeFromSha256 = [Data: UInt64]()
        for item in items {
            guard let fyle = item.fyle, let size = fyle.getFileSize() else { assertionFailure(); continue }
            sizeFromSha256[fyle.sha256] = UInt64(size)
        }
        return sizeFromSha256
    }
    
    
    /// Returns a subset of sha256s, containing only the sha256s of files that are known and complete.
    public static func filterKnownAndCompleteFyles(sha256s: [Data], within context: NSManagedObjectContext) throws -> [Data] {
        let sliceSize = 100
        var knownAndComplete = [Data]()
        let slices = sha256s.toSlices(ofMaxSize: sliceSize)
        for slice in slices {
            let request: NSFetchRequest<SentFyleMessageJoinWithStatus> = SentFyleMessageJoinWithStatus.fetchRequest()
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.isComplete,
                Predicate.fyleSha256IsIn(sha256s: slice),
            ])
            request.fetchLimit = sliceSize
            let results = try context.fetch(request)
            for result in results {
                if let sha256 = result.fyle?.sha256 {
                    knownAndComplete.append(sha256)
                }
            }
        }
        return knownAndComplete
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
    
    /// Returns a dictionary where each key is the objectID of a `PersistedDiscussion` having at least one `FyleMessageJoinWithStatus`, and the value is the sum of total byte count of those fyles..
    /// Note that if a discussion has no relevant attachment, it does *not* appear in the returned dictionary.
    ///
    public static func getAllDiscussionsWithSentFyleMessageJoinWithStatusDownloadedTotalByteCount(for ownedCryptoId: ObvCryptoId) -> NSFetchRequest<any NSFetchRequestResult> {
        
        let expressionDescription = NSExpressionDescription()
        expressionDescription.name = "sumOfTotalByteCount"
        expressionDescription.expression = NSExpression(forFunction: "sum:", arguments: [NSExpression(forKeyPath: "totalByteCount")])
        expressionDescription.expressionResultType = .integer64AttributeType

        let sentDiscussionPredicate = [Predicate.Key.sentMessage.rawValue,
                                       PersistedMessage.Predicate.Key.discussion.rawValue].joined(separator: ".")
        
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [expressionDescription, sentDiscussionPredicate]
        request.includesPendingChanges = true
        request.sortDescriptors = [NSSortDescriptor(key: FyleMessageJoinWithStatus.Predicate.Key.index.rawValue, ascending: true)]
        request.propertiesToGroupBy = [sentDiscussionPredicate]
        let subPredicates = [
            FyleMessageJoinWithStatus.Predicate.forStatus(SentFyleMessageJoinWithStatus.FyleStatus.complete.rawValue),
            FyleMessageJoinWithStatus.Predicate.forSentOwnedCryptoId(ownedCryptoId),
            FyleMessageJoinWithStatus.Predicate.isWiped(is: false)
        ]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subPredicates)
        
        return request
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
            self.setSkipAllNotificationsOnDidSave(to: false)
        }
        
        guard !self.skipAllNotificationsOnDidSave else { return }

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
