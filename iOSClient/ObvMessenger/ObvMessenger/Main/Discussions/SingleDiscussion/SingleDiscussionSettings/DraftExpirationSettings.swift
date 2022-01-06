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
import CoreData

@available(iOS 15, *)
extension DraftSettingsHostingViewController: UISheetPresentationControllerDelegate {

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        model.detentWasUpdated(with: sheetPresentationController.selectedDetentIdentifier)
    }

}

@available(iOS 13, *)
final class DraftSettingsHostingViewController: UIHostingController<DraftExpirationSettingsWrapperView>, DiscussionExpirationSettingsViewModelDelegate {

    fileprivate let model: DraftExpirationSettingsViewModel

    init?(draft: PersistedDraft) {
        assert(Thread.isMainThread)
        assert(draft.managedObjectContext == ObvStack.shared.viewContext)

        self.model = DraftExpirationSettingsViewModel(draftInViewContext: draft)

        let view = DraftExpirationSettingsWrapperView(
            model: model,
            draft: model.draftInViewContext,
            sharedConfiguration: model.sharedConfigurationInViewContext)

        super.init(rootView: view)
        model.delegate = self
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dismissAction() {
        self.dismiss(animated: true)
    }

}

@available(iOS 13, *)
final fileprivate class DraftExpirationSettingsViewModel: ObservableObject {

    weak var delegate: DiscussionExpirationSettingsViewModelDelegate?

    @Published private(set) var draftInViewContext: PersistedDraft
    @Published private(set) var sharedConfigurationInViewContext: PersistedDiscussionSharedConfiguration
    @Published var showExplanation: Bool = false

    init(draftInViewContext: PersistedDraft) {
        self.draftInViewContext = draftInViewContext
        self.sharedConfigurationInViewContext = draftInViewContext.discussion.sharedConfiguration
    }

    func updateConfiguration(with value: PersistedDiscussionSharedConfigurationValue?) {
        NewSingleDiscussionNotification.userWantsToUpdateDraftExpiration(draftObjectID: draftInViewContext.typedObjectID, value: value).postOnDispatchQueue()
    }

    @available(iOS 15, *)
    func detentWasUpdated(with detent: UISheetPresentationController.Detent.Identifier?) {
        withAnimation { self.showExplanation = detent == .large }
    }

}


@available(iOS 13, *)
fileprivate extension PersistedDraft {

    func getReadOnce(model: DraftExpirationSettingsViewModel) -> Bool {
        readOnce || model.sharedConfigurationInViewContext.readOnce
    }

    func getVisibilityDurationOption(model: DraftExpirationSettingsViewModel) -> DurationOption {
        if let visibilityDuration = visibilityDuration {
            return PersistedDiscussionSharedConfiguration.toDurationOption(visibilityDuration) { setVisibilityDurationOption(model: model, to: $0) }
        }
        return PersistedDiscussionSharedConfiguration.toDurationOption(model.sharedConfigurationInViewContext.visibilityDuration) { _ in }
    }

    func setVisibilityDurationOption(model: DraftExpirationSettingsViewModel, to value: DurationOption) {
        guard value.le(model.sharedConfigurationInViewContext.visibilityDuration) else { return }
        model.updateConfiguration(with: .visibilityDuration(visibilityDuration: value.timeInterval))
    }

    func getExistenceDurationOption(model: DraftExpirationSettingsViewModel) -> DurationOption {
        if let existenceDuration = existenceDuration {
            return PersistedDiscussionSharedConfiguration.toDurationOption(existenceDuration) { setExistenceDurationOption(model: model, to: $0) }
        }
        return PersistedDiscussionSharedConfiguration.toDurationOption(model.sharedConfigurationInViewContext.existenceDuration) { _ in }
    }

    func setExistenceDurationOption(model: DraftExpirationSettingsViewModel, to value: DurationOption) {
        guard value.le(model.sharedConfigurationInViewContext.existenceDuration) else { return }
        model.updateConfiguration(with: .existenceDuration(existenceDuration: value.timeInterval))
    }
}

@available(iOS 13, *)
struct DraftExpirationSettingsWrapperView: View {

    fileprivate var model: DraftExpirationSettingsViewModel
    @ObservedObject fileprivate var draft: PersistedDraft
    @ObservedObject fileprivate var sharedConfiguration: PersistedDiscussionSharedConfiguration

    var body: some View {
        DraftExpirationSettingsView(
            discussionReadOnce: sharedConfiguration.readOnce,
            discussionExistenceDuration: sharedConfiguration.existenceDuration,
            discussionVisibilityDuration: sharedConfiguration.visibilityDuration,

            readOnce: ValueWithBinding(draft, draft.getReadOnce(model: model)) { value, _ in
                model.updateConfiguration(with: .readOnce(readOnce: value))
            },

            visibilityDurationOption: ValueWithBinding(draft, draft.getVisibilityDurationOption(model: model)) { value, _ in
                draft.setVisibilityDurationOption(model: model, to: value)
            },
            maximumVisiblityDuration: sharedConfiguration.visibilityDuration,

            existenceDurationOption: ValueWithBinding(draft, draft.getExistenceDurationOption(model: model)) { value, _ in
                draft.setExistenceDurationOption(model: model, to: value)
            },
            maximumExistenceDuration: sharedConfiguration.existenceDuration,
            reset: {
                model.updateConfiguration(with: .none)
            },
            dismiss: {
                model.delegate?.dismissAction()
            })
    }

}

@available(iOS 13, *)
fileprivate struct DefaultDiscussionSettingsView: View {

    let readOnce: Bool
    let visibilityDuration: TimeInterval?
    let existenceDuration: TimeInterval?

    private let durationFormatter = DurationFormatter()

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            if readOnce {
                Group {
                    Image(systemIcon: .flameFill)
                    Text("READ_ONCE_LABEL")
                }.foregroundColor(.red)
                Spacer()
            }
            if let visibilityDuration = visibilityDuration {
                Group {
                    Image(systemIcon: .eyes)
                    Text(durationFormatter.string(from: visibilityDuration) ?? "")
                }.foregroundColor(.gray)
                Spacer()
            }
            if let existenceDuration = existenceDuration {
                Group {
                    Image(systemIcon: .timer)
                    Text(durationFormatter.string(from: existenceDuration) ?? "")
                }.foregroundColor(.orange)
                Spacer()
            }
            if !readOnce && existenceDuration == nil && visibilityDuration == nil {
                Text("NON_EPHEMERAL_MESSAGES_LABEL")
                Spacer()
            }
        }
    }
}

@available(iOS 13, *)
fileprivate struct DraftExpirationSettingsView: View {

    let discussionReadOnce: Bool
    let discussionExistenceDuration: TimeInterval?
    let discussionVisibilityDuration: TimeInterval?

    let readOnce: ValueWithBinding<PersistedDraft, Bool>

    let visibilityDurationOption: ValueWithBinding<PersistedDraft, DurationOption>
    let maximumVisiblityDuration: TimeInterval?

    let existenceDurationOption: ValueWithBinding<PersistedDraft, DurationOption>
    let maximumExistenceDuration: TimeInterval?

    let reset: () -> Void
    let dismiss: () -> Void

    func filterDuration(maximum: TimeInterval?) -> [DurationOption] {
        return DurationOption.allCases.filter { $0.le(maximum) }
    }

    private var disableReset: Bool {
        readOnce.value == false &&
        visibilityDurationOption.value == .none &&
        existenceDurationOption.value == .none
    }

    var resetButton: some View {
        OlvidButton(style: .standard,
                    title: Text(CommonString.Word.Reset), systemIcon: nil) {
            guard !disableReset else { return }
            reset()
        }.disabled(disableReset)
    }

    var okButton: OlvidButton {
        OlvidButton(style: .blue,
                    title: Text(CommonString.Word.Ok),
                    systemIcon: nil,
                    action: { dismiss() })
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("DEFAULT_DISCUSSION_SETTINGS"),
                        footer: Text("DRAFT_EXPIRATION_EXPLANATION")) {
                    DefaultDiscussionSettingsView(
                        readOnce: discussionReadOnce,
                        visibilityDuration: discussionVisibilityDuration,
                        existenceDuration: discussionExistenceDuration)
                }

                Section {
                    Toggle(isOn: readOnce.binding) {
                        ObvLabel("READ_ONCE_LABEL", systemImage: "flame.fill")
                    }.disabled(discussionReadOnce)

                    Picker(selection: visibilityDurationOption.binding, label: ObvLabel("LIMITED_VISIBILITY_LABEL", systemImage: "eyes")) {
                        ForEach(filterDuration(maximum: maximumVisiblityDuration)) { duration in
                            Text(duration.description).tag(duration)
                        }
                    }

                    Picker(selection: existenceDurationOption.binding, label: ObvLabel("LIMITED_EXISTENCE_SECTION_LABEL", systemImage: "timer")) {
                        ForEach(filterDuration(maximum: maximumExistenceDuration)) { duration in
                            Text(duration.description).tag(duration)
                        }
                    }
                } footer: {
                    VStack {
                        Spacer()
                        HStack {
                            resetButton
                            okButton
                        }
                    }
                }
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle()) // Prevents split on iPad
    }
}

@available(iOS 13, *)
struct DraftExpirationSettingsView_Previews: PreviewProvider {

    static var previews: some View {
        DraftExpirationSettingsView(
            discussionReadOnce: false,
            discussionExistenceDuration: nil,
            discussionVisibilityDuration: DurationOption.sixHour.timeInterval,
            readOnce: ValueWithBinding(constant: false),
            visibilityDurationOption: ValueWithBinding(constant: .none),
            maximumVisiblityDuration: DurationOption.oneHour.timeInterval,
            existenceDurationOption: ValueWithBinding(constant: .oneHour),
            maximumExistenceDuration: nil,
            reset: {},
            dismiss: {})
    }

}
