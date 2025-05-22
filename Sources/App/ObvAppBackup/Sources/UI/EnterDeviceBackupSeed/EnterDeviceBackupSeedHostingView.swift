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


@MainActor
protocol EnterDeviceBackupSeedHostingViewDelegate: AnyObject {
    func userWantsToUseDeviceBackupSeed(_ vc: EnterDeviceBackupSeedHostingView, deviceBackupSeed: BackupSeed) async throws -> ObvListOfDeviceBackupProfiles
    func userWantsToRestoreLegacyBackup(_ vc: EnterDeviceBackupSeedHostingView, backupSeedManuallyEntered: BackupSeed)
    func userWantsToNavigateToListOfBackupedProfilesAcrossDeviceView(_ vc: EnterDeviceBackupSeedHostingView, listModel: ObvListOfDeviceBackupProfiles)
}


final class EnterDeviceBackupSeedHostingView: UIHostingController<EnterDeviceBackupSeedView<ObvListOfDeviceBackupProfiles>> {
    
    private let actions = ViewsActions()
    private weak var internalDelegate: EnterDeviceBackupSeedHostingViewDelegate?
    
    init(allowLegacyBackupRestoration: Bool, delegate: EnterDeviceBackupSeedHostingViewDelegate) {
        let rootView = EnterDeviceBackupSeedView(allowLegacyBackupRestoration: allowLegacyBackupRestoration, actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        actions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


// MARK: - Implementing EnterDeviceBackupSeedViewActionsProtocol

extension EnterDeviceBackupSeedHostingView: EnterDeviceBackupSeedViewActionsProtocol {
        
    typealias ListModel = ObvListOfDeviceBackupProfiles

    enum ObvError: Error {
        case internalDelegateIsNil
    }

    func userWantsToUseDeviceBackupSeed(_ backupSeed: BackupSeed) async throws -> ListModel {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        return try await internalDelegate.userWantsToUseDeviceBackupSeed(self, deviceBackupSeed: backupSeed)
    }
        
    func userWantsToRestoreLegacyBackup(_ backupSeed: BackupSeed) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToRestoreLegacyBackup(self, backupSeedManuallyEntered: backupSeed)
    }
    
    func userWantsToNavigateToListOfBackupedProfilesAcrossDeviceView(listModel: ObvListOfDeviceBackupProfiles) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToNavigateToListOfBackupedProfilesAcrossDeviceView(self, listModel: listModel)
    }

}



// MARK: - View's actions

@MainActor
private final class ViewsActions: EnterDeviceBackupSeedViewActionsProtocol {
        
    typealias ListModel = ObvListOfDeviceBackupProfiles
    
    weak var delegate: (any EnterDeviceBackupSeedViewActionsProtocol<ListModel>)?
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
    func userWantsToUseDeviceBackupSeed(_ backupSeed: BackupSeed) async throws -> ListModel {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userWantsToUseDeviceBackupSeed(backupSeed)
    }
    
    func userWantsToRestoreLegacyBackup(_ backupSeed: BackupSeed) {
        delegate?.userWantsToRestoreLegacyBackup(backupSeed)
    }

    func userWantsToNavigateToListOfBackupedProfilesAcrossDeviceView(listModel: ObvListOfDeviceBackupProfiles) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToNavigateToListOfBackupedProfilesAcrossDeviceView(listModel: listModel)
    }

}
