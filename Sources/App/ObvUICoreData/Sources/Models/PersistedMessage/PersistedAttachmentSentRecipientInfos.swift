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
import OlvidUtils

@objc(PersistedAttachmentSentRecipientInfos)
public final class PersistedAttachmentSentRecipientInfos: NSManagedObject, Identifiable {

    private static let entityName = "PersistedAttachmentSentRecipientInfos"

    public enum ReceptionStatus: Int {
        case uploadable = -3
        case uploading = -2
        case complete = -1
        case delivered = 0
        case read = 1

        static func < (lhs: Self, rhs: Self) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Attributes

    @NSManaged public private(set) var index: Int
    @NSManaged private var rawStatus: Int

    // MARK: - Relationships

    @NSManaged public var messageInfo: PersistedMessageSentRecipientInfos?


    // MARK: - Computed variables

    public private(set) var status: ReceptionStatus {
        get {
            ReceptionStatus(rawValue: rawStatus) ?? .uploadable
        }
        set {
            guard self.status < newValue else { return }
            guard self.rawStatus != newValue.rawValue else { return }
            self.rawStatus = newValue.rawValue
        }
    }

    // MARK: - Initializer

    /// Creates a `PersistedAttachmentSentRecipientInfos` instance in the `.uploadable` status
    convenience init(index: Int, info: PersistedMessageSentRecipientInfos) throws {

        guard let context = info.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }

        let entityDescription = NSEntityDescription.entity(forEntityName: Self.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.messageInfo = info
        self.index = index
        self.rawStatus = ReceptionStatus.uploadable.rawValue // Only place where we must use the raw status
    }

    // MARK: - Status management
    
    public func attachmentWasUploaded() {
        if self.status < .complete {
            self.status = .complete
        }
    }
    
    
    func attachmentWasDelivered(andRead: Bool) {
        if andRead {
            if self.status < .read {
                self.status = .read
            }
        } else {
            if self.status < .delivered {
                self.status = .delivered
            }
        }
    }


    // MARK: - Convenience DB getters

    private struct Predicate {
        enum Key: String {
            case messageInfo = "messageInfo"
        }
        static var withoutAssociatedPersistedMessageSentRecipientInfos: NSPredicate {
            NSPredicate(withNilValueForKey: Key.messageInfo)
        }
        static func withObjectID(_ objectID: TypeSafeManagedObjectID<PersistedAttachmentSentRecipientInfos>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
    }

    
    @nonobjc private static func fetchRequest() -> NSFetchRequest<PersistedAttachmentSentRecipientInfos> {
        return NSFetchRequest<PersistedAttachmentSentRecipientInfos>(entityName: PersistedAttachmentSentRecipientInfos.entityName)
    }

    
    public static func deleteOrphaned(within obvContext: ObvContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = PersistedAttachmentSentRecipientInfos.fetchRequest()
        request.predicate = Predicate.withoutAssociatedPersistedMessageSentRecipientInfos
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        batchDeleteRequest.resultType = .resultTypeObjectIDs
        let result = try obvContext.execute(batchDeleteRequest) as? NSBatchDeleteResult
        // The previous call **immediately** updates the SQLite database
        // We merge the changes back to the current context
        if let objectIDArray = result?.result as? [NSManagedObjectID] {
            let changes = [NSUpdatedObjectsKey : objectIDArray]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [obvContext.context])
        } else {
            assertionFailure()
        }
    }

    
    static func getPersistedMessageSentRecipientInfos(objectID: TypeSafeManagedObjectID<PersistedAttachmentSentRecipientInfos>, within context: NSManagedObjectContext) throws -> PersistedAttachmentSentRecipientInfos? {
        let request: NSFetchRequest<PersistedAttachmentSentRecipientInfos> = PersistedAttachmentSentRecipientInfos.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

}
