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
import Combine
import ObvDiscussionsList
import ObvSettings
import TipKit
import ObvAppCoreConstants
import ObvUICoreData
import StoreKit
import ObvAppTypes


@MainActor
final class TipCellViewAppDataSource {
    
    private var tipCellViewModelStreamManagerForStreamUUID: [UUID: TipCellViewModelStreamManager] = [:]
    
}



extension TipCellViewAppDataSource: TipCellViewDataSource {
    
    func getAsyncStreamOfTipCellViewModel(_ view: ObvDiscussionsList.ObvDiscussionsListView) throws -> (streamUUID: UUID, stream: AsyncStream<ObvDiscussionsList.TipCellViewModel?>) {
        let manager = TipCellViewModelStreamManager()
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


extension TipCellViewAppDataSource {
    
    @MainActor
    private final class TipCellViewModelStreamManager {
        
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
            
            let stream = AsyncStream(TipCellViewModel?.self) { [weak self] (continuation: AsyncStream<TipCellViewModel?>.Continuation) in
                guard let self else { return }
                self.continuation = continuation
                let model = createModel()
                yieldModelIfNeeded(model: model)
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
                    let model = createModel()
                    yieldModelIfNeeded(model: model)
                }
                .store(in: &cancellables)
            
            ObvMessengerSettingsObservableObject.shared.$dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    self.userDidSetupBackupsAtLeastOnce = ObvMessengerSettings.Backup.userDidSetupBackupsAtLeastOnce
                    self.dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey = newValue
                    let model = createModel()
                    yieldModelIfNeeded(model: model)
                }
                .store(in: &cancellables)
            
            ObvMessengerSettingsObservableObject.shared.$doSendReadReceipt
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    let model = createModel()
                    yieldModelIfNeeded(model: model)
                }
                .store(in: &cancellables)
            
            ObvMessengerSettingsObservableObject.shared.$dateWhenUserDimissedTip
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    let model = createModel()
                    yieldModelIfNeeded(model: model)
                }
                .store(in: &cancellables)
            
            observationTokens.append(contentsOf: [
                ObvMessengerInternalNotification.observeUserRequestedToResetAllAlerts { [weak self] in
                    self?.userDefaults?.setDate(nil, for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastOlvidPlusTipDisplay)
                    self?.createAndYieldModelIfNeeded()
                },
            ])
            
        }
        
        
        func finishStream() {
            continuation?.finish()
            cancellables.forEach({ $0.cancel() })
        }
        
        
        private func createModel() -> TipCellViewModel? {
            
            // Priority 0: Subscription confirmation
            
            if let ownershipType = createSubScriptionConfirmationTip() {
                return TipCellViewModel.olvidPlusSuccessfulSubscription(ownershipType: ownershipType)
            }

            // Priority 1: backups
            
            if let backupModel = createModelForTipBackup(
                userDidSetupBackupsAtLeastOnce: userDidSetupBackupsAtLeastOnce,
                dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey: dateWhenUserRequestedToBeToBeRemenberedToWriteDownBackupKey) {
                return TipCellViewModel.backup(backupModel)
            }

            guard previousTipWasShownLongTimeAgo else {
                return nil
            }
            
            // Priority 2: Send read receipts

            if !doSendReadReceiptIsSet {
                return TipCellViewModel.doSendReadReceipt
            }
            
            // Priority 3: Olvid+
            
            if let olvidPlusTipViewModel = createOlvidPlusTipViewModel() {
                return TipCellViewModel.olvidPlus(olvidPlusTipViewModel)
            }
            
            return nil
            
        }

        
        private func yieldModelIfNeeded(model: TipCellViewModel?) {
            guard let continuation else { assertionFailure(); return }
            guard previouslyYieldedModel != model else { return }
            previouslyYieldedModel = model
            continuation.yield(model)
        }

        
        private func createSubScriptionConfirmationTip() -> ObvOwnershipType? {
            if let ownershipTypeRawValue = userDefaults?.value(forKey: ObvMessengerConstants.UserDefaultsKeys.olvidPlusSubscriptionConfirmationTipToDisplay.rawValue) as? String, let ownerShipType = ObvOwnershipType(rawValue: ownershipTypeRawValue) {
                return ownerShipType
            } else {
                return nil
            }
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
                let model = createModel()
                self.yieldModelIfNeeded(model: model)
            }
        }
        
        /// Method called by the `MetaFlowController` when the user dismisses the `OlvidShopView`.
        /// In the case, we want to ensure we don't show an Olvid+ tip
        func olvidShopViewControllerDidDisappear() {
            // For now, the only case where we want to reset dateOfLastOlvidPlusTipDisplay is when
            // we show an Olvid+ tip.
            switch previouslyYieldedModel {
            case .olvidPlus:
                break
            case .backup, .doSendReadReceipt, .archivedDiscussionsHelpMessage, .none, .olvidPlusSuccessfulSubscription:
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
                
                let apiPermissionsAcrossAllOwnedIdentities = try PersistedObvOwnedIdentity.getBestAPIPermissionsAcrossAllOwnedIdentities(within: ObvStack.shared.viewContext)
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
