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

import ObvEngine

@objc(ReceivedFyleMessageJoinWithStatus)
final class ReceivedFyleMessageJoinWithStatus: FyleMessageJoinWithStatus, Identifiable {
    
    enum FyleStatus: Int {
        case downloadable = 0
        case downloading = 1
        case complete = 2
        case cancelledByServer = 3
    }
    
    // MARK: - Internal constants
    
    private static let entityName = "ReceivedFyleMessageJoinWithStatus"
    private static let fyleKey = "fyle"

    // MARK: - Properties
    
    @NSManaged private(set) var downsizedThumbnail: Data?
    @NSManaged private(set) var wasOpened: Bool

    // MARK: - Computed properties
    
    var status: FyleStatus {
        return FyleStatus(rawValue: self.rawStatus)!
    }
    
    var messageIdentifierFromEngine: Data {
        return receivedMessage.messageIdentifierFromEngine
    }
    
    override var message: PersistedMessage? { receivedMessage }

    override var fullFileIsAvailable: Bool { status == .complete }

    var fyleElementOfReceivedJoin: FyleElement? {
        // If the associated received message requires a user interaction to be read, we do *not* return
        // FyleElement as these are typically used to display the join content on screen.
        guard !receivedMessage.readingRequiresUserAction else { return nil }
        return try? FyleElementForFyleMessageJoinWithStatus(self)
    }

    private var changedKeys = Set<String>()

    // MARK: - Relationships
    
    @NSManaged private(set) var receivedMessage: PersistedMessageReceived


    // MARK: - Initializer
    
    // Called when a fyle is already available
    convenience init(metadata: FyleMetadata, obvAttachment: ObvAttachment, within context: NSManagedObjectContext) throws {

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
    
    
    override func wipe() throws {
        try super.wipe()
        tryToSetStatusTo(.complete)
        deleteDownsizedThumbnail()
    }
    
}

// MARK: - Other methods

extension ReceivedFyleMessageJoinWithStatus {

    // `true` if this join is not complete, or if the fyle is not completely available on disk
    var requiresDownsizedThumbnail: Bool {
        guard let fyle = self.fyle else { return true }
        return self.status != .complete || fyle.getFileSize() != self.totalByteCount
    }
    
    
    func setDownsizedThumbnailIfRequired(data: Data) {
        assert(self.downsizedThumbnail == nil)
        guard !isWiped else { assertionFailure(); return }
        guard requiresDownsizedThumbnail else { return }
        self.downsizedThumbnail = data
    }
    
    
    func deleteDownsizedThumbnail() {
        self.downsizedThumbnail = nil
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

    func markAsOpened() {
        guard !self.wasOpened else { return }
        self.wasOpened = true
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
            case wasOpened = "wasOpened"
            case receivedMessage = "receivedMessage"
        }
        static var FyleIsNonNil: NSPredicate {
            NSPredicate(format: "\(ReceivedFyleMessageJoinWithStatus.fyleKey) != NIL")
        }
        static func withSha256(_ sha256: Data) -> NSPredicate {
            let key = [ReceivedFyleMessageJoinWithStatus.fyleKey, Fyle.Predicate.Key.sha256.rawValue].joined(separator: ".")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                FyleIsNonNil,
                NSPredicate(format: "\(key) == %@", sha256 as NSData)
            ])
        }
        static func forReceivedMessage(_ receivedMessage: PersistedMessageReceived) -> NSPredicate {
            NSPredicate(format: "\(Key.receivedMessage.rawValue) == %@", receivedMessage)
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<ReceivedFyleMessageJoinWithStatus> {
        return NSFetchRequest<ReceivedFyleMessageJoinWithStatus>(entityName: ReceivedFyleMessageJoinWithStatus.entityName)
    }
    
    static func getReceivedFyleMessageJoinWithStatus(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> ReceivedFyleMessageJoinWithStatus {
        guard let obj = try context.existingObject(with: objectID) as? ReceivedFyleMessageJoinWithStatus else { throw makeError(message: "The objectID does not exist or is not a ReceivedFyleMessageJoinWithStatus") }
        return obj
    }
    
    static func get(metadata: FyleMetadata, obvAttachment: ObvAttachment, within context: NSManagedObjectContext) throws -> ReceivedFyleMessageJoinWithStatus? {
        guard let receivedMessage = try PersistedMessageReceived.get(messageIdentifierFromEngine: obvAttachment.messageIdentifier,
                                                                     from: obvAttachment.fromContactIdentity,
                                                                     within: context) else { throw makeError(message: "Could not find the associated PersistedMessageReceived") }
        let request: NSFetchRequest<ReceivedFyleMessageJoinWithStatus> = ReceivedFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withSha256(metadata.sha256),
            Predicate.forReceivedMessage(receivedMessage),
        ])
        request.fetchLimit = 1
        let receivedFyleMessageJoinWithStatuses = try context.fetch(request)
        return receivedFyleMessageJoinWithStatuses.first
    }
 
    
    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = ReceivedFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSPredicate(format: "%K == NIL", Predicate.Key.receivedMessage.rawValue)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }

    static func get(objectID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>, within context: NSManagedObjectContext) throws -> ReceivedFyleMessageJoinWithStatus? {
        return try super.get(objectID: objectID.objectID, within: context) as? ReceivedFyleMessageJoinWithStatus
    }


}


// Reacting to changes

extension ReceivedFyleMessageJoinWithStatus {
    
    // MARK: - Deleting Fyle when deleting the last ReceivedFyleMessageJoinWithStatus
    
    override func willSave() {
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
 
    
    override func didSave() {
        super.didSave()
        
        defer {
            self.changedKeys.removeAll()
        }
        
        if changedKeys.contains(Predicate.Key.wasOpened.rawValue), wasOpened {
            ReceivedFyleMessageJoinWithStatusNotifications.receivedFyleJoinHasBeenMarkAsOpened(receivedFyleJoinID: self.typedObjectID)
                .postOnDispatchQueue()
        }
                
        let statusChanged = changedKeys.contains(FyleMessageJoinWithStatus.Predicate.Key.rawStatus.rawValue)
        
        if !isDeleted && (statusChanged || isInserted), status == .complete, let returnReceipt = receivedMessage.returnReceipt, let contactCryptoId = receivedMessage.contactIdentity?.cryptoId, let ownedCryptoId = receivedMessage.contactIdentity?.ownedIdentity?.cryptoId {
            ReceivedFyleMessageJoinWithStatusNotifications.aDeliveredReturnReceiptShouldBeSentForAReceivedFyleMessageJoinWithStatus(
                returnReceipt: returnReceipt,
                contactCryptoId: contactCryptoId,
                ownedCryptoId: ownedCryptoId,
                messageIdentifierFromEngine: receivedMessage.messageIdentifierFromEngine,
                attachmentNumber: index)
            .postOnDispatchQueue()
        }
        
    }
    
}
