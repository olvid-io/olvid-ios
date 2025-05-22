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


@MainActor
protocol OnboardingBackupRestoreStartingPointHostingViewDelegate: AnyObject {
    func userWantsToRestoreBackupAutomaticallyFromICloudKeychain(_ vc: OnboardingBackupRestoreStartingPointHostingView)
    func userWantsToRestoreBackupManually(_ vc: OnboardingBackupRestoreStartingPointHostingView)
}


final class OnboardingBackupRestoreStartingPointHostingView: UIHostingController<OnboardingBackupRestoreStartingPointView> {
    
    private let viewsActions = ViewsActions()
    private weak var internalDelegate: OnboardingBackupRestoreStartingPointHostingViewDelegate?
    
    
    init(delegate: OnboardingBackupRestoreStartingPointHostingViewDelegate) {
        let rootView = OnboardingBackupRestoreStartingPointView(actions: viewsActions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        self.viewsActions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


// MARK: - Implementing OnboardingBackupRestoreStartingPointViewActionsProtocol

extension OnboardingBackupRestoreStartingPointHostingView: OnboardingBackupRestoreStartingPointViewActionsProtocol {
    
    func userWantsToRestoreBackupAutomaticallyFromICloudKeychain() {
        internalDelegate?.userWantsToRestoreBackupAutomaticallyFromICloudKeychain(self)
    }
    
    func userWantsToRestoreBackupManually() {
        internalDelegate?.userWantsToRestoreBackupManually(self)
    }

}


// MARK: - View's actions

@MainActor
private final class ViewsActions: OnboardingBackupRestoreStartingPointViewActionsProtocol {
    
    weak var delegate: (any OnboardingBackupRestoreStartingPointViewActionsProtocol)?
    
    func userWantsToRestoreBackupAutomaticallyFromICloudKeychain() {
        delegate?.userWantsToRestoreBackupAutomaticallyFromICloudKeychain()
    }
    
    func userWantsToRestoreBackupManually() {
        delegate?.userWantsToRestoreBackupManually()
    }

}
