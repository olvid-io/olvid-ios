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
import ObvTypes
import ObvCrypto
import ObvDesignSystem


@MainActor
protocol EnteredDeviceBackupSeedResultViewControllerDelegate: AnyObject {
    func userWantsToNavigateToListOfAllProfileBackups(_ vc: EnteredDeviceBackupSeedResultViewController, profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: BackupSeed)
    func fetchAvatarImage(_ vc: EnteredDeviceBackupSeedResultViewController, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage?
}


final class EnteredDeviceBackupSeedResultViewController: UIHostingController<EnteredDeviceBackupSeedResultView<ObvListOfDeviceBackupProfiles>> {
    
    private let actions = ViewsActions()
    private weak var internalDelegate: EnteredDeviceBackupSeedResultViewControllerDelegate?

    init(listModel: ObvListOfDeviceBackupProfiles, canNavigateToListOfProfileBackupsForProfilesOnDevice: Bool, delegate: EnteredDeviceBackupSeedResultViewControllerDelegate) {
        let rootView = EnteredDeviceBackupSeedResultView(
            listModel: listModel,
            actions: actions,
            canNavigateToListOfProfileBackupsForProfilesOnDevice: canNavigateToListOfProfileBackupsForProfilesOnDevice)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        actions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}


// MARK: - Implementing EnteredDeviceBackupSeedResultViewActionsProtocol

extension EnteredDeviceBackupSeedResultViewController: EnteredDeviceBackupSeedResultViewActionsProtocol {
    
    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvTypes.ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToNavigateToListOfAllProfileBackups(self, profileCryptoId: profileCryptoId, profileName: profileName, profileBackupSeed: profileBackupSeed)
    }

    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let internalDelegate else { assertionFailure(); return nil }
        return await internalDelegate.fetchAvatarImage(self, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }

}



@MainActor
private final class ViewsActions: EnteredDeviceBackupSeedResultViewActionsProtocol {
    
    typealias ListModel = ObvListOfDeviceBackupProfiles
    
    weak var delegate: (any EnteredDeviceBackupSeedResultViewActionsProtocol)?

    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: profileCryptoId,
                                                              profileName: profileName,
                                                              profileBackupSeed: profileBackupSeed)
    }
    
    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let delegate else { assertionFailure(); return nil }
        return await delegate.fetchAvatarImage(profileCryptoId: profileCryptoId,
                                               encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel,
                                               frameSize: frameSize)
    }

}
