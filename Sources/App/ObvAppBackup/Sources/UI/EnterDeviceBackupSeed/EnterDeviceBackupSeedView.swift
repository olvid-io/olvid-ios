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
import ObvTypes
import ObvDesignSystem


@MainActor
protocol EnterDeviceBackupSeedViewActionsProtocol<ListModel>: AnyObject {
    associatedtype ListModel: ListOfBackupedProfilesFromServerViewModelProtocol
    func userWantsToUseDeviceBackupSeed(_ backupSeed: BackupSeed) async throws -> ListModel
    func userWantsToRestoreLegacyBackup(_ backupSeed: BackupSeed)
    func userWantsToNavigateToListOfBackupedProfilesAcrossDeviceView(listModel: ListModel)
}


struct EnterDeviceBackupSeedView<ListModel: ListOfBackupedProfilesFromServerViewModelProtocol>: View {
    
    let allowLegacyBackupRestoration: Bool
    let actions: any EnterDeviceBackupSeedViewActionsProtocol<ListModel>

    @State private var enteredBackupSeed: String = ""
    @State private var deviceBackupSeed: BackupSeed?
    
    @State private var isProgressViewShown = false
    @State private var isTextFieldDisabled = false
    @State private var isButtonDisabled = false
    
    @State private var requestedBackupSeedFailed = false

    private let textFieldTitle = String(repeating: "X", count: 32)
    
    private func userWantsToUseDeviceBackupSeed() {
        guard let deviceBackupSeed else { assertionFailure(); return }
        isTextFieldDisabled = true
        isButtonDisabled = true
        isProgressViewShown = true
        requestedBackupSeedFailed = false
        Task {
            defer { isProgressViewShown = false }
            do {
                let listModel = try await actions.userWantsToUseDeviceBackupSeed(deviceBackupSeed)
                actions.userWantsToNavigateToListOfBackupedProfilesAcrossDeviceView(listModel: listModel)
                isTextFieldDisabled = false
                isButtonDisabled = false
            } catch {
                isTextFieldDisabled = false
                isButtonDisabled = false
                requestedBackupSeedFailed = true
            }
        }
    }
    
    private func onChangeOfEnteredBackupSeed() {
        if let seed = BackupSeed(enteredBackupSeed) {
            deviceBackupSeed = seed
        } else {
            deviceBackupSeed = nil
            requestedBackupSeedFailed = false
        }
    }
    
    private let listTitle = String(localizedInThisBundle: "AVAILABLE_BACKUPED_PROFILES_FOR_THIS_KEY")

    var body: some View {
                
        List {

            HStack {
                Spacer(minLength: 0)
                ObvHeaderView(title: String(localizedInThisBundle: "RESTORE_ONE_OF_YOUR_BACKUPS"),
                              subtitle: String(localizedInThisBundle: "ENTER_A_BACKUP_KEY"))
                Spacer(minLength: 0)
            }
            .listRowSeparator(.hidden)
            .padding(.bottom, 20)

            Section {
                
                HStack {
                    Spacer(minLength: 0)
                    
                    VStack {
                        
                        BackupKeyView(kind: .editable(value: $enteredBackupSeed))
                            .onChange(of: enteredBackupSeed) { newValue in
                                onChangeOfEnteredBackupSeed()
                            }
                            .disabled(isTextFieldDisabled)
                        
                        Button(action: userWantsToUseDeviceBackupSeed) {
                            HStack {
                                Spacer(minLength: 0)
                                Text("VALIDATE")
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 8)
                        }
                        .padding(.top,8)
                        .frame(width: BackupKeyView.Constant.width)
                        .buttonStyle(.borderedProminent)
                        .disabled(deviceBackupSeed == nil)
                        .listRowSeparator(.hidden)
                        .disabled(isButtonDisabled)

                    }
                        
                    Spacer(minLength: 0)
                }
                .listRowSeparator(.hidden)

            }

            if isProgressViewShown {
                HStack {
                    Spacer(minLength: 0)
                    ProgressView()
                        .id(UUID()) // Otherwise, the progress is shown only once
                    Spacer(minLength: 0)
                }
                .listRowSeparator(.hidden)
            }

            if requestedBackupSeedFailed {
                HStack {
                    Spacer(minLength: 0)
                    // We use a Markdown trick so as to show an in-line link instead of a button.
                    Text(allowLegacyBackupRestoration ? "WE_COULD_NOT_FIND_ANY_BACKUP_FOR_THIS_KEY_SO_[RESTORE_LEGACY](_)" : "WE_COULD_NOT_FIND_ANY_BACKUP_FOR_THIS_KEY")
                        .environment(\.openURL, OpenURLAction { url in
                            guard let deviceBackupSeed else { assertionFailure(); return .discarded }
                            actions.userWantsToRestoreLegacyBackup(deviceBackupSeed)
                            return .discarded
                        })
                        .frame(width: BackupKeyView.Constant.width)
                    Spacer(minLength: 0)
                }
                .listRowSeparator(.hidden)
            }
            
        }
        .listStyle(.plain)
        .listRowSpacing(10)

    }
}


// MARK: - Previews

#if DEBUG

@MainActor
private final class ActionsForPreviews: EnterDeviceBackupSeedViewActionsProtocol {
    
    func fetchAvatarImage(profileCryptoId: ObvTypes.ObvCryptoId, encodedPhotoServerKeyAndLabel: Data?, frameSize: ObvDesignSystem.ObvAvatarSize) async -> UIImage? {
        let actions = AvatarActionsForPreviews()
        return await actions.fetchAvatarImage(profileCryptoId: profileCryptoId, encodedPhotoServerKeyAndLabel: encodedPhotoServerKeyAndLabel, frameSize: frameSize)
    }
    
    
    func userWantsToNavigateToListOfAllProfileBackups(profileCryptoId: ObvCryptoId, profileName: String, profileBackupSeed: ObvCrypto.BackupSeed) {}
    
    func userWantsToUseDeviceBackupSeed(_ backupSeed: ObvCrypto.BackupSeed) async throws -> ListOfBackupedProfilesFromServerViewModelForPreviews {

        // Uncomment to simulate a wront password seed
        //try! await Task.sleep(seconds: 2)
        //throw NSError(domain: "", code: 0)
        
        // Simulates a list of 2 backups
        return ListOfBackupedProfilesFromServerViewModelForPreviews(range: 0..<2)
        
    }
    
    func userWantsToRestoreLegacyBackup(_ backupSeed: BackupSeed) {}
    
    func userWantsToNavigateToListOfBackupedProfilesAcrossDeviceView(listModel: ListModel) {
        // Nothing to simulate
    }
    
    typealias ListModel = ListOfBackupedProfilesFromServerViewModelForPreviews
    
}

#Preview {
    EnterDeviceBackupSeedView(allowLegacyBackupRestoration: false, actions: ActionsForPreviews())
}

#endif
