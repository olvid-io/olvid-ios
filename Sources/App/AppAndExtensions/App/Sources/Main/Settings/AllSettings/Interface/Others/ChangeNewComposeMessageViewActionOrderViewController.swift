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
import ObvUI
import ObvUICoreData
import Combine
import ObvSettings
import ObvDesignSystem


enum ComposeMessageViewSettingsViewControllerInput {
    case local(configuration: PersistedDiscussionLocalConfiguration)
    case global
}



final class ComposeMessageViewSettingsViewController: UITableViewController {

    private var notificationTokens = [NSObjectProtocol]()
    private var cancellables = Set<AnyCancellable>()
    let input: ComposeMessageViewSettingsViewControllerInput

    init(input: ComposeMessageViewSettingsViewControllerInput) {
        self.input = input
        super.init(style: .insetGrouped)

        observePreferredComposeMessageViewActionsDidChangeNotifications()
        observeDiscussionLocalConfigurationHasBeenUpdatedNotifications()
        reloadOnPreferredEmojisListChange()

    }

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        cancellables.forEach { $0.cancel() }
    }

    private func observePreferredComposeMessageViewActionsDidChangeNotifications() {
        let token = ObvMessengerSettingsNotifications.observePreferredComposeMessageViewActionsDidChange(queue: OperationQueue.main) { [weak self] in
            assert(Thread.isMainThread)
            guard let self else { return }
            guard let section = Section.shown(forInput: input).firstIndex(of: .preferredComposeMessageViewActionsOrder) else { assertionFailure(); return }
            let cells = self.tableView.visibleCells.compactMap { $0 as? ActionCell }
            self.tableView.beginUpdates()
            let actions = ObvMessengerSettings.Interface.preferredComposeMessageViewActionsOrder
            for index in 0..<actions.count {
                let action = actions[index]
                guard let cell = (cells.first { $0.action == action }) else { continue }
                guard let srcIndexPath = self.tableView.indexPath(for: cell) else { assertionFailure(); continue }
                let destIndexPath = IndexPath(row: index, section: section)
                guard srcIndexPath != destIndexPath else { continue }
                self.tableView.moveRow(at: srcIndexPath, to: destIndexPath)
            }
            self.tableView.endUpdates()
            if let section = Section.shown(forInput: input).firstIndex(of: .resetPreferredComposeMessageViewActions) {
                self.tableView.reloadRows(at: [IndexPath.init(row: 0, section: section)], with: .none)
            }
        }
        self.notificationTokens.append(token)
    }

    private func observeDiscussionLocalConfigurationHasBeenUpdatedNotifications() {
        let token = ObvMessengerCoreDataNotification.observeDiscussionLocalConfigurationHasBeenUpdated { [weak self] value, objectId in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard case .defaultEmoji = value else { return }
                guard let sectionToReload = Section.shown(forInput: input).firstIndex(of: .defaultEmojiAtDiscussionLevel) else { return }
                self.tableView.reloadSections([sectionToReload], with: .none)
            }
        }
        self.notificationTokens.append(token)
    }
    
    
    private func reloadOnPreferredEmojisListChange() {
        ObvMessengerSettingsObservableObject.shared.$preferredEmojisList
            .sink { [weak self] _ in
                guard let self else { return }
                let indexPathsToReload: [IndexPath] = [
                    DefaultPreferredEmojisAtAppLevelItem.listOfPreferredEmojis.indexPath(forInput: input),
                    DefaultPreferredEmojisAtAppLevelItem.resetButton.indexPath(forInput: input),
                ].compactMap({ $0 })
                tableView.reloadRows(at: indexPathsToReload, with: .automatic)
            }
            .store(in: &cancellables)
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
        guard let section = Section.shown(forInput: input).firstIndex(of: .preferredComposeMessageViewActionsOrder) else { assertionFailure(); return }
        let cells = tableView.visibleCells.compactMap { $0 as? ActionCell }
        tableView.beginUpdates()
        let actions = ObvMessengerSettings.Interface.preferredComposeMessageViewActionsOrder
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

    
    // MARK: - Section
    
    private enum Section: CaseIterable {
        
        case preferredComposeMessageViewActionsOrder
        case resetPreferredComposeMessageViewActions
        case defaultEmojiAtAppLevel
        case defaultPreferredEmojisAtAppLevel
        case defaultEmojiAtDiscussionLevel
        
        static func shown(forInput input: ComposeMessageViewSettingsViewControllerInput) -> [Section] {
            switch input {
            case .local:
                return [
                    .preferredComposeMessageViewActionsOrder,
                    .resetPreferredComposeMessageViewActions,
                    .defaultPreferredEmojisAtAppLevel,
                    .defaultEmojiAtAppLevel,
                    .defaultEmojiAtDiscussionLevel,
                ]
            case .global:
                return [
                    .preferredComposeMessageViewActionsOrder,
                    .resetPreferredComposeMessageViewActions,
                    .defaultPreferredEmojisAtAppLevel,
                    .defaultEmojiAtAppLevel,
                ]
            }
        }
        
        
        var numberOfItems: Int {
            switch self {
            case .preferredComposeMessageViewActionsOrder: return PreferredComposeMessageViewActionsOrderItem.shown.count
            case .resetPreferredComposeMessageViewActions: return ResetPreferredComposeMessageViewActionsItem.shown.count
            case .defaultEmojiAtAppLevel: return DefaultEmojiAtAppLevelItem.shown.count
            case .defaultPreferredEmojisAtAppLevel: return DefaultPreferredEmojisAtAppLevelItem.shown.count
            case .defaultEmojiAtDiscussionLevel: return DefaultEmojiAtDiscussionLevelItem.shown.count
            }
        }

        
        static func shownSectionAt(section: Int, forInput input: ComposeMessageViewSettingsViewControllerInput) -> Section? {
            return shown(forInput: input)[safe: section]
        }


        var canEditOrMoveRow: Bool {
            switch self {
            case .preferredComposeMessageViewActionsOrder:
                return true
            case .defaultEmojiAtAppLevel,
                    .defaultEmojiAtDiscussionLevel,
                    .defaultPreferredEmojisAtAppLevel,
                    .resetPreferredComposeMessageViewActions:
                return false
            }
        }
        
        
        func section(forInput input: ComposeMessageViewSettingsViewControllerInput) -> Int? {
            Self.shown(forInput: input).firstIndex(of: self)
        }
        
    }
    
    
    // MARK: - Items
    
    private enum PreferredComposeMessageViewActionsOrderItem: CaseIterable {

        private static var preferredActions: [NewComposeMessageViewSortableAction] {
            ObvMessengerSettings.Interface.preferredComposeMessageViewActionsOrder
        }

        static var shown: [NewComposeMessageViewSortableAction] {
            preferredActions
        }

        static func shownItemAt(item: Int) -> NewComposeMessageViewSortableAction? {
            return shown[safe: item]
        }
        
        static func indexPath(ofAction action: NewComposeMessageViewSortableAction, forInput input: ComposeMessageViewSettingsViewControllerInput) -> IndexPath? {
            guard let section = Section.preferredComposeMessageViewActionsOrder.section(forInput: input) else { return nil }
            guard let row = Self.shown.firstIndex(of: action) else { return nil }
            return IndexPath(row: row, section: section)
        }
        
    }
    
    
    private enum ResetPreferredComposeMessageViewActionsItem: CaseIterable {

        case resetButton
        
        static var shown: [Self] {
            return Self.allCases
        }

        static func shownItemAt(item: Int) -> Self? {
            return shown[safe: item]
        }

        var cellIdentifier: String {
            switch self {
            case .resetButton: return "ResetPreferredComposeMessageViewActionsItem.resetButton"
            }
        }
        
        func indexPath(forInput input: ComposeMessageViewSettingsViewControllerInput) -> IndexPath? {
            guard let section = Section.resetPreferredComposeMessageViewActions.section(forInput: input) else { return nil }
            guard let row = Self.shown.firstIndex(of: self) else { return nil }
            return IndexPath(row: row, section: section)
        }
        
    }

    
    private enum DefaultPreferredEmojisAtAppLevelItem: CaseIterable {
        
        case listOfPreferredEmojis
        case resetButton
        
        static var shown: [Self] {
            return Self.allCases
        }

        static func shownItemAt(item: Int) -> Self? {
            return shown[safe: item]
        }

        var cellIdentifier: String {
            switch self {
            case .listOfPreferredEmojis: return "DefaultPreferredEmojisAtAppLevel.listOfPreferredEmojis"
            case .resetButton: return "DefaultPreferredEmojisAtAppLevel.resetButton"
            }
        }

        func indexPath(forInput input: ComposeMessageViewSettingsViewControllerInput) -> IndexPath? {
            guard let section = Section.defaultPreferredEmojisAtAppLevel.section(forInput: input) else { return nil }
            guard let row = Self.shown.firstIndex(of: self) else { return nil }
            return IndexPath(row: row, section: section)
        }

    }

    
    private enum DefaultEmojiAtAppLevelItem: CaseIterable {
        
        case changeDefaultEmojiAtAppLevel
        case resetButton

        static var shown: [Self] {
            return Self.allCases
        }

        static func shownItemAt(item: Int) -> Self? {
            return shown[safe: item]
        }

        var cellIdentifier: String {
            switch self {
            case .changeDefaultEmojiAtAppLevel: return "DefaultEmojiAtAppLevelItem.changeDefaultEmojiAtAppLevel"
            case .resetButton: return "DefaultEmojiAtAppLevelItem.resetButton"
            }
        }

        func indexPath(forInput input: ComposeMessageViewSettingsViewControllerInput) -> IndexPath? {
            guard let section = Section.defaultEmojiAtAppLevel.section(forInput: input) else { return nil }
            guard let row = Self.shown.firstIndex(of: self) else { return nil }
            return IndexPath(row: row, section: section)
        }

    }
    

    private enum DefaultEmojiAtDiscussionLevelItem: CaseIterable {
        
        case changeDefaultEmojiAtDiscussionLevel
        case resetButton

        static var shown: [Self] {
            return Self.allCases
        }

        static func shownItemAt(item: Int) -> Self? {
            return shown[safe: item]
        }

        var cellIdentifier: String {
            switch self {
            case .changeDefaultEmojiAtDiscussionLevel: return "DefaultEmojiAtDiscussionLevel.changeDefaultEmojiAtDiscussionLevel"
            case .resetButton: return "DefaultEmojiAtDiscussionLevel.resetButton"
            }
        }

        func indexPath(forInput input: ComposeMessageViewSettingsViewControllerInput) -> IndexPath? {
            guard let section = Section.defaultEmojiAtDiscussionLevel.section(forInput: input) else { return nil }
            guard let row = Self.shown.firstIndex(of: self) else { return nil }
            return IndexPath(row: row, section: section)
        }

    }
    
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.shown(forInput: input).count
    }

    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section.shownSectionAt(section: section, forInput: input) else { return 0 }
        return section.numberOfItems
    }

    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cellInCaseOfError = UITableViewCell(style: .default, reuseIdentifier: nil)

        guard let section = Section.shownSectionAt(section: indexPath.section, forInput: input) else {
            assertionFailure()
            return cellInCaseOfError
        }

        switch section {
            
        case .preferredComposeMessageViewActionsOrder:
            
            guard let action = PreferredComposeMessageViewActionsOrderItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            let cell = tableView.dequeueReusableCell(withIdentifier: "PreferredActionCell") ?? ActionCell(action: action)
            cell.selectionStyle = .none
            var configuration = cell.defaultContentConfiguration()
            configuration.text = action.title
            configuration.image = UIImage(systemIcon: action.icon)
            cell.contentConfiguration = configuration
            return cell

        case .resetPreferredComposeMessageViewActions:

            guard let item = ResetPreferredComposeMessageViewActionsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {
                
            case .resetButton:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.isUserInteractionEnabled = ObvMessengerSettings.Interface.preferredComposeMessageViewActionsOrder != NewComposeMessageViewSortableAction.defaultOrder
                var configuration = cell.defaultContentConfiguration()
                configuration.text = NSLocalizedString("RESET_COMPOSE_MESSAGE_VIEW_ACTIONS_ORDER", comment: "reset compose view message action title")
                if cell.isUserInteractionEnabled {
                    configuration.textProperties.color = AppTheme.shared.colorScheme.link
                }
                cell.contentConfiguration = configuration
                return cell
                
            }
            
        case .defaultPreferredEmojisAtAppLevel:

            guard let item = DefaultPreferredEmojisAtAppLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {
                
            case .listOfPreferredEmojis:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var cellConfiguration = cell.defaultContentConfiguration()
                let preferredEmojisList = ObvMessengerSettings.Emoji.preferredEmojisList
                cellConfiguration.text = preferredEmojisList.isEmpty ? NSLocalizedString("EMPTY_PREFERRED_EMOJIS_LIST", comment: "") : preferredEmojisList.joined(separator: " ")
                if preferredEmojisList.isEmpty {
                    cellConfiguration.textProperties.color = AppTheme.shared.colorScheme.tertiaryLabel
                }
                cell.contentConfiguration = cellConfiguration
                return cell

                
            case .resetButton:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.isUserInteractionEnabled = ObvMessengerSettings.Emoji.preferredEmojisList != ObvMessengerSettings.Emoji.defaultPreferredEmojisList
                var configuration = cell.defaultContentConfiguration()
                configuration.text = NSLocalizedString("RESET_DISCUSSION_EMOJI_TO_DEFAULT", comment: "")
                if cell.isUserInteractionEnabled {
                    configuration.textProperties.color = AppTheme.shared.colorScheme.link
                }
                cell.contentConfiguration = configuration
                return cell

            }

        case .defaultEmojiAtAppLevel:

            guard let item = DefaultEmojiAtAppLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {
                
            case .changeDefaultEmojiAtAppLevel:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var cellConfiguration = cell.defaultContentConfiguration()
                cellConfiguration.text = NSLocalizedString("DEFAULT_EMOJI", comment: "")
                cell.contentConfiguration = cellConfiguration
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
                label.textAlignment = .right
                label.textColor = AppTheme.shared.colorScheme.secondaryLabel
                label.text = ObvMessengerSettings.Emoji.defaultEmojiButton ?? ObvMessengerConstants.defaultEmoji
                cell.accessoryView = label
                return cell
                
            case .resetButton:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
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

            guard let item = DefaultEmojiAtDiscussionLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }

            guard case .local(let discussionConfiguration) = input else { assertionFailure(); return cellInCaseOfError }

            switch item {
                
            case .changeDefaultEmojiAtDiscussionLevel:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
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

            case .resetButton:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
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
    
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard let section = Section.shownSectionAt(section: indexPath.section, forInput: input) else { assertionFailure(); return }

        switch section {
            
        case .preferredComposeMessageViewActionsOrder:
            
            break
            
        case .resetPreferredComposeMessageViewActions:

            guard let item = ResetPreferredComposeMessageViewActionsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            
            switch item {
                
            case .resetButton:
                
                ObvMessengerSettings.Interface.preferredComposeMessageViewActionsOrder = NewComposeMessageViewSortableAction.defaultOrder
                
            }
            
        case .defaultPreferredEmojisAtAppLevel:

            guard let item = DefaultPreferredEmojisAtAppLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            
            switch item {
                
            case .listOfPreferredEmojis:
                let model = EmojiPickerViewModel(selectedEmoji: nil) { _ in
                    debugPrint("Test")
                }
                let vc = EmojiPickerHostingViewController(model: model)
                if let sheet = vc.sheetPresentationController {
                    sheet.detents = [.medium()]
                    sheet.prefersGrabberVisible = true
                    sheet.preferredCornerRadius = 30.0
                }
                present(vc, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }

            case .resetButton:
                ObvMessengerSettings.Emoji.preferredEmojisList = ObvMessengerSettings.Emoji.defaultPreferredEmojisList
                // We rely on the observed published preferredEmojisList to reload the table view rows
                
            }

        case .defaultEmojiAtAppLevel:
            
            guard let item = DefaultEmojiAtAppLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            
            let indexPathsToReload: [IndexPath] = [
                DefaultEmojiAtAppLevelItem.changeDefaultEmojiAtAppLevel.indexPath(forInput: input),
                DefaultEmojiAtAppLevelItem.resetButton.indexPath(forInput: input),
                DefaultEmojiAtDiscussionLevelItem.changeDefaultEmojiAtDiscussionLevel.indexPath(forInput: input),
            ].compactMap({ $0 })
            
            switch item {
                
            case .changeDefaultEmojiAtAppLevel:
                let model = EmojiPickerViewModel(selectedEmoji: ObvMessengerSettings.Emoji.defaultEmojiButton ?? ObvMessengerConstants.defaultEmoji) { emoji in
                    ObvMessengerSettings.Emoji.defaultEmojiButton = emoji
                    tableView.reloadRows(at: indexPathsToReload, with: .automatic)
                }
                let vc = EmojiPickerHostingViewController(model: model)
                if let sheet = vc.sheetPresentationController {
                    sheet.detents = [.medium()]
                    sheet.prefersGrabberVisible = true
                    sheet.preferredCornerRadius = 30.0
                }
                present(vc, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }

            case .resetButton:
                ObvMessengerSettings.Emoji.defaultEmojiButton = ObvMessengerConstants.defaultEmoji
                tableView.reloadRows(at: indexPathsToReload, with: .automatic)

            }

        case .defaultEmojiAtDiscussionLevel:

            guard let item = DefaultEmojiAtDiscussionLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }

            guard case .local(let discussionConfiguration) = input else { assertionFailure(); return }

            switch item {
                
            case .changeDefaultEmojiAtDiscussionLevel:
                let model = EmojiPickerViewModel(selectedEmoji: discussionConfiguration.defaultEmoji) { emoji in
                    let value: PersistedDiscussionLocalConfigurationValue = .defaultEmoji(emoji)
                    ObvMessengerInternalNotification.userWantsToUpdateDiscussionLocalConfiguration(value: value, localConfigurationObjectID: discussionConfiguration.typedObjectID)
                        .postOnDispatchQueue()
                }
                let vc = EmojiPickerHostingViewController(model: model)
                if let sheet = vc.sheetPresentationController {
                    sheet.detents = [.medium()]
                    sheet.prefersGrabberVisible = true
                    sheet.preferredCornerRadius = 30.0
                }
                present(vc, animated: true) {
                    tableView.deselectRow(at: indexPath, animated: true)
                }

            case .resetButton:
                let value: PersistedDiscussionLocalConfigurationValue = .defaultEmoji(nil)
                ObvMessengerInternalNotification.userWantsToUpdateDiscussionLocalConfiguration(value: value, localConfigurationObjectID: discussionConfiguration.typedObjectID)
                    .postOnDispatchQueue()

            }

        }
        
    }
    
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {

        guard let section = Section.shownSectionAt(section: section, forInput: input) else { assertionFailure(); return nil }

        switch section {
        case .preferredComposeMessageViewActionsOrder:
            return NSLocalizedString("NEW_COMPOSE_MESSAGE_VIEW_ACTION_ORDER_HEADER", comment: "Section header")
        case .defaultEmojiAtAppLevel:
            return NSLocalizedString("DEFAULT_EMOJI_AT_APP_LEVEL", comment: "Section header")
        case .defaultPreferredEmojisAtAppLevel:
            return NSLocalizedString("DEFAULT_PREFERRED_EMOJIS_LIST", comment: "Section header")
        case .resetPreferredComposeMessageViewActions,
                .defaultEmojiAtDiscussionLevel:
            return nil
        }
        
    }

    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {

        guard let section = Section.shownSectionAt(section: section, forInput: input) else { assertionFailure(); return nil }

        switch section {
        case .preferredComposeMessageViewActionsOrder:
            return NSLocalizedString("NEW_COMPOSE_MESSAGE_VIEW_ACTION_ORDER_FOOTER", comment: "Section footer")
        case .defaultEmojiAtAppLevel:
            if Section.shown(forInput: input).contains(.defaultEmojiAtDiscussionLevel) {
                return nil
            } else {
                return NSLocalizedString("QUICK_EMOJI_EXPLANATION", comment: "Section footer")
            }
        case .defaultPreferredEmojisAtAppLevel:
            return nil
        case .defaultEmojiAtDiscussionLevel:
            return NSLocalizedString("QUICK_EMOJI_EXPLANATION", comment: "Section footer")
        case .resetPreferredComposeMessageViewActions:
            return nil
        }
        
    }


    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        guard indexPath.section < Section.shown(forInput: input).count else { assertionFailure(); return false }
        let section = Section.shown(forInput: input)[indexPath.section]
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
        
        guard sourceIndexPath.section < Section.shown(forInput: input).count else { assertionFailure(); return }
        let section = Section.shown(forInput: input)[sourceIndexPath.section]

        guard case .preferredComposeMessageViewActionsOrder = section else { assertionFailure(); return }

        let movedObject = PreferredComposeMessageViewActionsOrderItem.shown[sourceIndexPath.row]
        var actions = ObvMessengerSettings.Interface.preferredComposeMessageViewActionsOrder
        actions.remove(at: sourceIndexPath.row)
        actions.insert(movedObject, at: destinationIndexPath.row)
        ObvMessengerSettings.Interface.preferredComposeMessageViewActionsOrder = actions
    }

}


// MARK: - Helpers

private class ActionCell: UITableViewCell {
    let action: NewComposeMessageViewSortableAction
    init(action: NewComposeMessageViewSortableAction) {
        self.action = action
        super.init(style: .default, reuseIdentifier: "PreferredActionCell")
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
