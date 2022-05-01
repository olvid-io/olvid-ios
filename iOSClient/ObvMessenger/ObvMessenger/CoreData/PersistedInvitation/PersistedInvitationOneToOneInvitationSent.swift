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
import OlvidUtils


@objc(PersistedInvitationOneToOneInvitationSent)
final class PersistedInvitationOneToOneInvitationSent: PersistedInvitation {
    
    private static let entityName = "PersistedInvitationOneToOneInvitationSent"
    private static let errorDomain = "PersistedInvitationOneToOneInvitationSent"

    private static func makeError(message: String) -> Error { NSError(domain: errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: - Attributes

    @NSManaged private var rawContactIdentity: Data
    
    // MARK: - Computed variables
    
    var contactIdentity: ObvCryptoId? {
        get {
            try? ObvCryptoId(identity: rawContactIdentity)
        }
        set {
            guard let newValue = newValue else { assertionFailure(); return }
            self.rawContactIdentity = newValue.getIdentity()
        }
    }
}


// MARK: - Initializer

extension PersistedInvitationOneToOneInvitationSent {
    
    convenience init(obvDialog: ObvDialog, within context: NSManagedObjectContext) throws {
        let contactIdentity: ObvCryptoId
        switch obvDialog.category {
        case .oneToOneInvitationSent(contactIdentity: let identity):
            contactIdentity = identity.cryptoId
        default:
            throw Self.makeError(message: "Unexpected category")
        }
        if let existingInvitation = try PersistedInvitation.get(uuid: obvDialog.uuid, within: context) {
            try existingInvitation.delete()
        }
        try self.init(obvDialog: obvDialog, forEntityName: PersistedInvitationOneToOneInvitationSent.entityName, within: context)
        self.contactIdentity = contactIdentity
    }
    
}


// MARK: - Getters

extension PersistedInvitationOneToOneInvitationSent {
    
    struct SubentityPredicate {
        enum Key: String {
            case rawContactIdentity = "rawContactIdentity"
        }
        static func toContactIdentity(_ contact: ObvCryptoId) -> NSPredicate {
            NSPredicate(Key.rawContactIdentity, EqualToData: contact.getIdentity())
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedInvitationOneToOneInvitationSent> {
        return NSFetchRequest<PersistedInvitationOneToOneInvitationSent>(entityName: PersistedInvitationOneToOneInvitationSent.entityName)
    }

    
    static func get(fromOwnedIdentity ownedIdentity: ObvCryptoId, toContact contactIdentity: ObvCryptoId, within context: NSManagedObjectContext) throws -> PersistedInvitationOneToOneInvitationSent? {
        let request = getFetchRequest(fromOwnedIdentity: ownedIdentity, toContact: contactIdentity)
        return try context.fetch(request).first
    }
    
    
    static func getFetchRequest(fromOwnedIdentity ownedIdentity: ObvCryptoId, toContact contactIdentity: ObvCryptoId) -> NSFetchRequest<PersistedInvitationOneToOneInvitationSent> {
        let request: NSFetchRequest<PersistedInvitationOneToOneInvitationSent> = PersistedInvitationOneToOneInvitationSent.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withOwnedIdentity(ownedIdentity),
            SubentityPredicate.toContactIdentity(contactIdentity),
        ])
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.date.rawValue, ascending: true)]
        request.fetchLimit = 1
        return request
    }
    
    
    static func getFetchRequestWithNoResult() -> NSFetchRequest<PersistedInvitationOneToOneInvitationSent> {
        let request: NSFetchRequest<PersistedInvitationOneToOneInvitationSent> = PersistedInvitationOneToOneInvitationSent.fetchRequest()
        request.predicate = NSPredicate(value: false)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.date.rawValue, ascending: true)]
        request.fetchLimit = 1
        return request
    }
    
}
