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
import ObvTypes
import ObvUICoreData
import ObvSystemIcon


final class ContactsPresentationViewController: UINavigationController {
    
    let ownedCryptoId: ObvCryptoId
    let presentedContactCryptoId: ObvCryptoId
    let dismissAction: () -> Void

    private(set) var selectedContacts = Set<PersistedObvContactIdentity>()
    
    init(ownedCryptoId: ObvCryptoId, presentedContactCryptoId: ObvCryptoId, dismissAction: @escaping () -> Void) {
        self.ownedCryptoId = ownedCryptoId
        self.presentedContactCryptoId = presentedContactCryptoId
        self.dismissAction = dismissAction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    override func viewDidLoad() {
        
        let verticalConfiguration = VerticalUsersViewConfiguration(
            showExplanation: false,
            disableUsersWithoutDevice: true,
            allowMultipleSelection: true,
            textAboveUserList: nil,
            selectionStyle: .checkmark)
        let horizontalConfiguration = HorizontalUsersViewConfiguration(
            textOnEmptySetOfUsers: self.title ?? "",
            canEditUsers: true)
        let buttonConfiguration = HorizontalAndVerticalUsersViewButtonConfiguration(
            title: Strings.performContactIntroduction,
            systemIcon: .personLineDottedPersonFill,
            action: { [weak self] cryptoIds in self?.userDidSelectContactsToIntroduce(cryptoIds)},
            allowEmptySetOfContacts: false)
        let configuration = HorizontalAndVerticalUsersViewConfiguration(
            verticalConfiguration: verticalConfiguration,
            horizontalConfiguration: horizontalConfiguration,
            buttonConfiguration: buttonConfiguration)

        let multipleContactsVC = MultipleUsersHostingViewController(
            ownedCryptoId: ownedCryptoId,
            mode: .excluded(from: Set([presentedContactCryptoId]), oneToOneStatus: .oneToOne, requiredCapabilitites: nil),
            configuration: configuration,
            delegate: nil)
        
        multipleContactsVC.navigationItem.rightBarButtonItem = .init(systemItem: .cancel, primaryAction: .init(handler: { [weak self] _ in
            guard let self else { return }
            dismissAction()
        }))
        
        multipleContactsVC.navigationItem.searchController = multipleContactsVC.searchController
        multipleContactsVC.navigationItem.hidesSearchBarWhenScrolling = false

        multipleContactsVC.title = self.title
        
        self.viewControllers = [multipleContactsVC]

    }
    
    private func userDidSelectContactsToIntroduce(_ contactCryptoIds: Set<ObvCryptoId>) {
        guard !contactCryptoIds.isEmpty else { assertionFailure(); return }
        self.userWantsToIntroduce(presentedContactCryptoId: presentedContactCryptoId, to: contactCryptoIds, ofOwnedCryptoId: ownedCryptoId)
    }
    

    private func userWantsToIntroduce(presentedContactCryptoId: ObvCryptoId, to contacts: Set<ObvCryptoId>, ofOwnedCryptoId ownedCryptoId: ObvCryptoId) {
        guard let otherContact = contacts.first else { return }
        guard otherContact != presentedContactCryptoId else { return }
        self.dismiss(animated: true) {
            ObvMessengerInternalNotification.userWantsToIntroduceContactToAnotherContact(ownedCryptoId: ownedCryptoId, firstContactCryptoId: presentedContactCryptoId, secondContactCryptoIds: contacts)
                .postOnDispatchQueue()
        }
    }

}


extension ContactsPresentationViewController {
    
    struct Strings {
        static let performContactIntroduction = NSLocalizedString("PERFORM_CONTACT_INTRODUCTION", comment: "")
    }
    
}
