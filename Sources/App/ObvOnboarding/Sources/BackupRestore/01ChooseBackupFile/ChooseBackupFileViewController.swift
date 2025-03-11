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

import UIKit
import SwiftUI
import CloudKit
import os.log
import ObvAppCoreConstants


protocol ChooseBackupFileViewControllerDelegate: AnyObject {
    func userWantsToProceedWithBackup(controller: ChooseBackupFileViewController, encryptedBackup: Data) async
}


final class ChooseBackupFileViewController: UIHostingController<ChooseBackupFileView>, ChooseBackupFileViewActionsProtocol, UIDocumentPickerDelegate {
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: String(describing: ChooseBackupFileViewController.self))
    weak private var delegate: ChooseBackupFileViewControllerDelegate?
    
    init(delegate: ChooseBackupFileViewControllerDelegate) {
        let actions = ChooseBackupFileViewActions()
        let view = ChooseBackupFileView(actions: actions)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    deinit {
        debugPrint("ChooseBackupFileViewController deinit")
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureNavigation(animated: false)
    }
    
    
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        configureNavigation(animated: animated)
    }

    
    private func configureNavigation(animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    // ChooseBackupFileViewActionsProtocol
    
    /// The continuation is created when presenting the document picker, and resumed in the delegates methods called when the picker is dismissed.
    private var currentContinuation: CheckedContinuation<[NewBackupInfo], Never>?
    
    @MainActor
    func userWantsToRestoreBackupFromFile() async -> [NewBackupInfo] {
        // We do *not* specify ObvUTIUtils.kUTTypeOlvidBackup here. It does not work under Google Drive.
        // And it never works within the simulator.
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: [.item])
        // let documentTypes = [kUTTypeItem] as [String] // 2020-03-13 Custom UTIs do not work in the simulator
        // let documentPicker = UIDocumentPickerViewController(documentTypes: documentTypes, in: .import)
        documentPicker.delegate = self
        documentPicker.allowsMultipleSelection = true
        let backupInfos: [NewBackupInfo] = await withCheckedContinuation { (continuation: CheckedContinuation<[NewBackupInfo], Never>) in
            resumePreviousContinuationIfRequired()
            currentContinuation = continuation
            present(documentPicker, animated: true)
        }
        return backupInfos
    }
    
    
    private func resumePreviousContinuationIfRequired() {
        guard let continuation = currentContinuation else { return }
        self.currentContinuation = nil
        continuation.resume(returning: [])
    }
    
    
    func userWantsToRestoreBackupFromICloud() async throws -> [NewBackupInfo] {
        let container = CKContainer(identifier: ObvAppCoreConstants.iCloudContainerIdentifierForEngineBackup)
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                os_log("The iCloud account isn't available. We cannot restore an uploaded backup.", log: Self.log, type: .fault)
                throw ChooseBackupFileView.ObvError.icloudAccountStatusIsNotAvailable
            }

            // The iCloud service is available. Look for backups to restore.

            let container = CKContainer(identifier: ObvAppCoreConstants.iCloudContainerIdentifierForEngineBackup)
            let database = container.privateCloudDatabase

            let config = CKOperation.Configuration()
            config.qualityOfService = .userInitiated

            let predicate = NSPredicate(value: true)
            let query = CKQuery(recordType: ObvAppCoreConstants.BackupConstants.recordType, predicate: predicate)
            query.sortDescriptors = [NSSortDescriptor(key: ObvAppCoreConstants.BackupConstants.creationDate, ascending: false)]

            let records = try await database.configuredWith(configuration: config) { db in
                try await db.records(matching: query, resultsLimit: 5) // Get up to 5 records
            }

            let infos: [NewBackupInfo] = records.matchResults
                .compactMap { matchResult in
                    let result = matchResult.1
                    switch result {
                    case .success(let ckRecord):
                        guard let asset = ckRecord[ObvAppCoreConstants.BackupConstants.Key.encryptedBackupFile.rawValue] as? CKAsset,
                              let url = asset.fileURL else {
                            return nil
                        }
                        let deviceName = ckRecord[ObvAppCoreConstants.BackupConstants.Key.deviceName.rawValue] as? String
                        let creationDate = ckRecord.creationDate
                        let backupInfos = NewBackupInfo(fileUrl: url, deviceName: deviceName, creationDate: creationDate)
                        return backupInfos
                    case .failure:
                        return nil
                    }
                }
            
            return infos
            
        } catch {
            if let ckError = error as? CKError {
                throw ChooseBackupFileView.ObvError.cloudKitError(ckError: ckError)
            } else if error is ChooseBackupFileView.ObvError {
                throw error
            } else {
                throw ChooseBackupFileView.ObvError.otherCloudError(error: error as NSError)
            }
        }
    }
    
    
    func userWantsToProceedWithBackup(encryptedBackup: Data) async {
        Task { [weak self] in
            guard let self else { return }
            await delegate?.userWantsToProceedWithBackup(controller: self, encryptedBackup: encryptedBackup)
        }
    }
    

    // MARK: - UIDocumentPickerDelegate
        
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let continuation = self.currentContinuation else { assertionFailure(); return }
        self.currentContinuation = nil
        let infos = urls.compactMap({ NewBackupInfo.createBackupInfoByCopyingFile(at: $0) })
        continuation.resume(returning: infos)
    }

    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        guard let continuation = self.currentContinuation else { assertionFailure(); return }
        self.currentContinuation = nil
        continuation.resume(returning: [])
    }
    
}


private final class ChooseBackupFileViewActions: ChooseBackupFileViewActionsProtocol {
    
    weak var delegate: ChooseBackupFileViewActionsProtocol?
    
    func userWantsToRestoreBackupFromFile() async -> [NewBackupInfo] {
        guard let delegate else { assertionFailure(); return [] }
        return await delegate.userWantsToRestoreBackupFromFile()
    }
    
    func userWantsToRestoreBackupFromICloud() async throws -> [NewBackupInfo] {
        guard let delegate else { assertionFailure(); return [] }
        return try await delegate.userWantsToRestoreBackupFromICloud()
    }
    
    func userWantsToProceedWithBackup(encryptedBackup: Data) async {
        await delegate?.userWantsToProceedWithBackup(encryptedBackup: encryptedBackup)
    }
    
}
