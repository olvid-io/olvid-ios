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
import LinkPresentation
import OlvidUtils
import os.log


class AdvancedSettingsViewController: UITableViewController {

    let ownedCryptoId: ObvCryptoId
    
    let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: AdvancedSettingsViewController.self))

    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    private var currentWebSocketStatus: (state: URLSessionTask.State, pingInterval: TimeInterval?)?
    
    private var showExperimentalSettings: Bool {
        ObvMessengerConstants.developmentMode || ObvMessengerConstants.isTestFlight || ObvMessengerSettings.BetaConfiguration.showBetaSettings
    }
    
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
    
}


// MARK: - UITableViewDataSource

extension AdvancedSettingsViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return showExperimentalSettings ? 5 : 3
    }
    
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return 1 // Custom keyboards
        case 2: return 1 // WebSocket state
        case 3: return showExperimentalSettings ? 5 : 0
        case 4: return showExperimentalSettings ? 1 : 0 // For logs
        default: return 0
        }
    }
    
    @MainActor
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ClearCacheCell") ?? UITableViewCell(style: .default, reuseIdentifier: "ClearCacheCell")
            cell.textLabel?.text = Strings.clearCache
            cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
                guard let tableView = self?.tableView else { return }
                guard tableView.numberOfSections >= indexPath.section && tableView.numberOfRows(inSection: indexPath.section) >= indexPath.row else { return }
                tableView.reloadRows(at: [indexPath], with: .automatic)
            }
            return cell
        case 1:
            let cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: "AllowCustomKeyboardsCell")
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
        case 2:
            let cell = tableView.dequeueReusableCell(withIdentifier: "WebSocketStateCell") ?? UITableViewCell(style: .value1, reuseIdentifier: "WebSocketStateCell")
            if let status = currentWebSocketStatus {
                cell.textLabel?.text = status.state.description
                if let pingInterval = status.pingInterval {
                    cell.detailTextLabel?.text = pingIntervalFormatter(pingInterval: pingInterval)
                } else {
                    cell.detailTextLabel?.text = nil
                }
            } else {
                cell.textLabel?.text = CommonString.Word.Unavailable
                cell.detailTextLabel?.text = nil
            }
            cell.selectionStyle = .none
            let toDoIfPingsTakesTooLong = DispatchWorkItem { [weak self] in
                self?.currentWebSocketStatus = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                    guard let tableView = self?.tableView else { return }
                    guard tableView.numberOfSections > indexPath.section && tableView.numberOfRows(inSection: indexPath.section) > indexPath.row else { return }
                    tableView.reloadRows(at: [indexPath], with: .none)
                }
            }
            let ownedCryptoId = self.ownedCryptoId
            Task {
                let obvEngine = await NewAppStateManager.shared.waitUntilAppIsInitializedAndMetaFlowControllerViewDidAppearAtLeastOnce()
                DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5), execute: toDoIfPingsTakesTooLong)
                obvEngine.getWebSocketState(ownedIdentity: ownedCryptoId) { [weak self] result in
                    toDoIfPingsTakesTooLong.cancel()
                    switch result {
                    case .failure:
                        break
                    case .success(let webSocketStatus):
                        self?.currentWebSocketStatus = webSocketStatus
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                        guard let tableView = self?.tableView else { return }
                        guard tableView.numberOfSections > indexPath.section && tableView.numberOfRows(inSection: indexPath.section) > indexPath.row else { return }
                        tableView.reloadRows(at: [indexPath], with: .none)
                    }
                }
            }
            return cell
        case 3:
            switch indexPath.row {
            case 0:
                let cell = tableView.dequeueReusableCell(withIdentifier: "CopyDocumentsURL") ?? UITableViewCell(style: .default, reuseIdentifier: "CopyDocumentsURL")
                cell.textLabel?.text = Strings.copyDocumentsURL
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            case 1:
                let cell = tableView.dequeueReusableCell(withIdentifier: "CopyAppDatabaseURL") ?? UITableViewCell(style: .default, reuseIdentifier: "CopyAppDatabaseURL")
                cell.textLabel?.text = Strings.copyAppDatabaseURL
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            case 2:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ExportAppDatabase") ?? UITableViewCell(style: .default, reuseIdentifier: "ExportAppDatabase")
                cell.textLabel?.text = Strings.exportAppDatabase
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            case 3:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ExportEngineDatabase") ?? UITableViewCell(style: .default, reuseIdentifier: "ExportEngineDatabase")
                cell.textLabel?.text = Strings.exportEngineDatabase
                cell.textLabel?.textColor = AppTheme.shared.colorScheme.link
                return cell
            case 4:
                let _cell = ObvTitleAndSwitchTableViewCell(reuseIdentifier: "AllowAPIKeyActivationWithBadKeyStatusCell")
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
            default:
                assertionFailure()
                return UITableViewCell()
            }
        case 4:
            switch indexPath.row {
            case 0:
                let cell = tableView.dequeueReusableCell(withIdentifier: "DisplayableLogs") ?? UITableViewCell(style: .default, reuseIdentifier: "DisplayableLogs")
                cell.textLabel?.text = "Logs"
                cell.accessoryType = .disclosureIndicator
                return cell
            default:
                assertionFailure()
                return UITableViewCell()
            }
        default:
            assertionFailure()
            return UITableViewCell()
        }
    }

    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch indexPath.section {
        case 0:
            LPMetadataProvider.removeCachedURLMetadata(olderThan: Date())
            tableView.deselectRow(at: indexPath, animated: true)
        case 1:
            break
        case 2:
            break
        case 3:
            switch indexPath.row {
            case 0:
                UIPasteboard.general.string = ObvMessengerConstants.containerURL.forDocuments.path
                tableView.deselectRow(at: indexPath, animated: true)
            case 1:
                UIPasteboard.general.string = ObvMessengerConstants.containerURL.forDatabase.path
                tableView.deselectRow(at: indexPath, animated: true)
            case 2:
                guard let cell = tableView.cellForRow(at: indexPath) else { return }
                let appDatabaseURL = ObvMessengerConstants.containerURL.forDatabase
                guard FileManager.default.fileExists(atPath: appDatabaseURL.path) else { return }
                let ativityController = UIActivityViewController(activityItems: [appDatabaseURL], applicationActivities: nil)
                ativityController.popoverPresentationController?.sourceView = cell
                present(ativityController, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            case 3:
                guard let cell = tableView.cellForRow(at: indexPath) else { return }
                let appDatabaseURL = ObvMessengerConstants.containerURL.mainEngineContainer.appendingPathComponent("database")
                guard FileManager.default.fileExists(atPath: appDatabaseURL.path) else { return }
                let ativityController = UIActivityViewController(activityItems: [appDatabaseURL], applicationActivities: nil)
                ativityController.popoverPresentationController?.sourceView = cell
                present(ativityController, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            default:
                return
            }
        case 4:
            let vc = DisplayableLogsHostingViewController()
            present(vc, animated: true) {
                tableView.deselectRow(at: indexPath, animated: true)
            }
        default:
            return
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0:
            return Strings.cacheManagement
        case 1:
            return Strings.customKeyboardsManagement
        case 2:
            return Strings.webSocketStatus
        default:
            return nil
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        switch section {
        case 1:
            return Strings.customKeyboardsManagementExplanation
        default:
            return nil
        }
    }
}


extension AdvancedSettingsViewController {
    
    struct Strings {
        
        static let clearCache = NSLocalizedString("Clear cache", comment: "")
        static let copyDocumentsURL = NSLocalizedString("Copy Documents URL", comment: "Button title, only in dev mode")
        static let copyAppDatabaseURL = NSLocalizedString("Copy App Database URL", comment: "Button title, only in dev mode")
        static let cacheManagement = NSLocalizedString("Cache management", comment: "")
        static let customKeyboardsManagement = NSLocalizedString("CUSTOM_KEYBOARD_MANAGEMENT", comment: "")
        static let customKeyboardsManagementExplanation = NSLocalizedString("CUSTOM_KEYBOARD_MANAGEMENT_EXPLANATION", comment: "")
        static let allowCustomKeyboards = NSLocalizedString("ALLOW_CUSTOM_KEYBOARDS", comment: "")
        static let websocketStatus = NSLocalizedString("Websocket status", comment: "")
        static let exportAppDatabase = NSLocalizedString("Export App Database", comment: "only in dev mode")
        static let exportEngineDatabase = NSLocalizedString("Export Engine Database", comment: "only in dev mode")
        static let allowAPIKeyActivationWithBadKeyStatusTitle = NSLocalizedString("Allow all api key activations", comment: "")
        static let webSocketStatus = NSLocalizedString("Websocket status", comment: "")
        
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
