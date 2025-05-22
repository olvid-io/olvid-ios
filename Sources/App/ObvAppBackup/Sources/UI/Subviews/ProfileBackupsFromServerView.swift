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
import ObvSystemIcon
import ObvCrypto
import ObvAppCoreConstants



/// This view shows a profile backup made from a device. It is intended to be used by `ListOfProfileBackupsFromServerView` which lists
/// all the profiles backups made by all the devices where the profile was (or is) used.
struct ProfileBackupsFromServerView: View {
    
    let model: ObvProfileBackupFromServer
    let context: ContextOfListOfBackupsOfProfile
    let isRecommended: Bool
    @Binding var selectedBackup: ObvProfileBackupFromServer?
    @Binding var deletionOrRestorationInProgress: Bool
    var refreshListRequested: () async -> Void
    
    @State private var presentConfirmationDialogForOldBackupRestoreRequest: Bool = false
    @State private var deletionInProgress: Bool = false
    @State private var restorationInProgress: Bool = false
    
    @State private var errorOnRestore: Error?
    @State private var presentErrorOnRestoreAlert: Bool = false

    @State private var errorOnDeletion: Error?
    @State private var presentErrorOnDeletionAlert: Bool = false

    private var isSelected: Bool {
        self.model.id == selectedBackup?.id
    }
    

    private var groupsString: String { String(localizedInThisBundle: "\(model.parsedData.numberOfGroups)_GROUPS") }
    private var contactsString: String { String(localizedInThisBundle: "\(model.parsedData.numberOfContacts)_CONTACTS").lowercased() }
    private var groupsAndContactString: String { "\(groupsString), \(contactsString)" }

    
    private struct RecommendedBadge: View {
        var body: some View {
            Text("RECOMMENDED")
                .foregroundStyle(.white)
                .font(.caption)
                .padding(6)
                .background(Capsule().fill(Color(UIColor.systemGreen)))
        }
    }
    
    
    private struct FromThisDeviceBadge: View {
        var body: some View {
            Text("FROM_THIS_DEVICE")
                .foregroundStyle(.white)
                .font(.caption2)
                .padding(6)
                .background(Capsule().fill(Color(UIColor.systemBlue)))
        }
    }
    
    
    private func userWantsToRestoreProfileBackupFromSettingsMenu(userConfirmedOldBackupRestore: Bool = false) {
        guard !model.profileExistsOnThisDevice else { assertionFailure(); return }
        switch context {
        case .onboarding:
            assertionFailure()
        case .settings(let actions):
            guard isRecommended || userConfirmedOldBackupRestore else {
                presentConfirmationDialogForOldBackupRestoreRequest = true
                return
            }
            
            withAnimation {
                restorationInProgress = true
                deletionOrRestorationInProgress = true
            }
            
            Task {
                defer {
                    withAnimation {
                        restorationInProgress = false
                        deletionOrRestorationInProgress = false
                    }
                }
                do {
                    try await actions.userWantsToRestoreProfileBackupFromSettingsMenu(profileBackupFromServer: model)
                } catch {
                    errorOnRestore = error
                    presentErrorOnRestoreAlert = true
                }
            }
        }
    }
    
    
    private func userWantsToDeleteProfileBackupFromSettings() {
        switch context {
        case .onboarding:
            assertionFailure()
        case .settings(let actions):
            withAnimation {
                deletionInProgress = true
                deletionOrRestorationInProgress = true
            }
            Task {
                defer {
                    withAnimation {
                        deletionInProgress = false
                        deletionOrRestorationInProgress = false
                    }
                }
                do {
                    try await actions.userWantsToDeleteProfileBackupFromSettingsMenu(infoForDeletion: model.infoForDeletion)
                    await refreshListRequested()
                } catch {
                    errorOnDeletion = error
                    presentErrorOnDeletionAlert = true
                }
            }
        }
    }
    
    
    
    private struct DeletionInProgressView: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .foregroundStyle(.black)
                    .opacity(0.5)
                HStack {
                    Text("DELETING")
                        .font(.callout)
                        .foregroundStyle(.white)
                    ProgressView()
                        .tint(.white)
                }
                .padding()
                .background(Capsule().foregroundStyle(.red))
                .transition(.opacity)
            }
        }
    }

    
    private struct RestorationInProgressView: View {
        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .foregroundStyle(.black)
                    .opacity(0.5)
                HStack {
                    Text("RESTORING")
                        .font(.callout)
                        .foregroundStyle(.white)
                    ProgressView()
                        .tint(.white)
                }
                .padding()
                .background(Capsule().foregroundStyle(.green.opacity(1.0)))
                .transition(.opacity)
            }
        }
    }

    
    var body: some View {
        
        switch context {
        case .onboarding:
            
            Button {
                self.selectedBackup = self.model
            } label: {
                HStack(alignment: .top) {
                    DeviceImageView(platform: model.additionalInfosForProfileBackup.platformOfDeviceWhichPerformedBackup)
                    VStack(alignment: .leading) {
                        HStack {
                            Text(model.creationDate.formatted(.dateTime.year().month().day().hour().minute()))
                                .foregroundStyle(.primary)
                            Spacer()
                            RecommendedBadge()
                                .opacity(isRecommended ? 1 : 0)
                        }
                        Text(groupsAndContactString)
                            .foregroundStyle(.secondary)
                        HStack(alignment: .lastTextBaseline) {
                            Text("FROM_DEVICE_\(model.additionalInfosForProfileBackup.nameOfDeviceWhichPerformedBackup)")
                                .foregroundStyle(.secondary)
                            if model.backupMadeByThisDevice {
                                Spacer().overlay(alignment: .leadingFirstTextBaseline) {
                                    FromThisDeviceBadge()
                                        .offset(x: 8, y: -2)
                                }
                            } else {
                                Spacer()
                            }
                        }
                        
                    }
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(UIColor.secondarySystemFill)))
            }
            .buttonStyle(.plain)
            .padding(1)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(UIColor.secondaryLabel)).opacity(isSelected ? 1 : 0))

        case .settings:
            
            HStack(alignment: .top) {
                DeviceImageView(platform: model.additionalInfosForProfileBackup.platformOfDeviceWhichPerformedBackup)
                VStack(alignment: .leading) {
                    HStack {
                        Text(model.creationDate.formatted(.dateTime.year().month().day().hour().minute()))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    Text(groupsAndContactString)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .lastTextBaseline) {
                        Text("FROM_DEVICE_\(model.additionalInfosForProfileBackup.nameOfDeviceWhichPerformedBackup)")
                            .foregroundStyle(.secondary)
                        if model.backupMadeByThisDevice {
                            Spacer().overlay(alignment: .leadingFirstTextBaseline) {
                                FromThisDeviceBadge()
                                    .offset(x: 8, y: -2)
                            }
                        } else {
                            Spacer()
                        }
                    }
                    
                }
                Spacer(minLength: 0)
                Menu {
                    
                    if !model.profileExistsOnThisDevice {
                        Button {
                            userWantsToRestoreProfileBackupFromSettingsMenu()
                        } label: {
                            Label { Text("RESTORE") } icon: { Image(systemIcon: .icloudAndArrowDown) }
                        }
                    }

                    Button(role: .destructive) {
                        userWantsToDeleteProfileBackupFromSettings()
                    } label: {
                        Label { Text("DELETE") } icon: { Image(systemIcon: .trash) }
                            
                    }

                } label: {
                    Image(systemIcon: .ellipsisCircle)
                        .font(.headline)
                }
                .disabled(deletionInProgress || restorationInProgress)

            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(UIColor.secondarySystemFill)))
            .overlay {
                if deletionInProgress {
                    DeletionInProgressView()
                } else if restorationInProgress {
                    RestorationInProgressView()
                }
            }
            .alert(String(localizedInThisBundle: "WE_COULD_NOT_RESTORE_THIS_PROFILE"), isPresented: $presentErrorOnRestoreAlert) {
                Button.init(action: {}) {
                    Text("OK")
                }
            } message: {
                Text(errorOnRestore?.localizedDescription ?? String(localizedInThisBundle: "AN_ERROR_OCCURED"))
            }
            .alert(String(localizedInThisBundle: "WE_COULD_NOT_DELETE_THIS_PROFILE"), isPresented: $presentErrorOnDeletionAlert) {
                Button.init(action: {}) {
                    Text("OK")
                }
            } message: {
                Text(errorOnDeletion?.localizedDescription ?? String(localizedInThisBundle: "AN_ERROR_OCCURED"))
            }
            .confirmationDialog(String(localizedInThisBundle: "YOU_REQUESTED_THE_RESTORATION_OF_AN_OLD_BACKUP"),
                                isPresented: $presentConfirmationDialogForOldBackupRestoreRequest,
                                titleVisibility: .visible) {
                Button(String(localizedInThisBundle: "RESTORE_THIS_OLD_BACKUP")) {
                    userWantsToRestoreProfileBackupFromSettingsMenu(userConfirmedOldBackupRestore: true)
                }
            }
        }
        
    }
}



// MARK: - Previews

#if DEBUG
private struct NodeForPreviews: ObvSyncSnapshotNode {
    
    var id = UUID()
    
}

private struct PreviewHelper: View {
    
    @State private var selectedBackup: ObvProfileBackupFromServer?
    @State private var deletionOrRestorationInProgress: Bool = false
    let context: ContextOfListOfBackupsOfProfile
    
    static let prng = ObvCryptoSuite.sharedInstance.concretePRNG().init(with: Seed(with: Data(repeating: 0x00, count: Seed.minLength))!)
    static let serverURL = URL(string: "https://fake.server.olvid.io")!
    
    private let model: ObvProfileBackupFromServer = .init(
        ownedCryptoId: PreviewsHelper.cryptoIds.first!,
        profileExistsOnThisDevice: false,
        parsedData: .init(numberOfGroups: 12,
                          numberOfContacts: 42,
                          isKeycloakManaged: .no,
                          encodedPhotoServerKeyAndLabel: nil,
                          ownedCryptoIdentity: ObvOwnedCryptoIdentity.gen(withServerURL: serverURL, using: prng),
                          coreDetails: PreviewsHelper.coreDetails[0]),
        identityNode: NodeForPreviews(),
        appNode: NodeForPreviews(),
        additionalInfosForProfileBackup: .init(nameOfDeviceWhichPerformedBackup: "Alice's iPhone",
                                               platformOfDeviceWhichPerformedBackup: .iPhone),
        creationDate: Date.now,
        backupSeed: BackupSeed(with: Data(repeating: 0, count: 20))!,
        threadUID: UID.zero,
        backupVersion: 0,
        backupMadeByThisDevice: true)
    
    init(context: ContextOfListOfBackupsOfProfile) {
        selectedBackup = self.model
        self.context = context
    }
    
    var body: some View {
        ProfileBackupsFromServerView(model: model,
                                     context: context,
                                     isRecommended: false,
                                     selectedBackup: $selectedBackup,
                                     deletionOrRestorationInProgress: $deletionOrRestorationInProgress,
                                     refreshListRequested: {})
    }
}


private final class OtherActionsForPreviews: ContextOfListOfBackupsOfProfileSettingsActionsDelegate {
    func userWantsToRestoreProfileBackupFromSettingsMenu(profileBackupFromServer: ObvTypes.ObvProfileBackupFromServer) async throws {
        try? await Task.sleep(seconds: 3)
        throw ObvErrorForPreviews.someError
    }
    func userWantsToDeleteProfileBackupFromSettingsMenu(infoForDeletion: ObvTypes.ObvProfileBackupFromServer.InfoForDeletion) async throws {
        try? await Task.sleep(seconds: 3)
        throw ObvErrorForPreviews.someError
    }
    
    enum ObvErrorForPreviews: Error {
        case someError
    }
    
}


#Preview("Within onboarding") {
    PreviewHelper(context: .onboarding)
}


#Preview("Within settings") {
    PreviewHelper(context: .settings(actions: OtherActionsForPreviews()))
}

#endif
