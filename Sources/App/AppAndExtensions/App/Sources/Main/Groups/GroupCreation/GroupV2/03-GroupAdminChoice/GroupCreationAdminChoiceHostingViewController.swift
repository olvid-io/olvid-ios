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
import Combine


protocol GroupCreationAdminChoiceHostingViewControllerDelegate: AnyObject {
    @MainActor func userWantsToChangeUserAdminStatus(in controller: GroupCreationAdminChoiceHostingViewController, userCryptoId: ObvTypes.ObvCryptoId, isAdmin: Bool) -> Set<ObvUICoreData.PersistedUser>
    func userConfirmedGroupAdminChoice(in controller: GroupCreationAdminChoiceHostingViewController) async
    @MainActor func userWantsToCancelGroupCreationFlow(in controller: GroupCreationAdminChoiceHostingViewController)
}


final class GroupCreationAdminChoiceHostingViewController: UIHostingController<GroupAdminChoiceView<GroupAdminChoiceViewModel>>, GroupAdminChoiceViewActionsProtocol {
        
    private let viewModel: GroupAdminChoiceViewModel
    private weak var delegate: GroupCreationAdminChoiceHostingViewControllerDelegate?
    private let showButton: Bool

    init(users: [PersistedUser], admins: Set<PersistedUser>, showButton: Bool, delegate: GroupCreationAdminChoiceHostingViewControllerDelegate) {
        self.showButton = showButton
        self.delegate = delegate
        self.viewModel = .init(users: users.map({ .init(user: $0, isAdmin: admins.contains($0)) }))
        let actions = Actions()
        let view = GroupAdminChoiceView(model: self.viewModel, actions: actions, showButton: showButton)
        super.init(rootView: view)
        actions.delegate = self
    }
    

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemGroupedBackground
        self.title = String(localized: "DISCUSSION_ADMIN_CHOICE")
        
        if showButton {
            self.navigationItem.rightBarButtonItem = .init(systemItem: .cancel, primaryAction: .init(handler: { [weak self] _ in
                guard let self else { return }
                delegate?.userWantsToCancelGroupCreationFlow(in: self)
            }))
        }

    }
    
    // GroupAdminChoiceViewActionsProtocol
    
    func userWantsToChangeUserAdminStatus(userCryptoId: ObvTypes.ObvCryptoId, isAdmin: Bool) {
        guard let delegate else { assertionFailure(); return }
        let newAdmins = delegate.userWantsToChangeUserAdminStatus(in: self, userCryptoId: userCryptoId, isAdmin: isAdmin)
        viewModel.users.forEach { user in
            user.isAdmin = newAdmins.contains(user.user)
        }
    }

    
    func userConfirmedGroupAdminChoice() async {
        await delegate?.userConfirmedGroupAdminChoice(in: self)
    }
    
}


private final class Actions: GroupAdminChoiceViewActionsProtocol {
    
    weak var delegate: GroupAdminChoiceViewActionsProtocol?
    
    func userWantsToChangeUserAdminStatus(userCryptoId: ObvCryptoId, isAdmin: Bool) {
        delegate?.userWantsToChangeUserAdminStatus(userCryptoId: userCryptoId, isAdmin: isAdmin)
    }
    
    func userConfirmedGroupAdminChoice() async {
        await delegate?.userConfirmedGroupAdminChoice()
    }
    
}


// MARK: - Models for the SwiftUI views

final class UserOrAdminCellViewModel: UserOrAdminCellViewModelProtocol {
    
    @Published fileprivate(set) var user: PersistedUser
    @Published fileprivate(set) var isAdmin: Bool
    
    init(user: PersistedUser, isAdmin: Bool) {
        self.user = user
        self.isAdmin = isAdmin
    }
    
}


final class GroupAdminChoiceViewModel: GroupAdminChoiceViewModelProtocol {
    var users: [UserOrAdminCellViewModel]
    
    init(users: [UserOrAdminCellViewModel]) {
        self.users = users
    }

}
