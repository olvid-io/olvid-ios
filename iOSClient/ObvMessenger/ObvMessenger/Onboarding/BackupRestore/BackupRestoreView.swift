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

import ObvUI
import SwiftUI
import CloudKit
import os.log
import MobileCoreServices


protocol BackupRestoreViewHostingControllerDelegate: AnyObject {
    func proceedWithBackupFile(atUrl: URL) async
}


final class BackupRestoreViewHostingController: UIHostingController<BackupRestoreView>, BackupRestoreViewModelDelegate, UIDocumentPickerDelegate {
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: BackupRestoreViewHostingController.self))

    private let backupRestoreViewModel: BackupRestoreViewModel
    private var allCloudOperationsAreCancelled = false
    
    private weak var delegate: BackupRestoreViewHostingControllerDelegate?
    
    init(delegate: BackupRestoreViewHostingControllerDelegate) {
        let backupRestoreViewModel = BackupRestoreViewModel()
        self.backupRestoreViewModel = backupRestoreViewModel
        let view = BackupRestoreView(store: backupRestoreViewModel)
        super.init(rootView: view)
        self.backupRestoreViewModel.delegate = self
        self.delegate = delegate
    }
    
    deinit {
        debugPrint("BackupRestoreViewHostingController deinit")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = NSLocalizedString("Restore", comment: "")
    }
    
    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        backupRestoreViewModel.clear()
        allCloudOperationsAreCancelled = true
    }

    
    // MARK: - BackupRestoreViewModelDelegate
    
    func userWantsToRestoreBackupFromFile() async {
        // We do *not* specify ObvUTIUtils.kUTTypeOlvidBackup here. It does not work under Google Drive.
        // And it never works within the simulator.
        let documentTypes = [kUTTypeItem] as [String] // 2020-03-13 Custom UTIs do not work in the simulator
        let documentPicker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = false
        present(documentPicker, animated: true)
    }

    
    func userWantToRestoreBackupFromCloud() async {
        self.allCloudOperationsAreCancelled = false
        let container = CKContainer(identifier: ObvMessengerConstants.iCloudContainerIdentifierForEngineBackup)
        let backupRestoreViewModel = self.backupRestoreViewModel
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                os_log("The iCloud account isn't available. We cannot restore an uploaded backup.", log: Self.log, type: .fault)
                await backupRestoreViewModel.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .icloudAccountStatusIsNotAvailable)
                return
            }

            // The iCloud service is available. Look for backups to restore.
            // This iterator only fetches the deviceIdentifierForVendor to load records efficiently.
            let iterator = CloudKitBackupRecordIterator(identifierForVendor: nil,
                                                        resultsLimit: nil,
                                                        desiredKeys: [.deviceIdentifierForVendor])
            // The already seen devices, since we show the latest record by device.
            var seenDevices = Set<UUID>()
            try await withThrowingTaskGroup(of: Void.self) { group in
                for try await records in iterator {
                    guard !allCloudOperationsAreCancelled else { break }
                    for recordWithoutData in records {
                        guard !allCloudOperationsAreCancelled else { break }
                        guard let deviceIdentifierForVendor = recordWithoutData.deviceIdentifierForVendor else {
                            continue
                        }
                        guard !seenDevices.contains(deviceIdentifierForVendor) else {
                            // We have already seen this record.
                            continue
                        }
                        // 'record' should be the latest record for the device 'deviceIdentifierForVendor'
                        seenDevices.insert(deviceIdentifierForVendor)
                        // Launch a task that fetches all the data of the latest record
                        group.addTask {
                            let iteratorWithData = CloudKitBackupRecordIterator(identifierForVendor: deviceIdentifierForVendor,
                                                                                resultsLimit: 1,
                                                                                desiredKeys: nil)
                            guard await !self.allCloudOperationsAreCancelled else { return  }
                            guard let recordWithData = try? await iteratorWithData.next()?.first else {
                                await backupRestoreViewModel.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveEncryptedBackupFile)
                                return
                            }
                            guard await !self.allCloudOperationsAreCancelled else { return }
                            guard let asset = recordWithData[.encryptedBackupFile] as? CKAsset,
                                  let url = asset.fileURL else {
                                await backupRestoreViewModel.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveEncryptedBackupFile)
                                return
                            }
                            guard await !self.allCloudOperationsAreCancelled else { return }
                            guard let creationDate = recordWithData.creationDate else {
                                await backupRestoreViewModel.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveCreationDate)
                                return
                            }
                            guard await !self.allCloudOperationsAreCancelled else { return }
                            guard let deviceName = recordWithData[.deviceName] as? String else {
                                await backupRestoreViewModel.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveDeviceName)
                                return
                            }
                            guard await !self.allCloudOperationsAreCancelled else { return }
                            let info = BackupInfo(fileUrl: url, deviceName: deviceName, creationDate: creationDate)
                            await backupRestoreViewModel.addNewSelectableBackups([info])
                        }
                    }
                }
            }
            await backupRestoreViewModel.noMoreCloudBackupToFetch()
        } catch {
            await backupRestoreViewModel.backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: .couldNotRetrieveEncryptedBackupFile)
            return
        }
    }

    
    func proceedWithBackupFile(atUrl url: URL) async {
        assert(delegate != nil)
        await delegate?.proceedWithBackupFile(atUrl: url)
    }
    
    
    // MARK: - UIDocumentPickerDelegate
        
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        
        DispatchQueue(label: "Queue for processing the backup file").async { [weak self] in

            guard urls.count == 1 else { return }
            let url = urls.first!

            let tempBackupFileUrl: URL
            do {
                _ = url.startAccessingSecurityScopedResource()
                defer { url.stopAccessingSecurityScopedResource() }

                guard let fileUTI = ObvUTIUtils.utiOfFile(atURL: url) else {
                    os_log("Could not determine the UTI of the file at URL %{public}@", log: Self.log, type: .fault, url.path)
                    return
                }

                guard ObvUTIUtils.uti(fileUTI, conformsTo: ObvUTIUtils.kUTTypeOlvidBackup) else {
                    os_log("The chosen file does not conform to the appropriate type. The file name shoud in with .olvidbackup", log: Self.log, type: .error)
                    return
                }

                os_log("A file with an appropriate file extension was returned.", log: Self.log, type: .info)

                // We can copy the backup file at an appropriate location

                let tempDir = ObvMessengerConstants.containerURL.forTempFiles.appendingPathComponent("BackupFilesToRestore", isDirectory: true)
                do {
                    if FileManager.default.fileExists(atPath: tempDir.path) {
                        try FileManager.default.removeItem(at: tempDir) // Clean the directory
                    }
                    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
                } catch let error {
                    os_log("Could not create temporary directory: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                    return
                }

                let fileName = url.lastPathComponent
                tempBackupFileUrl = tempDir.appendingPathComponent(fileName)

                do {
                    try FileManager.default.copyItem(at: url, to: tempBackupFileUrl)
                } catch let error {
                    os_log("Could not copy backup file to temp location: %{public}@", log: Self.log, type: .error, error.localizedDescription)
                    return
                }

                // Check that the file can be read
                do {
                    _ = try Data(contentsOf: tempBackupFileUrl)
                } catch {
                    os_log("Could not read backup file: %{public}@", log: Self.log, type: .error, error.localizedDescription)
                    return
                }
            }

            // If we reach this point, we can start processing the backup file located at tempBackupFileUrl
            let info = BackupInfo(fileUrl: tempBackupFileUrl, deviceName: nil, creationDate: nil)
            
            Task {
                await self?.backupRestoreViewModel.addNewSelectableBackups([info])
            }

        }
        
    }
    
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        assert(Thread.isMainThread)
        backupRestoreViewModel.userCanceledSelectionOfBackupFile()
    }

}

struct BackupInfo: Identifiable {
    var id: URL { fileUrl }

    let fileUrl: URL
    let deviceName: String?
    let creationDate: Date?
}


protocol BackupRestoreViewModelDelegate: AnyObject {
    func userWantToRestoreBackupFromCloud() async
    func userWantsToRestoreBackupFromFile() async
    func proceedWithBackupFile(atUrl: URL) async
}

fileprivate final class BackupRestoreViewModel: ObservableObject {

    @Published private(set) var backups: [BackupInfo] = []
    @Published var userIsRequestingBackupFileOrCloudBackup = false
    @Published var backupFileOrCloudBackupHasBeenRequested = false
    @Published fileprivate var isAlertPresented = false
    @Published fileprivate var alertType = AlertType.none
    @Published fileprivate var isFetchingFromICloud: Bool = false
    @Published fileprivate var selectedBackup: URL?

    
    fileprivate enum AlertType {
        case cloudFailure(reason: CloudFailureReason)
        case noMoreCloudBackupToFetch
        case none // Dummy type
    }

    weak var delegate: BackupRestoreViewModelDelegate?
    
    func restoreFromFileAction() {
        withAnimation {
            userIsRequestingBackupFileOrCloudBackup = true
            backupFileOrCloudBackupHasBeenRequested = true
        }
        Task { await delegate?.userWantsToRestoreBackupFromFile() }
    }
    
    func restoreFromCloudAction() {
        withAnimation {
            userIsRequestingBackupFileOrCloudBackup = true
            backupFileOrCloudBackupHasBeenRequested = true
            isFetchingFromICloud = true
        }
        Task {
            await delegate?.userWantToRestoreBackupFromCloud()
        }
    }
    
    @MainActor
    func addNewSelectableBackups(_ backups: [BackupInfo]) async {
        assert(Thread.isMainThread)
        withAnimation {
            self.userIsRequestingBackupFileOrCloudBackup = false
            self.backups += backups
            self.backups.sort { b1, b2 in
                guard let d1 = b1.creationDate else { assertionFailure(); return false }
                guard let d2 = b2.creationDate else { assertionFailure(); return false }
                return d2 < d1
            }
        }
    }

    func userCanceledSelectionOfBackupFile() {
        assert(Thread.isMainThread)
        clear()
    }
    
    func proceedWithBackupFile(backupFileUrl: URL) {
        Task { await delegate?.proceedWithBackupFile(atUrl: backupFileUrl) }
    }
    
    @MainActor
    func backupFileFailedToBeRetrievedFromCloud(cloudFailureReason: CloudFailureReason) async {
        withAnimation {
            self.alertType = .cloudFailure(reason: cloudFailureReason)
            self.isAlertPresented = true
        }
    }
    
    @MainActor
    func noMoreCloudBackupToFetch() async {
        if backups.isEmpty {
            withAnimation {
                alertType = .noMoreCloudBackupToFetch
                isAlertPresented = true
            }
        }
        withAnimation {
            isFetchingFromICloud = false
        }
    }

    func clear() {
        DispatchQueue.main.async {
            withAnimation {
                self.selectedBackup = nil
                self.backups.removeAll()
                self.userIsRequestingBackupFileOrCloudBackup = false
                self.backupFileOrCloudBackupHasBeenRequested = false
                self.isAlertPresented = false
                self.alertType = AlertType.none
                self.isFetchingFromICloud = false
            }
        }
    }
}

struct BackupRestoreView: View {
    
    @ObservedObject fileprivate var store: BackupRestoreViewModel
    
    var body: some View {
        BackupRestoreInnerView(backups: store.backups,
                               restoreFromFileAction: store.restoreFromFileAction,
                               restoreFromCloudAction: store.restoreFromCloudAction,
                               proceedWithBackupFile: store.proceedWithBackupFile,
                               alertType: store.alertType,
                               isAlertPresented: $store.isAlertPresented,
                               disableButtons: $store.userIsRequestingBackupFileOrCloudBackup,
                               backupFileOrCloudBackupHasBeenRequested: $store.backupFileOrCloudBackupHasBeenRequested,
                               isFetchingFromICloud: $store.isFetchingFromICloud,
                               selectedBackup: $store.selectedBackup)
    }
    
}

struct BackupRestoreInnerView: View {
    
    fileprivate let backups: [BackupInfo]
    fileprivate let restoreFromFileAction: () -> Void
    fileprivate let restoreFromCloudAction: () -> Void
    fileprivate let proceedWithBackupFile: (URL) -> Void
    fileprivate let alertType: BackupRestoreViewModel.AlertType
    @Binding var isAlertPresented: Bool
    @Binding var disableButtons: Bool
    @Binding var backupFileOrCloudBackupHasBeenRequested: Bool
    @Binding var isFetchingFromICloud: Bool
    @Binding var selectedBackup: URL?
    
    private let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .short
        df.dateStyle = .short
        return df
    }()

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
            case .couldNotRetrieveDeviceName:
                return Text("Unexpected iCloud file error")
            case .iCloudError:
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
            case .couldNotRetrieveDeviceName:
                return Text("We could not retrieve the device name of the backup content from iCloud")
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
            VStack(spacing: 16) {
                BackupRestoreExplanationView(backupFileOrCloudBackupHasBeenRequested: backupFileOrCloudBackupHasBeenRequested)
                if !backupFileOrCloudBackupHasBeenRequested {
                    HStack {
                        OlvidButton(style: .blue,
                                    title: Text("From a file"),
                                    systemIcon: .folderFill,
                                    action: restoreFromFileAction)
                        OlvidButton(style: .blue,
                                    title: Text("From the cloud"),
                                    systemIcon: .icloud(.fill),
                                    action: restoreFromCloudAction)
                    }.disabled(disableButtons)
                } else {
                    if !backups.isEmpty {
                        ObvCardView(padding: 0) {
                            List {
                                ForEach(backups) { backup in
                                    BackupFileDescriptionView(fileUrl: backup.fileUrl,
                                                              deviceName: backup.deviceName,
                                                              creationDate: backup.creationDate,
                                                              selectedBackup: $selectedBackup)
                                }
                                if isFetchingFromICloud {
                                    ObvActivityIndicator(isAnimating: .constant(true), style: .medium, color: nil)
                                        .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .center)
                                }
                            }
                            .listStyle(.plain)
                        }
                    } else {
                        ObvActivityIndicator(isAnimating: .constant(true), style: .medium, color: nil)
                            .frame(idealWidth: .infinity, maxWidth: .infinity, alignment: .center)
                    }
                }
                Spacer()
                OlvidButton(style: .blue, title: Text("Proceed and enter backup key"), systemIcon: .checkmarkShieldFill) {
                    guard let selectedBackup else { assertionFailure(); return }
                    proceedWithBackupFile(selectedBackup)
                }
                .disabled(selectedBackup == nil)
            }.padding()
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
    }
}


fileprivate struct BackupFileDescriptionView: View {
    
    let fileUrl: URL
    let deviceName: String?
    let creationDate: Date?

    @Binding var selectedBackup: URL?
    
    private let dateFormater: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale.current
        df.doesRelativeDateFormatting = true
        df.timeStyle = .short
        df.dateStyle = .short
        return df
    }()

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if let deviceName {
                    Text(deviceName)
                        .font(.system(.headline, design: .rounded))
                }
                if let formattedDate = creationDate?.relativeFormatted {
                    Text(formattedDate)
                        .font(.system(.callout))
                } else {
                    Text(fileUrl.lastPathComponent)
                        .font(.system(.footnote, design: .monospaced))
                }
            }
            Spacer()
            Image(systemIcon: fileUrl == selectedBackup ? .checkmarkCircleFill : .circle)
                .font(Font.system(size: 24, weight: .regular, design: .default))
                .foregroundColor(fileUrl == selectedBackup ? Color.green : Color.gray)
                .padding(.leading)
        }
        .padding(.vertical, 6.0)
        .contentShape(Rectangle()) // This makes it possible to have an "on tap" gesture that also works when the Spacer is tapped
        .onTapGesture {
            selectedBackup = fileUrl
        }
    }
    
}


fileprivate struct BackupRestoreExplanationView: View {

    let backupFileOrCloudBackupHasBeenRequested: Bool

    var body: some View {
        ObvCardView(padding: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    if backupFileOrCloudBackupHasBeenRequested {
                        Text("PLEASE_CHOOSE_THE_BACKUP_TO_RESTORE")
                    } else {
                        Text("Please choose the location of the backup file you wish to restore.")
                        Text("Choose From a file to pick a backup file create from a manual backup.")
                        Text("Choose From the cloud to select an account used for automatic backups.")
                    }
                }
                Spacer()
            }
            .font(.body)
            .padding()
        }
    }
}


struct BackupRestoreInnerView_Previews: PreviewProvider {

    static let backups = [
        BackupInfo(fileUrl: URL(string: "file://fake.url.olvid.io/Olvid_backup_2020-11-10_12-57-45.olvidbackup")!,
                                     deviceName: "iPhone 8",
                                     creationDate: Date()),
        BackupInfo(fileUrl: URL(string: "file://fake.url.olvid.io/Olvid_backup_2020-11-10_12-57-46.olvidbackup")!,
                   deviceName: "iPhone X",
                   creationDate: Date()),
        BackupInfo(fileUrl: URL(string: "file://fake.url.olvid.io/Olvid_backup_2020-11-10_12-57-47.olvidbackup")!,
                   deviceName: "iPhone 11",
                   creationDate: Date()),
        BackupInfo(fileUrl: URL(string: "file://fake.url.olvid.io/Olvid_backup_2020-11-10_12-57-48.olvidbackup")!,
                   deviceName: "iPhone 14",
                   creationDate: Date())
    ]
    
    static let fileUrl = URL(string: "file://fake.url.olvid.io/Olvid_backup_2020-11-10_12-57-45.olvidbackup")!

    static var previews: some View {
        Group {
            NavigationView {
                BackupRestoreInnerView(backups: backups,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .none,
                                       isAlertPresented: .constant(false),
                                       disableButtons: .constant(false),
                                       backupFileOrCloudBackupHasBeenRequested: .constant(false),
                                       isFetchingFromICloud: .constant(false),
                                       selectedBackup: .constant(nil))
            }
            NavigationView {
                BackupRestoreInnerView(backups: backups,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .none,
                                       isAlertPresented: .constant(false),
                                       disableButtons: .constant(false),
                                       backupFileOrCloudBackupHasBeenRequested: .constant(false),
                                       isFetchingFromICloud: .constant(false),
                                       selectedBackup: .constant(nil))
            }
            .environment(\.colorScheme, .dark)
            NavigationView {
                BackupRestoreInnerView(backups: backups,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .none,
                                       isAlertPresented: .constant(false),
                                       disableButtons: .constant(false),
                                       backupFileOrCloudBackupHasBeenRequested: .constant(true),
                                       isFetchingFromICloud: .constant(false),
                                       selectedBackup: .constant(fileUrl))
            }
            .environment(\.colorScheme, .dark)
            .previewDevice(PreviewDevice(rawValue: "iPhone8,4"))
            NavigationView {
                BackupRestoreInnerView(backups: backups,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .none,
                                       isAlertPresented: .constant(false),
                                       disableButtons: .constant(false),
                                       backupFileOrCloudBackupHasBeenRequested: .constant(true),
                                       isFetchingFromICloud: .constant(false),
                                       selectedBackup: .constant(nil))
            }
            NavigationView {
                BackupRestoreInnerView(backups: backups,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .none,
                                       isAlertPresented: .constant(false),
                                       disableButtons: .constant(false),
                                       backupFileOrCloudBackupHasBeenRequested: .constant(true),
                                       isFetchingFromICloud: .constant(true),
                                       selectedBackup: .constant(nil))
                    .environment(\.colorScheme, .dark)
            }
            NavigationView {
                BackupRestoreInnerView(backups: backups,
                                       restoreFromFileAction: {},
                                       restoreFromCloudAction: {},
                                       proceedWithBackupFile: { _ in },
                                       alertType: .cloudFailure(reason: .icloudAccountStatusIsNotAvailable),
                                       isAlertPresented: .constant(true),
                                       disableButtons: .constant(false),
                                       backupFileOrCloudBackupHasBeenRequested: .constant(false),
                                       isFetchingFromICloud: .constant(false),
                                       selectedBackup: .constant(nil))
                    .environment(\.colorScheme, .dark)
            }
        }
    }
}
