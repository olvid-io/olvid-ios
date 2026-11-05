/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

import Intents
import CoreData
import ObvTypes
import ObvUICoreData


/// The call parameters extracted from a resolved `INStartCallIntent`.
struct INStartCallParameters {
    let ownedCryptoId: ObvCryptoId
    let contactCryptoIds: Set<ObvCryptoId>
    let groupId: GroupIdentifier?
}


extension INStartCallIntent {

    /// Extracts call parameters from the intent, performing Core Data lookups as needed.
    ///
    /// Handles two resolution paths:
    ///
    /// 1. **Call-back from history** (single contact, UUID handle): looks up the original call log
    ///    item to recover all participants and the group ID, allowing a group call to be restarted
    ///    from the system Recents list with the same participants.
    ///
    /// 2. **`ObvContactIdentifier` handles** (one or more contacts): parses each contact's handle
    ///    directly. All contacts must belong to the same owned identity; mixed-identity contact
    ///    lists are rejected.
    ///
    /// Returns `nil` if the intent carries no contacts or the handles cannot be resolved.
    func callParameters(within context: NSManagedObjectContext) -> INStartCallParameters? {

        let contacts = self.contacts ?? []
        guard !contacts.isEmpty else { return nil }

        // Path 1: single contact with a UUID handle → call log lookup.
        // This is the call-back-from-Recents case: the donated callRecordToCallBack.identifier
        // is the call's UUID, and recovering the log item restores all original participants.
        if contacts.count == 1,
           let handle = contacts.first?.personHandle?.value ?? contacts.first?.siriMatches?.first?.customIdentifier,
           let callUUID = UUID(handle),
           let item = try? PersistedCallLogItem.get(callUUID: callUUID, within: context),
           let ownedCryptoId = item.ownedCryptoId {
            let contactCryptoIds = item.logContacts.compactMap { try? $0.contactIdentity?.cryptoId }
            return INStartCallParameters(
                ownedCryptoId: ownedCryptoId,
                contactCryptoIds: Set(contactCryptoIds),
                groupId: item.groupIdentifier)
        }

        // Path 2: ObvContactIdentifier handles — single or multiple contacts.
        // Introduced in September 2024; older handle formats are no longer supported.
        var contactCryptoIds = Set<ObvCryptoId>()
        var ownedCryptoId: ObvCryptoId?

        for contact in contacts {
            guard let handle = contact.personHandle?.value ?? contact.siriMatches?.first?.customIdentifier,
                  let identifier = ObvContactIdentifier(handle) else { return nil }
            // All contacts must belong to the same owned identity.
            if let existing = ownedCryptoId, existing != identifier.ownedCryptoId { return nil }
            ownedCryptoId = identifier.ownedCryptoId
            contactCryptoIds.insert(identifier.contactCryptoId)
        }

        guard let ownedCryptoId, !contactCryptoIds.isEmpty else { return nil }
        return INStartCallParameters(
            ownedCryptoId: ownedCryptoId,
            contactCryptoIds: contactCryptoIds,
            groupId: nil)
    }

}
