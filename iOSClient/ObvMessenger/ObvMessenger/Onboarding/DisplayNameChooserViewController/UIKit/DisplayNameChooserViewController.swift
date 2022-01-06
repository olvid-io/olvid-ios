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

final class DisplayNameChooserViewController: UIViewController {
    
    // Views
    
    @IBOutlet weak var tableView: UITableView!

    
    // Properties
    
    private var displaynameMaker: DisplaynameStruct
    private var initialDisplayNameMaker: DisplaynameStruct
    private let serverAndAPIKey: ServerAndAPIKey?
    private var notificationTokens = [NSObjectProtocol]()
    private weak var firstnameTextField: UITextField?
    private weak var lastnameTextField: UITextField?
    private weak var companyTextField: UITextField?
    private weak var positionTextField: UITextField?
    private var saveButton: UIBarButtonItem!
    private var activeTextField: UITextField?
    
    private static let typicalDurationKbdAnimation: TimeInterval = 0.25
    private let animatorForTableViewContent = UIViewPropertyAnimator(duration: typicalDurationKbdAnimation*2.3, dampingRatio: 0.65)

    private var completionHandlerOnSave: (DisplaynameStruct) -> Void
    
    // Initializers
    
    init(displaynameMaker: DisplaynameStruct, completionHandlerOnSave: @escaping (DisplaynameStruct) -> Void, serverAndAPIKey: ServerAndAPIKey?) {
        self.displaynameMaker = displaynameMaker
        self.initialDisplayNameMaker = displaynameMaker
        self.completionHandlerOnSave = completionHandlerOnSave
        self.serverAndAPIKey = serverAndAPIKey
        super.init(nibName: nil, bundle: nil)
        
        let token = NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: nil, queue: nil) { (notification) in
            let textField = notification.object as! UITextField
            self.textDidChangeNotification(textField: textField)
        }
        notificationTokens.append(token)

        registerForKeyboardNotifications()
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    

}


// MARK: - View controller lifecycle

extension DisplayNameChooserViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        self.tableView.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        
        tableView.register(UINib(nibName: ObvSimpleTextFieldTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: ObvSimpleTextFieldTableViewCell.identifier)
        tableView.register(UINib(nibName: ObvSimpleMessageTableViewCell.nibName, bundle: nil), forCellReuseIdentifier: ObvSimpleMessageTableViewCell.identifier)
        tableView.dataSource = self
        tableView.alwaysBounceVertical = true
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 30.0
        tableView.separatorColor = UIColor.clear
        tableView.keyboardDismissMode = .interactive
        extendedLayoutIncludesOpaqueBars = true
        title = Strings.titleMyId
        saveButton = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveButtonTapped))
        saveButton.isEnabled = false
        if let initialFirstName = initialDisplayNameMaker.firstName, !initialFirstName.isEmpty {
            // This is a hack
            saveButton.isEnabled = true
        }
        navigationItem.setRightBarButton(saveButton, animated: false)
        setTableViewBottomInset(to: 0.0)
        
        // Set self as the delegate of the `presentationController`. This allows to present a confirmation dialog if the user dismisses this view controller after editing a field.
        if self.navigationController?.presentationController != nil && self.navigationController?.presentationController?.delegate == nil {
            self.navigationController?.presentationController?.delegate = self
        } else if self.presentationController != nil && self.presentationController?.delegate == nil {
            self.presentationController?.delegate = self
        }
    }
    
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension DisplayNameChooserViewController: UIAdaptivePresentationControllerDelegate {
    
    func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        confirmDismiss()
    }
    
    
    private func confirmDismiss() {
        
        let alert = UIAlertController(title: nil, message: nil, preferredStyleForTraitCollection: self.traitCollection)
        let actionSave = UIAlertAction(title: CommonString.AlertButton.saveChanges, style: .default) { [weak self] (_) in
            self?.saveButtonTapped()
        }
        let actionDiscard = UIAlertAction(title: CommonString.AlertButton.discardChanges, style: .destructive) { (_) in
            self.dismiss(animated: true)
        }
        alert.addAction(actionSave)
        alert.addAction(actionDiscard)
        self.present(alert, animated: true)
        
    }
    
}


// MARK: - UITableViewDataSource

extension DisplayNameChooserViewController: UITableViewDataSource {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        if serverAndAPIKey == nil {
            return 2
        } else {
            return 2 // Set to 3 in order to display the API Key, 2 to hide it.
        }
    }
    
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 4 // Text fields for name
        case 2: return 2 // Server settings
        default: return 0
        }
    }
    
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return nil
        case 1:
            return Strings.sectionTitleNameEditor
        case 2:
            return Strings.sectionTitleSeverSettings
        default:
            return ""
        }
    }

    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: ObvSimpleMessageTableViewCell.identifier, for: indexPath) as! ObvSimpleMessageTableViewCell
            cell.selectionStyle = .none
            cell.label.text = Strings.disclaimer
            return cell
        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: ObvSimpleTextFieldTableViewCell.identifier, for: indexPath) as! ObvSimpleTextFieldTableViewCell
            cell.selectionStyle = .none
            switch indexPath.row {
            case 0:
                cell.label.text = Strings.firstNameLabel
                cell.textField.placeholder = Strings.mandatory
                cell.textField.text = displaynameMaker.firstName
                cell.textField.textContentType = .givenName
                cell.textField.autocapitalizationType = .words
                cell.textField.delegate = self
                firstnameTextField = cell.textField
            case 1:
                cell.label.text = Strings.lastNameLabel
                cell.textField.placeholder = Strings.mandatory
                cell.textField.text = displaynameMaker.lastName
                cell.textField.textContentType = .familyName
                cell.textField.autocapitalizationType = .words
                cell.textField.delegate = self
                lastnameTextField = cell.textField
            case 2:
                cell.label.text = Strings.companyLabel
                cell.textField.placeholder = Strings.optional
                cell.textField?.text = displaynameMaker.company
                cell.textField.textContentType = .organizationName
                cell.textField.autocapitalizationType = .words
                cell.textField.delegate = self
                companyTextField = cell.textField
            case 3:
                cell.label.text = Strings.positionLabel
                cell.textField.placeholder = Strings.optional
                cell.textField?.text = displaynameMaker.position
                cell.textField.textContentType = .jobTitle
                cell.textField.autocapitalizationType = .words
                cell.textField.delegate = self
                positionTextField = cell.textField
            default:
                break
            }
            cell.textField.tag = indexPath.row
            return cell
        case 2:
            let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
            switch indexPath.row {
            case 0:
                cell.textLabel?.text = Strings.apiKey
                cell.detailTextLabel?.text = serverAndAPIKey?.apiKey.uuidString
                cell.adjustFontSizeInSecondLabel()
                cell.selectionStyle = .none
            case 1:
                cell.textLabel?.text = Strings.urlString
                cell.detailTextLabel?.text = serverAndAPIKey?.server.absoluteString
                cell.selectionStyle = .none
            default:
                break
            }
            return cell
        default:
            return UITableViewCell()
        }
    }
}


// MARK: - Reacting to text fields changes

extension DisplayNameChooserViewController {

    private func textDidChangeNotification(textField: UITextField) {
        switch textField {
        case firstnameTextField:
            do {
                displaynameMaker = try displaynameMaker.settingFirstName(firstName: firstnameTextField?.text)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        case lastnameTextField:
            do {
                displaynameMaker = try displaynameMaker.settingLastName(lastName: lastnameTextField?.text)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        case companyTextField:
            do {
                displaynameMaker = try displaynameMaker.settingCompany(company: companyTextField?.text)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        case positionTextField:
            do {
                displaynameMaker = try displaynameMaker.settingPosition(position: positionTextField?.text)
            } catch {
                assertionFailure(error.localizedDescription)
            }
        default:
            break
        }
        saveButton.isEnabled = displaynameMaker.isValid
        if #available(iOS 13.0, *) {
            isModalInPresentation = (displaynameMaker != initialDisplayNameMaker)
            debugPrint("isModalInPresentation: \(isModalInPresentation)")
        }
    }
    
    
    @objc func saveButtonTapped() {
        guard displaynameMaker.isValid else { return }
        self.completionHandlerOnSave(self.displaynameMaker)
    }

}

private extension UITableViewCell {
    
    // This clearly is a hack, sufficient for now
    func adjustFontSizeInSecondLabel() {
        guard let subviews = self.subviews.first?.subviews else { return }
        guard subviews.count >= 2 else { return }
        guard let label = subviews[1] as? UILabel else { return }
        label.minimumScaleFactor = 0.3
        label.adjustsFontSizeToFitWidth = true
    }
    
}


// MARK: - Handling keyboard

extension DisplayNameChooserViewController {
    
    private func registerForKeyboardNotifications() {
        do {
            let token = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) { [weak self] (notification) in
                self?.keyboardWillShow(notification)
            }
            notificationTokens.append(token)
        }
        
        do {
            let token = NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil) { [weak self] (notification) in
                self?.keyboardWillHide(notification)
            }
            notificationTokens.append(token)
        }
    }
    
    
    private func keyboardWillShow(_ notification: Notification) {
        
        defer {
            if animatorForTableViewContent.state != .active {
                animatorForTableViewContent.startAnimation()
            }
        }

        let kbdHeight = getKeyboardHeight(notification)
        let tabbarHeight = tabBarController?.tabBar.frame.height ?? 0.0
        
        guard let activeTextField = self.activeTextField else { return }
        guard let activeCell = getCellCorrespondingToActiveTextField() else { return }
        
        // If the active text field is visible on screen, do not scroll any further. Otherwise, scroll.
        
        var aRect = self.view.frame
        aRect.size.height -= kbdHeight
        let bottomLeftCornerOfActiveTextField = activeTextField.convert(CGPoint(x: 0, y: activeTextField.bounds.height), to: view)
        let doScrollAfterSettingTheCollectionViewBottomInset = !aRect.contains(bottomLeftCornerOfActiveTextField)
        
        setTableViewBottomInset(to: kbdHeight - tabbarHeight)
        
        guard doScrollAfterSettingTheCollectionViewBottomInset else { return }
        
        let cellOrigin = activeCell.convert(CGPoint.zero, to: self.tableView)
        let cellHeight = activeCell.frame.height
        let collectionViewHeight = tableView.bounds.height
        let newY = cellOrigin.y + cellHeight - collectionViewHeight + kbdHeight
        let newContentOffset = CGPoint(x: tableView.contentOffset.x,
                                       y: max(0, newY))
        animatorForTableViewContent.addAnimations { [weak self] in
            self?.tableView.contentOffset = newContentOffset
        }
        
    }
    
    
    private func keyboardWillHide(_ notification: Notification) {
        
        defer {
            if animatorForTableViewContent.state != .active {
                animatorForTableViewContent.startAnimation()
            }
        }
        
        animatorForTableViewContent.addAnimations { [weak self] in
            self?.setTableViewBottomInset(to: 0.0)
        }

    }
    
    
    private func getKeyboardHeight(_ notification: Notification) -> CGFloat {
        let userInfo = notification.userInfo!
        let kbSize = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as! CGRect).size
        return kbSize.height
    }

    
    private func getCellCorrespondingToActiveTextField() -> UITableViewCell? {
        guard let activeTextField = self.activeTextField else { return nil }
        var currentSuperView = activeTextField.superview
        while currentSuperView != nil {
            if currentSuperView! is UITableViewCell {
                return (currentSuperView! as! UITableViewCell)
            } else {
                currentSuperView = currentSuperView!.superview
            }
        }
        return nil
    }

    
    private func setTableViewBottomInset(to bottom: CGFloat) {
        let topInset: CGFloat
        if #available(iOS 13, *) {
            topInset = 35.0
        } else {
            topInset = 0.0
        }
        tableView?.contentInset = UIEdgeInsets(top: topInset,
                                               left: tableView.contentInset.left,
                                               bottom: bottom,
                                               right: tableView.contentInset.right)
        tableView?.scrollIndicatorInsets = UIEdgeInsets(top: topInset,
                                                        left: tableView.scrollIndicatorInsets.left,
                                                        bottom: bottom,
                                                        right: tableView.scrollIndicatorInsets.right)
        
    }

}


extension DisplayNameChooserViewController: UITextFieldDelegate {
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        self.activeTextField = textField
    }
    
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        self.activeTextField = nil
    }
    
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        // Try to find next responder
        if let nextField = tableView.viewWithTag(textField.tag + 1) as? UITextField {
            nextField.becomeFirstResponder()
        } else {
            // Not found, so remove keyboard.
            textField.resignFirstResponder()
        }
        // Do not add a line break
        return false
    }

}
