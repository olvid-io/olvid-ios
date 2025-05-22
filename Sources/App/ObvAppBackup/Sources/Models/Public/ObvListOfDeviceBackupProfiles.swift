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
import ObvCrypto
import ObvTypes
import ObvDesignSystem


/// This model is used when showing a list of profiles contained in a device backup. It is used both by the view showing a list per device, and by the view showing a list across devices.
@MainActor
public final class ObvListOfDeviceBackupProfiles: ListOfBackupedProfilesFromServerViewModelProtocol {
    
    @Published public private(set) var profiles: [Profile]
    
    public init(profiles: [Profile]) {
        self.profiles = profiles
    }
    
    func insertProfileIfNotAlreadyExisting(_ newProfiles: [Profile]) {
        let knownOwnedCryptoIds: Set<ObvCryptoId> = Set(profiles.map(\.ownedCryptoId))
        let profilesToInsert = newProfiles.filter({ !knownOwnedCryptoIds.contains($0.ownedCryptoId) })
        withAnimation {
            profiles.append(contentsOf: profilesToInsert)
        }
    }
    
}


extension ObvListOfDeviceBackupProfiles {
        
    /// Represents a profile in a device backup
    @MainActor
    public final class Profile: BackupedProfileFromServerViewModelProtocol {
                
        public let ownedCryptoId: ObvCryptoId
        public let firstNameThenLastName: String
        public let positionAtCompany: String
        public let customDisplayName: String?
        @Published public private(set) var avatar: Avatar
        public let isOnThisDevice: Bool
        public let profileBackupSeed: ObvCrypto.BackupSeed
        public let encodedPhotoServerKeyAndLabel: Data?

        public init(ownedCryptoId: ObvCryptoId, coreDetails: ObvIdentityCoreDetails, customDisplayName: String?, isOnThisDevice: Bool, profileBackupSeed: ObvCrypto.BackupSeed, showGreenShield: Bool, encodedPhotoServerKeyAndLabel: Data?) {
            self.ownedCryptoId = ownedCryptoId
            self.firstNameThenLastName = coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
            self.positionAtCompany = coreDetails.getDisplayNameWithStyle(.positionAtCompany)
            self.avatar = .init(ownedCryptoId: ownedCryptoId, displayedLetter: self.firstNameThenLastName.first ?? "?", showGreenShield: showGreenShield)
            self.isOnThisDevice = isOnThisDevice
            self.profileBackupSeed = profileBackupSeed
            self.encodedPhotoServerKeyAndLabel = encodedPhotoServerKeyAndLabel
            self.customDisplayName = customDisplayName
        }
        
    }
    
}


extension ObvListOfDeviceBackupProfiles.Profile {
    
    @MainActor
    public final class Avatar: ObvAvatarLegacyViewModel {
                
        public let displayedLetter: Character
        @Published public private(set) var displayedImage: UIImage?
        public let colors: (foreground: UIColor, background: UIColor)
        private let ownedCryptoId: ObvCryptoId
        public let size: ObvDesignSystem.ObvAvatarSize
        public var showGreenShield: Bool

        public func setDisplayedImage(to image: UIImage) {
            withAnimation {
                self.displayedImage = image
            }
        }

        init(ownedCryptoId: ObvCryptoId, displayedLetter: Character, showGreenShield: Bool) {
            let colors = AppTheme.shared.identityColors(for: ownedCryptoId, using: .hue)
            self.colors = (colors.text, colors.background)
            self.displayedLetter = displayedLetter
            self.ownedCryptoId = ownedCryptoId
            self.size = .normal
            self.showGreenShield = showGreenShield
        }

    }
    
}
