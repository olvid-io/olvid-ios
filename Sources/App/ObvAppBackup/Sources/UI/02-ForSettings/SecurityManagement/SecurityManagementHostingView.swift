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


protocol SecurityManagementHostingViewDelegate: AnyObject {
    @MainActor func userWantsToNavigateToBackupKeyDisplayerView(_ vc: SecurityManagementHostingView)
    @MainActor func userWantsToNavigateToStolenOrCompromisedKeyView(_ vc: SecurityManagementHostingView)
    @MainActor func userWantsToResetThisDeviceSeedAndBackups(_ vc: SecurityManagementHostingView) async throws
}


final class SecurityManagementHostingView: UIHostingController<SecurityManagementView> {
    
    private let actions = ViewsActions()
    private weak var internalDelegate: SecurityManagementHostingViewDelegate?
    
    init(delegate: SecurityManagementHostingViewDelegate) {
        let rootView = SecurityManagementView(actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        actions.delegate = self
        self.title = String(localizedInThisBundle: "SECURITY")
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


// MARK: - Implementing SecurityManagementViewActionsDelegate

extension SecurityManagementHostingView: SecurityManagementViewActionsDelegate {
    
    func userWantsToNavigateToBackupKeyDisplayerView() {
        internalDelegate?.userWantsToNavigateToBackupKeyDisplayerView(self)
    }
    
    func userWantsToNavigateToStolenOrCompromisedKeyView() {
        internalDelegate?.userWantsToNavigateToStolenOrCompromisedKeyView(self)
    }
    
    func userWantsToResetThisDeviceSeedAndBackups() async throws {
        try await internalDelegate?.userWantsToResetThisDeviceSeedAndBackups(self)
    }
    
}


// MARK: - Errors

extension SecurityManagementHostingView {
    
    enum ObvError: Error {
        case delegateIsNil
    }

}


// MARK: - View's actions

private final class ViewsActions: SecurityManagementViewActionsDelegate {
    
    weak var delegate: SecurityManagementViewActionsDelegate?
    
    func userWantsToNavigateToBackupKeyDisplayerView() {
        delegate?.userWantsToNavigateToBackupKeyDisplayerView()
    }
    
    func userWantsToNavigateToStolenOrCompromisedKeyView() {
        delegate?.userWantsToNavigateToStolenOrCompromisedKeyView()
    }
    
    func userWantsToResetThisDeviceSeedAndBackups() async throws {
        try await delegate?.userWantsToResetThisDeviceSeedAndBackups()
    }
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}
