/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


final class ContactsPresentationViewController: UIViewController {
    
    let ownedCryptoId: ObvCryptoId
    let presentedContactCryptoId: ObvCryptoId
    let dismissAction: () -> Void

    private var viewController: UIViewController!
    private var okButtonItem: UIBarButtonItem!

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
        let excludedContactCryptoIds = Set([presentedContactCryptoId])
        let mode: MultipleContactsMode = .excluded(from: excludedContactCryptoIds, oneToOneStatus: .oneToOne, requiredCapabilitites: nil)

        let multipleContactsVC = MultipleContactsViewController(ownedCryptoId: ownedCryptoId,
                                                                mode: mode,
                                                                button: .floating(title: Strings.performContactIntroduction, systemIcon: .personLineDottedPersonFill),
                                                                disableContactsWithoutDevice: true,
                                                                allowMultipleSelection: true,
                                                                showExplanation: false,
                                                                allowEmptySetOfContacts: false,
                                                                textAboveContactList: nil) { [weak self] selectedContacts in
            guard let presentedContactCryptoId = self?.presentedContactCryptoId,
                  let ownedCryptoId = self?.ownedCryptoId else { assertionFailure(); return }
            let cryptoIds = Set(selectedContacts.map({ $0.cryptoId }))
            guard !cryptoIds.isEmpty else { assertionFailure(); return }
            self?.userWantsToIntroduce(presentedContactCryptoId: presentedContactCryptoId, to: cryptoIds, ofOwnedCryptoId: ownedCryptoId)
        } dismissAction: {
            self.dismissAction()
        }
        multipleContactsVC.title = self.title
        viewController = ObvNavigationController(rootViewController: multipleContactsVC)

        displayContentController(content: viewController)
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
