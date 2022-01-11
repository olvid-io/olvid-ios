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
import os.log
import ObvTypes
import CloudKit

final class BackupTableViewController: UITableViewController {

    private var notificationTokens = [NSObjectProtocol]()
    private var backupKeyInformation: ObvBackupKeyInformation?
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BackupTableViewController.self))
    private var indexPathOfCellThatInitiatedBackupForExport: IndexPath?
    private var lastCloudBackupState: LastCloudBackupState?

    private enum LastCloudBackupState {
        case lastBackup(_: Date)
        case noBackups
        case error(_: AppBackupCoordinator.AppBackupError)
    }

    private let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .medium
        df.locale = Locale.current
        return df
    }()
    
    private enum Section: Int, CaseIterable {
        case generateKey = 0
        case manualBackup
        case automaticBackup
    }
    
    private enum GenerateKeyRow {
        case verifyOrGenerateKey
    }
    private var shownGenerateKeyRows = [GenerateKeyRow]()

    private enum ManualBackupRow {
        case shareBackup
        case iCloudBackup
    }
    private var shownManualBackupRows = [ManualBackupRow]()

    private enum AutomaticBackupRow {
        case automaticBackup
        case automaticCleaning
        case listBackups
    }
    private var shownAutomaticBackupRows = [AutomaticBackupRow]()

    private static let errorDomain = "BackupTableViewController"
    
    private static func makeError(message: String) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: errorDomain, code: 0, userInfo: userInfo)
    }

    init() {
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Backup
        listenToNotifications()
        refreshBackupKeyInformation(reloadData: false)
        refreshLatestCloudBackupInformation()
    }
    
    private func refreshBackupKeyInformation(reloadData: Bool) {
        assert(Thread.current == Thread.main)
        do {
            self.backupKeyInformation = try obvEngine.getCurrentBackupKeyInformation()
        } catch {
            os_log("Could not get current backup key information from engine", log: log, type: .default)
            assertionFailure()
        }
        if reloadData {
            tableView?.reloadData()
        }
    }

    private func refreshLatestCloudBackupInformation() {
        assert(Thread.isMainThread)
        AppBackupCoordinator.getLatestCloudBackup { result in
            switch result {
            case .success(let record):
                if let record = record {
                    if let creationDate = record.creationDate {
                        self.lastCloudBackupState = .lastBackup(creationDate)
                    } else {
                        self.lastCloudBackupState = .error(.operationError(Self.makeError(message: "Cannot get last backup creationDate")))
                    }
                } else {
                    self.lastCloudBackupState = .noBackups
                }
            case .failure(let error):
                self.lastCloudBackupState = .error(error)
            }
            DispatchQueue.main.async {
                self.reloadAutomaticBackupSections()
            }
        }
    }

    private func listenToNotifications() {
        
        do {
            let token = ObvEngineNotificationNew.observeNewBackupKeyGenerated(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (backupKeyString, backupKeyInformation) in
                self?.backupKeyInformation = backupKeyInformation
                let backupKeyViewerVC = BackupKeyViewerViewController()
                backupKeyViewerVC.backupKeyString = backupKeyString
                let nav = UINavigationController(rootViewController: backupKeyViewerVC)
                self?.present(nav, animated: true) {
                    self?.tableView.reloadData()
                }
            }
            notificationTokens.append(token)
        }
        
        do {
            let token = ObvEngineNotificationNew.observeBackupFailed(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (backupRequestUuid) in
                self?.refreshBackupKeyInformation(reloadData: true)
            }
            notificationTokens.append(token)
        }
        
        do {
            // When receiving a BackupForExportWasFinished notification, we do not handle the backup itself.
            // It is up to the AppBackupCoordinator to deal with it
            let token = ObvEngineNotificationNew.observeBackupForExportWasFinished(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (backupRequestUuid, backupKeyUid, backupVersion, encryptedContent) in
                guard let _self = self else { return }
                guard let indexPath = _self.indexPathOfCellThatInitiatedBackupForExport else { assertionFailure(); return }
                _self.indexPathOfCellThatInitiatedBackupForExport = nil
                let cell = self?.tableView.cellForRow(at: indexPath)
                self?.enable(cell: cell)
            }
            notificationTokens.append(token)
        }
        
        notificationTokens.append(ObvEngineNotificationNew.observeBackupForUploadWasUploaded(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (_, _, _) in
            self?.refreshBackupKeyInformation(reloadData: true)
            self?.lastCloudBackupState = nil
            self?.reloadAutomaticBackupSections()
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
                self?.refreshLatestCloudBackupInformation()
            }
        })

        notificationTokens.append(ObvEngineNotificationNew.observeBackupForExportWasExported(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (_, _, _) in
            self?.refreshBackupKeyInformation(reloadData: true)
        })

    }

}


// MARK: - UITableViewDataSource

extension BackupTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        if backupKeyInformation == nil {
            assert(Section.generateKey.rawValue == 0)
            return 1
        } else {
            return (Section.allCases.map({ $0.rawValue }).max() ?? 0) + 1
        }
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { assertionFailure(); return 0 }
        switch section {
        case .generateKey:
            shownGenerateKeyRows = [.verifyOrGenerateKey]
            return shownGenerateKeyRows.count
        case .manualBackup:
            shownManualBackupRows = [.shareBackup, .iCloudBackup]
            return shownManualBackupRows.count
        case .automaticBackup:
            shownAutomaticBackupRows = [.automaticBackup]
            if ObvMessengerSettings.BetaConfiguration.showBetaSettings {
                shownAutomaticBackupRows += [.automaticCleaning]
            }
            if #available(iOS 13.0, *) {
                shownAutomaticBackupRows += [.listBackups]
            }
            return shownAutomaticBackupRows.count
        }
    }
    

    private func reloadAutomaticBackupSections() {
        assert(Thread.isMainThread)
        guard Section.automaticBackup.rawValue < self.tableView.numberOfSections else { return }
        self.tableView.reloadSections([Section.automaticBackup.rawValue], with: .none)
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard let section = Section(rawValue: indexPath.section) else { assertionFailure(); return UITableViewCell() }
        
        switch section {
        case .generateKey:
            guard indexPath.row < shownGenerateKeyRows.count else { assertionFailure(); return UITableViewCell() }
            switch shownGenerateKeyRows[indexPath.row] {
            case .verifyOrGenerateKey:
                let cell = tableView.dequeueReusableCell(withIdentifier: "VerifyOrGenerateKeyCell") ?? UITableViewCell(style: .default, reuseIdentifier: "VerifyOrGenerateKeyCell")
                if self.backupKeyInformation == nil {
                    cell.textLabel?.text = Strings.generateNewBackupKey
                } else {
                    cell.textLabel?.text = Strings.verifyOrGenerateNewBackupKey
                }
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            }
        case .manualBackup:
            guard indexPath.row < shownManualBackupRows.count else { assertionFailure(); return UITableViewCell() }
            switch shownManualBackupRows[indexPath.row] {
            case .shareBackup:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ManualShareBackupCell") ?? UITableViewCell(style: .default, reuseIdentifier: "ManualShareBackupCell")
                cell.textLabel?.text = Strings.backupAndShareNow
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            case .iCloudBackup:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ManualICloudBackupCell") ?? UITableViewCell(style: .default, reuseIdentifier: "ManualICloudBackupCell")
                cell.textLabel?.text = Strings.backupAndUploadNow
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                enable(cell: cell)
                return cell
            }
        case .automaticBackup:
            guard indexPath.row < shownAutomaticBackupRows.count else { assertionFailure(); return UITableViewCell() }
            switch shownAutomaticBackupRows[indexPath.row] {
            case .automaticBackup:
                let cell: ObvTitleAndSwitchTableViewCell
                if let _cell = tableView.dequeueReusableCell(withIdentifier: "AutomaticBackupCell") as? ObvTitleAndSwitchTableViewCell {
                    cell = _cell
                } else {
                    cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: "AutomaticBackupCell")
                }
                cell.selectionStyle = .none
                cell.title = Strings.enableCloudKitBackupTitle
                cell.switchIsOn = ObvMessengerSettings.Backup.isAutomaticBackupEnabled
                cell.blockOnSwitchValueChanged = { [weak self] (value) in self?.isAutomaticBackupEnabledChangedTo(value, at: indexPath)  }
                return cell
            case .automaticCleaning:
                let cell: ObvTitleAndSwitchTableViewCell
                if let _cell = tableView.dequeueReusableCell(withIdentifier: "AutomaticBackupCleaning") as? ObvTitleAndSwitchTableViewCell {
                    cell = _cell
                } else {
                    cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: "AutomaticBackupCleaning")
                }
                cell.selectionStyle = .none
                cell.title = Strings.enableAutomaticBackupCleaning
                cell.switchIsOn = ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled
                cell.blockOnSwitchValueChanged = { [weak self] (value) in self?.isAutomaticCleaningBackupEnabledChangedTo(value, at: indexPath)  }
                return cell
            case .listBackups:
                let cell = tableView.dequeueReusableCell(withIdentifier: "iCloudBackupList") ?? UITableViewCell(style: .default, reuseIdentifier: "iCloudBackupList")
                cell.textLabel?.text = Strings.iCloudBackupList
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                enable(cell: cell)
                return cell
            }
        }
    }
        
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .generateKey:
            return Strings.generateBackupKeySectionTitle
        case .manualBackup:
            return Strings.manualBackup
        case .automaticBackup:
            return Strings.automaticBackup
        }
    }
    
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section(rawValue: section) else { return nil }
        switch section {
        case .generateKey:
            if let backupKeyInformation = self.backupKeyInformation {
                return Strings.currentBackupKeyGenerated(dateFormater.string(from: backupKeyInformation.keyGenerationTimestamp))
            } else {
                return Strings.noBackupKeyGeneratedYet
            }
        case .manualBackup:
            if let lastBackupExportTimestamp = backupKeyInformation?.lastBackupExportTimestamp {
                return [Strings.manualBackupExplanation, Strings.latestExport(dateFormater.string(from: lastBackupExportTimestamp))].joined(separator: "\n")
            }
            return [Strings.manualBackupExplanation, Strings.neverExported].joined(separator: "\n")
        case .automaticBackup:
            var titleForFooter = [Strings.automaticBackupExplanation]
            if let lastCloudBackupState = self.lastCloudBackupState {
                switch lastCloudBackupState {
                case .lastBackup(let date):
                    titleForFooter.append(Strings.latestUpload(dateFormater.string(from: date)))
                case .noBackups:
                    titleForFooter.append(Strings.neverUploaded)
                case .error:
                    titleForFooter.append(Strings.fetchingLatestUploadError)
                }
            } else {
                titleForFooter.append(Strings.fetchingLatestUpload)
            }
            if let timestamp = backupKeyInformation?.lastBackupUploadFailureTimestamp, timestamp > (backupKeyInformation?.lastBackupUploadTimestamp ?? Date.distantPast) {
                titleForFooter.append(Strings.latestUploadFailed(dateFormater.string(from: timestamp)))
            }
            return titleForFooter.joined(separator: "\n")
        }
    }
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Section(rawValue: indexPath.section) else { assertionFailure(); return }
        switch section {
        case .generateKey:
            guard indexPath.row < shownGenerateKeyRows.count else { assertionFailure(); return }
            switch shownGenerateKeyRows[indexPath.row] {
            case .verifyOrGenerateKey:
                if self.backupKeyInformation == nil {
                    obvEngine.generateNewBackupKey()
                } else {
                    if #available(iOS 13, *) {
                        let vc = BackupKeyVerifierViewHostingController(obvEngine: obvEngine, dismissAction: { [weak self] in
                            self?.dismiss(animated: true)
                        }, dismissThenGenerateNewBackupKeyAction: { [weak self] in
                            self?.dismiss(animated: true, completion: {
                                self?.obvEngine.generateNewBackupKey()
                            })
                        })
                        let nav = UINavigationController(rootViewController: vc)
                        present(nav, animated: true) {
                            tableView.deselectRow(at: indexPath, animated: true)
                        }
                    } else {
                        let backupKeyVerifierVC = BackupKeyVerifierViewController()
                        let nav = UINavigationController(rootViewController: backupKeyVerifierVC)
                        present(nav, animated: true) {
                            tableView.deselectRow(at: indexPath, animated: true)
                        }
                    }
                }
            }
        case .manualBackup:
            guard indexPath.row < shownManualBackupRows.count else { assertionFailure(); return }
            switch shownManualBackupRows[indexPath.row] {
            case .shareBackup:
                guard self.backupKeyInformation != nil else { assertionFailure(); return }
                guard let cell = tableView.cellForRow(at: indexPath) else { assertionFailure(); return }
                disable(cell: cell)
                indexPathOfCellThatInitiatedBackupForExport = indexPath
                tableView.deselectRow(at: indexPath, animated: true)
                let notification = ObvMessengerInternalNotification.userWantsToPerfomBackupForExportNow(sourceView: cell)
                notification.postOnDispatchQueue()
            case .iCloudBackup:
                guard self.backupKeyInformation != nil else { assertionFailure(); return }
                guard let cell = tableView.cellForRow(at: indexPath) else { assertionFailure(); return }
                disable(cell: cell)
                userTappedOnPerfomCloudKitBackupNow { [weak self] in
                    assert(Thread.isMainThread)
                    self?.enable(cell: cell)
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            }
        case .automaticBackup:
            guard indexPath.row < shownAutomaticBackupRows.count else { assertionFailure(); return }
            switch shownAutomaticBackupRows[indexPath.row] {
            case .automaticBackup:
                break
            case .automaticCleaning:
                break
            case .listBackups:
                if #available(iOS 13.0, *) {
                    tableView.deselectRow(at: indexPath, animated: true)
                    let backupView = ICloudBackupListViewController()
                    backupView.delegate = self
                    navigationController?.pushViewController(backupView, animated: true)
                }
            }
        }
    }

}


// MARK: - ICloudBackupListViewControllerDelegate

extension BackupTableViewController: ICloudBackupListViewControllerDelegate {
    
    func lastCloudBackupForCurrentDeviceWasDeleted() {
        self.lastCloudBackupState = nil
        DispatchQueue.main.async {
            self.reloadAutomaticBackupSections()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
            self.refreshLatestCloudBackupInformation()
        }
    }

}


// MARK: - Helpers

extension BackupTableViewController {
    
    private func asyncReloadData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) { [weak self] in
            self?.tableView.reloadData()
        }
    }

    static func CKAccountStatusMessage(_ accountStatus: CKAccountStatus) -> (title: String, message: String)? {
        switch accountStatus {
        case .noAccount:
            return (Strings.titleSignIn, Strings.messageSignIn)
        case .couldNotDetermine:
            return (Strings.titleCloudKitStatusUnclear, Strings.messageSignIn)
        case .restricted:
            return (Strings.titleCloudRestricted, Strings.messageRestricted)
        case .available:
            return nil
        case .temporarilyUnavailable:
            return (Strings.temporarilyUnavailable, Strings.tryAgainLater)
        @unknown default:
            assertionFailure()
            return nil
        }
    }
    
    
    private func userTappedOnPerfomCloudKitBackupNow(completion: @escaping () -> Void) {
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        container.accountStatus { [weak self] (accountStatus, error) in
            guard error == nil else {
                debugPrint(error!.localizedDescription)
                DispatchQueue.main.async {
                    completion()
                }
                return
            }
            if case .available = accountStatus {
                let notification = ObvMessengerInternalNotification.userWantsToPerfomCloudKitBackupNow
                notification.postOnDispatchQueue()
                DispatchQueue.main.async {
                    completion()
                }
            } else {
                guard let (title, message) = Self.CKAccountStatusMessage(accountStatus) else {
                    assertionFailure(); return
                }
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: title,
                                                  message: message,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default) { _ in
                        completion()
                    })
                    self?.present(alert, animated: true)
                }
            }
        }
    }
    
    
    private func isAutomaticBackupEnabledChangedTo(_ value: Bool, at indexPath: IndexPath) {
        guard ObvMessengerSettings.Backup.isAutomaticBackupEnabled != value else { return }
        guard value else {
            ObvMessengerSettings.Backup.isAutomaticBackupEnabled = value // False
            return
        }
        // If we reach this point, the user wants to activate automatic backup.
        // We must check this is possible.
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        container.accountStatus { [weak self] (accountStatus, error) in
            guard error == nil else {
                debugPrint(error!.localizedDescription)
                return
            }
            if case .available = accountStatus {
                self?.obvEngine.userJustActivatedAutomaticBackup()
                DispatchQueue.main.async {
                    assert(value)
                    ObvMessengerSettings.Backup.isAutomaticBackupEnabled = value // True
                }
            } else {
                guard let (title, message) = Self.CKAccountStatusMessage(accountStatus) else {
                    assertionFailure(); return
                }
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: title,
                                                  message: message,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                    self?.present(alert, animated: true) {
                        self?.tableView.reloadRows(at: [indexPath], with: .automatic)
                    }
                }
            }
        }
    }

    private func isAutomaticCleaningBackupEnabledChangedTo(_ value: Bool, at indexPath: IndexPath) {
        guard ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled != value else { return }
        guard value else {
            ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled = value // False
            return
        }
        ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled = value // True
        // If we reach this point, the user wants to activate automatic backup cleaning.
        // Perform first cleaning now
        AppBackupCoordinator.incrementalCleanCloudBackups(cleanAllDevices: false) { [weak self] result in
            guard let _self = self else { return }
            switch result {
            case .success:
                DispatchQueue.main.async {
                    assert(value)
                    ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled = value // True
                }
            case .failure(let error):
                let accountStatus: CKAccountStatus
                switch error {
                case .accountError, .operationError:
                    accountStatus = .couldNotDetermine
                case .accountNotAvailable(let status):
                    accountStatus = status
                }
                guard let (title, message) = Self.CKAccountStatusMessage(accountStatus) else {
                    assertionFailure(); return
                }
                DispatchQueue.main.async {
                    let alert = UIAlertController(title: title,
                                                  message: message,
                                                  preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default))
                    _self.present(alert, animated: true) {
                        _self.tableView.reloadRows(at: [indexPath], with: .automatic)
                    }
                }
            }
        }
    }
    
    private func disable(cell: UITableViewCell?) {
        assert(Thread.current == Thread.main)
        guard let cell = cell else { return }
        cell.isUserInteractionEnabled = false
        cell.textLabel?.isEnabled = false
        let spinner: UIActivityIndicatorView
        if #available(iOS 13, *) {
            spinner = UIActivityIndicatorView(style: .medium)
        } else {
            spinner = UIActivityIndicatorView(style: .gray)
        }
        cell.accessoryView = spinner
        spinner.startAnimating()
    }
    
    private func enable(cell: UITableViewCell?) {
        assert(Thread.current == Thread.main)
        guard let cell = cell else { return }
        cell.isUserInteractionEnabled = true
        cell.textLabel?.isEnabled = true
        cell.accessoryView = nil
    }


}

extension BackupTableViewController {
    
    private struct Strings {
        
        static let generateNewBackupKey = NSLocalizedString("GENERATE_NEW_BACKUP_KEY", comment: "")
        static let verifyOrGenerateNewBackupKey = NSLocalizedString("VERIFIY_OR_GENERATE_NEW_BACKUP_KEY", comment: "")
        static let backupAndShareNow = NSLocalizedString("BACKUP_AND_SHARE_NOW", comment: "Button title allowing to backup now")
        static let backupAndUploadNow = NSLocalizedString("BACKUP_AND_UPLOAD_NOW", comment: "Button title allowing to backup and upload now")
        static let iCloudBackupList = NSLocalizedString("iCloud backups list", comment: "Button title allowing to show backup list")
        static let generateBackupKeySectionTitle = NSLocalizedString("GENERATE_BACKUP_KEY_SECTION_TITLE", comment: "Table view section header")
        static let manualBackup = NSLocalizedString("MANUAL_BACKUP_TITLE", comment: "Table view section header")
        static let automaticBackup = NSLocalizedString("AUTOMATIC_BACKUP", comment: "Table view section header")
        static let manualBackupExplanation = NSLocalizedString("MANUAL_BACKUP_EXPLANATION_FOOTER", comment: "Table view section footer")
        static let automaticBackupExplanation = NSLocalizedString("AUTOMATIC_BACKUP_EXPLANATION", comment: "Table view section footer")
        static let noBackupKeyGeneratedYet = NSLocalizedString("NO_BACKUP_KEY_GENERATED_YET", comment: "Table view section footer")
        static let currentBackupKeyGenerated = { (date: String) in
            String.localizedStringWithFormat(NSLocalizedString("Current backup key generated: %@", comment: "Table view section footer"), date)
        }
        static let fetchingLatestUpload = NSLocalizedString("Fetching latest upload", comment: "Table view section footer")
        static let fetchingLatestUploadError = NSLocalizedString("CANNOT_FETCH_LATEST_UPLOAD", comment: "Table view section footer")
        static let latestExport = { (date: String) in
            String.localizedStringWithFormat(NSLocalizedString("Latest export: %@", comment: "Table view section footer"), date)
        }
        static let latestUpload = { (date: String) in
            String.localizedStringWithFormat(NSLocalizedString("Latest upload: %@", comment: "Table view section footer"), date)
        }
        static let latestUploadFailed = { (date: String) in
            String.localizedStringWithFormat(NSLocalizedString("⚠️ Latest failed upload: %@", comment: "Table view section footer"), date)
        }
        static let neverExported = NSLocalizedString("No backup was exported yet.", comment: "Table view section footer")
        static let neverUploaded = NSLocalizedString("No backup was uploaded yet.", comment: "Table view section footer")
        static let titleSignIn = NSLocalizedString("Sign in to iCloud", comment: "Alert title")
        static let titleCloudKitStatusUnclear = NSLocalizedString("iCloud status is unclear", comment: "Alert title")
        static let titleCloudRestricted = NSLocalizedString("iCloud access is restricted", comment: "Alert title")
        static let messageRestricted = NSLocalizedString("Your iCloud account is not available. Access was denied due to Parental Controls or Mobile Device Management restrictions", comment: "Alert body")
        static let messageSignIn = NSLocalizedString("Please sign in to your iCloud account to enable automatic backups. On the Home screen, launch Settings, tap iCloud, and enter your Apple ID. Turn iCloud Drive on. If you don't have an iCloud account, tap Create a new Apple ID.", comment: "Alert message")
        static let enableCloudKitBackupTitle = NSLocalizedString("AUTOMATIC_ICLOUD_BACKUPS", comment: "Cell title")
        static let enableAutomaticBackupCleaning = NSLocalizedString("Automatic iCloud backup cleaning", comment: "Button title allowing to enable automatic backup cleaning")
        static let temporarilyUnavailable = NSLocalizedString("ICLOUD_ACCOUNT_TEMPORARILY_UNAVAILABLE", comment: "Alert title")
        static let tryAgainLater = NSLocalizedString("ICLOUD_ACCOUNT_TRY_AGAIN_LATER", comment: "Alert body")
    }
    
}
