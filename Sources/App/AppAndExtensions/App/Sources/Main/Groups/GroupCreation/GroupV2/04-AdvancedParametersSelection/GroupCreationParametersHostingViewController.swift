/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import OSLog
import ObvTypes
import ObvUICoreData


protocol GroupCreationParametersHostingViewControllerDelegate: AnyObject {
    @MainActor func userWantsToChangeReadOnlyParameter(in controller: GroupCreationParametersHostingViewController, isReadOnly: Bool) -> Bool
    @MainActor func userWantsToNavigateToAdminsChoice(in controller: GroupCreationParametersHostingViewController)
    @MainActor func userWantsToNavigateToRemoteDeleteAnythingPolicyChoice(in controller: GroupCreationParametersHostingViewController)
    @MainActor func userWantsToNavigateToNextScreen(in controller: GroupCreationParametersHostingViewController)
    @MainActor func userWantsToCancelGroupCreationFlow(in controller: GroupCreationParametersHostingViewController)
}


final class GroupCreationParametersHostingViewController: UIHostingController<GroupParametersView<GroupParametersViewModel>>, GroupParametersViewActionsProtocol {

    private let viewModel: GroupParametersViewModel
    private weak var delegate: GroupCreationParametersHostingViewControllerDelegate?
    
    init(model: GroupParametersViewModel, delegate: GroupCreationParametersHostingViewControllerDelegate) {
        self.delegate = delegate
        self.viewModel = model
        let actions = Actions()
        let view = GroupParametersView(model: model, actions: actions)
        super.init(rootView: view)
        actions.delegate = self
    }
    
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func userChangedRemoteDeleteAnythingPolicy(to newValue: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) {
        self.viewModel.remoteDeleteAnythingPolicy = newValue
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemGroupedBackground
        
        self.navigationItem.rightBarButtonItem = .init(systemItem: .cancel, primaryAction: .init(handler: { [weak self] _ in
            guard let self else { return }
            delegate?.userWantsToCancelGroupCreationFlow(in: self)
        }))

    }
    
    // GroupParametersViewActionsProtocol
    
    func userWantsToChangeReadOnlyParameter(isReadOnly: Bool) {
        guard let delegate else { assertionFailure(); return }
        viewModel.isReadOnly = delegate.userWantsToChangeReadOnlyParameter(in: self, isReadOnly: isReadOnly)
    }
    
    func userWantsToNavigateToAdminsChoice() {
        delegate?.userWantsToNavigateToAdminsChoice(in: self)
    }
    
    func userWantsToNavigateToRemoteDeleteAnythingPolicyChoice() {
        delegate?.userWantsToNavigateToRemoteDeleteAnythingPolicyChoice(in: self)
    }
    
    func userWantsToNavigateToNextScreen() {
        delegate?.userWantsToNavigateToNextScreen(in: self)
    }
    
}


private final class Actions: GroupParametersViewActionsProtocol {
    
    weak var delegate: GroupParametersViewActionsProtocol?
    
    func userWantsToChangeReadOnlyParameter(isReadOnly: Bool) {
        delegate?.userWantsToChangeReadOnlyParameter(isReadOnly: isReadOnly)
    }
    
    func userWantsToNavigateToAdminsChoice() {
        delegate?.userWantsToNavigateToAdminsChoice()
    }
    
    func userWantsToNavigateToRemoteDeleteAnythingPolicyChoice() {
        delegate?.userWantsToNavigateToRemoteDeleteAnythingPolicyChoice()
    }

    func userWantsToNavigateToNextScreen() {
        delegate?.userWantsToNavigateToNextScreen()
    }
    
}


// MARK: - GroupParametersViewModel
@MainActor
final class GroupParametersViewModel: GroupParametersViewModelProtocol {
    
    let selectedUsersOrdered: [PersistedUser] // Group members
    @Published var remoteDeleteAnythingPolicy: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy
    @Published var isReadOnly: Bool
    let canEditContacts = false

    var groupHasNoOtherMembers: Bool { selectedUsersOrdered.isEmpty }

    init(selectedUsersOrdered: [PersistedUser], remoteDeleteAnythingPolicy: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy, isReadOnly: Bool) {
        self.selectedUsersOrdered = selectedUsersOrdered
        self.remoteDeleteAnythingPolicy = remoteDeleteAnythingPolicy
        self.isReadOnly = isReadOnly
    }

}
