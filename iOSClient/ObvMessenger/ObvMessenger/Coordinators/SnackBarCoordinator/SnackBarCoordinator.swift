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

import Foundation
import ObvEngine
import os.log
import UIKit
import AVFAudio


final class SnackBarCoordinator {
    
    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: SnackBarCoordinator.self))
    
    private let obvEngine: ObvEngine

    private let internalQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .background
        return queue
    }()
    
    private var observationTokens = [NSObjectProtocol]()
    private var alreadyCheckedIdentities = Set<ObvCryptoId>()
    private var currentCryptoId: ObvCryptoId? {
        didSet {
            internalQueue.addOperation { [weak self] in
                self?.determineSnackBarToDisplay()
            }
        }
    }
    
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
        listenToNotifications()
    }
    
    private let oneDay = TimeInterval(86_400)
    private let oneWeek = TimeInterval(604_800)
    private let oneMonth = TimeInterval(2_419_200)

    private func listenToNotifications() {
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeAppStateChanged(queue: internalQueue) { [weak self] (previousState, currentState) in
                if !previousState.isInitializedAndActive && currentState.isInitializedAndActive {
                    self?.determineSnackBarToDisplay()
                } else if currentState.iOSAppState == .inBackground {
                    self?.alreadyCheckedIdentities.removeAll()
                }
            },
            ObvMessengerInternalNotification.observeCurrentOwnedCryptoIdChanged(queue: internalQueue) { [weak self] newOwnedCryptoId, _ in
                self?.currentCryptoId = newOwnedCryptoId
            },
            ObvMessengerInternalNotification.observeUserDismissedSnackBarForLater(queue: internalQueue) { [weak self] ownedCryptoId, snackBarCategory in
                self?.processUserDismissedSnackBarForLater(ownedCryptoId: ownedCryptoId, snackBarCategory: snackBarCategory)
            },
            ObvMessengerInternalNotification.observeUserRequestedToResetAllAlerts(queue: internalQueue) { [weak self] in
                self?.processUserRequestedToResetAllAlerts()
            },
            ObvEngineNotificationNew.observeNewBackupKeyGenerated(within: NotificationCenter.default, queue: internalQueue) { [weak self] _, _ in
                self?.alreadyCheckedIdentities.removeAll()
                self?.determineSnackBarToDisplay()
            },
            ObvEngineNotificationNew.observeBackupForExportWasExported(within: NotificationCenter.default, queue: internalQueue) { [weak self] _, _, _ in
                self?.alreadyCheckedIdentities.removeAll()
                self?.determineSnackBarToDisplay()
            },
            ObvEngineNotificationNew.observeBackupForUploadWasUploaded(within: NotificationCenter.default, queue: internalQueue) { [weak self] _, _, _ in
                self?.alreadyCheckedIdentities.removeAll()
                self?.determineSnackBarToDisplay()
            },
            ObvMessengerInternalNotification.observePersistedContactWasDeleted(queue: internalQueue) { [weak self] _, _ in
                self?.alreadyCheckedIdentities.removeAll()
                self?.determineSnackBarToDisplay()
            },
            ObvMessengerInternalNotification.observeDisplayedSnackBarShouldBeRefreshed { [weak self] in
                self?.internalQueue.addOperation { [weak self] in
                    self?.alreadyCheckedIdentities.removeAll()
                    self?.determineSnackBarToDisplay()
                }
            }
        ])
    }
    
    
    private func processUserRequestedToResetAllAlerts() {
        OlvidSnackBarCategory.removeAllLastDisplayDate()
        alreadyCheckedIdentities.removeAll()
        determineSnackBarToDisplay()
    }
    
    
    private func processUserDismissedSnackBarForLater(ownedCryptoId: ObvCryptoId, snackBarCategory: OlvidSnackBarCategory) {
        OlvidSnackBarCategory.setLastDisplayDate(for: snackBarCategory)
        alreadyCheckedIdentities.removeAll()
        determineSnackBarToDisplay()
    }

    
    private func determineSnackBarToDisplay() {
        assert(OperationQueue.current == internalQueue)
        guard let currentCryptoId = self.currentCryptoId else { return }
        guard AppStateManager.shared.currentState.isInitializedAndActive else { return }
        guard !alreadyCheckedIdentities.contains(currentCryptoId) else { return }
        alreadyCheckedIdentities.insert(currentCryptoId)
        let log = self.log
        let obvEngine = self.obvEngine
        
        ObvStack.shared.performBackgroundTaskAndWait { context in
                        
            do {
                
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: currentCryptoId, within: context) else {
                    os_log("Could not find owned identity", log: log, type: .error)
                    return
                }
                
                // We never display a snackbar if the owned identity has no contact

                let ownedIdentityHasAtLeastOneContact = !ownedIdentity.contacts.isEmpty
                guard ownedIdentityHasAtLeastOneContact else { return }
                
                // If the user's device has an old iOS version, recommend upgrade
                
                do {
                    let lastDisplayDate = OlvidSnackBarCategory.upgradeIOS.lastDisplayDate ?? Date.distantPast
                    let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < oneWeek
                    if !didDismissSnackBarRecently {
                        if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.supportedIOSVersion || ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.recommendedMinimumIOSVersion {
                            ObvMessengerInternalNotification.olvidSnackBarShouldBeShown(ownedCryptoId: currentCryptoId, snackBarCategory: OlvidSnackBarCategory.upgradeIOS)
                                .postOnDispatchQueue()
                            return
                        }
                    }
                }

                // If the owned identity
                // - has at least one contact
                // - has not granted access to the microphone
                // - missed a called because of this
                // Then notify of this fact and display a button allowing to grant access to the microphone
                // (or a button allowing to go to the settings to do so)
                
                let recordPermission = AVAudioSession.sharedInstance().recordPermission
                
                switch recordPermission {
                case .granted:
                    break
                case .denied, .undetermined:
                    do {
                        let hasRejectedIncomingCallMessage = try PersistedMessageSystem.hasRejectedIncomingCallBecauseOfDeniedRecordPermission(within: context)
                        if hasRejectedIncomingCallMessage {
                            if recordPermission == .denied {
                                let lastDisplayDate = OlvidSnackBarCategory.grantPermissionToRecordInSettings.lastDisplayDate ?? Date.distantPast
                                let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < oneWeek
                                guard didDismissSnackBarRecently else {
                                    ObvMessengerInternalNotification.olvidSnackBarShouldBeShown(ownedCryptoId: currentCryptoId, snackBarCategory: OlvidSnackBarCategory.grantPermissionToRecordInSettings)
                                        .postOnDispatchQueue()
                                    return
                                }
                            }
                            if recordPermission == .undetermined {
                                let lastDisplayDate = OlvidSnackBarCategory.grantPermissionToRecord.lastDisplayDate ?? Date.distantPast
                                let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < oneDay
                                guard didDismissSnackBarRecently else {
                                    ObvMessengerInternalNotification.olvidSnackBarShouldBeShown(ownedCryptoId: currentCryptoId, snackBarCategory: OlvidSnackBarCategory.grantPermissionToRecord)
                                        .postOnDispatchQueue()
                                    return
                                }
                            }
                        }
                    } catch {
                        os_log("Could not determine if the user missed a call because she denied record permission", log: log, type: .fault, error.localizedDescription)
                        assertionFailure()
                        // Continue anyway
                    }
                @unknown default:
                    assertionFailure()
                }
                
                // If the owned identity
                // - has at least one contact
                // - did not dismiss the OlvidSnackBarCategory.createBackupKey for the past week
                // - has no backup key
                // Then notify that we should display a OlvidSnackBarCategory.createBackupKey snack bar.
                
                let backupKeyInformation = try obvEngine.getCurrentBackupKeyInformation()

                if backupKeyInformation == nil {
                    let lastDisplayDate = OlvidSnackBarCategory.createBackupKey.lastDisplayDate ?? Date.distantPast
                    let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < oneWeek
                    guard didDismissSnackBarRecently else {
                        ObvMessengerInternalNotification.olvidSnackBarShouldBeShown(ownedCryptoId: currentCryptoId, snackBarCategory: OlvidSnackBarCategory.createBackupKey)
                            .postOnDispatchQueue()
                        return
                    }
                }
                
                // If the owned identity
                // - has a backup key
                // - did not activate automatic backups
                // - did not dismiss the OlvidSnackBarCategory.shouldPerformBackup for the past week
                // - did not export a backup for more than a week
                // Then notify that we should display a OlvidSnackBarCategory.shouldPerformBackup snack bar.
                
                if let backupKeyInformation = backupKeyInformation, !ObvMessengerSettings.Backup.isAutomaticBackupEnabled {
                    let lastBackupExportTimestamp = backupKeyInformation.lastBackupExportTimestamp ?? Date.distantPast
                    let didExportBackupRecently = abs(lastBackupExportTimestamp.timeIntervalSinceNow) < oneWeek
                    let lastDisplayDate = OlvidSnackBarCategory.shouldPerformBackup.lastDisplayDate ?? Date.distantPast
                    let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < oneWeek
                    guard didDismissSnackBarRecently || didExportBackupRecently else {
                        ObvMessengerInternalNotification.olvidSnackBarShouldBeShown(ownedCryptoId: currentCryptoId, snackBarCategory: OlvidSnackBarCategory.shouldPerformBackup)
                            .postOnDispatchQueue()
                        return
                    }
                }
                
                // If the owned identity
                // - has a backup key
                // - did not verify her backup key for the past month
                // - did generate her key more than a two weeks ago
                // - did not dismiss the OlvidSnackBarCategory.shouldVerifyBackupKey for the past week
                // Then notify that we should display a OlvidSnackBarCategory.shouldVerifyBackupKey snack bar.

                if let backupKeyInformation = backupKeyInformation {
                    let keyGenerationTimestamp = backupKeyInformation.keyGenerationTimestamp
                    let didGenerateKeyRecently = abs(keyGenerationTimestamp.timeIntervalSinceNow) < 2*oneWeek
                    let lastSuccessfulKeyVerificationTimestamp = backupKeyInformation.lastSuccessfulKeyVerificationTimestamp ?? Date.distantPast
                    let didSuccessfullyVerifyKeyRecently = abs(lastSuccessfulKeyVerificationTimestamp.timeIntervalSinceNow) < oneMonth
                    let lastDisplayDate = OlvidSnackBarCategory.shouldVerifyBackupKey.lastDisplayDate ?? Date.distantPast
                    let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < oneWeek
                    guard didGenerateKeyRecently || didSuccessfullyVerifyKeyRecently || didDismissSnackBarRecently else {
                        ObvMessengerInternalNotification.olvidSnackBarShouldBeShown(ownedCryptoId: currentCryptoId, snackBarCategory: OlvidSnackBarCategory.shouldVerifyBackupKey)
                            .postOnDispatchQueue()
                        return
                    }
                }

                // If we rech this point, there is no appropriate snackbar to display, so we request to hide all already shown snackbar
                ObvMessengerInternalNotification.olvidSnackBarShouldBeHidden(ownedCryptoId: currentCryptoId)
                    .postOnDispatchQueue()

            } catch {
                os_log("SnackBarCoordinator error: %{public}@", log: log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
            
        }
        
        
    }
    
    
}
