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


protocol SecurityManagementViewActionsDelegate: AnyObject {
    @MainActor func userWantsToNavigateToBackupKeyDisplayerView()
    @MainActor func userWantsToNavigateToStolenOrCompromisedKeyView()
    @MainActor func userWantsToResetThisDeviceSeedAndBackups() async throws
}


struct SecurityManagementView: View {
    
    let actions: SecurityManagementViewActionsDelegate
    
    private struct DisplayYourKeyButton: View {
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack {
                    Text("DISPLAY_YOUR_KEY")
                    Spacer()
                    Image(systemIcon: .chevronRight)
                }
            }
        }
    }

    private struct StolenOrCompromisedKeyButton: View {
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack {
                    Text("STOLEN_OR_COMPROMISED_KEY")
                    Spacer()
                    Image(systemIcon: .chevronRight)
                }
            }
        }
    }
    
    
    @State private var presentResetAllConfirmation: Bool = false
    @State private var isUIDisabled: Bool = false
    @State private var resetAllErrorMessage: String?
    @State private var resetProgressViewIsShown: Bool = false
    
    func userWantsToResetThisDeviceSeedAndBackups() {
        withAnimation {
            resetAllErrorMessage = nil
            isUIDisabled = true
        }
        resetProgressViewIsShown = true
        Task {
            do {
                try await actions.userWantsToResetThisDeviceSeedAndBackups()
            } catch {
                resetProgressViewIsShown = false
                withAnimation {
                    isUIDisabled = false
                    resetAllErrorMessage = error.localizedDescription
                }
            }
        }
    }
    
    var body: some View {
        Form {
            
            Section {
                DisplayYourKeyButton(action: actions.userWantsToNavigateToBackupKeyDisplayerView)
                StolenOrCompromisedKeyButton(action: actions.userWantsToNavigateToStolenOrCompromisedKeyView)
            }
            
            Section {
                Button(role: .destructive, action: { presentResetAllConfirmation = true }) {
                    HStack {
                        Text("RESET")
                        Spacer()
                        ProgressView()
                            .opacity(resetProgressViewIsShown ? 1.0 : 0.0)
                    }
                }
            } footer: {
                VStack(alignment: .leading) {
                    Text("RESET_BUTTON_EXPLANATION")
                    Label { Text("RESET_BUTTON_EXPLANATION_EXPLANATION_STEP_1") } icon: { Image(systemIcon: .trash) }
                    Label { Text("RESET_BUTTON_EXPLANATION_EXPLANATION_STEP_2") } icon: { Image(systemIcon: .trash) }
                }
            }

            if let resetAllErrorMessage {
                Label {
                    Text("FAILED_TO_RESET_ALL_\(resetAllErrorMessage)")
                } icon: {
                    Image(systemIcon: .exclamationmarkCircle)
                        .foregroundStyle(.red)
                }

            }
            
        }
        .disabled(isUIDisabled)
        .confirmationDialog(String(localizedInThisBundle: "CONFIRM_RESET_ALL_TITLE"), isPresented: $presentResetAllConfirmation, titleVisibility: .visible) {
            Button(role: .destructive, action: userWantsToResetThisDeviceSeedAndBackups) {
                Text("RESET")
            }

        }
    }
    
}


// MARK: - Previews

private final class ActionsForPreviews: SecurityManagementViewActionsDelegate {
    func userWantsToNavigateToBackupKeyDisplayerView() {}
    func userWantsToNavigateToStolenOrCompromisedKeyView() {}
    func userWantsToResetThisDeviceSeedAndBackups() async throws {
        try await Task.sleep(seconds: 1)
        //throw NSError(domain: "Error domain", code: 0)
    }
}


#Preview {
    SecurityManagementView(actions: ActionsForPreviews())
}
