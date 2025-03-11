/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import MessageUI
import ObvAppCoreConstants


final class OwnedIdentityTransferFailureViewController: UIHostingController<OwnedIdentityTransferFailureView>, MFMailComposeViewControllerDelegate, OwnedIdentityTransferFailureViewActionsProtocol {
    
    init(model: OwnedIdentityTransferFailureView.Model) {
        let actions = OwnedIdentityTransferFailureViewActions()
        let view = OwnedIdentityTransferFailureView(actions: actions, model: model, canSendMail: Self.canSendMail)
        super.init(rootView: view)
        actions.delegate = self
    }
    
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .systemBackground
        configureNavigation(animated: false)
    }

    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureNavigation(animated: animated)
    }


    private func configureNavigation(animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    
    private static var canSendMail: Bool {
        MFMailComposeViewController.canSendMail()
    }
    
    
    // OwnedIdentityTransferFailureViewActions
    
    @MainActor
    func userWantsToSendErrorByEmail(errorMessage: String) async {

        assert(MFMailComposeViewController.canSendMail())
        
        let composeVC = MFMailComposeViewController()
        composeVC.mailComposeDelegate = self
         
        // Configure the fields of the interface.
        composeVC.setToRecipients([ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage])
        composeVC.setSubject(Strings.mailSubject)
        composeVC.setMessageBody(Strings.messageBody(errorMessage), isHTML: false)

        // Present the view controller modally.
        self.present(composeVC, animated: true, completion: nil)

    }
    
    
    // MFMailComposeViewControllerDelegate
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        guard error == nil else { return }
        Task { [weak self] in
            await self?.showSuccess()
        }
    }
    
    
    @MainActor
    private func showSuccess() async {
        await showHUDAndAwaitAnimationEnd(type: .checkmark)
        try? await Task.sleep(seconds: 1)
        hideHUD()
    }

    
    // Strings
    
    private struct Strings {
        static let mailSubject = String(localizedInThisBundle: "MAIL_SUBJECT_COULD_NOT_TRANSFER_PROFILE_ERROR")
        static let messageBody = { (errorMessage: String) in
            String.localizedStringWithFormat(String(localizedInThisBundle: "MAIL_BODY_COULD_NOT_TRANSFER_PROFILE_ERROR$@"), errorMessage)
        }
    }

}


private final class OwnedIdentityTransferFailureViewActions: OwnedIdentityTransferFailureViewActionsProtocol {
    
    weak var delegate: OwnedIdentityTransferFailureViewActionsProtocol?
    
    func userWantsToSendErrorByEmail(errorMessage: String) async {
        await delegate?.userWantsToSendErrorByEmail(errorMessage: errorMessage)
    }
    
}
