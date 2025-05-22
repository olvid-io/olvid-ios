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
import ObvCrypto
import ObvDesignSystem
import ObvTypes


@MainActor
protocol ListOfBackupsOfProfileViewModelProtocol: AnyObject, ObservableObject {
    var listOfProfileBackups: ListOfProfileBackupsFromServerView.Model? { get }
    var profileBackupSeed: BackupSeed { get }
    func fetchListOfProfileBackups() async
}


protocol ListOfBackupsOfProfileViewActionsProtocol: AnyObject {
    @MainActor func userWantsToRestoreProfileBackup(profileBackupFromServer: ObvProfileBackupFromServer) async throws
}


protocol ContextOfListOfBackupsOfProfileSettingsActionsDelegate: AnyObject {
    @MainActor func userWantsToRestoreProfileBackupFromSettingsMenu(profileBackupFromServer: ObvProfileBackupFromServer) async throws
    @MainActor func userWantsToDeleteProfileBackupFromSettingsMenu(infoForDeletion: ObvProfileBackupFromServer.InfoForDeletion) async throws
}

enum ContextOfListOfBackupsOfProfile {
    case onboarding
    case settings(actions: ContextOfListOfBackupsOfProfileSettingsActionsDelegate)
}


/// View shown when the user selects a profile that they want to restore. In that case, we fetch all the available backups of that profile
/// (one per device where the profile was used). This view lists these profile backups, allowing the user to choose the one to be
/// restored.
///
/// We expect the model to fetch these backups in its `onTask()` method, and to set its published `getter:listOfProfileBackups` property.
///
struct ListOfBackupsOfProfileView<Model: ListOfBackupsOfProfileViewModelProtocol>: View {
    
    @ObservedObject var model: Model
    let context: ContextOfListOfBackupsOfProfile
    let actions: ListOfBackupsOfProfileViewActionsProtocol
        
    @State private var selectedProfileBackup: ObvProfileBackupFromServer?
    @State private var isInterfaceDisabled: Bool = false
    @State private var showWaitingIndicator: Bool = false

    @State private var errorOnRestore: Error?
    @State private var presentErrorOnRestoreAlert: Bool = false

    @State private var presentConfirmationDialogForOldBackupRestoreRequest: Bool = false

    private func onTask() async {
        await model.fetchListOfProfileBackups()
    }
    
    private func refreshListRequested() async {
        await model.fetchListOfProfileBackups()
    }
    
    private struct WaitingView: View {
        var body: some View {
            VStack {
                ProgressView()
                    .padding()
                    .progressViewStyle(.circular)
                Text("ONE_MOMENT_PLEASE")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                Text("PLEASE_WAIT_WHILE_WE_LOAD_THE_BACKUPS")
                    .multilineTextAlignment(.center)
                    .font(.headline)
            }
        }
    }
    
    
    private struct TitleView: View {
        let numberOfProfileBackups: Int
        private let title = String(localizedInThisBundle: "WHICH_PROFILE_BACKUP_DO_YOU_WISH_TO_RESTORE")
        private func subtitle(numberOfProfileBackups: Int) -> String {
            return String(localizedInThisBundle: "\(numberOfProfileBackups)_BACKUPS_FOUND")
        }
        var body: some View {
            HStack {
                Spacer(minLength: 0)
                ObvHeaderView(title: title, subtitle: subtitle(numberOfProfileBackups: numberOfProfileBackups))
                Spacer(minLength: 0)
            }
        }
    }
    
    
    private func restoreButtonTapped(userConfirmedOldBackupRestore: Bool = false) {
        guard let selectedProfileBackup else { return }
        
        if !userConfirmedOldBackupRestore,
           let recommendedProfileBackup = model.listOfProfileBackups?.recommendedProfileBackup,
           selectedProfileBackup.id != recommendedProfileBackup.id {
            
            presentConfirmationDialogForOldBackupRestoreRequest = true
            
        } else {
            
            proceedWithTheRestoration(selectedProfileBackup: selectedProfileBackup)
            
        }
    }
    
    
    private func proceedWithTheRestoration(selectedProfileBackup: ObvProfileBackupFromServer) {
        isInterfaceDisabled = true
        showWaitingIndicator = true
        Task {
            defer {
                withAnimation {
                    isInterfaceDisabled = false
                    showWaitingIndicator = false
                }
            }
            do {
                try await actions.userWantsToRestoreProfileBackup(profileBackupFromServer: selectedProfileBackup)
            } catch {
                errorOnRestore = error
                presentErrorOnRestoreAlert = true
            }
        }
    }
    

    var body: some View {
        if let listOfProfileBackups = model.listOfProfileBackups {
            
            if listOfProfileBackups.profileBackups.isEmpty {
                
                VStack {
                    TitleView(numberOfProfileBackups: listOfProfileBackups.profileBackups.count)
                        .padding(.bottom, 40)
                    Text("TRY_AGAIN_LATER")
                        .font(.title2)
                    Spacer()
                }
                .padding(.horizontal)
                
            } else {
                
                switch context {

                case .onboarding:
                    
                    VStack {
                        
                        List {
                            TitleView(numberOfProfileBackups: listOfProfileBackups.profileBackups.count)
                                .padding(.bottom)
                                .listRowSeparator(.hidden)
                            ListOfProfileBackupsFromServerView(model: listOfProfileBackups, context: context, selectedProfileBackup: $selectedProfileBackup, refreshListRequested: refreshListRequested)
                                .disabled(isInterfaceDisabled)
                                .padding(.horizontal)
                                .onAppear { self.selectedProfileBackup = listOfProfileBackups.profileBackups.first }
                        }
                        .listStyle(.plain)
                        .listRowSpacing(10)
                        
                        Button {
                            restoreButtonTapped()
                        } label: {
                            HStack {
                                Spacer(minLength: 0)
                                Text("RESTORE")
                                if showWaitingIndicator {
                                    ProgressView()
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding()
                        .disabled(selectedProfileBackup == nil || isInterfaceDisabled)
                        .confirmationDialog(String(localizedInThisBundle: "YOU_REQUESTED_THE_RESTORATION_OF_AN_OLD_BACKUP"),
                                            isPresented: $presentConfirmationDialogForOldBackupRestoreRequest,
                                            titleVisibility: .visible) {
                            Button(String(localizedInThisBundle: "RESTORE_THIS_OLD_BACKUP")) {
                                restoreButtonTapped(userConfirmedOldBackupRestore: true)
                            }
                        }
                        .alert(String(localizedInThisBundle: "WE_COULD_NOT_RESTORE_THIS_PROFILE"), isPresented: $presentErrorOnRestoreAlert) {
                            Button.init(action: {}) {
                                Text("OK")
                            }
                        } message: {
                            Text(errorOnRestore?.localizedDescription ?? String(localizedInThisBundle: "AN_ERROR_OCCURED"))
                        }

                    }

                case .settings:

                    List {
                        ListOfProfileBackupsFromServerView(model: listOfProfileBackups, context: context, selectedProfileBackup: $selectedProfileBackup, refreshListRequested: refreshListRequested)
                            .disabled(isInterfaceDisabled)
                            .padding(.horizontal)
                            .onAppear { self.selectedProfileBackup = listOfProfileBackups.profileBackups.first }
                    }
                    .listStyle(.plain)
                    .listRowSpacing(10)

                }
                
            }
            
        } else {
            WaitingView()
                .task(onTask)
        }
    }
}











// MARK: - Previews

#if DEBUG

private final class ModelForPreviews: ListOfBackupsOfProfileViewModelProtocol {
    
    let profileBackupSeed: BackupSeed
    @Published private(set) var listOfProfileBackups: ListOfProfileBackupsFromServerView.Model?
    
    init() {
        self.profileBackupSeed = BackupSeed(String(repeating: "0", count: 32))!
    }
    
    func fetchListOfProfileBackups() async {
        //try? await Task.sleep(seconds: 1)
        let listOfProfileBackups = ListOfProfileBackupsFromServerView.Model(
            profileBackups: ProfileBackupsForPreviews.profileBackups,
            recommendedProfileBackup: ProfileBackupsForPreviews.profileBackups.first!)
        withAnimation {
            self.listOfProfileBackups = listOfProfileBackups
        }
    }
}


private final class ActionsForPreviews: ListOfBackupsOfProfileViewActionsProtocol {
    func userWantsToRestoreProfileBackup(profileBackupFromServer: ObvProfileBackupFromServer) async throws {
        try? await Task.sleep(seconds: 2)
        throw ObvErrorForPreviews.restoreError
    }
    
    enum ObvErrorForPreviews: Error {
        case restoreError
    }
}


private final class OtherActionsForPreviews: ContextOfListOfBackupsOfProfileSettingsActionsDelegate {
    func userWantsToRestoreProfileBackupFromSettingsMenu(profileBackupFromServer: ObvTypes.ObvProfileBackupFromServer) async throws {
        try? await Task.sleep(seconds: 3)
    }
    func userWantsToDeleteProfileBackupFromSettingsMenu(infoForDeletion: ObvTypes.ObvProfileBackupFromServer.InfoForDeletion) async throws {
        try? await Task.sleep(seconds: 3)
    }
}


#Preview("Within onboarding") {
    ListOfBackupsOfProfileView(model: ModelForPreviews(), context: .onboarding, actions: ActionsForPreviews())
}

#Preview("Within settings") {
    ListOfBackupsOfProfileView(model: ModelForPreviews(), context: .settings(actions: OtherActionsForPreviews()), actions: ActionsForPreviews())
}

#endif
