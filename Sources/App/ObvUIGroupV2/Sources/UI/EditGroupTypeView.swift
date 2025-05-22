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
protocol EditGroupTypeViewDataSource: AnyObject {
    func getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>)
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: UUID)
}


@MainActor
protocol EditGroupTypeViewActionsProtocol: AnyObject {
    func userWantsToLeaveGroupFlow(groupIdentifier: ObvGroupV2Identifier)
    func userWantsToUpdateGroupV2(groupIdentifier: ObvGroupV2Identifier, changeset: ObvGroupV2.Changeset) async throws // During edition
    func userChosedGroupTypeAndWantsToSelectAdmins(groupIdentifier: ObvGroupV2Identifier, selectedGroupType: ObvGroupType) // During edition
    func userChosedGroupTypeDuringGroupCreation(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, selectedGroupType: ObvGroupType)
}


struct EditGroupTypeViewModel {
    let initialGroupType: ObvGroupType?
}



struct EditGroupTypeView: View {
    
    let mode: Mode
    let dataSource: EditGroupTypeViewDataSource
    let actions: EditGroupTypeViewActionsProtocol
        
    enum Mode {
        case creation(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, preSelectedGroupType: ObvGroupType)
        case edition(groupIdentifier: ObvTypes.ObvGroupV2Identifier)
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
        case .creation(creationSessionUUID: _, ownedCryptoId: _, preSelectedGroupType: let preSelectedGroupType):
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
        case .edition(let groupIdentifier):
            Task {
                do {
                    let (streamUUID, stream) = try dataSource.getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: groupIdentifier)
                    if let previousStreamUUID = self.modelStreamUUID {
                        dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: previousStreamUUID)
                    }
                    self.modelStreamUUID = streamUUID
                    for await item in stream {
                        
                        switch item {
                            
                        case .groupNotFound:

                            // This typically happens if the group is disbanded by another user while the current user is displaying this view
                            
                            withAnimation {
                                self.model = nil
                            }
                            
                            actions.userWantsToLeaveGroupFlow(groupIdentifier: groupIdentifier)
                            
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
                                    case .none:
                                        self.selectedGroupTypeValue = nil
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
            dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: previousStreamUUID)
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
        case .creation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: let ownedCryptoId, preSelectedGroupType: _):
            actions.userChosedGroupTypeDuringGroupCreation(creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, selectedGroupType: selectedGroupType)
        case .edition(groupIdentifier: let groupIdentifier):
            guard let serializedGroupType = try? selectedGroupType.toSerializedGroupType() else { assertionFailure(); return }
            let changes: Set<ObvGroupV2.Change> = [.groupType(serializedGroupType: serializedGroupType)]
            isInterfaceDisabled = true
            hudCategory = .progress
            Task {
                do {
                    try await actions.userWantsToUpdateGroupV2(groupIdentifier: groupIdentifier, changeset: .init(changes: changes))
                    hudCategory = .checkmark
                    try? await Task.sleep(seconds: 1)
                    actions.userWantsToLeaveGroupFlow(groupIdentifier: groupIdentifier)
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
        case .creation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: let ownedCryptoId, preSelectedGroupType: _):
            actions.userChosedGroupTypeDuringGroupCreation(creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, selectedGroupType: selectedGroupType)
        case .edition(let groupIdentifier):
            actions.userChosedGroupTypeAndWantsToSelectAdmins(groupIdentifier: groupIdentifier, selectedGroupType: selectedGroupType)
        }
        
    }

    
    var body: some View {
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
                    return selectedGroupTypeValue == model.initialGroupType?.value
                case .managed:
                    return selectedGroupTypeValue == model.initialGroupType?.value
                case .readOnly:
                    return selectedGroupTypeValue == model.initialGroupType?.value
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
        guard let groupType = singleGroupV2MainViewModel.groupType else {
            self.init(initialGroupType: nil)
            return
        }
        self.init(initialGroupType: groupType)
    }
}












// MARK: - Previews

#if DEBUG

@MainActor
private final class DataSourceForPreviews: EditGroupTypeViewDataSource {
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(groupIdentifier: ObvGroupV2Identifier) throws -> (streamUUID: UUID, stream: AsyncStream<SingleGroupV2MainViewModelOrNotFound>) {
        let stream = AsyncStream(SingleGroupV2MainViewModelOrNotFound.self) { (continuation: AsyncStream<SingleGroupV2MainViewModelOrNotFound>.Continuation) in
            let model = PreviewsHelper.singleGroupV2MainViewModels[0]
            continuation.yield(.model(model: model))
        }
        return (UUID(), stream)
    }
    
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(streamUUID: UUID) {
        // Nothing to terminate in these previews
    }
    
}


@MainActor
private final class ActionsForPreviews: EditGroupTypeViewActionsProtocol {
    
    func userChosedGroupTypeDuringGroupCreation(creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, selectedGroupType: ObvAppTypes.ObvGroupType) {
        // Nothing to simulate
    }
    
    func userChosedGroupTypeAndWantsToSelectAdmins(groupIdentifier: ObvTypes.ObvGroupV2Identifier, selectedGroupType: ObvAppTypes.ObvGroupType) {
        // Nothing to simulate
    }
    
    func userWantsToUpdateGroupV2(groupIdentifier: ObvTypes.ObvGroupV2Identifier, changeset: ObvTypes.ObvGroupV2.Changeset) async throws {
        try await Task.sleep(seconds: 1)
    }
    
    func userWantsToLeaveGroupFlow(groupIdentifier: ObvGroupV2Identifier) {
        // Nothing to simulate
    }
    
}


@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()

@MainActor
private let actionsForPreviews = ActionsForPreviews()


#Preview("Creation") {
    EditGroupTypeView(mode: .creation(creationSessionUUID: UUID(), ownedCryptoId: PreviewsHelper.cryptoIds[0], preSelectedGroupType: .standard),
                      dataSource: dataSourceForPreviews,
                      actions: actionsForPreviews)
}

#Preview("Edition") {
    EditGroupTypeView(mode: .edition(groupIdentifier: PreviewsHelper.obvGroupV2Identifiers[0]),
                      dataSource: dataSourceForPreviews,
                      actions: actionsForPreviews)
}

#endif
