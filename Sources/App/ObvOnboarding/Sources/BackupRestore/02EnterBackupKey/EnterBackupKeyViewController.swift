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


protocol EnterBackupKeyViewControllerDelegate: AnyObject {
    func recoverBackupFromEncryptedBackup(controller: EnterBackupKeyViewController, encryptedBackup: Data, backupKey: String) async throws -> (backupRequestIdentifier: UUID, backupDate: Date)
    func userWantsToRestoreBackup(controller: EnterBackupKeyViewController, backupRequestIdentifier: UUID) async throws
}


final class EnterBackupKeyViewController: UIHostingController<EnterBackupKeyView>, EnterBackupKeyViewActionsProtocol {
    
    private weak var delegate: EnterBackupKeyViewControllerDelegate?
    
    init(model: EnterBackupKeyView.Model, delegate: EnterBackupKeyViewControllerDelegate) {
        let actions = EnterBackupKeyViewActions()
        let view = EnterBackupKeyView(model: model, actions: actions)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // EnterBackupKeyViewActionsProtocol
    
    func recoverBackupFromEncryptedBackup(_ encryptedBackup: Data, backupKey: String) async throws -> (backupRequestIdentifier: UUID, backupDate: Date) {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet }
        return try await delegate.recoverBackupFromEncryptedBackup(controller: self, encryptedBackup: encryptedBackup, backupKey: backupKey)
    }
    
    func userWantsToRestoreBackup(backupRequestIdentifier: UUID) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet }
        try await delegate.userWantsToRestoreBackup(controller: self, backupRequestIdentifier: backupRequestIdentifier)
    }
        
    // Error
    
    enum ObvError: Error {
        case theDelegateIsNotSet
    }

}


private final class EnterBackupKeyViewActions: EnterBackupKeyViewActionsProtocol {
    
    weak var delegate: EnterBackupKeyViewActionsProtocol?

    func recoverBackupFromEncryptedBackup(_ encryptedBackup: Data, backupKey: String) async throws -> (backupRequestIdentifier: UUID, backupDate: Date) {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet  }
        return try await delegate.recoverBackupFromEncryptedBackup(encryptedBackup, backupKey: backupKey)
    }
    
    func userWantsToRestoreBackup(backupRequestIdentifier: UUID) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.theDelegateIsNotSet  }
        return try await delegate.userWantsToRestoreBackup(backupRequestIdentifier: backupRequestIdentifier)
    }
    
    enum ObvError: Error {
        case theDelegateIsNotSet
    }
    
}
