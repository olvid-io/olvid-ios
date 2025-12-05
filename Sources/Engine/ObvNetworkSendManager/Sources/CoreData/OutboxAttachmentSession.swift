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
import ObvTypes
import ObvMetaManager
import OlvidUtils


@objc(OutboxAttachmentSession)
final class OutboxAttachmentSession: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "OutboxAttachmentSession"

    // MARK: Attributes
    
    @NSManaged private var rawAppType: Int
    @NSManaged private var rawIdentifier: UUID
    @NSManaged private(set) var timestamp: Date

    // MARK: Relationships

    // We do not expect `attachment` to be nil since it is cascade deleted
    @NSManaged private(set) var attachment: OutboxAttachment?

    // MARK: Variables
    
    fileprivate static let backgroundURLSessionIdentifierPrefix = "UploadAttachmentSession"

    private(set) var appType: AppType? {
        get { return AppType(rawValue: rawAppType) }
        set { self.rawAppType = newValue!.rawValue }
    }

    var sessionIdentifier: String { [OutboxAttachmentSession.backgroundURLSessionIdentifierPrefix, rawIdentifier.uuidString].joined(separator: "_") }

    // Initializer
    
    convenience init?(attachment: OutboxAttachment, appType: AppType) {
        guard let context = attachment.managedObjectContext else { return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: OutboxAttachmentSession.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.appType = appType
        self.rawIdentifier = UUID()
        self.timestamp = Date()
        self.attachment = attachment
    }
}


extension OutboxAttachmentSession {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case rawAppType = "rawAppType"
            case rawIdentifier = "rawIdentifier"
            case timestamp = "timestamp"
            // Relationships
            case attachment = "attachment"
        }
        static var withoutAttachment: NSPredicate {
            NSPredicate(withNilValueForKey: Key.attachment)
        }
        static func withAppType(_ appType: AppType) -> NSPredicate {
            NSPredicate(Key.rawAppType, EqualToInt: appType.rawValue)
        }
        static func withRawIdentifier(_ rawIdentifier: UUID) -> NSPredicate {
            NSPredicate(Key.rawIdentifier, EqualToUuid: rawIdentifier)
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<OutboxAttachmentSession> {
        return NSFetchRequest<OutboxAttachmentSession>(entityName: OutboxAttachmentSession.entityName)
    }

    
    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: OutboxAttachmentSession.entityName)
        fetchRequest.predicate = Predicate.withoutAttachment
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        request.resultType = .resultTypeObjectIDs
        let result = try context.execute(request) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
        } else {
            assertionFailure()
        }
    }
    
    
    static func getSessionIdentifiersOfAllOrphanedOutboxAttachmentSession(within context: NSManagedObjectContext) throws -> Set<String> {
        let request: NSFetchRequest<OutboxAttachmentSession> = OutboxAttachmentSession.fetchRequest()
        request.predicate = Predicate.withoutAttachment
        request.propertiesToFetch = [Predicate.Key.rawIdentifier.rawValue]
        let items = try context.fetch(request)
        return Set(items.map({ $0.sessionIdentifier }))
    }
    
    
    static func getAll(within context: NSManagedObjectContext) throws -> [OutboxAttachmentSession] {
        let request: NSFetchRequest<OutboxAttachmentSession> = OutboxAttachmentSession.fetchRequest()
        return try context.fetch(request)
    }
    
    
    static func getAllCreatedByAppType(_ appType: AppType, within context: NSManagedObjectContext) throws -> [OutboxAttachmentSession] {
        let request: NSFetchRequest<OutboxAttachmentSession> = OutboxAttachmentSession.fetchRequest()
        request.predicate = Predicate.withAppType(appType)
        return try context.fetch(request)
    }

    static func getWithSessionIdentifier(_ sessionIdentifier: String, within context: NSManagedObjectContext) throws -> OutboxAttachmentSession? {
        guard let rawIdentifier = parseSessionIdentifier(sessionIdentifier) else { return nil }
        let request: NSFetchRequest<OutboxAttachmentSession> = OutboxAttachmentSession.fetchRequest()
        request.predicate = Predicate.withRawIdentifier(rawIdentifier)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}


// MARK: - Helpers

extension OutboxAttachmentSession {
    
    private static func parseSessionIdentifier(_ sessionIdentifier: String) -> UUID? {
        guard sessionIdentifier.starts(with: backgroundURLSessionIdentifierPrefix) else { return nil }
        let sessionElements = sessionIdentifier.split(separator: "_")
        guard sessionElements.count == 2 else { return nil }
        return UUID(uuidString: String(sessionElements[1]))
    }
    
}

extension String {
    
    func isBackgroundURLSessionIdentifierForUploadingAttachment() -> Bool {
        return self.starts(with: OutboxAttachmentSession.backgroundURLSessionIdentifierPrefix)
    }

}
