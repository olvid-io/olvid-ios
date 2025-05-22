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

import UIKit
import SwiftUI
import ObvDesignSystem
import ObvTypes


@MainActor
public final class ObvRestoredOwnedIdentityInfos: ObservableObject {
    
    let ownedCryptoId: ObvCryptoId
    let firstNameThenLastName: String
    let positionAtCompany: String
    @Published var avatar: Avatar
    let isKeycloakManaged: Bool
    
    public init(ownedCryptoId: ObvCryptoId, firstNameThenLastName: String, positionAtCompany: String, displayedLetter: Character, isKeycloakManaged: Bool) {
        self.ownedCryptoId = ownedCryptoId
        let colors = AppTheme.shared.identityColors(for: ownedCryptoId, using: .hue)
        self.firstNameThenLastName = firstNameThenLastName
        self.positionAtCompany = positionAtCompany
        self.isKeycloakManaged = isKeycloakManaged
        self.avatar = .init(displayedLetter: displayedLetter,
                            colors: (colors.text, colors.background),
                            showGreenShield: isKeycloakManaged)
    }
    
    
    final class Avatar: ObvAvatarLegacyViewModel {
        
        let displayedLetter: Character
        @Published private(set) var displayedImage: UIImage?
        let colors: (foreground: UIColor, background: UIColor)
        let size: ObvDesignSystem.ObvAvatarSize = .large
        let showGreenShield: Bool
        
        init(displayedLetter: Character, colors: (foreground: UIColor, background: UIColor), showGreenShield: Bool) {
            self.displayedLetter = displayedLetter
            self.displayedImage = nil
            self.colors = colors
            self.showGreenShield = showGreenShield
        }
        
        func setDisplayedImage(to image: UIImage) {
            withAnimation {
                self.displayedImage = image
            }
        }
        
    }

}
