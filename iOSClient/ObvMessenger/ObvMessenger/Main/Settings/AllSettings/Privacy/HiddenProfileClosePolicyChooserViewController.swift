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

class HiddenProfileClosePolicyChooserViewController: UITableViewController {

    init() {
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("HIDDEN_PROFILES", comment: "")
    }
    
    
    private enum Section: CaseIterable {
        case hiddenProfileClosePolicy
        case timeIntervalForBackgroundHiddenProfileClosePolicy
        static var shown: [Section] {
            var result = [Section]()
            result += [hiddenProfileClosePolicy]
            if ObvMessengerSettings.Privacy.hiddenProfileClosePolicy == .background {
                result += [timeIntervalForBackgroundHiddenProfileClosePolicy]
            }
            return result
        }
        var numberOfItems: Int {
            switch self {
            case .hiddenProfileClosePolicy: return HiddenProfileClosePolicyItem.shown.count
            case .timeIntervalForBackgroundHiddenProfileClosePolicy: return TimeIntervalForBackgroundHiddenProfileClosePolicyItem.shown.count
            }
        }
        static func shownSectionAt(section: Int) -> Section? {
            return shown[safe: section]
        }
    }
    
    
    struct HiddenProfileClosePolicyItem {
        static var shown: [ObvMessengerSettings.Privacy.HiddenProfileClosePolicy] {
            return ObvMessengerSettings.Privacy.HiddenProfileClosePolicy.allCases.sorted(by: { $0.rawValue < $1.rawValue })
        }
        static func shownItemAt(item: Int) -> ObvMessengerSettings.Privacy.HiddenProfileClosePolicy? {
            return shown[safe: item]
        }
        static func cellIdentifier(for policy: ObvMessengerSettings.Privacy.HiddenProfileClosePolicy) -> String {
            switch policy {
            case .manualSwitching: return "manualSwitching"
            case .screenLock: return "screenLock"
            case .background: return "background"
            }
        }
    }
    
    
    struct TimeIntervalForBackgroundHiddenProfileClosePolicyItem {
        static var shown: [ObvMessengerSettings.Privacy.TimeIntervalForBackgroundHiddenProfileClosePolicy] {
            return ObvMessengerSettings.Privacy.TimeIntervalForBackgroundHiddenProfileClosePolicy.allCases.sorted(by: { $0.rawValue < $1.rawValue })
        }
        static func shownItemAt(item: Int) -> ObvMessengerSettings.Privacy.TimeIntervalForBackgroundHiddenProfileClosePolicy? {
            return shown[safe: item]
        }
        static func cellIdentifier(for timeInverval: ObvMessengerSettings.Privacy.TimeIntervalForBackgroundHiddenProfileClosePolicy) -> String {
            switch timeInverval {
            case .immediately: return "immediately"
            case .tenSeconds: return "tenSeconds"
            case .thirtySeconds: return "thirtySeconds"
            case .oneMinute: return "oneMinute"
            case .twoMinutes: return "twoMinutes"
            case .fiveMinutes: return "fiveMinutes"
            }
        }
    }

    
    // MARK: - Table view data source

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
            
        case .hiddenProfileClosePolicy:
            guard let policy = HiddenProfileClosePolicyItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            let cell = UITableViewCell(style: .default, reuseIdentifier: HiddenProfileClosePolicyItem.cellIdentifier(for: policy))
            switch policy {
            case .manualSwitching:
                cell.textLabel?.text = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_ACTION_MANUAL_SWITCHING", comment: "")
            case .screenLock:
                cell.textLabel?.text = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_ACTION_SCREEN_LOCK", comment: "")
            case .background:
                cell.textLabel?.text = NSLocalizedString("ALERT_CHOOSE_HIDDEN_PROFILE_CLOSE_POLICY_ACTION_BACKGROUND", comment: "")
            }
            cell.selectionStyle = .none
            if policy == ObvMessengerSettings.Privacy.hiddenProfileClosePolicy {
                cell.accessoryType = .checkmark
            }
            return cell

        case .timeIntervalForBackgroundHiddenProfileClosePolicy:
            guard let timeInterval = TimeIntervalForBackgroundHiddenProfileClosePolicyItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            let cell = UITableViewCell(style: .default, reuseIdentifier: TimeIntervalForBackgroundHiddenProfileClosePolicyItem.cellIdentifier(for: timeInterval))
            switch timeInterval {
            case .immediately:
                cell.textLabel?.text = CommonString.Word.Immediately
            case .tenSeconds:
                cell.textLabel?.text = NSLocalizedString("AFTER_TEN_SECONDS", comment: "")
            case .thirtySeconds:
                cell.textLabel?.text = NSLocalizedString("AFTER_THIRTY_SECONDS", comment: "")
            case .oneMinute:
                cell.textLabel?.text = NSLocalizedString("AFTER_ONE_MINUTE", comment: "")
            case .twoMinutes:
                cell.textLabel?.text = NSLocalizedString("AFTER_TWO_MINUTE", comment: "")
            case .fiveMinutes:
                cell.textLabel?.text = NSLocalizedString("AFTER_FIVE_MINUTE", comment: "")
            }
            cell.selectionStyle = .none
            if timeInterval == ObvMessengerSettings.Privacy.timeIntervalForBackgroundHiddenProfileClosePolicy {
                cell.accessoryType = .checkmark
            }
            return cell
        }
        
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard let section = Section.shownSectionAt(section: indexPath.section) else {
            assertionFailure()
            return
        }

        switch section {

        case .hiddenProfileClosePolicy:
            guard let selectedPolicy = HiddenProfileClosePolicyItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            ObvMessengerSettings.Privacy.hiddenProfileClosePolicy = selectedPolicy

        case .timeIntervalForBackgroundHiddenProfileClosePolicy:
            guard let selectedTimeInterval = TimeIntervalForBackgroundHiddenProfileClosePolicyItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            ObvMessengerSettings.Privacy.timeIntervalForBackgroundHiddenProfileClosePolicy = selectedTimeInterval
        }
                
        tableView.reloadData()
    }

    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section.shownSectionAt(section: section) else {
            assertionFailure()
            return nil
        }
        switch section {
        case .hiddenProfileClosePolicy:
            return CommonString.Title.closeOpenHiddenProfile
        case .timeIntervalForBackgroundHiddenProfileClosePolicy:
            return CommonString.Title.timeIntervalForBackgroundHiddenProfileClosePolicy
        }
    }
    
}
