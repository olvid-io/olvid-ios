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
import OlvidUtils
import ObvTypes
import ObvUICoreData
import CoreData


/// Marks the cards of a contacts suggestions deck as seen when the user opens or closes it, so that they no longer make the badge of the contacts
/// tab red: the suggestions on their contact, the invitations on the invitation.
final class MarkContactSuggestionsAsSeenOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {

    private let ownedCryptoId: ObvCryptoId
    private let contactCryptoIds: Set<ObvCryptoId>
    private let invitationUUIDs: Set<UUID>

    init(ownedCryptoId: ObvCryptoId, contactCryptoIds: Set<ObvCryptoId>, invitationUUIDs: Set<UUID>) {
        self.ownedCryptoId = ownedCryptoId
        self.contactCryptoIds = contactCryptoIds
        self.invitationUUIDs = invitationUUIDs
        super.init()
    }

    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            try PersistedObvContactIdentity.markSuggestionsAsSeen(ownedCryptoId: ownedCryptoId, contactCryptoIds: contactCryptoIds, within: obvContext.context)
            try PersistedInvitation.markSuggestionsAsSeen(ownedCryptoId: ownedCryptoId, invitationUUIDs: invitationUUIDs, within: obvContext.context)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
    }

}
