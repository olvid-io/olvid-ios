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
import ObvTypes
import ObvEngine
import ObvUI
import ObvDesignSystem


public final class UserTriesToAccessPaidFeatureHostingController: UIHostingController<UserTriesToAccessPaidFeatureView> {
    
    public init(requestedPermission: APIPermissions,
                ownedCryptoId: ObvCryptoId,
                actions: any UserTriesToAccessPaidFeatureViewActions,
                navigation: any UserTriesToAccessPaidFeatureViewNavigation) {
        let rootView = UserTriesToAccessPaidFeatureView(
            requestedPermission: requestedPermission,
            ownedCryptoId: ownedCryptoId,
            actions: actions,
            navigation: navigation)
        super.init(rootView: rootView)
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


@MainActor
public protocol UserTriesToAccessPaidFeatureViewNavigation {
    func userWantsToNavigateToTheMyProfilePage(_ view: UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvCryptoId)
    func userTriesToAccessPaidFeatureViewShouldBeDismissed(_ view: UserTriesToAccessPaidFeatureView)
}


@MainActor
public protocol UserTriesToAccessPaidFeatureViewActions {
    func queryServerForFreeTrial(_ view: UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvCryptoId) async throws -> Bool
    func startFreeTrial(_ view: UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvCryptoId) async throws
    func userWantsToChooseUserToCall(_ view: UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvCryptoId)
}


/// A view displayed when a user attempts to initiate a call but lacks an active subscription.
///
/// This view informs the user that calling functionality is restricted to subscribers and provides a clear call-to-action to navigate to the **"My Profile"** page.
/// On the **"My Profile"** page, users can review their subscription status and, if necessary, upgrade to enable calling features.
///
/// - Note: This view is typically presented when the user taps the **"Call"** button on a single contact sheet while unsubscribed.
public struct UserTriesToAccessPaidFeatureView: View {
    
    /// This is the permission required for the feature the user requested but for which she has no permission
    let requestedPermission: APIPermissions
    let ownedCryptoId: ObvCryptoId
    let actions: any UserTriesToAccessPaidFeatureViewActions
    let navigation: any UserTriesToAccessPaidFeatureViewNavigation
    
    func textForPermission(_ permission: APIPermissions) -> String {
        switch permission {
        case .canCall:
            return String(localizedInThisBundle: "MESSAGE_SUBSCRIPTION_REQUIRED_CALL")
        case .multidevice:
            return String(localizedInThisBundle: "MESSAGE_SUBSCRIPTION_REQUIRED_GENERIC")
        default:
            return String(localizedInThisBundle: "MESSAGE_SUBSCRIPTION_REQUIRED_GENERIC")
        }
    }
    
    private func buttonTapped() {
        navigation.userWantsToNavigateToTheMyProfilePage(self, ownedCryptoId: ownedCryptoId)
    }
    
    private func closeButtonTapped() {
        navigation.userTriesToAccessPaidFeatureViewShouldBeDismissed(self)
    }
    
    private var navigationTitle: String {
        String(localizedInThisBundle: "SUBSCRIPTION_REQUIRED")
    }
    
    private enum StateOfQueryingServerForFreeTrial: Equatable {
        case noQuerying
        case querying
        case resultReceived(canActivateFreeTrial: Bool)
        case freeTrialActivated
    }
    
    @State private var isQueryingServerForFreeTrial: StateOfQueryingServerForFreeTrial = .noQuerying
    
    /// Makes request to determine if the user still can activate their free trial.
    /// Since the free trial only concerns calls, we restrict to that permission
    private func onTask() async {
        guard requestedPermission == .canCall else { return }
        withAnimation { isQueryingServerForFreeTrial = .querying }
        defer {
            switch isQueryingServerForFreeTrial {
            case .querying, .noQuerying:
                withAnimation { isQueryingServerForFreeTrial = .noQuerying }
            case .resultReceived, .freeTrialActivated:
                break
            }
        }
        do {
            let canActivateFreeTrial = try await actions.queryServerForFreeTrial(self, ownedCryptoId: ownedCryptoId)
            withAnimation { isQueryingServerForFreeTrial = .resultReceived(canActivateFreeTrial: canActivateFreeTrial) }
        } catch {
            assertionFailure()
        }
    }
    
    @State private var isStartingFreeTrial: Bool = false
    
    private var isInterfaceDisabled: Bool {
        isStartingFreeTrial
    }
    
    private func userTappedMakeCallNow() {
        actions.userWantsToChooseUserToCall(self, ownedCryptoId: ownedCryptoId)
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ObvCardView {
                        VStack {
                            HStack {
                                Text(textForPermission(requestedPermission))
                                    .font(.body)
                                Spacer(minLength: 0)
                            }.padding(.bottom)
                            OlvidButtonNew(action: buttonTapped) {
                                Label(title: { Text("BUTTON_LABEL_CHECK_SUBSCRIPTION") }, icon: { Image(systemIcon: .eyesInverse) })
                            }
                        }
                    }
                    .padding(.bottom)
                    
                    // Free trial button
                    
                    switch isQueryingServerForFreeTrial {
                    case .noQuerying, .querying:
                        EmptyView()
                    case .resultReceived(canActivateFreeTrial: let canActivateFreeTrial):
                        if canActivateFreeTrial {
                            FreeTrialButtonView(isStartingFreeTrial: $isStartingFreeTrial,
                                                actions: self)
                        }
                    case .freeTrialActivated:
                        ObvCardView {
                            VStack {
                                HStack {
                                    Text("START_FREE_TRIAL_ACTIVATED_EXPLANATION")
                                    Spacer(minLength: 0)
                                }
                                OlvidButtonNew(action: userTappedMakeCallNow) {
                                    Label(title: { Text("BUTTON_TITLE_CALL_NOW") }, icon: { Image(systemIcon: .phone) })
                                }
                            }
                        }
                    }
                    

                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top)
            }
            .disabled(isInterfaceDisabled)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .background(Color(AppTheme.shared.colorScheme.systemBackground))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    ObvButtonWithCancelRole(action: closeButtonTapped)
                }
                if isQueryingServerForFreeTrial == .querying {
                    ToolbarItem {
                        ProgressView().progressViewStyle(.circular)
                    }
                }
            }
        }
        .task(onTask)
    }
}


extension UserTriesToAccessPaidFeatureView: InternalActions {
    
    fileprivate func startFreeTrial(_ view: FreeTrialButtonView) async throws {
        try await actions.startFreeTrial(self, ownedCryptoId: ownedCryptoId)
        withAnimation { isQueryingServerForFreeTrial = .freeTrialActivated }
    }
    
}


@MainActor
private protocol InternalActions {
    func startFreeTrial(_ view: FreeTrialButtonView) async throws
}

/// View shown only if the engine indicates that the user can activate a free trial.
private struct FreeTrialButtonView: View {
    
    @Binding var isStartingFreeTrial: Bool
    let actions: InternalActions
    
    private func buttonTapped() {
        withAnimation { isStartingFreeTrial = true }
        Task {
            defer { isStartingFreeTrial = false }
            try await actions.startFreeTrial(self)
        }
    }
    
    var body: some View {
        ObvCardView {
            VStack {
                HStack {
                    Text("START_FREE_TRIAL_EXPLANATION")
                    Spacer(minLength: 0)
                    
                }.padding(.bottom)
                OlvidButtonNew(action: buttonTapped) {
                    HStack {
                        if isStartingFreeTrial {
                            ProgressView().progressViewStyle(.circular)
                        }
                        Label(title: { Text("BUTTON_TITLE_START_FREE_TRIAL") }, icon: { Image(systemIcon: .giftcardFill) })
                    }
                }
                .disabled(isStartingFreeTrial)
            }
        }
    }
    
}



// MARK: - Previews

#if DEBUG

extension ObvCryptoId {
    @MainActor
    static let sampleOwnedCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
}

@MainActor
private final class NavigationForPreviews {}

extension NavigationForPreviews: UserTriesToAccessPaidFeatureViewNavigation {
    
    func userWantsToNavigateToTheMyProfilePage(_ view: UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvCryptoId) {
        print("User wants to navigate to the My Profile Page")
    }
    
    func userTriesToAccessPaidFeatureViewShouldBeDismissed(_ view: UserTriesToAccessPaidFeatureView) {
        print("View should be dismissed")
    }
    
}

extension NavigationForPreviews: UserTriesToAccessPaidFeatureViewActions {
    
    func userWantsToChooseUserToCall(_ view: UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvTypes.ObvCryptoId) {}
        
    func queryServerForFreeTrial(_ view: UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvCryptoId) async throws -> Bool {
        try? await Task.sleep(seconds: 0)
        return true
    }
    
    func startFreeTrial(_ view: UserTriesToAccessPaidFeatureView, ownedCryptoId: ObvCryptoId) async throws {
        try? await Task.sleep(for: 1)
    }
    
}

@MainActor
private let navigationForPreviews = NavigationForPreviews()

#Preview("For calls") {
    UserTriesToAccessPaidFeatureView(
        requestedPermission: .canCall,
        ownedCryptoId: .sampleOwnedCryptoId,
        actions: navigationForPreviews,
        navigation: navigationForPreviews)
}

#Preview("For multidevice") {
    UserTriesToAccessPaidFeatureView(
        requestedPermission: .multidevice,
        ownedCryptoId: .sampleOwnedCryptoId,
        actions: navigationForPreviews,
        navigation: navigationForPreviews)
}

#endif
