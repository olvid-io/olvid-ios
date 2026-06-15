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
import Combine
import ObvDiscussionsList
import ObvSettings
import ObvAppCoreConstants


@MainActor
final class TipCellViewAppDataSourceForListOfArchivedDiscussions {
    
    private var tipCellViewModelStreamManagerForStreamUUID: [UUID: TipCellViewModelStreamManager] = [:]
    
}


// MARK: - Implementing TipCellViewDataSource

extension TipCellViewAppDataSourceForListOfArchivedDiscussions: TipCellViewDataSource {
    
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


// MARK: - Implementing TipCellViewDataSourceActions

extension TipCellViewAppDataSourceForListOfArchivedDiscussions: TipCellViewDataSourceActions {
    
    /// Called when the users taps the "Ok" button on the tip about OS upgrade. In that case, we reset the `dateOfLastOSUpgradeTipDisplay` and request a refresh of the data source. This will dismiss the tip.
    func userWantsToDismissOSUpgradeCell(_ view: ObvDiscussionsList.OSUpgradeCell) {
        guard let userDefaults = UserDefaults(suiteName: ObvAppCoreConstants.appGroupIdentifier) else { assertionFailure(); return }
        userDefaults.setDate(Date.now, for: ObvMessengerConstants.UserDefaultsKeys.dateOfLastOSUpgradeTipDisplay)
        for manager in self.tipCellViewModelStreamManagerForStreamUUID.values {
            manager.createAndYieldModelIfNeeded()
        }
    }

    /// Called when the user taps the dismiss button of the `OwnedDeviceExpiringSoonTipView`.
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

}


// MARK: - Internal managers

extension TipCellViewAppDataSourceForListOfArchivedDiscussions {
    
    @MainActor
    private final class TipCellViewModelStreamManager {
        
        let streamUUID = UUID()
        private var stream: AsyncStream<ObvDiscussionsList.TipCellViewModel?>?
        private var continuation: AsyncStream<ObvDiscussionsList.TipCellViewModel?>.Continuation?
        private var previouslyYieldedModel: ObvDiscussionsList.TipCellViewModel?

        private var cancellables = Set<AnyCancellable>()

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
            
            ObvMessengerSettingsObservableObject.shared.$unarchiveDiscussions
                .receive(on: OperationQueue.main)
                .sink { [weak self] newValue in
                    guard let self else { return }
                    let model = createModel()
                    yieldModelIfNeeded(model: model)
                }
                .store(in: &cancellables)
            
        }
        
        func finishStream() {
            continuation?.finish()
            cancellables.forEach({ $0.cancel() })
        }

        private func createModel() -> TipCellViewModel {
            return TipCellViewModel.archivedDiscussionsHelpMessage(discussionsAreUnarchivedAutomatically: ObvMessengerSettings.Discussions.unarchiveDiscussions)
        }
        
        fileprivate func createAndYieldModelIfNeeded() {
            Task {
                let model = createModel()
                self.yieldModelIfNeeded(model: model)
            }
        }

        private func yieldModelIfNeeded(model: TipCellViewModel?) {
            guard let continuation else { assertionFailure(); return }
            guard previouslyYieldedModel != model else { return }
            previouslyYieldedModel = model
            continuation.yield(model)
        }

    }
    
}
