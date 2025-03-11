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
import ObvSystemIcon
import ObvTypes
import ObvAppCoreConstants


protocol WaitingForBackupRestoreViewActionsProtocol: AnyObject {
    /// Returns the CryptoId of the restore owned identity. When many identities were restored, only one is returned here
    func restoreBackupNow(backupRequestIdentifier: UUID) async throws -> ObvCryptoId
    func userWantsToEnableAutomaticBackup() async throws
    func backupRestorationSucceeded(restoredOwnedCryptoId: ObvCryptoId) async // 2023-09-15 Many Ids can be restored at this time, we only return one
    func backupRestorationFailed() async
}

struct WaitingForBackupRestoreView: View {
    
    let actions: WaitingForBackupRestoreViewActionsProtocol
    let model: Model
    
    @State private var backupRestoreRequested = false
    @State private var restoreState = RestoreState.restoreInProgress
    @State private var isAlertPresented: Bool = false
    @State private var alertType: AlertType? = nil

    struct Model {
        let backupRequestIdentifier: UUID
    }
    
    private enum AlertType {
        case couldNotEnableAutomaticBackup(error: LocalizedError)
    }

    fileprivate enum RestoreState {
        case restoreInProgress
        case restoreSucceeded(restoredOwnedCryptoId: ObvCryptoId)
        case restoreFailed(error: Error)
    }
    
    @MainActor
    private func restoreBackupNow() async {
        guard !backupRestoreRequested else { return }
        backupRestoreRequested = true
        do {
            let restoredOwnedCryptoId = try await actions.restoreBackupNow(backupRequestIdentifier: model.backupRequestIdentifier)
            restoreState = .restoreSucceeded(restoredOwnedCryptoId: restoredOwnedCryptoId)
        } catch {
            restoreState = .restoreFailed(error: error)
        }
    }
    
    private var alertTitle: String {
        switch alertType {
        case .couldNotEnableAutomaticBackup(let error):
            return error.errorDescription ?? DefaultError.couldNotEnableAutomaticBackup.errorDescription
        case nil:
            return DefaultError.genericError.errorDescription
        }
    }

    private var alertMessage: String {
        switch alertType {
        case .couldNotEnableAutomaticBackup(let error):
            return error.recoverySuggestion ?? DefaultError.couldNotEnableAutomaticBackup.recoverySuggestion
        case nil:
            return DefaultError.genericError.recoverySuggestion
        }
    }

    @MainActor
    private func userWantsToEnableAutomaticBackup() async {
        do {
            try await actions.userWantsToEnableAutomaticBackup()
            backupRestorationSucceeded()
        } catch {
            let localizedError = (error as? LocalizedError) ?? DefaultError.couldNotEnableAutomaticBackup
            alertType = .couldNotEnableAutomaticBackup(error: localizedError)
            isAlertPresented = true
        }
    }
    
    /// Error used when something when wrong but we fail to obtain a localized error
    private enum DefaultError: LocalizedError {
        case couldNotEnableAutomaticBackup
        case genericError
        var errorDescription: String {
            switch self {
            case .couldNotEnableAutomaticBackup:
                return String(localizedInThisBundle: "AUTOMATIC_BACKUP_COULD_NOT_BE_ENABLED_TITLE")
            case .genericError:
                return String(localizedInThisBundle: "ERROR")
            }
        }
        var recoverySuggestion: String {
            return String(localizedInThisBundle: "PLEASE_TRY_AGAIN_LATER")
        }
    }
    
    
    private func backupRestorationSucceeded() {
        let restoredOwnedCryptoId: ObvCryptoId
        switch restoreState {
        case .restoreSucceeded(let _restoredOwnedCryptoId):
            restoredOwnedCryptoId = _restoredOwnedCryptoId
        default:
            assertionFailure()
            return
        }
        Task { await actions.backupRestorationSucceeded(restoredOwnedCryptoId: restoredOwnedCryptoId) } // This call navigates to the next onboarding screen
    }
    
    
    private func backupRestorationFailed() {
        Task { await actions.backupRestorationFailed() } // This call navigates to the next onboarding screen
    }
    
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch restoreState {
                
            case .restoreInProgress:
                
                RestoringBackupView()
                
            case .restoreSucceeded:
                
                VStack {
                    ScrollView {
                        VStack {
                            NewOnboardingHeaderView(title: "TITLE_BACKUP_RESTORED", subtitle: nil)
                            Text("ENABLE_AUTOMATIC_BACKUP_EXPLANATION")
                                .padding()
                        }
                    }
                    VStack {
                        ValidateButton(title: "ENABLE_AUTOMATIC_BACKUP_AND_CONTINUE", systemIcon: .checkmarkCircleFill, action: { Task { await userWantsToEnableAutomaticBackup() } })
                            .padding(.bottom)
                        HStack {
                            Spacer()
                            Button("Later".localizedInThisBundle, action: backupRestorationSucceeded)
                        }
                    }.padding()
                }
                
                
            case .restoreFailed(error: let error):
                
                VStack {
                    ScrollView {
                        VStack {
                            NewOnboardingHeaderView(title: "Restore failed 🥺", subtitle: nil)
                            Text("RESTORE_BACKUP_FAILED_EXPLANATION")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                            if ObvAppCoreConstants.developmentMode || ObvAppCoreConstants.isTestFlight {
                                VStack {
                                    Text("ERROR_DESCRIPTION")
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(error.localizedDescription)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text((error as NSError).debugDescription)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(.horizontal)
                            }
                        }
                    }
                    ValidateButton(title: "Back", systemIcon: .arrowshapeTurnUpBackwardFill, action: backupRestorationFailed)
                        .padding()
                }

            }
            
        }
        .onAppear {
            Task { await restoreBackupNow() }
        }
        .alert(alertTitle,
                isPresented: $isAlertPresented,
                presenting: alertType)
        { _ in
        } message: { _ in
            Text(alertMessage)
        }
    }
}


// MARK: - Internal validate button

private struct ValidateButton: View {

    let title: LocalizedStringKey
    let systemIcon: SystemIcon
    let action: () -> Void
        
    var body: some View {
        Button(action: action) {
            Label(title, systemIcon: systemIcon)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.vertical)
                .frame(maxWidth: .infinity)
        }
        .background(Color.blue01)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
}


private struct RestoringBackupView: View {
    var body: some View {
        HStack {
            Spacer()
            VStack {
                Text("RESTORING_BACKUP_PLEASE_WAIT")
                    .font(.headline)
                    .fontWeight(.bold)
                ProgressView()
            }
            Spacer()
        }
    }
}


struct WaitingForBackupRestoreView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: WaitingForBackupRestoreViewActionsProtocol {
    
        private let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

        private let errorWhenEnablingAutomaticBackup: LocalizedError?
        private let errorWhenRestoringBackup: LocalizedError?

        init(errorWhenRestoringBackup: LocalizedError?, errorWhenEnablingAutomaticBackup: LocalizedError?) {
            self.errorWhenRestoringBackup = errorWhenRestoringBackup
            self.errorWhenEnablingAutomaticBackup = errorWhenEnablingAutomaticBackup
        }
        
        func backupRestorationIsOver() async {}
        
        func userWantsToEnableAutomaticBackup() async throws {
            if let errorWhenEnablingAutomaticBackup {
                throw errorWhenEnablingAutomaticBackup
            } else {
                // Do nothing to simulate success
            }
        }
        
        func restoreBackupNow(backupRequestIdentifier: UUID) async throws  -> ObvTypes.ObvCryptoId {
            if let errorWhenRestoringBackup {
                throw errorWhenRestoringBackup
            } else {
                try! await Task.sleep(seconds: 1)
                return ownedCryptoId
            }
        }
        
        func backupRestorationSucceeded(restoredOwnedCryptoId: ObvTypes.ObvCryptoId) async {
            // Should navigate to the next onboarding screen
        }

        func backupRestorationFailed() async {
            // Should navigate to the backup selection screen
        }

    }
    
    private static let actions = [
        ActionsForPreviews(errorWhenRestoringBackup: nil,
                           errorWhenEnablingAutomaticBackup: nil),
        ActionsForPreviews(errorWhenRestoringBackup: ObvErrorForPreviews.someError,
                           errorWhenEnablingAutomaticBackup: nil),
        ActionsForPreviews(errorWhenRestoringBackup: nil,
                           errorWhenEnablingAutomaticBackup: ObvErrorForPreviews.someError),
    ]
    private static let model = WaitingForBackupRestoreView.Model(backupRequestIdentifier: UUID())
    
    static var previews: some View {
        WaitingForBackupRestoreView(actions: actions[0], model: model) // No error when enabling automatic backups
        WaitingForBackupRestoreView(actions: actions[1], model: model) // When backup restore fails
        WaitingForBackupRestoreView(actions: actions[2], model: model) // When restore succeeds, but cannot enable auto auto backup
    }
    
    private enum ObvErrorForPreviews: LocalizedError {
        case someError
        
        var errorDescription: String? {
            switch self {
            case .someError:
                return "Some error"
            }
        }
        
        var recoverySuggestion: String? {
            switch self {
            case .someError:
                return String(localizedInThisBundle: "PLEASE_TRY_AGAIN_LATER")
            }
        }
        
    }
    
}
