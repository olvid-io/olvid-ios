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
import OlvidUtils
import ObvUI
import ObvUICoreData
import ObvSettings
import ObvDesignSystem


/// First table view controller shown when navigating to the backup settings.
@MainActor
final class BackupTableViewController: UITableViewController {

    private var notificationTokens = [NSObjectProtocol]()

    private var backupKeyInformationState: BackupKeyInformationState

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BackupTableViewController.self))
    private var lastCloudBackupState: LastCloudBackupState?
    private var ckRecordCountState: CKRecordCountState?
    private let obvEngine: ObvEngine
    private weak var appBackupDelegate: AppBackupDelegate?
    private static let waitingTimeBeforeRefreshingLatestCloudBackupInformation = 3 // In seconds

    private enum BackupKeyInformationState {
        case evaluating
        case none
        case some(ObvBackupKeyInformation)
    }

    private enum LastCloudBackupState {
        case lastBackup(_: Date)
        case noBackups
        case error(_: CloudKitError)
    }

    private enum CKRecordCountState {
        case count(_: Int)
        case error(_: CloudKitError)
    }

    private let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = true
        df.dateStyle = .short
        df.timeStyle = .medium
        df.locale = Locale.current
        return df
    }()
    
    // MARK: - Sections description
    
    private enum Section: Int, CaseIterable {
        case generateKey
        case manualBackup
        case automaticBackup
        case debug
        
        static func shownFor(backupKeyInformationState: BackupKeyInformationState) -> [Section] {
            switch backupKeyInformationState {
            case .evaluating:
                return []
            case .none:
                assert(Section.generateKey.rawValue == 0)
                return [Section.generateKey]
            case .some:
                var result = [Section.generateKey, .manualBackup, .automaticBackup]
                if ObvMessengerConstants.developmentMode && ObvMessengerSettings.BetaConfiguration.showBetaSettings {
                    result += [.debug]
                }
                return result
            }
        }
        
        var numberOfItems: Int {
            switch self {
            case .generateKey: return GenerateKeyRow.shown.count
            case .manualBackup: return ManualBackupRow.shown.count
            case .automaticBackup: return AutomaticBackupRow.shown.count
            case .debug: return DebugRow.shown.count
            }
        }
        
        static func shownForAt(section: Int, for backupKeyInformationState: BackupKeyInformationState) -> Section? {
            let shownSections = shownFor(backupKeyInformationState: backupKeyInformationState)
            guard section < shownSections.count else { assertionFailure(); return nil }
            return shownSections[section]
        }
        
    }
    
    // MARK: - Rows description
    
    private enum GenerateKeyRow: CaseIterable {
        case verifyOrGenerateKey
        
        static var shown: [GenerateKeyRow] {
            return self.allCases
        }
        static func shownRowAt(row: Int) -> GenerateKeyRow? {
            guard row < shown.count else { assertionFailure(); return nil }
            return shown[row]
        }
        var cellIdentifier: String {
            switch self {
            case .verifyOrGenerateKey: return "VerifyOrGenerateKeyCell"
            }
        }
    }

    
    private enum ManualBackupRow: CaseIterable {
        case shareBackup
        case iCloudBackup
        
        static var shown: [ManualBackupRow] {
            return self.allCases
        }
        static func shownRowAt(row: Int) -> ManualBackupRow? {
            guard row < shown.count else { assertionFailure(); return nil }
            return shown[row]
        }
        var cellIdentifier: String {
            switch self {
            case .shareBackup: return "ShareBackupCell"
            case .iCloudBackup: return "ICloudBackupCell"
            }
        }
    }

    
    private enum AutomaticBackupRow: CaseIterable {
        case automaticBackup
        case automaticCleaning
        case listBackups
        
        static var shown: [AutomaticBackupRow] {
            var result = [AutomaticBackupRow.automaticBackup]
            if ObvMessengerSettings.BetaConfiguration.showBetaSettings {
                result += [.automaticCleaning]
            }
            result += [.listBackups]
            return result
        }
        static func shownRowAt(row: Int) -> AutomaticBackupRow? {
            guard row < shown.count else { assertionFailure(); return nil }
            return shown[row]
        }
        var cellIdentifier: String {
            switch self {
            case .automaticBackup: return "AutomaticBackupCell"
            case .automaticCleaning: return "AutomaticCleaningCell"
            case .listBackups: return "ListBackupsCell"
            }
        }
    }

    
    private enum DebugRow: CaseIterable {
        case computeCKRecordCount
        
        static var shown: [DebugRow] {
            return self.allCases
        }
        static func shownRowAt(row: Int) -> DebugRow? {
            guard row < shown.count else { assertionFailure(); return nil }
            return shown[row]
        }
        var cellIdentifier: String {
            switch self {
            case .computeCKRecordCount: return "ComputeCKRecordCountCell"
            }
        }
    }

    
    // MARK: - Init

    init(obvEngine: ObvEngine, appBackupDelegate: AppBackupDelegate?) {
        self.obvEngine = obvEngine
        self.appBackupDelegate = appBackupDelegate
        self.backupKeyInformationState = .evaluating
        super.init(style: Self.settingsTableStyle)
    }
    
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Backup
        listenToNotifications()
        refreshBackupKeyInformation()
        refreshLatestCloudBackupInformation()
    }

    
    private func listenToNotifications() {
        notificationTokens.append(contentsOf: [
            ObvEngineNotificationNew.observeNewBackupKeyGenerated(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (backupKeyString, backupKeyInformation) in
                self?.backupKeyInformationState = .some(backupKeyInformation)
                self?.presentBackupKeyViewerViewController(backupKeyString: backupKeyString)
            },
            ObvMessengerInternalNotification.observeIncrementalCleanBackupTerminates(queue: OperationQueue.main) { [weak self] in
                self?.resetRecordCountState()
            },
            ObvMessengerInternalNotification.observeIncrementalCleanBackupStarts(queue: OperationQueue.main) { [weak self] in
                self?.resetRecordCountState()
            },
        ])
    }
    
    
    /// When a new backup key is generated, we always show this new key to the user. We show it only once.
    private func presentBackupKeyViewerViewController(backupKeyString: String) {
        assert(Thread.isMainThread)
        let backupKeyViewerVC = BackupKeyViewerViewController()
        backupKeyViewerVC.delegate = self
        backupKeyViewerVC.backupKeyString = backupKeyString
        let nav = UINavigationController(rootViewController: backupKeyViewerVC)
        present(nav, animated: true) { [weak self] in
            self?.tableView.reloadData()
        }
    }

}


// MARK: - BackupKeyViewerViewControllerDelegate

extension BackupTableViewController: BackupKeyViewerViewControllerDelegate {
    
    func backupKeyViewerViewControllerDidDisappear() {
        presentEnableAutomaticBackupActionSheet()
    }
    
}


// MARK: - UITableViewDataSource

extension BackupTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.shownFor(backupKeyInformationState: backupKeyInformationState).count
    }
    
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section.shownForAt(section: section, for: backupKeyInformationState) else { return 0 }
        return section.numberOfItems
    }
    
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cellInCaseOfError = UITableViewCell(style: .default, reuseIdentifier: nil)
        
        guard let section = Section.shownForAt(section: indexPath.section, for: backupKeyInformationState) else {
            assertionFailure()
            return cellInCaseOfError
        }
        
        switch section {
            
        case .generateKey:
            guard let row = GenerateKeyRow.shownRowAt(row: indexPath.row) else { assertionFailure(); return cellInCaseOfError }
            switch row {
            case .verifyOrGenerateKey:
                let cell = tableView.dequeueReusableCell(withIdentifier: row.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: row.cellIdentifier)
                switch backupKeyInformationState {
                case .evaluating:
                    cell.textLabel?.text = nil
                case .none:
                    cell.textLabel?.text = Strings.generateNewBackupKey
                case .some:
                    cell.textLabel?.text = Strings.verifyOrGenerateNewBackupKey
                }
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            }
            
        case .manualBackup:
            guard let row = ManualBackupRow.shownRowAt(row: indexPath.row) else { assertionFailure(); return cellInCaseOfError }
            switch row {
            case .shareBackup:
                let cell = tableView.dequeueReusableCell(withIdentifier: row.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: row.cellIdentifier)
                cell.textLabel?.text = Strings.backupAndShareNow
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                enable(cell: cell)
                return cell
            case .iCloudBackup:
                let cell = tableView.dequeueReusableCell(withIdentifier: row.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: row.cellIdentifier)
                cell.textLabel?.text = Strings.backupAndUploadNow
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                enable(cell: cell)
                return cell
            }
            
        case .automaticBackup:
            guard let row = AutomaticBackupRow.shownRowAt(row: indexPath.row) else { assertionFailure(); return cellInCaseOfError }
            switch row {
            case .automaticBackup:
                let cell = tableView.dequeueReusableCell(withIdentifier: row.cellIdentifier) as? ObvTitleAndSwitchTableViewCell ?? ObvTitleAndSwitchTableViewCell(reuseIdentifier: row.cellIdentifier)
                cell.selectionStyle = .none
                cell.title = Strings.enableCloudKitBackupTitle
                cell.switchIsOn = ObvMessengerSettings.Backup.isAutomaticBackupEnabled
                cell.blockOnSwitchValueChanged = { [weak self] (value) in
                    Task {
                        await self?.isAutomaticBackupEnabledChangedTo(value)
                    }
                }
                return cell
            case .automaticCleaning:
                let cell = tableView.dequeueReusableCell(withIdentifier: row.cellIdentifier) as? ObvTitleAndSwitchTableViewCell ?? ObvTitleAndSwitchTableViewCell(reuseIdentifier: row.cellIdentifier)
                cell.selectionStyle = .none
                cell.title = Strings.enableAutomaticBackupCleaning
                cell.switchIsOn = ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled
                cell.blockOnSwitchValueChanged = { [weak self] (value) in
                    Task {
                        await self?.isAutomaticCleaningBackupEnabledChangedTo(value)
                    }
                }
                return cell
            case .listBackups:
                let cell = tableView.dequeueReusableCell(withIdentifier: row.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: row.cellIdentifier)
                cell.textLabel?.text = Strings.iCloudBackupList
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                cell.accessoryType = .disclosureIndicator
                enable(cell: cell)
                return cell
            }
            
        case .debug:
            guard let row = DebugRow.shownRowAt(row: indexPath.row) else { assertionFailure(); return cellInCaseOfError }
            switch row {
            case .computeCKRecordCount:
                let cell = tableView.dequeueReusableCell(withIdentifier: row.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: row.cellIdentifier)
                updateComputeCKRecordCountCell(cell: cell)
                enable(cell: cell)
                return cell
            }
        }
    }
    
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section.shownForAt(section: section, for: backupKeyInformationState) else {
            assertionFailure()
            return nil
        }
        switch section {
        case .generateKey: return Strings.generateBackupKeySectionTitle
        case .manualBackup: return Strings.manualBackup
        case .automaticBackup: return Strings.automaticBackup
        case .debug: return CommonString.Word.Debug
        }
    }
    
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section.shownForAt(section: section, for: backupKeyInformationState) else {
            assertionFailure()
            return nil
        }
        switch section {
        case .generateKey:
            switch backupKeyInformationState {
            case .evaluating:
                return nil
            case .none:
                return Strings.noBackupKeyGeneratedYet
            case .some(let info):
                return Strings.currentBackupKeyGenerated(dateFormater.string(from: info.keyGenerationTimestamp))
            }
        case .manualBackup:
            if case let .some(info) = backupKeyInformationState,
               let lastBackupExportTimestamp = info.lastBackupExportTimestamp {
                return [Strings.manualBackupExplanation, Strings.latestExport(dateFormater.string(from: lastBackupExportTimestamp))].joined(separator: "\n")
            } else {
                return [Strings.manualBackupExplanation, Strings.neverExported].joined(separator: "\n")
            }
        case .automaticBackup:
            var titleForFooter = [Strings.automaticBackupExplanation]
            var lastSuccessBackupDate: Date?
            if let lastCloudBackupState = self.lastCloudBackupState {
                switch lastCloudBackupState {
                case .lastBackup(let date):
                    titleForFooter.append(Strings.latestUpload(dateFormater.string(from: date)))
                    lastSuccessBackupDate = date
                case .noBackups:
                    titleForFooter.append(Strings.neverUploaded)
                case .error:
                    titleForFooter.append(Strings.fetchingLatestUploadError)
                }
                if case let .some(info) = backupKeyInformationState,
                   let timestamp = info.lastBackupUploadFailureTimestamp {
                    if let lastSuccessBackupDate, timestamp < lastSuccessBackupDate {
                        // A more recent backup succeeded, do not show failed backup that is older
                    } else {
                        titleForFooter.append(Strings.latestUploadFailed(dateFormater.string(from: timestamp)))
                    }
                }
            } else {
                titleForFooter.append(Strings.fetchingLatestUpload)
            }
            return titleForFooter.joined(separator: "\n")
        case .debug:
            return nil
        }
    }

}


// MARK: - UITableViewDelegate

extension BackupTableViewController {
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        guard let section = Section.shownForAt(section: indexPath.section, for: backupKeyInformationState) else {
            assertionFailure()
            return
        }

        switch section {
            
        case .generateKey:
            guard let row = GenerateKeyRow.shownRowAt(row: indexPath.row) else { assertionFailure(); return }
            switch row {
            case .verifyOrGenerateKey:
                switch backupKeyInformationState {
                case .evaluating:
                    break
                case .none:
                    Task {
                        await obvEngine.generateNewBackupKey()
                    }
                case .some:
                    let vc = BackupKeyVerifierViewHostingController(obvEngine: obvEngine, dismissAction: { [weak self] in
                        self?.dismiss(animated: true)
                    }, dismissThenGenerateNewBackupKeyAction: { [weak self] in
                        self?.dismiss(animated: true, completion: {
                            Task {
                                await self?.obvEngine.generateNewBackupKey()
                            }
                        })
                    })
                    let nav = UINavigationController(rootViewController: vc)
                    present(nav, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }
                }
            }
            
        case .manualBackup:
            guard let row = ManualBackupRow.shownRowAt(row: indexPath.row) else { assertionFailure(); return }
            switch row {
            case .shareBackup:
                guard case .some = self.backupKeyInformationState else { assertionFailure(); return }
                guard let cell = tableView.cellForRow(at: indexPath) else { assertionFailure(); return }
                disable(cell: cell)
                tableView.deselectRow(at: indexPath, animated: true)
                Task {
                    do {
                        _ = try await appBackupDelegate?.exportBackup(sourceView: cell, sourceViewController: self)
                        DispatchQueue.main.async { [weak self] in
                            self?.refreshBackupKeyInformation()
                        }
                    } catch let error {
                        os_log("Could not export backup: %{public}@", log: log, type: .fault, error.localizedDescription)
                    }
                }
            case .iCloudBackup:
                guard case .some = self.backupKeyInformationState else { assertionFailure(); return }
                guard let cell = tableView.cellForRow(at: indexPath) else { assertionFailure(); return }
                resetRecordCountState()
                disable(cell: cell)
                showHUD(type: .spinner) // removed when receiving the BackupForUploadWasUploaded/Failed notification
                Task {
                    do {
                        try await self.userTappedOnPerfomCloudKitBackupNow()
                    } catch {
                        DispatchQueue.main.async {
                            // Remove the HUD if there is one
                            if self.hudIsShown() == true {
                                self.showHUD(type: .xmark)
                                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) { self.hideHUD() }
                            }
                        }
                    }
                    DispatchQueue.main.async {
                        self.enable(cell: cell)
                        tableView.deselectRow(at: indexPath, animated: true)
                    }
                }
            }
            
        case .automaticBackup:
            guard let row = AutomaticBackupRow.shownRowAt(row: indexPath.row) else { assertionFailure(); return }
            switch row {
            case .automaticBackup:
                break
            case .automaticCleaning:
                break
            case .listBackups:
                tableView.deselectRow(at: indexPath, animated: true)
                let backupView = ICloudBackupListViewController(appBackupDelegate: appBackupDelegate)
                backupView.delegate = self
                navigationController?.pushViewController(backupView, animated: true)
            }
            
        case .debug:
            guard let row = DebugRow.shownRowAt(row: indexPath.row) else { assertionFailure(); return }
            switch row {
            case .computeCKRecordCount:
                guard let cell = tableView.cellForRow(at: indexPath) else { assertionFailure(); return }
                self.ckRecordCountState = nil
                self.updateComputeCKRecordCountCell(cell: cell)
                self.disable(cell: cell)
                Task {
                    do {
                        if let (backupCount, _) = try await appBackupDelegate?.getBackupsAndDevicesCount(identifierForVendor: nil) {
                            self.ckRecordCountState = .count(backupCount)
                        } else {
                            self.ckRecordCountState = .error(.internalError)
                        }
                    } catch(let error) {
                        let error = error as? CloudKitError ?? .unknownError(error)
                        self.ckRecordCountState = .error(error)
                    }
                    DispatchQueue.main.async {
                        self.updateComputeCKRecordCountCell(cell: cell)
                        self.enable(cell: cell)
                    }
                }
            }
            
        }
    }

}


// MARK: - Others

extension BackupTableViewController {
    
    private func resetRecordCountState() {
        assert(Thread.isMainThread)
        ckRecordCountState = nil
        reloadSection(.debug)
    }

    
    private func refreshLatestCloudBackupInformation() {
        assert(Thread.isMainThread)
        Task {
            do {
                if let latestBackup = try await appBackupDelegate?.getLatestCloudBackup(desiredKeys: []) {
                    if let creationDate = latestBackup.creationDate {
                        self.lastCloudBackupState = .lastBackup(creationDate)
                    } else {
                        self.lastCloudBackupState = .error(.operationError(ObvError.cannotGetLastBackupCreationDate))
                    }
                } else {
                    self.lastCloudBackupState = .noBackups
                }
            } catch(let error) {
                let error = error as? CloudKitError ?? .unknownError(error)
                self.lastCloudBackupState = .error(error)
            }
            DispatchQueue.main.async {
                self.reloadSection(.automaticBackup)
            }
        }
    }

    
    private func refreshBackupKeyInformation() {
        assert(Thread.isMainThread)
        var backupKeyInformationStateWasInitiallyNone = false
        if case .none = self.backupKeyInformationState {
            backupKeyInformationStateWasInitiallyNone = true
            self.backupKeyInformationState = .evaluating
            self.showHUD(type: .spinner)
            self.tableView?.reloadData()
        }
        Task {
            do {
                if let info = try await obvEngine.getCurrentBackupKeyInformation() {
                    self.backupKeyInformationState = .some(info)
                } else {
                    self.backupKeyInformationState = .none
                }
            } catch {
                os_log("Could not get current backup key information from engine", log: log, type: .default)
                assertionFailure()
                self.backupKeyInformationState = BackupKeyInformationState.none
            }
            DispatchQueue.main.async {
                if backupKeyInformationStateWasInitiallyNone {
                    self.hideHUD()
                }
                self.tableView?.reloadData()
            }
        }
    }

    
    private func reloadSection(_ section: Section) {
        assert(Thread.isMainThread)
        guard section.rawValue < self.tableView.numberOfSections else { return }
        self.tableView.reloadSections([section.rawValue], with: .automatic)
    }


    private func updateComputeCKRecordCountCell(cell: UITableViewCell) {
        var configuration = UIListContentConfiguration.valueCell()
        configuration.text = Strings.computeCKRecordCount
        configuration.textProperties.color = AppTheme.shared.colorScheme.link
        if let ckRecordCountState = ckRecordCountState {
            switch ckRecordCountState {
            case .count(let count):
                configuration.secondaryText = String(count)
            case .error:
                configuration.secondaryText = CommonString.Word.Error
            }
        } else {
            configuration.secondaryText = nil
        }
        cell.contentConfiguration = configuration
    }
    

    private func presentEnableAutomaticBackupActionSheet() {
        guard !ObvMessengerSettings.Backup.isAutomaticBackupEnabled else { return }
        let traitCollection = self.traitCollection
        DispatchQueue.main.async {
            let alert = UIAlertController(title: Strings.enableAutomaticBackup,
                                          message: Strings.automaticBackupExplanation,
                                          preferredStyleForTraitCollection: traitCollection)
            alert.addAction(UIAlertAction(title: CommonString.Word.Enable, style: .default) { _ in
                Task { [weak self] in
                    await self?.isAutomaticBackupEnabledChangedTo(true)
                    DispatchQueue.main.async {
                        self?.reloadSection(.automaticBackup)
                    }
                }
            })
            alert.addAction(UIAlertAction(title: CommonString.Word.Later, style: .cancel))
            self.present(alert, animated: true)
        }
    }

}


// MARK: - ICloudBackupListViewControllerDelegate

extension BackupTableViewController: ICloudBackupListViewControllerDelegate {
    
    func lastCloudBackupForCurrentDeviceWasDeleted() {
        DispatchQueue.main.async { [weak self] in
            self?.lastCloudBackupState = nil
            self?.reloadSection(.automaticBackup)
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(Self.waitingTimeBeforeRefreshingLatestCloudBackupInformation)) {
                self?.refreshLatestCloudBackupInformation()
            }
        }
    }

}


// MARK: - Helpers

extension BackupTableViewController {
    
    private func checkIfAccountStatusIsAvailableOrShowError() async throws {
        let accountStatus = (try? await appBackupDelegate?.getAccountStatus()) ?? .couldNotDetermine
        if case .available = accountStatus {
            return
        }
        guard let (title, message) = AppBackupManager.CKAccountStatusMessage(accountStatus) else {
            assertionFailure()
            throw ObvError.cannotComputeErrorTitleAndMessage
        }
        DispatchQueue.main.async {
            let alert = UIAlertController(title: title,
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: CommonString.Word.Ok, style: .default) { _ in
            })
            self.present(alert, animated: true)
        }
        throw ObvError.ckAccountStatusMessageError(message: message)
    }

    
    private func userTappedOnPerfomCloudKitBackupNow() async throws {
        try await self.checkIfAccountStatusIsAvailableOrShowError()
        try await appBackupDelegate?.uploadBackupToICloud()

        DispatchQueue.main.async {
            self.refreshBackupKeyInformation()
            self.lastCloudBackupState = nil
            self.reloadSection(.automaticBackup)
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(Self.waitingTimeBeforeRefreshingLatestCloudBackupInformation)) {
                self.refreshLatestCloudBackupInformation()
            }
            // Remove the HUD if there is one
            if self.hudIsShown() == true {
                self.showHUD(type: .checkmark)
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2)) {
                    self.hideHUD()
                }
            }
        }
    }

    
    private func isAutomaticBackupEnabledChangedTo(_ value: Bool) async {
        guard ObvMessengerSettings.Backup.isAutomaticBackupEnabled != value else { return }

        if value {
            do {
                try await checkIfAccountStatusIsAvailableOrShowError()
                    ObvMessengerSettings.Backup.isAutomaticBackupEnabled = true
                self.obvEngine.userJustActivatedAutomaticBackup()
            } catch {
                ObvMessengerSettings.Backup.isAutomaticBackupEnabled = false
                DispatchQueue.main.async {
                    self.reloadSection(.automaticBackup)
                }
                return
            }
        } else {
            ObvMessengerSettings.Backup.isAutomaticBackupEnabled = false
            DispatchQueue.main.async {
                self.reloadSection(.automaticBackup)
            }
        }
    }


    private func isAutomaticCleaningBackupEnabledChangedTo(_ value: Bool) async {
        guard ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled != value else { return }
        if value {
            do {
                try await self.checkIfAccountStatusIsAvailableOrShowError()
                ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled = true
                ObvMessengerInternalNotification.userWantsToStartIncrementalCleanBackup(cleanAllDevices: false).postOnDispatchQueue()
            } catch {
                ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled = false
                return
            }
        } else {
            ObvMessengerSettings.Backup.isAutomaticCleaningBackupEnabled = false
        }
    }
    
    
    private func disable(cell: UITableViewCell?) {
        assert(Thread.current == Thread.main)
        guard let cell = cell else { return }
        cell.isUserInteractionEnabled = false
        cell.textLabel?.isEnabled = false
        let spinner = UIActivityIndicatorView(style: .medium)
        cell.accessoryView = spinner
        spinner.startAnimating()
    }
    
    private func enable(cell: UITableViewCell?) {
        assert(Thread.isMainThread)
        guard let cell = cell else { return }
        cell.isUserInteractionEnabled = true
        cell.textLabel?.isEnabled = true
        cell.accessoryView = nil
    }


}


// MARK: - Errors

extension BackupTableViewController {
    
    enum ObvError: Error {
        case cannotGetLastBackupCreationDate
        case cannotComputeErrorTitleAndMessage
        case ckAccountStatusMessageError(message: String)
    }
    
}


// MARK: - Localized Strings

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
        static let enableAutomaticBackup = NSLocalizedString("ENABLE_AUTOMATIC_BACKUP", comment: "Table view section header")
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
        static let enableCloudKitBackupTitle = NSLocalizedString("AUTOMATIC_ICLOUD_BACKUPS", comment: "Cell title")
        static let enableAutomaticBackupCleaning = NSLocalizedString("Automatic iCloud backup cleaning", comment: "Button title allowing to enable automatic backup cleaning")
        static let computeCKRecordCount = NSLocalizedString("COMPUTE_CKRECORD_COUNT", comment: "Button title allowing to show backup list")
    }
    
}
