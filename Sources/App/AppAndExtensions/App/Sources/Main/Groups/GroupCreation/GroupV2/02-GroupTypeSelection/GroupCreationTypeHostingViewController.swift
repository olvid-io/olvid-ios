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
import ObvTypes
import ObvTypes
import ObvUICoreData
import Combine


protocol GroupCreationTypeHostingViewControllerDelegate: AnyObject {
    func userDidSelectGroupType(in controller: GroupCreationTypeHostingViewController, selectedGroupType: GroupTypeValue) async
    @MainActor func userWantsToCancelGroupCreationFlow(in controller: GroupCreationTypeHostingViewController)
}


final class GroupCreationTypeHostingViewController: UIHostingController<GroupTypeView<PersistedUser>>, GroupTypeViewActionsProtocol {

    private weak var delegate: GroupCreationTypeHostingViewControllerDelegate?
    
    init(preselectedGroupType: GroupTypeValue?, selectedUsersOrdered: [PersistedUser], delegate: GroupCreationTypeHostingViewControllerDelegate) {
        self.delegate = delegate
        let actions = Actions()
        let view = GroupTypeView(model: .init(selectedUsersOrdered: selectedUsersOrdered, preselectedGroupType: preselectedGroupType), actions: actions)
        super.init(rootView: view)
        actions.delegate = self
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemGroupedBackground
        self.title = String(localized: "GROUP_TYPE_TITLE")
        
        let cancelButton = UIBarButtonItem(systemItem: .cancel, primaryAction: .init(handler: { [weak self] _ in
            guard let self else { return }
            delegate?.userWantsToCancelGroupCreationFlow(in: self)
        }))
        self.navigationItem.setRightBarButton(cancelButton, animated: false)

    }
    
    // GroupTypeViewActionsProtocol
    
    func userDidSelectGroupType(selectedGroupType: GroupTypeValue) async {
        await delegate?.userDidSelectGroupType(in: self, selectedGroupType: selectedGroupType)
    }

}


fileprivate final class Actions: GroupTypeViewActionsProtocol {
            
    weak var delegate: GroupTypeViewActionsProtocol?
    
    func userDidSelectGroupType(selectedGroupType: GroupTypeValue) async {
        await delegate?.userDidSelectGroupType(selectedGroupType: selectedGroupType)
    }

}
