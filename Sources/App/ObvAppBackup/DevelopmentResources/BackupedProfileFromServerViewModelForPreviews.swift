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

import Foundation
import ObvCrypto
import ObvTypes


@MainActor
final class BackupedProfileFromServerViewModelForPreviews: BackupedProfileFromServerViewModelProtocol {
        
    let firstNameThenLastName: String
    let customDisplayName: String?
    let positionAtCompany: String
    @Published var avatar: AvatarModelForPreviews
    let isOnThisDevice: Bool
    let canNavigateToListOfThisProfileBackups: Bool
    let profileBackupSeed: ObvCrypto.BackupSeed
    let ownedCryptoId: ObvCryptoId
    let encodedPhotoServerKeyAndLabel: Data?

    init(index: Int, isOnThisDevice: Bool, canNavigateToListOfThisProfileBackups: Bool, profileBackupSeed: ObvCrypto.BackupSeed) {
        let coreDetails = PreviewsHelper.coreDetails[index]
        self.firstNameThenLastName = coreDetails.getDisplayNameWithStyle(.firstNameThenLastName)
        self.positionAtCompany = coreDetails.getDisplayNameWithStyle(.positionAtCompany)
        self.avatar = AvatarModelForPreviews(index: index, size: .normal)
        self.isOnThisDevice = isOnThisDevice
        self.canNavigateToListOfThisProfileBackups = canNavigateToListOfThisProfileBackups
        self.profileBackupSeed = profileBackupSeed
        self.ownedCryptoId = PreviewsHelper.cryptoIds[index]
        self.encodedPhotoServerKeyAndLabel = nil
        self.customDisplayName = "MyNickname"
    }

}
