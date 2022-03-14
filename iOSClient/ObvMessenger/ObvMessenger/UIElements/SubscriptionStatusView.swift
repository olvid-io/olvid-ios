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


struct SubscriptionStatusView: View {
    
    let title: Text?
    let apiKeyStatus: APIKeyStatus
    let apiKeyExpirationDate: Date?
    let showSubscriptionPlansButton: Bool
    let subscriptionPlanAction: () -> Void
    let showRefreshStatusButton: Bool
    let refreshStatusAction: () -> Void
    
    struct Feature: Identifiable {
        let id = UUID()
        let imageSystemName: String
        let imageColor: Color
        let description: String
    }

    private var isPremiumFeaturesAvailable: Bool {
        switch apiKeyStatus {
        case .expired, .unknown, .licensesExhausted, .awaitingPaymentOnHold, .freeTrialExpired:
            return false
        case .free, .valid, .freeTrial, .awaitingPaymentGracePeriod:
            return true
        }
    }
    
    private func refreshStatusNow() {
        refreshStatusAction()
    }

    private static let freeFeatures = [
        SubscriptionStatusView.Feature(imageSystemName: "bubble.left.and.bubble.right.fill",
                                       imageColor: Color(.displayP3, red: 1.0, green: 0.35, blue: 0.39, opacity: 1.0),
                                       description: NSLocalizedString("Sending & receiving messages and attachments", comment: "")),
        SubscriptionStatusView.Feature(imageSystemName: "person.3.fill",
                                       imageColor: Color(.displayP3, red: 7.0/255, green: 132.0/255, blue: 254.0/255, opacity: 1.0),
                                       description: NSLocalizedString("Create groups", comment: "")),
        SubscriptionStatusView.Feature(imageSystemName: "phone.fill.arrow.down.left",
                                       imageColor: Color(.displayP3, red: 253.0/255, green: 56.0/255, blue: 95.0/255, opacity: 1.0),
                                       description: NSLocalizedString("Receive secure calls", comment: "")),
    ]
    
    static let premiumFeatures = [
        SubscriptionStatusView.Feature(imageSystemName: "phone.fill.arrow.up.right",
                                       imageColor: Color(.displayP3, red: 253.0/255, green: 56.0/255, blue: 95.0/255, opacity: 1.0),
                                       description: NSLocalizedString("Make secure calls", comment: "")),
    ]

    var body: some View {
        VStack {
            if let title = self.title {
                HStack(alignment: .firstTextBaseline) {
                    title
                        .font(.title)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.bottom, 8)
            }
            ObvCardView {
                VStack(alignment: .leading, spacing: 0) {
                    SubscriptionStatusSummaryView(apiKeyStatus: apiKeyStatus,
                                                  apiKeyExpirationDate: apiKeyExpirationDate)
                        .padding(.bottom, 16)
                    if showSubscriptionPlansButton {
                        OlvidButton(style: .blue,
                                    title: Text("See subscription plans"),
                                    systemIcon: .flameFill,
                                    action: subscriptionPlanAction)
                            .padding(.bottom, 16)
                    }
                    HStack { Spacer() } // Force full width
                    if apiKeyStatus != .licensesExhausted {
                        SeparatorView()
                            .padding(.bottom, 16)
                        FeatureListView(title: NSLocalizedString("Free features", comment: ""),
                                        features: SubscriptionStatusView.freeFeatures,
                                        available: true)
                        SeparatorView()
                            .padding(.bottom, 16)
                        FeatureListView(title: NSLocalizedString("Premium features", comment: ""),
                                        features: SubscriptionStatusView.premiumFeatures,
                                        available: isPremiumFeaturesAvailable)
                    }
                    if showRefreshStatusButton {
                        OlvidButton(style: .standard,
                                    title: Text("Refresh status"),
                                    systemIcon: .arrowClockwise,
                                    action: refreshStatusNow)
                            .padding(.bottom, 16)
                    }
                }
            }
        }
    }
}




struct FeatureListView: View {
    
    let title: String
    let features: [SubscriptionStatusView.Feature]
    let available: Bool
    
    private var colorScheme: ObvSemanticColorScheme { AppTheme.shared.colorScheme }
    private let colorWhenUnavailable = Color(AppTheme.shared.colorScheme.secondaryLabel)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Image(systemName: available ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundColor(available ? .green : colorWhenUnavailable)
                    .font(.headline)
            }
            .padding(.bottom, 16)
            ForEach(features) { feature in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: feature.imageSystemName)
                        .font(.system(size: 16))
                        .foregroundColor(available ? feature.imageColor : colorWhenUnavailable)
                        .frame(minWidth: 30)
                    Text(feature.description)
                        .foregroundColor(available ? Color(colorScheme.label) : colorWhenUnavailable)
                        .font(.body)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(.bottom, 16)
            }
        }
    }
    
}



struct SubscriptionStatusSummaryView: View {
    
    let apiKeyStatus: APIKeyStatus
    let apiKeyExpirationDate: Date?
    
    private let df: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .full
        return df
    }()
    
    var body: some View {
        switch apiKeyStatus {
        case .unknown:
            Text("No active subscription")
                .font(.headline)
        case .valid:
            VStack(alignment: .leading, spacing: 4) {
                Text("Valid license")
                    .font(.headline)
                if let date = apiKeyExpirationDate {
                    Text("Valid until \(df.string(from: date))")
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                }
            }
        case .licensesExhausted:
            VStack(alignment: .leading, spacing: 4) {
                Text("Invalid subscription")
                    .font(.headline)
                Text("This subscription is already associated to another user")
                    .font(.footnote)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .expired:
            VStack(alignment: .leading, spacing: 4) {
                Text("Subscription expired")
                    .font(.headline)
                if let date = apiKeyExpirationDate {
                    Text("Expired since \(df.string(from: date))")
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                }
            }
        case .free:
            VStack(alignment: .leading, spacing: 4) {
                Text("Premium features tryout")
                    .font(.headline)
                if let date = apiKeyExpirationDate {
                    Text("Premium features are available for free until \(df.string(from: date))")
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Premium features are available for a limited period of time")
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .freeTrial:
            VStack(alignment: .leading, spacing: 4) {
                Text("Premium features free trial")
                    .font(.headline)
                if let date = apiKeyExpirationDate {
                    Text("Premium features available until \(df.string(from: date))")
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Premium features available for free")
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .awaitingPaymentGracePeriod:
            VStack(alignment: .leading, spacing: 4) {
                Text("BILLING_GRACE_PERIOD")
                    .font(.headline)
                if let date = apiKeyExpirationDate {
                    Text("GRACE_PERIOD_ENDS_ON_\(df.string(from: date))")
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .awaitingPaymentOnHold:
            VStack(alignment: .leading, spacing: 4) {
                Text("GRACE_PERIOD_ENDED")
                    .font(.headline)
                if let date = apiKeyExpirationDate {
                    Text("GRACE_PERIOD_ENDED_ON_\(df.string(from: date))")
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .freeTrialExpired:
            VStack(alignment: .leading, spacing: 4) {
                Text("FREE_TRIAL_EXPIRED")
                    .font(.headline)
                if let date = apiKeyExpirationDate {
                    Text("FREE_TRIAL_ENDED_ON_\(df.string(from: date))")
                        .font(.footnote)
                        .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}




struct SeparatorView: View {
    
    var body: some View {
        Rectangle()
            .fill(Color(AppTheme.shared.colorScheme.quaternaryLabel))
            .frame(height: 1)
    }
    
}










struct FeatureListView_Previews: PreviewProvider {
    
    private static let testFreeFeatures = [
        SubscriptionStatusView.Feature(imageSystemName: "bubble.left.and.bubble.right.fill",
                                       imageColor: Color(.displayP3, red: 1.0, green: 0.35, blue: 0.39, opacity: 1.0),
                                       description: "Send & receive messages and attachments"),
        SubscriptionStatusView.Feature(imageSystemName: "person.3.fill",
                                       imageColor: Color(.displayP3, red: 7.0/255, green: 132.0/255, blue: 254.0/255, opacity: 1.0),
                                       description: "Create groups"),
        SubscriptionStatusView.Feature(imageSystemName: "phone.fill.arrow.down.left",
                                       imageColor: Color(.displayP3, red: 253.0/255, green: 56.0/255, blue: 95.0/255, opacity: 1.0),
                                       description: "Receive secure calls"),
    ]
    
    private static let testPremiumFeatures = [
        SubscriptionStatusView.Feature(imageSystemName: "phone.fill.arrow.up.right",
                                       imageColor: Color(.displayP3, red: 253.0/255, green: 56.0/255, blue: 95.0/255, opacity: 1.0),
                                       description: "Make secure calls"),
    ]
    
    static var previews: some View {
        Group {
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .unknown,
                                   apiKeyExpirationDate: nil,
                                   showSubscriptionPlansButton: true,
                                   subscriptionPlanAction: {},
                                   showRefreshStatusButton: true,
                                   refreshStatusAction: {})
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .valid,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   subscriptionPlanAction: {},
                                   showRefreshStatusButton: true,
                                   refreshStatusAction: {})
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .licensesExhausted,
                                   apiKeyExpirationDate: nil,
                                   showSubscriptionPlansButton: false,
                                   subscriptionPlanAction: {},
                                   showRefreshStatusButton: false,
                                   refreshStatusAction: {})
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .expired,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   subscriptionPlanAction: {},
                                   showRefreshStatusButton: true,
                                   refreshStatusAction: {})
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .free,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   subscriptionPlanAction: {},
                                   showRefreshStatusButton: false,
                                   refreshStatusAction: {})
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .awaitingPaymentGracePeriod,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   subscriptionPlanAction: {},
                                   showRefreshStatusButton: false,
                                   refreshStatusAction: {})
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .awaitingPaymentOnHold,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   subscriptionPlanAction: {},
                                   showRefreshStatusButton: false,
                                   refreshStatusAction: {})
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .freeTrialExpired,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   subscriptionPlanAction: {},
                                   showRefreshStatusButton: false,
                                   refreshStatusAction: {})
                .padding()
                .previewLayout(.sizeThatFits)
                .environment(\.locale, .init(identifier: "fr"))
        }
    }
}
