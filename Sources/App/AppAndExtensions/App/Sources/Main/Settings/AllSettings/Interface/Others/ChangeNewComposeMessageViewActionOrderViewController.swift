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
import CoreData
import ObvUI
import ObvUICoreData
import Combine
import ObvSettings
import ObvDesignSystem
import ObvAppTypes


enum ComposeMessageViewSettingsViewControllerInput {
    case local(configuration: PersistedDiscussionLocalConfiguration)
    case global
}


@MainActor
protocol ComposeMessageViewSettingsViewControllerActions: AnyObject {
    func userWantsToUpdateDiscussionLocalConfiguration(_ vc: ComposeMessageViewSettingsViewController, value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) async throws
}


final class ComposeMessageViewSettingsViewController: UITableViewController {

    private var notificationTokens = [NSObjectProtocol]()
    private var cancellables = Set<AnyCancellable>()
    let input: ComposeMessageViewSettingsViewControllerInput
    private weak var actions: (any ComposeMessageViewSettingsViewControllerActions)?

    init(input: ComposeMessageViewSettingsViewControllerInput, actions: any ComposeMessageViewSettingsViewControllerActions) {
        self.input = input
        self.actions = actions
        super.init(style: .insetGrouped)

        reloadWhenThisDiscussionsConfigurationChangesInTheViewContext()
        reloadOnPreferredEmojisListChange()
        reloadOnDoubleTapEmojiChange()

    }

    deinit {
        notificationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        cancellables.forEach { $0.cancel() }
    }

    /// Esc closes this screen when it is presented on its own, which is how the composition bar shows it; its close button is a UIKit bar button, so no
    /// SwiftUI shortcut can carry the key. Pushed within the settings, it offers nothing, and Esc is left to the navigation it is part of.
    ///
    /// The selector is named after this screen because UIKit sends a key command's action to the first responder in the chain that implements it,
    /// not to the controller that offered the command: with a common name, the settings' own Esc landed here and closed them.
    override var keyCommands: [UIKeyCommand]? {
        guard presentingViewController != nil, navigationController?.viewControllers.first === self else { return super.keyCommands }
        return (super.keyCommands ?? []) + [UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(composeMessageViewSettingsAnswerTheEscapeKey))]
    }

    @objc private func composeMessageViewSettingsAnswerTheEscapeKey() {
        dismiss(animated: true)
    }

    /// Redraws the two discussion-level rows when this discussion's configuration changes under them, which is what an
    /// emoji chosen on another of the user's devices does.
    ///
    /// **The view context's own change rather than `discussionLocalConfigurationHasBeenUpdated`**, which these rows used to
    /// watch. That notification and the merge into the view context are two independent hops off the saving thread — the
    /// notification through a queue of its own, the merge through `viewContext.perform` — and nothing orders them. The rows
    /// read a view-context object, so a reload arriving first redraws the value that is already there and nothing reloads
    /// them again. Observing the merge cannot be early by construction.
    private func reloadWhenThisDiscussionsConfigurationChangesInTheViewContext() {
        guard case .local(let configuration) = input, let viewContext = configuration.managedObjectContext else { return }
        let objectID = configuration.objectID
        let token = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextObjectsDidChange, object: viewContext, queue: .main) { [weak self] notification in
            guard let self else { return }
            let touched = (notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? [])
                .union(notification.userInfo?[NSRefreshedObjectsKey] as? Set<NSManagedObject> ?? [])
            guard touched.contains(where: { $0.objectID == objectID }) else { return }
            let sectionsToReload = [Section.defaultEmojiAtDiscussionLevel, Section.doubleTapEmojiAtDiscussionLevel]
                .compactMap { Section.shown(forInput: self.input).firstIndex(of: $0) }
            guard !sectionsToReload.isEmpty else { return }
            self.tableView.reloadSections(IndexSet(sectionsToReload), with: .none)
        }
        self.notificationTokens.append(token)
    }
    
    
    /// The global double tap emoji travels between a user's own devices, so it can change while this screen is open.
    ///
    /// **On the main queue**, unlike the list above: that one is only ever written by this app's own UI, where an atom
    /// arriving from another device is applied by a background operation, so the value is published off the main thread.
    /// And after `dropFirst`, a `@Published` handing its current value to every new subscriber being a reload of rows
    /// that do not exist yet.
    private func reloadOnDoubleTapEmojiChange() {
        ObvMessengerSettingsObservableObject.shared.$defaultDoubleTapEmoji
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let indexPathsToReload: [IndexPath] = [
                    DoubleTapEmojiAtAppLevelItem.changeDoubleTapEmojiAtAppLevel.indexPath(forInput: input),
                    DoubleTapEmojiAtAppLevelItem.resetButton.indexPath(forInput: input),
                    DoubleTapEmojiAtDiscussionLevelItem.changeDoubleTapEmojiAtDiscussionLevel.indexPath(forInput: input),
                ].compactMap({ $0 })
                guard !indexPathsToReload.isEmpty else { return }
                tableView.reloadRows(at: indexPathsToReload, with: .automatic)
            }
            .store(in: &cancellables)
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
        self.title = NSLocalizedString("NEW_COMPOSE_MESSAGE_VIEW_PREFERENCES", comment: "ComposeMessageViewSettingsViewController title")
    }
    
    // MARK: - Section
    
    private enum Section: CaseIterable {
        
        case defaultEmojiAtAppLevel
        case defaultPreferredEmojisAtAppLevel
        case defaultEmojiAtDiscussionLevel

        /// What a **double tap** on a message reacts with, globally.
        ///
        /// **A section of its own rather than a row of `defaultEmojiAtAppLevel`**, because that section carries a reset button whose enablement is a fact about
        /// the quick emoji; a second emoji sharing it would make the reset ambiguous. So it follows the shape this file already has, one section per setting.
        ///
        /// Global, so shown for both inputs — and, like its discussion-level twin below, only while the reader is on the
        /// SwiftUI discussion.
        case doubleTapEmojiAtAppLevel

        /// What a **double tap** reacts with in this discussion, overriding the section above. The twin of
        /// ``defaultEmojiAtDiscussionLevel``, shown only when this screen was opened from a discussion.
        case doubleTapEmojiAtDiscussionLevel

        /// **Neither double-tap section is offered on the legacy discussion**, which answers a double tap by showing the bar
        /// of favourite emojis: `SingleDiscussionViewAppDataSource` is the only reader of either value, and it serves the
        /// SwiftUI screen alone. Shown there, they would be settings a reader can change to no effect at all, with nothing
        /// saying why. Both conditions go at the cutover, when there is one discussion screen again.
        static func shown(forInput input: ComposeMessageViewSettingsViewControllerInput) -> [Section] {
            let doubleTapIsAnswered = ObvMessengerSettings.Interface.discussionLayoutType == .swiftUI
            switch input {
            case .local:
                var sections: [Section] = [
                    .defaultPreferredEmojisAtAppLevel,
                    .defaultEmojiAtAppLevel,
                    .defaultEmojiAtDiscussionLevel,
                ]
                if doubleTapIsAnswered {
                    sections += [.doubleTapEmojiAtAppLevel, .doubleTapEmojiAtDiscussionLevel]
                }
                return sections
            case .global:
                var sections: [Section] = [
                    .defaultPreferredEmojisAtAppLevel,
                    .defaultEmojiAtAppLevel,
                ]
                if doubleTapIsAnswered {
                    sections += [.doubleTapEmojiAtAppLevel]
                }
                return sections
            }
        }
        
        
        var numberOfItems: Int {
            switch self {
            case .defaultEmojiAtAppLevel: return DefaultEmojiAtAppLevelItem.shown.count
            case .defaultPreferredEmojisAtAppLevel: return DefaultPreferredEmojisAtAppLevelItem.shown.count
            case .defaultEmojiAtDiscussionLevel: return DefaultEmojiAtDiscussionLevelItem.shown.count
            case .doubleTapEmojiAtAppLevel: return DoubleTapEmojiAtAppLevelItem.shown.count
            case .doubleTapEmojiAtDiscussionLevel: return DoubleTapEmojiAtDiscussionLevelItem.shown.count
            }
        }

        
        static func shownSectionAt(section: Int, forInput input: ComposeMessageViewSettingsViewControllerInput) -> Section? {
            return shown(forInput: input)[safe: section]
        }


        func section(forInput input: ComposeMessageViewSettingsViewControllerInput) -> Int? {
            Self.shown(forInput: input).firstIndex(of: self)
        }
        
    }
    
    
    // MARK: - Items
    
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
    

    /// The two rows of the double-tap emoji section, and the twin of ``DefaultEmojiAtAppLevelItem``.
    private enum DoubleTapEmojiAtAppLevelItem: CaseIterable {

        case changeDoubleTapEmojiAtAppLevel
        case resetButton

        static var shown: [Self] {
            return Self.allCases
        }

        static func shownItemAt(item: Int) -> Self? {
            return shown[safe: item]
        }

        var cellIdentifier: String {
            switch self {
            case .changeDoubleTapEmojiAtAppLevel: return "DoubleTapEmojiAtAppLevelItem.changeDoubleTapEmojiAtAppLevel"
            case .resetButton: return "DoubleTapEmojiAtAppLevelItem.resetButton"
            }
        }

        func indexPath(forInput input: ComposeMessageViewSettingsViewControllerInput) -> IndexPath? {
            guard let section = Section.doubleTapEmojiAtAppLevel.section(forInput: input) else { return nil }
            guard let row = Self.shown.firstIndex(of: self) else { return nil }
            return IndexPath(row: row, section: section)
        }

    }


    private enum DoubleTapEmojiAtDiscussionLevelItem: CaseIterable {

        case changeDoubleTapEmojiAtDiscussionLevel
        case resetButton

        static var shown: [Self] {
            return Self.allCases
        }

        static func shownItemAt(item: Int) -> Self? {
            return shown[safe: item]
        }

        var cellIdentifier: String {
            switch self {
            case .changeDoubleTapEmojiAtDiscussionLevel: return "DoubleTapEmojiAtDiscussionLevel.changeDoubleTapEmojiAtDiscussionLevel"
            case .resetButton: return "DoubleTapEmojiAtDiscussionLevel.resetButton"
            }
        }

        func indexPath(forInput input: ComposeMessageViewSettingsViewControllerInput) -> IndexPath? {
            guard let section = Section.doubleTapEmojiAtDiscussionLevel.section(forInput: input) else { return nil }
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
    
    
    /// How the emoji picker is presented from this screen.
    ///
    /// **A fraction of the room there is, rather than `.medium()`.** A medium detent is half of whatever contains the
    /// sheet, and what contains it differs: this screen fills an iPhone, so half of it held eight rows of emojis, while on
    /// an iPad it is itself a form sheet and half of *that* held three. A resolver is handed the height the sheet could
    /// have, so one rule covers a phone, a form sheet and Slide Over without asking which it is in — and asking was its own
    /// trap, a form sheet overriding the traits of what it presents so that a controller inside one answers `.compact` on
    /// an iPad.
    private func configureTheEmojiPickersSheet(_ sheet: UISheetPresentationController) {
        sheet.detents = [.custom(identifier: Self.emojiPickerDetent) { context in
            context.maximumDetentValue * 0.75
        }]
        sheet.prefersGrabberVisible = true
        sheet.preferredCornerRadius = 30.0
    }


    private static let emojiPickerDetent = UISheetPresentationController.Detent.Identifier("emojiPicker")


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
                        
        case .doubleTapEmojiAtAppLevel:

            guard let item = DoubleTapEmojiAtAppLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }

            switch item {

            case .changeDoubleTapEmojiAtAppLevel:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var cellConfiguration = cell.defaultContentConfiguration()
                cellConfiguration.text = NSLocalizedString("DOUBLE_TAP_EMOJI", comment: "")
                cell.contentConfiguration = cellConfiguration
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
                label.textAlignment = .right
                label.textColor = AppTheme.shared.colorScheme.secondaryLabel
                label.text = ObvMessengerSettings.Emoji.defaultDoubleTapEmoji ?? ObvMessengerConstants.defaultDoubleTapEmoji
                cell.accessoryView = label
                return cell

            case .resetButton:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.isUserInteractionEnabled = ObvMessengerSettings.Emoji.defaultDoubleTapEmoji != nil && ObvMessengerSettings.Emoji.defaultDoubleTapEmoji != ObvMessengerConstants.defaultDoubleTapEmoji
                var configuration = cell.defaultContentConfiguration()
                configuration.text = NSLocalizedString("RESET_DISCUSSION_EMOJI_TO_DEFAULT", comment: "")
                if cell.isUserInteractionEnabled {
                    configuration.textProperties.color = AppTheme.shared.colorScheme.link
                }
                cell.contentConfiguration = configuration
                return cell

            }

        case .doubleTapEmojiAtDiscussionLevel:

            guard let item = DoubleTapEmojiAtDiscussionLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }

            guard case .local(let discussionConfiguration) = input else { assertionFailure(); return cellInCaseOfError }

            switch item {

            case .changeDoubleTapEmojiAtDiscussionLevel:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var cellConfiguration = cell.defaultContentConfiguration()
                // `String(localized:)` rather than the `NSLocalizedString` beside it: the localisation tooling extracts
                // the modern form and not the legacy one, so a key spelled the old way only reaches the catalogue
                // through a build in Xcode.
                cellConfiguration.text = String(localized: "DISCUSSION_DOUBLE_TAP_EMOJI")
                cell.contentConfiguration = cellConfiguration
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
                label.textAlignment = .right
                label.textColor = AppTheme.shared.colorScheme.secondaryLabel
                if let doubleTapEmoji = discussionConfiguration.doubleTapEmoji {
                    label.text = doubleTapEmoji
                } else {
                    label.text = "\(CommonString.Word.Default) (\(ObvMessengerSettings.Emoji.defaultDoubleTapEmoji ?? ObvMessengerConstants.defaultDoubleTapEmoji))"
                }
                cell.accessoryView = label
                return cell

            case .resetButton:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                cell.isUserInteractionEnabled = discussionConfiguration.doubleTapEmoji != nil
                var configuration = cell.defaultContentConfiguration()
                configuration.text = NSLocalizedString("RESET_DISCUSSION_EMOJI_TO_DEFAULT_DISCUSSION_LEVEL", comment: "")
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
            
        case .defaultPreferredEmojisAtAppLevel:

            guard let item = DefaultPreferredEmojisAtAppLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            
            switch item {
                
            case .listOfPreferredEmojis:
                let model = EmojiPickerViewModel(selectedEmoji: nil) { _ in
                    debugPrint("Test")
                }
                let vc = EmojiPickerHostingViewController(model: model)
                
                if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
                    
                    let nav = UINavigationController(rootViewController: vc)
                    present(nav, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

                } else {
                
                    if let sheet = vc.sheetPresentationController {
                        configureTheEmojiPickersSheet(sheet)
                    }
                    present(vc, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

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
                
                if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
                    
                    let nav = UINavigationController(rootViewController: vc)
                    present(nav, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

                } else {
                    
                    if let sheet = vc.sheetPresentationController {
                        configureTheEmojiPickersSheet(sheet)
                    }
                    present(vc, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

                }

            case .resetButton:
                ObvMessengerSettings.Emoji.defaultEmojiButton = ObvMessengerConstants.defaultEmoji
                tableView.reloadRows(at: indexPathsToReload, with: .automatic)

            }

        case .doubleTapEmojiAtAppLevel:

            guard let item = DoubleTapEmojiAtAppLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }

            // The discussion-level row shows this value in brackets while the discussion has chosen nothing of its own,
            // so it changes with it.
            let indexPathsToReload: [IndexPath] = [
                DoubleTapEmojiAtAppLevelItem.changeDoubleTapEmojiAtAppLevel.indexPath(forInput: input),
                DoubleTapEmojiAtAppLevelItem.resetButton.indexPath(forInput: input),
                DoubleTapEmojiAtDiscussionLevelItem.changeDoubleTapEmojiAtDiscussionLevel.indexPath(forInput: input),
            ].compactMap({ $0 })

            switch item {

            case .changeDoubleTapEmojiAtAppLevel:
                let model = EmojiPickerViewModel(selectedEmoji: ObvMessengerSettings.Emoji.defaultDoubleTapEmoji ?? ObvMessengerConstants.defaultDoubleTapEmoji) { emoji in
                    ObvMessengerSettings.Emoji.setDefaultDoubleTapEmoji(to: emoji, changeMadeFromAnotherOwnedDevice: false)
                    tableView.reloadRows(at: indexPathsToReload, with: .automatic)
                }
                let vc = EmojiPickerHostingViewController(model: model)

                // Presented exactly as its twin is, a Mac having no sheet detents worth using.
                if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {

                    let nav = UINavigationController(rootViewController: vc)
                    present(nav, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

                } else {

                    if let sheet = vc.sheetPresentationController {
                        configureTheEmojiPickersSheet(sheet)
                    }
                    present(vc, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

                }

            case .resetButton:
                ObvMessengerSettings.Emoji.setDefaultDoubleTapEmoji(to: ObvMessengerConstants.defaultDoubleTapEmoji, changeMadeFromAnotherOwnedDevice: false)
                tableView.reloadRows(at: indexPathsToReload, with: .automatic)

            }

        case .doubleTapEmojiAtDiscussionLevel:

            guard let item = DoubleTapEmojiAtDiscussionLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }

            guard case .local(let discussionConfiguration) = input else { assertionFailure(); return }

            switch item {

            case .changeDoubleTapEmojiAtDiscussionLevel:
                let model = EmojiPickerViewModel(selectedEmoji: discussionConfiguration.doubleTapEmoji) { [weak self] emoji in
                    guard let self, let actions = self.actions else { assertionFailure(); return }
                    let value: PersistedDiscussionLocalConfigurationValue = .doubleTapEmoji(emoji)
                    let localConfigurationObjectID = discussionConfiguration.typedObjectID
                    let indexPathToReload = DoubleTapEmojiAtDiscussionLevelItem.resetButton.indexPath(forInput: input)
                    Task {
                        do {
                            try await actions.userWantsToUpdateDiscussionLocalConfiguration(self, value: value, localConfigurationObjectID: localConfigurationObjectID)
                            await MainActor.run { self.tableView.reloadRows(at: [indexPath, indexPathToReload].compactMap({ $0 }), with: .none) }
                        } catch {
                            assertionFailure()
                        }
                    }
                }
                let vc = EmojiPickerHostingViewController(model: model)

                if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {

                    let nav = UINavigationController(rootViewController: vc)
                    present(nav, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

                } else {

                    if let sheet = vc.sheetPresentationController {
                        configureTheEmojiPickersSheet(sheet)
                    }
                    present(vc, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

                }

            case .resetButton:
                guard let actions = self.actions else { assertionFailure(); return }
                let value: PersistedDiscussionLocalConfigurationValue = .doubleTapEmoji(nil)
                let localConfigurationObjectID = discussionConfiguration.typedObjectID
                let indexPathToReload = DoubleTapEmojiAtDiscussionLevelItem.changeDoubleTapEmojiAtDiscussionLevel.indexPath(forInput: input)
                Task {
                    do {
                        try await actions.userWantsToUpdateDiscussionLocalConfiguration(self, value: value, localConfigurationObjectID: localConfigurationObjectID)
                        await MainActor.run { self.tableView.reloadRows(at: [indexPath, indexPathToReload].compactMap({ $0 }), with: .none) }
                    } catch {
                        assertionFailure()
                    }
                }
            }

        case .defaultEmojiAtDiscussionLevel:

            guard let item = DefaultEmojiAtDiscussionLevelItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }

            guard case .local(let discussionConfiguration) = input else { assertionFailure(); return }

            switch item {
                
            case .changeDefaultEmojiAtDiscussionLevel:
                let model = EmojiPickerViewModel(selectedEmoji: discussionConfiguration.defaultEmoji) { [weak self] emoji in
                    guard let self, let actions = self.actions else { assertionFailure(); return }
                    let value: PersistedDiscussionLocalConfigurationValue = .defaultEmoji(emoji)
                    let localConfigurationObjectID = discussionConfiguration.typedObjectID
                    let indexPathToReload = DefaultEmojiAtDiscussionLevelItem.resetButton.indexPath(forInput: input)
                    Task {
                        do {
                            try await actions.userWantsToUpdateDiscussionLocalConfiguration(self, value: value, localConfigurationObjectID: localConfigurationObjectID)
                            await MainActor.run { self.tableView.reloadRows(at: [indexPath, indexPathToReload].compactMap({ $0 }), with: .none) }
                        } catch {
                            assertionFailure()
                        }
                    }
                }
                let vc = EmojiPickerHostingViewController(model: model)
                
                if ObvMessengerConstants.targetEnvironmentIsMacCatalyst {
                    
                    let nav = UINavigationController(rootViewController: vc)
                    present(nav, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

                } else {
                
                    if let sheet = vc.sheetPresentationController {
                        configureTheEmojiPickersSheet(sheet)
                    }
                    present(vc, animated: true) {
                        tableView.deselectRow(at: indexPath, animated: true)
                    }

                }
                
            case .resetButton:
                guard let actions = self.actions else { assertionFailure(); return }
                let value: PersistedDiscussionLocalConfigurationValue = .defaultEmoji(nil)
                let localConfigurationObjectID = discussionConfiguration.typedObjectID
                let indexPathToReload = DefaultEmojiAtDiscussionLevelItem.changeDefaultEmojiAtDiscussionLevel.indexPath(forInput: input)
                Task {
                    do {
                        try await actions.userWantsToUpdateDiscussionLocalConfiguration(self, value: value, localConfigurationObjectID: localConfigurationObjectID)
                        await MainActor.run { self.tableView.reloadRows(at: [indexPath, indexPathToReload].compactMap({ $0 }), with: .none) }
                    } catch {
                        assertionFailure()
                    }
                }
            }

        }
        
    }
    
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {

        guard let section = Section.shownSectionAt(section: section, forInput: input) else { assertionFailure(); return nil }

        switch section {
        case .defaultEmojiAtAppLevel:
            return NSLocalizedString("DEFAULT_EMOJI_AT_APP_LEVEL", comment: "Section header")
        case .defaultPreferredEmojisAtAppLevel:
            return NSLocalizedString("DEFAULT_PREFERRED_EMOJIS_LIST", comment: "Section header")
        case .doubleTapEmojiAtAppLevel:
            return NSLocalizedString("DOUBLE_TAP_EMOJI_AT_APP_LEVEL", comment: "Section header")
        case .defaultEmojiAtDiscussionLevel, .doubleTapEmojiAtDiscussionLevel:
            return nil
        }
        
    }

    
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {

        guard let section = Section.shownSectionAt(section: section, forInput: input) else { assertionFailure(); return nil }

        switch section {
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
        case .doubleTapEmojiAtAppLevel:
            if Section.shown(forInput: input).contains(.doubleTapEmojiAtDiscussionLevel) {
                return nil
            } else {
                return NSLocalizedString("DOUBLE_TAP_EMOJI_EXPLANATION", comment: "Section footer")
            }
        case .doubleTapEmojiAtDiscussionLevel:
            return NSLocalizedString("DOUBLE_TAP_EMOJI_EXPLANATION", comment: "Section footer")
        }
        
    }


}
