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
import OSLog
import ObvTypes
import SwiftUI
import ObvUICoreData
import ObvAppCoreConstants


protocol UsersSelectionForGroupViewControllerDelegate: AnyObject {
    @MainActor func userDidValidateSelectedUsers(in controller: UsersSelectionForGroupViewController, selectedUsers: [PersistedUser]) async
    @MainActor func userWantsToCancelGroupCreationFlow(in controller: UsersSelectionForGroupViewController)
}


final class UsersSelectionForGroupViewController: UIViewController {
    
    private let ownedCryptoId: ObvCryptoId
    private let mode: Mode
    private let preSelectedUsers: Set<PersistedUser>
    private var multipleContactsHostingViewController: MultipleUsersHostingViewController?

    private weak var delegate: UsersSelectionForGroupViewControllerDelegate?

    enum Mode {
        case modify(groupIdentifier: GroupV2Identifier)
        case create
    }
    
    init(ownedCryptoId: ObvCryptoId, mode: Mode, preSelectedUsers: Set<PersistedUser>, delegate: UsersSelectionForGroupViewControllerDelegate?) {
        self.ownedCryptoId = ownedCryptoId
        self.mode = mode
        self.preSelectedUsers = preSelectedUsers
        super.init(nibName: nil, bundle: nil)
        self.delegate = delegate
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = .systemGroupedBackground
        
        addAndConfigureMultipleContactsHostingViewController()
        
        switch mode {
        case .modify:
            self.navigationItem.title = Strings.updateGroupTitle
        case .create:
            self.navigationItem.title = Strings.newGroupTitle
        }

        self.navigationItem.rightBarButtonItem = .init(systemItem: .cancel, primaryAction: .init(handler: { [weak self] _ in
            guard let self else { return }
            delegate?.userWantsToCancelGroupCreationFlow(in: self)
        }))
        
    }
    
    
    func addAndConfigureMultipleContactsHostingViewController() {
        
        let verticalConfiguration = VerticalUsersViewConfiguration(
            showExplanation: false,
            disableUsersWithoutDevice: true,
            allowMultipleSelection: true,
            textAboveUserList: nil,
            selectionStyle: .checkmark)
        let horizontalConfiguration = HorizontalUsersViewConfiguration(
            textOnEmptySetOfUsers: Strings.textOnEmptySetOfContacts,
            canEditUsers: true)
        let buttonConfiguration = HorizontalAndVerticalUsersViewButtonConfiguration(
            title: CommonString.Word.Next,
            systemIcon: .personCropCircleFillBadgeCheckmark,
            action: { [weak self] _ in self?.userDidChooseGroupMembers() },
            allowEmptySetOfContacts: true)
        let configuration = HorizontalAndVerticalUsersViewConfiguration(
            verticalConfiguration: verticalConfiguration,
            horizontalConfiguration: horizontalConfiguration,
            buttonConfiguration: buttonConfiguration)
        let groupMembersMode: MultipleUsersHostingViewController.GroupMembersMode
        switch self.mode {
        case .create:
            groupMembersMode = .none
        case .modify(groupIdentifier: let groupIdentifier):
            groupMembersMode = .notContact(groupIdentifier: groupIdentifier)
        }

        let vc = MultipleUsersHostingViewController(
            ownedCryptoId: ownedCryptoId,
            mode: .all(oneToOneStatus: .any, requiredCapabilitites: [.groupsV2]),
            groupMembersMode: groupMembersMode,
            configuration: configuration,
            delegate: nil)
             
        vc.resetSelectedUsers(to: preSelectedUsers)
        
        navigationItem.searchController = vc.searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        displayContentController(content: vc)
        
        multipleContactsHostingViewController = vc

    }
    

    func userDidChooseGroupMembers() {
        guard let delegate = self.delegate else { assertionFailure(); return }
        guard let orderedSelectedUsers = self.multipleContactsHostingViewController?.orderedSelectedUsers else { assertionFailure(); return }
        Task { [weak self] in
            guard let self else { return }
            await delegate.userDidValidateSelectedUsers(in: self, selectedUsers: orderedSelectedUsers)
        }
    }

}


// MARK: - Localized strings

extension UsersSelectionForGroupViewController {

    struct Strings {
        static let newGroupTitle = NSLocalizedString("NEW_GROUP", comment: "View controller title")
        static let updateGroupTitle = NSLocalizedString("EDIT_GROUP", comment: "View controller title")
        static let textOnEmptySetOfContacts = NSLocalizedString("SOME_OF_YOUR_CONTACTS_MAY_NOT_APPEAR_AS_GROUP_V2_CANDIDATES", comment: "")
    }

}
