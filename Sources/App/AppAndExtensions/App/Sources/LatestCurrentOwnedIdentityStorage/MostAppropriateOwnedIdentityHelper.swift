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
@preconcurrency import CoreData
import ObvTypes
import ObvUICoreData
import ObvSettings
import OlvidUtils


actor MostAppropriateOwnedIdentityHelper: ObvContextualActorIsolated {

    nonisolated let obvContextualExecutor: ObvContextualExecutor

    init(context: NSManagedObjectContext) {
        obvContextualExecutor = ObvContextualExecutor(context: context)
    }

    func mostAppropriateOwnedCryptoIdToShow() async -> ObvCryptoId? {
        guard let latestCurrentOwnedIdentityStored = await LatestCurrentOwnedIdentityStorage.shared.getLatestCurrentOwnedIdentityStored() else {
            return randomExistingNonHiddenOwnedCryptoId()
        }
        guard let hiddenCryptoId = latestCurrentOwnedIdentityStored.hiddenCryptoId else {
            let nonHiddenCryptoId = latestCurrentOwnedIdentityStored.nonHiddenCryptoId
            guard (try? PersistedObvOwnedIdentity.get(cryptoId: nonHiddenCryptoId, within: context)) != nil else {
                return randomExistingNonHiddenOwnedCryptoId()
            }
            return nonHiddenCryptoId
        }
        // The latest current identity was hidden — determine if it is still appropriate to show it.
        guard (try? PersistedObvOwnedIdentity.get(cryptoId: hiddenCryptoId, within: context)) != nil else {
            return randomExistingNonHiddenOwnedCryptoId()
        }
        switch ObvMessengerSettings.Privacy.hiddenProfileClosePolicy {
        case .manualSwitching:
            return hiddenCryptoId
        case .screenLock, .background:
            assertionFailure("The hidden cryptoId should have been cleared by now")
            return latestCurrentOwnedIdentityStored.nonHiddenCryptoId
        }
    }

    private func randomExistingNonHiddenOwnedCryptoId() -> ObvCryptoId? {
        guard let ownedIdentities = try? PersistedObvOwnedIdentity.getAllNonHiddenOwnedIdentities(within: context) else { assertionFailure(); return nil }
        return ownedIdentities.first?.cryptoId
    }

}
