/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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
import CoreServices
import ObvEngine


@objc(ReceivedFyleMessageJoinWithStatus)
public final class ReceivedFyleMessageJoinWithStatus: FyleMessageJoinWithStatus, Identifiable {
    
    private static let entityName = "ReceivedFyleMessageJoinWithStatus"

    public enum FyleStatus: Int {
        case downloadable = 0
        case downloading = 1
        case complete = 2
        case cancelledByServer = 3
    }
        
    // MARK: Properties
    
    @NSManaged public private(set) var downsizedThumbnail: Data?
    @NSManaged public private(set) var wasOpened: Bool

    // MARK: Relationships
    
    @NSManaged public private(set) var receivedMessage: PersistedMessageReceived

    // MARK: Computed properties
    
    public var status: FyleStatus {
        return FyleStatus(rawValue: self.rawStatus)!
    }
    
    public var messageIdentifierFromEngine: Data {
        return receivedMessage.messageIdentifierFromEngine
    }
    
    public override var message: PersistedMessage? { receivedMessage }

    public override var fullFileIsAvailable: Bool { status == .complete }

    private var changedKeys = Set<String>()

    // MARK: - Initializer
    
    // Called when a fyle is already available
    public convenience init(metadata: FyleMetadata, obvAttachment: ObvAttachment, within context: NSManagedObjectContext) throws {

        guard let receivedMessage = try PersistedMessageReceived.get(messageIdentifierFromEngine: obvAttachment.messageIdentifier,
                                                                     from: obvAttachment.fromContactIdentity,
                                                                     within: context) else { throw Self.makeError(message: "Could not find PersistedMessageReceived") }

        guard !receivedMessage.isWiped else {
            throw Self.makeError(message: "Trying to create a ReceivedFyleMessageJoinWithStatus for a wiped received message")
        }
        
        // Pre-compute a few things
        
        let fyle: Fyle
        do {
            let _fyle = try Fyle.get(sha256: metadata.sha256, within: context)
            guard _fyle != nil else { throw Self.makeError(message: "Could not get Fyle (1)") }
            fyle = _fyle!
        }

        let rawStatus: Int
        let totalByteCount: Int64
        if let fileSize = fyle.getFileSize() {
            rawStatus = FyleStatus.complete.rawValue
            totalByteCount = fileSize
        } else {
            rawStatus = obvAttachment.downloadPaused ? FyleStatus.downloadable.rawValue : FyleStatus.downloading.rawValue
            totalByteCount = obvAttachment.totalUnitCount
        }
        
        // Call the superclass initializer

        self.init(totalByteCount: totalByteCount,
                  fileName: metadata.fileName,
                  uti: metadata.uti,
                  rawStatus: rawStatus,
                  messageSortIndex: receivedMessage.sortIndex,
                  index: obvAttachment.number,
                  fyle: fyle,
                  forEntityName: ReceivedFyleMessageJoinWithStatus.entityName,
                  within: context)

        // Set the remaining properties and relationships
        
        self.downsizedThumbnail = nil
        self.receivedMessage = receivedMessage
    }
    
    
    public override func wipe() throws {
        try super.wipe()
        tryToSetStatusTo(.complete)
        deleteDownsizedThumbnail()
    }
    
}

// MARK: - Other methods

extension ReceivedFyleMessageJoinWithStatus {

    public func deleteDownsizedThumbnail() {
        self.downsizedThumbnail = nil
    }
    
    
    public func tryToSetStatusTo(_ newStatus: FyleStatus) {
        guard self.status != .complete else { return }
        self.rawStatus = newStatus.rawValue
        self.message?.setHasUpdate()
        if self.status == .complete {
            let joinObjectID = (self as FyleMessageJoinWithStatus).typedObjectID
            Task {
                await FyleMessageJoinWithStatus.removeProgressForJoinWithObjectID(joinObjectID)
            }
        }
    }

    public func markAsOpened() {
        guard !self.wasOpened else { return }
        self.wasOpened = true
    }

    
    public func fyleElementOfReceivedJoin() -> FyleElement? {
        // If the associated received message requires a user interaction to be read, we do *not* return
        // FyleElement as these are typically used to display the join content on screen.
        guard !receivedMessage.readingRequiresUserAction else { return nil }
        return try? FyleElementForFyleMessageJoinWithStatus(self)
    }

    
    func attachementImage() -> NotificationAttachmentImage? {
        guard !receivedMessage.readingRequiresUserAction else { return nil }
        if let fyleElement = fyleElementOfReceivedJoin(), fyleElement.fullFileIsAvailable {
            guard ObvUTIUtils.uti(fyleElement.uti, conformsTo: kUTTypeJPEG) else { return nil }
            return .url(attachmentNumber: index, fyleElement.fyleURL)
        } else if let data = downsizedThumbnail {
            return .data(attachmentNumber: index, data)
        } else {
            return nil
        }
    }

    // `true` if this join is not complete, or if the fyle is not completely available on disk
    func requiresDownsizedThumbnail() -> Bool {
        guard let fyle = self.fyle else { return true }
        return self.status != .complete || fyle.getFileSize() != self.totalByteCount
    }
    
    /// Set the downsized thumbnail if required. Returns `true` if this was the case, or `false` otherwise.
    public func setDownsizedThumbnailIfRequired(data: Data) -> Bool {
        assert(self.downsizedThumbnail == nil)
        guard !isWiped else { assertionFailure(); return false }
        guard requiresDownsizedThumbnail() else { return false }
        guard self.downsizedThumbnail != data else { return false }
        self.downsizedThumbnail = data
        return true
    }

}


// MARK: - Determining actions availability

extension ReceivedFyleMessageJoinWithStatus {
    
    var copyActionCanBeMadeAvailableForReceivedJoin: Bool {
        return shareActionCanBeMadeAvailableForReceivedJoin
    }
    
    var shareActionCanBeMadeAvailableForReceivedJoin: Bool {
        guard status == .complete else { return false }
        return receivedMessage.shareActionCanBeMadeAvailableForReceivedMessage
    }
    
    var forwardActionCanBeMadeAvailableForReceivedJoin: Bool {
        return shareActionCanBeMadeAvailableForReceivedJoin
    }
    
}


// MARK: - Convenience DB getters

extension ReceivedFyleMessageJoinWithStatus {
    
    struct Predicate {
        enum Key: String {
            // Properties
            case downsizedThumbnail = "downsizedThumbnail"
            case wasOpened = "wasOpened"
            // Relationships
            case receivedMessage = "receivedMessage"
        }
        static func forReceivedMessage(_ receivedMessage: PersistedMessageReceived) -> NSPredicate {
            NSPredicate(Key.receivedMessage, equalTo: receivedMessage)
        }
    }

    
    @nonobjc static func fetchRequest() -> NSFetchRequest<ReceivedFyleMessageJoinWithStatus> {
        return NSFetchRequest<ReceivedFyleMessageJoinWithStatus>(entityName: ReceivedFyleMessageJoinWithStatus.entityName)
    }
    
    
    public static func getReceivedFyleMessageJoinWithStatus(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> ReceivedFyleMessageJoinWithStatus {
        guard let obj = try context.existingObject(with: objectID) as? ReceivedFyleMessageJoinWithStatus else { throw makeError(message: "The objectID does not exist or is not a ReceivedFyleMessageJoinWithStatus") }
        return obj
    }
    
    
    public static func get(metadata: FyleMetadata, obvAttachment: ObvAttachment, within context: NSManagedObjectContext) throws -> ReceivedFyleMessageJoinWithStatus? {
        guard let receivedMessage = try PersistedMessageReceived.get(messageIdentifierFromEngine: obvAttachment.messageIdentifier,
                                                                     from: obvAttachment.fromContactIdentity,
                                                                     within: context) else { throw makeError(message: "Could not find the associated PersistedMessageReceived") }
        let request: NSFetchRequest<ReceivedFyleMessageJoinWithStatus> = ReceivedFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            FyleMessageJoinWithStatus.Predicate.withSha256(metadata.sha256),
            Predicate.forReceivedMessage(receivedMessage),
        ])
        request.fetchLimit = 1
        let receivedFyleMessageJoinWithStatuses = try context.fetch(request)
        return receivedFyleMessageJoinWithStatuses.first
    }
 
    
    public static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = ReceivedFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSPredicate(format: "%K == NIL", Predicate.Key.receivedMessage.rawValue)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }

    
    public static func get(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, within context: NSManagedObjectContext) throws -> ReceivedFyleMessageJoinWithStatus? {
        return try super.get(objectID: objectID.objectID, within: context) as? ReceivedFyleMessageJoinWithStatus
    }
}


// Reacting to changes

extension ReceivedFyleMessageJoinWithStatus {
    
    // MARK: - Deleting Fyle when deleting the last ReceivedFyleMessageJoinWithStatus
    
    public override func willSave() {
        super.willSave()
        
        assert(!Thread.isMainThread)

        if isDeleted {
            if let fyle = self.fyle, fyle.allFyleMessageJoinWithStatus.count == 1 && fyle.allFyleMessageJoinWithStatus.first == self {
                managedObjectContext?.delete(fyle)
            }
        } else if isUpdated {
            changedKeys = Set<String>(self.changedValues().keys)
        }

    }
 
    
    public override func didSave() {
        super.didSave()
        
        defer {
            self.changedKeys.removeAll()
        }
        
        if changedKeys.contains(Predicate.Key.wasOpened.rawValue), wasOpened {
            ObvMessengerCoreDataNotification.receivedFyleJoinHasBeenMarkAsOpened(receivedFyleJoinID: self.typedObjectID)
                .postOnDispatchQueue()
        }
                
        let statusChanged = changedKeys.contains(FyleMessageJoinWithStatus.Predicate.Key.rawStatus.rawValue)
        
        if !isDeleted && (statusChanged || isInserted), status == .complete, let returnReceipt = receivedMessage.returnReceipt, let contactCryptoId = receivedMessage.contactIdentity?.cryptoId, let ownedCryptoId = receivedMessage.contactIdentity?.ownedIdentity?.cryptoId {
            ObvMessengerCoreDataNotification.aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus(
                returnReceipt: returnReceipt,
                contactCryptoId: contactCryptoId,
                ownedCryptoId: ownedCryptoId,
                messageIdentifierFromEngine: receivedMessage.messageIdentifierFromEngine,
                attachmentNumber: index)
            .postOnDispatchQueue()
        }
        
    }
    
}