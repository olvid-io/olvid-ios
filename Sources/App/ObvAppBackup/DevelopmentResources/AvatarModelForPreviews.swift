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
final class AvatarModelForPreviews: ObvAvatarLegacyViewModel {
        
    let displayedLetter: Character
    let colors: (foreground: UIColor, background: UIColor)
    @Published private(set) var displayedImage: UIImage?
    private let imageName: String
    let size: ObvDesignSystem.ObvAvatarSize
    let showGreenShield: Bool

    init(index: Int, size: ObvDesignSystem.ObvAvatarSize, showGreenShield: Bool = false) {
        self.displayedLetter = PreviewsHelper.coreDetails[index].getDisplayNameWithStyle(.firstNameThenLastName).first!
        let colors = AppTheme.shared.identityColors(for: PreviewsHelper.cryptoIds[index], using: .hue)
        self.colors = (colors.text, colors.background)
        self.displayedImage = nil
        self.imageName = "avatar0\(index)"
        self.size = size
        self.showGreenShield = showGreenShield
    }
    
    func setDisplayedImage(to image: UIImage) {
        withAnimation {
            self.displayedImage = image
        }
    }
    
}


@MainActor
final class AvatarActionsForPreviews: BackupedProfileFromServerViewActionsProtocol {
    
    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let index = PreviewsHelper.cryptoIds.firstIndex(where: { $0.getIdentity() == profileCryptoId.getIdentity() }) else { return nil }
        let imageName = "avatar0\(index)"
        let uiImage = UIImage(named: imageName, in: ObvAppBackupResources.bundle, compatibleWith: nil)
        try? await Task.sleep(seconds: 3)
        return uiImage
    }
    
}
