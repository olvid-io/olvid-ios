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
import OlvidUtils
import ObvUI


class SasView: UIView, ObvErrorMaker {

    static let nibName = "SasView"
    
    private let expectedSasLength = 4
    private let sasFont = UIFont.preferredFont(forTextStyle: .title2)
    static let errorDomain = "SasView"

    // Views
    
    @IBOutlet weak var ownSasTitleLabel: UILabel! { didSet { ownSasTitleLabel.textColor = AppTheme.shared.colorScheme.label } }
    @IBOutlet weak var contactSasTitleLabel: UILabel! { didSet { contactSasTitleLabel.textColor = AppTheme.shared.colorScheme.label }}
    
    @IBOutlet weak var ownSasLabel: UILabel! {
        didSet {
            ownSasLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
            ownSasLabel.font = sasFont
        }
    }
    
    @IBOutlet weak var contactSasTextField: ObvTextField! {
        didSet {
            contactSasTextField.delegate = self
            contactSasTextField.font = sasFont
            contactSasTextField.textColor = appTheme.colorScheme.secondaryLabel
            NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: contactSasTextField, queue: OperationQueue.main, using: self.textFieldDidChange)
        }
    }

    @IBOutlet weak var contactSasTextFieldWidth: NSLayoutConstraint! {
        didSet {
            let width = computeWidthOfContactSasTextField()
            if contactSasTextFieldWidth.constant != width {
               contactSasTextFieldWidth.constant = width
                setNeedsLayout()
            }
        }
    }
    
    @IBOutlet weak var doneButton: ObvButtonBorderless!

    var onSasInput: ((_ enteredDigits: String) -> Void)?
    var onAbort: (() -> Void)?
}

// MARK: - awakeFromNib, configuration and responding to external events

extension SasView {

    override func awakeFromNib() {
        super.awakeFromNib()
        translatesAutoresizingMaskIntoConstraints = false
        evaluateEnteredContactSasAndUpdateUI()
    }

    @IBAction func doneButtonTapped(_ sender: UIButton) {
        if let sas = evaluateEnteredContactSasAndUpdateUI() {
            onSasInput?(sas)
        }
    }

    @IBAction func abortButtonTapped(_ sender: Any) {
        onAbort?()
    }

    
    private func computeWidthOfContactSasTextField() -> CGFloat {
        let typicalSas = String(repeating: "X", count: expectedSasLength) as NSString
        let minimumWidth = typicalSas.size(withAttributes: [NSAttributedString.Key.font: sasFont]).width
        let finalWidth = minimumWidth * 1.1
        return finalWidth
    }
    
    override func resignFirstResponder() -> Bool {
        if let enteredSas = contactSasTextField.text {
            if enteredSas.isEmpty {
                resetContactSas()
            }
        } else {
            resetContactSas()
        }
        return contactSasTextField.resignFirstResponder()
    }

}

// MARK: - SAS related stuff

fileprivate extension String {
    
    func isValidSas(ofLength length: Int) -> Bool {
        guard self.count == length else { return false }
        return self.allSatisfy { $0.isValidSasCharacter() }
    }
    
}

fileprivate extension Character {
    
    func isValidSasCharacter() -> Bool {
        return self >= "0" && self <= "9"
    }
    
}

extension SasView {
    
    func setOwnSas(ownSas: Data) throws {
        guard let sas = String(data: ownSas, encoding: .utf8) else { throw Self.makeError(message: "Could not turn SAS into string") }
        guard sas.isValidSas(ofLength: expectedSasLength) else { throw Self.makeError(message: "Invalid SAS") }
        ownSasLabel.text = sas
        
    }
    
    func resetContactSas() {
        contactSasTextField.text = ""
        contactSasTextField.placeholder = String(repeating: "X", count: expectedSasLength)
        evaluateEnteredContactSasAndUpdateUI()
    }
    
    // Returns a SAS as a String iff it may be a valid SAS
    @discardableResult
    private func evaluateEnteredContactSasAndUpdateUI() -> String? {
        var sas: String? = nil
        doneButton.isEnabled = false
        if let text = contactSasTextField.text {
            if text.isValidSas(ofLength: expectedSasLength) {
                sas = text
                doneButton.isEnabled = true
            }
        }
        return sas
    }

}

// MARK: - UITextFieldDelegate

extension SasView: UITextFieldDelegate {
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        let NotificationType = MessengerInternalNotification.TextFieldDidBeginEditing.self
        let userInfo = [NotificationType.Key.textField: textField]
        NotificationCenter.default.post(name: NotificationType.name,
                                        object: nil,
                                        userInfo: userInfo)
        contactSasTextField.placeholder = ""
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        let NotificationType = MessengerInternalNotification.TextFieldDidEndEditing.self
        let userInfo = [NotificationType.Key.textField: textField]
        NotificationCenter.default.post(name: NotificationType.name,
                                        object: nil,
                                        userInfo: userInfo)

    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        
        defer {
            evaluateEnteredContactSasAndUpdateUI()
        }

        // Validate the string
        guard range.location >= 0 && range.location < expectedSasLength else { return false }
        guard string.isValidSas(ofLength: string.count) else { return false }

        return true
    }
    
    func textFieldDidChange(notification: Notification) {
        debugPrint(contactSasTextField.text ?? "Vide")
        evaluateEnteredContactSasAndUpdateUI()
    }
    
}
