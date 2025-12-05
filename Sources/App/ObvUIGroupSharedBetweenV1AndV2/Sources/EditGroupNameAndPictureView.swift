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
import ObvCircleAndTitlesView
import ObvAppTypes



@MainActor
public protocol EditGroupNameAndPictureViewDataSource {
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupNameAndPictureView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) async throws -> (streamUUID: UUID, stream: AsyncStream<EditGroupNameAndPictureView.ModelOrNotFound>)
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupNameAndPictureView, streamUUID: UUID)
}


@MainActor
public protocol EditGroupNameAndPictureViewActionsProtocol {
    func userWantsObtainAvatar(_ view: EditGroupNameAndPictureView.InternalView, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    func userWantsToSaveImageToTempFile(_ view: EditGroupNameAndPictureView.InternalView, image: UIImage) async throws -> URL
}

@MainActor
public protocol EditGroupNameAndPictureViewActionsForEdition {
    func userWantsToUpdateGroupNameAndPicture(_ view: EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvGroupIdentifier, changes: Set<EditGroupNameAndPictureView.Change>) async throws
}

@MainActor
public protocol EditGroupNameAndPictureViewActionsForCreation {
    func userWantsToPublishCreatedGroupWithDetails(_ view: EditGroupNameAndPictureView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, groupDetails: ObvGroupDetails) async throws
}

@MainActor
public protocol EditGroupNameAndPictureViewNavigationDuringCreation {
    func groupWasSuccessfullyCreated(_ view: EditGroupNameAndPictureView.InternalView, ownedCryptoId: ObvCryptoId)
}

@MainActor
public protocol EditGroupNameAndPictureViewNavigationDuringEdition {
    func userWantsToLeaveGroupFlow(_ view: EditGroupNameAndPictureView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) // Only called during edition
    func groupDetailsWereSuccessfullyUpdated(_ view: EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvGroupIdentifier)
}

public struct EditGroupNameAndPictureView: View {
    
    let mode: Mode
    let actions: EditGroupNameAndPictureViewActionsProtocol
    
    public init(mode: Mode, actions: EditGroupNameAndPictureViewActionsProtocol) {
        self.mode = mode
        self.actions = actions
    }

    
    public enum Change: Hashable, Sendable {
        case groupDetails(groupCoreDetails: ObvGroupCoreDetails)
        case groupPhoto(photoURL: URL?)
    }
    
    public enum Mode {
        case creation(creationSessionUUID: UUID, ownedCryptoId: ObvCryptoId, preSelectedPhoto: UIImage?, preSelectedGroupName: String?, preSelectedGroupDescription: String?, navigation: EditGroupNameAndPictureViewNavigationDuringCreation, actions: EditGroupNameAndPictureViewActionsForCreation)
        case edition(groupIdentifier: ObvAppTypes.ObvGroupIdentifier, navigation: EditGroupNameAndPictureViewNavigationDuringEdition, dataSource: EditGroupNameAndPictureViewDataSource, avatarViewDataSource: ObvAvatarViewDataSource, actions: EditGroupNameAndPictureViewActionsForEdition)
    }
    
    public enum ModelOrNotFound: Sendable, Equatable {
        case model(Model)
        case groupNotFound
    }
    
    public struct Model: Sendable, Equatable {
        let isKeycloakManaged: Bool
        let circleColors: InitialCircleView.Model.Colors
        let trustedName: String
        let publishedDetailsForValidation: PublishedDetailsValidationViewModel?
        let trustedDescription: String?
        let trustedPhotoURL: URL?
        
        public init(isKeycloakManaged: Bool, circleColors: InitialCircleView.Model.Colors, trustedName: String, publishedDetailsForValidation: PublishedDetailsValidationViewModel?, trustedDescription: String?, trustedPhotoURL: URL?) {
            self.isKeycloakManaged = isKeycloakManaged
            self.circleColors = circleColors
            self.trustedName = trustedName
            self.publishedDetailsForValidation = publishedDetailsForValidation
            self.trustedDescription = trustedDescription
            self.trustedPhotoURL = trustedPhotoURL
        }
    }

    @State private var groupModel: Model?
    @State private var groupModelStreamUUID: UUID?

    @State private var photo: UIImage? // During edition: If there is a published photo, we show it. Otherwise, we show the trusted photo if there is one.

    @State private var photoChosenDuringEdition: UIImage?
    @State private var userWantsToRemoveCurrentlyPublishedPhoto: Bool = false
    
    // The first time the group model is set, we reset these values with the group published details (or, if there aren't any, with the trusted details).
    @State private var groupName: String = ""
    @State private var groupDescription: String = ""
    @State private var groupModelWasUsedToSetNameAndDescription: Bool = false
    
    @State private var isInterfaceDisabled: Bool = false
    @State private var hudCategory: HUDView.Category? = nil

    @State private var preSelectedValuesSetDuringCreation: Bool = false
    
    private func onAppear() {
        switch mode {
        case .creation(creationSessionUUID: _, ownedCryptoId: _, preSelectedPhoto: let preSelectedPhoto, preSelectedGroupName: let preSelectedGroupName, preSelectedGroupDescription: let preSelectedGroupDescription, navigation: _, actions: _):
            // No stream needed during group creation.
            // Instead, we set the pre-selected photo, name and description if this was not already done
            if !preSelectedValuesSetDuringCreation {
                preSelectedValuesSetDuringCreation = true
                self.photoChosenDuringEdition = preSelectedPhoto
                self.groupName = preSelectedGroupName ?? ""
                self.groupDescription = preSelectedGroupDescription ?? ""
            }
        case .edition(groupIdentifier: let groupIdentifier, navigation: let navigation, dataSource: let dataSource, avatarViewDataSource: _, actions: _):
            Task {
                do {
                    let (streamUUID, stream) = try await dataSource.getAsyncSequenceOfSingleGroupV2MainViewModel(self, groupIdentifier: groupIdentifier)
                    if let previousStreamUUID = self.groupModelStreamUUID {
                        dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(self, streamUUID: previousStreamUUID)
                    }
                    self.groupModelStreamUUID = streamUUID
                    for await item in stream {
                        
                        switch item {
                            
                        case .groupNotFound:

                            // This typically happens if userIsLeavingGroup or userIsDisbandingGroup is true,
                            // or when the group is disbanded by another user while the current user is displaying this view
                            
                            withAnimation {
                                self.groupModel = nil
                                self.photo = nil
                            }
                            
                            navigation.userWantsToLeaveGroupFlow(self, groupIdentifier: groupIdentifier)
                            
                        case .model(let model):
                            let previousPhotoURL = self.groupModel?.publishedDetailsForValidation?.publishedPhotoURL ?? self.groupModel?.trustedPhotoURL
                            
                            withAnimation {
                                if !groupModelWasUsedToSetNameAndDescription {
                                    groupModelWasUsedToSetNameAndDescription = true
                                    self.groupName = getInitialGroupNameValueFrom(model)
                                    self.groupDescription = getInitialGroupDescriptionValueFrom(model)
                                }
                                self.groupModel = model
                            }
                            
                            let newPhotoURL = self.groupModel?.publishedDetailsForValidation?.publishedPhotoURL ?? self.groupModel?.trustedPhotoURL
                            
                            try? await fetchAndSetPhoto(previousPhotoURL: previousPhotoURL, newPhotoURL: newPhotoURL)
                        }
                        
                    }
                } catch {
                    // Do nothing for now
                }
            }
        }
    }
    
    private func onDisappear() {
        switch mode {
        case .creation:
            return
        case .edition(groupIdentifier: _, navigation: _, dataSource: let dataSource, avatarViewDataSource: _, actions: _):
            if let previousStreamUUID = self.groupModelStreamUUID {
                dataSource.finishAsyncSequenceOfSingleGroupV2MainViewModel(self, streamUUID: previousStreamUUID)
                self.groupModelStreamUUID = nil
            }
        }
    }

    private func getInitialGroupNameValueFrom(_ model: Model) -> String {
        model.publishedDetailsForValidation?.publishedName ?? model.trustedName
    }

    private func getInitialGroupDescriptionValueFrom(_ model: Model) -> String {
        model.publishedDetailsForValidation?.publishedDescription ?? model.trustedDescription ?? ""
    }
    
    private func fetchAndSetPhoto(previousPhotoURL: URL?, newPhotoURL: URL?) async throws {
        switch mode {
        case .creation:
            assertionFailure("Not expected to be called during group creation")
        case .edition(groupIdentifier: _, navigation: _, dataSource: _, avatarViewDataSource: let avatarViewDataSource, actions: _):
            guard previousPhotoURL != newPhotoURL else { return }
            withAnimation {
                self.photo = nil
            }
            guard let newPhotoURL else { return }
            let newPhoto = try await avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: newPhotoURL, avatarSize: .xLarge)
            if self.groupModel?.publishedDetailsForValidation?.publishedPhotoURL ?? self.groupModel?.trustedPhotoURL == newPhotoURL {
                withAnimation {
                    self.photo = newPhoto
                }
            }
        }
    }
    
        
    public var body: some View {
        InternalView(mode: mode,
                     actions: actions,
                     groupModel: groupModel,
                     photo: photo,
                     photoChosenDuringEdition: $photoChosenDuringEdition,
                     userWantsToRemoveCurrentlyPublishedPhoto: $userWantsToRemoveCurrentlyPublishedPhoto,
                     groupName: $groupName,
                     groupDescription: $groupDescription,
                     groupModelWasUsedToSetNameAndDescription: groupModelWasUsedToSetNameAndDescription,
                     hudCategory: $hudCategory,
                     isInterfaceDisabled: $isInterfaceDisabled,
                     getInitialGroupNameValueFrom: getInitialGroupNameValueFrom,
                     getInitialGroupDescriptionValueFrom: getInitialGroupDescriptionValueFrom)
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .disabled(isInterfaceDisabled)
            .navigationTitle(String(localizedInThisBundle: "EDIT_GROUP_DETAILS"))
    }

    
    public struct InternalView: View {
        
        let mode: Mode
        let actions: EditGroupNameAndPictureViewActionsProtocol
        let groupModel: EditGroupNameAndPictureView.Model?
        let photo: UIImage? // During edition: If there is a published photo, we show it. Otherwise, we show the trusted photo if there is one.
        @Binding var photoChosenDuringEdition: UIImage? // Must be a binding
        @Binding var userWantsToRemoveCurrentlyPublishedPhoto: Bool // Must be a binding
        @Binding var groupName: String // Must be a binding
        @Binding var groupDescription: String // Must be a binding
        let groupModelWasUsedToSetNameAndDescription: Bool
        @Binding var hudCategory: HUDView.Category? // Must be a binding
        @Binding var isInterfaceDisabled: Bool // Must be a binding
        let getInitialGroupNameValueFrom: (_ model: EditGroupNameAndPictureView.Model) -> String
        let getInitialGroupDescriptionValueFrom: (_ model: EditGroupNameAndPictureView.Model) -> String
        
        private var backgroundColor: Color? {
            return Color(AppTheme.shared.colorScheme.systemBackground)
        }

        private func profilePictureViewModel(groupModel: EditGroupNameAndPictureView.Model) -> ProfilePictureView.Model.Content {
            let profilePicture: UIImage?
            if let photoChosenDuringEdition {
                profilePicture = photoChosenDuringEdition
            } else if let photo {
                profilePicture = userWantsToRemoveCurrentlyPublishedPhoto ? nil : photo
            } else {
                profilePicture = nil
            }
            return .init(text: nil,
                  icon: .person3Fill,
                  profilePicture: profilePicture,
                  showGreenShield: groupModel.isKeycloakManaged,
                  showRedShield: false)
        }

        private func profilePictureViewModel(groupModel: EditGroupNameAndPictureView.Model) -> ProfilePictureView.Model {
            .init(content: profilePictureViewModel(groupModel: groupModel),
                  colors: groupModel.circleColors,
                  circleDiameter: circleDiameter)
        }

        private var profilePictureViewModelContentlDuringCreation: ProfilePictureView.Model.Content {
            return .init(text: nil,
                  icon: .person3Fill,
                  profilePicture: photoChosenDuringEdition,
                  showGreenShield: false,
                  showRedShield: false)
        }
        
        private var profilePictureViewModelDuringCreation: ProfilePictureView.Model {
            .init(content: profilePictureViewModelContentlDuringCreation,
                  colors: .init(background: nil, foreground: nil),
                  circleDiameter: circleDiameter)
        }

        private var circleDiameter: CGFloat {
            ObvDesignSystem.ObvAvatarSize.xLarge.frameSize.width
        }

        var publishButtonDisabled: Bool {
            switch mode {
            case .creation:
                return false
            case .edition:
                if self.groupName.trimmingWhitespacesAndNewlines().isEmpty { return true }
                guard let groupModel else { return true }
                if photoChosenDuringEdition != nil { return false }
                if groupName != getInitialGroupNameValueFrom(groupModel) { return false }
                if groupDescription != getInitialGroupDescriptionValueFrom(groupModel) { return false }
                if userWantsToRemoveCurrentlyPublishedPhoto { return false }
                return true
            }
        }

        private func userTappedMenuButtonToChoosePhotoWithCamera() {
            Task {
                do {
                    if let newPhotoChosenDuringEdition = try await actions.userWantsObtainAvatar(self, avatarSource: .camera, avatarSize: .xLarge) {
                        withAnimation { self.photoChosenDuringEdition = newPhotoChosenDuringEdition }
                    }
                } catch {
                    assertionFailure()
                }
            }
        }
        
        private func userTappedMenuButtonToChoosePhotoFromLibrary() {
            Task {
                do {
                    if let newPhotoChosenDuringEdition = try await actions.userWantsObtainAvatar(self, avatarSource: .photoLibrary, avatarSize: .xLarge) {
                        withAnimation { self.photoChosenDuringEdition = newPhotoChosenDuringEdition }
                    }
                } catch {
                    assertionFailure()
                }
            }
        }

        private func userTappedMenuButtonToChoosePhotoFromFiles() {
            Task {
                do {
                    if let newPhotoChosenDuringEdition = try await actions.userWantsObtainAvatar(self, avatarSource: .files, avatarSize: .xLarge) {
                        withAnimation { self.photoChosenDuringEdition = newPhotoChosenDuringEdition }
                    }
                } catch {
                    assertionFailure()
                }
            }
        }
        
        private func userTappedMenuButtonToRemovePhotoChosenDuringEdition() {
            // If the user chose a new photo, the button removes it.
            // If she did not, this button removes the currently published (or trusted) photo.
            if photoChosenDuringEdition != nil {
                withAnimation {
                    self.photoChosenDuringEdition = nil
                }
            } else if self.photo != nil {
                withAnimation {
                    self.userWantsToRemoveCurrentlyPublishedPhoto = true
                }
            }
        }
        
        private func userTappedMenuButtonToRestorePublishedPhoto() {
            assert(self.photo != nil && self.userWantsToRemoveCurrentlyPublishedPhoto)
            withAnimation {
                self.photoChosenDuringEdition = nil
                self.userWantsToRemoveCurrentlyPublishedPhoto = false
            }
        }
            
        private var sanitizedChosentGroupName: String? {
            let sanitized = self.groupName.trimmingWhitespacesAndNewlines()
            return sanitized.isEmpty ? nil : sanitized
        }

        private var sanitizedChosentGroupDescription: String? {
            let sanitized = self.groupDescription.trimmingWhitespacesAndNewlines()
            return sanitized.isEmpty ? nil : sanitized
        }
        
        private func userTappedOnThePublishChangesButton() {
            
            switch mode {
                
            case .creation(creationSessionUUID: let creationSessionUUID, ownedCryptoId: let ownedCryptoId, preSelectedPhoto: _, preSelectedGroupName: _, preSelectedGroupDescription: _, navigation: let navigation, actions: let actionsForCreation):
                
                isInterfaceDisabled = true
                hudCategory = .progress
                Task {
                    do {
                        let tempURL: URL?
                        if let photoChosenDuringEdition {
                            tempURL = try await actions.userWantsToSaveImageToTempFile(self, image: photoChosenDuringEdition)
                        } else {
                            tempURL = nil
                        }
                        let coreDetails = ObvGroupCoreDetails(name: sanitizedChosentGroupName ?? "", description: sanitizedChosentGroupDescription)
                        let groupDetails = ObvGroupDetails(coreDetails: coreDetails, photoURL: tempURL)
                        try await actionsForCreation .userWantsToPublishCreatedGroupWithDetails(self, creationSessionUUID: creationSessionUUID, ownedCryptoId: ownedCryptoId, groupDetails: groupDetails)
                        hudCategory = .checkmark
                        try? await Task.sleep(seconds: 1)
                        navigation.groupWasSuccessfullyCreated(self, ownedCryptoId: ownedCryptoId)
                    } catch {
                        hudCategory = .xmark
                        try? await Task.sleep(seconds: 1)
                        isInterfaceDisabled = false
                    }
                }
                
            case .edition(groupIdentifier: let groupIdentifier, navigation: let navigation, dataSource: _, avatarViewDataSource: _, actions: let actionsForEdition):

                guard let groupModel else { assertionFailure(); return }
                guard let sanitizedChosentGroupName else { assertionFailure(); return }
                isInterfaceDisabled = true
                hudCategory = .progress
                Task {
                    var changes = Set<EditGroupNameAndPictureView.Change>()
                    do {
                        if let photoChosenDuringEdition {
                            let tempURL = try await actions.userWantsToSaveImageToTempFile(self, image: photoChosenDuringEdition)
                            changes.insert(.groupPhoto(photoURL: tempURL))
                        } else if userWantsToRemoveCurrentlyPublishedPhoto {
                            changes.insert(.groupPhoto(photoURL: nil))
                        }
                        if self.sanitizedChosentGroupName != getInitialGroupNameValueFrom(groupModel) || self.sanitizedChosentGroupDescription != getInitialGroupDescriptionValueFrom(groupModel) {
                            guard !self.groupName.isEmpty else { assertionFailure(); return }
                            let groupCoreDetails = ObvGroupCoreDetails(name: sanitizedChosentGroupName, description: sanitizedChosentGroupDescription)
                            changes.insert(.groupDetails(groupCoreDetails: groupCoreDetails))
                        }
                        guard !changes.isEmpty else { assertionFailure(); return }
                        try await actionsForEdition.userWantsToUpdateGroupNameAndPicture(self, groupIdentifier: groupIdentifier, changes: changes)
                        hudCategory = .checkmark
                        try? await Task.sleep(seconds: 1)
                        navigation.groupDetailsWereSuccessfullyUpdated(self, groupIdentifier: groupIdentifier)
                    } catch {
                        hudCategory = .xmark
                        try? await Task.sleep(seconds: 1)
                        isInterfaceDisabled = false
                    }
                }
                
            }
        }
        
        private var showRemovePhotoMenuAction: Bool {
            if photoChosenDuringEdition != nil { return true }
            if photo != nil && !userWantsToRemoveCurrentlyPublishedPhoto { return true }
            return false
        }
        
        
        private var canShowInternalView: Bool {
            switch mode {
            case .creation:
                return true
            case .edition:
                return groupModel != nil
            }
        }
        
        private var buttonTitle: String {
            switch mode {
            case .creation:
                return String(localizedInThisBundle: "PUBLISH_GROUP")
            case .edition:
                return String(localizedInThisBundle: "PUBLISH_CHANGES")
            }
        }

        public var body: some View {
            
            ZStack {
                
                backgroundColor
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .edgesIgnoringSafeArea(.all)
                
                if canShowInternalView {
                    
                    VStack {
                        
                        ScrollView {
                            VStack(spacing: 0) {
                                
                                // Top large photo and edit button
                                
                                ZStack {
                                    // The bottom view show the current published photo, if there is one.
                                    // Otherwise, it shows the trusted photo, if there is one.
                                    switch mode {
                                    case .creation:
                                        ProfilePictureView(model: profilePictureViewModelDuringCreation)
                                    case .edition:
                                        if let groupModel {
                                            // Always true as canShowInternalView == true
                                            ProfilePictureView(model: profilePictureViewModel(groupModel: groupModel))
                                        }
                                    }
                                }
                                .overlay(alignment: .init(horizontal: .trailing, vertical: .bottom)) {
                                    Menu {
                                        if UIImagePickerController.isCameraDeviceAvailable(.front) {
                                            Button(action: userTappedMenuButtonToChoosePhotoWithCamera) {
                                                Label {
                                                    Text("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_TAKE_PICTURE")
                                                } icon: {
                                                    Image(systemIcon: .camera(.none))
                                                }
                                            }
                                        }
                                        Button(action: userTappedMenuButtonToChoosePhotoFromLibrary) {
                                            Label {
                                                Text("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_CHOOSE_PICTURE")
                                            } icon: {
                                                Image(systemIcon: .photo)
                                            }
                                        }
                                        Button(action: userTappedMenuButtonToChoosePhotoFromFiles) {
                                            Label {
                                                Text("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_CHOOSE_PICTURE_FROM_DOCUMENT_PICKER")
                                            } icon: {
                                                Image(systemIcon: .doc)
                                            }
                                        }
                                        if showRemovePhotoMenuAction {
                                            Button(action: userTappedMenuButtonToRemovePhotoChosenDuringEdition) {
                                                Label {
                                                    Text("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_REMOVE_PICTURE")
                                                } icon: {
                                                    Image(systemIcon: .trash)
                                                }
                                            }
                                        }
                                        if photo != nil && userWantsToRemoveCurrentlyPublishedPhoto {
                                            Button(action: userTappedMenuButtonToRestorePublishedPhoto) {
                                                Label {
                                                    Text("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_RESTORE_PICTURE")
                                                } icon: {
                                                    Image(systemIcon: .trashSlash)
                                                }
                                            }
                                        }
                                    } label: {
                                        ZStack {
                                            if let backgroundColor {
                                                Circle()
                                                    .fill(backgroundColor)
                                                    .frame(width: circleDiameter/4+10, height: circleDiameter/4+10)
                                            } else {
                                                Circle()
                                                    .fill(.background)
                                                    .frame(width: circleDiameter/4+10, height: circleDiameter/4+10)
                                            }
                                            Circle()
                                                .fill(.white)
                                                .frame(width: circleDiameter/4-1, height: circleDiameter/4-1)
                                            Image(systemIcon: .camera(.circleFill))
                                                .font(.system(size: circleDiameter/4))
                                                .foregroundStyle(.blue)
                                                .offset(x: 0, y: 0)
                                        }
                                    }
                                    
                                }
                                .accessibilityElement(children: .combine)
                                .if(photo != nil) {
                                    $0.accessibilityLabel(Text("REPLACE_GROUP_PHOTO"))
                                }
                                .if(photo == nil) {
                                    $0.accessibilityLabel(Text("CHOOSE_A_GROUP_PHOTO"))
                                }
                                
                                
                                // Editing the name and description
                                
                                VStack(spacing: 6) {
                                    
                                    HStack {
                                        Text("ENTER_GROUP_DETAILS")
                                            .font(.footnote)
                                            .textCase(.uppercase)
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                    }.padding(.leading, 30)
                                    
                                    ObvCardView(shadow: false) {
                                        VStack(spacing: 0) {
                                            TextField(String(localizedInThisBundle: "GROUP_NAME"), text: $groupName)
                                            Divider()
                                                .padding(.vertical)
                                            TextField(String(localizedInThisBundle: "GROUP_DESCRIPTION"), text: $groupDescription)
                                        }
                                    }
                                    .padding(.horizontal)
                                    
                                }.padding(.top, 40)
                                
                            }
                        }
                     
                        Button(action: userTappedOnThePublishChangesButton) {
                            HStack {
                                Spacer(minLength: 0)
                                Text(buttonTitle)
                                    .padding(.vertical, 8)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .padding(.bottom)
                        .disabled(publishButtonDisabled)

                    }
                    
                } else {
                    ProgressView()
                }

                if let hudCategory = self.hudCategory {
                    HUDView(category: hudCategory)
                }
                
            }

        }
    }
    
}



// MARK: - Previews

#if DEBUG

@MainActor
private final class DataSourceForPreviews {}

extension DataSourceForPreviews: EditGroupNameAndPictureViewDataSource {
    
    func getAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupNameAndPictureView, groupIdentifier: ObvGroupIdentifier) throws -> (streamUUID: UUID, stream: AsyncStream<EditGroupNameAndPictureView.ModelOrNotFound>) {
        let stream = AsyncStream(EditGroupNameAndPictureView.ModelOrNotFound.self) { (continuation: AsyncStream<EditGroupNameAndPictureView.ModelOrNotFound>.Continuation) in
            let model = PreviewsHelper.editGroupNameAndPictureViewModels[0]
            continuation.yield(.model(model))
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfSingleGroupV2MainViewModel(_ view: EditGroupNameAndPictureView, streamUUID: UUID) {
        // Nothing to terminate in these previews
    }
    
    func getPhotoForGroup(_ view: EditGroupNameAndPictureView, groupIdentifier: ObvGroupIdentifier, photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        if let image = PreviewsHelper.profilePictureForURL[photoURL] {
            return image
        } else {
            return nil
        }
    }
    
}

extension DataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        if let image = PreviewsHelper.profilePictureForURL[photoURL] {
            return image
        } else {
            return nil
        }
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        try await Task.sleep(seconds: 1)
        if let image = PreviewsHelper.profilePictureForURL[photoURL] {
            return image
        } else {
            return nil
        }
    }
    
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    
}

private final class ActionsForPreviews: EditGroupNameAndPictureViewActionsProtocol {
    
    func userWantsToSaveImageToTempFile(_ view: EditGroupNameAndPictureView.InternalView, image: UIImage) async throws -> URL {
        return PreviewsHelper.photoURLForGroupPicture[0]
    }


    func userWantsObtainAvatar(_ view: EditGroupNameAndPictureView.InternalView, avatarSource: ObvAppTypes.ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        let url: URL
        switch avatarSource {
        case .camera:
            url = PreviewsHelper.photoURLForGroupPicture[2]
        case .photoLibrary:
            url = PreviewsHelper.photoURLForGroupPicture[0]
        case .files:
            url = PreviewsHelper.photoURLForGroupPicture[2]
        }
        if let image = PreviewsHelper.profilePictureForURL[url] {
            return image
        } else {
            return nil
        }
    }
    
}


extension ActionsForPreviews: EditGroupNameAndPictureViewActionsForCreation {
    
    func userWantsToPublishCreatedGroupWithDetails(_ view: EditGroupNameAndPictureView.InternalView, creationSessionUUID: UUID, ownedCryptoId: ObvTypes.ObvCryptoId, groupDetails: ObvTypes.ObvGroupDetails) async throws {
        try await Task.sleep(seconds: 1)
    }

}

extension ActionsForPreviews: EditGroupNameAndPictureViewActionsForEdition {
    
    func userWantsToUpdateGroupNameAndPicture(_ view: EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvGroupIdentifier, changes: Set<EditGroupNameAndPictureView.Change>) async throws {
        try await Task.sleep(seconds: 1)
    }

}

private final class NavigationForPreviewsDuringEdition: EditGroupNameAndPictureViewNavigationDuringEdition {
    func userWantsToLeaveGroupFlow(_ view: EditGroupNameAndPictureView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {}
    func groupDetailsWereSuccessfullyUpdated(_ view: EditGroupNameAndPictureView.InternalView, groupIdentifier: ObvAppTypes.ObvGroupIdentifier) {}
}

private final class NavigationForPreviewsDuringCreation: EditGroupNameAndPictureViewNavigationDuringCreation {
    func groupWasSuccessfullyCreated(_ view: EditGroupNameAndPictureView.InternalView, ownedCryptoId: ObvTypes.ObvCryptoId) {}
}


@MainActor
private let dataSourceForPreviews = DataSourceForPreviews()


@MainActor
private let actionsForPreviews = ActionsForPreviews()

@MainActor
private let navigationForPreviewsDuringCreation = NavigationForPreviewsDuringCreation()

@MainActor
private let navigationForPreviewsDuringEdition = NavigationForPreviewsDuringEdition()


#Preview("Creation") {
    NavigationStack {
        EditGroupNameAndPictureView(mode: .creation(creationSessionUUID: UUID(),
                                                    ownedCryptoId: PreviewsHelper.cryptoIds[0],
                                                    preSelectedPhoto: nil,
                                                    preSelectedGroupName: nil,
                                                    preSelectedGroupDescription: nil,
                                                    navigation: navigationForPreviewsDuringCreation,
                                                    actions: actionsForPreviews),
                                    actions: actionsForPreviews)
    }
}

#Preview("Edition") {
    NavigationStack {
        EditGroupNameAndPictureView(mode: .edition(groupIdentifier: .groupV2(PreviewsHelper.obvGroupV2Identifiers.first!),
                                                   navigation: navigationForPreviewsDuringEdition,
                                                   dataSource: dataSourceForPreviews,
                                                   avatarViewDataSource: dataSourceForPreviews,
                                                   actions: actionsForPreviews),
                                    actions: actionsForPreviews)
    }
}

#endif
