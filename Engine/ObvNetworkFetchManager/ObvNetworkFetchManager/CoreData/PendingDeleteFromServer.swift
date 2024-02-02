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
import os.log
import ObvMetaManager
import ObvCrypto
import ObvTypes
import OlvidUtils

@objc(PendingDeleteFromServer)
final class PendingDeleteFromServer: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "PendingDeleteFromServer"

    // MARK: Attributes
    
    @NSManaged private var rawMessageIdOwnedIdentity: Data? // Expected to be non-nil. Non nil in the model. This is just to make sure we do not crash when accessing this attribute on a deleted instance.
    @NSManaged private var rawMessageIdUid: Data? // Expected to be non-nil. Non nil in the model. This is just to make sure we do not crash when accessing this attribute on a deleted instance.

    // MARK: Other variables
    
    /// This identifier is expected to be non nil, unless this `PendingDeleteFromServer` was deleted on another thread.
    private(set) var messageId: ObvMessageIdentifier? {
        get {
            guard let rawMessageIdOwnedIdentity = self.rawMessageIdOwnedIdentity else { return nil }
            guard let rawMessageIdUid = self.rawMessageIdUid else { return nil }
            return ObvMessageIdentifier(rawOwnedCryptoIdentity: rawMessageIdOwnedIdentity, rawUid: rawMessageIdUid)
        }
        set {
            guard let newValue else { assertionFailure("We should not be setting a nil value"); return }
            self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity()
            self.rawMessageIdUid = newValue.uid.raw
        }
    }

    var obvContext: ObvContext?

    // MARK: - Initializer
    
    convenience init(messageId: ObvMessageIdentifier, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PendingDeleteFromServer.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.messageId = messageId
    }

}


// MARK: - Convenience DB getters

extension PendingDeleteFromServer {
    
    struct Predicate {
        enum Key: String {
            case rawMessageIdOwnedIdentity = "rawMessageIdOwnedIdentity"
            case rawMessageIdUid = "rawMessageIdUid"
        }
        static func withOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity) -> NSPredicate {
            NSPredicate(Key.rawMessageIdOwnedIdentity, EqualToData: ownedCryptoIdentity.getIdentity())
        }
        static func withMessageIdUid(_ messageIdUid: UID) -> NSPredicate {
            NSPredicate(Key.rawMessageIdUid, EqualToData: messageIdUid.raw)
        }
        static func withMessageId(_ messageId: ObvMessageIdentifier) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                withOwnedCryptoIdentity(messageId.ownedCryptoIdentity),
                withMessageIdUid(messageId.uid),
            ])
        }
    }
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PendingDeleteFromServer> {
        return NSFetchRequest<PendingDeleteFromServer>(entityName: PendingDeleteFromServer.entityName)
    }

    static func get(messageId: ObvMessageIdentifier, within obvContext: ObvContext) throws -> PendingDeleteFromServer? {
        let request: NSFetchRequest<PendingDeleteFromServer> = PendingDeleteFromServer.fetchRequest()
        request.predicate = Predicate.withMessageId(messageId)
        request.fetchLimit = 1
        let item = (try obvContext.fetch(request)).first
        return item
    }
    
    static func getAll(within obvContext: ObvContext) throws -> [PendingDeleteFromServer] {
        let request: NSFetchRequest<PendingDeleteFromServer> = PendingDeleteFromServer.fetchRequest()
        let items = try obvContext.fetch(request)
        return items
    }
    
    static func deleteAllPendingDeleteFromServerForOwnedCryptoIdentity(_ ownedCryptoIdentity: ObvCryptoIdentity, within obvContext: ObvContext) throws {
        let request: NSFetchRequest<PendingDeleteFromServer> = PendingDeleteFromServer.fetchRequest()
        request.predicate = Predicate.withOwnedCryptoIdentity(ownedCryptoIdentity)
    }
}
