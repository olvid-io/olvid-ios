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
import ObvUICoreData


protocol GroupCreationModerationHostingViewControllerDelegate: AnyObject {
    func userWantsToChangeRemoteDeleteAnythingPolicy(in controller: GroupCreationModerationHostingViewController, to policy: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) -> ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy
}


class GroupCreationModerationHostingViewController: UIHostingController<GroupModerationView<GroupModerationViewModel>>, GroupModerationViewActionsProtocol {

    private let model: GroupModerationViewModel
    private weak var delegate: GroupCreationModerationHostingViewControllerDelegate?
    
    init(model: GroupModerationViewModel, delegate: GroupCreationModerationHostingViewControllerDelegate) {
        self.delegate = delegate
        self.model = model
        let actions = Actions()
        let view = GroupModerationView(model: model, actions: actions)
        super.init(rootView: view)
        actions.delegate = self
    }
    
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemGroupedBackground
    }
    
    
    // GroupModerationViewActionsProtocol
    
    func userWantsToChangeRemoteDeleteAnythingPolicy(to policy: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) {
        guard let delegate else { assertionFailure(); return }
        model.currentPolicy = delegate.userWantsToChangeRemoteDeleteAnythingPolicy(in: self, to: policy)
    }
    
}


private final class Actions: GroupModerationViewActionsProtocol {
    
    weak var delegate: GroupModerationViewActionsProtocol?
    
    func userWantsToChangeRemoteDeleteAnythingPolicy(to policy: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) {
        delegate?.userWantsToChangeRemoteDeleteAnythingPolicy(to: policy)
    }
    
}


// MARK: - GroupModerationViewModel

final class GroupModerationViewModel: GroupModerationViewModelProtocol {
    
    @Published var currentPolicy: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy
    
    init(currentPolicy: ObvUICoreData.PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) {
        self.currentPolicy = currentPolicy
    }
    
}
