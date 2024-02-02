/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvUI
import UI_SystemIcon
import ObvDesignSystem


struct SubscriptionStatusView: View {
    
    let title: Text?
    let apiKeyStatus: APIKeyStatus
    let apiKeyExpirationDate: Date?
    let showSubscriptionPlansButton: Bool
    let userWantsToSeeSubscriptionPlans: () -> Void
    let showRefreshStatusButton: Bool
    let refreshStatusAction: () -> Void
    let apiPermissions: APIPermissions
    
    struct Feature: Identifiable {
        let id = UUID()
        let imageSystemName: String
        let imageColor: Color
        let description: String
    }
    
    private func refreshStatusNow() {
        refreshStatusAction()
    }

    private static let freeFeature: [FeatureView.Model] = [
        .init(feature: .sendAndReceiveMessagesAndAttachments, showAsAvailable: true),
        .init(feature: .createGroupChats, showAsAvailable: true),
        .init(feature: .receiveSecureCalls, showAsAvailable: true),
    ]
    
    
    private var premiumFeatures: [FeatureView.Model] {[
        .init(feature: .startSecureCalls, showAsAvailable: apiPermissions.contains(.canCall)),
        .init(feature: .multidevice, showAsAvailable: apiPermissions.contains(.multidevice))
    ]}

    
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
                                    action: userWantsToSeeSubscriptionPlans)
                            .padding(.bottom, 16)
                    }
                    HStack { Spacer() } // Force full width
                    if apiKeyStatus != .licensesExhausted {
                        SeparatorView()
                            .padding(.bottom, 16)
                        FeatureListView(title: NSLocalizedString("Free features", comment: ""),
                                        features: SubscriptionStatusView.freeFeature)
                        SeparatorView()
                            .padding(.bottom, 16)
                        FeatureListView(title: NSLocalizedString("Premium features", comment: ""),
                                        features: premiumFeatures)
                    }
                    if showRefreshStatusButton {
                        OlvidButton(style: .standardWithBlueText,
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
    let features: [FeatureView.Model]
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
            }
            .padding(.bottom, 16)
            ForEach(features) { feature in
                FeatureView(model: feature)
                    .padding(.bottom, 16)
            }
        }
    }
    
}


// MARK: - FeatureView

struct FeatureView: View {

    let model: Model
    
    
    struct Model: Identifiable {
        let feature: FeatureView.Feature
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
        model.showAsAvailable ? Color(UIColor.systemGreen) : Color(AppTheme.shared.colorScheme.secondaryLabel)
    }
    
    
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemIcon: systemIcon)
                .font(.system(size: 16))
                .foregroundColor(systemIconColor)
                .frame(minWidth: 30)
            Text(description)
                .foregroundColor(Color(AppTheme.shared.colorScheme.label))
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
        case .anotherOwnedIdentityHasValidAPIKey:
            VStack(alignment: .leading, spacing: 4) {
                Text("Valid license")
                    .font(.headline)
                Text("ANOTHER_PROFILE_HAS_VALID_API_KEY")
                    .font(.footnote)
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
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
    
    private static let apiPermissionsCalls = {
        var permissions = APIPermissions()
        permissions.insert(.canCall)
        return permissions
    }()
    
    private static let apiPermissionsMultiDevice = {
        var permissions = APIPermissions()
        permissions.insert(.multidevice)
        return permissions
    }()

    private static let apiPermissionsCallsAndMultiDevice = {
        var permissions = APIPermissions()
        permissions.insert(.canCall)
        permissions.insert(.multidevice)
        return permissions
    }()

    static var previews: some View {
        Group {
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .anotherOwnedIdentityHasValidAPIKey,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   userWantsToSeeSubscriptionPlans: {},
                                   showRefreshStatusButton: true,
                                   refreshStatusAction: {},
                                   apiPermissions: Self.apiPermissionsCalls)
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .unknown,
                                   apiKeyExpirationDate: nil,
                                   showSubscriptionPlansButton: true,
                                   userWantsToSeeSubscriptionPlans: {},
                                   showRefreshStatusButton: true,
                                   refreshStatusAction: {},
                                   apiPermissions: apiPermissionsCallsAndMultiDevice)
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .valid,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   userWantsToSeeSubscriptionPlans: {},
                                   showRefreshStatusButton: true,
                                   refreshStatusAction: {},
                                   apiPermissions: apiPermissionsMultiDevice)
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .licensesExhausted,
                                   apiKeyExpirationDate: nil,
                                   showSubscriptionPlansButton: false,
                                   userWantsToSeeSubscriptionPlans: {},
                                   showRefreshStatusButton: false,
                                   refreshStatusAction: {},
                                   apiPermissions: apiPermissionsMultiDevice)
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .expired,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   userWantsToSeeSubscriptionPlans: {},
                                   showRefreshStatusButton: true,
                                   refreshStatusAction: {},
                                   apiPermissions: apiPermissionsMultiDevice)
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .free,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   userWantsToSeeSubscriptionPlans: {},
                                   showRefreshStatusButton: false,
                                   refreshStatusAction: {},
                                   apiPermissions: apiPermissionsMultiDevice)
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .awaitingPaymentGracePeriod,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   userWantsToSeeSubscriptionPlans: {},
                                   showRefreshStatusButton: false,
                                   refreshStatusAction: {},
                                   apiPermissions: apiPermissionsMultiDevice)
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .awaitingPaymentOnHold,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   userWantsToSeeSubscriptionPlans: {},
                                   showRefreshStatusButton: false,
                                   refreshStatusAction: {},
                                   apiPermissions: apiPermissionsMultiDevice)
                .padding()
                .previewLayout(.sizeThatFits)
            SubscriptionStatusView(title: Text("SUBSCRIPTION_STATUS"),
                                   apiKeyStatus: .freeTrialExpired,
                                   apiKeyExpirationDate: Date(),
                                   showSubscriptionPlansButton: false,
                                   userWantsToSeeSubscriptionPlans: {},
                                   showRefreshStatusButton: false,
                                   refreshStatusAction: {},
                                   apiPermissions: apiPermissionsMultiDevice)
                .padding()
                .previewLayout(.sizeThatFits)
                .environment(\.locale, .init(identifier: "fr"))
        }
    }
}
