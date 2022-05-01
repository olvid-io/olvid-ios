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
import MobileCoreServices
import ObvEngine

@objc(SentFyleMessageJoinWithStatus)
final class SentFyleMessageJoinWithStatus: FyleMessageJoinWithStatus {
    
    enum FyleStatus: Int {
        case uploadable = 0
        case uploading = 1
        case complete = 2
    }

    // MARK: - Properties

    @NSManaged var identifierForNotifications: UUID?
    @NSManaged private(set) var index: Int

    // MARK: - Computed properties
    
    private(set) var status: FyleStatus {
        get {
            return FyleStatus(rawValue: self.rawStatus)!
        }
        set {
            guard newValue.rawValue != self.rawStatus else { return }
            self.rawStatus = newValue.rawValue
        }
    }

    override var message: PersistedMessage? { sentMessage }

    override var fullFileIsAvailable: Bool { true }

    // MARK: - Relationships
    
    @NSManaged private(set) var sentMessage: PersistedMessageSent

    // MARK: - Internal constants
    
    private static let entityName = "SentFyleMessageJoinWithStatus"
    private static let identifierForNotificationsKey = "identifierForNotifications"
    private static let sentMessageKey = "sentMessage"
    private static let indexKey = "index"

}


// MARK: - Getting FyleMetadata

extension SentFyleMessageJoinWithStatus {
    
    func getFyleMetadata() -> FyleMetadata? {

        guard let fyle = self.fyle else { return nil }
        
        let uti: String
        if let _uti = ObvUTIUtils.utiOfFile(withName: self.fileName) {
            uti = _uti
        } else {
            uti = String(kUTTypeData)
        }

        return FyleMetadata(fileName: self.fileName,
                            sha256: fyle.sha256,
                            uti: uti)
        
    }
    
    func markAsComplete() {
        self.status = .complete
        let objectID = self.objectID
        DispatchQueue.main.async {
            FyleMessageJoinWithStatus.progressesForAttachment.removeValue(forKey: objectID)
        }
    }
    
}

// MARK: - Initializer

extension SentFyleMessageJoinWithStatus {
    
    convenience init?(fyleJoin: FyleJoin, persistedMessageSentObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, within context: NSManagedObjectContext) {
        
        guard let fyle = fyleJoin.fyle else { return nil }

        // Pre-compute a few things

        guard let persistedMessageSent = try? PersistedMessageSent.getPersistedMessageSent(objectID: persistedMessageSentObjectID, within: context) else { return nil }

        // Call the superclass initializer

        self.init(totalUnitCount: fyle.getFileSize() ?? 0,
                  fileName: fyleJoin.fileName,
                  uti: fyleJoin.uti,
                  rawStatus: FyleStatus.uploadable.rawValue,
                  fyle: fyle,
                  forEntityName: SentFyleMessageJoinWithStatus.entityName,
                  within: context)
        
        // Set the remaining properties and relationships

        self.identifierForNotifications = nil
        self.index = fyleJoin.index
        self.sentMessage = persistedMessageSent
        
    }
    
}


// MARK: - Convenience DB getters

extension SentFyleMessageJoinWithStatus {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<SentFyleMessageJoinWithStatus> {
        return NSFetchRequest<SentFyleMessageJoinWithStatus>(entityName: SentFyleMessageJoinWithStatus.entityName)
    }

    static func getByIdentifierForNotifications(_ identifierForNotifications: UUID, within context: NSManagedObjectContext) -> SentFyleMessageJoinWithStatus? {
        let request: NSFetchRequest<SentFyleMessageJoinWithStatus> = SentFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", identifierForNotificationsKey, identifierForNotifications as NSUUID)
        request.fetchLimit = 1
        do { return try context.fetch(request).first } catch { return nil }
    }

    static func getSentFyleMessageJoinWithStatus(objectID: NSManagedObjectID, within context: NSManagedObjectContext) -> SentFyleMessageJoinWithStatus? {
        let sentFyleMessageJoinWithStatus: SentFyleMessageJoinWithStatus
        do {
            guard let res = try context.existingObject(with: objectID) as? SentFyleMessageJoinWithStatus else { throw NSError() }
            sentFyleMessageJoinWithStatus = res
        } catch {
            return nil
        }
        return sentFyleMessageJoinWithStatus
    }
    
    
    static func getAllIncomplete(within context: NSManagedObjectContext) throws -> [SentFyleMessageJoinWithStatus] {
        let request: NSFetchRequest<SentFyleMessageJoinWithStatus> = SentFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSPredicate(format: "%K != %d", rawStatusKey, FyleStatus.complete.rawValue)
        return try context.fetch(request)
    }
    
    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = SentFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = NSPredicate(format: "%K == NIL", sentMessageKey)
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }
}


// MARK: - Convenience NSFetchedResultsController creators

extension SentFyleMessageJoinWithStatus {
    
    static func getFetchedResultsControllerForSentMessage(_ sentMessage: PersistedMessageSent) throws -> NSFetchedResultsController<SentFyleMessageJoinWithStatus> {
        guard let context = sentMessage.managedObjectContext else { throw NSError() }
        let fetchRequest: NSFetchRequest<SentFyleMessageJoinWithStatus> = SentFyleMessageJoinWithStatus.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "%K == %@", sentMessageKey, sentMessage)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: indexKey, ascending: true)]
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest,
                                                                  managedObjectContext: context,
                                                                  sectionNameKeyPath: nil,
                                                                  cacheName: nil)
        return fetchedResultsController
    }
    
}
