/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

protocol WaitingForBackupRestoreViewControllerDelegate: AnyObject {
    /// Returns the CryptoId of the restore owned identity. When many identities were restored, only one is returned here
    func restoreBackupNow(controller: WaitingForBackupRestoreViewController, backupRequestIdentifier: UUID) async throws -> ObvCryptoId
    func userWantsToEnableAutomaticBackup(controller: WaitingForBackupRestoreViewController) async throws
    func backupRestorationSucceeded(controller: WaitingForBackupRestoreViewController, restoredOwnedCryptoId: ObvCryptoId) async
    func backupRestorationFailed(controller: WaitingForBackupRestoreViewController) async
}


final class WaitingForBackupRestoreViewController: UIHostingController<WaitingForBackupRestoreView>, WaitingForBackupRestoreViewActionsProtocol {
    
    weak var delegate: WaitingForBackupRestoreViewControllerDelegate?
    
    init(model: WaitingForBackupRestoreView.Model, delegate: WaitingForBackupRestoreViewControllerDelegate) {
        let actions = WaitingForBackupRestoreViewActions()
        let view = WaitingForBackupRestoreView(actions: actions, model: model)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation(animated: false)
    }
    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureNavigation(animated: animated)
    }

    
    private func configureNavigation(animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    
    // WaitingForBackupRestoreViewActionsProtocol
    
    func restoreBackupNow(backupRequestIdentifier: UUID) async throws -> ObvCryptoId {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet }
        return try await delegate.restoreBackupNow(controller: self, backupRequestIdentifier: backupRequestIdentifier)
    }
    
    func userWantsToEnableAutomaticBackup() async throws {
        try await delegate?.userWantsToEnableAutomaticBackup(controller: self)
    }
    
    func backupRestorationSucceeded(restoredOwnedCryptoId: ObvCryptoId) async {
        await delegate?.backupRestorationSucceeded(controller: self, restoredOwnedCryptoId: restoredOwnedCryptoId)
    }
    
    func backupRestorationFailed() async {
        await delegate?.backupRestorationFailed(controller: self)
    }

    
    // Errors
    
    enum ObvError: Error {
        case theDelegateIsNotSet
    }

}


private final class WaitingForBackupRestoreViewActions: WaitingForBackupRestoreViewActionsProtocol {
        
    weak var delegate: WaitingForBackupRestoreViewActionsProtocol?
    
    func restoreBackupNow(backupRequestIdentifier: UUID) async throws -> ObvCryptoId {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet }
        return try await delegate.restoreBackupNow(backupRequestIdentifier: backupRequestIdentifier)
    }
    
    func userWantsToEnableAutomaticBackup() async throws {
        try await delegate?.userWantsToEnableAutomaticBackup()
    }
    
    func backupRestorationSucceeded(restoredOwnedCryptoId: ObvCryptoId) async {
        await delegate?.backupRestorationSucceeded(restoredOwnedCryptoId: restoredOwnedCryptoId)
    }

    func backupRestorationFailed() async {
        await delegate?.backupRestorationFailed()
    }

    enum ObvError: Error {
        case theDelegateIsNotSet
    }
    
}
