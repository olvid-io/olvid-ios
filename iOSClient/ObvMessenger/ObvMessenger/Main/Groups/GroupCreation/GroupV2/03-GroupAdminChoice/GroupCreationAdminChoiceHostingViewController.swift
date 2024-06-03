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
    func userWantsToChangeContactAdminStatus(in controller: GroupCreationAdminChoiceHostingViewController, contactCryptoId: ObvTypes.ObvCryptoId, isAdmin: Bool) -> Set<PersistedObvContactIdentity>
    func userConfirmedGroupAdminChoice(in controller: GroupCreationAdminChoiceHostingViewController) async
    func userWantsToCancelGroupCreationFlow(in controller: GroupCreationAdminChoiceHostingViewController)
}


final class GroupCreationAdminChoiceHostingViewController: UIHostingController<GroupAdminChoiceView<GroupAdminChoiceViewModel>>, GroupAdminChoiceViewActionsProtocol {
        
    private let viewModel: GroupAdminChoiceViewModel
    private weak var delegate: GroupCreationAdminChoiceHostingViewControllerDelegate?
    private let showButton: Bool

    init(contacts: [PersistedObvContactIdentity], admins: Set<PersistedObvContactIdentity>, showButton: Bool, delegate: GroupCreationAdminChoiceHostingViewControllerDelegate) {
        self.showButton = showButton
        self.delegate = delegate
        self.viewModel = .init(contacts: contacts.map({ .init(contact: $0, isAdmin: admins.contains($0)) }))
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
    
    func userWantsToChangeContactAdminStatus(contactCryptoId: ObvTypes.ObvCryptoId, isAdmin: Bool) {
        guard let delegate else { assertionFailure(); return }
        let newAdmins = delegate.userWantsToChangeContactAdminStatus(in: self, contactCryptoId: contactCryptoId, isAdmin: isAdmin)
        viewModel.contacts.forEach { contact in
            contact.isAdmin = newAdmins.contains(contact.contact)
        }
    }

    
    func userConfirmedGroupAdminChoice() async {
        await delegate?.userConfirmedGroupAdminChoice(in: self)
    }
    
}


private final class Actions: GroupAdminChoiceViewActionsProtocol {
    
    weak var delegate: GroupAdminChoiceViewActionsProtocol?
    
    func userWantsToChangeContactAdminStatus(contactCryptoId: ObvCryptoId, isAdmin: Bool) {
        delegate?.userWantsToChangeContactAdminStatus(contactCryptoId: contactCryptoId, isAdmin: isAdmin)
    }
    
    func userConfirmedGroupAdminChoice() async {
        await delegate?.userConfirmedGroupAdminChoice()
    }
    
}


// MARK: - Models for the SwiftUI views

final class ContactOrAdminCellViewModel: ContactOrAdminCellViewModelProtocol {
    
    @Published fileprivate(set) var contact: PersistedObvContactIdentity
    @Published fileprivate(set) var isAdmin: Bool
    
    init(contact: PersistedObvContactIdentity, isAdmin: Bool) {
        self.contact = contact
        self.isAdmin = isAdmin
    }
    
}


final class GroupAdminChoiceViewModel: GroupAdminChoiceViewModelProtocol {
    var contacts: [ContactOrAdminCellViewModel]
    
    init(contacts: [ContactOrAdminCellViewModel]) {
        self.contacts = contacts
    }

}
