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
import os.log
import ObvMetaManager
import ObvCrypto
import ObvTypes
import OlvidUtils

@objc(PendingDeleteFromServer)
final class PendingDeleteFromServer: NSManagedObject, ObvManagedObject {
    
    // MARK: Internal constants
    
    private static let entityName = "PendingDeleteFromServer"
    private static let rawMessageIdOwnedIdentityKey = "rawMessageIdOwnedIdentity"
    private static let rawMessageIdUidKey = "rawMessageIdUid"

    // MARK: Attributes
    
    @NSManaged private var rawMessageIdOwnedIdentity: Data
    @NSManaged private var rawMessageIdUid: Data

    // MARK: Other variables
    
    private(set) var messageId: MessageIdentifier {
        get { return MessageIdentifier(rawOwnedCryptoIdentity: self.rawMessageIdOwnedIdentity, rawUid: self.rawMessageIdUid)! }
        set { self.rawMessageIdOwnedIdentity = newValue.ownedCryptoIdentity.getIdentity(); self.rawMessageIdUid = newValue.uid.raw }
    }

    var obvContext: ObvContext?

    // MARK: - Initializer
    
    convenience init(messageId: MessageIdentifier, within obvContext: ObvContext) {
        let entityDescription = NSEntityDescription.entity(forEntityName: PendingDeleteFromServer.entityName, in: obvContext)!
        self.init(entity: entityDescription, insertInto: obvContext)
        self.messageId = messageId
    }

}


// MARK: - Convenience DB getters

extension PendingDeleteFromServer {
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PendingDeleteFromServer> {
        return NSFetchRequest<PendingDeleteFromServer>(entityName: PendingDeleteFromServer.entityName)
    }

    static func get(messageId: MessageIdentifier, within obvContext: ObvContext) throws -> PendingDeleteFromServer? {
        let request: NSFetchRequest<PendingDeleteFromServer> = PendingDeleteFromServer.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %@",
                                        rawMessageIdOwnedIdentityKey, messageId.ownedCryptoIdentity.getIdentity() as NSData,
                                        rawMessageIdUidKey, messageId.uid.raw as NSData)
        request.fetchLimit = 1
        let item = (try obvContext.fetch(request)).first
        return item
    }
    
    static func getAll(within obvContext: ObvContext) throws -> [PendingDeleteFromServer] {
        let request: NSFetchRequest<PendingDeleteFromServer> = PendingDeleteFromServer.fetchRequest()
        let items = try obvContext.fetch(request)
        return items
    }
}
