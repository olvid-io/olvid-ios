/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

    /// The one task that refreshes the websocket status, owned by this screen and stopped when it goes.
    ///
    /// **It used to be started from `cellForRowAt`, and each one perpetuated itself**: the task slept two seconds and called `reconfigureRows`, which called
    /// `cellForRowAt`, which started another. So a chain was born every time that row was built for any other reason — every `reloadData()`, every visit to
    /// this screen, and every time the row was scrolled back into view — and none of them ever ended. With several running, the row was re-measured several
    /// times every two seconds, and a re-measure during a scroll is a jump. One task, started when the screen appears and cancelled when it leaves.
    private var webSocketStatusRefreshTask: Task<Void, Never>?


    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Advanced
    }

    deinit {
        // **Cancelled here as well as in `viewWillDisappear`, because a task is not cancelled by being released.** This screen's own teardown is the only
        // thing that used to stop the poll, and a screen can be deallocated without it — the settings flow going away while some other screen is the one
        // being popped. The task holds this controller weakly, so nothing kept it alive; it simply went on running. Belt and braces with the guard in the
        // loop: this ends it at once, that one ends it at the next tick.
        webSocketStatusRefreshTask?.cancel()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        startRefreshingTheWebSocketStatusIfRequired()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        webSocketStatusRefreshTask?.cancel()
        webSocketStatusRefreshTask = nil
    }


    /// Refreshes the websocket status every couple of seconds, for as long as this screen is on show.
    private func startRefreshingTheWebSocketStatusIfRequired() {

        guard webSocketStatusRefreshTask == nil else { return }
        let ownedCryptoId = self.ownedCryptoId

        webSocketStatusRefreshTask = Task { [weak self] in
            let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
            while !Task.isCancelled {
                let status: (state: URLSessionTask.State, pingInterval: TimeInterval?)? = await withCheckedContinuation { continuation in
                    let hasResumed = OSAllocatedUnfairLock<Bool>(initialState: false)
                    Task {
                        await obvEngine.getWebSocketState(ownedIdentity: ownedCryptoId) { result in
                            // The engine's callback is not promised to arrive exactly once, and resuming a continuation twice traps.
                            let isOurs = hasResumed.withLock { alreadyResumed in
                                guard !alreadyResumed else { return false }
                                alreadyResumed = true
                                return true
                            }
                            guard isOurs else { return }
                            continuation.resume(returning: try? result.get())
                        }
                    }
                }
                guard !Task.isCancelled else { return }

                // **The `guard` for a screen that has gone has to end the *task*, and it used to end the closure.** Written as
                // `await MainActor.run { guard let self else { return } … }`, its `return` leaves the closure and the loop carries on — so a screen that was
                // deallocated left this asking the engine for the websocket state every two seconds, for the lifetime of the process, with nothing to show
                // it to. Answering whether the screen is still there, and reading the answer out here, is what makes the guard mean what it looks like it
                // means.
                let theScreenIsStillThere = await MainActor.run { () -> Bool in
                    guard let self else { return false }
                    self.currentWebSocketStatus = status
                    self.reconfigureTheWebSocketRow()
                    return true
                }
                guard theScreenIsStillThere else { return }

                try? await Task.sleep(seconds: Double(Self.websocketRefreshTimeInterval))
            }
        }

    }


    private func reconfigureTheWebSocketRow() {
        guard let section = Section.shown.firstIndex(of: .websockedStatus) else { return }
        let indexPath = IndexPath(row: 0, section: section)
        guard indexPath.section < tableView.numberOfSections else { return }
        guard indexPath.row < tableView.numberOfRows(inSection: indexPath.section) else { return }
        tableView.reconfigureRows(at: [indexPath])
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
        case consoleLogs
        case exportsDatabasesAndCopyURLs

        static var shown: [Section] {
            // **The diagnostics and the inbox maintenance are no longer here**, having moved to a panel of their own in the main settings. They were the only
            // two things in this drawer addressed to a reader rather than to us — one says *send us this*, the other *tap this and wait* — and a reader
            // following a support mail should not have to walk past caches, websocket status and database exports to reach them.
            var result = [Section.clearCache, .troubleshooting, .customKeyboards, .websockedStatus, .diskUsage]
            if ObvMessengerConstants.showExperimentalFeature {
                result += [Section.logs, .consoleLogs, .exportsDatabasesAndCopyURLs]
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
            case .consoleLogs: return ConsoleLogsItem.shown.count
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
    
    /// The system console, which is **not** the in-app logs of ``LogsItem`` above and is in a section of its own for exactly that reason: those
    /// are files a reader can list and share, this reaches the unified log and needs the device attached to be read at all.
    private enum ConsoleLogsItem: CaseIterable {
        case logTranscriptFrames
        static var shown: [ConsoleLogsItem] {
            return ObvMessengerConstants.showExperimentalFeature ? self.allCases : []
        }
        static func shownItemAt(item: Int) -> ConsoleLogsItem? {
            guard item < shown.count else { assertionFailure(); return nil }
            return shown[item]
        }
        var cellIdentifier: String {
            switch self {
            case .logTranscriptFrames: return "LogTranscriptFrames"
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
                    ObvDisplayableLogs.shared.doEnableRunningLogs(value)
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
            
        case .consoleLogs:
            guard let item = ConsoleLogsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            switch item {
            case .logTranscriptFrames:
                let cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                cell.selectionStyle = .none
                cell.title = Strings.logTranscriptFrames
                cell.switchIsOn = ObvMessengerSettings.Advanced.logTranscriptFrames
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.Advanced.logTranscriptFrames = value
                }
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
        case .consoleLogs:
            guard let item = ConsoleLogsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .logTranscriptFrames:
                return
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
        case .consoleLogs: return Strings.systemConsoleLogs
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
        case .consoleLogs: return Strings.logTranscriptFramesExplanation
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
        // English as the key, like `Cache management` and `Troubleshooting` beside them rather than the shouting-case keys elsewhere in this
        // struct: those have catalogue entries already, and a key with none renders as the key itself — which in a TestFlight build a tester can
        // reach is a screen showing `SYSTEM_CONSOLE_LOGS`.
        static let systemConsoleLogs = String(localized: "System console logs")
        static let logTranscriptFrames = String(localized: "Log discussion frames")
        static let logTranscriptFramesExplanation = String(localized: "In-app logs, above, are written to files you can view and share. This is different: it goes to the system console, is meant for developers investigating scrolling, and writes one entry for every frame displayed — several thousand a minute while a discussion is moving. Leave it off unless you have been asked to turn it on.")
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


