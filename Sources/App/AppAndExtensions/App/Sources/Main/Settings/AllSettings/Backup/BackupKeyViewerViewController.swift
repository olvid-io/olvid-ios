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
import ObvUI

protocol BackupKeyViewerViewControllerDelegate: AnyObject {
    @MainActor func backupKeyViewerViewControllerDidDisappear()
}

/// This view controller is presented when a new backup is generated. It allows to see it once (and only once).
final class BackupKeyViewerViewController: UIViewController {

    var backupKeyString: String!
    
    @IBOutlet weak var topLabel: UILabel!
    @IBOutlet weak var bottomLabel: UILabel!
    @IBOutlet weak var firstLineForBackupKey: UIStackView!
    @IBOutlet weak var secondLineForBackupKey: UIStackView!
    @IBOutlet weak var keyCopiedButton: ObvImageButton!
    
    weak var delegate: BackupKeyViewerViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        assert(backupKeyString.count == 32)
        title = Strings.title
        configure()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        delegate?.backupKeyViewerViewControllerDidDisappear()
    }

    private func backupKeyStringElement(index: Int) -> String? {
        guard index >= 0 && index < 8 else {
            assertionFailure()
            return nil
        }
        guard backupKeyString.count == 32 else {
            assertionFailure()
            return nil
        }
        let start = backupKeyString.index(backupKeyString.startIndex, offsetBy: 4*index)
        let end = backupKeyString.index(backupKeyString.startIndex, offsetBy: 4*(index+1))
        return String(backupKeyString[start..<end])
    }
    
    private let fontForDigits: UIFont = {
        let font: UIFont
        if let _font = UIFont(name: "Courier-Bold", size: UIFont.labelFontSize) {
            font = _font
        } else {
            font = UIFont.preferredFont(forTextStyle: .body)
        }
        return UIFontMetrics(forTextStyle: .headline).scaledFont(for: font)
    }()
    
    private func configure() {
        
        topLabel.text = Strings.topLabelText
        bottomLabel.text = Strings.bottomLabelText
        keyCopiedButton.setTitle(Strings.buttonTitle, for: .normal)
        
        for index in 0..<8 {
            guard let stringElement = backupKeyStringElement(index: index) else {
                assertionFailure()
                continue
            }
            let label = UILabel()
            label.font = fontForDigits
            label.adjustsFontForContentSizeCategory = true
            label.adjustsFontSizeToFitWidth = true
            label.text = stringElement
            if index < 4 {
                firstLineForBackupKey.addArrangedSubview(label)
            } else {
                secondLineForBackupKey.addArrangedSubview(label)
            }
        }
        
        // In dev mode, allow to copy the key
        if ObvMessengerConstants.developmentMode {
            let copyButton = UIBarButtonItem(image: UIImage(systemName: "doc.on.doc"), style: .plain, target: self, action: #selector(copyToKeyToClipboardButtonTapped))
            self.navigationItem.setRightBarButton(copyButton, animated: false)
        }
        
    }
    
    
    @objc func copyToKeyToClipboardButtonTapped() {
        UIPasteboard.general.string = backupKeyString
    }
    
    
    @IBAction func keyCopiedButtonTapped(_ sender: Any) {
        self.navigationController?.dismiss(animated: true)
    }
    
}


// MARK: - Localization

extension BackupKeyViewerViewController {
    
    struct Strings {
        
        static let title = NSLocalizedString("New backup key", comment: "Title of the view showing a new backup key")
        static let topLabelText = NSLocalizedString("The backup key below will be used to encrypt all your Olvid backups. Please keep it in a safe place.\nOlvid will periodically check you are able to enter this key to ensure you do note lose access to your backups.", comment: "Explanation shown on on top of a backup key shown to the user.")
        static let bottomLabelText = NSLocalizedString("This is the only time this key will be displayed. If you lose it, you will need to generate a new one.", comment: "Explanation shown below a backup key shown to the user.")
        static let buttonTitle = NSLocalizedString("I have copied the key", comment: "Button title shown to the user")
        
    }
    
}
