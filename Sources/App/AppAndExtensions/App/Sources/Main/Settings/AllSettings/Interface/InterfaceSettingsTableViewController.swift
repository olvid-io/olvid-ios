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
import ObvUICoreData
import ObvSettings
import ObvAppTypes
import ObvDesignSystem


@MainActor
protocol InterfaceSettingsTableViewControllerActions: AnyObject {
    func userWantsToUpdateDiscussionLocalConfiguration(_ vc: InterfaceSettingsTableViewController, value: PersistedDiscussionLocalConfigurationValue, localConfigurationObjectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) async throws
}


final class InterfaceSettingsTableViewController: UITableViewController {

    let ownedCryptoId: ObvCryptoId
    private weak var actions: (any InterfaceSettingsTableViewControllerActions)?
    
    init(ownedCryptoId: ObvCryptoId,
         actions: any InterfaceSettingsTableViewControllerActions) {
        self.ownedCryptoId = ownedCryptoId
        self.actions = actions
        super.init(style: Self.settingsTableStyle)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(theReduceMotionSettingChanged),
                                               name: UIAccessibility.reduceMotionStatusDidChangeNotification,
                                               object: nil)
        title = CommonString.Word.Interface
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
    }
    
    
    private enum Section: CaseIterable {
        
        case discussion
        case singleDiscussionLayoutTests
        case scrollingEffects
        
        /// **Two conditions, not one.** Beta options reveal this section; the *version* decides whether it means anything. Every row in it describes
        /// the SwiftUI screen, and below iOS 18 that screen is not offered whatever is stored — so showing the chooser there would give a reader a
        /// pull-down that adopts their selection and changes nothing. See ``ObvMessengerSettings/Interface/discussionLayoutTypeCanBeChosen``.
        static var shown: [Section] {
            var result: [Section] = [.discussion]
            if ObvMessengerConstants.showExperimentalFeature && ObvMessengerSettings.Interface.discussionLayoutTypeCanBeChosen {
                result += [.singleDiscussionLayoutTests]
            }
            // **Last, and after the layout chooser** — asked for on 2026-08-30. For a beta reader the chooser is the thing these two depend on, so they read in
            // the right order; for everybody else the chooser is absent and these simply come last.
            //
            // **Shown to every reader, and only where they mean something.** Both rows describe the SwiftUI screen and do nothing on the legacy one, so offering
            // them on iOS 16 or 17 — or to a beta reader who has chosen Classic — would be two switches that change nothing.
            if ObvMessengerSettings.Interface.discussionLayoutType == .swiftUI {
                result += [.scrollingEffects]
            }
            return result
        }
        
        var numberOfItems: Int {
            switch self {
            case .discussion: return DiscussionItem.shown.count
            case .scrollingEffects: return ScrollingEffectsItem.shown.count
            case .singleDiscussionLayoutTests: return SingleDiscussionLayoutTestsItem.shown.count
            }
        }
        
        static func shownSectionAt(section: Int) -> Section? {
            return shown[safe: section]
        }
        
    }
    
    /// The two effects the new discussion screen draws while it is scrolled, **shown to every reader** rather than only under beta options: they are on by
    /// default and plainly visible, so somebody who does not want them must be able to say so. Both are switched off entirely when the system's Reduce Motion
    /// is on — which this screen *reports* and does not enforce.
    private enum ScrollingEffectsItem: CaseIterable {
        case sentBubbleHueVariesWithScroll
        case elasticScrolling
        static var shown: [Self] { Self.allCases }
        static func shownItemAt(item: Int) -> Self? { shown[safe: item] }
        var cellIdentifier: String {
            switch self {
            case .sentBubbleHueVariesWithScroll: return "sentBubbleHueVariesWithScroll"
            case .elasticScrolling: return "elasticScrolling"
            }
        }
    }


    private enum DiscussionItem: CaseIterable {
        case customizeMessageComposeArea
        case sendMessageShortcut
        case hideLinks
        case shortenIntroductoryMessage
        static var shown: [Self] {
            return Self.allCases
        }
        static func shownItemAt(item: Int) -> Self? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .customizeMessageComposeArea: return "customizeMessageComposeArea"
            case .sendMessageShortcut: return "SendMessageShortcutCell"
            case .hideLinks: return "hideLinks"
            case .shortenIntroductoryMessage: return  "shortenIntroductoryMessage"
            }
        }
    }
    
    
    private enum SingleDiscussionLayoutTestsItem: CaseIterable {
        case chooseLayoutType
        /// **The chooser alone while the production screen is selected.** Everything under it describes the SwiftUI screen and nothing else — a hue that only its
        /// bubbles have, an entry only it performs, a date line only it hides — so offering them beside a screen that ignores all three is offering three switches
        /// that do nothing.
        static var shown: [SingleDiscussionLayoutTestsItem] {
            switch ObvMessengerSettings.Interface.discussionLayoutType {
            case .productionLayout: return [.chooseLayoutType]
            case .swiftUI: return Self.allCases
            }
        }
        static func shownItemAt(item: Int) -> SingleDiscussionLayoutTestsItem? {
            return shown[safe: item]
        }
        var cellIdentifier: String {
            switch self {
            case .chooseLayoutType: return "chooseLayoutType"
            }
        }
    }
    
}

// MARK: - UITableViewDataSource

extension InterfaceSettingsTableViewController {
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return Section.shown.count
    }
    
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section.shownSectionAt(section: section) else { return 0 }
        return section.numberOfItems
    }
    
    

    /// The accessory of a row whose value is chosen **in place**, from a menu, rather than on a screen of its own.
    ///
    /// **The chevron belongs to the button's *configuration*, not to the button or its menu.** A `UIButton(type: .system)` built without one
    /// stays on the legacy rendering path, where there is no `configuration` for `indicator` to live on — so a pop-up button drawn that way has
    /// no `chevron.up.chevron.down` however its menu is set up, and colours its title with `tintColor`, which reads as a link rather than as a
    /// value. With a configuration, `indicator` defaults to `.automatic` and resolves to the popup chevron precisely because
    /// `changesSelectionAsPrimaryAction` makes this a pop-up button. iOS 16, so no availability guard at this deployment target.
    ///
    /// `changesSelectionAsPrimaryAction` is also what makes the button read as the current value, taking its title from whichever action is
    /// `.on` — so a caller sets that state and nothing has to write the title.
    ///
    /// Grey rather than tinted, matching the SwiftUI `Picker` in a `Form` that renders the same idea elsewhere in the settings.
    private static func pullDownButton(children: [UIAction]) -> UIButton {
        var buttonConfiguration = UIButton.Configuration.plain()
        buttonConfiguration.baseForegroundColor = .secondaryLabel
        buttonConfiguration.contentInsets = .zero
        let button = UIButton(configuration: buttonConfiguration)
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = true
        button.menu = UIMenu(children: children)
        // **Sized for the widest of its values, not for the one chosen now.** A cell lays its accessory out at the frame it was handed, and
        // `changesSelectionAsPrimaryAction` changes the title without touching that frame — so a button sized for *Enter* and then switched to
        // *Cmd+Enter* wrapped the new title into the old width, and the row showed `+En-`: the middle line of three. The widest value fits every
        // value, so choosing one never changes the button's size and nothing has to be reloaded.
        var sizeOfTheWidestValue = CGSize.zero
        for child in children {
            button.configuration?.title = child.title
            let size = button.intrinsicContentSize
            sizeOfTheWidestValue.width = max(sizeOfTheWidestValue.width, size.width)
            sizeOfTheWidestValue.height = max(sizeOfTheWidestValue.height, size.height)
        }
        button.configuration?.title = children.first(where: { $0.state == .on })?.title ?? children.first?.title
        button.frame.size = sizeOfTheWidestValue
        return button
    }


    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        let cellInCaseOfError = UITableViewCell(style: .default, reuseIdentifier: nil)

        guard let section = Section.shownSectionAt(section: indexPath.section) else {
            assertionFailure()
            return cellInCaseOfError
        }

        switch section {
            
        case .discussion:
            
            guard let item = DiscussionItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {
                
            case .customizeMessageComposeArea:
                let cell = UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var configuration = cell.defaultContentConfiguration()
                configuration.text = Strings.newComposeMessageViewActionOrder
                cell.contentConfiguration = configuration
                cell.accessoryType = .disclosureIndicator
                return cell
                
            case .sendMessageShortcut:
                // **Chosen in place**, as the layout type is below: two values, and a pushed screen to pick between them cost a navigation each
                // way to change one word. The screen it replaces showed the same two names with a checkmark and nothing else.
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var content = cell.defaultContentConfiguration()
                content.text = String(localized: "KEYBOARD_SHORTCUT_FOR_SENDING_MESSAGE")
                cell.contentConfiguration = content
                cell.accessoryType = .none
                cell.selectionStyle = .none
                cell.accessoryView = Self.pullDownButton(children: ObvMessengerSettings.Interface.SendMessageShortcutType.allCases.map { shortcut in
                    UIAction(title: shortcut.description,
                             state: ObvMessengerSettings.Interface.sendMessageShortcutType == shortcut ? .on : .off) { _ in
                        ObvMessengerSettings.Interface.sendMessageShortcutType = shortcut
                    }
                })
                return cell
                
            case .hideLinks:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) as? ObvTitleAndSwitchTableViewCell ?? ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                var config = cell.defaultContentConfiguration()
                config.text = String(localized: "HIDE_TRAILING_URL_IN_MESSAGES_WHEN_PREVIEW_IS_AVAILABLE")
                cell.contentConfiguration = config
                cell.switchIsOn = ObvMessengerSettings.Interface.hideTrailingURLInMessagesWhenPreviewIsAvailable
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.Interface.hideTrailingURLInMessagesWhenPreviewIsAvailable = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadData()
                    }
                }
                return cell
                
            case .shortenIntroductoryMessage:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) as? ObvTitleAndSwitchTableViewCell ?? ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                var config = cell.defaultContentConfiguration()
                config.text = String(localized: "SHORTEN_INTRODUCTURY_MESSAGE")
                cell.contentConfiguration = config
                cell.switchIsOn = ObvMessengerSettings.Interface.shortenIntroductoryMessage
                cell.blockOnSwitchValueChanged = { (value) in
                    ObvMessengerSettings.Interface.shortenIntroductoryMessage = value
                    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) {
                        tableView.reloadData()
                    }
                }
                return cell

            }
            
        case .scrollingEffects:

            guard let item = ScrollingEffectsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }

            switch item {

            case .sentBubbleHueVariesWithScroll:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) as? ObvTitleAndSwitchTableViewCell ?? ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                var config = cell.defaultContentConfiguration()
                config.text = Strings.colourShift
                cell.contentConfiguration = config
                cell.switchIsOn = ObvMessengerSettings.Interface.sentBubbleHueVariesWithScroll
                // **Disabled, not hidden, and still showing what the reader chose.** See the footer.
                cell.isEnabled = !UIAccessibility.isReduceMotionEnabled
                cell.blockOnSwitchValueChanged = { value in
                    ObvMessengerSettings.Interface.sentBubbleHueVariesWithScroll = value
                }
                return cell

            case .elasticScrolling:
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) as? ObvTitleAndSwitchTableViewCell ?? ObvTitleAndSwitchTableViewCell(reuseIdentifier: item.cellIdentifier)
                var config = cell.defaultContentConfiguration()
                config.text = Strings.elasticScrolling
                cell.contentConfiguration = config
                cell.switchIsOn = ObvMessengerSettings.Interface.elasticScrolling
                cell.isEnabled = !UIAccessibility.isReduceMotionEnabled
                cell.blockOnSwitchValueChanged = { value in
                    ObvMessengerSettings.Interface.elasticScrolling = value
                }
                return cell

            }

        case .singleDiscussionLayoutTests:
            
            guard let item = SingleDiscussionLayoutTestsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return cellInCaseOfError }
            
            switch item {
                
            case .chooseLayoutType:
                // **Chosen in place rather than on a screen of its own**, as the autocorrection setting is in the discussion defaults — asked for on 2026-08-28,
                // and it is the right shape for two values: a whole pushed screen to pick between *Production* and *SwiftUI* costs a navigation each way to change
                // one word. That one is a SwiftUI `Picker` in a `Form`, which renders exactly this; here the screen is a `UITableViewController`, so the same thing
                // is a pull-down button as the cell's accessory. `changesSelectionAsPrimaryAction` is what makes the button read as the current value, taking its
                // title from whichever action is `.on`.
                let cell = tableView.dequeueReusableCell(withIdentifier: item.cellIdentifier) ?? UITableViewCell(style: .default, reuseIdentifier: item.cellIdentifier)
                var configuration = cell.defaultContentConfiguration()
                configuration.text = Strings.discussionLayoutType
                cell.contentConfiguration = configuration
                cell.accessoryType = .none
                cell.selectionStyle = .none
                cell.accessoryView = Self.pullDownButton(children: ObvMessengerSettings.Interface.DiscussionLayoutType.allCases.map { layoutType in
                    UIAction(title: layoutType.description,
                             state: ObvMessengerSettings.Interface.discussionLayoutType == layoutType ? .on : .off) { [weak tableView] _ in
                        ObvMessengerSettings.Interface.discussionLayoutType = layoutType
                        // **The rows under this one come and go with it**, so the section is rebuilt — see ``SingleDiscussionLayoutTestsItem/shown``. On the next
                        // turn rather than in the handler, the button being in the middle of adopting the selection that provoked this.
                        DispatchQueue.main.async { tableView?.reloadData() }
                    }
                })
                return cell

            }
        }
    }

    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let section = Section.shownSectionAt(section: section) else { return nil }
        switch section {
        case .scrollingEffects: return Strings.scrollingEffects
        case .discussion, .singleDiscussionLayoutTests: return nil
        }
    }


    /// **The screen reports Reduce Motion; it does not enforce it.** Each effect asks the same question where it runs, which is the answer that counts — so a
    /// mistake here can leave a footer wrong but can never leave an effect running for somebody who asked for it to stop.
    ///
    /// Two footers rather than one carrying a conditional clause: when the rows are greyed out the only thing worth saying is *why*, and a reader in that state
    /// does not need the effects described to them.
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard let section = Section.shownSectionAt(section: section) else { return nil }
        switch section {
        case .scrollingEffects:
            return UIAccessibility.isReduceMotionEnabled ? Strings.scrollingEffectsWithReduceMotionOn : Strings.scrollingEffectsExplanation
        case .discussion, .singleDiscussionLayoutTests:
            return nil
        }
    }


    /// **Reduce Motion can be turned on while this screen is open**, from Control Centre or another app, and without this both the greyed rows and the footer
    /// would be stale — which reads as broken rather than as out of date.
    @objc private func theReduceMotionSettingChanged() {
        tableView.reloadData()
    }


    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard let section = Section.shownSectionAt(section: indexPath.section) else { assertionFailure(); return }
        
        switch section {
            
        case .discussion:
            
            guard let item = DiscussionItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            
            switch item {
                
            case .customizeMessageComposeArea:
                let vc = ComposeMessageViewSettingsViewController(input: .global, actions: self)
                navigationController?.pushViewController(vc, animated: true)
                
            case .sendMessageShortcut:
                // A menu on the row itself, so the row leads nowhere.
                return
                
            case .hideLinks:
                // A switch, so the row itself leads nowhere. Its own handler answers the reader.
                return
                
            case .shortenIntroductoryMessage:
                return

            }
            
        case .scrollingEffects:
            // Two switches, so the rows themselves lead nowhere.
            return

        case .singleDiscussionLayoutTests:
            guard let item = SingleDiscussionLayoutTestsItem.shownItemAt(item: indexPath.item) else { assertionFailure(); return }
            switch item {
            case .chooseLayoutType:
                // The pull-down button beside the title is the control, and the row itself leads nowhere — it used to push
                // `SingleDiscussionLayoutTestsChooserViewController`, which nothing reaches any more.
                break
            }
        }
    }

}


// MARK: - Implemting ComposeMessageViewSettingsViewControllerActions

extension InterfaceSettingsTableViewController: ComposeMessageViewSettingsViewControllerActions {
    
    func userWantsToUpdateDiscussionLocalConfiguration(
        _ vc: ComposeMessageViewSettingsViewController,
        value: ObvUICoreData.PersistedDiscussionLocalConfigurationValue,
        localConfigurationObjectID: ObvUICoreData.TypeSafeManagedObjectID<ObvUICoreData.PersistedDiscussionLocalConfiguration>) async throws {
            guard let actions else { assertionFailure(); throw ObvError.actionsDelegateIsNil }
            try await actions.userWantsToUpdateDiscussionLocalConfiguration(self, value: value, localConfigurationObjectID: localConfigurationObjectID)
        }
    
}


// MARK: - Errors

extension InterfaceSettingsTableViewController {
    
    enum ObvError: Error {
        case actionsDelegateIsNil
    }
    
}


extension ContactsSortOrder {
    public var description: String {
        switch self {
        case .byFirstName: return InterfaceSettingsTableViewController.Strings.firstNameThenLastName
        case .byLastName: return InterfaceSettingsTableViewController.Strings.lastNameThenFirstName
        }
    }
}


private extension InterfaceSettingsTableViewController {
    
    struct Strings {
        static let scrollingEffects = String(localized: "SCROLLING_EFFECTS")
        static let scrollingEffectsExplanation = String(localized: "SCROLLING_EFFECTS_EXPLANATION")
        static let scrollingEffectsWithReduceMotionOn = String(localized: "SCROLLING_EFFECTS_REDUCE_MOTION_ON")
        static let colourShift = String(localized: "COLOUR_SHIFT")
        static let elasticScrolling = String(localized: "ELASTIC_SCROLLING")
        static let newComposeMessageViewActionOrder = NSLocalizedString("NEW_COMPOSE_MESSAGE_VIEW_PREFERENCES", comment: "")
        static let firstNameThenLastName = NSLocalizedString("FIRST_NAME_LAST_NAME", comment: "")
        static let lastNameThenFirstName = NSLocalizedString("LAST_NAME_FIRST_NAME", comment: "")
        static let discussionLayoutType = NSLocalizedString("DISCUSSION_LAYOUT_TYPE", comment: "")
    }
    
}


extension ObvMessengerSettings.Interface.DiscussionLayoutType {

    /// What each option is called in the chooser.
    ///
    /// **Renamed 2026-08-29, and the old names had to go rather than be reworded.** They were *In production* and *SwiftUI*: the second is an
    /// implementation detail a reader has no way to interpret, and the first became **untrue** the day the new screen started shipping by default
    /// on iOS 18 — it named the option that is no longer production.
    ///
    /// The two screens are near-identical by design, parity having been the whole goal, so no *descriptive* name is possible: nobody can say
    /// *the one with the X*. Only a temporal pair works, and its job here is to tell a tester which one is the thing being tried.
    ///
    /// The keys are renamed rather than repointed. A key called `PRODUCTION_LAYOUT` resolving to *Classic* is the next person's confusion, and
    /// several of the old translations carried the *manufacturing* sense of the word — `В производстве`, `正在生产中` — so there was nothing worth
    /// keeping on the other side of them.
    var description: String {
        switch self {
        case .productionLayout:
            return NSLocalizedString("DISCUSSION_LAYOUT_CLASSIC", comment: "")
        case .swiftUI:
            return NSLocalizedString("DISCUSSION_LAYOUT_NEW", comment: "")
        }
    }

}
