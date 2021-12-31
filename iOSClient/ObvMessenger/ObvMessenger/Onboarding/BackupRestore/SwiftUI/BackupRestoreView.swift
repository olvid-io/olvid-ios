/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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


@available(iOS 13, *)
final class BackupRestoreViewHostingController: UIHostingController<BackupRestoreView> {
    
    private let backupRestoreViewModel: BackupRestoreViewModel
    
    init() {
        let backupRestoreViewModel = BackupRestoreViewModel()
        self.backupRestoreViewModel = backupRestoreViewModel
        let view = BackupRestoreView(store: backupRestoreViewModel)
        super.init(rootView: view)
    }
    
    var delegate: BackupRestoreViewHostingControllerDelegate? {
        get { backupRestoreViewModel.delegate }
        set { backupRestoreViewModel.delegate = newValue }
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: CloudFailureReason) {
        backupRestoreViewModel.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: cloudFailureReason)
    }
    
    func backupFileSelected(atURL url: URL, creationDate: Date? = nil) {
        backupRestoreViewModel.backupFileSelected(atURL: url, creationDate: creationDate)
    }
    
    func noMoreCloudBackupToFetch() {
        backupRestoreViewModel.noMoreCloudBackupToFetch()
    }
    
    func userCanceledSelectionOfBackupFile() {
        backupRestoreViewModel.userCanceledSelectionOfBackupFile()
    }
}


@available(iOS 13, *)
protocol BackupRestoreViewHostingControllerDelegate: AnyObject {
    func userWantsToRestoreBackupFromFile()
    func userWantToRestoreBackupFromCloud()
    func proceedWithBackupFile(atUrl: URL)
}


@available(iOS 13, *)
fileprivate final class BackupRestoreViewModel: ObservableObject {
    
    @Published private(set) var backupFileUrl: URL?
    @Published private(set) var backupCreationDate: Date?
    @Published var userIsRequestingBackupFileOrCloudBackup = false
    
    @Published fileprivate var isAlertPresented = false
    @Published fileprivate var alertType = AlertType.none
    
    fileprivate enum AlertType {
        case cloudFailure(reason: CloudFailureReason)
        case noMoreCloudBackupToFetch
        case none // Dummy type
    }

    weak var delegate: BackupRestoreViewHostingControllerDelegate?
    
    func restoreFromFileAction() {
        withAnimation {
            userIsRequestingBackupFileOrCloudBackup = true
        }
        delegate?.userWantsToRestoreBackupFromFile()
    }
    
    func restoreFromCloudAction() {
        withAnimation {
            userIsRequestingBackupFileOrCloudBackup = true
        }
        delegate?.userWantToRestoreBackupFromCloud()
    }
    
    func backupFileSelected(atURL url: URL, creationDate: Date?) {
        assert(Thread.isMainThread)
        withAnimation {
            self.userIsRequestingBackupFileOrCloudBackup = false
            self.backupFileUrl = url
            self.backupCreationDate = creationDate
        }
    }
    
    func userCanceledSelectionOfBackupFile() {
        assert(Thread.isMainThread)
        withAnimation {
            userIsRequestingBackupFileOrCloudBackup = false
        }
    }
    
    func proceedWithBackupFile(backupFileUrl: URL) {
        delegate?.proceedWithBackupFile(atUrl: backupFileUrl)
    }
    
    func backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: CloudFailureReason) {
        DispatchQueue.main.async { [weak self] in
            withAnimation {
                self?.alertType = .cloudFailure(reason: cloudFailureReason)
                self?.isAlertPresented = true
            }
        }
    }
    
    func noMoreCloudBackupToFetch() {
        DispatchQueue.main.async { [weak self] in
            guard self?.backupFileUrl == nil else { return }
            withAnimation {
                self?.alertType = .noMoreCloudBackupToFetch
                self?.isAlertPresented = true
            }
        }
    }
}

@available(iOS 13, *)
struct BackupRestoreView: View {
    
    @ObservedObject fileprivate var store: BackupRestoreViewModel
    
    var body: some View {
        BackupRestoreInnerView(backupFileUrl: store.backupFileUrl,
                               backupCreationDate: store.backupCreationDate,
                               restoreFromFileAction: store.restoreFromFileAction,
                               restoreFromCloudAction: store.restoreFromCloudAction,
                               proceedWithBackupFile: store.proceedWithBackupFile,
                               alertType: store.alertType,
                               isAlertPresented: $store.isAlertPresented,
                               disableButtons: $store.userIsRequestingBackupFileOrCloudBackup)
    }
    
}

@available(iOS 13, *)
struct BackupRestoreInnerView: View {
    
    fileprivate let backupFileUrl: URL?
    fileprivate let backupCreationDate: Date?
    fileprivate let restoreFromFileAction: () -> Void
    fileprivate let restoreFromCloudAction: () -> Void
    fileprivate let proceedWithBackupFile: (URL) -> Void
    fileprivate let alertType: BackupRestoreViewModel.AlertType
    @Binding var isAlertPresented: Bool
    @Binding var disableButtons: Bool
    
    private let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .short
        df.dateStyle = .short
        return df
    }()
    
    private func backupFileTitle(backupFileUrl: URL) -> Text {
        if let backupCreationDate = self.backupCreationDate {
            return Text("Backup creation date: \(dateFormater.string(from: backupCreationDate))")
        } else {
            return Text(backupFileUrl.lastPathComponent)
        }
    }
    
    private var alertTitle: Text {
        switch alertType {
        case .cloudFailure(reason: let reason):
            switch reason {
            case .icloudAccountStatusIsNotAvailable:
                return Text("Sign in to iCloud")
            case .couldNotRetrieveEncryptedBackupFile:
                return Text("Unexpected iCloud file error")
            case .couldNotRetrieveCreationDate:
                return Text("Unexpected iCloud file error")
            case .iCloudError(description: _):
                return Text("iCloud error")
            }
        case .noMoreCloudBackupToFetch:
            return Text("No backup available in iCloud")
        case .none:
            assertionFailure()
            return Text("")
        }
    }

    private var alertMessage: Text {
        switch alertType {
        case .cloudFailure(reason: let reason):
            switch reason {
            case .icloudAccountStatusIsNotAvailable:
                return Text("Please sign in to your iCloud account. On the Home screen, launch Settings, tap iCloud, and enter your Apple ID. Turn iCloud Drive on.")
            case .couldNotRetrieveEncryptedBackupFile:
                return Text("We could not retrieve the encrypted backup content from iCloud")
            case .couldNotRetrieveCreationDate:
                return Text("We could not retrieve the creation date of the backup content from iCloud")
            case .iCloudError(description: let description):
                return Text(description)
            }
        case .noMoreCloudBackupToFetch:
            return Text("We could not find any backup in you iCloud account. Please make sure this device uses the same iCloud account as the one you were using on the previous device.")
        case .none:
            assertionFailure()
            return Text("")
        }
    }

    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            ScrollView {
                VStack(spacing: 16) {
                    BackupRestoreExplanationView()
                    HStack {
                        OlvidButton(style: .blue,
                                    title: Text("From a file"),
                                    systemIcon: .folderFill,
                                    action: restoreFromFileAction)
                        OlvidButton(style: .blue,
                                    title: Text("From the cloud"),
                                    systemIcon: .icloudFill,
                                    action: restoreFromCloudAction)
                    }.disabled(disableButtons)
                    if let backupFileUrl = self.backupFileUrl {
                        VStack(spacing: 16) {
                            BackupFileDescriptionView(backupFileUrl: backupFileUrl, backupCreationDate: backupCreationDate)
                            OlvidButton(style: .blue, title: Text("Proceed and enter backup key"), systemIcon: .checkmarkShieldFill) {
                                proceedWithBackupFile(backupFileUrl)
                            }
                        }
                    }
                    Spacer()
                }.padding()
            }
        }
        .alert(isPresented: $isAlertPresented) {
            Alert(title: alertTitle,
                  message: alertMessage,
                  dismissButton: Alert.Button.cancel {
                    withAnimation {
                        disableButtons = false
                    }
                  })
        }
        .navigationBarTitle(Text("Restore"), displayMode: .large)
    }
}


@available(iOS 13, *)
fileprivate struct BackupFileDescriptionView: View {
    
    let backupFileUrl: URL
    let backupCreationDate: Date?
    
    private let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .short
        df.dateStyle = .short
        return df
    }()

    private var backupFileTitle: Text {
        if let backupCreationDate = self.backupCreationDate {
            return Text("Backup creation date: \(dateFormater.string(from: backupCreationDate))")
        } else {
            return Text(backupFileUrl.lastPathComponent)
        }
    }

    var body: some View {
        ObvCardView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Backup file selected")
                        .font(.headline)
                    Spacer()
                }
                backupFileTitle
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
            }
        }
    }
    
}


@available(iOS 13, *)
fileprivate struct BackupRestoreExplanationView: View {
    
    var body: some View {
        ObvCardView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Please choose the location of the backup file you wish to restore.")
                Text("Choose From a file to pick a backup file create from a manual backup.")
                Text("Choose From the cloud to select an account used for automatic backups.")
            }
            .font(.body)
        }
    }
}


@available(iOS 13, *)
struct BackupRestoreInnerView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationView {
                BackupRestoreInnerView(backupFileUrl: nil,
                                       backupCreationDate: nil,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .none,
                                       isAlertPresented: .constant(false),
                                       disableButtons: .constant(false))
            }
            NavigationView {
                BackupRestoreInnerView(backupFileUrl: nil,
                                       backupCreationDate: nil,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .none,
                                       isAlertPresented: .constant(false),
                                       disableButtons: .constant(false))
            }
            .environment(\.colorScheme, .dark)
            NavigationView {
                BackupRestoreInnerView(backupFileUrl: nil,
                                       backupCreationDate: nil,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .none,
                                       isAlertPresented: .constant(false),
                                       disableButtons: .constant(false))
            }
            .environment(\.colorScheme, .dark)
            .previewDevice(PreviewDevice(rawValue: "iPhone8,4"))
            NavigationView {
                BackupRestoreInnerView(backupFileUrl: URL(string: "file://fake.url.olvid.io/Olvid_backup_2020-11-10_12-57-45.olvidbackup")!,
                                       backupCreationDate: nil,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .none,
                                       isAlertPresented: .constant(false),
                                       disableButtons: .constant(false))
            }
            NavigationView {
                BackupRestoreInnerView(backupFileUrl: URL(string: "file://fake.url.olvid.io/Olvid_backup_2020-11-10_12-57-45.olvidbackup")!,
                                       backupCreationDate: nil,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .none,
                                       isAlertPresented: .constant(false),
                                       disableButtons: .constant(false))
                    .environment(\.colorScheme, .dark)
            }
            NavigationView {
                BackupRestoreInnerView(backupFileUrl: nil,
                                       backupCreationDate: nil,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .cloudFailure(reason: .icloudAccountStatusIsNotAvailable),
                                       isAlertPresented: .constant(true),
                                       disableButtons: .constant(false))
                    .environment(\.colorScheme, .dark)
            }
        }
    }
}
