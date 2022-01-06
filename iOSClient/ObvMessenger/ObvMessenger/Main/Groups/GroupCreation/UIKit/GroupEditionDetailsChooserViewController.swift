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
import ObvEngine


final class GroupEditionDetailsChooserViewController: UIViewController {
    
    // Views
    
    private let stackView = UIStackView()
    private let groupNameLabel = UILabel()
    private let groupNameTextField = ObvTextField()
    private let groupDescriptionLabel = UILabel()
    private let groupDescriptionTextField = ObvTextField()
    
    // Vars
    
    let ownedCryptoId: ObvCryptoId
    private var observationTokens = [NSObjectProtocol]()

    weak var delegate: GroupEditionDetailsChooserViewControllerDelegate?
    
    // Initializer
    
    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func set(groupName: String, groupDescription: String?) {
        self.groupNameTextField.text = groupName
        self.groupDescriptionTextField.text = groupDescription
    }
    
}


// MARK: - View Controller Lifecycle

extension GroupEditionDetailsChooserViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        listenToTextDidChangeNotifications()
        setup()
    }
    
    
    private func setup() {
        
        groupNameLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        groupNameLabel.textColor = AppTheme.shared.colorScheme.label
        groupNameLabel.text = Strings.groupNameTitle
        
        groupNameTextField.font = UIFont.preferredFont(forTextStyle: .title2)
        groupNameTextField.placeholder = Strings.groupNamePlaceholder
        groupNameTextField.autocapitalizationType = .sentences
        groupNameTextField.textColor = AppTheme.shared.colorScheme.secondaryLabel
        groupNameTextField.delegate = self
        
        groupDescriptionLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        groupDescriptionLabel.textColor = AppTheme.shared.colorScheme.label
        groupDescriptionLabel.text = Strings.groupDescriptionTitle

        groupDescriptionTextField.font = UIFont.preferredFont(forTextStyle: .title2)
        groupDescriptionTextField.placeholder = Strings.groupDescriptionPlaceholder
        groupDescriptionTextField.autocapitalizationType = .sentences
        groupDescriptionTextField.textColor = AppTheme.shared.colorScheme.secondaryLabel
        groupDescriptionTextField.delegate = self

        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.distribution = .fill
        stackView.addArrangedSubview(groupNameLabel)
        stackView.addArrangedSubview(groupNameTextField)
        stackView.addArrangedSubview(groupDescriptionLabel)
        stackView.addArrangedSubview(groupDescriptionTextField)
        stackView.spacing = 16
        stackView.setCustomSpacing(stackView.spacing*2, after: groupNameTextField)
        self.view.addSubview(stackView)
        
        self.view.backgroundColor = AppTheme.shared.colorScheme.systemBackground
        
        setupConstraints()
    }
    
    
    private func setupConstraints() {
        let margins = view.layoutMarginsGuide
        let constraints = [
            stackView.topAnchor.constraint(equalTo: margins.topAnchor, constant: 16),
            stackView.leadingAnchor.constraint(equalTo: self.view.leadingAnchor, constant: 16),
            stackView.trailingAnchor.constraint(equalTo: self.view.trailingAnchor, constant: -16)
        ]
        NSLayoutConstraint.activate(constraints)
    }
    
}


// MARK: - UITextFieldDelegate

extension GroupEditionDetailsChooserViewController: UITextFieldDelegate {
    
    func listenToTextDidChangeNotifications() {
        do {
            let token = NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: groupNameTextField, queue: nil) { [weak self] (notification) in
                guard let _self = self else { return }
                let groupName = _self.groupNameTextField.text
                let groupDescription = _self.groupDescriptionTextField.text
                // Do not deal with photo edtion
                _self.delegate?.groupDescriptionDidChange(groupName: groupName, groupDescription: groupDescription, photoURL: nil)
            }
            observationTokens.append(token)
        }
        do {
            let token = NotificationCenter.default.addObserver(forName: UITextField.textDidChangeNotification, object: groupDescriptionTextField, queue: nil) { [weak self] (notification) in
                guard let _self = self else { return }
                let groupName = _self.groupNameTextField.text
                let groupDescription = _self.groupDescriptionTextField.text
                // Do not deal with photo edtion
                _self.delegate?.groupDescriptionDidChange(groupName: groupName, groupDescription: groupDescription, photoURL: nil)
            }
            observationTokens.append(token)
        }

    }
    
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == groupNameTextField {
            groupDescriptionTextField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return false
    }

}


private extension GroupEditionDetailsChooserViewController {
    
    struct Strings {
        static let groupNameTitle = NSLocalizedString("Group name:", comment: "Title group name text field")
        static let groupNamePlaceholder = NSLocalizedString("Type a discussion group name...", comment: "Placeholder for group name")
        static let groupDescriptionTitle = NSLocalizedString("Group description:", comment: "Title group description text field")
        static let groupDescriptionPlaceholder = NSLocalizedString("Optional description...", comment: "Placeholder for group name")
    }
    
}
