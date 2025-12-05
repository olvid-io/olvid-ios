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


@objc(InboxAttachmentSession)
final class InboxAttachmentSession: NSManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "InboxAttachmentSession"

    // MARK: Attributes
    
    @NSManaged private var rawIdentifier: UUID // Primary key
    @NSManaged private(set) var timestamp: Date

    // MARK: Relationships

    // We do not expect `attachment` to be nil since it is cascade deleted
    @NSManaged private(set) var attachment: InboxAttachment?

    // MARK: Variables
    
    fileprivate static let backgroundURLSessionIdentifierPrefix = "DownloadAttachmentSession"
    
    var sessionIdentifier: String { [InboxAttachmentSession.backgroundURLSessionIdentifierPrefix, rawIdentifier.uuidString].joined(separator: "_") }

    // Initializer
    
    convenience init?(attachment: InboxAttachment) {
        guard let context = attachment.managedObjectContext else { return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: InboxAttachmentSession.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.rawIdentifier = UUID()
        self.timestamp = Date()
        self.attachment = attachment
    }

    
    func deleteInboxAttachmentSession() throws {
        guard let managedObjectContext else {
            throw ObvError.contextIsNil
        }
        managedObjectContext.delete(self)
    }
    
    
    enum ObvError: Error {
        case contextIsNil
    }
}


extension InboxAttachmentSession {
    
    private struct Predicate {
        
        private enum Key: String {
            // Attributes
            case rawIdentifier = "rawIdentifier"
            case timestamp = "timestamp"
            // Relationships
            case attachment = "attachment"
        }
        
        static func withRawIdentifier(_ rawIdentifier: UUID) -> NSPredicate {
            NSPredicate(Key.rawIdentifier, EqualToUuid: rawIdentifier)
        }
        
        static var withNoAttachment: NSPredicate {
            NSPredicate(withNilValueForKey: Key.attachment)
        }
        
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<InboxAttachmentSession> {
        return NSFetchRequest<InboxAttachmentSession>(entityName: InboxAttachmentSession.entityName)
    }

    
    static func getWithSessionIdentifier(_ sessionIdentifier: String, within context: NSManagedObjectContext) throws -> InboxAttachmentSession? {
        guard let rawIdentifier = parseSessionIdentifier(sessionIdentifier) else { return nil }
        let request: NSFetchRequest<InboxAttachmentSession> = InboxAttachmentSession.fetchRequest()
        request.predicate = Predicate.withRawIdentifier(rawIdentifier)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    

    static func getAll(within context: NSManagedObjectContext) throws -> [InboxAttachmentSession] {
        let request: NSFetchRequest<InboxAttachmentSession> = InboxAttachmentSession.fetchRequest()
        return try context.fetch(request)
    }

    static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: InboxAttachmentSession.entityName)
        fetch.predicate = Predicate.withNoAttachment
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
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

}


// MARK: - Helpers

extension InboxAttachmentSession {
    
    private static func parseSessionIdentifier(_ sessionIdentifier: String) -> UUID? {
        guard sessionIdentifier.starts(with: backgroundURLSessionIdentifierPrefix) else { return nil }
        let sessionElements = sessionIdentifier.split(separator: "_")
        guard sessionElements.count == 2 else { return nil }
        return UUID(uuidString: String(sessionElements[1]))
    }
    
}


// MARK: - String extension

extension String {
    
    func isBackgroundURLSessionIdentifierForDownloadingAttachment() -> Bool {
        return self.starts(with: InboxAttachmentSession.backgroundURLSessionIdentifierPrefix)
    }
    
}
