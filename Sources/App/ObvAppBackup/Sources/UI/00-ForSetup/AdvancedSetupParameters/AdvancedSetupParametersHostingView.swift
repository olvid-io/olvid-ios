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


@MainActor
protocol AdvancedSetupParametersHostingViewDelegate: AnyObject {
    func userValidatedAdvancedSetupParameterThusNewSeedMustBeGenerated(_ vc: AdvancedSetupParametersHostingView, saveToKeychain: Bool) async throws -> ObvCrypto.BackupSeed
    func userValidatedAdvancedSetupParameterAndDoNotWantBackups(_ vc: AdvancedSetupParametersHostingView) async throws
    func userValidatedAdvancedSetupParameterAndNewSeedWasGenerated(_ vc: AdvancedSetupParametersHostingView, backupSeed: ObvCrypto.BackupSeed, savedToKeychain: Bool)
    func userValidatedAdvancedSetupParameterButNewSeedFailedToBeGenerate(_ vc: AdvancedSetupParametersHostingView)
    func userValidatedAdvancedSetupParameterButDeactivationFailed(_ vc: AdvancedSetupParametersHostingView)
}


final class AdvancedSetupParametersHostingView: UIHostingController<AdvancedSetupParametersView> {
    
    private let actions = ViewsActions()
    weak private var internalDelegate: AdvancedSetupParametersHostingViewDelegate?
    
    init(delegate: AdvancedSetupParametersHostingViewDelegate) {
        let rootView = AdvancedSetupParametersView(actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        actions.delegate = self
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = String(localizedInThisBundle: "ADVANCED_SETTINGS")
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.navigationController?.setNavigationBarHidden(false, animated: animated)
    }

}


// MARK: - Implementing AdvancedSetupParametersViewActionsProtocol

extension AdvancedSetupParametersHostingView: AdvancedSetupParametersViewActionsProtocol {
    
    func userValidatedAdvancedSetupParameterThusNewSeedMustBeGenerated(saveToKeychain: Bool) async throws -> ObvCrypto.BackupSeed {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await internalDelegate.userValidatedAdvancedSetupParameterThusNewSeedMustBeGenerated(self, saveToKeychain: saveToKeychain)
    }
    
    func userValidatedAdvancedSetupParameterAndDoNotWantBackups() async throws {
        guard let internalDelegate else { assertionFailure(); return }
        try await internalDelegate.userValidatedAdvancedSetupParameterAndDoNotWantBackups(self)
    }

    func userValidatedAdvancedSetupParameterAndNewSeedWasGenerated(backupSeed: ObvCrypto.BackupSeed, savedToKeychain: Bool) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userValidatedAdvancedSetupParameterAndNewSeedWasGenerated(self, backupSeed: backupSeed, savedToKeychain: savedToKeychain)
    }
    
    func userValidatedAdvancedSetupParameterButNewSeedFailedToBeGenerate() {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userValidatedAdvancedSetupParameterButNewSeedFailedToBeGenerate(self)
    }
    
    func userValidatedAdvancedSetupParameterButDeactivationFailed() {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userValidatedAdvancedSetupParameterButDeactivationFailed(self)
    }
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


// MARK: - View's actions

private final class ViewsActions: AdvancedSetupParametersViewActionsProtocol {

    weak var delegate: AdvancedSetupParametersViewActionsProtocol?

    func userValidatedAdvancedSetupParameterThusNewSeedMustBeGenerated(saveToKeychain: Bool) async throws -> ObvCrypto.BackupSeed {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        return try await delegate.userValidatedAdvancedSetupParameterThusNewSeedMustBeGenerated(saveToKeychain: saveToKeychain)
    }
    
    func userValidatedAdvancedSetupParameterAndDoNotWantBackups() async throws {
        guard let delegate else { assertionFailure(); return }
        try await delegate.userValidatedAdvancedSetupParameterAndDoNotWantBackups()
    }
    
    func userValidatedAdvancedSetupParameterAndNewSeedWasGenerated(backupSeed: ObvCrypto.BackupSeed, savedToKeychain: Bool) {
        delegate?.userValidatedAdvancedSetupParameterAndNewSeedWasGenerated(backupSeed: backupSeed, savedToKeychain: savedToKeychain)
    }
    
    func userValidatedAdvancedSetupParameterButNewSeedFailedToBeGenerate() {
        delegate?.userValidatedAdvancedSetupParameterButNewSeedFailedToBeGenerate()
    }
    
    func userValidatedAdvancedSetupParameterButDeactivationFailed() {
        delegate?.userValidatedAdvancedSetupParameterButDeactivationFailed()
    }
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}
