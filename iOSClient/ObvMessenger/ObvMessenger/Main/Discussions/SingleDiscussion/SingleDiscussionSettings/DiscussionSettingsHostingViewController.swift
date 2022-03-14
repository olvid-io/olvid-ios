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

import SwiftUI
import CoreData
import Combine
import os.log

final class DiscussionSettingsHostingViewController: UIHostingController<DiscussionExpirationSettingsWrapperView>, DiscussionExpirationSettingsViewModelDelegate {

    fileprivate let model: DiscussionExpirationSettingsViewModel

    init?(discussionSharedConfiguration: PersistedDiscussionSharedConfiguration, discussionLocalConfiguration: PersistedDiscussionLocalConfiguration) {
        assert(Thread.isMainThread)
        assert(discussionSharedConfiguration.managedObjectContext == ObvStack.shared.viewContext)
        guard let model = DiscussionExpirationSettingsViewModel(
            sharedConfigurationInViewContext: discussionSharedConfiguration,
            localConfigurationInViewContext: discussionLocalConfiguration) else {
                return nil
            }
        let view = DiscussionExpirationSettingsWrapperView(
            model: model,
            localConfiguration: discussionLocalConfiguration,
            sharedConfiguration: model.sharedConfigurationInScratchViewContext)
        self.model = model
        super.init(rootView: view)
        model.delegate = self
        self.isModalInPresentation = true // We make sure the modal cannot be too easily dismissed
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dismissAction() {
        self.dismiss(animated: true)
    }

}


protocol DiscussionExpirationSettingsViewModelDelegate: AnyObject {
    func dismissAction()
}

final class DiscussionExpirationSettingsViewModel: ObservableObject {

    weak var delegate: DiscussionExpirationSettingsViewModelDelegate?

    private let scratchViewContext: NSManagedObjectContext
    @Published private(set) var localConfigurationInViewContext: PersistedDiscussionLocalConfiguration
    private(set) var sharedConfigurationInScratchViewContext: PersistedDiscussionSharedConfiguration
    private let ownedIdentityInViewContext: PersistedObvOwnedIdentity
    @Published var changed: Bool // This allows to "force" the refresh of the view
    @Published var showConfirmationMessageBeforeSavingSharedConfig = false

    init?(sharedConfigurationInViewContext: PersistedDiscussionSharedConfiguration, localConfigurationInViewContext: PersistedDiscussionLocalConfiguration) {
        let scratchViewContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        scratchViewContext.persistentStoreCoordinator = ObvStack.shared.persistentStoreCoordinator
        self.scratchViewContext = scratchViewContext
        guard let sharedConfigurationInScratchViewContext = try? PersistedDiscussionSharedConfiguration.get(objectID: sharedConfigurationInViewContext.objectID, within: scratchViewContext) else {
            return nil
        }
        self.sharedConfigurationInScratchViewContext = sharedConfigurationInScratchViewContext
        self.localConfigurationInViewContext = localConfigurationInViewContext
        guard let _ownedIdentity = sharedConfigurationInScratchViewContext.discussion?.ownedIdentity else {
            return nil
        }
        self.ownedIdentityInViewContext = _ownedIdentity
        self.changed = false
    }

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "DiscussionExpirationSettingsViewModel")

    var sharedConfigCanBeModified: Bool {
        sharedConfigurationInScratchViewContext.canBeModifiedAndSharedByOwnedIdentity
    }

    func updateSharedConfiguration(with value: PersistedDiscussionSharedConfigurationValue) {
        guard (try? value.update(for: sharedConfigurationInScratchViewContext, initiator: ownedIdentityInViewContext.cryptoId)) == true else { return }
        withAnimation {
            self.changed.toggle()
        }
    }

    func dismissAction(sendNewSharedConfiguration: Bool?) {
        assert(Thread.isMainThread)
        guard let discussionObjectID = sharedConfigurationInScratchViewContext.discussion?.objectID else {
            delegate?.dismissAction()
            return
        }
        guard scratchViewContext.hasChanges else {
            delegate?.dismissAction()
            return
        }
        // If we reach this point, the user may have changed the shared settings.
        // We compare the shared settings within the scratch context with those within the view context.
        guard let sharedConfigurationInViewContext = try? PersistedDiscussionSharedConfiguration.get(objectID: sharedConfigurationInScratchViewContext.objectID, within: ObvStack.shared.viewContext) else {
            assertionFailure()
            delegate?.dismissAction()
            return
        }
        guard sharedConfigurationInViewContext.differs(from: sharedConfigurationInScratchViewContext) else {
            delegate?.dismissAction()
            return
        }
        // If we reach this point, we should as the user to confirm her changes since they will be shared with other participants
        guard let confirmed = sendNewSharedConfiguration else {
            showConfirmationMessageBeforeSavingSharedConfig = true
            return
        }
        if confirmed {
            let expirationJSON = sharedConfigurationInScratchViewContext.toExpirationJSON()
            ObvMessengerInternalNotification.userWantsToSetAndShareNewDiscussionSharedExpirationConfiguration(
                persistedDiscussionObjectID: discussionObjectID,
                expirationJSON: expirationJSON,
                ownedCryptoId: ownedIdentityInViewContext.cryptoId)
                .postOnDispatchQueue()
        }
        delegate?.dismissAction()
    }

}

fileprivate extension PersistedDiscussionLocalConfiguration {

    var _autoRead: OptionalBoolType {
        OptionalBoolType(autoRead)
    }

    var _retainWipedOutboundMessages: OptionalBoolType {
        OptionalBoolType(retainWipedOutboundMessages)
    }

    var _doSendReadReceipt: OptionalBoolType {
        OptionalBoolType(doSendReadReceipt)
    }

    var _doFetchContentRichURLsMetadata: OptionalFetchContentRichURLsMetadataChoice {
        OptionalFetchContentRichURLsMetadataChoice(doFetchContentRichURLsMetadata)
    }

    var _countBasedRetentionIsActive: OptionalBoolType {
        OptionalBoolType(countBasedRetentionIsActive)
    }

    var _muteNotificationsDuration: MuteDurationOption? { nil }

}

extension PersistedDiscussionSharedConfiguration {

    func setReadOnce(model: DiscussionExpirationSettingsViewModel, to value: Bool) {
        model.updateSharedConfiguration(with: .readOnce(readOnce: value))
    }

    static func toDurationOption(_ timeInterval: TimeInterval?, setValue: (DurationOption) -> Void) -> DurationOption {
        guard let timeInterval = timeInterval else { return .none }
        if let option = DurationOption(rawValue: Int(timeInterval)) {
            return option
        } else {
            // Set the value of the configuration to none since we are not able to build a DurationOption from the stored value.
            setValue(.none)
            return .none
        }
    }

    func getVisibilityDurationOption(model: DiscussionExpirationSettingsViewModel) -> DurationOption {
        return Self.toDurationOption(visibilityDuration) { setVisibilityDurationOption(model: model, to: $0) }
    }

    func setVisibilityDurationOption(model: DiscussionExpirationSettingsViewModel, to value: DurationOption) {
        model.updateSharedConfiguration(with: .visibilityDuration(visibilityDuration: value.timeInterval))
    }

    func getExistenceDurationOption(model: DiscussionExpirationSettingsViewModel) -> DurationOption {
        return Self.toDurationOption(existenceDuration) { setExistenceDurationOption(model: model, to: $0) }
    }

    func setExistenceDurationOption(model: DiscussionExpirationSettingsViewModel, to value: DurationOption) {
        model.updateSharedConfiguration(with: .existenceDuration(existenceDuration: value.timeInterval))
    }

}

enum OptionalBoolType: Int, CaseIterable, Identifiable {

    case none = -1
    case falseValue = 0
    case trueValue = 1
    var id: Int { rawValue }
    init(_ value: Bool?) {
        switch value {
        case .none:
            self = .none
        case .some(let val):
            self = val ? .trueValue : .falseValue
        }
    }
    var value: Bool? {
        switch self {
        case .none: return nil
        case .trueValue: return true
        case .falseValue: return false
        }
    }
}

enum OptionalFetchContentRichURLsMetadataChoice: Int, CaseIterable, Identifiable {
    case none = -1
    case never = 0
    case withinSentMessagesOnly = 1
    case always = 2
    var id: Int { rawValue }
    init(_ value: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice?) {
        switch value {
        case .none:
            self = .none
        case .some(let val):
            switch val {
            case .never: self = .never
            case .withinSentMessagesOnly: self = .withinSentMessagesOnly
            case .always: self = .always
            }
        }
    }
    var value: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice? {
        switch self {
        case .none: return nil
        case .never: return .never
        case .withinSentMessagesOnly: return .withinSentMessagesOnly
        case .always: return .always
        }
    }
}

struct DiscussionExpirationSettingsWrapperView: View {

    @ObservedObject fileprivate var model: DiscussionExpirationSettingsViewModel
    @ObservedObject fileprivate var localConfiguration: PersistedDiscussionLocalConfiguration
    fileprivate var sharedConfiguration: PersistedDiscussionSharedConfiguration

    var body: some View {
        DiscussionExpirationSettingsView(
            changed: $model.changed,
            readOnce: ValueWithBinding(sharedConfiguration, \.readOnce) { value, _ in
                sharedConfiguration.setReadOnce(model: model, to: value)
            },
            autoRead: ValueWithBinding(localConfiguration, \._autoRead) {
                PersistedDiscussionLocalConfigurationValue.autoRead(autoRead: $0.value).sendUpdateRequestNotifications(with: $1)
            },
            visibilityDurationOption: ValueWithBinding(sharedConfiguration, sharedConfiguration.getVisibilityDurationOption(model: model)) { value, _ in
                sharedConfiguration.setVisibilityDurationOption(model: model, to: value)
            },
            existenceDurationOption: ValueWithBinding(sharedConfiguration, sharedConfiguration.getExistenceDurationOption(model: model)) { value, _ in
                sharedConfiguration.setExistenceDurationOption(model: model, to: value)
            },
            retainWipedOutboundMessages: ValueWithBinding(localConfiguration, \._retainWipedOutboundMessages) {
                PersistedDiscussionLocalConfigurationValue.retainWipedOutboundMessages(retainWipedOutboundMessages: $0.value).sendUpdateRequestNotifications(with: $1)
            },
            doSendReadReceipt: ValueWithBinding(localConfiguration, \._doSendReadReceipt) {
                PersistedDiscussionLocalConfigurationValue.doSendReadReceipt(doSendReadReceipt: $0.value).sendUpdateRequestNotifications(with: $1)
            },
            doFetchContentRichURLsMetadata: ValueWithBinding(localConfiguration, \._doFetchContentRichURLsMetadata) {
                PersistedDiscussionLocalConfigurationValue.doFetchContentRichURLsMetadata(doFetchContentRichURLsMetadata: $0.value).sendUpdateRequestNotifications(with: $1) },
            showConfirmationMessageBeforeSavingSharedConfig: $model.showConfirmationMessageBeforeSavingSharedConfig,
            countBasedRetentionIsActive: ValueWithBinding(localConfiguration, \._countBasedRetentionIsActive) {
                PersistedDiscussionLocalConfigurationValue.countBasedRetentionIsActive(countBasedRetentionIsActive: $0.value).sendUpdateRequestNotifications(with: $1)
            },
            countBasedRetention: ValueWithBinding(
                localConfiguration, \.countBasedRetention,
                defaultValue: ObvMessengerSettings.Discussions.countBasedRetentionPolicy) {
                    PersistedDiscussionLocalConfigurationValue.countBasedRetention(countBasedRetention: $0).sendUpdateRequestNotifications(with: $1) },
            timeBasedRetention: ValueWithBinding(
                localConfiguration, \.timeBasedRetention) {
                    PersistedDiscussionLocalConfigurationValue.timeBasedRetention(timeBasedRetention: $0).sendUpdateRequestNotifications(with: $1) },
            muteNotificationsEndDate: localConfiguration.currentMuteNotificationsEndDate,
            muteNotificationsDuration:
                ValueWithBinding(
                    localConfiguration, \._muteNotificationsDuration) {
                        PersistedDiscussionLocalConfigurationValue.muteNotificationsDuration(muteNotificationsDuration: $0).sendUpdateRequestNotifications(with: $1) },
            defaultEmoji: ValueWithBinding(
                localConfiguration, \.defaultEmoji) {
                    PersistedDiscussionLocalConfigurationValue.defaultEmoji(emoji: $0).sendUpdateRequestNotifications(with: $1) },
            sharedConfigCanBeModified: model.sharedConfigCanBeModified,
            dismissAction: model.dismissAction)
    }

}


fileprivate struct DiscussionExpirationSettingsView: View {

    @Binding var changed: Bool
    let readOnce: ValueWithBinding<PersistedDiscussionSharedConfiguration, Bool>
    let autoRead: ValueWithBinding<PersistedDiscussionLocalConfiguration, OptionalBoolType>
    let visibilityDurationOption: ValueWithBinding<PersistedDiscussionSharedConfiguration, DurationOption>
    let existenceDurationOption: ValueWithBinding<PersistedDiscussionSharedConfiguration, DurationOption>
    let retainWipedOutboundMessages: ValueWithBinding<PersistedDiscussionLocalConfiguration, OptionalBoolType>
    let doSendReadReceipt: ValueWithBinding<PersistedDiscussionLocalConfiguration, OptionalBoolType>
    let doFetchContentRichURLsMetadata: ValueWithBinding<PersistedDiscussionLocalConfiguration, OptionalFetchContentRichURLsMetadataChoice>
    @Binding var showConfirmationMessageBeforeSavingSharedConfig: Bool
    let countBasedRetentionIsActive: ValueWithBinding<PersistedDiscussionLocalConfiguration, OptionalBoolType>
    let countBasedRetention: ValueWithBinding<PersistedDiscussionLocalConfiguration, Int>
    let timeBasedRetention: ValueWithBinding<PersistedDiscussionLocalConfiguration, DurationOptionAltOverride>
    let muteNotificationsEndDate: Date?
    let muteNotificationsDuration: ValueWithBinding<PersistedDiscussionLocalConfiguration, MuteDurationOption?>
    let defaultEmoji: ValueWithBinding<PersistedDiscussionLocalConfiguration, String?>

    let sharedConfigCanBeModified: Bool
    var dismissAction: (Bool?) -> Void

    @State private var showingMuteActionSheet = false

    private func countBasedRetentionIncrement() {
        countBasedRetention.binding.wrappedValue += 10
    }

    private func countBasedRetentionDecrement() {
        countBasedRetention.binding.wrappedValue = max(10, countBasedRetention.value - 10)
    }

    private var stringPartForDoFetchContentRichURLsMetadata: String {
        switch ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata {
        case .never:
            return CommonString.Word.Never
        case .withinSentMessagesOnly:
            return NSLocalizedString("Sent messages only", comment: "")
        case .always:
            return CommonString.Word.Always
        }
    }

    var muteNotificationsFooter: Text {
        if let muteNotificationsEndDate = muteNotificationsEndDate {
            if muteNotificationsEndDate == Date.distantFuture {
                return Text("MUTED_NOTIFICATIONS_FOOTER_INDEFINITELY")
            } else {
                return Text("MUTED_NOTIFICATIONS_FOOTER_UNTIL_\(PersistedDiscussionLocalConfiguration.formatDateForMutedNotification(muteNotificationsEndDate))")
            }
        } else {
            return Text("UNMUTED_NOTIFICATIONS_FOOTER")
        }
    }

    var body: some View {
        NavigationView {
            Form {
                /* LOCAL SETTINGS */
                Group {
                    Section(footer: muteNotificationsFooter) {
                        Toggle(isOn: .init {
                            muteNotificationsEndDate != nil
                        } set: { newValue in
                            if newValue {
                                showingMuteActionSheet.toggle()
                            } else {
                                muteNotificationsDuration.set(nil)
                            }
                        }) {
                            ObvLabel("MUTE_NOTIFICATIONS", systemImage: ObvMessengerConstants.muteIcon.systemName)
                        }
                    }
                    Section(footer: Text("SEND_READ_RECEIPT_SECTION_FOOTER")) {
                        Picker(selection: doSendReadReceipt.binding, label: ObvLabel("SEND_READ_RECEIPTS_LABEL", systemImage: "eye.fill")) {
                            ForEach(OptionalBoolType.allCases) { optionalBool in
                                switch optionalBool {
                                case .none:
                                    let textAppDefault = ObvMessengerSettings.Discussions.doSendReadReceipt ? CommonString.Word.Yes : CommonString.Word.No
                                    Text("\(CommonString.Word.Default) (\(textAppDefault))").tag(optionalBool)
                                case .trueValue:
                                    Text(CommonString.Word.Yes).tag(optionalBool)
                                case .falseValue:
                                    Text(CommonString.Word.No).tag(optionalBool)
                                }
                            }
                        }
                    }
                    Section {
                        Picker(selection: doFetchContentRichURLsMetadata.binding, label: ObvLabel("SHOW_RICH_LINK_PREVIEW_LABEL", systemImage: "text.below.photo.fill")) {
                            ForEach(OptionalFetchContentRichURLsMetadataChoice.allCases) { value in
                                switch value {
                                case .none:
                                    Text("\(CommonString.Word.Default) (\(stringPartForDoFetchContentRichURLsMetadata))").tag(value)
                                case .never:
                                    Text(CommonString.Word.Never).tag(value)
                                case .withinSentMessagesOnly:
                                    Text("Sent messages only").tag(value)
                                case .always:
                                    Text(CommonString.Word.Always).tag(value)
                                }
                            }
                        }
                    }
                    if #available(iOS 15.0, *) {
                        ChangeDefaultEmojiView(defaultEmoji: defaultEmoji.binding)
                    }
                }
                /* RETENTION SETTINGS */
                Group {
                    Section {
                        Text("RETENTION_SETTINGS_TITLE")
                            .font(.headline)
                        Text("LOCAL_RETENTION_SETTINGS_EXPLANATION")
                            .font(.callout)
                    }
                    Section(footer: Text("COUNT_BASED_SINGLE_DISCUSSION_SECTION_FOOTER")) {
                        Picker(selection: countBasedRetentionIsActive.binding, label: ObvLabel("COUNT_BASED_LABEL", systemImage: "number")) {
                            ForEach(OptionalBoolType.allCases) { optionalBool in
                                switch optionalBool {
                                case .none:
                                    let textAppDefault = ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive ? CommonString.Word.Yes : CommonString.Word.No
                                    Text("\(CommonString.Word.Default) (\(textAppDefault))").tag(optionalBool)
                                case .trueValue:
                                    Text(CommonString.Word.Yes).tag(optionalBool)
                                case .falseValue:
                                    Text(CommonString.Word.No).tag(optionalBool)
                                }
                            }
                        }
                        switch countBasedRetentionIsActive.value {
                        case .none:
                            if ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive {
                                Stepper(onIncrement: countBasedRetentionIncrement,
                                        onDecrement: countBasedRetentionDecrement) {
                                    Text("KEEP_\(countBasedRetention.value)_MESSAGES")
                                }
                            } else {
                                EmptyView()
                            }
                        case .falseValue:
                            EmptyView()
                        case .trueValue:
                            Stepper(onIncrement: countBasedRetentionIncrement,
                                    onDecrement: countBasedRetentionDecrement) {
                                Text("KEEP_\(countBasedRetention.value)_MESSAGES")
                            }
                        }
                    }
                    Section(footer: Text("TIME_BASED_SINGLE_DISCUSSION_SECTION_FOOTER")) {
                        Picker(selection: timeBasedRetention.binding, label: ObvLabel("TIME_BASED_LABEL", systemImage: "calendar.badge.clock")) {
                            ForEach(DurationOptionAltOverride.allCases) { durationOverride in
                                switch durationOverride {
                                case .useAppDefault:
                                    let textAppDefault = ObvMessengerSettings.Discussions.timeBasedRetentionPolicy.description
                                    Text("\(durationOverride.description) (\(textAppDefault))").tag(durationOverride)
                                default:
                                    Text(durationOverride.description).tag(durationOverride)
                                }
                            }
                        }
                    }
                }
                /* EPHEMERAL MESSAGES - LOCAL CONFIG */
                Group {
                    Section {
                        VStack(alignment: .leading) {
                            Text("EPHEMERAL_MESSAGES")
                                .font(.headline)
                            Text("LOCAL_CONFIG")
                                .font(.callout)
                                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        }
                        Text("LOCAL_EPHEMERAL_SETTINGS_EXPLANATION")
                            .font(.callout)
                    }
                    Section(footer: Text("AUTO_READ_SECTION_FOOTER")) {
                        Picker(selection: autoRead.binding, label: ObvLabel("AUTO_READ_LABEL", systemImage: "hand.tap.fill")) {
                            ForEach(OptionalBoolType.allCases) { optionalBool in
                                switch optionalBool {
                                case .none:
                                    let textAppDefault = ObvMessengerSettings.Discussions.autoRead ? CommonString.Word.Yes : CommonString.Word.No
                                    Text("\(CommonString.Word.Default) (\(textAppDefault))").tag(optionalBool)
                                case .trueValue:
                                    Text(CommonString.Word.Yes).tag(optionalBool)
                                case .falseValue:
                                    Text(CommonString.Word.No).tag(optionalBool)
                                }
                            }
                        }
                    }
                    Section(footer: Text("RETAIN_WIPED_OUTBOUND_MESSAGES_SECTION_FOOTER")) {
                        Picker(selection: retainWipedOutboundMessages.binding, label: ObvLabel("RETAIN_WIPED_OUTBOUND_MESSAGES_LABEL", systemImage: "trash.slash")) {
                            ForEach(OptionalBoolType.allCases) { optionalBool in
                                switch optionalBool {
                                case .none:
                                    let textAppDefault = ObvMessengerSettings.Discussions.retainWipedOutboundMessages ? CommonString.Word.Yes : CommonString.Word.No
                                    Text("\(CommonString.Word.Default) (\(textAppDefault))").tag(optionalBool)
                                case .trueValue:
                                    Text(CommonString.Word.Yes).tag(optionalBool)
                                case .falseValue:
                                    Text(CommonString.Word.No).tag(optionalBool)
                                }
                            }
                        }
                    }
                    /* SHARED SETTINGS FOR EPHEMERAL MESSAGES */
                    Section {
                        VStack(alignment: .leading) {
                            Text("EPHEMERAL_MESSAGES")
                                .font(.headline)
                            Text("SHARED_CONFIG")
                                .font(.callout)
                                .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        }
                        Text("EXPIRATION_SETTINGS_EXPLANATION")
                            .font(.callout)
                        if !sharedConfigCanBeModified {
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: "person.fill.questionmark")
                                Text("ONLY_GROUP_OWNER_CAN_MODIFY")
                            }.font(.callout)
                        }
                    }
                    Section(footer: Text("READ_ONCE_SECTION_FOOTER")) {
                        Toggle(isOn: readOnce.binding) {
                            ObvLabel("READ_ONCE_LABEL", systemImage: "flame.fill")
                        }.disabled(!sharedConfigCanBeModified)
                    }
                    Section(footer: Text("LIMITED_VISIBILITY_SECTION_FOOTER")) {
                        Picker(selection: visibilityDurationOption.binding, label: ObvLabel("LIMITED_VISIBILITY_LABEL", systemImage: "eyes")) {
                            ForEach(DurationOption.allCases) { duration in
                                Text(duration.description).tag(duration)
                            }
                        }.disabled(!sharedConfigCanBeModified)
                    }
                    Section(footer: Text("LIMITED_EXISTENCE_SECTION_FOOTER")) {
                        Picker(selection: existenceDurationOption.binding, label: ObvLabel("LIMITED_EXISTENCE_SECTION_LABEL", systemImage: "timer")) {
                            ForEach(DurationOption.allCases) { duration in
                                Text(duration.description).tag(duration)
                            }
                        }.disabled(!sharedConfigCanBeModified)
                    }
                }
            }
            .navigationBarTitle(CommonString.Title.discussionSettings)
            .navigationBarItems(leading:
                                    Button(action: { dismissAction(nil) },
                                           label: {
                Image(systemName: "xmark.circle.fill")
                    .font(Font.system(size: 24, weight: .semibold, design: .default))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
            })
            )
            .alert(isPresented: $showConfirmationMessageBeforeSavingSharedConfig) {
                Alert(title: Text("MODIFIED_SHARED_SETTINGS_CONFIRMATION_TITLE"),
                      message: Text("MODIFIED_SHARED_SETTINGS_CONFIRMATION_MESSAGE"),
                      primaryButton: Alert.Button.cancel(Text(CommonString.Word.Discard), action: {
                    dismissAction(false)
                }),
                      secondaryButton: Alert.Button.default(Text(CommonString.Word.Update), action: {
                    dismissAction(true)
                })
                )
            }
            .actionSheet(isPresented: $showingMuteActionSheet) {
                return ActionSheet(title: Text("MUTE_NOTIFICATIONS"),
                                   buttons: muteActionSheetButtons)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Prevents split on iPad
    }

    private var muteActionSheetButtons: [ActionSheet.Button] {
        var buttons = [ActionSheet.Button]()
        buttons += MuteDurationOption.allCases.map { duration in
            return Alert.Button.default(
                Text(duration.description),
                action: {
                    muteNotificationsDuration.set(duration)
                    changed.toggle()
                })
        }
        buttons += [.cancel()]
        return buttons
    }
}

@available(iOS 15, *)
struct ChangeDefaultEmojiView: View {

    @Binding var defaultEmoji: String?
    @State private var showingEmojiPickerSheet = false

    var body: some View {
        Section {
            Button(action: {
                showingEmojiPickerSheet = true
            }) {
                HStack {
                    Image(systemIcon: .handThumbsup)
                        .foregroundColor(.blue)
                    Text("DEFAULT_EMOJI")
                        .foregroundColor(Color(AppTheme.shared.colorScheme.label))
                    Spacer()
                    if let defaultEmoji = defaultEmoji {
                        Text(defaultEmoji)
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    } else {
                        Text("\(CommonString.Word.Default) (\(ObvMessengerSettings.Emoji.defaultEmojiButton ?? ObvMessengerConstants.defaultEmoji))")
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    }
                }
            }
        }
        .sheet(isPresented: $showingEmojiPickerSheet) {
            EmojiPickerView(model: EmojiPickerViewModel(selectedEmoji: defaultEmoji) { emoji in
                self.defaultEmoji = emoji
                self.showingEmojiPickerSheet = false
            })
        }
    }
}


struct DiscussionExpirationSettingsView_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            DiscussionExpirationSettingsView(
                changed: .constant(false),
                readOnce: ValueWithBinding(constant: false),
                autoRead: ValueWithBinding(constant: .falseValue),
                visibilityDurationOption: ValueWithBinding(constant: .none),
                existenceDurationOption: ValueWithBinding(constant: .ninetyDays),
                retainWipedOutboundMessages: ValueWithBinding(constant: .falseValue),
                doSendReadReceipt: ValueWithBinding(constant: .none),
                doFetchContentRichURLsMetadata: ValueWithBinding(constant: .none),
                showConfirmationMessageBeforeSavingSharedConfig: .constant(false),
                countBasedRetentionIsActive: ValueWithBinding(constant: .none),
                countBasedRetention: ValueWithBinding(constant: 0),
                timeBasedRetention: ValueWithBinding(constant: .useAppDefault),
                muteNotificationsEndDate: nil,
                muteNotificationsDuration: ValueWithBinding(constant: .indefinitely),
                defaultEmoji: ValueWithBinding(constant: nil),
                sharedConfigCanBeModified: true,
                dismissAction: { _ in })
            DiscussionExpirationSettingsView(
                changed: .constant(false),
                readOnce: ValueWithBinding(constant: true),
                autoRead: ValueWithBinding(constant: .falseValue),
                visibilityDurationOption: ValueWithBinding(constant: .oneHour),
                existenceDurationOption: ValueWithBinding(constant: .none),
                retainWipedOutboundMessages: ValueWithBinding(constant: .trueValue),
                doSendReadReceipt: ValueWithBinding(constant: .trueValue),
                doFetchContentRichURLsMetadata: ValueWithBinding(constant: .withinSentMessagesOnly),
                showConfirmationMessageBeforeSavingSharedConfig: .constant(false),
                countBasedRetentionIsActive: ValueWithBinding(constant: .none),
                countBasedRetention: ValueWithBinding(constant: 0),
                timeBasedRetention: ValueWithBinding(constant: .none),
                muteNotificationsEndDate: Date.distantFuture,
                muteNotificationsDuration: ValueWithBinding(constant: .indefinitely),
                defaultEmoji: ValueWithBinding(constant: nil),
                sharedConfigCanBeModified: false,
                dismissAction: { _ in })
        }
    }
}


struct ObvLabel: View {

    let title: LocalizedStringKey
    let systemImage: String

    init(_ title: LocalizedStringKey, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Group {
            if #available(iOS 14, *) {
                Label(title, systemImage: systemImage)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: systemImage)
                        .foregroundColor(.blue)
                    Text(title)
                }
            }
        }
    }

}
