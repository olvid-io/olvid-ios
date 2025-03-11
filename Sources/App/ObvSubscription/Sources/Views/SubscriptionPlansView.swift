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
import StoreKit
import ObvTypes
import ObvSystemIcon
import ObvUI
import ObvAppCoreConstants



public struct SubscriptionPlansView<Model: SubscriptionPlansViewModelProtocol>: View, NewSKProductCardViewActionsProtocol, BottomButtonsViewActionsProtocol {
    
    @ObservedObject var model: Model
    let actions: SubscriptionPlansViewActionsProtocol
    let dismissActions: SubscriptionPlansViewDismissActionsProtocol
    
    // Avoid calling the method twice
    @State private var isFetchSubscriptionPlansCalled = false
    @State private var shownHUDCategory: HUDView.Category? = nil
    @State private var isInterfaceDisabled = false
    @State private var fetchErrorShown: Error?
    @State private var buyErrorShown: BuyError?
    
    public init(model: Model, actions: SubscriptionPlansViewActionsProtocol, dismissActions: SubscriptionPlansViewDismissActionsProtocol) {
        self.model = model
        self.actions = actions
        self.dismissActions = dismissActions
    }
    
    private var currentlyFetchingSubscriptionPlans: Bool {
        return model.freePlanIsAvailable != nil && model.products != nil
    }
    
    private var canShowPlans: Bool {
        model.freePlanIsAvailable != nil && model.products != nil
    }

    
    /// When the view appears, we immediately request our delegate to fetch subscriptions plans.
    /// When receiving the plans from our delegate, we set them in the model, and this will update the UI.
    private func viewDidAppear() {
        Task {
            do {
                let result = try await actions.fetchSubscriptionPlans(for: model.ownedCryptoId, alsoFetchFreePlan: model.showFreePlanIfAvailable)
                await model.setSubscriptionPlans(freePlanIsAvailable: result.freePlanIsAvailable, products: result.products)
            } catch {
                withAnimation {
                    fetchErrorShown = error
                }
            }
        }
    }
    
    
    private var featuresForFreeTrial: [NewFeatureView.Model] {[
        .init(feature: .startSecureCalls, showAsAvailable: true),
    ]}
    
    private var featuresForSKProduct: [NewFeatureView.Model] {[
        .init(feature: .startSecureCalls, showAsAvailable: true),
        .init(feature: .multidevice, showAsAvailable: true)
    ]}
    
    
    func dismissAction() {
        Task {
            await dismissActions.userWantsToDismissSubscriptionPlansView()
        }
    }
    
    
    // NewSKProductCardViewActionsProtocol
    
    func userWantsToStartFreeTrial() {
        isInterfaceDisabled = true
        withAnimation {
            shownHUDCategory = .progress
        }
        Task {
            do {
                // The following call returns APIKeyElements updated after a successful start of a free trial.
                // We discard them since we don't display this information here.
                _ = try await actions.userWantsToStartFreeTrialNow(ownedCryptoId: model.ownedCryptoId)
                await enableInterfaceAndShowHUD(category: .checkmark, duringTimeInterval: 1)
                await dismissActions.dismissSubscriptionPlansViewAfterPurchaseWasMade()
            } catch {
                assertionFailure()
                await enableInterfaceAndShowHUD(category: .xmark, duringTimeInterval: 1)
                buyErrorShown = BuyError.failedToStartFreeTrial
            }
        }
    }
    
    
    @MainActor
    private func setShownHUDCategory(category: HUDView.Category?) async {
        guard shownHUDCategory != category else { return }
        withAnimation {
            shownHUDCategory = category
        }
    }
    
    
    @MainActor
    private func enableInterface() async {
        guard isInterfaceDisabled else { return }
        withAnimation {
            isInterfaceDisabled = false
        }
    }
    
    
    @MainActor
    private func enableInterfaceAndShowHUD(category: HUDView.Category, duringTimeInterval: TimeInterval) async {
        await enableInterface()
        await setShownHUDCategory(category: category)
        try? await Task.sleep(seconds: duringTimeInterval)
        await setShownHUDCategory(category: nil)
    }
    
    
    func userWantsToBuy(_ product: Product) {
        isInterfaceDisabled = true
        shownHUDCategory = .progress
        buyErrorShown = nil
        Task {
            do {
                let result = try await actions.userWantsToBuy(product)
                switch result {
                case .purchaseSucceeded(let serverVerificationResult):
                    switch serverVerificationResult {
                    case .succeededAndSubscriptionIsValid:
                        await enableInterfaceAndShowHUD(category: .checkmark, duringTimeInterval: 1)
                        await dismissActions.dismissSubscriptionPlansViewAfterPurchaseWasMade()
                    case .succeededButSubscriptionIsExpired:
                        buyErrorShown = BuyError.buySucceededButSubscriptionIsExpired
                        await enableInterfaceAndShowHUD(category: .xmark, duringTimeInterval: 1)
                    case .failed:
                        buyErrorShown = BuyError.buyFailed
                        await enableInterfaceAndShowHUD(category: .xmark, duringTimeInterval: 1)
                    }
                case .userCancelled, .pending:
                    await enableInterface()
                    await setShownHUDCategory(category: nil)
                }
            } catch {
                if let error = error as? StoreKit.Product.PurchaseError {
                    switch error {
                    case .invalidQuantity:
                        buyErrorShown = .otherError(error: error)
                    case .productUnavailable:
                        buyErrorShown = .productUnavailable
                    case .purchaseNotAllowed:
                        buyErrorShown = .purchaseNotAllowed
                    case .ineligibleForOffer:
                        buyErrorShown = .otherError(error: error)
                    case .invalidOfferIdentifier:
                        buyErrorShown = .otherError(error: error)
                    case .invalidOfferPrice:
                        buyErrorShown = .otherError(error: error)
                    case .invalidOfferSignature:
                        buyErrorShown = .otherError(error: error)
                    case .missingOfferParameters:
                        buyErrorShown = .otherError(error: error)
                    @unknown default:
                        buyErrorShown = .otherError(error: error)
                    }
                } else {
                    buyErrorShown = .otherError(error: error)
                }
                await enableInterfaceAndShowHUD(category: .xmark, duringTimeInterval: 1)
            }
        }
    }
    
    
    private func dismissBuyErrorView() {
        withAnimation {
            buyErrorShown = nil
        }
    }
    
    // BottomButtonsViewActionsProtocol
    
    func userWantsToRestorePurchaseNow() {
        isInterfaceDisabled = true
        shownHUDCategory = .progress
        Task {
            do {
                try await actions.userWantsToRestorePurchases()
                await enableInterfaceAndShowHUD(category: .checkmark, duringTimeInterval: 1)
            } catch {
                await enableInterfaceAndShowHUD(category: .xmark, duringTimeInterval: 1)
                buyErrorShown = BuyError.couldNotRestorePurchases(error: error)
            }
        }
    }

    
    // View
    
    public var body: some View {
        NavigationView {
            
            ZStack {
                
                ScrollView {
                    VStack {
                        
                        // Make sure the VStack is nevery empty (otherwise, animations don't work)
                        EmptyView()
                        
                        if let fetchErrorShown {
                            
                            ErrorView(title: "WE_COULD_NOT_LOOK_FOR_AVAILABLE_SUBSCRIPTION_PLANS", error: fetchErrorShown, dismissAction: nil)
                                .padding(.bottom)
                                                    
                            BottomButtonsView(actions: self)
                            
                        } else if let freePlanIsAvailable = model.freePlanIsAvailable, let products = model.products {
                            
                            if let buyErrorShown {
                                
                                ErrorView(title: "THE_SUBSCRIPTION_REQUEST_FAILED", error: buyErrorShown, dismissAction: dismissBuyErrorView)
                                    .padding(.bottom)
                                
                            } else {
                                
                                if freePlanIsAvailable && model.showFreePlanIfAvailable {
                                    NewSKProductCardView(model: .init(title: String(localizedInThisBundle: "TRY_SECURE_CALLS"),
                                                                      price: String(localizedInThisBundle: "Free"),
                                                                      description: String(localizedInThisBundle: "TRY_SECURE_CALLS_DESCRIPTION"),
                                                                      buttonTitle: String(localizedInThisBundle: "Start free trial now"),
                                                                      buttonSystemIcon: .handThumbsupFill,
                                                                      features: featuresForFreeTrial),
                                                         actions: self)
                                    .transition(AnyTransition.move(edge: .trailing))
                                    .padding(.bottom, 32)
                                }
                                
                                ForEach(products, id: \.self) { product in
                                    NewSKProductCardView(model: .init(product: product,
                                                                      features: featuresForSKProduct,
                                                                      buttonTitle: String(localizedInThisBundle: "Subscribe now"),
                                                                      buttonSystemIcon: .cartFill),
                                                         actions: self)
                                    .transition(AnyTransition.move(edge: .leading))
                                    .padding(.bottom, 32)
                                }
                                
                            }
                                                        
                            BottomButtonsView(actions: self)
                            
                        } else {
                            
                            HStack {
                                Spacer()
                                ProgressView {
                                    Text("Looking for available subscription plans")
                                }
                                Spacer()
                            }.padding(.top, 64)
                            
                        }
                        
                    }
                    .padding()
                }
                .disabled(isInterfaceDisabled)
                .navigationBarTitle(Text("Available subscription plans"), displayMode: .inline)
                .toolbar {
                    ToolbarItemGroup {
                        Button.init(action: dismissAction, label: {
                            Image(systemIcon: .xmarkCircleFill)
                        })
                    }
                }
                .onAppear(perform: viewDidAppear)
                
                if let shownHUDCategory {
                    HUDView(category: shownHUDCategory)
                        .zIndex(1)
                }
                
            }
        }
    }
    
}


// MARK: ErrorView

private struct ErrorView: View {
    
    let title: LocalizedStringKey
    let error: Error
    let dismissAction: (() -> Void)?
    
    var body: some View {
        ObvCardView {
            VStack {
                HStack {
                    Label {
                        VStack(alignment: .leading) {
                            Text(title)
                                .foregroundStyle(.primary)
                            Text(verbatim: (error as? BuyError)?.localizedDescription ?? error.localizedDescription)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemIcon: .xmarkCircleFill)
                            .foregroundStyle(Color(UIColor.systemRed))
                            .font(.system(size: 36))
                    }
                    Spacer()
                }
                if let dismissAction {
                    OlvidButton(style: .blue, title: Text("Dismiss"), action: dismissAction)
                }
            }
        }
    }
    
}




// MARK: BottomButtonsView

protocol BottomButtonsViewActionsProtocol {
    func userWantsToRestorePurchaseNow()
}

private struct BottomButtonsView: View {
    
    let actions: BottomButtonsViewActionsProtocol
    
    var body: some View {
        VStack(spacing: 16) {
            
            OlvidButton(style: .standardWithBlueText,
                        title: Text("Manage your subscription"),
                        systemIcon: .link,
                        action: {
                            let url = ObvAppCoreConstants.urlForManagingSubscriptionWithTheAppStore
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        })
            
            OlvidButton(style: .standardWithBlueText,
                        title: Text("Manage payments"),
                        systemIcon: .creditcardFill,
                        action: {
                            let url = ObvAppCoreConstants.urlForManagingPaymentsOnTheAppStore
                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                        })
            
            OlvidButton(style: .standardWithBlueText,
                        title: Text("Restore Purchases"),
                        systemIcon: .arrowUturnForwardCircleFill,
                        action: actions.userWantsToRestorePurchaseNow)

        }
    }
    
}



// MARK: NewSKProductCardView

protocol NewSKProductCardViewActionsProtocol {
    func userWantsToStartFreeTrial()
    func userWantsToBuy(_: Product)
}


private struct NewSKProductCardView: View {
    
    struct Model {
        let title: String
        let price: String
        let description: String
        let buttonTitle: String
        let buttonSystemIcon: SystemIcon?
        let features: [NewFeatureView.Model]
        let product: Product? // App Store product
        
        init(title: String, price: String, description: String, buttonTitle: String, buttonSystemIcon: SystemIcon?, features: [NewFeatureView.Model]) {
            self.title = title
            self.price = price
            self.description = description
            self.buttonTitle = buttonTitle
            self.buttonSystemIcon = buttonSystemIcon
            self.features = features
            self.product = nil
        }
        
        init(product: Product, features: [NewFeatureView.Model], buttonTitle: String, buttonSystemIcon: SystemIcon?) {
            let subscription = AvailableSubscription(productIdentifier: product.id)
            assert(subscription != nil)
            self.title = subscription?.localizedTitle ?? product.displayName
            if let subscription = product.subscription {
                self.price = "\(product.displayPrice)/\(subscription.subscriptionPeriod.unit)"
            } else {
                assertionFailure()
                self.price = "\(product.displayPrice)"
            }
            self.description = subscription?.localizedDescription ?? product.description
            self.buttonTitle = buttonTitle
            self.buttonSystemIcon = buttonSystemIcon
            self.features = features
            self.product = product
        }

        
    }
    
    let model: Model
    let actions: NewSKProductCardViewActionsProtocol
    
    
    private func buttonTapped() {
        if let product = model.product {
            actions.userWantsToBuy(product)
        } else {
            actions.userWantsToStartFreeTrial()
        }
    }
    
    
    var body: some View {
        ObvCardView {
            VStack(spacing: 16.0) {
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(model.title)
                        .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    Text(verbatim: model.price)
                        .fontWeight(.bold)
                        .font(.system(.title, design: .rounded))
                }
                HStack {
                    Text(model.description)
                        .font(.body)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(Color(UIColor.secondaryLabel))
                    Spacer()
                }
                .fixedSize(horizontal: false, vertical: true)
                NewFeatureListView(model: .init(title: "Premium features", features: model.features))
                OlvidButton(style: .blue,
                            title: Text(verbatim: model.buttonTitle),
                            systemIcon: model.buttonSystemIcon,
                            action: buttonTapped)
            }
        }
    }
    
}


// MARK: - NewFeatureListView

private struct NewFeatureListView: View {
    
    struct Model {
        let title: String
        let features: [NewFeatureView.Model]
    }
    
    let model: Model
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.title)
                    .font(.headline)
            }
            .padding(.bottom, 16)
            ForEach(model.features) { feature in
                NewFeatureView(model: feature)
                    .padding(.bottom, 16)
            }
        }
    }
    
}


// MARK: - FeatureView

private struct NewFeatureView: View {

    let model: Model
    
    
    struct Model: Identifiable {
        let feature: NewFeatureView.Feature
        let showAsAvailable: Bool
        var id: Int { self.feature.rawValue }
    }
    
    
    enum Feature: Int, Identifiable {
        case startSecureCalls = 0
        case multidevice
        case sendAndReceiveMessagesAndAttachments
        case createGroupChats
        case receiveSecureCalls
        var id: Int { self.rawValue }
    }
    
    
    private var systemIcon: SystemIcon {
        switch model.feature {
        case .startSecureCalls: return .phoneArrowUpRightFill
        case .multidevice: return .macbookAndIphone
        case .sendAndReceiveMessagesAndAttachments: return .bubbleLeftAndBubbleRightFill
        case .createGroupChats: return .person3Fill
        case .receiveSecureCalls: return .phoneArrowDownLeftFill
        }
    }
    
    
    private var systemIconColor: Color {
        switch model.feature {
        case .startSecureCalls: return Color(.displayP3, red: 253.0/255, green: 56.0/255, blue: 95.0/255, opacity: 1.0)
        case .multidevice: return Color(UIColor.systemBlue)
        case .sendAndReceiveMessagesAndAttachments: return Color(.displayP3, red: 1.0, green: 0.35, blue: 0.39, opacity: 1.0)
        case .createGroupChats: return Color(.displayP3, red: 7.0/255, green: 132.0/255, blue: 254.0/255, opacity: 1.0)
        case .receiveSecureCalls: return Color(.displayP3, red: 253.0/255, green: 56.0/255, blue: 95.0/255, opacity: 1.0)
        }
    }
    
    
    private var description: LocalizedStringKey {
        switch model.feature {
        case .startSecureCalls: return "MAKE_SECURE_CALLS"
        case .multidevice: return "MULTIDEVICE"
        case .sendAndReceiveMessagesAndAttachments: return "Sending & receiving messages and attachments"
        case .createGroupChats: return "Create groups"
        case .receiveSecureCalls: return "RECEIVE_SECURE_CALLS"
        }
    }
    
    
    private var systemIconForAvailability: SystemIcon {
        model.showAsAvailable ? .checkmarkSealFill : .xmarkSealFill
    }
    
    
    private var systemIconForAvailabilityColor: Color {
        model.showAsAvailable ? Color(UIColor.systemGreen) : Color(UIColor.secondaryLabel)
    }
    
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemIcon: systemIcon)
                .font(.system(size: 16))
                .foregroundColor(systemIconColor)
                .frame(minWidth: 30)
            Text(description)
                .foregroundColor(Color(UIColor.label))
                .font(.body)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Image(systemIcon: systemIconForAvailability)
                .font(.system(size: 16))
                .foregroundColor(systemIconForAvailabilityColor)
        }
    }
    
}


// MARK: - Errors occuring during a subscription, free trial activation, or restore

fileprivate enum BuyError: Error, LocalizedError {
    case buySucceededButSubscriptionIsExpired
    case buyFailed
    case failedToStartFreeTrial
    case couldNotRestorePurchases(error: Error)
    case purchaseNotAllowed
    case productUnavailable
    case otherError(error: Error)
    var localizedDescription: String {
        switch self {
        case .buySucceededButSubscriptionIsExpired:
            return String(localizedInThisBundle: "BUY_SUCCEEDED_BUT_SUBSCRIPTION_EXPIRED")
        case .buyFailed:
            return String(localizedInThisBundle: "BUY_FAILED")
        case .failedToStartFreeTrial:
            return String(localizedInThisBundle: "FAILED_TO_START_FREE_TRIAL")
        case .couldNotRestorePurchases(error: let error):
            return String(format: String(localizedInThisBundle: "FAILED_TO_RESTORE_PURCHASES_%@"), error.localizedDescription)
        case .purchaseNotAllowed:
            return String(localizedInThisBundle: "USER_CANNOT_MAKE_PAYMENT_DESCRIPTION")
        case .otherError(error: let error):
            return String(format: String(localizedInThisBundle: "Sorry, the purchase failed 😢. Please try again later or contact us if this problem is recurring. \(error.localizedDescription)"))
        case .productUnavailable:
            return String(localizedInThisBundle: "Sorry, the product is not available in your store 😢.")
        }
    }
}



// MARK: - Previews


struct SubscriptionPlansView_Previews: PreviewProvider {
    
    private final class ModelForPreviews: SubscriptionPlansViewModelProtocol {
        
        let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
        
        let showFreePlanIfAvailable = false
        
        @Published var freePlanIsAvailable: Bool? = nil // Nil until we know whether a free plan is available or not
        @Published var products: [Product]? = nil // Nil until store plans are known
        
        @MainActor
        func setSubscriptionPlans(freePlanIsAvailable: Bool, products: [Product]) async {
            DispatchQueue.main.async {
                withAnimation(.spring) {
                    self.freePlanIsAvailable = freePlanIsAvailable
                    self.products = products
                }
            }
        }
        
    }
    
    private final class ActionsForPreviews: SubscriptionPlansViewActionsProtocol, SubscriptionPlansViewDismissActionsProtocol {
        
        func fetchSubscriptionPlans(for ownedCryptoId: ObvCryptoId, alsoFetchFreePlan: Bool) async throws -> (freePlanIsAvailable: Bool, products: [Product]) {
            try! await Task.sleep(seconds: 1)
            return (alsoFetchFreePlan, [])
        }
        
        func userWantsToStartFreeTrialNow(ownedCryptoId: ObvTypes.ObvCryptoId) async throws -> APIKeyElements {
            try! await Task.sleep(seconds: 2)
            return .init(status: .freeTrial, permissions: [.canCall], expirationDate: Date().addingTimeInterval(.init(days: 30)))
        }
        
        func userWantsToBuy(_: Product) async -> StoreKitDelegatePurchaseResult {
            try! await Task.sleep(seconds: 2)
            return .userCancelled
        }
        
        func userWantsToRestorePurchases() async {
            try! await Task.sleep(seconds: 2)
        }
        
        func userWantsToDismissSubscriptionPlansView() async {}
        
        func dismissSubscriptionPlansViewAfterPurchaseWasMade() async {}

    }
    
    private static let model = ModelForPreviews()
    private static let actions = ActionsForPreviews()

        
    static var previews: some View {
        SubscriptionPlansView(model: model, actions: actions, dismissActions: actions)
    }
    
}
