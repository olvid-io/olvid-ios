/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
final class ReceivedFyleMessageJoinWithStatus: FyleMessageJoinWithStatus {
    
    private static let errorDomain = "ReceivedFyleMessageJoinWithStatus"
    private static func makeError(message: String) -> Error { NSError(domain: ReceivedFyleMessageJoinWithStatus.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { ReceivedFyleMessageJoinWithStatus.makeError(message: message) }

    enum FyleStatus: Int {
        case downloadable = 0
        case downloading = 1
        case complete = 2
        case cancelledByServer = 3
    }
    
    // MARK: - Internal constants
    
    private static let entityName = "ReceivedFyleMessageJoinWithStatus"
    private static let fyleKey = "fyle"
    private static let receivedMessageKey = "receivedMessage"
    private static let numberFromEngineKey = "numberFromEngine"

    // MARK: - Properties
    
    @NSManaged private(set) var downsizedThumbnail: Data?
    @NSManaged private(set) var numberFromEngine: Int

    // MARK: - Computed properties
    
    var status: FyleStatus {
        return FyleStatus(rawValue: self.rawStatus)!
    }
    
    var messageIdentifierFromEngine: Data {
        return receivedMessage.messageIdentifierFromEngine
    }
    
    // MARK: - Relationships
    
    @NSManaged private(set) var receivedMessage: PersistedMessageReceived

}

// MARK: - Initializer

extension ReceivedFyleMessageJoinWithStatus {
    
    // Called when a fyle is already available
    convenience init(metadata: FyleMetadata, obvAttachment: ObvAttachment, within context: NSManagedObjectContext) throws {

        // Pre-compute a few things
        
        let fyle: Fyle
        do {
            let _fyle = try Fyle.get(sha256: metadata.sha256, within: context)
            guard _fyle != nil else { throw ReceivedFyleMessageJoinWithStatus.makeError(message: "Could not get Fyle (1)") }
            fyle = _fyle!
        }

        let rawStatus: Int
        let totalUnitCount: Int64
        if let fileSize = fyle.getFileSize() {
            rawStatus = FyleStatus.complete.rawValue
            totalUnitCount = fileSize
        } else {
            rawStatus = obvAttachment.downloadPaused ? FyleStatus.downloadable.rawValue : FyleStatus.downloading.rawValue
            totalUnitCount = obvAttachment.totalUnitCount
        }
        
        // Call the superclass initializer

        self.init(totalUnitCount: totalUnitCount,
                  fileName: metadata.fileName,
                  uti: metadata.uti,
                  rawStatus: rawStatus,
                  fyle: fyle,
                  forEntityName: ReceivedFyleMessageJoinWithStatus.entityName,
                  within: context)

        // Set the remaining properties and relationships
        
        self.downsizedThumbnail = nil
        self.numberFromEngine = obvAttachment.number
        
        do {
            guard let receivedMessage = try PersistedMessageReceived.get(messageIdentifierFromEngine: obvAttachment.messageIdentifier,
                                                                         from: obvAttachment.fromContactIdentity,
                                                                         within: context) else { throw makeError(message: "Could not find PersistedMessageReceived") }
            self.receivedMessage = receivedMessage
        }

    }
    
}

// MARK: - Other methods

extension ReceivedFyleMessageJoinWithStatus {

    // `true` if this join is not complete, or if the fyle is not completely available on disk
    var requiresDownsizedThumbnail: Bool {
        guard let fyle = self.fyle else { return true }
        return self.status != .complete || fyle.getFileSize() != self.totalUnitCount
    }
    
    func setDownsizedThumbnailIfRequired(data: Data) {
        assert(self.downsizedThumbnail == nil)
        guard requiresDownsizedThumbnail else { return }
        self.downsizedThumbnail = data
    }
    
    func deleteDownsizedThumbnail() {
        self.downsizedThumbnail = nil
    }
    
    func tryToSetStatusTo(_ newStatus: FyleStatus) {
        guard self.status != .complete else { return }
        self.rawStatus = newStatus.rawValue
        switch status {
        case .cancelledByServer, .complete:
            let objectID = self.objectID
            DispatchQueue.main.async {
                FyleMessageJoinWithStatus.progressesForAttachment.removeValue(forKey: objectID)
            }
        case .downloading, .downloadable:
            break
        }
    }

}


// MARK: - Convenience DB getters

extension ReceivedFyleMessageJoinWithStatus {
    
    private struct Predicate {
        static var FyleIsNonNil: NSPredicate {
            NSPredicate(format: "\(ReceivedFyleMessageJoinWithStatus.fyleKey) != NIL")
        }
        static func withSha256(_ sha256: Data) -> NSPredicate {
            let key = [ReceivedFyleMessageJoinWithStatus.fyleKey, Fyle.sha256Key].joined(separator: ".")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                FyleIsNonNil,
                NSPredicate(format: "\(key) == %@", sha256 as NSData)
            ])
        }
        static func forReceivedMessage(_ receivedMessage: PersistedMessageReceived) -> NSPredicate {
            NSPredicate(format: "\(ReceivedFyleMessageJoinWithStatus.receivedMessageKey) == %@", receivedMessage)
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
        request.predicate = NSPredicate(format: "%K == NIL", receivedMessageKey)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }

}


// MARK: - Convenience NSFetchedResultsController creators

extension ReceivedFyleMessageJoinWithStatus {
    
    static func getFetchedResultsControllerForReceivedMessage(_ receivedMessage: PersistedMessageReceived) throws -> NSFetchedResultsController<ReceivedFyleMessageJoinWithStatus> {
        guard let context = receivedMessage.managedObjectContext else { throw makeError(message: "Could not find managed object context") }
        let fetchRequest: NSFetchRequest<ReceivedFyleMessageJoinWithStatus> = ReceivedFyleMessageJoinWithStatus.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", receivedMessageKey, receivedMessage)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: numberFromEngineKey, ascending: true)]
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
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
        }

    }
    
}
