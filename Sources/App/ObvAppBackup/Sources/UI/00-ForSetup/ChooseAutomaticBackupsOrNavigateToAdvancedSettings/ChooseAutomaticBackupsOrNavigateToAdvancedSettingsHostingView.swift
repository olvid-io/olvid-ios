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


protocol ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingViewDelegate: AnyObject {
    @MainActor func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainThusNewSeedMustBeGenerated(_ vc: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView) async throws -> ObvCrypto.BackupSeed
    @MainActor func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedWasGenerated(_ vc: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView, backupSeed: ObvCrypto.BackupSeed)
    @MainActor func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedFailedToBeGenerated(_ vc: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView)
    @MainActor func userWantsToSeeAdvancedSetupParameters(_ vc: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView) async
}


/// Simple UIKit hosting view of the `ChooseAutomaticBackupsOrNavigateToAdvancedSettingsView` view, which allows the user to confirm she wishes to activate automatic backups to iCloud keychain,
/// or to navigate to the more advanced settings.
final class ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView: UIHostingController<ChooseAutomaticBackupsOrNavigateToAdvancedSettingsView> {
    
    private let actions = Actions()
    private weak var delegate: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingViewDelegate?
    
    init(context: ObvAppBackupSetupContext, delegate: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingViewDelegate) {
        let rootView = ChooseAutomaticBackupsOrNavigateToAdvancedSettingsView(context: context, actions: actions)
        super.init(rootView: rootView)
        self.delegate = delegate
        self.actions.delegate = self
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        self.navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    
}


// MARK: - Implementing ChooseBackupModeViewActionsProtocol

extension ChooseAutomaticBackupsOrNavigateToAdvancedSettingsHostingView: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsViewActionsProtocol {

    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainThusNewSeedMustBeGenerated() async throws -> ObvCrypto.BackupSeed {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainThusNewSeedMustBeGenerated(self)
    }
    

    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedWasGenerated(_ backupSeed: ObvCrypto.BackupSeed) {
        guard let delegate else { assertionFailure(); return }
        delegate.userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedWasGenerated(self, backupSeed: backupSeed)
    }


    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedFailedToBeGenerated() {
        delegate?.userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedFailedToBeGenerated(self)
    }
    
    
    func userWantsToSeeAdvancedSetupParameters() {
        Task { await delegate?.userWantsToSeeAdvancedSetupParameters(self) }
    }

    enum ObvError: Error {
        case delegateIsNil
    }

}


private final class Actions: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsViewActionsProtocol {
        
    weak var delegate: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsViewActionsProtocol?
    
    
    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainThusNewSeedMustBeGenerated() async throws -> ObvCrypto.BackupSeed {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainThusNewSeedMustBeGenerated()
    }
    
    
    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedWasGenerated(_ backupSeed: ObvCrypto.BackupSeed) {
        delegate?.userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedWasGenerated(backupSeed)
    }


    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedFailedToBeGenerated() {
        delegate?.userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedFailedToBeGenerated()
    }

    
    func userWantsToSeeAdvancedSetupParameters() {
        delegate?.userWantsToSeeAdvancedSetupParameters()
    }

    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}
