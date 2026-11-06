/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import AVFAudio
import CoreData
import Combine
import ObvTypes
import OlvidUtils
import ObvDiscussionsList
import ObvSettings
import ObvAppCoreConstants
import ObvUICoreData
import StoreKit
import ObvAppTypes


@MainActor
final class TipCellViewAppDataSource {
    
    private let viewContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext

    private var tipCellViewModelStreamManagerForStreamUUID: [UUID: TipCellViewModelStreamManager] = [:]
    
    init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        self.backgroundContext = backgroundContext
    }
    
}



extension TipCellViewAppDataSource: TipCellViewDataSource {
    
    func getAsyncStreamOfTipCellViewModel(_ view: ObvDiscussionsList.ObvDiscussionsListView) throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsList.TipCellViewModel?>) {
        let manager = TipCellViewModelStreamManager(viewContext: viewContext, backgroundContext: backgroundContext)
        tipCellViewModelStreamManagerForStreamUUID[manager.streamUUID] = manager
        return try manager.startStream()
    }
    
    func finishAsyncStreamOfTipCellViewModel(_ view: ObvDiscussionsList.ObvDiscussionsListView, streamUUID: UUID) {
        if let manager = tipCellViewModelStreamManagerForStreamUUID.removeValue(forKey: streamUUID) {
            manager.finishStream()
        }
    }
    
}

extension TipCellViewAppDataSource {
    
    func olvidShopViewControllerDidDisappear() {
        for streamManager in tipCellViewModelStreamManagerForStreamUUID.values {
            streamManager.olvidShopViewControllerDidDisappear()
        }
    }
    
    func refreshTip() {
        for streamManager in tipCellViewModelStreamManagerForStreamUUID.values {
            streamManager.createAndYieldModelIfNeeded()
        }
    }
    
}


extension TipCellViewAppDataSource: TipCellViewDataSourceActions {
    
    /// Called when the users taps the "Ok" button on the tip about OS upgrade. In that case, we reset the `dateOfLastOSUpgradeTipDisplay` and request a refresh of the data source. This will dismiss the tip.
    func userWantsToDismissOSUpgradeCell(_ view: ObvDiscussionsList.OSUpgradeCell) {
        guard let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier) else { assertionFailure(); return }
        userDefaults.setDate(Date.now, for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastOSUpgradeTipDisplay)
        for manager in self.tipCellViewModelStreamManagerForStreamUUID.values {
            manager.createAndYieldModelIfNeeded()
        }
    }
    
    
    /// Called when the user taps the dismiss button of the `OwnedDeviceExpiringSoonTipView`. In that case, we reset the `dateOfLastOwnedDeviceExpiringTipDisplay` and request a refresh of the data source. This will dismiss the tip.
    func userWantsToDismissOwnedDeviceExpiringSoonTipView(_ view: ObvDiscussionsList.OwnedDeviceExpiringSoonTipView) {
        // Record the current date before returning the model.
        guard let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier) else { assertionFailure(); return }
        userDefaults.setDate(.now, for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastOwnedDeviceExpiringTipDisplay)
        ObvMessengerSettings.ObvTips.setDateWhenUserDimissedTip(to: .now)
        for manager in self.tipCellViewModelStreamManagerForStreamUUID.values {
            manager.createAndYieldModelIfNeeded()
        }
    }

    
    /// Called when the user taps the dismiss button of the `RequestUserNotificationsAuthorizationTipView`.
    func userWantsToDismissRequestUserNotificationsAuthorizationTipView(_ view: ObvDiscussionsList.RequestUserNotificationsAuthorizationTipView) {
        ObvMessengerSettings.ObvTips.setDateWhenUserDimissedTip(to: .now)
        for manager in self.tipCellViewModelStreamManagerForStreamUUID.values {
            manager.createAndYieldModelIfNeeded()
        }
    }


    /// Called when the user dismisses the `NewerAppVersionAvailableTipView`, either by tapping the dismiss button or after tapping the
    /// "Open the App Store" button. We record the dismissal date (one-day cooldown, see `createNewerAppVersionAvailableTip()`) and request
    /// a refresh of the data source. This will dismiss the tip.
    func userWantsToDismissNewerAppVersionAvailableTipView(_ view: ObvDiscussionsList.NewerAppVersionAvailableTipView) {
        guard let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier) else { assertionFailure(); return }
        userDefaults.setDate(.now, for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastNewerAppVersionAvailableTipDisplay)
        for manager in self.tipCellViewModelStreamManagerForStreamUUID.values {
            manager.createAndYieldModelIfNeeded()
        }
    }


    /// Called when the user dismisses the `GrantRecordPermissionTipView`, either via the "Later" button or after tapping the primary
    /// button (grant in-app / open Settings). We record the dismissal date (per-variant cooldown enforced in
    /// `createGrantRecordPermissionTip()`) and request a refresh of the data source. This will dismiss the tip.
    func userWantsToDismissGrantRecordPermissionTipView(_ view: ObvDiscussionsList.GrantRecordPermissionTipView) {
        guard let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier) else { assertionFailure(); return }
        userDefaults.setDate(.now, for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastGrantRecordPermissionTipDisplay)
        for manager in self.tipCellViewModelStreamManagerForStreamUUID.values {
            manager.createAndYieldModelIfNeeded()
        }
    }

}


extension TipCellViewAppDataSource {
    
    @MainActor
    fileprivate final class TipCellViewModelStreamManager {
        
        private let viewContext: NSManagedObjectContext
        private let backgroundContext: NSManagedObjectContext

        let streamUUID = UUID()
        private var stream: AsyncStream<ObvDiscussionsList.TipCellViewModel?>?
        private var continuation: AsyncStream<ObvDiscussionsList.TipCellViewModel?>.Continuation?
        private var previouslyYieldedModel: ObvDiscussionsList.TipCellViewModel?

        private var cancellables = Set<AnyCancellable>()
        private var observationTokens = [any NSObjectProtocol]()
        
        private var dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey: Date? = ObvMessengerSettings.Backup.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey
        private var userDidSetupBackupsAtLeastOnce: Bool = ObvMessengerSettings.Backup.userDidSetupBackupsAtLeastOnce
        
        private var doSendReadReceiptIsSet: Bool { ObvMessengerSettings.Discussions.doSendReadReceiptIsSet }
        private var previousTipWasShownLongTimeAgo: Bool { ObvMessengerSettings.ObvTips.previousTipWasShownLongTimeAgo }
        
        private let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier)

        private var currentOwnedCryptoId: ObvCryptoId?
        private var ownedIdentitiesAndOwnedDevices: Set<TipCellViewAppDataSource.OwnedIdentityAndDevices>? // Set soon after init
        
        private var ownedIdentitiesAndOwnedDevicesStreamManager: OwnedIdentitiesAndOwnedDevicesStreamManager?
        
        init(viewContext: NSManagedObjectContext, backgroundContext: NSManagedObjectContext) {
            self.viewContext = viewContext
            self.backgroundContext = backgroundContext
        }
        
        deinit {
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
            observationTokens.removeAll()
        }
        
        func startStream() throws -> (streamUUID: UUID, stream: AsyncStream<TipCellViewModel?>) {
            if let stream {
                return (streamUUID, stream)
            }

            continuouslyObserveSettings()
            continuouslyObserveDeactivatedOwnedCryptoIds(context: backgroundContext)
            
            let stream = AsyncStream(TipCellViewModel?.self) { [weak self] (continuation: AsyncStream<TipCellViewModel?>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                createAndYieldModelIfNeeded()
            }
            self.stream = stream
            return (streamUUID, stream)
        }
        
        
        private func continuouslyObserveSettings() {
            
            ObvMessengerSettingsObservableObject.shared.$userDidSetupBackupsAtLeastOnce
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    self.userDidSetupBackupsAtLeastOnce = newValue
                    self.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = ObvMessengerSettings.Backup.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey
                    createAndYieldModelIfNeeded()
                }
                .store(in: &cancellables)
            
            ObvMessengerSettingsObservableObject.shared.$dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    self.userDidSetupBackupsAtLeastOnce = ObvMessengerSettings.Backup.userDidSetupBackupsAtLeastOnce
                    self.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = newValue
                    createAndYieldModelIfNeeded()
                }
                .store(in: &cancellables)
            
            ObvMessengerSettingsObservableObject.shared.$doSendReadReceipt
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    createAndYieldModelIfNeeded()
                }
                .store(in: &cancellables)
            
            ObvMessengerSettingsObservableObject.shared.$dateWhenUserDimissedTip
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    createAndYieldModelIfNeeded()
                }
                .store(in: &cancellables)
            
            OlvidUserActivitySingleton.shared.$currentUserActivity
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    guard let newValue else { return }
                    guard self.currentOwnedCryptoId != newValue.ownedCryptoId else { return }
                    self.currentOwnedCryptoId = newValue.ownedCryptoId
                    createAndYieldModelIfNeeded()
                }
                .store(in: &cancellables)

            observationTokens.append(contentsOf: [
                ObvMessengerInternalNotification.observeUserRequestedToResetAllAlerts { [weak self] in
                    self?.userDefaults?.setDate(nil, for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastOlvidPlusTipDisplay)
                    self?.userDefaults?.setDate(nil, for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastOwnedDeviceExpiringTipDisplay)
                    self?.createAndYieldModelIfNeeded()
                },
                
            ])
            
        }
        
        
        /// **The manager is captured, not read back from the property, and that is the whole of a crash found on 2026-09-01.**
        ///
        /// This is called once, from `init`, so nothing starts streams repeatedly. What happens is narrower: the `Task` used to read
        /// `self.ownedIdentitiesAndOwnedDevicesStreamManager` *after* awaiting `startStream()`, and ``finishStream()`` may have set it to nil in
        /// between — whereupon the optional chain yielded nil, the `guard` tripped, and the `assertionFailure()` on it killed the app in Debug. It was
        /// met by dragging an iPad's Split View divider quickly with the discussions list showing, which creates and tears these down fast enough to
        /// land in that window.
        ///
        /// **The assertion is kept rather than removed**, and capturing the manager is what makes it mean something again: it now fires only if
        /// `startStream()` genuinely threw. Removing it — which was done first, to get through an unrelated walk — left a bare `return` covering two
        /// quite different states, one a real fault and one entirely ordinary, and told nobody which had happened.
        ///
        /// **The identity check is the half that is easy to leave out.** A manager whose owner was torn down while the stream was starting is a
        /// manager nobody holds and nobody will finish, so it finishes itself. The original code avoided that leak only by never getting that far.
        private func continuouslyObserveDeactivatedOwnedCryptoIds(context: NSManagedObjectContext) {
            self.ownedIdentitiesAndOwnedDevicesStreamManager = .init(context: context)
            guard let manager = self.ownedIdentitiesAndOwnedDevicesStreamManager else { assertionFailure(); return }
            Task {
                guard let (_, stream) = try? await manager.startStream() else { assertionFailure(); return }
                guard self.ownedIdentitiesAndOwnedDevicesStreamManager === manager else { return manager.finishStream() }
                for await model in stream {
                    self.ownedIdentitiesAndOwnedDevices = model
                    self.createAndYieldModelIfNeeded()
                }
            }
        }
        
        
        func finishStream() {
            continuation?.finish()
            cancellables.forEach({ $0.cancel() })
            self.ownedIdentitiesAndOwnedDevicesStreamManager?.finishStream()
            self.ownedIdentitiesAndOwnedDevicesStreamManager = nil
        }
        
        
        private func createModel() async -> TipCellViewModel? {
            
            // Priority 0: Subscription confirmation
            
            if let ownershipType = createSubScriptionConfirmationTip() {
                return TipCellViewModel.olvidPlusSuccessfulSubscription(ownershipType: ownershipType)
            }
            
            // Priority 1: Profile is deactivated on this device

            if let cryptoId = createProfileIsDeactivatedOnThisDeviceTipViewModel() {
                return TipCellViewModel.profileIsDeactivatedOnThisDevice(ownedCryptoId: cryptoId)
            }
            
            // Priority 2: Device expiring soon
            
            if let model = createOwnedDeviceExpriginSoonModel() {
                return TipCellViewModel.ownedDeviceExpriginSoon(model)
            }

            // Priority 3: backups

            if let backupModel = createModelForTipBackup(
                userDidSetupBackupsAtLeastOnce: userDidSetupBackupsAtLeastOnce,
                dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey: dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey) {
                return TipCellViewModel.backup(backupModel)
            }

            // Priority 4: a newer version of the app is available on the App Store

            if createNewerAppVersionAvailableTip() {
                return TipCellViewModel.newerAppVersionAvailable
            }

            // Priority 5: grant microphone access (shown only after the user missed an incoming call because the permission was off)

            if let permission = createGrantRecordPermissionTip() {
                return TipCellViewModel.grantRecordPermission(permission)
            }

            // The following tips are shown only if no tip was shown for a long time

            guard previousTipWasShownLongTimeAgo else {
                return nil
            }

            // Priority 6: Send read receipts

            if !doSendReadReceiptIsSet {
                return TipCellViewModel.doSendReadReceipt
            }

            // Priority 7: Olvid+

            if let olvidPlusTipViewModel = createOlvidPlusTipViewModel() {
                return TipCellViewModel.olvidPlus(olvidPlusTipViewModel)
            }

            // Priority 8: OS upgrade
            
            if let upgradeTip = createOSUpgradeTip() {
                return TipCellViewModel.osUpgrade(upgradeTip)
            }
            
            // Priority 9: Request User notifications authorization
            
            if await notificationAuthorizationStatusIsNotDetermined {
                return TipCellViewModel.requestUserNotificationsAuthorization
            }
                        
            return nil
            
        }

        
        private func yieldModelIfNeeded(model: TipCellViewModel?) {
            guard let continuation else { assertionFailure(); return }
            guard previouslyYieldedModel != model else { return }
            previouslyYieldedModel = model
            continuation.yield(model)
        }

        
        /// Returns `true` when the user has not yet been asked about local-notification authorization.
        /// Evaluated asynchronously because `UNUserNotificationCenter.notificationSettings()` is itself async.
        private var notificationAuthorizationStatusIsNotDetermined: Bool {
            get async {
                let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
                return notificationSettings.authorizationStatus == .notDetermined
            }
        }
        
        
        private func createSubScriptionConfirmationTip() -> ObvOwnershipType? {
            if let ownershipTypeRawValue = userDefaults?.value(forKey: ObvMessengerConstants.UserDefaultsKeys.olvidPlusSubscriptionConfirmationTipToDisplay.rawValue) as? String, let ownerShipType = ObvOwnershipType(rawValue: ownershipTypeRawValue) {
                return ownerShipType
            } else {
                return nil
            }
        }
        
        
        private func createProfileIsDeactivatedOnThisDeviceTipViewModel() -> ObvCryptoId? {
            guard let currentOwnedCryptoId, let ownedIdentitiesAndOwnedDevices else { return nil }
            guard let owned = ownedIdentitiesAndOwnedDevices.first(where: { $0.ownedCryptoId == currentOwnedCryptoId }) else { return nil }
            if owned.isActiveOnThisDevice {
                return nil
            } else {
                return currentOwnedCryptoId
            }
        }
        
        /// Tiers that govern how often the "device expiring soon" tip is shown.
        /// Tiers must be ordered from most urgent (shortest time) to least urgent (longest time).
        /// If the time remaining until expiration exceeds all tiers' `maxTimeUntilExpiration`, the tip is suppressed.
        /// To tune the policy, edit only this array.
        private static let expiringDeviceTipTiers: [ExpiringDeviceTipTier] = [
            // ≤ 10 days left: show at most once per day
            ExpiringDeviceTipTier(maxTimeUntilExpiration: .days(10), cooldown: .days(1)),
            // ≤ 20 days left: show at most once every 2 days
            ExpiringDeviceTipTier(maxTimeUntilExpiration: .days(20), cooldown: .days(2)),
            // > 20 days left: never show (no tier matches → nil)
        ]

        private func createOwnedDeviceExpriginSoonModel() -> TipCellViewModel.OwnedDeviceExpriginSoonModel? {
            assert(Thread.isMainThread)
            do {

                guard let currentOwnedCryptoId else { return nil }
                
                // Make sure the profile is still active on this device
                
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: currentOwnedCryptoId, within: viewContext) else {
                    return nil
                }
                
                guard ownedIdentity.isActive else { return nil }
                
                // Look for an expiring device

                guard let expiringDevice = try PersistedObvOwnedDevice.getOwnedDeviceExpiringSoon(ownedCryptoId: currentOwnedCryptoId, within: viewContext) else {
                    return nil
                }

                guard let model = TipCellViewModel.OwnedDeviceExpriginSoonModel(device: expiringDevice) else {
                    return nil
                }

                // Determine the time remaining until expiration.
                let timeUntilExpiration = model.expirationDate.timeIntervalSinceNow

                // Find the first (most-urgent) matching tier.
                guard let tier = Self.expiringDeviceTipTiers.first(where: { timeUntilExpiration <= $0.maxTimeUntilExpiration }) else {
                    return nil // Too far in the future — don't show yet.
                }

                // Enforce the cooldown for the matched tier.
                let lastDisplay = userDefaults?.dateOrNil(for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastOwnedDeviceExpiringTipDisplay) ?? .distantPast
                guard Date.now.timeIntervalSince(lastDisplay) >= tier.cooldown else {
                    return nil // Still within the cooldown window.
                }

                return model

            } catch {
                assertionFailure()
                return nil
            }
        }
        
        
        private func createOSUpgradeTip() -> TipCellViewModel.OSUpgrade? {
            guard let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier) else { assertionFailure(); return nil }
            let lastDisplayDate = userDefaults.dateOrNil(for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastOSUpgradeTipDisplay) ?? Date.distantPast
            let didDismissSnackBarRecently = abs(lastDisplayDate.timeIntervalSinceNow) < TimeInterval(days: 7)
            if !didDismissSnackBarRecently {
                if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.supportedIOSVersion {
                    return .required
                } else if ObvMessengerConstants.localIOSVersion < ObvMessengerConstants.recommendedMinimumIOSVersion {
                    return .recommended
                }
            }
            return nil
        }


        /// Returns `true` when a newer version of Olvid is available on the App Store and the tip has not been dismissed recently.
        /// Mirrors the logic that used to live in the `SnackBarManager` for the `newerAppVersionAvailable` snack bar: a one-day
        /// cooldown after dismissal, and a comparison between the latest build number advertised by the server and the local build.
        private func createNewerAppVersionAvailableTip() -> Bool {
            guard let userDefaults else { assertionFailure(); return false }
            let lastDisplayDate = userDefaults.dateOrNil(for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastNewerAppVersionAvailableTipDisplay) ?? Date.distantPast
            let didDismissTipRecently = abs(lastDisplayDate.timeIntervalSinceNow) < TimeInterval(days: 1)
            guard !didDismissTipRecently else { return false }
            guard let latestBuildNumberAvailable = ObvMessengerSettings.AppVersionAvailable.latest else { return false }
            return latestBuildNumberAvailable > ObvAppCoreConstants.bundleVersionAsInt
        }


        /// Returns the appropriate "grant microphone access" variant when the user has missed an incoming call because the record
        /// permission is off, or `nil` otherwise. Mirrors the logic that used to live in the `SnackBarManager`: it only nudges after a
        /// rejected incoming call, picks `.requestInApp` when the permission is undetermined and `.openSettings` when it was denied,
        /// and enforces a per-variant cooldown (1 day for the in-app prompt, 7 days for the Settings round-trip).
        private func createGrantRecordPermissionTip() -> TipCellViewModel.GrantRecordPermission? {
            assert(Thread.isMainThread)

            let permission: TipCellViewModel.GrantRecordPermission
            let cooldown: TimeInterval
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                return nil
            case .denied:
                permission = .openSettings
                cooldown = TimeInterval(days: 7)
            case .undetermined:
                permission = .requestInApp
                cooldown = TimeInterval(days: 1)
            @unknown default:
                assertionFailure()
                return nil
            }

            // Only nudge if the user actually missed an incoming call because of the missing permission.
            let hasRejectedIncomingCall: Bool
            do {
                hasRejectedIncomingCall = try PersistedMessageSystem.hasRejectedIncomingCallBecauseOfDeniedRecordPermission(within: viewContext)
            } catch {
                assertionFailure()
                return nil
            }
            guard hasRejectedIncomingCall else { return nil }

            // Enforce the cooldown for the matched variant.
            guard let userDefaults else { assertionFailure(); return nil }
            let lastDisplayDate = userDefaults.dateOrNil(for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastGrantRecordPermissionTipDisplay) ?? Date.distantPast
            guard abs(lastDisplayDate.timeIntervalSinceNow) >= cooldown else { return nil }

            return permission
        }


        private func createModelForTipBackup(userDidSetupBackupsAtLeastOnce: Bool, dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey: Date?) -> TipCellViewModel.SetupNewBackupsCellViewModel? {
            if userDidSetupBackupsAtLeastOnce && dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey == nil {
                // The "setup backup cell" should not be displayed.
                return nil
            } else {
                // The "setup backup cell" should be displayed.
                if !userDidSetupBackupsAtLeastOnce {
                    return .newBackupsShouldBeSetup
                } else if dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey != nil {
                    return .rememberToWriteDownBackupKey
                } else {
                    return nil
                }
            }
        }
        
        fileprivate func createAndYieldModelIfNeeded() {
            Task {
                let model = await createModel()
                self.yieldModelIfNeeded(model: model)
            }
        }
        
        /// Method called by the `MetaFlowController` when the user dismisses the `OlvidShopView`.
        /// In the case, we want to ensure we don't show an Olvid+ tip
        func olvidShopViewControllerDidDisappear() {
            // For now, the only cases where we want to reset dateOfLastOlvidPlusTipDisplay is when
            // we show an Olvid+ tip, or when showing the "Device will soon be deactivated" tip
            switch previouslyYieldedModel {
            case .olvidPlus, .ownedDeviceExpriginSoon:
                break
            case .backup, .doSendReadReceipt, .archivedDiscussionsHelpMessage, .none, .olvidPlusSuccessfulSubscription, .osUpgrade, .profileIsDeactivatedOnThisDevice, .requestUserNotificationsAuthorization, .newerAppVersionAvailable, .grantRecordPermission:
                return
            }
            userDefaults?.setDate(.now, for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastOlvidPlusTipDisplay)
            createAndYieldModelIfNeeded()
        }
        
        
        /// Called when the data source determined that an Olvid+ tip should be prioritized for display over other available tips.
        ///
        /// - Returns: An `OlvidPlusTip` instance if an Olvid+ tip is a relevant option to display at this time.
        ///            Return `nil` to allow the data source to evaluate and display an alternative tip.
        ///
        /// - Note: This method is invoked by the data source when it determines that an Olvid+ tip is the best choice for the current context.
        ///         The returned tip will be displayed immediately if provided.
        private func createOlvidPlusTipViewModel() -> TipCellViewModel.OlvidPlusTipViewModel? {
            assert(Thread.isMainThread)
            do {
                
                // Do not advertise for in-app purchase if the user cannot make payments (see https://developer.apple.com/documentation/storekit/appstore/canmakepayments)
                guard StoreKit.AppStore.canMakePayments else {
                    return nil
                }
                
                // Do not show a tip if one of the profiles already has a permission. This is notably the case when
                // the user already subscribed, has a licence distributed by a keycloak, or activated a free trial for the secure calls.
                
                let apiPermissionsAcrossAllOwnedIdentities = try PersistedObvOwnedIdentity.getBestAPIPermissionsAcrossAllOwnedIdentities(within: viewContext)
                guard apiPermissionsAcrossAllOwnedIdentities.isEmpty else { return nil }
                
                // Make sure the user has been using Olvid for enough time (at least one month since the creation of the first profile)
                
                guard let userDefaults else { assertionFailure(); return nil }
                guard let dateOfCreationOfFirstProfile = userDefaults.dateOrNil(for: ObvMessengerConstants.UserDefaultsKeys.dateOfCreationOfFirstProfile) else {
                    return nil
                }
                guard Date.now.timeIntervalSince(dateOfCreationOfFirstProfile) > TimeInterval(months: 1) else {
                    return nil
                }
                
                // Make sure we don't show this tip too often (not more than once a month)
                
                let dateOfLastOlvidPlusTipDisplay: Date = userDefaults.dateOrNil(for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastOlvidPlusTipDisplay) ?? .distantPast
                guard Date.now.timeIntervalSince(dateOfLastOlvidPlusTipDisplay) > TimeInterval(months: 1) else {
                    return nil
                }

                // We will show an Olvid+ tip (we choose one in a fun way, one different every month)
                // We don't set the `ObvMessengerConstants.UserDefaultsKeys.dateOfLastOlvidPlusTipDisplay`. This will be set when the user
                // dismisses the OlvidShop view.
                
                let currentMonth = max(0, Calendar.current.component(.month, from: .now) % 12) // Between 0 and 11, included
                let allCases = TipCellViewModel.OlvidPlusTipViewModel.allCases
                let indexOfTipToShow: Int = currentMonth % allCases.count
                guard allCases.indices.contains(indexOfTipToShow) else {
                    assertionFailure()
                    return TipCellViewModel.OlvidPlusTipViewModel.allCases.randomElement() ?? .secureCalls
                }
                return allCases[indexOfTipToShow]

            } catch {
                assertionFailure()
                return nil
            }
        }

    }
    
    
}


// MARK: - Internal managers

extension TipCellViewAppDataSource {
    
    /// This model is a *change detector*, not a source of values: nothing ever reads its `devices`, and the tips are always
    /// recomputed from Core Data by `createModel()`. Its only job is to differ whenever something a tip depends on has changed,
    /// so that `createAndYieldModelIfNeeded()` gets called — the stream manager skips a yield when the new model equals the
    /// previous one.
    ///
    /// **So every value a tip reads off a device must appear here, and `expirationDate` was missing.** What that cost was a tip
    /// that outlived the fact it described. Adding a second device to a profile with no multidevice subscription schedules a
    /// deactivation, and the source device is the one the server picks first: it rightly showed "This device will be deactivated
    /// in less than …". The user then chose to keep *that* device active, so the server moved the expiration onto the new device
    /// and cleared it here — the devices' identifiers and `isCurrentDevice` were untouched, this model came out identical, no
    /// yield was made, and the tip stayed on screen counting down to a deactivation that was no longer going to happen. The list
    /// of devices, one screen away, read the same store and said the opposite, which is the fingerprint of a stale observer
    /// rather than of bad data.
    fileprivate struct OwnedIdentityAndDevices: Sendable, Hashable {
        let ownedCryptoId: ObvCryptoId
        let isActiveOnThisDevice: Bool
        let devices: Set<Device>
        struct Device: Sendable, Hashable {
            let isCurrentDevice: Bool
            let identifier: Data
            /// Read by the "device expiring soon" tip, both to decide whether to show it and to say when the deactivation happens.
            let expirationDate: Date?
            /// Displayed by the "device expiring soon" tip when the expiring device is not the current one.
            let name: String
        }
    }
    
    private final class OwnedIdentitiesAndOwnedDevicesStreamManager:
        ObvDataSourceStreamManagerWithTwoFetchedResultsController<Set<OwnedIdentityAndDevices>, PersistedObvOwnedIdentity, PersistedObvOwnedDevice>, @unchecked Sendable {
     
        deinit {
            debugPrint("Deinit")
        }
        
        init(context: NSManagedObjectContext) {
            let frc1 = PersistedObvOwnedIdentity.getFetchedResultsControllerForAllOwnedIdentities(within: context)
            let frc2 = PersistedObvOwnedDevice.getFetchedResultsController(within: context)
            super.init(frc1: frc1, frc2: frc2)
        }
        
        override func createModel(fetchedObjects1: [PersistedObvOwnedIdentity], fetchedObjects2: [PersistedObvOwnedDevice]) throws -> Set<TipCellViewAppDataSource.OwnedIdentityAndDevices> {
            let model: [OwnedIdentityAndDevices] = fetchedObjects1.map({ .init(ownedIdentity: $0) })
            return Set(model)
        }
        
    }
    
}


private struct ExpiringDeviceTipTier {
    /// The tip is eligible for this tier only when the device expires within this interval.
    let maxTimeUntilExpiration: TimeInterval
    /// Minimum time that must have elapsed since the last display before showing again.
    let cooldown: TimeInterval
}


extension TipCellViewModel.OwnedDeviceExpriginSoonModel {
    
    init?(device: PersistedObvOwnedDevice) {
        
        guard let ownedCryptoId = try? device.ownedCryptoId else { return nil }
        guard let expirationDate = device.expirationDate else { return nil }
        let deviceName: String? = device.name
        
        self.init(ownedCryptoId: ownedCryptoId,
                  isCurrentDevice: device.isCurrentDevice,
                  expirationDate: expirationDate,
                  deviceName: deviceName)
        
    }
    
}


extension TipCellViewAppDataSource.OwnedIdentityAndDevices {
    
    init(ownedIdentity: PersistedObvOwnedIdentity) {
        let devices = Set(ownedIdentity.devices.map { Device(device: $0) })
        self = .init(ownedCryptoId: ownedIdentity.cryptoId,
                     isActiveOnThisDevice: ownedIdentity.isActive,
                     devices: devices)
    }
    
}


extension TipCellViewAppDataSource.OwnedIdentityAndDevices.Device {
    
    init(device: PersistedObvOwnedDevice) {
        self = .init(isCurrentDevice: device.isCurrentDevice,
                     identifier: device.identifier,
                     expirationDate: device.expirationDate,
                     name: device.name)
    }
    
}
