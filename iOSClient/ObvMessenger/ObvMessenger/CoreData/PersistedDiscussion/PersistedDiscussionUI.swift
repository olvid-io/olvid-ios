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

import UIKit
import ObvTypes

protocol PersistedDiscussionUI: PersistedDiscussion {
    var title: String { get }
    var identityColors: (background: UIColor, text: UIColor)? { get }
    var photoURL: URL? { get }
    var isLocked: Bool { get }
    var isGroupDiscussion: Bool { get }
    var showGreenShield: Bool { get }
    var showRedShield: Bool { get }
}

extension PersistedOneToOneDiscussion: PersistedDiscussionUI {
    var identityColors: (background: UIColor, text: UIColor)? {
        self.contactIdentity?.cryptoId.colors
    }
    var photoURL: URL? {
        self.contactIdentity?.customPhotoURL ?? self.contactIdentity?.photoURL
    }
    var isLocked: Bool { false }
    var isGroupDiscussion: Bool { false }
    var showGreenShield: Bool {
        contactIdentity?.isCertifiedByOwnKeycloak ?? false
    }
    var showRedShield: Bool {
        guard let contactIdentity = contactIdentity else { return false }
        return !contactIdentity.isActive
    }
}

extension PersistedGroupDiscussion: PersistedDiscussionUI {
    var identityColors: (background: UIColor, text: UIColor)? {
        AppTheme.shared.groupColors(forGroupUid: self.contactGroup?.groupUid ?? UID.zero)
    }
    var photoURL: URL? {
        self.contactGroup?.displayPhotoURL
    }
    var isLocked: Bool { false }
    var isGroupDiscussion: Bool { true }
    var showGreenShield: Bool { false }
    var showRedShield: Bool { false }
}
