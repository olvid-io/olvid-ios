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
import MessageUI
import ObvAppCoreConstants


final class ProfileRestoreFailureHostingView: UIHostingController<ProfileRestoreFailureView> {
    
    private let actions = ViewsActions()
    
    init(model: ProfileRestoreFailureView.Model) {
        let view = ProfileRestoreFailureView(actions: actions, model: model, canSendMail: Self.canSendMail)
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
    
    
    // Strings
    
    private struct Strings {
        static let mailSubject = String(localizedInThisBundle: "MAIL_SUBJECT_COULD_NOT_RESTORE_PROFILE_ERROR")
        static func messageBody(errorMessage: String) -> String {
            String(localizedInThisBundle: "MAIL_BODY_COULD_NOT_RESTORE_PROFILE_ERROR_\(errorMessage)")
        }
    }

}


// MARK: - Implementing MFMailComposeViewControllerDelegate

extension ProfileRestoreFailureHostingView: MFMailComposeViewControllerDelegate {
    
    nonisolated
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { [weak self] in
                guard let self else { return }
                controller.dismiss(animated: true) {
                    if error != nil {
                        Task { [weak self] in await self?.showFailure() }
                    } else {
                        switch result {
                        case .cancelled:
                            return
                        case .saved, .sent:
                            Task { [weak self] in await self?.showSuccess() }
                        case .failed:
                            Task { [weak self] in await self?.showFailure() }
                        @unknown default:
                            return
                        }
                    }
                }
            }
        }
    }
    
    
    @MainActor
    private func showSuccess() async {
        await showHUDAndAwaitAnimationEnd(type: .checkmark)
        try? await Task.sleep(seconds: 1)
        hideHUD()
    }
    
    
    @MainActor
    private func showFailure() async {
        await showHUDAndAwaitAnimationEnd(type: .xmark)
        try? await Task.sleep(seconds: 1)
        hideHUD()
    }

}



// MARK: - Implementing ProfileRestoreFailureViewActionsProtocol

extension ProfileRestoreFailureHostingView: ProfileRestoreFailureViewActionsProtocol {
    
    @MainActor
    func userWantsToSendErrorByEmail(errorMessage: String) async {

        assert(MFMailComposeViewController.canSendMail())
        
        let composeVC = MFMailComposeViewController()
        composeVC.mailComposeDelegate = self
         
        // Configure the fields of the interface.
        composeVC.setToRecipients([ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage])
        composeVC.setSubject(Strings.mailSubject)
        composeVC.setMessageBody(Strings.messageBody(errorMessage: errorMessage), isHTML: false)

        // Present the view controller modally.
        self.present(composeVC, animated: true, completion: nil)

    }

}


// MARK: - View's actions

private final class ViewsActions: ProfileRestoreFailureViewActionsProtocol {
    
    weak var delegate: ProfileRestoreFailureViewActionsProtocol?
    
    func userWantsToSendErrorByEmail(errorMessage: String) async {
        await delegate?.userWantsToSendErrorByEmail(errorMessage: errorMessage)
    }
    
}


// MARK: - Previews

private enum ObvErrorForPreviews: Error {
    case someError
}

@available(iOS 17.0, *)
#Preview {
    ProfileRestoreFailureHostingView(model: .init(error: ObvErrorForPreviews.someError))
}
