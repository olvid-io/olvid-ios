/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

import SwiftUI


public enum ObvAvatarSize: Sendable {
    case normal
    case large
    case xLarge
    case custom(frameSize: CGSize)
    
    public var frameSize: CGSize {
        switch self {
        case .normal:
            return CGSize(width: 48, height: 48)
        case .large:
            return CGSize(width: 84, height: 84)
        case .xLarge:
            return CGSize(width: 120, height: 120)
        case .custom(frameSize: let frameSize):
            return frameSize
        }
    }
    
    public var frameSizeInPixels: CGSize {
        @MainActor
        get async {
            let scale = UIScreen.main.scale
            return CGSize(width: self.frameSize.width * scale, height: self.frameSize.height * scale)
        }
    }
    
}
