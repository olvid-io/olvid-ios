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


protocol StolenOrCompromisedKeyViewActionsDelegate: AnyObject {
    @MainActor func userWantsToEraseAndGenerateNewDeviceBackupSeed() async throws
    @MainActor func userWantsToNavigateToBackupKeyDisplayerView()
}


struct StolenOrCompromisedKeyView: View {
    
    let actions: StolenOrCompromisedKeyViewActionsDelegate
    
    private enum EraseAndGenerateNewKeyStatus {
        case none
        case ongoing
        case succeeded
        case failed
    }

    @State private var presentEraseAndGenerateNewKeyConfirmation: Bool = false
    @State private var status: EraseAndGenerateNewKeyStatus = .none
    
    private func userWantsToEraseAndGenerateNewDeviceBackupSeed() {
        status = .ongoing
        Task {
            do {
                try await actions.userWantsToEraseAndGenerateNewDeviceBackupSeed()
                withAnimation {
                    status = .succeeded
                }

            } catch {
                status = .failed
            }
        }
    }

    var body: some View {
        Form {
            
            Section {
                
                Button(action: { presentEraseAndGenerateNewKeyConfirmation = true }) {
                    HStack {
                        Text("ERASE_AND_GENERATE_NEW_KEY")
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
                
            } footer: {
                
                Label {
                    Text("ERASE_AND_GENERATE_COMPROMISED_KEY_EXPLANATION")
                } icon: {
                    Image(systemIcon: .infoCircle)
                }

            }
            
            if status == .succeeded {
                Button(action: actions.userWantsToNavigateToBackupKeyDisplayerView) {
                    HStack {
                        Text("SHOW_MY_NEW_KEY")
                        Spacer()
                        Image(systemIcon: .chevronRight)
                    }
                }
            }
            
        }
        .confirmationDialog(String(localizedInThisBundle: "ERASE_AND_GENERATE_NEW_KEY_CONFIRMATION_TITLE"), isPresented: $presentEraseAndGenerateNewKeyConfirmation, titleVisibility: .visible) {
            Button(role: .destructive, action: userWantsToEraseAndGenerateNewDeviceBackupSeed) {
                Text("ERASE_AND_GENERATE_NEW_KEY")
            }
        }
    }
    
}


// MARK: - Previews

private final class ActionsForPreviews: StolenOrCompromisedKeyViewActionsDelegate {
    
    @MainActor func userWantsToEraseAndGenerateNewDeviceBackupSeed() async throws {
        try! await Task.sleep(seconds: 2)
    }
    
    func userWantsToNavigateToBackupKeyDisplayerView() {}
    
}

#Preview {
    StolenOrCompromisedKeyView(actions: ActionsForPreviews())
}
