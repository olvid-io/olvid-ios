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
import MessageUI
import ObvUI
import ObvAppCoreConstants

final class InitializationFailureViewController: UIViewController {

    @IBOutlet weak var standardErrorMessage: UILabel!
    @IBOutlet weak var errorMessageLabel: UILabel!
    @IBOutlet weak var shareErrorMessageExplanationLabel: UILabel!
    @IBOutlet weak var shareButton: UIButton!
    @IBOutlet weak var thankYouLabel: UILabel!
    
    enum Category {
        case initializationFailed
        case initializationTakesTooLong
    }
    
    var category = Category.initializationFailed
    
    var error: Error? {
        didSet {
            errorMessageLabel?.text = errorMessage
        }
    }
    
    override var canBecomeFirstResponder: Bool { true }
    
    private var errorMessage: String? {
        guard let error = self.error else { return nil }
        let exactModel = UIDevice.current.exactModel
        let systemName = UIDevice.current.name
        let systemVersion = UIDevice.current.systemVersion
        let fullOlvidVersion = ObvAppCoreConstants.fullVersion
        let msg = [
            "Olvid version: \(fullOlvidVersion)",
            "Device model: \(exactModel)",
            "System: \(systemName) \(systemVersion)",
            "Error messages:\n\(error.localizedDescription)",
        ]
        return msg.joined(separator: "\n")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = Strings.title
        self.standardErrorMessage.text = Strings.stdErrorMsgForCategory(category)
        self.errorMessageLabel.text = errorMessage
        self.shareButton.setTitle(Strings.shareButtonTitle, for: .normal)
        self.thankYouLabel.text = Strings.thankYou
        if MFMailComposeViewController.canSendMail() {
            self.shareErrorMessageExplanationLabel.text = Strings.shareErrorMessageExplanation(category)
        } else {
            self.shareErrorMessageExplanationLabel.text = Strings.shareErrorMessageExplanationWhenNoMail(ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage)
        }
        if !MFMailComposeViewController.canSendMail() {
            self.shareButton.isHidden = true
        } else {
            self.shareButton.isHidden = false
        }
        
        let copyButton = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), style: .plain, target: self, action: #selector(copyErrorMessageClipboardButtonTapped))
        self.navigationItem.setRightBarButton(copyButton, animated: false)
        self.thankYouLabel.isHidden = true
    }
    
    @objc func copyErrorMessageClipboardButtonTapped() {
        UIPasteboard.general.string = errorMessage
    }
    
    @IBAction func shareButtonTapped(_ sender: Any) {
        if MFMailComposeViewController.canSendMail() {
            shareFailureMessageByMail()
        } else {
            return
        }
    }
    
    
    private func shareFailureMessageByMail() {
        
        assert(Thread.current == Thread.main)
        assert(MFMailComposeViewController.canSendMail())
        
        let composeVC = MFMailComposeViewController()
        composeVC.mailComposeDelegate = self
         
        // Configure the fields of the interface.
        composeVC.setToRecipients([ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage])
        composeVC.setSubject(Strings.pleaseFix)
        composeVC.setMessageBody(Strings.messageBody(errorMessage ?? ""), isHTML: false)

        // Present the view controller modally.
        self.present(composeVC, animated: true, completion: nil)

    }
    
}

extension InitializationFailureViewController: MFMailComposeViewControllerDelegate {
    
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        switch result {
        case .sent:
            shareButton.isEnabled = false
            self.presentedViewController?.dismiss(animated: true, completion: { [weak self] in
                UIView.animate(withDuration: 0.3) {
                    self?.thankYouLabel.isHidden = false
                }
            })
        default:
            self.presentedViewController?.dismiss(animated: true)
        }
    }
    
}


extension InitializationFailureViewController {
    
    private struct Strings {
        static let title = NSLocalizedString("Sorry...", comment: "Title")
        static func stdErrorMsgForCategory(_ category: Category) -> String {
            switch category {
            case .initializationFailed:
                return NSLocalizedString("Olvid failed to start properly. This is a terrible experience, we deeply appologize about this.", comment: "Body text")
            case .initializationTakesTooLong:
                return NSLocalizedString("STD_MSG_OLVID_TAKES_TOO_LONG_TO_START", comment: "Body text")
            }
        }
        static let shareButtonTitle = NSLocalizedString("Send this to the development team", comment: "Button title")
        static func shareErrorMessageExplanation(_ category: Category) -> String {
            switch category {
            case .initializationFailed:
                return NSLocalizedString("If you wish, you can help the development team by tapping the button below. This will share (only) the above message with them.", comment: "Body text")
            case .initializationTakesTooLong:
                return NSLocalizedString("SHARE_MSG_OLVID_TAKES_TOO_LONG_TO_START", comment: "Body text")
            }
        }
        
        static let shareErrorMessageExplanationWhenNoMail = { (email: String) in
            String.localizedStringWithFormat(NSLocalizedString("Please report this error to %1$@ so we can fix this issue as fast as possible.", comment: "body text"), email)
        }
        static let thankYou = NSLocalizedString("Thank you!", comment: "Body with title font")
        static let pleaseFix = NSLocalizedString("Please fix this serious issue with Olvid", comment: "Mail subject")
        static let messageBody = { (errorMessage: String) in
            String.localizedStringWithFormat(NSLocalizedString("Olvid failed to initialize with the following error message:\n\n%1$@", comment: "mail body text"), errorMessage)
        }
    }
    
}


fileprivate extension UIDevice {
    
    var exactModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let exactModel = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return "\(self.model) (\(exactModel))"
    }
    
}
