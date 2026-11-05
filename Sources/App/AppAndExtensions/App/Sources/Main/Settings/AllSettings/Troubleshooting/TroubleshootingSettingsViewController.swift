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
import ObvEngine
import ObvUI
import ObvDesignSystem
import ObvAppCoreConstants


protocol TroubleshootingSettingsViewControllerDelegate: AnyObject {
    @MainActor func userRequestedDrainOfTheEngineInbox(_ vc: TroubleshootingSettingsViewController, run: ObvInboxDrainInProgress) async -> ObvInboxDrainReport
}


/// The two things a reader can do about a fault on their own device, and the one thing they can send us about it.
///
/// **Its own panel rather than two sections of the advanced settings, because those are two different audiences.** The advanced settings are a developer's
/// drawer — caches, websocket status, disk usage, database exports — where these two are support instructions: *tap this and send us what it says*, and *tap
/// this and leave the screen open*. A reader following a support mail should not have to walk past six things that will not help them.
@MainActor
final class TroubleshootingSettingsViewController: UITableViewController {

    private let ownedCryptoId: ObvCryptoId
    private let obvEngine: ObvEngine

    weak var delegate: TroubleshootingSettingsViewControllerDelegate?

    init(ownedCryptoId: ObvCryptoId, obvEngine: ObvEngine, delegate: TroubleshootingSettingsViewControllerDelegate) {
        self.ownedCryptoId = ownedCryptoId
        self.obvEngine = obvEngine
        super.init(style: Self.settingsTableStyle)
        self.delegate = delegate
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Strings.troubleshooting
    }


    private enum Item: CaseIterable {

        case engineDiagnostics
        case inboxMaintenance

        var title: String {
            switch self {
            case .engineDiagnostics: return Strings.engineDiagnostics
            case .inboxMaintenance: return Strings.inboxMaintenance
            }
        }

        var explanation: String? {
            switch self {
            case .engineDiagnostics: return Strings.engineDiagnosticsExplanation
            case .inboxMaintenance: return Strings.inboxMaintenanceExplanation
            }
        }

        var cellIdentifier: String {
            switch self {
            case .engineDiagnostics: return "EngineDiagnosticsCell"
            case .inboxMaintenance: return "InboxMaintenanceCell"
            }
        }

    }


    // MARK: UITableViewDataSource

    override func numberOfSections(in tableView: UITableView) -> Int {
        // A section each, so that every one can carry the sentence saying what it is for. These are the rows a reader is most likely to reach on somebody
        // else's instruction, and no name among them says what it does.
        Item.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        1
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let item = Item.allCases[safe: indexPath.section] else { assertionFailure(); return UITableViewCell() }
        switch item {
        case .engineDiagnostics, .inboxMaintenance:
            let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
            cell.textLabel?.text = item.title
            cell.accessoryType = .disclosureIndicator
            return cell
        }
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        Item.allCases[safe: section]?.explanation
    }


    // MARK: UITableViewDelegate

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        guard let item = Item.allCases[safe: indexPath.section] else { assertionFailure(); return }
        tableView.deselectRow(at: indexPath, animated: true)

        switch item {

        case .engineDiagnostics:
            let vc = EngineDiagnosticsHostingView(delegate: self)
            navigationController?.pushViewController(vc, animated: true)

        case .inboxMaintenance:
            let vc = InboxMaintenanceHostingView(delegate: self)
            navigationController?.pushViewController(vc, animated: true)

        }

    }

}


// MARK: - Implementing EngineDiagnosticsHostingViewDelegate

extension TroubleshootingSettingsViewController: EngineDiagnosticsHostingViewDelegate {

    /// The engine call is made here rather than in the hosting controller, which exists only to satisfy what UIKit insists on.
    func getAsyncStreamOfEngineDiagnostics(_ vc: EngineDiagnosticsHostingView) throws -> AsyncStream<ObvEngineDiagnostic> {
        return try obvEngine.getAsyncStreamOfEngineDiagnostics()
    }


    func getLastInboxDrainReport(_ vc: EngineDiagnosticsHostingView) -> ObvInboxDrainReport? {
        return ObvInboxDrainReport.lastStored(in: UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier))
    }

}


// MARK: - Implementing InboxMaintenanceHostingViewDelegate

extension TroubleshootingSettingsViewController: InboxMaintenanceHostingViewDelegate {

    /// Forwarded rather than answered here: the drain lives on the bootstrap coordinator, five hops up, and this screen is one link of that chain like every
    /// other.
    func userRequestedDrainOfTheEngineInbox(_ vc: InboxMaintenanceHostingView, run: ObvInboxDrainInProgress) async -> ObvInboxDrainReport {
        guard let delegate else {
            assertionFailure("The troubleshooting screen has no delegate, so the inbox maintenance cannot be run")
            return .couldNotBeRun(trigger: .userRequestedItInTheSettings)
        }
        return await delegate.userRequestedDrainOfTheEngineInbox(self, run: run)
    }

}


// MARK: - Strings

extension TroubleshootingSettingsViewController {

    private struct Strings {
        static let troubleshooting = String(localized: "Troubleshooting")
        static let engineDiagnostics = String(localized: "Diagnostics")
        static let engineDiagnosticsExplanation = String(localized: "Figures about what this device is holding and doing. If we have asked you what is going on, this is the screen to send us.")
        // **Named for what the reader gets, not for how it is done.** It was *Inbox maintenance*, which is the mechanism's name: a reader who has not read
        // the code does not know they have an inbox, and would not guess that this is what to tap when messages are slow. The footer below says the rest.
        // The name also survives the mechanism changing again, which it has twice.
        static let inboxMaintenance = String(localized: "Catch up on messages")
        static let inboxMaintenanceExplanation = String(localized: "If messages are slow to arrive, or a great many have built up, this does the work of catching up now rather than waiting until your device is idle and charging.")
    }

}


private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
