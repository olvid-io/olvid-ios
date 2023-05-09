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

import ObvUI
import UIKit


enum ComposeMessageViewSettingsViewControllerInput {
    case local(configuration: PersistedDiscussionLocalConfiguration)
    case global
}

@available(iOS 15, *)
final class ComposeMessageViewSettingsViewController: UITableViewController {

    var notificationTokens = [NSObjectProtocol]()
    let input: ComposeMessageViewSettingsViewControllerInput

    init(input: ComposeMessageViewSettingsViewControllerInput) {
        self.input = input
        super.init(style: .insetGrouped)

        observePreferredComposeMessageViewActionsDidChangeNotifications()
        observeDiscussionLocalConfigurationHasBeenUpdatedNotifications()
    }

    private func observePreferredComposeMessageViewActionsDidChangeNotifications() {
        let token = ObvMessengerSettingsNotifications.observePreferredComposeMessageViewActionsDidChange(queue: OperationQueue.main) { [weak self] in
            assert(Thread.isMainThread)
            guard let _self = self else { return }
            guard let section = _self.shownSections.firstIndex(of: .preferredComposeMessageViewActionsOrder) else { assertionFailure(); return }
            let cells = _self.tableView.visibleCells.compactMap { $0 as? Cell }
            _self.tableView.beginUpdates()
            let actions = ObvMessengerSettings.Interface.preferredComposeMessageViewActions
            for index in 0..<actions.count {
                let action = actions[index]
                guard let cell = (cells.first { $0.action == action }) else { continue }
                guard let srcIndexPath = _self.tableView.indexPath(for: cell) else { assertionFailure(); continue }
                let destIndexPath = IndexPath(row: index, section: section)
                guard srcIndexPath != destIndexPath else { continue }
                _self.tableView.moveRow(at: srcIndexPath, to: destIndexPath)
            }
            _self.tableView.endUpdates()
            if let section = _self.shownSections.firstIndex(of: .resetPreferredComposeMessageViewActions) {
                _self.tableView.reloadRows(at: [IndexPath.init(row: 0, section: section)], with: .none)
            }
        }
        self.notificationTokens.append(token)
    }

    private func observeDiscussionLocalConfigurationHasBeenUpdatedNotifications() {
        let token = ObvMessengerInternalNotification.observeDiscussionLocalConfigurationHasBeenUpdated(queue: OperationQueue.main) { [weak self] value, objectId in
            guard let _self = self else { return }
            guard case .defaultEmoji = value else { return }
            guard let sectionToReload = _self.shownSections.firstIndex(of: .defaultEmojiAtDiscussionLevel) else { return }
            _self.tableView.reloadSections([sectionToReload], with: .none)
        }
        self.notificationTokens.append(token)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.tableView.isEditing = true
        self.tableView.allowsSelectionDuringEditing = true
        self.title = NSLocalizedString("NEW_COMPOSE_MESSAGE_VIEW_PREFERENCES", comment: "ComposeMessageViewSettingsViewController title")
    }

    private func processPreferredComposeMessageViewActionsDidChangeNotifications() {
        assert(Thread.isMainThread)
        guard let section = shownSections.firstIndex(of: .preferredComposeMessageViewActionsOrder) else { assertionFailure(); return }
        let cells = tableView.visibleCells.compactMap { $0 as? Cell }
        tableView.beginUpdates()
        let actions = ObvMessengerSettings.Interface.preferredComposeMessageViewActions
        for index in 0..<actions.count {
            let action = actions[index]
            guard let cell = (cells.first { $0.action == action }) else { continue }
            guard let srcIndexPath = tableView.indexPath(for: cell) else { assertionFailure(); continue }
            let destIndexPath = IndexPath(row: index, section: section)
            guard srcIndexPath != destIndexPath else { continue }
            tableView.moveRow(at: srcIndexPath, to: destIndexPath)
        }
        tableView.endUpdates()
        tableView.reloadSections([section], with: .none)
    }

    private enum Section: CaseIterable {
        case preferredComposeMessageViewActionsOrder
        case resetPreferredComposeMessageViewActions
        case defaultEmojiAtAppLevel
        case defaultEmojiAtDiscussionLevel

        var canEditOrMoveRow: Bool {
            switch self {
            case .preferredComposeMessageViewActionsOrder:
                return true
            case .defaultEmojiAtAppLevel,
                    .defaultEmojiAtDiscussionLevel,
                    .resetPreferredComposeMessageViewActions:
                return false
            }
        }
        
        var isAvailableInGlobalMode: Bool {
            switch self {
            case .preferredComposeMessageViewActionsOrder,
                    .resetPreferredComposeMessageViewActions,
                    .defaultEmojiAtAppLevel:
                return true
            case .defaultEmojiAtDiscussionLevel:
                return false
            }
        }
                 
    }
    
    private var shownSections: [Section] {
        switch input {
        case .local:
            return [.preferredComposeMessageViewActionsOrder, .resetPreferredComposeMessageViewActions, .defaultEmojiAtAppLevel, .defaultEmojiAtDiscussionLevel]
        case .global:
            return [.preferredComposeMessageViewActionsOrder, .resetPreferredComposeMessageViewActions, .defaultEmojiAtAppLevel]
        }
    }
    
    
    private func sectionNumberOf(section: Section) -> Int? {
        shownSections.firstIndex(of: section)
    }

    
    private enum ResetPreferredComposeMessageViewRow {
        case reset
    }
    private let shownResetPreferredComposeMessageViewRows: [ResetPreferredComposeMessageViewRow] = [.reset]

    private func indexPathOf(_ row: ResetPreferredComposeMessageViewRow) -> IndexPath? {
        guard let sectionNumber = sectionNumberOf(section: .resetPreferredComposeMessageViewActions),
              let rowNumber = shownResetPreferredComposeMessageViewRows.firstIndex(of: row) else { return nil }
        return IndexPath(row: rowNumber, section: sectionNumber)
    }
    
    private enum EmojiRow {
        case changeDefaultEmoji
        case resetDefaultEmoji
    }
    private let shownEmojiRows: [EmojiRow] = [.changeDefaultEmoji, .resetDefaultEmoji]

    private func indexPathOf(_ row: EmojiRow, inSection section: Section) -> IndexPath? {
        guard section == .defaultEmojiAtDiscussionLevel || section == .defaultEmojiAtAppLevel else { return nil }
        guard let sectionNumber = sectionNumberOf(section: section),
              let rowNumber = shownEmojiRows.firstIndex(of: row) else { return nil }
        return IndexPath(row: rowNumber, section: sectionNumber)
    }

    private var preferredActions: [NewComposeMessageViewAction] {
        ObvMessengerSettings.Interface.preferredComposeMessageViewActions.filter({ $0.canBeReordered })
    }

    
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        shownSections.count
    }


    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard section < shownSections.count else { assertionFailure(); return 0 }
        let section = shownSections[section]
        switch section {
        case .preferredComposeMessageViewActionsOrder:
            return preferredActions.count
        case .resetPreferredComposeMessageViewActions:
            return shownResetPreferredComposeMessageViewRows.count
        case .defaultEmojiAtAppLevel:
            return shownEmojiRows.count
        case .defaultEmojiAtDiscussionLevel:
            return shownEmojiRows.count
        }
    }

    
    private class Cell: UITableViewCell {
        let action: NewComposeMessageViewAction
        init(action: NewComposeMessageViewAction) {
            self.action = action
            super.init(style: .default, reuseIdentifier: "PreferredActionCell")
        }
        required init?(coder aDecoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }

    private var currentActionsIsDefault: Bool {
        ObvMessengerSettings.Interface.preferredComposeMessageViewActions == NewComposeMessageViewAction.defaultActions
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard indexPath.section < shownSections.count else { assertionFailure(); return UITableViewCell() }
        let section = shownSections[indexPath.section]
        
        switch section {
        case .preferredComposeMessageViewActionsOrder:
            guard indexPath.row < preferredActions.count else { assertionFailure(); return UITableViewCell() }
            let action = preferredActions[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "PreferredActionCell") ?? Cell(action: action)
            cell.selectionStyle = .none
            var configuration = cell.defaultContentConfiguration()
            configuration.text = action.title
            configuration.image = UIImage(systemIcon: action.icon)
            cell.contentConfiguration = configuration
            return cell
        case .resetPreferredComposeMessageViewActions:
            guard indexPath.row < shownResetPreferredComposeMessageViewRows.count else { assertionFailure(); return UITableViewCell() }
            switch shownResetPreferredComposeMessageViewRows[indexPath.row] {
            case .reset:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ResetPreferredActionCell") ?? UITableViewCell(style: .default, reuseIdentifier: "ResetPreferredActionCell")
                cell.isUserInteractionEnabled = !currentActionsIsDefault
                var configuration = cell.defaultContentConfiguration()
                configuration.text = NSLocalizedString("RESET_COMPOSE_MESSAGE_VIEW_ACTIONS_ORDER", comment: "reset compose view message action title")
                if cell.isUserInteractionEnabled {
                    configuration.textProperties.color = AppTheme.shared.colorScheme.link
                }
                cell.contentConfiguration = configuration
                return cell
            }
        case .defaultEmojiAtAppLevel:
            guard indexPath.row < shownEmojiRows.count else { assertionFailure(); return UITableViewCell() }
            switch shownEmojiRows[indexPath.row] {
            case .changeDefaultEmoji:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ChangeDefaultEmojiAppLevel") ?? UITableViewCell(style: .default, reuseIdentifier: "ChangeDefaultEmojiAppLevel")
                var cellConfiguration = cell.defaultContentConfiguration()
                cellConfiguration.text = NSLocalizedString("DEFAULT_EMOJI", comment: "")
                cell.contentConfiguration = cellConfiguration
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
                label.textAlignment = .right
                label.textColor = AppTheme.shared.colorScheme.secondaryLabel
                label.text = ObvMessengerSettings.Emoji.defaultEmojiButton ?? ObvMessengerConstants.defaultEmoji
                cell.accessoryView = label
                return cell
            case .resetDefaultEmoji:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ResetDefaultEmojiAppLevel") ?? UITableViewCell(style: .default, reuseIdentifier: "ResetDefaultEmojiAppLevel")
                cell.isUserInteractionEnabled = ObvMessengerSettings.Emoji.defaultEmojiButton != nil && ObvMessengerSettings.Emoji.defaultEmojiButton != ObvMessengerConstants.defaultEmoji
                var configuration = cell.defaultContentConfiguration()
                configuration.text = NSLocalizedString("RESET_DISCUSSION_EMOJI_TO_DEFAULT", comment: "")
                if cell.isUserInteractionEnabled {
                    configuration.textProperties.color = AppTheme.shared.colorScheme.link
                }
                cell.contentConfiguration = configuration
                return cell
            }
        case .defaultEmojiAtDiscussionLevel:
            guard indexPath.row < shownEmojiRows.count else { assertionFailure(); return UITableViewCell() }
            guard case .local(let discussionConfiguration) = input else { assertionFailure(); return UITableViewCell() }
            switch shownEmojiRows[indexPath.row] {
            case .changeDefaultEmoji:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ChangeDefaultEmojiDiscussionLevel") ?? UITableViewCell(style: .default, reuseIdentifier: "ChangeDefaultEmojiDiscussionLevel")
                var cellConfiguration = cell.defaultContentConfiguration()
                cellConfiguration.text = NSLocalizedString("DISCUSSION_QUICK_EMOJI", comment: "")
                cell.contentConfiguration = cellConfiguration
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
                label.textAlignment = .right
                label.textColor = AppTheme.shared.colorScheme.secondaryLabel
                if let defaultEmoji = discussionConfiguration.defaultEmoji {
                    label.text = defaultEmoji
                } else {
                    label.text = "\(CommonString.Word.Default) (\(ObvMessengerSettings.Emoji.defaultEmojiButton ?? ObvMessengerConstants.defaultEmoji))"
                }
                cell.accessoryView = label
                return cell
            case .resetDefaultEmoji:
                let cell = tableView.dequeueReusableCell(withIdentifier: "ResetDefaultEmojiDiscussionLevel") ?? UITableViewCell(style: .default, reuseIdentifier: "ResetDefaultEmojiDiscussionLevel")
                cell.isUserInteractionEnabled = discussionConfiguration.defaultEmoji != nil
                var configuration = cell.defaultContentConfiguration()
                configuration.text = NSLocalizedString("RESET_DISCUSSION_EMOJI_TO_DEFAULT_DISCUSSION_LEVEL", comment: "")
                if cell.isUserInteractionEnabled {
                    configuration.textProperties.color = AppTheme.shared.colorScheme.link
                }
                cell.contentConfiguration = configuration
                return cell
            }
        }
    }

    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {

        guard section < shownSections.count else { assertionFailure(); return nil }
        let section = shownSections[section]

        switch section {
        case .preferredComposeMessageViewActionsOrder:
            return NSLocalizedString("NEW_COMPOSE_MESSAGE_VIEW_ACTION_ORDER_HEADER", comment: "Section header")
        case .defaultEmojiAtAppLevel:
            return NSLocalizedString("DEFAULT_EMOJI_AT_APP_LEVEL", comment: "Section header")
        case .resetPreferredComposeMessageViewActions, .defaultEmojiAtDiscussionLevel:
            return nil
        }
        
    }

    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {

        guard section < shownSections.count else { assertionFailure(); return nil }
        let section = shownSections[section]

        switch section {
        case .preferredComposeMessageViewActionsOrder:
            return NSLocalizedString("NEW_COMPOSE_MESSAGE_VIEW_ACTION_ORDER_FOOTER", comment: "Section footer")
        case .defaultEmojiAtAppLevel:
            if shownSections.contains(.defaultEmojiAtDiscussionLevel) {
                return nil
            } else {
                return NSLocalizedString("QUICK_EMOJI_EXPLANATION", comment: "Section footer")
            }
        case .defaultEmojiAtDiscussionLevel:
            return NSLocalizedString("QUICK_EMOJI_EXPLANATION", comment: "Section footer")
        case .resetPreferredComposeMessageViewActions:
            return nil
        }
        
    }
    

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {

        guard indexPath.section < shownSections.count else { assertionFailure(); return }
        let section = shownSections[indexPath.section]

        switch section {
            
        case .preferredComposeMessageViewActionsOrder:
            break
            
        case .resetPreferredComposeMessageViewActions:
            guard indexPath.row < shownResetPreferredComposeMessageViewRows.count else { assertionFailure(); return }
            switch shownResetPreferredComposeMessageViewRows[indexPath.row] {
            case .reset:
                ObvMessengerSettings.Interface.preferredComposeMessageViewActions = NewComposeMessageViewAction.defaultActions
            }
            
        case .defaultEmojiAtAppLevel:
            guard indexPath.row < shownEmojiRows.count else { assertionFailure(); return }
            let indexPathsToReload = [
                indexPathOf(.changeDefaultEmoji, inSection: .defaultEmojiAtAppLevel),
                indexPathOf(.resetDefaultEmoji, inSection: .defaultEmojiAtAppLevel),
                indexPathOf(.changeDefaultEmoji, inSection: .defaultEmojiAtDiscussionLevel),
            ].compactMap({ $0 })
            switch shownEmojiRows[indexPath.row] {
            case .changeDefaultEmoji:
                let model = EmojiPickerViewModel(selectedEmoji: ObvMessengerSettings.Emoji.defaultEmojiButton ?? ObvMessengerConstants.defaultEmoji) { emoji in
                    ObvMessengerSettings.Emoji.defaultEmojiButton = emoji
                    tableView.reloadRows(at: indexPathsToReload, with: .automatic)
                }
                let vc = EmojiPickerHostingViewController(model: model)
                if let sheet = vc.sheetPresentationController {
                    sheet.detents = [ .medium() ]
                    sheet.prefersGrabberVisible = true
                    sheet.preferredCornerRadius = 30.0
                }
                present(vc, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            case .resetDefaultEmoji:
                ObvMessengerSettings.Emoji.defaultEmojiButton = ObvMessengerConstants.defaultEmoji
                tableView.reloadRows(at: indexPathsToReload, with: .automatic)
            }
        case .defaultEmojiAtDiscussionLevel:
            guard indexPath.row < shownEmojiRows.count else { assertionFailure(); return }
            guard case .local(let configuration) = input else { assertionFailure(); return }
            switch shownEmojiRows[indexPath.row] {
            case .changeDefaultEmoji:
                let model = EmojiPickerViewModel(selectedEmoji: configuration.defaultEmoji) { emoji in
                    let value: PersistedDiscussionLocalConfigurationValue = .defaultEmoji(emoji)
                    ObvMessengerCoreDataNotification.userWantsToUpdateDiscussionLocalConfiguration(value: value, localConfigurationObjectID: configuration.typedObjectID)
                        .postOnDispatchQueue()
                }
                let vc = EmojiPickerHostingViewController(model: model)
                if let sheet = vc.sheetPresentationController {
                    sheet.detents = [ .medium() ]
                    sheet.prefersGrabberVisible = true
                    sheet.preferredCornerRadius = 30.0
                }
                present(vc, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }
            case .resetDefaultEmoji:
                let value: PersistedDiscussionLocalConfigurationValue = .defaultEmoji(nil)
                ObvMessengerCoreDataNotification.userWantsToUpdateDiscussionLocalConfiguration(value: value, localConfigurationObjectID: configuration.typedObjectID)
                    .postOnDispatchQueue()
            }
        }
    }

    
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard indexPath.section < shownSections.count else { assertionFailure(); return false }
        let section = shownSections[indexPath.section]
        return section.canEditOrMoveRow
    }

    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return self.tableView(tableView, canMoveRowAt: indexPath)
    }

    override func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        return .none
    }

    override func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        return false
    }

    override func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt sourceIndexPath: IndexPath, toProposedIndexPath proposedDestinationIndexPath: IndexPath) -> IndexPath {
        guard sourceIndexPath.section == proposedDestinationIndexPath.section else { return sourceIndexPath }
        return proposedDestinationIndexPath
    }

    override func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {

        guard sourceIndexPath.section == destinationIndexPath.section else { assertionFailure(); return }
        
        guard sourceIndexPath.section < shownSections.count else { assertionFailure(); return }
        let section = shownSections[sourceIndexPath.section]

        guard case .preferredComposeMessageViewActionsOrder = section else { assertionFailure(); return }

        let movedObject = self.preferredActions[sourceIndexPath.row]
        var actions = ObvMessengerSettings.Interface.preferredComposeMessageViewActions
        actions.remove(at: sourceIndexPath.row)
        actions.insert(movedObject, at: destinationIndexPath.row)
        ObvMessengerSettings.Interface.preferredComposeMessageViewActions = actions
    }

}
