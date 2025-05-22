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


protocol ListOfBackupedProfilesAcrossDeviceHostingViewDelegate: AnyObject {
    @MainActor func userWantsToFetchDeviceBakupFromServer(_ vc: ListOfBackupedProfilesAcrossDeviceHostingView) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind>
    @MainActor func userWantsToNavigateToListOfAllProfileBackups(_ vc: ListOfBackupedProfilesAcrossDeviceHostingView, profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed)
    @MainActor func fetchAvatarImage(_ vc: ListOfBackupedProfilesAcrossDeviceHostingView, profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage?
}




final class ListOfBackupedProfilesAcrossDeviceHostingView: UIHostingController<ListOfBackupedProfilesAcrossDeviceView<ListOfBackupedProfilesAcrossDeviceModel>> {
    
    private weak var internalDelegate: ListOfBackupedProfilesAcrossDeviceHostingViewDelegate?
    private let actions = ViewActions()
    
    init(delegate: ListOfBackupedProfilesAcrossDeviceHostingViewDelegate, canNavigateToListOfProfileBackupsForProfilesOnDevice: Bool) {
        let model = ListOfBackupedProfilesAcrossDeviceModel()
        let rootView = ListOfBackupedProfilesAcrossDeviceView(model: model, actions: actions, canNavigateToListOfProfileBackupsForProfilesOnDevice: canNavigateToListOfProfileBackupsForProfilesOnDevice)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        model.delegate = self
        actions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

// MARK: - Implementing ListOfBackupedProfilesAcrossDeviceModelDelegate

extension ListOfBackupedProfilesAcrossDeviceHostingView: ListOfBackupedProfilesAcrossDeviceModelDelegate {
    
    func userWantsToFetchDeviceBakupFromServer(_ model: ListOfBackupedProfilesAcrossDeviceModel) async throws -> AsyncStream<ObvDeviceBackupFromServerWithAppInfoKind> {
        guard let internalDelegate else {
            assertionFailure()
            throw ObvError.delegateIsNil
        }
        return try await internalDelegate.userWantsToFetchDeviceBakupFromServer(self)
    }
        
}


// MARK: - Implementing ListOfBackupedProfilesFromServerViewActionsProtocol

extension ListOfBackupedProfilesAcrossDeviceHostingView: ListOfBackupedProfilesFromServerViewActionsProtocol {
    
    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToNavigateToListOfAllProfileBackups(self, profileCryptoId: profileCryptoId, profileName: profileName, profileBackupSeed: profileBackupSeed)
    }
    
    
    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let internalDelegate else { assertionFailure(); return nil }
        return await internalDelegate.fetchAvatarImage(self, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    

}


// MARK: - Errors

extension ListOfBackupedProfilesAcrossDeviceHostingView {
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


// MARK: - Actions for previews

private final class ViewActions: ListOfBackupedProfilesFromServerViewActionsProtocol {
        
    weak var delegate: ListOfBackupedProfilesFromServerViewActionsProtocol?
    
    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: profileCryptoId, profileName: profileName, profileBackupSeed: profileBackupSeed)
    }
    
    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let delegate else { assertionFailure(); return nil }
        return await delegate.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }

}
