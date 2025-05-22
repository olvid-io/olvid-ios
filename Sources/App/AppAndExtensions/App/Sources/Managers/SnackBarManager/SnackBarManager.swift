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

import Foundation
import ObvTypes
import os.log
import UIKit
import AVFAudio
import ObvEngine
import ObvUICoreData
import ObvSettings
import ObvAppCoreConstants


actor SnackBarManager {
    
    private static let log = OSLog(subsystem: ObvAppCoreConstants.logSubsystem, category: "SnackBarManager")
    
    private let obvEngine: ObvEngine

    private var observationTokens = [NSObjectProtocol]()
    private var alreadyCheckedIdentities = Set<ObvCryptoId>()

    private var currentCryptoId: ObvCryptoId? {
        didSet {
            Task {
                if let currentCryptoId = self.currentCryptoId {
                    await determineSnackBarToDisplay(for: currentCryptoId)
                }
            }
        }
    }
    
    
    init(obvEngine: ObvEngine) {
        self.obvEngine = obvEngine
    }
    
    deinit {
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func performPostInitialization() async {
        await listenToNotifications()
    }

    private func listenToNotifications() async {
        await listenToUIApplicationNotifications()
        observationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeMetaFlowControllerDidSwitchToOwnedIdentity { newOwnedCryptoId in
                Task { [weak self] in
                    await self?.removeAllAlreadyCheckedIdentities()
                    await self?.replaceCurrentCryptoId(by: newOwnedCryptoId)
                    if let currentCryptoId = await self?.currentCryptoId {
                        await self?.determineSnackBarToDisplay(for: currentCryptoId)
                    }
                }
            },
            ObvMessengerCoreDataNotification.observeOwnedIdentityWasReactivated { _ in
                Task { [weak self] in
                    await self?.removeAllAlreadyCheckedIdentities()
                    if let currentCryptoId = await self?.currentCryptoId {
                        // Since a backup is not linked to a specific owned identity, we use the current one for the snack bar
                        await self?.determineSnackBarToDisplay(for: currentCryptoId)
                    }
                }
            },
            ObvMessengerCoreDataNotification.observeOwnedIdentityWasDeactivated { _ in
                Task { [weak self] in
                    await self?.removeAllAlreadyCheckedIdentities()
                    if let currentCryptoId = await self?.currentCryptoId {
                        // Since a backup is not linked to a specific owned identity, we use the current one for the snack bar
                        await self?.determineSnackBarToDisplay(for: currentCryptoId)
                    }
                }
            },
            ObvMessengerInternalNotification.observeUserDismissedSnackBarForLater { [weak self] ownedCryptoId, snackBarCategory in
                Task { [weak self] in await self?.processUserDismissedSnackBarForLater(ownedCryptoId: ownedCryptoId, snackBarCategory: snackBarCategory) }
            },
            ObvMessengerInternalNotification.observeUserRequestedToResetAllAlerts { [weak self] in
                Task { [weak self] in await self?.processUserRequestedToResetAllAlerts() }
            },
            ObvMessengerInternalNotification.observeBackupForExportWasExported { [weak self] in
                Task { [weak self] in
                    await self?.removeAllAlreadyCheckedIdentities()
                    if let currentCryptoId = await self?.currentCryptoId {
                        // Since a backup is not linked to a specific owned identity, we use the current one for the snack bar
                        await self?.determineSnackBarToDisplay(for: currentCryptoId)
                    }
                }
            },
            ObvMessengerInternalNotification.observeBackupForUploadWasUploaded { [weak self] in
                Task { [weak self] in
                    await self?.removeAllAlreadyCheckedIdentities()
                    if let currentCryptoId = await self?.currentCryptoId {
                        // Since a backup is not linked to a specific owned identity, we use the current one for the snack bar
                        await self?.determineSnackBarToDisplay(for: currentCryptoId)
                    }
                }
            },
            ObvMessengerInternalNotification.observeBackupForUploadFailedToUpload { [weak self] in
                Task { [weak self] in
                    guard let _self = self else { return }
                    guard ObvMessengerSettings.Backup.isAutomaticBackupEnabled else { return }
                    guard let backupKeyInformation = try await _self.obvEngine.getCurrentLegacyBackupKeyInformation() else { return }
                    guard backupKeyInformation.lastBackupUploadFailureTimestamp != nil else { return }
                    await _self.removeAllAlreadyCheckedIdentities()
                    if let currentCryptoId = await _self.currentCryptoId {
                        await _self.determineSnackBarToDisplay(for: currentCryptoId)
                    }
                }
            },
            ObvMessengerCoreDataNotification.observePersistedContactWasDeleted { [weak self] _, _ in
                Task { [weak self] in
                    await self?.removeAllAlreadyCheckedIdentities()
                    if let currentCryptoId = await self?.currentCryptoId {
                        await self?.determineSnackBarToDisplay(for: currentCryptoId)
                    }
                }
            },
            ObvMessengerInternalNotification.observeDisplayedSnackBarShouldBeRefreshed { [weak self] in
                Task { [weak self] in
                    await self?.removeAllAlreadyCheckedIdentities()
                    if let currentCryptoId = await self?.currentCryptoId {
                        await self?.determineSnackBarToDisplay(for: currentCryptoId)
                    }
                }
            },
        ])
    }
    
    
    @MainActor
    private func listenToUIApplicationNotifications() async {
        let token = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { _ in
            Task { [weak self] in await self?.removeAllAlreadyCheckedIdentities() }
        }
        await appendToObservationTokens(newToken: token)
    }
    
    
    private func appendToObservationTokens(newToken: NSObjectProtocol) {
        observationTokens.append(newToken)
    }
    
    
    private func removeAllAlreadyCheckedIdentities() {
        alreadyCheckedIdentities.removeAll()
    }
    
    
    private func replaceCurrentCryptoId(by newOwnedCryptoId: ObvCryptoId) {
        guard self.currentCryptoId != newOwnedCryptoId else { return }
        self.currentCryptoId = newOwnedCryptoId
    }
    
    
    func applicationAppearedOnScreen(forTheFirstTime: Bool) async {
        if let currentCryptoId = currentCryptoId {
            await determineSnackBarToDisplay(for: currentCryptoId)
        }
    }
    
    
    private func processUserRequestedToResetAllAlerts() async {
        OlvidSnackBarCategory.removeAllLastDisplayDate()
        ObvMessengerInternalNotification.displayedSnackBarShouldBeRefreshed.postOnDispatchQueue()
        alreadyCheckedIdentities.removeAll()
        if let currentCryptoId = currentCryptoId {
            await determineSnackBarToDisplay(for: currentCryptoId)
        }
    }
    
    
    private func processUserDismissedSnackBarForLater(ownedCryptoId: ObvCryptoId, snackBarCategory: OlvidSnackBarCategory) async {
        OlvidSnackBarCategory.setLastDisplayDate(for: snackBarCategory)
        alreadyCheckedIdentities.removeAll()
        if let currentCryptoId = currentCryptoId {
            await determineSnackBarToDisplay(for: currentCryptoId)
        }
    }

    
    private func determineSnackBarToDisplay(for currentCryptoId: ObvCryptoId) async {
        
        os_log("Starting determineSnackBarToDisplay", log: Self.log, type: .info)
        defer { os_log("Ending determineSnackBarToDisplay", log: Self.log, type: .info) }

        guard currentCryptoId == self.currentCryptoId else { return }
        guard !alreadyCheckedIdentities.contains(currentCryptoId) else { return }
        alreadyCheckedIdentities.insert(currentCryptoId)

        var ownedIdentityHasAtLeastOneContact: Bool = false
        var ownedIdentityIsActive = true
        ObvStack.shared.performBackgroundTaskAndWait { context in
            do {
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: currentCryptoId, within: context) else {
                    os_log("Could not find owned identity", log: Self.log, type: .error)
                    return
                }
                
                ownedIdentityHasAtLeastOneContact = !ownedIdentity.contacts.isEmpty
                ownedIdentityIsActive = ownedIdentity.isActive
            } catch {
                os_log("SnackBarManager error: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                assertionFailure()
                return
            }
        }
        
        // If the owned identity (profile) is inactive, inform the user
        
        guard ownedIdentityIsActive else {
            ObvMessengerInternalNotification.olvidSnackBarShouldBeShown(ownedCryptoId: currentCryptoId, snackBarCategory: OlvidSnackBarCategory.ownedIdentityIsInactive)
                .postOnDispatchQueue()
            return
        }


        // We never display a snackbar if the owned identity has no contact

        guard ownedIdentityHasAtLeastOneContact else {
            ObvMessengerInternalNotification.olvidSnackBarShouldBeHidden(ownedCryptoId: currentCryptoId)
                .postOnDispatchQueue()
            return
        }

        // If the user should upgrade to a newer version of Olvid, recommend the update

        do {
            let lastDisplayDate = OlvidSnackBarCategory.newerAppVersionAvailable.lastDisplayDate ?? Date.distantPast
            let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < TimeInterval(days: 1)
            if !didDismissSnackBarRecently {
                if let latestBuildNumberAvailable = ObvMessengerSettings.AppVersionAvailable.latest, latestBuildNumberAvailable > ObvAppCoreConstants.bundleVersionAsInt {
                    ObvMessengerInternalNotification.olvidSnackBarShouldBeShown(ownedCryptoId: currentCryptoId, snackBarCategory: OlvidSnackBarCategory.newerAppVersionAvailable)
                        .postOnDispatchQueue()
                    return
                }
            }
        }

        // If the user's device has an old iOS version, recommend upgrade

        if !ObvAppCoreConstants.targetEnvironmentIsMacCatalyst {
            let lastDisplayDate = OlvidSnackBarCategory.upgradeIOS.lastDisplayDate ?? Date.distantPast
            let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < TimeInterval(days: 7)
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
            var hasRejectedStartCallMessage: Bool = false
            ObvStack.shared.performBackgroundTaskAndWait { context in
                do {
                    hasRejectedStartCallMessage = try PersistedMessageSystem.hasRejectedIncomingCallBecauseOfDeniedRecordPermission(within: context)
                } catch {
                    os_log("SnackBarManager error: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
                    assertionFailure()
                    return
                }
            }
            if hasRejectedStartCallMessage {
                if recordPermission == .denied {
                    let lastDisplayDate = OlvidSnackBarCategory.grantPermissionToRecordInSettings.lastDisplayDate ?? Date.distantPast
                    let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < TimeInterval(days: 7)
                    guard didDismissSnackBarRecently else {
                        ObvMessengerInternalNotification.olvidSnackBarShouldBeShown(ownedCryptoId: currentCryptoId, snackBarCategory: OlvidSnackBarCategory.grantPermissionToRecordInSettings)
                            .postOnDispatchQueue()
                        return
                    }
                }
                if recordPermission == .undetermined {
                    let lastDisplayDate = OlvidSnackBarCategory.grantPermissionToRecord.lastDisplayDate ?? Date.distantPast
                    let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < TimeInterval(days: 1)
                    guard didDismissSnackBarRecently else {
                        ObvMessengerInternalNotification.olvidSnackBarShouldBeShown(ownedCryptoId: currentCryptoId, snackBarCategory: OlvidSnackBarCategory.grantPermissionToRecord)
                            .postOnDispatchQueue()
                        return
                    }
                }
            }
        @unknown default:
            assertionFailure()
        }
        
        // If we rech this point, there is no appropriate snackbar to display, so we request to hide all already shown snackbar
        ObvMessengerInternalNotification.olvidSnackBarShouldBeHidden(ownedCryptoId: currentCryptoId)
            .postOnDispatchQueue()
    }
    
    
}
