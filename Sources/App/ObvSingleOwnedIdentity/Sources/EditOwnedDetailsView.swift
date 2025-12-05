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
import ObvCircleAndTitlesView
import ObvDesignSystem
import ObvAppTypes

@MainActor
public protocol EditOwnedDetailsViewActions {
    func userWantsObtainAvatar(_ view: EditOwnedDetailsView, avatarSource: ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage?
    func userWantsToSaveImageToTempFile(_ view: EditOwnedDetailsView, image: UIImage) async throws -> URL
    func userWantsToPublishNewOwnedDetails(_ view: EditOwnedDetailsView, ownedCryptoId: ObvCryptoId, newIdentityDetails: ObvIdentityDetails) async throws
    func userWantsToUnbindOwnedIdentityFromKeycloak(_ view: EditOwnedDetailsView, ownedCryptoId: ObvCryptoId) async throws
}

@MainActor
public protocol EditOwnedDetailsViewDataSource {
    func getAsyncSequenceOfEditOwnedDetailsViewModel(_ view: EditOwnedDetailsView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<EditOwnedDetailsView.Model>)
    func finishAsyncSequenceOfEditOwnedDetailsViewModel(_ view: EditOwnedDetailsView, streamUUID: UUID)
}

@MainActor
public protocol EditOwnedDetailsViewNavigation {
    func userWantsToDismissEditOwnedDetailsView(_ view: EditOwnedDetailsView)
}

public struct EditOwnedDetailsView: View {
    
    let ownedCryptoId: ObvCryptoId
    let dataSources: DataSources
    let actions: any EditOwnedDetailsViewActions
    let navigation: any EditOwnedDetailsViewNavigation
        
    public struct Model: Sendable, Equatable {
        let ownedIdentityDetails: ObvIdentityDetails
        let largePhotoModel: LargePhotoAndEditButton.InitialModel
        let isManagedByKeycloak: Bool

        public init(ownedIdentityDetails: ObvIdentityDetails, largePhotoModel: LargePhotoAndEditButton.InitialModel, isManagedByKeycloak: Bool) {
            self.ownedIdentityDetails = ownedIdentityDetails
            self.largePhotoModel = largePhotoModel
            self.isManagedByKeycloak = isManagedByKeycloak
        }
        
    }
    
    public struct DataSources {
        let dataSource: EditOwnedDetailsViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        public init(dataSource: EditOwnedDetailsViewDataSource, avatarViewDataSource: any ObvAvatarViewDataSource) {
            self.dataSource = dataSource
            self.avatarViewDataSource = avatarViewDataSource
        }
    }
        
    @State private var firstName: String = ""
    @State private var lastName: String = ""
    @State private var company: String = ""
    @State private var position: String = ""
            
    @State private var initialPhotoURL: URL? = nil
    
    @State private var photoChosenDuringEdition: UIImage? = nil

    @State private var userWantsToRemoveCurrentlyPublishedPhoto: Bool = false
    
    private enum InterfaceLoadingState {
        case loading
        case loaded(currentModel: Model, initialPhoto: UIImage?)
        var model: Model? {
            switch self {
            case .loading: return nil
            case .loaded(let currentModel, _): return currentModel
            }
        }
    }
    
    /// Contains the current published values for the profile. The first time it is set, we also
    /// set the initial values of `firstName`, etc.
    @State private var interfaceLoadingState = InterfaceLoadingState.loading
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncSequenceOfEditOwnedDetailsViewModel(self, ownedCryptoId: ownedCryptoId)
            defer { dataSources.dataSource.finishAsyncSequenceOfEditOwnedDetailsViewModel(self, streamUUID: streamUUID) }
            for await receivedModel in stream {
                switch interfaceLoadingState {
                case .loading:
                    // We receive the current published values for the first time, so we set the initial
                    // values shown in the interface.
                    self.firstName = receivedModel.ownedIdentityDetails.coreDetails.firstName ?? ""
                    self.lastName = receivedModel.ownedIdentityDetails.coreDetails.lastName ?? ""
                    self.company = receivedModel.ownedIdentityDetails.coreDetails.company ?? ""
                    self.position = receivedModel.ownedIdentityDetails.coreDetails.position ?? ""
                    self.initialPhotoURL = receivedModel.ownedIdentityDetails.photoURL
                    let initialPhoto: UIImage?
                    if let initialPhotoURL {
                        // Note that we load the photo before changing the interface loading state, ensuring that the information is complete on the first
                        // user display.
                        initialPhoto = try await dataSources.avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: initialPhotoURL, avatarSize: .xLarge)
                    } else {
                        initialPhoto = nil
                    }
                    interfaceLoadingState = .loaded(currentModel: receivedModel, initialPhoto: initialPhoto)
                case .loaded(currentModel: let currentModel, initialPhoto: _):
                    if (currentModel.isManagedByKeycloak != receivedModel.isManagedByKeycloak) || currentModel.isManagedByKeycloak {
                        let initialPhoto: UIImage?
                        if let initialPhotoURL {
                            // Note that we load the photo before changing the interface loading state, ensuring that the information is complete on the first
                            // user display.
                            initialPhoto = try await dataSources.avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: initialPhotoURL, avatarSize: .xLarge)
                        } else {
                            initialPhoto = nil
                        }
                        withAnimation { interfaceLoadingState = .loaded(currentModel: receivedModel, initialPhoto: initialPhoto) }
                    } else {
                        // The `isManagedByKeycloak` parameter did not change and it is false. So we are dealing with a non-managed profile.
                        // We already received a first version of the published details of the contact, so we
                        // don't reset the values of the interface (as this could override values manually changed by the user).
                        // Yet we keep them, to keep the "publish" button in sync.
                        let initialPhoto: UIImage?
                        if let initialPhotoURL {
                            // Note that we load the photo before changing the interface loading state, ensuring that the information is complete on the first
                            // user display.
                            initialPhoto = try await dataSources.avatarViewDataSource.fetchAvatarForLegacyViews(photoURL: initialPhotoURL, avatarSize: .xLarge)
                        } else {
                            initialPhoto = nil
                        }
                        withAnimation { interfaceLoadingState = .loaded(currentModel: receivedModel, initialPhoto: initialPhoto) }
                    }
                }
            }
        } catch {
            assertionFailure()
        }
    }
    
    private var isInterfaceDisabled: Bool {
        isPublishingNewDetails || isUnbindingProfile
    }

    @State private var isPublishingNewDetails: Bool = false
    
    /// This method is typically called for a non-keycloak managed profile. But it can also be called for a keycloak profile, when the user
    /// changes their photo.
    private func publishButtonTapped() {
        withAnimation { isPublishingNewDetails = true }
        Task {
            defer { withAnimation { isPublishingNewDetails = false } }
            do {
                let newCoreDetails = try ObvIdentityCoreDetails(
                    firstName: firstName,
                    lastName: lastName,
                    company: company,
                    position: position,
                    signedUserDetails: nil)
                let newPhotoURL: URL?
                if let photoChosenDuringEdition {
                    newPhotoURL = try await actions.userWantsToSaveImageToTempFile(self, image: photoChosenDuringEdition)
                } else {
                    newPhotoURL = nil
                }
                let newIdentityDetails: ObvIdentityDetails = .init(coreDetails: newCoreDetails, photoURL: newPhotoURL ?? initialPhotoURL)
                try await actions.userWantsToPublishNewOwnedDetails(self, ownedCryptoId: ownedCryptoId, newIdentityDetails: newIdentityDetails)
                navigation.userWantsToDismissEditOwnedDetailsView(self)
            } catch {
                assertionFailure()
            }
        }
    }
    
    private var publishButtonDisabled: Bool {
        switch interfaceLoadingState {
        case .loading:
            return true
        case .loaded(currentModel: let currentModel, initialPhoto: _):
            do {
                let newCoreDetails = try ObvIdentityCoreDetails(
                    firstName: firstName,
                    lastName: lastName,
                    company: company,
                    position: position,
                    signedUserDetails: nil)
                if !newCoreDetails.fieldsAreTheSameAndSignedDetailsAreNotConsidered(than: currentModel.ownedIdentityDetails.coreDetails) { return false }
                if photoChosenDuringEdition != nil { return false }
                if userWantsToRemoveCurrentlyPublishedPhoto { return false }
                return true
            } catch {
                return true // We could not construct the core details, we must disable the button
            }
        }
    }
    
    private var navigationTitle: String {
        String(localizedInThisBundle: "NAVIGATION_TITLE_EDIT_MY_PROFILE")
    }
    
    private func userWantsToDismissEditOwnedDetailsView() {
        navigation.userWantsToDismissEditOwnedDetailsView(self)
    }
    
    @State private var isUnbindOwnedIdentityFromKeycloakAlertPresented: Bool = false
    
    private func userWantsToUnbindOwnedIdentityFromKeycloakButHasNotConfirmed() {
        isUnbindOwnedIdentityFromKeycloakAlertPresented = true
    }
    
    @State private var isUnbindingProfile: Bool = false
    
    private func userWantsToUnbindOwnedIdentityFromKeycloakAndHasConfirmed() {
        withAnimation { isUnbindingProfile = true }
        Task {
            defer { withAnimation { isUnbindingProfile = false } }
            do {
                try await actions.userWantsToUnbindOwnedIdentityFromKeycloak(self, ownedCryptoId: ownedCryptoId)
            } catch {
                assertionFailure()
            }
        }
    }
    
    public var body: some View {
        NavigationStack {
            Group {
                switch interfaceLoadingState {
                case .loading:
                    ObvCenteredProgressView()
                case .loaded(let currentModel, let initialPhoto):
                    VStack {
                        ScrollView {
                            
                            LargePhotoAndEditButton(
                                initialModel: currentModel.largePhotoModel,
                                userWantsToRemoveCurrentlyPublishedPhoto: $userWantsToRemoveCurrentlyPublishedPhoto,
                                photoChosenDuringEdition: $photoChosenDuringEdition,
                                initialPhoto: initialPhoto,
                                internalActions: self)
                            .padding()
                            
                            ObvCardView {
                                VStack(spacing: 0) {
                                    TextField(String(localizedInThisBundle: "TEXT_FIELD_FIRST_NAME"), text: $firstName)
                                        .keyboardType(.default)
                                        .autocorrectionDisabled()
                                    Divider()
                                        .padding(.vertical)
                                    TextField(String(localizedInThisBundle: "TEXT_FIELD_LAST_NAME"), text: $lastName)
                                        .keyboardType(.default)
                                        .autocorrectionDisabled()
                                    Divider()
                                        .padding(.vertical)
                                    TextField(String(localizedInThisBundle: "TEXT_FIELD_POSITION"), text: $position)
                                    Divider()
                                        .padding(.vertical)
                                    TextField(String(localizedInThisBundle: "TEXT_FIELD_COMPANY"), text: $company)
                                }
                            }
                            .padding()
                            .disabled(currentModel.isManagedByKeycloak)
                            
                            if currentModel.isManagedByKeycloak {
                                ObvCardView {
                                    HStack {
                                        Text("EXPLANATION_MANAGED_IDENTITY")
                                            .foregroundStyle(.secondary)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                        }
                        
                        VStack {
                            if currentModel.isManagedByKeycloak {
                                OlvidButtonNew(action: userWantsToUnbindOwnedIdentityFromKeycloakButHasNotConfirmed, style: .glassOrBordered) {
                                    HStack {
                                        if isUnbindingProfile { ProgressView().progressViewStyle(.circular) }
                                        Label(title: { Text("REMOVE_IDENTITY_PROVIDER") }, icon: { Image(systemIcon: .personCropCircleFillBadgeXmark) })
                                    }
                                }
                            }
                            OlvidButtonNew(action: publishButtonTapped) {
                                HStack {
                                    if isPublishingNewDetails { ProgressView().progressViewStyle(.circular).foregroundStyle(.white) }
                                    Label(title: { Text("BUTTON_TITLE_PUBLISH_MY_PROFILE_UPDATE") }, icon: { Image(systemIcon: .paperplaneFill) })
                                }
                            }
                            .disabled(publishButtonDisabled)
                        }
                        .padding()
                    }
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .navigationTitle(navigationTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: userWantsToDismissEditOwnedDetailsView)
                }
            }
        }
        .task(onTask)
        .disabled(isInterfaceDisabled)
        .alert(String(localizedInThisBundle: "REMOVE_IDENTITY_PROVIDER"),
               isPresented: $isUnbindOwnedIdentityFromKeycloakAlertPresented) {
            Button(action: {}, label: { Text("CANCEL") })
            Button(action: userWantsToUnbindOwnedIdentityFromKeycloakAndHasConfirmed, label: { Text("OK") })
        } message: {
            Text("DIALOG_MESSAGE_UNBIND_FROM_KEYCLOAK")
        }

    }
    
}


extension EditOwnedDetailsView: LargePhotoAndEditButtonActions {
    
    func userTappedMenuButtonToChoosePhotoWithCamera() {
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
    
    func userTappedMenuButtonToChoosePhotoFromLibrary() {
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
    
    func userTappedMenuButtonToChoosePhotoFromFiles() {
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
    
}


// MARK: - Internal view

@MainActor
protocol LargePhotoAndEditButtonActions {
    func userTappedMenuButtonToChoosePhotoWithCamera()
    func userTappedMenuButtonToChoosePhotoFromLibrary()
    func userTappedMenuButtonToChoosePhotoFromFiles()
}

public struct LargePhotoAndEditButton: View {
    
    let initialModel: InitialModel
    @Binding var userWantsToRemoveCurrentlyPublishedPhoto: Bool // Must be a binding
    @Binding var photoChosenDuringEdition: UIImage? // Must be a binding
    let initialPhoto: UIImage?
    let internalActions: LargePhotoAndEditButtonActions
    
    public struct InitialModel: Sendable, Equatable {
        let textForInitial: String? // For the initial
        let colors: InitialCircleView.Model.Colors
        let showGreenShield: Bool
        
        public init(textForInitial: String?, colors: InitialCircleView.Model.Colors, showGreenShield: Bool) {
            self.textForInitial = textForInitial
            self.colors = colors
            self.showGreenShield = showGreenShield
        }
    }

    private var content: ProfilePictureView.Model.Content {
        .init(text: initialModel.textForInitial,
              icon: .person,
              profilePicture: photoChosenDuringEdition ?? initialPhoto,
              showGreenShield: initialModel.showGreenShield,
              showRedShield: false)
    }
    
    private var circleDiameter: CGFloat {
        ObvDesignSystem.ObvAvatarSize.xLarge.frameSize.width
    }

    private var model: ProfilePictureView.Model {
        .init(content: content,
              colors: initialModel.colors,
              circleDiameter: circleDiameter)
    }
    
    private func userTappedMenuButtonToRemovePhotoChosenDuringEdition() {
        withAnimation {
            self.photoChosenDuringEdition = nil
        }
    }
    
    private func userTappedMenuButtonToRestorePublishedPhoto() {
        assert(self.initialPhoto != nil && self.userWantsToRemoveCurrentlyPublishedPhoto)
        withAnimation {
            self.photoChosenDuringEdition = nil
            self.userWantsToRemoveCurrentlyPublishedPhoto = false
        }
    }
    
    private var backgroundColor: Color? {
        return Color(AppTheme.shared.colorScheme.systemBackground)
    }

    public var body: some View {
        ProfilePictureView(model: model)
            .overlay(alignment: .init(horizontal: .trailing, vertical: .bottom)) {
                Menu {
                    if UIImagePickerController.isCameraDeviceAvailable(.front) {
                        Button(action: internalActions.userTappedMenuButtonToChoosePhotoWithCamera) {
                            Label {
                                Text("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_TAKE_PICTURE")
                            } icon: {
                                Image(systemIcon: .camera(.none))
                            }
                        }
                    }
                    Button(action: internalActions.userTappedMenuButtonToChoosePhotoFromLibrary) {
                        Label {
                            Text("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_CHOOSE_PICTURE")
                        } icon: {
                            Image(systemIcon: .photo)
                        }
                    }
                    Button(action: internalActions.userTappedMenuButtonToChoosePhotoFromFiles) {
                        Label {
                            Text("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_CHOOSE_PICTURE_FROM_DOCUMENT_PICKER")
                        } icon: {
                            Image(systemIcon: .doc)
                        }
                    }
                    if photoChosenDuringEdition != nil {
                        Button(action: userTappedMenuButtonToRemovePhotoChosenDuringEdition) {
                            Label {
                                Text("ONBOARDING_PROFILE_PICTURE_CHOOSER_BUTTON_TITLE_REMOVE_PICTURE")
                            } icon: {
                                Image(systemIcon: .trash)
                            }
                        }
                    }
                    if initialPhoto != nil && userWantsToRemoveCurrentlyPublishedPhoto {
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
            .if(initialPhoto != nil) {
                $0.accessibilityLabel(Text("REPLACE_PROFILE_PHOTO"))
            }
            .if(initialPhoto == nil) {
                $0.accessibilityLabel(Text("CHOOSE_A_PROFILE_PHOTO"))
            }
    }
    
}


#if DEBUG

@MainActor
private final class DataSourceForPreviews {}

extension DataSourceForPreviews: EditOwnedDetailsViewDataSource {
    
    func getAsyncSequenceOfEditOwnedDetailsViewModel(_ view: EditOwnedDetailsView, ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<EditOwnedDetailsView.Model>) {
        let stream = AsyncStream<EditOwnedDetailsView.Model> { (continuation: AsyncStream<EditOwnedDetailsView.Model>.Continuation) in
            Task {
                do {
                    let model: EditOwnedDetailsView.Model = .init(
                        ownedIdentityDetails: .sampleData[0],
                        largePhotoModel: .init(textForInitial: "X",
                                               colors: .init(background: .green, foreground: .blue),
                                               showGreenShield: false),
                        isManagedByKeycloak: true)
                    continuation.yield(model)
                }
                try? await Task.sleep(seconds: 5)
                let model: EditOwnedDetailsView.Model = .init(
                    ownedIdentityDetails: .sampleData[1],
                    largePhotoModel: .init(textForInitial: "X",
                                           colors: .init(background: .green, foreground: .blue),
                                           showGreenShield: false),
                    isManagedByKeycloak: true)
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfEditOwnedDetailsViewModel(_ view: EditOwnedDetailsView, streamUUID: UUID) {}
    
}

extension DataSourceForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
    /// Called for the initial photo
    func fetchAvatarForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    /// Called for the initial photo
    func fetchAvatarFromCacheForLegacyViews(photoURL: URL, avatarSize: ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}

extension DataSourceForPreviews: EditOwnedDetailsViewActions {
    
    func userWantsObtainAvatar(_ view: EditOwnedDetailsView, avatarSource: ObvAppTypes.ObvAvatarSource, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func userWantsToSaveImageToTempFile(_ view: EditOwnedDetailsView, image: UIImage) async throws -> URL {
        return URL(string: "https://olvid.io")!
    }
    
    func userWantsToPublishNewOwnedDetails(_ view: EditOwnedDetailsView, ownedCryptoId: ObvTypes.ObvCryptoId, newIdentityDetails: ObvTypes.ObvIdentityDetails) async throws {
        try? await Task.sleep(seconds: 2)
    }
    
    func userWantsToUnbindOwnedIdentityFromKeycloak(_ view: EditOwnedDetailsView, ownedCryptoId: ObvCryptoId) async throws {
        try? await Task.sleep(seconds: 2)
    }
    
}

extension DataSourceForPreviews: EditOwnedDetailsViewNavigation {
    
    func userWantsToDismissEditOwnedDetailsView(_ view: EditOwnedDetailsView) {
        print("User wants to dismiss EditOwnedDetailsView")
    }
    
}

@MainActor
private let dataSourcesForPreviews = DataSourceForPreviews()

#Preview {
    EditOwnedDetailsView(
        ownedCryptoId: .sampleOwnedCryptoId,
        dataSources: .init(dataSource: dataSourcesForPreviews,
                           avatarViewDataSource: dataSourcesForPreviews),
        actions: dataSourcesForPreviews,
        navigation: dataSourcesForPreviews)
}

#endif

