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
import ObvCrypto
import ObvTypes
import ObvDesignSystem


protocol ListOfDeviceBackupsFromServerHostingViewDelegate: AnyObject {
    @MainActor func userWantsToFetchDeviceBakupFromServer(_ vc: ListOfBackupedProfilesPerDeviceHostingView) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind>
    @MainActor func userWantsToShowAllBackupsOfProfile(_ vc: ListOfBackupedProfilesPerDeviceHostingView, profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: BackupSeed)
    @MainActor func fetchAvatarImage(_ vc: ListOfBackupedProfilesPerDeviceHostingView, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage?
}




final class ListOfBackupedProfilesPerDeviceHostingView: UIHostingController<ListOfBackupedProfilesPerDeviceView<ListOfBackupedProfilesPerDeviceModel>> {
    
    private weak var internalDelegate: ListOfDeviceBackupsFromServerHostingViewDelegate?
    private let model: ListOfBackupedProfilesPerDeviceModel
    private let actions = ViewActions()
    
    init(delegate: ListOfDeviceBackupsFromServerHostingViewDelegate, canNavigateToListOfProfileBackupsForProfilesOnDevice: Bool) {
        self.model = ListOfBackupedProfilesPerDeviceModel()
        let rootView = ListOfBackupedProfilesPerDeviceView(model: model, actions: actions, canNavigateToListOfProfileBackupsForProfilesOnDevice: canNavigateToListOfProfileBackupsForProfilesOnDevice)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        self.model.delegate = self
        self.actions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

// MARK: - Implementing ListOfDeviceBackupsFromServerViewModelDelegate

extension ListOfBackupedProfilesPerDeviceHostingView: ListOfBackupedProfilesPerDeviceModelDelegate {
        
    @MainActor func userWantsToFetchDeviceBakupFromServer(_ model: ListOfBackupedProfilesPerDeviceModel) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind> {
        guard let internalDelegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        return try await internalDelegate.userWantsToFetchDeviceBakupFromServer(self)
    }
    
}


// MARK: - Implementing ListOfBackupedProfilesPerDeviceViewActionsProtocol

extension ListOfBackupedProfilesPerDeviceHostingView: ListOfBackupedProfilesPerDeviceViewActionsProtocol {
        
    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToShowAllBackupsOfProfile(self, profileCryptoId: profileCryptoId, profileName: profileName, profileBackupSeed: profileBackupSeed)
    }
    
    
    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let internalDelegate else { assertionFailure(); return nil }
        return await internalDelegate.fetchAvatarImage(self, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }

}


// MARK: - Errors

extension ListOfBackupedProfilesPerDeviceHostingView {
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


// MARK: - ViewActions

final private class ViewActions: ListOfBackupedProfilesPerDeviceViewActionsProtocol {
    
    weak var delegate: ListOfBackupedProfilesPerDeviceViewActionsProtocol?
    
    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: profileCryptoId, profileName: profileName, profileBackupSeed: profileBackupSeed)
    }
    
    
    func fetchAvatarImage(profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let delegate else { assertionFailure(); return nil }
        return await delegate.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
}
