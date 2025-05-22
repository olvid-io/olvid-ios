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


@MainActor
protocol DeviceDeactivationWarningOnBackupRestoreHostingViewDelegate: AnyObject {
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(_ vc: DeviceDeactivationWarningOnBackupRestoreHostingView, ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence
    func userConfirmedSheWantsToRestoreProfileBackupNow(_ vc: DeviceDeactivationWarningOnBackupRestoreHostingView, profileBackupFromServer: ObvTypes.ObvProfileBackupFromServer) async throws
    func userWantsToCancelProfileRestoration(_ vc: DeviceDeactivationWarningOnBackupRestoreHostingView)
}


final class DeviceDeactivationWarningOnBackupRestoreHostingView: UIHostingController<DeviceDeactivationWarningOnBackupRestoreView> {
    
    private let actions = ViewsAction()
    private weak var internalDelegate: DeviceDeactivationWarningOnBackupRestoreHostingViewDelegate?
    
    init(model: DeviceDeactivationWarningOnBackupRestoreViewModel, delegate: DeviceDeactivationWarningOnBackupRestoreHostingViewDelegate) {
        let rootView = DeviceDeactivationWarningOnBackupRestoreView(model: model, actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        self.actions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


// MARK: - Implementing DeviceDeactivationWarningOnBackupRestoreViewActionsProtocol

extension DeviceDeactivationWarningOnBackupRestoreHostingView: DeviceDeactivationWarningOnBackupRestoreViewActionsProtocol {
    
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await internalDelegate.userWantsToKeepAllDevicesActiveThanksToOlvidPlus(self, ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    
    func userConfirmedSheWantsToRestoreProfileBackupNow(profileBackupFromServer: ObvTypes.ObvProfileBackupFromServer) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await internalDelegate.userConfirmedSheWantsToRestoreProfileBackupNow(self, profileBackupFromServer: profileBackupFromServer)
    }
    
    
    func userWantsToCancelProfileRestoration() {
        internalDelegate?.userWantsToCancelProfileRestoration(self)
    }
    
    
    enum ObvError: Error {
        case delegateIsNil
    }

}



// MARK: - ViewsAction

private final class ViewsAction: DeviceDeactivationWarningOnBackupRestoreViewActionsProtocol {
    
    weak var delegate: DeviceDeactivationWarningOnBackupRestoreViewActionsProtocol?
    
    
    func userWantsToKeepAllDevicesActiveThanksToOlvidPlus(ownedCryptoIdentity: ObvOwnedCryptoIdentity) async throws -> ObvDeviceDeactivationConsequence {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToKeepAllDevicesActiveThanksToOlvidPlus(ownedCryptoIdentity: ownedCryptoIdentity)
    }
    
    
    func userConfirmedSheWantsToRestoreProfileBackupNow(profileBackupFromServer: ObvTypes.ObvProfileBackupFromServer) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userConfirmedSheWantsToRestoreProfileBackupNow(profileBackupFromServer: profileBackupFromServer)
    }
    
    
    func userWantsToCancelProfileRestoration() {
        delegate?.userWantsToCancelProfileRestoration()
    }
    
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}
