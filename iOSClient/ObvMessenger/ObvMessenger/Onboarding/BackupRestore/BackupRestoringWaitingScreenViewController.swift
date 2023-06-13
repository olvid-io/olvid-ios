/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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

import ObvEngine
import ObvUI
import SwiftUI
import ObvUICoreData


protocol BackupRestoringWaitingScreenViewControllerDelegate: AnyObject {
    func userWantsToStartOnboardingFromScratch() async
    @MainActor func ownedIdentityRestoredFromBackupRestore() async
}

/// This view controller is shown right after the user entered her backup key. It shows a confirmation message if the backup was restored, or an error message if not.
/// In case the backup was restored, the user gets a chance to activate automatic backups to iCloud.
final class BackupRestoringWaitingScreenHostingController: UIHostingController<BackupRestoringWaitingScreenView> {

    fileprivate let model: BackupRestoringWaitingScreenModel

    var delegate: BackupRestoringWaitingScreenViewControllerDelegate? {
        get {
            self.model.delegate
        }
        set {
            self.model.delegate = newValue
        }
    }
    
    var appBackupDelegate: AppBackupDelegate? {
        get {
            self.model.appBackupDelegate
        }
        set {
            self.model.appBackupDelegate = newValue
        }
    }

    init(backupRequestUuid: UUID, obvEngine: ObvEngine) {
        self.model = BackupRestoringWaitingScreenModel(backupRequestUuid: backupRequestUuid, obvEngine: obvEngine)
        let view = BackupRestoringWaitingScreenView(model: self.model)
        super.init(rootView: view)
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { await model.restoreFullBackupNow() }
    }

}

fileprivate enum RestoreState {
    case restoreInProgress
    case restoreSucceeded
    case restoreFailed
    case restoreSucceededButActivationOfAutomaticBackupsFailed(title: String, message: String)
}

fileprivate class BackupRestoringWaitingScreenModel: ObservableObject {

    let obvEngine: ObvEngine
    let backupRequestUuid: UUID
    weak var delegate: BackupRestoringWaitingScreenViewControllerDelegate?
    weak var appBackupDelegate: AppBackupDelegate?
    
    init(backupRequestUuid: UUID, obvEngine: ObvEngine) {
        self.backupRequestUuid = backupRequestUuid
        self.obvEngine = obvEngine
    }
    
    @Published var restoreState: RestoreState = .restoreInProgress

    func userWantsToStartOnboardingFromScratch() {
        Task { await delegate?.userWantsToStartOnboardingFromScratch() }
    }

    func ownedIdentityRestoredFromBackupRestore() {
        Task { await delegate?.ownedIdentityRestoredFromBackupRestore() }
    }


    @MainActor
    fileprivate func restoreFullBackupNow() async {
        do {
            try await obvEngine.restoreFullBackup(backupRequestIdentifier: backupRequestUuid)
            withAnimation {
                restoreState = .restoreSucceeded
            }
        } catch {
            withAnimation {
                restoreState = .restoreFailed
            }
        }
    }
    

    /// Activates automatic backups to iCloud.
    /// - Returns: `nil`if this method succeeds, or an error title and message if it fails.
    @MainActor
    func userWantsToEnableAutomaticBackup() async {
        if let errorTitleAndMessage = await userWantsToEnableAutomaticBackup() {
            withAnimation {
                self.restoreState = .restoreSucceededButActivationOfAutomaticBackupsFailed(title: errorTitleAndMessage.title, message: errorTitleAndMessage.message)
            }
        } else {
            ownedIdentityRestoredFromBackupRestore()
        }
    }
    
    
    /// Activates automatic backups to iCloud.
    /// - Returns: `nil`if this method succeeds, or an error title and message if it fails.
    private func userWantsToEnableAutomaticBackup() async -> (title: String, message: String)? {

        guard !ObvMessengerSettings.Backup.isAutomaticBackupEnabled else { return nil }
        guard let appBackupDelegate else { assertionFailure(); return nil }
        
        // The user wants to activate automatic backup.
        // We must check whether it's possible.
        do {
            let accountStatus = try await appBackupDelegate.getAccountStatus()
            if case .available = accountStatus {
                obvEngine.userJustActivatedAutomaticBackup()
                ObvMessengerSettings.Backup.isAutomaticBackupEnabled = true
                return nil
            } else {
                guard let titleAndMessage = AppBackupManager.CKAccountStatusMessage(accountStatus) else {
                    assertionFailure()
                    return AppBackupManager.CKAccountStatusMessage(.couldNotDetermine)
                }
                return titleAndMessage
            }
        } catch {
            return AppBackupManager.CKAccountStatusMessage(.noAccount)
        }
    }

    
}


struct BackupRestoringWaitingScreenView: View {

    @ObservedObject fileprivate var model: BackupRestoringWaitingScreenModel

    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    switch model.restoreState {
                    case .restoreInProgress:
                        Text(Strings.restoringBackup)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    case .restoreSucceeded, .restoreSucceededButActivationOfAutomaticBackupsFailed:
                        Text("TITLE_BACKUP_RESTORED")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    case .restoreFailed:
                        Text(Strings.restoreFailed)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                    }
                    Spacer()
                }
                ObvCardView {
                    switch model.restoreState {
                    case .restoreInProgress:
                        HStack {
                            Spacer()
                            ObvActivityIndicator(isAnimating: .constant(true), style: .large, color: nil)
                            Spacer()
                        }
                    case .restoreSucceeded:
                        Text("ENABLE_AUTOMATIC_BACKUP_EXPLANATION")
                            .frame(minWidth: .none,
                                   maxWidth: .infinity,
                                   minHeight: .none,
                                   idealHeight: .none,
                                   maxHeight: .none,
                                   alignment: .center)
                    case .restoreFailed:
                        Text("RESTORE_BACKUP_FAILED_EXPLANATION")
                            .frame(minWidth: .none,
                                   maxWidth: .infinity,
                                   minHeight: .none,
                                   idealHeight: .none,
                                   maxHeight: .none,
                                   alignment: .center)
                    case .restoreSucceededButActivationOfAutomaticBackupsFailed(title: let title, message: let message):
                        VStack {
                            Text(title)
                                .font(.body)
                                .fontWeight(.heavy)
                                .lineLimit(1)
                            Text(message)
                                .font(.body)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                switch model.restoreState {
                case .restoreInProgress:
                    EmptyView()
                case .restoreSucceeded, .restoreSucceededButActivationOfAutomaticBackupsFailed:
                    if model.appBackupDelegate != nil {
                        OlvidButton(style: .blue, title: Text("ENABLE_AUTOMATIC_BACKUP_AND_CONTINUE")) {
                            Task {
                                await model.userWantsToEnableAutomaticBackup()
                            }
                        }
                        OlvidButton(style: .standard, title: Text("Later")) {
                            model.ownedIdentityRestoredFromBackupRestore()
                        }
                    } else {
                        OlvidButton(style: .standard, title: Text("Continue")) {
                            model.ownedIdentityRestoredFromBackupRestore()
                        }
                    }
                case .restoreFailed:
                    OlvidButton(style: .standard, title: Text("Back")) {
                        model.userWantsToStartOnboardingFromScratch()
                    }
                }
                Spacer()
            }.padding()

        }
    }

     private struct Strings {
         static let restoringBackup = NSLocalizedString("RESTORING_BACKUP_PLEASE_WAIT", comment: "Title centered on screen")
         static let restoreFailed = NSLocalizedString("Restore failed 🥺", comment: "Body displayed when a backup restore failed")
     }
}
