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


protocol ManageBackupsHostingViewDelegate: AnyObject {
    @MainActor func userWantsToSeeListOfBackupedProfilesAcrossDevice(_ yourBackupsHostingView: ManageBackupsHostingView)
    @MainActor func userWantsToSeeListOfBackupedProfilesPerDevice(_ yourBackupsHostingView: ManageBackupsHostingView)
    @MainActor func userWantsToEnterDeviceBackupSeed(_ yourBackupsHostingView: ManageBackupsHostingView)
}


final class ManageBackupsHostingView: UIHostingController<ManageBackupsView> {
    
    private let actions = ViewsActions()
    private weak var yourBackupsHostingViewDelegate: ManageBackupsHostingViewDelegate?

    init(delegate: ManageBackupsHostingViewDelegate) {
        let rootView = ManageBackupsView(actions: actions)
        super.init(rootView: rootView)
        self.yourBackupsHostingViewDelegate = delegate
        self.actions.delegate = self
        self.title = String(localizedInThisBundle: "YOUR_BACKUPS")
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

// MARK: - Implementing ManageBackupsViewActionsProtocol

extension ManageBackupsHostingView: ManageBackupsViewActionsProtocol {
    
    func userWantsToSeeListOfBackupedProfilesPerDevice() {
        yourBackupsHostingViewDelegate?.userWantsToSeeListOfBackupedProfilesPerDevice(self)
    }
    
    func userWantsToSeeListOfBackupedProfilesAcrossDevice() {
        yourBackupsHostingViewDelegate?.userWantsToSeeListOfBackupedProfilesAcrossDevice(self)
    }
    
    func userWantsToEnterDeviceBackupSeed() {
        yourBackupsHostingViewDelegate?.userWantsToEnterDeviceBackupSeed(self)
    }
}


// MARK: - View's actions

private final class ViewsActions: ManageBackupsViewActionsProtocol {

    weak var delegate: ManageBackupsViewActionsProtocol?

    func userWantsToSeeListOfBackupedProfilesPerDevice() {
        delegate?.userWantsToSeeListOfBackupedProfilesPerDevice()
    }
    
    func userWantsToSeeListOfBackupedProfilesAcrossDevice() {
        delegate?.userWantsToSeeListOfBackupedProfilesAcrossDevice()
    }
    
    func userWantsToEnterDeviceBackupSeed() {
        delegate?.userWantsToEnterDeviceBackupSeed()
    }

}
