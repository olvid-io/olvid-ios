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
import ObvTypes


@MainActor
protocol SelectUsersToAddViewControllerDelegate: AnyObject {
    func userWantsToAddSelectedUsersToExistingGroup(_ vc: SelectUsersToAddViewController, groupIdentifier: ObvTypes.ObvGroupV2Identifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws
    func userWantsToAddSelectedUsersToCreatingGroup(_ vc: SelectUsersToAddViewController, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier])
    func userWantsToCancelAndDismiss(_ vc: SelectUsersToAddViewController)
    func viewShouldBeDismissed(_ vc: SelectUsersToAddViewController)
}


final class SelectUsersToAddViewController: UIHostingController<SelectUsersToAddView> {
    
    private let actions = ViewsActions()
    private weak var internalDelegate: SelectUsersToAddViewControllerDelegate?
    let mode: SelectUsersToAddView.Mode
    
    init(mode: SelectUsersToAddView.Mode, dataSource: SelectUsersToAddViewDataSource, delegate: SelectUsersToAddViewControllerDelegate) {
        self.mode = mode
        let rootView = SelectUsersToAddView(mode: mode, dataSource: dataSource, actions: actions)
        super.init(rootView: rootView)
        self.internalDelegate = delegate
        self.actions.delegate = self
        self.title = String(localizedInThisBundle: "TITLE_ADD_GROUP_MEMBERS")
    }
    
    @MainActor @preconcurrency required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var groupIdentifier: ObvGroupV2Identifier? {
        switch mode {
        case .edition(groupIdentifier: let groupIdentifier): return groupIdentifier
        case .creation: return nil
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel,
            primaryAction: .init(handler: { [weak self] _ in
                guard let self else { return }
                internalDelegate?.userWantsToCancelAndDismiss(self)
            }),
            menu: nil)

    }
 
    enum ObvError: Error {
        case internalDelegateIsNil
    }
}


extension SelectUsersToAddViewController: SelectUsersToAddViewActionsProtocol {
    
    func userWantsToAddSelectedUsersToCreatingGroup(creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) {
        guard let internalDelegate else { assertionFailure(); return }
        internalDelegate.userWantsToAddSelectedUsersToCreatingGroup(self, creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, withIdentifiers: userIdentifiers)
    }
        
    func userWantsToAddSelectedUsersToExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {
        guard let internalDelegate else { assertionFailure(); throw ObvError.internalDelegateIsNil }
        try await internalDelegate.userWantsToAddSelectedUsersToExistingGroup(self, groupIdentifier: groupIdentifier, withIdentifiers: userIdentifiers)
    }
    
    func viewShouldBeDismissed() {
        guard let internalDelegate else { assertionFailure(); return }
        return internalDelegate.viewShouldBeDismissed(self)
    }
    
}


private final class ViewsActions: SelectUsersToAddViewActionsProtocol {
    
    weak var delegate: SelectUsersToAddViewActionsProtocol?
    
    enum ObvError: Error {
        case delegateIsNil
    }
    
    func userWantsToAddSelectedUsersToExistingGroup(groupIdentifier: ObvTypes.ObvGroupV2Identifier, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToAddSelectedUsersToExistingGroup(groupIdentifier: groupIdentifier, withIdentifiers: userIdentifiers)
    }
 
    func userWantsToAddSelectedUsersToCreatingGroup(creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, withIdentifiers userIdentifiers: [SelectUsersToAddViewModel.User.Identifier]) {
        guard let delegate else { assertionFailure(); return }
        delegate.userWantsToAddSelectedUsersToCreatingGroup(creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, withIdentifiers: userIdentifiers)
    }

    func viewShouldBeDismissed() {
        guard let delegate else { assertionFailure(); return }
        return delegate.viewShouldBeDismissed()
    }
}
