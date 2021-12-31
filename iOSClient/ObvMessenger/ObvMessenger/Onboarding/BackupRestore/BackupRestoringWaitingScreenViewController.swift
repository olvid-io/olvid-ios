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

class BackupRestoringWaitingScreenViewController: UIViewController {

    @IBOutlet weak var mainLabel: UILabel!
    @IBOutlet weak var tryAgainButton: UIButton!
    @IBOutlet weak var stackView: UIStackView!
    private let spinner: UIActivityIndicatorView = {
        if #available(iOS 13, *) {
            return UIActivityIndicatorView(style: .medium)
        } else {
            return UIActivityIndicatorView(style: .gray)
        }
    }()
    
    private var restoreFailed = false
    var backupRequestUuid: UUID?
    private var viewDidLoadWasCalled = false
    private var notificationTokens = [NSObjectProtocol]()
    weak var delegate: BackupRestoringWaitingScreenViewControllerDelegate?

    override func viewDidLoad() {
        super.viewDidLoad()
        defer { viewDidLoadWasCalled = true }
        setup()
    }
    
    private func setup() {
        stackView.insertArrangedSubview(spinner, at: 1)
        tryAgainButton.setTitle(Strings.tryAgain, for: .normal)
        mainLabel.text = restoreFailed ? Strings.restoreFailed : Strings.restoringBackup
        spinner.isHidden = restoreFailed
        if !restoreFailed {
            spinner.startAnimating()
        }
        tryAgainButton.isHidden = !restoreFailed
    }
    
    func setRestoreFailed() {
        assert(Thread.main == Thread.main)
        restoreFailed = true
        guard viewDidLoadWasCalled else { return }
        refresh()
    }
    
    private func refresh() {
        assert(viewDidLoadWasCalled)
        let restoreFailed = self.restoreFailed
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.mainLabel.text = restoreFailed ? Strings.restoreFailed : Strings.restoringBackup
            self?.spinner.isHidden = restoreFailed
            self?.tryAgainButton.isHidden = !restoreFailed
        }
    }

    @IBAction func tryAgainButtonTapped(_ sender: Any) {
        delegate?.userWantsToStartOnboardingFromScratch()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
}


extension BackupRestoringWaitingScreenViewController {
    private struct Strings {
        static let restoringBackup = NSLocalizedString("RESTORING_BACKUP_PLEASE_WAIT", comment: "Title centered on screen")
        static let restoreFailed = NSLocalizedString("Restore failed 🥺", comment: "Body displayed when a backup restore failed")
        static let tryAgain = NSLocalizedString("Try again", comment: "Button title")
    }
}


protocol BackupRestoringWaitingScreenViewControllerDelegate: AnyObject {
    func userWantsToStartOnboardingFromScratch()
}
