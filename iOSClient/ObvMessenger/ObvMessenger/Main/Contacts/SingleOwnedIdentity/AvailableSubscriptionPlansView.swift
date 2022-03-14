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
import ObvEngine
import StoreKit
import os.log



final class AvailableSubscriptionPlans: ObservableObject {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "AvailableSubscriptionPlans")

    let ownedCryptoId: ObvCryptoId
    private let fetchSubscriptionPlanAction: () -> Void
    private let userWantsToStartFreeTrialNow: () -> Void
    private let userWantsToFallbackOnFreeVersion: () -> Void
    private let userWantsToBuy: (SKProduct) -> Void
    private let userWantsToRestorePurchases: () -> Void
    @Published private(set) var freePlanIsAvailable: Bool? = nil // Nil until we know whether a free plan is available or not
    @Published private(set) var skProducts: [SKProduct]? // Nil until store plans are known
    @Published private(set) var requestedListOfSKProductsError: SubscriptionCoordinator.RequestedListOfSKProductsError? // Nil until an error occurs when fetching skProducts
    @Published private(set) var shownHUD: HUDView.Category? = nil
    @Published var buttonsAreDisabled = false
    @Published private(set) var errorMessage = Text("")
    @Published var showErrorMessage = false

    
    private var notificationsTokens = [NSObjectProtocol]()
    
    init(ownedCryptoId: ObvCryptoId, fetchSubscriptionPlanAction: @escaping () -> Void, userWantsToStartFreeTrialNow: @escaping () -> Void, userWantsToFallbackOnFreeVersion: @escaping () -> Void, userWantsToBuy: @escaping (SKProduct) -> Void, userWantsToRestorePurchases: @escaping () -> Void) {
        self.freePlanIsAvailable = nil
        self.skProducts = nil
        self.ownedCryptoId = ownedCryptoId
        self.fetchSubscriptionPlanAction = fetchSubscriptionPlanAction
        self.userWantsToStartFreeTrialNow = userWantsToStartFreeTrialNow
        self.userWantsToFallbackOnFreeVersion = userWantsToFallbackOnFreeVersion
        self.userWantsToBuy = userWantsToBuy
        self.userWantsToRestorePurchases = userWantsToRestorePurchases
    }
    
    // Used within SwiftUI previews
    fileprivate init(ownedCryptoId: ObvCryptoId, freePlanIsAvailable: Bool, skProducts: [SKProduct]) {
        self.freePlanIsAvailable = freePlanIsAvailable
        self.skProducts = skProducts
        self.ownedCryptoId = ownedCryptoId
        self.fetchSubscriptionPlanAction = {}
        self.userWantsToStartFreeTrialNow = {}
        self.userWantsToFallbackOnFreeVersion = {}
        self.userWantsToBuy = { _ in }
        self.userWantsToRestorePurchases = {}
    }
    
    var canShowPlans: Bool {
        freePlanIsAvailable != nil && (skProducts != nil || requestedListOfSKProductsError != nil)
    }
    
    func startFreeTrialNow() {
        guard freePlanIsAvailable == true else { return }
        // We observe engine notifications informing us that the current api key of the owned identity has new elements.
        // When this happens, we assume that the free trial has started. In that case, we can display an appropriate HUD and dismiss this view. We know that, in parallel, the owned identity view has been updated and displays the free trial key elements.
        notificationsTokens.append(ObvEngineNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
            guard self?.ownedCryptoId == ownedIdentity else { return }
            guard apiKeyStatus == .freeTrial else { return }
            self?.shownHUD = .checkmark
        })
        shownHUD = .progress
        userWantsToStartFreeTrialNow()
    }
    
    func buySKProductNow(product: SKProduct) {
        notificationsTokens.append(ObvEngineNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
            guard self?.ownedCryptoId == ownedIdentity else { return }
            guard apiKeyStatus == .valid else { return }
            self?.shownHUD = .checkmark
        })
        notificationsTokens.append(SubscriptionNotification.observeUserDecidedToCancelToTheSKProductPurchase(queue: OperationQueue.main) { [weak self] in
            withAnimation {
                self?.shownHUD = nil
                self?.buttonsAreDisabled = false
            }
        })
        notificationsTokens.append(SubscriptionNotification.observeSkProductPurchaseFailed(queue: OperationQueue.main) { [weak self] (error) in
            withAnimation {
                self?.shownHUD = nil
                self?.buttonsAreDisabled = false
                self?.errorMessage = error.text
                self?.showErrorMessage = true
            }
        })
        notificationsTokens.append(SubscriptionNotification.observeSkProductPurchaseWasDeferred(queue: OperationQueue.main) { [weak self] in
            self?.shownHUD = nil
            self?.buttonsAreDisabled = false
            self?.errorMessage = Text("Your purchase must be approved before it can go through.")
            self?.showErrorMessage = true
        })
        shownHUD = .progress
        userWantsToBuy(product)
    }
    
    func restorePurchaseNow() {
        notificationsTokens.append(SubscriptionNotification.observeThereWasNoAppStorePurchaseToRestore(queue: OperationQueue.main) { [weak self] in
            self?.shownHUD = nil
            self?.buttonsAreDisabled = false
            self?.errorMessage = Text("We found no purchase to restore.")
            self?.showErrorMessage = true
        })
        notificationsTokens.append(ObvEngineNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
            guard self?.ownedCryptoId == ownedIdentity else { return }
            guard apiKeyStatus == .valid else { return }
            self?.shownHUD = .checkmark
        })
        notificationsTokens.append(SubscriptionNotification.observeAllPurchaseTransactionsSentToEngineWereProcessed(queue: OperationQueue.main) { [weak self] in
            self?.shownHUD = nil
            self?.buttonsAreDisabled = false
        })
        shownHUD = .progress
        userWantsToRestorePurchases()
    }
    
    func startFetchingSubscriptionPlans() {
        // Before calling the fetchSubscriptionPlanAction, we observe the engine notifications allowing to be notified whether there is a free trial or not
        notificationsTokens.append(ObvEngineNotificationNew.observeFreeTrialIsStillAvailableForOwnedIdentity(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (obvCryptoId) in
            guard let _self = self else { return }
            guard _self.ownedCryptoId == obvCryptoId else { return }
            guard _self.freePlanIsAvailable == nil else { return }
            withAnimation(.spring()) {
                _self.freePlanIsAvailable = true
            }
        })
        notificationsTokens.append(ObvEngineNotificationNew.observeNoMoreFreeTrialAPIKeyAvailableForOwnedIdentity(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (obvCryptoId) in
            guard let _self = self else { return }
            guard _self.ownedCryptoId == obvCryptoId else { return }
            guard _self.freePlanIsAvailable == nil else { return }
            withAnimation(.spring()) {
                _self.freePlanIsAvailable = false
            }
        })
        notificationsTokens.append(SubscriptionNotification.observeNewListOfSKProducts(queue: OperationQueue.main) { [weak self] result in
            guard let _self = self else { return }
            switch result {
            case .failure(let error):
                withAnimation(.spring()) {
                    _self.requestedListOfSKProductsError = error
                }
            case .success(let skProducts):
                for skProduct in skProducts {
                    os_log("Received skProduct with localizedTitle %{public}@", log: _self.log, type: .info, skProduct.localizedTitle)
                }
                withAnimation(.spring()) {
                    _self.skProducts = skProducts
                }
            }
        })
        DispatchQueue(label: "Queue for fetching subscription plans").asyncAfter(deadline: .now() + .seconds(1)) { [weak self] in
            self?.fetchSubscriptionPlanAction()
        }
    }
    
    func fallbackOnFreeVersionNow() {
        // We observe engine notifications informing us that the current api key of the owned identity has new elements.
        // When this happens, we assume that the free trial has started. In that case, we can display an appropriate HUD and dismiss this view. We know that, in parallel, the owned identity view has been updated and displays the free trial key elements.
        notificationsTokens.append(ObvEngineNotificationNew.observeNewAPIKeyElementsForCurrentAPIKeyOfOwnedIdentity(within: NotificationCenter.default, queue: OperationQueue.main) { [weak self] (ownedIdentity, apiKeyStatus, apiPermissions, apiKeyExpirationDate) in
            guard self?.ownedCryptoId == ownedIdentity else { return }
            guard apiKeyStatus == .free else { return }
            self?.shownHUD = .checkmark
        })
        shownHUD = .progress
        userWantsToFallbackOnFreeVersion()
    }
}


struct AvailableSubscriptionPlansView: View {
    
    @ObservedObject var plans: AvailableSubscriptionPlans
    let dismissAction: () -> Void
    
    private let priceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale.current
        return formatter
    }()
        
    var body: some View {
        NavigationView {
            ZStack {
                
                Color(AppTheme.shared.colorScheme.systemBackground)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 0) {
                        if plans.canShowPlans {
                            if plans.freePlanIsAvailable == true {
                                SKProductCardView(title: Text("Free Trial"),
                                                  price: Text("Free"),
                                                  description: Text("Get access to premium features for free for one month. This free trial can be activated only once."),
                                                  buttonTitle: Text("Start free trial now"),
                                                  buttonSystemIcon: .handThumbsupFill,
                                                  buttonAction: plans.startFreeTrialNow,
                                                  buttonIsDisabled: $plans.buttonsAreDisabled)
                                    .transition(AnyTransition.move(edge: .trailing))
                                    .padding(.bottom, 32)
                            }
                            if let skProducts = plans.skProducts {
                                ForEach(skProducts, id: \.self) { skProduct in
                                    SKProductCardView(skProduct: skProduct,
                                                      buttonTitle: Text("Subscribe now"),
                                                      buttonSystemIcon: .cartFill,
                                                      buttonAction: { plans.buySKProductNow(product: skProduct) },
                                                      buttonIsDisabled: $plans.buttonsAreDisabled)
                                        .transition(AnyTransition.move(edge: .leading))
                                        .padding(.bottom, 32)
                                }
                            } else if let error = plans.requestedListOfSKProductsError {
                                SKProductErrorCardView(error: error)
                                    .transition(AnyTransition.move(edge: .leading))
                                    .padding(.bottom, 32)
                            }
                            if ObvMessengerConstants.developmentMode {
                                OlvidButton(style: .standardWithBlueText,
                                            title: Text("Fallback to free version"),
                                            systemIcon: .giftcardFill,
                                            action: {
                                                plans.buttonsAreDisabled = true
                                                plans.fallbackOnFreeVersionNow()
                                            })
                                    .padding(.bottom, 16)
                                    .disabled(plans.buttonsAreDisabled)
                                    .transition(AnyTransition.move(edge: .bottom))
                            }
                            OlvidButton(style: .standardWithBlueText,
                                        title: Text("Manage your subscription"),
                                        systemIcon: .link,
                                        action: {
                                            let url = ObvMessengerConstants.urlForManagingSubscriptionWithTheAppStore
                                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                                        })
                                .padding(.bottom, 16)
                                .disabled(plans.buttonsAreDisabled)
                                .animation(Animation.default.delay(0.025))
                                .transition(AnyTransition.move(edge: .bottom))
                            OlvidButton(style: .standardWithBlueText,
                                        title: Text("Manage payments"),
                                        systemIcon: .creditcardFill,
                                        action: {
                                            let url = ObvMessengerConstants.urlForManagingPaymentsOnTheAppStore
                                            UIApplication.shared.open(url, options: [:], completionHandler: nil)
                                        })
                                .padding(.bottom, 16)
                                .disabled(plans.buttonsAreDisabled)
                                .animation(Animation.default.delay(0.025))
                                .transition(AnyTransition.move(edge: .bottom))
                            OlvidButton(style: .standardWithBlueText,
                                        title: Text("Restore Purchases"),
                                        systemIcon: .arrowUturnForwardCircleFill,
                                        action: {
                                            plans.buttonsAreDisabled = true
                                            plans.restorePurchaseNow()
                                        })
                                .disabled(plans.buttonsAreDisabled)
                                .animation(Animation.default.delay(0.05))
                                .transition(AnyTransition.move(edge: .bottom))
                        } else {
                            HStack {
                                Spacer()
                                if #available(iOS 14.0, *) {
                                    ProgressView("Looking for available subscription plans")
                                } else {
                                    ObvActivityIndicator(isAnimating: .constant(true), style: .large, color: nil)
                                }
                                Spacer()
                            }.padding(.top)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 32)
                }
                if let shownHUD = plans.shownHUD {
                    if shownHUD == .progress {
                        HUDView(category: .progress)
                    } else if shownHUD == .checkmark {
                        HUDView(category: .checkmark)
                            .onAppear(perform: {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                                            dismissAction()
                                        }})
                    }
                }
            }
            .alert(isPresented: $plans.showErrorMessage) {
                Alert(title: Text("😧 Oups..."), message: plans.errorMessage, dismissButton: Alert.Button.default(Text("Ok")))
            }
            .navigationBarTitle(Text("Available subscription plans"), displayMode: .inline)
            .navigationBarItems(leading: Button(action: dismissAction,
                                                label: {
                                                    Image(systemName: "xmark.circle.fill")
                                                        .font(Font.system(size: 24, weight: .semibold, design: .default))
                                                        .foregroundColor(Color(AppTheme.shared.colorScheme.tertiaryLabel))
                                                }))
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: {
            plans.startFetchingSubscriptionPlans()
        })
    }
}



struct SKProductErrorCardView: View {
    
    let error: SubscriptionCoordinator.RequestedListOfSKProductsError

    private var title: Text {
        switch error {
        case .userCannotMakePayments:
            return Text("USER_CANNOT_MAKE_PAYMENT_TITLE")
        }
    }
    
    private var description: Text {
        switch error {
        case .userCannotMakePayments:
            return Text("USER_CANNOT_MAKE_PAYMENT_DESCRIPTION")
        }
    }
    
    var body: some View {
        ObvCardView {
            VStack(spacing: 16.0) {
                HStack(alignment: .firstTextBaseline) {
                    title
                        .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    Image(systemIcon: .xmarkOctagonFill)
                        .font(.system(.title, design: .rounded))
                        .foregroundColor(.red)
                }
                HStack {
                    description
                        .font(.body)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    Spacer()
                }.fixedSize(horizontal: false, vertical: true)
                OlvidButton(style: .standardWithBlueText,
                            title: Text("Manage payments"),
                            systemIcon: .creditcardFill,
                            action: {
                                let url = ObvMessengerConstants.urlForManagingPaymentsOnTheAppStore
                                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                            })
                    .padding(.bottom, 16)
            }
        }
    }
    
}


struct SKProductCardView: View {
    
    let title: Text
    let price: Text
    let description: Text
    let buttonTitle: Text
    let buttonSystemIcon: ObvSystemIcon?
    let buttonAction: () -> Void
    @Binding var buttonIsDisabled: Bool
        
    init(title: Text, price: Text, description: Text, buttonTitle: Text, buttonSystemIcon: ObvSystemIcon?, buttonAction: @escaping () -> Void, buttonIsDisabled: Binding<Bool>) {
        self.title = title
        self.price = price
        self.description = description
        self.buttonTitle = buttonTitle
        self.buttonSystemIcon = buttonSystemIcon
        self.buttonAction = buttonAction
        self._buttonIsDisabled = buttonIsDisabled
    }
    
    init(skProduct: SKProduct, buttonTitle: Text, buttonSystemIcon: ObvSystemIcon?, buttonAction: @escaping () -> Void, buttonIsDisabled: Binding<Bool>) {
        let price: Text
        if let subscriptionPeriod = skProduct.subscriptionPeriod {
            price = Text("\(skProduct.localizedPrice)/\(subscriptionPeriod.unit.localizedDescription)")
        } else {
            assertionFailure()
            price = Text("\(skProduct.localizedPrice)")
        }
        let subscription = AvailableSubscription(productIdentifier: skProduct.productIdentifier)
        assert(subscription != nil)
        self.init(title: Text(subscription?.localizedTitle ?? skProduct.localizedTitle),
                  price: price,
                  description: Text(subscription?.localizedDescription ?? skProduct.localizedDescription),
                  buttonTitle: buttonTitle,
                  buttonSystemIcon: buttonSystemIcon,
                  buttonAction: buttonAction,
                  buttonIsDisabled: buttonIsDisabled)
    }
    
    var body: some View {
        ObvCardView {
            VStack(spacing: 16.0) {
                HStack(alignment: .firstTextBaseline) {
                    title
                        .fontWeight(/*@START_MENU_TOKEN@*/.bold/*@END_MENU_TOKEN@*/)
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                    price
                        .fontWeight(.bold)
                        .font(.system(.title, design: .rounded))
                }
                HStack {
                    description
                        .font(.body)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    Spacer()
                }.fixedSize(horizontal: false, vertical: true)
                FeatureListView(title: NSLocalizedString("Premium features", comment: ""),
                                features: SubscriptionStatusView.premiumFeatures,
                                available: true)
                OlvidButton(style: .blue,
                            title: buttonTitle,
                            systemIcon: buttonSystemIcon,
                            action: {
                    buttonIsDisabled = true
                    buttonAction()
                })
                    .disabled(buttonIsDisabled)
            }
        }
    }
    
}



extension SKProduct {

    var localizedPrice: String {
        let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "SKProduct")
        os_log("💰 Price locale is %{public}@", log: log, type: .info, priceLocale.description)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        return formatter.string(from: price)!
    }

}



fileprivate extension SKError {

    
    var text: Text {
        let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "SKProduct")
        os_log("💰 SKError code is %d", log: log, type: .error, self.code.rawValue)
        switch self.code {
        case .clientInvalid: return Text("Sorry, it seems you are not allowed to issue the request 😢.")
        case .paymentCancelled: return Text("Ok, the payment was successfully cancelled.")
        case .paymentNotAllowed: return Text("Sorry, it seems you are not allowed to make the payment 😢.")
        case .storeProductNotAvailable: return Text("Sorry, the product is not available in your store 😢.")
        case .cloudServicePermissionDenied: return Text("The purchase failed because you did not allowed access to cloud service information 😢.")
        case .cloudServiceNetworkConnectionFailed: return Text("Sorry, the purchase failed because we could not connect to the nework 😢. Please try again later.")
        case .privacyAcknowledgementRequired: return Text("Sorry, the purchase failed because you still need to acknowledge Apple's privacy policy 😢.")
        default: return Text("Sorry, the purchase failed 😢. Please try again later or contact us if this problem is recurring.")
        }
    }

}







struct AvailableSubscriptionPlansView_Previews: PreviewProvider {
    
    private static let identityAsURL = URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!
    private static let testOwnedCryptoId = ObvURLIdentity(urlRepresentation: identityAsURL)!.cryptoId
    
    static var previews: some View {
        Group {
            AvailableSubscriptionPlansView(plans: AvailableSubscriptionPlans(ownedCryptoId: testOwnedCryptoId, fetchSubscriptionPlanAction: {}, userWantsToStartFreeTrialNow: {}, userWantsToFallbackOnFreeVersion: {}, userWantsToBuy: { _ in }, userWantsToRestorePurchases: {}), dismissAction: {})
            AvailableSubscriptionPlansView(plans: AvailableSubscriptionPlans(ownedCryptoId: testOwnedCryptoId, freePlanIsAvailable: true, skProducts: []), dismissAction: {})
            AvailableSubscriptionPlansView(plans: AvailableSubscriptionPlans(ownedCryptoId: testOwnedCryptoId, freePlanIsAvailable: true, skProducts: []), dismissAction: {})
            SKProductErrorCardView(error: .userCannotMakePayments)
        }
    }
}
