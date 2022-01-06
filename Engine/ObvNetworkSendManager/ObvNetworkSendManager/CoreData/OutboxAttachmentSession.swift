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
import ObvTypes
import ObvMetaManager
import OlvidUtils


@objc(OutboxAttachmentSession)
final class OutboxAttachmentSession: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "OutboxAttachmentSession"
    private static let attachmentKey = "attachment"
    private static let rawIdentifierKey = "rawIdentifier"
    private static let rawAppTypeKey = "rawAppType"

    // MARK: Attributes
    
    @NSManaged private var rawAppType: Int
    @NSManaged private var rawIdentifier: UUID
    @NSManaged private(set) var timestamp: Date

    // MARK: Relationships

    // We do not expect `attachment` to be nil since it is cascade deleted
    @NSManaged private(set) var attachment: OutboxAttachment?

    // MARK: Variables
    
    fileprivate static let backgroundURLSessionIdentifierPrefix = "UploadAttachmentSession"

    var obvContext: ObvContext?

    private(set) var appType: AppType? {
        get { return AppType(rawValue: rawAppType) }
        set { self.rawAppType = newValue!.rawValue }
    }

    var sessionIdentifier: String { [OutboxAttachmentSession.backgroundURLSessionIdentifierPrefix, rawIdentifier.uuidString].joined(separator: "_") }

    // Initializer
    
    convenience init?(attachment: OutboxAttachment, appType: AppType) {
        guard let obvContext = attachment.obvContext else { return nil }
        let entityDescription = NSEntityDescription.entity(forEntityName: OutboxAttachmentSession.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.appType = appType
        self.rawIdentifier = UUID()
        self.timestamp = Date()
        self.attachment = attachment
    }
}


extension OutboxAttachmentSession {
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<OutboxAttachmentSession> {
        return NSFetchRequest<OutboxAttachmentSession>(entityName: OutboxAttachmentSession.entityName)
    }

    
    static func deleteAllOrphaned(within obvContext: ObvContext) throws {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: OutboxAttachmentSession.entityName)
        fetchRequest.predicate = NSPredicate(format: "%K == NIL", attachmentKey)
        let request = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        _ = try obvContext.execute(request)
    }
    
    
    static func getSessionIdentifiersOfAllOrphanedOutboxAttachmentSession(within obvContext: ObvContext) throws -> Set<String> {
        let request: NSFetchRequest<OutboxAttachmentSession> = OutboxAttachmentSession.fetchRequest()
        request.predicate = NSPredicate(format: "%K == NIL", attachmentKey)
        request.propertiesToFetch = [rawIdentifierKey]
        let items = try obvContext.fetch(request)
        return Set(items.map({ $0.sessionIdentifier }))
    }
    
    
    static func getAll(within obvContext: ObvContext) throws -> [OutboxAttachmentSession] {
        let request: NSFetchRequest<OutboxAttachmentSession> = OutboxAttachmentSession.fetchRequest()
        return try obvContext.fetch(request)
    }
    
    
    static func getAllCreatedByAppType(_ appType: AppType, within obvContext: ObvContext) throws -> [OutboxAttachmentSession] {
        let request: NSFetchRequest<OutboxAttachmentSession> = OutboxAttachmentSession.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %d", rawAppTypeKey, appType.rawValue)
        return try obvContext.fetch(request)
    }

    static func getWithSessionIdentifier(_ sessionIdentifier: String, within obvContext: ObvContext) throws -> OutboxAttachmentSession? {
        guard let rawIdentifier = parseSessionIdentifier(sessionIdentifier) else { return nil }
        let request: NSFetchRequest<OutboxAttachmentSession> = OutboxAttachmentSession.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", rawIdentifierKey, rawIdentifier as NSUUID)
        request.fetchLimit = 1
        return try obvContext.fetch(request).first
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
