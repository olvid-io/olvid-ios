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


@MainActor
protocol AdvancedSetupParametersViewActionsProtocol: AnyObject {
    func userValidatedAdvancedSetupParameterThusNewSeedMustBeGenerated(saveToKeychain: Bool) async throws -> BackupSeed
    func userValidatedAdvancedSetupParameterAndDoNotWantBackups() async throws
    func userValidatedAdvancedSetupParameterAndNewSeedWasGenerated(backupSeed: BackupSeed, savedToKeychain: Bool)
    func userValidatedAdvancedSetupParameterButNewSeedFailedToBeGenerate()
    func userValidatedAdvancedSetupParameterButDeactivationFailed()
}


enum BackupMode: CaseIterable, Identifiable {
    case keychain
    case manual
    case noBackup
    var id: Self { self }
}


struct AdvancedSetupParametersView: View {
    
    let actions: AdvancedSetupParametersViewActionsProtocol
    
    @State private var isDisabled = false
    @State private var chosenBackupMode: BackupMode = .keychain
        
    @State private var showAlertAsGenerationFailed: Bool = false
    @State private var errorOnFailedGeneration: Error?

    @State private var showAlertAsDeactivationFailed: Bool = false
    @State private var errorOnFailedDeactivation: Error?

    init(actions: AdvancedSetupParametersViewActionsProtocol) {
        self.actions = actions
    }
    
    
    private func validateButtonTapped() {
        isDisabled = true
        Task {
            do {
                switch chosenBackupMode {
                case .keychain:
                    let backupSeed = try await actions.userValidatedAdvancedSetupParameterThusNewSeedMustBeGenerated(saveToKeychain: true)
                    actions.userValidatedAdvancedSetupParameterAndNewSeedWasGenerated(backupSeed: backupSeed, savedToKeychain: true)
                case .manual:
                    let backupSeed = try await actions.userValidatedAdvancedSetupParameterThusNewSeedMustBeGenerated(saveToKeychain: false)
                    actions.userValidatedAdvancedSetupParameterAndNewSeedWasGenerated(backupSeed: backupSeed, savedToKeychain: false)
                case .noBackup:
                    do {
                        try await actions.userValidatedAdvancedSetupParameterAndDoNotWantBackups()
                    } catch {
                        errorOnFailedDeactivation = error
                        showAlertAsDeactivationFailed = true
                        return
                    }
                }
            } catch {
                errorOnFailedGeneration = error
                showAlertAsGenerationFailed = true
            }
        }
    }

    
    private struct BackupModeCardView: View {
        
        let backupMode: BackupMode
        @Binding var chosenBackupMode: BackupMode
        
        private var titleText: String {
            switch backupMode {
            case .keychain:
                String(localizedInThisBundle: "BACKUP_MODE_TITLE_KEYCHAIN")
            case .manual:
                String(localizedInThisBundle: "BACKUP_MODE_TITLE_MANUAL")
            case .noBackup:
                String(localizedInThisBundle: "BACKUP_MODE_TITLE_NO_BACKUP")
            }
        }
        
        private var bodyText: String {
            switch backupMode {
            case .keychain:
                String(localizedInThisBundle: "BACKUP_MODE_BODY_KEYCHAIN")
            case .manual:
                String(localizedInThisBundle: "BACKUP_MODE_BODY_MANUAL")
            case .noBackup:
                String(localizedInThisBundle: "BACKUP_MODE_BODY_NO_BACKUP")
            }
        }
        
        var body: some View {
            Button {
                withAnimation {
                    chosenBackupMode = backupMode
                }
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    ObvRadioButtonView(value: backupMode, selectedValue: $chosenBackupMode)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top) {
                            Text(titleText)
                                .font(.headline)
                            Spacer()
                            if backupMode == .keychain {
                                Text("RECOMMENDED")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .foregroundStyle(.white)
                                    .background(.blue)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(bodyText)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .buttonStyle(.plain)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke()
                    .foregroundStyle(chosenBackupMode == backupMode ? .blue : .secondary)
                    .transition(.identity)
            }
        }
    }
    
    
    var body: some View {
        ZStack {
            Color(UIColor.systemGroupedBackground).ignoresSafeArea()
            VStack {
                
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(BackupMode.allCases) { backupMode in
                            BackupModeCardView(backupMode: backupMode, chosenBackupMode: $chosenBackupMode)
                                .padding(.horizontal)
                        }
                        Spacer()
                    }
                }
                
                Button {
                    validateButtonTapped()
                } label: {
                    HStack {
                        Spacer()
                        Text("VALIDATE")
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding()

            }
        }
        .disabled(isDisabled)
        .alert(String(localizedInThisBundle: "WE_COULD_NOT_ACTIVATE_BACKUPS_PLEASE_TRY_AGAIN"), isPresented: $showAlertAsGenerationFailed, actions: {
            Button(String(localizedInThisBundle: "OK"), action: actions.userValidatedAdvancedSetupParameterButNewSeedFailedToBeGenerate)
        }, message: {
            if let errorDescription = errorOnFailedGeneration?.localizedDescription {
                Text(errorDescription)
            }
        })
        .alert(String(localizedInThisBundle: "WE_COULD_NOT_DEACTIVATE_BACKUPS_PLEASE_TRY_AGAIN"), isPresented: $showAlertAsDeactivationFailed, actions: {
            Button(String(localizedInThisBundle: "OK"), action: actions.userValidatedAdvancedSetupParameterButDeactivationFailed)
        }, message: {
            if let errorDescription = errorOnFailedDeactivation?.localizedDescription {
                Text(errorDescription)
            }
        })

    }
}


// MARK: - Previews

private final class ActionsForPreviews: AdvancedSetupParametersViewActionsProtocol {
    
    func userValidatedAdvancedSetupParameterThusNewSeedMustBeGenerated(saveToKeychain: Bool) async throws -> ObvCrypto.BackupSeed {
        try await Task.sleep(seconds: 1)
        throw NSError(domain: "FAILED", code: 0)
        //return .init(with: Data(repeating: 0x04, count: 20))!
    }
    
    func userValidatedAdvancedSetupParameterAndDoNotWantBackups() async throws {
        try await Task.sleep(seconds: 1)
        throw NSError(domain: "DEACTIVATION_FAILED", code: 1)
    }
        
    func userValidatedAdvancedSetupParameterAndNewSeedWasGenerated(backupSeed: ObvCrypto.BackupSeed, savedToKeychain: Bool) {}
    
    func userValidatedAdvancedSetupParameterButNewSeedFailedToBeGenerate() {}
    
    func userValidatedAdvancedSetupParameterButDeactivationFailed() {}
    
}


#Preview {
    AdvancedSetupParametersView(actions: ActionsForPreviews())
}
