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

class BackupRestoreViewController: UIViewController {

    @IBOutlet weak var mainStackView: UIStackView!
    @IBOutlet weak var firstParagraphLabel: UILabel!
    @IBOutlet weak var secondParagraphLabel: UILabel!
    @IBOutlet weak var thirdParagraphLabel: UILabel!
    
    @IBOutlet weak var fromFileButton: ObvImageButton!
    @IBOutlet weak var fromCloudButton: ObvImageButton!
    
    @IBOutlet weak var backupFileSelectedRoundedView: ObvRoundedRectView!
    @IBOutlet weak var backupFileTitleLabel: UILabel!
    @IBOutlet weak var backupFileBodyLabel: UILabel!
    
    @IBOutlet weak var proceedButton: ObvButton!
    
    weak var delegate: BackupRestoreViewControllerDelegate?
    
    private var backupFileUrl: URL?
    
    private var spinner: UIActivityIndicatorView = {
        if #available(iOS 13, *) {
            return UIActivityIndicatorView(style: .medium)
        } else {
            return UIActivityIndicatorView(style: .gray)
        }
    }()
    
    private let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .short
        df.dateStyle = .short
        return df
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Restore
        configure()
    }

    private func configure() {
        firstParagraphLabel.text = Strings.firstParagraph
        secondParagraphLabel.text = Strings.secondParagraph
        thirdParagraphLabel.text = Strings.thirdParagraph
        fromFileButton.setTitle(Strings.fromFile, for: .normal)
        fromCloudButton.setTitle(Strings.fromCloud, for: .normal)
        if #available(iOS 13, *) {
            fromFileButton.setImage(UIImage(systemName: "folder.fill"), for: .normal)
            fromCloudButton.setImage(UIImage(systemName: "cloud.fill"), for: .normal)
        }
        backupFileSelectedRoundedView.backgroundColor = AppTheme.shared.colorScheme.secondarySystemBackground
        backupFileTitleLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        backupFileBodyLabel.textColor = AppTheme.shared.colorScheme.secondaryLabel
        backupFileTitleLabel.text = Strings.backupFileSelected
        backupFileBodyLabel.text = nil
        proceedButton.setTitle(Strings.proceedButtonTitle, for: .normal)
        backupFileSelectedRoundedView.isHidden = true
        proceedButton.isHidden = true
    }
    
    @IBAction func fromFileButtonTapped(_ sender: Any) {
        backupFileUrl = nil
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.backupFileSelectedRoundedView.isHidden = true
            self?.proceedButton.isHidden = true
        }
        delegate?.userWantsToRestoreBackupFromFileLegacy()
    }
    
    @IBAction func fromCloudButtonTapped(_ sender: Any) {
        backupFileUrl = nil
        startSpinner()
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.backupFileSelectedRoundedView.isHidden = true
            self?.proceedButton.isHidden = true
            self?.fromFileButton.isEnabled = false
            self?.fromCloudButton.isEnabled = false
        }
        delegate?.userWantToRestoreBackupFromCloudLegacy()
    }
    
    
    private func resetUI() {
        assert(Thread.current == Thread.main)
        stopSpinner()
        UIView.animate(withDuration: 0.3) { [weak self] in
            self?.backupFileSelectedRoundedView.isHidden = true
            self?.proceedButton.isHidden = true
            self?.fromFileButton.isEnabled = true
            self?.fromCloudButton.isEnabled = true
        }
    }
    
    
    func backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: CloudFailureReason) {
        DispatchQueue.main.async { [weak self] in
            let alert: UIAlertController
            switch cloudFailureReason {
            case .icloudAccountStatusIsNotAvailable:
                alert = UIAlertController(title: Strings.titleSignIn,
                                          message: Strings.messageSignIn,
                                          preferredStyle: .alert)
            case .couldNotRetrieveEncryptedBackupFile:
                alert = UIAlertController(title: Strings.titleUnexpectedCloudKitRecord,
                                          message: Strings.messageCouldNotRetrieveEncryptedBackupFile,
                                          preferredStyle: .alert)
            case .couldNotRetrieveCreationDate:
                alert = UIAlertController(title: Strings.titleUnexpectedCloudKitRecord,
                                          message: Strings.messageCouldNotRetrieveCreationDate,
                                          preferredStyle: .alert)
            case .iCloudError(description: let description):
                alert = UIAlertController(title: Strings.titleCloudKitError,
                                          message: description,
                                          preferredStyle: .alert)
            }
            let action = UIAlertAction(title: CommonString.Word.Ok, style: .default, handler: { (_) in self?.resetUI() })
            alert.addAction(action)
            self?.present(alert, animated: true)
        }
    }
    
    func backupFileSelected(atURL url: URL, creationDate: Date? = nil) {
        assert(Thread.current == Thread.main)
        backupFileUrl = url
        if let creationDate = creationDate {
            backupFileBodyLabel.text = Strings.backupCreationDate(dateFormater.string(from: creationDate))
        } else {
            backupFileBodyLabel.text = url.lastPathComponent
        }
        UIView.showInStackView(views: [backupFileSelectedRoundedView, proceedButton])
        stopSpinner()
    }
    
    func noMoreCloudBackupToFetch() {
        guard backupFileUrl == nil else { return }
        DispatchQueue.main.async { [weak self] in
            let alert = UIAlertController(title: Strings.titleNoBackupFileInCloud,
                                          message: Strings.messageNoBackupFileInCloud,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
            self?.present(alert, animated: true, completion: {
                UIView.animate(withDuration: 0.3) {
                    self?.stopSpinner()
                    self?.fromFileButton.isEnabled = true
                    self?.fromCloudButton.isEnabled = true
                }
            })
        }
    }
    
    @IBAction func proceedButtonTapped(_ sender: Any) {
        guard let backupFileUrl = self.backupFileUrl else { assertionFailure(); return }
        delegate?.proceedWithBackupFileLegacy(atUrl: backupFileUrl)
    }
    
    
    private func startSpinner() {
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: spinner)
        spinner.startAnimating()
    }
    
    private func stopSpinner() {
        spinner.stopAnimating()
        navigationItem.rightBarButtonItem = nil
    }
    
}


extension BackupRestoreViewController {
    
    fileprivate struct Strings {
        static let firstParagraph = NSLocalizedString("Please choose the location of the backup file you wish to restore.", comment: "BackupRestoreViewController first paragraph")
        static let secondParagraph = NSLocalizedString("Choose From a file to pick a backup file create from a manual backup.", comment: "BackupRestoreViewController second paragraph")
        static let thirdParagraph = NSLocalizedString("Choose From the cloud to select an account used for automatic backups.", comment: "BackupRestoreViewController third paragraph")
        static let fromFile = NSLocalizedString("From a file", comment: "Button title")
        static let fromCloud = NSLocalizedString("From the cloud", comment: "Button title")
        static let backupFileSelected = NSLocalizedString("Backup file selected", comment: "Title of a card")
        static let proceedButtonTitle = NSLocalizedString("Proceed and enter backup key", comment: "Button title")
        static let backupCreationDate = { (date: String) in
            String.localizedStringWithFormat(NSLocalizedString("Backup creation date: %@", comment: "Title of card"), date)
        }
        static let messageSignIn = NSLocalizedString("Please sign in to your iCloud account. On the Home screen, launch Settings, tap iCloud, and enter your Apple ID. Turn iCloud Drive on.", comment: "Alert message")
        static let titleSignIn = NSLocalizedString("Sign in to iCloud", comment: "Alert title")
        static let titleUnexpectedCloudKitRecord = NSLocalizedString("Unexpected iCloud file error", comment: "Alert title")
        static let messageCouldNotRetrieveEncryptedBackupFile = NSLocalizedString("We could not retrieve the encrypted backup content from iCloud", comment: "Alert message")
        static let messageCouldNotRetrieveCreationDate = NSLocalizedString("We could not retrieve the creation date of the backup content from iCloud", comment: "Alert message")
        static let titleCloudKitError = NSLocalizedString("iCloud error", comment: "Alert title")
        static let titleNoBackupFileInCloud = NSLocalizedString("No backup available in iCloud", comment: "Alert title")
        static let messageNoBackupFileInCloud = NSLocalizedString("We could not find any backup in you iCloud account. Please make sure this device uses the same iCloud account as the one you were using on the previous device.", comment: "Alert message")
    }
    
}


protocol BackupRestoreViewControllerDelegate: AnyObject {
    
    func userWantsToRestoreBackupFromFileLegacy()
    func userWantToRestoreBackupFromCloudLegacy()
    func proceedWithBackupFileLegacy(atUrl: URL)
    
}


fileprivate extension UIView {
    
    static func showInStackView(views: [UIView?]) {
        for view in views {
            view?.isHidden = false
        }
    }
    
}
