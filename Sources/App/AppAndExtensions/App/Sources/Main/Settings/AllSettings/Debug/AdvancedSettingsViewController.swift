/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvTypes
import LinkPresentation
import OlvidUtils
import os.log
import ObvUI
import ObvUICoreData
import ObvEngine
import ObvSettings
import ObvDesignSystem
import ObvAppCoreConstants


@MainActor
final class AdvancedSettingsViewController: UITableViewController {

    let ownedCryptoId: ObvCryptoId
    let obvEngine: ObvEngine
    
    let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: AdvancedSettingsViewController.self))
    
    weak var delegate: AdvancedSettingsViewControllerDelegate?

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, delegate: AdvancedSettingsViewControllerDelegate) {
        self.ownedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        super.init(style: Self.settingsTableStyle)
        self.delegate = delegate
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    private var currentWebSocketStatus: (state: URLSessionTask.State, pingInterval: TimeInterval?)?
    private static let websocketRefreshTimeInterval = 2 // In seconds
        
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Advanced
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }

    private func pingIntervalFormatter(pingInterval: TimeInterval) -> String {
        "\(Int(pingInterval * 1000.0)) ms"
    }
    
    private enum Section: CaseIterable {
        case clearCache
        case troubleshooting
        case customKeyboards
        case websockedStatus
        case diskUsage
        case logs
        case exportsDatabasesAndCopyURLs
        
        static var shown: [Section] {
            var result = [Section.clearCache, .troubleshooting, .customKeyboards, .websockedStatus, .diskUsage]
            if ObvMessengerConstants.showExperimentalFeature {
                result += [Section.logs, .exportsDatabasesAndCopyURLs]
            }
            return result
        }
        
        var numberOfItems: Int {
            switch self {
            case .clearCache: return ClearCacheItem.shown.count
            case .troubleshooting: return TroubleshootingItem.shown.count
            case .customKeyboards: return CustomKeyboardsItem.shown.count
            case .websockedStatus: return WebsockedStatusItem.shown.count
            case .diskUsage: return DiskUsageItem.shown.count
            case .logs: return LogsItem.shown.count
            case .exportsDatabasesAndCopyURLs: return ExportsDatabasesAndCopyURLsItem.shown.count
            }
        }
        
        static func shownSectionAt(section: Int) -> Section? {
            guard section < shown.count else { assertionFailure(); return nil }
            return shown[section]
        }

    }

    
    private enum ClearCacheItem: CaseIterable {
        case clearCache
        static var shown: [ClearCacheItem] {
            return self.allCases
        }
        static func shownItemAt(item: Int) -> ClearCacheItem? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }
        var cellIdentifier: String {
            switch self {
            case .clearCache: return "ClearCacheCell"
            }
        }
    }

    private enum TroubleshootingItem: CaseIterable {
        case syncAppDatabaseWithEngine
        case downloadMissingProfilePictures
        static var shown: [Self] {
            return self.allCases
        }
        static func shownItemAt(item: Int) -> Self? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }
        var cellIdentifier: String {
            switch self {
            case .syncAppDatabaseWithEngine: return "SyncAppDatabaseWithEngineCell"
            case .downloadMissingProfilePictures: return "DownloadMissingProfilePicturesCell"
            }
        }
    }

    private enum CustomKeyboardsItem: CaseIterable {
        case customKeyboards
        static var shown: [CustomKeyboardsItem] {
            return self.allCases
        }
        static func shownItemAt(item: Int) -> CustomKeyboardsItem? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }
        var cellIdentifier: String {
            switch self {
            case .customKeyboards: return "AllowCustomKeyboardsCell"
            }
        }
    }
    
    private enum WebsockedStatusItem: CaseIterable {
        case websockedStatus
        static var shown: [WebsockedStatusItem] {
            return self.allCases
        }
        static func shownItemAt(item: Int) -> WebsockedStatusItem? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }
        var cellIdentifier: String {
            switch self {
            case .websockedStatus: return "WebSocketStateCell"
            }
        }
    }
    
    private enum DiskUsageItem: CaseIterable {
        case diskUsage
        case internalStorageExplorer
        static var shown: [DiskUsageItem] {
            return ObvMessengerConstants.showExperimentalFeature ? self.allCases : [.diskUsage]
        }
        static func shownItemAt(item: Int) -> DiskUsageItem? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }
        var cellIdentifier: String {
            switch self {
            case .internalStorageExplorer: return "InternalStorageExplorer"
            case .diskUsage: return "DiskUsage"
            }
        }
    }
    
    private enum LogsItem: CaseIterable {
        case enableLogs
        case logsList
        case betaButtonForShowingCoordinatorsQueue
        static var shown: [LogsItem] {
            return ObvMessengerConstants.showExperimentalFeature ? self.allCases : []
        }
        static func shownItemAt(item: Int) -> LogsItem? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }
        var cellIdentifier: String {
            switch self {
            case .logsList: return "DisplayableLogsList"
            case .enableLogs: return "EnableLogs"
            case .betaButtonForShowingCoordinatorsQueue: return "betaButtonForShowingCoordinatorsQueue"
            }
        }
    }
    
    private enum ExportsDatabasesAndCopyURLsItem: CaseIterable {
        case copyDocumentsURL
        case copyDatabaseURL
        case exportAppDatabase
        case exportEngineDatabase
        case exportTmpDirectory
        case allowAnyAPIKeyActivation
        static var shown: [ExportsDatabasesAndCopyURLsItem] {
            return ObvMessengerConstants.showExperimentalFeature ? self.allCases : []
        }
        static func shownItemAt(item: Int) -> ExportsDatabasesAndCopyURLsItem? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }
        var cellIdentifier: String {
            switch self {
            case .copyDocumentsURL: return "CopyDocumentsURL"
            case .copyDatabaseURL: return "CopyAppDatabaseURL"
            case .exportAppDatabase: return "ExportAppDatabase"
            case .exportEngineDatabase: return "ExportEngineDatabase"
            case .exportTmpDirectory: return "ExportTmpDirectory"
            case .allowAnyAPIKeyActivation: return "AllowAPIKeyActivationWithBadKeyStatusCell"
            }
        }
    }
}


// MARK: - UITableViewDataSource

extension AdvancedSettingsViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.shown.count
    }
    
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section.shownSectionAt(section: section) else { return 0 }
        return section.numberOfItems
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cellInCaseOfError = UITableViewCell(style: .default, reuseIdentifier: nil)
        
        guard let section = Section.shownSectionAt(section: indexPath.section) else {
            assertionFailure()
            return cellInCaseOfError
        }

        switch section {
            
        case .clearCache:
            guard let item = ClearCacheItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .clearCache:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.clearCache
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            }
            
        case .troubleshooting:
            guard let item = TroubleshootingItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .syncAppDatabaseWithEngine:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var content = cell.defaultContentConfiguration()
                content.text = Strings.syncAppDatabaseWithEngine
                content.textProperties.color = AppTheme.shared.colorScheme.link
                cell.contentConfiguration = content
                return cell
            case .downloadMissingProfilePictures:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var content = cell.defaultContentConfiguration()
                content.text = Strings.downloadMissingProfilePictures
                content.textProperties.color = AppTheme.shared.colorScheme.link
                cell.contentConfiguration = content
                return cell
            }
            
        case .customKeyboards:
            guard let item = CustomKeyboardsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .customKeyboards:
                let cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                cell.selectionStyle = .none
                cell.title = Strings.allowCustomKeyboards
                cell.switchIsOn = ObvMessengerSettings.Advanced.allowCustomKeyboards
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.Advanced.allowCustomKeyboards = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadData()
                    }
                }
                return cell
            }
            
        case .websockedStatus:
            guard let item = WebsockedStatusItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .websockedStatus:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .value1, reuseIdentifier: item.cellIdentifier)
                if let status = currentWebSocketStatus {
                    cell.textLabel?.text = status.state.description
                    if let pingInterval = status.pingInterval {
                        cell.detailTextLabel?.text = pingIntervalFormatter(pingInterval: pingInterval)
                    } else {
                        cell.detailTextLabel?.text = nil
                    }
                } else {
                    cell.textLabel?.text = String(localized: "PLEASE_WAIT")
                    cell.detailTextLabel?.text = nil
                }
                cell.selectionStyle = .none
                let ownedCryptoId = self.ownedCryptoId
                Task {
                    let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
                    let newWebSocketStatus = try? await obvEngine.getWebSocketState(ownedIdentity: ownedCryptoId)
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(AdvancedSettingsViewController.websocketRefreshTimeInterval)) { [weak self] in
                        self?.currentWebSocketStatus = newWebSocketStatus
                        guard let tableView = self?.tableView else { return }
                        guard tableView.numberOfSections > indexPath.section && tableView.numberOfRows(inSection: indexPath.section) > indexPath.row else { return }
                        tableView.reconfigureRows(at: [indexPath])
                    }
                }
                return cell
            }
            
        case .diskUsage:
            guard let item = DiskUsageItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .diskUsage:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.diskUsageTitle
                cell.accessoryType = .disclosureIndicator
                return cell
            case .internalStorageExplorer:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.internalStorageExplorer
                cell.accessoryType = .disclosureIndicator
                return cell
            }
            
        case .logs:
            guard let item = LogsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .logsList:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.inAppLogs
                cell.accessoryType = .disclosureIndicator
                return cell
            case .enableLogs:
                let cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                cell.selectionStyle = .none
                cell.title = Strings.enableRunningLogs
                cell.switchIsOn = ObvMessengerSettings.Advanced.enableRunningLogs
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.Advanced.enableRunningLogs = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadData()
                    }
                }
                return cell
            case .betaButtonForShowingCoordinatorsQueue:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.showCoordinatorsQueue
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            }
            
        case .exportsDatabasesAndCopyURLs:
            guard let item = ExportsDatabasesAndCopyURLsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .copyDocumentsURL:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.copyDocumentsURL
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            case .copyDatabaseURL:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.copyAppDatabaseURL
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            case .exportAppDatabase:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.exportAppDatabase
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            case .exportEngineDatabase:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.exportEngineDatabase
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            case .exportTmpDirectory:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.textLabel?.text = Strings.exportTmpDirectory
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            case .allowAnyAPIKeyActivation:
                let _cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                _cell.selectionStyle = .none
                _cell.title = Strings.allowAPIKeyActivationWithBadKeyStatusTitle
                _cell.switchIsOn = ObvMessengerSettings.Subscription.allowAPIKeyActivationWithBadKeyStatus
                _cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.Subscription.allowAPIKeyActivationWithBadKeyStatus = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadData()
                    }
                }
                return _cell
            }
        }
    }

    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let section = Section.shownSectionAt(section: indexPath.section) else { assertionFailure(); return }
        switch section {
            
        case .clearCache:
            guard let item = ClearCacheItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .clearCache:
                MissingReceivedLinkPreviewFetcher.removeCachedPreviewFilesGenerated(olderThan: Date())
                Task { await CachedObvLinkMetadataManager.shared.clearCache() }
                tableView.deselectRow(at: indexPath, animated: true)
            }
            return
            
        case .troubleshooting:
            guard let item = TroubleshootingItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .downloadMissingProfilePictures:
                showHUD(type: .spinner)
                Task {
                    var finalHUDTypeToShow = ObvHUDType.checkmark
                    do { try await obvEngine.downloadMissingProfilePicturesForContacts() } catch { finalHUDTypeToShow = .xmark }
                    do { try await obvEngine.downloadMissingProfilePicturesForGroupsV1() } catch { finalHUDTypeToShow = .xmark }
                    do { try await obvEngine.downloadMissingProfilePicturesForGroupsV2() } catch { finalHUDTypeToShow = .xmark }
                    do { try await obvEngine.downloadMissingProfilePicturesForOwnedIdentities() } catch { finalHUDTypeToShow = .xmark }
                    await showThenHideHUD(type: finalHUDTypeToShow, andDeselectRowAt: indexPath)
                }
            case .syncAppDatabaseWithEngine:
                showHUD(type: .spinner)
                Task { [weak self] in
                    guard let self else { return }
                    assert(delegate != nil)
                    var finalHUDTypeToShow = ObvHUDType.checkmark
                    do {
                        try await delegate?.userRequestedAppDatabaseSyncWithEngine(advancedSettingsViewController: self)
                    } catch {
                        finalHUDTypeToShow = ObvHUDType.xmark
                    }
                    await showThenHideHUD(type: finalHUDTypeToShow, andDeselectRowAt: indexPath)
                }
            }
            
        case .customKeyboards:
            return
        case .websockedStatus:
            return
            
        case .diskUsage:
            guard let item = DiskUsageItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .diskUsage:
                let vc = DiskUsageViewController()
                present(vc, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            case .internalStorageExplorer:
                let vc = InternalStorageExplorerViewController(root: ObvUICoreDataConstants.ContainerURL.securityApplicationGroupURL)
                let nav = UINavigationController(rootViewController: vc)
                present(nav, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
                break
            }
            
            
        case .logs:
            guard let item = LogsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch (item) {
            case .logsList:
                let vc = DisplayableLogsHostingViewController()
                present(vc, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            case .enableLogs:
                return
            case .betaButtonForShowingCoordinatorsQueue:
                ObvMessengerInternalNotification.betaUserWantsToDebugCoordinatorsQueue
                    .postOnDispatchQueue()
                tableView.deselectRow(at: indexPath, animated: true)
            }
        case .exportsDatabasesAndCopyURLs:
            guard let item = ExportsDatabasesAndCopyURLsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .copyDocumentsURL:
                UIPasteboard.general.string = ObvUICoreDataConstants.ContainerURL.forDocuments.path
                tableView.deselectRow(at: indexPath, animated: true)
            case .copyDatabaseURL:
                UIPasteboard.general.string = ObvUICoreDataConstants.ContainerURL.forDatabase.path
                tableView.deselectRow(at: indexPath, animated: true)
            case .exportAppDatabase:
                guard let cell = tableView.cellForRow(at: indexPath) else { return }
                let appDatabaseURL = ObvUICoreDataConstants.ContainerURL.forDatabase.url
                guard FileManager.default.fileExists(atPath: appDatabaseURL.path) else { return }
                let ativityController = UIActivityViewController(activityItems: [appDatabaseURL], applicationActivities: nil)
                ativityController.popoverPresentationController?.sourceView = cell
                present(ativityController, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            case .exportEngineDatabase:
                guard let cell = tableView.cellForRow(at: indexPath) else { return }
                let appDatabaseURL = ObvUICoreDataConstants.ContainerURL.mainEngineContainer.appendingPathComponent("database")
                guard FileManager.default.fileExists(atPath: appDatabaseURL.path) else { return }
                let ativityController = UIActivityViewController(activityItems: [appDatabaseURL], applicationActivities: nil)
                ativityController.popoverPresentationController?.sourceView = cell
                present(ativityController, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            case .exportTmpDirectory:
                guard let cell = tableView.cellForRow(at: indexPath) else { return }
                let tmpURL = ObvUICoreDataConstants.ContainerURL.forTempFiles.url
                guard FileManager.default.fileExists(atPath: tmpURL.path) else { return }
                let ativityController = UIActivityViewController(activityItems: [tmpURL], applicationActivities: nil)
                ativityController.popoverPresentationController?.sourceView = cell
                present(ativityController, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            case .allowAnyAPIKeyActivation:
                return
            }
        }
    }
    
    
    @MainActor
    private func showThenHideHUD(type: ObvHUDType, andDeselectRowAt indexPath: IndexPath) async {
        showHUD(type: type)
        try? await Task.sleep(seconds: 2)
        hideHUD()
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section.shownSectionAt(section: section) else { assertionFailure(); return nil }
        switch section {
        case .clearCache: return Strings.cacheManagement
        case .troubleshooting: return Strings.troubleshooting
        case .customKeyboards: return Strings.customKeyboardsManagement
        case .websockedStatus: return Strings.webSocketStatus
        case .logs: return Strings.inAppLogs
        case .diskUsage: return nil
        case .exportsDatabasesAndCopyURLs: return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section.shownSectionAt(section: section) else { assertionFailure(); return nil }
        switch section {
        case .clearCache: return nil
        case .troubleshooting: return Strings.downloadMissingProfilePicturesExplanation
        case .customKeyboards: return Strings.customKeyboardsManagementExplanation
        case .websockedStatus: return nil
        case .diskUsage: return nil
        case .logs: return nil
        case .exportsDatabasesAndCopyURLs: return nil
        }
    }
    
}


extension AdvancedSettingsViewController {
    
    struct Strings {
        
        static let clearCache = NSLocalizedString("Clear cache", comment: "")
        static let downloadMissingProfilePictures = NSLocalizedString("DOWNLOAD_MISSING_PROFILE_PICTURES_BUTTON_TITLE", comment: "")
        static let downloadMissingProfilePicturesExplanation = NSLocalizedString("DOWNLOAD_MISSING_PROFILE_PICTURES_EXPLANATION", comment: "")
        static let copyDocumentsURL = NSLocalizedString("Copy Documents URL", comment: "Button title, only in dev mode")
        static let copyAppDatabaseURL = NSLocalizedString("Copy App Database URL", comment: "Button title, only in dev mode")
        static let cacheManagement = NSLocalizedString("Cache management", comment: "")
        static let troubleshooting = String(localized: "Troubleshooting")
        static let customKeyboardsManagement = NSLocalizedString("CUSTOM_KEYBOARD_MANAGEMENT", comment: "")
        static let customKeyboardsManagementExplanation = NSLocalizedString("CUSTOM_KEYBOARD_MANAGEMENT_EXPLANATION", comment: "")
        static let allowCustomKeyboards = NSLocalizedString("ALLOW_CUSTOM_KEYBOARDS", comment: "")
        static let websocketStatus = NSLocalizedString("Websocket status", comment: "")
        static let exportAppDatabase = NSLocalizedString("Export App Database", comment: "only in dev mode")
        static let exportEngineDatabase = NSLocalizedString("Export Engine Database", comment: "only in dev mode")
        static let exportTmpDirectory = NSLocalizedString("EXPORT_TMP_DIRECTORY", comment: "")
        static let allowAPIKeyActivationWithBadKeyStatusTitle = NSLocalizedString("Allow all api key activations", comment: "")
        static let webSocketStatus = NSLocalizedString("Websocket status", comment: "")
        static let diskUsageTitle = NSLocalizedString("DISK_USAGE", comment: "")
        static let internalStorageExplorer = NSLocalizedString("INTERNAL_STORAGE_EXPLORER", comment: "")
        static let enableRunningLogs = NSLocalizedString("ENABLE_RUNNING_LOGS", comment: "")
        static let inAppLogs = NSLocalizedString("IN_APP_LOGS", comment: "")
        static let showCoordinatorsQueue = NSLocalizedString("SHOW_CURRENT_COORDINATORS_OPS", comment: "")
        static let syncAppDatabaseWithEngine = String(localized: "SYNC_APP_DATABASE_WITH_ENGINE_BUTTON_TITLE")
    }
    
}

private extension URLSessionTask.State {
    
    var description: String {
        switch self {
        case .canceling: return "Canceling"
        case .completed: return "Completed"
        case .running: return "Running"
        case .suspended: return "Suspended"
        @unknown default:
            fatalError()
        }
    }
    
}


protocol AdvancedSettingsViewControllerDelegate: AnyObject {
    func userRequestedAppDatabaseSyncWithEngine(advancedSettingsViewController: AdvancedSettingsViewController) async throws
}
