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
import ObvTypes
import ObvMetaManager
import OlvidUtils


@objc(InboxAttachmentSession)
final class InboxAttachmentSession: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "InboxAttachmentSession"
    private static let rawIdentifierKey = "rawIdentifier"
    private static let attachmentKey = "attachment"

    // MARK: Attributes
    
    @NSManaged private var rawIdentifier: UUID
    @NSManaged private(set) var timestamp: Date

    // MARK: Relationships

    // We do not expect `attachment` to be nil since it is cascade deleted
    @NSManaged private(set) var attachment: InboxAttachment?

    // MARK: Variables
    
    fileprivate static let backgroundURLSessionIdentifierPrefix = "DownloadAttachmentSession"
    
    var sessionIdentifier: String { [InboxAttachmentSession.backgroundURLSessionIdentifierPrefix, rawIdentifier.uuidString].joined(separator: "_") }

    var obvContext: ObvContext?
    
    // Initializer
    
    convenience init?(attachment: InboxAttachment) {
        guard let obvContext = attachment.obvContext else { return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: InboxAttachmentSession.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
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
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<InboxAttachmentSession> {
        return NSFetchRequest<InboxAttachmentSession>(entityName: InboxAttachmentSession.entityName)
    }

    static func getWithSessionIdentifier(_ sessionIdentifier: String, within obvContext: ObvContext) throws -> InboxAttachmentSession? {
        guard let rawIdentifier = parseSessionIdentifier(sessionIdentifier) else { return nil }
        let request: NSFetchRequest<InboxAttachmentSession> = InboxAttachmentSession.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", rawIdentifierKey, rawIdentifier as NSUUID)
        request.fetchLimit = 1
        return try obvContext.fetch(request).first
    }

    static func getAll(within obvContext: ObvContext) throws -> [InboxAttachmentSession] {
        let request: NSFetchRequest<InboxAttachmentSession> = InboxAttachmentSession.fetchRequest()
        return try obvContext.fetch(request)
    }

    static func deleteAllOrphaned(within obvContext: ObvContext) throws {
        let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: InboxAttachmentSession.entityName)
        fetch.predicate = NSPredicate(format: "%K == NIL", attachmentKey)
        let request = NSBatchDeleteRequest(fetchRequest: fetch)
        _ = try obvContext.execute(request)
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
