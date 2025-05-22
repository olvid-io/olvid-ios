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


protocol ChooseAutomaticBackupsOrNavigateToAdvancedSettingsViewActionsProtocol: AnyObject {
    @MainActor func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainThusNewSeedMustBeGenerated() async throws -> BackupSeed
    @MainActor func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedWasGenerated(_ backupSeed: BackupSeed)
    @MainActor func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedFailedToBeGenerated()
    @MainActor func userWantsToSeeAdvancedSetupParameters()
}


/// This view is typically displayed during the onboarding process, for new Olvid users.
/// It can also be displayed to all the users who are still using the "legacy" backups.
public enum ObvAppBackupSetupContext {
    case onboarding
    case afterOnboardingWithoutMigratingFromLegacyBackups
    case afterOnboardingMigratingFromLegacyBackups
}


/// This view allows the user to choose between a manual backup (where she shall write down the backup key) and iCloud backup (where the key is automatically saved to iCloud).
struct ChooseAutomaticBackupsOrNavigateToAdvancedSettingsView: View {
    
    let context: ObvAppBackupSetupContext
    let actions: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsViewActionsProtocol
    
    @State private var isDisabled = false
    @State private var navigationTitle: String = ""

    @State private var showAlertAsGenerationFailed: Bool = false
    @State private var errorOnFailedGeneration: Error?

    private func validateButtonTapped() {
        isDisabled = true
        Task {
            do {
                let backupSeed = try await actions.userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainThusNewSeedMustBeGenerated()
                actions.userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedWasGenerated(backupSeed)
            } catch {
                errorOnFailedGeneration = error
                showAlertAsGenerationFailed = true
            }
        }
    }
    
    private struct Explanation: View {
        let context: ObvAppBackupSetupContext
        private var explantationBody: String {
            switch context {
            case .onboarding, .afterOnboardingWithoutMigratingFromLegacyBackups:
                String(localizedInThisBundle: "CHOOSE_BETWEEN_MANUAL_AND_ICLOUD_BACKUPS_DURING_ONBOARDING")
            case .afterOnboardingMigratingFromLegacyBackups:
                String(localizedInThisBundle: "CHOOSE_BETWEEN_MANUAL_AND_ICLOUD_BACKUPS_WHILE_MIGRATING")
            }
        }
        var body: some View {
            HStack {
                Text(explantationBody)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
    }
    
    
    private struct LearnMoreButton: View {
        let action: () -> Void
        var body: some View {
            HStack {
                Spacer(minLength: 0)
                Button(String(localizedInThisBundle: "LEARN_MORE"), action: action)
            }
        }
    }
    
    
    private struct ValidateButton: View {

        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack {
                    Spacer(minLength: 0)
                    Text("ACTIVATE_AUTOMATIC_BACKUPS")
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        
    }
    
    
    private func userWantsToSeeAdvancedSetupParameters() {
        actions.userWantsToSeeAdvancedSetupParameters()
    }
    

    var body: some View {
        
        VStack {
            
            Form {
                
                ExplanationsSectionView(navigationTitle: $navigationTitle)
                
                Section {
                    
                    Explanation(context: context)
                    
                    Button {
                        userWantsToSeeAdvancedSetupParameters()
                    } label: {
                        HStack {
                            Text("ADVANCED_SETTINGS")
                            Spacer()
                            Image(systemIcon: .chevronRight)
                        }
                    }
                    
                }
                
            }
            
            ValidateButton(action: validateButtonTapped)
                .padding(.horizontal)
                .padding(.bottom)
            
        }
        .background(Color(UIColor.systemGroupedBackground))
        .disabled(isDisabled)
        .alert(String(localizedInThisBundle: "WE_COULD_NOT_ACTIVATE_BACKUPS_PLEASE_TRY_AGAIN"), isPresented: $showAlertAsGenerationFailed, actions: {
            Button(String(localizedInThisBundle: "OK"), action: actions.userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedFailedToBeGenerated)
        }, message: {
            if let errorDescription = errorOnFailedGeneration?.localizedDescription {
                Text(errorDescription)
            }
        })
        
    }
}


// MARK: - Previews

private final class ActionsForPreviews: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsViewActionsProtocol {
    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainThusNewSeedMustBeGenerated() async throws -> ObvCrypto.BackupSeed {
        try await Task.sleep(seconds: 1)
        throw NSError(domain: "", code: 0)
        //return .init(with: Data(repeating: 0x04, count: 20))!
    }
    
    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedWasGenerated(_ backupSeed: ObvCrypto.BackupSeed) {}

    func userChoseToActivateBackupsAndToSaveDeviceSeedToKeychainAndNewSeedFailedToBeGenerated() {}
    
    func userWantsToSeeAdvancedSetupParameters() {}
    
}


final class NavigationControllerForPreviews: UINavigationController {
        
    init() {
        let vc = UIHostingController(rootView: ChooseAutomaticBackupsOrNavigateToAdvancedSettingsView(context: .onboarding, actions: ActionsForPreviews()))
        super.init(rootViewController: vc)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.setNavigationBarHidden(true, animated: false)
        self.view.backgroundColor = .red
        self.navigationItem.largeTitleDisplayMode = .never
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


#Preview("Onboarding") {
    ChooseAutomaticBackupsOrNavigateToAdvancedSettingsView(context: .onboarding, actions: ActionsForPreviews())
}

#Preview("After onboarding - no migration") {
    ChooseAutomaticBackupsOrNavigateToAdvancedSettingsView(context: .afterOnboardingWithoutMigratingFromLegacyBackups, actions: ActionsForPreviews())
}

#Preview("After onboarding - migrating from legacy backups") {
    ChooseAutomaticBackupsOrNavigateToAdvancedSettingsView(context: .afterOnboardingMigratingFromLegacyBackups, actions: ActionsForPreviews())
}

@available(iOS 17.0, *)
#Preview("Within NavigationController") {
    NavigationControllerForPreviews()
}

