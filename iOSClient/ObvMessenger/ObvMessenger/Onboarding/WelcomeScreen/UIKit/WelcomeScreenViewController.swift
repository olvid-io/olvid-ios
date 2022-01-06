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

class WelcomeScreenViewController: UIViewController {

    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var firstParagraphLabel: UILabel!
    @IBOutlet weak var secondParagraphLabel: UILabel!
    
    @IBOutlet weak var restoreBackupButton: UIButton!
    @IBOutlet weak var continueAsNewUserButton: UIButton!
        
    weak var delegate: WelcomeScrenViewControllerDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        configure()
                
    }
    
    private func configure() {
        
        titleLabel.text = Strings.title
        firstParagraphLabel.text = Strings.firstParagraph
        secondParagraphLabel.text = Strings.secondParagraph
        restoreBackupButton.setTitle(CommonString.restoreBackupTitle, for: .normal)
        continueAsNewUserButton.setTitle(Strings.continueAsNewUserButtonTitle, for: .normal)
        
        if #available(iOS 13, *) {
            titleLabel.textColor = DynamicColor.forText
            firstParagraphLabel.textColor = DynamicColor.forText
            secondParagraphLabel.textColor = DynamicColor.forText
            restoreBackupButton.setTitleColor(DynamicColor.forText, for: .normal)
            (continueAsNewUserButton as? ObvButton)?.preferredBackgroundColor = DynamicColor.forObvButtonBackground
            (continueAsNewUserButton as? ObvButton)?.preferredTitleColor = DynamicColor.forObvButtonTitle
        } else {
            titleLabel.textColor = Color.forText
            firstParagraphLabel.textColor = Color.forText
            secondParagraphLabel.textColor = Color.forText
            restoreBackupButton.setTitleColor(Color.forText, for: .normal)
            (continueAsNewUserButton as? ObvButton)?.preferredBackgroundColor = .white
            (continueAsNewUserButton as? ObvButton)?.preferredTitleColor = .black
        }
        
        
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    @IBAction func restoreBackupButtonTapped(_ sender: Any) {
        delegate?.userWantsToRestoreBackup()
    }
    
    @IBAction func continueAsNewUserButtonTapped(_ sender: Any) {
        delegate?.userWantsToContinueAsNewUser()
    }
    
}


@available(iOS 13, *)
extension WelcomeScreenViewController {
    
    private struct DynamicColor {
        static let forText = UIColor { (traitCollection: UITraitCollection) -> UIColor in
            if traitCollection.userInterfaceStyle == .dark {
                return AppTheme.shared.colorScheme.label
            } else {
                return .white
            }
        }
        static let forObvButtonBackground = UIColor { (traitCollection: UITraitCollection) -> UIColor in
            if traitCollection.userInterfaceStyle == .dark {
                return AppTheme.shared.colorScheme.obvYellow
            } else {
                return .white
            }
        }
        static let forObvButtonTitle = UIColor { (traitCollection: UITraitCollection) -> UIColor in
            if traitCollection.userInterfaceStyle == .dark {
                return .white
            } else {
                return AppTheme.shared.colorScheme.olvidLight
            }
        }
    }

}


extension WelcomeScreenViewController {
    
    private struct Color {
        static let forText = UIColor.white
    }
    
}


extension WelcomeScreenViewController {
    
    private struct Strings {
        
        static let title = NSLocalizedString("Welcome to Olvid!", comment: "Title of the Welcome screen view")
        static let firstParagraph = NSLocalizedString("If you are a new Olvid user, simply click Continue as a new user below.", comment: "First paragraph of the welcome screen")
        static let secondParagraph = NSLocalizedString("If you already used Olvid and want to restore your identity and contacts from a backup, click Restore a backup", comment: "Second paragraph of the welcome screen")
        static let continueAsNewUserButtonTitle = NSLocalizedString("Continue as a new user", comment: "Button title")

    }
    
}


protocol WelcomeScrenViewControllerDelegate: AnyObject {
    
    func userWantsToContinueAsNewUser()
    func userWantsToRestoreBackup()
    
}
