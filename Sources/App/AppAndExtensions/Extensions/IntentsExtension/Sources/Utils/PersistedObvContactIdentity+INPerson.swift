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

import Foundation
import CoreData
import Intents
import ObvCommunicationInteractor
import ObvTypes
import ObvUICoreData


extension PersistedObvContactIdentity {
    
    static func getContactAsINPerson(contactIdentifier: ObvContactIdentifier, whereOneToOneStatusIs oneToOneStatus: PersistedObvContactIdentity.OneToOneStatus) async throws -> INPerson? {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<INPerson?, any Error>, context: NSManagedObjectContext) in
            guard let contact = try Self.get(persisted: contactIdentifier, whereOneToOneStatusIs: oneToOneStatus, within: context) else {
                return continuation.resume(returning: nil)
            }
            // Siri-sourced identifiers may point at a contact whose owned profile has since been hidden.
            guard contact.ownedIdentity?.isHidden == false else {
                return continuation.resume(returning: nil)
            }
            let contactINPerson = try contact.toINPerson(withImage: true)
            return continuation.resume(returning: contactINPerson)
        }
    }
    
    
    // Bulk-search helpers below intentionally use `withImage: false`. Materialising avatars across a
    // disambiguation list multiplies CPU (decode) and peak memory by the result count, which matters
    // under CarPlay's tight extension budget. Single-key getters (`getContactAsINPerson` above) keep
    // `withImage: true` so the chosen contact still presents an avatar in Siri's confirmation card.

    static func getAllReachableContactsOfNonHiddenOwnedIdentitiesAsINPerson(searchText: String) async throws -> [INPerson]  {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INPerson], any Error>, context: NSManagedObjectContext) in
            let contacts = try Self.getAllReachableContactsOfNonHiddenOwnedIdentities(searchText: searchText, within: context)
            let inPersons = contacts.compactMap { try? $0.toINPerson(withImage: false) }
            return continuation.resume(returning: inPersons)
        }
    }


    static func getAllReachableContactsAsINPerson(searchText: String, ownedCryptoId: ObvCryptoId) async throws -> [INPerson] {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INPerson], any Error>, context: NSManagedObjectContext) in
            // Siri-sourced ownedCryptoId may point at a profile the user has since hidden.
            guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context), !ownedIdentity.isHidden else {
                return continuation.resume(returning: [])
            }
            let contacts = try Self.getAllReachableContactsOfOwnedIdentity(ownedCryptoId: ownedCryptoId, searchText: searchText, within: context)
            let inPersons = contacts.compactMap { try? $0.toINPerson(withImage: false) }
            return continuation.resume(returning: inPersons)
        }
    }

}
