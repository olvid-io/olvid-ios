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


protocol StolenOrCompromisedKeyHostingViewDelegate: AnyObject {
    @MainActor func userWantsToEraseAndGenerateNewDeviceBackupSeed(_ vc: StolenOrCompromisedKeyHostingView) async throws
    @MainActor func userWantsToNavigateToBackupKeyDisplayerView(_ vc: StolenOrCompromisedKeyHostingView)
}


final class StolenOrCompromisedKeyHostingView: UIHostingController<StolenOrCompromisedKeyView> {
    
    private let actions = ViewsActions()
    private weak var internalDelegate: StolenOrCompromisedKeyHostingViewDelegate?
    
    init(delegate: StolenOrCompromisedKeyHostingViewDelegate) {
        let rootView = StolenOrCompromisedKeyView(actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        self.actions.delegate = self
        self.title = String(localizedInThisBundle: "STOLEN_OR_COMPROMISED_KEY")
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
}


// MARK: - Implementing StolenOrCompromisedKeyViewActionsDelegate

extension StolenOrCompromisedKeyHostingView: StolenOrCompromisedKeyViewActionsDelegate {
    
    func userWantsToEraseAndGenerateNewDeviceBackupSeed() async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await internalDelegate.userWantsToEraseAndGenerateNewDeviceBackupSeed(self)
    }
    
    func userWantsToNavigateToBackupKeyDisplayerView() {
        internalDelegate?.userWantsToNavigateToBackupKeyDisplayerView(self)
    }
    
}


// MARK: - Errors

extension StolenOrCompromisedKeyHostingView {
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}


// MARK: - View's actions

private final class ViewsActions: StolenOrCompromisedKeyViewActionsDelegate {
    
    weak var delegate: StolenOrCompromisedKeyViewActionsDelegate?
    
    func userWantsToEraseAndGenerateNewDeviceBackupSeed() async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToEraseAndGenerateNewDeviceBackupSeed()
    }
    
    func userWantsToNavigateToBackupKeyDisplayerView() {
        delegate?.userWantsToNavigateToBackupKeyDisplayerView()
    }
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
}
