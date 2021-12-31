/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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
import ObvEngine
import os.log

class BackupKeyVerifierViewController: UIViewController {

    /// If this is non-nil, we are restoring a backup. Otherwise, we are checking a backup key
    var backupFileURL: URL?
    
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var firstLineForBackupKey: UIStackView!
    @IBOutlet weak var secondLineForBackupKey: UIStackView!
    private var backupKeyFields = [UITextField]()
    private var separatorLabels = [UILabel]()
    private var notificationTokens = [NSObjectProtocol]()
    private var acceptableCharactersForKey = CharacterSet()
    @IBOutlet weak var forgotButton: UIButton!
    @IBOutlet weak var dismissButton: UIButton!
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var stackViewForVerificationButtons: UIStackView!
    
    @IBOutlet weak var statusReportView: ObvRoundedRectView!
    @IBOutlet weak var statusReportImage: UIImageView!
    @IBOutlet weak var statusReportTitle: UILabel!
    @IBOutlet weak var statusReportBody: UILabel!
    @IBOutlet weak var restoreNowButton: ObvButton!

    private var activeBackupTextField: UITextField?

    private var spinner: UIActivityIndicatorView?
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    
    private var backupRequestIdentifierToRestore: UUID?
    
    weak var delegate: BackupKeyVerifierViewControllerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        if backupFileURL == nil {
            title = Strings.titleForVerification
            let closeButton = UIBarButtonItem.forClosing(target: self, action: #selector(closeButtonTapped))
            self.navigationItem.setLeftBarButton(closeButton, animated: false)
        } else {
            title = Strings.titleForRestore
        }
        configure()
        registerForKeyboardNotifications()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Resize the font within the text fields for small screens
        if self.view.frame.width <= 320.0 {
            resetSeparatorLabelsAndBackupFieldsFontSize(to: BackupKeyTextField.smallFontsize)
        } else {
            resetSeparatorLabelsAndBackupFieldsFontSize(to: BackupKeyTextField.normalFontsize)
        }
    }
    
    
    private func resetSeparatorLabelsAndBackupFieldsFontSize(to size: CGFloat) {
        for separator in separatorLabels {
            separator.font = separator.font.withSize(size)
        }
        for backupKeyField in backupKeyFields {
            if let font = backupKeyField.font {
                backupKeyField.font? = font.withSize(size)
            }
        }
    }
    

    private func configure() {
        
        acceptableCharactersForKey = obvEngine.getAcceptableCharactersForBackupKeyString()
        
        for index in 0..<8 {
            let textField = BackupKeyTextField()
            textField.tag = index
            textField.delegate = self
            textField.autocapitalizationType = .allCharacters
            textField.autocorrectionType = .no
            backupKeyFields.append(textField)
            if index < 4 {
                firstLineForBackupKey.addArrangedSubview(textField)
                let separatorLabel = BackupKeyVerifierViewController.makeSeparatorLabel()
                separatorLabels.append(separatorLabel)
                firstLineForBackupKey.addArrangedSubview(separatorLabel)
            } else {
                secondLineForBackupKey.addArrangedSubview(textField)
                let separatorLabel = BackupKeyVerifierViewController.makeSeparatorLabel()
                separatorLabels.append(separatorLabel)
                secondLineForBackupKey.addArrangedSubview(separatorLabel)
            }
        }
        
        if let view = firstLineForBackupKey.arrangedSubviews.last {
            firstLineForBackupKey.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        if let view = secondLineForBackupKey.arrangedSubviews.last {
            secondLineForBackupKey.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        
        forgotButton.setTitle(Strings.forgotButtonTitle, for: .normal)
        dismissButton.setTitle(CommonString.Word.Cancel, for: .normal)
        if backupFileURL == nil {
            topLabel.text = Strings.topLabelTextForVerification
        } else {
            topLabel.text = Strings.topLabelTextForRestore
        }
        stopAndHideSpinner()

        statusReportView.backgroundColor = AppTheme.shared.colorScheme.secondarySystemBackground
        statusReportTitle.textColor = AppTheme.shared.colorScheme.secondaryLabel
        statusReportBody.textColor = AppTheme.shared.colorScheme.secondaryLabel

        hideStatusReport()
        
        if backupFileURL != nil {
            stackViewForVerificationButtons.isHidden = true
        }
        
        observeNotifications()
    }
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        backupKeyFields.first?.becomeFirstResponder()
    }
    
    
    private enum StatusReportType {
        case backupKeyVerificationFailed
        case backupKeyVerificationSucceded
        case fullBackupRecovered(backupRequestIdentifier: UUID, fullBackupDate: Date)
        case fullBackupCouldNotBeRecovered
    }
    
        
    private func showStatusReport(for status: StatusReportType) {
        assert(Thread.current == Thread.main)
        switch status {
        case .backupKeyVerificationFailed:
            if #available(iOS 13, *) {
                statusReportImage.image = UIImage(systemName: "exclamationmark.circle.fill")
                statusReportImage.tintColor = .red
            } else {
                statusReportImage.isHidden = true
            }
            statusReportTitle.text = Strings.backupKeyIncorrect
            statusReportBody.text = Strings.checkBackupKey
        case .backupKeyVerificationSucceded:
            if #available(iOS 13, *) {
                statusReportImage.image = UIImage(systemName: "checkmark.circle.fill")
                statusReportImage.tintColor = AppTheme.shared.colorScheme.systemFill
            } else {
                statusReportImage.isHidden = true
            }
            statusReportTitle.text = Strings.backupKeyVerified
            statusReportBody.text = ""
        case .fullBackupRecovered(fullBackupDate: _):
            if #available(iOS 13, *) {
                statusReportImage.image = UIImage(systemName: "checkmark.circle.fill")
                statusReportImage.tintColor = AppTheme.shared.colorScheme.systemFill
            } else {
                statusReportImage.isHidden = true
            }
            statusReportTitle.text = Strings.backupKeyVerified
            statusReportBody.text = Strings.youMayPRoceed
            restoreNowButton.setTitle(Strings.restoreThisBackup, for: .normal)
        case .fullBackupCouldNotBeRecovered:
            if #available(iOS 13, *) {
                statusReportImage.image = UIImage(systemName: "exclamationmark.circle.fill")
                statusReportImage.tintColor = AppTheme.shared.colorScheme.systemFill
            } else {
                statusReportImage.isHidden = true
            }
            statusReportTitle.text = Strings.backupKeyIncorrect
            statusReportBody.text = Strings.checkBackupKey
            restoreNowButton.setTitle(nil, for: .normal)
        }
        statusReportView.isHidden = false
        switch status {
        case .fullBackupRecovered:
            restoreNowButton.isHidden = false
        default:
            break
        }
    }
    
    
    private func hideStatusReport() {
        assert(Thread.current == Thread.main)
        guard !statusReportView.isHidden else { return }
        statusReportView.isHidden = true
        restoreNowButton.isHidden = true
    }
    
    private static func makeSeparatorLabel() -> UILabel {
        let label = UILabel()
        label.text = "-"
        label.textAlignment = .left
        label.font = BackupKeyTextField.fontForDigits
        return label
    }
    
    
    private func observeNotifications() {
        do {
            let token = NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: nil, queue: nil) { (notification) in
                let textField = notification.object as! UITextField
                self.textDidChangeNotification(textField: textField)
            }
            notificationTokens.append(token)
        }
    }

}


// MARK: - Dealing with the backup key text fields

extension BackupKeyVerifierViewController: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard backupKeyFields.contains(textField) else { return true }
        textField.resignFirstResponder()
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard backupKeyFields.contains(textField) else { return true }

        hideStatusReport()

        // Make sure all characters of the replacement string are acceptable
        
        if !string.isEmpty {
            let charset = CharacterSet(charactersIn: string)
            guard charset.isSubset(of: acceptableCharactersForKey) else {
                return false
            }
        }
        
        // Make sure the text field will not contain more than 4 characters
        
        guard let textFieldText = textField.text, let rangeOfTextToReplace = Range(range, in: textFieldText) else {
            return false
        }
        
        let substringToReplace = textFieldText[rangeOfTextToReplace]
        let textFieldCountAfterReplacement = textFieldText.count - substringToReplace.count + string.count

        if textFieldCountAfterReplacement < 5 {
            // This is typical
            return true
        } else {
            // In that case, the only acceptable situation is when all the fields are empty and we are pasting 32 characters in the first field.
            guard textField == backupKeyFields.first else { return false }
            guard textFieldCountAfterReplacement == 32 else { return false }
            tryPasteAllCharactersAtOnce(string: string)
            return false
        }

    }

    
    private func tryPasteAllCharactersAtOnce(string: String) {
        guard string.utf8.count == 32 else { return }
        for textField in backupKeyFields {
            guard textField.text == nil || textField.text?.isEmpty == true else { return }
        }
        let allStrings = string.byFour
        guard allStrings.count == backupKeyFields.count else { return }
        guard allStrings.count == 8 else { return }
        for i in 0..<8 {
            backupKeyFields[i].text = String(allStrings[i])
        }
        textDidChangeNotification(textField: backupKeyFields.first!)
    }
    
    private func textDidChangeNotification(textField: UITextField) {
        guard backupKeyFields.contains(textField) else { return }
        let log = self.log
        if let textFieldText = textField.text, textFieldText.count == 4 {
            let nextTag = textField.tag + 1
            if let nextTextField = backupKeyFields.filter({ $0.tag == nextTag }).first {
                nextTextField.becomeFirstResponder()
            }
        }
        if allBackupKeyTextFieldsAreFilled {
            // Create a string to pass to the engine
            let backupKeyString = backupKeyFields.map({ $0.text ?? "" }).joined()
            guard backupKeyString.count == 32 else { activateAllBackupKeyFields(); return }
            if let backupFileURL = self.backupFileURL {
                DispatchQueue(label: "Queue for reading backup data").async { [weak self] in
                    let backupData: Data
                    do {
                        backupData = try Data(contentsOf: backupFileURL)
                    } catch let error {
                        os_log("Could not read backup file: %{public}@", log: log, type: .fault, error.localizedDescription)
                        DispatchQueue.main.async {
                            let uiAlert = UIAlertController(title: Strings.couldNotReadBackupFile, message: nil, preferredStyle: .alert)
                            let okAction = UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: nil)
                            uiAlert.addAction(okAction)
                            self?.present(uiAlert, animated: true)
                        }
                        return
                    }
                    DispatchQueue.main.async {
                        self?.useEnteredBackupKey(backupKeyString, forDecryptingBackupData: backupData)
                    }
                }
            } else {
                testEnteredBackupKey(backupKeyString: backupKeyString)
            }
        }
    }

    
    private func testEnteredBackupKey(backupKeyString: String) {
        assert(Thread.current == Thread.main)
        deactivateAllBackupKeyFields()
        startAndShowSpinner()
        DispatchQueue(label: "Queue for testing backup string").async { [weak self] in
            do {
                try self?.obvEngine.verifyBackupKeyString(backupKeyString) { result in
                    ObvMessengerInternalNotification.displayedSnackBarShouldBeRefreshed.postOnDispatchQueue()
                    DispatchQueue.main.async {
                        switch result {
                        case .failure: self?.backupKeyWasTestedByEngine(success: false)
                        case .success: self?.backupKeyWasTestedByEngine(success: true)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.stopAndHideSpinner()
                    self?.activateAllBackupKeyFields()
                }
            }
        }
    }

    
    private func fullBackupWasRecoveredByEngine(backupRequestIdentifier: UUID, fullbackupDate: Date) {
        assert(Thread.current == Thread.main)
        stopAndHideSpinner()
        activateAllBackupKeyFields()
        showStatusReport(for: .fullBackupRecovered(backupRequestIdentifier: backupRequestIdentifier, fullBackupDate: fullbackupDate))
        backupRequestIdentifierToRestore = backupRequestIdentifier
    }
    
    
    private func fullBackupCouldNotBeRecoveredByEngine() {
        assert(Thread.current == Thread.main)
        stopAndHideSpinner()
        activateAllBackupKeyFields()
        showStatusReport(for: .fullBackupCouldNotBeRecovered)
    }
    
    private func backupKeyWasTestedByEngine(success: Bool) {
        assert(Thread.current == Thread.main)
        stopAndHideSpinner()
        activateAllBackupKeyFields()
        if success {
            showStatusReport(for: .backupKeyVerificationSucceded)
        } else {
            showStatusReport(for: .backupKeyVerificationFailed)
        }

    }
    
    
    private func useEnteredBackupKey(_ backupKeyString: String, forDecryptingBackupData backupData: Data) {
        assert(Thread.current == Thread.main)
        deactivateAllBackupKeyFields()
        startAndShowSpinner()
        DispatchQueue(label: "Queue for decrypting backup data").async { [weak self] in
            do {
                try self?.obvEngine.recoverBackupData(backupData, withBackupKey: backupKeyString) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .failure:
                            self?.fullBackupCouldNotBeRecoveredByEngine()
                        case .success(let (backupRequestIdentifier, backupDate)):
                            self?.fullBackupWasRecoveredByEngine(backupRequestIdentifier: backupRequestIdentifier, fullbackupDate: backupDate)
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.stopAndHideSpinner()
                    self?.activateAllBackupKeyFields()
                }
            }
        }
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        guard backupKeyFields.contains(textField) else { return }
        self.activeBackupTextField = textField
    }
    
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        guard backupKeyFields.contains(textField) else { return }
        self.activeBackupTextField = nil
    }

}

// MARK: Helpers

extension BackupKeyVerifierViewController {
    
    private var allBackupKeyTextFieldsAreFilled: Bool {
        for textField in backupKeyFields {
            guard let text = textField.text else { return false }
            guard text.count == 4 else { return false }
        }
        return true
    }

    private func deactivateAllBackupKeyFields() {
        assert(Thread.current == Thread.main)
        for textField in backupKeyFields {
            textField.isEnabled = false
        }
    }
    
    private func activateAllBackupKeyFields() {
        assert(Thread.current == Thread.main)
        for textField in backupKeyFields {
            textField.isEnabled = true
        }
    }
    
    func stopAndHideSpinner() {
        assert(Thread.current == Thread.main)
        if #available(iOS 13, *) {
            spinner?.stopAnimating()
            spinner?.isHidden = true
            spinner = nil
        }
    }
    
    func startAndShowSpinner() {
        assert(Thread.current == Thread.main)
        if #available(iOS 13, *) {
            spinner = UIActivityIndicatorView(style: .medium)
            spinner?.hidesWhenStopped = true
            spinner?.startAnimating()
            navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner!)
        }
    }
    
}

// MARK: - Forgot the backup key

extension BackupKeyVerifierViewController {
    
    @IBAction func forgotButtonTapped(_ sender: Any) {
        generateNewBackupKey(confirmed: false)
    }
    
    private func generateNewBackupKey(confirmed: Bool) {
        assert(Thread.current == Thread.main)
        if confirmed {
            let obvEngine = self.obvEngine
            self.navigationController?.dismiss(animated: true, completion: {
                obvEngine.generateNewBackupKey()
            })
        } else {
            let alert = UIAlertController(title: Strings.titleGenerateNewBackupKey,
                                          message: Strings.messageGenerateNewBackupKey,
                                          preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: Strings.actionGenerateNewBackupKey, style: .destructive, handler: { [weak self] (_) in
                self?.generateNewBackupKey(confirmed: true)
            }))
            alert.addAction(UIAlertAction(title: CommonString.Word.Cancel, style: .default))
            alert.popoverPresentationController?.sourceView = forgotButton
            present(alert, animated: true)
        }
    }
    
    @IBAction func dismissButtonTapped(_ sender: Any) {
        navigationController?.dismiss(animated: true)
    }
    
    @objc func closeButtonTapped() {
        navigationController?.dismiss(animated: true)
    }
    
    @IBAction func restoreNowButtonTapped(_ sender: Any) {
        guard let backupRequestIdentifierToRestore = backupRequestIdentifierToRestore else { assertionFailure(); return }
        DispatchQueue(label: "Queue for requesting a backup restore").async { [weak self] in
            self?.delegate?.userWantsToRestoreBackupIdentifiedByRequestUuid(backupRequestIdentifierToRestore)
        }
    }

}


// MARK: - Localization

extension BackupKeyVerifierViewController {
    
    struct Strings {
        
        static let titleForVerification = NSLocalizedString("Verify backup key", comment: "Title of the view allowing to verify a backup key")
        static let titleForRestore = NSLocalizedString("Enter backup key", comment: "Title of the view allowing to enter a backup key when restoring a backup")
        static let forgotButtonTitle = NSLocalizedString("Forgot your backup key?", comment: "Button title")
        static let topLabelTextForVerification = NSLocalizedString("Please enter all the characters of your backup key.", comment: "")
        static let topLabelTextForRestore = NSLocalizedString("Please enter the backup key that was presented to you when you configured backups.\n\nThis key is the only way to decrypt the backup. If you lost it, backup restoration is impossible.", comment: "Text displayed when entering a backup key in order to decrypt a backup.")
        static let backupKeyVerified = NSLocalizedString("The backup key is correct", comment: "Title of a card")
        static let youMayPRoceed = NSLocalizedString("You may proceed with the restoration.", comment: "Body of a card")
        static let restoreThisBackup = NSLocalizedString("Restore this backup", comment: "Button title")
        static let backupKeyIncorrect = NSLocalizedString("The backup key is incorrect", comment: "Title of a card")
        static let checkBackupKey = NSLocalizedString("Please check your backup key and try again.", comment: "Body of a card")
        static let titleGenerateNewBackupKey = NSLocalizedString("Generate new backup key?", comment: "Alert title")
        static let messageGenerateNewBackupKey = NSLocalizedString("Please note that generating a new backup key will invalidate all your previous backups. If you generate a new backup key, please create a fresh backup right afterwards.", comment: "Alert message")
        static let actionGenerateNewBackupKey = NSLocalizedString("Generate new backup key now", comment: "Action title")
        static let couldNotReadBackupFile = NSLocalizedString("Could not read backup file", comment: "Action title")
        
    }
    
}

protocol BackupKeyVerifierViewControllerDelegate: AnyObject {
    
    func userWantsToRestoreBackupIdentifiedByRequestUuid(_ requestUuid: UUID)
    
}


private final class BackupKeyTextField: UITextField {
    
    let padding = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
    
    static let normalFontsize: CGFloat = 24
    static let smallFontsize: CGFloat = 19

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        font = BackupKeyTextField.fontForDigits
        placeholder = "XXXX"
        smartInsertDeleteType = .no
        spellCheckingType = .no
    }
    
    fileprivate static let fontForDigits: UIFont = {
        let font: UIFont
        if let _font = UIFont(name: "Courier-Bold", size: BackupKeyTextField.normalFontsize) {
            font = _font
        } else {
            font = UIFont.preferredFont(forTextStyle: .largeTitle)
        }
        return UIFontMetrics(forTextStyle: .headline).scaledFont(for: font)
    }()

    override func textRect(forBounds bounds: CGRect) -> CGRect {
      return bounds.inset(by: padding)
    }
    
    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
      return bounds.inset(by: padding)
    }
    
    override func editingRect(forBounds bounds: CGRect) -> CGRect {
      return bounds.inset(by: padding)
    }

}


fileprivate extension Collection {
    var byFour: [SubSequence] {
        var startIndex = self.startIndex
        let count = self.count
        let n = count/4 + count % 4
        return (0..<n).map { _ in
            let endIndex = index(startIndex, offsetBy: 4, limitedBy: self.endIndex) ?? self.endIndex
            defer { startIndex = endIndex }
            return self[startIndex..<endIndex]
        }
    }
}


// MARK: - Handling keyboard

extension BackupKeyVerifierViewController {
    
    private func registerForKeyboardNotifications() {
        notificationTokens.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) { [weak self] (notification) in
            self?.keyboardWillShow(notification)
        })
        notificationTokens.append(NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil) { [weak self] (notification) in
            self?.keyboardWillHide(notification)
        })
    }
    
    
    private func keyboardWillShow(_ notification: Notification) {
        let kbdHeight = getKeyboardHeight(notification)
        let contentInsets = UIEdgeInsets(top: 0, left: 0, bottom: kbdHeight, right: 0)
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
        // If the active text field is visible on screen, do not scroll any further. Otherwise, scroll.
        guard let activeTextField = self.activeBackupTextField else { return }
        var aRect = self.view.frame
        aRect.size.height -= kbdHeight
        let bottomLeftCornerOfActiveTextField = activeTextField.convert(CGPoint(x: 0, y: activeTextField.bounds.height), to: view)
        if bottomLeftCornerOfActiveTextField.y > aRect.height {
            scrollView.scrollRectToVisible(activeTextField.frame, animated: true)
        }
    }
    
    
    private func keyboardWillHide(_ notification: Notification) {
        let contentInsets = UIEdgeInsets.zero
        scrollView.contentInset = contentInsets
        scrollView.scrollIndicatorInsets = contentInsets
    }
    
    
    private func getKeyboardHeight(_ notification: Notification) -> CGFloat {
        let userInfo = notification.userInfo!
        let kbSize = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! CGRect).size
        return kbSize.height
    }
    
    
}
