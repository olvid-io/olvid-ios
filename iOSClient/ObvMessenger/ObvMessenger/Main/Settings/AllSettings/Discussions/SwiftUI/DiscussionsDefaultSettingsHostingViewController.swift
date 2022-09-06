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

import Foundation
import SwiftUI
import Combine


final class DiscussionsDefaultSettingsHostingViewController: UIHostingController<DiscussionsDefaultSettingsWrapperView> {

    fileprivate let model: DiscussionsDefaultSettingsViewModel

    init() {
        assert(Thread.isMainThread)
        let model = DiscussionsDefaultSettingsViewModel()
        let view = DiscussionsDefaultSettingsWrapperView(model: model)
        self.model = model
        super.init(rootView: view)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Discussion
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}



final fileprivate class DiscussionsDefaultSettingsViewModel: ObservableObject {

    var doSendReadReceipt: Binding<Bool>!
    var doFetchContentRichURLsMetadata: Binding<ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice>!
    var readOnce: Binding<Bool>!
    var visibilityDuration: Binding<DurationOption>!
    var existenceDuration: Binding<DurationOption>!
    var countBasedRetentionIsActive: Binding<Bool>!
    var countBasedRetention: Binding<Int>!
    var timeBasedRetention: Binding<DurationOptionAlt>!
    var autoRead: Binding<Bool>!
    var retainWipedOutboundMessages: Binding<Bool>!
    var notificationSound: Binding<OptionalNotificationSound>!

    @Published var changed: Bool // This allows to "force" the refresh of the view

    init() {
        self.changed = false
        self.doSendReadReceipt = Binding<Bool>(get: getDoSendReadReceipt, set: setDoSendReadReceipt)
        self.doFetchContentRichURLsMetadata = Binding<ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice>(get: getDoFetchContentRichURLsMetadata, set: setDoFetchContentRichURLsMetadata)
        self.readOnce = Binding<Bool>(get: getReadOnce, set: setReadOnce)
        self.visibilityDuration = Binding<DurationOption>(get: getVisibilityDuration, set: setVisibilityDuration)
        self.existenceDuration = Binding<DurationOption>(get: getExistenceDuration, set: setExistenceDuration)
        self.countBasedRetention = Binding<Int>(get: getCountBasedRetention, set: setCountBasedRetention)
        self.countBasedRetentionIsActive = Binding<Bool>(get: getCountBasedRetentionIsActive, set: setCountBasedRetentionIsActive)
        self.timeBasedRetention = Binding<DurationOptionAlt>(get: getTimeBasedRetention, set: setTimeBasedRetention)
        self.autoRead = Binding<Bool>(get: getAutoRead, set: setAutoRead)
        self.retainWipedOutboundMessages = Binding<Bool>(get: getRetainWipedOutboundMessages, set: setRetainWipedOutboundMessages)
        self.notificationSound = Binding<OptionalNotificationSound>(get: getNotificationSound, set: setNotificationSound)
    }
    
    private func getTimeBasedRetention() -> DurationOptionAlt {
        ObvMessengerSettings.Discussions.timeBasedRetentionPolicy
    }
    
    private func setTimeBasedRetention(_ newValue: DurationOptionAlt) {
        ObvMessengerSettings.Discussions.timeBasedRetentionPolicy = newValue
        withAnimation {
            self.changed.toggle()
        }
    }
    
    private func getCountBasedRetentionIsActive() -> Bool {
        return ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive
    }
    
    private func setCountBasedRetentionIsActive(_ newValue: Bool) {
        ObvMessengerSettings.Discussions.countBasedRetentionPolicyIsActive = newValue
        withAnimation {
            self.changed.toggle()
        }
    }

    private func getCountBasedRetention() -> Int {
        ObvMessengerSettings.Discussions.countBasedRetentionPolicy
    }
    
    private func setCountBasedRetention(_ newValue: Int) {
        ObvMessengerSettings.Discussions.countBasedRetentionPolicy = newValue
        withAnimation {
            self.changed.toggle()
        }
    }
    
    private func getDoSendReadReceipt() -> Bool {
        ObvMessengerSettings.Discussions.doSendReadReceipt
    }

    private func setDoSendReadReceipt(_ newValue: Bool) {
        ObvMessengerSettings.Discussions.doSendReadReceipt = newValue
        withAnimation {
            self.changed.toggle()
        }
    }
    
    private func getDoFetchContentRichURLsMetadata() -> ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice {
        ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata
    }

    private func setDoFetchContentRichURLsMetadata(_ newValue: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice) {
        ObvMessengerSettings.Discussions.doFetchContentRichURLsMetadata = newValue
        self.changed.toggle() // No animation
    }
    
    private func getReadOnce() -> Bool {
        ObvMessengerSettings.Discussions.readOnce
    }
    
    private func setReadOnce(_ newValue: Bool) {
        ObvMessengerSettings.Discussions.readOnce = newValue
        withAnimation {
            self.changed.toggle()
        }
    }

    private func getVisibilityDuration() -> DurationOption {
        ObvMessengerSettings.Discussions.visibilityDuration
    }
    
    private func setVisibilityDuration(_ newValue: DurationOption) {
        ObvMessengerSettings.Discussions.visibilityDuration = newValue
        withAnimation {
            self.changed.toggle()
        }
    }

    private func getExistenceDuration() -> DurationOption {
        ObvMessengerSettings.Discussions.existenceDuration
    }
    
    private func setExistenceDuration(_ newValue: DurationOption) {
        ObvMessengerSettings.Discussions.existenceDuration = newValue
        withAnimation {
            self.changed.toggle()
        }
    }

    private func getAutoRead() -> Bool {
        ObvMessengerSettings.Discussions.autoRead
    }

    private func setAutoRead(_ newValue: Bool) {
        ObvMessengerSettings.Discussions.autoRead = newValue
        withAnimation {
            self.changed.toggle()
        }
    }

    private func getRetainWipedOutboundMessages() -> Bool {
        ObvMessengerSettings.Discussions.retainWipedOutboundMessages
    }

    private func setRetainWipedOutboundMessages(_ newValue: Bool) {
        ObvMessengerSettings.Discussions.retainWipedOutboundMessages = newValue
        withAnimation {
            self.changed.toggle()
        }
    }

    private func getNotificationSound() -> OptionalNotificationSound {
        if let notificationSound = ObvMessengerSettings.Discussions.notificationSound {
            return OptionalNotificationSound.some(notificationSound)
        } else {
            return OptionalNotificationSound.some(.system)
        }
    }

    private func setNotificationSound(_ newValue: OptionalNotificationSound) {
        ObvMessengerSettings.Discussions.notificationSound = newValue.value
        withAnimation {
            self.changed.toggle()
        }
    }
}




struct DiscussionsDefaultSettingsWrapperView: View {
    
    @ObservedObject fileprivate var model: DiscussionsDefaultSettingsViewModel

    var body: some View {
        DiscussionsDefaultSettingsView(doSendReadReceipt: model.doSendReadReceipt,
                                       doFetchContentRichURLsMetadata: model.doFetchContentRichURLsMetadata,
                                       readOnce: model.readOnce,
                                       visibilityDuration: model.visibilityDuration,
                                       existenceDuration: model.existenceDuration,
                                       countBasedRetentionIsActive: model.countBasedRetentionIsActive,
                                       countBasedRetention: model.countBasedRetention,
                                       timeBasedRetention: model.timeBasedRetention,
                                       autoRead: model.autoRead,
                                       retainWipedOutboundMessages: model.retainWipedOutboundMessages,
                                       notificationSound: model.notificationSound,
                                       changed: $model.changed)
    }
    
}

fileprivate struct DiscussionsDefaultSettingsView: View {
    
    @Binding var doSendReadReceipt: Bool
    @Binding var doFetchContentRichURLsMetadata: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice
    @Binding var readOnce: Bool
    @Binding var visibilityDuration: DurationOption
    @Binding var existenceDuration: DurationOption
    @Binding var countBasedRetentionIsActive: Bool
    @Binding var countBasedRetention: Int
    @Binding var timeBasedRetention: DurationOptionAlt
    @Binding var autoRead: Bool
    @Binding var retainWipedOutboundMessages: Bool
    @Binding var notificationSound: OptionalNotificationSound
    @Binding var changed: Bool

    @State private var presentChooseNotificationSoundSheet: Bool = false

    private var sendReadReceiptSectionFooter: Text {
        Text(doSendReadReceipt ? DiscussionsSettingsTableViewController.Strings.SendReadRecceipts.explanationWhenYes : DiscussionsSettingsTableViewController.Strings.SendReadRecceipts.explanationWhenNo)
    }

    private func countBasedRetentionIncrement() {
        countBasedRetention += 10
    }

    private func countBasedRetentionDecrement() {
        countBasedRetention = max(10, countBasedRetention - 10)
    }

    var body: some View {
        Form {
            Section(footer: sendReadReceiptSectionFooter) {
                Toggle(isOn: $doSendReadReceipt) {
                    ObvLabel("SEND_READ_RECEIPTS_LABEL", systemImage: "eye.fill")
                }
            }
            Section {
                Picker(selection: $doFetchContentRichURLsMetadata, label:
                        ObvLabel("SHOW_RICH_LINK_PREVIEW_LABEL", systemImage: "text.below.photo.fill")) {
                    ForEach(ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice.allCases) { value in
                        switch value {
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
            Section {
                NotificationSoundPicker(selection: $notificationSound, showDefault: false) { sound -> Text in
                    switch sound {
                    case .none:
                        return Text(CommonString.Title.systemSound)
                            .italic()
                    case .some(let sound):
                        if sound == .system {
                            return Text(sound.description)
                                .italic()
                        } else {
                            return Text(sound.description)
                        }
                    }
                }
            }
            Group {
                Section {
                    Text("RETENTION_SETTINGS_TITLE")
                        .font(.headline)
                    Text("GLOBAL_RETENTION_SETTINGS_EXPLANATION")
                        .font(.callout)
                }
                Section(footer: Text("COUNT_BASED_SECTION_FOOTER")) {
                    Toggle(isOn: $countBasedRetentionIsActive) {
                        ObvLabel("COUNT_BASED_LABEL", systemImage: "number")
                    }
                    if countBasedRetentionIsActive {
                        Stepper(onIncrement: countBasedRetentionIncrement,
                                onDecrement: countBasedRetentionDecrement) {
                            Text("KEEP_\(countBasedRetention)_MESSAGES")
                        }
                    }
                }
                Section(footer: Text("TIME_BASED_SECTION_FOOTER")) {
                    Picker(selection: $timeBasedRetention, label: ObvLabel("TIME_BASED_LABEL", systemIcon: .calendarBadgeClock)) {
                        ForEach(DurationOptionAlt.allCases) { duration in
                            Text(duration.description).tag(duration)
                        }
                    }
                }
            }
            Group {
                Section {
                    VStack(alignment: .leading) {
                        Text("EXPIRATION_SETTINGS_TITLE")
                            .font(.headline)
                        Text("LOCAL_CONFIG")
                            .font(.callout)
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    }
                    Text("GLOBAL_LOCAL_EPHEMERAL_SETTINGS_EXPLANATION")
                        .font(.callout)
                }
                Section(footer: Text("AUTO_READ_SECTION_FOOTER")) {
                    Toggle(isOn: $autoRead) {
                        ObvLabel("AUTO_READ_LABEL", systemImage: "hand.tap.fill")
                    }
                }
                Section(footer: Text("RETAIN_WIPED_OUTBOUND_MESSAGES_SECTION_FOOTER")) {
                    Toggle(isOn: $retainWipedOutboundMessages) {
                        ObvLabel("RETAIN_WIPED_OUTBOUND_MESSAGES_LABEL", systemImage: "trash.slash")
                    }
                }
            }
            Group {
                Section {
                    VStack(alignment: .leading) {
                        Text("EXPIRATION_SETTINGS_TITLE")
                            .font(.headline)
                        Text("SHARED_CONFIG")
                            .font(.callout)
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    }
                    Text("GLOBAL_EXPIRATION_SETTINGS_EXPLANATION")
                        .font(.callout)
                }
                Section(footer: Text("READ_ONCE_SECTION_FOOTER")) {
                    Toggle(isOn: $readOnce) {
                        ObvLabel("READ_ONCE_LABEL", systemImage: "flame.fill")
                    }
                }
                Section(footer: Text("LIMITED_VISIBILITY_SECTION_FOOTER")) {
                    Picker(selection: $visibilityDuration, label: ObvLabel("LIMITED_VISIBILITY_LABEL", systemIcon: .eyes)) {
                        ForEach(DurationOption.allCases) { duration in
                            Text(duration.description).tag(duration)
                        }
                    }
                }
                Section(footer: Text("LIMITED_EXISTENCE_SECTION_FOOTER")) {
                    Picker(selection: $existenceDuration, label: ObvLabel("LIMITED_EXISTENCE_SECTION_LABEL", systemImage: "timer")) {
                        ForEach(DurationOption.allCases) { duration in
                            Text(duration.description).tag(duration)
                        }
                    }
                }
            }
        }
    }
    
}





struct DiscussionsDefaultSettingsView_Previews: PreviewProvider {
    
    static var previews: some View {
        Group {
            DiscussionsDefaultSettingsView(doSendReadReceipt: .constant(false),
                                           doFetchContentRichURLsMetadata: .constant(.never),
                                           readOnce: .constant(false),
                                           visibilityDuration: .constant(.none),
                                           existenceDuration: .constant(.none),
                                           countBasedRetentionIsActive: .constant(false),
                                           countBasedRetention: .constant(0),
                                           timeBasedRetention: .constant(.none),
                                           autoRead: .constant(false),
                                           retainWipedOutboundMessages: .constant(false),
                                           notificationSound: .constant(.none),
                                           changed: .constant(false))
            DiscussionsDefaultSettingsView(doSendReadReceipt: .constant(true),
                                           doFetchContentRichURLsMetadata: .constant(.always),
                                           readOnce: .constant(false),
                                           visibilityDuration: .constant(.oneHour),
                                           existenceDuration: .constant(.oneDay),
                                           countBasedRetentionIsActive: .constant(true),
                                           countBasedRetention: .constant(50),
                                           timeBasedRetention: .constant(.sevenDays),
                                           autoRead: .constant(false),
                                           retainWipedOutboundMessages: .constant(false),
                                           notificationSound: .constant(.some(.bell)),
                                           changed: .constant(false))
                .environment(\.locale, .init(identifier: "fr"))
        }
    }
    
}
