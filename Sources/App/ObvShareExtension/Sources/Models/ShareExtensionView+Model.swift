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
import ObvOwnedIdentityChooser
import ObvDesignSystem

extension ShareExtensionView {

    public struct Model: Sendable, Equatable {

        /// Whether the selected owned identity has at least one discussion the user could pick as a
        /// recipient. We deliberately keep only this flag (not the full list of discussions): the discussion
        /// chooser streams identifiers on demand and resolves one model per visible cell, so the share
        /// extension model never has to hold every discussion's display model.
        let hasAtLeastOneDiscussionAvailable: Bool

        private(set) var selectedOwnedIdentity: OwnedIdentityChooserViewModel.OwnedIdentity?

        let allOwnedIdentities: [OwnedIdentityChooserViewModel.OwnedIdentity]

        public init(allOwnedIdentities: [OwnedIdentityChooserViewModel.OwnedIdentity],
                    selectedOwnedIdentity: OwnedIdentityChooserViewModel.OwnedIdentity?,
                    hasAtLeastOneDiscussionAvailable: Bool) {
            self.allOwnedIdentities = allOwnedIdentities
            self.selectedOwnedIdentity = selectedOwnedIdentity
            self.hasAtLeastOneDiscussionAvailable = hasAtLeastOneDiscussionAvailable
        }

        // MARK: Sender
        var fromIdentityText: String? { selectedOwnedIdentity?.title }

        var fromIdentityAvatar: ObvAvatarViewModel? { selectedOwnedIdentity?.avatarViewModel }

        var hasMultipleOwnedIdentities: Bool { allOwnedIdentities.count > 1 }
    }

}
