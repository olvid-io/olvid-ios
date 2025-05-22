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
import ObvDesignSystem


protocol ProfileRestoredConfirmationHostingViewDelegate: AnyObject {
    @MainActor func restoreProfileBackupFromServerNow(_ vc: ProfileRestoredConfirmationHostingView, profileBackupFromServerToRestore: ObvTypes.ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos
    @MainActor func userWantsToOpenProfile(_ vc: ProfileRestoredConfirmationHostingView, ownedCryptoId: ObvCryptoId)
    @MainActor func userWantsToRestoreAnotherProfile(_ vc: ProfileRestoredConfirmationHostingView)
    @MainActor func fetchAvatarImage(_ vc: ProfileRestoredConfirmationHostingView, profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage?
    @MainActor func navigateToErrorViewAsRestorationFailed(_ vc: ProfileRestoredConfirmationHostingView, error: any Error)
}


final class ProfileRestoredConfirmationHostingView: UIHostingController<ProfileRestoredConfirmationView> {
    
    private let actions = ViewsActions()
    private weak var internalDelegate: ProfileRestoredConfirmationHostingViewDelegate?
    
    init(profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?, delegate: ProfileRestoredConfirmationHostingViewDelegate) {
        let model = ProfileRestoredConfirmationView.Model(profileBackupFromServerToRestore: profileBackupFromServerToRestore, rawAuthState: rawAuthState)
        let rootView = ProfileRestoredConfirmationView(model: model, actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        actions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    enum ObvError: Error {
        case internalDelegateIsNil
    }

}


// MARK: - Implementing ProfileRestoredConfirmationViewActionsProtocol

extension ProfileRestoredConfirmationHostingView: ProfileRestoredConfirmationViewActionsProtocol {
    
    func restoreProfileBackupFromServerNow(profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        return try await internalDelegate.restoreProfileBackupFromServerNow(self, profileBackupFromServerToRestore: profileBackupFromServerToRestore, rawAuthState: rawAuthState)
    }
    
    
    func userWantsToOpenProfile(ownedCryptoId: ObvCryptoId) {
        internalDelegate?.userWantsToOpenProfile(self, ownedCryptoId: ownedCryptoId)
    }
    
    
    func userWantsToRestoreAnotherProfile() {
        internalDelegate?.userWantsToRestoreAnotherProfile(self)
    }
    
    
    func fetchAvatarImage(profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let internalDelegate else { assertionFailure(); return nil }
        return await internalDelegate.fetchAvatarImage(self, profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
    
    func navigateToErrorViewAsRestorationFailed(error: any Error) {
        internalDelegate?.navigateToErrorViewAsRestorationFailed(self, error: error)
    }
    
}



// MARK: - View's actions

private final class ViewsActions: ProfileRestoredConfirmationViewActionsProtocol {
    
    weak var delegate: ProfileRestoredConfirmationViewActionsProtocol?
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
    func restoreProfileBackupFromServerNow(profileBackupFromServerToRestore: ObvProfileBackupFromServer, rawAuthState: Data?) async throws -> ObvRestoredOwnedIdentityInfos {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.restoreProfileBackupFromServerNow(profileBackupFromServerToRestore: profileBackupFromServerToRestore, rawAuthState: rawAuthState)
    }
    
    
    func userWantsToOpenProfile(ownedCryptoId: ObvCryptoId) {
        delegate?.userWantsToOpenProfile(ownedCryptoId: ownedCryptoId)
    }
    
    
    func userWantsToRestoreAnotherProfile() {
        delegate?.userWantsToRestoreAnotherProfile()
    }
    
    
    func fetchAvatarImage(profileCryptoId: ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        guard let delegate else { assertionFailure(); return nil }
        return await delegate.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
    
    func navigateToErrorViewAsRestorationFailed(error: any Error) {
        delegate?.navigateToErrorViewAsRestorationFailed(error: error)
    }
    
}
