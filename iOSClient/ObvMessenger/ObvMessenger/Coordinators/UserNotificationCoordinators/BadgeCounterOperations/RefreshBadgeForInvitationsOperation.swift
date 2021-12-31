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

final class RefreshBadgeForInvitationsOperation: BadgeCounterOperation {
    
    override func main() {
        guard !isCancelled else { return }
        ObvStack.shared.performBackgroundTaskAndWait { [weak self] (context) in
            guard let _self = self else { return }
            guard let persistedObvOwnedIdentity = try? PersistedObvOwnedIdentity.get(cryptoId: _self.ownedCryptoId, within: context) else { _self.cancel();  return }
            guard let newCount = try? PersistedInvitation.countInvitationsRequiringActionOrWithNotOldStatus(for: persistedObvOwnedIdentity) else { _self.cancel(); return }
            guard !_self.isCancelled else { return }
            _self.setCurrentCountForInvitationsBadge(to: newCount)
        }
    }
    
}
