/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvTypes
import ObvAppTypes
import ObvDesignSystem


@MainActor
public protocol EditGroupTypeViewDataSource {
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier) async throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>)
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupTypeView, streamUUID: UUID)
}


@MainActor
public protocol EditGroupTypeViewActionsForEdition: AnyObject {
    func userWantsToUpdateGroupV2(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws // During edition
}


@MainActor
public protocol EditGroupTypeViewNavigationDuringCreation {
    func userChosedGroupTypeDuringGroupCreation(_ view: EditGroupTypeView, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, selectedGroupType: ObvGroupType)
}


@MainActor
public protocol EditGroupTypeViewNavigationDuringEdition {
    func userChosedGroupTypeAndWantsToSelectAdmins(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier, selectedGroupType: ObvGroupType)
    func userWantsToLeaveGroupFlowAsGroupWasDisbanded(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier)
    func editGroupTypeViewShouldBeDismissed(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier)
}

struct EditGroupTypeViewModel {
    let initialGroupType: ObvGroupType
}



public struct EditGroupTypeView: View {
    
    let mode: Mode
    let dataSource: EditGroupTypeViewDataSource
        
    enum Mode {
        case creation(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, preSelectedGroupType: ObvGroupType, navigation: EditGroupTypeViewNavigationDuringCreation)
        case edition(groupIdentifier: ObvTypes.ObvGroupV2Identifier, navigation: EditGroupTypeViewNavigationDuringEdition, actions: EditGroupTypeViewActionsForEdition)
    }

    @State private var model: EditGroupTypeViewModel? // Set only once
    @State private var modelStreamUUID: UUID?
    
    @State private var selectedGroupTypeValue: GroupTypeValue? = nil
    @State private var isReadOnly: Bool = false
    @State private var remoteDeleteAnythingPolicy: ObvGroupType.RemoteDeleteAnythingPolicy = .nobody
    
    @State private var isInterfaceDisabled: Bool = false
    @State private var hudCategory: HUDView.Category? = nil

    private func onAppear() {
        switch mode {
        case .creation(creationSessionUUID: _, ownedCryptoId: _, preSelectedGroupType: let preSelectedGroupType, navigation: _):
            // We don't need any stream during a group creation.
            // Instead, if the selectedGroupTypeValue is nil, we set it to the preselected value
            if self.selectedGroupTypeValue == nil {
                switch preSelectedGroupType {
                case .standard:
                    self.selectedGroupTypeValue = .standard
                case .managed:
                    self.selectedGroupTypeValue = .managed
                case .readOnly:
                    self.selectedGroupTypeValue = .readOnly
                case .advanced(isReadOnly: let isReadOnly, remoteDeleteAnythingPolicy: let remoteDeleteAnythingPolicy):
                    self.selectedGroupTypeValue = .advanced
                    self.isReadOnly = isReadOnly
                    self.remoteDeleteAnythingPolicy = remoteDeleteAnythingPolicy
                }
            }
        case .edition(groupIdentifier: let groupIdentifier, navigation: let navigation, actions: _):
            Task {
                do {
                    let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfSingleGroupV2MainViewModel(self, groupIdentifier: groupIdentifier)
                    if let previousStreamUUID = self.modelStreamUUID {
                        dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(self, streamUUID: previousStreamUUID)
                    }
                    self.modelStreamUUID = streamUUID
                    for await item in stream {
                        
                        switch item {
                            
                        case .groupNotFound:

                            // This typically happens if the group is disbanded by another user while the current user is displaying this view
                            
                            withAnimation {
                                self.model = nil
                            }
                            
                            navigation.userWantsToLeaveGroupFlowAsGroupWasDisbanded(self, groupIdentifier: groupIdentifier)
                            
                        case .model(let model):
                            
                            // We only set the model once
                            guard self.model == nil else { continue }
                            
                            withAnimation {
                                self.model = .init(singleGroupV2MainViewModel: model)
                                if let currentModel = self.model {
                                    switch currentModel.initialGroupType {
                                    case .standard:
                                        self.selectedGroupTypeValue = .standard
                                    case .managed:
                                        self.selectedGroupTypeValue = .managed
                                    case .readOnly:
                                        self.selectedGroupTypeValue = .readOnly
                                    case .advanced(let isReadOnly, let remoteDeleteAnythingPolicy):
                                        self.selectedGroupTypeValue = .advanced
                                        self.isReadOnly = isReadOnly
                                        self.remoteDeleteAnythingPolicy = remoteDeleteAnythingPolicy
                                    }
                                }
                            }
                            
                        }
                        
                    }
                } catch {
                    // Do nothing for now
                }
            }
        }
    }
    
    
    private func onDisappear() {
        if let previousStreamUUID = self.modelStreamUUID {
            dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(self, streamUUID: previousStreamUUID)
            self.modelStreamUUID = nil
        }
    }
    
    
    private var selectedGroupType: ObvGroupType? {
        let selectedGroupType: ObvGroupType
        switch selectedGroupTypeValue {
        case .standard:
            selectedGroupType = .standard
        case .managed:
            selectedGroupType = .managed
        case .readOnly:
            selectedGroupType = .readOnly
        case .advanced:
            selectedGroupType = .advanced(isReadOnly: self.isReadOnly,
                                          remoteDeleteAnythingPolicy: self.remoteDeleteAnythingPolicy)
        case .none:
            return nil
        }
        return selectedGroupType
    }
    
    
    func userTappedPublishGroupButton() {
        
        guard let selectedGroupType else { assertionFailure(); return }
        guard selectedGroupTypeValue == .standard else { assertionFailure(); return }
        
        switch mode {
        case .creation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: let ownedCryptoId, preSelectedGroupType: _, navigation: let navigation):
            navigation.userChosedGroupTypeDuringGroupCreation(self, creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, selectedGroupType: selectedGroupType)
        case .edition(groupIdentifier: let groupIdentifier, navigation: let navigation, actions: let actions):
            guard let serializedGroupType = try? selectedGroupType.toSerializedGroupType() else { assertionFailure(); return }
            let changes: Set<ObvGroupV2.Change> = [.groupType(serializedGroupType: serializedGroupType)]
            isInterfaceDisabled = true
            hudCategory = .progress
            Task {
                do {
                    try await actions.userWantsToUpdateGroupV2(self, groupIdentifier: groupIdentifier, changeset: .init(changes: changes))
                    hudCategory = .checkmark
                    try? await Task.sleep(seconds: 1)
                    navigation.editGroupTypeViewShouldBeDismissed(self, groupIdentifier: groupIdentifier)
                } catch {
                    assertionFailure()
                    hudCategory = .xmark
                    isInterfaceDisabled = false
                }
            }
        }
        
    }
    
    
    func userTappedChooseAdminsButton() {
        guard let selectedGroupType else { assertionFailure(); return }
        guard selectedGroupType != .standard else { assertionFailure(); return }
        
        switch mode {
        case .creation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: let ownedCryptoId, preSelectedGroupType: _, navigation: let navigation):
            navigation.userChosedGroupTypeDuringGroupCreation(self, creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, selectedGroupType: selectedGroupType)
        case .edition(groupIdentifier: let groupIdentifier, navigation: let navigation, actions: _):
            navigation.userChosedGroupTypeAndWantsToSelectAdmins(self, groupIdentifier: groupIdentifier, selectedGroupType: selectedGroupType)
        }
        
    }

    
    public var body: some View {
        ZStack {
            
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            
            InternalView(mode: mode,
                         model: model,
                         selectedGroupTypeValue: $selectedGroupTypeValue,
                         isReadOnly: $isReadOnly,
                         remoteDeleteAnythingPolicy: $remoteDeleteAnythingPolicy,
                         userTappedPublishGroupButton: userTappedPublishGroupButton,
                         userTappedChooseAdminsButton: userTappedChooseAdminsButton)
                .onDisappear(perform: onDisappear)
                .onAppear(perform: onAppear)
                .disabled(isInterfaceDisabled)
                .navigationTitle(String(localizedInThisBundle: "GROUP_TYPE"))
            
            if let hudCategory = self.hudCategory {
                HUDView(category: hudCategory)
            }

        }

    }
    
    
    private struct InternalView: View {
        
        let mode: Mode
        let model: EditGroupTypeViewModel?

        @Binding var selectedGroupTypeValue: GroupTypeValue? // Must be a binding
        @Binding var isReadOnly: Bool // Must be a binding
        @Binding var remoteDeleteAnythingPolicy: ObvGroupType.RemoteDeleteAnythingPolicy // Must be a binding

        let userTappedPublishGroupButton: () -> Void
        let userTappedChooseAdminsButton: () -> Void
                
        private var disableButton: Bool {
            switch mode {
            case .creation:
                return selectedGroupTypeValue == nil
            case .edition:
                guard let selectedGroupTypeValue, let model else { return true }
                switch selectedGroupTypeValue {
                case .standard:
                    return selectedGroupTypeValue == model.initialGroupType.value
                case .managed:
                    return selectedGroupTypeValue == model.initialGroupType.value
                case .readOnly:
                    return selectedGroupTypeValue == model.initialGroupType.value
                case .advanced:
                    return false // Since we want to allow navigation to the screen allowing to choose advanced parameters
                }
            }
        }
        
        private var buttonTitle: String {
            switch mode {
            case .creation:
                switch buttonType {
                case .publishGroupType:
                    return String(localizedInThisBundle: "CONFIRM")
                case .editAdmins:
                    return String(localizedInThisBundle: "CHOOSE_ADMINS")
                }
            case .edition:
                switch buttonType {
                case .publishGroupType:
                    return String(localizedInThisBundle: "PUBLISH_NEW_GROUP_TYPE")
                case .editAdmins:
                    return String(localizedInThisBundle: "EDIT_ADMINS")
                }
            }
        }
        
        
        private enum ButtonType {
            case publishGroupType
            case editAdmins
        }
        
        
        private var buttonType: ButtonType {
            switch selectedGroupTypeValue {
            case .standard, nil:
                return .publishGroupType
            case .advanced, .managed, .readOnly:
                return .editAdmins
            }
        }
        
        
        private func buttonTapped() {
            switch buttonType {
            case .publishGroupType:
                self.userTappedPublishGroupButton()
            case .editAdmins:
                self.userTappedChooseAdminsButton()
            }
        }

        private var internalViewCanBeShown: Bool {
            switch mode {
            case .creation:
                return selectedGroupTypeValue != nil // Automatically set onAppear
            case .edition:
                return model != nil
            }
        }

        var body: some View {
            if internalViewCanBeShown {

                VStack {
                    
                    ScrollView {
                        
                        VStack(alignment: .leading, spacing: 0) {
                            
                            Text("GROUP_TYPE_TITLE")
                                .textCase(.uppercase)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .padding(.bottom, 4)
                            
                            GroupTypeSelectorView(selectedGroupTypeValue: $selectedGroupTypeValue,
                                                  isReadOnly: $isReadOnly,
                                                  remoteDeleteAnythingPolicy: $remoteDeleteAnythingPolicy)
                            
                            Spacer()
                                                        
                        }
                        .padding()
                        
                    }
                    
                    Button(action: buttonTapped) {
                        HStack {
                            Spacer(minLength: 0)
                            Text(buttonTitle)
                                .padding(.vertical, 8)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(disableButton)
                    .padding()
                    
                }
                
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ProgressView()
                }
            }
        }
    }
        
}


// MARK: - EditGroupTypeViewModel from SingleGroupV2MainViewModel

extension EditGroupTypeViewModel {
    init(singleGroupV2MainViewModel: SingleGroupV2MainViewModel) {
        self.init(initialGroupType: singleGroupV2MainViewModel.groupType)
    }
}












// MARK: - Previews

#if DEBUG

@MainActor
private final class DataSourceForPreviews: EditGroupTypeViewDataSource {
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        let stream = AsyncStream(SingleGroupV2MainViewModelOrNotFound.self) { (continuation: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation) in
            let model = PreviewsHelper.singleGroupV2MainViewModels[0]
            continuation.yield(.model(model: model))
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupTypeView, streamUUID: UUID) {
        // Nothing to terminate in these previews
    }
    
}


@MainActor
private final class ActionsForPreviews: EditGroupTypeViewActionsForEdition {
            
    func userWantsToUpdateGroupV2(_ view: EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        try await Task.sleep(seconds: 1)
    }
        
}


@MainActor
private final class NavigationForPreviews {}

extension NavigationForPreviews: EditGroupTypeViewNavigationDuringEdition {
    func userChosedGroupTypeAndWantsToSelectAdmins(_ view: EditGroupTypeView, groupIdentifier: ObvTypes.ObvGroupV2Identifier, selectedGroupType: ObvAppTypes.ObvGroupType) {}
    func userWantsToLeaveGroupFlowAsGroupWasDisbanded(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier) {}
    func editGroupTypeViewShouldBeDismissed(_ view: EditGroupTypeView, groupIdentifier: ObvGroupV2Identifier) {}
}
 
extension NavigationForPreviews: EditGroupTypeViewNavigationDuringCreation {
    func userChosedGroupTypeDuringGroupCreation(_ view: EditGroupTypeView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, selectedGroupType: ObvAppTypes.ObvGroupType) {}
}

@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let navigationForPreviews = NavigationForPreviews()

#Preview("Creation") {
    EditGroupTypeView(mode: .creation(creationSessionUUID: UUID(), ownedCryptoId: PreviewsHelper.cryptoIds[0], preSelectedGroupType: .standard, navigation: navigationForPreviews),
                      dataSource: dataSourceForPreviews)
}

#Preview("Edition") {
    EditGroupTypeView(mode: .edition(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0], navigation: navigationForPreviews, actions: actionsForPreviews),
                      dataSource: dataSourceForPreviews)
}

#endif
