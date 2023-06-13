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
import ObvTypes
import UIKit
import ObvCrypto
import UI_SystemIcon

// MARK: - CircledInitialsConfiguration
public enum CircledInitialsConfiguration: Hashable {
    /// Possible tint adjustment modes for the avatar view
    ///
    /// - normal: A normal tint mode
    /// - disabled: A disabled tint mode, for example when a contact hasn't been synced
    public enum TintAdjustementMode {
        /// A normal tint mode
        case normal

        /// A disabled tint mode, for example when a contact hasn't been synced
        case disabled
    }

    case contact(initial: String, photoURL: URL?, showGreenShield: Bool, showRedShield: Bool, cryptoId: ObvCryptoId, tintAdjustementMode: TintAdjustementMode)
    case group(photoURL: URL?, groupUid: UID)
    case groupV2(photoURL: URL?, groupIdentifier: Data, showGreenShield: Bool)
    case icon(_ icon: CircledInitialsIcon)

    public var photo: UIImage? {
        let url: URL?
        switch self {
        case .contact(initial: _, photoURL: let photoURL, showGreenShield: _, showRedShield: _, cryptoId: _, tintAdjustementMode: _):
            url = photoURL
        case .group(photoURL: let photoURL, groupUid: _):
            url = photoURL
        case .groupV2(photoURL: let photoURL, groupIdentifier: _, showGreenShield: _):
            url = photoURL
        case .icon:
            url = nil
        }
        guard let url = url else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    
    public var showGreenShield: Bool {
        switch self {
        case .contact(initial: _, photoURL: _, showGreenShield: let showGreenShield, showRedShield: _, cryptoId: _, tintAdjustementMode: _):
            return showGreenShield
        case .groupV2(photoURL: _, groupIdentifier: _, showGreenShield: let showGreenShield):
            return showGreenShield
        case .group, .icon:
            return false
        }
    }
    
    public var showRedShield: Bool {
        switch self {
        case .contact(initial: _, photoURL: _, showGreenShield: _, showRedShield: let showRedShield, cryptoId: _, tintAdjustementMode: _): return showRedShield
        default: return false
        }
    }
    
    public var initials: (text: String, cryptoId: ObvCryptoId)? {
        switch self {
        case .contact(initial: let initial, photoURL: _, showGreenShield: _, showRedShield: _, cryptoId: let cryptoId, tintAdjustementMode: _):
            guard let str = initial.trimmingCharacters(in: .whitespacesAndNewlines).first else { return nil }
            return (String(str), cryptoId)
        default: return nil
        }
    }

}
