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
import CoreData
import ObvUICoreData
import ObvSettings
import ObvUI


protocol DraftSettingsHostingViewControllerDelegate: AnyObject {
    func userWantsToUpdateDraftExpiration(_ draftSettingsHostingViewController: DraftSettingsHostingViewController, draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws
}


final class DraftSettingsHostingViewController: UIHostingController<DraftExpirationSettingsWrapperView> {

    fileprivate let model: DraftExpirationSettingsViewModel

    private weak var delegate: DraftSettingsHostingViewControllerDelegate?
    
    init?(draft: PersistedDraft, delegate: DraftSettingsHostingViewControllerDelegate) {
        assert(Thread.isMainThread)
        assert(draft.managedObjectContext == ObvStack.shared.viewContext)

        self.model = DraftExpirationSettingsViewModel(draftInViewContext: draft)
        self.delegate = delegate

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

}


extension DraftSettingsHostingViewController: DraftExpirationSettingsViewModelViewModelDelegate {

    func dismissAction() {
        self.dismiss(animated: true)
    }

    func userWantsToUpdateDraftExpiration(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws {
        guard let delegate else { assertionFailure(); throw ObvError.delegateIsNil }
        try await delegate.userWantsToUpdateDraftExpiration(self, draftObjectID: draftObjectID, value: value)
    }
    
}


extension DraftSettingsHostingViewController {
    enum ObvError: Error {
        case delegateIsNil
    }
}



extension DraftSettingsHostingViewController: UISheetPresentationControllerDelegate {

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheetPresentationController: UISheetPresentationController) {
        model.detentWasUpdated(with: sheetPresentationController.selectedDetentIdentifier)
    }

}

protocol DraftExpirationSettingsViewModelViewModelDelegate: AnyObject {
    func dismissAction()
    func userWantsToUpdateDraftExpiration(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, value: PersistedDiscussionSharedConfigurationValue?) async throws
}


final fileprivate class DraftExpirationSettingsViewModel: ObservableObject {

    weak var delegate: DraftExpirationSettingsViewModelViewModelDelegate?

    @Published private(set) var draftInViewContext: PersistedDraft
    @Published private(set) var sharedConfigurationInViewContext: PersistedDiscussionSharedConfiguration
    @Published var showExplanation: Bool = false

    init(draftInViewContext: PersistedDraft) {
        self.draftInViewContext = draftInViewContext
        self.sharedConfigurationInViewContext = draftInViewContext.discussion.sharedConfiguration
    }

    func updateConfiguration(with value: PersistedDiscussionSharedConfigurationValue?) {
        guard let delegate else { assertionFailure(); return }
        let draftObjectID = draftInViewContext.typedObjectID
        Task {
            try? await delegate.userWantsToUpdateDraftExpiration(draftObjectID: draftObjectID, value: value)
        }
    }

    func detentWasUpdated(with detent: UISheetPresentationController.Detent.Identifier?) {
        withAnimation { self.showExplanation = detent == .large }
    }

}



fileprivate extension PersistedDraft {

    func getReadOnce(model: DraftExpirationSettingsViewModel) -> Bool {
        readOnce || model.sharedConfigurationInViewContext.readOnce
    }

    func getVisibilityDurationOption(model: DraftExpirationSettingsViewModel) -> TimeInterval? {
        visibilityDuration ?? model.sharedConfigurationInViewContext.visibilityDuration
    }

    func setVisibilityDurationOption(model: DraftExpirationSettingsViewModel, to value: TimeInterval?) {
        switch (value, model.sharedConfigurationInViewContext.visibilityDuration) {
        case let (.some(requestedDuration), .some(sharedDuration)):
            guard requestedDuration < sharedDuration else { return }
            model.updateConfiguration(with: .visibilityDuration(visibilityDuration: requestedDuration))
        case (.none, .none):
            model.updateConfiguration(with: .visibilityDuration(visibilityDuration: nil))
        case let (.some(requestedDuration), .none):
            model.updateConfiguration(with: .visibilityDuration(visibilityDuration: requestedDuration))
        case (.none, .some):
            return
        }
    }

    func getExistenceDurationOption(model: DraftExpirationSettingsViewModel) -> TimeInterval? {
        existenceDuration ?? model.sharedConfigurationInViewContext.existenceDuration
    }

    func setExistenceDurationOption(model: DraftExpirationSettingsViewModel, to value: TimeInterval?) {
        switch (value, model.sharedConfigurationInViewContext.existenceDuration) {
        case let (.some(requestedDuration), .some(sharedDuration)):
            guard requestedDuration < sharedDuration else { return }
            model.updateConfiguration(with: .existenceDuration(existenceDuration: requestedDuration))
        case (.none, .none):
            model.updateConfiguration(with: .existenceDuration(existenceDuration: nil))
        case let (.some(requestedDuration), .none):
            model.updateConfiguration(with: .existenceDuration(existenceDuration: requestedDuration))
        case (.none, .some):
            return
        }
    }
    
}


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


fileprivate struct DraftExpirationSettingsView: View {

    let discussionReadOnce: Bool
    let discussionExistenceDuration: TimeInterval?
    let discussionVisibilityDuration: TimeInterval?

    let readOnce: ValueWithBinding<PersistedDraft, Bool>

    let visibilityDurationOption: ValueWithBinding<PersistedDraft, TimeInterval?>
    let maximumVisiblityDuration: TimeInterval?

    let existenceDurationOption: ValueWithBinding<PersistedDraft, TimeInterval?>
    let maximumExistenceDuration: TimeInterval?

    let reset: () -> Void
    let dismiss: () -> Void

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
                        Label("READ_ONCE_LABEL", systemIcon: .flameFill)
                    }.disabled(discussionReadOnce)
                    ExistenceOrVisibilityDurationPicker(timeInverval: visibilityDurationOption.binding, maxTimeInterval: maximumVisiblityDuration) {
                        Label("LIMITED_VISIBILITY_LABEL", systemIcon: .eyes)
                    }
                    ExistenceOrVisibilityDurationPicker(timeInverval: existenceDurationOption.binding, maxTimeInterval: maximumExistenceDuration) {
                        Label("LIMITED_EXISTENCE_SECTION_LABEL", systemIcon: .timer)
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


struct DraftExpirationSettingsView_Previews: PreviewProvider {

    static var previews: some View {
        DraftExpirationSettingsView(
            discussionReadOnce: false,
            discussionExistenceDuration: nil,
            discussionVisibilityDuration: .init(hours: 6),
            readOnce: ValueWithBinding(constant: false),
            visibilityDurationOption: ValueWithBinding(constant: .none),
            maximumVisiblityDuration: .init(hours: 1),
            existenceDurationOption: ValueWithBinding(constant: .init(hours: 1)),
            maximumExistenceDuration: nil,
            reset: {},
            dismiss: {})
    }

}
