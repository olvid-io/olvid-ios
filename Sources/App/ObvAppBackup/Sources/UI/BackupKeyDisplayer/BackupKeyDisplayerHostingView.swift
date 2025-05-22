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


public protocol BackupKeyDisplayerHostingHostingViewDelegate: AnyObject {
    @MainActor func userConfirmedWritingDownTheBackupKey(_ vc: BackupKeyDisplayerHostingHostingView, remindToSaveBackupKey: Bool)
}



/// Simple UIKit hosting view of the `BackupKeyDisplayerView` view, which allows the user to confirm they did write down the displayed backup key for the new backups.
public final class BackupKeyDisplayerHostingHostingView: UIHostingController<BackupKeyDisplayerView> {
    
    private let actions = Actions()
    private weak var delegate: BackupKeyDisplayerHostingHostingViewDelegate?
    
    public init(model: BackupKeyDisplayerView.Model, delegate: BackupKeyDisplayerHostingHostingViewDelegate) {
        let rootView = BackupKeyDisplayerView(model: model, actions: actions)
        super.init(rootView: rootView)
        self.delegate = delegate
        self.actions.delegate = self
        self.title = String(localizedInThisBundle: "DISPLAY_YOUR_KEY")
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

// MARK: - Implementing BackupKeyDisplayerViewActionsDelegate

extension BackupKeyDisplayerHostingHostingView: BackupKeyDisplayerViewActionsDelegate {
    
    func userConfirmedWritingDownTheBackupKey(remindToSaveBackupKey: Bool) {
        delegate?.userConfirmedWritingDownTheBackupKey(self, remindToSaveBackupKey: remindToSaveBackupKey)
    }

}


private final class Actions: BackupKeyDisplayerViewActionsDelegate {
    
    weak var delegate: BackupKeyDisplayerViewActionsDelegate?
    
    func userConfirmedWritingDownTheBackupKey(remindToSaveBackupKey: Bool) {
        delegate?.userConfirmedWritingDownTheBackupKey(remindToSaveBackupKey: remindToSaveBackupKey)
    }

}
