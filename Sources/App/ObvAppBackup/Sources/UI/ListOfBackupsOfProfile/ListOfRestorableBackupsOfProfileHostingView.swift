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


protocol ListOfBackupsOfProfileHostingViewDelegate: AnyObject {
    @MainActor func userWantsToRestoreProfileBackup(_ vc: ListOfBackupsOfProfileHostingView, profileBackupFromServer: ObvProfileBackupFromServer) async throws
}


final class ListOfBackupsOfProfileHostingView: UIHostingController<ListOfBackupsOfProfileView<ObvListOfProfileBackups>> {
    
    private let actions = ActionsForView()
    private weak var internalDelegate: ListOfBackupsOfProfileHostingViewDelegate?
    
    init(listOfProfileBackups: ObvListOfProfileBackups, profileName: String, context: ContextOfListOfBackupsOfProfile, delegate: ListOfBackupsOfProfileHostingViewDelegate) {
        let rootView = ListOfBackupsOfProfileView.init(model: listOfProfileBackups, context: context, actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        actions.delegate = self
        self.title = profileName
    }
    
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}


// MARK: - Implementing ListOfBackupsOfProfileViewActionsProtocol

extension ListOfBackupsOfProfileHostingView: ListOfBackupsOfProfileViewActionsProtocol {
    
    func userWantsToRestoreProfileBackup(profileBackupFromServer: ObvProfileBackupFromServer) async throws {
        assert(internalDelegate != nil)
        try await internalDelegate?.userWantsToRestoreProfileBackup(self, profileBackupFromServer: profileBackupFromServer)
    }
    
}



private final class ActionsForView: ListOfBackupsOfProfileViewActionsProtocol {
    
    weak var delegate: ListOfBackupsOfProfileViewActionsProtocol?
    
    func userWantsToRestoreProfileBackup(profileBackupFromServer: ObvProfileBackupFromServer) async throws {
        assert(delegate != nil)
        try await delegate?.userWantsToRestoreProfileBackup(profileBackupFromServer: profileBackupFromServer)
    }
    
}
