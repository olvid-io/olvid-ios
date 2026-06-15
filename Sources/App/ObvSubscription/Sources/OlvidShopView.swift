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
import MessageUI
import UniformTypeIdentifiers
import Combine
import ObvDesignSystem
import ObvTypes
import ObvSystemIcon
import ObvAppTypes
import ConfettiSwiftUI
import ObvAppCoreConstants


@MainActor
public protocol OlvidShopViewDataSource {
    func getAsyncSequenceOfOlvidShopViewModel(_ view: OlvidShopView) throws -> (streamUUID: UUID, stream: AsyncStream<OlvidShopView.Model>)
    func finishAsyncSequenceOfOlvidShopViewModel(_ view: OlvidShopView, streamUUID: UUID)
}

@MainActor
public protocol OlvidShopViewNavigation {
    func userWantsToDismissPresentedOlvidShopView(_ view: OlvidShopView)
}

@MainActor
public protocol OlvidShopViewActions {
    func userWantsToBuy(_ view: OlvidShopView, product: Product) async throws -> StoreKitDelegatePurchaseResult
    func getCurrentActiveSubscriptionPublisher(_ view: OlvidShopView) throws -> Published<Product?>.Publisher
    func refreshSubscriptionStatus() async throws
}

public struct OlvidShopView: View {
    
    let dataSources: DataSources
    let navigation: any OlvidShopViewNavigation
    let actions: any OlvidShopViewActions
    
    public init(dataSources: DataSources, navigation: any OlvidShopViewNavigation, actions: any OlvidShopViewActions) {
        self.dataSources = dataSources
        self.navigation = navigation
        self.actions = actions
    }
    
    public struct DataSources {
        let dataSource: any OlvidShopViewDataSource
        public init(dataSource: any OlvidShopViewDataSource) {
            self.dataSource = dataSource
        }
    }

    public struct Model {
        let productIDs: [Product.ID]
        public init(productIDs: [Product.ID]) {
            self.productIDs = productIDs
        }
    }
    
    private enum LoadingState {
        case loading
        case loaded(model: Model)
        case failure(error: Error)
    }
    
    @State private var loadingState: LoadingState = .loading
    
    /// Controls whether confetti should be triggered on subscription state changes.
    ///
    /// Confetti are displayed when the `currentActiveSubscription` transitions from `nil` to a valid product.
    /// This variable prevents unwanted confetti when the view appears with an existing subscription.
    /// It is set to `true` only when the user explicitly taps the "Subscribe" button,
    /// ensuring confetti are shown only for new purchases.
    @State private var triggerConfettiIfPurchaseIsMade: Bool = false
    
    private func onTask() async {
        do {
            // Refresh the subscription status to ensure the `currentActiveSubscription` of `SubscriptionManager`
            // reflects the user's currently purchased product, if any.
            // This step is required to:
            // 1. Sync local subscriptions with StoreKit.
            // 2. Validate the subscription status with Olvid's servers via a network request.
            // This ensures the UI can accurately mark the subscribed plan as purchased.
            Task { try await actions.refreshSubscriptionStatus() }
            let (streamUUID, stream) = try dataSources.dataSource.getAsyncSequenceOfOlvidShopViewModel(self)
            defer { dataSources.dataSource.finishAsyncSequenceOfOlvidShopViewModel(self, streamUUID: streamUUID) }
            for await receivedModel in stream {
                loadingState = .loaded(model: receivedModel)
            }
        } catch {
            loadingState = .failure(error: error)
            assertionFailure()
        }
    }
    
    
    public var body: some View {
        if #available(iOS 17.0, *) {
            FullView(loadingState: $loadingState,
                     actions: self,
                     triggerConfettiIfPurchaseIsMade: $triggerConfettiIfPurchaseIsMade)
            .task(onTask)
        } else {
            SubscribeViaEmailOnOldOSVersion()
        }
    }
    
}


/// We use iOS17+ APIs for the store. On iOS 16, we show a screen allowing to send an email to Olvid's support
private struct SubscribeViaEmailOnOldOSVersion: View {
    
    private func buttonTapped() {
        isEmailComposerViewPresented = true
    }
    
    @State private var isEmailComposerViewPresented = false
    @State private var hudCategory: HUDView.Category? = nil

    private var emailModel: ObvEmailComposerView.Model {
        .init(subject: String(localizedInThisBundle: "SUBSCRIBE_VIA_EMAIL_INFO_SUBJECT"),
              toRecipients: [ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage],
              messageBody: String(localizedInThisBundle: "SUBSCRIBE_VIA_EMAIL_INFO_BODY"))
    }
    
    var body: some View {
        ZStack {
            VStack(alignment: .center) {
                HStack {
                    Spacer()
                    VStack {
                        Image(systemIcon: .envelope)
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 8)
                        Text("SUBSCRIBE_VIA_EMAIL_TITLE")
                            .font(.title2)
                            .bold()
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.center)
                            .padding([.bottom, .horizontal])
                        Text("SUBSCRIBE_VIA_EMAIL_DESCRIPTION")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding([.bottom, .horizontal])
                        if ObvEmailComposerView.canSendEmail() {
                            OlvidButtonNew(action: buttonTapped) {
                                Label {
                                    Text("SUBSCRIBE_VIA_EMAIL_BUTTON_TITLE")
                                } icon: {
                                    Image(systemIcon: .envelope)
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            HStack {
                                Text(verbatim: ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(.horizontal)
                                Button {
                                    UIPasteboard.general.setValue(ObvAppCoreConstants.toEmailForSendingInitializationFailureErrorMessage, forPasteboardType: UTType.plainText.identifier)
                                } label: {
                                    Image(systemIcon: .docOnDoc)
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                    Spacer()
                }
            }
            if let hudCategory {
                HUDView(category: hudCategory)
                    .zIndex(1)
            }
        }
        .obvEmailComposerView(isPresented: $isEmailComposerViewPresented, model: emailModel, delegate: self)
    }
    
}

extension SubscribeViaEmailOnOldOSVersion: ObvEmailComposerViewDelegate {
    
    func emailComposerViewDidFinish(_ view: ObvDesignSystem.ObvEmailComposerView, result: Result<MFMailComposeResult, any Error>) {
        switch result {
        case .success:
            hudCategory = .checkmark
        case .failure:
            hudCategory = .xmark
        }
        Task {
            try? await Task.sleep(seconds: 1)
            hudCategory = nil
        }
    }
    
}


extension OlvidShopView: FullViewActions {
    
    func userWantsToBuy(product: Product) async throws -> ObvAppTypes.StoreKitDelegatePurchaseResult {
        triggerConfettiIfPurchaseIsMade = true
        return try await actions.userWantsToBuy(self, product: product)
    }
    
 
    internal func userWantsToDismissPresentedOlvidShopView() {
        navigation.userWantsToDismissPresentedOlvidShopView(self)
    }
    
    func getCurrentActiveSubscriptionPublisher() throws -> Published<Product?>.Publisher {
        try actions.getCurrentActiveSubscriptionPublisher(self)
    }
    
}


@MainActor
protocol FullViewActions {
    func userWantsToDismissPresentedOlvidShopView()
    func userWantsToBuy(product: Product) async throws -> StoreKitDelegatePurchaseResult
    func getCurrentActiveSubscriptionPublisher() throws -> Published<Product?>.Publisher
}


extension OlvidShopView {
    
    @available(iOS 17.0, *)
    private struct FullView: View {
        
        @Binding var loadingState: LoadingState
        let actions: FullViewActions
        @Binding var triggerConfettiIfPurchaseIsMade: Bool
        
        @State private var productsState: Product.CollectionTaskState = .loading

        private var navigationTitle: String {
            String(localizedInThisBundle: "NAVIGATION_TITLE_SUBSCRIPTION_PLANS")
        }
        
        @State var selectedProduct: Product?

        @Environment(\.colorScheme) var colorScheme: ColorScheme
                
        var body: some View {
            NavigationStack {
                Group {
                    switch loadingState {
                    case .loading:
                        ObvCenteredProgressView()
                    case .failure(error: let error):
                        ContentUnavailableViewOnStoreProductsTaskError(error: error)
                    case .loaded(model: let model):
                        Group {
                            switch productsState {
                            case .loading:
                                ObvCenteredProgressView()
                            case .success(let products, unavailable: _):
                                OnSuccessfulProducsStateView(products: products,
                                                             selectedProduct: $selectedProduct,
                                                             actions: actions,
                                                             triggerConfettiIfPurchaseIsMade: $triggerConfettiIfPurchaseIsMade)
                            case .failure(let error):
                                ContentUnavailableViewOnStoreProductsTaskError(error: error)
                            @unknown default:
                                ContentUnavailableViewOnStoreProductsTaskError(error: nil)
                            }
                        }
                        .storeProductsTask(for: model.productIDs) { state in
                            self.productsState = state
                        }
                    }
                }
                .navigationTitle(navigationTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        ObvButtonWithCancelRole(action: actions.userWantsToDismissPresentedOlvidShopView)
                    }
                }
                .background(colorScheme == .dark ? Color(UIColor.systemBackground) : Color(UIColor.secondarySystemBackground))
            }
        }
        
    }
    
}


@available(iOS 17.0, *)
private struct ContentUnavailableViewOnStoreProductsTaskError: View {
    
    let error: Error?
    
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("STORE_PRODUCTS_TASK_FAILURE_TITLE")
            } icon: {
                Image(systemIcon: .storefront)
            }
        } description: {
            if let error {
                Text(verbatim: error.localizedDescription)
            } else {
                Text("STORE_PRODUCTS_TASK_FAILURE_DESCRIPTION")
            }
        }
    }
}


@available(iOS 17.0, *)
private struct OnSuccessfulProducsStateView: View {
    
    let products: [Product]
    @Binding var selectedProduct: Product?
    let actions: FullViewActions
    @Binding var triggerConfettiIfPurchaseIsMade: Bool

    private func remindMeLaterButtonTapped() {
        // For now, the remind me later button does the exact same thing than the navigation close button
        actions.userWantsToDismissPresentedOlvidShopView()
    }
     
    @State private var alreadySubscribedProduct: Product?
    @State private var unitPicked: GridOfProductsView.UnitForPicker = .monthly
    @State private var userManuallyChangedProduct: Bool = false

    @State private var isOfferCodeRedemptionViewPresented: Bool = false
    
    private var isSubscribeButtonDisabled: Bool {
        guard let alreadySubscribedProduct else { return false }
        guard let selectedProduct else { return false }
        return alreadySubscribedProduct == selectedProduct
    }
    
    private func onTask() async {
        do {
            let publisher = try actions.getCurrentActiveSubscriptionPublisher()
            for await product in publisher.values {
                self.alreadySubscribedProduct = product
                guard let alreadySubscribedProduct else { continue }
                guard !userManuallyChangedProduct else { return }
                self.selectedProduct = alreadySubscribedProduct
                switch alreadySubscribedProduct.subscription?.subscriptionPeriod.unit {
                case .month:
                    unitPicked = .monthly
                case .year:
                    unitPicked = .yearly
                default:
                    break
                }
            }
        } catch {
            assertionFailure()
        }
    }

    var body: some View {
        if products.isEmpty {
            ContentUnavailableViewOnEmptyProducts()
        } else {
            ScrollView(.vertical) {
                VStack {
                    
                    GridOfProductsView(products: products,
                                       selectedProduct: $selectedProduct,
                                       alreadySubscribedProduct: alreadySubscribedProduct,
                                       unitPicked: $unitPicked,
                                       userManuallyChangedProduct: $userManuallyChangedProduct,
                                       triggerConfettiIfPurchaseIsMade: $triggerConfettiIfPurchaseIsMade)
                    .padding()
                    
                    VStack {
                        if let selectedProduct {
                            SubscribeButton(selectedProduct: selectedProduct,
                                            actions: actions)
                            .disabled(isSubscribeButtonDisabled)
                        }
                        OlvidButtonNew(action: remindMeLaterButtonTapped, style: .glassOrBordered) {
                            Text("BUTTON_TITLE_REMIND_ME_LATER")
                        }
                    }
                    .padding([.horizontal, .bottom])
                    
                    MarketingView(selectedProduct: $selectedProduct)
                        .padding(.horizontal)
                        .padding(.top)
                    
                    Spacer()
                }
            }
            .task(onTask)
            .toolbar {
                // For some reason, the `offerCodeRedemption` call freezes on macOS
                #if targetEnvironment(macCatalyst)
                EmptyView()
                #else
                InternalMenu(actions: self)
                #endif
            }
            .offerCodeRedemption(isPresented: $isOfferCodeRedemptionViewPresented)
        }
    }
}


@available(iOS 17.0, *)
extension OnSuccessfulProducsStateView: InternalMenuActions {
    
    func userWantsToPresentOfferCodeRedemptionView() {
        isOfferCodeRedemptionViewPresented = true
    }
    
}


@MainActor
protocol InternalMenuActions {
    func userWantsToPresentOfferCodeRedemptionView()
}

private struct InternalMenu: View {
    
    let actions: InternalMenuActions
    
    private var systemIconForMenuLabel: SystemIcon {
        if #available(iOS 26, *) {
            return .ellipsis
        } else {
            return .ellipsisCircle
        }
    }

    var body: some View {
        Menu {
            Button(action: actions.userWantsToPresentOfferCodeRedemptionView) {
                Label {
                    Text("REDEEM_CODE")
                } icon: {
                    Image(systemIcon: .giftcardFill)
                }

            }
        } label: {
            Image(systemIcon: systemIconForMenuLabel)
        }
    }
}


@available(iOS 17.0, *)
private struct ContentUnavailableViewOnEmptyProducts: View {
    
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("CONTENT_UNAVAILABLE_VIEW_TITLE_ON_EMPTY_PRODUCTS")
            } icon: {
                Image(systemIcon: .storefront)
            }
        } description: {
            Text("CONTENT_UNAVAILABLE_VIEW_DESCRIPTION_ON_EMPTY_PRODUCTS")
        }

    }
    
}


private struct MarketingView: View {
    
    @Binding var selectedProduct: Product?

    var body: some View {
        VStack(alignment: .center) {
            Text("MARKETING_VIEW_TITLE")
                .font(.system(.title3, design: .rounded, weight: .bold))
                .padding(.bottom, 4)
            if let selectedProduct {
                Text("MARKETING_VIEW_SUBTITLE_FOR_PRICE_WITH_UNIT_\(selectedProduct.displayPriceWithUnit)")
                    .foregroundStyle(.secondary)
                    .padding(.bottom)
            }
            ForEach(MarketingCapsuleView.Kind.allCases, id: \.self) { kind in
                if kind != .family || selectedProduct?.isFamilyShareable == true {
                    MarketingCapsuleView(kind: kind)
                        .padding(.bottom, 4)
                }
            }
        }
        .multilineTextAlignment(.center)
    }
    
}


private struct MarketingCapsuleView: View {

    let kind: Kind
    
    enum Kind: CaseIterable {
        case family
        case multidevice
        case secureCalls
        case support
    }
    
    private var title: String {
        switch kind {
        case .multidevice: return String(localizedInThisBundle: "MARKETING_CAPSULE_TITLE_MULTIDEVICE")
        case .secureCalls: return String(localizedInThisBundle: "MARKETING_CAPSULE_TITLE_SECURE_CALLS")
        case .support: return String(localizedInThisBundle: "MARKETING_CAPSULE_TITLE_SUPPORT")
        case .family: return String(localizedInThisBundle: "MARKETING_CAPSULE_TITLE_FAMILY")
        }
    }

    private var subtitle: String {
        switch kind {
        case .multidevice: return String(localizedInThisBundle: "MARKETING_CAPSULE_SUBTITLE_MULTIDEVICE")
        case .secureCalls: return String(localizedInThisBundle: "MARKETING_CAPSULE_SUBTITLE_SECURE_CALLS")
        case .support: return String(localizedInThisBundle: "MARKETING_CAPSULE_SUBTITLE_SUPPORT")
        case .family: return String(localizedInThisBundle: "MARKETING_CAPSULE_SUBTITLE_FAMILY")
        }
    }

        // Any change made here should be reflected in `ObvDiscussionsList.TipCellView`
    private var systemIcon: SystemIcon {
        switch kind {
        case .multidevice: return .macbookAndIphone
        case .secureCalls: return .phone
        case .support: return .heart
        case .family: return .figureTwoAndChildHoldinghands
        }
    }
    
    @Environment(\.colorScheme) var colorScheme: ColorScheme

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(UIColor.secondarySystemBackground) : Color(UIColor.systemBackground)
    }
    
    private let cornerRadius: CGFloat = 26.0
    
    // Any change made here should be reflected in `ObvDiscussionsList.TipCellView`
    private var iconBackgroundColor: Color {
        switch kind {
        case .family: return .blue
        case .multidevice: return .green
        case .secureCalls: return .orange
        case .support: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top) {
            Image(systemIcon: systemIcon)
                .foregroundStyle(.white)
                .font(.system(size: 17))
                .padding(12)
                .background(iconBackgroundColor, in: Circle())
                .padding(.trailing, 4)
            VStack(alignment: .leading) {
                Text(title)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .multilineTextAlignment(.leading)
        .padding(.vertical)
        .padding(.leading, 8)
        .padding(.trailing)
        .background(backgroundColor, in: RoundedRectangle(cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous))
    }
}



private struct SubscribeButton: View {
    
    let selectedProduct: Product
    let actions: FullViewActions

    private var titlePart1: AttributedString {
        AttributedString(String(localizedInThisBundle: "BUTTON_TITLE_SUBSCRIBE"))
    }
    
    private var titlePart2: AttributedString {
        var result = AttributedString(" • ")
        result.font = .body.bold()
        return result
    }
    
    private var titlePart3: AttributedString {
        AttributedString("\(selectedProduct.displayPriceWithUnit)")
    }
    
    private var title: AttributedString {
        titlePart1 + titlePart2 + titlePart3
    }
    
    @State private var isPurchasing: Bool = false
    
    @State private var isPendingResultAlertPresented: Bool = false
    
    private func action() {
        isPurchasing = true
        Task {
            defer { isPurchasing = false }
            let result = try await actions.userWantsToBuy(product: selectedProduct)
            switch result {
            case .purchaseSucceeded,
                    .userCancelled:
                break
            case .pending:
                isPendingResultAlertPresented = true
            case .expired:
                break
            case .revoked:
                break
            case .isUpgraded:
                break
            }
        }
    }
    

    var body: some View {
        OlvidButtonNew(action: action) {
            HStack {
                if isPurchasing {
                    ProgressView().progressViewStyle(.circular)
                }
                Text(title)
                    .animation(nil, value: selectedProduct)
            }
        }
        .disabled(isPurchasing)
        .alert(String(localizedInThisBundle: "PURCHASE_RESULT_ALERT_TITLE_PENDING"), isPresented: $isPendingResultAlertPresented, actions: {})
    }
    
}


@available(iOS 17.0, *)
private struct GridOfProductsView: View {

    let products: [Product]
    @Binding var selectedProduct: Product?
    let alreadySubscribedProduct: Product?
    @Binding var unitPicked: UnitForPicker
    @Binding var userManuallyChangedProduct: Bool
    @Binding var triggerConfettiIfPurchaseIsMade: Bool
    
    private func onAppear() {
        guard selectedProduct == nil else { return }
        selectedProduct = products.first
    }

    var productsSlicedByTwo: [[Product]] {
        products.toSlices(ofMaxSize: 2)
    }
    
    private var gridSpacing: CGFloat { 20.0 }
    
    enum UnitForPicker: Int, CaseIterable, Identifiable {
        case monthly = 0
        case yearly
        var id: Int { self.rawValue }
        var title: Text {
            switch self {
            case .monthly:
                return Text("PICKER_ITEM_TITLE_MONTHLY")
            case .yearly:
                return Text("PICKER_ITEM_TITLE_YEARLY")
            }
        }
        var unit: Product.SubscriptionPeriod.Unit {
            switch self {
            case .monthly: return .month
            case .yearly: return .year
            }
        }
    }
    
    private func productsForUnitPicked(_ unitPicked: UnitForPicker) -> [Product] {
        self.products.filter { $0.subscription?.subscriptionPeriod.unit == unitPicked.unit }
    }
    
    /// Resets the `selectedProduct` when the user switches tabs.
    ///
    /// This method ensures the `selectedProduct` always corresponds to one of the products currently displayed on screen.
    /// When the tab changes, the previously selected product is no longer be visible. To maintain consistency,
    /// the method automatically selects a replacement product with matching characteristics (e.g., individual vs. family plan type).
    private func onChangeOfUnitPicked(_ oldValue: GridOfProductsView.UnitForPicker, _ newValue: GridOfProductsView.UnitForPicker) {
        guard let selectedProduct else { return }
        switch newValue {
        case .monthly:
            self.selectedProduct = selectedProduct.equivalentMonthlyProduct(in: products)
        case .yearly:
            self.selectedProduct = selectedProduct.equivalentYearlyProduct(in: products)
        }
    }
        
    var body: some View {
        
        VStack {
            
            Picker("SUBSCRIPTION_PLAN_PERIOD", selection: $unitPicked) {
                ForEach(UnitForPicker.allCases) { unitPicked in
                    unitPicked.title.tag(unitPicked)
                }
            }
            .controlSize(.large)
            .onChange(of: unitPicked, onChangeOfUnitPicked)
            .pickerStyle(.segmented)
            .overlay(alignment: .topTrailing) {
                if let discountString = Product.discountStringForPicker(products: products, kind: .freeMonths) {
                    DiscountCapsule(discountString: discountString)
                        .offset(x: -8, y: -14)
                }
            }
            .padding(.bottom)

            
            HStack {
                ForEach(productsForUnitPicked(unitPicked)) { product in
                    OlvidProductView(product: product,
                                     products: products,
                                     alreadySubscribedProduct: alreadySubscribedProduct,
                                     triggerConfettiIfPurchaseIsMade: $triggerConfettiIfPurchaseIsMade)
                    .padding(1)
                    .background {
                        if selectedProduct == product {
                            SelectedProductViewBackground()
                        }
                    }
                    .onTapGesture {
                        userManuallyChangedProduct = true
                        withAnimation { selectedProduct = product }
                    }
                }
            }
        }
        .onAppear(perform: onAppear)

    }
    
}


private struct SelectedProductViewBackground: View {
    
    let cornerRadius = ObvCardViewParameters.defaultCornerRadius + 1
    
    var body: some View {
        RoundedRectangle(cornerSize: .init(width: cornerRadius, height: cornerRadius), style: .continuous)
            .foregroundStyle(AngularGradient.rainbow)
    }
    
}


@available(iOS 17.0, *)
struct OlvidProductView: View {
    
    let product: Product
    let products: [Product] // All available products
    let alreadySubscribedProduct: Product?
    @Binding var triggerConfettiIfPurchaseIsMade: Bool

    private var isAlreadySubscribed: Bool {
        product == alreadySubscribedProduct
    }
    
    private func onChangeOfAlreadySubscribedProduct(_ oldValue: Product?, _ newValue: Product?) {
        if oldValue != newValue && newValue == product && triggerConfettiIfPurchaseIsMade {
            triggerConfettiIfPurchaseIsMade = false
            Task {
                try? await Task.sleep(seconds: 1)
                triggerConfettiCanon += 1
            }
        }
    }
    
    @State private var triggerConfettiCanon: Int = 0

    var body: some View {
        ObvCardView {
            HStack {
                VStack(alignment: .leading) {
                    YourPlanView().opacity(0)
                    Text(product.displayName)
                        .font(.headline)
                    Text(verbatim: product.displayPriceWithUnit)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    YourPlanView().opacity(isAlreadySubscribed ? 1.0 : 0.0)
                }
                Spacer(minLength: 0)
            }
        }
        .onChange(of: alreadySubscribedProduct, onChangeOfAlreadySubscribedProduct)
        .confettiCannon(trigger: $triggerConfettiCanon,
                        num: 100,
                        openingAngle: Angle(degrees: 0),
                        closingAngle: Angle(degrees: 360),
                        radius: 200)
    }
}


private struct DiscountCapsule: View {

    let discountString: String
    
    var body: some View {
        Text(discountString)
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.tint, in: Capsule())
    }
    
}


private struct YourPlanView: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Image(systemIcon: .starFill).foregroundStyle(.tint)
            Text("YOUR_PLAN").foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}


extension StoreKit.Product {
    
    var displayPriceWithUnit: String {
        if let subscription = self.subscription {
            return "\(self.displayPrice)/\(subscription.subscriptionPeriod.unit.formatted(self.subscriptionPeriodUnitFormatStyle).lowercased())"
        } else {
            return "\(self.displayPrice)"
        }
    }
    
    fileprivate func equivalentMonthlyProduct(in products: [Self]) -> Self? {
        guard self.subscription?.subscriptionPeriod.unit == .year else { return nil }
        let mps = products.filter { $0.subscription?.subscriptionPeriod.unit == .month }
        if self.isFamilyShareable {
            return mps.first(where: { $0.isFamilyShareable })
        } else {
            return mps.first(where: { !$0.isFamilyShareable })
        }
    }
    
    fileprivate func equivalentYearlyProduct(in products: [Self]) -> Self? {
        guard self.subscription?.subscriptionPeriod.unit == .month else { return nil }
        let mps = products.filter { $0.subscription?.subscriptionPeriod.unit == .year }
        if self.isFamilyShareable {
            return mps.first(where: { $0.isFamilyShareable })
        } else {
            return mps.first(where: { !$0.isFamilyShareable })
        }
    }

    
    func discountComparedToMonthlyProduct(in products: [Self]) -> Double? {
        guard let mp = self.equivalentMonthlyProduct(in: products) else { return nil }
        guard mp.price > 0 else { return nil }
        let discount =  1.0 - self.price.doubleValue / (12*mp.price.doubleValue) // Percentage
        return Double(Int(discount * 100)) / 100
    }
    
    func numberOfFreeMonthsOfYearlyProductComparedToMonthlyProduct(in products: [Self]) -> Int? {
        guard let mp = self.equivalentMonthlyProduct(in: products) else { return nil }
        guard mp.price > 0 else { return nil }
        let diff = 12*mp.price - self.price
        guard diff > 0 else { return nil }
        let freeMonthsCount = diff.doubleValue / mp.price.doubleValue
        guard freeMonthsCount >= 1 else { return nil }
        return Int(freeMonthsCount)
    }
    
    static func allFreeMonthsCountBetweenMonthlyAndYearlyProducts(in products: [Self]) -> Set<Int> {
        let freeMonthsCount: [Int] = products.compactMap { $0.numberOfFreeMonthsOfYearlyProductComparedToMonthlyProduct(in: products) }
        return Set(freeMonthsCount)
    }
    
    static func allDiscountsBetweenMonthlyAndYearlyProducts(in products: [Self]) -> Set<Double> {
        let discounts: [Double] = products.compactMap { $0.discountComparedToMonthlyProduct(in: products) }
        return Set(discounts)
    }
    
    enum FreeMonthsOrDiscount {
        case freeMonths
        case discount
    }
    
    static func discountStringForPicker(products: [Self], kind: FreeMonthsOrDiscount) -> String? {
        switch kind {
        case .freeMonths:
            let freeMonthsCounts = Self.allFreeMonthsCountBetweenMonthlyAndYearlyProducts(in: products)
            guard let maxFreeMonths = freeMonthsCounts.max() else { return nil }
            switch freeMonthsCounts.count {
            case 1:
                return String(localizedInThisBundle: "\(maxFreeMonths)_MONTHS_FREE")
            default:
                return String(localizedInThisBundle: "UP_TO_\(maxFreeMonths)_FREE")
            }
        case .discount:
            let discounts = Self.allDiscountsBetweenMonthlyAndYearlyProducts(in: products)
            guard let maxDiscount = discounts.max() else { return nil }
            let formatter = NumberFormatter()
            formatter.numberStyle = .percent
            let number = NSNumber(value: maxDiscount)
            guard let formattedValue = formatter.string(from: number) else { assertionFailure(); return nil }
            switch discounts.count {
            case 1:
                return String(localizedInThisBundle: "Save \(formattedValue)")
            default:
                return String(localizedInThisBundle: "Save up to \(formattedValue)")
            }
        }
        
        
    }
    
}

extension [Product] {
    
    func getActiveSubscriptionProduct() async -> Product? {
        var activeSubscriptionProduct = [Product]()
        for product in self {
            guard let result = await Transaction.latest(for: product.id) else {
                // This product has no transaction, it cannot be the currently subscribed one
                continue
            }
            switch result {
            case .unverified:
                continue
            case .verified(let verifiedTransaction):
                guard verifiedTransaction.revocationDate == nil else {
                    // The transaction has been refounded, the product cannot be the currently subscribed one
                    continue
                }
                if verifiedTransaction.isUpgraded {
                    // The customer upgraded to a higher level of service, the product cannot be the currently subscribed one
                    continue
                }
                activeSubscriptionProduct.append(product)
            }
        }
        assert(activeSubscriptionProduct.count <= 1, "Since all our products belongs to the same group, we do not expect more than one currently subscribed product")
        return activeSubscriptionProduct.first
    }
    
}

extension Decimal {
    var doubleValue:Double {
        return NSDecimalNumber(decimal:self).doubleValue
    }
}









// MARK: - Previews

#if DEBUG

@MainActor
private final class DataSourcesForPreviews {
    
    /// From NewStoreKitConfiguration.storekit. Don't forget to set it in the target configuration during testing.
    static let productIDs: [Product.ID] = [
        "io.olvid.premium_2020_monthly",
        "io.olvid.subscription.family.monthly",
        "io.olvid.subscription.individual.yearly",
        "io.olvid.subscription.family.yearly",
    ]
    
    @Published var currentActiveSubscriptionsPublisher: Product?
    
}

extension DataSourcesForPreviews: OlvidShopViewDataSource {
    
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

extension DataSourcesForPreviews: OlvidShopViewNavigation {
    
    func userWantsToDismissPresentedOlvidShopView(_ view: OlvidShopView) {
        print("User wants to dismiss the shop view")
    }
    
}

extension DataSourcesForPreviews: OlvidShopViewActions {
    
    func refreshSubscriptionStatus() async throws {
        // Returns immediately for previews
    }

    func getCurrentActiveSubscriptionPublisher(_ view: OlvidShopView) throws -> Published<Product?>.Publisher {
        $currentActiveSubscriptionsPublisher
    }
    
    
    func userWantsToBuy(_ view: OlvidShopView, product: Product) async throws -> ObvAppTypes.StoreKitDelegatePurchaseResult {
        print("User wants to buy produc")
        try? await Task.sleep(seconds: 3)
        return .purchaseSucceeded(serverVerificationResult: .succeededAndSubscriptionIsValid)
    }
    
}

@available(iOS 17.0, *)
@MainActor
private let dataSourcesForPreviews = DataSourcesForPreviews()

@available(iOS 17.0, *)
#Preview {
    OlvidShopView(dataSources: .init(dataSource: dataSourcesForPreviews),
                  navigation: dataSourcesForPreviews,
                  actions: dataSourcesForPreviews)
}

#endif
