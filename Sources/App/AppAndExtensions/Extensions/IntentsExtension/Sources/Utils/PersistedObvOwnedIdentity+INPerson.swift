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

extension PersistedObvOwnedIdentity {
    
    static func getOwnedIdentityAsINPerson(ownedCryptoId: ObvCryptoId) async throws -> INPerson? {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<INPerson?, any Error>, context: NSManagedObjectContext) in
            // Siri-sourced identifiers may point at a profile the user has since hidden;
            // refuse to surface a hidden profile to any intent flow.
            guard let ownedIdentity = try Self.get(cryptoId: ownedCryptoId, within: context), !ownedIdentity.isHidden else {
                return continuation.resume(returning: nil)
            }
            let ownedINPerson = try ownedIdentity.toINPerson(withImage: true)
            return continuation.resume(returning: ownedINPerson)
        }
    }
    
    
    // Bulk-search helper below uses `withImage: false`: under CarPlay's tight extension budget, eagerly
    // materialising avatars across a disambiguation list multiplies CPU (decode) and peak memory by the
    // result count. Single-key `getOwnedIdentityAsINPerson(ownedCryptoId:)` above keeps `withImage: true`.
    static func getAllNonHiddenOwnedIdentitiesAsINPerson() async throws -> [INPerson] {
        return try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<[INPerson], any Error>, context: NSManagedObjectContext) in
            let ownedIdentities = try Self.getAllNonHiddenOwnedIdentities(within: context)
            let ownedINPersons = ownedIdentities.compactMap { try? $0.toINPerson(withImage: false) }
            return continuation.resume(returning: ownedINPersons)
        }
    }
    
}
