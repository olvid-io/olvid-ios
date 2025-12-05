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
import StoreKit
import ObvTypes
import ObvDesignSystem
import ObvLicenceActivationFlow
import ObvAppTypes
import ObvSubscription
import ObvSystemIcon


@MainActor
public protocol ObvSingleOwnedIdentityViewDataSource {
    func getAsyncSequenceOfObvSingleOwnedIdentityViewModel(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId) async throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleOwnedIdentityView.ModelOrDeleted>)
    func finishAsyncSequenceOfObvSingleOwnedIdentityViewModel(_ view: ObvSingleOwnedIdentityView, streamUUID: UUID)
}


@MainActor
public protocol ObvSingleOwnedIdentityViewNavigation {
    func userWantsToEditOwnedProfile(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId)
    func userWantsToNavigateToListOfOwnedDevices(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId)
    func userWantsToNavigateToViewAllowingToAddNewDevice(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId)
}

@MainActor
public protocol ObvSingleOwnedIdentityViewActions: InactiveOwnedIdentityViewActions, OlvidShopViewActions, HiddenProfilePasswordChooserViewActions {
    func userWantsToRefreshSubscriptionStatus(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId) async throws -> [ObvAppTypes.StoreKitDelegatePurchaseResult]
    func userWantsToDeleteOwnedIdentityButHasNotConfirmedYet(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId)
    func userWantsToAddOwnedProfile(_ view: ObvSingleOwnedIdentityView)
    func userWantsToUnhideOwnedIdentity(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId) async throws
    func userWantsToUpdateOwnedCustomDisplayName(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId, newCustomDisplayName: String?) async throws
}

public struct ObvSingleOwnedIdentityView: View {

    let ownedCryptoId: ObvCryptoId
    let dataSources: DataSources
    let actions: any ObvSingleOwnedIdentityViewActions
    let navigation: any ObvSingleOwnedIdentityViewNavigation
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    public struct DataSources {
        let dataSource: any ObvSingleOwnedIdentityViewDataSource
        let avatarViewDataSource: any ObvAvatarViewDataSource
        let chooseDeviceToReactivateViewDataSource: any ObvChooseDeviceToReactivateViewDataSource
        let olvidShopViewDataSources: OlvidShopView.DataSources
        let ownedDetailedInfosViewDataSources: ObvOwnedDetailedInfosView.DataSources
        public init(dataSource: any ObvSingleOwnedIdentityViewDataSource,
                    avatarViewDataSource: any ObvAvatarViewDataSource,
                    chooseDeviceToReactivateViewDataSource: any ObvChooseDeviceToReactivateViewDataSource,
                    olvidShopViewDataSources: OlvidShopView.DataSources,
                    ownedDetailedInfosViewDataSources: ObvOwnedDetailedInfosView.DataSources) {
            self.dataSource = dataSource
            self.avatarViewDataSource = avatarViewDataSource
            self.chooseDeviceToReactivateViewDataSource = chooseDeviceToReactivateViewDataSource
            self.olvidShopViewDataSources = olvidShopViewDataSources
            self.ownedDetailedInfosViewDataSources = ownedDetailedInfosViewDataSources
        }
    }
    
    public enum ModelOrDeleted: Sendable, Equatable {
        case deleted
        case model(Model)
    }

    public struct Model: Sendable, Equatable {
        let ownedCryptoId: ObvCryptoId
        let avatarModel: ObvAvatarViewModel
        let identityDetails: ObvIdentityDetails
        let isActive: Bool
        let numberOfOwnedDevices: Int
        let apiKeyElements: APIKeyElements
        let isHidden: Bool
        let numberOfOtherNonHiddenOwnedIdentities: Int
        let customDisplayName: String?
        
        public init(ownedCryptoId: ObvCryptoId,
                    avatarModel: ObvAvatarViewModel,
                    identityDetails: ObvIdentityDetails,
                    isActive: Bool,
                    numberOfOwnedDevices: Int,
                    apiKeyElements: APIKeyElements,
                    isHidden: Bool,
                    numberOfOtherNonHiddenOwnedIdentities: Int,
                    customDisplayName: String?) {
            self.ownedCryptoId = ownedCryptoId
            self.avatarModel = avatarModel
            self.identityDetails = identityDetails
            self.isActive = isActive
            self.numberOfOwnedDevices = numberOfOwnedDevices
            self.apiKeyElements = apiKeyElements
            self.isHidden = isHidden
            self.numberOfOtherNonHiddenOwnedIdentities = numberOfOtherNonHiddenOwnedIdentities
            self.customDisplayName = customDisplayName
        }
        
    }
    
    private func onTask() async {
        do {
            let (streamUUID, stream) = try await dataSources.dataSource.getAsyncSequenceOfObvSingleOwnedIdentityViewModel(self, ownedCryptoId: ownedCryptoId)
            defer { dataSources.dataSource.finishAsyncSequenceOfObvSingleOwnedIdentityViewModel(self, streamUUID: streamUUID) }
            for await receivedModel in stream {
                if self.streamedModel == nil {
                    self.streamedModel = receivedModel
                } else {
                    withAnimation { self.streamedModel = receivedModel }
                }
            }
        } catch {
            assertionFailure()
        }
    }
    
    @State private var streamedModel: ModelOrDeleted?
    
    @State private var shownHUD: HUDView.Category? = nil

    public var body: some View {
        ZStack {
            switch streamedModel {
            case .deleted:
                DeletedProfileView()
            case .model(let model):
                InternalView(ownedCryptoId: ownedCryptoId,
                             model: model,
                             dataSources: dataSources,
                             actions: actions,
                             uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet,
                             internalActions: self)
            case nil:
                ObvCenteredProgressView()
            }
            if let shownHUD {
                HUDView(category: shownHUD)
            }
        }
        .task(onTask)
    }
    
}


extension ObvSingleOwnedIdentityView: ObvSingleOwnedIdentityViewInternalActions {
    
    func userWantsToRefreshSubscriptionStatus() {
        self.shownHUD = .progress
        Task {
            do {
                _ = try await actions.userWantsToRefreshSubscriptionStatus(self, ownedCryptoId: ownedCryptoId)
                self.shownHUD = .checkmark
            } catch {
                self.shownHUD = .xmark
            }
            try? await Task.sleep(seconds: 1)
            self.shownHUD = nil
        }
    }
    
    internal func userTappedEditProfileButton() {
        navigation.userWantsToEditOwnedProfile(self, ownedCryptoId: ownedCryptoId)
    }
    
    internal func userWantsToNavigateToListOfOwnedDevices() {
        navigation.userWantsToNavigateToListOfOwnedDevices(self, ownedCryptoId: ownedCryptoId)
    }
    
    internal func userWantsToNavigateToViewAllowingToAddNewDevice() {
        navigation.userWantsToNavigateToViewAllowingToAddNewDevice(self, ownedCryptoId: ownedCryptoId)
    }

    internal func userWantsToDeleteOwnedIdentityButHasNotConfirmedYet(ownedCryptoId: ObvCryptoId) {
        actions.userWantsToDeleteOwnedIdentityButHasNotConfirmedYet(self, ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToAddOwnedProfile() {
        actions.userWantsToAddOwnedProfile(self)
    }
    
    func userWantsToUnhideOwnedIdentity(ownedCryptoId: ObvCryptoId) async throws {
        try await actions.userWantsToUnhideOwnedIdentity(self, ownedCryptoId: ownedCryptoId)
    }
    
    func userWantsToUpdateOwnedCustomDisplayName(ownedCryptoId: ObvCryptoId, newCustomDisplayName: String?) async throws {
        try await actions.userWantsToUpdateOwnedCustomDisplayName(self, ownedCryptoId: ownedCryptoId, newCustomDisplayName: newCustomDisplayName)
    }
    
}


private struct DeletedProfileView: View {
    var body: some View {
        ObvContentUnavailableView(
            title: String(localizedInThisBundle: "DELETED_PROFILE_TITLE"),
            systemIcon: .personSlash,
            description: String(localizedInThisBundle: "DELETED_PROFILE_DESCRIPTION"))
    }
}


@MainActor
private protocol ObvSingleOwnedIdentityViewInternalActions {
    func userTappedEditProfileButton()
    func userWantsToNavigateToListOfOwnedDevices()
    func userWantsToNavigateToViewAllowingToAddNewDevice()
    func userWantsToRefreshSubscriptionStatus()
    func userWantsToDeleteOwnedIdentityButHasNotConfirmedYet(ownedCryptoId: ObvCryptoId)
    func userWantsToAddOwnedProfile()
    func userWantsToUnhideOwnedIdentity(ownedCryptoId: ObvCryptoId) async throws
    func userWantsToUpdateOwnedCustomDisplayName(ownedCryptoId: ObvCryptoId, newCustomDisplayName: String?) async throws
}


extension ObvSingleOwnedIdentityView {
    struct InternalView: View {
        
        let ownedCryptoId: ObvCryptoId
        let model: Model
        let dataSources: DataSources
        let actions: any ObvSingleOwnedIdentityViewActions
        let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
        fileprivate let internalActions: ObvSingleOwnedIdentityViewInternalActions
        
        @State private var isOlvidShopViewPresented: Bool = false
        @State private var isAtLeastOneUnhiddenProfileMustExistAlertPresented: Bool = false
        @State private var isHiddenProfilePasswordChooserPresented: Bool = false
        @State private var isUnhideProfileAlertPresented: Bool = false
        @State private var isEditMyNicknameAlertPresented: Bool = false
        @State private var nickname: String = ""
        @State private var isOwnedDetailedInfosViewPresented: Bool = false
        
        private func userWantsToSeeSubscriptionPlansAction() {
            isOlvidShopViewPresented = true
        }
        
        func userWantsToHideThisOwnedIdentity() {
            
            guard !model.isHidden else { assertionFailure(); return }
            
            switch model.numberOfOtherNonHiddenOwnedIdentities {
            case 0:
                isAtLeastOneUnhiddenProfileMustExistAlertPresented = true
                return
            default:
                isHiddenProfilePasswordChooserPresented = true
                return
            }
            
        }

        private func userWantsToUnhideThisOwnedIdentityButNeedsToConfirm() {
            guard model.isHidden else { assertionFailure(); return }
            isUnhideProfileAlertPresented = true
        }
        
        @State private var shownHUDCategory: HUDView.Category? = nil

        private func userWantsToUnhideThisOwnedIdentityAndHasConfirmed() {
            Task {
                do {
                    try await internalActions.userWantsToUnhideOwnedIdentity(ownedCryptoId: ownedCryptoId)
                    shownHUDCategory = .icon(.eye)
                } catch {
                    shownHUDCategory = .xmark
                }
                try? await Task.sleep(seconds: 1)
                shownHUDCategory = nil
            }
        }
        
        private func userWantsToSeeOwnedIdentityDetails() {
            isOwnedDetailedInfosViewPresented = true
        }
        
        private func showAlertForEditingCustomDisplayName() {
            self.nickname = model.customDisplayName ?? ""
            isEditMyNicknameAlertPresented = true
        }
        
        private func userConfirmedTheNewDisplayName() {
            let nickname = self.nickname.trimmingWhitespacesAndNewlines().mapToNilIfZeroLength()
            guard nickname != model.customDisplayName else { assertionFailure(); return }
            Task {
                try await internalActions.userWantsToUpdateOwnedCustomDisplayName(
                    ownedCryptoId: ownedCryptoId,
                    newCustomDisplayName: nickname)
            }
        }
        
        private var nickameIsDifferentFromCurrentOne: Bool {
            self.nickname.trimmingWhitespacesAndNewlines().mapToNilIfZeroLength() != model.customDisplayName
        }
        
        private func userTappedDeleteProfileInTheMenu() {
            internalActions.userWantsToDeleteOwnedIdentityButHasNotConfirmedYet(ownedCryptoId: ownedCryptoId)
        }
        
        private var systemIconForMenuLabel: SystemIcon {
            if #available(iOS 26, *) {
                return .ellipsis
            } else {
                return .ellipsisCircle
            }
        }
        
        @Namespace private var namespace
        private static let hiddenProfilePasswordChooserViewTransitionID = "ObvSingleOwnedIdentity.ObvSingleOwnedIdentityView.HiddenProfilePasswordChooserView"
        private static let ownedDetailedInfosViewTransitionID = "ObvSingleOwnedIdentity.ObvSingleOwnedIdentityView.ObvOwnedDetailedInfosView"
        private static let olvidShopViewTransitionID = "ObvSingleOwnedIdentity.ObvSingleOwnedIdentityView.ObvSubscription.OlvidShopView"

        var body: some View {
            ZStack {
                ScrollView(.vertical) {
                    VStack {
                        
                        // Header
                        
                        HeaderView(viewModel: model, avatarViewDataSource: dataSources.avatarViewDataSource)
                        
                        // EditProfileButton
                        
                        EditProfileButton(action: internalActions.userTappedEditProfileButton)
                            .padding()
                        
                        if model.isActive {
                            
                            // Owned devices (when profile is active on this device)
                            
                            OwnedDevicesCardView(
                                numberOfOwnedDevices: model.numberOfOwnedDevices,
                                userWantsToNavigateToListOfOwnedDevices: internalActions.userWantsToNavigateToListOfOwnedDevices,
                                userWantsToNavigateToViewAllowingToAddNewDevice: internalActions.userWantsToNavigateToViewAllowingToAddNewDevice)
                            .padding()
                            
                        } else {
                            
                            // View when profile is inactive on this device
                            
                            InactiveOwnedIdentityView(
                                ownedCryptoId: ownedCryptoId,
                                chooseDeviceToReactivateViewDataSource: dataSources.chooseDeviceToReactivateViewDataSource,
                                actions: actions,
                                uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet)
                            .padding()
                            
                        }
                        
                        // Subscription
                        
                        NewSubscriptionStatusView(
                            title: Text("SUBSCRIPTION_STATUS"),
                            apiKeyStatus: model.apiKeyElements.status,
                            apiKeyExpirationDate: model.apiKeyElements.expirationDate,
                            userWantsToSeeSubscriptionPlansAction: userWantsToSeeSubscriptionPlansAction,
                            refreshStatusAction: internalActions.userWantsToRefreshSubscriptionStatus,
                            apiPermissions: model.apiKeyElements.permissions,
                            transitionID: Self.olvidShopViewTransitionID)
                        .padding()
                        
                    }
                    .padding(.bottom)
                }
                if let shownHUDCategory {
                    HUDView(category: shownHUDCategory)
                }
            }
            .background(Color(UIColor.systemGroupedBackground))
            .alert(
                String(localizedInThisBundle: "AT_LEAST_ONE_UNHIDDEN_PROFILE_MUST_EXIST_TITLE"),
                isPresented: $isAtLeastOneUnhiddenProfileMustExistAlertPresented,
                actions: {
                    Button(action: internalActions.userWantsToAddOwnedProfile) { Text("ADD_OWNED_IDENTITY") }
                    Button(action: {}) { Text("OK") }
                }, message: {
                    Text("AT_LEAST_ONE_UNHIDDEN_PROFILE_MUST_EXIST_MESSAGE")
                })
            .alert(
                String(localizedInThisBundle: "UNHIDE_OWNED_IDENTITY_ALERT_TITLE"),
                isPresented: $isUnhideProfileAlertPresented,
                actions: {
                    Button(action: { isUnhideProfileAlertPresented = false }) {
                        Text("UNHIDE_OWNED_IDENTITY_ALERT_ACTION_STAY_HIDDEN")
                    }
                    Button(action: userWantsToUnhideThisOwnedIdentityAndHasConfirmed) { Text("UNHIDE_OWNED_IDENTITY_ALERT_ACTION_UNHIDE")
                    }
                }, message: {
                    Text("UNHIDE_OWNED_IDENTITY_ALERT_MESSAGE")
                }
            )
            .alert(
                String(localizedInThisBundle: "ALERT_FOR_EDITING_NICKNAME_TITLE"),
                isPresented: $isEditMyNicknameAlertPresented,
                actions: {
                    TextField(String(localizedInThisBundle: "FORM_NICKNAME"), text: $nickname)
                    Button(action: { isEditMyNicknameAlertPresented = false }) { Text("CANCEL") }
                    Button(action: userConfirmedTheNewDisplayName) { Text("SAVE") }
                        .disabled(!nickameIsDifferentFromCurrentOne)
                }, message: {
                    Text("ALERT_FOR_EDITING_NICKNAME_MESSAGE")
                }
            )
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        if model.isHidden {
                            Button(action: userWantsToUnhideThisOwnedIdentityButNeedsToConfirm) {
                                Label { Text("UNHIDE_THIS_IDENTITY") } icon: { Image(systemIcon: .eye) }
                            }
                        } else {
                            Button(action: userWantsToHideThisOwnedIdentity) {
                                Label { Text("HIDE_THIS_IDENTITY") } icon: { Image(systemIcon: .eyeSlash) }
                            }
                        }
                        Button(action: userWantsToSeeOwnedIdentityDetails) {
                            Label { Text("SHOW_OWNED_IDENTITY_DETAILS") } icon: { Image(systemIcon: .personCropCircleBadgeQuestionmark) }
                        }
                        Button(action: showAlertForEditingCustomDisplayName) {
                            Label { Text("EDIT_OWNED_IDENTITY_NICKNAME") } icon: { Image(systemIcon: .ellipsisRectangle) }
                        }
                        Button(action: userTappedDeleteProfileInTheMenu) {
                            Label { Text("DELETE_THIS_PROFILE").foregroundStyle(.red) } icon: { Image(systemIcon: .trash).tint(.red) }
                        }
                    } label: {
                        Image(systemIcon: systemIconForMenuLabel)
                    }
                    .matchedTransitionSourceOnIOS18(id: Self.hiddenProfilePasswordChooserViewTransitionID, in: namespace)
                    .matchedTransitionSourceOnIOS18(id: Self.ownedDetailedInfosViewTransitionID, in: namespace)
                }
            }
            .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isHiddenProfilePasswordChooserPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
                HiddenProfilePasswordChooserView(
                    ownedCryptoId: ownedCryptoId,
                    navigation: self,
                    actions: actions)
                    .navigationZoomTransitionOnIOS18(id: Self.hiddenProfilePasswordChooserViewTransitionID, in: namespace)
            }
            .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isOwnedDetailedInfosViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
                ObvOwnedDetailedInfosView(ownedCryptoId: ownedCryptoId,
                                          dataSources: dataSources.ownedDetailedInfosViewDataSources,
                                          navigation: self)
                .navigationZoomTransitionOnIOS18(id: Self.ownedDetailedInfosViewTransitionID, in: namespace)
            }
            .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isOlvidShopViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
                OlvidShopView(dataSources: dataSources.olvidShopViewDataSources,
                              navigation: self,
                              actions: actions)
                .navigationZoomTransitionOnIOS18(id: Self.olvidShopViewTransitionID, in: namespace)
            }

        }
    }
    
}


extension ObvSingleOwnedIdentityView.InternalView: ObvOwnedDetailedInfosViewNavigation {
    
    func ownedDetailedInfosViewShouldBeDismissed(_ view: ObvOwnedDetailedInfosView) {
        isOwnedDetailedInfosViewPresented = false
    }
    
}


extension ObvSingleOwnedIdentityView.InternalView: HiddenProfilePasswordChooserViewNavigation {
    
    func hiddenProfilePasswordChooserViewShouldBeDismissed(_ view: HiddenProfilePasswordChooserView) {
        isHiddenProfilePasswordChooserPresented = false
    }
    
}


extension ObvSingleOwnedIdentityView.InternalView: OlvidShopViewNavigation {
    
    func userWantsToDismissPresentedOlvidShopView(_ view: ObvSubscription.OlvidShopView) {
        isOlvidShopViewPresented = false
    }
    
}



// MARK: - Internal view

@MainActor
public protocol InactiveOwnedIdentityViewActions: ObvChooseDeviceToReactivateViewActions {}

private struct InactiveOwnedIdentityView: View {
    
    let ownedCryptoId: ObvCryptoId
    let chooseDeviceToReactivateViewDataSource: any ObvChooseDeviceToReactivateViewDataSource
    let actions: InactiveOwnedIdentityViewActions
    let uiKitDelegateForSwiftUISheet: any UIKitDelegateForSwiftUISheet
    
    @State private var isObvChooseDeviceToReactivateViewPresented = false

    private func buttonTapped() {
        isObvChooseDeviceToReactivateViewPresented = true
    }
    
    var body: some View {
        ObvCardView {
            VStack(alignment: .leading) {
                Text("INACTIVE_PROFILE_EXPLANATION_ON_MY_PROFILE_VIEW")
                    .font(.body)
                    .foregroundStyle(.primary)
                OlvidButtonNew(action: buttonTapped) {
                    Label(title: { Text("REACTIVATE_PROFILE_BUTTON_TITLE") }, icon: { Image(systemIcon: .checkmarkCircleFill) })
                }
            }
        }
        .sheetBackedByUIKitViewControllerOnCatalyst(isPresented: $isObvChooseDeviceToReactivateViewPresented, uiKitDelegateForSwiftUISheet: uiKitDelegateForSwiftUISheet) {
            ObvChooseDeviceToReactivateView(ownedCryptoId: ownedCryptoId,
                                            dataSource: chooseDeviceToReactivateViewDataSource,
                                            actions: actions,
                                            navigation: self)
        }
    }
    
}

extension InactiveOwnedIdentityView: ObvChooseDeviceToReactivateViewNavigation {
    
    func userWantsToDismissObvChooseDeviceToReactivateView(_ view: ObvChooseDeviceToReactivateView) {
        isObvChooseDeviceToReactivateViewPresented = false
    }
    
}


// MARK: - Internal view

private struct OwnedDevicesCardView: View {
    
    let numberOfOwnedDevices: Int
    let userWantsToNavigateToListOfOwnedDevices: () -> Void
    let userWantsToNavigateToViewAllowingToAddNewDevice: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            
            Text("MY_DEVICES")
                .font(.headline)
                .foregroundStyle(.primary)
            
            ObvCardView(padding: 0) {
                VStack {
                    
                    Button(action: userWantsToNavigateToListOfOwnedDevices) {

                        HStack(alignment: .firstTextBaseline) {
                            Image(systemIcon: .laptopcomputerAndIphone)
                                .foregroundStyle(Color(.tintColor))
                                .font(.system(size: 22))
                                .frame(width: 40)

                            Text("YOU_HAVE_\(numberOfOwnedDevices)_DEVICES")
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(.primary)
                            
                            Spacer()

                            ObvChevronRight()
                            
                        }
                        .contentShape(Rectangle()) // Trcik that makes it possible to have an "on tap" gesture that also works when the Spacer is tapped

                    }
                    .buttonStyle(.plain)
                    .padding([.horizontal, .top])

                    Divider()
                        .padding(.leading, 62)

                    Button(action: userWantsToNavigateToViewAllowingToAddNewDevice) {
                        
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemIcon: .plusCircle)
                                .foregroundStyle(Color(.tintColor))
                                .font(.system(size: 22))
                                .frame(width: 40)

                            Text("ADD_A_NEW_DEVICE")
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                                .font(.system(.headline, design: .rounded))
                                .foregroundStyle(.primary)
                            
                            Spacer()

                            ObvChevronRight()
                            
                        }
                        .contentShape(Rectangle()) // Trcik that makes it possible to have an "on tap" gesture that also works when the Spacer is tapped

                    }
                    .buttonStyle(.plain)
                    .padding([.horizontal, .bottom])

                }
            }
        }
    }
    
}


// MARK: - Internal view

private struct EditProfileButton: View {
    
    let action: () -> Void
    
    var body: some View {
        OlvidButtonNew(action: action, style: .glassOrBorderedProminent) {
            Label(title: { Text("EDIT_MY_ID") }, icon: { Image(systemIcon: .squareAndPencil) })
        }
    }
}


// MARK: - Internal view

private struct HeaderView: View {
    
    let viewModel: ObvSingleOwnedIdentityView.Model
    let avatarViewDataSource: ObvAvatarViewDataSource

    private var headerTitle: String {
        return viewModel.customDisplayName ?? viewModel.identityDetails.getDisplayNameWithStyle(.firstNameThenLastName)
    }
    
    private var headerSubtitle: String? {
        if viewModel.customDisplayName == nil {
            return viewModel.identityDetails.coreDetails.positionAtCompany()
        } else {
            return viewModel.identityDetails.getDisplayNameWithStyle(.firstNameThenLastName)
        }
    }

    private var headerSubSubtitle: String? {
        if viewModel.customDisplayName == nil {
            return nil
        } else {
            return viewModel.identityDetails.getDisplayNameWithStyle(.positionAtCompany)
        }
    }

    var body: some View {
        VStack {
            ObvAvatarView(model: viewModel.avatarModel,
                          style: .circle,
                          size: .xLarge,
                          dataSource: avatarViewDataSource,
                          showGreenShieldIfAppropriate: true)
            Text(headerTitle)
                .font(.system(.title, design: .rounded))
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            if let headerSubtitle {
                Text(headerSubtitle)
                    .font(.system(.title2, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let headerSubSubtitle {
                Text(headerSubSubtitle)
                    .font(.system(.title3, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
}


#if DEBUG

@MainActor
private final class DataSourceAndActionsForPreviews {
    
    /// From NewStoreKitConfiguration.storekit. Don't forget to set it in the target configuration during testing.
    static let productIDs: [Product.ID] = [
        "io.olvid.premium_2020_monthly",
        "io.olvid.subscription.family.monthly",
        "io.olvid.subscription.individual.yearly",
        "io.olvid.subscription.family.yearly",
    ]

    @Published var currentActiveSubscriptionsPublisher: Product?
    
}

extension DataSourceAndActionsForPreviews: ObvSingleOwnedIdentityViewDataSource {
    
    func getAsyncSequenceOfObvSingleOwnedIdentityViewModel(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<ObvSingleOwnedIdentityView.ModelOrDeleted>) {
        let stream = AsyncStream<ObvSingleOwnedIdentityView.ModelOrDeleted> { (continuation: AsyncStream<ObvSingleOwnedIdentityView.ModelOrDeleted>.Continuation) in
            Task {
                let model: ObvSingleOwnedIdentityView.Model = .sampleData
                continuation.yield(.model(model))
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfObvSingleOwnedIdentityViewModel(_ view: ObvSingleOwnedIdentityView, streamUUID: UUID) {}
    
}

extension DataSourceAndActionsForPreviews: ObvAvatarViewDataSource {
    
    func fetchAvatar(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) async throws -> UIImage? {
        return nil
    }
    
    func fetchAvatarFromCache(_ view: ObvDesignSystem.ObvAvatarView, photoURL: URL, avatarSize: ObvDesignSystem.ObvAvatarSize) -> UIImage? {
        return nil
    }
    
}

extension DataSourceAndActionsForPreviews: ObvChooseDeviceToReactivateViewActions {
    
    func userWantsToActivateCurrentDevice(_ view: ObvChooseDeviceToReactivateView, ownedCryptoId: ObvTypes.ObvCryptoId, currentDeviceIdentifier: Data, deviceIdentifierOfOtherDeviceToDeactivate: Data?) async throws {
        print("User wants to activate current device")
    }
    
}

extension DataSourceAndActionsForPreviews: OlvidShopViewActions {
    
    func refreshSubscriptionStatus() async throws {
        // Return immediately
    }
    
    
    func getCurrentActiveSubscriptionPublisher(_ view: OlvidShopView) throws -> Published<Product?>.Publisher {
        $currentActiveSubscriptionsPublisher
    }
    
    
    func userWantsToBuy(_ view: OlvidShopView, product: Product) async throws -> ObvAppTypes.StoreKitDelegatePurchaseResult {
        print("User wants to buy product")
        try? await Task.sleep(seconds: 3)
        return .purchaseSucceeded(serverVerificationResult: .succeededAndSubscriptionIsValid)
    }

}

extension DataSourceAndActionsForPreviews: HiddenProfilePasswordChooserViewActions {
    
    func userWantsToHideOwnedIdentity(_ view: HiddenProfilePasswordChooserView, ownedCryptoId: ObvTypes.ObvCryptoId, password: String) async throws {
        print("User wants to hide owned identity")
    }
    
    func userChosePasswordForHidingOwnedIdentity(_ view: HiddenProfilePasswordChooserView, ownedCryptoId: ObvTypes.ObvCryptoId, password: String) async throws {
        try await Task.sleep(seconds: 2)
        print("User chose password for hiding owned identity")
    }
    
}

extension DataSourceAndActionsForPreviews: ObvSingleOwnedIdentityViewActions {
    
    func userWantsToRefreshSubscriptionStatus(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId) async throws -> [StoreKitDelegatePurchaseResult] {
        print("User wants to refresh subscription status")
        return []
    }
    
    func userWantsToDeleteOwnedIdentityButHasNotConfirmedYet(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId) {
        print("User wants to delete owned identity but has not confirmed yet")
    }
    
    func userWantsToAddOwnedProfile(_ view: ObvSingleOwnedIdentityView) {
        print("User wants to add owned profile")
    }
    
    func userWantsToUnhideOwnedIdentity(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId) async throws {
        print("User wants to unhide owned identity")
    }
    
    func userWantsToUpdateOwnedCustomDisplayName(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvCryptoId, newCustomDisplayName: String?) async throws {
        print("User wants to update owned custom display name \(String(describing: newCustomDisplayName))")
    }
    
}

extension DataSourceAndActionsForPreviews: ObvSingleOwnedIdentityViewNavigation {
    
    func userWantsToSeeSubscriptionPlans(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        print("User wants to see subscription plans")
    }
    
    func userWantsToEditOwnedProfile(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        print("User wants to edit owned profile")
    }
    
    func userWantsToNavigateToListOfOwnedDevices(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        print("User wants to navigate to list of owned devices")
    }
    
    func userWantsToNavigateToViewAllowingToAddNewDevice(_ view: ObvSingleOwnedIdentityView, ownedCryptoId: ObvTypes.ObvCryptoId) {
        print("User wants to navigate to view allowing to add new device")
    }
    
}

extension DataSourceAndActionsForPreviews: ObvChooseDeviceToReactivateViewDataSource {
    
    func getObvChooseDeviceToReactivateViewModel(_ view: ObvChooseDeviceToReactivateView, ownedCryptoId: ObvCryptoId) async throws -> ObvChooseDeviceToReactivateView.Model {
        try? await Task.sleep(seconds: 1)
        return .init(currentDeviceName: "My current device name",
                     currentDeviceIdentifier: Data(repeating: 0x88, count: 16))
    }
    
    func performOwnedDeviceDiscoveryNow(_ view: ObvChooseDeviceToReactivateView, ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> ObvTypes.ObvOwnedDeviceDiscoveryResult {
        try? await Task.sleep(seconds: 1)
        let otherDevice1 = ObvOwnedDeviceDiscoveryResult.Device(
            identifier:  Data(repeating: 0x89, count: 16),
            expirationDate: nil,
            latestRegistrationDate: .now.addingTimeInterval(-.init(days: 1)),
            name: "Other device 1")
        let otherDevice2 = ObvOwnedDeviceDiscoveryResult.Device(
            identifier:  Data(repeating: 0x90, count: 16),
            expirationDate: nil,
            latestRegistrationDate: .now.addingTimeInterval(-.init(days: 2)),
            name: "Other device 2")
        return .init(devices: Set([otherDevice1, otherDevice2]),
                     isMultidevice: false)
    }
    
}

extension DataSourceAndActionsForPreviews: OlvidShopViewDataSource {
    
    func getAsyncSequenceOfOlvidShopViewModel(_ view: OlvidShopView) throws -> (streamUUID: UUID, stream: AsyncStream<OlvidShopView.Model>) {
        let stream = AsyncStream<OlvidShopView.Model> { (continuation: AsyncStream<OlvidShopView.Model>.Continuation) in
            Task {
                try? await Task.sleep(seconds: 0)
                let model: OlvidShopView.Model = .init(productIDs: Self.productIDs)
                continuation.yield(model)
            }
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfOlvidShopViewModel(_ view: OlvidShopView, streamUUID: UUID) {}
    
}

extension DataSourceAndActionsForPreviews: ObvOwnedDetailedInfosViewDataSource {
    
    func getAsyncSequenceOfObvOwnedDetailedInfosViewModel(_ view: ObvOwnedDetailedInfosView, ownedCryptoId: ObvTypes.ObvCryptoId) throws -> (streamUUID: UUID, stream: AsyncStream<ObvOwnedDetailedInfosView.Model>) {
        let stream = AsyncStream<ObvOwnedDetailedInfosView.Model> { (continuation: AsyncStream<ObvOwnedDetailedInfosView.Model>.Continuation) in
            // We don't stream this model in previews for now
        }
        return (UUID(), stream)
    }
    
    func finishAsyncSequenceOfObvOwnedDetailedInfosViewModel(_ view: ObvOwnedDetailedInfosView, streamUUID: UUID) {}
    
}

extension DataSourceAndActionsForPreviews: UIKitDelegateForSwiftUISheet {
    func userWantsToPresentView<Content>(_ view: some View, content: @escaping () -> Content) async where Content : View {
        // We don't implement this method. Consequently certain views cannot be presented when showing previews on catalyst.
    }
    func userWantsToDismissPresentedView(_ view: some View) async {}
}

@MainActor
private let dataSourceAndActionsForPreviews = DataSourceAndActionsForPreviews()

#Preview {
    NavigationStack {
        ObvSingleOwnedIdentityView(
            ownedCryptoId: .sampleOwnedCryptoId,
            dataSources: .init(dataSource: dataSourceAndActionsForPreviews,
                               avatarViewDataSource: dataSourceAndActionsForPreviews,
                               chooseDeviceToReactivateViewDataSource: dataSourceAndActionsForPreviews,
                               olvidShopViewDataSources: .init(dataSource: dataSourceAndActionsForPreviews),
                               ownedDetailedInfosViewDataSources: .init(dataSource: dataSourceAndActionsForPreviews,
                                                                        avatarViewDataSource: dataSourceAndActionsForPreviews)),
            actions: dataSourceAndActionsForPreviews,
            navigation: dataSourceAndActionsForPreviews,
            uiKitDelegateForSwiftUISheet: dataSourceAndActionsForPreviews)
    }
}

#endif
