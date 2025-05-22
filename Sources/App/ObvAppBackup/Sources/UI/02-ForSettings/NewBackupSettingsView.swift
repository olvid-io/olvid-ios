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
import ObvDesignSystem


protocol NewBackupSettingsViewActionsProtocol: ICloudToggleViewActions {
    @MainActor func userWantsToNavigateToNavigateToSecuritySettings()
    @MainActor func userWantsToNavigateToManageBackups()
    @MainActor func userWantsToSubscribeOlvidPlus()
    @MainActor func userWantsToAddDevice()
    @MainActor func userWantsToPerformABackupNow() async throws
}


/// This is the entry point of the backup settings
struct NewBackupSettingsView: View {
    
    let subscriptionStatus: ObvSubscriptionStatusForAppBackup
    let actions: NewBackupSettingsViewActionsProtocol
    
    
    private enum MakeBackupNowStatus {
        case none
        case ongoing
        case succeeded
        case failed
    }
    
    @State private var makeBackupNowStatus: MakeBackupNowStatus = .none
    @State private var navigationTitle: String = ""
        
    private func userWantsToPerformABackupNow() {
        makeBackupNowStatus = .ongoing
        Task {
            do {
                try await actions.userWantsToPerformABackupNow()
                makeBackupNowStatus = .succeeded
            } catch {
                makeBackupNowStatus = .failed
            }
        }
    }
    
    private struct devicesImages: View {
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Image(systemIcon: .desktopcomputer)
                Image(systemIcon: .laptopcomputer)
                Image(systemIcon: .iphone)
            }
            .foregroundStyle(.secondary)
        }
    }
    
    
    private struct SubscribeButton: View {
        let subscriptionStatus: ObvSubscriptionStatusForAppBackup
        let action: () -> Void
        private var title: String {
            switch subscriptionStatus {
            case .noSubscription:
                String(localizedInThisBundle: "SUBSCRIBE_TO_OLVID_PLUS")
            case .multideviceSubscriptionWithOnlyOneDeviceUsed:
                String(localizedInThisBundle: "ADD_DEVICE")
            case .multideviceSubscriptionWithMultipleDevicesUsed:
                String(localizedInThisBundle: "ADD_DEVICE")
            }
        }
        var body: some View {
            Button(action: action) {
                Text(title)
            }
            .buttonStyle(.borderedProminent)
        }
    }
    
    
    fileprivate struct HintCard: View {
        let subscriptionStatus: ObvSubscriptionStatusForAppBackup
        let action: () -> Void
        private var bodyText: String {
            switch subscriptionStatus {
            case .noSubscription:
                String(localizedInThisBundle: "MULTIPLE_DEVICE_HINT_NO_SUBSCRIPTION")
            case .multideviceSubscriptionWithOnlyOneDeviceUsed:
                String(localizedInThisBundle: "MULTIPLE_DEVICE_HINT_SUBSCRIBED_ONE_DEVICE")
            case .multideviceSubscriptionWithMultipleDevicesUsed:
                String(localizedInThisBundle: "MULTIPLE_DEVICE_HINT_SUBSCRIBED_MULTIPLE_DEVICES")
            }
        }
        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemIcon: .lightbulbMax)
                    .font(.headline)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading) {
                    Text("HINT")
                        .font(.headline)
                    Text(bodyText)
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        devicesImages()
                            .padding(.trailing, 8)
                        switch subscriptionStatus {
                        case .noSubscription:
                            SubscribeButton(subscriptionStatus: subscriptionStatus, action: action)
                        case .multideviceSubscriptionWithOnlyOneDeviceUsed:
                            SubscribeButton(subscriptionStatus: subscriptionStatus, action: action)
                        case .multideviceSubscriptionWithMultipleDevicesUsed:
                            EmptyView()
                        }
                    }
                }
            }
        }
    }
    
    
    private struct SecurityButton: View {
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack {
                    Text("SECURITY")
                    Spacer()
                    Image(systemIcon: .chevronRight)
                }
            }
        }
    }

    
    private struct ManageBackupsButton: View {
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack {
                    Text("MANAGE_BACKUPS")
                    Spacer()
                    Image(systemIcon: .chevronRight)
                }
            }
        }
    }
    
    
    private struct MakeBackupNowButton: View {
        let action: () -> Void
        @Binding var status: MakeBackupNowStatus
        var body: some View {
            Button(action: action) {
                HStack {
                    Text("MAKE_BACKUP_NOW")
                    Spacer()
                    switch status {
                    case .none:
                        EmptyView()
                    case .ongoing:
                        ProgressView()
                    case .succeeded:
                        Image(systemIcon: .checkmarkCircle)
                            .foregroundStyle(.green)
                    case .failed:
                        Image(systemIcon: .exclamationmarkCircle)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(status == .ongoing)
        }
    }
    
    
    private func hintCardAction() {
        switch subscriptionStatus {
        case .noSubscription:
            actions.userWantsToSubscribeOlvidPlus()
        case .multideviceSubscriptionWithOnlyOneDeviceUsed:
            actions.userWantsToAddDevice()
        case .multideviceSubscriptionWithMultipleDevicesUsed:
            actions.userWantsToAddDevice()
        }
    }
    
    
    var body: some View {
        Form {
            
            ExplanationsSectionView(navigationTitle: $navigationTitle)

            Section {
                ICloudToggleView(mode: .updatingValue(actions: actions))
            } footer: {
                ICloudToggleViewFooter()
            }
                        
            Section(String(localizedInThisBundle: "BACKUPS")) {
                ManageBackupsButton(action: actions.userWantsToNavigateToManageBackups)
                MakeBackupNowButton(action: userWantsToPerformABackupNow, status: $makeBackupNowStatus)
            }
            
            Section {
                SecurityButton(action: actions.userWantsToNavigateToNavigateToSecuritySettings)
            } footer: {
                Text("SECURITY_EXPLANATION")
            }

            HintCard(subscriptionStatus: subscriptionStatus,
                     action: hintCardAction)

        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}




// MARK: - Previews

private final class Actions: NewBackupSettingsViewActionsProtocol {

    func userWantsToPerformABackupNow() async throws {
        try await Task.sleep(seconds: 1)
    }
    
    
    private var isSynchronizedWithICloud: Bool = false

    func usersWantsToGetBackupParameterIsSynchronizedWithICloud() async throws -> Bool {
        try! await Task.sleep(seconds: 1)
        return isSynchronizedWithICloud
    }
    
    func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(newIsSynchronizedWithICloud: Bool) async throws {
        try! await Task.sleep(seconds: 1)
        isSynchronizedWithICloud = newIsSynchronizedWithICloud
    }

    func userWantsToNavigateToNavigateToSecuritySettings() {}
    func userWantsToNavigateToManageBackups() {}
    func userWantsToSubscribeOlvidPlus() {}
    func userWantsToAddDevice() {}
}


#Preview {
    NewBackupSettingsView(subscriptionStatus: .noSubscription, actions: Actions())
}
