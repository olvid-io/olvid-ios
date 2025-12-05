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
import ObvAppCoreConstants
import ObvDesignSystem
import ObvSystemIcon
import ObvAppTypes


public enum TipCellViewModel: Sendable, Equatable {
    
    case backup(SetupNewBackupsCellViewModel)
    case doSendReadReceipt
    case archivedDiscussionsHelpMessage(discussionsAreUnarchivedAutomatically: Bool) // Only used within the list of archived discussions
    case olvidPlus(OlvidPlusTipViewModel)
    case olvidPlusSuccessfulSubscription(ownershipType: ObvOwnershipType)
    
    public enum SetupNewBackupsCellViewModel: Sendable, Equatable {
        case newBackupsShouldBeSetup
        case rememberToWriteDownBackupKey
    }
    
    public enum OlvidPlusTipViewModel: Sendable, Equatable, CaseIterable {
        case family
        case multidevice
        case secureCalls
        case support
    }
    
}


@MainActor
public protocol TipCellViewDataSource: Sendable {
    func getAsyncStreamOfTipCellViewModel(_ view: ObvDiscussionsListView) throws -> (streamUUID: UUID, stream: AsyncStream<TipCellViewModel?>)
    func finishAsyncStreamOfTipCellViewModel(_ view: ObvDiscussionsListView, streamUUID: UUID)
}


@MainActor protocol TipCellViewActionsProtocol: SetupNewBackupsCellViewActionsProtocol, DoSendReadReceiptTipViewActionsProtocol, ArchivedDiscussionsHelpMessageViewActionsProtocol, OlvidPlusTipViewActions, OlvidPlusSuccessfulSubscriptionViewActions {}


struct TipCellView: View {
    
    let viewModel: TipCellViewModel
    let actions: TipCellViewActionsProtocol
    
    var body: some View {
        switch viewModel {
        case .backup(let model):
            SetupNewBackupsCellView(item: model, actions: actions)
        case .doSendReadReceipt:
            DoSendReadReceiptTipView(actions: actions)
        case .archivedDiscussionsHelpMessage(discussionsAreUnarchivedAutomatically: let discussionsAreUnarchivedAutomatically):
            ArchivedDiscussionsHelpMessageView(
                discussionsAreUnarchivedAutomatically: discussionsAreUnarchivedAutomatically,
                actions: actions)
        case .olvidPlus(let olvidPlusTipViewModel):
            OlvidPlusTipView(olvidPlusTipViewModel: olvidPlusTipViewModel, actions: actions)
        case .olvidPlusSuccessfulSubscription(ownershipType: let ownershipType):
            OlvidPlusSuccessfulSubscriptionView(ownershipType: ownershipType, actions: actions)
        }
    }
    
}


// MARK: - Internal view

@MainActor
protocol OlvidPlusSuccessfulSubscriptionViewActions {
    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ view: OlvidPlusSuccessfulSubscriptionView)
}

struct OlvidPlusSuccessfulSubscriptionView: View {
    
    let ownershipType: ObvOwnershipType
    let actions: any OlvidPlusSuccessfulSubscriptionViewActions
    
    private var systemIcon: SystemIcon {
        switch ownershipType {
        case .familyShared: return .figureTwoAndChildHoldinghands
        case .purchasedAndFamilyShareable: return .figureTwoAndChildHoldinghands
        case .purchasedButNotFamilyShareable: return .storefront
        }
    }

    private var title: String {
        switch ownershipType {
        case .familyShared: return String(localizedInThisBundle: "TITLE_OLVID_PLUS_SUCCESSFUL_SUBSCRIPTION_FAMILY_SHARED")
        case .purchasedAndFamilyShareable: return String(localizedInThisBundle: "TITLE_OLVID_PLUS_SUCCESSFUL_SUBSCRIPTION_PURCHASED_AND_FAMILY_SHAREABLE")
        case .purchasedButNotFamilyShareable: return String(localizedInThisBundle: "TITLE_OLVID_PLUS_SUCCESSFUL_SUBSCRIPTION_PURCHASED_BUT_NOT_FAMILY_SHAREABLE")
        }
    }
    
    private var message: String {
        switch ownershipType {
        case .familyShared: return String(localizedInThisBundle: "MESSAGE_OLVID_PLUS_SUCCESSFUL_SUBSCRIPTION_FAMILY_SHARED")
        case .purchasedAndFamilyShareable: return String(localizedInThisBundle: "MESSAGE_OLVID_PLUS_SUCCESSFUL_SUBSCRIPTION_PURCHASED_AND_FAMILY_SHAREABLE")
        case .purchasedButNotFamilyShareable: return String(localizedInThisBundle: "MESSAGE_OLVID_PLUS_SUCCESSFUL_SUBSCRIPTION_PURCHASED_BUT_NOT_FAMILY_SHAREABLE")
        }
    }
    
    private func buttonTapped() {
        actions.userWantsToDismissOlvidPlusSuccessfulSubscriptionView(self)
    }

    private var cornerSize: CGSize {
        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            return CGSize(width: 8, height: 8)
        } else {
            return CGSize(width: 12, height: 12)
        }
    }

    private var backgroundColor: Color {
        Color(UIColor.secondarySystemBackground)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            
            Image(systemIcon: systemIcon)
                .foregroundStyle(.white)
                .font(.system(size: 13))
                .padding(10)
                .background(.green, in: Circle())
                .padding(.trailing, 6)

            VStack(alignment: .leading) {
                
                VStack(alignment: .leading) {
                    HStack {
                        Text(title)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                            .padding(.bottom, 4)
                        Spacer(minLength: 0)
                    }
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                
                HStack {
                    Spacer(minLength: 0)
                    Button(action: buttonTapped) {
                        Text("BUTTON_TITLE_OK")
                    }
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                }
                
            }
            
        }
        .padding(.horizontal, 8)
        .padding(.vertical)
        .background(RoundedRectangle(cornerSize: cornerSize, style: .continuous).foregroundStyle(backgroundColor))
        .buttonStyle(PlainButtonStyle()) // Prevents the whole view to act as a button, required when using a SwiftUI List
    }
    
}

// MARK: - Internal view

@MainActor
protocol OlvidPlusTipViewActions {
    func userWantsToDiscoverOlvidPlus(_ view: OlvidPlusTipView)
}

struct OlvidPlusTipView: View {
    
    let olvidPlusTipViewModel: TipCellViewModel.OlvidPlusTipViewModel
    let actions: any OlvidPlusTipViewActions
    
    private var systemIcon: SystemIcon {
        switch olvidPlusTipViewModel {
        case .multidevice: return .macbookAndIphone
        case .secureCalls: return .phone
        case .support: return .heart
        case .family: return .figureTwoAndChildHoldinghands
        }
    }
    
    private var iconBackgroundColor: Color {
        switch olvidPlusTipViewModel {
        case .family: return .blue
        case .multidevice: return .green
        case .secureCalls: return .yellow
        case .support: return .red
        }
    }

    private var title: LocalizedStringKey {
        switch olvidPlusTipViewModel {
        case .family: return "TIP_OLVID_PLUS_TITLE_FAMILY"
        case .multidevice: return "TIP_OLVID_PLUS_TITLE_MULTIDEVICE"
        case .secureCalls: return "TIP_OLVID_PLUS_TITLE_SECURE_CALLS"
        case .support: return "TIP_OLVID_PLUS_TITLE_SUPPORT"
        }
    }

    private var message: LocalizedStringKey {
        switch olvidPlusTipViewModel {
        case .family: return "TIP_OLVID_PLUS_MESSAGE_FAMILY"
        case .multidevice: return "TIP_OLVID_PLUS_MESSAGE_MULTIDEVICE"
        case .secureCalls: return "TIP_OLVID_PLUS_MESSAGE_SECURE_CALLS"
        case .support: return "TIP_OLVID_PLUS_MESSAGE_SUPPORT"
        }
    }
        
    private var backgroundColor: Color {
        Color(UIColor.secondarySystemBackground)
    }

    private var cornerSize: CGSize {
        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            return CGSize(width: 8, height: 8)
        } else {
            return CGSize(width: 12, height: 12)
        }
    }
    
    private func userTappedTheDiscoverOlvidPlusButton() {
        actions.userWantsToDiscoverOlvidPlus(self)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            
            Image(systemIcon: systemIcon)
                .foregroundStyle(.white)
                .font(.system(size: 13))
                .padding(10)
                .background(iconBackgroundColor, in: Circle())
                .padding(.trailing, 6)

            VStack(alignment: .leading) {
                
                VStack(alignment: .leading) {
                    HStack {
                        Text(title)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                            .padding(.bottom, 4)
                        Spacer(minLength: 0)
                    }
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }
                
                HStack {
                    Spacer(minLength: 0)
                    Button(action: userTappedTheDiscoverOlvidPlusButton) {
                        Text("BUTTON_TITLE_DISCOVER_OLVID_PLUS")
                    }
                    .controlSize(.mini)
                    .buttonStyle(.borderedProminent)
                }
                
            }
            
        }
        .padding(.horizontal, 8)
        .padding(.vertical)
        .background(RoundedRectangle(cornerSize: cornerSize, style: .continuous).foregroundStyle(backgroundColor))
        .buttonStyle(PlainButtonStyle()) // Prevents the whole view to act as a button, required when using a SwiftUI List
    }
}


// MARK: - Interanl view: ArchivedDiscussionsHelpMessageView

@MainActor
protocol ArchivedDiscussionsHelpMessageViewActionsProtocol {
    func userWantsToNavigateToSettingsToChangeDiscussionsUnarchivingBehavior(_ view: ArchivedDiscussionsHelpMessageView) async
}


struct ArchivedDiscussionsHelpMessageView: View {
    
    let discussionsAreUnarchivedAutomatically: Bool
    let actions: ArchivedDiscussionsHelpMessageViewActionsProtocol
    
    private var title: String {
        if discussionsAreUnarchivedAutomatically {
            String(localizedInThisBundle: "ABOUT_ARCHIVED_DISCUSSIONS_TITLE_AUTOMATIC_UNARCHIVING_TRUE")
        } else {
            String(localizedInThisBundle: "ABOUT_ARCHIVED_DISCUSSIONS_TITLE_AUTOMATIC_UNARCHIVING_FALSE")
        }
    }
    
    private var message: String {
        if discussionsAreUnarchivedAutomatically {
            return String(localizedInThisBundle: "ABOUT_ARCHIVED_DISCUSSIONS_MESSAGE_AUTOMATIC_UNARCHIVING_TRUE")
        } else {
            return String(localizedInThisBundle: "ABOUT_ARCHIVED_DISCUSSIONS_MESSAGE_AUTOMATIC_UNARCHIVING_FALSE")
        }
    }

    private var backgroundColor: Color {
        Color(UIColor.secondarySystemBackground)
    }

    private var cornerSize: CGSize {
        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            return CGSize(width: 8, height: 8)
        } else {
            return CGSize(width: 12, height: 12)
        }
    }
    
    private func buttonTapped() {
        Task {
            await actions.userWantsToNavigateToSettingsToChangeDiscussionsUnarchivingBehavior(self)
        }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            
            Image(systemIcon: .archivebox)
                .padding(.trailing, 8)
                .foregroundStyle(.orange)
            
            VStack(alignment: .leading) {
                
                VStack(alignment: .leading) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                        .padding(.bottom, 4)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)
                }.padding(.trailing)
                
                Divider()
                
                Button(action: buttonTapped) {
                    HStack {
                        Text("CONFIGURE_UNARCHIVING")
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .background(Rectangle().foregroundStyle(backgroundColor))
                }
                
            }
            
        }
        .padding(.leading)
        .padding(.vertical)
        .background(RoundedRectangle(cornerSize: cornerSize, style: .continuous).foregroundStyle(backgroundColor))
        .buttonStyle(PlainButtonStyle()) // Prevents the whole view to act as a button, required when using a SwiftUI List
    }
}


// MARK: - Internal view: DoSendReadReceiptTipView

@MainActor
protocol DoSendReadReceiptTipViewActionsProtocol {
    func userWantsToSetDoSendReadReceipt(doSendReadReceipt: Bool)
    func userWantsToDismissTip()
}

private struct DoSendReadReceiptTipView: View {
    
    let actions: DoSendReadReceiptTipViewActionsProtocol

    private var title: String {
        String(localizedInThisBundle: "Read receipts")
    }
    
    private var message: String {
        String(localizedInThisBundle: "Turn on read receipts to let your contacts know when you've read their messages. You can adjust this setting anytime.")
    }
    
    private var cornerSize: CGSize {
        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            return CGSize(width: 8, height: 8)
        } else {
            return CGSize(width: 12, height: 12)
        }
    }
    
    private func userWantsToSetDoSendReadReceipt(to doSendReadReceipt: Bool) {
        actions.userWantsToSetDoSendReadReceipt(doSendReadReceipt: doSendReadReceipt)
    }

    private var backgroundColor: Color {
        Color(UIColor.secondarySystemBackground)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemIcon: .eye)
                .padding(.trailing, 8)
                .foregroundStyle(.blue)
            VStack(alignment: .leading) {
                VStack(alignment: .leading) {
                    HStack {
                        Text(title)
                            .font(.system(.headline, design: .rounded))
                            .fontWeight(.semibold)
                        Spacer(minLength: 0)
                        Button {
                            actions.userWantsToDismissTip()
                        } label: {
                            Image(systemIcon: .xmark)
                                .font(Font.headline.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }

                    }
                    .padding(.bottom, 4)
                    HStack {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)
                        Spacer(minLength: 0)
                    }
                }.padding(.trailing)
                
                Divider()

                Button {
                    userWantsToSetDoSendReadReceipt(to: true)
                } label: {
                    HStack {
                        Text("TURN_ON")
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .background(Rectangle().foregroundStyle(backgroundColor))
                }

                Divider()

                Button {
                    userWantsToSetDoSendReadReceipt(to: false)
                } label: {
                    HStack {
                        Text("DONT_TURN_ON")
                            .foregroundStyle(.blue)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .background(Rectangle().foregroundStyle(backgroundColor))
                }
                
            }
        }
        .padding(.leading)
        .padding(.vertical)
        .background(RoundedRectangle(cornerSize: cornerSize, style: .continuous).foregroundStyle(backgroundColor))
        .buttonStyle(PlainButtonStyle()) // Prevents the whole view to act as a button, required when using a SwiftUI List
    }
    
}


// MARK: - Internal view: SetupNewBackupsCellView

@MainActor
protocol SetupNewBackupsCellViewActionsProtocol {
    func userWantsToSetupNewBackups()
    func userWantsToDisplayBackupKey()
}

private struct SetupNewBackupsCellView: View {
    
    let item: TipCellViewModel.SetupNewBackupsCellViewModel
    let actions: SetupNewBackupsCellViewActionsProtocol
    
    private let trailingPadding: CGFloat = 8
    
    private var title: String {
        switch item {
        case .newBackupsShouldBeSetup:
            return String(localizedInThisBundle: "TIP_SETUP_NEW_BACKUPS_TITLE")
        case .rememberToWriteDownBackupKey:
            return String(localizedInThisBundle: "TIP_REMEMBER_TO_WRITE_DOWN_BACKUP_KEY_TITLE")
        }
    }
    
    private var message: String {
        switch item {
        case .newBackupsShouldBeSetup:
            return String(localizedInThisBundle: "TIP_SETUP_NEW_BACKUPS_MESSAGE")
        case .rememberToWriteDownBackupKey:
            return String(localizedInThisBundle: "TIP_REMEMBER_TO_WRITE_DOWN_BACKUP_KEY_MESSAGE")
        }
    }
    
    private var cornerSize: CGSize {
        if ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            return CGSize(width: 8, height: 8)
        } else {
            return CGSize(width: 12, height: 12)
        }
    }
    
    private var backgroundColor: Color {
        Color(UIColor.secondarySystemBackground)
    }

    var body: some View {
        
        HStack(alignment: .firstTextBaseline) {
            ObvCloudBackupIconView(size: .small)
                .padding(.trailing, 8)
                .offset(y: -2)
            VStack(alignment: .leading) {
                HStack {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                        .fontWeight(.semibold)
                    Spacer(minLength: 0)
                }
                .padding(.bottom, 4)
                .padding(.trailing, trailingPadding)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                    .padding(.trailing, trailingPadding)

                Divider()

                switch item {
                case .newBackupsShouldBeSetup:
                    Button {
                        actions.userWantsToSetupNewBackups()
                    } label: {
                        HStack {
                            Text("CONFIGURE_NEW_BACKUPS_NOW")
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .background(Rectangle().foregroundStyle(backgroundColor))
                    }
                case .rememberToWriteDownBackupKey:
                    Button {
                        actions.userWantsToDisplayBackupKey()
                    } label: {
                        HStack {
                            Text("SHOW_BACKUP_KEY_NOW")
                                .fontWeight(.semibold)
                                .foregroundStyle(.blue)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .background(Rectangle().foregroundStyle(backgroundColor))
                    }
                }

            }
        }
        .padding(.leading)
        .padding(.vertical)
        .background(RoundedRectangle(cornerSize: cornerSize, style: .continuous).foregroundStyle(backgroundColor))
        .buttonStyle(PlainButtonStyle()) // Prevents the whole view to act as a button, required when using a SwiftUI List

    }
    
}




// MARK: - Previews

#if DEBUG

private struct ActionsForPreviews: TipCellViewActionsProtocol {
    
    func userWantsToDismissTip() {
        print("User wants to dismiss tip")
    }
    
    func userWantsToSetDoSendReadReceipt(doSendReadReceipt: Bool) {
        print("User wants to set do send read receipt to \(doSendReadReceipt)")
    }
    
    func userWantsToDisplayBackupKey() {
        print("User wants to display backup key")
    }
    
    func userWantsToSetupNewBackups() {
        print("User wants to setup new backups")
    }
    
    func userWantsToNavigateToSettingsToChangeDiscussionsUnarchivingBehavior(_ view: ArchivedDiscussionsHelpMessageView) async {
        print("User wants to navigate to settings to change discussions unarchiving behavior")
    }
    
    func userWantsToDiscoverOlvidPlus(_ view: OlvidPlusTipView) {
        print("User wants to discover Olvid+")
    }
    
    func userWantsToDismissOlvidPlusSuccessfulSubscriptionView(_ view: OlvidPlusSuccessfulSubscriptionView) {
        print("User wants to dismiss Olvid+ successful subscription view")
    }
    
}

@MainActor
private let actionsForPreviews = ActionsForPreviews()

#Preview("Successful Olvid+") {
    ScrollView {
        VStack {
            ForEach(ObvOwnershipType.allCases, id: \.self) { ownershipType in
                TipCellView(viewModel: .olvidPlusSuccessfulSubscription(ownershipType: ownershipType), actions: actionsForPreviews)
                    .padding(.bottom)
            }
        }.padding()
    }
}

#Preview("Olvid+") {
    ScrollView {
        VStack {
            ForEach(TipCellViewModel.OlvidPlusTipViewModel.allCases, id: \.self) { olvidPlusTipViewModel in
                TipCellView(viewModel: .olvidPlus(olvidPlusTipViewModel), actions: actionsForPreviews)
                    .padding(.bottom)
            }
        }.padding()
    }
    //.environment(\.locale, .init(identifier: "fr-FR"))
}

#Preview("Backups: Setup") {
    TipCellView(viewModel: .backup(.newBackupsShouldBeSetup), actions: actionsForPreviews)
}

#Preview("Backups: Write key") {
    TipCellView(viewModel: .backup(.rememberToWriteDownBackupKey), actions: actionsForPreviews)
}

#Preview("Read receipts") {
    TipCellView(viewModel: .doSendReadReceipt, actions: actionsForPreviews)
}

#Preview("Archive") {
    TipCellView(viewModel: .archivedDiscussionsHelpMessage(discussionsAreUnarchivedAutomatically: true), actions: actionsForPreviews)
}

#endif
