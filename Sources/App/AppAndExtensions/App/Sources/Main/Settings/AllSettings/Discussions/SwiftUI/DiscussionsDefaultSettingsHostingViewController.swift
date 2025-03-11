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

import Foundation
import SwiftUI
import Combine
import ObvUI
import ObvUICoreData
import ObvSystemIcon
import ObvTypes
import ObvSettings
import ObvDesignSystem
import ObvUserNotificationsSounds


final class DiscussionsDefaultSettingsHostingViewController: UIHostingController<DiscussionsDefaultSettingsWrapperView> {

    fileprivate let model: DiscussionsDefaultSettingsViewModel

    init(ownedCryptoId: ObvCryptoId) {
        assert(Thread.isMainThread)
        let model = DiscussionsDefaultSettingsViewModel(ownedCryptoId: ownedCryptoId)
        let view = DiscussionsDefaultSettingsWrapperView(model: model)
        self.model = model
        super.init(rootView: view)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = CommonString.Word.Discussions
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}



final fileprivate class DiscussionsDefaultSettingsViewModel: ObservableObject {

    let ownedCryptoId: ObvCryptoId
    var doSendReadReceipt: Binding<Bool>!
    var alwaysShowNotificationsWhenMentioned: Binding<Bool>!
    var attachLinkPreviewtoMessageSent: Binding<Bool>!
    var fetchMissingLinkPreviewFromMessagereceived: Binding<Bool>!
    var readOnce: Binding<Bool>!
    var visibilityDuration: Binding<TimeInterval?>!
    var existenceDuration: Binding<TimeInterval?>!
    var countBasedRetentionIsActive: Binding<Bool>!
    var countBasedRetention: Binding<Int>!
    var timeBasedRetention: Binding<DurationOptionAlt>!
    var autoRead: Binding<Bool>!
    var retainWipedOutboundMessages: Binding<Bool>!
    var notificationSound: Binding<OptionalNotificationSound>!
    var performInteractionDonation: Binding<Bool>!

    @Published var changed: Bool // This allows to "force" the refresh of the view

    /// Allows to observe changes made to certain settings made from other owned devices
    private var cancellables = Set<AnyCancellable>()

    init(ownedCryptoId: ObvCryptoId) {
        self.ownedCryptoId = ownedCryptoId
        self.changed = false
        self.doSendReadReceipt = Binding<Bool>(get: getDoSendReadReceipt, set: setDoSendReadReceipt)
        alwaysShowNotificationsWhenMentioned = Binding<Bool> {
            return ObvMessengerSettings.Discussions.notificationOptions.contains(.alwaysNotifyWhenMentionnedEvenInMutedDiscussion)
        } set: { newValue in
            if newValue {
                ObvMessengerSettings.Discussions.notificationOptions.insert(.alwaysNotifyWhenMentionnedEvenInMutedDiscussion)
            } else {
                ObvMessengerSettings.Discussions.notificationOptions.remove(.alwaysNotifyWhenMentionnedEvenInMutedDiscussion)
            }

            withAnimation {
                self.changed.toggle()
            }
        }
        self.readOnce = Binding<Bool>(get: getReadOnce, set: setReadOnce)
        self.attachLinkPreviewtoMessageSent = Binding<Bool>(get: getAttachLinkPreviewtoMessageSent, set: setAttachLinkPreviewtoMessageSent)
        self.fetchMissingLinkPreviewFromMessagereceived = Binding<Bool>(get: getFetchMissingLinkPreviewFromMessagereceived, set: setFetchMissingLinkPreviewFromMessagereceived)
        self.visibilityDuration = Binding<TimeInterval?>(get: getVisibilityDuration, set: setVisibilityDuration)
        self.existenceDuration = Binding<TimeInterval?>(get: getExistenceDuration, set: setExistenceDuration)
        self.countBasedRetention = Binding<Int>(get: getCountBasedRetention, set: setCountBasedRetention)
        self.countBasedRetentionIsActive = Binding<Bool>(get: getCountBasedRetentionIsActive, set: setCountBasedRetentionIsActive)
        self.timeBasedRetention = Binding<DurationOptionAlt>(get: getTimeBasedRetention, set: setTimeBasedRetention)
        self.autoRead = Binding<Bool>(get: getAutoRead, set: setAutoRead)
        self.retainWipedOutboundMessages = Binding<Bool>(get: getRetainWipedOutboundMessages, set: setRetainWipedOutboundMessages)
        self.notificationSound = Binding<OptionalNotificationSound>(get: getNotificationSound, set: setNotificationSound)
        self.performInteractionDonation = Binding<Bool>(get: getPerformInteractionDonation, set: setPerformInteractionDonation)
        observeChangesMadeFromOtherOwnedDevices()
    }
    
    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    private func observeChangesMadeFromOtherOwnedDevices() {
        
        ObvMessengerSettingsObservableObject.shared.$doSendReadReceipt
            .compactMap { (doSendReadReceipt, changeMadeFromAnotherOwnedDevice) in
                // We only observe changes made from other owned devices
                guard changeMadeFromAnotherOwnedDevice else { return nil }
                return doSendReadReceipt
            }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (doSendReadReceipt: Bool) in
                withAnimation {
                    self?.changed.toggle()
                }
            }
            .store(in: &cancellables)

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
        ObvMessengerSettings.Discussions.setDoSendReadReceipt(to: newValue, changeMadeFromAnotherOwnedDevice: false)
        withAnimation {
            self.changed.toggle()
        }
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

    private func getAttachLinkPreviewtoMessageSent() -> Bool {
        ObvMessengerSettings.Discussions.attachLinkPreviewToMessageSent
    }
    
    private func setAttachLinkPreviewtoMessageSent(_ newValue: Bool) {
        ObvMessengerSettings.Discussions.attachLinkPreviewToMessageSent = newValue
        withAnimation {
            self.changed.toggle()
        }
    }
    
    private func getFetchMissingLinkPreviewFromMessagereceived() -> Bool {
        ObvMessengerSettings.Discussions.fetchMissingLinkPreviewFromMessageReceived
    }
    
    private func setFetchMissingLinkPreviewFromMessagereceived(_ newValue: Bool) {
        ObvMessengerSettings.Discussions.fetchMissingLinkPreviewFromMessageReceived = newValue
        withAnimation {
            self.changed.toggle()
        }
    }
    
    private func getVisibilityDuration() -> TimeInterval? {
        ObvMessengerSettings.Discussions.visibilityDuration
    }
    
    private func setVisibilityDuration(_ newValue: TimeInterval?) {
        ObvMessengerSettings.Discussions.visibilityDuration = newValue
        withAnimation {
            self.changed.toggle()
        }
    }

    private func getExistenceDuration() -> TimeInterval? {
        ObvMessengerSettings.Discussions.existenceDuration
    }
    
    private func setExistenceDuration(_ newValue: TimeInterval?) {
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

    private func getPerformInteractionDonation() -> Bool {
        ObvMessengerSettings.Discussions.performInteractionDonation
    }

    private func setPerformInteractionDonation(_ newValue: Bool) {
        ObvMessengerSettings.Discussions.performInteractionDonation = newValue
        withAnimation {
            self.changed.toggle()
        }
    }
}




struct DiscussionsDefaultSettingsWrapperView: View {
    
    @ObservedObject fileprivate var model: DiscussionsDefaultSettingsViewModel

    var body: some View {
        DiscussionsDefaultSettingsView(doSendReadReceipt: model.doSendReadReceipt,
                                       alwaysShowNotificationsWhenMentioned: model.alwaysShowNotificationsWhenMentioned,
                                       readOnce: model.readOnce,
                                       attachLinkPreviewtoMessageSent: model.attachLinkPreviewtoMessageSent,
                                       fetchMissingLinkPreviewFromMessagereceived: model.fetchMissingLinkPreviewFromMessagereceived,
                                       visibilityDuration: model.visibilityDuration,
                                       existenceDuration: model.existenceDuration,
                                       countBasedRetentionIsActive: model.countBasedRetentionIsActive,
                                       countBasedRetention: model.countBasedRetention,
                                       timeBasedRetention: model.timeBasedRetention,
                                       autoRead: model.autoRead,
                                       retainWipedOutboundMessages: model.retainWipedOutboundMessages,
                                       notificationSound: model.notificationSound,
                                       performInteractionDonation: model.performInteractionDonation,
                                       changed: $model.changed)
    }
    
}

fileprivate struct DiscussionsDefaultSettingsView: View {
    
    @Binding var doSendReadReceipt: Bool
    @Binding var alwaysShowNotificationsWhenMentioned: Bool
    @Binding var readOnce: Bool
    @Binding var attachLinkPreviewtoMessageSent: Bool
    @Binding var fetchMissingLinkPreviewFromMessagereceived: Bool
    @Binding var visibilityDuration: TimeInterval?
    @Binding var existenceDuration: TimeInterval?
    @Binding var countBasedRetentionIsActive: Bool
    @Binding var countBasedRetention: Int
    @Binding var timeBasedRetention: DurationOptionAlt
    @Binding var autoRead: Bool
    @Binding var retainWipedOutboundMessages: Bool
    @Binding var notificationSound: OptionalNotificationSound
    @Binding var performInteractionDonation: Bool
    @Binding var changed: Bool

    @State private var presentChooseNotificationSoundSheet: Bool = false

    private var sendReadReceiptSectionFooter: Text {
        Text(doSendReadReceipt ? Strings.SendReadRecceipts.explanationWhenYes : Strings.SendReadRecceipts.explanationWhenNo)
    }
    
    private struct Strings {
        struct SendReadRecceipts {
            static let explanationWhenYes = NSLocalizedString("Your contacts will be notified when you have read their messages. This settting can be overriden on a per discussion basis.", comment: "Explantation")
            static let explanationWhenNo = NSLocalizedString("Your contacts won't be notified when you read their messages. This settting can be overriden on a per discussion basis.", comment: "Explantation")
        }
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
                    Label("SEND_READ_RECEIPTS_LABEL", systemImage: "eye.fill")
                }
            }
            Section(footer: Text("discussion-default-settings-view.mention-notification-mode.picker.footer.title")) {
                Picker(selection: $alwaysShowNotificationsWhenMentioned,
                       label: Label("discussion-default-settings-view.mention-notification-mode.picker.title", systemIcon: .bell(.fill))) {
                    Text(NSLocalizedString("discussion-default-settings-view.mention-notification-mode.picker.mode.always",
                                           comment: "Display title for the `always` value for mention notification mode"))
                        .tag(true)

                    Text(NSLocalizedString("discussion-default-settings-view.mention-notification-mode.picker.mode.never",
                                           comment: "Display title for the `never` value for mention notification mode"))
                        .tag(false)
                }
            }
            Section(footer: Text("ATTACH_PREVIEW_SECTION_FOOTER")) {
                Toggle(isOn: $attachLinkPreviewtoMessageSent) {
                    Label("ATTACH_PREVIEW_LABEL", systemImage: "text.below.photo.fill")
                }
            }
            Section(footer: Text("FETCH_MISSING_PREVIEW_SECTION_FOOTER")) {
                Toggle(isOn: $fetchMissingLinkPreviewFromMessagereceived) {
                    Label("FETCH_MISSING_PREVIEW_LABEL", systemImage: "photo.fill.on.rectangle.fill")
                }
            }
            Section {
                NotificationSoundPicker(selection: $notificationSound, showDefault: false) { sound -> Text in
                    switch sound {
                    case .none:
                        return Text(NotificationSound.system.description)
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
            Section(footer: Text("PERFORM_INTERACTION_DONATION_FOOTER")) {
                Toggle(isOn: $performInteractionDonation) {
                    Label("PERFORM_INTERACTION_DONATION_LABEL", systemIcon: .squareAndArrowUp)
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
                        Label("COUNT_BASED_LABEL", systemImage: "number")
                    }
                    if countBasedRetentionIsActive {
                        Stepper(onIncrement: countBasedRetentionIncrement,
                                onDecrement: countBasedRetentionDecrement) {
                            Text("KEEP_\(UInt(countBasedRetention))_MESSAGES")
                        }
                    }
                }
                Section(footer: Text("TIME_BASED_SECTION_FOOTER")) {
                    Picker(selection: $timeBasedRetention, label: Label("TIME_BASED_LABEL", systemIcon: .calendarBadgeClock)) {
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
                        Label("AUTO_READ_LABEL", systemImage: "hand.tap.fill")
                    }
                }
                Section(footer: Text("RETAIN_WIPED_OUTBOUND_MESSAGES_SECTION_FOOTER")) {
                    Toggle(isOn: $retainWipedOutboundMessages) {
                        Label("RETAIN_WIPED_OUTBOUND_MESSAGES_LABEL", systemImage: "trash.slash")
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
                        Label("READ_ONCE_LABEL", systemImage: "flame.fill")
                    }
                }
                Section(footer: Text("LIMITED_VISIBILITY_SECTION_FOOTER")) {
                    NavigationLink {
                        ExistenceOrVisibilityDurationView(timeInverval: $visibilityDuration)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Label("LIMITED_VISIBILITY_LABEL", systemIcon: .eyes)
                            Spacer()
                            Text(verbatim: TimeInterval.formatForExistenceOrVisibilityDuration(timeInterval: $visibilityDuration.wrappedValue, unitsStyle: .short))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section(footer: Text("LIMITED_EXISTENCE_SECTION_FOOTER")) {
                    NavigationLink {
                        ExistenceOrVisibilityDurationView(timeInverval: $existenceDuration)
                    } label: {
                        HStack(alignment: .firstTextBaseline) {
                            Label("LIMITED_EXISTENCE_SECTION_LABEL", systemIcon: .timer)
                            Spacer()
                            Text(verbatim: TimeInterval.formatForExistenceOrVisibilityDuration(timeInterval: $existenceDuration.wrappedValue, unitsStyle: .short))
                                .foregroundStyle(.secondary)
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
                                           alwaysShowNotificationsWhenMentioned: .constant(true),
                                           readOnce: .constant(false),
                                           attachLinkPreviewtoMessageSent: .constant(false),
                                           fetchMissingLinkPreviewFromMessagereceived: .constant(false),
                                           visibilityDuration: .constant(nil),
                                           existenceDuration: .constant(nil),
                                           countBasedRetentionIsActive: .constant(false),
                                           countBasedRetention: .constant(0),
                                           timeBasedRetention: .constant(.none),
                                           autoRead: .constant(false),
                                           retainWipedOutboundMessages: .constant(false),
                                           notificationSound: .constant(.none),
                                           performInteractionDonation: .constant(true),
                                           changed: .constant(false))
            DiscussionsDefaultSettingsView(doSendReadReceipt: .constant(true),
                                           alwaysShowNotificationsWhenMentioned: .constant(false),
                                           readOnce: .constant(false),
                                           attachLinkPreviewtoMessageSent: .constant(false),
                                           fetchMissingLinkPreviewFromMessagereceived: .constant(false),
                                           visibilityDuration: .constant(.init(hours: 1)),
                                           existenceDuration: .constant(.init(days: 1)),
                                           countBasedRetentionIsActive: .constant(true),
                                           countBasedRetention: .constant(50),
                                           timeBasedRetention: .constant(.sevenDays),
                                           autoRead: .constant(false),
                                           retainWipedOutboundMessages: .constant(false),
                                           notificationSound: .constant(.some(.bell)),
                                           performInteractionDonation: .constant(false),
                                           changed: .constant(false))
                .environment(\.locale, .init(identifier: "fr"))
        }
    }
    
}
